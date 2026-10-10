import AppKit
import Darwin
import WebKit
import XCTest
@testable import ClaudeAX

private final class QueueDefaults: ThemeDefaults {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

final class WindowSafetyQueueTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let mainFrame = CGRect(x: 50, y: 60, width: 450, height: 600)
    private let rickFrame = CGRect(x: 1200, y: 130, width: 650, height: 770)

    private func temp() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("window-safe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testRequestReaderAcceptsBoundedRegularFilesAndRejectsOtherKinds() throws {
        let box = try temp(), regular = box.appendingPathComponent("regular")
        let bytes = Data(repeating: 65, count: 65_536)
        try bytes.write(to: regular)
        XCTAssertEqual(PimpChannel.readRequest(regular), bytes)
        try Data(repeating: 65, count: 65_537).write(to: regular)
        XCTAssertNil(PimpChannel.readRequest(regular))
        let link = box.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: regular)
        XCTAssertNil(PimpChannel.readRequest(link))
        let fifo = box.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertNil(PimpChannel.readRequest(fifo), "No writer exists: the nonblocking open must return")
        XCTAssertNil(PimpChannel.readRequest(box))
        XCTAssertNil(PimpChannel.readRequest(box.appendingPathComponent("missing")))
    }

    func testExternalBrowserRequiresAnExplicitLinkInEitherDelegate() {
        let web = URL(string: "https://example.test/")!
        XCTAssertTrue(FileView.opensExternally(web, type: .linkActivated))
        for type in [WKNavigationType.other, .formSubmitted, .formResubmitted, .reload, .backForward] {
            XCTAssertFalse(FileView.opensExternally(web, type: type))
        }
        XCTAssertFalse(FileView.opensExternally(URL(fileURLWithPath: "/tmp/a.html"), type: .linkActivated))
        XCTAssertFalse(FileView.opensExternally(URL(string: "javascript:alert(1)")!, type: .linkActivated))
    }

    func testExplicitCenterHubOwnsTheScreenAndSurvivesMissingNeighbours() throws {
        let large = CGRect(x: 0, y: 0, width: 2560, height: 1400)
        let small = CGRect(x: 2560, y: 0, width: 1512, height: 900)
        let windows: [(id: CGWindowID, frame: CGRect)] = [
            (1, CGRect(x: 2700, y: 30, width: 400, height: 600)),
            (2, CGRect(x: 200, y: 30, width: 500, height: 600)),
            (3, CGRect(x: 3200, y: 30, width: 400, height: 600)),
            (4, CGRect(x: 3650, y: 30, width: 400, height: 600))]
        func plan(_ available: [(id: CGWindowID, frame: CGRect)]) -> [PimpMove] {
            ClaudeActions.orderedPlacement(ids: [1, 2, 3, 4], mode: .center, hub: 2, windows: available,
                                           minWidth: 280, gap: 5) { frames in
                XCTAssertEqual(frames, [windows[1].frame])
                return [large, small][Screens.pick(screens: [large, small], for: frames)]
            }
        }
        let placed = plan(windows)
        XCTAssertEqual(placed.count, 4)
        XCTAssertTrue(placed.allSatisfy { large.contains($0.frame) })
        let expected = ArrangeLayout.frames(count: 4, in: large, mode: .center, minCellWidth: 280, gap: 5)
        XCTAssertEqual(placed.first { $0.id == 2 }?.frame,
                       expected[ArrangeLayout.centerHubIndex(count: 4, in: large, minCellWidth: 280, gap: 5)])
        let compact = plan(windows.filter { $0.id != 1 })
        XCTAssertEqual(compact.map { $0.id }.count, 3)
        XCTAssertEqual(compact[ArrangeLayout.centerHubIndex(count: 3, in: large, minCellWidth: 280, gap: 5)].id, 2)
        XCTAssertTrue(plan(windows.filter { $0.id != 2 }).isEmpty)
    }

    func testMainRollbackWaitsForFreshCompleteCensusAndNeverReplaysTransfer() throws {
        for outcome in ["absent", "main", "offspace", "incomplete"] {
            let box = try temp()
            var now = start
            var windows = [PimpWindow(id: 10, title: "Main", chat: "local_old", frame: mainFrame, main: true),
                           PimpWindow(id: 11, title: "Rick", chat: "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f", frame: rickFrame, main: false)]
            var complete = true, answered = false
            var opens: [String] = [], transfers: [String] = []
            var moves: [PimpMove] = []
            let channel = PimpChannel(directory: box, now: { now })
            channel.seats.claudeRunning = { true }
            channel.seats.windows = { windows.filter { $0.id != 99 } }
            channel.seats.restoreWindows = { (windows, complete) }
            channel.seats.demandChats = { _ in answered = false }
            channel.seats.chatsAnswered = { _ in answered }
            channel.seats.close = { id in windows.removeAll { $0.id == id }; return true }
            channel.seats.sendMainChat = { chat, _ in transfers.append(chat) }
            channel.seats.openChat = { chat, _, _ in opens.append(chat) }
            channel.seats.place = { moves += $0 }
            channel.start()
            let request: [String: Any] = ["id": "901-0001", "at": PimpChannel.stampText(now), "action": "main", "from": "", "chat": "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"]
            let requestData = try JSONSerialization.data(withJSONObject: request)
            XCTAssertEqual(try XCTUnwrap(PimpRequest.parse(requestData)).chat, "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f")
            let requestURL = box.appendingPathComponent("901-0001.json")
            try requestData.write(to: requestURL)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: requestURL.path)
            XCTAssertEqual(PimpChannel.readRequest(requestURL), requestData)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: requestURL.path)[.modificationDate] as? Date, now)
            channel.tick() // Close donor.
            XCTAssertTrue(channel.isBusy)
            XCTAssertFalse(windows.contains { $0.id == 11 })
            now += 2; channel.tick() // One main-chat command.
            XCTAssertEqual(transfers, ["local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"])
            now += 16; channel.tick() // Timeout starts fresh rollback observation.
            XCTAssertTrue(opens.isEmpty)
            XCTAssertTrue(channel.isBusy)
            if outcome == "main" { windows[0] = PimpWindow(id: 10, title: "Rick", chat: "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f", frame: mainFrame, main: true) }
            if outcome == "offspace" { windows.append(PimpWindow(id: 99, title: "Rick", chat: "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f", frame: rickFrame, main: false)) }
            complete = outcome != "incomplete"
            answered = true
            now += 2; channel.tick()
            if outcome == "incomplete" { now += 16; channel.tick() }
            if outcome == "absent" {
                XCTAssertTrue(channel.isBusy, "One reopen must be followed by a confirmed full-frame placement")
                windows.append(PimpWindow(id: 100, title: "Rick", chat: "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f",
                    frame: CGRect(x: 0, y: 0, width: 900, height: 700), main: false))
                answered = true; now += 2; channel.tick()
                XCTAssertEqual(moves, [PimpMove(id: 100, frame: rickFrame)])
            } else { XCTAssertTrue(moves.isEmpty) }
            XCTAssertEqual(opens, outcome == "absent" ? ["local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"] : [], outcome)
            XCTAssertFalse(channel.isBusy)
            now += 2; channel.tick()
            XCTAssertEqual(transfers, ["local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"], "Never retry main-chat after a missing ACK")
            XCTAssertEqual(opens.count, outcome == "absent" ? 1 : 0)
        }
    }

    func testArbitraryNamedLayoutRestoresOnlySavedRecordsAndKeepsLegacyGrid() throws {
        let windows = [PimpWindow(id: 10, title: "Main", chat: "local_old", frame: mainFrame, main: true),
                       PimpWindow(id: 11, title: "Rick", chat: "local_rick", frame: rickFrame, main: false)]
        let snapshot = LayoutsStore.snapshot(name: "Rick and main", at: start, mode: .five,
            windows: windows, cells: [], isMain: { _ in false })
        XCTAssertTrue(snapshot.unknown.isEmpty)
        XCTAssertEqual(LayoutsStore.placedCells(snapshot.layout), 2)
        let loaded = try XCTUnwrap(LayoutsStore.parse(Data(LayoutsStore.json([snapshot.layout]).utf8)).first)
        XCTAssertEqual(loaded, snapshot.layout)
        let box = try temp()
        var live = [PimpWindow(id: 10, title: "Main", chat: "local_old", frame: rickFrame, main: true),
                    PimpWindow(id: 99, title: "Unrelated", chat: "local_unrelated", frame: mainFrame, main: false)]
        var moves: [PimpMove] = [], opened: [String] = []
        var now = start
        let channel = PimpChannel(directory: box, now: { now })
        channel.seats.claudeRunning = { true }
        channel.seats.windows = { live }
        channel.seats.restoreWindows = { (live, true) }
        channel.seats.place = { moves += $0 }
        channel.seats.openChat = { chat, _, _ in
            opened.append(chat)
            live.append(PimpWindow(id: 12, title: "Rick", chat: chat, frame: self.mainFrame, main: false))
        }
        XCTAssertTrue(channel.startRestore(loaded, fresh: false))
        now += 2; channel.tick()
        XCTAssertEqual(opened, ["local_rick"])
        XCTAssertFalse(moves.contains { $0.id == 99 })
        XCTAssertTrue(moves.contains(PimpMove(id: 10, frame: mainFrame)))
        XCTAssertTrue(moves.contains(PimpMove(id: 12, frame: rickFrame)))
        let old = Data("{\"layouts\":[{\"name\":\"Old\",\"mode\":\"5\",\"cells\":[{\"chat\":\"main\",\"cell\":0}]}]}".utf8)
        let legacy = try XCTUnwrap(LayoutsStore.parse(old).first)
        XCTAssertNil(legacy.cells[0].frame)
        XCTAssertEqual(legacy.cells[0].cell, 0)
    }

    func testActualModelRequiresMatchingSuccessfulFreshNewWindowRun() throws {
        let actual: [String: Any] = ["commandId": "command-1", "chat": "local_new", "model": " Opus 5.5 ", "effort": "High"]
        let raw: [String: Any] = ["at": start.timeIntervalSince1970 * 1000, "state": "ok", "id": "local_new", "actual": actual]
        var run = try XCTUnwrap(NewWindowRun.parse(raw))
        XCTAssertEqual(run.confirmedActual(commandId: "command-1", since: start - 1, now: start)?.model, "Opus 5.5")
        XCTAssertNil(run.confirmedActual(commandId: "other", since: start - 1, now: start))
        XCTAssertNil(run.confirmedActual(commandId: "command-1", since: start + 1, now: start))
        XCTAssertNil(run.confirmedActual(commandId: "command-1", since: start - 1, now: start + 30))
        run.busy = true
        XCTAssertNil(run.confirmedActual(commandId: "command-1", since: start - 1, now: start))
        run.busy = false; run.state = "error"
        XCTAssertNil(run.confirmedActual(commandId: "command-1", since: start - 1, now: start))
        var bad = actual; bad["chat"] = "local_other"
        run = try XCTUnwrap(NewWindowRun.parse(raw.merging(["actual": bad]) { _, new in new }))
        XCTAssertNil(run.confirmedActual(commandId: "command-1", since: start - 1, now: start))
        bad = actual; bad["model"] = "Opus\nInjected"
        XCTAssertNil(NewWindowRun.actual(bad)?.model)
        bad["commandId"] = String(repeating: "x", count: 65)
        XCTAssertNil(NewWindowRun.actual(bad))
    }
    func testActualNoticeKeepsProbeReasonUntilCorrelatedAckOrTimeout() throws {
        let directory = try temp(), command = directory.appendingPathComponent("command.json")
        var now = start
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
            commands: CommandChannel(path: command, now: { now }, schedule: { _, _ in }),
            themes: [], fonts: [], themeStore: ThemeStore(defaults: QueueDefaults()),
            myThemes: MyThemesStore(url: directory.appendingPathComponent("themes.json")),
            autoPaintStore: AutoPaintStore(defaults: QueueDefaults()),
            liveColorsStore: LiveColorsStore(defaults: QueueDefaults()))
        actions.clock = { now }
        actions.schedule = { _, _ in } // No synthetic keyboard action in a test.
        var notices: [String] = []
        actions.onNotice = { text, _ in notices.append(text) }
        let project = Project(folder: directory, name: "Test", lastFocusedAt: 0)
        actions.newWindow(in: project, on: nil, text: "",
            handoff: NewChatHandoff(model: "Requested model", effort: "Requested effort", stay: false, transfer: false))
        XCTAssertTrue(actions.isAwaitingNewWindowActual)
        XCTAssertFalse(notices.contains { $0.contains("Requested") })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: command)) as? [String: Any])
        let id = try XCTUnwrap(body["id"] as? String)
        now += 1
        var run = NewWindowRun(at: now, step: "back", handoff: "", chat: "local_new", state: "ok", busy: false,
            actual: NewWindowRun.Actual(commandId: "old-command", chat: "local_new", model: "Actual model", effort: "High"))
        actions.newWindowRun = { run }
        actions.noteNewWindowOutcome()
        XCTAssertTrue(actions.isAwaitingNewWindowActual)
        run.actual = NewWindowRun.Actual(commandId: id, chat: "local_new", model: "Actual model", effort: "High")
        actions.noteNewWindowOutcome()
        XCTAssertFalse(actions.isAwaitingNewWindowActual)
        XCTAssertTrue(notices.last?.contains("Actual model") == true)
        now += 10
        actions.newWindow(in: project, on: nil, text: "")
        XCTAssertTrue(actions.isAwaitingNewWindowActual)
        now += PimpChannel.newWindowSeconds + 1
        actions.noteNewWindowOutcome()
        XCTAssertFalse(actions.isAwaitingNewWindowActual)
    }

}
