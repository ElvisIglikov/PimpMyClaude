import XCTest
@testable import ClaudeAX

final class SourceBoundaryTests: XCTestCase {
    private func envelope(url: String = "https://claude.ai/epitaxy", origin: String = "https://claude.ai",
                          loader: Int = 8) -> [String: Any] {
        ["id": 1, "url": url,
         "source": ["loader": loader, "origin": origin, "url": url, "processId": 12, "routingId": 3],
         "result": ["v": 1, "nonce": "n", "kind": "main", "self": "local_a", "title": "A",
                    "folder": "/tmp/project", "working": false, "themes": ["chat:A": ["frame": true]],
                    "send": ["id": "x", "state": "sent"], "cashout": ["delivery": "вставлено"], "wait": true]]
    }

    func testAllProbeFieldsRequireLoaderProvenance() throws {
        var missing = envelope()
        missing.removeValue(forKey: "source")
        // A hostile renderer may put any claims INSIDE result; that never authenticates it.
        var payload = missing["result"] as! [String: Any]
        payload["source"] = envelope()["source"]
        missing["result"] = payload
        let invalid = [missing, envelope(loader: 7), envelope(origin: "null"),
                       envelope(url: "about:blank", origin: "https://evil.test"),
                       envelope(url: "https://claude.ai.evil.test/"),
                       envelope(url: "https://claude.ai:444/"), envelope(url: "data:text/html,secret"),
                       envelope(url: "file:///tmp/page.html")]
        for entry in invalid {
            let data = try JSONSerialization.data(withJSONObject: ["results": [entry]])
            let result = ChatProbe.parseAnswer(data, nonce: "n", at: Date())
            XCTAssertTrue(result.pages.isEmpty)
            XCTAssertNil(result.themes)
        }
        for url in ["https://claude.ai/epitaxy", "about:blank", ""] {
            let data = try JSONSerialization.data(withJSONObject: ["results": [envelope(url: url)]])
            let result = ChatProbe.parseAnswer(data, nonce: "n", at: Date())
            XCTAssertEqual(result.pages.count, 1)
            XCTAssertEqual(result.pages.first?.send?.state, "sent")
        }
    }

    private let token = String(repeating: "a", count: 32)
    private func head(origin: String? = "https://claude.ai", method: String = "GET",
                      extra: String = "", complete: Bool = true) -> String {
        "\(method) /context?chat=local_a HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n"
            + (origin.map { "Origin: \($0)\r\n" } ?? "") + extra + (complete ? "\r\n" : "")
    }

    func testHTTPRejectsBeforeAnySideEffectAndWaitsForCompleteHeaders() {
        let opener = HtmlChromeOpener()
        opener.channelToken = { self.token }
        var called: [String] = []
        opener.onContext = { called.append($0) }
        for request in [head(complete: false), head(origin: nil), head(origin: "null"),
                        head(origin: "https://evil.test"), head(origin: "https://claude.ai.evil.test"),
                        head(extra: "Host: localhost:47615\r\n"), head(extra: "Origin: https://claude.ai\r\n"),
                        head(extra: " Origin: https://claude.ai\r\n"),
                        head(origin: "null", extra: "X-Pimp-Viewer-Token: \(token)\r\n"),
                        head(method: "OPTIONS", extra: "Access-Control-Request-Method: GET\r\n")] {
            opener.handleOld(request)
        }
        XCTAssertEqual(called, [])
        opener.handleOld(head())
        opener.handleOld(head(origin: nil, extra: "X-Pimp-Viewer-Token: \(token)\r\n"))
        XCTAssertEqual(called, ["local_a", "local_a"])
    }

    func testHTTPCorsIsExactAndNeverOnNativeOrRejectedResponses() {
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(), token: nil), .browser(preflight: false))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(method: "OPTIONS", extra: "Access-Control-Request-Method: GET\r\n"), token: nil),
                       .browser(preflight: true))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(method: "OPTIONS", extra: "Access-Control-Request-Method: POST\r\n"), token: nil),
                       .reject(403))
        let cors = String(decoding: HtmlChromeOpener.pageResponse(.browser(preflight: true)), as: UTF8.self)
        XCTAssertTrue(cors.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"))
        XCTAssertFalse(cors.contains("Access-Control-Allow-Origin: *"))
        for access in [HtmlChromeOpener.PageAccess.native, .reject(403), .reject(400)] {
            XCTAssertFalse(String(decoding: HtmlChromeOpener.pageResponse(access), as: UTF8.self).contains("Access-Control"))
        }
    }
}
