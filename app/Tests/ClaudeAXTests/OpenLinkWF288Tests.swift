import Network
import XCTest
@testable import ClaudeAX

/// Наши ссылки WF288 (#10891, #10892; контракт `docs/contracts/600-wf288-our-links.md`, К-LINK): белый список адресов
/// `/open-link`, выбор Trelvis.app или Chrome, отказ чужим адресам, ответ по настоящему сокету и 404 у `/open-html`, когда
/// файла нет. Приложений не открываем (`linkOpen`, `linkHasApp`, `browserSeam` подменены), живой порт 47615 не трогаем.
final class OpenLinkWF288Tests: XCTestCase {
    private let task = "https://vlusnoff-production.up.railway.app/#t/10850"

    private func head(_ target: String, origin: String? = "https://claude.ai") -> String {
        "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n" } ?? "") + "\r\n"
    }

    private func encoded(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    func testWhiteListTakesOnlyTrelvisTasks() {
        XCTAssertEqual(HtmlChromeOpener.linkTarget(task), .trelvisTask(10850))
        XCTAssertEqual(HtmlChromeOpener.linkTarget("https://vlusnoff-production.up.railway.app/#task/7"), .trelvisTask(7))
        XCTAssertEqual(HtmlChromeOpener.linkTarget("trelvis://task/12"), .trelvisTask(12))
        XCTAssertEqual(HtmlChromeOpener.linkTarget("kaban://task/12"), .trelvisTask(12))
        for raw in ["https://vlusnoff-production.up.railway.app/#t/0", "https://vlusnoff-production.up.railway.app/#t/12x",
                    "https://vlusnoff-production.up.railway.app.evil.test/#t/5", "http://vlusnoff-production.up.railway.app/#t/5",
                    "https://vlusnoff-production.up.railway.app/x#t/5", "https://vlusnoff-production.up.railway.app/#tasks/1-3",
                    "https://vlusnoff-production.up.railway.app/#t/1234567890", "trelvis://card/5", "file:///etc/passwd",
                    "https://vkusstatbot-production.up.railway.app/r/tP77pRg5", "javascript:alert(1)", ""] {
            XCTAssertNil(HtmlChromeOpener.linkTarget(raw), raw)
        }
        XCTAssertEqual(HtmlChromeOpener.parseLink(head("/open-link?url=\(encoded(task))")), .trelvisTask(10850))
        XCTAssertNil(HtmlChromeOpener.parseLink(head("/open-link")), "нет url")
        XCTAssertNil(HtmlChromeOpener.parseLink(head("/open-html?url=\(encoded(task))")), "другой путь")
    }

    func testPlanPicksTrelvisAppOrChrome() {
        XCTAssertEqual(HtmlChromeOpener.linkPlan(.trelvisTask(10850), hasTrelvis: true),
                       HtmlChromeOpener.LinkPlan(url: URL(string: "trelvis://task/10850")!, via: "trelvis"))
        XCTAssertEqual(HtmlChromeOpener.linkPlan(.trelvisTask(10850), hasTrelvis: false),
                       HtmlChromeOpener.LinkPlan(url: URL(string: "https://vlusnoff-production.up.railway.app/#task/10850")!,
                                                 via: "chrome"))
    }

    func testPageAccessListsOpenLink() {
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/open-link?url=x"), token: nil), .browser(preflight: false))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/open-link?url=x", origin: "https://evil.test"), token: nil), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/open-link?url=x", origin: nil), token: nil), .reject(403))
    }

    // MARK: - по настоящему сокету

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
            listener.start(queue: DispatchQueue(label: "test.link-server"))
            _ = ready.wait(timeout: .now() + 3)
        }
        deinit { listener.cancel() }

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
            connection.start(queue: DispatchQueue(label: "test.link-client"))
            defer { connection.cancel() }
            XCTAssertEqual(ended.wait(timeout: .now() + 5), .success, target)
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    func testOpenLinkAnswersAndOpensOnlyWhiteList() throws {
        let server = try Server()
        let lock = NSLock()
        var plans: [HtmlChromeOpener.LinkPlan] = []
        var asked: [URL] = []
        var hasTrelvis = true
        server.opener.linkHasApp = { url in lock.lock(); asked.append(url); lock.unlock(); return hasTrelvis }
        server.opener.linkOpen = { plan in lock.lock(); plans.append(plan); lock.unlock() }
        let target = "/open-link?url=\(encoded(task))"
        let viaApp = try server.exchange(target)
        XCTAssertTrue(viaApp.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n"), viaApp)
        XCTAssertTrue(viaApp.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"), "страница читает ответ")
        XCTAssertTrue(viaApp.hasSuffix(#"{"opened":true,"via":"trelvis"}"#), viaApp)
        hasTrelvis = false
        XCTAssertTrue(try server.exchange(target).hasSuffix(#"{"opened":true,"via":"chrome"}"#))
        let foreign = try server.exchange("/open-link?url=\(encoded("https://evil.test/#t/5"))")
        XCTAssertTrue(foreign.hasPrefix("HTTP/1.1 400 "), foreign)
        XCTAssertTrue(foreign.hasSuffix(#"{"opened":false}"#), foreign)
        XCTAssertTrue(try server.exchange("/open-link").hasPrefix("HTTP/1.1 400 "))
        XCTAssertTrue(try server.exchange(target, origin: "https://evil.test").hasPrefix("HTTP/1.1 403 "))
        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(plans.map(\.via), ["trelvis", "chrome"], "чужие адреса и чужой Origin ничего не открыли")
        XCTAssertEqual(plans.map(\.url.absoluteString),
                       ["trelvis://task/10850", "https://vlusnoff-production.up.railway.app/#task/10850"])
        XCTAssertEqual(asked.map(\.absoluteString), ["trelvis://task/10850", "trelvis://task/10850"])
    }

    func testOpenHtmlMissingFileAnswers404() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("open-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("tP77pRg5.html")
        try Data("<p>hi</p>".utf8).write(to: file)
        let server = try Server()
        let lock = NSLock()
        var browser: [String] = []
        server.opener.browserSeam = { lock.lock(); browser.append($0.path); lock.unlock() }
        let path = ViewerClient.encode(file.path)
        let missingPath = ViewerClient.encode(folder.appendingPathComponent("нет.html").path)
        XCTAssertTrue(try server.exchange("/open-html?mode=click&path=\(path)&chat=local_a").hasPrefix("HTTP/1.1 204 "))
        let missing = try server.exchange("/open-html?mode=click&path=\(missingPath)&chat=local_a")
        XCTAssertTrue(missing.hasPrefix("HTTP/1.1 404 "), missing)
        XCTAssertTrue(missing.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"), "страница видит 404")
        // С местом дока — то же тело, что было, но 404.
        server.opener.toDock = { _, done in done(true, true) }
        let room = "&dock=1&x=0&y=40&w=420&h=700&wx=383&wy=29&ww=896&wh=742"
        let docked = try server.exchange("/open-html?mode=click&path=\(missingPath)&chat=local_a\(room)")
        XCTAssertTrue(docked.hasPrefix("HTTP/1.1 404 "), docked)
        XCTAssertTrue(docked.hasSuffix(#"{"taken":false,"opened":false}"#), docked)
        XCTAssertTrue(try server.exchange("/open-html?mode=click&path=\(path)&chat=local_a\(room)")
            .hasSuffix(#"{"taken":true,"opened":true}"#))
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            lock.lock(); let count = browser.count; lock.unlock()
            if count > 0 { break }
            usleep(20_000)
        }
        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(browser, [file.path], "существующий файл — прежний путь, несуществующий — ничего")
    }
}
