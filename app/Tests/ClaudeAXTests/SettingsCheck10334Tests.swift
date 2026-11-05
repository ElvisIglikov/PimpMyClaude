import XCTest
@testable import ClaudeAX

/// #10334 — проверка всех настроек: починки по итогам (отчёт о проверке настроек в `docs/`).
/// 1. «Прятать инструменты» повторяется каждому новому поколению страниц, как `text-justify`: выбор, сделанный при
///    закрытом Claude, раньше до страниц не доходил (лоадер не шлёт команду, записанную до его запуска).
/// 2. Выбор задержки и клавиш, которого в панели больше нет (3 с, Enter «ничего», ⇧Enter «отправить»), на запуске
///    встаёт в ближайший из тех, что есть.
final class SettingsCheck10334Tests: XCTestCase {
    private typealias Sent = (action: String, json: String)

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

    private static let at = Date(timeIntervalSince1970: 1_790_400_000)

    private func hide(_ sent: [Sent]) -> [String] {
        sent.filter { $0.action == "hide-tools" }.map(\.json)
    }

    func testHideToolsWithoutChoiceStaysSilent() {
        let (settings, defaults, sent) = makeSettings()
        settings.beginGeneration()
        for n in 0..<4 { settings.tick(titles: ["\(n)"], at: Self.at.addingTimeInterval(Double(n) * 6)) }
        XCTAssertTrue(hide(sent()).isEmpty, "ключа нет — страница прячет сама, слать нечего")
        XCTAssertNil(defaults.object(forKey: ClaudeActions.hideToolsKey), "тики ключ не создают")
    }

    func testHideToolsChoiceRepeatsToNewGeneration() {
        let (settings, defaults, sent) = makeSettings()
        defaults.set(false, forKey: ClaudeActions.hideToolsKey)
        settings.beginGeneration()
        settings.tick(titles: [], at: Self.at)
        XCTAssertTrue(hide(sent()).isEmpty, "окон нет — слать некому")
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertEqual(hide(sent()), ["{\"on\":\"false\"}"])
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(6))
        XCTAssertEqual(hide(sent()).count, 1, "тот же состав окон — повтора нет")
        for n in 1...5 { settings.tick(titles: ["\(n)"], at: Self.at.addingTimeInterval(Double(n) * 6 + 6)) }
        XCTAssertEqual(hide(sent()).count, 3, "не больше трёх за поколение")

        // Claude перезапустился (или PMP) — новое поколение получает тот же выбор.
        let (fresh, _, again) = makeSettings(defaults)
        fresh.beginGeneration()
        fresh.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(hide(again()), ["{\"on\":\"false\"}"])

        // Выбор в панели (ключ сменился) начинает поколение заново: страницы, пропустившие команду, получат её на
        // ближайшем тике с окнами — и ещё до двух раз при смене состава.
        defaults.set(true, forKey: ClaudeActions.hideToolsKey)
        settings.tick(titles: ["5"], at: Self.at.addingTimeInterval(60))
        XCTAssertEqual(hide(sent()).last, "{\"on\":\"true\"}")
        XCTAssertEqual(hide(sent()).count, 4)
        settings.tick(titles: ["5"], at: Self.at.addingTimeInterval(66))
        XCTAssertEqual(hide(sent()).count, 4, "тот же выбор и состав — повтора нет")
    }

    /// Повтор — тот же провод, что пишет выключатель панели (`ClaudeActions.setHideTools`, К-B1).
    func testHideToolsRepeatWireMatchesSwitch() throws {
        let (settings, defaults, _) = makeSettings()
        defaults.set(false, forKey: ClaudeActions.hideToolsKey)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("s10334-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let channel = CommandChannel(path: dir.appendingPathComponent("command.json"), now: { Date() }, schedule: { _, _ in })
        // В провод — только «hide-tools»: остальные повторы тика (с 03.11.2026 и Bypass без выбора) встали бы перед ним.
        settings.write = { action, fields, priority in
            action == "hide-tools" ? channel.write(action: action, fields: fields, priority: priority) : true
        }
        settings.beginGeneration()
        settings.tick(titles: ["А"], at: Self.at)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("command.json")))
            as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "hide-tools")
        XCTAssertEqual(json["on"] as? String, "false", "строкой, как у выключателя панели")
    }

    func testLegacyDelayAndKeysMoveToShownChoices() {
        let (settings, defaults, _) = makeSettings()
        defaults.set(["on": true, "seconds": 3], forKey: SendDelaySetting.key)
        defaults.set(EnterKeys.Second.nothing.rawValue, forKey: EnterKeys.secondKey)
        defaults.set(EnterKeys.Shift.send.rawValue, forKey: EnterKeys.shiftKey)
        settings.migrateLegacy()
        XCTAssertEqual(settings.savedSendDelay, SendDelaySetting(on: true, seconds: 2))
        XCTAssertEqual(settings.enterKeys, EnterKeys(second: .cancel, shift: .newline))

        // Выключенная задержка остаётся выключенной — меняются только секунды.
        defaults.set(["on": false, "seconds": 3], forKey: SendDelaySetting.key)
        settings.migrateLegacy()
        XCTAssertEqual(settings.savedSendDelay, SendDelaySetting(on: false, seconds: 2))
    }

    func testMigrationKeepsShownChoicesAndCreatesNothing() {
        let (settings, defaults, sent) = makeSettings()
        settings.migrateLegacy()
        XCTAssertNil(defaults.object(forKey: SendDelaySetting.key), "выбора не было — ключ не появляется")
        XCTAssertNil(defaults.object(forKey: EnterKeys.secondKey))
        XCTAssertNil(defaults.object(forKey: EnterKeys.shiftKey))
        for seconds in [2, 5, 10] {
            defaults.set(["on": true, "seconds": seconds], forKey: SendDelaySetting.key)
            settings.migrateLegacy()
            XCTAssertEqual(settings.savedSendDelay?.seconds, seconds)
        }
        defaults.set(EnterKeys.Second.send.rawValue, forKey: EnterKeys.secondKey)
        defaults.set(EnterKeys.Shift.newline.rawValue, forKey: EnterKeys.shiftKey)
        settings.migrateLegacy()
        XCTAssertEqual(settings.enterKeys, EnterKeys(second: .send, shift: .newline))
        XCTAssertTrue(sent().isEmpty, "перевод только в памяти; страницам выбор уходит повтором поколения")
    }

    /// После перевода новое поколение страниц получает уже показанный выбор: 2 с и «отменяет»/перенос.
    func testMigratedChoiceReachesPagesWithGeneration() {
        let (settings, defaults, sent) = makeSettings()
        defaults.set(["on": true, "seconds": 3], forKey: SendDelaySetting.key)
        defaults.set(EnterKeys.Shift.send.rawValue, forKey: EnterKeys.shiftKey)
        settings.migrateLegacy()
        settings.beginGeneration()
        settings.tick(titles: ["А"], at: Self.at)
        let delay = sent().filter { $0.action == "send-delay" }.map(\.json)
        XCTAssertTrue(delay.contains("{\"on\":true,\"seconds\":2}"), "\(delay)")
        XCTAssertTrue(delay.contains("{\"shift\":\"newline\"}"), "\(delay)")
    }
}
