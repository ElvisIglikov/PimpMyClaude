import AppKit
import XCTest
@testable import ClaudeAX

/// Chrome reserves a strip without taking a cell from Claude (#7962). No live AX effects.
final class ArrangeWF120Tests: XCTestCase {
    /// Живой замер 26.09: Odyssey G91SD — 2560×720 pt (как в `WF94WindowsTests`).
    private static let odyssey = CGRect(x: -3360, y: -575, width: 2560, height: 720)
    /// Что остаётся окнам Claude левее ChatGPT 703 при зазоре 5.
    private static let odysseyLeft = CGRect(x: -3360, y: -575, width: 1852, height: 720)
    private static let macbook = CGRect(x: 0, y: 30, width: 1470, height: 900)

    private static func loose(_ count: Int) -> [CGRect] {
        (0..<count).map { i in
            CGRect(x: -3300 + CGFloat(i) * 150, y: -560 + CGFloat(i % 3) * 20, width: 500, height: 400)
        }
    }

    // MARK: - 7962: полоса Chrome

    /// Подставное окно: уже `minimum` не сужается и прижимается правым краем, как живое.
    private final class FakeStrip {
        let minimum: CGFloat
        var calls: [CGRect] = []
        init(minimum: CGFloat) { self.minimum = minimum }
        func set(_ want: CGRect) -> CGRect? {
            calls.append(want)
            guard want.width < minimum else { return want }
            return CGRect(x: want.maxX - minimum, y: want.minY, width: minimum, height: want.height)
        }
    }

    private static var screens: [(full: CGRect, usable: CGRect)] {
        [(full: macbook, usable: macbook), (full: odyssey, usable: odyssey)]
    }

    /// Сперва ChatGPT справа (как в WF94), затем Chrome тем же резервом: полоса его минимума левее
    /// ChatGPT с зазором, окнам Claude — остаток левее Chrome; места им хватает.
    func testChromeTakesStripLeftOfChatGPT() throws {
        let claude = ArrangeWF120Tests.loose(3)
        let gpt = FakeStrip(minimum: 703)
        let afterGPT = ChatGPTWindows.reserve(screens: ArrangeWF120Tests.screens, claude: claude,
                                              chatGPT: CGRect(x: -2000, y: -500, width: 900, height: 600),
                                              minCellWidth: 220, gap: 5, set: gpt.set)
        let chatGPT = try XCTUnwrap(afterGPT.chatGPT)
        let chrome = FakeStrip(minimum: 500)
        let plan = ChatGPTWindows.reserve(screens: afterGPT.screens, claude: claude,
                                          chatGPT: CGRect(x: -3000, y: -400, width: 1200, height: 700),
                                          minCellWidth: 220, gap: 5, keepCells: true, set: chrome.set)
        let strip = try XCTUnwrap(plan.chatGPT)
        XCTAssertEqual(strip, CGRect(x: -2008, y: -575, width: 500, height: 720))
        XCTAssertEqual(strip.maxX, chatGPT.minX - 5, "левее ChatGPT, с зазором")
        XCTAssertEqual(plan.screens[1].usable, CGRect(x: -3360, y: -575, width: 1347, height: 720))
        XCTAssertEqual(plan.screens[0].usable, ArrangeWF120Tests.macbook, "чужой экран как был")
        let placed = ArrangeLayout.smart(frames: claude, screens: plan.screens, minCellWidth: 220, gap: 5)
        XCTAssertTrue(placed.allSatisfy { $0.maxX <= strip.minX - 5 }, "окна Claude левее Chrome")
    }

    /// Семь окон при минимуме 220 (Элвис) и ChatGPT: Chrome 500 отнял бы седьмому ячейку (8→6
    /// столбцов) — не резервируем: сдвинули и не влезло — ставим как стоял; минимум известен —
    /// не двигаем вовсе. Без `keepCells` (путь ChatGPT) тот же резерв оставил бы окно без места.
    func testChromeIsLeftAloneWhenClaudeWouldLoseCells() throws {
        let claude = ArrangeWF120Tests.loose(7)
        let afterGPT = ChatGPTWindows.reserve(screens: ArrangeWF120Tests.screens, claude: claude,
                                              chatGPT: CGRect(x: -2000, y: -500, width: 900, height: 600),
                                              minCellWidth: 220, gap: 5, set: FakeStrip(minimum: 703).set)
        XCTAssertEqual(afterGPT.screens[1].usable, ArrangeWF120Tests.odysseyLeft)
        let original = CGRect(x: -3000, y: -400, width: 1200, height: 700)

        let chrome = FakeStrip(minimum: 500)
        let plan = ChatGPTWindows.reserve(screens: afterGPT.screens, claude: claude, chatGPT: original,
                                          minCellWidth: 220, gap: 5, keepCells: true, set: chrome.set)
        XCTAssertNil(plan.chatGPT)
        XCTAssertEqual(plan.screens[1].usable, ArrangeWF120Tests.odysseyLeft, "окнам Claude — прежний остаток")
        XCTAssertEqual(chrome.calls.count, 2)
        XCTAssertEqual(chrome.calls.last, original, "Chrome вернули как стоял")
        XCTAssertGreaterThanOrEqual(ArrangeLayout.smartCells(count: 7, in: plan.screens[1].usable,
                                                           minCellWidth: 220, gap: 5).count, 7)

        let known = FakeStrip(minimum: 500)
        XCTAssertNil(ChatGPTWindows.reserve(screens: afterGPT.screens, claude: claude, chatGPT: original,
                                            knownMinWidth: 500, minCellWidth: 220, gap: 5, keepCells: true,
                                            set: known.set).chatGPT)
        XCTAssertTrue(known.calls.isEmpty, "минимум известен — не дёргаем")

        let greedy = ChatGPTWindows.reserve(screens: afterGPT.screens, claude: claude, chatGPT: original,
                                            minCellWidth: 220, gap: 5, set: FakeStrip(minimum: 500).set)
        XCTAssertNotNil(greedy.chatGPT)
        XCTAssertEqual(ArrangeLayout.smartCells(count: 7, in: greedy.screens[1].usable,
                                                minCellWidth: 220, gap: 5).count, 6)
    }

    /// Chrome на экране, где окон Claude нет, не трогается.
    func testChromeOnAnotherScreenIsLeftAlone() {
        let chrome = FakeStrip(minimum: 500)
        let plan = ChatGPTWindows.reserve(screens: ArrangeWF120Tests.screens, claude: ArrangeWF120Tests.loose(3),
                                          chatGPT: CGRect(x: 200, y: 100, width: 900, height: 700),
                                          minCellWidth: 220, gap: 5, keepCells: true, set: chrome.set)
        XCTAssertNil(plan.chatGPT)
        XCTAssertTrue(chrome.calls.isEmpty)
        XCTAssertEqual(plan.screens.map { $0.usable }, ArrangeWF120Tests.screens.map { $0.usable })
    }

    /// Чьи окна: по умолчанию ChatGPT (прежние два bundle id), у полосы Chrome — `com.google.Chrome`.
    func testStripBundleIDs() {
        XCTAssertEqual(ChatGPTWindows().bundleIDs, ["com.openai.codex", "com.openai.chat"])
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                    commands: CommandChannel(path: URL(fileURLWithPath: NSTemporaryDirectory())
                                        .appendingPathComponent("wf120a-\(UUID().uuidString).json"),
                                                             now: { Date() }, schedule: { _, _ in }))
        XCTAssertEqual(actions.chatGPTWindows.bundleIDs, ChatGPTWindows.chatGPTBundleIDs)
        XCTAssertEqual(actions.chromeWindows.bundleIDs, ["com.google.Chrome"])
    }

    func testAnchorNeverReservesChromeOnAnotherClaudeScreen() {
        let chrome = FakeStrip(minimum: 500)
        let anchor = CGRect(x: 100, y: 100, width: 500, height: 600)
        let plan = ChatGPTWindows.reserve(screens: Self.screens, claude: Self.loose(3) + [anchor],
            chatGPT: CGRect(x: -3000, y: -400, width: 1200, height: 700),
            minCellWidth: 220, gap: 5, keepCells: true, anchor: anchor, set: chrome.set)
        XCTAssertNil(plan.chatGPT); XCTAssertTrue(chrome.calls.isEmpty)
    }

    func testChromeCannotReserveWhenExistingGridAlreadyOverflows() {
        let chrome = FakeStrip(minimum: 500)
        let plan = ChatGPTWindows.reserve(screens: [(full: Self.odyssey, usable: Self.odysseyLeft)],
            claude: Self.loose(20), chatGPT: CGRect(x: -3000, y: -400, width: 1200, height: 700),
            minCellWidth: 280, gap: 5, keepCells: true, set: chrome.set)
        XCTAssertNil(plan.chatGPT); XCTAssertTrue(chrome.calls.isEmpty)
    }

    func testRefusedNewWindowUndoesOnlyCapturedChromeAtExpectedFrame() throws {
        // Variants: same window; manually moved; disappeared; another window at front.
        for variant in 0..<4 {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf120-chrome-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
            var now = Date(timeIntervalSince1970: 1_790_000_000)
            let wide = CGRect(x: 300, y: 34, width: 900, height: 700)
            let narrow = CGRect(x: 960, y: 34, width: 500, height: 700)
            let captured = ChatGPTWindow(element: AXUIElementCreateApplication(0), title: "Chrome", frame: wide, id: 44, pid: 123)
            var actual: CGRect? = wide, front = captured
            var undo: [CGWindowID] = []
            let channel = PimpChannel(directory: dir, now: { now })
            channel.seats.claudeRunning = { true }
            channel.seats.windows = { [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 480, height: 700))] }
            channel.seats.newWindowLayers = { true }
            channel.seats.chrome = { front }
            channel.seats.chromeFrame = { target in
                XCTAssertEqual(target.id, 44); XCTAssertEqual(target.pid, 123)
                return actual
            }
            channel.seats.placeChrome = { target, expected, original in
                XCTAssertEqual(expected, narrow); XCTAssertEqual(original, wide)
                undo.append(target.id); actual = original
            }
            channel.seats.openNewWindow = { _, _ in }
            channel.seats.placeNew = { _ in }
            channel.seats.makeRoom = { ids in
                actual = narrow
                return ids.enumerated().map { index, id in
                    PimpWindow(id: id, title: "", frame: CGRect(x: index * 480, y: 34, width: 480, height: 700))
                }
            }
            channel.start()
            XCTAssertTrue(channel.startNewWindow(project: Project(folder: dir, name: "Test", lastFocusedAt: 0)))
            XCTAssertEqual(actual, narrow)
            if variant == 1 { actual = wide.offsetBy(dx: 1, dy: 100) }
            if variant == 2 { actual = nil }
            if variant == 3 {
                front = ChatGPTWindow(element: AXUIElementCreateApplication(0), title: "Other", frame: narrow, id: 55, pid: 123)
            }
            now = now.addingTimeInterval(PimpChannel.newWindowSeconds + 1)
            channel.tick()
            XCTAssertEqual(undo, variant == 0 || variant == 3 ? [44] : [])
        }
    }

}
