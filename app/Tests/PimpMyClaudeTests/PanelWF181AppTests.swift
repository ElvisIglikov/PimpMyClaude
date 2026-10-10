import XCTest
@testable import PimpMyClaude

/// WF181 (#9217, слово Элвиса 09.10 03:05: недельный блок стоял криво по высоте — «по высоте все элементы одинаковые»):
/// карточки одного ряда — одной высоты, по самой высокой.
final class PanelWF181AppTests: XCTestCase {
    func testRowCardsShareTallestHeight() {
        let placed = WidgetGrid.frames([[("week", false, 120), ("reset", false, 70)],
                                        [("limits", false, 90), ("fable", false, 84)],
                                        [("colors", true, 50)]],
                                       width: 316, gap: 8, spacing: 10)
        XCTAssertEqual(placed.frames["week"]?.height, 120)
        XCTAssertEqual(placed.frames["reset"]?.height, 120, "«Сброс» — до высоты «Недели»")
        XCTAssertEqual(placed.frames["reset"]?.minY, placed.frames["week"]?.minY)
        XCTAssertEqual(placed.frames["limits"]?.height, placed.frames["fable"]?.height)
        XCTAssertEqual(placed.frames["limits"]?.minY, 130)
        XCTAssertEqual(placed.frames["reset"]?.minX, 162)
        XCTAssertEqual(placed.frames["colors"]?.width, 316)
        XCTAssertEqual(placed.height, 120 + 10 + 90 + 10 + 50)
    }

    /// Раскрытый график (память) — ряд не выравнивается: температура рядом не тянется пустой коробкой.
    func testOpenChartRowStaysLoose() {
        let placed = WidgetGrid.frames([[("temperature", false, 36), ("memory", false, 210)], [("tokens", true, 36)]],
                                       width: 316, gap: 8, spacing: 10, loose: ["memory"])
        XCTAssertEqual(placed.frames["temperature"]?.height, 36)
        XCTAssertEqual(placed.frames["memory"]?.height, 210)
        XCTAssertEqual(placed.frames["tokens"]?.minY, 220, "следующий ряд — под самым высоким")
    }
}
