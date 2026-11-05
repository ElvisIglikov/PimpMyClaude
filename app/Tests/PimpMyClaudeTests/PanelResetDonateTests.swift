import XCTest
@testable import PimpMyClaude

/// Слово 03.11.2026: «Сброс» крупно парами цифра и буква; «Поддержать автора» скрывается на 100 часов.
final class PanelResetDonateTests: XCTestCase {
    private func line(_ seconds: TimeInterval) -> String {
        let now = Date()
        return PanelShort.heroParts(now.addingTimeInterval(seconds), now: now)
            .map { $0.number + $0.unit }.joined(separator: " ")
    }

    func testHeroParts() {
        XCTAssertEqual(line(5 * 86400 + 2 * 3600), "5д 2ч")
        XCTAssertEqual(line(5 * 3600 + 12 * 60), "5ч 12м")
        XCTAssertEqual(line(23 * 3600 + 59 * 60), "23ч 59м")
        XCTAssertEqual(line(2 * 86400), "2д")
        XCTAssertEqual(line(20), "<1м")
        XCTAssertEqual(PanelShort.heroParts(nil, now: Date()), [])
    }

    func testDonateReturnsAfterHundredHours() {
        let now = Date()
        let shown = { (hiddenAt: Date?, available: Bool) in
            PanelModel.donateButtonShown(available: available, hiddenAt: hiddenAt, now: now)
        }
        XCTAssertTrue(shown(nil, true))
        XCTAssertFalse(shown(nil, false), "окну нечего показать — кнопки нет")
        XCTAssertFalse(shown(now.addingTimeInterval(-99 * 3600), true))
        XCTAssertTrue(shown(now.addingTimeInterval(-100 * 3600), true))
        XCTAssertFalse(shown(now.addingTimeInterval(-100 * 3600), false))
    }
}
