import AppKit
import XCTest
@testable import ClaudeAX

final class WindowIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let left = CGRect(x: 0, y: 40, width: 400, height: 800)
    private let right = CGRect(x: 500, y: 40, width: 400, height: 800)

    /// Спрятанные однофамильцы (#8282): страница ждущего чата находится по номеру окна от лоадера —
    /// тем же резолвером, что у прочих действий (`WindowIdentity.resolveNative`).
    func testWaitingHiddenTwinsUseTheSameFreshIdentity() {
        var answer = ChatPage(kind: .popout, chat: "local_b", title: "Same", path: "blank", store: "ok",
                              frame: left, windowId: 202, at: now)
        answer.waiting = true
        let hidden: [(title: String, frame: CGRect?)] = [("Same", left), ("Same", right)]
        let native = [WindowIdentity.Native(title: "Same", frame: left, id: 201),
                      WindowIdentity.Native(title: "Same", frame: right, id: 202)]
        let resolve: (String, CGRect?) -> WindowIdentity = { title, frame in
            WindowIdentity.resolveNative(title: title, frame: frame, pages: [answer], nativeWindows: native, at: self.now)
        }
        XCTAssertEqual(WindowHide.waiting(hidden, resolve: resolve), 1, "рамка из ответа страницы (left) не в счёт")
        XCTAssertNil(WindowHide.page(for: hidden[0], resolve: resolve))
        XCTAssertEqual(WindowHide.page(for: hidden[1], resolve: resolve)?.chat, "local_b")
        let main = ChatPage(kind: .main, chat: "local_a", title: "Same", path: "/epitaxy/local_a", store: "ok",
                            frame: left, windowId: 201, at: now)
        let withMain: (String, CGRect?) -> WindowIdentity = { title, frame in
            WindowIdentity.resolveNative(title: title, frame: frame, pages: [main, answer], nativeWindows: native,
                                         at: self.now)
        }
        XCTAssertNil(WindowHide.page(for: hidden[0], resolve: withMain), "главное окно — не попап, разворачивать нечего")
    }

    func testResolvedRoleSurvivesSnapshotEvenWhenTitlesAreIdentical() {
        let windows = [PimpWindow(id: 1, title: "Same", chat: "local_a", folder: "", frame: left, main: true),
                       PimpWindow(id: 2, title: "Same", chat: "local_b", folder: "", frame: right, main: false)]
        let snapshot = WindowSnapshotStore.windows(from: windows, isMain: { _ in true }, screen: { _ in "Display" })
        XCTAssertEqual(snapshot.map { $0.chat }, [LayoutsStore.mainChat, "local_b"])
        XCTAssertEqual(PimpChannel.window("local_b", in: windows, isMain: { _ in true })?.id, 2)
    }
}
