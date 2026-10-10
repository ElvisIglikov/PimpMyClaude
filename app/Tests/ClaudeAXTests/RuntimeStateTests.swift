import AppKit
import XCTest
@testable import ClaudeAX

final class RuntimeStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let left = CGRect(x: 0, y: 40, width: 400, height: 700)
    private let right = CGRect(x: 500, y: 40, width: 400, height: 700)

    func testThemeMenuMemorySeparatesTwinsAndSurvivesRenameAndMove() throws {
        let suite = "theme-memory-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ThemeStore(defaults: defaults)
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(), commands: CommandChannel(), themes: [], fonts: [], themeStore: store)
        var pages = [ChatPage(kind: .main, chat: "local_a", title: "Same", store: "ok", windowId: 101, at: start),
                     ChatPage(kind: .popout, chat: "local_b", title: "Same", store: "ok", windowId: 102, at: start)]
        var native = [WindowIdentity.Native(title: "Same", frame: left, id: 101),
                      WindowIdentity.Native(title: "Same", frame: right, id: 102)]
        actions.windowIdentity = { title, frame in
            WindowIdentity.resolveNative(title: title, frame: frame, pages: pages, nativeWindows: native, at: self.start)
        }
        actions.uniqueLegacyTitle = { title in native.filter { $0.title == title }.count == 1 }
        store.setWindowTheme("old-title-theme", title: "Same")
        let a = actions.memoryKey(title: "Same", frame: left), b = actions.memoryKey(title: "Same", frame: right)
        XCTAssertEqual(a, "c:local_a")
        XCTAssertEqual(b, "c:local_b")
        XCTAssertNil(store.windowThemeID(title: a), "Ambiguous legacy title must not be migrated to either twin")
        store.setWindowTheme("ocean", title: a)
        store.setWindowTheme("sand", title: b)
        store.setWindowLook(Look(dense: true), title: a)
        pages[0] = ChatPage(kind: .main, chat: "local_a", title: "Renamed", store: "ok", windowId: 101, at: start)
        native = [.init(title: "Renamed", frame: right, id: 101), .init(title: "Same", frame: left, id: 102)]
        XCTAssertEqual(store.windowThemeID(title: actions.memoryKey(title: "Renamed", frame: right)), "ocean")
        XCTAssertEqual(store.windowLook(title: actions.memoryKey(title: "Renamed", frame: right)), Look(dense: true))
        XCTAssertEqual(store.windowThemeID(title: actions.memoryKey(title: "Same", frame: left)), "sand")
        XCTAssertEqual(actions.memoryKey(title: "Same", frame: nil), "", "Unknown production identity has no shared title key")
        store.setWindowFont("legacy-font", title: "Renamed")
        _ = actions.memoryKey(title: "Renamed", frame: right)
        XCTAssertEqual(store.windowFontID(title: a), "legacy-font")
        XCTAssertNil(store.windowFontID(title: "Renamed"))
    }

    func testThemeAgeIsRestoredBeforeTrimmingAndReturnedToPage() throws {
        let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: box) }
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        let store = WindowThemeStore(url: box.appendingPathComponent("themes.json"), now: { self.start })
        store.absorb(page: ["id:local_z": WindowThemeEntry(layers: ["frame": .value(.bool(true))], at: 9000)], at: start)
        var raw: [String: Any] = ["id:local_z": ["frame": true]]
        for i in 0..<205 { raw["id:local_\(i)"] = ["frame": true] }
        let parsed = WindowThemeStore.map(from: raw, trimming: false)
        XCTAssertEqual(parsed.count, 206)
        store.absorb(page: parsed, at: start.addingTimeInterval(100))
        XCTAssertEqual(store.entries.count, WindowThemeStore.keyLimit)
        XCTAssertEqual(store.entries["id:local_z"]?.at, 9000, "Prior saved age survives before zero-age newcomers are trimmed")
        store.absorb(page: ["id:local_z": WindowThemeEntry(layers: ["frame": .value(.bool(true))], at: 10000)], at: start)
        XCTAssertEqual(store.entries["id:local_z"]?.at, 10000, "Same-layer usage timestamp is not lost")
        let body = CommandChannel.payload(action: WindowThemeStore.restoreAction, fields: WindowThemeStore.restoreFields(store.entries))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let entries = try XCTUnwrap(object["entries"] as? [String: [String: Any]])
        XCTAssertEqual(entries["id:local_z"]?["at"] as? Int, 10000)
        let unknown = WindowThemeStore.map(from: ["id:local_old": ["frame": true]])
        store.absorb(page: unknown, at: start.addingTimeInterval(200))
        XCTAssertEqual(store.entries["id:local_old"]?.at, 0, "Reading an archive does not make it new")
    }

    func testGalleryReloadResendsBoundedlyAndAcknowledgementStopsRetries() {
        let sync = ViewerCountsSync()
        var sent = 0
        func tick(_ seconds: Double, _ counted: Int) {
            let now = start.addingTimeInterval(seconds)
            var page = ChatPage(kind: .main, chat: "local_a", title: "A", store: "ok", windowId: 101, at: now)
            page.galleryCounted = counted
            sync.tick(titles: ["A"], pages: [page], at: now) { done in sent += 1; done(true) }
        }
        for t in [0.0, 6, 12, 18, 24] { tick(t, 0) }
        XCTAssertEqual(sent, 3)
        tick(25, 1)
        tick(31, 1)
        XCTAssertEqual(sent, 3)
        tick(32, 0) // Same title and same native ID, but a reloaded page.
        XCTAssertEqual(sent, 4)
        tick(33, 1)
        tick(40, 1)
        XCTAssertEqual(sent, 4)
    }

    func testGalleryFailedAndLateDeliveriesNeverBecomeAcknowledgements() {
        let sync = ViewerCountsSync()
        var callbacks: [(Bool) -> Void] = []
        func tick(_ seconds: Double) {
            sync.tick(titles: ["A"], pages: [], at: start.addingTimeInterval(seconds)) { callbacks.append($0) }
        }
        tick(0)
        tick(6)
        XCTAssertEqual(callbacks.count, 1, "Only one in-flight request")
        sync.beginGeneration()
        tick(7)
        callbacks[0](true)
        tick(13)
        XCTAssertEqual(callbacks.count, 2, "Old completion cannot release the newer in-flight send")
        callbacks[1](false)
        tick(14)
        XCTAssertEqual(callbacks.count, 3, "A failed send is retried within the bounded generation")
    }
    func testOldPositiveGalleryCounterCannotAcknowledgeANewTitleGeneration() {
        let sync = ViewerCountsSync()
        var callbacks: [(Bool) -> Void] = []
        func tick(_ seconds: Double, _ title: String, _ counted: Int) {
            let at = start.addingTimeInterval(seconds)
            var page = ChatPage(kind: .main, chat: "local_a", title: title, store: "ok", windowId: 101, at: at)
            page.galleryCounted = counted
            sync.tick(titles: [title], pages: [page], at: at) { callbacks.append($0) }
        }
        tick(0, "A", 1); callbacks[0](true)
        tick(1, "A", 1)
        tick(6, "A", 1)
        XCTAssertEqual(callbacks.count, 2, "Old positive value is not acknowledgement")
        callbacks[1](true)
        tick(7, "A", 2); tick(13, "A", 2)
        XCTAssertEqual(callbacks.count, 2)
        tick(14, "Renamed", 2)
        tick(15, "Renamed", 2) // Probe returned while async state was still in flight.
        callbacks[2](true)
        tick(20, "Renamed", 2)
        XCTAssertEqual(callbacks.count, 4)
    }

    func testUnavailableViewerDoesNotExhaustTheAcceptedDeliveryBudget() {
        let sync = ViewerCountsSync()
        var sends = 0
        for second in [0.0, 6, 12, 18] {
            sync.tick(titles: ["A"], pages: [], at: start.addingTimeInterval(second)) { done in
                sends += 1; done(second == 18)
            }
        }
        XCTAssertEqual(sends, 4)
    }

    func testResolvedEditorOwnershipDoesNotBlockSameTitleNeighbour() {
        defer { ClaudeActions.themeEditorKey = nil; ClaudeActions.themeEditorTitle = nil }
        ClaudeActions.themeEditorTitle = "Same"
        ClaudeActions.themeEditorKey = "c:local_a"
        let own = ProjectTarget(key: "c:local_a", match: "", chat: "local_a", title: "Same", folder: nil)
        let other = ProjectTarget(key: "c:local_b", match: "", chat: "local_b", title: "Same", folder: nil)
        XCTAssertTrue(ProjectPaint.ownedByEditor(own))
        XCTAssertFalse(ProjectPaint.ownedByEditor(other))
    }

    func testGlobalThemeRemainsAvailableToSaveAndEditorButWindowOverrideWins() throws {
        let suite = "theme-all-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ThemeStore(defaults: defaults)
        let all = Theme(id: "all", name: "All", type: "dark", palette: ["accent": "#0088ff", "background": "#111122"])
        let own = Theme(id: "own", name: "Own", type: "light", palette: ["accent": "#ff8800", "background": "#eeeeee"])
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(), commands: CommandChannel(), themes: [all, own], fonts: [], themeStore: store)
        actions.windowIdentity = { _, _ in .page(ChatPage(kind: .main, chat: "local_a", title: "A", store: "ok", windowId: 101, at: self.start)) }
        store.setAllTheme(all.id)
        XCTAssertEqual(actions.themeToSave(window: nil), all)
        XCTAssertEqual(actions.editorKnobs(window: nil), ThemeKnobs.from(palette: all.palette, type: all.type))
        store.setWindowTheme(own.id, title: "c:local_a")
        XCTAssertEqual(actions.themeToSave(window: nil), own)
        XCTAssertEqual(actions.editorKnobs(window: nil), ThemeKnobs.from(palette: own.palette, type: own.type))
    }

}
