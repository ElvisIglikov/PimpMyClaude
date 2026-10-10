import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Гейт 2 WF108: исход автовозврата снимка для `restart-claude` и склад чатов без явного корня.
final class Gate2WF108Tests: XCTestCase {
    private static func date(_ text: String) -> Date { PimpChannel.date(text)! }

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gate2-wf108-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private static let frame = CGRect(x: 0, y: 34, width: 700, height: 859)

    private func keeper(in box: URL, claude: @escaping () -> (pid: pid_t, launch: Date?, version: String)?,
                        windows: @escaping () -> [SnapshotWindow]) -> (WindowSnapshotKeeper, WindowSnapshotStore) {
        let store = WindowSnapshotStore(url: box.appendingPathComponent(WindowSnapshotStore.fileName))
        let keeper = WindowSnapshotKeeper(store: store)
        keeper.claude = claude
        keeper.windows = windows
        keeper.startRestore = { _ in true }
        return (keeper, store)
    }

    func testKeeperOutcomeGaveUpNamesSnapshotChats() {
        let box = makeTemp()
        var claude: (pid: pid_t, launch: Date?, version: String)? = (pid: 1, launch: Self.date("2026-09-30T03:00:00Z"), version: "1")
        let (keeper, store) = keeper(in: box, claude: { claude }, windows: { [] })
        store.save(WindowSnapshot(at: Self.date("2026-09-30T03:20:01Z"), claude: "1", windows: [
            SnapshotWindow(chat: LayoutsStore.mainChat, folder: "", title: "Claude", frame: Self.frame, screen: ""),
            SnapshotWindow(chat: "local_a", folder: "", title: "Чат А", frame: Self.frame, screen: ""),
        ]))
        // Старый Claude: снимок ведётся, возвращать нечего.
        keeper.tick(at: Self.date("2026-09-30T03:20:02Z"))
        XCTAssertEqual(keeper.outcome, .notNeeded)
        // Перезапуск: заморозка → ещё впереди.
        keeper.freeze(at: Self.date("2026-09-30T03:20:03Z"))
        XCTAssertEqual(keeper.outcome, .pending)
        // Новый Claude, окна у него так и не появились.
        claude = (pid: 2, launch: Self.date("2026-09-30T03:20:30Z"), version: "1")
        keeper.tick(at: Self.date("2026-09-30T03:20:31Z"))
        XCTAssertEqual(keeper.phase, .waiting)
        XCTAssertEqual(keeper.outcome, .pending)
        keeper.tick(at: Self.date("2026-09-30T03:22:30Z"))
        XCTAssertEqual(keeper.outcome, .pending, "120 с ещё не вышли")
        keeper.tick(at: Self.date("2026-09-30T03:22:32Z"))
        XCTAssertEqual(keeper.phase, .keeping)
        XCTAssertEqual(keeper.outcome, .gaveUp(skipped: ["Чат А"]), "сдался — не «нечего возвращать»")
        // Следующий Claude начинает с чистого листа.
        claude = (pid: 3, launch: Self.date("2026-09-30T02:00:00Z"), version: "1")
        keeper.tick(at: Self.date("2026-09-30T03:30:00Z"))
        XCTAssertEqual(keeper.outcome, .notNeeded)
    }

    func testChatArchiveWithoutExplicitRootStaysInFallback() {
        let box = makeTemp()
        let fallback = box.appendingPathComponent("MyClaude", isDirectory: true)
        let projects = box.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        XCTAssertEqual(ChatArchive.storeFolder(projectsRoot: nil, fallback: fallback).path,
                       fallback.appendingPathComponent(ChatArchive.storeFolderName).path,
                       "ключа projectsRoot нет — склад там же, где был (Application Support)")
        XCTAssertEqual(ChatArchive.storeFolder(projectsRoot: projects, fallback: fallback).path,
                       projects.appendingPathComponent(ChatArchive.keepFolderName)
                        .appendingPathComponent(ChatArchive.storeFolderName).path)
    }
}
