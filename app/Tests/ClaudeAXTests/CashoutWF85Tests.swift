import XCTest
@testable import ClaudeAX

/// Живой гейт WF85 (24.09.2026): «💬 Новый чат» из попапа — новое окно встало в рамку донора,
/// пары «номер Quartz → AX» по рамке перепутались, и закрылось НОВОЕ окно. Закрываем AX-окно
/// донора, снятое до ⌘N.
final class CashoutWF85Tests: XCTestCase {
    func testDonorToCloseIsTheStoredWindowNotTheFresh() {
        XCTAssertEqual(ClaudeActions.cashoutDonorToClose(stored: 7, fresh: 12, same: ==), 7)
        XCTAssertNil(ClaudeActions.cashoutDonorToClose(stored: 12, fresh: 12, same: ==),
                     "запомненный донор и есть новое окно — не закрываем ничего")
    }
}
