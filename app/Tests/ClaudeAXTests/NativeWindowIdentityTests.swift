import AppKit
import XCTest
@testable import ClaudeAX

final class NativeWindowIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let left = CGRect(x: 0, y: 40, width: 400, height: 800)
    private let right = CGRect(x: 500, y: 40, width: 400, height: 800)
    private func page(_ kind: ChatPage.Kind, _ chat: String, _ frame: CGRect, _ id: CGWindowID?) -> ChatPage {
        ChatPage(kind: kind, chat: chat, title: "Same", path: kind == .main ? "/epitaxy/\(chat)" : "blank",
                 store: "ok", frame: frame, windowId: id, at: now)
    }

    func testSameTitleFrameSwapRetainsNativeIdentityAcrossConsumers() {
        let pages = [page(.main, "local_a", left, 101), page(.popout, "local_b", right, 102)]
        let native = [WindowIdentity.Native(title: "Same", frame: right, id: 101),
                      WindowIdentity.Native(title: "Same", frame: left, id: 102)]
        let resolve: (String, CGRect?) -> WindowIdentity = { title, frame in
            WindowIdentity.resolveNative(title: title, frame: frame, pages: pages, nativeWindows: native, at: self.now)
        }
        XCTAssertTrue(resolve("Same", right).isMain)
        XCTAssertEqual(resolve("Same", left).page?.chat, "local_b")
        XCTAssertTrue(WindowIdentity.resolveNative(id: 101, title: "", frame: nil, pages: pages,
                                                   nativeWindows: native, at: now).isMain)
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(), commands: CommandChannel(), themes: [], fonts: [])
        actions.windowIdentity = resolve
        XCTAssertEqual(actions.windowRoute(title: "Same", frame: left), .popout(chat: "local_b"))
        XCTAssertEqual(actions.windowRoute(title: "Same", frame: right), .main)
        XCTAssertEqual(actions.themeAddress(scope: MenuModel.themeScopeWindow, title: "Same", frame: left).chat, "local_b")
        XCTAssertEqual(actions.themeAddress(scope: MenuModel.themeScopeWindow, title: "Same", frame: right).match, "/epitaxy/local_a")
        let windows = native.map { n -> PimpWindow in
            let identity = resolve(n.title, n.frame)
            return PimpWindow(id: n.id!, title: n.title, chat: identity.page?.chat ?? "", folder: "", frame: n.frame!, main: identity.isMain)
        }
        XCTAssertEqual(PimpChannel.window("local_b", in: windows, isMain: { _ in true })?.id, 102)
        XCTAssertEqual(WindowSnapshotStore.windows(from: windows, isMain: { _ in true }, screen: { _ in "D" }).map { $0.chat },
                       [LayoutsStore.mainChat, "local_b"])
    }

    func testMissingDuplicateOrStaleIdentityNeverFallsBackToFramesOrTitles() {
        let native = [WindowIdentity.Native(title: "Same", frame: left, id: 101)]
        for pages in [[page(.main, "local_a", left, nil)], [page(.main, "local_a", left, 102)],
                      [page(.main, "local_a", left, 101), page(.popout, "local_b", right, 101)]] {
            XCTAssertNil(WindowIdentity.resolveNative(title: "Same", frame: left, pages: pages, nativeWindows: native, at: now).page)
        }
        let pages = [page(.main, "local_a", left, 101)]
        for inventory in [[WindowIdentity.Native(title: "Same", frame: left)], native + native] {
            XCTAssertNil(WindowIdentity.resolveNative(title: "Same", frame: left, pages: pages, nativeWindows: inventory, at: now).page)
        }
        XCTAssertNil(WindowIdentity.resolveNative(title: "Same", frame: nil, pages: pages, nativeWindows: native, at: now).page)
        XCTAssertNil(WindowIdentity.resolveNative(title: "Same", frame: left, pages: pages, nativeWindows: native,
                                                  at: now.addingTimeInterval(ChatProbe.mainChatSeconds + 1)).page)
    }

    func testCurrentFullFrameDisambiguatesSameOriginWithDifferentSizes() {
        let wider = CGRect(x: left.minX, y: left.minY, width: 700, height: left.height)
        let native = [WindowIdentity.Native(title: "Same", frame: left, id: 101),
                      WindowIdentity.Native(title: "Same", frame: wider, id: 102)]
        let pages = [page(.main, "local_a", right, 101), page(.popout, "local_b", right, 102)]
        XCTAssertTrue(WindowIdentity.resolveNative(title: "Same", frame: left, pages: pages, nativeWindows: native, at: now).isMain)
        XCTAssertEqual(WindowIdentity.resolveNative(title: "Same", frame: wider, pages: pages, nativeWindows: native, at: now).page?.chat, "local_b")
    }

    func testThemeEditorOwnershipUsesCurrentFrameAndProtectsNamedMain() {
        let pages = [page(.main, "local_a", left, 101), page(.popout, "local_b", right, 102)]
        let native = [WindowIdentity.Native(title: "Same", frame: right, id: 101),
                      WindowIdentity.Native(title: "Same", frame: left, id: 102)]
        let paint = ProjectPaint()
        paint.windowIdentity = { title, frame in
            WindowIdentity.resolveNative(title: title, frame: frame, pages: pages, nativeWindows: native, at: self.now)
        }
        let oldResolver = ClaudeActions.windowKeyForTitle
        let oldTitle = ClaudeActions.themeEditorTitle, oldKey = ClaudeActions.themeEditorKey
        defer {
            ClaudeActions.windowKeyForTitle = oldResolver
            ClaudeActions.themeEditorTitle = oldTitle
            ClaudeActions.themeEditorKey = oldKey
        }
        ClaudeActions.windowKeyForTitle = { title, frame in paint.windowKey(forTitle: title, frame: frame) }
        ClaudeActions.themeEditorTitle = "Same"
        ClaudeActions.themeEditorKey = ClaudeActions.windowKeyForTitle?("Same", right)
        XCTAssertEqual(ClaudeActions.themeEditorKey, ProjectPaint.mainKey)
        XCTAssertTrue(ProjectPaint.ownedByEditor(ProjectTarget(key: ProjectPaint.mainKey, match: "/epitaxy/local_a", chat: nil,
                                                              title: ProjectPaint.mainWindowTitle, folder: nil)))
    }

    func testOnlyOuterLoaderMetadataProvidesValidatedWindowID() throws {
        func parse(_ id: Any?) throws -> [ChatPage] {
            var source: [String: Any] = ["loader": 8, "origin": "https://claude.ai", "url": "about:blank", "processId": 1, "routingId": 2]
            if let id = id { source["windowId"] = id }
            let entry: [String: Any] = ["url": "about:blank", "source": source,
                "result": ["nonce": "n", "kind": "popout", "self": "local_a", "title": "Same", "windowId": 999, "source": ["windowId": 999]]]
            return ChatProbe.parseAnswer(try JSONSerialization.data(withJSONObject: ["results": [entry]]), nonce: "n", at: now).pages
        }
        XCTAssertEqual(try parse(101).first?.windowId, 101)
        XCTAssertEqual(try parse(UInt32.max).first?.windowId, UInt32.max)
        XCTAssertEqual(try parse(nil).count, 1)
        XCTAssertNil(try parse(nil).first?.windowId)
        for invalid in [true, 0, -1, 1.5, 4294967296, "101", NSNull()] as [Any] {
            XCTAssertTrue(try parse(invalid).isEmpty)
        }
    }
}
