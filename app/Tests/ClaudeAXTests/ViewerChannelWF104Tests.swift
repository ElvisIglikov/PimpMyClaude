import Network
import XCTest
@testable import ClaudeAX

/// Канал Пимп ↔ PimpViewer.app (план WF104, батч Б1; контракт К-V8): ручки галереи на порту 47615 — чистыми
/// функциями, `ViewerClient` — против своего слушателя на порту 0. Живой порт 47615 и склад Элвиса не трогаем.
final class ViewerChannelWF104Tests: XCTestCase {
    private let token = String(repeating: "a1", count: 16)
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("viewer-channel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - К-V1 страницы — как было

    func testPortParseKeepsOldRequestsAndAddsChat() {
        let old = HtmlChromeOpener.parse("GET /open-html?mode=auto&path=%2FUsers%2Fe%2Fa.html HTTP/1.1\r\nHost: x\r\n")
        XCTAssertNil(old)
        XCTAssertNil(old?.chat)
        let withChat = HtmlChromeOpener.parse("GET /open-html?mode=click&path=%2Fa%2Fb.png&chat=local_abc-1 HTTP/1.1")
        XCTAssertEqual(withChat?.chat, "local_abc-1")
        XCTAssertNil(HtmlChromeOpener.parse("GET /open-html?path=%2Fa%2Fb.png&chat=local_%3Cx%3E HTTP/1.1")?.chat)
        XCTAssertEqual(HtmlChromeOpener.parseViewer("GET /viewer?chat=local_abc&on=1 HTTP/1.1"),
                       HtmlChromeOpener.ViewerRequest(chat: "local_abc", on: true))
        XCTAssertEqual(HtmlChromeOpener.parseViewer("GET /viewer?chat=local_abc&on=0 HTTP/1.1")?.on, false)
        XCTAssertNil(HtmlChromeOpener.parseViewer("GET /viewer?on=1 HTTP/1.1"))
        XCTAssertNil(HtmlChromeOpener.parseViewer("GET /viewer?chat=evil&on=1 HTTP/1.1"))
        XCTAssertNil(HtmlChromeOpener.parseViewer("GET /viewer?chat=local_abc&on=2 HTTP/1.1"))
        XCTAssertNil(HtmlChromeOpener.parseViewer("POST /viewer?chat=local_abc&on=1 HTTP/1.1"))
        XCTAssertNil(HtmlChromeOpener.parse("GET /viewer?chat=local_abc&on=1 HTTP/1.1"))
    }

    // MARK: - ручки галереи на 47615

    private func head(_ target: String, method: String = "GET", host: [String] = ["127.0.0.1:47615"],
                      token: [String]? = nil, end: String = "\r\n") -> String {
        var lines = ["\(method) \(target) HTTP/1.1"]
        lines += host.map { "Host: \($0)" }
        lines += (token ?? [self.token]).map { "X-Pimp-Viewer-Token: \($0)" }
        return lines.joined(separator: "\r\n") + "\r\n" + end
    }

    private func check(_ head: String, token: String? = nil) -> HtmlChromeOpener.ChannelVerdict {
        HtmlChromeOpener.checkChannel(head, token: token ?? self.token)
    }

    func testChannelRoutes() {
        XCTAssertEqual(check(head("/viewer-nudge?what=chat")), .nudge(chat: true, counts: false))
        XCTAssertEqual(check(head("/viewer-nudge?what=counts")), .nudge(chat: false, counts: true))
        XCTAssertEqual(check(head("/viewer-nudge")), .nudge(chat: true, counts: true))
        XCTAssertEqual(check(head("/viewer-nudge?what=x", host: ["LocalHost:47615"])), .nudge(chat: true, counts: true))
        XCTAssertEqual(check(head("/viewer-open-chat?chat=local_abc-1")), .openChat("local_abc-1"))
        XCTAssertEqual(check(head("/viewer-open-chat?chat=evil")), .openChat(nil))
        XCTAssertEqual(check(head("/viewer-open-chat")), .openChat(nil))
        XCTAssertEqual(check(head("/viewer-open-browser?path=%2FUsers%2Fe%2Fa%20b.html")), .openBrowser("/Users/e/a b.html"))
        XCTAssertEqual(check(head("/viewer-open-browser?path=%2Fa%2Fb.PNG")), .openBrowser("/a/b.PNG"))
    }

    func testChannelRejectsInOrder() {
        // Неполный заголовок — 400 раньше всего.
        XCTAssertEqual(check(head("/viewer-nudge", end: "")), .reject(400))
        XCTAssertEqual(check("GET /viewer-nudge\r\n\r\n"), .reject(400))
        // Чужой Host (DNS-rebinding), два Host, без Host — 403.
        XCTAssertEqual(check(head("/viewer-nudge", host: ["evil.example:47615"])), .reject(403))
        XCTAssertEqual(check(head("/viewer-nudge", host: ["127.0.0.1:47616"])), .reject(403))
        XCTAssertEqual(check(head("/viewer-nudge", host: ["127.0.0.1:47615", "127.0.0.1:47615"])), .reject(403))
        XCTAssertEqual(check(head("/viewer-nudge", host: [])), .reject(403))
        // Без токена, чужой, два, токена нет у Пимпа (файла нет) — 403.
        XCTAssertEqual(check(head("/viewer-nudge", token: [])), .reject(403))
        XCTAssertEqual(check(head("/viewer-nudge", token: [String(repeating: "b2", count: 16)])), .reject(403))
        XCTAssertEqual(check(head("/viewer-nudge", token: [token, token])), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkChannel(head("/viewer-nudge"), token: nil), .reject(403))
        // Токен раньше метода: чужой OPTIONS — тоже 403, свой OPTIONS — 403, прочее — 405.
        XCTAssertEqual(check(head("/viewer-nudge", method: "OPTIONS", token: [])), .reject(403))
        XCTAssertEqual(check(head("/viewer-nudge", method: "OPTIONS")), .reject(403))
        XCTAssertEqual(check(head("/viewer-nudge", method: "POST")), .reject(405))
        // Неизвестная ручка — 404; фильтр пути «в браузер» — 400.
        XCTAssertEqual(check(head("/viewer-foo")), .reject(404))
        for bad in ["etc%2Fpasswd.html", "%2Fetc%2Fpasswd", "%2Fa%2Fb.sh", "%2Fa%00.html", ""] {
            XCTAssertEqual(check(head("/viewer-open-browser?path=\(bad)")), .reject(400), bad)
        }
        XCTAssertEqual(check(head("/viewer-open-browser")), .reject(400))
    }

    func testChannelOnlyForViewerDashPaths() {
        XCTAssertTrue(HtmlChromeOpener.isChannel("GET /viewer-nudge HTTP/1.1\r\n"))
        XCTAssertFalse(HtmlChromeOpener.isChannel("GET /viewer?chat=local_a&on=1 HTTP/1.1\r\n"))
        XCTAssertFalse(HtmlChromeOpener.isChannel("GET /open-html?path=%2Fviewer-x.html HTTP/1.1\r\n"))
    }

    func testChannelResponses() {
        func text(_ status: Int, _ body: String? = nil) -> String {
            String(decoding: HtmlChromeOpener.channelResponse(status: status, body: body), as: UTF8.self)
        }
        for status in [204, 400, 403, 404, 405] {
            XCTAssertFalse(text(status).lowercased().contains("access-control"), "\(status)")
            XCTAssertEqual(text(status).contains("Content-Length: 0\r\n"), status != 204, "\(status)")
            XCTAssertTrue(text(status).contains("Cache-Control: no-store\r\nConnection: close\r\n\r\n"), "\(status)")
        }
        XCTAssertTrue(text(204).hasPrefix("HTTP/1.1 204 No Content\r\nX-Pimp-Viewer: 1\r\n"))
        for status in [400, 403, 404, 405] { XCTAssertFalse(text(status).contains("X-Pimp-Viewer"), "\(status)") }
        let ok = text(200, "ok")
        XCTAssertTrue(ok.hasPrefix("HTTP/1.1 200 OK\r\nX-Pimp-Viewer: 1\r\nContent-Type: text/plain; charset=utf-8\r\n"))
        XCTAssertTrue(ok.hasSuffix("Content-Length: 2\r\nCache-Control: no-store\r\nConnection: close\r\n\r\nok"))
        XCTAssertFalse(ok.lowercased().contains("access-control"))
        XCTAssertTrue(text(200, "chat-closed").hasSuffix("\r\n\r\nchat-closed"))
    }

    /// Галерея создаёт токен уже после старта Пимпа — ручки читают файл на каждом запросе.
    func testTokenAppearingAfterStartIsAccepted() throws {
        setenv("PIMP_VIEWER_STORE", tmp.path, 1)
        defer { unsetenv("PIMP_VIEWER_STORE") }
        let opener = HtmlChromeOpener()
        XCTAssertNil(opener.channelToken())
        XCTAssertEqual(HtmlChromeOpener.checkChannel(head("/viewer-nudge"), token: opener.channelToken()), .reject(403))
        try Data((token + "\n").utf8).write(to: tmp.appendingPathComponent("channel.token"))
        XCTAssertEqual(opener.channelToken(), token)
        XCTAssertEqual(HtmlChromeOpener.checkChannel(head("/viewer-nudge"), token: opener.channelToken()),
                       .nudge(chat: true, counts: true))
        // Мусор в файле — токена нет.
        try Data("not-a-token\n".utf8).write(to: tmp.appendingPathComponent("channel.token"))
        XCTAssertNil(opener.channelToken())
        XCTAssertFalse(ViewerClient().launches, "гейт на копии склада — без автозапуска")
    }

    // MARK: - ViewerClient против своего слушателя

    /// Слушатель на порту 0: записывает заголовки запросов, отвечает по сценарию (nil — молчит).
    private final class FakeViewer {
        let listener: NWListener
        private let queue = DispatchQueue(label: "test.fake-viewer")
        private let lock = NSLock()
        private var heads: [String] = []
        var answer: (_ head: String, _ index: Int) -> String? = { _, _ in nil }

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [unowned self] connection in
                connection.start(queue: self.queue)
                self.read(connection, Data())
            }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 2)
        }

        var port: UInt16 { listener.port?.rawValue ?? 0 }
        var requests: [String] { lock.lock(); defer { lock.unlock() }; return heads }

        private func read(_ connection: NWConnection, _ head: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [unowned self] data, _, _, _ in
                var head = head
                if let data = data { head.append(data) }
                let text = String(decoding: head, as: UTF8.self)
                guard text.contains("\r\n\r\n") else { return self.read(connection, head) }
                self.lock.lock()
                self.heads.append(text)
                let index = self.heads.count - 1
                self.lock.unlock()
                guard let reply = self.answer(text, index) else { return }
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }

        static func json(_ body: String, status: String = "200 OK") -> String {
            "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
                + "Connection: close\r\n\r\n\(body)"
        }

        deinit { listener.cancel() }
    }

    private var tokenURL: URL { tmp.appendingPathComponent("channel.token") }

    private func writeToken(_ value: String) throws {
        try Data((value + "\n").utf8).write(to: tokenURL)
    }

    private func client(_ fake: FakeViewer, launches: Bool = false, installed: Bool = false) -> ViewerClient {
        let client = ViewerClient(port: fake.port, tokenURL: tokenURL, launches: launches)
        client.installed = { installed }
        client.running = { false }
        client.launch = { XCTFail("запуск не ждали") }
        client.raise = { XCTFail("вывод вперёд не ждали"); return true }
        return client
    }

    private func accept(_ client: ViewerClient, mode: HtmlChromeOpener.Mode = .click, chat: String? = "local_a",
                        path: String = "/p/a b.html") -> Bool? {
        let done = expectation(description: "accept")
        var result: Bool?
        client.accept(path: path, mode: mode, chat: chat) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    func testAcceptTakenAndRefused() throws {
        try writeToken(token)
        let fake = try FakeViewer()
        fake.answer = { head, _ in
            FakeViewer.json(head.contains("chat=local_a") ? #"{"focus":false,"taken":true}"# : #"{"focus":false,"taken":false}"#)
        }
        let client = client(fake)
        XCTAssertEqual(accept(client), true)
        XCTAssertEqual(accept(client, chat: nil), false)
        let first = try XCTUnwrap(fake.requests.first)
        XCTAssertTrue(first.hasPrefix("GET /accept?mode=click&path=%2Fp%2Fa%20b.html&chat=local_a HTTP/1.1\r\n"), first)
        XCTAssertTrue(first.lowercased().contains("x-pimp-viewer-token: \(token)\r\n"))
        XCTAssertTrue(first.lowercased().contains("host: 127.0.0.1:\(fake.port)\r\n"))
        XCTAssertEqual(client.status, "up/1/1")
    }

    func testFocusRaisesGalleryWindowWithRetries() throws {
        try writeToken(token)
        let fake = try FakeViewer()
        fake.answer = { _, _ in FakeViewer.json(#"{"focus":true,"taken":true}"#) }
        let client = client(fake)
        let raised = expectation(description: "окно появилось с третьей попытки")
        var tries = 0
        client.raise = {
            tries += 1
            if tries == 3 { raised.fulfill() }
            return tries == 3
        }
        XCTAssertEqual(accept(client), true)
        wait(for: [raised], timeout: 3)
    }

    func testForbiddenRereadsTokenOnceAndRetries() throws {
        try writeToken(String(repeating: "0", count: 32))
        let fake = try FakeViewer()
        let fresh = token
        fake.answer = { head, _ in
            head.contains(fresh) ? FakeViewer.json(#"{"focus":false,"taken":true}"#)
                : FakeViewer.json(#"{"ok":false,"error":"forbidden"}"#, status: "403 Forbidden")
        }
        let client = client(fake)
        XCTAssertEqual(accept(client), false, "старый токен и файл не сменился — второй 403 = неуспех")
        XCTAssertEqual(fake.requests.count, 2)
        try writeToken(fresh)
        XCTAssertEqual(accept(client), true)
        XCTAssertEqual(fake.requests.count, 4)
    }

    func testSilenceAndRedirectAreFailures() throws {
        try writeToken(token)
        let fake = try FakeViewer()
        fake.answer = { head, _ in
            head.contains("path=%2Fredirect") ? "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/x\r\nContent-Length: 0\r\n\r\n" : nil
        }
        let client = client(fake)
        let started = Date()
        XCTAssertEqual(accept(client), false)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "тишина — таймаут ≈300 мс, приложения нет — без ожидания")
        XCTAssertEqual(accept(client, path: "/redirect.html"), false)
        XCTAssertEqual(fake.requests.filter { $0.hasPrefix("GET /accept") }.count, 2)
    }

    /// Токена нет (галерея не запускалась) — запуск в фоне, ожидание `ready`, один повтор.
    func testUnreachableLaunchesWaitsReadyAndRetries() throws {
        let fake = try FakeViewer()
        fake.answer = { head, _ in
            FakeViewer.json(head.hasPrefix("GET /ping") ? #"{"ok":true,"pid":1,"ready":true,"version":"1.0"}"#
                                                        : #"{"focus":false,"taken":true}"#)
        }
        let client = client(fake, launches: true, installed: true)
        var launched = 0
        let token = self.token
        let url = tokenURL
        client.launch = { launched += 1; try? Data((token + "\n").utf8).write(to: url) }
        XCTAssertEqual(accept(client, mode: .click), true)
        XCTAssertEqual(launched, 1)
        XCTAssertEqual(fake.requests.map { String($0.prefix(11)) }, ["GET /ping H", "GET /accept"])
    }

    func testMissingAppFallsBackAndReportsMissing() throws {
        let fake = try FakeViewer()
        let client = client(fake, launches: true, installed: false)
        let missing = expectation(description: "плашка «Галерея не установлена»")
        client.onMissing = { missing.fulfill() }
        XCTAssertEqual(accept(client), false)
        client.show()
        wait(for: [missing], timeout: 3)
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertEqual(client.status, "none/0/1")
    }

    func testStateParsesCountsAndFilter() throws {
        try writeToken(token)
        let fake = try FakeViewer()
        fake.answer = { _, _ in FakeViewer.json(#"{"counts":{"local_b":[3,1],"evil":[1,1],"local_a":[2,0]},"filterChat":"local_a"}"#) }
        let client = client(fake)
        let done = expectation(description: "state")
        var got: (filterChat: String?, counts: [String: [Int]])?
        client.state { got = $0; done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(got?.filterChat, "local_a")
        XCTAssertEqual(got?.counts, ["local_a": [2, 0], "local_b": [3, 1]])
        XCTAssertTrue(client.isUp)
        XCTAssertEqual(ViewerClient.parseState(["filterChat": NSNull(), "counts": [:]]).filterChat, nil)
    }

    /// Просмотр в окне чата: `onView` сразу, галерее — `accept(mode=view)`, браузера нет, ответа не ждём.
    func testRouteViewShowsAtOnceAndSendsQuietAccept() throws {
        try writeToken(token)
        let fake = try FakeViewer()
        let asked = expectation(description: "галерея получила view")
        fake.answer = { head, _ in
            if head.hasPrefix("GET /accept?mode=view&") { asked.fulfill() }
            return FakeViewer.json(#"{"focus":false,"taken":false}"#)
        }
        let client = client(fake)
        let opener = HtmlChromeOpener()
        var views = 0
        var browser = 0
        opener.onView = { _ in views += 1 }
        opener.isKnownChat = { _ in true }
        opener.browserSeam = { _ in browser += 1 }
        opener.toViewer = { request, done in
            client.accept(path: request.path, mode: request.mode, chat: request.chat, done: done)
        }
        opener.route(HtmlChromeOpener.Request(path: "/p/a.html", mode: .view, chat: "local_a",
                                              frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        XCTAssertEqual(views, 1, "окно просмотра не ждёт галерею")
        wait(for: [asked], timeout: 3)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(browser, 0)
    }
}
