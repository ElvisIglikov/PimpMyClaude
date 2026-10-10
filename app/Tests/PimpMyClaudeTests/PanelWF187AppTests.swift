@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF187 (#9247, #9250, слово Элвиса 09.10 03:35): значки управления блоком — не на каждое наведение, а через 0,8 с над
/// заголовком; «Токены» — число целиком, у линии подпись «7 дней»; одинокая половинка ряда — во всю ширину.
final class PanelWF187AppTests: XCTestCase {
    private let title = CGRect(x: 12, y: 9, width: 46, height: 16)

    func testChromeWaitsAndFadesQuietly() {
        XCTAssertEqual(WidgetChrome.delay, 0.8, accuracy: 0.001)
        XCTAssertEqual(WidgetChrome.fade, 0.15, accuracy: 0.001)
    }

    func testChromeZoneIsTitleNotWholeCard() {
        let zone = WidgetChrome.zone(title: title, icons: 3)
        XCTAssertTrue(zone.contains(CGPoint(x: title.midX, y: title.midY)), "над заголовком — да")
        XCTAssertFalse(zone.contains(CGPoint(x: title.midX, y: 60)), "над телом карточки — нет")
        XCTAssertFalse(zone.contains(CGPoint(x: 140, y: title.midY)), "над числом справа — нет")
        // Строка значков шире короткого заголовка — курсор, дошедший до крестика, их не гасит.
        let row = 3 * WidgetChrome.icon.width + 2 * WidgetChrome.spacing
        XCTAssertTrue(zone.contains(CGPoint(x: title.minX - WidgetChrome.inset + row - 1, y: title.midY)))
        XCTAssertTrue(WidgetChrome.zone(title: .zero, icons: 3).isNull, "нет заголовка — нет зоны")
    }

    func testChromeSteps() {
        XCTAssertEqual(WidgetChrome.step(inside: true, shown: false, waiting: false), .wait, "вошёл — ждём 0,8 с")
        XCTAssertEqual(WidgetChrome.step(inside: true, shown: false, waiting: true), .keep)
        XCTAssertEqual(WidgetChrome.step(inside: false, shown: false, waiting: true), .cancel, "прошёл мимо — не показываем")
        XCTAssertEqual(WidgetChrome.step(inside: false, shown: true, waiting: false), .hide, "ушёл — гаснут")
        XCTAssertEqual(WidgetChrome.step(inside: true, shown: true, waiting: false), .keep)
        XCTAssertEqual(WidgetChrome.step(inside: false, shown: false, waiting: false), .keep)
    }

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
        XCTAssertEqual(lone.map { $0.id }, [PanelWidget.memory.rawValue])
        XCTAssertEqual(layout.item(PanelWidget.memory.rawValue)?.wide, false)
    }
}
