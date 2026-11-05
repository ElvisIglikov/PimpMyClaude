import AppKit
import XCTest
@testable import ClaudeAX

/// Волна B WF88 (N2, 25.09.2026): «💬 Новый чат» из попапа встаёт на место старого и закрывает
/// его, даже когда свежий попап назвал себя прошлым чатом (#7378); мелочи проверки S — серая
/// строка подменю, правый клик только по переднему окну Claude, замок пустого окна в обе
/// стороны; маяк окон доступа у часов; хвост «Ждёт пользователя:» в карточке status.md.
final class WaveBTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_413_200)

    // MARK: - #7378: ход цепочки главного окна в круге переноса

    private func run(at: Date, step: String = "back", handoff: String = "send",
                     chat: String = "local_6f1bd03f") -> NewWindowRun {
        NewWindowRun(at: at, step: step, handoff: handoff, chat: chat)
    }

    private func mainPage(_ run: NewWindowRun?, at: Date) -> ChatPage {
        ChatPage(kind: .main, chat: "local_dc5ef534", title: "Claude", store: "ok", newWindow: run, at: at)
    }

    func testNewWindowRunParses() throws {
        let parsed = try XCTUnwrap(NewWindowRun.parse([
            "at": 1_790_413_205_000.0, "step": "back", "handoff": "send", "id": "local_6f1bd03f",
            "state": "ok", "busy": false,
        ] as [String: Any]))
        // С WF94 разбор держит и исход цепочки (`state`).
        XCTAssertEqual(parsed, NewWindowRun(at: t0.addingTimeInterval(5), step: "back", handoff: "send",
                                            chat: "local_6f1bd03f", state: "ok"))
        XCTAssertNil(NewWindowRun.parse(["step": "back"]), "без штампа — не ответ")
        XCTAssertNil(NewWindowRun.parse(NSNull()))
        let junk = try XCTUnwrap(NewWindowRun.parse(["at": 1.0, "id": "../etc", "handoff": 7] as [String: Any]))
        XCTAssertEqual(junk.chat, "", "id не по ситу — пусто")
        XCTAssertEqual(junk.handoff, "")
    }

    func testProbeTakesNewWindowOnlyFromMainPage() throws {
        let nonce = "chats-1-0001"
        let body: [String: Any] = ["at": 1, "results": [
            ["id": 1, "source": ProbeSourceFixture.metadata(url: "https://claude.ai/epitaxy/local_a"), "url": "https://claude.ai/epitaxy/local_a",
             "result": ["v": 1, "nonce": nonce, "kind": "main", "self": "local_a", "title": "Claude",
                        "newWindow": ["at": 1_790_413_205_000.0, "step": "back", "handoff": "send",
                                      "id": "local_b"]]],
            ["id": 2, "source": ProbeSourceFixture.metadata(url: "about:blank"), "url": "about:blank",
             "result": ["v": 1, "nonce": nonce, "kind": "popout", "self": "local_a", "title": "Loading",
                        "newWindow": ["at": 1_790_413_205_000.0, "step": "back", "handoff": "send",
                                      "id": "local_b"]]],
        ]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let pages = ChatProbe.parse(data, nonce: nonce, at: t0)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].newWindow?.chat, "local_b")
        XCTAssertNil(pages[1].newWindow, "у попапа цепочки «Нового окна» не бывает")
    }

    func testCashScriptAsksForNewWindowPlainDoesNot() {
        let plain = ChatProbe.script(nonce: "chats-1-0001", scan: false, cash: false)
        let asking = ChatProbe.script(nonce: "chats-1-0001", scan: false, cash: true)
        XCTAssertFalse(plain.contains("newWindow"))
        XCTAssertTrue(asking.contains("status.newWindow"))
        XCTAssertTrue(asking.contains("newWindow: newWindow"))
        XCTAssertTrue(ChatProbe.isOwnScript(asking))
    }

    func testHandoffSentNeedsThisRunPoppedOutWithTextGone() {
        let since = t0
        let later = t0.addingTimeInterval(9)
        XCTAssertTrue(ClaudeActions.handoffSent(pages: [mainPage(run(at: later), at: later)], since: since))
        XCTAssertTrue(ClaudeActions.handoffSent(pages: [mainPage(run(at: later, handoff: "empty"), at: later)],
                                                since: since), "текста не было — ждать нечего")
        XCTAssertFalse(ClaudeActions.handoffSent(pages: [mainPage(run(at: t0.addingTimeInterval(-60)), at: later)],
                                                 since: since), "цепочка прошлого нажатия")
        XCTAssertFalse(ClaudeActions.handoffSent(pages: [mainPage(run(at: later), at: t0.addingTimeInterval(-1))],
                                                 since: since), "круг до нажатия")
        XCTAssertFalse(ClaudeActions.handoffSent(pages: [mainPage(run(at: later, handoff: "held"), at: later)],
                                                 since: since), "текст ждёт вставки в новом окне")
        XCTAssertFalse(ClaudeActions.handoffSent(pages: [mainPage(run(at: later, handoff: "none"), at: later)],
                                                 since: since))
        XCTAssertFalse(ClaudeActions.handoffSent(pages: [mainPage(run(at: later, step: "popout"), at: later)],
                                                 since: since), "окно ещё не вынесено")
        XCTAssertFalse(ClaudeActions.handoffSent(pages: [mainPage(run(at: later, chat: ""), at: later)],
                                                 since: since), "сессия не родилась")
        XCTAssertFalse(ClaudeActions.handoffSent(pages: [mainPage(nil, at: later)], since: since))
        let popout = ChatPage(kind: .popout, chat: nil, title: "Loading", store: "ok",
                              newWindow: run(at: later), at: later)
        XCTAssertFalse(ClaudeActions.handoffSent(pages: [popout], since: since), "слово — только главного окна")
    }

    func testOnlyNewWindowIsSingleAndNotDonor() {
        XCTAssertEqual(ClaudeActions.onlyNewWindow(before: [1, 2], donor: 2, windows: [1, 2, 7]), 7)
        XCTAssertNil(ClaudeActions.onlyNewWindow(before: [1, 2], donor: 2, windows: [1, 2]), "не родилось")
        XCTAssertNil(ClaudeActions.onlyNewWindow(before: [1, 2], donor: 2, windows: [1, 2, 7, 8]),
                     "два новых — чужое окно тех же секунд, не берём")
        XCTAssertNil(ClaudeActions.onlyNewWindow(before: [1], donor: 2, windows: [1, 2]),
                     "донор новым окном не бывает")
    }

    // MARK: - шов cashoutTick: закрытие донора только в правильном случае (проверка wf93-n2)

    private typealias Win = (id: CGWindowID, window: AXUIElement, title: String, frame: CGRect)

    private final class CashRig {
        let actions: ClaudeActions
        var now: Date
        var queued: [(delay: TimeInterval, run: () -> Void)] = []
        var windows: [Win] = []
        var pages: [ChatPage] = []
        var closed: [AXUIElement] = []
        var warnings: [String] = []
        let main = AXUIElementCreateApplication(999_901)
        let donor = AXUIElementCreateApplication(999_902)
        let fresh = AXUIElementCreateApplication(999_903)
        let stranger = AXUIElementCreateApplication(999_904)
        let donorFrame = CGRect(x: 500, y: 34, width: 480, height: 859)
        /// Резолвер окна стенда (в бою — `WindowIdentity.resolveNative`): окно «Claude» и окно в
        /// рамке `mainFrame` — главное, прочие — попапы своего чата.
        var mainFrame: CGRect?

        init(at: Date) {
            now = at
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("waveb-\(UUID().uuidString)", isDirectory: true)
            actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                    commands: CommandChannel(path: dir.appendingPathComponent("command.json"),
                                                             now: { at }, schedule: { _, _ in }))
            actions.clock = { [unowned self] in self.now }
            actions.schedule = { [unowned self] delay, block in self.queued.append((delay, block)) }
            actions.cashoutWindows = { [unowned self] in self.windows }
            actions.cashoutAnswers = { [unowned self] in self.pages }
            actions.closeWindow = { [unowned self] window in self.closed.append(window); return true }
            actions.onWarning = { [unowned self] in self.warnings.append($0) }
            actions.windowIdentity = { [unowned self] title, frame in
                let isMain = title == "Claude" || (frame != nil && frame == self.mainFrame)
                return .page(ChatPage(kind: isMain ? .main : .popout, chat: isMain ? nil : "local_donor",
                                      title: title, store: "ok", at: self.now))
            }
            windows = [(1, main, "Claude", CGRect(x: 0, y: 34, width: 490, height: 859)),
                       (2, donor, "Старый чат", donorFrame)]
        }

        func start(handoff: Bool) {
            actions.beginCashoutReplace(donor: donorFrame, window: donor, handoff: handoff)
        }

        func born(_ id: CGWindowID = 3, _ window: AXUIElement? = nil, title: String = "Loading") {
            windows.append((id, window ?? fresh, title, CGRect(x: 520, y: 60, width: 480, height: 700)))
        }

        func mainSays(_ handoff: String, step: String = "back") {
            let at = now
            pages = [ChatPage(kind: .main, chat: "local_dc5ef534", title: "Claude", store: "ok",
                              newWindow: NewWindowRun(at: at, step: step, handoff: handoff, chat: "local_6f1bd03f"),
                              at: at)]
        }

        /// Тик, потом все отложенные шаги (пауза перед закрытием).
        func tick() {
            actions.cashoutTick()
            while !queued.isEmpty { queued.removeFirst().run() }
        }

        var closedDonor: Bool { closed.count == 1 && CFEqual(closed[0], donor) }
    }

    func testHandoffClosesDonorOnlyOnMainWordAndSingleNewWindow() {
        for word in ["send", "empty"] {
            let rig = CashRig(at: t0)
            rig.start(handoff: true)
            XCTAssertTrue(rig.actions.cashoutPending)
            rig.now = t0.addingTimeInterval(9)
            rig.born()
            rig.mainSays(word)
            rig.tick()
            XCTAssertTrue(rig.closedDonor, "handoff+back+\(word)+одно новое окно — донор закрыт")
            XCTAssertEqual(rig.warnings, [MenuModel.cashoutReplacedNotice])
            XCTAssertFalse(rig.actions.cashoutPending)
        }
    }

    func testHandoffKeepsDonorWhenWordOrWindowIsWrong() {
        let cases: [(name: String, word: String, step: String, born: Int)] = [
            ("held — слово за новой страницей", "held", "back", 1),
            ("none — записи нет", "none", "back", 1),
            ("окно ещё не вынесено", "send", "popout", 1),
            ("два новых окна", "send", "back", 2),
            ("нового окна нет", "send", "back", 0),
        ]
        for c in cases {
            let rig = CashRig(at: t0)
            rig.start(handoff: true)
            rig.now = t0.addingTimeInterval(9)
            if c.born >= 1 { rig.born() }
            if c.born >= 2 { rig.born(4, rig.stranger, title: "Чужой") }
            rig.mainSays(c.word, step: c.step)
            rig.tick()
            XCTAssertTrue(rig.closed.isEmpty, c.name)
            XCTAssertTrue(rig.warnings.isEmpty, c.name)
            XCTAssertTrue(rig.actions.cashoutPending, "\(c.name): ждём до потолка")
        }
    }

    func testCashoutHasNoOnlyNewWindowFallback() {
        // «Обкэшить»: слово главного окна не довод.
        let rig = CashRig(at: t0)
        rig.start(handoff: false)
        rig.now = t0.addingTimeInterval(9)
        rig.born()
        rig.mainSays("send")
        rig.tick()
        XCTAssertTrue(rig.closed.isEmpty)
        XCTAssertTrue(rig.actions.cashoutPending)

        // «Вставлено» чужим заголовком: «Новый чат» берёт единственное новое окно, «Обкэшить» — нет.
        for handoff in [true, false] {
            let rig = CashRig(at: t0)
            rig.start(handoff: handoff)
            rig.now = t0.addingTimeInterval(9)
            rig.born(title: "Новый чат проекта")
            rig.pages = [ChatPage(kind: .popout, chat: nil, title: "Старый чат", store: "ok",
                                  cashout: ClaudeActions.cashoutLanded, at: rig.now)]
            rig.tick()
            XCTAssertEqual(rig.closedDonor, handoff)
        }

        // «Вставлено» от «Loading»: по заглушке окно не сопоставляем.
        let loading = CashRig(at: t0)
        loading.start(handoff: false)
        loading.now = t0.addingTimeInterval(9)
        loading.born(title: "Loading")
        loading.pages = [ChatPage(kind: .popout, chat: nil, title: "Loading", store: "ok",
                                  cashout: ClaudeActions.cashoutLanded, at: loading.now)]
        loading.tick()
        XCTAssertTrue(loading.closed.isEmpty)
    }

    func testDonorRecheckedBeforeClose() {
        // Донор к закрытию стал главным окном по заголовку.
        let byTitle = CashRig(at: t0)
        byTitle.start(handoff: true)
        byTitle.now = t0.addingTimeInterval(9)
        byTitle.born()
        byTitle.mainSays("send")
        byTitle.actions.cashoutTick()
        byTitle.windows[1].title = "Claude"
        while !byTitle.queued.isEmpty { byTitle.queued.removeFirst().run() }
        XCTAssertTrue(byTitle.closed.isEmpty)
        XCTAssertEqual(byTitle.warnings, [MenuModel.cashoutDonorMainNotice])

        // …или его рамка — рамка страницы главного окна.
        let byFrame = CashRig(at: t0)
        byFrame.mainFrame = byFrame.donorFrame
        byFrame.start(handoff: true)
        byFrame.now = t0.addingTimeInterval(9)
        byFrame.born()
        byFrame.mainSays("send")
        byFrame.tick()
        XCTAssertTrue(byFrame.closed.isEmpty)
        XCTAssertEqual(byFrame.warnings, [MenuModel.cashoutDonorMainNotice])
    }

    // MARK: - один перенос за раз и метка прогрева с первой миллисекунды (проверка wf93-n2)

    func testSecondHandoffWaitsForFirst() {
        let rig = CashRig(at: t0)
        rig.start(handoff: true)
        var ran = 0
        rig.actions.whenCashoutIdle { ran += 1 }
        XCTAssertEqual(ran, 0, "первый перенос идёт — второй ждёт, работу первого не подменяет")
        XCTAssertEqual(rig.queued.map { $0.delay }, [BlankWindow.pollSeconds])
        rig.now = rig.now.addingTimeInterval(BlankWindow.pollSeconds)
        rig.queued.removeFirst().run()
        XCTAssertEqual(ran, 0)

        // Первый кончился отказом страницы — второй пошёл и сразу забронировал перенос.
        rig.pages = [ChatPage(kind: .popout, chat: nil, title: "Старый чат", store: "ok",
                              cashout: "отказ: протух", at: rig.now)]
        rig.actions.cashoutTick()
        XCTAssertFalse(rig.actions.cashoutPending)
        rig.now = rig.now.addingTimeInterval(BlankWindow.pollSeconds)
        rig.queued.removeFirst().run()
        XCTAssertEqual(ran, 1)
        XCTAssertTrue(rig.actions.cashoutPending, "бронь с выпуска, до работы")
        XCTAssertTrue(rig.actions.newWindowBusy)

        // Третий в щель брони не проскакивает; бронь без работы истекает.
        rig.actions.whenCashoutIdle { ran += 1 }
        XCTAssertEqual(ran, 1)
        rig.now = rig.now.addingTimeInterval(ClaudeActions.cashoutReserveSeconds)
        rig.queued.removeFirst().run()
        XCTAssertEqual(ran, 2)

        // Работа, беглая бронь снята: новая работа первого стирает бронь.
        rig.start(handoff: true)
        XCTAssertTrue(rig.actions.cashoutPending)
    }

    func testSecondHandoffGivesUpAtCeiling() {
        let rig = CashRig(at: t0)
        rig.start(handoff: true)
        var ran = 0
        rig.actions.whenCashoutIdle { ran += 1 }
        while let next = rig.queued.first {
            rig.queued.removeFirst()
            rig.now = rig.now.addingTimeInterval(BlankWindow.pollSeconds)
            next.run()
        }
        XCTAssertEqual(ran, 0)
        XCTAssertEqual(rig.warnings, [MenuModel.cashoutBusyNotice])
        XCTAssertGreaterThanOrEqual(rig.now.timeIntervalSince(t0), ClaudeActions.cashoutWaitSeconds)
        XCTAssertTrue(MenuModel.cashoutBusyNotice.contains("ещё открывает прошлый новый чат"))
    }

    func testChainReleaseMarksNewWindowBusyAtOnce() {
        let rig = CashRig(at: t0)
        XCTAssertFalse(rig.actions.newWindowBusy)
        var busyInside = false
        rig.actions.whenBlankIdle { busyInside = rig.actions.newWindowBusy }
        XCTAssertTrue(busyInside, "метка стоит до первого шага цепочки")
        rig.now = t0.addingTimeInterval(BlankWindow.newWindowQuietSeconds + 1)
        XCTAssertFalse(rig.actions.newWindowBusy)
    }

    // MARK: - «Loading» — заглушка (зеркало страницы wf93-n1)

    func testLoadingTitleIsStub() {
        XCTAssertTrue(ProjectIndex.isStub("Loading"))
        XCTAssertTrue(ProjectIndex.isLoadingTitle(" loading "))
        XCTAssertFalse(ProjectIndex.isLoadingTitle("Code"))
        let old = ChatPage(kind: .popout, chat: "local_6f1bd03f", title: "Loading", store: "ok", at: t0)
        XCTAssertNil(ClaudeActions.cashoutFresh(title: "Loading", before: [1],
                                                windows: [(1, "Claude"), (3, "Loading")]))
    }

    // MARK: - маяк окон доступа у часов

    func testConsentBeaconDefaultsOn() throws {
        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(ConsentBeacon.isEnabled(in: defaults), "нет ключа — включено")
        defaults.set(false, forKey: ConsentBeacon.enabledKey)
        XCTAssertFalse(ConsentBeacon.isEnabled(in: defaults))
        defaults.set(true, forKey: ConsentBeacon.enabledKey)
        XCTAssertTrue(ConsentBeacon.isEnabled(in: defaults))
    }

    // MARK: - карточка status.md: «Ждёт пользователя:» наравне с «Ждёт Элвиса:»

    func testStatusTailAcceptsWaitingForUser() {
        let text = """
        PimpMyClaude
        3 воркфлоу
        1 готово

        2️⃣ Workflow 💭 идёт
        - о чём: пустое окно
        - шаги 1 из 3

        Сейчас: идёт кодинг.
        Ждёт пользователя: нажми «Поставить».
        """
        XCTAssertEqual(StatusFeed.compact(text).components(separatedBy: "\n"), [
            "PimpMyClaude", "3 воркфлоу", "1 готово",
            "Сейчас: идёт кодинг.", "Ждёт пользователя: нажми «Поставить».",
            "2️⃣ Workflow 💭 идёт", "- о чём: пустое окно", "- шаги 1 из 3",
        ])
        XCTAssertTrue(StatusFeed.tailKind("Ждёт пользователя: ответ") != nil)
        XCTAssertTrue(StatusFeed.tailKind("Ждёт Элвиса: буква") != nil)
        XCTAssertTrue(StatusFeed.tailKind("- **Сейчас:** кодинг") != nil, "пункт списка и жирное — как у страницы")
        XCTAssertTrue(StatusFeed.tailKind("* Ждёт пользователя: да") != nil)
        XCTAssertFalse(StatusFeed.tailKind("Ждёт пользователей нет") != nil)
        XCTAssertFalse(StatusFeed.tailKind("- шаги 1 из 3") != nil)
        XCTAssertEqual(StatusFeed.compact(StatusFeed.compact(text)), StatusFeed.compact(text), "идемпотентно")
    }
}
