import XCTest
@testable import Patcher

/// Обновитель Claude (WF84, #7078/#7079). Весь путь — на копиях во временной папке:
/// живой /Applications и работающий Claude не трогаются (`signsApp`, `managesClaudeProcess` выключены).
final class ClaudeUpdaterTests: XCTestCase {
    private var scratch: URL!
    private var apps: URL!
    private var support: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimpmyclaude-updater-\(UUID().uuidString)", isDirectory: true)
        apps = scratch.appendingPathComponent("Applications", isDirectory: true)
        support = scratch.appendingPathComponent("Support", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch = scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    // ---------------------------------------------------------------- чистые правила

    func testVersionsCompareByNumbers() {
        XCTAssertEqual(ClaudeUpdater.compareVersions("2.2553.13", "2.2553.2"), .orderedDescending)
        XCTAssertEqual(ClaudeUpdater.compareVersions("2.2553.2", "2.2553.13"), .orderedAscending)
        XCTAssertEqual(ClaudeUpdater.compareVersions("2.2553.13", "2.2553.13"), .orderedSame)
        XCTAssertEqual(ClaudeUpdater.compareVersions("2.3", "2.2553.13"), .orderedAscending)
        XCTAssertEqual(ClaudeUpdater.compareVersions("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(ClaudeUpdater.compareVersions("10.0.0", "9.9.9"), .orderedDescending)
        XCTAssertNil(ClaudeUpdater.compareVersions("2.x", "2.1"))
        XCTAssertNil(ClaudeUpdater.compareVersions("2..1", "2.1"))
        XCTAssertNil(ClaudeUpdater.compareVersions("", "2.1"))
    }

    func testPreviousCopyNameIsNotAnApp() {
        let name = ClaudeUpdater.previousName(appName: "Claude.app", version: "2.2553.13")
        XCTAssertEqual(name, "Claude-2.2553.13.previous")
        XCTAssertFalse(Patcher.isVisibleInstall(apps.appendingPathComponent(name)), "прежняя копия не должна считаться установкой")
        XCTAssertTrue(ClaudeUpdater.isOwnPrevious(name, appName: "Claude.app"))
        // Скрытые копии Элвиса и живой бандл — не наши, их не убирать никогда.
        for foreign in [".Claude-before-Matrix-1.20186.1.app", ".Claude 2-original-backup-2026-07-11",
                        ".Claude-2.2553.1.previous", "Claude.app", "Claude 2.app", "Claude-2.2553.1.app", "PimpMyClaude.app"] {
            XCTAssertFalse(ClaudeUpdater.isOwnPrevious(foreign, appName: "Claude.app"), foreign)
        }
    }

    func testSignatureRequirementPinsTeamAndBundle() {
        let requirement = ClaudeUpdater.signatureRequirement()
        XCTAssertEqual(requirement, #"identifier "com.anthropic.claudefordesktop" and anchor apple generic and certificate leaf[subject.OU] = "Q6L2SF6YDW""#)
    }

    // ---------------------------------------------------------------- путь на копии

    /// Поддельный бандл: Info.plist (при `asarFrom` — вместе с живым Info.plist и чистым app.asar).
    @discardableResult
    private func makeBundle(at app: URL, version: String, bundleID: String = Patcher.claudeBundleID,
                            asarFrom source: URL? = nil) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        var plist: [String: Any] = [:]
        if let source = source {
            let asar = app.appendingPathComponent("Contents/Resources/app.asar")
            try fm.copyItem(at: source.appendingPathComponent("Contents/Resources/app.asar"), to: asar)
            _ = try Asar.removeLoader(asar)
            let data = try Data(contentsOf: source.appendingPathComponent("Contents/Info.plist"))
            plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        }
        plist["CFBundleIdentifier"] = bundleID
        plist["CFBundleShortVersionString"] = version
        let out = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try out.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    /// Архив, как у Anthropic: `ditto -c -k --keepParent Claude.app`; релиз указывает на него через file://.
    private func makeRelease(version: String, bundleID: String = Patcher.claudeBundleID,
                             asarFrom source: URL? = nil) throws -> ClaudeRelease {
        let src = scratch.appendingPathComponent("src-\(UUID().uuidString)", isDirectory: true)
        let app = try makeBundle(at: src.appendingPathComponent("Claude.app"), version: version, bundleID: bundleID, asarFrom: source)
        let zip = src.appendingPathComponent("Claude.zip")
        try Shell.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        let size = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as! NSNumber
        return ClaudeRelease(version: version, url: zip, sha256: try ClaudeUpdater.sha256(of: zip), size: size.int64Value)
    }

    private func makeUpdater() -> ClaudeUpdater {
        var updater = ClaudeUpdater(appURL: apps.appendingPathComponent("Claude.app"), supportDirectory: support, resourcesDirectory: nil)
        updater.signsApp = false
        updater.managesClaudeProcess = false
        updater.checksSignature = false
        return updater
    }

    private func version(of app: URL) throws -> String {
        try ClaudePatcher(appURL: app, supportDirectory: support, resourcesDirectory: nil).appVersion()
    }

    private func listing() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []).sorted()
    }

    /// Весь путь: скачать → проверить → подмена → патч; прежняя копия одна, чужие скрытые на месте.
    func testFullUpdateOnCopy() throws {
        let live = Patcher.locateClaude().first
        try XCTSkipUnless(live.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Resources/app.asar").path) } ?? false,
                          "Claude.app не найден — нечем собрать копию с настоящим app.asar")
        let fm = FileManager.default
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "2.2553.13", asarFrom: live!)
        // Чужая скрытая копия и наша прежняя копия с прошлого обновления.
        let hidden = apps.appendingPathComponent(".Claude-before-Matrix-1.20186.1.app/Contents", isDirectory: true)
        try fm.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: hidden.appendingPathComponent("marker"))
        try makeBundle(at: apps.appendingPathComponent("Claude-2.2553.1.previous"), version: "2.2553.1")

        let release = try makeRelease(version: "2.2554.0", asarFrom: live!)
        let prepared = try updater.prepare(release)
        XCTAssertEqual(try version(of: updater.appURL), "2.2553.13", "до install живой бандл не меняется")
        XCTAssertEqual(prepared.stagedApp.deletingLastPathComponent().lastPathComponent, ClaudeUpdater.stagingDirName)
        XCTAssertTrue(fm.fileExists(atPath: updater.archiveURL(release).path))

        let outcome = try updater.install(prepared, relaunch: false)
        XCTAssertEqual(outcome.from, "2.2553.13")
        XCTAssertEqual(outcome.to, "2.2554.0")
        if case .installed = outcome.patch {} else { XCTFail("на новом бандле ждали полную установку патча, а не \(outcome.patch)") }
        XCTAssertEqual(try version(of: updater.appURL), "2.2554.0")
        XCTAssertEqual(try Asar.status(of: updater.appURL.appendingPathComponent("Contents/Resources/app.asar")).loaderVersion,
                       Patcher.requiredLoaderVersion)
        XCTAssertEqual(try version(of: outcome.previous), "2.2553.13")
        XCTAssertEqual(listing(), [".Claude-before-Matrix-1.20186.1.app", "Claude-2.2553.13.previous", "Claude.app"],
                       "прежняя копия одна, распаковка убрана, чужая скрытая на месте")
        XCTAssertEqual(try String(contentsOf: hidden.appendingPathComponent("marker"), encoding: .utf8), "keep")
        XCTAssertFalse(fm.fileExists(atPath: updater.archiveURL(release).path), "архив после удачи не держим")
    }

    func testBadChecksumLeavesClaudeUntouched() throws {
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let good = try makeRelease(version: "1.0.1")
        let bad = ClaudeRelease(version: good.version, url: good.url, sha256: String(repeating: "0", count: 64), size: good.size)
        XCTAssertThrowsError(try updater.prepare(bad)) { error in
            guard case ClaudeUpdateError.checksumMismatch = error else { return XCTFail("\(error)") }
        }
        let short = ClaudeRelease(version: good.version, url: good.url, sha256: good.sha256, size: good.size + 1)
        XCTAssertThrowsError(try updater.prepare(short)) { error in
            guard case ClaudeUpdateError.sizeMismatch = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try version(of: updater.appURL), "1.0.0")
        XCTAssertEqual(listing(), ["Claude.app"], "распаковки не было")
    }

    func testWrongBundleIsRefusedBeforeClosingClaude() throws {
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let foreign = try makeRelease(version: "1.0.1", bundleID: "com.example.fake")
        XCTAssertThrowsError(try updater.prepare(foreign)) { error in
            guard case ClaudeUpdateError.wrongBundle = error else { return XCTFail("\(error)") }
        }
        // Фид обещал одну версию, а внутри другая.
        let liar = try makeRelease(version: "1.0.2")
        let claimed = ClaudeRelease(version: "1.0.3", url: liar.url, sha256: liar.sha256, size: liar.size)
        XCTAssertThrowsError(try updater.prepare(claimed)) { error in
            guard case ClaudeUpdateError.wrongBundle = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(listing(), ["Claude.app"])
    }

    func testUnsignedBundleFailsSignatureCheck() throws {
        var updater = makeUpdater()
        updater.checksSignature = true
        try makeBundle(at: updater.appURL, version: "1.0.0")
        XCTAssertThrowsError(try updater.prepare(try makeRelease(version: "1.0.1"))) { error in
            guard case ClaudeUpdateError.signature = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(listing(), ["Claude.app"])
    }

    func testNotNewerIsRefused() throws {
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "2.0.0")
        XCTAssertThrowsError(try updater.prepare(try makeRelease(version: "2.0.0"))) { error in
            guard case ClaudeUpdateError.notNewer = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try updater.prepare(try makeRelease(version: "1.9.9")))
    }

    /// Патч на новый бандл не лёг (здесь — в нём нет app.asar) — прежний Claude возвращается на место.
    func testPatchFailureBringsPreviousBack() throws {
        let fm = FileManager.default
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        try Data("old".utf8).write(to: updater.appURL.appendingPathComponent("Contents/Resources/marker"))
        let prepared = try updater.prepare(try makeRelease(version: "1.0.1"))
        XCTAssertThrowsError(try updater.install(prepared, relaunch: false)) { error in
            guard case ClaudeUpdateError.patchFailed(_, let restored, _) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(restored)
        }
        XCTAssertEqual(try version(of: updater.appURL), "1.0.0")
        XCTAssertTrue(fm.fileExists(atPath: updater.appURL.appendingPathComponent("Contents/Resources/marker").path))
        XCTAssertEqual(listing(), ["Claude.app"], "ни прежней копии, ни распаковки не осталось")
    }

    /// Между prepare и install Claude поменялся — подмены нет.
    func testInstallRefusesWhenInstalledVersionChanged() throws {
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let prepared = try updater.prepare(try makeRelease(version: "1.0.2"))
        try FileManager.default.removeItem(at: updater.appURL)
        try makeBundle(at: updater.appURL, version: "1.0.1")
        XCTAssertThrowsError(try updater.install(prepared, relaunch: false)) { error in
            guard case ClaudeUpdateError.changedMeanwhile = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try version(of: updater.appURL), "1.0.1")
    }

    /// Уже скачанный архив с верной суммой второй раз не качается.
    func testVerifiedArchiveIsReused() throws {
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let release = try makeRelease(version: "1.0.1")
        let first = try updater.prepare(release)
        try FileManager.default.removeItem(at: first.stagedApp.deletingLastPathComponent()) // распаковку убрали
        XCTAssertEqual(listing(), ["Claude.app"])
        try FileManager.default.removeItem(at: release.url) // источника больше нет — выручит только готовый архив
        var lines: [String] = []
        _ = try updater.prepare(release) { lines.append($0) }
        XCTAssertTrue(lines.contains { $0.contains("уже скачан") }, "\(lines)")
    }

    // ---------------------------------------------------------------- WF86: источники и выбор версии

    /// Форма `https://claudeapp.agentsmirror.com/latest/manifest`, снята живьём 25.09.2026.
    private let liveManifest = """
        {"schemaVersion":2,"generatedAt":"2026-09-24T20:52:36Z","version":"2.9939.2","sources":{"macos":{"universal":{\
        "platform":"darwin","arch":"universal","format":"dmg",\
        "redirect":"https://api.anthropic.com/api/desktop/darwin/universal/dmg/latest/redirect","version":"2.9939.2",\
        "url":"https://downloads.claude.ai/releases/darwin/universal/2.9939.2/Claude-d3e50475d5d6bb0c317560310200249dd61b87d8.dmg",\
        "contentLength":374386569,"sha256":"db9d09eda0131576960e5d5a4569335dc700664b8ffde534ef541cc8635aa587",\
        "assetName":"Claude-mac-universal.dmg"}},"windows":{}}}
        """
    private let liveRedirect = URL(string: "https://downloads.claude.ai/releases/darwin/universal/2.9939.2/Claude-d3e50475d5d6bb0c317560310200249dd61b87d8.dmg")!

    func testParsesLiveMirrorManifest() throws {
        let release = try ClaudeUpdater.parseMirrorManifest(Data(liveManifest.utf8))
        XCTAssertEqual(release.version, "2.9939.2")
        XCTAssertEqual(release.size, 374_386_569)
        XCTAssertEqual(release.sha256, "db9d09eda0131576960e5d5a4569335dc700664b8ffde534ef541cc8635aa587")
        XCTAssertEqual(release.format, .dmg)
        XCTAssertEqual(release.url, ClaudeUpdater.fastMirror)
        XCTAssertEqual(release.mirrors, [ClaudeUpdater.githubPinned("2.9939.2"), liveRedirect],
                       "тот же файл: GitHub по тегу версии и Anthropic по url манифеста")
    }

    func testBrokenManifestsAreRefused() {
        let good = liveManifest
        for broken in [
            "не json",
            good.replacingOccurrences(of: #""format":"dmg""#, with: #""format":"zip""#),
            good.replacingOccurrences(of: #""version":"2.9939.2","url""#, with: #""version":"2.x","url""#),
            good.replacingOccurrences(of: "db9d09ed", with: "zz9d09ed"),
            good.replacingOccurrences(of: #""contentLength":374386569"#, with: #""contentLength":true"#),
            good.replacingOccurrences(of: #""contentLength":374386569"#, with: #""contentLength":0"#),
        ] {
            XCTAssertThrowsError(try ClaudeUpdater.parseMirrorManifest(Data(broken.utf8)), broken)
        }
        // Чужая ссылка в url манифеста — в копии не идёт, сам релиз годится.
        let foreign = good.replacingOccurrences(of: "https://downloads.claude.ai/", with: "https://evil.example/")
        XCTAssertEqual(try ClaudeUpdater.parseMirrorManifest(Data(foreign.utf8)).mirrors, [ClaudeUpdater.githubPinned("2.9939.2")])
    }

    func testOfficialRedirectTarget() throws {
        let release = try ClaudeUpdater.parseOfficialRedirect(liveRedirect)
        XCTAssertEqual(release.version, "2.9939.2")
        XCTAssertEqual(release.url, liveRedirect)
        XCTAssertEqual(release.sha256, "", "редирект sha256 не даёт")
        XCTAssertEqual(release.size, 0)
        for bad in ["http://downloads.claude.ai/releases/darwin/universal/2.9939.2/C.dmg",
                    "https://evil.example/releases/darwin/universal/2.9939.2/C.dmg",
                    "https://downloads.claude.ai/releases/win32/x64/2.9939.2/C.msix",
                    "https://downloads.claude.ai/releases/darwin/universal/latest/C.dmg",
                    "https://downloads.claude.ai/releases/darwin/universal/2.9939.2/C.zip"] {
            XCTAssertThrowsError(try ClaudeUpdater.parseOfficialRedirect(URL(string: bad)!), bad)
        }
    }

    private func release(_ version: String, _ host: String = "downloads.claude.ai") -> ClaudeRelease {
        ClaudeRelease(version: version, url: URL(string: "https://\(host)/\(version).dmg")!, sha256: "", size: 0, format: .dmg)
    }

    struct Offline: Error {}

    /// «Последняя» — только когда ответили оба (#7639); молчание источника — «не узнал».
    func testLatestOnlyWhenEverySourceAnswered() throws {
        let mirror = release("2.0.0", "claudeapp.agentsmirror.com")
        let official = release("2.0.0")
        XCTAssertEqual(try ClaudeUpdater.combine(installed: "2.0.0", mirror: .success(mirror), official: .success(official)),
                       .latest(installed: "2.0.0", feed: "2.0.0"))
        XCTAssertThrowsError(try ClaudeUpdater.combine(installed: "2.0.0", mirror: .failure(Offline()), official: .success(official))) { error in
            XCTAssertTrue(ClaudeUpdater.describe(error).contains("зеркало"), ClaudeUpdater.describe(error))
        }
        XCTAssertThrowsError(try ClaudeUpdater.combine(installed: "2.0.0", mirror: .success(mirror), official: .failure(Offline())))
        XCTAssertThrowsError(try ClaudeUpdater.combine(installed: "2.0.0", mirror: .failure(Offline()), official: .failure(Offline()))) { error in
            let text = ClaudeUpdater.describe(error)
            XCTAssertTrue(text.contains("зеркало") && text.contains("Anthropic"), text)
        }
        // Новее хоть у одного — ответ есть и без второго.
        guard case .available(_, let found) = try ClaudeUpdater.combine(
            installed: "1.9.0", mirror: .failure(Offline()), official: .success(official)) else { return XCTFail() }
        XCTAssertEqual(found.version, "2.0.0")
    }

    /// Старое зеркало не прячет новый официальный, и наоборот: второй остаётся запасным.
    func testNewestWinsAndOtherStaysFallback() throws {
        let mirror = release("2.0.0", "claudeapp.agentsmirror.com")
        let official = release("2.1.0")
        guard case .available(_, let best) = try ClaudeUpdater.combine(
            installed: "1.0.0", mirror: .success(mirror), official: .success(official)) else { return XCTFail() }
        XCTAssertEqual(best.version, "2.1.0")
        XCTAssertEqual(best.fallbacks, [mirror])
        let newer = release("2.2.0", "claudeapp.agentsmirror.com")
        let flipped = try ClaudeUpdater.preferredRelease(mirror: newer, official: official)
        XCTAssertEqual(flipped.version, "2.2.0")
        XCTAssertEqual(flipped.fallbacks, [official], "зеркало провалится — выручит официальный, он тоже новее стоящего")
    }

    func testCheckFallsBackToGitHubAndReadsRedirect() throws {
        var updater = makeUpdater()
        updater.allowMirrors = true // Explicit legacy/opt-in policy keeps the mirror race.
        try makeBundle(at: updater.appURL, version: "2.9000.0")
        let github = """
            {"draft":false,"prerelease":false,"tag_name":"claude-app-v2.9939.2","assets":[{"name":"Claude-mac-universal.dmg",\
            "state":"uploaded","size":374386569,\
            "digest":"sha256:db9d09eda0131576960e5d5a4569335dc700664b8ffde534ef541cc8635aa587",\
            "browser_download_url":"https://github.com/Wangnov/claude-app-mirror/releases/download/claude-app-v2.9939.2/Claude-mac-universal.dmg"}]}
            """
        var asked: [URL] = []
        updater.fetchMetadata = { url, _ in
            asked.append(url)
            if url == ClaudeUpdater.mirrorManifest { throw ClaudeUpdateError.feed("R2 молчит") }
            return Data(github.utf8)
        }
        updater.resolveRedirect = { url, _ in
            XCTAssertEqual(url, ClaudeUpdater.officialRedirect)
            XCTAssertNil(url.query, "без device_id и версии")
            return self.liveRedirect
        }
        guard case .available(let installed, let release) = try updater.check() else { return XCTFail() }
        XCTAssertEqual(installed, "2.9000.0")
        XCTAssertEqual(release.version, "2.9939.2")
        XCTAssertEqual(asked, [ClaudeUpdater.mirrorManifest, ClaudeUpdater.mirrorFeed])
        let sources = ClaudeUpdater.sources(ClaudeUpdater.versionGroups(release)[0])
        XCTAssertEqual(sources.map { $0.title }, ["R2", "GitHub", "Anthropic"], "три полосы одной версии")
        XCTAssertEqual(sources.last?.sha256, nil, "у официального sha256 нет")
    }

    func testSameFileFromManifestAndRedirectIsOneLaneWithChecksum() throws {
        let mirror = try ClaudeUpdater.parseMirrorManifest(Data(liveManifest.utf8))
        let official = try ClaudeUpdater.parseOfficialRedirect(liveRedirect)
        let best = try ClaudeUpdater.preferredRelease(mirror: mirror, official: official)
        let groups = ClaudeUpdater.versionGroups(best)
        XCTAssertEqual(groups.count, 1)
        let sources = ClaudeUpdater.sources(groups[0])
        XCTAssertEqual(sources.map { $0.id }, ["r2", "github", "anthropic"])
        XCTAssertTrue(sources.allSatisfy { $0.sha256 == mirror.sha256 && $0.expectedSize == mirror.size })
    }

    // ---------------------------------------------------------------- WF86: prepare, ready.json

    /// Новейший не скачался — выручает запасной постарше, если он всё ещё новее стоящего.
    func testFallsBackToOlderReleaseWhenNewestFails() throws {
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let older = try makeRelease(version: "1.0.2")
        let gone = ClaudeRelease(version: "1.0.3", url: scratch.appendingPathComponent("нет-такого.zip"),
                                 sha256: String(repeating: "a", count: 64), size: 10, fallbacks: [older])
        let prepared = try updater.prepare(gone)
        XCTAssertEqual(prepared.release.version, "1.0.2")
        XCTAssertEqual(try version(of: prepared.stagedApp), "1.0.2")
    }

    /// Источники без sha256 (официальный редирект): опора на версию внутри бандла — лживый отсеивается.
    func testSourcesWithoutChecksumAreJudgedByBundle() throws {
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let liar = try makeRelease(version: "1.0.2")
        let honest = try makeRelease(version: "1.0.3")
        let release = ClaudeRelease(version: "1.0.3", url: liar.url, sha256: "", size: 0,
                                    fallbacks: [ClaudeRelease(version: "1.0.3", url: honest.url, sha256: "", size: 0)])
        let prepared = try updater.prepare(release)
        XCTAssertEqual(try version(of: prepared.stagedApp), "1.0.3")
    }

    func testReadyFileSurvivesRestartAndIsCheckedOnLoad() throws {
        let fm = FileManager.default
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let prepared = try updater.prepare(try makeRelease(version: "1.0.1"))
        let readyFile = prepared.stagedApp.deletingLastPathComponent().appendingPathComponent(ClaudeUpdater.readyFileName)
        XCTAssertTrue(fm.fileExists(atPath: readyFile.path))

        // «Перезапуск Пимпа» — новый обновитель той же копии.
        let loaded = try XCTUnwrap(makeUpdater().loadReady())
        XCTAssertEqual(loaded.release.version, "1.0.1")
        XCTAssertEqual(loaded.installedVersion, "1.0.0")
        XCTAssertEqual(loaded.stagedApp.standardizedFileURL, prepared.stagedApp.standardizedFileURL)

        // Другая копия Claude — чужое «готово» не берём (и её распаковку не трогаем).
        var other = makeUpdater()
        other.appURL = apps.appendingPathComponent("Другой/Claude.app")
        XCTAssertNil(other.loadReady())
        XCTAssertTrue(fm.fileExists(atPath: readyFile.path))

        // Claude поставили руками — стоит уже 1.0.1: готовое не новее, распаковка удаляется.
        try fm.removeItem(at: updater.appURL)
        try makeBundle(at: updater.appURL, version: "1.0.1")
        XCTAssertNil(makeUpdater().loadReady())
        XCTAssertFalse(fm.fileExists(atPath: prepared.stagedApp.deletingLastPathComponent().path))
    }

    func testBareStagingIsNotReady() throws {
        let fm = FileManager.default
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let prepared = try updater.prepare(try makeRelease(version: "1.0.1"))
        let staging = prepared.stagedApp.deletingLastPathComponent()
        try fm.removeItem(at: staging.appendingPathComponent(ClaudeUpdater.readyFileName))
        XCTAssertNil(updater.loadReady())
        XCTAssertFalse(fm.fileExists(atPath: staging.path), "голая папка распаковки — не «готово»")

        // Бандл пропал или не тот — тоже.
        let again = try updater.prepare(try makeRelease(version: "1.0.1"))
        try makeBundle(at: again.stagedApp, version: "1.0.5")
        XCTAssertNil(updater.loadReady(), "внутри не та версия")
        XCTAssertEqual(listing(), ["Claude.app"])
    }

    func testTargetIsPatchedCopyNotAnyCopy() {
        let applications = URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true)
        let keep = URL(fileURLWithPath: "/Users/e/_Не удалять/Другое/Claude/Claude.app", isDirectory: true)
        let copies = [keep, applications]
        XCTAssertEqual(ClaudeUpdater.targetClaude(installedAppPath: "/Applications/Claude.app", savedPath: keep.path, copies: copies),
                       applications, "installed.json сильнее выбора в меню")
        XCTAssertEqual(ClaudeUpdater.targetClaude(installedAppPath: nil, savedPath: keep.path, copies: copies), keep)
        XCTAssertEqual(ClaudeUpdater.targetClaude(installedAppPath: "/нет/Claude.app", savedPath: nil, copies: copies),
                       applications, "иначе — копия в /Applications, а не первая попавшаяся")
        XCTAssertNil(ClaudeUpdater.targetClaude(installedAppPath: nil, savedPath: nil, copies: [keep]))
    }

    func testPreflightNeedsWritableFolderAndSpace() throws {
        XCTAssertEqual(ClaudeUpdater.neededSpace(archiveSize: 374_386_569, sources: 3), 3_123_159_707)
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        let small = ClaudeRelease(version: "1.0.1", url: ClaudeUpdater.fastMirror, sha256: "", size: 1, format: .dmg)
        XCTAssertEqual(updater.preflight(small), .ok)
        let huge = ClaudeRelease(version: "1.0.1", url: ClaudeUpdater.fastMirror, sha256: "", size: Int64.max / 4, format: .dmg)
        if case .noSpace = updater.preflight(huge) {} else { XCTFail("места на такой архив нет") }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: apps.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: apps.path) }
        XCTAssertEqual(updater.preflight(small), .notWritable(apps.path))
    }

    /// Настоящий DMG: смонтирован только на время копирования, после — ни монтирования, ни папки.
    func testDMGIsDetachedAfterSuccessAndFailure() throws {
        let fm = FileManager.default
        let updater = makeUpdater()
        try makeBundle(at: updater.appURL, version: "1.0.0")
        func dmg(_ version: String, withApp: Bool) throws -> ClaudeRelease {
            let src = scratch.appendingPathComponent("dmg-\(UUID().uuidString)", isDirectory: true)
            if withApp { try makeBundle(at: src.appendingPathComponent("Claude.app"), version: version) }
            else { try fm.createDirectory(at: src.appendingPathComponent("Пусто"), withIntermediateDirectories: true) }
            let image = scratch.appendingPathComponent("Claude-\(UUID().uuidString).dmg")
            try Shell.run("/usr/bin/hdiutil", ["create", "-quiet", "-fs", "HFS+", "-volname", "Claude", "-srcfolder", src.path,
                                              "-format", "UDZO", "-ov", image.path])
            let size = try fm.attributesOfItem(atPath: image.path)[.size] as! NSNumber
            return ClaudeRelease(version: version, url: image, sha256: try ClaudeUpdater.sha256(of: image),
                                 size: size.int64Value, format: .dmg)
        }
        func mounts() -> String { (try? Shell.run("/usr/bin/hdiutil", ["info"])) ?? "" }
        func leftovers() -> [String] {
            ((try? fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path)) ?? []).filter { $0.hasPrefix("pimp-claude-dmg-") }
        }
        let before = leftovers()
        let prepared = try updater.prepare(try dmg("1.0.1", withApp: true))
        XCTAssertEqual(try version(of: prepared.stagedApp), "1.0.1")
        XCTAssertFalse(mounts().contains("pimp-claude-dmg-"), "образ отцеплен")
        XCTAssertThrowsError(try updater.prepare(try dmg("1.0.2", withApp: false))) { error in
            guard case ClaudeUpdateError.badArchive = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(mounts().contains("pimp-claude-dmg-"), "и после ошибки тоже")
        XCTAssertEqual(leftovers(), before, "точки монтирования убраны")
    }
}
