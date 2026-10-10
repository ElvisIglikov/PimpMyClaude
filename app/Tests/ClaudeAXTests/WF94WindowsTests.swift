import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Окна WF94 (батч Б1): девять столбцов и половинки на Odyssey (#7730, #7746), ChatGPT справа
/// (#7732, #7651), новое окно самым правым (#7730), честный отказ страницы (K-N) и окна при
/// смене мониторов (#7740). Живого AX и мониторов тут нет — только арифметика и сиденья.
final class WF94WindowsTests: XCTestCase {
    /// Живой замер 26.09: Odyssey G91SD — 2560×720 pt, x −3360…−800, y −575.
    static let odyssey = CGRect(x: -3360, y: -575, width: 2560, height: 720)
    /// Макбук под ним (рабочая область) и SOTSU 800×1280 правее Odyssey.
    static let macbook = CGRect(x: 0, y: 30, width: 1470, height: 900)
    static let sotsu = CGRect(x: -800, y: -575, width: 800, height: 1280)
    static let gap: CGFloat = 5

    private static func loose(_ count: Int) -> [CGRect] {
        (0..<count).map { i in
            CGRect(x: -3300 + CGFloat(i) * 150, y: -560 + CGFloat(i % 3) * 20, width: 500, height: 400)
        }
    }

    // MARK: - 1. столбцы и половинки

    /// Экран 720 держит один ряд (`minCellHeight` 360), а столбец 720 делится на две
    /// половинки по настоящему минимуму окна (357) — тем же порогом, что «под этим».
    func testOdysseyIsOneRowButSplitsInHalves() throws {
        XCTAssertEqual(ArrangeLayout.capRows(height: 720, gap: 5), 1)
        XCTAssertEqual(PimpChannel.minSplitHeight, ArrangeLayout.splitMinHeight)
        let halves = try XCTUnwrap(PimpChannel.split(CGRect(x: 0, y: -575, width: 280, height: 720),
                                                     above: false, gap: 5))
        XCTAssertEqual(halves.old.height, 357)
        XCTAssertEqual(halves.new.height, 358)
        XCTAssertEqual(ArrangeLayout.cap(width: 2560, minCellWidth: 280, gap: 5), 9)
    }

    /// Десять окон на 2560×720 — девять столбцов, правый пополам: верх и низ (#7730).
    func testTenWindowsGiveNineColumnsAndRightHalves() {
        let area = WF94WindowsTests.odyssey
        let placed = ArrangeLayout.smart(frames: WF94WindowsTests.loose(10), in: area,
                                         minCellWidth: 280, gap: 5)
        let row = ArrangeLayout.cells(cols: 9, rows: 1, count: 9, in: area, gap: 5)
        XCTAssertEqual(Set(placed.map { $0.minX }).count, 9, "девять столбцов")
        XCTAssertEqual(Array(placed[0..<8]), Array(row[0..<8]), "восемь столбцов во всю высоту")
        let right = placed.filter { $0.minX == row[8].minX }.sorted { $0.minY < $1.minY }
        XCTAssertEqual(right.count, 2, "правый столбец поделён пополам")
        XCTAssertEqual(right[0], CGRect(x: row[8].minX, y: -575, width: row[8].width, height: 357))
        XCTAssertEqual(right[1], CGRect(x: row[8].minX, y: -213, width: row[8].width, height: 358))
    }

    /// Одиннадцать — два правых пополам; девятнадцатому места нет (девять столбцов по две
    /// половинки = 18), его не трогаем.
    func testMoreWindowsSplitMoreColumnsAndLeaveTheRestAlone() {
        let area = WF94WindowsTests.odyssey
        let eleven = ArrangeLayout.smart(frames: WF94WindowsTests.loose(11), in: area,
                                         minCellWidth: 280, gap: 5)
        XCTAssertEqual(eleven.filter { $0.height == 720 }.count, 7)
        XCTAssertEqual(eleven.filter { $0.height < 720 }.count, 4)
        let many = WF94WindowsTests.loose(19)
        let placed = ArrangeLayout.smart(frames: many, in: area, minCellWidth: 280, gap: 5)
        XCTAssertEqual(placed.filter { $0.height < 720 && !many.contains($0) }.count, 18, "все девять пополам")
        XCTAssertEqual(zip(placed, many).filter { $0 == $1 }.count, 1, "одно окно не тронуто")
    }

    /// Повторное ⌥⌘A половинки узнаёт сидящими и не перекладывает (кандидат перебора `smart`).
    func testRepeatedArrangeKeepsHalves() {
        let area = WF94WindowsTests.odyssey
        let placed = ArrangeLayout.smart(frames: WF94WindowsTests.loose(10), in: area,
                                         minCellWidth: 280, gap: 5)
        XCTAssertEqual(ArrangeLayout.smart(frames: placed, in: area, minCellWidth: 280, gap: 5), placed)
        XCTAssertEqual(ArrangeLayout.smart(frames: placed.reversed(), in: area, minCellWidth: 280, gap: 5),
                       placed.reversed())
    }

    /// Окон девять и меньше десяти, а не влезло по ширине — друг под другом НЕ ставим
    /// (слово Элвиса 26.09 ~01:20): лишние остаются где стояли.
    func testFewerThanTenNeverStack() {
        let area = CGRect(x: -3360, y: -575, width: 1852, height: 720)
        let frames = WF94WindowsTests.loose(7)
        let placed = ArrangeLayout.smart(frames: frames, in: area, minCellWidth: 280, gap: 5)
        XCTAssertEqual(placed.filter { $0.height == 720 }.count, 6, "шесть в ряд")
        XCTAssertEqual(zip(placed, frames).filter { $0 == $1 }.count, 1, "седьмое не тронуто")
        XCTAssertTrue(placed.allSatisfy { $0.height == 720 || frames.contains($0) }, "по высоте не делим")
    }

    /// «Сохранить раскладку» с половинками: умная сетка их не описывает — честный отказ.
    func testSittingGridDoesNotDescribeHalves() {
        let area = WF94WindowsTests.odyssey
        let placed = ArrangeLayout.smart(frames: WF94WindowsTests.loose(10), in: area,
                                         minCellWidth: 280, gap: 5)
        XCTAssertNil(ArrangeLayout.sittingGrid(frames: placed, in: area, minCellWidth: 280, gap: 5))
        // Без половинок сетка находится, как раньше.
        let nine = ArrangeLayout.smart(frames: WF94WindowsTests.loose(9), in: area,
                                       minCellWidth: 280, gap: 5)
        XCTAssertEqual(ArrangeLayout.sittingGrid(frames: nine, in: area, minCellWidth: 280, gap: 5)?.cols, 9)
    }

    // MARK: - 2. ChatGPT справа

    /// Подставной ChatGPT: уже `minimum` не сужается и прижимается правым краем, как живой.
    private final class FakeChatGPT {
        let minimum: CGFloat
        var calls: [CGRect] = []
        init(minimum: CGFloat) { self.minimum = minimum }
        func set(_ want: CGRect) -> CGRect? {
            calls.append(want)
            guard want.width < minimum else { return want }
            return CGRect(x: want.maxX - minimum, y: want.minY, width: minimum, height: want.height)
        }
    }

    /// Семь окон Claude + ChatGPT 703 на Odyssey: ChatGPT встаёт у правого края, окнам
    /// Claude остаётся 1852 pt. При минимуме 280 — шесть в ряд, седьмое не тронуто; при 220
    /// (живой случай Элвиса) — семь в ряд.
    func testChatGPTTakesRightStripAndClaudeGetsTheRest() {
        let screens = [(full: WF94WindowsTests.macbook, usable: WF94WindowsTests.macbook),
                       (full: WF94WindowsTests.odyssey, usable: WF94WindowsTests.odyssey)]
        let claude = WF94WindowsTests.loose(7)
        let chat = CGRect(x: -2000, y: -500, width: 900, height: 600)
        for (minimum, inRow) in [(CGFloat(280), 6), (CGFloat(220), 7)] {
            let fake = FakeChatGPT(minimum: 703)
            let plan = ChatGPTWindows.reserve(screens: screens, claude: claude, chatGPT: chat,
                                              minCellWidth: minimum, gap: 5, set: fake.set)
            XCTAssertEqual(plan.chatGPT, CGRect(x: -1503, y: -575, width: 703, height: 720))
            XCTAssertEqual(fake.calls.count, 1)
            XCTAssertEqual(plan.screens[1].usable, CGRect(x: -3360, y: -575, width: 1852, height: 720))
            XCTAssertEqual(plan.screens[0].usable, WF94WindowsTests.macbook, "чужой экран как был")
            let placed = ArrangeLayout.smart(frames: claude, screens: plan.screens,
                                             minCellWidth: minimum, gap: 5)
            XCTAssertEqual(placed.filter { $0.height == 720 }.count, inRow, "минимум \(minimum)")
            XCTAssertTrue(placed.allSatisfy { $0.maxX <= -1503 - 5 || claude.contains($0) },
                          "окна Claude левее ChatGPT")
        }
    }

    /// Проверка гейта WF94: минимум ChatGPT уже известен, и он стоит у правого края своей
    /// шириной — повторная расстановка его не трогает (не уезжает за край на время зажима).
    func testChatGPTAtKnownMinimumIsLeftInPlace() {
        let screens = [(full: WF94WindowsTests.macbook, usable: WF94WindowsTests.macbook),
                       (full: WF94WindowsTests.odyssey, usable: WF94WindowsTests.odyssey)]
        let claude = (0..<6).map { CGRect(x: -3360 + CGFloat($0) * 309, y: -575, width: 304, height: 720) }
        let chat = CGRect(x: -1503, y: -575, width: 703, height: 720)
        let fake = FakeChatGPT(minimum: 703)
        let plan = ChatGPTWindows.reserve(screens: screens, claude: claude, chatGPT: chat,
                                          knownMinWidth: 703, minCellWidth: 220, gap: 5, set: fake.set)
        XCTAssertEqual(plan.chatGPT, chat)
        XCTAssertTrue(fake.calls.isEmpty, "стоит на месте — не дёргаем")
    }

    /// Целевая ширина — один столбец Claude, но не уже `minWindowWidth`.
    func testChatGPTTargetIsOneClaudeColumn() {
        let area = WF94WindowsTests.odyssey
        let want = ChatGPTWindows.target(area: area, claudeCount: 6, minCellWidth: 220, gap: 5)
        XCTAssertEqual(want.maxX, area.maxX)
        XCTAssertEqual(want.width, ((2560 - 30) / 7 as CGFloat).rounded(.down))
        // SOTSU 800 с одним окном Claude: два столбца по 397.
        XCTAssertEqual(ChatGPTWindows.target(area: WF94WindowsTests.sotsu, claudeCount: 1,
                                             minCellWidth: 280, gap: 5).width, 397)
    }

    /// ChatGPT на экране, где окон Claude нет, не трогается.
    func testChatGPTOnAnotherScreenIsLeftAlone() {
        let screens = [(full: WF94WindowsTests.macbook, usable: WF94WindowsTests.macbook),
                       (full: WF94WindowsTests.odyssey, usable: WF94WindowsTests.odyssey)]
        let fake = FakeChatGPT(minimum: 703)
        let plan = ChatGPTWindows.reserve(screens: screens, claude: WF94WindowsTests.loose(3),
                                          chatGPT: CGRect(x: 200, y: 100, width: 900, height: 700),
                                          minCellWidth: 280, gap: 5, set: fake.set)
        XCTAssertNil(plan.chatGPT)
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertEqual(plan.screens.map { $0.usable }, screens.map { $0.usable })
    }

    /// SOTSU 800 + ChatGPT 703: остаток 92 pt уже минимума — не резервируем; сдвинули и не
    /// влезло — ставим как стоял; минимум уже известен — не двигаем вовсе.
    func testNarrowScreenDoesNotReserve() {
        let screens = [(full: WF94WindowsTests.sotsu, usable: WF94WindowsTests.sotsu)]
        let claude = [CGRect(x: -790, y: -500, width: 400, height: 500)]
        let chat = CGRect(x: -700, y: 100, width: 703, height: 600)
        let fake = FakeChatGPT(minimum: 703)
        let plan = ChatGPTWindows.reserve(screens: screens, claude: claude, chatGPT: chat,
                                          minCellWidth: 280, gap: 5, set: fake.set)
        XCTAssertNil(plan.chatGPT)
        XCTAssertEqual(plan.screens[0].usable, WF94WindowsTests.sotsu)
        XCTAssertEqual(fake.calls.last, chat, "ChatGPT вернули как стоял")
        let again = FakeChatGPT(minimum: 703)
        let known = ChatGPTWindows.reserve(screens: screens, claude: claude, chatGPT: chat,
                                           knownMinWidth: 703, minCellWidth: 280, gap: 5, set: again.set)
        XCTAssertNil(known.chatGPT)
        XCTAssertTrue(again.calls.isEmpty, "минимум известен — не дёргаем")
    }

    /// Список оконного сервера: только слой 0 нужных процессов, служебные мимо, спереди назад.
    func testChatGPTLayerZeroFilter() {
        func info(_ pid: Int32, _ layer: Int, _ rect: CGRect, alpha: Double = 1) -> [String: Any] {
            [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: NSNumber(value: layer),
             kCGWindowBounds as String: rect.dictionaryRepresentation as NSDictionary,
             kCGWindowAlpha as String: NSNumber(value: alpha)]
        }
        let front = CGRect(x: -1503, y: -575, width: 703, height: 720)
        let list = [info(7, 3, front), info(9, 0, front), info(7, 0, CGRect(x: 0, y: 0, width: 50, height: 50)),
                    info(7, 0, front, alpha: 0), info(7, 0, front)]
        let found = ChatGPTWindows.layerZero(list, pids: [7])
        XCTAssertEqual(found.map { $0.frame }, [front])
    }

    // MARK: - 3. новое окно справа

    /// «Справа» — навязанный порядок с якорем: новое окно последним среди окон Claude своего
    /// экрана, левее ChatGPT; сидящие сохраняют порядок, на другом экране никто не двигается
    /// (WF105, #8071: при якоре окна чужого экрана не трогаются вовсе; сетка — `least`).
    func testNewWindowGoesRightmostLeftOfChatGPT() {
        let odyssey = WF94WindowsTests.odyssey, macbook = WF94WindowsTests.macbook
        let rest = CGRect(x: -3360, y: -575, width: 1852, height: 720)
        let screens = [(full: macbook, usable: macbook), (full: odyssey, usable: rest)]
        let row = ArrangeLayout.cells(cols: 5, rows: 1, count: 5, in: rest, gap: 5)
        let four = ArrangeLayout.cells(cols: 4, rows: 1, count: 4, in: rest, gap: 5)
        // Стоят 0, 1 и 3 пятой сетки — дыра на месте 2; новое окно родилось уступом, на
        // макбуке своё окно.
        let fresh = CGRect(x: row[1].minX + 40, y: -535, width: 400, height: 600)
        let mac = CGRect(x: 100, y: 60, width: 600, height: 500)
        let frames = [row[0], row[1], row[3], mac, fresh]
        let placed = ArrangeLayout.smart(frames: frames, screens: screens, minCellWidth: 280, gap: 5,
                                         order: [0, 1, 2, 3, 4], anchor: 4)
        // Четыре окна — четыре столбца на всю ширину; порядок навязан — прежние слева
        // направо, новое окно последним, а не в дыру посередине, как до WF94.
        XCTAssertEqual(Array(placed[0..<3]), Array(four[0..<3]), "дыры нет, порядок прежний")
        XCTAssertEqual(placed[4], four[3], "новое — самым правым среди окон Claude")
        XCTAssertLessThanOrEqual(placed[4].maxX, -1503 - 5, "левее ChatGPT")
        XCTAssertEqual(placed[3], mac, "окно на макбуке не тронуто")
    }

    /// Десятое окно справа — под правым столбцом (#7730: «тот внизу открывается под ним»).
    func testTenthNewWindowOpensUnderRightColumn() {
        let area = WF94WindowsTests.odyssey
        let row = ArrangeLayout.cells(cols: 9, rows: 1, count: 9, in: area, gap: 5)
        let fresh = CGRect(x: -3000, y: -500, width: 500, height: 400)
        let placed = ArrangeLayout.smart(frames: row + [fresh], in: area, minCellWidth: 280, gap: 5,
                                         order: Array(0..<10))
        XCTAssertEqual(Array(placed[0..<8]), Array(row[0..<8]), "восемь столбцов на месте")
        XCTAssertEqual(placed[8].minY, -575)
        XCTAssertEqual(placed[9], CGRect(x: row[8].minX, y: -213, width: row[8].width, height: 358))
    }

    // MARK: - 4. честная ошибка канала

    func testNewWindowRunReadsState() throws {
        let run = try XCTUnwrap(NewWindowRun.parse([
            "at": 1_790_000_000_000.0, "step": "draft", "state": "draft", "runs": 4,
        ] as [String: Any]))
        XCTAssertEqual(run.state, "draft")
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(run.failure(since: at.addingTimeInterval(-1)), "draft")
        XCTAssertNil(run.failure(since: at), "прошлый исход не наш")
        let ok = NewWindowRun(at: at, step: "back", handoff: "", chat: "", state: "ok")
        XCTAssertNil(ok.failure(since: .distantPast))
        let junk = try XCTUnwrap(NewWindowRun.parse(["at": 1.0, "runs": "x"] as [String: Any]))
        XCTAssertEqual(junk.state, "")
    }

    private final class Rig {
        var now = PimpChannel.date("2026-09-25T02:10:31Z")!
        var windows: [PimpWindow] = []
        var chatGPT: PimpWindow?
        var run: NewWindowRun?
        var restored: (placed: Int, missing: Int)?
        var notices: [String] = []
        var saved: [WindowLayout] = []
        var closed: [CGWindowID] = []
        var popouts: [String] = []

        func seats() -> PimpSeats {
            var seats = PimpSeats(
                claudeRunning: { true },
                windows: { [unowned self] in self.windows },
                projects: { [Project(folder: URL(fileURLWithPath: "/tmp", isDirectory: true), name: "Dictator",
                                     lastFocusedAt: 0)] },
                arrangeSmart: { [unowned self] ids, _, _ in
                    ids.compactMap { id in self.windows.first { $0.id == id } }
                },
                saveLayout: { [unowned self] layout in
                    self.saved.append(layout)
                    return true
                },
                smartGrid: { frames in
                    (grid: LayoutGrid(cols: 2, rows: 1), cells: frames)
                },
                isMainWindow: { $0 == "Claude" },
                openChat: { [unowned self] chat, _, _ in self.popouts.append(chat) },
                notice: { [unowned self] text in self.notices.append(text) },
                close: { [unowned self] id in
                    self.closed.append(id)
                    return true
                },
                lastChat: { _ in (chat: "local_0f000000-0000-4000-8000-000000000001", title: "Старый чат") })
            seats.chatGPT = { [unowned self] in self.chatGPT }
            seats.newWindowRun = { [unowned self] in self.run }
            seats.restoreScreens = { [unowned self] in self.restored }
            return seats
        }
    }

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf94-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func channel(_ rig: Rig, in box: URL) -> PimpChannel {
        let channel = PimpChannel(directory: box, now: { rig.now })
        channel.seats = rig.seats()
        channel.start()
        return channel
    }

    private func ask(_ id: String, _ action: String, _ extra: String = "", at: Date, in box: URL) {
        let body = "{\"id\":\"\(id)\",\"at\":\"\(PimpChannel.stampText(at))\",\"action\":\"\(action)\","
            + "\"from\":\"\"\(extra)}"
        try? Data(body.utf8).write(to: box.appendingPathComponent(id + ".json"))
    }

    private func answer(_ id: String, in box: URL) throws -> String {
        try String(contentsOf: box.appendingPathComponent(id + ".result.json"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: WF94WindowsTests.fixtures.appendingPathComponent(name), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ответ `windows` с ChatGPT — побайтно эталон: запись последней, с полем `app`.
    func testWindowsAnswerListsChatGPTApart() throws {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: -3360, y: -575, width: 304, height: 720))]
        rig.chatGPT = PimpWindow(id: 0, title: "ChatGPT", frame: CGRect(x: -1503, y: -575, width: 703, height: 720))
        let pimp = channel(rig, in: box)
        ask("1790000000000-0940", "windows", at: rig.now, in: box)
        pimp.tick()
        XCTAssertEqual(try answer("1790000000000-0940", in: box), try fixture("windows-chatgpt.result.json"))
    }

    /// `layout-save` и `close-window` с открытым ChatGPT — как без него.
    func testLayoutSaveAndCloseIgnoreChatGPT() throws {
        var answers: [[String]] = []
        for withChatGPT in [false, true] {
            let box = makeTemp(), rig = Rig()
            rig.windows = [
                PimpWindow(id: 1, title: "Claude", chat: "local_a", folder: "/tmp/A",
                           frame: CGRect(x: 0, y: 0, width: 500, height: 500)),
                PimpWindow(id: 2, title: "Второй", chat: "local_b", folder: "/tmp/B",
                           frame: CGRect(x: 505, y: 0, width: 500, height: 500)),
            ]
            if withChatGPT {
                rig.chatGPT = PimpWindow(id: 0, title: "ChatGPT", frame: CGRect(x: 1010, y: 0, width: 703, height: 500))
            }
            let pimp = channel(rig, in: box)
            ask("1790000000000-0950", "layout-save", ",\"name\":\"Утро\"", at: rig.now, in: box)
            pimp.tick()
            ask("1790000000000-0951", "close-window", ",\"project\":\"/tmp/B\"", at: rig.now, in: box)
            pimp.tick()
            answers.append([try answer("1790000000000-0950", in: box), try answer("1790000000000-0951", in: box)])
            XCTAssertEqual(rig.saved.first?.cells.count, 2)
            XCTAssertEqual(rig.closed, [2])
        }
        XCTAssertEqual(answers[0], answers[1])
    }

    /// Свежая цепочка страницы сорвалась — `chat-not-created` сразу, побайтно эталон; старый
    /// исход (до начала работы) не в счёт — прежние 40 с и `window-missing`.
    func testNewWindowRefusedAtOnceOnlyByFreshRun() throws {
        let box = makeTemp(), rig = Rig()
        rig.now = PimpChannel.date("2026-09-25T02:11:00Z")!
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 0, width: 600, height: 600))]
        rig.run = NewWindowRun(at: rig.now.addingTimeInterval(-60), step: "draft", handoff: "", chat: "",
                               state: "draft")
        let pimp = channel(rig, in: box)
        ask("1790000000000-0941", "new-window", ",\"project\":\"Dictator\"", at: rig.now, in: box)
        pimp.tick()
        rig.now = rig.now.addingTimeInterval(2)
        pimp.tick()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: box.appendingPathComponent("1790000000000-0941.result.json").path), "старый исход не наш")
        rig.now = rig.now.addingTimeInterval(2)
        rig.run = NewWindowRun(at: rig.now, step: "draft", handoff: "", chat: "", state: "draft")
        pimp.tick()
        XCTAssertEqual(try answer("1790000000000-0941", in: box), try fixture("new-window-not-created.error.json"))
        XCTAssertFalse(pimp.isWaitingPage)

        // Исход «всё хорошо» отказа не даёт — ждём окно весь срок канала (65 с с WF102).
        rig.run = nil
        ask("1790000000000-0942", "new-window", ",\"project\":\"Dictator\"", at: rig.now, in: box)
        pimp.tick()
        XCTAssertTrue(pimp.isWaitingPage)
        rig.now = rig.now.addingTimeInterval(1)
        rig.run = NewWindowRun(at: rig.now, step: "stay", handoff: "", chat: "", state: "ok")
        pimp.tick()
        XCTAssertTrue(pimp.isWaitingPage)
        rig.now = rig.now.addingTimeInterval(PimpChannel.newWindowSeconds + 1)
        pimp.tick()
        let late = try answer("1790000000000-0942", in: box)
        XCTAssertTrue(late.contains("\"error\":\"window-missing\""), late)
    }

    /// Работа из меню (id nil) отказ получает плашкой — текст канала, не MenuModel.
    func testMenuJobGetsNoticeOnFailedRun() {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 0, width: 600, height: 600))]
        let pimp = channel(rig, in: box)
        let project = Project(folder: URL(fileURLWithPath: "/tmp", isDirectory: true), name: "Dictator",
                              lastFocusedAt: 0)
        XCTAssertTrue(pimp.startLast(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(rig.popouts.count, 1)
        rig.now = rig.now.addingTimeInterval(2)
        rig.run = NewWindowRun(at: rig.now, step: "popout", handoff: "", chat: "", state: "popout-failed")
        pimp.tick()
        XCTAssertEqual(rig.notices, ["«Старый чат»: чат не вынесся в окно — вынеси его руками"])
        XCTAssertEqual(PimpChannel.notCreatedNotice(state: "draft", name: ""),
                       "чат не создан — в поле главного окна черновик")
    }

    /// WF101 (z4-r03): все отказы страницы — словами, без сырого кода исхода.
    func testNotCreatedNoticeHasWordsForEveryFailedState() {
        for state in NewWindowRun.failedStates {
            let text = PimpChannel.notCreatedNotice(state: state, name: "Мой чат")
            XCTAssertFalse(text.contains(state), text)
            XCTAssertTrue(text.hasPrefix("«Мой чат»: чат не"), text)
        }
        XCTAssertEqual(PimpChannel.notCreatedNotice(state: "boom", name: ""), "чат не создан (boom)")
    }

    /// WF101 (z4-r02): «🪟 Новое окно ▸ проект» из меню без окна за срок канала — плашка с именем проекта
    /// и без «нажми ещё раз» (чат мог создаться, повтор завёл бы второй).
    func testMenuNewWindowTimeoutNamesProject() {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 0, width: 600, height: 600))]
        let pimp = channel(rig, in: box)
        let project = Project(folder: URL(fileURLWithPath: "/tmp", isDirectory: true), name: "Dictator",
                              lastFocusedAt: 0)
        XCTAssertTrue(pimp.startNewWindow(project: project))
        rig.now = rig.now.addingTimeInterval(PimpChannel.newWindowSeconds + 1)
        pimp.tick()
        let text = rig.notices.last ?? ""
        XCTAssertTrue(text.contains("Dictator"), text)
        XCTAssertFalse(text.contains("нажми ещё раз"), text)
    }

    // MARK: - 5. окна при смене мониторов

    func testScreensRestoreAnswersByFixture() throws {
        let box = makeTemp(), rig = Rig()
        rig.now = PimpChannel.date("2026-09-25T02:12:02Z")!
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 0, width: 600, height: 600))]
        rig.restored = (placed: 7, missing: 1)
        let pimp = channel(rig, in: box)
        let request = try fixture("screens-restore.request.json")
        XCTAssertEqual(PimpRequest.parse(Data(request.utf8))?.action, .screensRestore)
        rig.now = PimpChannel.date("2026-09-25T02:12:02Z")!
        try Data(request.utf8).write(to: box.appendingPathComponent("1790000000000-0942.json"))
        pimp.tick()
        XCTAssertEqual(try answer("1790000000000-0942", in: box), try fixture("screens-restore.result.json"))

        rig.restored = nil
        rig.now = PimpChannel.date("2026-09-25T02:12:30Z")!
        ask("1790000000000-0943", "screens-restore", at: rig.now, in: box)
        pimp.tick()
        XCTAssertEqual(try answer("1790000000000-0943", in: box), try fixture("screens-restore.error.json"))
    }

    func testScreenKeyNamesSizeAndOrigin() {
        let mac = ScreenSpec(name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        let big = ScreenSpec(name: "Odyssey G91SD", frame: CGRect(x: -3360, y: -575, width: 2560, height: 720))
        XCTAssertEqual(ScreenLayoutKeeper.key([mac, big]), ScreenLayoutKeeper.key([big, mac]),
                       "порядок NSScreen.screens ключ не меняет")
        XCTAssertEqual(ScreenLayoutKeeper.key([mac]), "Built-in@0,0,1470x956")
        let moved = ScreenSpec(name: "Odyssey G91SD", frame: CGRect(x: 1470, y: -575, width: 2560, height: 720))
        XCTAssertNotEqual(ScreenLayoutKeeper.key([mac, big]), ScreenLayoutKeeper.key([mac, moved]),
                          "перестановка мониторов — другой ключ")
    }

    /// Стенд хранителя: мониторы, окна и ChatGPT в памяти, файл во временной папке.
    private final class Desk {
        static let mac = ScreenSpec(name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        static let big = ScreenSpec(name: "Odyssey", frame: CGRect(x: -3360, y: -575, width: 2560, height: 720))
        var screens = [Desk.mac, Desk.big]
        var windows: [PimpWindow] = []
        var chatGPT: CGRect?
        var busy = false
        var applied: [(moves: [PimpMove], chatGPT: CGRect?)] = []
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let keeper: ScreenLayoutKeeper

        init(url: URL) {
            keeper = ScreenLayoutKeeper(store: ScreenLayoutStore(url: url))
            keeper.screens = { [unowned self] in self.screens }
            keeper.windows = { [unowned self] in
                WindowSnapshotStore.windows(from: self.windows, isMain: { $0 == "Claude" }, screen: { _ in "" })
            }
            keeper.live = { [unowned self] in self.windows }
            keeper.isMain = { $0 == "Claude" }
            keeper.chatGPT = { [unowned self] in self.chatGPT }
            keeper.busy = { [unowned self] in self.busy }
            keeper.apply = { [unowned self] moves, gpt in
                self.applied.append((moves: moves, chatGPT: gpt))
                for move in moves {
                    guard let index = self.windows.firstIndex(where: { $0.id == move.id }) else { continue }
                    let w = self.windows[index]
                    self.windows[index] = PimpWindow(id: w.id, title: w.title, chat: w.chat, folder: w.folder,
                                                     frame: move.frame)
                }
                if let gpt = gpt { self.chatGPT = gpt }
            }
        }

        /// Шаги общего тика по 2 с.
        func run(_ seconds: TimeInterval) {
            var left = seconds
            while left > 0 {
                keeper.tick(at: now)
                now = now.addingTimeInterval(2)
                left -= 2
            }
        }
    }

    private static let onOdyssey: [PimpWindow] = [
        PimpWindow(id: 1, title: "Claude", frame: CGRect(x: -3360, y: -575, width: 600, height: 720)),
        PimpWindow(id: 2, title: "Пимп", chat: "local_b", frame: CGRect(x: -2755, y: -575, width: 600, height: 720)),
        PimpWindow(id: 3, title: "Вкуснофф", chat: "local_c", frame: CGRect(x: -2150, y: -575, width: 600, height: 720)),
    ]

    /// X → Y → X: окна встают как стояли на X (и повтор через 5 с); закрытый чат не открываем.
    func testScreensChangeBackRestoresFrames() throws {
        let url = makeTemp().appendingPathComponent(ScreenLayoutStore.fileName)
        let desk = Desk(url: url)
        desk.windows = WF94WindowsTests.onOdyssey
        desk.chatGPT = CGRect(x: -1503, y: -575, width: 703, height: 720)
        desk.run(24)
        XCTAssertEqual(desk.keeper.writes, 1, "две выборки подряд совпали — записали")
        XCTAssertTrue(desk.keeper.status.hasPrefix("1/1/"))
        let stored = ScreenLayoutStore(url: url).load()
        XCTAssertEqual(stored.first?.windows.map { $0.chat }, ["main", "local_b", "local_c"])
        XCTAssertEqual(stored.first?.chatGPT, desk.chatGPT)

        // Odyssey выключили: macOS свалила окна на макбук. Чат «Вкуснофф» закрыли.
        desk.screens = [Desk.mac]
        desk.keeper.noteScreensChanged(at: desk.now)
        desk.windows = [
            PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 30, width: 600, height: 700)),
            PimpWindow(id: 2, title: "Пимп", chat: "local_b", frame: CGRect(x: 40, y: 70, width: 600, height: 700)),
        ]
        desk.chatGPT = CGRect(x: 200, y: 30, width: 703, height: 700)
        desk.run(40)
        XCTAssertTrue(desk.applied.isEmpty, "набор новый — возвращать нечего")
        XCTAssertEqual(desk.keeper.writes, 2, "набор «один макбук» записан после тишины")

        // Odyssey вернули — окна встают как стояли, закрытый чат не открываем.
        desk.screens = [Desk.mac, Desk.big]
        desk.keeper.noteScreensChanged(at: desk.now)
        desk.run(4)
        XCTAssertEqual(desk.applied.count, 1)
        XCTAssertEqual(desk.windows.map { $0.frame }, Array(WF94WindowsTests.onOdyssey[0..<2]).map { $0.frame })
        XCTAssertEqual(desk.chatGPT, CGRect(x: -1503, y: -575, width: 703, height: 720))
        XCTAssertEqual(desk.keeper.restoreNow()?.missing, 1, "«Вкуснофф» закрыт — не нашёлся")
        desk.run(8)
        XCTAssertEqual(desk.applied.count, 3, "повтор через 5 с и ручной возврат")
    }

    /// «A → A» (сон, док): уведомления есть, набор тот же — ничего не возвращаем; и пока
    /// после уведомления не прошло 20 с, не пишем даже совпавшие выборки (гонка уведомления).
    func testSameScreensAfterNoticeDoNothingAndWaitToWrite() {
        let url = makeTemp().appendingPathComponent(ScreenLayoutStore.fileName)
        let desk = Desk(url: url)
        desk.windows = WF94WindowsTests.onOdyssey
        desk.run(24)
        XCTAssertEqual(desk.keeper.writes, 1)
        // Окна подвинули и тут же пришло уведомление: 20 с выборки не пишут.
        desk.windows[0] = PimpWindow(id: 1, title: "Claude", frame: CGRect(x: -3360, y: -575, width: 500, height: 720))
        desk.keeper.noteScreensChanged(at: desk.now)
        desk.run(18)
        XCTAssertEqual(desk.keeper.writes, 1, "после уведомления не прошло 20 с")
        XCTAssertTrue(desk.applied.isEmpty, "A → A — ничего")
        desk.run(24)
        XCTAssertEqual(desk.keeper.writes, 2)
        // Мониторы мигнули X → Y → X быстрее тишины — это тоже «A → A».
        desk.screens = [Desk.mac]
        desk.run(0.5)
        desk.screens = [Desk.mac, Desk.big]
        desk.run(6)
        XCTAssertTrue(desk.applied.isEmpty)
    }

    /// Проверка гейта WF94: автовозврат сорвался (канал занят дольше минуты), выборка через
    /// 20 с переписала запись сбитой раскладкой — ручной возврат всё равно ставит окна как до смены.
    func testManualRestoreAfterFailedAutoRestoreUsesRecordBeforeChange() {
        let url = makeTemp().appendingPathComponent(ScreenLayoutStore.fileName)
        let desk = Desk(url: url)
        desk.windows = WF94WindowsTests.onOdyssey
        desk.run(24)
        desk.screens = [Desk.mac]
        let shuffled = WF94WindowsTests.onOdyssey.map {
            PimpWindow(id: $0.id, title: $0.title, chat: $0.chat, frame: CGRect(x: -3000, y: -575, width: 500, height: 500))
        }
        desk.windows = shuffled
        desk.run(40)
        desk.screens = [Desk.mac, Desk.big]
        desk.busy = true
        desk.run(70)
        XCTAssertTrue(desk.applied.isEmpty, "канал занят больше минуты — автовозврат брошен")
        desk.busy = false
        desk.run(40)
        XCTAssertTrue(desk.applied.isEmpty)
        XCTAssertNotNil(desk.keeper.restoreNow(at: desk.now))
        XCTAssertEqual(desk.windows.map { $0.frame }, WF94WindowsTests.onOdyssey.map { $0.frame },
                       "ручной возврат — по записи до смены, а не по переписанной")
    }

    /// Канал занят — возврат ждёт, освободился — идёт.
    func testScreensRestoreWaitsForBusyChannel() {
        let url = makeTemp().appendingPathComponent(ScreenLayoutStore.fileName)
        let desk = Desk(url: url)
        desk.windows = WF94WindowsTests.onOdyssey
        desk.run(24)
        desk.screens = [Desk.mac]
        desk.windows = WF94WindowsTests.onOdyssey.map {
            PimpWindow(id: $0.id, title: $0.title, chat: $0.chat, frame: CGRect(x: 0, y: 30, width: 500, height: 500))
        }
        desk.run(40)
        desk.screens = [Desk.mac, Desk.big]
        desk.busy = true
        desk.run(10)
        XCTAssertTrue(desk.applied.isEmpty, "канал занят — ждём")
        desk.busy = false
        desk.run(2)
        XCTAssertEqual(desk.applied.count, 1)
        XCTAssertEqual(desk.windows.map { $0.frame }, WF94WindowsTests.onOdyssey.map { $0.frame })
    }

    func testScreenLayoutStoreRoundTrip() {
        let layout = ScreenLayout(key: "Built-in@0,0,1470x956", at: PimpChannel.date("2026-09-26T02:00:00Z")!,
                                  windows: [SnapshotWindow(chat: "main", folder: "", title: "Claude",
                                                           frame: CGRect(x: 0, y: 30, width: 600, height: 700),
                                                           screen: "Built-in")],
                                  chatGPT: nil)
        XCTAssertEqual(ScreenLayoutStore.parse(Data(ScreenLayoutStore.json([layout]).utf8)), [layout])
        XCTAssertTrue(ScreenLayoutStore.json([layout]).contains("\"chatgpt\":null"))
        XCTAssertEqual(ScreenLayoutStore.parse(Data("{\"version\":2}".utf8)), [])
        let many = (0..<25).map { i in
            ScreenLayout(key: "k\(i)", at: layout.at, windows: [], chatGPT: nil)
        }.reduce([ScreenLayout]()) { ScreenLayoutStore.merge($1, into: $0) }
        XCTAssertEqual(many.count, ScreenLayoutStore.limit)
        XCTAssertEqual(many.first?.key, "k24")
    }
}
