@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// #10993 (слово Элвиса 27.10.2026): блоки одной строки сетки («Неделя · Сброс», «5 часов · Fable») сворачиваются и
/// разворачиваются вместе; кнопка шапки на виде по умолчанию — «Развернуть» (все блоки), всё развёрнуто — «Свернуть»
/// к виду по умолчанию; «Проц» → «Процессор».
final class PanelPairs10993Tests: XCTestCase {
    private let all = Set(PanelWidget.allCases.map { $0.rawValue })

    private func folds(_ layout: PanelWidgetLayout) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: layout.items.map { ($0.id, $0.collapsed) })
    }

    func testRowMatesFollowGridRows() {
        let layout = PanelWidgetLayout.standard
        XCTAssertEqual(layout.rowMates("week", visible: all), ["week", "reset"])
        XCTAssertEqual(layout.rowMates("reset", visible: all), ["week", "reset"])
        XCTAssertEqual(layout.rowMates("fable", visible: all), ["limits", "fable"])
        XCTAssertEqual(layout.rowMates("workflow", visible: all), ["workflow"], "во всю ширину — один")
        // «Сброса» нет (срок неизвестен) — «Неделя» встаёт в ряд с «5 часов»: пара — по видимым.
        XCTAssertEqual(layout.rowMates("week", visible: all.subtracting(["reset"])), ["week", "limits"])
        XCTAssertEqual(layout.rowMates("gone", visible: all), ["gone"])
        XCTAssertEqual(layout.rowMates("week", visible: []), ["week"], "вне сетки — только он")
    }

    func testSetRowCollapsedFoldsBothHalves() {
        var layout = PanelWidgetLayout.standard
        layout.setRowCollapsed("week", true, visible: all)
        XCTAssertEqual(layout.item("week")?.collapsed, true)
        XCTAssertEqual(layout.item("reset")?.collapsed, true, "сброс сворачивается с неделей")
        layout.setRowCollapsed("limits", false, visible: all)
        XCTAssertEqual(layout.item("limits")?.collapsed, false)
        XCTAssertEqual(layout.item("fable")?.collapsed, false, "Fable разворачивается с «5 часов»")
        XCTAssertEqual(layout.item("temperature")?.collapsed, true, "чужой ряд не трогаем")
    }

    func testHeaderButtonUnfoldsThenFoldsBackToDefault() {
        var layout = PanelWidgetLayout.standard
        XCTAssertTrue(layout.anyCollapsed(visible: all), "вид по умолчанию — кнопка «Развернуть»")
        layout.setAllCollapsed(false, visible: all)
        XCTAssertFalse(layout.anyCollapsed(visible: all), "всё развёрнуто — кнопка «Свернуть»")
        layout.setDefaultFolds(visible: all)
        XCTAssertEqual(layout, .standard, "«Свернуть» — назад к виду по умолчанию, не всё в строки")
    }

    func testDefaultFoldsKeepHiddenInvisibleAndPairs() {
        var layout = PanelWidgetLayout.unfolded
        layout.setHidden("tokens", true)
        let visible = all.subtracting(["fable"])
        layout.setDefaultFolds(visible: visible)
        XCTAssertEqual(layout.item("tokens")?.collapsed, false, "скрытый не трогаем")
        XCTAssertEqual(layout.item("fable")?.collapsed, false, "невидимый не трогаем")
        XCTAssertEqual(layout.item("week")?.collapsed, false)
        XCTAssertEqual(layout.item("temperature")?.collapsed, true)
        // Переставили: «Неделя» в паре с «5 часов» — ряд развёрнут целиком, не половиной.
        var moved = PanelWidgetLayout.unfolded
        moved.move("limits", over: "reset")
        moved.setDefaultFolds(visible: all)
        XCTAssertEqual(moved.rowMates("week", visible: all), ["week", "limits"])
        XCTAssertEqual(moved.item("limits")?.collapsed, false)
    }

    func testCpuTitleIsFullWord() {
        XCTAssertEqual(PanelWidget.cpu.title, "Процессор")
        // Длинное имя не мельчит подписи всей панели (#10704): общую долю ужатия «Процессор» не задаёт.
        XCTAssertEqual(CollapsedWidget.ownScale, [.cpu])
    }

    /// Модель: шеврон, нажатие по строке и кнопка шапки — парами (то, что делают `WidgetCell` и шапка).
    func testModelFoldsPairsAndHeader() {
        let model = PanelWF253Scenes.elvis(now: Date())
        model.reduceMotion = true
        model.layout = .standard
        defer { PanelWidgetLayout.standard.save() }
        model.toggleRow("week", visible: all)
        XCTAssertFalse(model.opened(.week))
        XCTAssertFalse(model.opened(.reset), "сброс свернулся вместе с неделей")
        model.widgetDragEnded = .distantPast
        model.tapRow("reset", visible: all)
        XCTAssertTrue(model.opened(.week) && model.opened(.reset), "нажатие по строке — оба развёрнуты")
        model.widgetDragEnded = .distantPast
        model.tapRow("fable", visible: all)
        XCTAssertTrue(model.opened(.limits) && model.opened(.fable), "5 часов и Fable — вместе")
        model.setAllCollapsed(false, visible: all)
        XCTAssertFalse(model.layout.anyCollapsed(visible: all))
        model.workflowOpen = true
        model.foldToDefault(visible: all)
        XCTAssertEqual(folds(model.layout), folds(.standard), "«Свернуть» — вид по умолчанию")
        XCTAssertFalse(model.workflowOpen, "Workflow сворачивается как прежде")
    }
}
