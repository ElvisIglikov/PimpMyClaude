import XCTest
@testable import ClaudeAX
import Patcher

/// Папка MyClaude со стороны ClaudeAX (ревизия WF247, С5б; аудит 10.10, В2, быстрая часть): всё, что Пимп пишет
/// туда сам, ложится файлом 0600 в свежую папку 0700; файл вида в папке проекта — прежние 0644; блок claude.css и
/// умолчания claude.json — одной копией с патчером.
final class SupportFilesWF248Tests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("wf248-support-\(UUID().uuidString)",
                                                                               isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func mode(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
    }

    func testLiveWritersMakeFreshFolder0700AndFiles0600() throws {
        let support = scratch.appendingPathComponent("MyClaude", isDirectory: true)
        let command = support.appendingPathComponent(SupportFiles.commandFileName)
        XCTAssertTrue(CommandChannel.writeAtomic(command, "{}"))
        XCTAssertEqual(mode(support), 0o700)
        XCTAssertEqual(mode(command), 0o600)

        // Пункт «🚀 Workflow» раскладывает комплект той же копией, что патчер.
        let kit = scratch.appendingPathComponent("kit", isDirectory: true)
        try FileManager.default.createDirectory(at: kit, withIntermediateDirectories: true)
        for name in WorkflowKit.files { try Data(name.utf8).write(to: kit.appendingPathComponent(name)) }
        let workflow = support.appendingPathComponent(WorkflowKit.installedFolderName, isDirectory: true)
        XCTAssertTrue(WorkflowKit.install(from: kit, to: workflow))
        XCTAssertEqual(mode(workflow), 0o700)
        for name in WorkflowKit.files {
            XCTAssertEqual(mode(workflow.appendingPathComponent(name)), 0o600, name)
            XCTAssertEqual(try Data(contentsOf: workflow.appendingPathComponent(name)), Data(name.utf8))
        }
        // Комплекта нет целиком — ничего не кладём и честно говорим «не вышло».
        try FileManager.default.removeItem(at: kit.appendingPathComponent(WorkflowKit.kickoffName))
        XCTAssertFalse(WorkflowKit.install(from: kit, to: workflow))

        // Поручение «Анализ памяти» — в своей подпапке.
        let prompts = support.appendingPathComponent(ChatStarter.folderName, isDirectory: true)
        _ = try ChatStarter.memoryPrompt(directory: prompts)
        XCTAssertEqual(mode(prompts), 0o700)
        XCTAssertEqual(mode(prompts.appendingPathComponent(ChatStarter.memoryFileName)), 0o600)

        // Ползунок полей пишет блок claude.css.
        XCTAssertTrue(LiveStyle.writeBlock(padding: 16, directory: support))
        XCTAssertEqual(mode(support.appendingPathComponent(SupportFiles.cssFileName)), 0o600)
    }

    func testProjectFolderFileKeeps0644() throws {
        let project = scratch.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let store = ProjectSettingsStore(registryURL: scratch.appendingPathComponent("MyClaude/project-views.json"))
        XCTAssertEqual(store.write(ProjectSettings(name: "Проект"), to: project), .written)
        XCTAssertEqual(mode(project.appendingPathComponent(ProjectSettings.fileName)), 0o644)
    }

    func testCSSBlockAndDefaultsAreOneCopyWithPatcher() {
        XCTAssertEqual(LiveStyle.markerStart, Patcher.cssMarkerStart)
        XCTAssertEqual(LiveStyle.markerEnd, Patcher.cssMarkerEnd)
        let block = LiveStyle.block(padding: 16, radius: 12)
        for live in ["", "a { color: red }\n", "a{}\n\(Patcher.cssMarkerStart)\nold\n\(Patcher.cssMarkerEnd)\nb{}\n",
                     "\(Patcher.cssMarkerEnd)\nx\n\(Patcher.cssMarkerStart)\n"] {
            XCTAssertEqual(LiveStyle.applying(block: block, to: live), Patcher.mergeCSS(bundled: block, live: live), live)
        }
        XCTAssertEqual(LiveStyle.defaultSidePadding, Patcher.configDefaults["sidePadding"])
        XCTAssertEqual(LiveStyle.defaultMinWindowWidth, Patcher.configDefaults["minWindowWidth"])
        XCTAssertEqual(Int(ClaudeActions.defaultWindowGap), Patcher.configDefaults["windowGap"])
    }
}
