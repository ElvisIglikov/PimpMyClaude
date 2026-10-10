import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// Проверяем привязку настоящей строки SwiftUI, без окон и живого AppDelegate.
final class AutoAllowPanelTests: XCTestCase {
    @MainActor
    func testSettingsAutoAllowUsesSharedKeyAndRefreshesBothWays() throws {
        let suite = "wf121-panel-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PanelModel()
        model.sheet = .settings
        func refresh() {
            model.toggles = [PanelToggle(id: AutomationDefaults.allowKey, title: "Авто-Allow",
                                        on: defaults.bool(forKey: AutomationDefaults.allowKey),
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
        XCTAssertEqual(try XCTUnwrap(row.autoAllowToggle).id, AutomationDefaults.allowKey)
        XCTAssertFalse(row.autoAllowBinding.wrappedValue)
        row.autoAllowBinding.wrappedValue = true
        XCTAssertEqual(pressed, [AutomationDefaults.allowKey])
        XCTAssertTrue(defaults.bool(forKey: AutomationDefaults.allowKey))
        XCTAssertTrue(row.autoAllowBinding.wrappedValue)
        row.autoAllowBinding.wrappedValue = true
        XCTAssertEqual(pressed.count, 1, "Повторное значение не переворачивает переключатель")
        row.autoAllowBinding.wrappedValue = false
        XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.allowKey))
        XCTAssertFalse(row.autoAllowBinding.wrappedValue)
        XCTAssertEqual(pressed, [AutomationDefaults.allowKey, AutomationDefaults.allowKey])
        // Обновление того же ключа извне (правое меню) отражается в этой же строке.
        defaults.set(true, forKey: AutomationDefaults.allowKey)
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
