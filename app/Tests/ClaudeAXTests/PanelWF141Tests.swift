import XCTest
@testable import ClaudeAX

/// WF141 (#9114, #9115, Рик «новые — наверх»): «Цвет Claude» свёрнут по умолчанию, «Живой фон» первой плиткой,
/// немного крупных плиток; плитки Workflow и `/digest` — свежие наверх, у проекта сводки поле `at`.
final class PanelWF141Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: «Цвет Claude»

    func testColorsCollapsedByDefaultAndRemembered() throws {
        let suite = "wf141-colors-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(PanelColorTiles.isOpen(defaults), "нет ключа — свёрнут")
        PanelColorTiles.setOpen(true, defaults)
        XCTAssertTrue(PanelColorTiles.isOpen(defaults))
        PanelColorTiles.setOpen(false, defaults)
        XCTAssertFalse(PanelColorTiles.isOpen(defaults))
        XCTAssertNil(defaults.object(forKey: PanelColorTiles.openKey), "свёрнут — ключа нет, как умолчание")
    }

    func testPanelThemesAndLiveThemeExistInCatalog() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("claude-patch")
        let ids = Set(ThemeCatalog.load(directory: root).map { $0.id })
        XCTAssertFalse(ids.isEmpty)
        for id in ClaudeAXController.panelThemeIDs {
            XCTAssertTrue(ids.contains(id), "темы \(id) нет в каталоге")
        }
    }

    // MARK: плитки Workflow — свежие наверх

    private func project(_ name: String, updated: Date?) -> PanelProject {
        let status = PanelProjects.parse("# \(name)\n1️⃣ Workflow 💭 идёт\n- о чём: x\n")
        return PanelProject(folder: "/p/\(name)", name: name, marker: "", isMain: false, updated: updated, now: "",
                            words: [], note: "", waits: false,
                            running: status.workflows.filter { $0.state == .running },
                            finished: [], planned: [], workflows: status.workflows, marathon: "")
    }

    func testTilesFreshFirstWithinGroup() {
        let old = project("Old", updated: now.addingTimeInterval(-3600))
        let fresh = project("Fresh", updated: now.addingTimeInterval(-60))
        let unknown = project("Unknown", updated: nil)
        let snapshot = PanelSnapshot(waiting: [], working: [unknown, old, fresh], others: [], mainEntry: nil, mainName: nil)
        let groups = PanelTiles.groups(snapshot, now: now)
        XCTAssertEqual(groups.first?.tiles.map { $0.name }, ["Fresh", "Old", "Unknown"])
    }

    // MARK: `/digest` — поле `at`, свежие наверх

    func testDigestAtIsFresherOfStatusAndRunFile() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("digest-wf141-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func make(_ name: String, status age: TimeInterval, run: TimeInterval? = nil) throws {
            let docs = root.appendingPathComponent(name).appendingPathComponent("docs")
            try fm.createDirectory(at: docs, withIntermediateDirectories: true)
            let file = docs.appendingPathComponent("status.md")
            try "# \(name)\nЖдёт Элвиса: «да»\n".write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
            if let run = run {
                let runFile = docs.appendingPathComponent("run-wf1-2026-10-08.json")
                try "{}".write(to: runFile, atomically: true, encoding: .utf8)
                try fm.setAttributes([.modificationDate: now.addingTimeInterval(-run)], ofItemAtPath: runFile.path)
            }
        }
        try make("Alpha", status: 600)
        try make("Bravo", status: 3600, run: 30)
        try make("Charlie", status: 120, run: 7200)
        let items = try XCTUnwrap(ProjectsDigest.projects(root: root, now: now, settings: { _ in nil }))
        XCTAssertEqual(items.map { $0.group }, ["ждут", "ждут", "ждут"])
        XCTAssertEqual(items.map { $0.name }, ["Bravo", "Charlie", "Alpha"], "свежие наверх")
        let iso = ISO8601DateFormatter()
        let at = Dictionary(uniqueKeysWithValues: items.map { ($0.name, iso.date(from: $0.at)) })
        XCTAssertEqual(at["Bravo"]??.timeIntervalSince1970, now.addingTimeInterval(-30).timeIntervalSince1970,
                       "run-файл свежее сводки")
        XCTAssertEqual(at["Charlie"]??.timeIntervalSince1970, now.addingTimeInterval(-120).timeIntervalSince1970,
                       "сводка свежее run-файла")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: ProjectsDigest.json(ProjectsDigest.body(items, now: now))) as? [String: Any])
        let first = try XCTUnwrap((json["projects"] as? [[String: Any]])?.first)
        XCTAssertNotNil(iso.date(from: first["at"] as? String ?? ""))
    }
}
