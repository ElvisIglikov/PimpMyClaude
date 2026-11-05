import Network
import XCTest
@testable import ClaudeAX

/// #11323 (К-LINK, `docs/contracts/600-wf288-our-links.md`): внешняя ссылка из чата — `/open-link?kind=web&url=…`,
/// уже открытая вкладка Chromium вперёд без перечитывания, иначе новая; не Chromium или скрипт не прошёл — `open(url)`.
/// Приложений не открываем: `webOpen` и подставки `openWeb` — свои, живой порт 47615 не трогаем.
final class WebTab11323Tests: XCTestCase {
    private func head(_ target: String, origin: String? = "https://claude.ai") -> String {
        "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n" } ?? "") + "\r\n"
    }

    private func encoded(_ raw: String) -> String { raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }

    func testScriptEscapesFocusesWithoutReloadAndComparesLoosely() {
        let script = HtmlChromeOpener.webTabScript(url: #"https://ex.com/a"b\c/#frag"#, browser: "Vivaldi")
        XCTAssertTrue(script.contains(#"set target to "https://ex.com/a\"b\\c/#frag""#), script)
        XCTAssertTrue(script.contains(#"set targetKey to "ex.com/a\"b\\c""#), "ключ без схемы, фрагмента и «/»")
        XCTAssertTrue(script.contains(#"tell application "Vivaldi""#))
        XCTAssertFalse(script.contains("reload"), "веб-страницу не перечитываем")
        XCTAssertTrue(script.contains("set active tab index of w to i"))
        XCTAssertTrue(script.contains("make new tab with properties {URL:target}"))
        XCTAssertTrue(script.contains(##"offset of "#" in k"##), "фрагмент вкладки отрезается")
        XCTAssertTrue(script.contains(#"k ends with "/""#), "конечный «/» вкладки отрезается")
        XCTAssertTrue(script.contains("considering case"))
        // Файлы — прежний скрипт с reload.
        XCTAssertTrue(HtmlChromeOpener.script(url: "file:///a.html").contains("reload t"))
    }

    func testWebKey() {
        XCTAssertEqual(HtmlChromeOpener.webKey("https://github.com/a/b/#x"), "github.com/a/b")
        XCTAssertEqual(HtmlChromeOpener.webKey("http://github.com/a/b"), "github.com/a/b", "http ↔ https — одна страница")
        XCTAssertEqual(HtmlChromeOpener.webKey("https://example.com/"), "example.com")
        XCTAssertEqual(HtmlChromeOpener.webKey("https://example.com/a?b=1#c"), "example.com/a?b=1")
        XCTAssertNotEqual(HtmlChromeOpener.webKey("https://evil.test/github.com/a"), HtmlChromeOpener.webKey("https://github.com/a"))
    }

    func testParseAndRefusals() {
        let url = "https://github.com/ElvisIglikov/PimpMyClaude/pull/7"
        XCTAssertEqual(HtmlChromeOpener.parseWeb(head("/open-link?kind=web&url=\(encoded(url))"))?.absoluteString, url)
        XCTAssertEqual(HtmlChromeOpener.parseWeb(head("/open-link?url=\(encoded("http://x.ru/a"))&kind=web"))?.absoluteString,
                       "http://x.ru/a")
        XCTAssertTrue(HtmlChromeOpener.isWebLink(head("/open-link?kind=web")))
        XCTAssertFalse(HtmlChromeOpener.isWebLink(head("/open-link?url=\(encoded(url))")), "без вида — задачи Trelvis")
        XCTAssertNil(HtmlChromeOpener.parseWeb(head("/open-link?url=\(encoded(url))")))
        XCTAssertNil(HtmlChromeOpener.parseWeb(head("/open-link?kind=web")), "нет url")
        XCTAssertNil(HtmlChromeOpener.parseWeb(head("/open-html?kind=web&url=\(encoded(url))")), "другой путь")
        for raw in ["https://claude.ai/new", "https://www.claude.com/x", "https://docs.anthropic.com/a", "https://claude.ai./x",
                    "HTTPS://CLAUDE.AI/x", "file:///etc/passwd", "javascript:alert(1)", "trelvis://task/5", "mailto:a@b.c",
                    "https://", "/Users/x.html", "", "https://x.ru/" + String(repeating: "a", count: 5000)] {
            XCTAssertNil(HtmlChromeOpener.webURL(raw), raw)
        }
        XCTAssertNotNil(HtmlChromeOpener.webURL("https://notclaude.ai/x"), "похожий хост — чужой сайт")
    }

    func testRouteChromiumScriptElseOpen() {
        let app = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let url = URL(string: "https://github.com/a")!
        var scripts: [String] = [], opened: [URL] = [], activated: [URL] = []
        let chromium = HtmlChromeOpener.route(app: app, bundleID: HtmlChromeOpener.chromeBundleID)
        XCTAssertEqual(HtmlChromeOpener.openWeb(url, route: chromium, runScript: { scripts.append($0); return true },
                                                open: { opened.append($0) }, activate: { activated.append($0) }), .script)
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains(#"tell application "Google Chrome""#))
        XCTAssertEqual(opened, [])
        XCTAssertEqual(activated, [app])
        XCTAssertEqual(HtmlChromeOpener.openWeb(url, route: chromium, runScript: { _ in false },
                                                open: { opened.append($0) }, activate: { activated.append($0) }), .scriptFailed)
        XCTAssertEqual(opened, [url], "нет разрешения Automation — open(url)")
        let safari = HtmlChromeOpener.route(app: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari")
        for route in [safari, HtmlChromeOpener.route(app: nil, bundleID: nil)] {
            XCTAssertEqual(HtmlChromeOpener.openWeb(url, route: route, runScript: { scripts.append($0); return true },
                                                    open: { opened.append($0) }, activate: { activated.append($0) }), .open)
        }
        XCTAssertEqual(scripts.count, 1, "не Chromium — без скрипта")
        XCTAssertEqual(opened, [url, url, url])
        XCTAssertEqual(activated, [app])
    }

    // MARK: - по настоящему сокету

    func testServeAnswersAndOpensOnlyWeb() throws {
        let opener = HtmlChromeOpener()
        opener.channelToken = { nil }
        let lock = NSLock()
        var webs: [String] = [], plans: [String] = []
        opener.webOpen = { url in lock.lock(); webs.append(url.absoluteString); lock.unlock() }
        opener.linkOpen = { plan in lock.lock(); plans.append(plan.via); lock.unlock() }
        opener.linkHasApp = { _ in false }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        defer { listener.cancel() }
        listener.newConnectionHandler = { opener.serve($0) }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: DispatchQueue(label: "test.web-server"))
        _ = ready.wait(timeout: .now() + 3)
        let port = try XCTUnwrap(listener.port)

        func exchange(_ target: String, origin: String? = "https://claude.ai") -> String {
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            let ended = DispatchSemaphore(value: 0)
            let box = NSLock()
            var data = Data()
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { bytes, _, done, error in
                    box.lock(); if let bytes = bytes { data.append(bytes) }; box.unlock()
                    if done || error != nil { ended.signal() } else { receive() }
                }
            }
            let request = head(target, origin: origin)
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                receive()
            }
            connection.start(queue: DispatchQueue(label: "test.web-client"))
            defer { connection.cancel() }
            XCTAssertEqual(ended.wait(timeout: .now() + 5), .success, target)
            box.lock(); defer { box.unlock() }
            return String(decoding: data, as: UTF8.self)
        }

        let url = "https://github.com/a/b#c"
        let ok = exchange("/open-link?kind=web&url=\(encoded(url))")
        XCTAssertTrue(ok.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n"), ok)
        XCTAssertTrue(ok.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"))
        XCTAssertTrue(ok.hasSuffix(#"{"opened":true,"via":"web"}"#), ok)
        let claude = exchange("/open-link?kind=web&url=\(encoded("https://claude.ai/new"))")
        XCTAssertTrue(claude.hasPrefix("HTTP/1.1 400 ") && claude.hasSuffix(#"{"opened":false}"#), claude)
        XCTAssertTrue(exchange("/open-link?kind=web&url=\(encoded(url))", origin: "https://evil.test").hasPrefix("HTTP/1.1 403 "))
        // Задача Trelvis без вида — прежний путь.
        let task = exchange("/open-link?url=\(encoded("https://vlusnoff-production.up.railway.app/#t/5"))")
        XCTAssertTrue(task.hasSuffix(#"{"opened":true,"via":"chrome"}"#), task)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(webs, [url], "Claude и чужой Origin ничего не открыли")
        XCTAssertEqual(plans, ["chrome"])
    }
}
