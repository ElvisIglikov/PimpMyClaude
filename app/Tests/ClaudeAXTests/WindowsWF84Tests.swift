import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Окна WF84: расстановка без сбоев (#7062, в ней #6747) и «окна как были» после запуска
/// Claude (#7065, контракт К5). Всё на подставных данных — ни AX, ни живого Claude.
final class WindowsWF84Tests: XCTestCase {
    /// «Экран» стенда: 1470×859 от 34 сверху, как у Элвиса на 15", минимум окна 280, зазор 5.
    static let area = CGRect(x: 0, y: 34, width: 1470, height: 859)
    static let minWidth: CGFloat = 280
    static let gap: CGFloat = 5

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf84-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private static func date(_ text: String) -> Date { PimpChannel.date(text)! }

    // MARK: - #6747: снимок раскладки узнаёт сетку умной расстановки

    func testSittingGridFindsSmartGrid() throws {
        let loose = [CGRect(x: 100, y: 100, width: 700, height: 500),
                     CGRect(x: 300, y: 200, width: 600, height: 600),
                     CGRect(x: 900, y: 80, width: 500, height: 700)]
        XCTAssertNil(ArrangeLayout.sittingGrid(frames: loose, in: Self.area,
                                               minCellWidth: Self.minWidth, gap: Self.gap),
                     "никто не сидит — сетки нет")

        let placed = ArrangeLayout.smart(frames: loose, in: Self.area,
                                         minCellWidth: Self.minWidth, gap: Self.gap)
        let grid = try XCTUnwrap(ArrangeLayout.sittingGrid(frames: placed, in: Self.area,
                                                           minCellWidth: Self.minWidth, gap: Self.gap))
        XCTAssertEqual(grid.cols, 3)
        XCTAssertEqual(grid.rows, 1)
        XCTAssertEqual(grid.sitting, 3)

        // Семь окон на 15" — два ряда по четыре (седьмое место из восьми).
        let seven = (0..<7).map { CGRect(x: CGFloat($0) * 150, y: 60, width: 500, height: 500) }
        let two = ArrangeLayout.smart(frames: seven, in: Self.area,
                                      minCellWidth: Self.minWidth, gap: Self.gap)
        let found = try XCTUnwrap(ArrangeLayout.sittingGrid(frames: two, in: Self.area,
                                                            minCellWidth: Self.minWidth, gap: Self.gap))
        XCTAssertEqual([found.cols, found.rows, found.sitting], [4, 2, 7])
    }

    func testBestSnapshotPrefersGridWhereWindowsSit() throws {
        let cells = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: Self.area, gap: Self.gap)
        let windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_m", folder: "/tmp/Pimp", frame: cells[0]),
            PimpWindow(id: 2, title: "Вкуснофф", chat: "local_v", folder: "/tmp/Vkus", frame: cells[1]),
            PimpWindow(id: 3, title: "Диктатор", chat: "local_d", folder: "/tmp/Dict", frame: cells[2]),
        ]
        // Последняя плитка — «4»: по ней не сидит никто, это и был отказ «не расставлены».
        let tile = ArrangeLayout.frames(count: 4, in: Self.area, mode: .four, gap: Self.gap)
        let smart = (grid: LayoutGrid(cols: 3, rows: 1), cells: cells)
        let best = LayoutsStore.bestSnapshot(name: "Утро", at: Self.date("2026-09-23T10:00:00Z"),
                                             mode: .four, windows: windows, tileCells: tile,
                                             smart: smart, isMain: { $0 == "Claude" })
        XCTAssertEqual(best.layout.grid, LayoutGrid(cols: 3, rows: 1))
        XCTAssertEqual(best.layout.mode, .ribbon)
        XCTAssertEqual(best.layout.cells.map { $0.cell }, [0, 1, 2])
        XCTAssertEqual(best.layout.cells.first?.chat, LayoutsStore.mainChat)

        // Ничья — остаётся плитка, как до WF84 (и файл без `grid`).
        let same = LayoutsStore.bestSnapshot(name: "Утро", at: Self.date("2026-09-23T10:00:00Z"),
                                             mode: .ribbon, windows: windows, tileCells: cells,
                                             smart: smart, isMain: { $0 == "Claude" })
        XCTAssertNil(same.layout.grid)
        XCTAssertEqual(same.layout.mode, .ribbon)
    }

    func testLayoutGridSurvivesFileAndOldRecordsStayByteForByte() throws {
        let at = Self.date("2026-09-23T10:00:00Z")
        let cell = LayoutCell(folder: "/tmp/Pimp", chat: "main", title: "Claude", cell: 0)
        let plain = WindowLayout(name: "Утро", at: at, mode: .four, cells: [cell])
        let smart = WindowLayout(name: "Разбор", at: at, mode: .ribbon, cells: [cell],
                                 grid: LayoutGrid(cols: 4, rows: 2))
        let text = LayoutsStore.json([plain, smart])
        XCTAssertTrue(text.contains("\"mode\":\"4\",\"cells\""), "у плитки поля grid нет")
        XCTAssertTrue(text.contains("\"mode\":\"row\",\"grid\":[4,2],\"cells\""), "grid — между mode и cells")
        let back = LayoutsStore.parse(Data(text.utf8))
        XCTAssertEqual(back.first { $0.name == "Разбор" }?.grid, LayoutGrid(cols: 4, rows: 2))
        XCTAssertNil(back.first { $0.name == "Утро" }?.grid)
        XCTAssertNil(LayoutsStore.parseGrid([0, 2]), "ноль столбцов — поля будто нет")
        XCTAssertNil(LayoutsStore.parseGrid([3]))
    }

    /// Канал: «запомни» сразу после умной расстановки пишется, «верни» ставит окна в ту же сетку.
    func testChannelSavesAndRestoresSmartGridLayout() throws {
        let box = makeTemp()
        var now = Self.date("2026-09-23T10:00:00Z")
        let cells = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: Self.area, gap: Self.gap)
        var windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_m", folder: "/tmp/Pimp", frame: cells[0]),
            PimpWindow(id: 2, title: "Вкуснофф", chat: "local_v", folder: "/tmp/Vkus", frame: cells[1]),
            PimpWindow(id: 3, title: "Диктатор", chat: "local_d", folder: "/tmp/Dict", frame: cells[2]),
        ]
        var saved: [WindowLayout] = []
        var moves: [PimpMove] = []
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { windows }
        seats.arrangeMode = { .four }
        seats.cells = { mode, count in
            ArrangeLayout.frames(count: count, in: Self.area, mode: mode, gap: Self.gap)
        }
        seats.smartGrid = { frames in
            guard let grid = ArrangeLayout.sittingGrid(frames: frames, in: Self.area,
                                                       minCellWidth: Self.minWidth, gap: Self.gap)
            else { return nil }
            return (grid: LayoutGrid(cols: grid.cols, rows: grid.rows),
                    cells: ArrangeLayout.cells(cols: grid.cols, rows: grid.rows,
                                               count: grid.cols * grid.rows, in: Self.area, gap: Self.gap))
        }
        seats.gridCells = { grid in
            ArrangeLayout.cells(cols: grid.cols, rows: grid.rows, count: grid.cols * grid.rows,
                                in: Self.area, gap: Self.gap)
        }
        seats.saveLayout = { layout in
            saved = LayoutsStore.merge(layout, into: saved)
            return true
        }
        seats.layouts = { saved }
        seats.isMainWindow = { $0 == "Claude" }
        seats.place = { list in
            moves += list
            for move in list {
                guard let at = windows.firstIndex(where: { $0.id == move.id }) else { continue }
                let old = windows[at]
                windows[at] = PimpWindow(id: old.id, title: old.title, chat: old.chat,
                                         folder: old.folder, frame: move.frame)
            }
        }
        let channel = PimpChannel(directory: box, now: { now })
        channel.seats = seats
        channel.start()

        func send(_ id: String, _ body: String) throws -> [String: Any] {
            try Data(body.utf8).write(to: box.appendingPathComponent(id + ".json"))
            channel.tick()
            let data = try Data(contentsOf: box.appendingPathComponent(id + ".result.json"))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let stamp = PimpChannel.stampText(now)
        let answer = try send("840-0001", "{\"id\":\"840-0001\",\"at\":\"\(stamp)\","
                                + "\"action\":\"layout-save\",\"from\":\"\",\"name\":\"Утро\"}")
        XCTAssertEqual(answer["ok"] as? Bool, true, "\(answer)")
        XCTAssertEqual(answer["cells"] as? Int, 3)
        XCTAssertEqual(saved.first?.grid, LayoutGrid(cols: 3, rows: 1))

        // Окна разъехались — «верни Утро» ставит их в ту же сетку 3×1.
        windows = windows.map {
            PimpWindow(id: $0.id, title: $0.title, chat: $0.chat, folder: $0.folder,
                       frame: CGRect(x: 50 * CGFloat($0.id), y: 100, width: 600, height: 500))
        }
        now = now.addingTimeInterval(5)
        let restored = try send("840-0002", "{\"id\":\"840-0002\",\"at\":\"\(PimpChannel.stampText(now))\","
                                  + "\"action\":\"layout-restore\",\"from\":\"\",\"name\":\"Утро\","
                                  + "\"fresh\":false}")
        XCTAssertEqual(restored["ok"] as? Bool, true, "\(restored)")
        XCTAssertEqual(restored["placed"] as? Int, 3)
        XCTAssertEqual(windows.map { $0.frame }, cells)
        XCTAssertEqual(moves.count, 3)
    }

    // MARK: - #7062: «под этим» делит столбец с зазором

    func testSplitKeepsGapBetweenHalves() throws {
        let column = CGRect(x: 0, y: 34, width: 490, height: 859)
        let halves = try XCTUnwrap(PimpChannel.split(column, above: false, gap: 5))
        XCTAssertEqual(halves.old, CGRect(x: 0, y: 34, width: 490, height: 427))
        XCTAssertEqual(halves.new, CGRect(x: 0, y: 466, width: 490, height: 427))
        XCTAssertEqual(halves.new.minY - halves.old.maxY, 5, "между половинками зазор")
        XCTAssertEqual(halves.new.maxY, column.maxY, "низ столбца на месте")

        let above = try XCTUnwrap(PimpChannel.split(column, above: true, gap: 5))
        XCTAssertEqual(above.new, halves.old)
        XCTAssertEqual(above.old, halves.new)

        // Без зазора — побайтно как до WF84.
        let flush = try XCTUnwrap(PimpChannel.split(column, above: false))
        XCTAssertEqual(flush.old.height, 429)
        XCTAssertEqual(flush.new, CGRect(x: 0, y: 463, width: 490, height: 430))
        XCTAssertNil(PimpChannel.split(CGRect(x: 0, y: 0, width: 400, height: 718), above: false, gap: 5),
                     "половинка ниже 357 (WF94) — не делим")
    }

    // MARK: - #7065: снимок окон (контракт К5)

    private static let mainFrame = CGRect(x: -3360, y: -575, width: 427, height: 720)
    private static let dictFrame = CGRect(x: -2928, y: -575, width: 427, height: 720)

    private static func snapshot(at: String) -> WindowSnapshot {
        WindowSnapshot(at: date(at), claude: "1.2553.13", windows: [
            SnapshotWindow(chat: "main", folder: "/Users/dev/Projects/PimpMyClaude",
                           title: "Claude", frame: mainFrame, screen: "Odyssey"),
            SnapshotWindow(chat: "local_d", folder: "/Users/dev/Projects/Dictator",
                           title: "Плашки \"и\" свечение", frame: dictFrame, screen: "Odyssey"),
        ])
    }

    func testSnapshotFileRoundTripAndKeyOrder() throws {
        let snap = Self.snapshot(at: "2026-09-23T10:00:00Z")
        let text = WindowSnapshotStore.json(snap)
        XCTAssertTrue(text.hasPrefix("{\"version\":1,\"at\":\"2026-09-23T10:00:00Z\",\"claude\":\"1.2553.13\","
                                     + "\"windows\":[{\"chat\":\"main\",\"folder\":"), text)
        XCTAssertTrue(text.contains("\"frame\":[-3360,-575,427,720],\"screen\":\"Odyssey\"}"), text)
        XCTAssertEqual(WindowSnapshotStore.parse(Data(text.utf8)), snap)

        XCTAssertNil(WindowSnapshotStore.parse(Data("{\"version\":2,\"at\":\"2026-09-23T10:00:00Z\"}".utf8)))
        XCTAssertNil(WindowSnapshotStore.parse(Data("не json".utf8)))
        let holes = "{\"version\":1,\"at\":\"2026-09-23T10:00:00Z\",\"claude\":\"\",\"windows\":["
            + "{\"chat\":\"\",\"frame\":[0,0,500,500]},{\"chat\":\"local_a\",\"frame\":[0,0]},"
            + "{\"chat\":\"local_b\",\"frame\":[10,20,500,600]}]}"
        XCTAssertEqual(WindowSnapshotStore.parse(Data(holes.utf8))?.windows.map { $0.chat }, ["local_b"])

        let box = makeTemp()
        let store = WindowSnapshotStore(url: box.appendingPathComponent(WindowSnapshotStore.fileName))
        XCTAssertNil(store.load())
        XCTAssertTrue(store.save(snap))
        XCTAssertEqual(store.load(), snap)
    }

    func testSnapshotWindowsMainFirstKnownChatsOnly() {
        let list = [
            PimpWindow(id: 2, title: "Вкуснофф", chat: "local_b", folder: "/tmp/Vkus",
                       frame: CGRect(x: 500, y: 0, width: 400, height: 700)),
            PimpWindow(id: 1, title: "Claude", chat: "local_m", folder: "/tmp/Pimp",
                       frame: CGRect(x: 0, y: 0, width: 400, height: 700)),
            PimpWindow(id: 3, title: "Вкуснофф", chat: "local_b", folder: "/tmp/Vkus",
                       frame: CGRect(x: 800, y: 0, width: 400, height: 700)),
            PimpWindow(id: 4, title: "Без карты", chat: "", folder: "",
                       frame: CGRect(x: 1000, y: 0, width: 400, height: 700)),
            PimpWindow(id: 5, title: "Claude", chat: "local_z", folder: "",
                       frame: CGRect(x: 1200, y: 0, width: 400, height: 700)),
        ]
        let out = WindowSnapshotStore.windows(from: list, isMain: { $0 == "Claude" },
                                              screen: { _ in "Odyssey" })
        XCTAssertEqual(out.map { $0.chat }, ["main", "local_b"])
        XCTAssertEqual(out.first?.frame, list[1].frame)
        XCTAssertEqual(out.last?.frame, list[0].frame, "дубль чата правее не пишется")
    }

    func testShouldRestoreOnlyForClaudeLaunchedAfterSnapshot() {
        let snap = Self.snapshot(at: "2026-09-23T10:00:00Z")
        let later = Self.date("2026-09-23T10:05:00Z")
        XCTAssertTrue(WindowSnapshotStore.shouldRestore(snap, launch: later, seenAt: later))
        // Подмена Пимпа на живом Claude: Claude запущен до снимка — второго возврата нет.
        XCTAssertFalse(WindowSnapshotStore.shouldRestore(snap, launch: Self.date("2026-09-23T09:00:00Z"),
                                                         seenAt: later))
        XCTAssertFalse(WindowSnapshotStore.shouldRestore(snap, launch: nil, seenAt: later))
        // Claude работает давно, а Пимп увидел его только сейчас — не трогаем.
        XCTAssertFalse(WindowSnapshotStore.shouldRestore(snap, launch: later,
                                                         seenAt: later.addingTimeInterval(301)))
        // Возраст снимка не ограничен: утром после ночи окна возвращаются.
        let morning = Self.date("2026-09-24T08:00:00Z")
        XCTAssertTrue(WindowSnapshotStore.shouldRestore(snap, launch: morning, seenAt: morning))
        let empty = WindowSnapshot(at: snap.at, claude: "", windows: [])
        XCTAssertFalse(WindowSnapshotStore.shouldRestore(empty, launch: later, seenAt: later))
    }

    /// Стенд хранителя снимка: Claude, окна, страница и канал — в памяти.
    private final class KeeperRig {
        var claude: (pid: pid_t, launch: Date?, version: String)?
        var windows: [SnapshotWindow] = []
        var pageReady = false
        var restoring = false
        var canStart = true
        var started: [WindowSnapshot] = []
        var demands = 0
        let store: WindowSnapshotStore
        let keeper: WindowSnapshotKeeper

        init(box: URL) {
            store = WindowSnapshotStore(url: box.appendingPathComponent(WindowSnapshotStore.fileName))
            keeper = WindowSnapshotKeeper(store: store)
            keeper.claude = { [unowned self] in self.claude }
            keeper.windows = { [unowned self] in self.windows }
            keeper.pageReady = { [unowned self] _ in self.pageReady }
            keeper.demandPages = { [unowned self] in self.demands += 1 }
            keeper.startRestore = { [unowned self] snapshot in
                guard self.canStart else { return false }
                self.started.append(snapshot)
                self.restoring = true
                return true
            }
            keeper.isRestoring = { [unowned self] in self.restoring }
        }
    }

    private static let oneMain = WindowSnapshot(at: date("2026-09-23T10:00:00Z"), claude: "", windows: [
        SnapshotWindow(chat: "main", folder: "", title: "Claude",
                       frame: CGRect(x: 0, y: 34, width: 700, height: 859), screen: ""),
    ]).windows

    func testKeeperDoesNotRestoreOnPimpSwapAndWritesStableWindows() {
        let rig = KeeperRig(box: makeTemp())
        let old = Self.snapshot(at: "2026-09-23T10:00:00Z")
        rig.store.save(old)
        rig.claude = (pid: 500, launch: Self.date("2026-09-23T09:00:00Z"), version: "1.2553.13")
        rig.windows = Self.oneMain
        var at = Self.date("2026-09-23T12:00:00Z")
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.phase, .keeping)
        XCTAssertNil(rig.keeper.launchSnapshot)
        XCTAssertEqual(rig.keeper.writes, 0, "один замер — ещё не «простояло»")
        at.addTimeInterval(2)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.writes, 0, "замер не чаще раза в 4 с")
        at.addTimeInterval(2)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.writes, 1)
        XCTAssertTrue(rig.started.isEmpty)
        XCTAssertEqual(rig.store.load()?.windows, Self.oneMain)
        XCTAssertEqual(rig.store.load()?.at, at)
        // Тот же набор — файл не переписываем.
        at.addTimeInterval(8)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.writes, 1)
        // Окон нет (всё свёрнуто) — снимок не затирается.
        rig.windows = []
        at.addTimeInterval(8)
        rig.keeper.tick(at: at)
        at.addTimeInterval(8)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.store.load()?.windows, Self.oneMain)
    }

    func testKeeperRestoresAfterClaudeRestartAndHoldsSnapshotUntilDone() {
        let rig = KeeperRig(box: makeTemp())
        let old = Self.snapshot(at: "2026-09-23T10:00:00Z")
        rig.store.save(old)
        // Claude был, потом закрыт: пока его нет, снимок не трогаем.
        rig.claude = nil
        var at = Self.date("2026-09-23T10:04:00Z")
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.phase, .idle)
        XCTAssertFalse(rig.keeper.saveNow(at: at))

        let launch = Self.date("2026-09-23T10:05:00Z")
        rig.claude = (pid: 600, launch: launch, version: "1.2553.14")
        at = launch.addingTimeInterval(1)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.phase, .waiting)
        XCTAssertEqual(rig.keeper.launchSnapshot, old)
        XCTAssertEqual(rig.demands, 1, "страницы просят ответить и при выключенном тумблере")
        // Главное окно есть, страница ещё молчит — ждём.
        rig.windows = Self.oneMain
        at.addTimeInterval(2)
        rig.keeper.tick(at: at)
        XCTAssertTrue(rig.started.isEmpty)
        rig.pageReady = true
        at.addTimeInterval(2)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.started, [old])
        XCTAssertEqual(rig.keeper.phase, .restoring)
        // Пока возврат идёт, снимок с одним главным окном в файл не попадает (критик Б4б).
        for _ in 0..<5 {
            at.addTimeInterval(4)
            rig.keeper.tick(at: at)
        }
        XCTAssertEqual(rig.keeper.writes, 0)
        XCTAssertEqual(rig.store.load()?.windows, old.windows)
        XCTAssertTrue(rig.store.load()?.restorePending == true)
        XCTAssertFalse(rig.keeper.restoreNow(), "второй возврат поверх идущего не начинаем")

        rig.restoring = false
        rig.windows = old.windows
        at.addTimeInterval(4)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.phase, .keeping)
        at.addTimeInterval(4)
        rig.keeper.tick(at: at)
        at.addTimeInterval(4)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.writes, 1, "первый снимок этого Claude пишется всегда — at позже запуска")
        let written = rig.store.load()
        XCTAssertEqual(written?.windows, old.windows)
        XCTAssertEqual(written?.claude, "1.2553.14")
        XCTAssertGreaterThan(written?.at ?? .distantPast, launch)
        XCTAssertEqual(rig.started.count, 1, "триггер один — второго возврата нет")

        // Подмена Пимпа на этом же Claude: новый хранитель снимок не возвращает.
        let swapped = WindowSnapshotKeeper(store: rig.store)
        var starts = 0
        swapped.claude = { rig.claude }
        swapped.windows = { rig.windows }
        swapped.pageReady = { _ in true }
        swapped.startRestore = { _ in
            starts += 1
            return true
        }
        swapped.tick(at: at.addingTimeInterval(60))
        XCTAssertEqual(swapped.phase, .keeping)
        XCTAssertEqual(starts, 0)
    }

    func testKeeperFallsBackWithoutPageAndRetriesWhenChannelBusy() {
        let rig = KeeperRig(box: makeTemp())
        let old = Self.snapshot(at: "2026-09-23T10:00:00Z")
        rig.store.save(old)
        let launch = Self.date("2026-09-23T10:05:00Z")
        rig.claude = (pid: 700, launch: launch, version: "")
        rig.windows = Self.oneMain
        rig.canStart = false
        var at = launch
        rig.keeper.tick(at: at)
        // Канал probe занят агентом: страница «молчит», через 20 с после окна идём всё равно.
        at.addTimeInterval(19)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.phase, .waiting)
        at.addTimeInterval(2)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.phase, .waiting, "канал занят — пробуем на следующем тике")
        rig.canStart = true
        at.addTimeInterval(2)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.phase, .restoring)
        XCTAssertEqual(rig.started, [old])
    }

    func testKeeperGivesUpAndManualRestoreUsesPreLaunchSnapshot() {
        let rig = KeeperRig(box: makeTemp())
        let old = Self.snapshot(at: "2026-09-23T10:00:00Z")
        rig.store.save(old)
        let launch = Self.date("2026-09-23T10:05:00Z")
        rig.claude = (pid: 800, launch: launch, version: "")
        var at = launch
        rig.keeper.tick(at: at)
        // Окна так и не появились — через 2 минуты автовозврат брошен.
        at.addTimeInterval(121)
        rig.keeper.tick(at: at)
        XCTAssertEqual(rig.keeper.phase, .keeping)
        XCTAssertTrue(rig.started.isEmpty)
        // Неполный набор не затирает прежний полный файл даже после giveUp.
        rig.windows = Self.oneMain
        for _ in 0..<3 {
            at.addTimeInterval(4)
            rig.keeper.tick(at: at)
        }
        XCTAssertEqual(rig.store.load()?.windows, old.windows)
        XCTAssertTrue(rig.keeper.restoreNow())
        XCTAssertEqual(rig.started, [old])
        XCTAssertEqual(rig.keeper.phase, .restoring)
    }

    func testKeeperManualRestoreWithoutLaunchSnapshotUsesFileAndSaveNow() {
        let rig = KeeperRig(box: makeTemp())
        XCTAssertFalse(rig.keeper.restoreNow(), "Claude не видели — возвращать некуда")
        let launch = Self.date("2026-09-23T10:05:00Z")
        rig.claude = (pid: 900, launch: launch, version: "1.0")
        rig.windows = Self.oneMain
        var at = launch.addingTimeInterval(3600)
        rig.keeper.tick(at: at)
        XCTAssertFalse(rig.keeper.restoreNow(), "снимка нет вовсе")
        // Перед закрытием Claude (обновление) снимок пишется сразу, без второго замера.
        at.addTimeInterval(1)
        XCTAssertTrue(rig.keeper.saveNow(at: at))
        XCTAssertEqual(rig.store.load()?.at, at)
        XCTAssertTrue(rig.keeper.restoreNow())
        XCTAssertEqual(rig.started.first?.windows, Self.oneMain)
        XCTAssertFalse(rig.keeper.saveNow(at: at), "пока идёт возврат — не пишем")
    }

    // MARK: - #7065: возврат снимка очередью канала

    func testChannelRestoresSnapshotPlacesMainOpensChatsSkipsMissing() throws {
        let box = makeTemp()
        var now = Self.date("2026-09-23T10:05:10Z")
        var windows = [PimpWindow(id: 1, title: "Claude", chat: "local_m", folder: "",
                                  frame: CGRect(x: 0, y: 34, width: 800, height: 600))]
        var popouts: [(chat: String, origin: (x: Int, y: Int))] = []
        var moves: [PimpMove] = []
        var notices: [String] = []
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { windows }
        seats.isMainWindow = { $0 == "Claude" }
        seats.openChat = { chat, _, origin in popouts.append((chat: chat, origin: origin)) }
        seats.notice = { notices.append($0) }
        seats.place = { list in
            moves += list
            for move in list {
                guard let at = windows.firstIndex(where: { $0.id == move.id }) else { continue }
                let old = windows[at]
                windows[at] = PimpWindow(id: old.id, title: old.title, chat: old.chat,
                                         folder: old.folder, frame: move.frame)
            }
        }
        let channel = PimpChannel(directory: box, now: { now })
        channel.seats = seats
        channel.start()

        var snap = Self.snapshot(at: "2026-09-23T10:00:00Z")
        snap = WindowSnapshot(at: snap.at, claude: snap.claude, windows: snap.windows + [
            SnapshotWindow(chat: "local_gone", folder: "", title: "Удалённый чат",
                           frame: CGRect(x: -2500, y: -575, width: 427, height: 720), screen: ""),
        ])
        XCTAssertTrue(channel.startRestore(snapshot: snap, name: WindowSnapshotStore.restoreName))
        XCTAssertTrue(channel.isRestoring)
        XCTAssertEqual(windows[0].frame, Self.mainFrame, "главное окно — сразу на своё место")
        XCTAssertEqual(popouts.map { $0.chat }, ["local_d"])
        XCTAssertEqual(popouts.first?.origin.x, -2928)
        XCTAssertFalse(channel.startRestore(snapshot: snap, name: "ещё раз"), "канал занят")

        // Окно чата родилось — встаёт на место, следующий чат выносится.
        windows.append(PimpWindow(id: 2, title: "Плашки", chat: "local_d", folder: "",
                                  frame: CGRect(x: -2928, y: -575, width: 600, height: 500)))
        now.addTimeInterval(2)
        channel.tick()
        XCTAssertEqual(windows[1].frame, Self.dictFrame)
        XCTAssertEqual(popouts.map { $0.chat }, ["local_d", "local_gone"])
        // Чата больше нет — место пропускаем, новых чатов не заводим.
        now.addTimeInterval(PimpChannel.restoreWindowSeconds + 1)
        channel.tick()
        XCTAssertFalse(channel.isRestoring)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(notices, ["Вернул «Окна как были»: 1 стояло, 1 открыл; не нашёл чат: Удалённый чат"])
    }
}
