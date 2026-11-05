import XCTest
@testable import ClaudeAX

/// WF263: «Показать» и «Галерея» не молчат.
///
/// #9812 (слово Элвиса 11.10: «ракету показать в окне клауда не работает»): после подъёма окна показ отсчёта шёл, только
/// если весь подбор окна сходился с первым, — а он плывёт сам (ответ главного окна живёт 10 с при круге карты 15 с).
/// Теперь сверка — только «окно то же»: адрес — его свежий, иначе прежний.
///
/// #9631 (жалоба коллеги 10.10: «нажимаю и ничего не открывается»): «Галерея» отвечает странице словом исхода; горящая
/// кнопка при спрятанном окне галереи открывает, а не гасит; запуск — «запускаю» сразу, сорвался потом — HUD.
final class SilentShowWF263Tests: XCTestCase {
    typealias FakeViewer = ViewerChannelWF104Tests.FakeViewer
    typealias Target = ClaudeActions.SendDelayPreviewTarget
    typealias Outcome = ViewerClient.GalleryOutcome
    private let token = String(repeating: "b2", count: 16)
    private let galleryPath = "/Applications/PimpViewer.app/Contents/MacOS/PimpViewer"
    private var tmp: URL!
    private var tokenURL: URL { tmp.appendingPathComponent("channel.token") }

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("silent-show-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try Data((token + "\n").utf8).write(to: tokenURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - #9812

    func testPreviewAddressKeepsTheRaisedWindow() {
        let sent = Target(id: 7, match: "/epitaxy/local_a", chat: nil)
        XCTAssertEqual(ClaudeAXController.sendDelayPreviewAddress(sent: sent, now: nil), sent,
                       "окно сейчас не опознано (ответ главного старше 10 с) — прежний адрес, а не тишина")
        let fresh = Target(id: 7, match: "/epitaxy/local_b", chat: nil)
        XCTAssertEqual(ClaudeAXController.sendDelayPreviewAddress(sent: sent, now: fresh), fresh,
                       "тот же windowId, чат сменился на месте — свежий адрес")
        XCTAssertEqual(ClaudeAXController.sendDelayPreviewAddress(sent: sent, now: Target(id: 9, match: nil, chat: "local_c")),
                       sent, "другое окно — не наш адрес")
        XCTAssertFalse(ClaudeAXController.sendDelayPreviewGone.isEmpty)
        XCTAssertFalse(ClaudeAXController.sendDelayPreviewNotWritten.isEmpty)
    }

    /// Источник: после подъёма нет сверки всего подбора с первым и нет тихого `return` без причины.
    func testPreviewSourceHasNoSilentDrop() throws {
        let url = Repo.root.appendingPathComponent("app/Sources/ClaudeAX/ClaudeAXController+PageLook.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("self.sendDelayPreviewTarget() == target"), "вернулась сверка, что молча глушит показ")
        XCTAssertTrue(source.contains("onSendDelayPreviewFailed?(Self.sendDelayPreviewGone)"))
        XCTAssertTrue(source.contains("onSendDelayPreviewFailed?(Self.sendDelayPreviewNotWritten)"))
    }

    // MARK: - #9631

    private func client(_ fake: FakeViewer, viewer: Bool = true) -> ViewerClient {
        let client = ViewerClient(port: fake.port, tokenURL: tokenURL, launches: false)
        client.installed = { true }
        client.running = { true }
        client.launch = { XCTFail("запуск не ждали") }
        client.raise = { true }
        let gallery = galleryPath
        if viewer { client.owners = { _, _ in [.init(pid: 42, path: gallery)] } }
        client.windowWait = 0.3
        return client
    }

    private func gallery(_ client: ViewerClient, on: Bool = true, timeout: TimeInterval = 8) -> [Outcome] {
        let done = expectation(description: "gallery")
        let lock = NSLock()
        var outcomes: [Outcome] = []
        client.gallery(chat: "local_a", on: on) { outcome in
            lock.lock(); outcomes.append(outcome); lock.unlock()
            done.fulfill()
        }
        wait(for: [done], timeout: timeout)
        // Второго ответа быть не должно.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        lock.lock(); defer { lock.unlock() }
        return outcomes
    }

    func testGalleryOpenedOffAndHiddenWindowOpens() throws {
        let fake = try FakeViewer()
        fake.answer = { _, _ in FakeViewer.json(#"{"ok":true}"#) }
        let client = client(fake)
        XCTAssertEqual(gallery(client), [.opened])
        XCTAssertEqual(gallery(client, on: false), [.off])
        client.windowShown = { false }
        XCTAssertEqual(gallery(client, on: false), [.noWindow], "окна галереи не видно — нажатие открывает, окна так и нет")
        let heads = fake.requests.map { $0.components(separatedBy: "\r\n")[0] }
        XCTAssertEqual(heads, ["GET /gallery?chat=local_a&on=1 HTTP/1.1", "GET /gallery?chat=local_a&on=0 HTTP/1.1",
                               "GET /gallery?chat=local_a&on=1 HTTP/1.1"])
    }

    func testGalleryRefusedAndForeign() throws {
        let fake = try FakeViewer()
        fake.answer = { _, _ in FakeViewer.json(#"{"error":"bad"}"#, status: "400 Bad Request") }
        XCTAssertEqual(gallery(client(fake)), [.refused])

        let foreign = client(fake, viewer: false)
        foreign.owners = { _, _ in [.init(pid: 77, path: "/tmp/evil")] }
        foreign.note = { _ in }
        let before = fake.requests.count
        XCTAssertEqual(gallery(foreign), [.foreign])
        XCTAssertEqual(fake.requests.count, before, "чужому слушателю запроса нет (#8302)")
    }

    func testGalleryMissing() throws {
        let fake = try FakeViewer()
        let client = client(fake, viewer: false)
        client.installed = { false }
        client.running = { false }
        client.owners = { _, _ in [] }
        XCTAssertEqual(gallery(client), [.missing])
    }

    func testGalleryNoTokenAndSilent() throws {
        let fake = try FakeViewer()
        try FileManager.default.removeItem(at: tokenURL)
        XCTAssertEqual(gallery(client(fake)), [.noToken])
        XCTAssertEqual(fake.requests.count, 0, "без ключа запросов нет")

        try Data((token + "\n").utf8).write(to: tokenURL)
        let quiet = try FakeViewer()
        XCTAssertEqual(gallery(client(quiet)), [.silent], "запущен, а не отвечает")
    }

    /// PimpViewer не запущен: «запускаю» уходит сразу, по запуску; окно не вышло — HUD поздним исходом.
    func testGalleryLaunchingAnswersAtOnceAndLateFailureGoesToHUD() throws {
        let fake = try FakeViewer()
        // Первый /gallery — до запуска: тишина (таймаут клиента); дальше галерея жива.
        fake.answer = { head, index in
            index == 0 ? nil : FakeViewer.json(head.hasPrefix("GET /ping") ? #"{"ready":true}"# : #"{"ok":true}"#)
        }
        let client = ViewerClient(port: fake.port, tokenURL: tokenURL, launches: true)
        client.installed = { true }
        client.running = { false }
        let gallery = galleryPath
        client.owners = { _, _ in [.init(pid: 42, path: gallery)] }
        client.windowShown = { false }
        client.windowWait = 0.2
        let lock = NSLock()
        var launches = 0
        client.launch = { lock.lock(); launches += 1; lock.unlock() }
        let late = expectation(description: "late")
        var lateOutcome: Outcome?
        client.onGalleryLate = { lateOutcome = $0; late.fulfill() }
        XCTAssertEqual(self.gallery(client), [.launching])
        wait(for: [late], timeout: 6)
        XCTAssertEqual(lateOutcome, .noWindow)
        lock.lock(); XCTAssertEqual(launches, 1); lock.unlock()
        XCTAssertEqual(ClaudeAXController.galleryLateText(.noWindow), "🖼 Галерея запустилась, но окна не показала")
    }

    /// Ответ странице: 200 — открылась/снят/запускается, иначе 503; слово — телом; CORS — только claude.ai.
    func testViewerResponseCarriesWord() {
        let browser = HtmlChromeOpener.PageAccess.browser(preflight: false)
        let ok = String(decoding: HtmlChromeOpener.viewerResponse("launching", access: browser), as: UTF8.self)
        XCTAssertTrue(ok.hasPrefix("HTTP/1.1 200 OK\r\n"), ok)
        XCTAssertTrue(ok.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"))
        XCTAssertTrue(ok.hasSuffix("\r\n\r\nlaunching"))
        let bad = String(decoding: HtmlChromeOpener.viewerResponse("no-token", access: browser), as: UTF8.self)
        XCTAssertTrue(bad.hasPrefix("HTTP/1.1 503 Service Unavailable\r\n"), bad)
        XCTAssertTrue(bad.hasSuffix("\r\n\r\nno-token"))
        let junk = String(decoding: HtmlChromeOpener.viewerResponse("???", access: .native), as: UTF8.self)
        XCTAssertTrue(junk.hasPrefix("HTTP/1.1 503"), "незнакомое слово — отказ")
        XCTAssertFalse(junk.contains("Access-Control"), "не браузеру CORS не нужен")
        for outcome in [Outcome.opened, .off, .launching] { XCTAssertTrue(outcome.ok) }
        for outcome in [Outcome.noWindow, .missing, .foreign, .noToken, .silent, .refused] { XCTAssertFalse(outcome.ok) }
    }
}
