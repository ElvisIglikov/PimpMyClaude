import AppKit
import XCTest
@testable import ClaudeAX

/// #9681 (слово Элвиса 11.10.2026): родная кнопка диктовки Claude в режиме Диктатора запускает Диктатора, как
/// кружок; правой кнопкой — выбор «Диктатор» или «Диктовка Claude». Всё на подставных данных.
final class Mic9681Tests: XCTestCase {
    private func suite() -> UserDefaults { UserDefaults(suiteName: testSuiteName())! }

    func testParseMicNative() throws {
        let raw = try Data(contentsOf: Repo.fixture("cashout/probe-answer-popout.json"))
        var result = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let nonce = try XCTUnwrap(result["nonce"] as? String)
        func parse(_ result: [String: Any]) throws -> ChatPage? {
            let body: [String: Any] = ["at": "2026-10-21T08:00:00Z",
                                       "results": [["id": 1, "source": ProbeSourceFixture.metadata(url: "about:blank"),
                                                    "url": "about:blank", "result": result]]]
            return ChatProbe.parseAnswer(try JSONSerialization.data(withJSONObject: body), nonce: nonce,
                                         at: Date(timeIntervalSince1970: 1_000_000)).pages.first
        }
        XCTAssertNil(try parse(result)?.micNative, "старая страница — поля нет")
        result["micNative"] = [1050, 74, 20, 20, 0]
        XCTAssertEqual(try parse(result)?.micNative, CGRect(x: 1050, y: 74, width: 20, height: 20))
        XCTAssertEqual(try parse(result)?.micNativeAnchor, .right)
        result["micNative"] = NSNull()
        XCTAssertNil(try parse(result)?.micNative)
    }

    func testBothSpotsAreHitTargets() {
        let window = CGRect(x: 100, y: 50, width: 1200, height: 800)
        var page = ChatPage(kind: .main, chat: "c", title: "t", store: "", mic: CGRect(x: 120, y: 40, width: 20, height: 20),
                            at: Date())
        XCTAssertEqual(MicMonitor.spots(page, window: window).count, 1)
        page.micNative = CGRect(x: 1050, y: 74, width: 20, height: 20)
        let spots = MicMonitor.spots(page, window: window)
        XCTAssertEqual(spots.count, 2)
        XCTAssertEqual(spots[1], MicMonitor.micRect(spot: page.micNative!, window: window, anchor: .right))
    }

    func testChoiceDecidesModeAndIsRemembered() {
        let defaults = suite()
        let monitor = MicMonitor()
        monitor.defaults = defaults
        var sent: [MicMode] = []
        monitor.sendMode = { sent.append($0); return true }
        monitor.choose(.dictator)
        monitor.noteDictator(true)
        XCTAssertEqual(monitor.mode, .dictator)
        monitor.tick(titles: ["a"], at: Date())
        XCTAssertEqual(sent.last, .dictator)
        monitor.choose(.claude)
        XCTAssertEqual(monitor.mode, .claude, "выбрана диктовка Claude — Диктатор кнопки не перехватывает")
        XCTAssertEqual(MicChoice.load(defaults), .claude, "выбор помнится")
        monitor.tick(titles: ["a"], at: Date())
        XCTAssertEqual(sent.last, .claude, "страницам — сразу, новым поколением")
        monitor.choose(.dictator)
        monitor.noteDictator(false)
        XCTAssertEqual(monitor.mode, .claude, "Диктатор не запущен — только Claude")
        XCTAssertEqual(MicChoice.load(suite()), .dictator, "по умолчанию — Диктатор, как до #9681")
    }

    func testMenuHasDictationChoiceThenRick() {
        var chosen: [MicChoice] = []
        let menu = MicMonitor.rickMenu(voices: [], current: nil, choice: .dictator, choose: { chosen.append($0) },
                                       use: { _ in }, repeatLast: {})
        XCTAssertEqual(menu.items.map { $0.title }, ["🎙 Диктовка", "● Диктатор", "○ Диктовка Claude"],
                       "без голосов Рика — только выбор")
        let full = MicMonitor.rickMenu(voices: [RickVoice(alias: "a", name: "Альфа")], current: "a", choice: .claude,
                                       use: { _ in }, repeatLast: {})
        XCTAssertEqual(full.items.prefix(4).map { $0.title }, ["🎙 Диктовка", "○ Диктатор", "● Диктовка Claude", ""])
        XCTAssertTrue(full.items.contains { $0.title == MicMonitor.rickTitle })
        let old = MicMonitor.rickMenu(voices: [RickVoice(alias: "a", name: "Альфа")], current: "a",
                                      use: { _ in }, repeatLast: {})
        XCTAssertEqual(old.items.first?.title, MicMonitor.rickTitle, "Диктатор не запущен — меню Рика как было")
        _ = chosen
    }
}
