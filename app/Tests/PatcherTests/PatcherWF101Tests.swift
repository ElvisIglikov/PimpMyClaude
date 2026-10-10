import XCTest
@testable import Patcher

/// WF101 (чистка по ревизии WF100), батч Б3a: второй замок Electron (A2), страница из сборки на
/// старте (z9-r01), уборка бэкапов (z7-r02). Всё на копиях во временной папке; живой Claude —
/// только чтением.
final class PatcherWF101Tests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimpmyclaude-wf101-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch = scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    // ---------------------------------------------------------------- синтетический Mach-O

    private static let arm64: UInt32 = 0x0100_000C
    private static let x86: UInt32 = 0x0100_0007

    private func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
    private func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
    private func be32(_ v: UInt32) -> [UInt8] { le32(v).reversed() }
    private func name16(_ s: String) -> [UInt8] { Array((Array(s.utf8) + [UInt8](repeating: 0, count: 16)).prefix(16)) }

    /// Тонкий 64-битный Mach-O: `used` nil — сегмента `__DATA_CONST` с секцией нет вовсе (Electron < 41).
    private func thin(cpu: UInt32 = arm64, used: UInt8?) -> [UInt8] {
        var commands: [UInt8] = []
        var slot: [UInt8] = []
        if let used = used {
            let commandSize = 72 + 80
            let slotOffset = UInt32(32 + commandSize)
            slot = Array("AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A".utf8) + [used, used == 0 ? 0 : 1] + [UInt8](repeating: 0xAB, count: 32)
            commands += le32(0x19) + le32(UInt32(commandSize)) + name16("__DATA_CONST")
            commands += le64(0) + le64(0) + le64(0) + le64(0) + le32(3) + le32(3) + le32(1) + le32(0)
            commands += name16("__asar_integrity") + name16("__DATA_CONST")
            commands += le64(0) + le64(UInt64(slot.count)) + le32(slotOffset) + le32(0) + le32(0) + le32(0)
            commands += le32(0) + le32(0) + le32(0) + le32(0)
        }
        let header = le32(0xFEED_FACF) + le32(cpu) + le32(0) + le32(6) + le32(used == nil ? 0 : 1)
            + le32(UInt32(commands.count)) + le32(0) + le32(0)
        return header + commands + slot
    }

    /// fat-заголовок big-endian, срезы с выравниванием 4096.
    private func fat(_ slices: [(cpu: UInt32, body: [UInt8])]) -> [UInt8] {
        var header = be32(0xCAFE_BABE) + be32(UInt32(slices.count))
        var body: [UInt8] = []
        var offset = 4096
        for slice in slices {
            header += be32(slice.cpu) + be32(0) + be32(UInt32(offset)) + be32(UInt32(slice.body.count)) + be32(12)
            let padded = slice.body + [UInt8](repeating: 0, count: 4096 - slice.body.count % 4096)
            body += padded
            offset += padded.count
        }
        return header + [UInt8](repeating: 0, count: 4096 - header.count) + body
    }

    private func file(_ bytes: [UInt8], _ name: String = UUID().uuidString) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    /// Папка `.framework`, как у Electron: бинарь — симлинком через `Versions/Current`.
    @discardableResult
    private func framework(in app: URL, _ bytes: [UInt8]) throws -> URL {
        let fm = FileManager.default
        let framework = Patcher.electronFramework(of: app)
        let versionA = framework.appendingPathComponent("Versions/A", isDirectory: true)
        try fm.createDirectory(at: versionA, withIntermediateDirectories: true)
        try Data(bytes).write(to: versionA.appendingPathComponent("Electron Framework"))
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Electron Framework").path,
                                  withDestinationPath: "Versions/Current/Electron Framework")
        return framework
    }

    private func isRefuse(_ verdict: AsarIntegrityVerdict) -> Bool { if case .refuse = verdict { return true }; return false }
    private func isUnknown(_ verdict: AsarIntegrityVerdict) -> Bool { if case .unknown = verdict { return true }; return false }

    // ---------------------------------------------------------------- A2: разбор

    func testFatRefusedWhenAnySliceUsesDigest() throws {
        let off = fat([(Self.x86, thin(cpu: Self.x86, used: 0)), (Self.arm64, thin(used: 0))])
        XCTAssertEqual(Patcher.asarIntegrityVerdict(framework: try file(off)), .ok)
        let on = fat([(Self.x86, thin(cpu: Self.x86, used: 0)), (Self.arm64, thin(used: 1))])
        let verdict = Patcher.asarIntegrityVerdict(framework: try file(on))
        XCTAssertTrue(isRefuse(verdict), "\(verdict)")
        if case .refuse(let why) = verdict { XCTAssertTrue(why.contains("arm64"), why) }
    }

    func testThinSliceAndFrameworkFolderThroughSymlink() throws {
        XCTAssertEqual(Patcher.asarIntegrityVerdict(framework: try file(thin(used: 0))), .ok)
        let app = scratch.appendingPathComponent("Claude.app", isDirectory: true)
        let folder = try framework(in: app, thin(used: 1))
        XCTAssertTrue(isRefuse(Patcher.asarIntegrityVerdict(framework: folder)), "симлинк Versions/Current не разрешился")
    }

    func testNoSectionIsOk() throws {
        XCTAssertEqual(Patcher.asarIntegrityVerdict(framework: try file(thin(used: nil))), .ok, "Electron < 41 — патчим как раньше")
        XCTAssertEqual(Patcher.asarIntegrityVerdict(framework: try file(fat([(Self.arm64, thin(used: nil))]))), .ok)
    }

    func testTruncatedOrForeignIsUnknownNotRefuse() throws {
        let whole = fat([(Self.x86, thin(cpu: Self.x86, used: 1)), (Self.arm64, thin(used: 1))])
        XCTAssertTrue(isUnknown(Patcher.asarIntegrityVerdict(framework: try file(Array(whole.prefix(4096 + 40))))))
        XCTAssertTrue(isUnknown(Patcher.asarIntegrityVerdict(framework: try file(Array(thin(used: 1).prefix(100))))))
        XCTAssertTrue(isUnknown(Patcher.asarIntegrityVerdict(framework: try file(Array("не Mach-O вовсе".utf8)))))
        XCTAssertTrue(isUnknown(Patcher.asarIntegrityVerdict(framework: scratch.appendingPathComponent("нет-такого"))))
    }

    /// Живой Claude 2.9939.2 (Electron 44.4.3): оба слота `used = 0` — только чтение.
    func testLiveClaudeIsOk() throws {
        let live = Patcher.electronFramework(of: URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true))
        try XCTSkipUnless(FileManager.default.fileExists(atPath: live.path), "Claude.app не найден")
        XCTAssertEqual(Patcher.asarIntegrityVerdict(framework: live), .ok)
    }

    // ---------------------------------------------------------------- A2: отказ в патче и обновлении

    private func plist(_ app: URL, version: String) throws {
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": Patcher.claudeBundleID, "CFBundleShortVersionString": version,
        ], format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    }

    func testInstallRefusesBeforeTouchingClaude() throws {
        let app = scratch.appendingPathComponent("Claude.app", isDirectory: true)
        try plist(app, version: "9.0.0")
        try framework(in: app, thin(used: 1))
        let support = scratch.appendingPathComponent("Support", isDirectory: true)
        var patcher = ClaudePatcher(appURL: app, supportDirectory: support, resourcesDirectory: nil)
        patcher.signsApp = false
        patcher.managesClaudeProcess = false
        XCTAssertThrowsError(try patcher.install()) { error in
            guard case PatchError.integrityDigestOn(let version, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(version, "9.0.0")
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("Claude 9.0.0 Пимп пока не патчит") == true)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path), "до отказа не создано ничего: ни настроек, ни бэкапа")
    }

    /// Новый Claude с включённым замком: отказ запомнен по версии — второй раз не качается вовсе.
    func testUpdaterRemembersRefusedVersion() throws {
        let apps = scratch.appendingPathComponent("Applications", isDirectory: true)
        var updater = ClaudeUpdater(appURL: apps.appendingPathComponent("Claude.app"),
                                    supportDirectory: scratch.appendingPathComponent("Support"), resourcesDirectory: nil)
        updater.signsApp = false
        updater.managesClaudeProcess = false
        updater.checksSignature = false
        updater.pimpBuild = "44"
        try plist(updater.appURL, version: "1.0.0")

        let src = scratch.appendingPathComponent("src", isDirectory: true)
        let new = src.appendingPathComponent("Claude.app", isDirectory: true)
        try plist(new, version: "1.0.1")
        try framework(in: new, thin(used: 1))
        let zip = src.appendingPathComponent("Claude.zip")
        try Shell.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", new.path, zip.path])
        let size = (try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as! NSNumber).int64Value
        let release = ClaudeRelease(version: "1.0.1", url: zip, sha256: try ClaudeUpdater.sha256(of: zip), size: size)

        XCTAssertThrowsError(try updater.prepare(release)) { error in
            guard case ClaudeUpdateError.integrityRefused(let version, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(version, "1.0.1")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: apps.path), ["Claude.app"], "распаковка убрана")
        XCTAssertFalse(FileManager.default.fileExists(atPath: updater.archiveURL(release).path), "архив не держим")
        try FileManager.default.removeItem(at: zip) // второй раз качать было бы нечего — и не надо
        XCTAssertThrowsError(try updater.prepare(release)) { error in
            guard case ClaudeUpdateError.integrityRefused = error else { return XCTFail("\(error)") }
        }
        XCTAssertNotNil(updater.refusedReason(for: release), "панель не предлагает «Скачать» отказанную версию")

        // Новая сборка Пимпа могла научиться патчить такой Claude: чужой отказ для неё не действует.
        var next = updater
        next.pimpBuild = "45"
        XCTAssertNil(next.refusedReason(for: release))
        XCTAssertThrowsError(try next.prepare(release)) { error in
            if case ClaudeUpdateError.integrityRefused = error { XCTFail("отказ прежней сборки сработал: \(error)") }
        }
    }

    // ---------------------------------------------------------------- z9-r01: страница на старте

    private func page(_ version: String) -> String { "// страница\nconst VERSION = \"\(version)\";\n" }

    private func resources(page version: String) throws -> URL {
        let resources = scratch.appendingPathComponent("Resources-\(version)", isDirectory: true)
        let kit = resources.appendingPathComponent(Patcher.workflowKitDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: kit, withIntermediateDirectories: true)
        try page(version).write(to: resources.appendingPathComponent("inject.js"), atomically: true, encoding: .utf8)
        try "kit \(version)".write(to: kit.appendingPathComponent("WORKFLOW.md"), atomically: true, encoding: .utf8)
        try "/* из сборки */".write(to: resources.appendingPathComponent(Patcher.cssFileName), atomically: true, encoding: .utf8)
        return resources
    }

    private func support(page version: String?) throws -> URL {
        let support = scratch.appendingPathComponent("Support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "/* свой */".write(to: support.appendingPathComponent(Patcher.cssFileName), atomically: true, encoding: .utf8)
        if let version = version {
            try page(version).write(to: support.appendingPathComponent("inject.js"), atomically: true, encoding: .utf8)
        }
        return support
    }

    private func live(_ support: URL, _ name: String) -> String? {
        try? String(contentsOf: support.appendingPathComponent(name), encoding: .utf8)
    }

    func testOlderLivePageIsReplacedWithKit() throws {
        let support = try support(page: "wf70-b-1")
        XCTAssertTrue(Patcher.refreshLiveFilesIfBundledNewer(supportDirectory: support,
                                                             resourcesDirectory: try resources(page: "wf99-a-1")))
        XCTAssertEqual(live(support, "inject.js"), page("wf99-a-1"))
        XCTAssertEqual(live(support, "workflow/WORKFLOW.md"), "kit wf99-a-1", "комплект workflow едет тем же триггером")
        XCTAssertEqual(live(support, Patcher.cssFileName), "/* свой */", "claude.css на старте не трогается")
    }

    func testEqualOrNewerLivePageIsKept() throws {
        let bundled = try resources(page: "wf99-a-1")
        for version in ["wf99-a-1", "wf100-a-1", "wf99-b-1", "wf99-a-2"] {
            let support = try support(page: version)
            XCTAssertFalse(Patcher.refreshLiveFilesIfBundledNewer(supportDirectory: support, resourcesDirectory: bundled), version)
            XCTAssertEqual(live(support, "inject.js"), page(version), version)
            XCTAssertNil(live(support, "workflow/WORKFLOW.md"), version)
        }
    }

    func testNoLivePageIsNotCreated() throws {
        let support = try support(page: nil)
        XCTAssertFalse(Patcher.refreshLiveFilesIfBundledNewer(supportDirectory: support,
                                                              resourcesDirectory: try resources(page: "wf99-a-1")))
        XCTAssertNil(live(support, "inject.js"), "без живой страницы Claude не пропатчен — класть незачем")
    }

    // ---------------------------------------------------------------- z7-r02: бэкапы

    /// После патча в backups/ — стоящая версия и версия прежней копии `.previous`, остальное убрано.
    func testInstallKeepsOnlyCurrentAndPreviousBackups() throws {
        let source = Patcher.locateClaude().first
        try XCTSkipUnless(source.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Resources/app.asar").path) } ?? false,
                          "Claude.app не найден — нечем собрать копию с настоящим app.asar")
        let fm = FileManager.default
        let apps = scratch.appendingPathComponent("Applications", isDirectory: true)
        let app = apps.appendingPathComponent("Claude.app", isDirectory: true)
        try fm.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try fm.copyItem(at: source!.appendingPathComponent("Contents/Resources/app.asar"),
                        to: app.appendingPathComponent("Contents/Resources/app.asar"))
        try fm.copyItem(at: source!.appendingPathComponent("Contents/Info.plist"), to: app.appendingPathComponent("Contents/Info.plist"))
        _ = try Asar.removeLoader(app.appendingPathComponent("Contents/Resources/app.asar"))
        try fm.createDirectory(at: apps.appendingPathComponent("Claude-2.0.0.previous"), withIntermediateDirectories: true)

        let support = scratch.appendingPathComponent("Support", isDirectory: true)
        let backups = support.appendingPathComponent("backups", isDirectory: true)
        for old in ["1.20186.1", "1.46388.4", "2.0.0"] {
            try fm.createDirectory(at: backups.appendingPathComponent(old), withIntermediateDirectories: true)
        }
        var patcher = ClaudePatcher(appURL: app, supportDirectory: support, resourcesDirectory: nil)
        patcher.signsApp = false
        patcher.managesClaudeProcess = false
        // Вторая копия Claude (как в ~/Applications) — её бэкап тоже остаётся (G3).
        let other = scratch.appendingPathComponent("Home/Applications/Claude.app", isDirectory: true)
        try plist(other, version: "1.46388.4")
        patcher.claudeCopies = { [app, other] }
        try patcher.install()
        let version = try patcher.appVersion()
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: backups.path).sorted(), ["1.46388.4", "2.0.0", version].sorted())
        XCTAssertTrue(fm.fileExists(atPath: backups.appendingPathComponent("\(version)/app.asar").path), "бэкап стоящей версии на месте")
    }
}
