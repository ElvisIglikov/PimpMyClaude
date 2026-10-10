import CoreGraphics
import XCTest
@testable import ClaudeAX

final class NamedRestorePreservationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let screen = ScreenSpec(name: "Mac", frame: CGRect(x: 0, y: 0, width: 2000, height: 1200))
    private var original: [SnapshotWindow] {
        [SnapshotWindow(chat: "main", folder: "", title: "Main", frame: CGRect(x: 20, y: 30, width: 400, height: 700), screen: "Mac"),
         SnapshotWindow(chat: "local_rick", folder: "", title: "Rick", frame: CGRect(x: 450, y: 30, width: 400, height: 700), screen: "Mac")]
    }
    private func box() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testNamedPendingSurvivesRecreationAndExplicitOriginalRestoreReplacesExpectation() throws {
        let directory = try box()
        let snapshots = WindowSnapshotStore(url: directory.appendingPathComponent("windows.json"))
        let screens = ScreenLayoutStore(url: directory.appendingPathComponent("screens.json"))
        let key = ScreenLayoutKeeper.key([screen])
        XCTAssertTrue(snapshots.save(WindowSnapshot(at: now, claude: "", windows: original)))
        XCTAssertTrue(screens.save([ScreenLayout(key: key, at: now, windows: original, chatGPT: nil)]))
        var live = original
        let makeWindows: () -> WindowSnapshotKeeper = {
            let keeper = WindowSnapshotKeeper(store: snapshots)
            keeper.claude = { (pid: 1, launch: self.now - 100, version: "") }
            keeper.observation = { SnapshotObservation(windows: live, complete: true) }
            return keeper
        }
        let makeScreens: () -> ScreenLayoutKeeper = {
            let keeper = ScreenLayoutKeeper(store: screens)
            keeper.screens = { [self.screen] }
            keeper.observation = { SnapshotObservation(windows: live, complete: true) }
            return keeper
        }
        var windows = makeWindows(), displays = makeScreens()
        windows.tick(at: now + 1); displays.tick(at: now + 1)
        let target = original.map { SnapshotWindow(chat: $0.chat, folder: $0.folder, title: $0.title,
            frame: $0.frame.offsetBy(dx: 100, dy: 50), screen: $0.screen) }
        XCTAssertTrue(windows.prepareNamedRestore(expected: target))
        XCTAssertTrue(displays.prepareNamedRestore(expected: target, at: now + 2))
        live = [target[0]] // Complete inventory, but the saved Rick target never arrived.
        windows = makeWindows(); displays = makeScreens()
        for offset in [4000.0, 4010, 4020] { windows.tick(at: now + offset); displays.tick(at: now + offset) }
        XCTAssertEqual(snapshots.load()?.windows, original)
        XCTAssertEqual(snapshots.load()?.restoreExpected, target)
        XCTAssertEqual(screens.load().first?.windows, original)
        XCTAssertEqual(screens.load().first?.restoreExpected, target)
        XCTAssertFalse(windows.saveNow(at: now + 4021))
        // A new named attempt can change its target, but never the protected original.
        XCTAssertTrue(windows.prepareNamedRestore(expected: []))
        XCTAssertTrue(displays.prepareNamedRestore(expected: [], at: now + 4022))
        live = original
        for offset in [4030.0, 4040] { windows.tick(at: now + offset); displays.tick(at: now + offset) }
        XCTAssertEqual(snapshots.load()?.restoreExpected, [])
        XCTAssertEqual(screens.load().first?.restoreExpected, [])
        XCTAssertTrue(snapshots.load()?.restorePending == true)
        XCTAssertTrue(screens.load().first?.restorePending == true)
        // An explicit old-baseline restore must replace that otherwise-unreachable target.
        windows.startRestore = { snapshot in XCTAssertEqual(snapshot.windows, self.original); return true }
        XCTAssertTrue(windows.restoreNow())
        XCTAssertNotNil(displays.restoreNow(at: now + 4041))
        for offset in [4050.0, 4060, 4070] { windows.tick(at: now + offset); displays.tick(at: now + offset) }
        XCTAssertFalse(snapshots.load()?.restorePending ?? true)
        XCTAssertFalse(screens.load().first?.restorePending ?? true)
        XCTAssertEqual(snapshots.load()?.windows, original)
    }

    func testSuccessfulNamedTargetKeepsExtrasAndClearsOnlyAfterStableReadback() throws {
        let directory = try box()
        let store = WindowSnapshotStore(url: directory.appendingPathComponent("windows.json"))
        XCTAssertTrue(store.save(WindowSnapshot(at: now, claude: "", windows: original)))
        var live = original
        let keeper = WindowSnapshotKeeper(store: store)
        keeper.claude = { (pid: 1, launch: self.now - 100, version: "") }
        keeper.observation = { SnapshotObservation(windows: live, complete: true) }
        keeper.tick(at: now + 1)
        let moved = SnapshotWindow(chat: "main", folder: "", title: "Main", frame: original[0].frame.offsetBy(dx: 40, dy: 30), screen: "Mac")
        let target = [moved, original[1]]
        XCTAssertTrue(keeper.prepareNamedRestore(expected: target))
        live = target
        keeper.tick(at: now + 10)
        XCTAssertTrue(store.load()?.restorePending == true)
        keeper.tick(at: now + 20)
        XCTAssertFalse(store.load()?.restorePending ?? true)
        XCTAssertEqual(store.load()?.windows, target)
    }

    func testNamedRestoreRefusesEffectsIfEitherBaselineCannotBeProtected() throws {
        let channel = PimpChannel(directory: try box())
        let live = [PimpWindow(id: 1, title: "Main", frame: original[0].frame, main: true)]
        channel.seats.claudeRunning = { true }
        channel.seats.restoreWindows = { (live, true) }
        var protected = false, effects = 0
        channel.seats.prepareNamedRestore = { _ in protected = true; return false }
        channel.seats.place = { _ in effects += 1 }
        channel.seats.openChat = { _, _, _ in effects += 1 }
        let layout = WindowLayout(name: "Only main", at: now, mode: .five,
            cells: [LayoutCell(folder: "", chat: "main", title: "Main", cell: nil, frame: original[0].frame)])
        XCTAssertFalse(channel.startRestore(layout, fresh: false))
        XCTAssertTrue(protected)
        XCTAssertEqual(effects, 0)
        XCTAssertFalse(channel.isRestoring)
    }
    func testBusyManualRestoreCannotReplaceEitherNamedExpectation() throws {
        let directory = try box()
        let windowsStore = WindowSnapshotStore(url: directory.appendingPathComponent("windows.json"))
        let screenStore = ScreenLayoutStore(url: directory.appendingPathComponent("screens.json"))
        let key = ScreenLayoutKeeper.key([screen])
        XCTAssertTrue(windowsStore.save(WindowSnapshot(at: now, claude: "", windows: original)))
        XCTAssertTrue(screenStore.save([ScreenLayout(key: key, at: now, windows: original, chatGPT: nil)]))
        let windows = WindowSnapshotKeeper(store: windowsStore)
        let displays = ScreenLayoutKeeper(store: screenStore)
        windows.claude = { (pid: 1, launch: self.now - 100, version: "") }
        windows.observation = { SnapshotObservation(windows: self.original, complete: true) }
        displays.screens = { [self.screen] }
        displays.observation = { SnapshotObservation(windows: self.original, complete: true) }
        windows.tick(at: now + 1)
        XCTAssertTrue(windows.prepareNamedRestore(expected: []))
        XCTAssertTrue(displays.prepareNamedRestore(expected: [], at: now + 1))
        var hooks = 0, effects = 0
        windows.prepareOtherRestore = { expected in
            hooks += 1
            return displays.prepareNamedRestore(expected: expected, at: self.now + 2)
        }
        windows.startRestore = { _ in effects += 1; return true }
        windows.busy = { true }
        XCTAssertFalse(windows.restoreNow())
        XCTAssertEqual(hooks, 0)
        XCTAssertEqual(effects, 0)
        XCTAssertEqual(windowsStore.load()?.restoreExpected, [])
        XCTAssertEqual(screenStore.load().first?.restoreExpected, [])
    }

}
