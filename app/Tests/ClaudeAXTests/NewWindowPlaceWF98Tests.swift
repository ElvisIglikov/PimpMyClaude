import XCTest
@testable import ClaudeAX

/// #7841 (WF98, слово Элвиса: «нажал — оно сразу открылось в свободном месте… сначала высчитать
/// нужное место, а потом показывать, чтобы быстрее и не так коряво»). Ячейка нового окна
/// считается ДО команды, соседи раздвигаются заранее, окно рождается в углу ячейки, а опрос
/// 0,1 с ставит ему размер в первый же шаг после появления — не через тик 2 с.
///
/// Без живого Claude и без AX: окна — записи канала, опрос шагаем сами по часам теста.
final class NewWindowPlaceWF98Tests: XCTestCase {
    private static let fromChat = "local_5265171a-0ab8-4472-b4e5-40604a36ef6e"
    private static let newChat = "local_9f1c2d3e-0000-4000-8000-000000000001"

    private final class Rig {
        var now = PimpChannel.date("2026-09-07T11:20:00Z")!
        var windows: [PimpWindow] = []
        /// Номера на экране сверх `windows` — служебные окна без AX-пары.
        var extraIDs: Set<CGWindowID> = []
        var queued: [(delay: TimeInterval, run: () -> Void)] = []
        var origins: [(x: Int, y: Int)?] = []
        var room: [[CGWindowID]] = []
        var placed: [[PimpMove]] = []
        var placedNew: [(move: PimpMove, at: Date)] = []
        var smartCalls = 0
        var windowsCalls = 0
        var notices: [String] = []

        /// Ровные столбцы по 490 на экране 1470 — как у умной сетки на MacBook.
        static func cells(_ ids: [CGWindowID]) -> [(CGWindowID, CGRect)] {
            let width = 1470 / CGFloat(ids.count)
            return ids.enumerated().map { ($1, CGRect(x: width * CGFloat($0), y: 34, width: width, height: 859)) }
        }

        func move(_ id: CGWindowID, to frame: CGRect) {
            guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
            let old = windows[index]
            windows[index] = PimpWindow(id: old.id, title: old.title, chat: old.chat, folder: old.folder,
                                        frame: frame)
        }

        func seats() -> PimpSeats {
            var seats = PimpSeats(
                claudeRunning: { true },
                windows: { [unowned self] in
                    self.windowsCalls += 1
                    return self.windows
                },
                projects: { [Project(folder: URL(fileURLWithPath: "/tmp", isDirectory: true), name: "Dictator",
                                     lastFocusedAt: 0)] },
                openNewWindow: { [unowned self] _, origin in self.origins.append(origin) },
                arrangeSmart: { [unowned self] ids, _, _ in
                    self.smartCalls += 1
                    return Rig.cells(ids).map { id, frame in
                        self.move(id, to: frame)
                        return PimpWindow(id: id, title: "", frame: frame)
                    }
                },
                place: { [unowned self] moves in
                    self.placed.append(moves)
                    for move in moves { self.move(move.id, to: move.frame) }
                },
                titleForChat: { $0 == NewWindowPlaceWF98Tests.fromChat ? "Claude" : nil },
                newWindowLayers: { true },
                notice: { [unowned self] in self.notices.append($0) },
                schedule: { [unowned self] delay, block in self.queued.append((delay, block)) })
            seats.windowIDs = { [unowned self] in Set(self.windows.map { $0.id }).union(self.extraIDs) }
            seats.makeRoom = { [unowned self] ids in
                self.room.append(ids)
                return Rig.cells(ids).map { id, frame in
                    self.move(id, to: frame)
                    return PimpWindow(id: id, title: "", frame: frame)
                }
            }
            seats.placeNew = { [unowned self] move in
                self.placedNew.append((move, self.now))
                self.move(move.id, to: move.frame)
            }
            return seats
        }

        /// Шаги опроса по часам теста, пока они есть и не вышел срок; `birth` — что происходит
        /// на экране к этому моменту.
        func poll(until end: Date, birth: (Date) -> Void = { _ in }) {
            while let step = queued.first, now < end {
                queued.removeFirst()
                now = now.addingTimeInterval(step.delay)
                birth(now)
                step.run()
            }
        }
    }

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf98-\(UUID().uuidString)", isDirectory: true)
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

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let dictator = Project(folder: URL(fileURLWithPath: "/tmp", isDirectory: true), name: "Dictator",
                                   lastFocusedAt: 0)

    // MARK: - канал: «🪟 Новое окно ▸ проект» из меню

    /// Ячейка до команды: соседи раздвинуты сразу, угол ячейки ушёл точкой; окно родилось там
    /// Claude-размера — и опрос поставил ему размер ячейки в первый же шаг после появления.
    func testMenuWindowIsBornInItsCellAndSizedWithin100ms() throws {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
                       PimpWindow(id: 2, title: "Второй", frame: CGRect(x: 735, y: 34, width: 735, height: 859))]
        let pimp = channel(rig, in: box)
        XCTAssertTrue(pimp.startNewWindow(project: dictator))

        XCTAssertEqual(rig.room, [[1, 2, PimpChannel.phantomID]], "«справа» — призрак последним")
        XCTAssertEqual(rig.origins.count, 1)
        XCTAssertEqual(rig.origins.first??.x, 980, "угол ячейки, а не уступ от окна в фокусе")
        XCTAssertEqual(rig.origins.first??.y, 34)
        XCTAssertEqual(rig.windows.map { $0.frame.minX }, [0, 490], "соседи раздвинуты ДО рождения")
        XCTAssertEqual(rig.queued.map { $0.delay }, [BirthWatch.pollSeconds], "опрос 0,1 с пошёл")

        // Цепочка страницы идёт секунды; окно появляется между шагами опроса.
        let start = rig.now
        let appear = start.addingTimeInterval(4.93)
        rig.poll(until: start.addingTimeInterval(10)) { now in
            guard now >= appear, !rig.windows.contains(where: { $0.id == 3 }) else { return }
            rig.windows.append(PimpWindow(id: 3, title: "Dictator",
                                          frame: CGRect(x: 980, y: 34, width: 900, height: 700)))
        }
        let placed = try XCTUnwrap(rig.placedNew.first)
        XCTAssertEqual(rig.placedNew.count, 1)
        XCTAssertEqual(placed.move, PimpMove(id: 3, frame: CGRect(x: 980, y: 34, width: 490, height: 859)))
        let ms = placed.at.timeIntervalSince(appear) * 1000
        XCTAssertLessThanOrEqual(ms, BirthWatch.pollSeconds * 1000 + 1, "встало в первый же шаг опроса")
        print("WF98 замер: окно встало через \(Int(ms.rounded())) мс после появления на экране "
              + "(опрос \(Int(BirthWatch.pollSeconds * 1000)) мс; до WF98 — тик 2 с, до 2000 мс)")
        XCTAssertEqual(rig.smartCalls, 0, "план годен — второй расстановки нет")
        XCTAssertFalse(pimp.isWaitingPage)
        XCTAssertTrue(rig.queued.isEmpty, "опрос погас вместе с работой")
    }

    /// Ответ канала по плану — побайтно эталон `new-window.result.json` (место «посередине»).
    func testRequestAnswerByPlanMatchesFixture() throws {
        let box = makeTemp(), rig = Rig()
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", chat: NewWindowPlaceWF98Tests.fromChat,
                       frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 2, title: "Второй", frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        let pimp = channel(rig, in: box)
        let request = PimpChannel.fixturesRequest(NewWindowPlaceWF98Tests.fixtures)
        try Data(contentsOf: request).write(to: box.appendingPathComponent("1788780000000-0421.json"))
        pimp.tick()
        XCTAssertEqual(rig.room, [[1, PimpChannel.phantomID, 2]])
        XCTAssertEqual(rig.origins.first??.x, 490)

        let appear = rig.now.addingTimeInterval(7.02)
        rig.poll(until: rig.now.addingTimeInterval(12)) { now in
            guard now >= appear, !rig.windows.contains(where: { $0.id == 3 }) else { return }
            rig.windows.append(PimpWindow(id: 3, title: "Диктаторик", chat: NewWindowPlaceWF98Tests.newChat,
                                          frame: CGRect(x: 490, y: 34, width: 900, height: 700)))
        }
        XCTAssertEqual(try text(box.appendingPathComponent("1788780000000-0421.result.json")),
                       try text(NewWindowPlaceWF98Tests.fixtures.appendingPathComponent("new-window.result.json")))
    }

    /// Окно не пришло за 40 с — раздвинутые соседи возвращаются, где стояли; тот, кого Элвис
    /// подвинул сам, остаётся где его поставили.
    func testNoWindowPutsNeighboursBack() {
        let box = makeTemp(), rig = Rig()
        let one = CGRect(x: 0, y: 34, width: 490, height: 859)
        let two = CGRect(x: 490, y: 34, width: 490, height: 859)
        let three = CGRect(x: 980, y: 34, width: 490, height: 859)
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: one),
                       PimpWindow(id: 2, title: "Второй", frame: two),
                       PimpWindow(id: 3, title: "Третий", frame: three)]
        let pimp = channel(rig, in: box)
        XCTAssertTrue(pimp.startNewWindow(project: dictator))
        XCTAssertEqual(rig.windows.map { $0.frame.width }, [367.5, 367.5, 367.5])
        let manual = CGRect(x: 100, y: 100, width: 600, height: 600)
        rig.move(2, to: manual)

        rig.now = rig.now.addingTimeInterval(PimpChannel.newWindowSeconds + 1)
        pimp.tick()
        XCTAssertFalse(pimp.isWaitingPage)
        XCTAssertEqual(rig.placed.last, [PimpMove(id: 1, frame: one), PimpMove(id: 3, frame: three)])
        XCTAssertEqual(rig.windows.map { $0.frame }, [one, manual, three])
        XCTAssertEqual(rig.notices.count, 1, "работа из меню говорит плашкой, как раньше")
    }

    /// Пока ждали, ряд сменился (соседа закрыли) — план не годен, окно ставится по-старому.
    func testStalePlanFallsBackToArrangeAtBirth() {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
                       PimpWindow(id: 2, title: "Второй", frame: CGRect(x: 735, y: 34, width: 735, height: 859))]
        let pimp = channel(rig, in: box)
        XCTAssertTrue(pimp.startNewWindow(project: dictator))
        rig.windows.removeAll { $0.id == 2 }
        rig.windows.append(PimpWindow(id: 3, title: "Dictator", frame: CGRect(x: 980, y: 34, width: 900, height: 700)))
        rig.poll(until: rig.now.addingTimeInterval(1))
        XCTAssertTrue(rig.placedNew.isEmpty)
        XCTAssertEqual(rig.smartCalls, 1, "как до WF98: умная расстановка с настоящим окном")
        XCTAssertFalse(pimp.isWaitingPage)
    }

    /// «Под этим»: столбец делится ДО рождения, новое окно рождается в углу нижней половины.
    func testBelowSplitsBeforeBirth() {
        let box = makeTemp(), rig = Rig()
        let column = CGRect(x: 0, y: 34, width: 490, height: 859)
        rig.windows = [PimpWindow(id: 1, title: "Claude", chat: NewWindowPlaceWF98Tests.fromChat, frame: column)]
        let pimp = channel(rig, in: box)
        let body = "{\"id\":\"1788780000000-0500\",\"at\":\"\(PimpChannel.stampText(rig.now))\","
            + "\"action\":\"new-window\",\"from\":\"\(NewWindowPlaceWF98Tests.fromChat)\","
            + "\"project\":\"Dictator\",\"place\":\"below\"}"
        try? Data(body.utf8).write(to: box.appendingPathComponent("1788780000000-0500.json"))
        pimp.tick()
        let halves = PimpChannel.split(column, above: false)!
        XCTAssertEqual(rig.placed.first, [PimpMove(id: 1, frame: halves.old)], "верхняя половина — сразу")
        XCTAssertEqual(rig.origins.first??.y, Int(halves.new.minY))
        rig.windows.append(PimpWindow(id: 4, title: "Dictator",
                                      frame: CGRect(origin: halves.new.origin, size: CGSize(width: 900, height: 700))))
        rig.poll(until: rig.now.addingTimeInterval(1))
        XCTAssertEqual(rig.placedNew.map { $0.move }, [PimpMove(id: 4, frame: halves.new)])
        XCTAssertEqual(rig.placed.count, 1, "делим один раз, до рождения")
    }

    /// Номер без AX-пары (служебное окно) опрос смотрит полным списком не дольше секунды.
    func testServiceWindowIsLookedAtOnlyForGrace() {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let pimp = channel(rig, in: box)
        XCTAssertTrue(pimp.startNewWindow(project: dictator))
        rig.extraIDs = [77]
        let before = rig.windowsCalls
        rig.poll(until: rig.now.addingTimeInterval(1.05))
        let during = rig.windowsCalls - before
        XCTAssertGreaterThan(during, 5)
        rig.poll(until: rig.now.addingTimeInterval(3))
        XCTAssertEqual(rig.windowsCalls - before, during, "после секунды — только дешёвый список номеров")
        XCTAssertTrue(pimp.isWaitingPage)
    }

    /// WF101 (z3-r02): свежий номер на экране — кэш AX-окон сбрасывается на каждом шаге окна
    /// поиска, а не ждёт своей секунды; до номера и после окна поиска — не трогается.
    func testFreshWindowIDDropsAXCache() {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let pimp = channel(rig, in: box)
        var born = 0
        pimp.seats.windowBorn = { born += 1 }
        XCTAssertTrue(pimp.startNewWindow(project: dictator))
        rig.poll(until: rig.now.addingTimeInterval(0.35))
        XCTAssertEqual(born, 0, "нового номера нет — кэш живёт")
        rig.extraIDs = [77]
        rig.poll(until: rig.now.addingTimeInterval(1.05))
        let during = born
        XCTAssertGreaterThan(during, 5)
        rig.poll(until: rig.now.addingTimeInterval(2))
        XCTAssertEqual(born, during)
    }

    /// Без сиденья номеров (старые сборки сидений) — ни плана опроса, ни лишних шагов: тик 2 с.
    func testWithoutWindowIDsNoPoll() {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let pimp = PimpChannel(directory: box, now: { rig.now })
        var seats = rig.seats()
        seats.windowIDs = nil
        pimp.seats = seats
        XCTAssertTrue(pimp.startNewWindow(project: dictator))
        XCTAssertTrue(rig.queued.isEmpty)
    }

    // MARK: - проверка гейта WF98: сверка рамки, возврат снимка, ChatGPT

    /// Electron отыграл рамку после первой записи — через `recheckSeconds` окно ставится ещё
    /// раз, ровно один; стоит на месте — второй записи нет (первый тест).
    func testPlacedWindowIsRecheckedOnce() {
        let box = makeTemp(), rig = Rig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
                       PimpWindow(id: 2, title: "Второй", frame: CGRect(x: 735, y: 34, width: 735, height: 859))]
        let pimp = channel(rig, in: box)
        XCTAssertTrue(pimp.startNewWindow(project: dictator))
        rig.windows.append(PimpWindow(id: 3, title: "Dictator", frame: CGRect(x: 980, y: 34, width: 900, height: 700)))
        let cell = CGRect(x: 980, y: 34, width: 490, height: 859)
        var bounced = false
        rig.poll(until: rig.now.addingTimeInterval(3)) { _ in
            // Сразу после первой записи окно «отскочило» в свой прежний размер.
            if rig.placedNew.count == 1, !bounced {
                bounced = true
                rig.move(3, to: CGRect(x: 980, y: 34, width: 900, height: 700))
            }
        }
        XCTAssertFalse(pimp.isWaitingPage)
        XCTAssertEqual(rig.placedNew.map { $0.move }, [PimpMove(id: 3, frame: cell), PimpMove(id: 3, frame: cell)])
        let gap = rig.placedNew[1].at.timeIntervalSince(rig.placedNew[0].at)
        XCTAssertEqual(gap, PimpChannel.recheckSeconds, accuracy: 0.001)
        XCTAssertTrue(rig.queued.isEmpty, "сверка одна")
    }

    /// Окно пришло во время возврата снимка окон: соседей не раздвигали, опрос окна не берёт;
    /// возврат кончился — окно ловится и ставится по-старому (плана нет).
    func testWindowArrivingDuringRestoreWaits() {
        let box = makeTemp(), rig = Rig()
        let one = CGRect(x: 0, y: 34, width: 735, height: 859)
        let two = CGRect(x: 735, y: 34, width: 735, height: 859)
        rig.windows = [PimpWindow(id: 1, title: "Claude", frame: one),
                       PimpWindow(id: 2, title: "Второй", frame: two)]
        let pimp = channel(rig, in: box)
        var restoring = true
        pimp.seats.isRestoring = { restoring }
        XCTAssertTrue(pimp.startNewWindow(project: dictator))
        XCTAssertTrue(rig.room.isEmpty, "во время возврата соседей не раздвигаем")
        XCTAssertEqual(rig.windows.map { $0.frame }, [one, two])
        XCTAssertNil(rig.origins.first ?? nil, "точки нет — окно рождается как в меню")

        rig.windows.append(PimpWindow(id: 3, title: "Dictator", frame: CGRect(x: 980, y: 34, width: 900, height: 700)))
        let before = rig.windowsCalls
        rig.poll(until: rig.now.addingTimeInterval(1))
        XCTAssertTrue(pimp.isWaitingPage, "опрос не взял окно во время возврата")
        XCTAssertEqual(rig.windowsCalls, before, "и полный список не гонял")
        XCTAssertTrue(rig.placedNew.isEmpty)

        restoring = false
        rig.poll(until: rig.now.addingTimeInterval(0.5))
        XCTAssertFalse(pimp.isWaitingPage)
        XCTAssertTrue(rig.placedNew.isEmpty, "плана не было — ставит умная расстановка")
        XCTAssertEqual(rig.smartCalls, 1)
    }

    /// Окно не пришло: ChatGPT, которого `makeRoom` сузил, возвращается в прежнюю рамку —
    /// только если так и стоит, куда его сдвинули.
    func testNoWindowPutsChatGPTBack() {
        for movedByHand in [false, true] {
            let box = makeTemp(), rig = Rig()
            rig.windows = [PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 735, height: 859))]
            let pimp = channel(rig, in: box)
            let wide = CGRect(x: 735, y: 34, width: 735, height: 859)
            let narrow = CGRect(x: 1100, y: 34, width: 370, height: 859)
            var gpt: CGRect? = wide
            var gptPlaced: [CGRect] = []
            pimp.seats.chatGPT = { gpt.map { PimpWindow(id: 0, title: "ChatGPT", frame: $0) } }
            pimp.seats.placeChatGPT = { gptPlaced.append($0); gpt = $0 }
            let room = pimp.seats.makeRoom
            pimp.seats.makeRoom = { ids in gpt = narrow; return room(ids) }
            XCTAssertTrue(pimp.startNewWindow(project: dictator))
            XCTAssertEqual(gpt, narrow)
            if movedByHand { gpt = CGRect(x: 200, y: 200, width: 600, height: 600) }

            rig.now = rig.now.addingTimeInterval(PimpChannel.newWindowSeconds + 1)
            pimp.tick()
            XCTAssertFalse(pimp.isWaitingPage)
            XCTAssertEqual(gptPlaced, movedByHand ? [] : [wide], "подвинутый руками — не трогаем")
        }
    }

    // MARK: - «Обкэшить» / «💬 Новый чат»: окно сразу на месте донора

    private final class CashoutRig {
        let actions: ClaudeActions
        var now = Date(timeIntervalSince1970: 1_790_400_000)
        var queued: [(delay: TimeInterval, run: () -> Void)] = []
        var list: [(id: CGWindowID, window: AXUIElement, title: String, frame: CGRect)] = []
        var fresh: [(window: AXUIElement, frame: CGRect, at: Date)] = []
        var restoring = false
        var moved = 0

        init() {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("wf98c-\(UUID().uuidString)", isDirectory: true)
            actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                    commands: CommandChannel(path: dir.appendingPathComponent("command.json"),
                                                             now: { Date() }, schedule: { _, _ in }))
            actions.clock = { [unowned self] in self.now }
            actions.schedule = { [unowned self] delay, block in self.queued.append((delay, block)) }
            actions.cashoutWindows = { [unowned self] in self.list }
            actions.windowIDs = { [unowned self] in Set(self.list.map { $0.id }) }
            actions.isRestoringWindows = { [unowned self] in self.restoring }
            actions.placeFresh = { [unowned self] window, frame in self.fresh.append((window, frame, self.now)) }
            actions.onWindowsMoved = { [unowned self] in self.moved += 1 }
        }

        func poll(steps: Int, birth: (Int) -> Void = { _ in }) {
            for step in 0..<steps {
                guard !queued.isEmpty else { return }
                let next = queued.removeFirst()
                now = now.addingTimeInterval(next.delay)
                birth(step)
                next.run()
            }
        }
    }

    func testCashoutWindowTakesDonorFrameAtBirth() {
        let rig = CashoutRig()
        let donor = AXUIElementCreateApplication(999_981)
        let born = AXUIElementCreateApplication(999_982)
        let frame = CGRect(x: 500, y: 34, width: 480, height: 859)
        rig.list = [(id: 2, window: donor, title: "Старый чат", frame: frame)]
        rig.actions.beginCashoutReplace(donor: frame, window: donor, handoff: true)
        XCTAssertEqual(rig.queued.map { $0.delay }, [BirthWatch.pollSeconds])
        rig.poll(steps: 60) { step in
            guard step == 40, rig.list.count == 1 else { return }
            rig.list.append((id: 5, window: born, title: "Code", frame: CGRect(x: 500, y: 34, width: 900, height: 700)))
        }
        XCTAssertEqual(rig.fresh.count, 1)
        XCTAssertTrue(rig.fresh.first.map { CFEqual($0.window, born) } ?? false)
        XCTAssertEqual(rig.fresh.first?.frame, frame, "рамка донора — сразу, не по «вставлено»")
        XCTAssertEqual(rig.moved, 1)
        XCTAssertTrue(rig.queued.isEmpty, "поставили — опрос погас")
        XCTAssertTrue(rig.actions.cashoutPending, "донор жив: закрытие — только по «вставлено» (#5779)")
    }

    /// Окно пришло, пока идёт возврат окон: не ставим вовсе — «единственное новое» могло быть
    /// окном возврата; встанет по «вставлено», по заголовку, как до WF98.
    func testCashoutWindowDuringRestoreIsNotPlaced() {
        let rig = CashoutRig()
        let donor = AXUIElementCreateApplication(999_983)
        let frame = CGRect(x: 500, y: 34, width: 480, height: 859)
        rig.list = [(id: 2, window: donor, title: "Старый чат", frame: frame)]
        rig.actions.beginCashoutReplace(donor: frame, window: donor, handoff: true)
        rig.restoring = true
        rig.list.append((id: 6, window: AXUIElementCreateApplication(999_984), title: "Code",
                         frame: CGRect(x: 0, y: 0, width: 900, height: 700)))
        rig.poll(steps: 10)
        XCTAssertTrue(rig.fresh.isEmpty)
        XCTAssertTrue(rig.queued.isEmpty, "опрос брошен до конца работы")
    }

    /// Два новых окна разом — не гадаем.
    func testCashoutTwoNewWindowsAreLeftToLandedPath() {
        let rig = CashoutRig()
        let donor = AXUIElementCreateApplication(999_985)
        let frame = CGRect(x: 500, y: 34, width: 480, height: 859)
        rig.list = [(id: 2, window: donor, title: "Старый чат", frame: frame)]
        rig.actions.beginCashoutReplace(donor: frame, window: donor, handoff: false)
        rig.list += [(id: 7, window: AXUIElementCreateApplication(999_986), title: "A", frame: .zero),
                     (id: 8, window: AXUIElementCreateApplication(999_987), title: "B", frame: .zero)]
        rig.poll(steps: 5)
        XCTAssertTrue(rig.fresh.isEmpty)
        XCTAssertTrue(rig.queued.isEmpty)
    }

    /// Без сиденья номеров — как до WF98: опроса нет (BusyWF97 держит очередь пустой).
    func testCashoutWithoutWindowIDsHasNoPoll() {
        let rig = CashoutRig()
        rig.actions.windowIDs = nil
        let donor = AXUIElementCreateApplication(999_988)
        let frame = CGRect(x: 500, y: 34, width: 480, height: 859)
        rig.list = [(id: 2, window: donor, title: "Старый чат", frame: frame)]
        rig.actions.beginCashoutReplace(donor: frame, window: donor)
        XCTAssertTrue(rig.queued.isEmpty)
    }

    // MARK: - опрос номеров

    func testBirthWatchGrace() {
        let t0 = Date(timeIntervalSince1970: 0)
        var watch = BirthWatch(seen: [1, 2])
        XCTAssertFalse(watch.worthLooking([1, 2], at: t0))
        XCTAssertTrue(watch.worthLooking([1, 2, 3], at: t0.addingTimeInterval(0.1)))
        XCTAssertTrue(watch.worthLooking([1, 2, 3], at: t0.addingTimeInterval(1.0)))
        XCTAssertFalse(watch.worthLooking([1, 2, 3], at: t0.addingTimeInterval(1.2)), "секунда вышла")
        XCTAssertTrue(watch.worthLooking([1, 2, 3, 4], at: t0.addingTimeInterval(1.3)), "новый номер — снова смотрим")
    }
}

private extension PimpChannel {
    static func fixturesRequest(_ dir: URL) -> URL { dir.appendingPathComponent("new-window.request.json") }
}
