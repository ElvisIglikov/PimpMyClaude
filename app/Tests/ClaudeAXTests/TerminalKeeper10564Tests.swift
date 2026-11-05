import XCTest
@testable import ClaudeAX

/// #10564: окно каждой сессии `rick-<проект>` — раз за её жизнь: нет окна — открыть, есть — развернуть.
final class TerminalKeeper10564Tests: XCTestCase {
    func testSessionsParseOnlyRickWithClients() {
        let ls = "rick-PimpMyClaude\t1790000000\nother\t1790000001\nrick-\t1\nrick-VkusSES\tx\nrick-Dictator\t1790000002\n"
        let clients = "/dev/ttys026\trick-PimpMyClaude\n/dev/ttys030\trick-PimpMyClaude\nbad\trick-Dictator\n"
        XCTAssertEqual(TerminalKeeper.sessions(ls: ls, clients: clients), [
            .init(name: "PimpMyClaude", created: 1_790_000_000, clients: ["/dev/ttys026", "/dev/ttys030"]),
            .init(name: "Dictator", created: 1_790_000_002, clients: []),
        ])
    }

    func testEachSessionOnceUntilItIsNew() {
        let keeper = TerminalKeeper(defaults: nil)
        let pimp = TerminalKeeper.Session(name: "PimpMyClaude", created: 10, clients: ["/dev/ttys026"])
        let dictator = TerminalKeeper.Session(name: "Dictator", created: 20, clients: [])
        XCTAssertEqual(keeper.steps([pimp, dictator]), [.open("Dictator"), .unminimize("PimpMyClaude", ["/dev/ttys026"])])
        XCTAssertEqual(keeper.steps([pimp, TerminalKeeper.Session(name: "Dictator", created: 20, clients: [])]), [],
                       "закрыл окно человек — не открываем снова")
        XCTAssertEqual(keeper.steps([pimp, TerminalKeeper.Session(name: "Dictator", created: 30, clients: [])]),
                       [.open("Dictator")], "сессию завели заново — окно снова")
        XCTAssertEqual(keeper.steps([]), [])
        XCTAssertEqual(keeper.steps([pimp]), [.unminimize("PimpMyClaude", ["/dev/ttys026"])], "ушедшая из tmux — забыта")
    }

    func testShownSessionsSurviveRestart() throws {
        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pimp = TerminalKeeper.Session(name: "PimpMyClaude", created: 10, clients: ["/dev/ttys026"])
        XCTAssertEqual(TerminalKeeper(defaults: defaults).steps([pimp]).count, 1)
        XCTAssertEqual(TerminalKeeper(defaults: defaults).steps([pimp]), [], "новая версия Пимпа свёрнутое не разворачивает")
    }
}
