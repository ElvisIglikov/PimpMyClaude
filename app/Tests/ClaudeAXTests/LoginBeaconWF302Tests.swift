import XCTest
import AppKit
@testable import ClaudeAX

/// Вход на сайт (WF302, #11225): очередь `logins/`, выбор поля входа, конец входа, AppleScript к Chrome, «вода» с явной
/// целью стрелки. Живых окон и Chrome тест не трогает (AppleScript только компилируется, не запускается).
/// `LOGIN_WATER_SNAPSHOT_DIR=<папка>` — ещё и кадры воды на макете окна входа (PNG).
final class LoginBeaconWF302Tests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let chrome = CGRect(x: 360, y: 60, width: 1000, height: 780)
    private let field = CGRect(x: 660, y: 420, width: 400, height: 44)
    private let dt: CGFloat = 1.0 / 60

    private func request(_ id: String, _ url: String, at: String = "2026-10-30T18:00:00Z", name: String? = nil) -> LoginRequest {
        var body: [String: Any] = ["v": 1, "id": id, "url": url, "at": at, "from": ""]
        if let name = name { body["name"] = name }
        return LoginRequest.parse(try! JSONSerialization.data(withJSONObject: body), fileID: id)!
    }

    // MARK: - очередь

    func testRequestParse() throws {
        let ok = request("1-1", "https://appstoreconnect.apple.com/login", name: "App Store Connect")
        XCTAssertEqual(ok.name, "App Store Connect")
        XCTAssertEqual(ok.host, "appstoreconnect.apple.com")
        XCTAssertEqual(request("1-2", "https://www.example.com/").name, "example.com", "без имени — хост")
        let data = { (body: [String: Any]) in try! JSONSerialization.data(withJSONObject: body) }
        XCTAssertNil(LoginRequest.parse(data(["v": 2, "id": "a", "url": "https://x.com"]), fileID: "a"), "чужая версия")
        XCTAssertNil(LoginRequest.parse(data(["v": 1, "id": "b", "url": "https://x.com"]), fileID: "a"), "id не как у файла")
        XCTAssertNil(LoginRequest.parse(data(["v": 1, "id": "a", "url": "file:///etc/passwd"]), fileID: "a"))
        XCTAssertNil(LoginRequest.parse(data(["v": 1, "id": "a", "url": "javascript:alert(1)"]), fileID: "a"))
        XCTAssertNil(LoginRequest.parse(Data("{".utf8), fileID: "a"))
    }

    func testQueueOrderAndOneLoginPerSite() {
        let a = request("1000-1", "https://appstoreconnect.apple.com", at: "2026-10-30T18:00:05Z")
        let b = request("0999-1", "https://play.google.com/console", at: "2026-10-30T18:00:01Z")
        let c = request("1001-1", "https://www.appstoreconnect.apple.com/login", at: "2026-10-30T18:00:09Z")
        let ordered = LoginQueue.ordered([a, c, b])
        XCTAssertEqual(ordered.map(\.id), ["0999-1", "1000-1", "1001-1"], "порядок прихода")
        let (queue, duplicates) = LoginQueue.split(ordered)
        XCTAssertEqual(queue.map(\.id), ["0999-1", "1000-1"], "тот же сайт второй раз — тот же вход")
        XCTAssertEqual(duplicates, ["1001-1": "1000-1"])
    }

    /// Слово Элвиса: «что будет, если несколько входов нужно сделать» — по одному, «вход 1 из 3».
    func testCounterKeepsFinishedInCount() {
        XCTAssertEqual(LoginQueue.counter(position: 0, finishedRecent: 0, queued: 3).index, 1)
        XCTAssertEqual(LoginQueue.counter(position: 0, finishedRecent: 0, queued: 3).total, 3)
        let second = LoginQueue.counter(position: 0, finishedRecent: 1, queued: 2)
        XCTAssertEqual([second.index, second.total], [2, 3], "первый вошёл — второй стал «2 из 3», а не «1 из 2»")
        XCTAssertEqual(LoginQueue.line2(index: 2, total: 3, click: .field), "2 из 3 · клик — в поле")
        XCTAssertEqual(LoginQueue.line2(index: 1, total: 1, click: .field), "клик — курсор в поле", "один вход — без счёта")
    }

    func testStateRecordRoundTrip() throws {
        let record = LoginStateRecord(id: "1-1", state: .shown, reason: "", url: "https://x.com", name: "X", index: 1, total: 2)
        let data = record.json(at: Date(timeIntervalSince1970: 1_800_000_000))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["v"] as? Int, 1)
        XCTAssertEqual(json["state"] as? String, "shown")
        XCTAssertEqual(json["total"] as? Int, 2)
        let parsed = try XCTUnwrap(LoginStateRecord.parse(data))
        XCTAssertEqual(parsed.state, .shown)
        XCTAssertEqual(parsed.at, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(LoginState.done.finished && LoginState.gone.finished && LoginState.failed.finished)
        XCTAssertFalse(LoginState.waiting.finished || LoginState.shown.finished)
    }

    // MARK: - поле входа

    private func input(_ label: String, y: CGFloat, secure: Bool = false, empty: Bool = true, enabled: Bool = true) -> LoginField {
        LoginField(role: "AXTextField", subrole: secure ? "AXSecureTextField" : nil,
                   frame: CGRect(x: 660, y: y, width: 400, height: 44), enabled: enabled, empty: empty, label: label)
    }

    /// App Store Connect: форма Apple ID в рамке idmsa.apple.com — сперва почта, заполнил — пароль.
    func testPicksAppleIDThenPassword() {
        let search = input("search", y: 100)
        let email = input("email or phone number account_name_text_field", y: 420)
        let password = input("password password_text_field", y: 480, secure: true)
        XCTAssertEqual(LoginFieldPick.choose([search, email, password], visible: chrome, loginURL: true), 1)
        var filled = email
        filled.empty = false
        XCTAssertEqual(LoginFieldPick.choose([search, filled, password], visible: chrome, loginURL: true), 2)
        var both = password
        both.empty = false
        XCTAssertEqual(LoginFieldPick.choose([search, filled, both], visible: chrome, loginURL: true), 1,
                       "всё заполнено — первое поле входа на виду, не поиск")
        XCTAssertEqual(LoginFieldPick.choose([input("email", y: 420, enabled: false), password], visible: chrome,
                                             loginURL: false), 1, "выключенное поле не берём")
    }

    /// Второй шаг (код подтверждения): подписи нет, но адрес — вход; кабинет после входа — не вход.
    func testCodesOnLoginPageAndNothingOnDashboard() {
        let digits = (0..<6).map { LoginField(role: "AXTextField", subrole: nil,
                                              frame: CGRect(x: 600 + CGFloat($0) * 50, y: 420, width: 40, height: 50),
                                              enabled: true, empty: $0 > 0, label: "") }
        XCTAssertEqual(LoginFieldPick.choose(digits, visible: chrome, loginURL: true), 1, "первое пустое")
        XCTAssertNil(LoginFieldPick.choose([input("search apps", y: 100)], visible: chrome, loginURL: false),
                     "кабинет: поиск — не вход")
        XCTAssertTrue(LoginFieldPick.isLoginURL("https://idmsa.apple.com/appleauth/auth/signin?widgetKey=1"))
        XCTAssertTrue(LoginFieldPick.isLoginURL("https://appstoreconnect.apple.com/login"))
        XCTAssertFalse(LoginFieldPick.isLoginURL("https://appstoreconnect.apple.com/apps"))
    }

    func testOffscreenFieldIsLastResort() {
        let below = input("email", y: 2000)
        let visible = input("email", y: 420, empty: false)
        XCTAssertEqual(LoginFieldPick.choose([below, visible], visible: chrome, loginURL: false), 1, "на виду — лучше")
        XCTAssertEqual(LoginFieldPick.choose([below], visible: chrome, loginURL: false), 0)
    }

    // MARK: - конец входа

    func testDoneWhenFieldVanishesForAWhile() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var tracker = LoginTracker(shownAt: t0)
        XCTAssertEqual(tracker.observe(found: true, active: true, now: t0 + 1), .wait)
        XCTAssertEqual(tracker.observe(found: false, active: true, now: t0 + 2), .wait)
        XCTAssertEqual(tracker.observe(found: false, active: true, now: t0 + 2.5), .wait)
        XCTAssertEqual(tracker.observe(found: false, active: true, now: t0 + 3), .wait, "три опроса, но меньше 4 с")
        XCTAssertEqual(tracker.observe(found: true, active: true, now: t0 + 3.5), .wait, "поле вернулось — счёт сначала")
        for step in 0..<8 { _ = tracker.observe(found: false, active: true, now: t0 + 4 + Double(step) * 0.5) }
        XCTAssertEqual(tracker.observe(found: false, active: true, now: t0 + 8.5), .done("поле входа пропало — вошёл"))
    }

    func testInactiveTabAndUnreadTreeDoNotCount() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var tracker = LoginTracker(shownAt: t0)
        _ = tracker.observe(found: true, active: true, now: t0 + 1)
        for step in 0..<40 {
            XCTAssertEqual(tracker.observe(found: false, active: false, now: t0 + 2 + Double(step)), .wait, "вкладка не видна")
            XCTAssertEqual(tracker.observe(found: nil, active: true, now: t0 + 2.5 + Double(step)), .wait, "дерево не прочли")
        }
    }

    func testAlreadyLoggedInAndTimeout() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var tracker = LoginTracker(shownAt: t0)
        for step in 0..<20 { XCTAssertEqual(tracker.observe(found: false, active: true, now: t0 + Double(step) * 0.5), .wait) }
        XCTAssertEqual(tracker.observe(found: false, active: true, now: t0 + 12.5),
                       .done("поля входа на странице нет — похоже, уже вошёл"))
        var waiting = LoginTracker(shownAt: t0)
        _ = waiting.observe(found: true, active: true, now: t0 + 1)
        XCTAssertEqual(waiting.observe(found: true, active: true, now: t0 + LoginTracker.timeout), .timeout)
    }

    // MARK: - Chrome

    func testChromeTabsPickAndAnswers() {
        let tabs = LoginChrome.parseList("11\t101\thttps://mail.google.com/\n11\t102\thttps://appstoreconnect.apple.com/apps\n"
                                         + "12\t201\thttps://appstoreconnect.apple.com/login?x=1\tхвост\n\nмусор\n")
        XCTAssertEqual(tabs.count, 3)
        XCTAssertEqual(tabs[2].url, "https://appstoreconnect.apple.com/login?x=1\tхвост", "адрес — до конца строки")
        XCTAssertEqual(LoginChrome.pick(tabs, for: "https://appstoreconnect.apple.com/login")?.tab, 201, "адрес совпал — лучше")
        XCTAssertEqual(LoginChrome.pick(tabs, for: "https://appstoreconnect.apple.com/")?.tab, 102)
        XCTAssertNil(LoginChrome.pick(tabs, for: "https://play.google.com/console"))
        let opened = LoginChrome.parseOpened("ok\t12\t201\t360, 60, 1360, 840\n")
        XCTAssertEqual(opened?.window, 12)
        XCTAssertEqual(opened?.tab, 201)
        XCTAssertEqual(opened?.bounds, chrome)
        XCTAssertNil(LoginChrome.parseOpened("execution error"))
        XCTAssertEqual(LoginChrome.parseCheck("gone\n"), .gone)
        XCTAssertEqual(LoginChrome.parseCheck("ok\t12\tfalse\t360,60,1360,840\thttps://a.b/c"),
                       .found(LoginChrome.Check(window: 12, active: false, bounds: chrome, url: "https://a.b/c")))
        XCTAssertNil(LoginChrome.parseCheck(""), "пустой ответ — не повод решать")
    }

    func testScriptsQuoteAddressAndCompile() throws {
        let tricky = "https://x.com/?q=\"a\"\\b"
        let script = LoginChrome.openScript(url: tricky)
        XCTAssertTrue(script.contains("\"https://x.com/?q=\\\"a\\\"\\\\b\""), "кавычки и обратная косая — экранированы")
        // Только компиляция (словарь Chrome из его пакета), ничего не запускаем. Chrome нет — проверять нечем.
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: LoginChrome.bundleID) != nil else { return }
        for source in [LoginChrome.listScript(), LoginChrome.activateScript(window: 1, tab: 2), script,
                       LoginChrome.checkScript(tab: 2)] {
            var error: NSDictionary?
            let compiled = NSAppleScript(source: source)?.compileAndReturnError(&error) ?? false
            XCTAssertTrue(compiled, "\(error ?? [:])\n\(source)")
        }
    }

    // MARK: - вода с явной целью

    private func run(_ sim: inout ConsentWaterSim, cursor: CGPoint, seconds: CGFloat, aim: CGRect?) -> ConsentWaterFrame {
        var frame = ConsentWaterFrame()
        for _ in 0..<Int(seconds / dt) {
            frame = sim.step(dt: dt, ConsentWaterInput(cursor: cursor, targets: [chrome], screens: [screen],
                                                       visible: [screen], alive: true, aim: aim))
        }
        return frame
    }

    /// Стрелка — на поле входа, а не на ближайшее окно; свечение — вокруг окна Chrome; окошко может лечь на окно Chrome.
    func testArrowAimsAtFieldAndWindowGlows() {
        var sim = ConsentWaterSim(seed: 3)
        // Курсор внутри окна Chrome, далеко от поля: у окон доступа окошко над окном запроса пропало бы.
        let cursor = CGPoint(x: 460, y: 760)
        let frame = run(&sim, cursor: cursor, seconds: 1.5, aim: field)
        XCTAssertEqual(frame.rings.first?.rect, field, "первая рамка — у поля (язык, бульк)")
        XCTAssertEqual(frame.rings.dropFirst().map(\.rect), [chrome], "вторая — свечение вокруг окна Chrome")
        XCTAssertEqual(frame.openRings, 1, "внутри окна Chrome вода есть — дырка только у поля")
        XCTAssertEqual(frame.uniforms(origin: .zero, scale: 2, light: false)[4].z, 1)
        XCTAssertGreaterThan(frame.plaque.opacity, 0.5, "окошко видно и над окном Chrome")
        let toField = atan2(field.midY - cursor.y, field.midX - cursor.x)
        XCTAssertEqual(Double(WaterGeo.angleDelta(frame.plaque.angle, toField)), 0, accuracy: 0.15, "стрелка — на поле")
        XCTAssertFalse(WaterGeo.hit(frame.plaque.panelRect, field), "на поле окошко не ложится")
        // Без явной цели — по-старому: ближайшее окно, и над ним окошка нет.
        var old = ConsentWaterSim(seed: 3)
        let plain = run(&old, cursor: cursor, seconds: 1.5, aim: nil)
        XCTAssertEqual(plain.rings.first?.rect, chrome)
        XCTAssertEqual(plain.plaque.opacity, 0)
        XCTAssertEqual(plain.openRings, 0)
    }

    func testCursorAtFieldMergesWithBlub() {
        var sim = ConsentWaterSim(seed: 3)
        _ = run(&sim, cursor: CGPoint(x: 460, y: 760), seconds: 1, aim: field)
        var blub = false
        for _ in 0..<60 {
            let frame = sim.step(dt: dt, ConsentWaterInput(cursor: CGPoint(x: field.midX, y: field.maxY + 30), targets: [chrome],
                                                           screens: [screen], visible: [screen], alive: true, aim: field))
            blub = blub || frame.blub
        }
        XCTAssertTrue(blub, "дошёл курсором до поля — «бульк», окошко влилось в рамку поля")
        XCTAssertTrue(sim.merged)
    }

    /// Без дырок: рамку поля рисовать поверх окна Chrome; монитор с целью — целиком, даже без курсора.
    func testLayersWithoutHolesCoverTargetScreen() {
        let right = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        let onRight = CGRect(x: 1800, y: 100, width: 800, height: 600)
        let cursor = CGPoint(x: 300, y: 300)
        XCTAssertEqual(ConsentWaterLayout.windows(screens: [screen, right], targets: [onRight], cursor: cursor, cut: false),
                       [screen, right])
        XCTAssertEqual(ConsentWaterLayout.windows(screens: [screen, right], targets: [onRight], cursor: cursor).count, 5,
                       "окна доступа — как раньше: монитор курсора и четыре куска вокруг дырки")
    }

    /// Подписи окошка влезают целиком: заголовок мельчает, но не меньше 12 у обычного имени; строки клика — без «…».
    func testPlaqueTextsFit() {
        let width = ConsentWaterK.plW - 68 - 8 - 2
        let fits = { (text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat? in
            let font = ConsentWaterPlaqueView.fittedFontSize(text, size: size, weight: weight, width: width)
            let wide = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: font, weight: weight)]).width
            return wide <= width + 0.5 ? font : nil
        }
        XCTAssertEqual(fits(ConsentWaterSim.titleConsent, 15, .bold), 15, "у окон доступа — как было")
        let title = fits(LoginQueue.title("App Store Connect"), 15, .bold)
        XCTAssertNotNil(title)
        XCTAssertGreaterThanOrEqual(title ?? 0, 12)
        for click in [LoginQueue.Click.field, .tab, .window] {
            XCTAssertNotNil(fits(LoginQueue.line2(index: 1, total: 1, click: click), 11.5, .medium), click.long)
            XCTAssertNotNil(fits(LoginQueue.line2(index: 3, total: 3, click: click), 11.5, .medium), click.short)
        }
    }

    // MARK: - кадры (по желанию)

    func testSnapshotsWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["LOGIN_WATER_SNAPSHOT_DIR"],
              let renderer = ConsentWaterRenderer() else { return }
        let url = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let shots: [(String, CGPoint, String, Bool)] = [
            ("login-far", CGPoint(x: 130, y: 780), LoginQueue.line2(index: 1, total: 1, click: .field), false),
            ("login-inside", CGPoint(x: 470, y: 740), LoginQueue.line2(index: 2, total: 3, click: .field), false),
            ("login-calm", CGPoint(x: 160, y: 300), LoginQueue.line2(index: 1, total: 1, click: .field), true),
        ]
        for (name, cursor, line2, calm) in shots {
            var sim = ConsentWaterSim(calm: calm, seed: 7)
            var frame = run(&sim, cursor: cursor, seconds: 1.4, aim: field)
            frame.plaque.title = LoginQueue.title("App Store Connect")
            frame.plaque.line2 = line2
            try write(compose(renderer: renderer, frame: frame, cursor: cursor), to: url.appendingPathComponent("\(name).png"))
        }
    }

    /// Стол, окно Chrome с формой Apple ID, вода, окошко и курсор — как на экране.
    private func compose(renderer: ConsentWaterRenderer, frame: ConsentWaterFrame, cursor: CGPoint) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(screen.width), height: Int(screen.height), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let flip = { (r: CGRect) in CGRect(x: r.minX, y: self.screen.maxY - r.maxY, width: r.width, height: r.height) }
        let colors = [NSColor(srgbRed: 0.20, green: 0.12, blue: 0.32, alpha: 1).cgColor,
                      NSColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: screen.width, y: screen.height), options: [])
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        // Окно Chrome: полоса вкладок, строка адреса, белая страница, форма входа.
        NSColor(white: 0.97, alpha: 1).setFill()
        NSBezierPath(roundedRect: flip(chrome), xRadius: 10, yRadius: 10).fill()
        NSColor(white: 0.86, alpha: 1).setFill()
        NSBezierPath(rect: flip(CGRect(x: chrome.minX, y: chrome.minY, width: chrome.width, height: 74))).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: flip(CGRect(x: chrome.minX + 90, y: chrome.minY + 42, width: 600, height: 26)),
                     xRadius: 13, yRadius: 13).fill()
        let text = { (s: String, at: CGPoint, size: CGFloat, color: NSColor) in
            (s as NSString).draw(at: CGPoint(x: at.x, y: self.screen.maxY - at.y - size * 1.25),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
        }
        text("appstoreconnect.apple.com/login", CGPoint(x: chrome.minX + 104, y: chrome.minY + 46), 13, .darkGray)
        text("App Store Connect", CGPoint(x: chrome.minX + 20, y: chrome.minY + 12), 12, .black)
        text("Sign in to App Store Connect", CGPoint(x: field.minX + 20, y: field.minY - 90), 26, .black)
        for (y, label) in [(field.minY, "Email or Phone Number"), (field.maxY + 16, "Password")] {
            let r = CGRect(x: field.minX, y: y, width: field.width, height: field.height)
            NSColor(white: 0.75, alpha: 1).setStroke()
            let path = NSBezierPath(roundedRect: flip(r), xRadius: 8, yRadius: 8)
            path.lineWidth = 1
            path.stroke()
            text(label, CGPoint(x: r.minX + 14, y: r.minY + 13), 15, .gray)
        }
        NSGraphicsContext.restoreGraphicsState()
        for window in ConsentWaterLayout.windows(screens: [screen], targets: [chrome, field], cursor: cursor, cut: false) {
            let px = try XCTUnwrap(renderer.pixels(frame, window: window, scale: 1, light: false))
            let provider = CGDataProvider(data: Data(px.bytes) as CFData)!
            let image = CGImage(width: px.width, height: px.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: px.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                    | CGImageAlphaInfo.premultipliedFirst.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            ctx.draw(image, in: flip(window))
        }
        if frame.plaque.shown {
            let view = ConsentWaterPlaqueView(frame: ConsentWaterPlaqueView.panelBounds)
            view.apply(frame.plaque, scale: 1)
            let r = flip(frame.plaque.panelRect)
            let bounds = ConsentWaterPlaqueView.panelBounds
            ctx.saveGState()
            ctx.translateBy(x: r.midX - bounds.width / 2, y: r.midY - bounds.height / 2)
            ctx.setAlpha(frame.plaque.opacity)
            view.layer?.render(in: ctx)
            ctx.restoreGState()
        }
        let c = CGPoint(x: cursor.x, y: screen.maxY - cursor.y)
        let arrow = CGMutablePath()
        arrow.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: -18), CGPoint(x: 4.6, y: -13.6),
                                 CGPoint(x: 7.7, y: -20.6), CGPoint(x: 10.9, y: -19.2), CGPoint(x: 7.8, y: -12.4),
                                 CGPoint(x: 13, y: -12.4)])
        arrow.closeSubpath()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.addPath(arrow)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.4)
        ctx.drawPath(using: .fillStroke)
        return try XCTUnwrap(ctx.makeImage())
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
