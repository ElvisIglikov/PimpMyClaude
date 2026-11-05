import Foundation
import XCTest
@testable import ClaudeAX

/// #10564: сводное окно iTerm2 — окна чатов `rick-*` связаны в `pimp-hub`; убираются только окна умерших чатов
/// (метка `@pimp-chat`), вкладка человека остаётся; последнее окно hub держит заглушка.
final class ITermHubWF10564Tests: XCTestCase {
    private func window(_ session: String, _ id: String, chat: Bool = true, _ name: String = "Demo") -> ITermHub.Window {
        ITermHub.Window(session: session, id: id, chat: chat, name: name)
    }

    func testFormatAsksChatMark() {
        XCTAssertTrue(ITermHub.windowsFormat.contains("#{@pimp-chat}"))
        XCTAssertTrue(ITermHub.windowsFormat.hasSuffix("#{window_name}"), "имя последним — в нём может быть ⇥")
    }

    func testWindowsParseMarkAndName() {
        let text = "rick-Demo\t@7\t1\tDemo\npimp-hub\t@9\t\tzsh\npimp-hub\t@3\t1\tИмя\tс табом\nbad\nx\tnoat\t1\tn\n\t@1\t1\tn\n"
        XCTAssertEqual(ITermHub.windows(text), [
            window("rick-Demo", "@7", "Demo"),
            window("pimp-hub", "@9", chat: false, "zsh"),
            window("pimp-hub", "@3", "Имя\tс табом"),
        ])
    }

    func testPresentOnlyExactHub() {
        XCTAssertTrue(ITermHub.present(ls: "rick-Demo\t1790000000\npimp-hub\t1790000001\n"))
        XCTAssertFalse(ITermHub.present(ls: "rick-Demo\t1790000000\npimp-hub-old\t1\n"))
    }

    func testNewChatIsMarkedAndLinkedPlaceholderGoes() {
        let plan = ITermHub.plan([
            window("rick-Demo", "@7", chat: false, "zsh"),
            window("pimp-hub", "@1", chat: false, ITermHub.placeholder),
        ])
        XCTAssertEqual(plan.mark, ["@7"])
        XCTAssertEqual(plan.link, [window("rick-Demo", "@7", chat: false, "zsh")])
        XCTAssertEqual(plan.kill, ["@1"], "есть что связать — заглушка больше не нужна")
        XCTAssertFalse(plan.placeholder)
    }

    func testOnlyDeadChatWindowsAreKilledHumanTabStays() {
        // Рик сменил чат: kill-session + new-session — старое окно @5 осталось только в hub, новое @12 уже связано.
        let plan = ITermHub.plan([
            window("rick-Demo", "@12"),
            window("pimp-hub", "@12"),
            window("pimp-hub", "@5"),
            window("pimp-hub", "@9", chat: false, "zsh"),
        ])
        XCTAssertEqual(plan.kill, ["@5"], "вкладку, открытую человеком (⌘T), не трогаем")
        XCTAssertEqual(plan.link, [])
        XCTAssertEqual(plan.mark, [])
        XCTAssertFalse(plan.placeholder)
    }

    func testUnmarkedHubWindowWithoutRickIsNeverKilled() {
        let plan = ITermHub.plan([window("pimp-hub", "@9", chat: false, "zsh"), window("pimp-hub", "@4", chat: false)])
        XCTAssertEqual(plan, ITermHub.Plan())
    }

    func testLastWindowKeptByPlaceholder() {
        XCTAssertEqual(ITermHub.plan([window("pimp-hub", "@5")]),
                       ITermHub.Plan(placeholder: true, kill: ["@5"]), "сперва заглушка, потом убить — сессия живёт")
        XCTAssertEqual(ITermHub.plan([window("pimp-hub", "@5"), window("pimp-hub", "@1", chat: false, ITermHub.placeholder)]),
                       ITermHub.Plan(kill: ["@5"]), "заглушка уже есть — её и оставить")
        XCTAssertEqual(ITermHub.plan([window("pimp-hub", "@1", chat: false, ITermHub.placeholder)]), ITermHub.Plan())
        XCTAssertEqual(ITermHub.plan([window("pimp-hub", "@5"), window("pimp-hub", "@9", chat: false, "zsh")]),
                       ITermHub.Plan(kill: ["@5"]), "вкладка человека держит сессию — заглушка не нужна")
    }

    func testChatAlreadyInHubByAnyWindowIsNotRelinked() {
        let plan = ITermHub.plan([
            window("rick-Demo", "@7", chat: false),
            window("rick-Demo", "@8"),
            window("pimp-hub", "@8"),
            window("rick-Other", "@20"),
            window("rick-", "@30", chat: false),
        ])
        XCTAssertEqual(plan.link, [window("rick-Other", "@20")], "первое окно — только у чата без окна в hub")
        XCTAssertEqual(plan.mark, ["@7"], "метка — всем окнам rick-*, у которых её нет; «rick-» без имени — не чат")
        XCTAssertEqual(plan.kill, [])
    }

    func testControlledOnlyControlModeClient() {
        XCTAssertTrue(ITermHub.controlled("0\n1\n"))
        XCTAssertFalse(ITermHub.controlled("0\n"))
        XCTAssertFalse(ITermHub.controlled(""))
    }

    func testCommandMarksChatWindowsAndKeepsLastWindow() throws {
        let body = ITermHub.command(tmux: "/opt/homebrew/bin/tmux")
        XCTAssertTrue(body.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(body.contains("TM=/opt/homebrew/bin/tmux\n"))
        let mark = try XCTUnwrap(body.range(of: "set-option -w -t \"$window\" @pimp-chat 1"))
        let link = try XCTUnwrap(body.range(of: "link-window -d -s \"$window\" -t \"=$HUB:\""))
        XCTAssertLessThan(mark.lowerBound, link.lowerBound, "метка до связи")
        XCTAssertTrue(body.contains("-gt 1 ]"), "заглушку не убивать, когда она последняя")
        XCTAssertTrue(body.contains("exec $TM -CC attach -t \"=$HUB\""))
        XCTAssertFalse(body.contains("osascript"), "без AppleScript — права управлять iTerm у Пимпа нет")
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/bin/sh")
        check.arguments = ["-n", "-c", body]
        try check.run()
        check.waitUntilExit()
        XCTAssertEqual(check.terminationStatus, 0, "sh -n: скрипт без синтаксических ошибок")
    }

    func testEnsureCommandWritesExecutableFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("iterm/hub.command")
        XCTAssertEqual(ITermHub.ensureCommand(tmux: "/usr/local/bin/tmux", file: file), file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), ITermHub.command(tmux: "/usr/local/bin/tmux"))
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode & 0o777, 0o700)
        try "старый".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        XCTAssertEqual(ITermHub.ensureCommand(tmux: "/usr/local/bin/tmux", file: file), file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), ITermHub.command(tmux: "/usr/local/bin/tmux"),
                       "чужой текст — переписан")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: file.path))
    }
}
