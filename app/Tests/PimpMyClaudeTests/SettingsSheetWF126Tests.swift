import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// Сводки групп листа «Настройки» (WF126 §7): справа у группы — что выбрано сейчас.
final class SettingsSheetWF126Tests: XCTestCase {
    private func toggle(_ id: String, on: Bool, access: Bool = false) -> PanelToggle {
        PanelToggle(id: id, title: id, on: on, needsAccess: access, toolTip: "")
    }

    func testSummaries() {
        XCTAssertEqual(SettingsText.enter(SendDelaySetting(on: true, seconds: 3)), "3 с")
        XCTAssertEqual(SettingsText.enter(SendDelaySetting(on: false, seconds: 5)), "нет")
        XCTAssertEqual(SettingsText.chats(bypass: true), "Bypass")
        XCTAssertEqual(SettingsText.chats(bypass: false), "", "ответов из панели нет (#9023) — и строки ответа нет")
        // WF245: выключателя таймера нет (таймеров у закреплённых нет с page-64) — сводка только о проекте.
        XCTAssertEqual(SettingsText.pinned(PinnedLook()), "с проектом")
        XCTAssertEqual(SettingsText.pinned(PinnedLook(folder: false)), "без проекта")
    }

    func testWindowsGroupLeavesMoreTogglesOut() {
        let toggles = [toggle(AutomationDefaults.allowOnceKey, on: false), toggle(AutomationDefaults.continueKey, on: false),
                       toggle("menu", on: true), toggle("quit", on: true), toggle("login", on: false)]
        XCTAssertEqual(SettingsText.windowToggles(toggles).map { $0.id }, ["menu", "quit", "login"])
        XCTAssertEqual(SettingsText.windows(toggles), "включено 2 из 3")
        XCTAssertEqual(SettingsText.windows(Array(toggles.prefix(4))), "всё включено")
        XCTAssertEqual(SettingsText.windows(toggles + [toggle("beacon", on: true, access: true)]), "нужен доступ")
    }

    func testUpdatesLine() {
        XCTAssertEqual(SettingsText.updates(.none, patch: .installed(version: "2.19675.0", loader: 8)), "Claude 2.19675.0")
        XCTAssertEqual(SettingsText.update(.ready(version: "2.19675.1", question: nil)).text, "скачалась 2.19675.1")
        XCTAssertTrue(SettingsText.update(.ready(version: "2.19675.1", question: nil)).ready)
        XCTAssertFalse(SettingsText.update(.available(version: "2.2", canWrite: true, note: nil)).ready)
    }

    /// «Обновить» в группе при идущих чатах: вопрос живёт только на листе «Панель» — туда и уводим.
    func testUpdateWithQuestionGoesToPanel() {
        let block = PimpPanelText.UpdateBlock.ready(version: "2.19675.1", question: "Идут чаты — обновить всё равно?")
        XCTAssertTrue(SettingsText.update(block).ready)
        XCTAssertEqual(SettingsText.update(block).text, "скачалась 2.19675.1")
        let model = PanelModel()
        model.update = block
        model.sheet = .settings
        model.settingsGroup = .updates
        var pressed = 0
        model.actions.update = {
            XCTAssertEqual(model.sheet, .panel)
            pressed += 1
        }
        SettingsSheet.pressUpdate(model)
        XCTAssertEqual(pressed, 1)
        XCTAssertEqual(model.sheet, .panel)
        XCTAssertNil(model.settingsGroup)
    }

    func testPermissionLine() {
        XCTAssertEqual(SettingsText.permission(.allowed).text, "✓ Режим разрешён в Claude")
        XCTAssertTrue(SettingsText.permission(.notAllowed).link)
        XCTAssertFalse(SettingsText.permission(.blockedByOrg).link)
        XCTAssertEqual(SettingsText.permission(.unknown).text, "Проверю, когда Claude запустится")
    }
}
