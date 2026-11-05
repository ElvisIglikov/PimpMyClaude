import Foundation
import XCTest
@testable import ClaudeAX

/// #11620: Пимп из launchd — без LANG; tmux 3.7 без UTF-8 локали меняет в выводе табуляцию на «_», и сторож терминалов
/// не видел ни hub, ни чатов (после смены чата новое окно не вставало в hub на место старого).
final class FlowShellLocale11620Tests: XCTestCase {
    func testEnvironmentAddsUTF8OnlyWhenLocaleIsMissingOrNotUTF8() {
        XCTAssertEqual(FlowShell.environment(["PATH": "/usr/bin"])["LC_CTYPE"], "en_US.UTF-8", "launchd: локали нет")
        XCTAssertEqual(FlowShell.environment(["LANG": "C"])["LC_CTYPE"], "en_US.UTF-8")
        let own = ["LANG": "ru_RU.UTF-8"]
        XCTAssertEqual(FlowShell.environment(own), own, "своя UTF-8 локаль человека — как есть")
        XCTAssertEqual(FlowShell.environment(["LC_CTYPE": "en_US.utf8"]), ["LC_CTYPE": "en_US.utf8"])
        XCTAssertEqual(FlowShell.environment(["LC_ALL": "C", "LANG": "en_US.UTF-8"])["LC_ALL"], "en_US.UTF-8",
                       "LC_ALL сильнее LC_CTYPE — меняем его")
        XCTAssertEqual(FlowShell.environment(["LC_ALL": "", "LANG": "C"])["LC_CTYPE"], "en_US.UTF-8")
    }

    /// Живой tmux на своём сокете: окружение без локали ломает табуляцию, `FlowShell.environment` — нет.
    func testTmuxKeepsTabWithFlowShellEnvironment() throws {
        guard let tmux = PanelTiles.tmuxPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("tmux нет")
        }
        let socket = "pimp-test-11620-\(getpid())"
        func run(_ arguments: [String], _ environment: [String: String]) -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmux)
            process.arguments = ["-L", socket, "-f", "/dev/null"] + arguments
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let bare = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        _ = run(["new-session", "-d", "-s", "rick-Demo"], FlowShell.environment(bare))
        defer { _ = run(["kill-server"], FlowShell.environment(bare)) }
        let format = ["ls", "-F", "#{session_name}\t#{session_created}"]
        let fixed = run(format, FlowShell.environment(bare))
        XCTAssertTrue(fixed.hasPrefix("rick-Demo\t"), "с UTF-8 — табуляция: \(fixed)")
        XCTAssertEqual(TerminalKeeper.sessions(ls: fixed, clients: "").map(\.name), ["Demo"])
    }
}
