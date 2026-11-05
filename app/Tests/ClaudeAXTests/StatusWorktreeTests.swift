import XCTest
@testable import ClaudeAX

/// #9519: Workflow проекта идут в рабочем дереве git (`VkusnoffKz-iiko1019`), сводка главной папки стоит — панель,
/// `/digest` и сводка проектов берут самую свежую сводку из папки и её деревьев; дерево проектом не становится.
final class StatusWorktreeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("status-worktree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func status(_ folder: URL, _ text: String, at date: Date) throws {
        let dir = folder.appendingPathComponent("audit", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("status.md")
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    func testFreshestStatusOfFolderAndItsWorktrees() throws {
        let fm = FileManager.default
        let main = root.appendingPathComponent("Cafe", isDirectory: true)
        let tree = root.appendingPathComponent("Cafe-iiko1019", isDirectory: true)
        let now = Date()
        try status(main, "# 🟠Cafe\n\n1️⃣ Workflow ✅ готово\n- о чём: старое\n", at: now.addingTimeInterval(-3600))
        try status(tree, "# 🟠Cafe\n\n2️⃣ Workflow ⏳ идёт\n- о чём: меню кафе\n- шаги 1 из 4\n", at: now)
        let link = main.appendingPathComponent(".git/worktrees/iiko", isDirectory: true)
        try fm.createDirectory(at: link, withIntermediateDirectories: true)
        try Data("\(tree.path)/.git\n".utf8).write(to: link.appendingPathComponent("gitdir"))
        try Data("gitdir: \(link.path)\n".utf8).write(to: tree.appendingPathComponent(".git"))

        XCTAssertEqual(PanelProjects.statusFile(in: main, fileManager: fm)?.standardizedFileURL.path,
                       tree.appendingPathComponent("audit/status.md").standardizedFileURL.path)
        let snapshot = PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: now, fileManager: fm)
        XCTAssertEqual(snapshot.working.count, 1, "Workflow дерева не виден у главной папки")
        XCTAssertEqual(snapshot.working.first?.folder, main.standardizedFileURL.path, "дерево стало проектом")

        // Дерево старее главной — главная.
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)],
                                              ofItemAtPath: tree.appendingPathComponent("audit/status.md").path)
        XCTAssertEqual(PanelProjects.statusFile(in: main, fileManager: fm)?.standardizedFileURL.path,
                       main.appendingPathComponent("audit/status.md").standardizedFileURL.path)
    }
}
