import CoreGraphics
import XCTest
@testable import ClaudeAX

final class OneShotLayoutGuardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let frame = CGRect(x: 20, y: 40, width: 400, height: 700)
    private var windows: [PimpWindow] {
        [PimpWindow(id: 10, title: "Twin", chat: "local_main", frame: frame, main: true),
         PimpWindow(id: 11, title: "Twin", chat: "local_rick", frame: frame.offsetBy(dx: 450, dy: 0), main: false)]
    }
    private var observation: OneShotLayoutGuard.Observation {
        .init(pid: 42, screens: "Mac@0,0,2000x1200", windows: windows, complete: true, safe: true)
    }
    private var desired: [PimpMove] { windows.map { PimpMove(id: $0.id, frame: $0.frame) } }
    private func shifted(_ input: OneShotLayoutGuard.Observation, dx: CGFloat = 30) -> OneShotLayoutGuard.Observation {
        var result = input
        result.windows = input.windows.map {
            PimpWindow(id: $0.id, title: $0.title, chat: $0.chat, frame: $0.frame.offsetBy(dx: dx, dy: 0), main: $0.main)
        }
        return result
    }
    private func armed() -> OneShotLayoutGuard {
        var hold = OneShotLayoutGuard()
        hold.arm(desired, observation: observation, at: now)
        XCTAssertTrue(hold.tick(observation, at: now + 2).isEmpty)
        XCTAssertFalse(hold.armed)
        XCTAssertTrue(hold.tick(observation, at: now + 4).isEmpty)
        XCTAssertTrue(hold.armed)
        return hold
    }

    func testTwoReadbacksThenTwoStableDeviationsProduceOnlyOneCorrection() {
        var hold = armed()
        let changed = shifted(observation)
        XCTAssertTrue(hold.tick(changed, at: now + 6).isEmpty)
        XCTAssertEqual(hold.tick(changed, at: now + 8), desired)
        XCTAssertFalse(hold.active, "Consumed before the caller performs any AX effect")
        for offset in [10.0, 12, 20] { XCTAssertTrue(hold.tick(changed, at: now + offset).isEmpty) }
        // Only another explicit layout operation may create a new candidate.
        hold.arm(desired, observation: observation, at: now + 21)
        XCTAssertTrue(hold.active)
        XCTAssertFalse(hold.armed)
    }

    func testDesiredFramesAloneNeverBecomeBaselineAndFailedPlacementExpires() {
        var hold = OneShotLayoutGuard()
        let wrong = shifted(observation)
        hold.arm(desired, observation: wrong, at: now)
        for offset in [2.0, 4, 20, 40] {
            XCTAssertTrue(hold.tick(wrong, at: now + offset).isEmpty)
            XCTAssertFalse(hold.armed)
        }
        XCTAssertTrue(hold.tick(wrong, at: now + OneShotLayoutGuard.candidateSeconds + 1).isEmpty)
        XCTAssertFalse(hold.active)
    }

    func testCorrectionUsesActualReadbackRatherThanDesiredRoundedCoordinates() {
        var hold = OneShotLayoutGuard()
        let actual = shifted(observation, dx: 1)
        hold.arm(desired, observation: actual, at: now)
        _ = hold.tick(actual, at: now + 2)
        _ = hold.tick(actual, at: now + 4)
        let changed = shifted(actual)
        _ = hold.tick(changed, at: now + 6)
        XCTAssertEqual(hold.tick(changed, at: now + 8), actual.windows.map { PimpMove(id: $0.id, frame: $0.frame) })
    }

    func testUnstableDeviationAndReturnToBaselineResetTheConfirmation() {
        var hold = armed()
        _ = hold.tick(shifted(observation), at: now + 6)
        XCTAssertTrue(hold.tick(shifted(observation, dx: 50), at: now + 8).isEmpty)
        XCTAssertTrue(hold.tick(observation, at: now + 10).isEmpty)
        XCTAssertTrue(hold.tick(shifted(observation), at: now + 12).isEmpty)
        XCTAssertEqual(hold.tick(shifted(observation), at: now + 14), desired)
    }

    func testIncompleteBusyInputOrChangedProcessDisplayAndIdentityDisarmPermanently() {
        var cases: [OneShotLayoutGuard.Observation] = []
        var incomplete = observation; incomplete.complete = false; cases.append(incomplete)
        var unsafe = observation; unsafe.safe = false; cases.append(unsafe) // busy/minimized/fullscreen/missing monitor
        var pid = observation; pid.pid = 43; cases.append(pid)
        var gone = observation; gone.pid = nil; cases.append(gone)
        var screens = observation; screens.screens = "Other"; cases.append(screens)
        var missing = observation; missing.windows.removeLast(); cases.append(missing)
        var swapped = observation
        swapped.windows[1] = PimpWindow(id: 11, title: "Twin", chat: "local_other", frame: windows[1].frame, main: false)
        cases.append(swapped)
        var added = observation
        added.windows.append(PimpWindow(id: 12, title: "New", chat: "local_new", frame: frame, main: false)); cases.append(added)
        var pending = observation; pending.restorePending = true; cases.append(pending)
        for changed in cases {
            var hold = armed()
            XCTAssertTrue(hold.tick(changed, at: now + 6).isEmpty)
            XCTAssertFalse(hold.active)
            XCTAssertTrue(hold.tick(shifted(observation), at: now + 8).isEmpty)
            XCTAssertTrue(hold.tick(shifted(observation), at: now + 10).isEmpty)
        }
    }

    func testShortManualDragBetweenTicksAndKeyboardInputCannotBeUndone() {
        for _ in ["mouse-down-drag-up", "keyboard", "programmatic-manual-placement"] {
            var hold = armed()
            // Passive event callbacks/known placement invalidate immediately, not by polling
            // pressedMouseButtons (which is already zero when the next watchdog tick arrives).
            hold.disarm()
            XCTAssertTrue(hold.tick(shifted(observation), at: now + 6).isEmpty)
            XCTAssertTrue(hold.tick(shifted(observation), at: now + 8).isEmpty)
            XCTAssertFalse(hold.active)
        }
    }

    func testNamedRestorePendingWaitIsBoundedAndCannotSkipStableReadback() {
        var pending = observation; pending.restorePending = true
        var hold = OneShotLayoutGuard()
        hold.arm(desired, observation: pending, at: now)
        XCTAssertFalse(hold.active, "Ordinary arrange does not bypass a protected restore")
        hold.arm(desired, observation: pending, at: now, waitForRestore: true)
        for offset in [2.0, 10, 20] {
            XCTAssertTrue(hold.tick(pending, at: now + offset).isEmpty)
            XCTAssertFalse(hold.armed)
        }
        _ = hold.tick(observation, at: now + 22)
        XCTAssertFalse(hold.armed)
        _ = hold.tick(observation, at: now + 24)
        XCTAssertTrue(hold.armed)
        hold.arm(desired, observation: pending, at: now, waitForRestore: true)
        _ = hold.tick(pending, at: now + OneShotLayoutGuard.candidateSeconds + 1)
        XCTAssertFalse(hold.active, "Partial restore never leaves a later surprise correction")
    }

    func testArmRejectsUnknownNativeIdentityDuplicateTargetsAndMissingObservationCapability() {
        var hold = OneShotLayoutGuard()
        var unsafe = observation; unsafe.safe = false
        hold.arm(desired, observation: unsafe, at: now)
        XCTAssertFalse(hold.active)
        hold.arm(desired + [desired[0]], observation: observation, at: now)
        XCTAssertFalse(hold.active)
        hold.arm([PimpMove(id: 99, frame: frame)], observation: observation, at: now)
        XCTAssertFalse(hold.active)
        var unknown = observation
        unknown.windows[1] = PimpWindow(id: 11, title: "Twin", frame: windows[1].frame)
        hold.arm(desired, observation: unknown, at: now)
        XCTAssertFalse(hold.active)
    }
    func testNamedRestoreArmsOnlySuccessfulExistingPlacementsAndNeverNewlyOpenedWindows() throws {
        for outcome in ["success", "partial", "guard-write-failed"] {
            let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: box) }
            var clock = now
            var live = [windows[0]]
            let channel = PimpChannel(directory: box, now: { clock })
            channel.seats.claudeRunning = { true }
            channel.seats.restoreWindows = { (live, true) }
            channel.seats.openChat = { chat, _, _ in
                if outcome != "partial" {
                    live.append(PimpWindow(id: 12, title: "Rick", chat: chat, frame: self.frame, main: false))
                }
            }
            var armed: [[PimpMove]] = []
            channel.seats.explicitNamedLayout = { armed.append($0) }
            channel.seats.finishNamedRestore = { _ in outcome != "guard-write-failed" }
            let layout = WindowLayout(name: "Saved", at: now, mode: .five, cells: [
                LayoutCell(folder: "", chat: "main", title: "Main", cell: nil, frame: frame),
                LayoutCell(folder: "", chat: "local_rick", title: "Rick", cell: nil, frame: frame.offsetBy(dx: 450, dy: 0))])
            XCTAssertTrue(channel.startRestore(layout, fresh: false))
            clock += PimpChannel.restoreWindowSeconds + 1
            channel.tick()
            XCTAssertFalse(channel.isRestoring)
            if outcome == "success" {
                XCTAssertEqual(armed, [[PimpMove(id: 10, frame: frame)]])
            } else { XCTAssertTrue(armed.isEmpty, outcome) }
        }
    }

    func testExplicitChannelArrangePublishesDesiredButLowLevelPlaceDoesNotArm() throws {
        let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: box) }
        let channel = PimpChannel(directory: box, now: { self.now })
        channel.seats.claudeRunning = { true }
        channel.seats.windows = { self.windows }
        channel.seats.arrangeSmart = { _, _, _ in self.windows }
        var plans: [[PimpMove]] = []
        channel.seats.explicitLayout = { plans.append($0) }
        channel.start()
        let body: [String: Any] = ["id": "layout-1", "at": PimpChannel.stampText(now), "action": "arrange", "from": ""]
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try XCTUnwrap(PimpRequest.parse(data))
        let file = box.appendingPathComponent("layout-1.json")
        try data.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        channel.tick()
        XCTAssertEqual(plans, [desired])
        channel.seats.place(desired)
        XCTAssertEqual(plans.count, 1)
    }

}
