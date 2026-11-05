import XCTest
@testable import ClaudeAX

/// #7976 — «Прятать код и планы» повторяется каждому новому поколению страниц, как «Прятать инструменты» (#10334):
/// выбор, сделанный при закрытом Claude, и новые окна раньше команду `hide-code` не получали.
final class HideCodeRepeat7976Tests: XCTestCase {
    private typealias Sent = (action: String, json: String)
    private static let at = Date(timeIntervalSince1970: 1_790_400_000)

    private func makeSettings(_ defaults: UserDefaults? = nil) -> (PageLookSettings, UserDefaults, () -> [Sent]) {
        let store: UserDefaults
        if let defaults = defaults {
            store = defaults
        } else {
            let suite = testSuiteName()
            store = UserDefaults(suiteName: suite)!
            addTeardownBlock { store.removePersistentDomain(forName: suite) }
        }
        let settings = PageLookSettings(defaults: store)
        var sent: [Sent] = []
        settings.write = { action, fields, _ in
            sent.append((action, CommandValue.object(fields).json))
            return true
        }
        return (settings, store, { sent })
    }

    private func code(_ sent: [Sent]) -> [String] { sent.filter { $0.action == "hide-code" }.map(\.json) }

    func testWithoutChoiceStaysSilent() {
        let (settings, defaults, sent) = makeSettings()
        settings.beginGeneration()
        for n in 0..<4 { settings.tick(titles: ["\(n)"], at: Self.at.addingTimeInterval(Double(n) * 6)) }
        XCTAssertTrue(code(sent()).isEmpty, "ключа нет — выключено, слать нечего")
        XCTAssertNil(defaults.object(forKey: ClaudeActions.hideCodeKey), "тики ключ не создают")
    }

    func testChoiceRepeatsToNewGenerationAndOnChange() {
        let (settings, defaults, sent) = makeSettings()
        defaults.set(true, forKey: ClaudeActions.hideCodeKey)
        settings.beginGeneration()
        settings.tick(titles: [], at: Self.at)
        XCTAssertTrue(code(sent()).isEmpty, "окон нет — слать некому")
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertEqual(code(sent()), ["{\"on\":\"true\"}"])
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(6))
        XCTAssertEqual(code(sent()).count, 1, "тот же состав окон — повтора нет")

        // Claude перезапустился — новое поколение получает тот же выбор.
        let (fresh, _, again) = makeSettings(defaults)
        fresh.beginGeneration()
        fresh.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(code(again()), ["{\"on\":\"true\"}"])

        // Выбор в панели сменился — поколение заново, новое значение уходит на ближайшем тике.
        defaults.set(false, forKey: ClaudeActions.hideCodeKey)
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(60))
        XCTAssertEqual(code(sent()).last, "{\"on\":\"false\"}")
    }

    /// Повтор — тот же провод, что у выключателя (`ClaudeActions.setHideCode`): действие `hide-code`, `on` строкой.
    func testRepeatDoesNotTouchHideTools() {
        let (settings, defaults, sent) = makeSettings()
        defaults.set(true, forKey: ClaudeActions.hideCodeKey)
        settings.beginGeneration()
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertTrue(sent().filter { $0.action == "hide-tools" }.isEmpty, "ключа «Прятать инструменты» нет — его не шлём")
    }
}
