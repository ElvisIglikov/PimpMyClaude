import CoreGraphics
import XCTest
@testable import ClaudeAX

/// «Главный по центру» клетками (WF107, #8125, контракт К1): запись `order` «A+B» — столбец, A сверху,
/// главный, названный в `order` отдельной записью, стоит там, где назван. Арифметика `ArrangeLayout` и
/// канал на своём стенде; сквозная сверка — эталоны `tests/fixtures/pimp/arrange-center-stack.*`.
final class ArrangeStackTests: XCTestCase {
    private static let odyssey = CGRect(x: -800, y: -720, width: 2560, height: 720)
    private static let macbook = CGRect(x: 0, y: 0, width: 1280, height: 832)
    private static let root = "/Users/dev/Projects/"
    private static let rick = "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"

    // MARK: - арифметика

    /// Одиссей 2560×720 при минимуме 280 и зазоре 5 (слово Элвиса: три слева, Рик, три справа): три столбца
    /// по 280, Рик 850, две стопки по 358/357 — встык к краям, с зазором 5 между окнами.
    func testOdysseyTwoStacksAt280Gap5() throws {
        let area = ArrangeStackTests.odyssey
        let frames = try XCTUnwrap(ArrangeLayout.centerStacks([1, 2, 2, 1, 1, 1, 1], hub: 3, in: area,
                                                              gap: 5, minCellWidth: 280))
        XCTAssertEqual(frames.map { $0[0].width }, [280, 280, 280, 850, 280, 280, 280])
        XCTAssertEqual(frames.map { $0[0].minX }, [-800, -515, -230, 55, 910, 1195, 1480])
        XCTAssertEqual(frames.last?[0].maxX, area.maxX, "правый край — встык")
        for stack in [frames[1], frames[2]] {
            XCTAssertEqual(stack.map { $0.height }, [358, 357])
            XCTAssertEqual(stack[0].minY, area.minY)
            XCTAssertEqual(stack[1].minY - stack[0].maxY, 5, "зазор между клетками")
            XCTAssertEqual(stack[1].maxY, area.maxY)
            XCTAssertEqual(stack[0].minX, stack[1].minX)
            XCTAssertEqual(stack[0].width, stack[1].width)
        }
        XCTAssertEqual(frames[3], [CGRect(x: 55, y: -720, width: 850, height: 720)])
    }

    /// Живой `claude.json` Элвиса — минимум 220, зазор 2 (критик WF107): столбцы как у эталона центра,
    /// Рик 852, стопки 359/359.
    func testOdysseyTwoStacksAt220Gap2() throws {
        let frames = try XCTUnwrap(ArrangeLayout.centerStacks([1, 2, 2, 1, 1, 1, 1], hub: 3,
                                                              in: ArrangeStackTests.odyssey,
                                                              gap: 2, minCellWidth: 220))
        XCTAssertEqual(frames.map { $0[0].minX }, [-800, -515, -231, 54, 908, 1193, 1477])
        XCTAssertEqual(frames.map { $0[0].width }, [283, 282, 283, 852, 283, 282, 283])
        XCTAssertEqual(frames[1].map { $0.height }, [359, 359])
        XCTAssertEqual(frames[2].map { $0.minY }, [-720, -359])
        // Без стопок столбцы — ровно прежние ячейки центра.
        XCTAssertEqual(frames.map { $0[0].minX },
                       ArrangeLayout.frames(count: 7, in: ArrangeStackTests.odyssey, mode: .center,
                                            minCellWidth: 220, gap: 2).map { $0.minX })
    }

    /// Три окна в столбец на 720 — окна по 236 pt, Claude ниже 357 не даёт: не влезает, влезает два.
    /// Вертикальный 1280 держит три.
    func testThreeInStackDoNotFitOnOdyssey() {
        XCTAssertNil(ArrangeLayout.centerStacks([1, 3, 1], hub: 1, in: ArrangeStackTests.odyssey,
                                                gap: 5, minCellWidth: 280))
        XCTAssertNil(ArrangeLayout.centerStacks([3, 1, 1], hub: 1, in: ArrangeStackTests.odyssey,
                                                gap: 2, minCellWidth: 220))
        XCTAssertEqual(ArrangeLayout.stackRows(height: 720, gap: 5), 2)
        XCTAssertEqual(ArrangeLayout.stackRows(height: 720, gap: 2), 2)
        XCTAssertEqual(ArrangeLayout.stackRows(height: 714, gap: 0), 2)
        XCTAssertEqual(ArrangeLayout.stackRows(height: 713, gap: 0), 1)
        XCTAssertEqual(ArrangeLayout.stackRows(height: 1280, gap: 5), 3)
        let tall = CGRect(x: 0, y: 0, width: 1440, height: 1280)
        let frames = ArrangeLayout.centerStacks([3, 1], hub: 1, in: tall, gap: 5, minCellWidth: 280)
        XCTAssertEqual(frames?[0].count, 3)
        XCTAssertTrue(frames?[0].allSatisfy { $0.height >= ArrangeLayout.splitMinHeight } ?? false)
    }

    /// Главный на месте 2 при трёх столбцах справа (L ≠ R): не тесно — левая треть на два, правая на три;
    /// тесно — все боковые одной ширины, главный — треть.
    func testHubPlaceTwoWithThreeOnTheRight() {
        let area = ArrangeStackTests.odyssey
        let loose = ArrangeLayout.centerColumns(left: 2, right: 3, in: area, gap: 2, minCellWidth: 220)
        XCTAssertEqual(loose.map { $0.width }, [425, 425, 852, 283, 282, 283])
        XCTAssertEqual(loose.first?.minX, area.minX)
        XCTAssertEqual(loose.last?.maxX, area.maxX)
        XCTAssertTrue(ArrangeLayout.centerFits(left: 2, right: 3, in: area, minCellWidth: 220, gap: 2))

        // Минимум 300: справа в трети по 280 — тесно.
        XCTAssertNotNil(ArrangeLayout.centerSqueeze(left: 2, right: 3, in: area, gap: 5, minCellWidth: 300))
        let tight = ArrangeLayout.centerColumns(left: 2, right: 3, in: area, gap: 5, minCellWidth: 300)
        XCTAssertEqual(tight.count, 6)
        XCTAssertEqual(tight[2].width, 850, "главный — треть")
        let sides = tight.enumerated().filter { $0.offset != 2 }.map { $0.element.width }
        XCTAssertLessThanOrEqual((sides.max() ?? 0) - (sides.min() ?? 0), 1, "боковые одной ширины: \(sides)")
        XCTAssertTrue(sides.allSatisfy { $0 >= 300 })
        XCTAssertEqual(tight.last?.maxX, area.maxX)
        for i in 1..<tight.count { XCTAssertEqual(tight[i].minX - tight[i - 1].maxX, 5, accuracy: 1) }
        // Не влезает вовсе — too-small.
        XCTAssertFalse(ArrangeLayout.centerFits(left: 2, right: 6, in: area, minCellWidth: 300, gap: 5))
    }

    /// Прежние рамки: центр без стопок — `centerColumns` с прежним местом главного, для любого числа окон.
    func testCenterCellsUnchangedThroughColumns() {
        let area = ArrangeStackTests.odyssey
        for (width, gap) in [(CGFloat(220), CGFloat(2)), (280, 5), (0, 0)] {
            for count in 1...10 {
                let hub = ArrangeLayout.centerHubIndex(count: count, in: area, minCellWidth: width, gap: gap)
                XCTAssertEqual(ArrangeLayout.centerCells(count: count, in: area, gap: gap, minCellWidth: width),
                               ArrangeLayout.centerColumns(left: hub, right: count - 1 - hub, in: area,
                                                           gap: gap, minCellWidth: width))
            }
        }
        // Восемь окон при 220 — тесно, главный пятым (#8123), как было.
        XCTAssertEqual(ArrangeLayout.centerHubIndex(count: 8, in: area, minCellWidth: 220, gap: 2), 4)
        XCTAssertTrue(ArrangeLayout.centerFits(count: 8, in: area, minCellWidth: 220, gap: 2))
        XCTAssertFalse(ArrangeLayout.centerFits(count: 9, in: area, minCellWidth: 280, gap: 2))
    }

    // MARK: - разбор записей

    /// «A+B» — части обрезаны, пустые выкинуты; плоский список — части подряд.
    func testStackPartsAndFlatOrder() {
        XCTAssertEqual(PimpChannel.stackParts(" Marketolog + VkusUchet "), ["Marketolog", "VkusUchet"])
        XCTAssertEqual(PimpChannel.stackParts("A++B+"), ["A", "B"])
        XCTAssertEqual(PimpChannel.stackParts("+"), [])
        XCTAssertEqual(PimpChannel.stackParts("Rick"), ["Rick"])
        XCTAssertEqual(PimpChannel.flatOrder(["A+B", "+", "C"]), ["A", "B", "C"])
    }

    /// План столбцов: главный в стопке выкинут, ненайденная часть — в `missing`, часть двух окон — обе в
    /// стопку по `base`, главный отдельной записью задаёт `left`; остальные и безымянные — в хвост.
    func testCenterPlanColumns() {
        let hub = window(1, "Rick")
        let others = [window(2, "A"), window(3, "B"), window(4, "B"), window(5, "C"), window(6, ""), window(7, "D")]
        let base = [0, 1, 2, 3, 4, 5]
        let plan = PimpChannel.centerPlan(of: others, hub: hub,
                                          by: ["C", "A+Rick+Nope", "Rick", "B+D"], base: base)
        XCTAssertEqual(plan.columns, [[3], [0], [1, 2, 5], [4]])
        XCTAssertEqual(plan.left, 2)
        XCTAssertEqual(plan.missing, ["Nope"])
        XCTAssertEqual(plan.unknown, 1)
        // Простая запись на два окна — два столбца, как раньше; главный не назван — `left` нет.
        let flat = PimpChannel.centerPlan(of: others, hub: hub, by: ["B"], base: base)
        XCTAssertEqual(flat.columns, [[1], [2], [0], [3], [5], [4]])
        XCTAssertNil(flat.left)
    }

    // MARK: - канал

    /// Сквозная сверка с эталоном: две стопки, Рик назван в `order` четвёртым; окна ставятся готовыми
    /// рамками (`place`), `arrange` не зовётся, окно MacBook не тронуто.
    func testChannelStackMatchesFixture() throws {
        let rig = try Rig(fixture: "arrange-center-stack.result.json", now: "2026-09-29T20:40:02Z")
        let stranger = PimpWindow(id: 99, title: "SkilZZZ", chat: "local_mac",
                                  folder: ArrangeStackTests.root + "SkilZZZ",
                                  frame: CGRect(x: 100, y: 100, width: 600, height: 600))
        rig.windows.append(stranger)
        let (channel, box) = makeChannel(rig)
        let id = "1790714410000-0801"
        try put(fixture("arrange-center-stack.request.json"), id: id, in: box, at: rig.now)
        channel.tick()
        XCTAssertEqual(resultText(id, in: box), try fixtureText("arrange-center-stack.result.json"))
        XCTAssertTrue(rig.arranged.isEmpty, "новый путь — готовыми рамками")
        XCTAssertEqual(rig.moves.count, 1)
        XCTAssertEqual(rig.moves.first?.map { $0.id }, [10, 11, 12, 13, 14, 15, 16, 17, 18])
        XCTAssertEqual(rig.window(99)?.frame, stranger.frame, "окно другого экрана не тронуто")
    }

    /// Старый эталон центра — старым путём (`seats.arrange`) и с полем `hub`.
    func testChannelOldCenterStillArranges() throws {
        let rig = try Rig(fixture: "arrange-center.result.json", now: "2026-09-26T18:40:02Z")
        let (channel, box) = makeChannel(rig)
        let id = "1790450010000-0701"
        try put(fixture("arrange-center.request.json"), id: id, in: box)
        channel.tick()
        XCTAssertEqual(resultText(id, in: box), try fixtureText("arrange-center.result.json"))
        XCTAssertEqual(rig.arranged, [[10, 11, 12, 13, 14, 15, 16]])
        XCTAssertTrue(rig.moves.isEmpty)
    }

    /// Главный первым или последним в `order` — прежнее место (старый путь, те же окна и рамки);
    /// посередине без стопок — там, где назван.
    func testChannelHubPlaceFromOrder() throws {
        let rig = try Rig(fixture: "arrange-center.result.json", now: "2026-09-26T18:40:02Z")
        let (channel, box) = makeChannel(rig)
        let sides = ["VkusnoffKz", "Risovalka", "Marketolog", "PimpMyClaude", "PimpViewer", "Dictator"]
        for (n, order) in [["Rick"] + sides, sides + ["Rick"]].enumerated() {
            let answer = ask(channel, rig, box, id: "500-000\(n)", order: order)
            XCTAssertEqual(answer?["ok"] as? Bool, true)
            XCTAssertEqual(answer?["hub"] as? Int, 3)
            XCTAssertEqual(rig.arranged.last, [10, 11, 12, 13, 14, 15, 16], "прежнее место, прежний путь")
        }
        XCTAssertTrue(rig.moves.isEmpty)
        // Рик третьим: слева два столбца, справа четыре — справа тесно, боковые одной ширины.
        let answer = ask(channel, rig, box, id: "500-0010", order: ["VkusnoffKz", "Risovalka", "Rick"] + sides.suffix(4))
        XCTAssertEqual(answer?["hub"] as? Int, 2)
        let placed = try XCTUnwrap(rig.moves.last)
        XCTAssertEqual(placed.map { $0.id }, [10, 11, 13, 12, 14, 15, 16])
        XCTAssertEqual(placed.map { $0.frame },
                       ArrangeLayout.centerColumns(left: 2, right: 4, in: ArrangeStackTests.odyssey, gap: 2,
                                                   minCellWidth: 220))
        XCTAssertEqual(placed[2].frame.width, 852, "главный — треть")
        XCTAssertEqual(placed.last?.frame.maxX, ArrangeStackTests.odyssey.maxX)
    }

    /// Стопка из трёх на 720 — `too-small` с `rows: 2` последним полем, окна не двигаются.
    func testChannelThreeInStackTooSmallWithRows() throws {
        let rig = try Rig(fixture: "arrange-center.result.json", now: "2026-09-26T18:40:02Z")
        rig.cellWidth = 280
        rig.gap = 5
        let (channel, box) = makeChannel(rig)
        let answer = ask(channel, rig, box, id: "500-0020",
                         order: ["VkusnoffKz", "Risovalka+Marketolog+PimpViewer", "Rick", "Dictator"])
        XCTAssertEqual(answer?["error"] as? String, "too-small")
        XCTAssertEqual(answer?["rows"] as? Int, 2)
        XCTAssertTrue(resultText("500-0020", in: box)?.hasSuffix("\"screen\":\"windows\",\"rows\":2}") ?? false,
                      resultText("500-0020", in: box) ?? "")
        XCTAssertTrue(rig.moves.isEmpty)
        XCTAssertTrue(rig.arranged.isEmpty)
    }

    /// Стопка при окне без папки не ждёт круга чатов: части нашлись — отвечаем сразу.
    func testStackDoesNotDemandChats() throws {
        let rig = try Rig(fixture: "arrange-center.result.json", now: "2026-09-26T18:40:02Z")
        rig.windows.append(PimpWindow(id: 30, title: "Без папки", frame: CGRect(x: 1400, y: -700, width: 300, height: 600)))
        let (channel, box) = makeChannel(rig)
        var demanded = 0
        channel.seats.demandChats = { _ in demanded += 1 }
        channel.seats.chatsAnswered = { _ in false }
        let answer = ask(channel, rig, box, id: "500-0030", order: ["Marketolog+Dictator"])
        XCTAssertEqual(demanded, 0)
        XCTAssertEqual(answer?["ok"] as? Bool, true)
        XCTAssertEqual(answer?["unknown"] as? Int, 1)
        XCTAssertEqual(answer?["missing"] as? [String], [])
        // Ненайденная часть — переспрос, как у простой записи.
        _ = ask(channel, rig, box, id: "500-0031", order: ["Marketolog+Nope"])
        XCTAssertEqual(demanded, 1)
    }

    /// `+` у прочих раскладок (`last`): части — как если бы их назвали подряд; ненайденная часть — в `missing`.
    func testPlusInLastIsFlat() throws {
        let rig = try Rig(fixture: "arrange-center.result.json", now: "2026-09-26T18:40:02Z")
        let (channel, box) = makeChannel(rig)
        var smart: [[CGWindowID]] = []
        channel.seats.arrangeSmart = { ids, _, _ in
            smart.append(ids)
            return ids.compactMap { rig.window($0) }
        }
        let body = "{\"id\":\"500-0040\",\"at\":\"2026-09-26T18:40:00Z\",\"action\":\"arrange\",\"from\":\"\","
            + "\"layout\":\"last\",\"order\":[\"Dictator+Marketolog\",\"Nope+VkusnoffKz\"]}"
        try put(Data(body.utf8), id: "500-0040", in: box)
        channel.tick()
        XCTAssertEqual(smart.first?.prefix(3).map { $0 }, [16, 12, 10])
        XCTAssertEqual(result("500-0040", in: box)?["missing"] as? [String], ["Nope"])
        XCTAssertNil(result("500-0040", in: box)?["hub"], "hub — только у центра")
    }

    /// Экранов не знаем (`area == nil`) — прежний путь: стопка раскладывается окнами подряд.
    func testNoScreensFallsBackToOldPath() throws {
        let rig = try Rig(fixture: "arrange-center.result.json", now: "2026-09-26T18:40:02Z")
        rig.screens = []
        let (channel, box) = makeChannel(rig)
        let answer = ask(channel, rig, box, id: "500-0050", order: ["Marketolog+Dictator"])
        XCTAssertEqual(answer?["ok"] as? Bool, true)
        XCTAssertTrue(rig.moves.isEmpty)
        XCTAssertEqual(rig.arranged.last?.prefix(2).map { $0 }, [12, 16])
    }

    // MARK: - стенд

    private final class Rig {
        var now: Date
        var windows: [PimpWindow]
        var screens: [(full: CGRect, usable: CGRect)] = [
            (full: ArrangeStackTests.macbook, usable: CGRect(x: 0, y: 38, width: 1280, height: 740)),
            (full: ArrangeStackTests.odyssey, usable: ArrangeStackTests.odyssey),
        ]
        var cellWidth: CGFloat = 220
        var gap: CGFloat = 2
        var arranged: [[CGWindowID]] = []
        var moves: [[PimpMove]] = []

        /// Окна эталона на Одиссее вразнобой: порядок по рамкам не совпадает ни с `order`, ни с итогом.
        init(fixture name: String, now: String) throws {
            self.now = PimpChannel.date(now)!
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: ArrangeStackTests.fixture(name))
                                     as? [String: Any])
            let list = try XCTUnwrap(json["windows"] as? [[String: Any]])
            let scattered: [CGFloat] = [900, -800, 1400, -300, 300, 1150, -550, 600, -100]
            windows = list.enumerated().map { index, item in
                PimpWindow(id: CGWindowID(10 + index), title: item["title"] as? String ?? "",
                           chat: item["chat"] as? String ?? "", folder: item["folder"] as? String ?? "",
                           frame: CGRect(x: scattered[index], y: -700, width: 150, height: 600))
            }
        }

        func window(_ id: CGWindowID) -> PimpWindow? { windows.first { $0.id == id } }

        func set(_ id: CGWindowID, _ frame: CGRect) -> PimpWindow? {
            guard let at = windows.firstIndex(where: { $0.id == id }) else { return nil }
            let old = windows[at]
            windows[at] = PimpWindow(id: id, title: old.title, chat: old.chat, folder: old.folder, frame: frame)
            return windows[at]
        }
    }

    private func makeChannel(_ rig: Rig) -> (PimpChannel, URL) {
        let box = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stack-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: box) }
        let channel = PimpChannel(directory: box, now: { rig.now })
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { rig.windows }
        seats.isMainWindow = { $0 == "Claude" }
        seats.screens = { rig.screens }
        seats.cellWidth = { rig.cellWidth }
        seats.gap = { rig.gap }
        seats.place = { list in
            rig.moves.append(list)
            for move in list { _ = rig.set(move.id, move.frame) }
        }
        seats.arrange = { ids, mode, _ in
            rig.arranged.append(ids)
            let cells = ArrangeLayout.frames(count: ids.count, in: ArrangeStackTests.odyssey, mode: mode,
                                             minCellWidth: rig.cellWidth, gap: rig.gap)
            let out = zip(ids, cells).compactMap { rig.set($0, $1) }
            return (windows: out, skipped: ids.count - out.count)
        }
        channel.seats = seats
        channel.start()
        return (channel, box)
    }

    private func ask(_ channel: PimpChannel, _ rig: Rig, _ box: URL, id: String, order: [String]) -> [String: Any]? {
        let list = order.map { "\"\($0)\"" }.joined(separator: ",")
        let body = "{\"id\":\"\(id)\",\"at\":\"\(PimpChannel.stampText(rig.now))\",\"action\":\"arrange\","
            + "\"from\":\"\",\"layout\":\"center\",\"order\":[\(list)],\"center\":\"Rick\"}"
        try? put(Data(body.utf8), id: id, in: box)
        channel.tick()
        return result(id, in: box)
    }

    private func window(_ id: CGWindowID, _ folder: String) -> PimpWindow {
        PimpWindow(id: id, title: folder, chat: "local_\(id)",
                   folder: folder.isEmpty ? "" : ArrangeStackTests.root + folder)
    }

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    private func fixture(_ name: String) throws -> Data { try ArrangeStackTests.fixture(name) }

    private func fixtureText(_ name: String) throws -> String {
        try String(data: fixture(name), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Файл запроса со временем стенда: уборка канала (файлы старше часа) иначе сочла бы его старым,
    /// если часы стенда впереди настоящих (как в `SendWF103Tests`).
    private func put(_ data: Data, id: String, in box: URL, at: Date? = nil) throws {
        let url = box.appendingPathComponent(id + ".json")
        try data.write(to: url)
        if let at = at { try FileManager.default.setAttributes([.modificationDate: at], ofItemAtPath: url.path) }
    }

    private func resultText(_ id: String, in box: URL) -> String? {
        (try? String(contentsOf: box.appendingPathComponent(id + ".result.json"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func result(_ id: String, in box: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: box.appendingPathComponent(id + ".result.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
