import XCTest
@testable import ClaudeAX

/// След потерянного нажатия по карточке файла (WF292, #10831): после окна галереи клиент сверяет по `/opened`, что
/// раскрыт именно этот файл, а не «окно галереи есть»; док, взявший клик без файла, не теряет его; каждое нажатие —
/// строкой в `viewer-clicks.jsonl`. Галерея — свой слушатель на порту 0 (`FakeViewer`), склад Элвиса не трогаем.
final class ViewerClickWF292Tests: XCTestCase {
    typealias Fake = ViewerChannelWF104Tests.FakeViewer
    private var tmp: URL!
    private let lock = NSLock()
    private var lines: [[String: Any]] = []

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("viewer-click-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try Data((String(repeating: "a1", count: 16) + "\n").utf8).write(to: tmp.appendingPathComponent("channel.token"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func client(_ fake: Fake, traced: XCTestExpectation? = nil) -> ViewerClient {
        let client = ViewerClient(port: fake.port, tokenURL: tmp.appendingPathComponent("channel.token"), launches: false)
        client.owners = { _, _ in [.init(pid: getpid(), path: "/Applications/PimpViewer.app/Contents/MacOS/PimpViewer")] }
        client.installed = { true }
        client.running = { true }
        client.launch = { XCTFail("запуск не ждали") }
        client.raise = { true }
        client.windowShown = { true }
        client.windowWait = 0.3
        client.openedWait = 0.5
        client.trace = { [self] line in
            lock.lock()
            lines.append(line)
            lock.unlock()
            traced?.fulfill()
        }
        return client
    }

    private var traced: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return lines }

    /// `/accept` — взяла (без `opened`, как до #10531), `/opened` — по сценарию.
    private func gallery(opened: String?) -> (String, Int) -> String? {
        { head, _ in
            if head.hasPrefix("GET /opened?") { return opened.map { Fake.json($0) } ?? Fake.json("{}", status: "404 Not Found") }
            return Fake.json(#"{"focus":false,"taken":true}"#)
        }
    }

    /// Нажатие; след пишется после исхода — ждём и его строку.
    private func click(_ client: ViewerClient, path: String = "/p/a b.html", chat: String? = "local_a") -> Bool? {
        let before = traced.count
        let done = expectation(description: "accept")
        var result: Bool?
        client.accept(path: path, mode: .click, chat: chat) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        let deadline = Date().addingTimeInterval(3)
        while traced.count == before, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return result
    }

    func testOpenedFileIsTakenAndTraced() throws {
        let fake = try Fake()
        fake.answer = gallery(opened: #"{"ok":true,"known":true,"open":true,"place":"window","parked":false,"loaded":true}"#)
        let client = client(fake)
        XCTAssertEqual(click(client), true)
        XCTAssertEqual(client.status, "up/1/0")
        XCTAssertTrue(fake.requests[1].hasPrefix("GET /opened?path=%2Fp%2Fa%20b.html HTTP/1.1\r\n"), fake.requests[1])
        let line = try XCTUnwrap(traced.last)
        XCTAssertEqual(line["via"] as? String, "gallery")
        XCTAssertEqual(line["path"] as? String, "/p/a b.html")
        XCTAssertEqual(line["chat"] as? String, "local_a")
        XCTAssertEqual(line["taken"] as? Bool, true)
        XCTAssertTrue(line["opened"] is NSNull, "галерея без поля opened — null")
        XCTAssertEqual(line["window"] as? Bool, true)
        XCTAssertEqual(line["file"] as? String, "open")
        XCTAssertEqual(line["fallback"] as? Bool, false)
        XCTAssertNotNil(line["ms"] as? Int)
        XCTAssertNotNil((line["at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
    }

    /// Окно галереи вышло, а файл в нём так и не раскрыт загруженной страницей — нажатие не теряется: сиденье
    /// показывает файл просмотром в окне чата, браузер не открывается.
    func testWindowWithoutTheFileFallsBackToChatView() throws {
        let fake = try Fake()
        fake.answer = gallery(opened: #"{"ok":true,"known":true,"open":false,"place":"window","parked":false,"loaded":true}"#)
        let client = client(fake)
        let started = Date()
        XCTAssertEqual(click(client), false)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.5, "ждали до срока")
        XCTAssertGreaterThan(fake.requests.filter { $0.hasPrefix("GET /opened?") }.count, 1, "спрашивали не раз")
        XCTAssertEqual(client.status, "up/1/0+1")
        XCTAssertEqual(traced.last?["file"] as? String, "missed")
        XCTAssertEqual(traced.last?["fallback"] as? Bool, true)

        let opener = HtmlChromeOpener()
        let shown = expectation(description: "просмотр в окне чата")
        var browser = 0
        opener.onView = { XCTAssertEqual($0.mode, .view); shown.fulfill() }
        opener.isKnownChat = { _ in true }
        opener.browserSeam = { _ in browser += 1 }
        opener.toViewer = { request, done in client.accept(path: request.path, mode: request.mode, chat: request.chat, done: done) }
        opener.route(HtmlChromeOpener.Request(path: "/p/2.html", mode: .click, chat: "local_a",
                                              frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        wait(for: [shown], timeout: 5)
        XCTAssertEqual(browser, 0)
    }

    /// Страница галереи грузится или выгружена, старая галерея без `/opened` (404), ответ без `open`, файл не на
    /// складе — как было: взяла.
    func testUnsureAnswersKeepTheGallery() throws {
        let fake = try Fake()
        let client = client(fake)
        let cases: [(String?, String)] = [
            (#"{"ok":true,"known":true,"open":false,"place":"window","parked":false,"loaded":false}"#, "loading"),
            (#"{"ok":true,"known":true,"open":false,"place":"hidden","parked":true,"loaded":true}"#, "loading"),
            (nil, "unknown"),
            (#"{"ok":false}"#, "unknown"),
            (#"{"ok":true,"known":false,"open":false}"#, "unknown"),
        ]
        for (opened, file) in cases {
            fake.answer = gallery(opened: opened)
            XCTAssertEqual(click(client), true, file)
            XCTAssertEqual(traced.last?["file"] as? String, file, opened ?? "404")
            XCTAssertEqual(traced.last?["fallback"] as? Bool, false)
        }
        XCTAssertTrue(client.isUp, "404 старой галереи на /opened не гасит «Галерею»")
        XCTAssertEqual(client.status, "up/5/0")
    }

    /// Не взяла, окна нет, `opened:false`, клик без чата — след есть, `/opened` не спрашиваем; тихий `view` — без следа.
    func testEveryClickIsTracedWithoutAsking() throws {
        let fake = try Fake()
        let client = client(fake)
        fake.answer = { _, _ in Fake.json(#"{"focus":false,"taken":false}"#) }
        XCTAssertEqual(click(client), false)
        XCTAssertEqual(traced.last?["taken"] as? Bool, false)
        XCTAssertEqual(traced.last?["fallback"] as? Bool, true)
        XCTAssertTrue(traced.last?["window"] is NSNull)
        fake.answer = { _, _ in Fake.json(#"{"focus":false,"opened":false,"taken":true}"#) }
        XCTAssertEqual(click(client), false)
        XCTAssertEqual(traced.last?["opened"] as? Bool, false)
        fake.answer = gallery(opened: nil)
        client.windowShown = { false }
        XCTAssertEqual(click(client), false)
        XCTAssertEqual(traced.last?["window"] as? Bool, false)
        XCTAssertEqual(click(client, chat: nil), true)
        XCTAssertTrue(traced.last?["chat"] is NSNull)
        XCTAssertEqual(traced.last?["file"] as? String, "unknown")
        XCTAssertEqual(fake.requests.filter { $0.hasPrefix("GET /opened?") }, [])
        XCTAssertEqual(traced.count, 4)

        let done = expectation(description: "view")
        client.accept(path: "/p/a.html", mode: .view, chat: "local_a") { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(traced.count, 4, "view — не нажатие человека")
    }

    /// Док взял клик без файла (`opened:false`) — сиденье открывает прежним путём, а не молчит; взял с файлом — исход
    /// сразу, `/opened` — только для следа.
    func testDockWithoutFileFallsBackAndDockTraceAsksOpened() throws {
        let fake = try Fake()
        fake.answer = { head, _ in
            if head.hasPrefix("GET /opened?") { return Fake.json(#"{"ok":true,"known":true,"open":true,"place":"dock"}"#) }
            return Fake.json(head.contains("path=%2Fp%2Fshut.html") ? #"{"taken":true,"focus":false,"opened":false}"#
                             : #"{"taken":true,"focus":false,"opened":true}"#)
        }
        let traced = expectation(description: "след дока")
        traced.expectedFulfillmentCount = 2
        let client = client(fake, traced: traced)
        client.windowShown = { XCTFail("окна галереи у дока не ждём"); return false }
        let opener = HtmlChromeOpener()
        var views: [String] = []
        var browser = 0
        opener.onView = { views.append($0.path) }
        opener.isKnownChat = { _ in true }
        opener.browserSeam = { _ in browser += 1 }
        let spot = MaterialsDock.Spot(window: 77, place: CGRect(x: 12, y: 40, width: 420, height: 690))
        opener.toDock = { request, done in client.accept(path: request.path, chat: request.chat, dock: spot, done: done) }
        let place = MaterialsDock.Place(place: CGRect(x: 0, y: 40, width: 420, height: 700),
                                        window: CGRect(x: 383, y: 29, width: 896, height: 742))
        let frame = CGRect(x: 383, y: 29, width: 896, height: 742)
        var answers: [String] = []
        for path in ["/p/shut.html", "/p/ok.html"] {
            let answered = expectation(description: path)
            opener.routeDock(HtmlChromeOpener.Request(path: path, mode: .click, chat: "local_a", frame: frame, dock: place)) {
                answers.append("\($0)/\($1)")
                answered.fulfill()
            }
            wait(for: [answered], timeout: 5)
        }
        wait(for: [traced], timeout: 5)
        XCTAssertEqual(answers, ["true/false", "true/true"])
        XCTAssertEqual(views, ["/p/shut.html"], "взятый без файла — просмотром в окне чата")
        XCTAssertEqual(browser, 0)
        XCTAssertEqual(client.status, "up/2/0+1")
        let lines = self.traced
        XCTAssertEqual(lines.map { $0["via"] as? String }, ["dock", "dock"])
        XCTAssertEqual(lines.map { $0["file"] as? String }, ["unknown", "open"])
        XCTAssertEqual(lines.map { $0["fallback"] as? Bool }, [true, false])
        XCTAssertEqual(lines.map { $0["opened"] as? Bool }, [false, true])
        XCTAssertEqual(fake.requests.filter { $0.hasPrefix("GET /opened?") }.count, 1)
    }

    /// Файл следа — строка JSON на нажатие, права 0600, хвост в 300 строк.
    func testTraceFileKeepsTailAndPermissions() throws {
        let url = tmp.appendingPathComponent(ViewerClient.traceFile)
        for n in 1...305 { ViewerClient.appendTrace(["n": n, "chat": NSNull(), "path": "/p/a.html"], to: url) }
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = text.split(separator: "\n")
        XCTAssertEqual(rows.count, ViewerClient.traceLines)
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(rows.first, #"{"chat":null,"n":6,"path":"/p/a.html"}"#)
        XCTAssertEqual(rows.last, #"{"chat":null,"n":305,"path":"/p/a.html"}"#)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }
}
