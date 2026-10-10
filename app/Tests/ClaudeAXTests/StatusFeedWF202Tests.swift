import AppKit
import XCTest
@testable import ClaudeAX

/// WF202: сводка проектов без рабочих копий и с потолком 128 КБ (#9159: в карточке Workflow почти не было сведений);
/// карта тем осталась при своих 32 КБ; «Живой фон» и «🎨 Схема ▸» ушли из «🧪 Опыты ▸» окна (слово Элвиса 02:50).
final class StatusFeedWF202Tests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("statusfeed-wf202-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private enum Git { case none, directory, file }

    private func project(_ name: String, git: Git = .directory, folder: String = "docs") throws {
        let url = root.appendingPathComponent(name)
        try fm.createDirectory(at: url.appendingPathComponent(folder), withIntermediateDirectories: true)
        switch git {
        case .none: break
        case .directory: try fm.createDirectory(at: url.appendingPathComponent(".git"), withIntermediateDirectories: true)
        case .file: try "gitdir: /elsewhere/.git/worktrees/x".write(to: url.appendingPathComponent(".git"),
                                                                    atomically: true, encoding: .utf8)
        }
        try "# ⚪\(name)\n1️⃣ Workflow 💭 идёт\n- о чём: \(name)\n- кодинг · 1 агент · Opus 5.5 high 💭\n"
            .write(to: url.appendingPathComponent("\(folder)/status.md"), atomically: true, encoding: .utf8)
    }

    // MARK: рабочие копии

    func testScanSkipsWorkingCopiesAndKeepsMainProjects() throws {
        // Основные: каталог .git, без git вовсе, сводка в audit/, «-» в имени без хвоста копии.
        try project("PimpMyClaude")
        try project("SkilZZZ", git: .none)
        try project("VkusnoffKz", folder: "audit")
        try project("TrelvisCom-old")
        try project("Rick-public")
        try project("Wfmaster")
        // Копии: хвост имени (даже с каталогом .git или без git) и git worktree с любым именем.
        try project("PimpMyClaude-wf199", git: .none)
        try project("PimpMyClaude-WF7")
        try project("Rick-rev", git: .none)
        try project("Rick-rev2")
        try project("Dictator-inst3", git: .none)
        try project("VkusnoffKz-bcart", git: .file, folder: "audit")
        try project("Rick-voice", git: .file)

        let names = Set(StatusFeed.scan(root: root).map { $0.name })
        XCTAssertEqual(names, ["PimpMyClaude", "SkilZZZ", "VkusnoffKz", "TrelvisCom-old", "Rick-public", "Wfmaster"])
    }

    func testWorkingCopyRuleIsSharedWithPanelAndDigest() throws {
        try project("Rick")
        try project("Rick-rev", git: .none)
        try project("PimpMyClaude-wf201", git: .none)
        try project("Rick-voice", git: .file)
        XCTAssertFalse(StatusFeed.isWorkingCopy(name: "Rick", at: root.appendingPathComponent("Rick")))
        XCTAssertFalse(StatusFeed.isWorkingCopy(name: "Rick-revolution", at: root.appendingPathComponent("x")),
                       "хвост — только целиком в конце имени")
        XCTAssertFalse(StatusFeed.isWorkingCopy(name: "wf12", at: root.appendingPathComponent("x")),
                       "без дефиса это не хвост копии")
        XCTAssertTrue(StatusFeed.isWorkingCopy(name: "Rick-inst12", at: root.appendingPathComponent("x")))

        let store = ProjectSettingsStore(registryURL: root.appendingPathComponent("no-registry.json"))
        let digest = ProjectsDigest.projects(root: root, now: Date(), settings: { store.settings(in: $0) }) ?? []
        XCTAssertEqual(digest.map { $0.name }, ["Rick"], "/digest видит те же проекты, что сводка")

        let copy = root.appendingPathComponent("PimpMyClaude-wf201")
        let snapshot = PanelProjects.snapshot(root: root, recent: [(folder: copy, name: "PimpMyClaude-wf201")],
                                              mainEntry: nil, now: Date())
        let panel = (snapshot.waiting + snapshot.working + snapshot.others).map { URL(fileURLWithPath: $0.folder).lastPathComponent }
        XCTAssertEqual(panel, ["Rick"], "панель «Проекты» — тоже без копий, даже недавних")
    }

    // MARK: потолки

    func testStatusCeilingIs128KAndThemeMapStays32K() {
        XCTAssertEqual(StatusFeed.totalLimit, 128 * 1024, "столько принимает страница с WF201 (STATUS_MAX_TOTAL)")
        XCTAssertEqual(WindowThemeStore.bodyLimit, 32 * 1024, "карта тем свой потолок не меняла")

        // 30 проектов по ~5,6 КБ: при 32 КБ доезжало бы пять, при 128 КБ — двадцать с лишним.
        let text = String(repeating: "- проверка · судья · Opus 5.5 xhigh\n", count: 100)
        let many = (1...30).map { StatusProject(name: "Проект \($0)", text: StatusFeed.slice(text)) }
        let capped = StatusFeed.cap(many)
        XCTAssertLessThanOrEqual(StatusFeed.payloadSize(capped), 128 * 1024)
        XCTAssertGreaterThan(StatusFeed.payloadSize(capped), 96 * 1024, "потолок использован, а не 32 КБ")
        XCTAssertEqual(capped.map { $0.name }, many.prefix(capped.count).map { $0.name })
        XCTAssertLessThan(capped.count, many.count)
    }

    func testStatusCommandOf128KGoesThroughQueueOnceAndYieldsToMenu() throws {
        let file = root.appendingPathComponent("command.json")
        var pending: [() -> Void] = []
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let channel = CommandChannel(path: file, now: { clock }, schedule: { _, block in pending.append(block) })
        let text = String(repeating: "- кодинг · 2 агента · Opus 5.5 high\n", count: 120)
        let projects = StatusFeed.cap((1...40).map { StatusProject(name: "P\($0)", text: StatusFeed.slice(text)) })
        var results: [Bool] = []
        channel.write(action: CommandChannel.statusAction, fields: StatusFeed.fields(projects),
                      priority: .normal) { results.append($0) }
        XCTAssertEqual(results, [true], "пустая очередь — сводка пишется сразу")
        let body = try Data(contentsOf: file)
        XCTAssertGreaterThan(body.count, 96 * 1024)
        XCTAssertLessThanOrEqual(body.count, 128 * 1024)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((json["projects"] as? [Any])?.count, projects.count, "128 КБ — целый JSON")

        // Команда меню, а следом сводка: меню первым, сводка ждёт; новая команда меню её вытесняет.
        clock.addTimeInterval(0.1)
        _ = channel.write(action: "theme")
        channel.write(action: CommandChannel.statusAction, fields: StatusFeed.fields(projects),
                      priority: .normal) { results.append($0) }
        _ = channel.write(action: "font")
        XCTAssertEqual(results, [true, false], "сводку вытеснила команда меню")
        clock.addTimeInterval(1)
        pending.forEach { $0() }
    }

    // MARK: меню окна

    func testLiveBackgroundAndSchemeOnlyInAllWindowsLab() throws {
        var config = MinimizeMenu.MenuConfig()
        config.windowLook = Look(aurora: true)
        XCTAssertEqual(MinimizeMenu.lookItems(config, scope: MenuModel.themeScopeWindow).map { $0.title },
                       [MenuModel.lookDenseTitle], "у окна «Опытов» нет — с WF220 они опустели")
        let all = try XCTUnwrap(MinimizeMenu.lookItems(config, scope: MenuModel.themeScopeAll)
            .first { $0.title == MenuModel.lookLabTitle }?.submenu)
        XCTAssertEqual(all.items.map { $0.title },
                       [MenuModel.lookAuroraTitle, MenuModel.lookSchemeTitle])

        // То же в собранном меню: верхний уровень — окно, «⋯ Ещё ▸ › 🖥 Всем окнам ▸» — все окна.
        let menu = MinimizeMenu.build(config: config)
        func titles(_ menu: NSMenu) -> [String] {
            menu.items.flatMap { [$0.title] + ($0.submenu.map(titles) ?? []) }
        }
        XCTAssertFalse(menu.items.contains { $0.title == MenuModel.lookLabTitle })
        XCTAssertFalse(menu.items.contains { $0.title == MenuModel.lookAuroraTitle })
        let more = try XCTUnwrap(menu.items.last?.submenu)
        let allWindows = try XCTUnwrap(more.items.last { $0.title == MenuModel.allWindowsTitle }?.submenu)
        let allLab = try XCTUnwrap(allWindows.items.first { $0.title == MenuModel.lookLabTitle }?.submenu)
        XCTAssertTrue(titles(allLab).contains(MenuModel.lookAuroraTitle))
        XCTAssertTrue(titles(allLab).contains(MenuModel.lookSchemeTitle))
    }
}
