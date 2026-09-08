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
        XCTAssertEqual(after.loaderVersion, Patcher.requiredLoaderVersion, "лоадер v7 в главном сценарии не найден")
        XCTAssertEqual(patcher.infoPlistHash(), after.headerSHA256, "хэш в Info.plist не совпал с новым архивом")
        XCTAssertEqual(patcher.state(), .installed(version: try patcher.appVersion(), loaderVersion: 7))

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

    /// Задача #5722: в Claude стоит СТАРЫЙ лоадер, installed.json это признаёт — значок обязан
    /// краснеть. До правки быстрый статус сверял только версию и хэш и отвечал «патч стоит».
    func testStateGoesLostWhenLoaderIsOld() throws {
        let patcher = makePatcher()
        // Кладём в главный сценарий лоадер прошлой версии — как у того, кто обновил приложение,
        // но «Поставить» не нажал.
        let result = try Asar.rewriteMain(patcher.asarURL) { source in
            "/* [MyClaude:v6:start] */\n/* [MyClaude:v6:end] */\n" + Asar.stripLoader(source)
        }
        try patcher.setInfoPlistHash(result.headerSHA256)
        try writeInstalledRecord(patcher, headerSHA256: result.headerSHA256, loaderVersion: 6, mainPath: result.mainPath)

        let version = try patcher.appVersion()
        XCTAssertEqual(patcher.state(), .lost(version: version, reason: "старый лоадер v6"),
                       "старый лоадер обязан красить значок, а не оставлять зелёную галку")

        // Записи без поля loaderVersion (древний installed.json) тоже нельзя считать «нужной версией».
        try writeInstalledRecord(patcher, headerSHA256: result.headerSHA256, loaderVersion: nil, mainPath: result.mainPath)
        XCTAssertEqual(patcher.state(), .lost(version: version, reason: "старый лоадер v6"))

        // А после установки статус снова зелёный — быстрый путь не сломан.
        _ = try patcher.install()
        XCTAssertEqual(patcher.state(), .installed(version: version, loaderVersion: Patcher.requiredLoaderVersion))
    }

    /// Задача #5726: бэкап хранит только ЧИСТЫЙ архив. Пропатченный старым лоадером туда не идёт —
    /// иначе «Снять» потом соврёт «оригинальные файлы на месте».
    func testBackupSkipsAlreadyPatchedArchive() throws {
        let patcher = makePatcher()
        _ = try Asar.rewriteMain(patcher.asarURL) { source in
            "/* [MyClaude:v6:start] */\n/* [MyClaude:v6:end] */\n" + Asar.stripLoader(source)
        }
        var log: [String] = []
        _ = try patcher.install(progress: { log.append($0) })

        let backup = patcher.backupDirectory(try patcher.appVersion()).appendingPathComponent("app.asar")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path),
                       "в бэкап попал архив с чужим лоадером — «Снять» вернёт не оригинал")
        XCTAssertTrue(log.contains { $0.contains("уже стоит лоадер v6") }, "про пропущенный бэкап нигде не сказано: \(log)")
        XCTAssertEqual(try Asar.status(of: patcher.asarURL).loaderVersion, Patcher.requiredLoaderVersion,
                       "сама установка при этом обязана пройти")
    }

    /// Задача #5724: осечка между записью app.asar и подписью не должна оставлять Claude,
    /// который не запускается. Подпись здесь падает по-настоящему: у копии нет исполняемого файла.
    func testFailedSigningRollsArchiveBack() throws {
        let resources = scratch.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: resources.appendingPathComponent("entitlements.plist"))

        var patcher = makePatcher()
        patcher.signsApp = true
        patcher.resourcesDirectory = resources

        var log: [String] = []
        XCTAssertThrowsError(try patcher.install(progress: { log.append($0) })) { error in
            guard case PatchError.installBroke(_, let restored) = error else {
                return XCTFail("ожидалась installBroke, получено \(error)")
            }
            XCTAssertTrue(restored, "бэкап был свежий — откат обязан пройти")
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("Поставить") == true,
                          "в плашке не сказано, что нажать")
        }
        XCTAssertEqual(try Data(contentsOf: patcher.asarURL), originalAsar, "app.asar не вернулся к исходным байтам")
        XCTAssertTrue(log.contains { $0.contains("возвращаю оригинальный Claude") }, "про откат в журнале ни строки: \(log)")
    }

    /// Задача #5727: «Открываю Claude…» и тишина. Открыть не вышло — строкой в журнал.
    func testRelaunchSaysWhenClaudeDidNotOpen() {
        var patcher = makePatcher()
        patcher.managesClaudeProcess = true
        patcher.appURL = scratch.appendingPathComponent("НетТакогоClaude.app", isDirectory: true)
        var log: [String] = []
        patcher.relaunchClaude(progress: { log.append($0) })
        XCTAssertTrue(log.contains { $0.contains("Claude открыть не удалось") }, "неудачный запуск проглочен: \(log)")
    }

    /// Задача #5723: «Поставить» больше не стирает личные правила в claude.css.
    func testInstallLiveFilesKeepsPersonalCSS() throws {
        let resources = scratch.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("/* база */\n\(Patcher.cssMarkerStart)\nbody{color:red}\n\(Patcher.cssMarkerEnd)\n".utf8)
            .write(to: resources.appendingPathComponent(Patcher.cssFileName))

        var patcher = makePatcher()
        patcher.resourcesDirectory = resources
        let live = support.appendingPathComponent(Patcher.cssFileName)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("/* моё правило */\n\(Patcher.cssMarkerStart)\nbody{color:blue}\n\(Patcher.cssMarkerEnd)\n/* и ещё моё */\n".utf8)
            .write(to: live)

        try patcher.installLiveFiles(progress: { _ in })
        let text = try String(contentsOf: live, encoding: .utf8)
        XCTAssertEqual(text, "/* моё правило */\n\(Patcher.cssMarkerStart)\nbody{color:red}\n\(Patcher.cssMarkerEnd)\n/* и ещё моё */\n")
    }

    private func writeInstalledRecord(_ patcher: ClaudePatcher, headerSHA256: String, loaderVersion: Int?, mainPath: String) throws {
        var record: [String: Any] = [
            "appPath": patcher.appURL.path,
            "version": try patcher.appVersion(),
            "headerSHA256": headerSHA256,
            "mainPath": mainPath,
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        if let loaderVersion = loaderVersion { record["loaderVersion"] = loaderVersion }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]).write(to: patcher.installedURL, options: .atomic)
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
    /// Умолчания claude.json: поля по бокам — 5 px (решение Элвиса 04.09, вопрос 4 макета WF14).
    /// Та же цифра лежит в `LiveStyle.defaultSidePadding` (таргет ClaudeAX его не видит),
    /// в `claude-patch/claude.json` и в `DEFAULTS` файла `patch-claude.mjs` — мелочь М6 критика.
    /// Ширина окна — 280 (WF45, задача #5751): на 360 две плитки раскладок из четырёх серые.
    func testConfigDefaultsCarryFivePixelSidePadding() {
        XCTAssertEqual(Patcher.configDefaults["sidePadding"], 5)
        XCTAssertEqual(Patcher.configDefaults["minWindowWidth"], 280)
    }

    /// Задача #5723: слияние claude.css — приложение владеет только блоком между маркерами.
    func testMergeCSSOwnsOnlyItsBlock() {
        let block = "\(Patcher.cssMarkerStart)\nbody{color:red}\n\(Patcher.cssMarkerEnd)"
        // Живого файла нет — кладём файл из бандла целиком.
        XCTAssertEqual(Patcher.mergeCSS(bundled: block + "\n", live: nil), block + "\n")
        // Маркеров в живом файле нет — блок дописывается в конец, чужие строки целы.
        XCTAssertEqual(Patcher.mergeCSS(bundled: block + "\n", live: "/* моё */\n"), "/* моё */\n" + block + "\n")
        // В бандле блока нет — живой файл не трогаем вовсе.
        XCTAssertEqual(Patcher.mergeCSS(bundled: "/* без блока */\n", live: "/* моё */\n"), "/* моё */\n")
        // Блок задвоился: мусор от первого маркера до последнего вырезаем, блок пишем в конец.
        let doubled = "/* моё */\n\(Patcher.cssMarkerStart)\nx{}\n\(Patcher.cssMarkerEnd)\n\(Patcher.cssMarkerStart)\ny{}\n\(Patcher.cssMarkerEnd)\n"
        XCTAssertEqual(Patcher.mergeCSS(bundled: block + "\n", live: doubled), "/* моё */\n" + block + "\n")
    }

    func testLoaderMarkersAreVersionSeven() {
        XCTAssertTrue(claudeLoaderSource.hasPrefix("/* [MyClaude:v7:start] */\n"))
        XCTAssertTrue(claudeLoaderSource.hasSuffix("/* [MyClaude:v7:end] */\n"))
        XCTAssertEqual(Asar.loaderVersion(of: claudeLoaderSource), 7)
        XCTAssertEqual(Asar.stripLoader(claudeLoaderSource + "// хвост"), "// хвост")
    }
}
