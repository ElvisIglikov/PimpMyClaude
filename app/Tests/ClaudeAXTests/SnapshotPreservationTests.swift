import CoreGraphics
import XCTest
@testable import ClaudeAX

final class SnapshotPreservationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let frame = CGRect(x: 0, y: 30, width: 400, height: 700)
    private func temp() throws -> URL {
        let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: box) }
        return box
    }
    private var full: [SnapshotWindow] {
        [SnapshotWindow(chat: "main", folder: "", title: "Main", frame: frame, screen: "Mac"),
         SnapshotWindow(chat: "local_c", folder: "", title: "Chat", frame: frame.offsetBy(dx: 450, dy: 0), screen: "Mac")]
    }

    func testIncompleteRestoreSurvivesGiveUpTimeAndRecreatedKeeperThenAllowsAnOrdinaryClose() throws {
        let store = WindowSnapshotStore(url: try temp().appendingPathComponent("snapshot.json"))
        XCTAssertTrue(store.save(WindowSnapshot(at: now.addingTimeInterval(-100), claude: "", windows: full)))
        var actual = [full[0]]
        let make: () -> WindowSnapshotKeeper = {
            let keeper = WindowSnapshotKeeper(store: store)
            keeper.claude = { (pid: 1, launch: self.now, version: "new") }
            keeper.observation = { SnapshotObservation(windows: actual, complete: true) }
            return keeper
        }
        var keeper = make()
        // The process is already more than thirty minutes old: no automatic retry,
        // but its incomplete state still cannot replace the pre-launch file.
        keeper.tick(at: now.addingTimeInterval(3600))
        keeper.tick(at: now.addingTimeInterval(3604))
        XCTAssertEqual(store.load()?.windows, full)
        XCTAssertFalse(keeper.saveNow(at: now.addingTimeInterval(3605)))
        keeper = make()
        keeper.tick(at: now.addingTimeInterval(4000))
        keeper.tick(at: now.addingTimeInterval(4004))
        XCTAssertEqual(store.load()?.windows, full)
        // All identities alone are insufficient when AX placement failed.
        actual = full.map { SnapshotWindow(chat: $0.chat, folder: $0.folder, title: $0.title,
                                          frame: $0.frame.offsetBy(dx: 20, dy: 0), screen: $0.screen) }
        keeper.tick(at: now.addingTimeInterval(4010))
        keeper.tick(at: now.addingTimeInterval(4014))
        XCTAssertEqual(store.load()?.windows, full)
        actual = full
        keeper.tick(at: now.addingTimeInterval(4020))
        keeper.tick(at: now.addingTimeInterval(4024))
        XCTAssertEqual(store.load()?.at, now.addingTimeInterval(4024))
        actual = [full[0]] // A later complete observation of an ordinary close is allowed.
        keeper.tick(at: now.addingTimeInterval(4030))
        keeper.tick(at: now.addingTimeInterval(4034))
        XCTAssertEqual(store.load()?.windows, actual)
    }

    func testBusyAndIncompleteIntervalsResetStableSampleAndUpdaterCannotBypassThem() throws {
        let store = WindowSnapshotStore(url: try temp().appendingPathComponent("snapshot.json"))
        let keeper = WindowSnapshotKeeper(store: store)
        var busy = false, complete = true
        keeper.claude = { (pid: 1, launch: self.now.addingTimeInterval(-4000), version: "") }
        keeper.observation = { SnapshotObservation(windows: self.full, complete: complete) }
        keeper.busy = { busy }
        keeper.tick(at: now)
        busy = true
        keeper.tick(at: now.addingTimeInterval(1))
        XCTAssertFalse(keeper.saveNow(at: now.addingTimeInterval(1)))
        busy = false
        keeper.tick(at: now.addingTimeInterval(4))
        XCTAssertNil(store.load())
        complete = false
        keeper.tick(at: now.addingTimeInterval(5))
        XCTAssertFalse(keeper.saveNow(at: now.addingTimeInterval(5)))
        complete = true
        keeper.tick(at: now.addingTimeInterval(8))
        XCTAssertNil(store.load())
        keeper.tick(at: now.addingTimeInterval(12))
        XCTAssertEqual(store.load()?.windows, full)
    }

    func testManualSameLaunchRestorePersistsPendingBeforeEffectsAndAcrossRecreation() throws {
        let store = WindowSnapshotStore(url: try temp().appendingPathComponent("snapshot.json"))
        XCTAssertTrue(store.save(WindowSnapshot(at: now, claude: "", windows: full)))
        var actual = full
        let make: () -> WindowSnapshotKeeper = {
            let keeper = WindowSnapshotKeeper(store: store)
            keeper.claude = { (pid: 1, launch: self.now.addingTimeInterval(-100), version: "") }
            keeper.observation = { SnapshotObservation(windows: actual, complete: true) }
            return keeper
        }
        var keeper = make()
        keeper.tick(at: now.addingTimeInterval(1))
        keeper.startRestore = { _ in
            XCTAssertTrue(store.load()?.restorePending == true)
            return true
        }
        XCTAssertTrue(keeper.restoreNow())
        actual = [full[0]]
        keeper = make()
        keeper.tick(at: now.addingTimeInterval(4000))
        keeper.tick(at: now.addingTimeInterval(4004))
        XCTAssertEqual(store.load()?.windows, full)
        XCTAssertTrue(store.load()?.restorePending == true)
        XCTAssertFalse(keeper.saveNow(at: now.addingTimeInterval(4005)))
        actual = full
        keeper.tick(at: now.addingTimeInterval(4010))
        keeper.tick(at: now.addingTimeInterval(4014))
        XCTAssertFalse(store.load()?.restorePending ?? true)
    }

    func testFailedPendingWritePreventsRestoreEffects() throws {
        let box = try temp()
        let directory = box.appendingPathComponent("storage")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WindowSnapshotStore(url: directory.appendingPathComponent("snapshot.json"))
        XCTAssertTrue(store.save(WindowSnapshot(at: now.addingTimeInterval(-100), claude: "", windows: full)))
        let keeper = WindowSnapshotKeeper(store: store)
        keeper.claude = { (pid: 1, launch: self.now, version: "") }
        keeper.tick(at: now)
        try FileManager.default.removeItem(at: directory)
        try Data("cannot be a directory".utf8).write(to: directory)
        var effects = 0
        keeper.startRestore = { _ in effects += 1; return true }
        XCTAssertFalse(keeper.restoreNow())
        XCTAssertEqual(effects, 0)
    }

    func testScreenPendingSurvivesBusyGiveUpAndRecreationUntilFramesAreRestored() throws {
        let store = ScreenLayoutStore(url: try temp().appendingPathComponent("screens.json"))
        let small = ScreenSpec(name: "Small", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let big = ScreenSpec(name: "Big", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        let key = ScreenLayoutKeeper.key([small, big])
        XCTAssertTrue(store.save([ScreenLayout(key: key, at: now, windows: full, chatGPT: nil)]))
        var specs = [small]
        var actual = [full[0]]
        var busy = true
        let make: () -> ScreenLayoutKeeper = {
            let keeper = ScreenLayoutKeeper(store: store)
            keeper.screens = { specs }
            keeper.observation = { SnapshotObservation(windows: actual, complete: true) }
            keeper.busy = { busy }
            return keeper
        }
        var keeper = make()
        keeper.tick(at: now)
        specs = [small, big]
        keeper.tick(at: now.addingTimeInterval(1))
        XCTAssertTrue(store.load().first?.restorePending == true)
        keeper.tick(at: now.addingTimeInterval(70))
        busy = false
        keeper.tick(at: now.addingTimeInterval(4000))
        keeper.tick(at: now.addingTimeInterval(4010))
        XCTAssertEqual(store.load().first?.windows, full)
        keeper = make()
        keeper.tick(at: now.addingTimeInterval(5000))
        keeper.tick(at: now.addingTimeInterval(5010))
        keeper.tick(at: now.addingTimeInterval(5020))
        XCTAssertEqual(store.load().first?.windows, full)
        XCTAssertTrue(store.load().first?.restorePending == true)
        actual = full
        keeper.tick(at: now.addingTimeInterval(5030))
        keeper.tick(at: now.addingTimeInterval(5040))
        XCTAssertFalse(store.load().first?.restorePending ?? true)
        actual = [full[0]]
        keeper.tick(at: now.addingTimeInterval(5050))
        keeper.tick(at: now.addingTimeInterval(5060))
        XCTAssertEqual(store.load().first?.windows, actual)
    }

    func testScreenFailedPendingWritePreventsEffects() throws {
        let box = try temp()
        let directory = box.appendingPathComponent("storage")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ScreenLayoutStore(url: directory.appendingPathComponent("screens.json"))
        let screen = ScreenSpec(name: "Mac", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertTrue(store.save([ScreenLayout(key: ScreenLayoutKeeper.key([screen]), at: now, windows: full, chatGPT: nil)]))
        let keeper = ScreenLayoutKeeper(store: store)
        keeper.screens = { [screen] }
        try FileManager.default.removeItem(at: directory)
        try Data("cannot be a directory".utf8).write(to: directory)
        var effects = 0
        keeper.apply = { _, _ in effects += 1 }
        XCTAssertNil(keeper.restoreNow(at: now))
        XCTAssertEqual(effects, 0)
    }

    func testScreenRestoreWritesPendingBeforeApplyAndBusySampleDoesNotWrite() throws {
        let store = ScreenLayoutStore(url: try temp().appendingPathComponent("screens.json"))
        let screen = ScreenSpec(name: "Mac", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let layout = ScreenLayout(key: ScreenLayoutKeeper.key([screen]), at: now, windows: full, chatGPT: nil)
        XCTAssertTrue(store.save([layout]))
        let keeper = ScreenLayoutKeeper(store: store)
        keeper.screens = { [screen] }
        keeper.live = { [PimpWindow(id: 1, title: "Main", frame: self.frame.offsetBy(dx: 20, dy: 0), main: true)] }
        var effects = 0
        keeper.apply = { _, _ in
            XCTAssertTrue(store.load().first?.restorePending == true)
            effects += 1
        }
        XCTAssertNotNil(keeper.restoreNow(at: now))
        XCTAssertEqual(effects, 1)
        keeper.busy = { true }
        keeper.observation = { SnapshotObservation(windows: [self.full[0]], complete: true) }
        for offset in [0.0, 10, 20, 4000] { keeper.tick(at: now.addingTimeInterval(offset)) }
        XCTAssertEqual(store.load().first?.windows, full)
    }
}
