import XCTest
@testable import ClaudeAX

/// #7975 (WF120): после сна, блокировки или мигания мониторов набор экранов тот же («A → A»),
/// а macOS сжала окна, — один возврат раскладки; уведомление без смены ключа ничего не трогает.
final class ScreenWakeWF120Tests: XCTestCase {
    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pimp-wf120-wake-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.appendingPathComponent(ScreenLayoutStore.fileName)
    }

    /// Стенд хранителя, как у WF94WindowsTests: мониторы, окна и ChatGPT в памяти.
    private final class Desk {
        static let mac = ScreenSpec(name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        static let big = ScreenSpec(name: "Odyssey", frame: CGRect(x: -3360, y: -575, width: 2560, height: 720))
        var screens = [Desk.mac, Desk.big]
        var windows: [PimpWindow] = []
        var chatGPT: CGRect?
        var busy = false
        var monitors = true
        var pid: pid_t? = 77
        var complete = true
        var applied: [(moves: [PimpMove], chatGPT: CGRect?)] = []
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let keeper: ScreenLayoutKeeper

        init(url: URL) {
            keeper = ScreenLayoutKeeper(store: ScreenLayoutStore(url: url))
            keeper.screens = { [unowned self] in self.screens }
            keeper.windows = { [unowned self] in
                WindowSnapshotStore.windows(from: self.windows, isMain: { $0 == "Claude" }, screen: { _ in "" })
            }
            keeper.processID = { [unowned self] in self.pid }
            keeper.wakeInputReady = { [unowned self] in self.monitors }
            keeper.observation = { [unowned self] in
                SnapshotObservation(windows: self.keeper.windows(), complete: self.complete)
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

        /// Возвраты, которые правда двигали окна (повтор через 5 с по месту ничего не двигает).
        var moving: Int { applied.filter { !$0.moves.isEmpty || $0.chatGPT != nil }.count }
    }

    private static let onOdyssey: [PimpWindow] = [
        PimpWindow(id: 1, title: "Claude", frame: CGRect(x: -3360, y: -575, width: 600, height: 720)),
        PimpWindow(id: 2, title: "Пимп", chat: "local_b", frame: CGRect(x: -2755, y: -575, width: 600, height: 720)),
        PimpWindow(id: 3, title: "Вкуснофф", chat: "local_c", frame: CGRect(x: -2150, y: -575, width: 600, height: 720)),
    ]

    /// Что сделала macOS за сон: окна съехали к левому краю и сжались.
    private static let squeezed: [PimpWindow] = onOdyssey.map {
        PimpWindow(id: $0.id, title: $0.title, chat: $0.chat,
                   frame: CGRect(x: -3360, y: -575, width: 420, height: 600))
    }

    private func recorded(_ url: URL) -> Desk {
        let desk = Desk(url: url)
        desk.windows = ScreenWakeWF120Tests.onOdyssey
        desk.run(24)
        XCTAssertEqual(desk.keeper.writes, 1, "раскладка набора записана")
        return desk
    }

    /// Мониторы мигнули A → B → A быстрее тишины, и macOS успела сжать окна — ровно один возврат.
    func testFlickerFasterThanQuietRestoresSqueezedWindowsOnce() {
        let url = makeTemp()
        let desk = recorded(url)
        desk.screens = [Desk.mac]
        desk.windows = ScreenWakeWF120Tests.squeezed
        desk.run(0.5)
        desk.screens = [Desk.mac, Desk.big]
        desk.run(16)
        XCTAssertEqual(desk.moving, 1, "один возврат; повтор через 5 с окна уже не двигает")
        XCTAssertEqual(desk.windows.map { $0.frame }, ScreenWakeWF120Tests.onOdyssey.map { $0.frame })
        XCTAssertTrue(desk.keeper.status.hasSuffix("/1"), desk.keeper.status)
    }

    /// Сон Мака: набор тот же, окна сжаты — после тишины один возврат; сжатая раскладка не записана.
    func testWakeWithSameScreensRestoresSqueezedWindowsOnce() {
        let url = makeTemp()
        let desk = recorded(url)
        desk.windows = ScreenWakeWF120Tests.squeezed
        desk.keeper.noteWake(at: desk.now)
        desk.run(2)
        XCTAssertTrue(desk.applied.isEmpty, "до тишины 2 с — ждём")
        desk.run(60)
        XCTAssertEqual(desk.moving, 1)
        XCTAssertEqual(desk.windows.map { $0.frame }, ScreenWakeWF120Tests.onOdyssey.map { $0.frame })
        XCTAssertEqual(ScreenLayoutStore(url: url).load().first?.windows.map { $0.frame },
                       ScreenWakeWF120Tests.onOdyssey.map { $0.frame }, "сжатая раскладка не записана")
    }

    /// Проснулись, а окна на месте — ничего не трогаем, и выборка дальше пишет как обычно.
    func testWakeWithWindowsInPlaceDoesNothingAndSamplingGoesOn() {
        let url = makeTemp()
        let desk = recorded(url)
        desk.keeper.noteWake(at: desk.now)
        desk.run(6)
        XCTAssertTrue(desk.applied.isEmpty, "окна стоят по записи — возвращать нечего")
        desk.windows[0] = PimpWindow(id: 1, title: "Claude", frame: CGRect(x: -3360, y: -575, width: 500, height: 720))
        desk.run(40)
        XCTAssertEqual(desk.keeper.writes, 2, "окно подвинули руками — записали")
        XCTAssertTrue(desk.applied.isEmpty)
        XCTAssertTrue(desk.keeper.status.hasSuffix("/0"), desk.keeper.status)
    }

    /// Уведомление без смены ключа (док, меню-бар) и сжатые окна — по-прежнему ничего.
    func testNoticeWithoutKeyChangeStillLeavesWindowsAlone() {
        let url = makeTemp()
        let desk = recorded(url)
        desk.windows = ScreenWakeWF120Tests.squeezed
        desk.keeper.noteScreensChanged(at: desk.now)
        desk.run(40)
        XCTAssertTrue(desk.applied.isEmpty, "смены набора не было — окна не трогаем")
    }

    /// Канал «Пимп» занят — возврат после сна ждёт; занят дольше минуты — брошен, как у X → Y.
    func testWakeWaitsForBusyChannelAndGivesUpAfterMinute() {
        let url = makeTemp()
        let desk = recorded(url)
        desk.windows = ScreenWakeWF120Tests.squeezed
        desk.busy = true
        desk.keeper.noteWake(at: desk.now)
        desk.run(20)
        XCTAssertTrue(desk.applied.isEmpty, "канал занят — ждём")
        desk.busy = false
        desk.run(2)
        XCTAssertEqual(desk.moving, 1, "освободился — вернули")

        let late = recorded(makeTemp())
        late.windows = ScreenWakeWF120Tests.squeezed
        late.busy = true
        late.keeper.noteWake(at: late.now)
        late.run(70)
        late.busy = false
        late.run(10)
        XCTAssertTrue(late.applied.isEmpty, "занят дольше минуты — возврат брошен")
    }

    /// Пробуждение до первого взгляда на мониторы — набора «до» нет, возвращать нечего.
    func testWakeBeforeFirstTickIsIgnored() {
        let url = makeTemp()
        let first = recorded(url)
        let desk = Desk(url: url)
        desk.now = first.now
        desk.windows = ScreenWakeWF120Tests.squeezed
        desk.keeper.noteWake(at: desk.now)
        desk.run(10)
        XCTAssertTrue(desk.applied.isEmpty, "на запуске ничего не возвращаем")
    }
    func testPairedWakeAndManualInputCancelWholeEpisode() {
        for afterApply in [false, true] {
            let desk = recorded(makeTemp())
            desk.keeper.noteSleep()
            desk.windows = Self.squeezed
            desk.keeper.noteWake(at: desk.now)
            desk.keeper.noteWake(at: desk.now.addingTimeInterval(0.5))
            if afterApply { desk.run(6); XCTAssertEqual(desk.moving, 1) }
            desk.keeper.cancelWake()
            let manual = Self.squeezed.map { PimpWindow(id: $0.id, title: $0.title, chat: $0.chat,
                frame: $0.frame.offsetBy(dx: 30, dy: 15)) }
            desk.windows = manual
            desk.keeper.noteWake(at: desk.now.addingTimeInterval(1))
            desk.run(12)
            XCTAssertEqual(desk.windows.map { $0.frame }, manual.map { $0.frame })
            XCTAssertEqual(desk.moving, afterApply ? 1 : 0)
        }
    }

    func testMissingMonitorsPIDChangeIncompleteOrChangedWindowsCannotRestore() {
        for failure in 0..<5 {
            let desk = recorded(makeTemp())
            desk.keeper.noteSleep()
            desk.windows = Self.squeezed
            switch failure {
            case 0: desk.monitors = false
            case 1: desk.pid = 88
            case 2: desk.complete = false
            case 3: desk.windows.removeLast()
            default: desk.windows.append(desk.windows[1])
            }
            desk.keeper.noteWake(at: desk.now)
            desk.run(10)
            XCTAssertTrue(desk.applied.isEmpty, "case \(failure)")
        }
    }

    func testMonitorLossBeforeRetryAndLaterPairedWakeDoesNotRearm() {
        let desk = recorded(makeTemp())
        desk.windows = Self.squeezed
        desk.keeper.noteWake(at: desk.now)
        desk.run(4)
        XCTAssertEqual(desk.moving, 1)
        desk.windows = Self.squeezed
        desk.monitors = false
        desk.run(4)
        desk.monitors = true
        desk.keeper.noteWake(at: desk.now)
        desk.run(10)
        XCTAssertEqual(desk.moving, 1)
        XCTAssertEqual(desk.windows.map { $0.frame }, Self.squeezed.map { $0.frame })
    }

    func testFailedProtectionWriteNeverMovesAndManualRestoreStillWorksWithoutMonitors() {
        let url = makeTemp(), desk = recorded(makeTemp())
        // A keeper with a read baseline but a deliberately unwritable file target.
        let good = ScreenLayoutStore(url: url)
        let layout = ScreenLayout(key: ScreenLayoutKeeper.key(desk.screens), at: desk.now,
                                  windows: desk.keeper.windows(), chatGPT: nil)
        XCTAssertTrue(good.save([layout]))
        let keeper = ScreenLayoutKeeper(store: good)
        keeper.screens = { desk.screens }; keeper.windows = { desk.keeper.windows() }
        keeper.live = { desk.windows }; keeper.isMain = { $0 == "Claude" }
        keeper.processID = { 77 }; keeper.wakeInputReady = { true }
        var applied = 0; keeper.apply = { _, _ in applied += 1 }
        keeper.tick(at: desk.now)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        desk.windows = Self.squeezed
        keeper.noteWake(at: desk.now)
        keeper.tick(at: desk.now.addingTimeInterval(3))
        XCTAssertEqual(applied, 0)
        // Explicit restore is independent of automatic input monitor permission.
        desk.monitors = false
        XCTAssertNotNil(desk.keeper.restoreNow(at: desk.now))
        XCTAssertEqual(desk.moving, 1)
    }

    func testWakeWaitsForFreshIdentityWithoutOverwritingBaseline() {
        let desk = recorded(makeTemp())
        desk.keeper.noteSleep()
        desk.windows = Self.squeezed
        desk.complete = false
        desk.keeper.noteWake(at: desk.now)
        desk.run(12)
        XCTAssertEqual(desk.moving, 0)
        XCTAssertTrue(desk.keeper.wantsWakeProbe)
        desk.complete = true
        desk.run(4)
        XCTAssertEqual(desk.moving, 1)
        XCTAssertEqual(desk.windows.map { $0.frame }, Self.onOdyssey.map { $0.frame })
    }

    func testInputAfterCompletedWakeDoesNotDisableOrdinarySampling() {
        let desk = recorded(makeTemp())
        desk.keeper.noteSleep()
        desk.windows = Self.squeezed
        desk.keeper.noteWake(at: desk.now)
        desk.run(60)
        XCTAssertEqual(desk.moving, 1)
        let writes = desk.keeper.writes
        desk.windows[0] = PimpWindow(id: 1, title: "Claude", frame: CGRect(x: -3360, y: -575, width: 500, height: 720))
        for _ in 0..<20 { desk.keeper.cancelWake(); desk.run(2) }
        XCTAssertGreaterThan(desk.keeper.writes, writes)
        XCTAssertEqual(desk.moving, 1)
    }

    func testSecondSleepStartsItsOwnDeadline() {
        let desk = recorded(makeTemp())
        for _ in 0..<2 {
            desk.keeper.noteSleep()
            desk.windows = Self.squeezed
            desk.keeper.noteWake(at: desk.now)
            desk.run(90)
        }
        XCTAssertEqual(desk.moving, 2)
        XCTAssertEqual(desk.windows.map { $0.frame }, Self.onOdyssey.map { $0.frame })
    }

    func testManualMoveImmediatelyBeforeSleepIsNotReversed() {
        let desk = recorded(makeTemp())
        desk.keeper.cancelWake() // The input monitor fires before the drag changes frames.
        let manual = Self.onOdyssey.map { PimpWindow(id: $0.id, title: $0.title, chat: $0.chat,
            frame: $0.frame.offsetBy(dx: 20, dy: 0)) }
        desk.windows = manual
        desk.keeper.noteSleep() // No stable sampling interval has elapsed.
        desk.keeper.noteWake(at: desk.now)
        desk.run(12)
        XCTAssertEqual(desk.moving, 0)
        XCTAssertEqual(desk.windows.map { $0.frame }, manual.map { $0.frame })
    }

}
