import XCTest
@testable import ClaudeAX

/// WF161: «Bypass permissions во всех чатах» командой `bypass-chats` (#9060 путь Б) и поля до 40 (#9148).
final class WF161Tests: XCTestCase {
    private typealias Sent = (action: String, json: String)

    private func makeSettings() -> (PageLookSettings, UserDefaults, () -> [Sent]) {
        let suite = "wf161-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = PageLookSettings(defaults: defaults)
        var sent: [Sent] = []
        settings.write = { action, fields, _ in
            sent.append((action, CommandValue.object(fields).json))
            return true
        }
        // Тик шлёт и другие выборы (dim, send-look) — здесь смотрим только bypass-chats.
        return (settings, defaults, { sent.filter { $0.action == BypassNew.action } })
    }

    private static let at = Date(timeIntervalSince1970: 1_790_200_000)

    func testBypassChatsWireMatchesContract() {
        XCTAssertEqual(BypassNew.menuTitle, "Bypass permissions во всех чатах")
        for (on, word) in [(true, "true"), (false, "false")] {
            XCTAssertEqual(CommandChannel.payload(action: BypassNew.action, fields: BypassNew.fields(on: on),
                                                  id: "wf161-bypass", at: PimpChannel.date("2026-10-08T00:00:00Z")!),
                           "{\"id\":\"wf161-bypass\",\"action\":\"bypass-chats\",\"at\":\"2026-10-08T00:00:00Z\",\"on\":\"\(word)\"}")
        }
    }

    func testNoKeyNoCommand() {
        let (settings, defaults, sent) = makeSettings()
        settings.beginGeneration()
        for n in 0..<4 { settings.tick(titles: ["\(n)"], at: Self.at.addingTimeInterval(Double(n) * 6)) }
        XCTAssertTrue(sent().isEmpty)
        XCTAssertFalse(settings.bypassChats)
        XCTAssertNil(defaults.object(forKey: BypassNew.key))
    }

    func testSwitchSendsAtOnceAndRepeatsToNewGeneration() {
        let (settings, defaults, sent) = makeSettings()
        settings.setBypassChats(true)
        XCTAssertTrue(defaults.bool(forKey: BypassNew.key))
        XCTAssertTrue(settings.bypassChats)
        XCTAssertEqual(sent().map { "\($0.action) \($0.json)" }, ["bypass-chats {\"on\":\"true\"}"])
        settings.tick(titles: [], at: Self.at)
        XCTAssertEqual(sent().count, 1, "окон нет — слать некому")
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertEqual(sent().last.map { "\($0.action) \($0.json)" }, "bypass-chats {\"on\":\"true\"}")
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(6))
        XCTAssertEqual(sent().filter { $0.action == "bypass-chats" }.count, 2, "тот же состав — повтора нет")

        // Новое поколение страниц (смена pid Claude) получает сохранённое значение.
        let fresh = PageLookSettings(defaults: defaults)
        var again: [Sent] = []
        fresh.write = { action, fields, _ in again.append((action, CommandValue.object(fields).json)); return true }
        fresh.beginGeneration()
        fresh.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(again.filter { $0.action == "bypass-chats" }.map(\.json), ["{\"on\":\"true\"}"])

        settings.setBypassChats(false)
        XCTAssertEqual(sent().last.map { "\($0.action) \($0.json)" }, "bypass-chats {\"on\":\"false\"}")
        settings.tick(titles: ["Б"], at: Self.at.addingTimeInterval(20))
        XCTAssertEqual(sent().last.map { "\($0.action) \($0.json)" }, "bypass-chats {\"on\":\"false\"}",
                       "выключенный выбор тоже повторяется: ключ есть")
    }

    func testSidePaddingCeilingIs40() {
        XCTAssertEqual(LiveStyle.maxSidePadding, 40)
        XCTAssertEqual(LiveStyle.clamp(40), 40)
        XCTAssertEqual(LiveStyle.clamp(41), 40)
        XCTAssertEqual(LiveStyle.clamp(32), 32)
        XCTAssertEqual(LiveStyle.clamp(-1), 0)
        XCTAssertEqual(LiveStyle.defaultSidePadding, 24, "умолчание прежнее")
    }
}
