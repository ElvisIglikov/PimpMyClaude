import XCTest
@testable import ClaudeAX

/// #9552 (К-OC): «Всё в одном чате» панели PMP страницы — `GET /one-chat` на порт страницы. Папка Рика есть — новое окно
/// в ней; по пути ничего нет — к строке «Поставить Рика»; там файл — плашка, ничего не открываем.
final class OneChat9552Tests: XCTestCase {
    private func head(_ target: String = "/one-chat", origin: String? = "https://claude.ai", method: String = "GET",
                      token: String? = nil) -> String {
        "\(method) \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n" } ?? "")
            + (token.map { "X-Pimp-Viewer-Token: \($0)\r\n" } ?? "") + "\r\n"
    }

    func testParseTakesOnlyGetOneChat() {
        XCTAssertTrue(HtmlChromeOpener.parseOneChat(head()))
        XCTAssertFalse(HtmlChromeOpener.parseOneChat(head("/one-chats")))
        XCTAssertFalse(HtmlChromeOpener.parseOneChat(head("/panel")))
        XCTAssertFalse(HtmlChromeOpener.parseOneChat(head(method: "POST")))
        XCTAssertFalse(HtmlChromeOpener.parsePanel(head()), "/one-chat — не «Настройки PMP»")
        XCTAssertNil(HtmlChromeOpener.parse(head()))
    }

    func testCheckPageAdmitsOnlyClaudePage() {
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(), token: nil), .browser(preflight: false))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(origin: "https://evil.test"), token: nil), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(origin: nil), token: nil), .reject(403), "без Origin и без токена")
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(method: "POST"), token: nil), .reject(405))
        XCTAssertEqual(HtmlChromeOpener.checkPage("OPTIONS /one-chat HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n"
            + "Origin: https://claude.ai\r\nAccess-Control-Request-Method: GET\r\n\r\n", token: nil), .browser(preflight: true))
        // Как у `/panel`: клиент без Origin с верным токеном канала галереи (К-V8) — свой, действие выполняется.
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(origin: nil, token: "s3cret"), token: "s3cret"), .native)
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(origin: nil, token: "other"), token: "s3cret"), .reject(403))
    }

    func testHandleCallsOneChatOnceAndNotPanel() {
        let opener = HtmlChromeOpener()
        opener.channelToken = { nil }
        var asked = 0
        var panels = 0
        opener.onOneChat = { asked += 1 }
        opener.onPanel = { panels += 1 }
        opener.handleOld(head())
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(panels, 0)
        // Чужая страница, запрос без Origin и предзапрос ничего не открывают.
        opener.handleOld(head(origin: "https://evil.test"))
        opener.handleOld(head(origin: nil))
        opener.handleOld("OPTIONS /one-chat HTTP/1.1\r\nHost: 127.0.0.1:47615\r\nOrigin: https://claude.ai\r\n"
            + "Access-Control-Request-Method: GET\r\n\r\n")
        XCTAssertEqual(asked, 1)
        // `/panel` — по-прежнему панель у часов, не «Всё в одном чате».
        opener.handleOld(head("/panel"))
        XCTAssertEqual([asked, panels], [1, 1])
    }

    func testResponseIsNoContentWithCors() {
        let text = String(decoding: HtmlChromeOpener.pageResponse(.browser(preflight: false)), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 204 No Content\r\n"), text)
        XCTAssertTrue(text.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"), text)
    }

    private func sandbox() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onechat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return base
    }

    func testStepFolderWindowNothingSetupFileOccupied() throws {
        let root = try sandbox()
        let rick = root.appendingPathComponent("Rick", isDirectory: true)
        XCTAssertEqual(ClaudeAXController.oneChatStep(folder: rick), .setup, "папки нет — к «Поставить Рика»")
        try FileManager.default.createDirectory(at: rick, withIntermediateDirectories: true)
        guard case .window(let project) = ClaudeAXController.oneChatStep(folder: rick) else {
            return XCTFail("папка есть — окно в ней")
        }
        XCTAssertEqual(project.name, "Rick")
        XCTAssertEqual(project.folder.path, rick.standardizedFileURL.path)
        // На месте папки — файл: строки «Поставить Рика» нет (RickKit.isPresent), окна открыть не в чем — плашка.
        try FileManager.default.removeItem(at: rick)
        try Data("x".utf8).write(to: rick)
        guard case .occupied(let text) = ClaudeAXController.oneChatStep(folder: rick) else {
            return XCTFail("файл на месте папки — плашка")
        }
        XCTAssertTrue(text.contains("не папка"), text)
        XCTAssertFalse(text.contains("Пимп"), "в интерфейсе — PMP")
        // Битая ссылка — тоже «занято»: чужое не трогаем.
        try FileManager.default.removeItem(at: rick)
        try FileManager.default.createSymbolicLink(atPath: rick.path, withDestinationPath: root.appendingPathComponent("нет").path)
        guard case .occupied = ClaudeAXController.oneChatStep(folder: rick) else { return XCTFail("битая ссылка") }
    }
}
