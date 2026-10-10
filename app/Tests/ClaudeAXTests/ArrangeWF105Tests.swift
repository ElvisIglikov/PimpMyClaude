import CoreGraphics
import XCTest
@testable import ClaudeAX

/// WF105, #8071: «расставь» делит всю ширину экрана, `--order` находит окна.
final class ArrangeWF105Tests: XCTestCase {
    // MARK: - данные Элвиса 29.09

    private static let root = "/Users/dev/Projects/"
    private static let vkusnoffChat = "local_e0cf98f0-b729-459e-9ff3-7fd854aa7230"

    /// Три окна Одиссея, как их показал `windows --json` (рамки — ячейки 6×1 плюс хвост).
    private static func elvisWindows(vkusnoffFolder: String = root + "VkusnoffKz") -> [PimpWindow] {
        [
            PimpWindow(id: 11, title: "Dictator", chat: "local_11111111-0000-0000-0000-000000000001",
                       folder: root + "Dictator",
                       frame: CGRect(x: 0, y: 25, width: 426, height: 695)),
            PimpWindow(id: 12, title: "VkusnoffKz параллельные workflow", chat: vkusnoffChat,
                       folder: vkusnoffFolder,
                       frame: CGRect(x: 426, y: 25, width: 426, height: 695)),
            PimpWindow(id: 13, title: "Marketolog", chat: "local_11111111-0000-0000-0000-000000000003",
                       folder: root + "Marketolog",
                       frame: CGRect(x: 1400, y: 100, width: 600, height: 500)),
        ]
    }

    func testOrderFindsElvisWindowsByMarkedName() {
        let windows = ArrangeWF105Tests.elvisWindows()
        let sorted = PimpChannel.order(of: windows, by: ["🟢 Dictator", "VkusnoffKz", "Marketolog"],
                                       base: [2, 1, 0])
        XCTAssertEqual(sorted.missing, [], "все три проекта названы — все найдены")
        XCTAssertEqual(sorted.order, [0, 1, 2])
        XCTAssertEqual(sorted.unknown, 0)
    }

    func testOrderTakesChatIdAndOtherCase() {
        let windows = ArrangeWF105Tests.elvisWindows()
        let sorted = PimpChannel.order(of: windows,
                                       by: ["marketolog", ArrangeWF105Tests.vkusnoffChat],
                                       base: [0, 1, 2])
        XCTAssertEqual(sorted.missing, [])
        XCTAssertEqual(sorted.order, [2, 1, 0])
    }

    /// Чат окна опознан, а папки нет (индекс молчит): по `local_…` оно первое и в хвост
    /// «без папки» второй раз не попадает.
    func testOrderByChatWithoutFolderIsNotDuplicated() {
        let windows = ArrangeWF105Tests.elvisWindows(vkusnoffFolder: "")
        let sorted = PimpChannel.order(of: windows, by: [ArrangeWF105Tests.vkusnoffChat], base: [0, 1, 2])
        XCTAssertEqual(sorted.order, [1, 0, 2])
        XCTAssertEqual(sorted.unknown, 0)
        XCTAssertEqual(sorted.missing, [])
    }

    /// Причина живого «не нашёл окна: VkusnoffKz»: чат окна не опознан — папка пустая.
    func testOrderMissesWindowWhoseChatIsUnknown() {
        let windows = ArrangeWF105Tests.elvisWindows(vkusnoffFolder: "")
        let sorted = PimpChannel.order(of: windows, by: ["🟢 Dictator", "VkusnoffKz", "Marketolog"],
                                       base: [0, 1, 2])
        XCTAssertEqual(sorted.missing, ["VkusnoffKz"])
    }

    /// Маркер с именем — одна сверка; путь и имя без маркера — как раньше.
    func testMatchesWindowKeepsFolderRules() {
        let window = ArrangeWF105Tests.elvisWindows()[0]
        XCTAssertTrue(PimpChannel.matches(window: window, entry: ArrangeWF105Tests.root + "Dictator"))
        XCTAssertTrue(PimpChannel.matches(window: window, entry: "Dictator"))
        XCTAssertTrue(PimpChannel.matches(window: window, entry: "🟢 Dictator"))
        XCTAssertTrue(PimpChannel.matches(window: window, entry: "dictator"))
        XCTAssertFalse(PimpChannel.matches(window: window, entry: "DictatorIOS"))
        XCTAssertFalse(PimpChannel.matches(window: window, entry: "🟢"))
        XCTAssertFalse(PimpChannel.matches(window: window, entry: "Dict"))
        // `matches(folder:)` (отбор окон других экранов для `center`) не расширен.
        XCTAssertFalse(PimpChannel.matches(folder: window.folder, entry: "🟢 Dictator"))
    }

    // MARK: - канал: неопознанный чат — переспросить карту чатов один раз

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pimp-wf105-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func result(_ id: String, in box: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: box.appendingPathComponent(id + ".result.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    func testArrangeOrderAsksChatsAgainWhenWindowUnknown() throws {
        let box = makeTemp()
        var now = PimpChannel.date("2026-09-29T09:18:00Z")!
        var known = false
        var asked: [Date] = []
        var answered = false
        var smart: [[CGWindowID]] = []
        let channel = PimpChannel(directory: box, now: { now })
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { ArrangeWF105Tests.elvisWindows(vkusnoffFolder: known ? ArrangeWF105Tests.root + "VkusnoffKz" : "") }
        seats.arrangeSmart = { ids, _, _ in
            smart.append(ids)
            return ArrangeWF105Tests.elvisWindows().filter { ids.contains($0.id) }
        }
        seats.demandChats = { asked.append($0) }
        seats.chatsAnswered = { _ in answered }
        channel.seats = seats
        channel.start()
        let body = "{\"id\":\"r1\",\"at\":\"\(PimpChannel.stampText(now))\",\"action\":\"arrange\","
            + "\"from\":\"\",\"order\":[\"🟢 Dictator\",\"VkusnoffKz\",\"Marketolog\"]}"
        try Data(body.utf8).write(to: box.appendingPathComponent("r1.json"))

        channel.tick()
        XCTAssertEqual(asked.count, 1, "карту чатов спросили")
        XCTAssertNil(result("r1", in: box), "ответа ещё нет — ждём круга")
        XCTAssertTrue(smart.isEmpty)
        XCTAssertTrue(channel.isBusy)

        now = now.addingTimeInterval(2)
        channel.tick()
        XCTAssertNil(result("r1", in: box), "круг не пришёл — ждём дальше")

        known = true
        answered = true
        now = now.addingTimeInterval(2)
        channel.tick()
        let answer = try XCTUnwrap(result("r1", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["missing"] as? [String], [])
        XCTAssertEqual(smart, [[11, 12, 13]])
        XCTAssertEqual(asked.count, 1, "переспросили ровно один раз")
        XCTAssertFalse(channel.isBusy)
    }

    func testArrangeOrderAnswersAfterWaitEvenIfStillUnknown() throws {
        let box = makeTemp()
        var now = PimpChannel.date("2026-09-29T09:18:00Z")!
        var asked = 0
        let channel = PimpChannel(directory: box, now: { now })
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { ArrangeWF105Tests.elvisWindows(vkusnoffFolder: "") }
        seats.arrangeSmart = { ids, _, _ in ArrangeWF105Tests.elvisWindows().filter { ids.contains($0.id) } }
        seats.demandChats = { _ in asked += 1 }
        seats.chatsAnswered = { _ in false }
        channel.seats = seats
        channel.start()
        let body = "{\"id\":\"r2\",\"at\":\"\(PimpChannel.stampText(now))\",\"action\":\"arrange\","
            + "\"from\":\"\",\"order\":[\"VkusnoffKz\"]}"
        try Data(body.utf8).write(to: box.appendingPathComponent("r2.json"))
        channel.tick()
        XCTAssertNil(result("r2", in: box))
        now = now.addingTimeInterval(PimpChannel.chatsWaitSeconds + 1)
        channel.tick()
        let answer = try XCTUnwrap(result("r2", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["missing"] as? [String], ["VkusnoffKz"], "честно: окна не нашли")
        XCTAssertEqual(asked, 1)
    }

    // MARK: - умная расстановка: всегда `least` столбцов

    /// Одиссей: рабочая 2560×720 от 25; потолок 9 столбцов при минимуме 280.
    private static let odyssey = CGRect(x: 0, y: 25, width: 2560, height: 695)

    func testThreeWindowsTwoSeatedInSixColumnsTakeWholeWidth() {
        let six = ArrangeLayout.cells(cols: 6, rows: 1, count: 6, in: ArrangeWF105Tests.odyssey)
        let frames = [six[0], six[1], CGRect(x: 1500, y: 100, width: 600, height: 500)]
        let placed = ArrangeLayout.smart(frames: frames, in: ArrangeWF105Tests.odyssey, minCellWidth: 280)
        let three = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: ArrangeWF105Tests.odyssey)
        XCTAssertEqual(placed, three, "три ячейки на всю ширину, справа не пусто")
        XCTAssertEqual(placed.map { $0.maxX }.max(), ArrangeWF105Tests.odyssey.maxX)
    }

    func testWindowsSeatedInLeastGridDoNotMove() {
        let three = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: ArrangeWF105Tests.odyssey)
        // Окна стоят в ячейках «наоборот» — сидящих не перекладывают.
        let frames = [three[2], three[0], three[1]]
        XCTAssertEqual(ArrangeLayout.smart(frames: frames, in: ArrangeWF105Tests.odyssey, minCellWidth: 280),
                       frames)
    }

    /// Новое окно на MacBook: окна Одиссея из широкой сетки не трогаем вовсе.
    func testNewWindowOnMacBookLeavesOdysseyAlone() {
        let odysseyFull = CGRect(x: 0, y: 0, width: 2560, height: 720)
        let macFull = CGRect(x: 0, y: 720, width: 1512, height: 982)
        let macUsable = CGRect(x: 0, y: 720 + 32, width: 1512, height: 950)
        let six = ArrangeLayout.cells(cols: 6, rows: 1, count: 6, in: ArrangeWF105Tests.odyssey)
        let mac = CGRect(x: 100, y: 800, width: 700, height: 800)
        let fresh = CGRect(x: 900, y: 800, width: 400, height: 600)
        let frames = [six[0], six[1], six[2], mac, fresh]
        let placed = ArrangeLayout.smart(frames: frames,
                                         screens: [(full: odysseyFull, usable: ArrangeWF105Tests.odyssey),
                                                   (full: macFull, usable: macUsable)],
                                         minCellWidth: 280, order: [3, 4], anchor: 4)
        XCTAssertEqual(Array(placed[0..<3]), Array(frames[0..<3]), "окна Одиссея на месте")
        XCTAssertEqual(Array(placed[3..<5]),
                       ArrangeLayout.cells(cols: 2, rows: 1, count: 2, in: macUsable))
    }

    /// «Главный по центру», тесно (#8123): 8 окон на Одиссее при минимуме 220 — 4 слева, главный, 3 справа,
    /// боковые одной ширины, главный — треть; встык до правого края. Раньше — «экран мал».
    func testCenterTightEightWindowsFourLeftThreeRight() {
        let odyssey = CGRect(x: -800, y: -720, width: 2560, height: 720)
        XCTAssertTrue(ArrangeLayout.centerFits(count: 8, in: odyssey, minCellWidth: 220, gap: 2))
        XCTAssertEqual(ArrangeLayout.centerHubIndex(count: 8, in: odyssey, minCellWidth: 220, gap: 2), 4)
        let cells = ArrangeLayout.frames(count: 8, in: odyssey, mode: .center, minCellWidth: 220, gap: 2)
        XCTAssertEqual(cells.count, 8)
        XCTAssertEqual(cells.first?.minX, odyssey.minX)
        XCTAssertEqual(cells.last?.maxX, odyssey.maxX, "правый край — встык")
        let sides = cells.enumerated().filter { $0.offset != 4 }.map { $0.element.width }
        XCTAssertTrue(sides.allSatisfy { $0 >= 220 }, "боковые не уже минимума: \(sides)")
        XCTAssertLessThanOrEqual((sides.max() ?? 0) - (sides.min() ?? 0), 1, "боковые одной ширины")
        XCTAssertGreaterThan(cells[4].width, sides.max()! * 2, "главный заметно шире")
        for i in 1..<cells.count { XCTAssertEqual(cells[i].minX - cells[i - 1].maxX, 2, accuracy: 1, "зазор \(i)") }
        // Семь окон по-прежнему тремя третями (не тесно) — главный на 3-м месте.
        XCTAssertEqual(ArrangeLayout.centerHubIndex(count: 7, in: odyssey, minCellWidth: 220, gap: 2), 3)
    }
}
