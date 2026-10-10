import AppKit
import XCTest
@testable import ClaudeAX

final class ProjectIdentityTests: XCTestCase {
    func testFreshMainChatNeverWritesOrPaintsThePreviousMainProject() throws {
        let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let root = box.appendingPathComponent("projects")
        let old = root.appendingPathComponent("Old")
        let sessions = box.appendingPathComponent("sessions/account/place")
        let status = box.appendingPathComponent("status.json")
        try FileManager.default.createDirectory(at: old.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: box) }
        let suite = "project-identity-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session: [String: Any] = ["sessionId": "local_a1", "title": "Old", "titleSource": "user",
                                      "cwd": old.path, "originCwd": old.path, "lastFocusedAt": 3000,
                                      "lastActivityAt": 3000, "isArchived": false]
        try JSONSerialization.data(withJSONObject: session).write(to: sessions.appendingPathComponent("local_a1.json"))
        try JSONSerialization.data(withJSONObject: ["webContents": [["url": "https://claude.ai/epitaxy/local_a1"]]])
            .write(to: status)
        let now = Date()
        let index = ProjectIndex(sessionsDirectory: box.appendingPathComponent("sessions"), statusURL: status,
                                 projectsRoot: root, home: box, now: { now })
        let store = ProjectSettingsStore(registryURL: box.appendingPathComponent("project-views.json"))
        XCTAssertEqual(store.write(ProjectSettings(name: "Old", look: .reset), to: old), .written)
        XCTAssertEqual(store.settings(in: old)?.look, .reset, "Fixture starts with the look explicitly reset")
        let paint = ProjectPaint(index: index, store: store, defaults: defaults, now: { now })
        let frame = CGRect(x: 10, y: 30, width: 400, height: 800)
        var page = ChatPage(kind: .main, chat: "local_new", title: "Fresh", path: "/epitaxy/local_new",
                            store: "ok", frame: frame, windowId: 101, at: now)
        paint.chatPages = { [page] }
        paint.windowTitles = { ["Fresh"] }
        paint.windowIdentity = { title, frame in
            WindowIdentity.resolveNative(title: title, frame: frame, pages: [page],
                                         nativeWindows: [.init(title: "Fresh", frame: page.frame, id: 101)], at: now)
        }
        paint.pageIdentity = { candidate in
            WindowIdentity.resolveNative(id: candidate.windowId, title: candidate.title, frame: nil, pages: [page],
                                         nativeWindows: [.init(title: "Fresh", frame: page.frame, id: 101)], at: now)
        }
        var sent: [ProjectPaintCommand] = []
        paint.send = { sent.append($0); return true }
        paint.tick()
        XCTAssertEqual(index.mainWindow()?.folder?.standardizedFileURL.path, old.standardizedFileURL.path)
        paint.noteManualChoice(title: "Fresh", windowFrame: frame, theme: .keep, font: .keep, size: .keep, frame: .keep, look: .set(Look(dense: true)))
        XCTAssertEqual(store.settings(in: old)?.look, .reset)
        XCTAssertNil(paint.projectTheme(forTitle: "Fresh", frame: frame))
        XCTAssertTrue(sent.isEmpty, "Unknown fresh chat must not receive the old project's appearance")
        XCTAssertEqual(paint.windowKey(forTitle: "Fresh", frame: frame), ProjectPaint.mainKey)
        // A fresh home page without a folder chip is equally authoritative.
        page = ChatPage(kind: .main, chat: nil, title: "Fresh", path: ChatProbe.homePath,
                        store: "ok", frame: frame, windowId: 101, at: now)
        paint.forget()
        paint.tick()
        paint.noteManualChoice(title: "Fresh", windowFrame: frame, theme: .keep, font: .keep, size: .keep, frame: .keep, look: .set(Look(dense: true)))
        XCTAssertEqual(store.settings(in: old)?.look, .reset)
        XCTAssertTrue(sent.isEmpty, "Home without a folder must not borrow the previous session's project")

        // A real chip pointing into a subdirectory writes the project root, as before.
        let subdir = old.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        page = ChatPage(kind: .main, chat: nil, title: "Fresh", path: ChatProbe.homePath,
                        store: "ok", folder: subdir.path, frame: frame, windowId: 101, at: now)
        paint.noteManualChoice(title: "Fresh", windowFrame: frame, theme: .keep, font: .keep, size: .keep, frame: .keep, look: .set(Look(dense: true)))
        XCTAssertEqual(store.settings(in: old)?.look, .set(Look(dense: true)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(in: subdir).path))
        XCTAssertEqual(store.write(ProjectSettings(name: "Old", look: .reset), to: old), .written)
        XCTAssertEqual(store.settings(in: old)?.look, .reset)
        paint.windowIdentity = { _, _ in .ambiguous }
        paint.noteManualChoice(title: "Old", windowFrame: frame, theme: .keep, font: .keep, size: .keep, frame: .keep, look: .set(Look(dense: true)))
        XCTAssertEqual(store.settings(in: old)?.look, .reset)
    }
}
