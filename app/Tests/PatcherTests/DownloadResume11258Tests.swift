import CryptoKit
import XCTest
@testable import Patcher

/// #11258 (слово Элвиса 30.10.2026: «скачано 98% и сорвалось… чтобы обновления точно скачивались»):
/// обрыв и «завис» — докачка с места по `Range`, сервер без `Range` — с нуля, недокачанное переживает
/// провал гонки, `prepareVersion` не стирает гонку этой версии, устаревший R2 — GitHub API в гонке.
final class DownloadResume11258Tests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimpmyclaude-resume-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let scratch = scratch { try? FileManager.default.removeItem(at: scratch) }
        RaceStubProtocol.reset([:])
    }

    private let url = "https://a.test/Claude.dmg"

    private func body(_ size: Int, seed: UInt8) -> Data {
        Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    private func source(_ data: Data) -> DownloadSource {
        DownloadSource(id: "a", title: "A", url: URL(string: url)!, expectedSize: Int64(data.count),
                       sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), format: .dmg)
    }

    private func rules(maxResumes: Int = 3) -> ClaudeDownloadRace.Rules {
        var rules = ClaudeDownloadRace.Rules()
        rules.warmup = 0.3
        rules.stallSeconds = 0.6
        rules.tick = 0.05
        rules.speedWindow = 0.3
        rules.maxResumes = maxResumes
        rules.resumePause = 0.01
        rules.resumePauseCap = 0.05
        return rules
    }

    private final class Lines { var all: [String] = [] }

    private func run(_ data: Data, maxResumes: Int = 3, lines: Lines = Lines()) throws -> RaceWinner {
        let race = ClaudeDownloadRace(sources: [source(data)], directory: scratch, rules: rules(maxResumes: maxResumes),
                                      configuration: RaceStubProtocol.configuration())
        race.log = { lines.all.append($0) }
        return try race.run()
    }

    func testBreakAtNinetyPercentResumesWithRangeAndChecksumMatches() throws {
        let data = body(1_000_000, seed: 21)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, failAfter: 900_000, breaksFor: 1)])
        let lines = Lines()
        let winner = try run(data, lines: lines)
        XCTAssertEqual(try Data(contentsOf: winner.file), data, "дописано в конец, sha256 сошлась")
        XCTAssertEqual(RaceStubProtocol.ranges(url), [nil, "bytes=900000-"])
        XCTAssertTrue(lines.all.contains { $0.contains("A: обрыв на 0 МБ — докачиваю с места (повтор 1)") }, "\(lines.all)")
    }

    func testServerWithoutRangeStartsOverAndMatches() throws {
        let data = body(1_000_000, seed: 22)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, failAfter: 500_000, breaksFor: 1, ranges: false)])
        let lines = Lines()
        let winner = try run(data, lines: lines)
        XCTAssertEqual(try Data(contentsOf: winner.file), data, "файл обнулён и скачан целиком")
        XCTAssertEqual(RaceStubProtocol.ranges(url), [nil, "bytes=500000-"])
        XCTAssertTrue(lines.all.contains { $0.contains("докачку не умеет — качаю с нуля") }, "\(lines.all)")
    }

    func testBreaksWithoutNewBytesFailAfterMaxResumes() {
        let data = body(800_000, seed: 23)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, failAfter: 300_000)])
        XCTAssertThrowsError(try run(data, maxResumes: 4)) { error in
            let text = ClaudeUpdater.describe(error)
            XCTAssertTrue(text.contains("обрыв, 4 повторов подряд без новых байтов"), text)
        }
        XCTAssertEqual(RaceStubProtocol.started(url), 5, "первый запрос и четыре повтора")
        XCTAssertEqual(Set(RaceStubProtocol.ranges(url).dropFirst()), ["bytes=300000-"])
    }

    func testStallResumesFromPlace() throws {
        let data = body(800_000, seed: 24)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, hangAfter: 400_000, breaksFor: 1)])
        let lines = Lines()
        let winner = try run(data, lines: lines)
        XCTAssertEqual(try Data(contentsOf: winner.file), data)
        XCTAssertEqual(RaceStubProtocol.ranges(url), [nil, "bytes=400000-"])
        XCTAssertTrue(lines.all.contains { $0.contains("A: завис на") }, "\(lines.all)")
    }

    /// Перезапуск Пимпа или сон Мака: гонка сорвалась, `.part` с меткой остался — новая гонка той же
    /// версии начинает с `Range`, а не с нуля.
    func testFailedRaceLeavesPartAndNextRaceContinues() throws {
        let data = body(1_000_000, seed: 25)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, failAfter: 600_000)])
        XCTAssertThrowsError(try run(data, maxResumes: 1))
        let part = scratch.appendingPathComponent("a.part")
        XCTAssertEqual(try Data(contentsOf: part), data.prefix(600_000))
        XCTAssertEqual(try String(contentsOf: part.appendingPathExtension("url"), encoding: .utf8), url)
        let mode = try FileManager.default.attributesOfItem(atPath: part.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, SupportFiles.filePermissions)

        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000)])
        let winner = try run(data)
        XCTAssertEqual(RaceStubProtocol.ranges(url), ["bytes=600000-"], "сразу с места")
        XCTAssertEqual(try Data(contentsOf: winner.file), data, "sha256 с учётом старых байтов")
        XCTAssertFalse(FileManager.default.fileExists(atPath: part.appendingPathExtension("url").path), "метка победителя убрана")
    }

    func testPartFromOtherAddressStartsOver() throws {
        let data = body(1_000_000, seed: 26)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let part = scratch.appendingPathComponent("a.part")
        try Data(repeating: 7, count: 600_000).write(to: part)
        try Data("https://other.test/Claude.dmg".utf8).write(to: part.appendingPathExtension("url"))
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000)])
        let winner = try run(data)
        XCTAssertEqual(RaceStubProtocol.ranges(url), [nil], "чужая метка — с нуля")
        XCTAssertEqual(try Data(contentsOf: winner.file), data)
    }

    // ------------------------------------------------- доводки после проверки bc385075

    /// Д1: 503 и 429 на докачку — повтор с места, а не провал со стиранием скачанного.
    func testServerBusyOnResumeRetriesFromPlace() throws {
        let data = body(1_000_000, seed: 27)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, failAfter: 900_000, breaksFor: 1,
                                           statuses: [2: 503, 3: 429])])
        let lines = Lines()
        let winner = try run(data, lines: lines)
        XCTAssertEqual(try Data(contentsOf: winner.file), data)
        XCTAssertEqual(RaceStubProtocol.ranges(url), [nil] + Array(repeating: "bytes=900000-", count: 3))
        XCTAssertTrue(lines.all.contains { $0.contains("A: сервер ответил 503 на 0 МБ — докачиваю с места") }, "\(lines.all)")
    }

    /// Д1: 5xx без конца — провал после `maxResumes`, но скачанное остаётся для следующей гонки.
    func testServerErrorsExhaustResumesAndKeepPart() {
        let data = body(1_000_000, seed: 28)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, failAfter: 900_000, breaksFor: 1,
                                           statuses: [2: 500, 3: 502, 4: 503])])
        XCTAssertThrowsError(try run(data, maxResumes: 3)) { error in
            let text = ClaudeUpdater.describe(error)
            XCTAssertTrue(text.contains("сервер ответил 503, 3 повторов подряд без новых байтов"), text)
        }
        XCTAssertEqual(RaceStubProtocol.started(url), 4, "первый запрос и три повтора")
        XCTAssertEqual(try Data(contentsOf: scratch.appendingPathComponent("a.part")), data.prefix(900_000), "98 % не стёрты")
    }

    /// Д1: сервер закрыл связь без ошибки, байт меньше ожидаемого — докачка с места.
    func testCleanEarlyCloseResumesFromPlace() throws {
        let data = body(1_000_000, seed: 29)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, breaksFor: 1, closeAfter: 700_000)])
        let lines = Lines()
        let winner = try run(data, lines: lines)
        XCTAssertEqual(try Data(contentsOf: winner.file), data)
        XCTAssertEqual(RaceStubProtocol.ranges(url), [nil, "bytes=700000-"])
        XCTAssertTrue(lines.all.contains { $0.contains("связь закрыта раньше срока") }, "\(lines.all)")
    }

    /// Д2: сервер без `Range` рвёт связь каждый раз — с нуля не больше `maxStartsOver` раз, потом провал словами.
    func testServerWithoutRangeBreakingEveryTimeStopsAfterStartsOver() {
        let data = body(800_000, seed: 30)
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000, failAfter: 400_000, ranges: false)])
        XCTAssertThrowsError(try run(data, maxResumes: 3)) { error in
            let text = ClaudeUpdater.describe(error)
            XCTAssertTrue(text.contains("докачку не держит — 3 раза начинал с нуля"), text)
        }
        XCTAssertEqual(RaceStubProtocol.started(url), 5, "первый запрос, три начала с нуля и отказ на четвёртом")
    }

    /// Д3: хост не найден — 3 повтора подряд, а не `maxResumes` (30).
    func testDeadHostGivesUpAfterThreeRetries() {
        let data = body(200_000, seed: 31)
        RaceStubProtocol.reset([url: .init(body: data, failAfter: 0, failCode: .cannotFindHost)])
        XCTAssertThrowsError(try run(data, maxResumes: 30)) { error in
            let text = ClaudeUpdater.describe(error)
            XCTAssertTrue(text.contains("источник недоступен, 3 повторов подряд без новых байтов"), text)
        }
        XCTAssertEqual(RaceStubProtocol.started(url), 4, "первый запрос и три повтора")
    }

    /// Мелочь: целый файл с прошлого запуска и sha256 сошлась — победа без сети; не сошлась — с нуля.
    func testWholePartWithMatchingChecksumWinsWithoutNetwork() throws {
        let data = body(500_000, seed: 32)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let part = scratch.appendingPathComponent("a.part")
        try data.write(to: part)
        try Data(url.utf8).write(to: part.appendingPathExtension("url"))
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000)])
        let winner = try run(data)
        XCTAssertEqual(RaceStubProtocol.started(url), 0, "ни одного запроса")
        XCTAssertEqual(try Data(contentsOf: winner.file), data)

        try Data(repeating: 9, count: data.count).write(to: part)
        try Data(url.utf8).write(to: part.appendingPathExtension("url"))
        RaceStubProtocol.reset([url: .init(body: data, chunk: 50_000)])
        let again = try run(data)
        XCTAssertEqual(RaceStubProtocol.ranges(url), [nil], "sha256 не сошлась — с нуля")
        XCTAssertEqual(try Data(contentsOf: again.file), data)
    }

    // ---------------------------------------------------------------- ClaudeUpdater

    private func makeUpdater(installed: String) throws -> ClaudeUpdater {
        let apps = scratch.appendingPathComponent("Applications", isDirectory: true)
        let app = apps.appendingPathComponent("Claude.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": Patcher.claudeBundleID, "CFBundleShortVersionString": installed]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        var updater = ClaudeUpdater(appURL: app, supportDirectory: scratch.appendingPathComponent("Support", isDirectory: true),
                                    resourcesDirectory: nil)
        updater.signsApp = false
        updater.managesClaudeProcess = false
        updater.checksSignature = false
        return updater
    }

    func testPrepareKeepsRaceOfThisVersionAndRemovesOlder() throws {
        let updater = try makeUpdater(installed: "1.0.0")
        let fm = FileManager.default
        for (dir, file) in [("race-1.0.3", "anthropic.part"), ("race-1.0.1", "old.part"), ("race-2.0.0", "new.part")] {
            let folder = updater.downloadDirectory.appendingPathComponent(dir, isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: folder.appendingPathComponent(file))
        }
        let gone = ClaudeRelease(version: "1.0.3", url: scratch.appendingPathComponent("нет-такого.zip"),
                                 sha256: String(repeating: "a", count: 64), size: 10)
        var prepared = updater
        prepared.raceRules = rules()
        XCTAssertThrowsError(try prepared.prepare(gone))
        let dir = updater.downloadDirectory
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("race-1.0.3/anthropic.part").path), "эта версия — докачать")
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("race-2.0.0/new.part").path), "новее — тоже")
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("race-1.0.1").path), "старее — убрана")
    }

    private func manifest(_ version: String) -> String {
        """
        {"schemaVersion":2,"version":"\(version)","sources":{"macos":{"universal":{"format":"dmg","version":"\(version)",\
        "contentLength":374386569,"sha256":"db9d09eda0131576960e5d5a4569335dc700664b8ffde534ef541cc8635aa587"}}}}
        """
    }

    private let feed = """
        {"draft":false,"prerelease":false,"tag_name":"claude-app-v4.4212.0","assets":[{"name":"Claude-mac-universal.dmg",\
        "state":"uploaded","size":377484763,\
        "digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111",\
        "browser_download_url":"https://github.com/Wangnov/claude-app-mirror/releases/download/claude-app-v4.4212.0/Claude-mac-universal.dmg"}]}
        """

    private let redirect = URL(string: "https://downloads.claude.ai/releases/darwin/universal/4.4212.0/Claude-abc.dmg")!

    /// Живьём 30.10: R2 отдавал 4.29.0, Anthropic и GitHub — 4.4212.0; в гонке была одна полоса Anthropic.
    func testStaleR2AsksGitHubAndItsLaneJoinsRace() throws {
        var updater = try makeUpdater(installed: "4.0.0")
        var asked: [URL] = []
        updater.fetchMetadata = { url, _ in
            asked.append(url)
            return Data((url == ClaudeUpdater.mirrorManifest ? self.manifest("4.29.0") : self.feed).utf8)
        }
        updater.resolveRedirect = { _, _ in self.redirect }
        guard case .available(_, let release) = try updater.check() else { return XCTFail() }
        XCTAssertEqual(asked, [ClaudeUpdater.mirrorManifest, ClaudeUpdater.mirrorFeed])
        XCTAssertEqual(release.version, "4.4212.0")
        let groups = ClaudeUpdater.versionGroups(release)
        XCTAssertEqual(groups.map { $0[0].version }, ["4.4212.0", "4.29.0"], "R2 остался запасным")
        let lanes = ClaudeUpdater.sources(groups[0])
        XCTAssertEqual(lanes.map { $0.title }, ["R2", "GitHub", "Anthropic"])
        let github = try XCTUnwrap(lanes.first { $0.title == "GitHub" })
        XCTAssertEqual(github.url, ClaudeUpdater.githubPinned("4.4212.0"))
        XCTAssertEqual(github.expectedSize, 377_484_763)
        XCTAssertEqual(github.sha256, String(repeating: "1", count: 64))
        XCTAssertEqual(lanes.last?.url, redirect)

        // R2 свежий — GitHub API не тратим (лимит 60 запросов в час).
        asked = []
        updater.fetchMetadata = { url, _ in
            asked.append(url)
            return Data(self.manifest("4.4212.0").utf8)
        }
        _ = try updater.check()
        XCTAssertEqual(asked, [ClaudeUpdater.mirrorManifest])
    }
}
