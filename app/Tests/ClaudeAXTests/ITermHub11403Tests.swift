import Foundation
import XCTest
@testable import ClaudeAX

/// #11403: новое окно в hub будит спрятанный iTerm (окно мигает) — пока iTerm не активен, чаты не связываем; метки,
/// убийство окон умерших чатов и заглушка — как всегда.
final class ITermHub11403Tests: XCTestCase {
    private func window(_ session: String, _ id: String, chat: Bool = true, _ name: String = "Demo") -> ITermHub.Window {
        ITermHub.Window(session: session, id: id, chat: chat, name: name)
    }

    func testDeferredNewChatIsMarkedNotLinkedPlaceholderStays() {
        let plan = ITermHub.plan([
            window("rick-Demo", "@7", chat: false, "zsh"),
            window("pimp-hub", "@1", chat: false, ITermHub.placeholder),
        ], link: false)
        XCTAssertEqual(plan, ITermHub.Plan(mark: ["@7"]), "без связи заглушка держит hub")
    }

    func testDeferredChatChangeStillKillsOldWindow() {
        // Рик сменил чат: старое окно @5 только в hub (в нём живёт прежний claude) — убить сразу, новое @12 подождёт.
        let windows = [window("rick-Demo", "@12"), window("pimp-hub", "@5"), window("pimp-hub", "@9", chat: false, "zsh")]
        XCTAssertEqual(ITermHub.plan(windows, link: false).kill, ["@5"])
        XCTAssertEqual(ITermHub.plan(windows, link: false).link, [])
        XCTAssertEqual(ITermHub.plan([window("rick-Demo", "@12"), window("pimp-hub", "@5")], link: false),
                       ITermHub.Plan(placeholder: true, kill: ["@5"]), "последнее окно hub — сперва заглушка")
        XCTAssertEqual(ITermHub.plan(windows).link, [window("rick-Demo", "@12")], "iTerm активен — связываем как раньше")
    }
}
