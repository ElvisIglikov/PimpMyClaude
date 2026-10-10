import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Находки судьи WF111 (батч S): спрятанные окна Electron и полнота переписи, защита после
/// возврата с выходом, свежесть опознания попапов, повтор действия по клику и старый лоадер.
final class JudgeWF111SwiftTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let left = CGRect(x: 0, y: 30, width: 400, height: 700)
    private let right = CGRect(x: 450, y: 30, width: 400, height: 700)

    private func temp() throws -> URL {
        let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: box) }
        return box
    }

    private func window(_ chat: String, _ frame: CGRect) -> SnapshotWindow {
        SnapshotWindow(chat: chat, folder: "", title: chat, frame: frame, screen: "Mac")
    }

    // MARK: - блокер 1: спрятанные окна Electron

    /// Живьём у Элвиса: в AX один попап Rick, в Quartz ещё закрытое главное 508×655 и спрятанное
    /// 854×720 — не на экране. Перепись полная, снимок К5 и «Запомни раскладку» пишутся.
    func testHiddenElectronWindowsKeepCensusCompleteAndSnapshotAndLayoutSaveWrite() throws {
        let rick = CGRect(x: 900, y: 40, width: 420, height: 820)
        let native = [WindowIdentity.Native(title: "Второй сезон Rick", frame: rick)]
        let quartz = [ClaudeWindowFrame(id: 333, frame: rick),
                      ClaudeWindowFrame(id: 97, frame: CGRect(x: 200, y: 120, width: 508, height: 655), onScreen: false),
                      ClaudeWindowFrame(id: 448, frame: CGRect(x: 300, y: 90, width: 854, height: 720), onScreen: false)]
        let census = WindowCensus.pair(native: native, quartz: quartz)
        XCTAssertTrue(census.complete)
        XCTAssertEqual(census.pairs.map { $0.id }, [333])
        // Окно на экране без AX-пары — перепись по-прежнему неполная.
        let stray = quartz + [ClaudeWindowFrame(id: 500, frame: left)]
        XCTAssertFalse(WindowCensus.pair(native: native, quartz: stray).complete)

        let windows = [PimpWindow(id: 333, title: "Второй сезон Rick", chat: "local_rick", frame: rick, main: false)]
        let observed = WindowSnapshotStore.observe(from: windows, complete: census.complete,
                                                   isMain: { _ in false }, screen: { _ in "Mac" })
        XCTAssertTrue(observed.complete, "главного окна нет — это полный замер, а не неизвестный")

        let box = try temp()
        let store = WindowSnapshotStore(url: box.appendingPathComponent("windows-snapshot.json"))
        let keeper = WindowSnapshotKeeper(store: store)
        keeper.claude = { (pid: 1, launch: self.now - 4000, version: "") }
        keeper.observation = { observed }
        keeper.tick(at: now)
        keeper.tick(at: now + 4)
        XCTAssertEqual(store.load()?.windows.map { $0.chat }, ["local_rick"])

        // Часы канала — в прошлом: уборка стирает файлы запросов старше часа по mtime.
        let directory = box.appendingPathComponent("pimp", isDirectory: true)
        let past = try XCTUnwrap(PimpChannel.date("2026-09-07T11:20:00Z"))
        let channel = PimpChannel(directory: directory, now: { past })
        channel.seats.claudeRunning = { true }
        channel.seats.restoreWindows = { (windows, observed.complete) }
        channel.seats.cells = { _, _ in [rick] }
        var saved: [WindowLayout] = []
        channel.seats.saveLayout = { saved.append($0); return true }
        channel.start()
        let request = "{\"id\":\"111-0001\",\"at\":\"\(PimpChannel.stampText(past))\",\"action\":\"layout-save\","
            + "\"from\":\"\",\"name\":\"Утро\"}"
        try Data(request.utf8).write(to: directory.appendingPathComponent("111-0001.json"))
        channel.tick()
        XCTAssertEqual(saved.first?.cells.map { $0.chat }, ["local_rick"])
    }

    // MARK: - блокер 2: защита после возврата не вечная

    /// К5: чат снимка заархивирован и не открылся — после возврата его не ждём, снимок пишется.
    func testSnapshotDropsMissingChatAfterRestoreAndWritesNextStableSample() throws {
        let store = WindowSnapshotStore(url: try temp().appendingPathComponent("snapshot.json"))
        let main = window("main", left), chat = window("local_c", right)
        let archived = window("local_gone", right.offsetBy(dx: 450, dy: 0))
        XCTAssertTrue(store.save(WindowSnapshot(at: now - 100, claude: "", windows: [main, chat, archived])))
        var restoring = true
        let keeper = WindowSnapshotKeeper(store: store)
        keeper.claude = { (pid: 1, launch: self.now, version: "") }
        keeper.observation = { SnapshotObservation(windows: [main, chat], complete: true) }
        keeper.pageReady = { _ in true }
        keeper.startRestore = { _ in true }
        keeper.isRestoring = { restoring }
        keeper.tick(at: now + 1)
        XCTAssertEqual(keeper.phase, .restoring)
        XCTAssertTrue(store.load()?.restorePending == true)
        restoring = false
        for offset in [10.0, 14, 18] { keeper.tick(at: now + offset) }
        XCTAssertFalse(store.load()?.restorePending ?? true)
        XCTAssertEqual(store.load()?.windows, [main, chat])
    }

    /// К5: окно после возврата сдвинули — защита держится `releaseSeconds`, потом пишется замер.
    func testSnapshotProtectionExpiresAfterRestoreWhenWindowsNeverMatch() throws {
        let store = WindowSnapshotStore(url: try temp().appendingPathComponent("snapshot.json"))
        let main = window("main", left), chat = window("local_c", right)
        XCTAssertTrue(store.save(WindowSnapshot(at: now - 100, claude: "", windows: [main, chat])))
        let moved = [window("main", left.offsetBy(dx: 20, dy: 0)), chat]
        var restoring = true
        let keeper = WindowSnapshotKeeper(store: store)
        keeper.claude = { (pid: 1, launch: self.now, version: "") }
        keeper.observation = { SnapshotObservation(windows: moved, complete: true) }
        keeper.pageReady = { _ in true }
        keeper.startRestore = { _ in true }
        keeper.isRestoring = { restoring }
        keeper.tick(at: now + 1)
        restoring = false
        for offset in [10.0, 14, 18, 100] { keeper.tick(at: now + offset) }
        XCTAssertTrue(store.load()?.restorePending == true)
        XCTAssertEqual(store.load()?.windows, [main, chat])
        keeper.tick(at: now + 14 + WindowSnapshotKeeper.releaseSeconds)
        XCTAssertFalse(store.load()?.restorePending ?? true)
        XCTAssertEqual(store.load()?.windows, moved)
    }

    private func screenRig(_ store: ScreenLayoutStore, observed: [SnapshotWindow]) -> (ScreenLayoutKeeper, () -> Void) {
        let small = ScreenSpec(name: "Small", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let big = ScreenSpec(name: "Big", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        var specs = [small]
        let keeper = ScreenLayoutKeeper(store: store)
        keeper.screens = { specs }
        keeper.observation = { SnapshotObservation(windows: observed, complete: true) }
        keeper.live = { observed.map { PimpWindow(id: 1, title: $0.title, frame: $0.frame, main: $0.chat == "main") } }
        keeper.chatGPT = { nil }
        return (keeper, { specs = [small, big] })
    }

    /// Мониторы: в записи набора закрытый чат и закрытый ChatGPT — запись всё равно обновляется.
    func testScreenRecordWithClosedChatAndChatGPTUpdatesAfterRestore() throws {
        let store = ScreenLayoutStore(url: try temp().appendingPathComponent("screens.json"))
        let main = window("main", left)
        let bigKey = ScreenLayoutKeeper.key([ScreenSpec(name: "Small", frame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
                                             ScreenSpec(name: "Big", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))])
        XCTAssertTrue(store.save([ScreenLayout(key: bigKey, at: now, windows: [main, window("local_closed", right)],
                                               chatGPT: CGRect(x: 1500, y: 30, width: 400, height: 700))]))
        let (keeper, plug) = screenRig(store, observed: [main])
        keeper.tick(at: now)
        plug()
        keeper.tick(at: now + 1)
        XCTAssertTrue(store.load().first?.restorePending == true)
        for offset in [4.0, 9, 14, 24] { keeper.tick(at: now + offset) }
        XCTAssertFalse(store.load().first?.restorePending ?? true)
        XCTAssertEqual(store.load().first?.windows, [main])
        XCTAssertNil(store.load().first?.chatGPT)
    }

    /// Мониторы: окно после возврата так и не встало на место — через `releaseSeconds` запись пишется.
    func testScreenProtectionExpiresAfterRestoreWhenWindowsNeverMatch() throws {
        let store = ScreenLayoutStore(url: try temp().appendingPathComponent("screens.json"))
        let main = window("main", left)
        let bigKey = ScreenLayoutKeeper.key([ScreenSpec(name: "Small", frame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
                                             ScreenSpec(name: "Big", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))])
        XCTAssertTrue(store.save([ScreenLayout(key: bigKey, at: now, windows: [main], chatGPT: nil)]))
        let moved = window("main", left.offsetBy(dx: 20, dy: 0))
        let (keeper, plug) = screenRig(store, observed: [moved])
        keeper.tick(at: now)
        plug()
        for offset in stride(from: 1.0, through: 101, by: 10) { keeper.tick(at: now + offset) }
        XCTAssertTrue(store.load().first?.restorePending == true)
        for offset in stride(from: 111.0, through: 181, by: 10) { keeper.tick(at: now + offset) }
        XCTAssertFalse(store.load().first?.restorePending ?? true)
        XCTAssertEqual(store.load().first?.windows, [moved])
    }

    // MARK: - серьёзное 1: свежесть опознания и клик по неопознанному окну

    func testPopoutIdentityLivesWhileMapIsFreshButMainStillNeedsRecentAnswer() {
        let native = [WindowIdentity.Native(title: "Main", frame: left, id: 101),
                      WindowIdentity.Native(title: "Rick", frame: right, id: 102)]
        let pages = [ChatPage(kind: .main, chat: "local_m", title: "Main", path: "/epitaxy/local_m", store: "ok",
                              frame: left, windowId: 101, at: now),
                     ChatPage(kind: .popout, chat: "local_rick", title: "Rick", store: "ok",
                              frame: right, windowId: 102, at: now)]
        let later = now + ChatProbe.askInterval + 10
        XCTAssertEqual(WindowIdentity.resolveNative(title: "Rick", frame: right, pages: pages, nativeWindows: native,
                                                    at: later).page?.chat, "local_rick")
        XCTAssertNil(WindowIdentity.resolveNative(title: "Main", frame: left, pages: pages, nativeWindows: native,
                                                  at: later).page)
        // Окна нет в текущей переписи — ответ страницы ему не достаётся.
        XCTAssertNil(WindowIdentity.resolveNative(id: 102, title: "Rick", frame: right, pages: pages,
                                                  nativeWindows: [native[0]], at: later).page)
    }

    func testClickOnUnknownWindowDemandsPagesRetriesAndSpeaksInsteadOfSilence() throws {
        let commands = CommandChannel(path: try temp().appendingPathComponent("command.json"))
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(), commands: commands, themes: [], fonts: [])
        let rick = ChatPage(kind: .popout, chat: "local_rick", title: "Rick", store: "ok", windowId: 102, at: now)
        var known = false
        actions.windowIdentity = { _, _ in known ? .page(rick) : .unknown }
        var queued: [() -> Void] = []
        actions.schedule = { _, block in queued.append(block) }
        var demands = 0, runs = 0
        var notices: [String] = []
        actions.demandPages = { demands += 1 }
        actions.onNotice = { text, _ in notices.append(text) }

        actions.whenIdentified(title: "Rick", frame: right) { runs += 1 }
        XCTAssertEqual(demands, 1)
        XCTAssertEqual(runs, 0)
        known = true
        queued.removeFirst()()
        XCTAssertEqual(runs, 1, "круг ответил — действие повторено")
        XCTAssertTrue(notices.isEmpty)

        known = false
        actions.whenIdentified(title: "Rick", frame: right) { runs += 1 }
        while !queued.isEmpty { queued.removeFirst()() }
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(demands, 2, "страницы спрошены один раз на клик")
        XCTAssertEqual(notices, [MenuModel.windowUnknownNotice])

        actions.pagesNeedRepatch = { true }
        actions.whenIdentified(title: "Rick", frame: right) { runs += 1 }
        XCTAssertTrue(queued.isEmpty)
        XCTAssertEqual(notices.last, MenuModel.oldLoaderNotice)
        XCTAssertEqual(runs, 1, "fail closed: старому лоадеру не верим")
    }

    func testSendAsksPagesOnceWhenWindowChatIsUnknownAndRetriesAfterAnswer() throws {
        let directory = try temp()
        let past = try XCTUnwrap(PimpChannel.date("2026-09-07T11:20:00Z"))
        let channel = PimpChannel(directory: directory, now: { past })
        let rick = "local_5265171a-0ab8-4472-b4e5-40604a36ef6e"
        var windows = [PimpWindow(id: 102, title: "Rick", frame: right)]
        var answered = false, demanded = 0
        var sent: [String] = []
        channel.seats.claudeRunning = { true }
        channel.seats.windows = { windows }
        channel.seats.demandChats = { _ in demanded += 1 }
        channel.seats.chatsAnswered = { _ in answered }
        channel.seats.sendText = { chat, _, _ in sent.append(chat) }
        channel.start()
        let request = "{\"id\":\"111-0002\",\"at\":\"\(PimpChannel.stampText(past))\",\"action\":\"send\","
            + "\"from\":\"\",\"chat\":\"\(rick)\",\"text\":\"привет\"}"
        try Data(request.utf8).write(to: directory.appendingPathComponent("111-0002.json"))
        channel.tick()
        channel.tick()
        XCTAssertEqual(demanded, 1)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("111-0002.result.json").path),
                       "не window-missing, пока круг страниц не ответил")
        windows = [PimpWindow(id: 102, title: "Rick", chat: rick, frame: right)]
        answered = true
        channel.tick()
        XCTAssertEqual(sent, [rick])
    }

    // MARK: - серьёзное 2: старый лоадер

    func testOldLoaderAnswersFailClosedAndPanelAsksForRepatch() throws {
        var clock = now
        var script: String?, result: Data?
        var writes = 0, version = 0
        let files = ChatProbeFiles(scriptInfo: { script == nil ? nil : ("\(writes)", clock) },
                                   readScript: { script },
                                   writeScript: { script = $0; writes += 1; return true },
                                   resultInfo: { result == nil ? nil : "\(version)" },
                                   readResult: { result })
        let probe = ChatProbe(files: files, now: { clock })
        probe.tick(windowTitles: ["Rick"], indexRevision: 1)
        let nonce = try XCTUnwrap(script.flatMap(ChatProbe.markNonce))
        func answer(source: [String: Any]?) {
            var entry: [String: Any] = ["id": 1, "url": "about:blank",
                                        "result": ["v": 1, "nonce": nonce, "kind": "popout", "self": "local_rick",
                                                   "title": "Rick", "store": "ok"]]
            if let source = source { entry["source"] = source }
            result = try? JSONSerialization.data(withJSONObject: ["results": [entry]])
            version += 1
        }
        answer(source: nil)
        clock += 2
        probe.tick(windowTitles: ["Rick"], indexRevision: 1)
        XCTAssertTrue(probe.pages.isEmpty, "fail closed: ответ без печати v8 не берём")
        XCTAssertTrue(probe.signals.needsRepatch)
        answer(source: ProbeSourceFixture.metadata(url: "about:blank"))
        clock += 2
        probe.tick(windowTitles: ["Rick"], indexRevision: 1)
        XCTAssertEqual(probe.pages.map { $0.chat }, ["local_rick"])
        XCTAssertFalse(probe.signals.needsRepatch)

        let installed = StatusIcon.Patch.installed(version: "1.3", loader: 8)
        XCTAssertEqual(PimpPanelText.patch(installed, needsRepatch: false), installed)
        let lost = PimpPanelText.patch(installed, needsRepatch: true)
        XCTAssertEqual(lost, .lost(version: "1.3", reason: PimpPanelText.oldLoaderReason))
        let card = try XCTUnwrap(PimpPanelText.patchCard(lost))
        XCTAssertEqual(card.button, "Вернуть патч")
        XCTAssertTrue(card.title.contains("Окна не опознаются"))
        XCTAssertTrue(card.title.contains("старый лоадер"))
        XCTAssertEqual(PimpPanelText.patch(.notInstalled(version: "1.3"), needsRepatch: true), .notInstalled(version: "1.3"))
    }
}
