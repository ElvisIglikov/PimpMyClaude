import XCTest
@testable import PimpMyClaude

/// #9604: в том, что читает человек, — только «PMP», не «Пимп». Отказы `restart-claude` уходят в ответ CLI.
final class PmpWord9604AppTests: XCTestCase {
    func testRestartRefusalsSayPMP() {
        XCTAssertEqual(AppDelegate.restartClosingText, "PMP закрывается")
        XCTAssertEqual(AppDelegate.restartBusyText, "PMP занят: обновляет или патчит Claude")
        for text in [AppDelegate.restartClosingText, AppDelegate.restartBusyText] {
            XCTAssertFalse(text.contains("Пимп"), text)
        }
    }
}
