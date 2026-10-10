import AppKit
import XCTest
@testable import ClaudeAX

final class WindowIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let left = CGRect(x: 0, y: 40, width: 400, height: 800)
    private let right = CGRect(x: 500, y: 40, width: 400, height: 800)

    private func page(_ kind: ChatPage.Kind, _ chat: String?, _ title: String,
                      _ frame: CGRect?, at: Date? = nil) -> ChatPage {
        ChatPage(kind: kind, chat: chat, title: title,
                 path: kind == .main ? "/epitaxy/\(chat ?? "")" : "blank",
                 store: "ok", frame: frame, at: at ?? now)
    }

    func testSameTitleMainAndPopoutUseTheirFramesForEveryConsumer() {
        let pages = [page(.main, "local_a", "Same", left), page(.popout, "local_b", "Same", right)]
        let native = pages.map { WindowIdentity.Native(title: $0.title, frame: $0.frame) }
        let resolve: (String, CGRect?) -> WindowIdentity = { title, frame in
            WindowIdentity.resolve(title: title, frame: frame, pages: pages, nativeWindows: native, at: self.now)
        }
        XCTAssertTrue(resolve("Same", left).isMain)
        XCTAssertEqual(resolve("Same", right).page?.chat, "local_b")
        XCTAssertEqual(resolve("Same", nil), .ambiguous)
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(), commands: CommandChannel(), themes: [], fonts: [])
        actions.windowIdentity = resolve
        actions.isMainWindowTitle = { _ in true } // Stale title shortcut must never win.
        XCTAssertEqual(actions.windowRoute(title: "Same", frame: right), .popout(chat: "local_b"))
        XCTAssertEqual(actions.windowRoute(title: "Same", frame: left), .main)
        XCTAssertNil(actions.windowRoute(title: "Same", frame: nil))
        let main = actions.themeAddress(scope: MenuModel.themeScopeWindow, title: "Same", frame: left)
        XCTAssertEqual(main.match, "/epitaxy/local_a")
        XCTAssertNil(main.chat)
        let popout = actions.themeAddress(scope: MenuModel.themeScopeWindow, title: "Same", frame: right)
        XCTAssertEqual(popout.chat, "local_b")
        XCTAssertNil(popout.match)
        XCTAssertFalse(actions.themeAddress(scope: MenuModel.themeScopeWindow, title: "Same").valid)
    }

    func testIncompleteOrSwappedObservationsCannotBorrowAnotherIdentity() {
        let a = page(.popout, "local_a", "A", left)
        let native = [WindowIdentity.Native(title: "B", frame: left), WindowIdentity.Native(title: "A", frame: right)]
        XCTAssertNil(WindowIdentity.resolve(title: "B", frame: left, pages: [a], nativeWindows: native).page)
        XCTAssertNil(WindowIdentity.resolve(title: "B", frame: left,
                      pages: [a, page(.main, "local_b", "B", right)], nativeWindows: native).page)
        let same = page(.popout, "local_a", "Same", nil)
        let twins = [WindowIdentity.Native(title: "Same", frame: left), WindowIdentity.Native(title: "Same", frame: right)]
        XCTAssertNil(WindowIdentity.resolve(title: "Same", frame: left, pages: [same], nativeWindows: twins).page)
        XCTAssertNil(WindowIdentity.resolve(title: "Same", frame: nil, pages: [same], nativeWindows: twins).page)
        XCTAssertNil(WindowIdentity.resolve(title: "Same", frame: nil, pages: [same]).page)
        let stacked = [WindowIdentity.Native(title: "A", frame: left), WindowIdentity.Native(title: "A", frame: left)]
        XCTAssertNil(WindowIdentity.resolve(title: "A", frame: left, pages: [a], nativeWindows: stacked).page)
        let unique = [WindowIdentity.Native(title: "Same", frame: left)]
        XCTAssertEqual(WindowIdentity.resolve(title: "Same", frame: left, pages: [same], nativeWindows: unique).page?.chat, "local_a")
    }

    func testWaitingHiddenTwinsUseTheSameFreshIdentity() {
        var answer = page(.popout, "local_b", "Same", right)
        answer.waiting = true
        let hidden: [(title: String, frame: CGRect?)] = [("Same", left), ("Same", right)]
        let native = hidden.map { WindowIdentity.Native(title: $0.title, frame: $0.frame) }
        let resolve: (String, CGRect?) -> WindowIdentity = { title, frame in
            WindowIdentity.resolve(title: title, frame: frame, pages: [answer], nativeWindows: native, at: self.now)
        }
        XCTAssertEqual(WindowHide.waiting(hidden, pages: [answer], resolve: resolve), 1)
        XCTAssertNil(WindowHide.page(for: hidden[0], in: [answer], resolve: resolve))
        XCTAssertEqual(WindowHide.page(for: hidden[1], in: [answer], resolve: resolve)?.chat, "local_b")
        let stale: (String, CGRect?) -> WindowIdentity = { title, frame in
            WindowIdentity.resolve(title: title, frame: frame, pages: [answer], nativeWindows: native,
                                   at: self.now.addingTimeInterval(ChatProbe.mainChatSeconds + 1))
        }
        XCTAssertNil(WindowHide.waiting(hidden, pages: [answer], resolve: stale))
    }

    func testStaleMapAndContradictoryTitleFallbackFailClosed() {
        let old = page(.main, "local_a", "A", left, at: now.addingTimeInterval(-ChatProbe.mainChatSeconds - 1))
        let native = [WindowIdentity.Native(title: "A", frame: right)]
        XCTAssertNil(WindowIdentity.resolve(title: "A", frame: left, pages: [old], nativeWindows: native, at: now).page)
        XCTAssertNil(WindowIdentity.resolve(title: "A", frame: nil,
                      pages: [page(.main, "local_a", "A", left)], nativeWindows: native, at: now).page)
    }

    func testResolvedRoleSurvivesSnapshotEvenWhenTitlesAreIdentical() {
        let windows = [PimpWindow(id: 1, title: "Same", chat: "local_a", folder: "", frame: left, main: true),
                       PimpWindow(id: 2, title: "Same", chat: "local_b", folder: "", frame: right, main: false)]
        let snapshot = WindowSnapshotStore.windows(from: windows, isMain: { _ in true }, screen: { _ in "Display" })
        XCTAssertEqual(snapshot.map { $0.chat }, [LayoutsStore.mainChat, "local_b"])
        XCTAssertEqual(PimpChannel.window("local_b", in: windows, isMain: { _ in true })?.id, 2)
    }
}
