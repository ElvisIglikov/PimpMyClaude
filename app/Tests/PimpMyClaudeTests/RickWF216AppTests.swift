import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF216: строка «Поставить Рика» в настройках панели — итог копирования → состояние и подпись.
final class RickWF216AppTests: XCTestCase {
    func testOutcomeBecomesRowState() {
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects/Rick", isDirectory: true)
        XCTAssertEqual(RickInstall(.installed(folder)), .done("~/Projects/Rick"))
        XCTAssertEqual(RickInstall(.exists(folder)), .done("~/Projects/Rick"), "появилась, пока шло, — тоже «стоит»")
        let failed = RickInstall(.failed("не получилось записать в ~/Projects"))
        XCTAssertTrue(failed.isFailed)
        XCTAssertEqual(failed.caption, "Рик не встал: не получилось записать в ~/Projects. Ничего не изменилось — нажми ещё раз.")
        XCTAssertFalse(RickInstall.idle.isFailed)
        XCTAssertEqual(RickInstall.idle.caption, RickInstall.running.caption)
        XCTAssertTrue(SetupWindow.rickLine(folder).hasPrefix("Рик уже стоит в ~/Projects/Rick — открой эту папку в Claude Code"))
    }
}
