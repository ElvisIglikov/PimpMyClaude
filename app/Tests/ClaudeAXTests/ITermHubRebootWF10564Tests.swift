import XCTest
@testable import ClaudeAX

/// Перезагрузка Мака (23.10.2026): hub.command связал окна чатов, а tmux назвал их по программе («claude») — Пимп
/// возвращает вкладкам имена проектов; уже верные и окна не чатов не трогает.
final class ITermHubRebootWF10564Tests: XCTestCase {
    private func window(_ session: String, _ id: String, _ name: String) -> ITermHub.Window {
        ITermHub.Window(session: session, id: id, chat: true, name: name)
    }

    func testRenamesOnlyFirstChatWindowWithWrongName() {
        let windows = [
            window("pimp-hub", "@1", "claude"),
            window("rick-Elblog", "@1", "claude"),
            window("rick-Elblog", "@7", "второе"),
            window("rick-Risovalka", "@2", "Рисовалка"),
            window("work", "@3", "claude"),
        ]
        let titles = ["Elblog": "Elblog", "Risovalka": "Рисовалка"]
        let out = ITermHub.renames(windows) { titles[$0] ?? "" }
        XCTAssertEqual(out.map { $0.0.id }, ["@1"])
        XCTAssertEqual(out.map { $0.1 }, ["Elblog"])
    }

    func testEmptyTitleIsNotARename() {
        XCTAssertTrue(ITermHub.renames([window("rick-X", "@4", "claude")]) { _ in "" }.isEmpty)
    }

    func testModeKeyIsStable() {
        XCTAssertEqual(ITermHub.modeKey, "terminalKeeperITermHub10564")
    }
}
