import XCTest
@testable import ClaudeAX

/// WF269 (#10205): свёрнутые блоки панели — в раскладке, «Свернуть всё», ряды.
final class PanelWF269CollapseTests: XCTestCase {
    private let all = Set(PanelWidget.allCases.map { $0.rawValue })

    func testCollapsedWrittenOnlyWhenTrueAndReadBack() throws {
        var layout = PanelWidgetLayout.unfolded
        layout.setCollapsed("week", true)
        let data = try JSONEncoder().encode(layout.items)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "collapsed").count - 1, 1)
        let back = try JSONDecoder().decode([PanelWidgetLayout.Item].self, from: data)
        XCTAssertEqual(PanelWidgetLayout(items: back), layout)
        XCTAssertTrue(back.first { $0.id == "week" }?.collapsed == true)
        // Старая раскладка без ключа — не свёрнута.
        let old = try JSONDecoder().decode([PanelWidgetLayout.Item].self, from: Data(#"[{"id":"memory","wide":false}]"#.utf8))
        XCTAssertFalse(old[0].collapsed)
    }

    func testSaveLoadAndStandardReset() {
        let defaults = UserDefaults(suiteName: testSuiteName())!
        var layout = PanelWidgetLayout.standard
        // #10461: в умолчании развёрнуты только «Неделя» и «Сброс».
        // «Неделя» свёрнута с соседом по ряду: пара вразнобой при чтении разворачивается (#11276).
        layout.setCollapsed("week", true)
        layout.setCollapsed("reset", true)
        XCTAssertFalse(layout.isStandard)
        layout.save(defaults)
        XCTAssertEqual(PanelWidgetLayout.load(defaults).item("week")?.collapsed, true)
        PanelWidgetLayout.standard.save(defaults)
        XCTAssertEqual(PanelWidgetLayout.load(defaults).item("week")?.collapsed, false)
    }

    func testCollapseAllAndExpandAll() {
        var layout = PanelWidgetLayout.unfolded
        layout.setHidden("tokens", true)
        let visible = all.subtracting(["fable"])
        XCTAssertTrue(layout.anyExpanded(visible: visible))
        layout.setAllCollapsed(true, visible: visible)
        XCTAssertFalse(layout.anyExpanded(visible: visible))
        XCTAssertEqual(layout.item("fable")?.collapsed, false, "невидимый не трогаем")
        XCTAssertEqual(layout.item("tokens")?.collapsed, false, "скрытый не трогаем")
        layout.setCollapsed("week", false)
        XCTAssertTrue(layout.anyExpanded(visible: visible))
        layout.setAllCollapsed(false, visible: visible)
        XCTAssertTrue(layout.items.allSatisfy { !$0.collapsed })
    }

    func testCollapsedBeatsExpandedGraphInRows() {
        var layout = PanelWidgetLayout.unfolded
        let visible: Set<String> = ["temperature", "memory"]
        XCTAssertEqual(layout.rows(visible: visible, expanded: ["temperature"]).map { $0.map(\.id) },
                       [["temperature"], ["memory"]])
        layout.setCollapsed("temperature", true)
        XCTAssertEqual(layout.rows(visible: visible, expanded: ["temperature"]).map { $0.map(\.id) },
                       [["temperature", "memory"]])
    }
}
