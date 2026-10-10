import XCTest
@testable import ClaudeAX

/// Лист «Настройки» WF126 (`docs/wf126-spec.md` §7.2–7.3 и поправки критика 1–6): второй Enter и ⇧Enter
/// полями `send-delay`, Bypass в черновиках PMP (`mode` у `draft-setup`), чтение разрешения Bypass из
/// файла настроек Claude. UserDefaults — своя папка, команды — в память.
final class EnterBypassWF126Tests: XCTestCase {
    private typealias Sent = (action: String, json: String)
    private static let at = Date(timeIntervalSince1970: 1_791_000_000)

    private func makeSettings() -> (PageLookSettings, UserDefaults, () -> [Sent]) {
        let suite = "wf126-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = PageLookSettings(defaults: defaults)
        var sent: [Sent] = []
        settings.write = { action, fields, _ in
            sent.append((action, CommandValue.object(fields).json))
            return true
        }
        return (settings, defaults, { sent })
    }

    // MARK: - клавиши отсчёта

    /// Подпись превью — ровно `sendDelayLabel` страницы (поправка критика 3).
    func testLabelMatchesPage() {
        XCTAssertEqual(EnterKeys(shift: .send).label(left: 3), "Отправка через 3 · Enter или Esc — отмена · ⇧Enter — сразу")
        XCTAssertEqual(EnterKeys().shift, .newline, "WF192: ⇧Enter по умолчанию — перенос")
        XCTAssertEqual(EnterKeys(second: .cancel, shift: .newline).label(left: 3), "Отправка через 3 · Enter или Esc — отмена")
        XCTAssertEqual(EnterKeys(second: .send).label(left: 5), "Отправка через 5 · Enter — сразу · Esc — отмена")
        XCTAssertEqual(EnterKeys(second: .send, shift: .newline).label(left: 5), "Отправка через 5 · Enter — сразу · Esc — отмена")
        XCTAssertEqual(EnterKeys(second: .nothing, shift: .send).label(left: 10), "Отправка через 10 · ⇧Enter — сразу · Esc — отмена")
        XCTAssertEqual(EnterKeys(second: .nothing, shift: .newline).label(left: 10), "Отправка через 10 · Esc — отмена")
        XCTAssertEqual(EnterKeys.Second.nothing.rawValue, "none", "значение страницы — none")
    }

    func testNoChoiceSendsNothingAndReadsDefaults() {
        let (settings, defaults, sent) = makeSettings()
        XCTAssertEqual(settings.enterKeys, EnterKeys(second: .cancel, shift: .newline))
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertTrue(sent().filter { $0.action == "send-delay" }.isEmpty, "выбора нет — отсчёта страницам не шлём")
        XCTAssertNil(defaults.object(forKey: EnterKeys.secondKey))
        XCTAssertNil(defaults.object(forKey: EnterKeys.shiftKey))
    }

    func testChoiceSendsOnlyChangedFieldAndRepeatsBoth() {
        let (settings, defaults, sent) = makeSettings()
        settings.setEnterKeys(second: .nothing)
        XCTAssertEqual(sent().last?.action, "send-delay")
        XCTAssertEqual(sent().last?.json, #"{"second":"none"}"#, "секунды и вкл. не трогаем")
        XCTAssertEqual(defaults.string(forKey: EnterKeys.secondKey), "none")
        XCTAssertNil(defaults.object(forKey: EnterKeys.shiftKey))
        settings.setEnterKeys(shift: .newline)
        XCTAssertEqual(sent().last?.json, #"{"shift":"newline"}"#)
        XCTAssertEqual(PageLookSettings(defaults: defaults).enterKeys, EnterKeys(second: .nothing, shift: .newline))
        let before = sent().count
        settings.setEnterKeys()
        XCTAssertEqual(sent().count, before, "пустой выбор — без команды")
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertEqual(sent().last { $0.action == "send-delay" }?.json, #"{"second":"none","shift":"newline"}"#,
                       "новое поколение узнаёт оба выбора")
        // Чужое значение в UserDefaults — умолчание, не падение.
        defaults.set("jump", forKey: EnterKeys.shiftKey)
        XCTAssertEqual(PageLookSettings(defaults: defaults).enterKeys.shift, .newline)
    }

    func testTimingRepeatStaysWithoutKeys() {
        let (settings, _, sent) = makeSettings()
        settings.setSendDelay(on: true, seconds: 5)
        settings.setEnterKeys(second: .send)
        settings.beginGeneration()
        settings.tick(titles: ["А"], at: Self.at)
        let delays = sent().filter { $0.action == "send-delay" }.map { $0.json }
        XCTAssertTrue(delays.contains(#"{"on":true,"seconds":5}"#))
        XCTAssertTrue(delays.contains(#"{"second":"send"}"#))
        XCTAssertFalse(delays.contains { $0.contains("seconds") && $0.contains("second\"") }, "поля не смешиваются")
    }

    // MARK: - Bypass

    func testDraftSetupModeLastOnlyWhenOn() {
        let on = BlankWindow.draftSetupFields(folder: "/Users/dev/Projects/Rick", model: "Opus 5.5",
                                              effort: "High", text: "привет", bypass: true)
        XCTAssertEqual(CommandValue.object(on).json,
                       #"{"scope":"window","title":"","draft":true,"folder":"/Users/dev/Projects/Rick","model":"Opus 5.5","effort":"High","text":"привет","mode":"bypass"}"#)
        let off = BlankWindow.draftSetupFields(folder: nil, model: nil, effort: nil)
        XCTAssertEqual(CommandValue.object(off).json, #"{"scope":"window","title":"","draft":true}"#)
    }

    func testPermissionFromClaudeConfig() {
        func check(_ json: String?) -> BypassNew.Permission { BypassNew.permission(config: json.map { Data($0.utf8) }) }
        XCTAssertEqual(check(nil), .unknown, "файла нет")
        XCTAssertEqual(check("не json"), .unknown)
        XCTAssertEqual(check(#"{"mcpServers":{}}"#), .notAllowed, "ключей нет — не разрешён")
        XCTAssertEqual(check(#"{"preferences":{"bypassPermissionsOptInByAccount":{"a":false,"b":true}}}"#), .allowed)
        XCTAssertEqual(check(#"{"preferences":{"bypassPermissionsOptInByAccount":{"a":false}}}"#), .notAllowed)
        XCTAssertEqual(check(#"{"preferences":{"bypassPermissionsOptInByAccount":{"a":true},"bypassPermissionsGateByAccount":{"a":false}}}"#),
                       .blockedByOrg, "запрет организации сильнее согласия")
        XCTAssertEqual(check(#"{"preferences":{"bypassPermissionsOptInByAccount":{"a":true},"bypassPermissionsGateByAccount":{"a":true}}}"#),
                       .allowed)
        XCTAssertEqual(check(#"{"preferences":{"bypassPermissionsModeEnabled":true}}"#), .notAllowed,
                       "ключа bypassPermissionsModeEnabled нет в живом файле — не читаем (поправка критика 6)")
    }

    func testSettingsMenuTitle() {
        XCTAssertTrue(ClaudeActions.isSettingsTitle("Settings…"))
        XCTAssertTrue(ClaudeActions.isSettingsTitle("Settings..."))
        XCTAssertTrue(ClaudeActions.isSettingsTitle("Preferences…"))
        XCTAssertFalse(ClaudeActions.isSettingsTitle("Settings Sync"))
        XCTAssertFalse(ClaudeActions.isSettingsTitle("About Claude"))
    }
}
