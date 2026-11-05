import Network
import XCTest
@testable import ClaudeAX

/// Панель материалов WF277 (#10644, контракт `docs/contracts/560-wf277-dock.md`): разбор К-DOCK-1, окно Claude по рамке
/// ±2, «последний выигрывает», сердце и тишина, владелец дока, виды файлов только для дока, К-DOCK-2 против своего
/// слушателя и ответ странице по настоящему сокету. Живые порты 47615/47616, окна и склад галереи не трогаем.
final class MaterialsDockWF277Tests: XCTestCase {
    private let windowA = CGRect(x: 383, y: 29, width: 896, height: 742)
    private let windowB = CGRect(x: -1200, y: 100, width: 1000, height: 800)

    private func head(_ target: String) -> String { "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" }

    private func dockQuery(on: Int = 1, vis: Int = 1, x: Int = 0, w: Int = 420, window: CGRect? = nil,
                           chat: String = "local_a") -> String {
        let frame = window ?? windowA
        return "/dock?on=\(on)&vis=\(vis)&x=\(x)&y=40&w=\(w)&h=700&wx=\(Int(frame.minX))&wy=\(Int(frame.minY))"
            + "&ww=\(Int(frame.width))&wh=\(Int(frame.height))&chat=\(chat)&seq=7"
    }

    private func request(vis: Bool = true, x: Int = 0, window: CGRect? = nil, chat: String = "local_a") -> MaterialsDock.Request {
        MaterialsDock.parse(head(dockQuery(vis: vis ? 1 : 0, x: x, window: window, chat: chat)))!
    }

    private func off(_ window: CGRect?, chat: String? = nil) -> MaterialsDock.Request {
        MaterialsDock.Request(on: false, vis: false, place: nil, chat: chat, window: window)
    }

    // MARK: - разбор К-DOCK-1

    func testParseDockRequest() throws {
        let on = try XCTUnwrap(MaterialsDock.parse(head(dockQuery())))
        XCTAssertEqual(on, MaterialsDock.Request(on: true, vis: true, place: MaterialsDock.Place(
            place: CGRect(x: 0, y: 40, width: 420, height: 700), window: windowA), chat: "local_a"))
        XCTAssertEqual(MaterialsDock.parse(head(dockQuery(vis: 0)))?.vis, false)
        XCTAssertEqual(MaterialsDock.parse(head(dockQuery(window: windowB)))?.place?.window, windowB, "второй экран — со знаком")
        XCTAssertEqual(MaterialsDock.parse(head("/dock?on=0&chat=local_a&seq=9")), off(nil, chat: "local_a"))
        XCTAssertEqual(MaterialsDock.parse(head("/dock?on=0")), off(nil))
        // on=0 несёт рамку окна — владельца Пимп узнаёт по окну (проверяющий WF277, ошибка 2).
        XCTAssertEqual(MaterialsDock.parse(head("/dock?on=0&chat=local_a&wx=-1200&wy=100&ww=1000&wh=800&seq=9")),
                       off(windowB, chat: "local_a"))
        XCTAssertEqual(MaterialsDock.parse(head("/dock?on=0&wx=1&wy=2&ww=0&wh=800")), off(nil), "негодная рамка — без рамки")
        // probe=1 — жив ли PimpViewer (ошибка 3).
        XCTAssertEqual(MaterialsDock.parse(head("/dock?probe=1")),
                       MaterialsDock.Request(on: false, vis: false, place: nil, chat: nil, probe: true))
        XCTAssertNil(MaterialsDock.parse(head(dockQuery(chat: "evil")))?.chat, "мусорный чат — без чата, запрос годен")
        XCTAssertNotNil(MaterialsDock.parse(head(dockQuery(chat: "evil"))))
        XCTAssertNil(MaterialsDock.parse(head("/dockx?on=0")))
        XCTAssertNil(MaterialsDock.parse("POST /dock?on=0 HTTP/1.1\r\n"))
    }

    func testParseRejectsBadNumbersAndPlaceOutsideWindow() {
        let good = dockQuery()
        let bad = [good.replacingOccurrences(of: "vis=1", with: "vis=2"), good.replacingOccurrences(of: "&vis=1", with: ""),
                   good.replacingOccurrences(of: "on=1", with: "on=yes"), good.replacingOccurrences(of: "w=420", with: "w=0"),
                   good.replacingOccurrences(of: "w=420", with: "w=4.5"), good.replacingOccurrences(of: "h=700", with: "h=abc"),
                   good.replacingOccurrences(of: "x=0", with: "x=-1"), good.replacingOccurrences(of: "x=0", with: "x=1234567"),
                   good.replacingOccurrences(of: "&wh=742", with: ""), good.replacingOccurrences(of: "ww=896", with: "ww=0"),
                   dockQuery(x: 600), // 600 + 420 > 896 + 2: место вне окна
                   good.replacingOccurrences(of: "y=40", with: "y=50")] // 50 + 700 > 742 + 2
        for query in bad { XCTAssertNil(MaterialsDock.parse(head(query)), query) }
        XCTAssertNotNil(MaterialsDock.parse(head(dockQuery(x: 478))), "478 + 420 = 898 — в допуске ±2")
    }

    // MARK: - окно Claude ±2

    private func info(_ number: Int, _ rect: CGRect, owner: String = "Claude", layer: Int = 0, onscreen: Bool = true) -> [String: Any] {
        var entry: [String: Any] = [kCGWindowNumber as String: NSNumber(value: number),
                                    kCGWindowOwnerName as String: owner,
                                    kCGWindowLayer as String: NSNumber(value: layer),
                                    kCGWindowBounds as String: rect.dictionaryRepresentation]
        if onscreen { entry[kCGWindowIsOnscreen as String] = NSNumber(value: true) }
        return entry
    }

    func testWindowFoundWithinTwoPoints() {
        let near = windowA.offsetBy(dx: 2, dy: -2).insetBy(dx: -1, dy: 0)
        XCTAssertEqual(MaterialsDock.windowID(in: [info(7, near)], frame: windowA), 7)
        XCTAssertNil(MaterialsDock.windowID(in: [info(7, windowA.offsetBy(dx: 3, dy: 0))], frame: windowA), "3 точки — мимо")
        XCTAssertNil(MaterialsDock.windowID(in: [info(7, windowA, owner: "PimpViewer")], frame: windowA))
        XCTAssertNil(MaterialsDock.windowID(in: [info(7, windowA, layer: 3)], frame: windowA), "не обычный слой")
        // Видимое — первым сверху; невидимое (другой стол) — только если видимого нет.
        let list = [info(5, windowA, onscreen: false), info(6, windowB), info(7, windowA), info(8, windowA)]
        XCTAssertEqual(MaterialsDock.windowID(in: list, frame: windowA), 7)
        XCTAssertEqual(MaterialsDock.windowID(in: [info(5, windowA, onscreen: false), info(9, windowA, onscreen: false)],
                                              frame: windowA), 5)
        XCTAssertEqual(MaterialsDock.windowID(in: list, frame: windowB), 6)
    }

    // MARK: - состояние дока

    /// Док с подменённой галереей: запросы копятся, ответы — по команде теста (`auto` — сразу).
    private final class Harness {
        let dock = MaterialsDock()
        var clock = Date(timeIntervalSince1970: 1_000)
        private let lock = NSLock()
        private var commands: [MaterialsDock.Command] = []
        private var waiting: [(MaterialsDock.Reply) -> Void] = []
        private var answers: [MaterialsDock.Answer] = []
        var auto = false
        var finds = 0

        init(windows: [(frame: CGRect, id: CGWindowID)]) {
            dock.heartTimer = false
            dock.now = { [unowned self] in self.clock }
            dock.findWindow = { [unowned self] frame in self.finds += 1; return windows.first { $0.frame == frame }?.id }
            dock.send = { [unowned self] command, done in
                self.lock.lock()
                self.commands.append(command)
                let auto = self.auto
                if !auto { self.waiting.append(done) }
                self.lock.unlock()
                if auto { done(MaterialsDock.Reply(viewer: .up, docked: command.spot != nil)) }
            }
        }

        var sent: [MaterialsDock.Command] { dock.drain(); lock.lock(); defer { lock.unlock() }; return commands }
        var replies: [MaterialsDock.Answer] { dock.drain(); lock.lock(); defer { lock.unlock() }; return answers }

        func handle(_ request: MaterialsDock.Request) {
            dock.handle(request) { [unowned self] answer in
                self.lock.lock(); self.answers.append(answer); self.lock.unlock()
            }
            dock.drain()
        }

        /// Ответить на самый старый запрос в полёте.
        func complete(docked: Bool = true) {
            dock.drain()
            lock.lock()
            let done = waiting.removeFirst()
            lock.unlock()
            done(MaterialsDock.Reply(viewer: .up, docked: docked))
            dock.drain()
        }

        func tick() { dock.tick(); dock.drain() }
    }

    func testLastWinsOneInFlightAndOnePending() {
        let harness = Harness(windows: [(windowA, 42)])
        for x in 0..<5 { harness.handle(request(x: x * 10)) }
        XCTAssertEqual(harness.sent.count, 1, "в полёте — один")
        XCTAssertEqual(harness.sent.first?.spot, MaterialsDock.Spot(window: 42, place: CGRect(x: 0, y: 40, width: 420, height: 700)))
        XCTAssertEqual(harness.finds, 1, "та же рамка окна — список окон не обходим на каждом кадре тяги")
        XCTAssertTrue(harness.replies.isEmpty, "ответ странице — когда PimpViewer ответил")
        harness.complete()
        XCTAssertEqual(harness.replies.count, 1)
        XCTAssertEqual(harness.sent.count, 2, "отложенный — один, последний: промежуточные рамки не ходят")
        XCTAssertEqual(harness.sent.last?.spot?.place.minX, 40)
        harness.complete(docked: true)
        XCTAssertEqual(harness.replies.count, 5, "ответ получили все: заменённые — по последней рамке")
        XCTAssertEqual(Set(harness.replies.map { $0.docked }), [true])
        XCTAssertEqual(harness.replies.last, MaterialsDock.Answer(ok: true, viewer: .up, docked: true, mine: true))
        XCTAssertEqual(harness.sent.count, 2)
        // Окна с такой рамкой нет — к галерее не ходим, `ok:false`.
        harness.handle(request(window: windowB))
        XCTAssertEqual(harness.sent.count, 2)
        XCTAssertEqual(harness.replies.last?.ok, false)
    }

    func testHeartEveryTwoSecondsAndSilenceSendsOff() {
        let harness = Harness(windows: [(windowA, 42)])
        harness.auto = true
        harness.handle(request())
        XCTAssertEqual(harness.sent.count, 1)
        harness.clock += 1
        harness.tick()
        XCTAssertEqual(harness.sent.count, 1, "запрос был секунду назад — сердце молчит")
        harness.clock += 1
        harness.tick()
        XCTAssertEqual(harness.sent.count, 2, "2 с без запроса — сердце повторяет место")
        XCTAssertEqual(harness.sent.last, harness.sent.first)
        // Страница шлёт дальше — тишины нет.
        harness.clock += 2
        harness.handle(request(vis: false))
        XCTAssertEqual(harness.sent.last?.vis, false, "пауза — vis=0, не on=0")
        harness.clock += 2
        harness.tick()
        XCTAssertEqual(harness.sent.count, 4)
        XCTAssertEqual(harness.sent.last?.vis, false, "сердце повторяет паузу")
        // На паузе страница скрыта — её таймеры редки: тишина владельца док не снимает (ошибка 4).
        for _ in 0..<10 { harness.clock += 2; harness.tick() }
        XCTAssertFalse(harness.sent.contains(MaterialsDock.Command.off), "20 с тишины на паузе — не on=0")
        XCTAssertEqual(harness.sent.last?.vis, false)
        // Видимый владелец: тишина 8 с — on=0, 7,9 с — ещё нет.
        harness.handle(request())
        let shown = harness.sent.count
        for _ in 0..<3 { harness.clock += 2; harness.tick() }
        harness.clock += 1.9
        harness.tick()
        XCTAssertFalse(harness.sent.dropFirst(shown).contains(MaterialsDock.Command.off), "7,9 с — ещё сердце")
        harness.clock += 0.1
        harness.tick()
        XCTAssertEqual(harness.sent.last, MaterialsDock.Command.off, "8 с тишины видимого владельца — on=0")
        let count = harness.sent.count
        harness.clock += 2
        harness.tick()
        XCTAssertEqual(harness.sent.count, count, "дока нет — сердца нет")
    }

    func testOwnerIsLastWindowWithVisibleOn() {
        let harness = Harness(windows: [(windowA, 1), (windowB, 2)])
        harness.auto = true
        harness.handle(request(chat: "local_a"))
        XCTAssertEqual(harness.replies.last?.mine, true)
        harness.handle(request(window: windowB, chat: "local_b"))
        XCTAssertEqual(harness.replies.last?.mine, true, "второе окно нажало — док у него")
        XCTAssertEqual(harness.sent.last?.spot?.window, 2)
        harness.handle(request(chat: "local_a"))
        XCTAssertEqual(harness.replies.last?.mine, false, "повтор сердца первого окна док не отнимает")
        harness.handle(request(vis: false, chat: "local_a"))
        XCTAssertEqual(harness.replies.last?.mine, false, "пауза чужого окна не прячет док владельца")
        XCTAssertEqual(harness.sent.count, 2)
        harness.handle(request(x: 10, chat: "local_a"))
        XCTAssertEqual(harness.replies.last?.mine, true, "первое окно тянет рейку — док снова у него")
        XCTAssertEqual(harness.sent.last?.spot?.window, 1)
        harness.handle(request(window: windowB, chat: "local_b"))
        XCTAssertEqual(harness.replies.last?.mine, false)
        // Владелец на паузе — видимое окно забирает док и повтором.
        harness.handle(request(vis: false, x: 10, chat: "local_a"))
        XCTAssertEqual(harness.sent.last?.vis, false)
        harness.handle(request(window: windowB, chat: "local_b"))
        XCTAssertEqual(harness.replies.last?.mine, true)
        XCTAssertEqual(harness.sent.last?.spot?.window, 2)
        // on=0 чужого окна док не снимает; владельца — снимает.
        let before = harness.sent.count
        harness.handle(off(windowA, chat: "local_a"))
        XCTAssertEqual(harness.replies.last?.mine, false)
        XCTAssertEqual(harness.sent.count, before)
        harness.handle(off(windowB, chat: "local_b"))
        XCTAssertEqual(harness.sent.last, MaterialsDock.Command.off)
        XCTAssertEqual(harness.replies.last, MaterialsDock.Answer(ok: true, viewer: .up, docked: false, mine: true))
        // Дока нет — on=0 любого окна доходит до галереи.
        harness.handle(off(nil))
        XCTAssertEqual(harness.sent.count, before + 2)
    }

    /// Проверяющий WF277, ошибка 2: владелец — по окну, не по `chat` (у чатов без id `nil == nil`).
    func testOffOwnerByWindowNotByChat() {
        let harness = Harness(windows: [(windowA, 1), (windowB, 2)])
        harness.auto = true
        harness.handle(request(chat: "evil"))
        XCTAssertNil(request(chat: "evil").chat, "мусорный чат — nil, как у чата без id")
        XCTAssertEqual(harness.sent.last?.spot?.window, 1, "док у окна A, чат без id")
        let before = harness.sent.count
        harness.handle(off(windowB))
        XCTAssertEqual(harness.replies.last?.mine, false, "окно B, тоже без чата, — не владелец")
        XCTAssertEqual(harness.sent.count, before, "чужой док не снят")
        harness.handle(off(nil))
        XCTAssertEqual(harness.sent.count, before, "без рамки — не владелец")
        // Окно владельца не нашлось по рамке (сдвинулось) — по рамке, с которой оно приходило последним.
        harness.handle(off(windowA.offsetBy(dx: 300, dy: 0)))
        XCTAssertEqual(harness.sent.count, before, "чужая рамка")
        harness.handle(off(windowA))
        XCTAssertEqual(harness.sent.last, MaterialsDock.Command.off, "владелец закрыл — снят")
        // Не владелец закрыл — его место забыто: следующее нажатие забирает док, а не ждёт его тишины.
        harness.handle(request(chat: "evil"))
        harness.handle(request(window: windowB, chat: "evil"))
        XCTAssertEqual(harness.sent.last?.spot?.window, 2)
        harness.handle(off(windowA))
        harness.handle(request(chat: "evil"))
        XCTAssertEqual(harness.replies.last?.mine, true, "снова нажал — док у A")
        XCTAssertEqual(harness.sent.last?.spot?.window, 1)
    }

    /// Ошибка 3: `probe=1` — жив ли PimpViewer: ответ `{ok, viewer}`, в PimpViewer ничего не уходит, док не снят.
    func testProbeAnswersWithoutTouchingViewer() {
        let harness = Harness(windows: [(windowA, 1)])
        harness.auto = true
        harness.handle(request())
        harness.dock.probe = { $0(.up) }
        let before = harness.sent.count
        harness.handle(MaterialsDock.parse(head("/dock?probe=1"))!)
        XCTAssertEqual(harness.sent.count, before, "PimpViewer не спрашиваем")
        XCTAssertEqual(String(decoding: harness.replies.last!.json, as: UTF8.self), #"{"ok":true,"viewer":"up","apart":false}"#)
        harness.dock.probe = { $0(.none) }
        harness.handle(MaterialsDock.parse(head("/dock?probe=1"))!)
        XCTAssertEqual(String(decoding: harness.replies.last!.json, as: UTF8.self), #"{"ok":true,"viewer":"none","apart":false}"#)
        harness.clock += 2
        harness.tick()
        XCTAssertEqual(harness.sent.last?.spot?.window, 1, "док стоит, сердце идёт")
    }

    func testOpenFromChatTakesDockAndKeepsHeart() {
        let harness = Harness(windows: [(windowA, 1), (windowB, 2)])
        harness.auto = true
        harness.handle(request(window: windowB, chat: "local_b"))
        let opened = expectation(description: "место для /accept")
        var spot: MaterialsDock.Spot?
        harness.dock.open(MaterialsDock.Place(place: CGRect(x: 0, y: 40, width: 420, height: 700), window: windowA)) {
            spot = $0
            opened.fulfill()
        }
        wait(for: [opened], timeout: 2)
        XCTAssertEqual(spot, MaterialsDock.Spot(window: 1, place: CGRect(x: 0, y: 40, width: 420, height: 700)))
        harness.handle(request(window: windowB, chat: "local_b"))
        XCTAssertEqual(harness.replies.last?.mine, false, "клик по файлу — док у окна клика")
        harness.clock += 2
        harness.tick()
        XCTAssertEqual(harness.sent.last?.spot?.window, 1, "сердце держит док окна клика")
        let missing = expectation(description: "окна нет")
        harness.dock.open(MaterialsDock.Place(place: .zero, window: CGRect(x: 1, y: 1, width: 5, height: 5))) {
            XCTAssertNil($0)
            missing.fulfill()
        }
        wait(for: [missing], timeout: 2)
    }

    // MARK: - виды файлов — только для дока

    func testNewKindsOnlyForClick() {
        for ext in ["md", "markdown", "txt", "mp4", "MOV", "m4v", "webm", "mp3", "m4a", "aac", "wav", "zip", "ZIP"] {
            XCTAssertFalse(HtmlChromeOpener.acceptsPath("/a/b.\(ext)"), ext)
            XCTAssertTrue(HtmlChromeOpener.acceptsPath("/a/b.\(ext)", dock: true), ext)
        }
        XCTAssertFalse(HtmlChromeOpener.acceptsPath("/a/b.sh", dock: true))
        XCTAssertFalse(HtmlChromeOpener.acceptsPath("a/b.md", dock: true))
        XCTAssertTrue(HtmlChromeOpener.acceptsPath("/a/b.html"))
        let frame = "&x=0&y=40&w=420&h=700&wx=383&wy=29&ww=896&wh=742"
        let md = "/open-html?mode=click&path=%2FUsers%2Fe%2F%D0%BE%D1%82%D1%87%D1%91%D1%82%20a.md&chat=local_a"
        // Клик без места (ошибка 1): страница забрала md у Claude, а панели нет — Пимп не молчит, берёт (галерея или
        // программа по умолчанию); `browser` и `view` — прежний фильтр.
        XCTAssertEqual(HtmlChromeOpener.parse(head(md))?.path, "/Users/e/отчёт a.md")
        XCTAssertNil(HtmlChromeOpener.parse(head(md))?.dock)
        XCTAssertNil(HtmlChromeOpener.parse(head(md + frame))?.dock, "рамка без dock=1 — не док")
        XCTAssertNil(HtmlChromeOpener.parse(head(md.replacingOccurrences(of: "mode=click", with: "mode=browser"))))
        let docked = HtmlChromeOpener.parse(head(md + "&dock=1" + frame))
        XCTAssertEqual(docked?.path, "/Users/e/отчёт a.md", "кириллица и пробел — декодированы")
        XCTAssertEqual(docked?.dock, MaterialsDock.Place(place: CGRect(x: 0, y: 40, width: 420, height: 700), window: windowA))
        let badPlace = HtmlChromeOpener.parse(head(md + "&dock=1" + frame.replacingOccurrences(of: "w=420", with: "w=0")))
        XCTAssertEqual(badPlace?.mode, .click, "негодное место — прежний клик, не тишина")
        XCTAssertNil(badPlace?.dock)
        XCTAssertNil(HtmlChromeOpener.parse(head(md.replacingOccurrences(of: "mode=click", with: "mode=view") + "&dock=1" + frame)),
                     "док — только у клика")
        // Страница с негодной рамкой — прежний клик без дока; `view` с dock=1 — прежний `view`.
        let html = "/open-html?mode=click&path=%2Fa%2Fb.html&chat=local_a"
        XCTAssertNil(HtmlChromeOpener.parse(head(html + "&dock=1&x=1"))?.dock)
        XCTAssertNotNil(HtmlChromeOpener.parse(head(html + "&dock=1&x=1")))
        let view = HtmlChromeOpener.parse(head(html.replacingOccurrences(of: "mode=click", with: "mode=view") + "&dock=1" + frame))
        XCTAssertEqual(view?.mode, .view)
        XCTAssertNil(view?.dock)
        // «в браузер» из галереи — прежний фильтр: текст и ролики туда не идут.
        let channel = "GET /viewer-open-browser?path=%2Fa%2Fb.md HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n"
            + "X-Pimp-Viewer-Token: \(String(repeating: "a1", count: 16))\r\n\r\n"
        XCTAssertEqual(HtmlChromeOpener.checkChannel(channel, token: String(repeating: "a1", count: 16)), .reject(400))
    }

    /// Ошибка 1: текст и ролик, которые док (или галерея) не взял, — программой macOS по умолчанию; не браузер, не
    /// «Просмотр», не `view` — и не тишина.
    func testDockKindsNotTakenOpenWithDefaultApp() throws {
        let opener = HtmlChromeOpener()
        var browser: [String] = []
        var system: [String] = []
        var views = 0
        opener.browserSeam = { browser.append($0.path) }
        opener.defaultSeam = { system.append($0.path) }
        opener.onView = { _ in views += 1 }
        opener.isKnownChat = { _ in true }
        let place = MaterialsDock.Place(place: CGRect(x: 0, y: 40, width: 420, height: 700), window: windowA)
        let frame = CGRect(x: 383, y: 29, width: 896, height: 742)
        var answers: [String] = []
        opener.toDock = { _, done in done(false, false) }
        for path in ["/p/a.md", "/p/a.mp4"] {
            opener.routeDock(HtmlChromeOpener.Request(path: path, mode: .click, chat: "local_a", frame: frame, dock: place)) {
                answers.append("\($0)/\($1)")
            }
        }
        XCTAssertEqual(browser, [])
        XCTAssertEqual(views, 0)
        XCTAssertEqual(answers, ["false/false", "false/false"])
        XCTAssertEqual(system, ["/p/a.md", "/p/a.mp4"])
        // Без `toDock` (нет контроллера) — прежний клик в галерею; не взяла — программа по умолчанию.
        opener.toDock = nil
        opener.toViewer = { _, done in done(false) }
        opener.routeDock(HtmlChromeOpener.Request(path: "/p/a.webm", mode: .click, chat: "local_a", dock: place)) { _, _ in }
        XCTAssertEqual(browser, [])
        XCTAssertEqual(system.last, "/p/a.webm")
        // Клик без места (страница забрала md, а места не нашлось) — так же: галерея, потом программа по умолчанию.
        opener.route(HtmlChromeOpener.Request(path: "/p/b.txt", mode: .click, chat: "local_a"))
        XCTAssertEqual(system.last, "/p/b.txt")
        XCTAssertEqual(browser, [])
        // Страница, которую док не взял, — прежний путь: окно просмотра поверх окна чата (ошибка 6: рамка и фон — в том
        // же запросе `dock=1`).
        opener.toDock = { _, done in done(false, false) }
        let docked = try XCTUnwrap(HtmlChromeOpener.parse(head("/open-html?mode=click&dock=1&path=%2Fp%2Fa.html&chat=local_a"
            + "&x=0&y=40&w=420&h=700&wx=383&wy=29&ww=896&wh=742&frame=383,29,896,742&bg=1c1917")))
        XCTAssertEqual(docked.frame, frame)
        XCTAssertEqual(docked.bg, "1c1917")
        opener.routeDock(docked) { _, _ in }
        XCTAssertEqual(views, 1)
        XCTAssertEqual(browser, [])
        XCTAssertEqual(system.count, 4, "страница — не программой по умолчанию")
    }

    // MARK: - К-DOCK-2 против своего слушателя

    private func client(_ fake: ViewerChannelWF104Tests.FakeViewer, installed: Bool = true) throws -> ViewerClient {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let token = folder.appendingPathComponent("channel.token")
        try Data((String(repeating: "a1", count: 16) + "\n").utf8).write(to: token)
        let client = ViewerClient(port: fake.port, tokenURL: token, launches: false)
        client.owners = { _, _ in [.init(pid: getpid(), path: "/Applications/PimpViewer.app/Contents/MacOS/PimpViewer")] }
        client.installed = { installed }
        client.running = { true }
        client.launch = { XCTFail("запуск не ждали") }
        client.raise = { XCTFail("вывод вперёд не ждали"); return true }
        client.windowShown = { XCTFail("окна галереи у дока не ждём"); return false }
        return client
    }

    private func dock(_ client: ViewerClient, _ command: MaterialsDock.Command) -> MaterialsDock.Reply? {
        let done = expectation(description: "dock")
        var result: MaterialsDock.Reply?
        client.dock(command) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    func testViewerClientDockTargetsAndReplies() throws {
        typealias Fake = ViewerChannelWF104Tests.FakeViewer
        let fake = try Fake()
        fake.answer = { head, _ in
            head.hasPrefix("GET /dock?on=1") ? Fake.json(#"{"ok":true,"docked":true}"#) : Fake.json(#"{"ok":true,"docked":false}"#)
        }
        let client = try client(fake)
        let spot = MaterialsDock.Spot(window: 4242, place: CGRect(x: 0, y: 40, width: 420, height: 700))
        XCTAssertEqual(dock(client, MaterialsDock.Command(vis: true, spot: spot)), MaterialsDock.Reply(viewer: .up, docked: true))
        XCTAssertEqual(dock(client, .off), MaterialsDock.Reply(viewer: .up, docked: false))
        XCTAssertTrue(fake.requests[0].hasPrefix("GET /dock?on=1&vis=1&win=4242&x=0&y=40&w=420&h=700 HTTP/1.1\r\n"),
                      fake.requests[0])
        XCTAssertTrue(fake.requests[0].lowercased().contains("x-pimp-viewer-token: \(String(repeating: "a1", count: 16))"))
        XCTAssertTrue(fake.requests[1].hasPrefix("GET /dock?on=0 HTTP/1.1\r\n"))
        XCTAssertEqual(ViewerClient.dockTarget(MaterialsDock.Command(vis: false, spot: spot)),
                       "/dock?on=1&vis=0&win=4242&x=0&y=40&w=420&h=700")
        // Старая галерея (дока не знает) — `down`, кнопки «PMP» нет.
        fake.answer = { _, _ in Fake.json(#"{"ok":false,"error":"not-found"}"#, status: "404 Not Found") }
        XCTAssertEqual(dock(client, .off), MaterialsDock.Reply(viewer: .down, docked: false))
        // Молчит: установлена — `down`, нет — `none`; без запуска.
        fake.answer = { _, _ in nil }
        XCTAssertEqual(dock(client, .off)?.viewer, .down)
        XCTAssertEqual(dock(try self.client(fake, installed: false), .off)?.viewer, MaterialsDock.Viewer.none)
    }

    /// Ошибка 5: `/dock` к PimpViewer ждёт до 1,5 с — занятая на 0,8 с главная галереи не даёт ложного `down`.
    func testViewerClientDockWaitsOneAndHalfSeconds() throws {
        typealias Fake = ViewerChannelWF104Tests.FakeViewer
        let fake = try Fake()
        fake.answer = { _, _ in
            Thread.sleep(forTimeInterval: 0.8)
            return Fake.json(#"{"ok":true,"docked":true}"#)
        }
        let client = try client(fake)
        let spot = MaterialsDock.Spot(window: 4242, place: CGRect(x: 0, y: 40, width: 420, height: 700))
        XCTAssertEqual(dock(client, MaterialsDock.Command(vis: true, spot: spot)), MaterialsDock.Reply(viewer: .up, docked: true))
        XCTAssertEqual(ViewerClient.dockTimeout, 1.5)
        XCTAssertLessThan(ViewerClient.dockTimeout, HtmlChromeOpener.dockReplyWait, "странице ответ — раньше, чем она бросит ждать")
    }

    /// Ошибка 3: «жив ли PimpViewer» для кнопки «PMP» — без запроса к галерее (on=0 снимал док другого окна).
    func testDockProbeSendsNothingToViewer() throws {
        typealias Fake = ViewerChannelWF104Tests.FakeViewer
        let fake = try Fake()
        fake.answer = { _, _ in XCTFail("в галерею ничего не шлём"); return nil }
        func probe(_ client: ViewerClient) -> MaterialsDock.Viewer? {
            let done = expectation(description: "probe")
            var result: MaterialsDock.Viewer?
            client.dockProbe { result = $0; done.fulfill() }
            wait(for: [done], timeout: 5)
            return result
        }
        let client = try client(fake)
        client.runningVersion = { "1.10.35" }
        XCTAssertEqual(probe(client), .up)
        client.runningVersion = { "1.11.0" }
        XCTAssertEqual(probe(client), .up)
        client.runningVersion = { nil }
        XCTAssertEqual(probe(client), .up, "версия не прочлась — скажет нажатие")
        client.runningVersion = { "1.10.34" }
        XCTAssertEqual(probe(client), .down, "старая галерея дока не знает — кнопки нет, как с on=0")
        client.running = { false }
        XCTAssertEqual(probe(client), .down)
        XCTAssertEqual(probe(try self.client(fake, installed: false)), MaterialsDock.Viewer.none)
        XCTAssertEqual(fake.requests, [])
    }

    func testAcceptIntoDockCarriesSpotAndDoesNotWaitForGalleryWindow() throws {
        typealias Fake = ViewerChannelWF104Tests.FakeViewer
        let fake = try Fake()
        fake.answer = { head, _ in
            Fake.json(head.contains("path=%2Fp%2Fshut.mp4") ? #"{"taken":true,"focus":false,"opened":false}"#
                      : #"{"taken":true,"focus":false,"opened":true}"#)
        }
        let client = try client(fake)
        let spot = MaterialsDock.Spot(window: 77, place: CGRect(x: 12, y: 40, width: 420, height: 690))
        func accept(_ path: String) -> String {
            let done = expectation(description: "accept")
            var result = ""
            client.accept(path: path, chat: "local_a", dock: spot) { result = "\($0)/\($1)"; done.fulfill() }
            wait(for: [done], timeout: 5)
            return result
        }
        XCTAssertEqual(accept("/p/от чёт.md"), "true/true")
        XCTAssertEqual(accept("/p/shut.mp4"), "true/false")
        XCTAssertTrue(fake.requests[0].hasPrefix("GET /accept?mode=click&path=%2Fp%2F%D0%BE%D1%82%20%D1%87%D1%91%D1%82.md"
            + "&chat=local_a&dock=1&win=77&x=12&y=40&w=420&h=690 HTTP/1.1\r\n"), fake.requests[0])
        XCTAssertEqual(client.status, "up/2/0+1", "взят без файла — в счёт «без окна» (#10831)")
    }

    // MARK: - ответ странице по настоящему сокету

    private final class Server {
        let opener = HtmlChromeOpener()
        let listener: NWListener
        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            opener.channelToken = { nil }
            listener.newConnectionHandler = { [opener] in opener.serve($0) }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: DispatchQueue(label: "test.dock-server"))
            _ = ready.wait(timeout: .now() + 3)
        }
        deinit { listener.cancel() }

        /// Запрос страницы целиком → ответ целиком (сервер закрывает соединение сам).
        func exchange(_ target: String, origin: String? = "https://claude.ai") throws -> String {
            let port = try XCTUnwrap(listener.port)
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            let ended = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var data = Data()
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { bytes, _, done, error in
                    lock.lock()
                    if let bytes = bytes { data.append(bytes) }
                    lock.unlock()
                    if done || error != nil { ended.signal() } else { receive() }
                }
            }
            let head = "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n" } ?? "") + "\r\n"
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
                receive()
            }
            connection.start(queue: DispatchQueue(label: "test.dock-client"))
            defer { connection.cancel() }
            XCTAssertEqual(ended.wait(timeout: .now() + 5), .success, target)
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    func testPageGetsDockAnswerWhenViewerAnswered() throws {
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/dock?on=0") + "Origin: https://claude.ai\r\n\r\n", token: nil),
                       .browser(preflight: false), "/dock — в белом списке страницы")
        let server = try Server()
        var asked: [MaterialsDock.Request] = []
        let lock = NSLock()
        server.opener.onDock = { request, reply in
            lock.lock(); asked.append(request); lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                reply(MaterialsDock.Answer(ok: true, viewer: .up, docked: true, mine: false))
            }
        }
        let started = Date()
        let answer = try server.exchange(dockQuery())
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.15, "не 204 сразу — ждём PimpViewer")
        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n"), answer)
        XCTAssertTrue(answer.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"))
        XCTAssertTrue(answer.hasSuffix(#"{"ok":true,"viewer":"up","docked":true,"owner":"other","apart":false}"#), answer)
        let bad = try server.exchange(dockQuery().replacingOccurrences(of: "w=420", with: "w=0"))
        XCTAssertTrue(bad.hasPrefix("HTTP/1.1 400 "), bad)
        XCTAssertTrue(bad.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"), "страница видит отказ")
        XCTAssertTrue(try server.exchange("/dock?on=0", origin: "https://evil.test").hasPrefix("HTTP/1.1 403 "))
        lock.lock()
        XCTAssertEqual(asked.count, 1, "отказ и чужой Origin до дока не доходят")
        lock.unlock()
        // Галерея молчит — страница всё равно слышит ответ.
        server.opener.onDock = { _, _ in }
        XCTAssertTrue(try server.exchange("/dock?on=0").hasSuffix(#"{"ok":false,"viewer":"down","docked":false,"owner":"this","apart":false}"#))
    }

    func testOpenHtmlDockAnswersTakenOpened() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dock-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("заметка 1.md")
        try Data("# hi".utf8).write(to: file)
        let server = try Server()
        var docked: [HtmlChromeOpener.Request] = []
        server.opener.toDock = { request, done in
            docked.append(request)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { done(true, true) }
        }
        server.opener.browserSeam = { _ in XCTFail("браузер не ждали") }
        let path = ViewerClient.encode(file.path)
        let target = "/open-html?mode=click&dock=1&path=\(path)&chat=local_a&x=0&y=40&w=420&h=700&wx=383&wy=29&ww=896&wh=742"
        let answer = try server.exchange(target)
        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n"), answer)
        XCTAssertTrue(answer.hasSuffix(#"{"taken":true,"opened":true}"#), answer)
        XCTAssertEqual(docked.first?.path, file.path)
        // Файла нет — сразу «не взят», до дока не доходит.
        let missing = try server.exchange(target.replacingOccurrences(of: "md&", with: "markdown&"))
        XCTAssertTrue(missing.hasSuffix(#"{"taken":false,"opened":false}"#), missing)
        XCTAssertEqual(docked.count, 1)
    }
}
