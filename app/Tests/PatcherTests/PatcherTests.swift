import XCTest
@testable import Patcher

/// Замена команды `patch-claude.mjs selftest`: живой Claude.app копируется во временную папку,
/// патч гоняется на копии, приложение не трогается.
final class PatcherTests: XCTestCase {
    private var scratch: URL!
    private var appURL: URL!
    private var support: URL!
    private var originalAsar: Data!

    override func setUpWithError() throws {
        let candidate = Patcher.locateClaude().first
        try XCTSkipUnless(candidate.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Resources/app.asar").path) } ?? false,
                          "Claude.app не найден — тест патчера пропущен")
        let source = candidate!

        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimpmyclaude-test-\(UUID().uuidString)", isDirectory: true)
        appURL = scratch.appendingPathComponent("Claude.app", isDirectory: true)
        support = scratch.appendingPathComponent("Support", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source.appendingPathComponent("Contents/Resources/app.asar"),
                                         to: appURL.appendingPathComponent("Contents/Resources/app.asar"))
        try FileManager.default.copyItem(at: source.appendingPathComponent("Contents/Info.plist"),
                                         to: appURL.appendingPathComponent("Contents/Info.plist"))

        // Копия живого Claude может быть уже пропатчена — снимаем лоадер, чтобы прогнать установку целиком.
        _ = try Asar.removeLoader(appURL.appendingPathComponent("Contents/Resources/app.asar"))
        originalAsar = try Data(contentsOf: appURL.appendingPathComponent("Contents/Resources/app.asar"))
    }

    override func tearDownWithError() throws {
        if let scratch = scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    private func makePatcher() -> ClaudePatcher {
        var patcher = ClaudePatcher(appURL: appURL, supportDirectory: support, resourcesDirectory: nil)
        patcher.signsApp = false            // копия не подписана, подписывать нечего
        patcher.managesClaudeProcess = false // живой Claude не трогаем
        return patcher
    }

    func testInstallPutsLoaderAndMatchingHash() throws {
        let patcher = makePatcher()
        let before = try Asar.status(of: patcher.asarURL)
        XCTAssertEqual(before.loaderVersion, 0, "перед установкой лоадера в копии быть не должно")

        let outcome = try patcher.install()
        if case .installed = outcome {} else { XCTFail("ожидалась установка, получено \(outcome)") }

        let after = try Asar.status(of: patcher.asarURL)
        XCTAssertEqual(after.loaderVersion, Patcher.requiredLoaderVersion, "лоадер v6 в главном сценарии не найден")
        XCTAssertEqual(patcher.infoPlistHash(), after.headerSHA256, "хэш в Info.plist не совпал с новым архивом")
        XCTAssertEqual(patcher.state(), .installed(version: try patcher.appVersion(), loaderVersion: 6))

        // Все упакованные файлы должны читаться по своим (сдвинутым) смещениям с прежними хэшами.
        let archive = try Asar.read(patcher.asarURL)
        var checked = 0
        try Asar.walkPacked(archive.header) { entry in
            guard let integrity = entry["integrity"] as? NSDictionary, let hash = integrity["hash"] as? String else { return }
            XCTAssertEqual(sha256Hex(try Asar.content(archive, entry)), hash, "хэш файла разошёлся после сдвига смещений")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100, "сверено подозрительно мало файлов: \(checked)")

        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("claude.json").path))
    }

    func testInstallIsIdempotent() throws {
        let patcher = makePatcher()
        _ = try patcher.install()
        let patched = try Data(contentsOf: patcher.asarURL)
        let outcome = try patcher.install()
        if case .alreadyInstalled = outcome {} else { XCTFail("повторная установка должна ничего не менять, получено \(outcome)") }
        XCTAssertEqual(try Data(contentsOf: patcher.asarURL), patched)
    }

    /// Решение 3 плана WF9: комплект воркфлоу из ресурсов сборки ложится рядом с command.json.
    func testInstallLiveFilesCopiesWorkflowKit() throws {
        let resources = scratch.appendingPathComponent("Resources", isDirectory: true)
        let kit = resources.appendingPathComponent(Patcher.workflowKitDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: kit, withIntermediateDirectories: true)
        try Data("правила".utf8).write(to: kit.appendingPathComponent("WORKFLOW.md"))
        try Data("кикофф".utf8).write(to: kit.appendingPathComponent("KICKOFF.md"))
        try Data("// inject".utf8).write(to: resources.appendingPathComponent("inject.js"))

        var patcher = makePatcher()
        patcher.resourcesDirectory = resources
        try patcher.installLiveFiles(progress: { _ in })

        let target = support.appendingPathComponent(Patcher.workflowDirName, isDirectory: true)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("KICKOFF.md"), encoding: .utf8), "кикофф")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("WORKFLOW.md"), encoding: .utf8), "правила")
        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("inject.js").path))

        // Комплекта в сборке нет (старый бандл) — установка не падает.
        try FileManager.default.removeItem(at: kit)
        try patcher.installLiveFiles(progress: { _ in })
    }

    func testRestoreReturnsOriginalBytes() throws {
        let patcher = makePatcher()
        _ = try patcher.install()
        XCTAssertNotEqual(try Data(contentsOf: patcher.asarURL), originalAsar, "после установки архив обязан отличаться")

        try patcher.restore()
        XCTAssertEqual(try Data(contentsOf: patcher.asarURL), originalAsar, "restore не вернул байт-в-байт оригинал")
        let backupInfo = try Data(contentsOf: patcher.backupDirectory(try patcher.appVersion()).appendingPathComponent("Info.plist"))
        XCTAssertEqual(try Data(contentsOf: patcher.infoPlistURL), backupInfo, "restore не вернул оригинальный Info.plist")
    }

}

/// Дешёвые проверки самой строки лоадера — без копирования 39 МБ.
final class LoaderTests: XCTestCase {
    func testLoaderMarkersAreVersionSix() {
        XCTAssertTrue(claudeLoaderSource.hasPrefix("/* [MyClaude:v6:start] */\n"))
        XCTAssertTrue(claudeLoaderSource.hasSuffix("/* [MyClaude:v6:end] */\n"))
        XCTAssertEqual(Asar.loaderVersion(of: claudeLoaderSource), 6)
        XCTAssertEqual(Asar.stripLoader(claudeLoaderSource + "// хвост"), "// хвост")
    }
}
