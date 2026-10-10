import XCTest
@testable import ClaudeAX

/// WF125 (#8894): кнопка «PMP» в окне Claude — `GET /panel` на порт страницы → открыть панель у часов.
final class PanelRequestWF125Tests: XCTestCase {
    private func head(_ target: String = "/panel", origin: String? = "https://claude.ai", method: String = "GET") -> String {
        "\(method) \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n" } ?? "") + "\r\n"
    }

    func testParseTakesOnlyGetPanel() {
        XCTAssertTrue(HtmlChromeOpener.parsePanel(head()))
        XCTAssertFalse(HtmlChromeOpener.parsePanel(head("/panels")))
        XCTAssertFalse(HtmlChromeOpener.parsePanel(head("/viewer?chat=local_a&on=1")))
        XCTAssertFalse(HtmlChromeOpener.parsePanel(head(method: "POST")))
        XCTAssertNil(HtmlChromeOpener.parse(head()))
    }

    func testPageOfClaudeOpensPanelAndGetsCorsAnswer() {
        let opener = HtmlChromeOpener()
        opener.channelToken = { nil }
        var opened = 0
        opener.onPanel = { opened += 1 }
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(), token: nil), .browser(preflight: false))
        opener.handleOld(head())
        XCTAssertEqual(opened, 1)
        // Чужая страница, запрос без Origin и предзапрос панель не открывают.
        opener.handleOld(head(origin: "https://evil.test"))
        opener.handleOld(head(origin: nil))
        opener.handleOld("OPTIONS /panel HTTP/1.1\r\nHost: 127.0.0.1:47615\r\nOrigin: https://claude.ai\r\n"
            + "Access-Control-Request-Method: GET\r\n\r\n")
        XCTAssertEqual(opened, 1)
    }
}
