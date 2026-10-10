import XCTest
@testable import ClaudeAX

/// WF171 (#9177): панель у часов лёгкая — «Идут Workflow», «Workflow списком» и «Остальные проекты» сняты
/// из виджетов и из старых раскладок; сводка проектов для значка у часов осталась.
final class PanelWF171Tests: XCTestCase {
    private static let removed = ["tiles", "workflows", "projects"]

    func testProjectWidgetsGoneRestStay() {
        let ids = PanelWidget.allCases.map { $0.rawValue }
        // WF214 (#9404, слово Элвиса 10.10): «Идёт Workflow сейчас» вернулся кольцами — новым id `workflow`.
        XCTAssertEqual(ids, ["workflow", "week", "limits", "fable", "reset", "temperature", "memory", "tokens", "colors"])
        for id in Self.removed { XCTAssertNil(PanelWidget(rawValue: id), id) }
        XCTAssertFalse(PanelWidget.allCases.map { $0.title }.contains { $0.contains("списком") || $0.contains("проекты") })
        XCTAssertEqual(Set(PanelWidgetLayout.standard.items.map { $0.id }), Set(ids))
    }

    func testOldSavedLayoutDropsThem() {
        let name = "PanelWF171Tests"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        defer { store.removePersistentDomain(forName: name) }
        // Раскладка до WF171: плитки Workflow наверху, список узким, проекты между цветами и неделей.
        store.set(#"[{"id":"tiles","wide":true},{"id":"colors","wide":true},{"id":"projects","wide":false},"#
                  + #"{"id":"week","wide":false},{"id":"workflows","wide":true},{"id":"limits","wide":false}]"#,
                  forKey: PanelWidgetLayout.key)
        var layout = PanelWidgetLayout.load(store)
        XCTAssertEqual(layout.items.map { $0.id },
                       ["workflow", "week", "limits", "fable", "reset", "temperature", "memory", "tokens", "colors"],
                       "WF177: при первом чтении «Цвет Claude» переезжает вниз; WF214: новый блок — сверху")
        XCTAssertEqual(layout.item("week")?.wide, false, "свои настройки остальных виджетов целы")
        XCTAssertEqual(layout.item("limits")?.wide, false)
        XCTAssertEqual(layout.rows(visible: Set(Self.removed + ["week", "limits"])).map { $0.map { $0.id } },
                       [["week", "limits"]], "снятые в ряды не попадают")
        XCTAssertFalse(layout.move("tiles", over: "colors"), "снятый не двигается")
    }

    func testIconSummaryStillWorks() {
        // Значок у часов (WF129 П2) — сводка проектов не тронута.
        XCTAssertEqual(PanelTiles.summary([]), "—")
        XCTAssertEqual(PanelTiles.summaryHelp([]), "PMP — Workflow сейчас не идут")
    }
}
