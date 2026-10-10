import XCTest
@testable import ClaudeAX

/// WF216 (#9381): Рик — житель Пимпа. Комплект из ресурсов ложится в `<projectsRoot>/Rick` только там, где папки
/// нет; чужая папка, заданный `mainProject` и сбой копирования ничего на диске не меняют. Всё — на временных каталогах.
final class RickKitWF216Tests: XCTestCase {
    private static let kit = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("resources/rick-kit", isDirectory: true)
    private let fm = FileManager.default

    /// Песочница: `projects` — корень проектов (ещё не создан), `claude.json` — рядом.
    private func sandbox() throws -> (root: URL, config: URL) {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rickkit-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return (base.appendingPathComponent("projects", isDirectory: true), base.appendingPathComponent("claude.json"))
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testKitInResourcesHasRules() throws {
        XCTAssertGreaterThan(try fm.contentsOfDirectory(atPath: Self.kit.path).count, 5)
        for name in ["AGENTS.md", "CLAUDE.md", "README.md", "install.sh", "KIT-SOURCE.txt"] {
            let size = try XCTUnwrap(fm.attributesOfItem(atPath: Self.kit.appendingPathComponent(name).path)[.size] as? Int)
            XCTAssertGreaterThan(size, 100, name)
        }
        XCTAssertTrue(fm.isExecutableFile(atPath: Self.kit.appendingPathComponent("install.sh").path))
    }

    func testNoFolderInstallsKitAndWritesMainProject() throws {
        let (root, config) = try sandbox()
        let outcome = RickKit.install(from: Self.kit, root: root, configURL: config,
                                      configDefaults: ["minWindowWidth": 280])
        let rick = root.appendingPathComponent("Rick", isDirectory: true)
        XCTAssertEqual(outcome, .installed(rick))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path), ["Rick"], "черновика рядом не осталось")
        for name in ["AGENTS.md", "CLAUDE.md", "tools/term.py"] {
            XCTAssertEqual(try Data(contentsOf: rick.appendingPathComponent(name)),
                           try Data(contentsOf: Self.kit.appendingPathComponent(name)), name)
        }
        XCTAssertTrue(fm.isExecutableFile(atPath: rick.appendingPathComponent("install.sh").path), "бит запуска доехал")
        // claude.json не было — начат умолчаниями патчера, главный проект — Рик.
        XCTAssertEqual(try json(config)["mainProject"] as? String, "Rick")
        XCTAssertEqual(try json(config)["minWindowWidth"] as? Int, 280)
    }

    func testMainProjectJoinsExistingConfigKeys() throws {
        let (root, config) = try sandbox()
        try Data(#"{"projectsRoot":"/somewhere/else","sidePadding":7}"#.utf8).write(to: config)
        XCTAssertEqual(RickKit.install(from: Self.kit, root: root, configURL: config, configDefaults: ["minWindowWidth": 280]),
                       .installed(root.appendingPathComponent("Rick", isDirectory: true)))
        let after = try json(config)
        XCTAssertEqual(after["mainProject"] as? String, "Rick")
        XCTAssertEqual(after["projectsRoot"] as? String, "/somewhere/else")
        XCTAssertEqual(after["sidePadding"] as? Int, 7)
        XCTAssertNil(after["minWindowWidth"], "готовый файл умолчаниями не дополняем")
    }

    func testExistingFolderIsNotTouched() throws {
        let (root, config) = try sandbox()
        let rick = root.appendingPathComponent("Rick", isDirectory: true)
        try fm.createDirectory(at: rick, withIntermediateDirectories: true)
        try Data("моё".utf8).write(to: rick.appendingPathComponent("NOW.md"))
        XCTAssertEqual(RickKit.install(from: Self.kit, root: root, configURL: config), .exists(rick))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: rick.path), ["NOW.md"])
        XCTAssertEqual(try String(contentsOf: rick.appendingPathComponent("NOW.md"), encoding: .utf8), "моё")
        XCTAssertFalse(fm.fileExists(atPath: config.path), "папка чужая — mainProject не пишем")

        // Битая ссылка с именем Rick — тоже чужое.
        try fm.removeItem(at: rick)
        try fm.createSymbolicLink(atPath: rick.path, withDestinationPath: "/nope/\(UUID().uuidString)")
        XCTAssertEqual(RickKit.install(from: Self.kit, root: root, configURL: config), .exists(rick))
        XCTAssertFalse(fm.fileExists(atPath: config.path))
    }

    func testSetMainProjectAndBrokenConfigStayByteForByte() throws {
        for body in [#"{"mainProject":"Boss","windowGap":9}"#, "{ не json"] {
            let (root, config) = try sandbox()
            try Data(body.utf8).write(to: config)
            XCTAssertEqual(RickKit.install(from: Self.kit, root: root, configURL: config, configDefaults: ["minWindowWidth": 280]),
                           .installed(root.appendingPathComponent("Rick", isDirectory: true)), body)
            XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), body)
        }
    }

    func testFailureMidCopyLeavesNoFolderAndSameConfig() throws {
        struct Boom: Error {}
        let halfCopy: (URL, URL) throws -> Void = { source, draft in
            try FileManager.default.createDirectory(at: draft, withIntermediateDirectories: false)
            try FileManager.default.copyItem(at: source.appendingPathComponent("AGENTS.md"),
                                             to: draft.appendingPathComponent("AGENTS.md"))
            throw Boom()
        }
        // Корня проектов не было — после отката его снова нет.
        let (root, config) = try sandbox()
        let body = #"{"sidePadding":7}"#
        try Data(body.utf8).write(to: config)
        guard case .failed(let why) = RickKit.install(from: Self.kit, root: root, configURL: config, copy: halfCopy) else {
            return XCTFail("сбой копирования должен вернуть failed")
        }
        XCTAssertTrue(why.contains("не получилось записать"), why)
        XCTAssertFalse(fm.fileExists(atPath: root.path))
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), body)

        // Корень был и в нём чужой проект — он на месте, ни Rick, ни черновика.
        try fm.createDirectory(at: root.appendingPathComponent("Shop", isDirectory: true), withIntermediateDirectories: true)
        XCTAssertNotEqual(RickKit.install(from: Self.kit, root: root, configURL: config, copy: halfCopy),
                          .installed(root.appendingPathComponent("Rick", isDirectory: true)))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path), ["Shop"])
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), body)

        // Комплекта в сборке нет — то же: ничего не создано.
        let (empty, emptyConfig) = try sandbox()
        guard case .failed = RickKit.install(from: nil, root: empty, configURL: emptyConfig) else { return XCTFail() }
        XCTAssertFalse(fm.fileExists(atPath: empty.path))
        XCTAssertFalse(fm.fileExists(atPath: emptyConfig.path))
    }

    func testOnlyNewInstallInstallsByItself() throws {
        let (root, config) = try sandbox()
        let install = { RickKit.install(from: Self.kit, root: root, configURL: config) }
        // Пимп уже ставили: настройки не пусты или есть installed.json — сам ничего не ставит.
        XCTAssertNil(RickKit.firstRun(values: ["setupDone": true], installed: nil, install: install))
        XCTAssertNil(RickKit.firstRun(values: [:], installed: Data("{}".utf8), install: install))
        XCTAssertFalse(fm.fileExists(atPath: root.path))
        XCTAssertFalse(fm.fileExists(atPath: config.path))
        // Новая установка — ставит.
        XCTAssertEqual(RickKit.firstRun(values: [:], installed: nil, install: install),
                       .installed(root.appendingPathComponent("Rick", isDirectory: true)))
    }
}
