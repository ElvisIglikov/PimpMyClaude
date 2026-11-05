@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// #11655, находка 3: умолчания 03.11.2026 — только новой установке; у кого Пимп уже стоял — прежние, один раз.
final class KeepOldDefaults11655Tests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = testSuiteName()
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func layout(_ items: [PanelWidgetLayout.Item]) -> String {
        String(data: try! JSONEncoder().encode(items), encoding: .utf8)!
    }

    func testNewInstallGetsNewDefaults() {
        let defaults = suite()
        XCTAssertFalse(KeepOldDefaults.apply(values: [:], installed: nil, defaults: defaults))
        XCTAssertEqual(PanelTypography.saved(defaults), .giant, "новой установке — 49.4")
        XCTAssertNil(defaults.object(forKey: PMPAccent.key), "акцент — умолчание, белый")
        XCTAssertNil(defaults.object(forKey: SendLook.sizeKey), "ракета — умолчание, 150 %")
        XCTAssertTrue(defaults.bool(forKey: KeepOldDefaults.doneKey))
    }

    func testOldInstallKeepsOldDefaultsAndWorkflow() {
        let defaults = suite()
        let saved = layout([PanelWidgetLayout.Item(id: PanelWidget.workflow.rawValue, collapsed: true)])
        defaults.set(saved, forKey: PanelWidgetLayout.key)
        let values: [String: Any] = [PanelWidgetLayout.key: saved, PanelWidgetLayout.orderKey: 4]
        XCTAssertTrue(KeepOldDefaults.apply(values: values, installed: nil, defaults: defaults))
        XCTAssertEqual(PanelTypography.saved(defaults), .newYork, "стоял Пимп — 2.4")
        XCTAssertEqual(defaults.string(forKey: PMPAccent.key), PMPAccent.violet.rawValue, "прежний фиолетовый")
        XCTAssertEqual(defaults.integer(forKey: SendLook.sizeKey), 100, "ракета 100 %")
        XCTAssertEqual(PanelWidgetLayout.load(defaults).item(PanelWidget.workflow.rawValue)?.hidden, false,
                       "Workflow в сохранённой раскладке остался")
        XCTAssertFalse(KeepOldDefaults.apply(values: defaults.dictionaryRepresentation(), installed: nil, defaults: defaults),
                       "второй раз — ничего")
    }

    func testChosenValuesStay() {
        let defaults = suite()
        let values: [String: Any] = [PanelTypography.key: "49.2", PMPAccent.key: "teal", SendLook.sizeKey: 120]
        defaults.setValuesForKeys(values)
        KeepOldDefaults.apply(values: values, installed: nil, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: PanelTypography.key), "49.2")
        XCTAssertEqual(defaults.string(forKey: PMPAccent.key), "teal")
        XCTAssertEqual(defaults.integer(forKey: SendLook.sizeKey), 120)
    }

    func testPatchedOnlyCountsAsOld() {
        let defaults = suite()
        XCTAssertTrue(KeepOldDefaults.apply(values: [:], installed: Data("{}".utf8), defaults: defaults),
                      "настроек нет, а Claude этим Пимпом патчили — Пимп стоял")
        XCTAssertEqual(PanelTypography.saved(defaults), .newYork)
    }

    func testOlyaBuildAlreadyLivedWithNewDefaults() {
        let defaults = suite()
        let values: [String: Any] = [PanelWidgetLayout.workflowHiddenKey: true, PanelWidgetLayout.orderKey: 4]
        XCTAssertFalse(KeepOldDefaults.apply(values: values, installed: nil, defaults: defaults))
        XCTAssertEqual(PanelTypography.saved(defaults), .giant, "сборка Оли — умолчания 03.11 остаются")
    }
}
