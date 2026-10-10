import XCTest
@testable import ClaudeAX

/// Второе нажатие, пока идёт первое (WF97 Б5s, #7772): без второго окна, второго переноса и
/// второго zip — только «уже идёт».
final class BusyWF97Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_400_000)

    private final class Rig {
        let actions: ClaudeActions
        var now: Date
        var queued: [(delay: TimeInterval, run: () -> Void)] = []
        var notices: [String] = []
        var warnings: [String] = []
        var run: NewWindowRun?

        init(at: Date) {
            now = at
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("busy97-\(UUID().uuidString)", isDirectory: true)
            actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                    commands: CommandChannel(path: dir.appendingPathComponent("command.json"),
                                                             now: { at }, schedule: { _, _ in }))
            actions.clock = { [unowned self] in self.now }
            actions.schedule = { [unowned self] delay, block in self.queued.append((delay, block)) }
            actions.onNotice = { [unowned self] text, _ in self.notices.append(text) }
            actions.onWarning = { [unowned self] in self.warnings.append($0) }
            actions.newWindowRun = { [unowned self] in self.run }
        }
    }

    // MARK: - «Новое окно»: ⌥⌘N, «Здесь же», «▸ проект»

    func testNewWindowRepeatIsRefusedWhileChainRuns() {
        let rig = Rig(at: t0)
        XCTAssertFalse(rig.actions.refuseNewWindowRepeat(), "первое нажатие проходит")
        rig.actions.whenBlankIdle {} // выпуск цепочки ставит метку прогрева
        rig.now = t0.addingTimeInterval(1)
        XCTAssertTrue(rig.actions.refuseNewWindowRepeat(), "второе через секунду — повтор")
        XCTAssertEqual(rig.notices, [MenuModel.newWindowRepeatNotice])

        // Страница взяла цепочку и ведёт её — повтор и после окна времени.
        rig.run = NewWindowRun(at: t0.addingTimeInterval(2), step: "store", handoff: "", chat: "", state: "run", busy: true)
        rig.now = t0.addingTimeInterval(ClaudeActions.newWindowRepeatSeconds + 5)
        XCTAssertTrue(rig.actions.refuseNewWindowRepeat())

        // Страница сказала «кончилось» — свободно сразу.
        rig.run = NewWindowRun(at: t0.addingTimeInterval(12), step: "back", handoff: "", chat: "", state: "ok")
        XCTAssertFalse(rig.actions.refuseNewWindowRepeat())
        XCTAssertEqual(rig.notices.count, 2)
    }

    func testNewWindowStartingRule() {
        let since = t0
        let at = { (s: TimeInterval) in self.t0.addingTimeInterval(s) }
        XCTAssertFalse(ClaudeActions.newWindowStarting(since: nil, run: nil, cashout: false, now: at(0)))
        XCTAssertTrue(ClaudeActions.newWindowStarting(since: nil, run: nil, cashout: true, now: at(0)),
                      "идёт «Обкэшить» — его цепочка тоже новое окно")
        XCTAssertTrue(ClaudeActions.newWindowStarting(since: since, run: nil, cashout: false, now: at(3)))
        XCTAssertFalse(ClaudeActions.newWindowStarting(since: since, run: nil, cashout: false,
                                                       now: at(ClaudeActions.newWindowRepeatSeconds)),
                       "страница молчит — решает одно время")
        let stale = NewWindowRun(at: at(-60), step: "back", handoff: "", chat: "", state: "ok")
        XCTAssertTrue(ClaudeActions.newWindowStarting(since: since, run: stale, cashout: false, now: at(3)),
                      "прошлый исход до нажатия — не «кончилось»")
        let stuck = NewWindowRun(at: at(-60), step: "store", handoff: "", chat: "", state: "run", busy: true)
        XCTAssertFalse(ClaudeActions.newWindowStarting(since: nil, run: stuck, cashout: false, now: at(0)),
                       "busy без отметок 40 с — зависшая запись, не держим")
        XCTAssertEqual(NewWindowRun.parse(["at": 1_790_400_000_000.0, "busy": true, "state": "run"])?.busy, true)
        XCTAssertEqual(NewWindowRun.parse(["at": 1_790_400_000_000.0, "state": "ok"])?.busy, false)
    }

    // MARK: - «Обкэшить» / «💬 Новый чат» с того же окна

    func testCashoutRepeatOnSameWindowIsRefused() {
        let rig = Rig(at: t0)
        let donor = AXUIElementCreateApplication(999_811)
        let other = AXUIElementCreateApplication(999_812)
        var ran = 0
        rig.actions.whenCashoutIdle(for: donor) { ran += 1 }
        XCTAssertEqual(ran, 1)
        XCTAssertTrue(rig.actions.cashoutClaimed(donor))

        rig.actions.whenCashoutIdle(for: donor) { ran += 1 }
        XCTAssertEqual(ran, 1, "тот же донор, бронь идёт — второго переноса нет")
        XCTAssertTrue(rig.queued.isEmpty, "и в очередь не встаёт")
        XCTAssertEqual(rig.notices, [MenuModel.cashoutRepeatNotice])

        // Другое окно — как раньше: ждёт конца первого.
        rig.actions.whenCashoutIdle(for: other) { ran += 1 }
        XCTAssertEqual(ran, 1)
        XCTAssertEqual(rig.queued.count, 1)
        XCTAssertTrue(rig.actions.cashoutClaimed(other), "ждущее окно тоже занято")
        rig.actions.whenCashoutIdle(for: other) { ran += 1 }
        XCTAssertEqual(rig.queued.count, 1, "повтор ждущего не плодит второй опрос")

        // Бронь истекла — ждущий пошёл, донор снова свободен.
        rig.now = t0.addingTimeInterval(ClaudeActions.cashoutReserveSeconds)
        rig.queued.removeFirst().run()
        XCTAssertEqual(ran, 2)
        XCTAssertFalse(rig.actions.cashoutClaimed(donor))
        XCTAssertTrue(rig.actions.cashoutClaimed(other))
    }

    /// WF101 (z2-r02): перенос ждёт идущую цепочку «Нового окна» и пишется, когда она кончилась.
    func testCashoutWaitsForNewWindowChain() {
        let rig = Rig(at: t0)
        rig.run = NewWindowRun(at: t0, step: "store", handoff: "", chat: "", state: "run", busy: true)
        var ran = 0
        rig.actions.whenCashoutIdle(for: AXUIElementCreateApplication(999_831)) { ran += 1 }
        XCTAssertEqual(ran, 0, "цепочка идёт — перенос не пишется")
        XCTAssertEqual(rig.queued.count, 1)
        XCTAssertTrue(rig.actions.newWindowStarting, "то же сиденье видят меню и канал")

        rig.now = t0.addingTimeInterval(3)
        rig.run = NewWindowRun(at: t0.addingTimeInterval(2), step: "back", handoff: "", chat: "", state: "ok")
        rig.queued.removeFirst().run()
        XCTAssertEqual(ran, 1, "кончилась — перенос пошёл")
        XCTAssertTrue(rig.warnings.isEmpty)
    }

    func testCashoutGivesUpOnEndlessChain() {
        let rig = Rig(at: t0)
        var ran = 0
        rig.run = NewWindowRun(at: t0, step: "store", handoff: "", chat: "", state: "run", busy: true)
        rig.actions.whenCashoutIdle { ran += 1 }
        rig.now = t0.addingTimeInterval(ClaudeActions.cashoutWaitSeconds)
        rig.run = NewWindowRun(at: rig.now, step: "store", handoff: "", chat: "", state: "run", busy: true)
        rig.queued.removeLast().run()
        XCTAssertEqual(ran, 0, "не дольше cashoutWaitSeconds")
        XCTAssertEqual(rig.warnings, [MenuModel.cashoutBusyNotice])
    }

    func testCashoutJobClaimsItsDonor() {
        let rig = Rig(at: t0)
        let donor = AXUIElementCreateApplication(999_821)
        let frame = CGRect(x: 500, y: 34, width: 480, height: 859)
        rig.actions.cashoutWindows = { [(id: 2, window: donor, title: "Старый чат", frame: frame)] }
        rig.actions.beginCashoutReplace(donor: frame, window: donor, handoff: true)
        var ran = 0
        rig.actions.whenCashoutIdle(for: donor) { ran += 1 }
        XCTAssertEqual(ran, 0)
        XCTAssertTrue(rig.queued.isEmpty)
        XCTAssertEqual(rig.notices, [MenuModel.cashoutRepeatNotice])
    }

    // MARK: - «Бэкап чатов» в меню

    func testArchiveItemShowsBusy() {
        var config = MinimizeMenu.MenuConfig()
        let idle = MinimizeMenu.archiveChatsItem(config)
        XCTAssertEqual(idle.title, MenuModel.archiveChatsTitle)
        XCTAssertTrue(idle.isEnabled)
        config.archiveBusy = true
        let busy = MinimizeMenu.archiveChatsItem(config)
        XCTAssertEqual(busy.title, MenuModel.archiveChatsBusyTitle)
        XCTAssertFalse(busy.isEnabled)
    }
}
