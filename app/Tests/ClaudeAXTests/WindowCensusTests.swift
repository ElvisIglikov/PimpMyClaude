import CoreGraphics
import XCTest
@testable import ClaudeAX

final class WindowCensusTests: XCTestCase {
    private let left = CGRect(x: 10, y: 30, width: 400, height: 700)
    private let right = CGRect(x: 500, y: 30, width: 400, height: 700)

    func testAllSpacePairsRemainDistinctAndAmbiguousGeometryIsIncomplete() {
        let native = [WindowIdentity.Native(title: "Main", frame: left), .init(title: "Off Space", frame: right)]
        let allSpaces = [ClaudeWindowFrame(id: 1, frame: left), .init(id: 2, frame: right)]
        XCTAssertTrue(WindowCensus.pair(native: native, quartz: allSpaces).complete)
        XCTAssertEqual(WindowCensus.pair(native: native, quartz: allSpaces).pairs.map { $0.id }, [1, 2])
        XCTAssertFalse(WindowCensus.pair(native: native, quartz: [allSpaces[0]]).complete)
        let stacked = [WindowIdentity.Native(title: "Same", frame: left), .init(title: "Same", frame: left)]
        let duplicateCG = [ClaudeWindowFrame(id: 1, frame: left), .init(id: 2, frame: left)]
        XCTAssertTrue(WindowCensus.pair(native: stacked, quartz: duplicateCG).pairs.isEmpty)
        XCTAssertFalse(WindowCensus.pair(native: stacked, quartz: duplicateCG).complete)
        XCTAssertFalse(WindowCensus.pair(native: [native[0]], quartz: duplicateCG).complete)
    }

    func testUnknownOrDuplicateIdentityMakesTheWholeSnapshotIncomplete() {
        let main = PimpWindow(id: 1, title: "Main", chat: "local_m", frame: left, main: true)
        let unknown = PimpWindow(id: 2, title: "Loading", frame: right, main: false)
        let observe: ([PimpWindow]) -> SnapshotObservation = {
            WindowSnapshotStore.observe(from: $0, complete: true, isMain: { _ in false }, screen: { _ in "Mac" })
        }
        XCTAssertFalse(observe([main, unknown]).complete)
        let chat = PimpWindow(id: 2, title: "Chat", chat: "local_c", frame: right, main: false)
        XCTAssertTrue(observe([main, chat]).complete)
        let duplicate = PimpWindow(id: 3, title: "Chat", chat: "local_c", frame: left, main: false)
        XCTAssertFalse(observe([main, chat, duplicate]).complete)
    }

    func testRestoreAdaptsDisconnectedDisplayAndClaudeMinimumBeforeVerification() {
        let screen = CGRect(x: 0, y: 30, width: 1000, height: 700)
        let old = CGRect(x: -2500, y: -600, width: 120, height: 1100)
        let adapt: (CGRect) -> CGRect = { RestoreFrame.adapt($0, screens: [screen], minWidth: 280) }
        let target = adapt(old)
        XCTAssertEqual(target, CGRect(x: 0, y: 30, width: 280, height: 700))
        let expected = SnapshotWindow(chat: "main", folder: "", title: "M", frame: old, screen: "Disconnected")
        let observed = SnapshotWindow(chat: "main", folder: "", title: "M", frame: target, screen: "Mac")
        XCTAssertTrue(RestoreFrame.restored([expected], in: [observed], adapt: adapt))
        let layout = ScreenLayout(key: "Mac", at: Date(), windows: [expected], chatGPT: nil)
        let live = [PimpWindow(id: 1, title: "M", frame: screen, main: true)]
        XCTAssertEqual(ScreenLayoutKeeper.moves(for: layout, live: live, isMain: { _ in false },
                                                chatGPT: nil, adaptFrame: adapt).moves.first?.frame, target)
    }

    func testRestoreDoesNotOpenChatAlreadyOnAnotherSpaceOrOnIncompleteCensus() {
        let channel = PimpChannel(directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString))
        let main = PimpWindow(id: 1, title: "Main", chat: "local_m", frame: left, main: true)
        let otherSpace = PimpWindow(id: 2, title: "Chat", chat: "local_c", frame: right, main: false)
        channel.seats.claudeRunning = { true }
        channel.seats.windows = { [main] }
        channel.seats.restoreWindows = { ([main, otherSpace], true) }
        var opened = 0
        var moves: [PimpMove] = []
        channel.seats.openChat = { _, _, _ in opened += 1 }
        channel.seats.place = { moves += $0 }
        let snapshot = WindowSnapshot(at: Date(), claude: "", windows: [
            SnapshotWindow(chat: "local_c", folder: "", title: "Chat", frame: left, screen: "Mac")])
        XCTAssertTrue(channel.startRestore(snapshot: snapshot, name: "Test"))
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(moves.map { $0.id }, [2])
        moves = []
        let duplicate = PimpWindow(id: 3, title: "Another Chat", chat: "local_c", frame: left, main: false)
        channel.seats.restoreWindows = { ([main, otherSpace, duplicate], true) }
        XCTAssertTrue(channel.startRestore(snapshot: snapshot, name: "Test"))
        XCTAssertEqual(opened, 0, "Ambiguous existing identities must never create a third popout")
        XCTAssertTrue(moves.isEmpty)
        // A second channel demonstrates the same refusal for an unpaired census.
        let incomplete = PimpChannel(directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString))
        incomplete.seats.claudeRunning = { true }
        incomplete.seats.windows = { [main] }
        incomplete.seats.openChat = { _, _, _ in opened += 1 }
        incomplete.seats.place = { moves += $0 }
        incomplete.seats.restoreWindows = { ([main], false) }
        XCTAssertTrue(incomplete.startRestore(snapshot: snapshot, name: "Test"))
        XCTAssertEqual(opened, 0)
        XCTAssertTrue(moves.isEmpty)
    }

    func testChatGPTLearnedMinimumKeepsRightEdgeForPlaceAndVerification() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let old = CGRect(x: 600, y: 30, width: 280, height: 700)
        let adapt: (CGRect) -> CGRect = { RestoreFrame.adaptChatGPT($0, screens: [screen], minWidth: 400) }
        let actual = CGRect(x: 480, y: 30, width: 400, height: 700)
        XCTAssertEqual(adapt(old), actual)
        let layout = ScreenLayout(key: "Mac", at: Date(), windows: [], chatGPT: old)
        let plan = ScreenLayoutKeeper.moves(for: layout, live: [], isMain: { _ in false },
                                            chatGPT: actual, adaptChatGPTFrame: adapt)
        XCTAssertNil(plan.chatGPT, "Learned minimum already occupies the valid restored rectangle")
    }
}
