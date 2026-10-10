import AppKit
import XCTest
@testable import ClaudeAX

/// «📦 Архив чатов» (#7729, план WF94 Б2). Всё во временных каталогах: настоящий `~/.claude`
/// и склад Элвиса тесты не читают и не пишут.
final class ChatArchiveTests: XCTestCase {
    private var root: URL!
    private var projects: URL!
    private var desktop: URL!
    private var store: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chat-archive-\(UUID().uuidString)", isDirectory: true)
        projects = root.appendingPathComponent("claude/projects", isDirectory: true)
        desktop = root.appendingPathComponent("Claude/claude-code-sessions", isDirectory: true)
        store = root.appendingPathComponent("Проекты/_Не удалять/Склад чатов Claude", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Файл без прав из теста «.partial» — вернуть права, иначе не удалится.
        if let walker = FileManager.default.enumerator(atPath: root.path) {
            for case let path as String in walker {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                       ofItemAtPath: root.appendingPathComponent(path).path)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// Два чата в двух проектах и субагент первого — внутри его папки.
    private func makeFixture() throws {
        let one = projects.appendingPathComponent("-Users-x-Alpha", isDirectory: true)
        let two = projects.appendingPathComponent("-Users-x-Beta", isDirectory: true)
        let sub = one.appendingPathComponent("aaaa/subagents", isDirectory: true)
        for dir in [one, two, sub, desktop!] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let chatA = [
            line(["type": "user", "cwd": "/Users/x/Alpha", "timestamp": "2026-09-20T10:00:00.000Z",
                  "message": ["role": "user", "content": "Сделай <b>кнопку</b> архива"]]),
            line(["type": "assistant", "cwd": "/Users/x/Alpha", "timestamp": "2026-09-20T10:01:00.000Z",
                  "message": ["role": "assistant", "content": [["type": "text", "text": "ок"]]]]),
            line(["type": "user", "cwd": "/Users/x/Alpha", "timestamp": "2026-09-20T10:02:00.000Z",
                  "toolUseResult": "x", "message": ["role": "user", "content": [["type": "tool_result"]]]]),
            line(["type": "custom-title", "customTitle": "Архив & чаты", "sessionId": "aaaa"]),
            line(["type": "assistant", "cwd": "/Users/x/Alpha", "timestamp": "2026-09-21T09:30:00Z",
                  "message": ["role": "assistant", "content": [["type": "text", "text": "готово"]]]]),
        ]
        try (chatA.joined(separator: "\n") + "\n").write(to: one.appendingPathComponent("aaaa.jsonl"),
                                                         atomically: true, encoding: .utf8)
        let chatB = [
            line(["type": "user", "cwd": "/Users/x/Beta", "timestamp": "2026-09-22T08:00:00.000Z",
                  "message": ["role": "user", "content": [["type": "text", "text": "Привет, Бета"]]]]),
        ]
        try chatB.joined(separator: "\n").write(to: two.appendingPathComponent("bbbb.jsonl"),
                                                atomically: true, encoding: .utf8)
        try line(["type": "user", "timestamp": "2026-09-20T10:05:00.000Z",
                  "message": ["role": "user", "content": "субагент"]])
            .write(to: sub.appendingPathComponent("agent-1.jsonl"), atomically: true, encoding: .utf8)
        try "{}".write(to: desktop.appendingPathComponent("meta.json"), atomically: true, encoding: .utf8)
    }

    private func archive(store: URL? = nil, free: Int64? = nil, cloud: Bool? = nil,
                         date: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> ChatArchive {
        let sources = [
            ChatArchive.Source(url: projects, name: "Claude Code/projects", chats: true),
            ChatArchive.Source(url: desktop, name: "Claude Desktop/claude-code-sessions"),
            ChatArchive.Source(url: root.appendingPathComponent("нет такой"), name: "Claude Desktop/missing"),
        ]
        return ChatArchive(sources: sources, store: store ?? self.store, now: { date },
                           freeSpace: { _ in free ?? Int64.max },
                           isCloud: { url in cloud ?? ChatArchive.isInCloud(url) })
    }

    private func storeLeftovers() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: store.path)) ?? [])
            .filter { $0.hasSuffix(".partial") || $0.hasSuffix(".staging") }
    }

    // MARK: - сборка

    func testArchivesTwoChatsWithSubagentInsideAndTableOfContents() throws {
        try makeFixture()
        let summary = try archive().make()
        XCTAssertEqual(summary.chats, 2, "субагент — часть родительского чата")
        XCTAssertEqual(summary.storeCount, 1)
        XCTAssertGreaterThan(summary.bytes, 0)
        XCTAssertEqual(summary.storeBytes, summary.bytes)
        XCTAssertTrue(summary.archive.lastPathComponent.hasPrefix("Claude-чаты-"))
        XCTAssertTrue(storeLeftovers().isEmpty)

        let attrs = try FileManager.default.attributesOfItem(atPath: summary.archive.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: store.path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        // Распаковка тем же ditto — внутри оглавление, переписки, субагент и метаданные.
        let out = root.appendingPathComponent("out", isDirectory: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", summary.archive.path, out.path]
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("Claude Code/projects/-Users-x-Alpha/aaaa.jsonl").path))
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent(
            "Claude Code/projects/-Users-x-Alpha/aaaa/subagents/agent-1.jsonl").path))
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("Claude Desktop/claude-code-sessions/meta.json").path))
        let toc = try String(contentsOf: out.appendingPathComponent("ОГЛАВЛЕНИЕ.html"), encoding: .utf8)
        XCTAssertTrue(toc.contains("Архив &amp; чаты"), "своё имя чата, экранированное")
        XCTAssertTrue(toc.contains("Привет, Бета"), "без имени — первая реплика человека")
        XCTAssertTrue(toc.contains("<td>Alpha</td>") && toc.contains("<td>Beta</td>"))
        XCTAssertTrue(toc.contains("Claude Code/projects/-Users-x-Alpha/aaaa.jsonl"))
        XCTAssertTrue(toc.contains("2 чата"))
        XCTAssertFalse(toc.contains("http"), "без внешних ресурсов")
        // Свежий чат (Beta) — первой строкой.
        XCTAssertLessThan(try XCTUnwrap(toc.range(of: "Привет, Бета")).lowerBound,
                          try XCTUnwrap(toc.range(of: "Архив &amp; чаты")).lowerBound)
    }

    func testEntryCountsMessagesAndDates() throws {
        try makeFixture()
        let entry = ChatArchive.entry(for: projects.appendingPathComponent("-Users-x-Alpha/aaaa.jsonl"))
        XCTAssertEqual(entry.title, "Архив & чаты")
        XCTAssertEqual(entry.project, "Alpha")
        XCTAssertEqual(entry.messages, 3, "ответ инструмента — не сообщение")
        XCTAssertEqual(entry.first, ISO8601DateFormatter().date(from: "2026-09-20T10:00:00Z"))
        XCTAssertEqual(entry.last, ISO8601DateFormatter().date(from: "2026-09-21T09:30:00Z"))
    }

    func testSecondArchiveInSameMinuteDoesNotOverwrite() throws {
        try makeFixture()
        let first = try archive().make()
        let second = try archive().make()
        XCTAssertNotEqual(first.archive, second.archive)
        XCTAssertEqual(second.storeCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.archive.path))
    }

    // MARK: - имя и склад

    func testFileNameFollowsLocalDate() {
        let date = ISO8601DateFormatter().date(from: "2026-09-26T01:07:00Z")!
        XCTAssertEqual(ChatArchive.fileName(for: date, timeZone: TimeZone(identifier: "Asia/Almaty")!),
                       "Claude-чаты-2026-09-26-0607.zip")
    }

    func testStoreFolderUsesProjectsRootOrFallback() throws {
        let projectsRoot = root.appendingPathComponent("Проекты", isDirectory: true)
        let fallback = root.appendingPathComponent("MyClaude", isDirectory: true)
        XCTAssertEqual(ChatArchive.storeFolder(projectsRoot: projectsRoot, fallback: fallback).path,
                       fallback.appendingPathComponent("Склад чатов Claude").path, "папки проектов нет — запасной")
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        XCTAssertEqual(ChatArchive.storeFolder(projectsRoot: projectsRoot, fallback: fallback).path,
                       projectsRoot.appendingPathComponent("_Не удалять/Склад чатов Claude").path)
    }

    // MARK: - отказы

    func testICloudStoreRefuses() throws {
        try makeFixture()
        let cloud = root.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Склад", isDirectory: true)
        XCTAssertTrue(ChatArchive.isInCloud(cloud))
        XCTAssertFalse(ChatArchive.isInCloud(store))
        XCTAssertThrowsError(try archive(store: cloud).make()) { error in
            XCTAssertEqual(error as? ChatArchive.Failure, .inCloud(cloud.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.path), "в облако ничего не пишем")
        XCTAssertThrowsError(try archive(cloud: true).make()) { error in
            guard case .inCloud = error as? ChatArchive.Failure else { return XCTFail("\(error)") }
        }
    }

    func testLowSpaceRefusesHonestly() throws {
        try makeFixture()
        XCTAssertThrowsError(try archive(free: 1024).make()) { error in
            guard case .noSpace(let needed, let free) = error as? ChatArchive.Failure else { return XCTFail("\(error)") }
            XCTAssertEqual(free, 1024)
            XCTAssertGreaterThan(needed, 50 << 20)
            XCTAssertTrue((error as! ChatArchive.Failure).notice.contains("Мало места"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
    }

    func testEmptySourceRefuses() throws {
        XCTAssertThrowsError(try archive().make()) { XCTAssertEqual($0 as? ChatArchive.Failure, .emptySource) }
        try FileManager.default.removeItem(at: projects)
        XCTAssertThrowsError(try archive().make()) { XCTAssertEqual($0 as? ChatArchive.Failure, .emptySource) }
    }

    func testFailureLeavesNoPartial() throws {
        try makeFixture()
        // Нечитаемый файл — копия источника падает посреди сборки.
        let locked = projects.appendingPathComponent("-Users-x-Beta/locked.txt")
        try "x".write(to: locked, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        XCTAssertThrowsError(try archive().make()) { error in
            guard case .failed = error as? ChatArchive.Failure else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(storeLeftovers().isEmpty)
        let zips = ((try? FileManager.default.contentsOfDirectory(atPath: store.path)) ?? []).filter { $0.hasSuffix(".zip") }
        XCTAssertTrue(zips.isEmpty)
    }

    // MARK: - фон и слова

    func testSecondClickWhileBusyDoesNothing() throws {
        try makeFixture()
        let archiver = archive()
        let done = expectation(description: "готово")
        XCTAssertTrue(archiver.start { result in
            if case .failure(let failure) = result { XCTFail("\(failure)") }
            done.fulfill()
        })
        XCTAssertTrue(archiver.isBusy)
        XCTAssertFalse(archiver.start { _ in XCTFail("второй клик не должен собирать") })
        wait(for: [done], timeout: 30)
        XCTAssertFalse(archiver.isBusy)
    }

    func testNoticeWords() {
        let summary = ChatArchive.Summary(archive: URL(fileURLWithPath: "/tmp/a.zip"), chats: 21,
                                          bytes: 3 * 1_048_576 / 2, storeCount: 3, storeBytes: 300 * 1_048_576)
        XCTAssertEqual(summary.notice, "💾 Бэкап готов: 21 чат, 1,5 МБ · на складе 3 бэкапа, 300 МБ")
        XCTAssertEqual(ChatArchive.chatsWord(12), "12 чатов")
        XCTAssertEqual(ChatArchive.archivesWord(5), "5 бэкапов")
    }

    func testMenuItemSitsUnderRestoreWindows() throws {
        var config = MinimizeMenu.MenuConfig()
        var asked = 0
        config.archiveChats = { asked += 1 }
        let menu = MinimizeMenu.build(config: config)
        let more = try XCTUnwrap(menu.items.first { $0.title == MenuModel.moreTitle }?.submenu)
        let titles = more.items.map { $0.title }
        let restore = try XCTUnwrap(titles.firstIndex(of: MenuModel.restoreWindowsTitle))
        XCTAssertEqual(titles[restore + 1], MenuModel.archiveChatsTitle)
        let item = more.items[restore + 1]
        let target = try XCTUnwrap(item.target as? NSObject)
        target.perform(try XCTUnwrap(item.action))
        XCTAssertEqual(asked, 1)
    }
}
