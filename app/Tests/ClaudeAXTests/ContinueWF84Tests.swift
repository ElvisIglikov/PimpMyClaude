import XCTest
@testable import ClaudeAX

/// «💬 Новый чат» кнопкой в самом чате (#7246, WF84 P3): метка страницы в
/// заголовке окна → `ContinueWatchMachine` → тот же путь, что пункт меню ⌘B; и закрепка —
/// поля `pin` / `unpin` команды `new-window` (эталон `new-window-handoff-pin.json`).
final class ContinueWF84Tests: XCTestCase {
    private static let id = "1756900000123-0042"
    private static let at = Date(timeIntervalSince1970: 1_756_900_000)
    private static let mainMatch = "/epitaxy/local_facfb20c-4b3c-4aa9-838f-e084b0941b74"
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: ContinueWF84Tests.repositoryRoot
            .appendingPathComponent("tests/fixtures/cashout/\(name)"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let mark = "Пимп: продолжить в новом чате · mfw3k2a1"

    // MARK: - метка

    func testNonceParsesOnlyOurLabel() {
        XCTAssertEqual(ContinueWatchMachine.nonce(of: mark), "mfw3k2a1")
        XCTAssertEqual(ContinueWatchMachine.nonce(of: "  \(mark)  "), "mfw3k2a1")
        XCTAssertNil(ContinueWatchMachine.nonce(of: "Пимп: продолжить в новом чате"), "без метки — не клик")
        XCTAssertNil(ContinueWatchMachine.nonce(of: "Пимп жмёт Allow · Trelvis"), "замок К6 — не наша метка")
        XCTAssertNil(ContinueWatchMachine.nonce(of: "VkusnoffKz 2"))
        XCTAssertEqual(ContinueWatch.labelPrefix, "Пимп: продолжить в новом чате", "побайтно как страница")
    }

    // MARK: - машина: запомнить окно, дождаться ухода метки, сработать один раз

    func testArmsOnMarkAndFiresWhenMarkLeaves() {
        var machine = ContinueWatchMachine()
        XCTAssertEqual(machine.step(titles: ["Trelvis", "VkusnoffKz 2"], now: 0), .none)
        XCTAssertEqual(machine.step(titles: ["Trelvis", mark], now: 0.25), .arm(1), "окно — второе в списке")
        XCTAssertEqual(machine.step(titles: ["Trelvis", mark], now: 0.5), .none, "метка ещё стоит — рано")
        XCTAssertEqual(machine.step(titles: [mark, "Trelvis"], now: 0.75), .none, "порядок окон сменился — ждём ту же метку")
        XCTAssertEqual(machine.step(titles: ["Trelvis", "VkusnoffKz 2"], now: 1.5), .fire, "метка ушла — пора")
        XCTAssertEqual(machine.step(titles: ["Trelvis", "VkusnoffKz 2"], now: 1.75), .none)
    }

    func testSameMarkNeverFiresTwice() {
        var machine = ContinueWatchMachine()
        _ = machine.step(titles: [mark], now: 0)
        XCTAssertEqual(machine.step(titles: [], now: 1), .fire)
        XCTAssertEqual(machine.step(titles: [mark], now: 1.25), .none, "та же метка мигнула снова — клик уже исполнен")
        let next = "Пимп: продолжить в новом чате · mfw3k9zz"
        XCTAssertEqual(machine.step(titles: ["Claude", next], now: 5), .arm(1), "новый клик — новая метка")
    }

    func testStuckMarkFiresAfterCeiling() {
        var machine = ContinueWatchMachine()
        _ = machine.step(titles: [mark], now: 10)
        XCTAssertEqual(machine.step(titles: [mark], now: 12), .none)
        XCTAssertEqual(machine.step(titles: [mark], now: 10 + ContinueWatchMachine.maxWait), .fire,
                       "страница не сняла метку (перезагрузка) — клик всё равно исполняем")
        XCTAssertEqual(machine.step(titles: [mark], now: 13), .none, "и не повторяем")
    }

    func testMemoryIsBounded() {
        var machine = ContinueWatchMachine()
        for index in 0..<(ContinueWatchMachine.memory + 5) {
            let label = "Пимп: продолжить в новом чате · n\(index)"
            _ = machine.step(titles: [label], now: Double(index))
            _ = machine.step(titles: [], now: Double(index) + 0.5)
        }
        XCTAssertEqual(machine.handled.count, ContinueWatchMachine.memory)
    }

    // MARK: - закрепка: поля new-window

    func testNewWindowPinFieldsMatchFixture() throws {
        let payload = CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(
                title: "PimpMyClaude", match: ContinueWF84Tests.mainMatch, x: 586, y: 303, text: "Привет",
                folder: "/Users/dev/Projects/PimpMyClaude", name: "",
                model: "Fable 5.1", effort: "Extra", sendTransfer: true, stay: true,
                pin: true, unpin: "local_facfb20c-4b3c-4aa9-838f-e084b0941b74"),
            id: ContinueWF84Tests.id, at: ContinueWF84Tests.at)
        XCTAssertEqual(payload, try fixture("new-window-handoff-pin.json"))
        let plain = CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "VkusnoffKz 2", x: 1, y: 2, text: "Привет"),
            id: ContinueWF84Tests.id, at: ContinueWF84Tests.at)
        XCTAssertFalse(plain.contains("\"pin\""), "обычное «Новое окно» не закрепляет")
        XCTAssertFalse(plain.contains("\"unpin\""))
    }

    func testHandoffCarriesDonorForUnpin() {
        XCTAssertEqual(NewChatHandoff.from(nil, stay: true, unpin: "local_a").unpin, "local_a")
        XCTAssertNil(NewChatHandoff.from(nil, stay: false).unpin, "донора не знаем — только закрепка")
    }
}
