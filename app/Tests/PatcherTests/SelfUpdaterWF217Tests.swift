import Security
import XCTest
@testable import Patcher

/// Автообновление Пимпа и PimpViewer (WF217, #9410, К-SU). Весь путь — во временной папке: источник и проверки
/// подписи подставные, /Applications, сеть и стоящие приложения не трогаются.
final class SelfUpdaterWF217Tests: XCTestCase {
    private var scratch: URL!
    private var apps: URL!
    private var store: URL!
    private var clock = Date(timeIntervalSince1970: 1_780_000_000)
    private var downloads = 0
    private var asked = 0
    private var signatureCalls: [String] = []
    private let pimp = SelfUpdateProduct.pimp
    private let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimp-self-update-\(UUID().uuidString)", isDirectory: true)
        apps = scratch.appendingPathComponent("Applications", isDirectory: true)
        store = scratch.appendingPathComponent("Support/self-update", isDirectory: true)
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch = scratch { try? fm.removeItem(at: scratch) }
    }

    // ---------------------------------------------------------------- подставные приложение, архив, источник

    @discardableResult
    private func makeApp(in folder: URL, name: String = "PimpMyClaude.app", version: String,
                         bundleID: String = "com.elvis.pimpmyclaude") throws -> URL {
        let app = folder.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    /// Архив из содержимого папки (как `ditto -c -k --keepParent PimpMyClaude.app`, когда в папке одно приложение).
    private func zip(_ fill: (URL) throws -> Void) throws -> URL {
        let source = scratch.appendingPathComponent("src-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fill(source)
        let archive = scratch.appendingPathComponent("archive-\(UUID().uuidString).zip")
        try Shell.run("/usr/bin/ditto", ["-c", "-k", source.path, archive.path])
        return archive
    }

    private func goodZip(_ version: String) throws -> URL {
        try zip { try self.makeApp(in: $0, version: version) }
    }

    private func size(_ file: URL) -> Int64 {
        (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? -1
    }

    private func releaseJSON(_ version: String, product: SelfUpdateProduct = .pimp, size: Int64 = 1000, digest: String? = nil,
                             _ change: (inout [String: Any], inout [String: Any]) -> Void = { _, _ in }) -> Data {
        let tag = "v" + version
        var asset: [String: Any] = ["name": product.assetName(version), "state": "uploaded", "size": size,
                                    "browser_download_url": product.assetURL(tag: tag, version: version).absoluteString]
        if let digest = digest { asset["digest"] = "sha256:" + digest }
        var release: [String: Any] = ["tag_name": tag, "draft": false, "prerelease": false]
        change(&release, &asset)
        if release["assets"] == nil { release["assets"] = [asset] }
        return try! JSONSerialization.data(withJSONObject: release)
    }

    /// Обновитель на временных папках: выпуск `version` с архивом `archive`, проверки подписи проходят.
    private func makeUpdater(version: String, archive: URL?, json: Data? = nil) -> SelfUpdater {
        var updater = SelfUpdater(directory: store)
        updater.allowedParents = [apps]
        updater.now = { self.clock }
        let body = json ?? releaseJSON(version, size: archive.map(size) ?? 1000)
        updater.transport = SelfUpdateTransport(
            latest: { _ in self.asked += 1; return .success(body) },
            download: { _, _, file in
                self.downloads += 1
                guard let archive = archive else { return .failure(.offline("нет архива")) }
                do { try self.fm.copyItem(at: archive, to: file) } catch { return .failure(.offline("\(error)")) }
                return .success(())
            })
        updater.checks = SelfUpdateChecks(signature: { app, _ in self.signatureCalls.append(app.path); return nil },
                                          gatekeeper: { _ in nil })
        return updater
    }

    private var installedApp: URL { apps.appendingPathComponent("PimpMyClaude.app", isDirectory: true) }
    private func installedVersion() -> String? { SelfUpdater.installedVersion(installedApp, bundleID: pimp.bundleID) }
    private func leftovers() -> [String] {
        ((try? fm.contentsOfDirectory(atPath: store.path)) ?? []).filter { $0.hasSuffix(".zip") || $0.hasPrefix("unpack-") }
    }
    private func mode(_ url: URL) -> Int { (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1 }

    // ---------------------------------------------------------------- версии и выпуск

    func testVersionsCompareByNumbersNotAsText() {
        XCTAssertTrue(SelfUpdater.isNewer("1.10.19", than: "1.10.9"))
        XCTAssertFalse(SelfUpdater.isNewer("1.10.9", than: "1.10.19"))
        XCTAssertFalse(SelfUpdater.isNewer("1.10.19", than: "1.10.19"), "равная — не новее")
        XCTAssertFalse(SelfUpdater.isNewer("1.10", than: "1.10.0"), "равная с недостающей частью — не новее")
        XCTAssertFalse(SelfUpdater.isNewer("1.9.99", than: "1.10.0"))
        XCTAssertTrue(SelfUpdater.isNewer("2.0", than: "1.99.99"))
        for garbage in ["", "abc", "1.10.x", "1..2", "v1.10.20", "1.10.20 ", "-1.2", "1.10.20-beta"] {
            XCTAssertFalse(SelfUpdater.isNewer(garbage, than: "1.10.19"), "мусор «\(garbage)» не новее ничего")
            XCTAssertFalse(SelfUpdater.isNewer("1.10.19", than: garbage))
        }
    }

    func testReleaseAndAssetAreChosenStrictly() throws {
        let sha = String(repeating: "ab", count: 32)
        let release = try SelfUpdater.parseRelease(releaseJSON("1.10.20", size: 5_000_000, digest: sha), product: pimp)
        XCTAssertEqual(release, SelfUpdateRelease(
            version: "1.10.20", tag: "v1.10.20", asset: "PimpMyClaude-1.10.20.zip", size: 5_000_000, sha256: sha,
            url: URL(string: "https://github.com/ElvisIglikov/PimpMyClaude/releases/download/v1.10.20/PimpMyClaude-1.10.20.zip")!))
        // Тег без «v» — тоже версия; у Viewer своё имя архива и свой репозиторий.
        XCTAssertEqual(try SelfUpdater.parseRelease(releaseJSON("1.10.20") { release, asset in
            release["tag_name"] = "1.10.20"
            asset["browser_download_url"] = "https://github.com/ElvisIglikov/PimpMyClaude/releases/download/1.10.20/PimpMyClaude-1.10.20.zip"
        }, product: pimp).tag, "1.10.20")
        let viewer = try SelfUpdater.parseRelease(releaseJSON("1.10.8", product: .viewer), product: .viewer)
        XCTAssertEqual(viewer.asset, "PimpViewer-1.10.8.zip")
        XCTAssertEqual(viewer.url.absoluteString, "https://github.com/ElvisIglikov/PimpViewer/releases/download/v1.10.8/PimpViewer-1.10.8.zip")
        XCTAssertNil(viewer.sha256)

        func refused(_ why: String, _ data: Data, product: SelfUpdateProduct = .pimp, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try SelfUpdater.parseRelease(data, product: product), why, file: file, line: line) { error in
                guard case SelfUpdateError.release = error else { return XCTFail("\(why): \(error)", file: file, line: line) }
            }
        }
        refused("черновик", releaseJSON("1.10.20") { release, _ in release["draft"] = true })
        refused("пред-выпуск", releaseJSON("1.10.20") { release, _ in release["prerelease"] = true })
        refused("про черновик не сказано", releaseJSON("1.10.20") { release, _ in release["draft"] = nil })
        refused("про пред-выпуск не сказано", releaseJSON("1.10.20") { release, _ in release["prerelease"] = nil })
        refused("тег с пробелом", releaseJSON("1.10.20") { release, _ in release["tag_name"] = "v1.10.20 " })
        refused("нет вложений", releaseJSON("1.10.20") { release, _ in release["assets"] = [[String: Any]]() })
        refused("чужое имя", releaseJSON("1.10.20") { _, asset in asset["name"] = "PimpMyClaude.zip" })
        refused("архив другой версии", releaseJSON("1.10.20") { _, asset in asset["name"] = "PimpMyClaude-1.10.21.zip" })
        refused("архив Viewer в выпуске Пимпа", releaseJSON("1.10.20", product: .viewer))
        refused("два вложения с одним именем", releaseJSON("1.10.20") { release, asset in release["assets"] = [asset, asset] })
        refused("не загружено", releaseJSON("1.10.20") { _, asset in asset["state"] = "starter" })
        refused("пустое", releaseJSON("1.10.20", size: 0))
        refused("больше потолка", releaseJSON("1.10.20", size: SelfUpdater.maxArchiveBytes + 1))
        refused("ссылка на чужой адрес", releaseJSON("1.10.20") { _, asset in
            asset["browser_download_url"] = "https://evil.example/PimpMyClaude-1.10.20.zip"
        })
        refused("ссылка на чужой репозиторий", releaseJSON("1.10.20") { _, asset in
            asset["browser_download_url"] = "https://github.com/Other/PimpMyClaude/releases/download/v1.10.20/PimpMyClaude-1.10.20.zip"
        })
        refused("тег — не версия", releaseJSON("1.10.20") { release, _ in release["tag_name"] = "latest" })
        refused("тег с хвостом", releaseJSON("1.10.20") { release, _ in release["tag_name"] = "v1.10.20-beta" })
        refused("сумма непонятного вида", releaseJSON("1.10.20") { _, asset in asset["digest"] = "md5:abc" })
        refused("не JSON", Data("<html>".utf8))
    }

    func testDownloadGoesOnlyToGitHubOverHTTPS() {
        for good in ["https://api.github.com/repos/ElvisIglikov/PimpMyClaude/releases/latest",
                     "https://github.com/ElvisIglikov/PimpMyClaude/releases/download/v1/PimpMyClaude-1.zip",
                     "https://release-assets.githubusercontent.com/x", "https://objects.githubusercontent.com/x"] {
            XCTAssertTrue(SelfUpdater.allowedHost(URL(string: good)), good)
        }
        for bad in ["http://github.com/x", "https://github.com.evil.test/x", "https://evilgithubusercontent.com/x",
                    "https://user@github.com/x", "https://github.com:8443/x", "https://claudeapp.agentsmirror.com/x",
                    "file:///tmp/x.zip"] {
            XCTAssertFalse(SelfUpdater.allowedHost(URL(string: bad)), bad)
        }
        XCTAssertFalse(SelfUpdater.allowedHost(nil))
    }

    func testCheckPacing() {
        var state = SelfUpdateState.Product()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertTrue(SelfUpdater.shouldCheck(nil, now: now, interval: SelfUpdater.checkInterval), "ни разу не спрашивали")
        state.attemptedAt = now.addingTimeInterval(-5 * 3600)
        XCTAssertFalse(SelfUpdater.shouldCheck(state, now: now, interval: SelfUpdater.checkInterval), "фоном — не чаще раза в 6 часов")
        XCTAssertTrue(SelfUpdater.shouldCheck(state, now: now, interval: SelfUpdater.launchInterval), "на запуске — можно")
        state.attemptedAt = now.addingTimeInterval(-10 * 60)
        XCTAssertFalse(SelfUpdater.shouldCheck(state, now: now, interval: SelfUpdater.launchInterval), "Claude перезапускают подряд")
        state.attemptedAt = now.addingTimeInterval(-6 * 3600)
        XCTAssertTrue(SelfUpdater.shouldCheck(state, now: now, interval: SelfUpdater.checkInterval))
        state.attemptedAt = now.addingTimeInterval(3600)
        XCTAssertTrue(SelfUpdater.shouldCheck(state, now: now, interval: SelfUpdater.checkInterval), "часы перевели назад")
    }

    // ---------------------------------------------------------------- момент установки

    func testNeverInstallsInTheMiddleOfWork() {
        XCTAssertTrue(SelfUpdater.mayInstall(.pimp, SelfUpdateMoment()))
        XCTAssertTrue(SelfUpdater.mayInstall(.viewer, SelfUpdateMoment()))
        XCTAssertFalse(SelfUpdater.mayInstall(.pimp, SelfUpdateMoment(panelOpen: true)), "панель открыта")
        XCTAssertFalse(SelfUpdater.mayInstall(.pimp, SelfUpdateMoment(busy: true)), "идёт патч или обновление Claude")
        XCTAssertFalse(SelfUpdater.mayInstall(.pimp, SelfUpdateMoment(recording: true)), "идёт запись")
        XCTAssertFalse(SelfUpdater.mayInstall(.pimp, SelfUpdateMoment(enabled: false)), "выключено")
        XCTAssertFalse(SelfUpdater.mayInstall(.viewer, SelfUpdateMoment(viewerRunning: true)), "Viewer запущен — откладываем")
        XCTAssertTrue(SelfUpdater.mayInstall(.pimp, SelfUpdateMoment(viewerRunning: true)), "Пимпу запущенный Viewer не мешает")
        XCTAssertFalse(SelfUpdater.mayInstall(.viewer, SelfUpdateMoment(busy: true)))
        XCTAssertFalse(SelfUpdater.mayInstall(.viewer, SelfUpdateMoment(enabled: false)))
    }

    // ---------------------------------------------------------------- проверить и скачать заранее

    func testNewerReleaseIsDownloadedVerifiedAndWaits() throws {
        try makeApp(in: apps, version: "1.10.19")
        let updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        // Хвосты оборванного круга: распаковка и архив прошлой версии; чужой архив (Viewer) — не наш.
        try fm.createDirectory(at: store.appendingPathComponent("unpack-old/PimpMyClaude.app"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: store.appendingPathComponent("PimpMyClaude-1.10.18.zip"))
        try Data("x".utf8).write(to: store.appendingPathComponent("PimpViewer-1.10.8.zip"))
        let entry = updater.check(pimp, app: installedApp)
        XCTAssertEqual(entry.ready, "1.10.20")
        XCTAssertEqual(entry.latest, "1.10.20")
        XCTAssertEqual(entry.checkedAt, clock)
        XCTAssertNil(entry.problem)
        XCTAssertEqual(installedVersion(), "1.10.19", "проверка ничего не ставит")
        XCTAssertEqual(leftovers().sorted(), ["PimpMyClaude-1.10.20.zip", "PimpViewer-1.10.8.zip"], "распаковка и хвосты убраны, архив ждёт")
        try fm.removeItem(at: store.appendingPathComponent("PimpViewer-1.10.8.zip"))
        // Своя папка закрыта от других учёток: 0700, файлы 0600.
        XCTAssertEqual(mode(store), 0o700)
        for name in ["PimpMyClaude-1.10.20.zip", "state.json", "journal.log"] {
            XCTAssertEqual(mode(store.appendingPathComponent(name)), 0o600, name)
        }
        // Второй круг архив не качает заново.
        updater.check(pimp, app: installedApp)
        XCTAssertEqual(downloads, 1)
    }

    func testEqualOrLowerReleaseIsNotDownloaded() throws {
        try makeApp(in: apps, version: "1.10.20")
        for offered in ["1.10.20", "1.10.19", "1.9.99"] {
            let entry = makeUpdater(version: offered, archive: try goodZip(offered)).check(pimp, app: installedApp)
            XCTAssertNil(entry.ready, offered)
            XCTAssertEqual(entry.latest, offered)
        }
        XCTAssertEqual(downloads, 0)
        XCTAssertEqual(leftovers(), [])
    }

    func testNoSourceIsQuiet() throws {
        try makeApp(in: apps, version: "1.10.19")
        var updater = makeUpdater(version: "1.10.20", archive: nil)
        updater.transport.latest = { _ in .failure(.offline("сети нет")) }
        var entry = updater.check(pimp, app: installedApp)
        XCTAssertEqual(entry.problem, .offline)
        XCTAssertEqual(entry.attemptedAt, clock, "следующая проверка — позже, от этой попытки")
        XCTAssertNil(entry.checkedAt)
        XCTAssertNil(entry.refused, "нет сети — не отказ")
        XCTAssertEqual(SelfUpdater.statusLine(installed: "1.10.19", state: entry, enabled: true, place: nil, now: clock),
                       "Стоит 1.10.19 · нет связи с GitHub")
        // Репозиторий закрыт, gh нет: тоже тихо.
        updater.transport.latest = { _ in .failure(.missing("GitHub ответил 404, gh не помог")) }
        entry = updater.check(pimp, app: installedApp)
        XCTAssertEqual(entry.problem, .missing)
        XCTAssertEqual(SelfUpdater.statusLine(installed: "1.10.19", state: entry, enabled: true, place: nil, now: clock),
                       "Стоит 1.10.19 · выпусков на GitHub не видно")
        // Выпуск есть, архив не скачался.
        updater.transport.latest = { _ in .success(self.releaseJSON("1.10.20")) }
        entry = updater.check(pimp, app: installedApp)
        XCTAssertEqual(entry.problem, .offline)
        XCTAssertNil(entry.ready)
        XCTAssertNil(entry.refused)
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(leftovers(), [])
        XCTAssertEqual(installedVersion(), "1.10.19")
        XCTAssertNil(try updater.install(pimp, app: installedApp), "ставить нечего")
    }

    func testAppOutsideApplicationsIsNeverTouchedAndNeverAsksNetwork() throws {
        let elsewhere = scratch.appendingPathComponent("Desktop", isDirectory: true)
        let app = try makeApp(in: elsewhere, version: "1.10.19")
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        XCTAssertEqual(updater.placeProblem(app, product: pimp), "Пимп лежит не в «Программах»")
        updater.check(pimp, app: app)
        XCTAssertEqual(asked, 0, "ставить некуда — и спрашивать незачем")
        XCTAssertEqual(downloads, 0)
        // Переименованная копия и ярлык на копию в другом месте — тоже не «Программы».
        let renamed = try makeApp(in: apps, name: "PimpMyClaude 2.app", version: "1.10.19")
        XCTAssertNotNil(updater.placeProblem(renamed, product: pimp))
        try fm.createSymbolicLink(at: installedApp, withDestinationURL: app)
        XCTAssertNotNil(updater.placeProblem(installedApp, product: pimp))
        try fm.removeItem(at: installedApp)
        // Скачали, пока лежал в «Программах», потом папку запретили: не ставим, архив цел.
        try makeApp(in: apps, version: "1.10.19")
        XCTAssertNil(updater.placeProblem(installedApp, product: pimp))
        updater.check(pimp, app: installedApp)
        updater.allowedParents = []
        XCTAssertThrowsError(try updater.install(pimp, app: installedApp)) { error in
            guard case SelfUpdateError.place = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(installedVersion(), "1.10.19")
        XCTAssertEqual(leftovers(), ["PimpMyClaude-1.10.20.zip"])
    }

    // ---------------------------------------------------------------- каждая проверка рубит установку и удаляет файл

    /// Круг проверки на архиве с изъяном: версия отложена, архив и распаковка удалены, стоящее приложение
    /// не тронуто, ставить нечего.
    private func assertRefused(_ updater: SelfUpdater, _ word: String, file: StaticString = #filePath, line: UInt = #line) throws {
        if installedVersion() == nil { try makeApp(in: apps, version: "1.10.19") }
        let entry = updater.check(pimp, app: installedApp)
        XCTAssertNil(entry.ready, file: file, line: line)
        XCTAssertEqual(entry.refused, "1.10.20", file: file, line: line)
        XCTAssertTrue(entry.refusedWhy?.contains(word) == true, "причина «\(entry.refusedWhy ?? "нет")» без «\(word)»", file: file, line: line)
        XCTAssertEqual(leftovers(), [], "архив и распаковка удалены", file: file, line: line)
        XCTAssertEqual(installedVersion(), "1.10.19", file: file, line: line)
        XCTAssertNil(try updater.install(pimp, app: installedApp), file: file, line: line)
        XCTAssertEqual(installedVersion(), "1.10.19", file: file, line: line)
        let journal = try String(contentsOf: store.appendingPathComponent("journal.log"), encoding: .utf8)
        XCTAssertTrue(journal.contains("pimp: 1.10.20 не ставлю"), "отказ — в журнале", file: file, line: line)
        XCTAssertEqual(mode(store.appendingPathComponent("journal.log")), 0o600, file: file, line: line)
    }

    func testTwoAppsInArchiveAreRefused() throws {
        let archive = try zip {
            try self.makeApp(in: $0, version: "1.10.20")
            try self.makeApp(in: $0, name: "Evil.app", version: "1.10.20")
        }
        try assertRefused(makeUpdater(version: "1.10.20", archive: archive), "не одно PimpMyClaude.app")
    }

    func testExtraFileNextToAppIsRefused() throws {
        let archive = try zip {
            try self.makeApp(in: $0, version: "1.10.20")
            try Data("#!/bin/sh".utf8).write(to: $0.appendingPathComponent("install.command"))
        }
        try assertRefused(makeUpdater(version: "1.10.20", archive: archive), "не одно PimpMyClaude.app")
    }

    func testForeignAppNameIsRefused() throws {
        let archive = try zip { try self.makeApp(in: $0, name: "PimpViewer.app", version: "1.10.20") }
        try assertRefused(makeUpdater(version: "1.10.20", archive: archive), "не одно PimpMyClaude.app")
    }

    func testSymlinkInsteadOfAppIsRefused() throws {
        let archive = try zip {
            try self.fm.createSymbolicLink(at: $0.appendingPathComponent("PimpMyClaude.app"),
                                           withDestinationURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
        }
        try assertRefused(makeUpdater(version: "1.10.20", archive: archive), "не папка приложения")
    }

    func testForeignBundleIDIsRefused() throws {
        let archive = try zip { try self.makeApp(in: $0, version: "1.10.20", bundleID: "com.elvis.pimpviewer") }
        try assertRefused(makeUpdater(version: "1.10.20", archive: archive), "bundle id com.elvis.pimpviewer")
    }

    func testBadSignatureIsRefused() throws {
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        var asked: [String] = []
        updater.checks.signature = { _, requirement in asked.append(requirement); return "code failed to satisfy specified code requirement(s)" }
        try assertRefused(updater, "подпись не прошла")
        XCTAssertEqual(asked, [pimp.requirement], "подпись спрашивают с требованием Developer ID F27N4S4NJ4 и этим bundle id")
    }

    func testGatekeeperRejectionIsRefused() throws {
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.checks.gatekeeper = { _ in "rejected: Unnotarized Developer ID" }
        try assertRefused(updater, "Gatekeeper не принял")
    }

    func testVersionInsideDifferentFromReleaseIsRefused() throws {
        // Выпуск обещал 1.10.20, внутри — другая (и выше, и ниже): не ставим.
        try assertRefused(makeUpdater(version: "1.10.20", archive: try goodZip("1.10.21")), "внутри 1.10.21, выпуск обещал 1.10.20")
        clock += SelfUpdater.refusedPause
        try assertRefused(makeUpdater(version: "1.10.20", archive: try goodZip("1.10.18")), "внутри 1.10.18")
    }

    func testVersionMustBeStrictlyAboveInstalled() throws {
        try makeApp(in: apps, version: "1.10.20")
        let updater = makeUpdater(version: "1.10.20", archive: nil)
        for installed in ["1.10.20", "1.10.21", "мусор"] {
            XCTAssertThrowsError(try updater.verify(archive: try goodZip("1.10.20"), product: pimp, version: "1.10.20", installed: installed)) { error in
                guard case SelfUpdateError.version = error else { return XCTFail("\(installed): \(error)") }
            }
        }
        XCTAssertEqual(leftovers(), [], "распаковка убрана")
    }

    func testWrongSizeOrChecksumIsRefused() throws {
        let archive = try goodZip("1.10.20")
        try assertRefused(makeUpdater(version: "1.10.20", archive: archive, json: releaseJSON("1.10.20", size: size(archive) + 1)), "размер")
        clock += SelfUpdater.refusedPause
        let wrong = releaseJSON("1.10.20", size: size(archive), digest: String(repeating: "0", count: 64))
        try assertRefused(makeUpdater(version: "1.10.20", archive: archive, json: wrong), "сумма не сошлась")
        XCTAssertEqual(signatureCalls, [], "до подписи дело не дошло — архив даже не распаковывали")
        // Верная сумма из выпуска — проходит.
        clock += SelfUpdater.refusedPause
        let right = releaseJSON("1.10.20", size: size(archive), digest: try ClaudeUpdater.sha256(of: archive))
        XCTAssertEqual(makeUpdater(version: "1.10.20", archive: archive, json: right).check(pimp, app: installedApp).ready, "1.10.20")
    }

    func testRefusedVersionIsNotDownloadedAgainForADay() throws {
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.checks.gatekeeper = { _ in "rejected" }
        try assertRefused(updater, "Gatekeeper")
        updater.check(pimp, app: installedApp)
        XCTAssertEqual(downloads, 1, "тот же битый выпуск не качаем каждые 6 часов")
        clock += SelfUpdater.refusedPause
        updater.checks.gatekeeper = { _ in nil }
        XCTAssertEqual(updater.check(pimp, app: installedApp).ready, "1.10.20", "через сутки — ещё попытка")
        XCTAssertEqual(downloads, 2)
    }

    // ---------------------------------------------------------------- подмена

    func testSwapKeepsOnePreviousVersionAndVerifiesAgainBeforeAndAfter() throws {
        try makeApp(in: apps, version: "1.10.19")
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        XCTAssertEqual(signatureCalls.count, 1)
        var confirmedAt: String?
        let note = try updater.install(pimp, app: installedApp, confirm: {
            confirmedAt = self.installedVersion()
            return true
        })
        XCTAssertEqual(note, SelfUpdateState.Note(product: "pimp", from: "1.10.19", to: "1.10.20"))
        XCTAssertEqual(confirmedAt, "1.10.19", "момент спрашивают до подмены")
        XCTAssertEqual(installedVersion(), "1.10.20")
        // Подпись: при загрузке, заново прямо перед подменой (распаковка) и ещё раз на месте (находка М7).
        XCTAssertEqual(signatureCalls.count, 3)
        XCTAssertTrue(signatureCalls[1].contains("/unpack-"))
        XCTAssertEqual(URL(fileURLWithPath: signatureCalls[2]).resolvingSymlinksInPath().path, installedApp.resolvingSymlinksInPath().path)
        let rollback = store.appendingPathComponent("rollback", isDirectory: true)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: rollback.path), ["PimpMyClaude-1.10.19.previous"])
        XCTAssertEqual(SelfUpdater.installedVersion(rollback.appendingPathComponent("PimpMyClaude-1.10.19.previous"), bundleID: pimp.bundleID), "1.10.19")
        XCTAssertEqual(mode(rollback), 0o700)
        XCTAssertEqual(leftovers(), [], "архив и распаковка убраны")
        let state = updater.loadState()
        XCTAssertNil(state.products["pimp"]?.ready)
        XCTAssertEqual(SelfUpdater.noteLine(state.notes), "Пимп обновился до 1.10.20")
        XCTAssertNil(try updater.install(pimp, app: installedApp), "второй раз ставить нечего")
        updater.clearNotes()
        XCTAssertNil(SelfUpdater.noteLine(updater.loadState().notes))

        // Следующая версия: в папке отката остаётся ОДНА прошлая.
        updater = makeUpdater(version: "1.10.21", archive: try goodZip("1.10.21"))
        clock += SelfUpdater.checkInterval
        updater.check(pimp, app: installedApp)
        XCTAssertNotNil(try updater.install(pimp, app: installedApp))
        XCTAssertEqual(installedVersion(), "1.10.21")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: rollback.path), ["PimpMyClaude-1.10.20.previous"])
    }

    func testFailedSwapPutsOldAppBack() throws {
        try makeApp(in: apps, version: "1.10.19")
        try Data("старое".utf8).write(to: installedApp.appendingPathComponent("Contents/marker"))
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        // Подпись сходится в распаковке и не сходится уже на месте — подменили между проверкой и подменой.
        let place = installedApp.resolvingSymlinksInPath().path
        updater.checks.signature = { app, _ in app.resolvingSymlinksInPath().path == place ? "invalid signature" : nil }
        XCTAssertThrowsError(try updater.install(pimp, app: installedApp)) { error in
            XCTAssertEqual(error as? SelfUpdateError, .swap("после подмены подпись не сошлась (invalid signature)", restored: true))
        }
        XCTAssertEqual(installedVersion(), "1.10.19", "прежняя версия вернулась")
        XCTAssertTrue(fm.fileExists(atPath: installedApp.appendingPathComponent("Contents/marker").path), "та же самая папка")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: store.appendingPathComponent("rollback").path), [], "в откате ничего не осталось")
        XCTAssertEqual(leftovers(), [], "чужой бандл и архив удалены")
        let entry = updater.loadState().products["pimp"]
        XCTAssertNil(entry?.ready)
        XCTAssertEqual(entry?.refused, "1.10.20")
        XCTAssertEqual(updater.loadState().notes, [], "«обновился» не говорим")
    }

    /// Находка R1 проверки 10.10.2026: обмен, в котором отказала macOS, — отказ на сутки, а не повтор на каждом
    /// запуске с обещанием «встанет при следующем запуске».
    func testSwapRefusedByMacOSIsARefusalNotAnEndlessRetry() throws {
        try makeApp(in: apps, version: "1.10.19")
        let updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedApp.path) }
        // Место проверено, архив распакован и проверен — и тут бандл закрыт от записи: обмен отвечает EACCES.
        XCTAssertThrowsError(try updater.install(pimp, app: installedApp, confirm: {
            try? self.fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: self.installedApp.path)
            return true
        })) { error in
            guard case SelfUpdateError.swap(let why, restored: true) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(why.contains("errno \(EACCES)"), why)
        }
        XCTAssertEqual(installedVersion(), "1.10.19", "стоящее приложение не тронуто")
        let entry = try XCTUnwrap(updater.loadState().products["pimp"])
        XCTAssertNil(entry.ready, "«скачано — встанет» больше не обещаем")
        XCTAssertEqual(entry.refused, "1.10.20")
        XCTAssertEqual(entry.refusedAt, clock)
        XCTAssertTrue(entry.refusedWhy?.contains("errno \(EACCES)") == true, entry.refusedWhy ?? "нет причины")
        XCTAssertEqual(leftovers(), [], "архив и распаковка убраны")
        XCTAssertEqual(SelfUpdater.statusLine(installed: "1.10.19", state: entry, enabled: true, place: nil, now: clock),
                       "Стоит 1.10.19 · 1.10.20 не встала на место — не ставлю")
        XCTAssertTrue(try String(contentsOf: store.appendingPathComponent("journal.log"), encoding: .utf8)
            .contains("pimp: 1.10.20 не ставлю — подмена сорвалась"))
        // Следующие моменты и проверки: ни распаковки, ни подписи, ни загрузки — сутки.
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedApp.path)
        signatureCalls = []
        XCTAssertNil(try updater.install(pimp, app: installedApp))
        updater.check(pimp, app: installedApp)
        XCTAssertEqual(signatureCalls, [])
        XCTAssertEqual(downloads, 1)
        clock += SelfUpdater.refusedPause
        XCTAssertEqual(updater.check(pimp, app: installedApp).ready, "1.10.20", "через сутки — ещё попытка")
        XCTAssertNotNil(try updater.install(pimp, app: installedApp))
        XCTAssertEqual(installedVersion(), "1.10.20")
    }

    /// Находка R1: бандл, в который этой учётке не записать, обменом не подменить — его и не качаем.
    func testBundleClosedForWritingIsNeitherAskedNorDownloaded() throws {
        try makeApp(in: apps, version: "1.10.19")
        let updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        XCTAssertNil(updater.placeProblem(installedApp, product: pimp))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: installedApp.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedApp.path) }
        let place = updater.placeProblem(installedApp, product: pimp)
        XCTAssertEqual(place, "Пимп в «Программах» закрыт от записи")
        updater.check(pimp, app: installedApp)
        XCTAssertEqual(asked, 0, "поставить не сможем — и спрашивать незачем")
        XCTAssertEqual(downloads, 0)
        XCTAssertEqual(SelfUpdater.statusLine(installed: "1.10.19", state: nil, enabled: true, place: place, now: clock),
                       "Стоит 1.10.19 · Пимп в «Программах» закрыт от записи — сам не обновится")
    }

    /// Находка R2: посреди работы канала «Пимп» и возврата окон Пимп себя не подменяет; Viewer это не держит.
    func testPimpDoesNotSwapItselfWhileWindowsSettle() {
        XCTAssertFalse(SelfUpdater.mayInstall(.pimp, SelfUpdateMoment(windows: true)))
        XCTAssertTrue(SelfUpdater.mayInstall(.viewer, SelfUpdateMoment(windows: true)), "подмена Viewer Пимп не перезапускает")
        XCTAssertFalse(SelfUpdater.mayInstall(.viewer, SelfUpdateMoment(viewerRunning: true, windows: true)))
    }

    // ---------------------------------------------------------------- мелкие находки R3–R9 проверки 10.10.2026

    /// R3: шаг проверки перед подменой не уложился в срок (завис syspolicyd) — ждать перестаём, но версия от
    /// этого не плохая: архив и `ready` остаются до следующего момента, на сутки ничего не откладывается.
    func testMissedDeadlineAtInstallKeepsTheVerifiedArchiveForNextTime() throws {
        try makeApp(in: apps, version: "1.10.19")
        try Data("старое".utf8).write(to: installedApp.appendingPathComponent("Contents/marker"))
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        updater.patience = 0.5
        func assertWaits(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
            let started = Date()
            XCTAssertThrowsError(try updater.install(pimp, app: installedApp), what, file: file, line: line) { error in
                guard case SelfUpdateError.timeout = error else { return XCTFail("\(what): \(error)", file: file, line: line) }
            }
            XCTAssertLessThan(Date().timeIntervalSince(started), 2.5, "\(what): ждём не дольше срока", file: file, line: line)
            XCTAssertEqual(installedVersion(), "1.10.19", what, file: file, line: line)
            XCTAssertTrue(fm.fileExists(atPath: installedApp.appendingPathComponent("Contents/marker").path), what, file: file, line: line)
            XCTAssertEqual(leftovers(), ["PimpMyClaude-1.10.20.zip"], "\(what): архив ждёт, распаковка убрана", file: file, line: line)
            let entry = updater.loadState().products["pimp"]
            XCTAssertEqual(entry?.ready, "1.10.20", what, file: file, line: line)
            XCTAssertNil(entry?.refused, "\(what): на сутки не отложена", file: file, line: line)
            XCTAssertEqual(SelfUpdater.statusLine(installed: "1.10.19", state: entry, enabled: true, place: nil, now: clock),
                           "Скачано 1.10.20 — встанет при следующем запуске", file: file, line: line)
        }
        updater.checks.gatekeeper = { _ in Thread.sleep(forTimeInterval: 3); return nil }
        assertWaits("Gatekeeper завис")
        updater.checks.gatekeeper = { _ in nil }
        updater.checks.signature = { _, _ in Thread.sleep(forTimeInterval: 3); return nil }
        assertWaits("проверка подписи зависла")
        // Зависла уже на месте, после обмена: прежнее приложение возвращается, версия ждёт дальше.
        let place = installedApp.resolvingSymlinksInPath().path
        updater.checks.signature = { app, _ in
            if app.resolvingSymlinksInPath().path == place { Thread.sleep(forTimeInterval: 3) }
            return nil
        }
        assertWaits("проверка подписи зависла после обмена")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: store.appendingPathComponent("rollback").path), [], "в откате ничего не осталось")
        XCTAssertTrue(try String(contentsOf: store.appendingPathComponent("journal.log"), encoding: .utf8)
            .contains("pimp: 1.10.20 пока не встала — не дождался"))
        // Следующий момент, проверки отвечают — встаёт без новой загрузки.
        updater.patience = 60
        updater.checks.signature = { _, _ in nil }
        XCTAssertNotNil(try updater.install(pimp, app: installedApp))
        XCTAssertEqual(installedVersion(), "1.10.20")
        XCTAssertEqual(downloads, 1)
    }

    /// R3, обратная сторона: при ЗАГРУЗКЕ версия ещё ни разу не проверена — не дождались проверки, значит отказ.
    func testMissedDeadlineAtDownloadIsStillARefusal() throws {
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.patience = 0.5
        updater.checks.gatekeeper = { _ in Thread.sleep(forTimeInterval: 3); return nil }
        try assertRefused(updater, "не дождался")
    }

    /// R5: gh ходит только на github.com и только в наш репозиторий, что бы ни стояло в окружении.
    func testGhGoesToGitHubWhateverTheEnvironmentSays() throws {
        let environment = SelfUpdater.ghEnvironment([
            "HOME": "/Users/x", "GH_TOKEN": "t", "PATH": "/tmp/evil/bin", "GH_HOST": "evil.example", "GH_REPO": "evil/repo",
            "GH_ENTERPRISE_TOKEN": "e", "GH_CONFIG_DIR": "/tmp/evil", "GH_DEBUG": "api"])
        XCTAssertEqual(environment, ["HOME": "/Users/x", "GH_TOKEN": "t", "PATH": "/usr/bin:/bin", "GH_PROMPT_DISABLED": "1",
                                     "GH_NO_UPDATE_NOTIFIER": "1", "NO_COLOR": "1"])
        XCTAssertEqual(SelfUpdater.ghLatestArguments(pimp),
                       ["api", "--hostname", "github.com", "repos/ElvisIglikov/PimpMyClaude/releases/latest"])
        let release = try SelfUpdater.parseRelease(releaseJSON("1.10.20"), product: pimp)
        XCTAssertEqual(SelfUpdater.ghDownloadArguments(release, pimp, to: URL(fileURLWithPath: "/tmp/a.zip")),
                       ["release", "download", "v1.10.20", "-R", "github.com/ElvisIglikov/PimpMyClaude", "-p", "PimpMyClaude-1.10.20.zip",
                        "-O", "/tmp/a.zip", "--clobber"])
    }

    /// R6: подпись права не покрывает — бандл, куда пишет группа или кто угодно, не ставим.
    func testBundleWritableByGroupOrOthersIsRefused() throws {
        let file = try zip {
            let app = try self.makeApp(in: $0, version: "1.10.20")
            try self.fm.setAttributes([.posixPermissions: 0o666], ofItemAtPath: app.appendingPathComponent("Contents/Info.plist").path)
        }
        try assertRefused(makeUpdater(version: "1.10.20", archive: file), "пишет не только хозяин: Contents/Info.plist")
        clock += SelfUpdater.refusedPause
        let folder = try zip {
            let app = try self.makeApp(in: $0, version: "1.10.20")
            try self.fm.setAttributes([.posixPermissions: 0o775], ofItemAtPath: app.path)
        }
        try assertRefused(makeUpdater(version: "1.10.20", archive: folder), "пишет не только хозяин: .")
        XCTAssertNil(SelfUpdater.writableByOthers(installedApp), "обычные права 755/644 проходят")
    }

    /// R6: пришло больше, чем обещал выпуск, — загрузка обрывается сразу, а не сверяется с потолком в конце.
    func testDownloadIsCutOffWhenMoreThanPromisedArrives() throws {
        let url = URL(string: "https://github.com/ElvisIglikov/PimpMyClaude/releases/download/v1.10.20/PimpMyClaude-1.10.20.zip")!
        let file = scratch.appendingPathComponent("flood.zip")
        Flood.start(chunks: 400)
        let answer = SelfUpdater.http(url, timeout: 10, resource: 60, file: file, limit: 200_000, protocols: [Flood.self])
        guard case .overflow = answer else { return XCTFail("\(answer)") }
        XCTAssertLessThan(Flood.sent, 400, "оборвана, не дожидаясь конца")
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        // Столько, сколько обещано, — доходит до конца.
        Flood.start(chunks: 2)
        guard case .ok = SelfUpdater.http(url, timeout: 10, resource: 60, file: file, limit: Int64(2 * Flood.chunk),
                                          protocols: [Flood.self]) else { return XCTFail("ровно обещанное должно пройти") }
        XCTAssertEqual(size(file), Int64(2 * Flood.chunk))
    }

    /// R6: оборванная загрузка — изъян выпуска, а не связи: отказ на сутки, а не новая попытка на каждом круге.
    func testOversizedDownloadIsARefusalNotARetry() throws {
        var updater = makeUpdater(version: "1.10.20", archive: nil)
        updater.transport.download = { _, _, file in
            self.downloads += 1
            try? Data("хвост".utf8).write(to: file)
            return .failure(.archive("пришло больше 1000 байт, обещанных выпуском"))
        }
        try assertRefused(updater, "пришло больше 1000 байт")
        updater.check(pimp, app: installedApp)
        XCTAssertEqual(downloads, 1)
    }

    /// R7: проверяется раскрытый путь — по нему же и меняем: ярлык в «Программах» остаётся ярлыком, а новая
    /// версия встаёт туда, куда он ведёт.
    func testSwapGoesToTheResolvedPlaceNotToTheSymlink() throws {
        let home = scratch.appendingPathComponent("Home/Applications", isDirectory: true)
        let real = try makeApp(in: home, version: "1.10.19")
        try fm.createSymbolicLink(at: installedApp, withDestinationURL: real)
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.allowedParents = [apps, home]
        XCTAssertNil(updater.placeProblem(installedApp, product: pimp))
        XCTAssertEqual(updater.check(pimp, app: installedApp).ready, "1.10.20")
        XCTAssertNotNil(try updater.install(pimp, app: installedApp))
        XCTAssertEqual(try fm.attributesOfItem(atPath: installedApp.path)[.type] as? FileAttributeType, .typeSymbolicLink,
                       "ярлык остался ярлыком")
        XCTAssertEqual(SelfUpdater.installedVersion(real, bundleID: pimp.bundleID), "1.10.20")
        XCTAssertEqual(SelfUpdater.installedVersion(store.appendingPathComponent("rollback/PimpMyClaude-1.10.19.previous"),
                                                    bundleID: pimp.bundleID), "1.10.19")
    }

    /// R7: имя в папке отката занято и не убирается — прежняя версия ложится рядом, а не пропадает с распаковкой.
    func testPreviousVersionSurvivesWhenItsRollbackNameIsTaken() throws {
        try makeApp(in: apps, version: "1.10.19")
        let updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        let rollback = store.appendingPathComponent("rollback", isDirectory: true)
        let stuck = rollback.appendingPathComponent("PimpMyClaude-1.10.19.previous", isDirectory: true)
        try fm.createDirectory(at: stuck, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: stuck.appendingPathComponent("хвост"))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: stuck.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stuck.path) }
        XCTAssertNotNil(try updater.install(pimp, app: installedApp))
        XCTAssertEqual(installedVersion(), "1.10.20")
        let kept = try fm.contentsOfDirectory(atPath: rollback.path).filter {
            SelfUpdater.installedVersion(rollback.appendingPathComponent($0), bundleID: pimp.bundleID) == "1.10.19"
        }
        XCTAssertEqual(kept.count, 1, "прежняя версия — в папке отката под запасным именем")
        XCTAssertTrue(kept.first?.hasSuffix(".previous") == true)
    }

    /// R8: выключатель читается перед каждым шагом круга — выключили посреди проверки, дальше ничего не идёт.
    func testSwitchedOffRoundStopsBeforeTheNextStep() throws {
        try makeApp(in: apps, version: "1.10.19")
        let updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        var entry = updater.check(pimp, app: installedApp, proceed: { false })
        XCTAssertEqual(asked, 0, "выключено — выпуск не спрашиваем")
        XCTAssertNil(entry.latest)
        // Выключили, пока шёл запрос выпуска.
        entry = updater.check(pimp, app: installedApp, proceed: { self.asked == 0 })
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(entry.latest, "1.10.20")
        XCTAssertEqual(downloads, 0, "архив не качаем")
        // Выключили, пока качался архив: не проверяем и не держим.
        entry = updater.check(pimp, app: installedApp, proceed: { self.downloads == 0 })
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(signatureCalls, [])
        XCTAssertNil(entry.ready)
        XCTAssertNil(entry.refused, "выключатель — не отказ версии")
        XCTAssertEqual(leftovers(), [])
        XCTAssertEqual(updater.check(pimp, app: installedApp).ready, "1.10.20", "включили — круг доходит до конца")
    }

    /// R9: общий запуск утилит патчера и обновления Claude тоже со сроком — зависшая утилита не держит «занято» вечно.
    func testPatcherToolsHaveADeadlineToo() throws {
        XCTAssertEqual(try Shell.run("/bin/echo", ["привет"]), "привет")
        XCTAssertThrowsError(try Shell.run("/usr/bin/false", [])) { error in
            guard case PatchError.tool(name: "false", output: "код 1") = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try Shell.run("/нет/такой", [])) { error in
            guard case PatchError.tool(name: "такой", _) = error else { return XCTFail("\(error)") }
        }
        let started = Date()
        XCTAssertThrowsError(try Shell.run("/bin/sleep", ["30"], timeout: 0.3)) { error in
            guard case PatchError.tool(name: "sleep", _) = error else { return XCTFail("\(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testArchiveChangedAfterVerificationIsNotInstalled() throws {
        try makeApp(in: apps, version: "1.10.19")
        let updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        // Архив в папке подменили другим — тоже «1.10.20», но не тем, что проверяли.
        let planted = try zip {
            try self.makeApp(in: $0, version: "1.10.20")
            try Data("чужое".utf8).write(to: $0.appendingPathComponent("PimpMyClaude.app/Contents/planted"))
        }
        let archive = store.appendingPathComponent("PimpMyClaude-1.10.20.zip")
        try fm.removeItem(at: archive)
        try fm.copyItem(at: planted, to: archive)
        signatureCalls = []
        XCTAssertThrowsError(try updater.install(pimp, app: installedApp)) { error in
            XCTAssertEqual(error as? SelfUpdateError, .archive("изменился после проверки"))
        }
        XCTAssertEqual(signatureCalls, [], "подменённый архив даже не распаковывали")
        XCTAssertEqual(installedVersion(), "1.10.19")
        XCTAssertEqual(leftovers(), [])
        XCTAssertEqual(updater.loadState().products["pimp"]?.refused, "1.10.20")
    }

    func testSignatureIsCheckedAgainRightBeforeSwap() throws {
        try makeApp(in: apps, version: "1.10.19")
        var updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        // При загрузке подпись прошла; к моменту установки — нет (сертификат отозван, файл испорчен).
        updater.checks.signature = { _, _ in "CSSMERR_TP_CERT_REVOKED" }
        var confirmed = false
        XCTAssertThrowsError(try updater.install(pimp, app: installedApp, confirm: { confirmed = true; return true })) { error in
            XCTAssertEqual(error as? SelfUpdateError, .signature("CSSMERR_TP_CERT_REVOKED"))
        }
        XCTAssertFalse(confirmed, "до подмены не дошло")
        XCTAssertEqual(installedVersion(), "1.10.19")
        XCTAssertEqual(leftovers(), [], "архив удалён")
        XCTAssertFalse(fm.fileExists(atPath: store.appendingPathComponent("rollback").path))
    }

    func testMomentGoneKeepsEverythingForNextTime() throws {
        try makeApp(in: apps, version: "1.10.19")
        let updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        // Пока распаковывали и проверяли, человек открыл панель.
        XCTAssertNil(try updater.install(pimp, app: installedApp, confirm: { false }))
        XCTAssertEqual(installedVersion(), "1.10.19")
        XCTAssertEqual(leftovers(), ["PimpMyClaude-1.10.20.zip"], "архив ждёт следующего момента, распаковка убрана")
        XCTAssertEqual(updater.loadState().products["pimp"]?.ready, "1.10.20")
        XCTAssertNotNil(try updater.install(pimp, app: installedApp))
        XCTAssertEqual(installedVersion(), "1.10.20")
    }

    func testManualUpdateMakesDownloadedArchiveUseless() throws {
        try makeApp(in: apps, version: "1.10.19")
        let updater = makeUpdater(version: "1.10.20", archive: try goodZip("1.10.20"))
        updater.check(pimp, app: installedApp)
        // Человек поставил ту же (или более новую) версию руками — скачанное не ставим: не ниже и не равно.
        try fm.removeItem(at: installedApp)
        try makeApp(in: apps, version: "1.10.20")
        XCTAssertNil(try updater.install(pimp, app: installedApp))
        XCTAssertEqual(leftovers(), [])
        XCTAssertNil(updater.loadState().products["pimp"]?.ready)
        XCTAssertFalse(fm.fileExists(atPath: store.appendingPathComponent("rollback").path))
    }

    func testViewerIsUpdatedByItsOwnNameAndBundleID() throws {
        let viewer = SelfUpdateProduct.viewer
        let app = try makeApp(in: apps, name: "PimpViewer.app", version: "1.10.7", bundleID: viewer.bundleID)
        let archive = try zip { try self.makeApp(in: $0, name: "PimpViewer.app", version: "1.10.8", bundleID: viewer.bundleID) }
        let json = releaseJSON("1.10.8", product: viewer, size: size(archive))
        let updater = makeUpdater(version: "1.10.8", archive: archive, json: json)
        XCTAssertEqual(updater.check(viewer, app: app).ready, "1.10.8")
        XCTAssertEqual(SelfUpdater.viewerLine(installed: "1.10.7", state: updater.loadState().products["viewer"]),
                       "Viewer 1.10.8 скачан — встанет, когда его закроешь")
        XCTAssertEqual(try updater.install(viewer, app: app)?.to, "1.10.8")
        XCTAssertEqual(SelfUpdater.installedVersion(app, bundleID: viewer.bundleID), "1.10.8")
        XCTAssertEqual(SelfUpdater.noteLine(updater.loadState().notes), "Viewer обновился до 1.10.8")
        XCTAssertNil(SelfUpdater.viewerLine(installed: "1.10.8", state: updater.loadState().products["viewer"]))
    }

    // ---------------------------------------------------------------- слова панели

    func testStatusLine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_780_000_000) // 28.05.2026 20:26 UTC
        func line(_ state: SelfUpdateState.Product?, enabled: Bool = true, place: String? = nil) -> String {
            SelfUpdater.statusLine(installed: "1.10.19", state: state, enabled: enabled, place: place, now: now, calendar: calendar)
        }
        var state = SelfUpdateState.Product()
        XCTAssertEqual(line(nil), "Стоит 1.10.19")
        XCTAssertEqual(line(state), "Стоит 1.10.19")
        state.checkedAt = now.addingTimeInterval(-3600)
        XCTAssertEqual(line(state), "Стоит 1.10.19 · проверено сегодня в 19:26")
        state.checkedAt = now.addingTimeInterval(-24 * 3600)
        XCTAssertEqual(line(state), "Стоит 1.10.19 · проверено вчера в 20:26")
        state.checkedAt = now.addingTimeInterval(-3 * 24 * 3600)
        XCTAssertEqual(line(state), "Стоит 1.10.19 · проверено 25.05 в 20:26")
        state.problem = .offline
        XCTAssertEqual(line(state), "Стоит 1.10.19 · нет связи с GitHub")
        state.problem = nil
        state.refused = "1.10.20"
        XCTAssertEqual(line(state), "Стоит 1.10.19 · 1.10.20 не прошла проверку — не ставлю")
        state.ready = "1.10.20"
        XCTAssertEqual(line(state), "Скачано 1.10.20 — встанет при следующем запуске")
        XCTAssertEqual(line(state, enabled: false), "Стоит 1.10.19", "выключено — только что стоит")
        XCTAssertEqual(line(state, place: "Пимп лежит не в «Программах»"), "Стоит 1.10.19 · Пимп лежит не в «Программах» — сам не обновится")
        state.ready = "1.10.19"
        state.refused = "1.10.18"
        state.checkedAt = now
        XCTAssertEqual(line(state), "Стоит 1.10.19 · проверено сегодня в 20:26", "скачанное и отказанное не новее стоящего — не про них")
        let notes = [SelfUpdateState.Note(product: "pimp", from: "1.10.18", to: "1.10.19"),
                     SelfUpdateState.Note(product: "viewer", from: "1.10.7", to: "1.10.8"),
                     SelfUpdateState.Note(product: "pimp", from: "1.10.19", to: "1.10.20")]
        XCTAssertEqual(SelfUpdater.noteLine(notes), "Пимп обновился до 1.10.20 · Viewer обновился до 1.10.8")
        XCTAssertNil(SelfUpdater.noteLine([]))
    }

    // ---------------------------------------------------------------- настоящие проверки и утилиты

    /// Настоящая проверка подписи (Security) на подставных бандлах: без подписи и с локальной подписью —
    /// отказ; требование к подписи разбирается системой и названо как у Developer ID.
    func testLiveSignatureCheckRejectsUnsignedAndAdHoc() throws {
        for product in [SelfUpdateProduct.pimp, .viewer] {
            var parsed: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(product.requirement as CFString, SecCSFlags(), &parsed), errSecSuccess, product.key)
        }
        XCTAssertEqual(pimp.requirement, #"identifier "com.elvis.pimpmyclaude" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "F27N4S4NJ4""#)
        let app = try makeApp(in: scratch.appendingPathComponent("live", isDirectory: true), version: "1.10.20")
        XCTAssertNotNil(SelfUpdateChecks.live.signature(app, pimp.requirement), "без подписи")
        // Локальная подпись с тем же bundle id: сама подпись цела, но это не Developer ID F27N4S4NJ4.
        try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/PimpMyClaude"))
        let plist: [String: Any] = ["CFBundleIdentifier": pimp.bundleID, "CFBundleShortVersionString": "1.10.20",
                                    "CFBundleExecutable": "PimpMyClaude", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        XCTAssertNil(SelfUpdater.signatureProblem(app, requirement: "identifier \"\(pimp.bundleID)\""), "локальная подпись сама по себе цела")
        XCTAssertNotNil(SelfUpdateChecks.live.signature(app, pimp.requirement), "локальная подпись — не Developer ID автора")
        XCTAssertNotNil(SelfUpdateChecks.live.signature(app, SelfUpdateProduct.viewer.requirement), "и bundle id не тот")
        // Тронули файл после подписи — строгая проверка это видит.
        try Data("x".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNotNil(SelfUpdater.signatureProblem(app, requirement: "identifier \"\(pimp.bundleID)\""))
    }

    func testGhIsTakenOnlyFromFilesOthersCannotWrite() throws {
        let bin = scratch.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        func file(_ name: String, mode: Int) throws -> String {
            let url = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\n".utf8).write(to: url)
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
            return url.path
        }
        let good = try file("gh-good", mode: 0o755)
        XCTAssertEqual(SelfUpdater.ghExecutable([good]).map { URL(fileURLWithPath: $0).lastPathComponent }, "gh-good")
        XCTAssertNil(SelfUpdater.ghExecutable([try file("gh-world", mode: 0o757)]), "пишут все")
        XCTAssertNil(SelfUpdater.ghExecutable([try file("gh-group", mode: 0o775)]), "пишет группа")
        XCTAssertNil(SelfUpdater.ghExecutable([try file("gh-plain", mode: 0o644)]), "не исполняемый")
        XCTAssertNil(SelfUpdater.ghExecutable([bin.path]), "папка")
        XCTAssertNil(SelfUpdater.ghExecutable([bin.appendingPathComponent("нет").path]))
        // Ярлык (как у Homebrew) — судим по самому файлу.
        let link = bin.appendingPathComponent("gh")
        try fm.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: try file("gh-open", mode: 0o777)))
        XCTAssertNil(SelfUpdater.ghExecutable([link.path]))
        XCTAssertEqual(SelfUpdater.ghExecutable([link.path, good]).map { URL(fileURLWithPath: $0).lastPathComponent }, "gh-good")
    }

    func testToolRunnerHasADeadline() {
        XCTAssertEqual(SelfUpdater.run("/bin/echo", ["привет"], timeout: 5)?.output, "привет")
        XCTAssertEqual(SelfUpdater.run("/usr/bin/false", [], timeout: 5)?.status, 1)
        let started = Date()
        XCTAssertNil(SelfUpdater.run("/bin/sleep", ["30"], timeout: 0.3), "не уложилась — погашена")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertNil(SelfUpdater.run("/нет/такой", [], timeout: 1))
    }

    /// Помощник перезапуска ждёт выхода процесса и только потом открывает приложение.
    func testRelaunchHelperWaitsForExit() throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["1"]
        try sleeper.run()
        let marker = scratch.appendingPathComponent("opened with space")
        XCTAssertTrue(SelfUpdater.relaunch(marker, afterExitOf: sleeper.processIdentifier, opener: "/usr/bin/touch"))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(fm.fileExists(atPath: marker.path), "процесс ещё жив — открывать рано")
        sleeper.waitUntilExit()
        let deadline = Date().addingTimeInterval(5)
        while !fm.fileExists(atPath: marker.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertTrue(fm.fileExists(atPath: marker.path), "процесс вышел — приложение открыто")
    }
}

/// Подставной сервер для `SelfUpdater.http`: отдаёт `chunks` кусков по 64 КБ без заголовка длины, пока не оборвут.
private final class Flood: URLProtocol {
    static let chunk = 64 * 1024
    private static let lock = NSLock()
    private static var total = 0
    private static var count = 0
    static var sent: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func start(chunks: Int) { lock.lock(); total = chunks; count = 0; lock.unlock() }
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { stopped = true }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global().async {
            while !self.stopped {
                Flood.lock.lock()
                let more = Flood.count < Flood.total
                if more { Flood.count += 1 }
                Flood.lock.unlock()
                guard more else {
                    self.client?.urlProtocolDidFinishLoading(self)
                    return
                }
                self.client?.urlProtocol(self, didLoad: Data(count: Flood.chunk))
                usleep(5_000)
            }
        }
    }
}
