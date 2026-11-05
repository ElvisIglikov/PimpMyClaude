import XCTest
@testable import ClaudeAX

/// Потоп окон iTerm (#10976, 27.10.2026): «Initial Text» профиля запускал окна — Пимп держит свой профиль с пустым
/// «Initial Text», не открывает iTerm при опасном профиле, толпе окон и псевдотерминалах у предела, а hub.command
/// сбрасывает старую раскладку — все вкладки в одном окне.
final class ITermFuse10976Tests: XCTestCase {
    func testLaunchersAreCaught() {
        XCTAssertTrue(ITermHub.launches("/Users/dev/Library/Application Support/MyClaude/iterm/open-tabs.command; exit"))
        XCTAssertTrue(ITermHub.launches("osascript -e 'tell application \"iTerm\" to create window'"))
        XCTAssertTrue(ITermHub.launches("open -a iTerm ~/x"))
        XCTAssertTrue(ITermHub.launches("cd ~; open ."))
        XCTAssertFalse(ITermHub.launches(""))
        XCTAssertFalse(ITermHub.launches("cd ~/projects && ls"))
        XCTAssertFalse(ITermHub.launches("opencode"), "слово open внутри другого — не запуск")
    }

    func testLaunchingProfileByName() {
        let profiles: [[String: Any]] = [
            ["Name": "Пимп", "Initial Text": ""],
            ["Name": "Default", "Initial Text": "~/iterm/open-tabs.command; exit"],
        ]
        XCTAssertEqual(ITermHub.launchingProfile(profiles), "Default")
        XCTAssertNil(ITermHub.launchingProfile([["Name": "Default"], ["Name": "Работа", "Initial Text": "cd ~/w"]]))
    }

    func testAlarmOrder() {
        XCTAssertNil(ITermHub.alarm(profile: nil, windows: 3, ptys: (21, 511)))
        XCTAssertEqual(ITermHub.alarm(profile: "Default", windows: 380, ptys: (500, 511)),
                       "iTerm: профиль «Default» сам открывает окна (Initial Text) — окна не открываю")
        XCTAssertEqual(ITermHub.alarm(profile: nil, windows: 106, ptys: (21, 511)),
                       "iTerm: 106 окон — что-то плодит окна, новые не открываю")
        XCTAssertNil(ITermHub.alarm(profile: nil, windows: ITermHub.maxWindows, ptys: (21, 511)))
        XCTAssertEqual(ITermHub.alarm(profile: nil, windows: 2, ptys: (409, 511)),
                       "Терминалов 409 из 511 — новые окна iTerm не открываю")
        XCTAssertNil(ITermHub.alarm(profile: nil, windows: 2, ptys: (408, 511)))
        XCTAssertNil(ITermHub.alarm(profile: nil, windows: 2, ptys: (900, 0)), "предела не прочли — по нему не держим")
    }

    func testProfileGetsEmptyInitialTextOnlyWhenNeeded() throws {
        let inherited = #"{"Profiles":[{"Name":"Пимп","Guid":"pimp-terminal-chats","Custom Tab Title":"\\(tab.tmuxWindowName)"},{"Name":"Чужой","Guid":"x","Initial Text":"cd ~"}]}"#
        let fixed = try XCTUnwrap(ITermHub.profileFixed(Data(inherited.utf8)))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: fixed) as? [String: Any])
        let list = try XCTUnwrap(root["Profiles"] as? [[String: Any]])
        XCTAssertEqual(list[0]["Initial Text"] as? String, "")
        XCTAssertEqual(list[0]["Custom Tab Title"] as? String, "\\(tab.tmuxWindowName)", "остальное профиля — как было")
        XCTAssertEqual(list[1]["Initial Text"] as? String, "cd ~", "чужой профиль не трогаем")
        XCTAssertNil(ITermHub.profileFixed(fixed), "уже пустой — не переписываем")
        let set = #"{"Profiles":[{"Guid":"pimp-terminal-chats","Initial Text":"~/open-tabs.command; exit"}]}"#
        XCTAssertNotNil(ITermHub.profileFixed(Data(set.utf8)))
        XCTAssertNil(ITermHub.profileFixed(Data("не json".utf8)))
    }

    func testEnsureProfileRewritesFileWithoutTmpInDynamicProfiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fuse-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("DynamicProfiles/pimp.json")
        let tmp = dir.appendingPathComponent("iterm/pimp.json.tmp")
        XCTAssertFalse(ITermHub.ensureProfile(file: file, tmp: tmp), "файла нет — не заводим")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"Profiles":[{"Guid":"pimp-terminal-chats"}]}"#.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(ITermHub.ensureProfile(file: file, tmp: tmp))
        XCTAssertNil(ITermHub.profileFixed(try Data(contentsOf: file)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path), ["pimp.json"])
        XCTAssertFalse(ITermHub.ensureProfile(file: file, tmp: tmp))
    }

    func testCommandResetsLayoutBeforeAttach() throws {
        let body = ITermHub.command(tmux: "/opt/homebrew/bin/tmux")
        let reset = try XCTUnwrap(body.range(of: "$TM set-option -u -t \"=$HUB:\" @affinities"),
                                  "цель с двоеточием: «=pimp-hub» без него tmux не находит")
        let attach = try XCTUnwrap(body.range(of: "exec $TM -CC attach"))
        XCTAssertLessThan(reset.lowerBound, attach.lowerBound)
    }
}
