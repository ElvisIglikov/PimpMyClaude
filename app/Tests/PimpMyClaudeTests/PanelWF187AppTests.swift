@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF187 (#9247, #9250, слово Элвиса 09.10 03:35): «Токены» — число целиком, у линии подпись «7 дней»; одинокая
/// половинка ряда — во всю ширину. Значки управления по наведению сняты 22.10.2026 (файл 53: шеврон, правка, меню).
final class PanelWF187AppTests: XCTestCase {
    func testTokensNumberWholeAndSparkCaption() {
        XCTAssertEqual(TokenStats.human(944_000_000), "944 млн")
        XCTAssertEqual(TokenStats.human(1_234_000_000), "1,2 млрд")
        XCTAssertEqual(TokenSpark(values: [1, 2, 944_000_000], scanned: nil).todayText, "944 млн")
        XCTAssertEqual(TokensTileText.sparkCaption, "7 дней")
        XCTAssertEqual(TokensTileText.help(TokenSpark(values: [1, 2, 3], scanned: nil), collected: ""),
                       "Токены по дням за 7 дней, справа — сегодня")
        XCTAssertFalse(TokensTileText.help(TokenSpark(values: [1, 2, 3], scanned: nil), collected: "").contains("…"))
    }

    func testLoneHalfTakesFullWidth() {
        let placed = WidgetGrid.frames([[("week", false, 120), ("limits", false, 90)],
                                        [("fable", false, 84)],
                                        [("tokens", true, 36)]],
                                       width: 316, gap: 8, spacing: 10)
        XCTAssertEqual(placed.frames["week"]?.width, 154)
        XCTAssertEqual(placed.frames["fable"]?.width, 316, "«Fable» без пары — во всю ширину")
        XCTAssertEqual(placed.frames["fable"]?.minX, 0)
        // Сохранённая раскладка не меняется: блок остаётся половинкой и встанет в пару, когда сосед вернётся.
        var layout = PanelWidgetLayout.standard
        layout.setHidden(PanelWidget.reset.rawValue, true)
        let rows = layout.rows(visible: Set(PanelWidget.allCases.map { $0.rawValue }))
        let lone = rows.filter { $0.count == 1 }.flatMap { $0 }.filter { !$0.wide }
        // #10461: «Неделя» встаёт к «5 часам», пары сдвигаются, без пары остаётся «Оформление».
        XCTAssertEqual(lone.map { $0.id }, [PanelWidget.colors.rawValue])
        XCTAssertEqual(layout.item(PanelWidget.colors.rawValue)?.wide, false)
    }
}
