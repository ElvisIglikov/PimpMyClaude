import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// Проверяем привязку настоящей строки SwiftUI, без окон и живого AppDelegate. Выключатель вернулся словом Элвиса
/// 16.10.2026 (#9998) со своим ключом: старый `autoAllowEnabled` — примета старой установки.
final class AutoAllowPanelTests: XCTestCase {
    func testOwnKeyOffByDefaultAndSummary() throws {
        XCTAssertNotEqual(AutomationDefaults.allowOnceKey, AutomationDefaults.allowKey,
                          "старый ключ у старых установок стоит true сам — выключатель не должен включиться без выбора")
        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        AutomationDefaults.migrate(defaults, values: ["setupWindowSeen": true], legacyPatched: true)
        XCTAssertTrue(defaults.bool(forKey: AutomationDefaults.allowKey), "миграция старой установки — как раньше")
        XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.allowOnceKey), "новый выключатель — выключен")
        XCTAssertEqual(SettingsText.more(autoAllow: true), "Allow — сам")
        XCTAssertEqual(SettingsText.more(autoAllow: false), "")
        XCTAssertTrue(SettingsText.autoAllowHelp.contains("Bypass permissions"))
        XCTAssertEqual(SettingsText.autoAllowTitle, "Сам нажимать «Allow once»")
    }

    @MainActor
    func testSettingsAutoAllowUsesSharedKeyAndRefreshesBothWays() throws {
        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PanelModel()
        model.sheet = .settings
        func refresh() {
            model.toggles = [PanelToggle(id: AutomationDefaults.allowOnceKey, title: "Авто-Allow",
                                        on: defaults.bool(forKey: AutomationDefaults.allowOnceKey),
                                        needsAccess: false, toolTip: "Разовый Allow")]
        }
        var pressed: [String] = []
        model.actions.toggle = { key in
            pressed.append(key)
            defaults.set(!defaults.bool(forKey: key), forKey: key)
            refresh()
        }
        refresh()
        let row = SettingsSheet(model: model)
        XCTAssertEqual(try XCTUnwrap(row.autoAllowToggle).id, AutomationDefaults.allowOnceKey)
        XCTAssertFalse(row.autoAllowBinding.wrappedValue)
        row.autoAllowBinding.wrappedValue = true
        XCTAssertEqual(pressed, [AutomationDefaults.allowOnceKey])
        XCTAssertTrue(defaults.bool(forKey: AutomationDefaults.allowOnceKey))
        XCTAssertTrue(row.autoAllowBinding.wrappedValue)
        row.autoAllowBinding.wrappedValue = true
        XCTAssertEqual(pressed.count, 1, "Повторное значение не переворачивает переключатель")
        row.autoAllowBinding.wrappedValue = false
        XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.allowOnceKey))
        XCTAssertFalse(row.autoAllowBinding.wrappedValue)
        XCTAssertEqual(pressed, [AutomationDefaults.allowOnceKey, AutomationDefaults.allowOnceKey])
        // Обновление того же ключа извне (правое меню) отражается в этой же строке.
        defaults.set(true, forKey: AutomationDefaults.allowOnceKey)
        refresh()
        XCTAssertTrue(row.autoAllowBinding.wrappedValue)
        XCTAssertEqual(pressed.count, 2, "Обновление состояния не вызывает обратное переключение")
    }

    @MainActor
    func testMissingAutoAllowRowDoesNotToggleAnotherSetting() {
        let model = PanelModel()
        model.toggles = [PanelToggle(id: AutomationDefaults.continueKey, title: "Продолжать",
                                    on: true, needsAccess: false, toolTip: "")]
        var pressed: [String] = []
        model.actions.toggle = { pressed.append($0) }
        let row = SettingsSheet(model: model)
        XCTAssertNil(row.autoAllowToggle)
        row.autoAllowBinding.wrappedValue = true
        XCTAssertTrue(pressed.isEmpty)
        XCTAssertTrue(model.toggles[0].on)
    }
}
