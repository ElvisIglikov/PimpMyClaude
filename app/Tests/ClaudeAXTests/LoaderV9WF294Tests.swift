import Foundation
import XCTest
@testable import ClaudeAX

/// WF294 (#10787): лоадер v9. Печать `source.loader` пишет сам лоадер; до перепатча в Claude стоит v8 — карта чатов
/// верит обеим, старее v8 и не-числу — нет.
final class LoaderV9WF294Tests: XCTestCase {
    private func entry(loader: Any?) -> [String: Any] {
        var source = ProbeSourceFixture.metadata(url: "about:blank")
        source["loader"] = loader
        return ["id": 1, "url": "about:blank", "source": source, "result": ["nonce": "n"]]
    }

    func testSealAcceptsV8AndV9Only() {
        XCTAssertTrue(ChatProbe.trustedSource(entry(loader: 8)))
        XCTAssertTrue(ChatProbe.trustedSource(entry(loader: 9)))
        for bad: Any? in [7, 0, nil, "9", 8.5] {
            XCTAssertFalse(ChatProbe.trustedSource(entry(loader: bad)), "\(String(describing: bad))")
        }
    }

    func testAnswerFromV9IsNotUntrusted() throws {
        let answer = { (loader: Int) in
            try JSONSerialization.data(withJSONObject: ["results": [self.entry(loader: loader)]])
        }
        XCTAssertFalse(ChatProbe.answeredUntrusted(try answer(9), nonce: "n"))
        XCTAssertFalse(ChatProbe.answeredUntrusted(try answer(8), nonce: "n"))
        XCTAssertTrue(ChatProbe.answeredUntrusted(try answer(7), nonce: "n"))
    }
}
