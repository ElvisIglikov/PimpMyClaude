import XCTest
@testable import ClaudeAX

/// #11620: строка «Больше всех: …» под графиком памяти — кто съел память, по человеческим именам.
final class MemoryEaters11620Tests: XCTestCase {
    private let gb: UInt64 = 1_073_741_824
    private let claudeCode = "/Users/dev/Library/Application Support/Claude/claude-code/2.1.317/91184d3d9ba3/claude.app/Contents/MacOS/claude"
    private let chromeGPU = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)"

    func testNamesSeparateClaudeCodeFromClaudeAppAndNameVM() {
        XCTAssertEqual(MemoryEaters.name(claudeCode), "Claude Code")
        XCTAssertEqual(MemoryEaters.name("/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)"),
                       "Claude", "приложение Claude — не Claude Code")
        XCTAssertEqual(MemoryEaters.name("/Applications/UTM.app/Contents/XPCServices/QEMUHelper.xpc/Contents/MacOS/QEMUHelper"), "ВМ UTM")
        XCTAssertEqual(MemoryEaters.name(chromeGPU), "Chrome")
    }

    func testGroupSumsHelpersAndCountsSortedByBytes() {
        let eaters = MemoryEaters.group([
            (path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", bytes: 2 * gb),
            (path: claudeCode, bytes: gb),
            (path: chromeGPU, bytes: gb),
            (path: claudeCode, bytes: gb),
            (path: claudeCode, bytes: 2 * gb),
            (path: "/usr/local/bin/someTool", bytes: 0),
            (path: "", bytes: gb),
        ])
        XCTAssertEqual(eaters, [MemoryEater(name: "Claude Code", bytes: 4 * gb, count: 3),
                                MemoryEater(name: "Chrome", bytes: 3 * gb, count: 2)],
                       "помощники Chrome — в «Chrome», claude ×3; нули и пустой путь — мимо")
    }

    func testGroupKeepsFirstSeenOrderForEqualBytes() {
        let eaters = MemoryEaters.group([(path: "/bin/b", bytes: gb), (path: "/bin/a", bytes: gb), (path: "/bin/c", bytes: 2 * gb)])
        XCTAssertEqual(eaters.map(\.name), ["c", "b", "a"])
    }

    func testTextShowsTopThreeWithCountAndNilWhenEmpty() {
        let eaters = [MemoryEater(name: "ВМ UTM", bytes: 10 * gb + gb / 10, count: 1),
                      MemoryEater(name: "Claude Code", bytes: 5 * gb, count: 29),
                      MemoryEater(name: "Chrome", bytes: 3 * gb + 7 * gb / 10, count: 14),
                      MemoryEater(name: "Python", bytes: gb, count: 2)]
        XCTAssertEqual(MemoryEaters.text(eaters),
                       "Больше всех: ВМ UTM 10.1\u{00A0}ГБ · Claude Code ×29 5\u{00A0}ГБ · Chrome ×14 3.7\u{00A0}ГБ")
        XCTAssertNil(MemoryEaters.text([]))
        XCTAssertNil(MemoryEaters.text([MemoryEater(name: "x", bytes: 0, count: 1)]))
    }
}
