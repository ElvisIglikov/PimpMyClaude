import CoreGraphics
import XCTest
@testable import ClaudeAX

final class WindowConfirmationTests: XCTestCase {
    func testQuietRestoreConfirmsAcrossPageTTLAndTenSecondScreenSamplesThenStopsPolling() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let frame = CGRect(x: 20, y: 40, width: 400, height: 700)
        let live = [PimpWindow(id: 10, title: "Main", chat: "local_main", frame: frame, main: true),
                    PimpWindow(id: 11, title: "Rick", chat: "local_rick", frame: frame.offsetBy(dx: 450, dy: 0), main: false)]
        let native = live.map { WindowIdentity.Native(title: $0.title, frame: $0.frame, id: $0.id) }
        let desired = live.map { PimpMove(id: $0.id, frame: $0.frame) }
        let screen = ScreenSpec(name: "Mac", frame: CGRect(x: 0, y: 0, width: 2000, height: 1200))
        let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: box) }
        let store = ScreenLayoutStore(url: box.appendingPathComponent("screens.json"))
        let saved = WindowSnapshotStore.windows(from: live, isMain: { _ in false }, screen: { _ in "Mac" })
        XCTAssertTrue(store.save([ScreenLayout(key: ScreenLayoutKeeper.key([screen]), at: start, windows: saved, chatGPT: nil)]))
        var script: String?, result: Data?
        var writes = 0, version = 0, answeredWrite = 0, confirmations = 0
        var scripts: [String] = [], asked: [Date] = []
        var lease: Date?
        var hold = OneShotLayoutGuard()
        let files = ChatProbeFiles(scriptInfo: { script == nil ? nil : ("\(writes)", now) },
            readScript: { script }, writeScript: { script = $0; scripts.append($0); writes += 1; asked.append(now); return true },
            resultInfo: { result == nil ? nil : "\(version)" }, readResult: { result })
        let probe = ChatProbe(files: files, now: { now })
        probe.isEnabled = { false }
        probe.isLayoutGuardWanted = { hold.wantsProbe(at: now) || lease.map { now <= $0 } == true }
        let keeper = ScreenLayoutKeeper(store: store)
        keeper.screens = { [screen] }
        keeper.live = { live }
        func observed() -> (windows: [PimpWindow], complete: Bool) {
            let windows = live.map { window -> PimpWindow in
                let page = WindowIdentity.resolveNative(id: window.id, title: window.title, frame: window.frame,
                    pages: probe.pages, nativeWindows: native, at: now).page
                return PimpWindow(id: window.id, title: window.title, chat: page?.chat ?? "", frame: window.frame,
                                  main: page.map { $0.kind == .main })
            }
            let check = WindowSnapshotStore.observe(from: windows, complete: true, isMain: { _ in false }, screen: { _ in "Mac" })
            return (windows, check.complete)
        }
        keeper.observation = {
            let sample = observed()
            return WindowSnapshotStore.observe(from: sample.windows, complete: sample.complete, isMain: { _ in false }, screen: { _ in "Mac" })
        }
        keeper.onRestorePlaced = { confirmations += 1; lease = now + OneShotLayoutGuard.lifetimeSeconds }
        keeper.tick(at: now)
        XCTAssertNotNil(keeper.restoreNow(at: now))
        XCTAssertEqual(confirmations, 1)
        let cold = observed()
        XCTAssertFalse(cold.complete, "No page answer exists at explicit arm time")
        hold.arm(desired, observation: .init(pid: 42, screens: "Mac", windows: cold.windows,
            complete: cold.complete, safe: true, restorePending: true), at: now, waitForRestore: true)
        XCTAssertTrue(hold.active)
        var armedAt: Date?
        for seconds in stride(from: 0, through: 70, by: 2) {
            now = start + Double(seconds)
            probe.tick(windows: live.map { (title: $0.title, frame: Optional($0.frame)) }, indexRevision: 1)
            keeper.tick(at: now)
            let sample = observed()
            XCTAssertTrue(hold.tick(.init(pid: 42, screens: "Mac", windows: sample.windows,
                complete: sample.complete, safe: true, restorePending: keeper.hasPendingRestore), at: now).isEmpty)
            if hold.armed, armedAt == nil { armedAt = now }
            if writes > answeredWrite {
                let nonce = try XCTUnwrap(script?.split(separator: "\n").first?.split(separator: " ").last.map(String.init))
                let entries: [[String: Any]] = live.map { window in
                    let url = window.main == true ? "https://claude.ai/epitaxy/local_main" : "about:blank"
                    var source = ProbeSourceFixture.metadata(url: url); source["windowId"] = window.id
                    return ["id": Int(window.id), "url": url, "source": source, "result": [
                        "v": 1, "nonce": nonce, "kind": window.main == true ? "main" : "popout",
                        "self": window.chat, "title": window.title, "store": "ok",
                        "path": "/epitaxy/local_main", "frame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height]]]
                }
                result = try JSONSerialization.data(withJSONObject: ["results": entries])
                version += 1; answeredWrite = writes
            }
        }
        XCTAssertFalse(store.load().first?.restorePending ?? true)
        XCTAssertNotNil(armedAt, "Fresh probes must span the screen keeper's two 10s samples")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(armedAt).timeIntervalSince(start), 12)
        XCTAssertFalse(hold.active)
        XCTAssertEqual(confirmations, 1, "Sampling/pending ticks cannot renew the lease")
        XCTAssertTrue(asked.allSatisfy { $0 <= start + OneShotLayoutGuard.lifetimeSeconds })
        XCTAssertTrue(zip(asked, asked.dropFirst()).allSatisfy { $0.1.timeIntervalSince($0.0) >= 4 })
        XCTAssertTrue(scripts.allSatisfy { !$0.contains("api.status(") }, "Confirmation uses only ordinary chats, never cash/status payload")
        XCTAssertFalse(ChatProbe.isRecent(ChatPage(kind: .main, chat: "local_main", title: "Main", store: "ok", at: start), at: start + 10))
    }

    func testDeferredCandidateWaitsForFreshIdentityButNeverForMissingNativeWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let frame = CGRect(x: 0, y: 30, width: 400, height: 700)
        let desired = [PimpMove(id: 10, frame: frame)]
        var cold = OneShotLayoutGuard.Observation(pid: 42, screens: "Mac",
            windows: [PimpWindow(id: 10, title: "Main", frame: frame)], complete: false, safe: true)
        var hold = OneShotLayoutGuard()
        hold.arm(desired, observation: cold, at: now)
        XCTAssertTrue(hold.wantsProbe(at: now))
        XCTAssertTrue(hold.tick(cold, at: now + 2).isEmpty)
        cold.complete = true
        cold.windows = [PimpWindow(id: 10, title: "Main", chat: "local_main", frame: frame, main: true)]
        _ = hold.tick(cold, at: now + 4)
        XCTAssertFalse(hold.armed)
        _ = hold.tick(cold, at: now + 6)
        XCTAssertTrue(hold.armed)
        XCTAssertFalse(hold.wantsProbe(at: now + 61))
        XCTAssertTrue(hold.tick(cold, at: now + 61).isEmpty)
        XCTAssertFalse(hold.active)
        cold.complete = false; cold.nativeComplete = false
        hold.arm(desired, observation: cold, at: now)
        XCTAssertFalse(hold.active)
    }
    func testIncompleteKeeperAfterConfirmationExpiryCannotBypassIdentityCooldownWithExplicitDemand() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: box) }
        let store = WindowSnapshotStore(url: box.appendingPathComponent("windows.json"))
        let frame = CGRect(x: 0, y: 30, width: 400, height: 700)
        let windows = [SnapshotWindow(chat: "main", folder: "", title: "Main", frame: frame, screen: "Mac")]
        XCTAssertTrue(store.save(WindowSnapshot(at: now, claude: "", windows: windows, restorePending: true)))
        let keeper = WindowSnapshotKeeper(store: store)
        keeper.claude = { (pid: 1, launch: now - 1000, version: "") }
        keeper.observation = { SnapshotObservation(windows: [], complete: false) }
        var explicitDemands = 0
        keeper.demandPages = { explicitDemands += 1 }
        for seconds in stride(from: 62, through: 180, by: 2) { keeper.tick(at: now + Double(seconds)) }
        XCTAssertEqual(explicitDemands, 0)
        XCTAssertTrue(store.load()?.restorePending == true)
        XCTAssertEqual(store.load()?.windows, windows)
    }

}
