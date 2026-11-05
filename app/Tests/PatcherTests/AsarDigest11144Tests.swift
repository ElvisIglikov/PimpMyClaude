import XCTest
@testable import Patcher

/// #11144: Claude 4.29 включил второй замок Electron (`__asar_integrity`, версия 1) — патч переписывает digest
/// в слотах Electron Framework под новый хэш. Всё на копиях во временной папке; живой Claude — только чтением.
final class AsarDigest11144Tests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimpmyclaude-11144-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch = scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    /// Info.plist Claude 4.29.0 (27.10.2026) и digest из обоих срезов его Electron Framework.
    private let claude429: [String: Any] = [
        "Resources/app.asar": ["algorithm": "SHA256", "hash": "0b29374b38fb4004ddd07217e87d948b0c8040b382af10fa249cc257f2e40975"],
        "Resources/ion-dist.asar": ["algorithm": "SHA256", "hash": "fc848cd6e93b0c76e9d6092c5cdd44b5a8ecf1a6a40e350b6a58df45d2c91d08"],
    ]
    private let claude429Digest = "199c2aee6e2819ec27e1c96c71678d30e167f09bf3da9847a556631118bece79"

    private func hex(_ data: Data?) -> String? { data.map { $0.map { String(format: "%02x", $0) }.joined() } }

    // ---------------------------------------------------------------- синтетический Electron Framework

    private func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
    private func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
    private func be32(_ v: UInt32) -> [UInt8] { le32(v).reversed() }
    private func name16(_ s: String) -> [UInt8] { Array((Array(s.utf8) + [UInt8](repeating: 0, count: 16)).prefix(16)) }

    /// Срез с одним слотом: сторожевая строка, used = 1, `version`, `digest`.
    private func slice(cpu: UInt32, version: UInt8, digest: Data) -> [UInt8] {
        let commandSize = 72 + 80
        let slot = Array(MachOIntegrity.sentinel) + [1, version] + Array(digest)
        var commands = le32(0x19) + le32(UInt32(commandSize)) + name16("__DATA_CONST")
        commands += le64(0) + le64(0) + le64(0) + le64(0) + le32(3) + le32(3) + le32(1) + le32(0)
        commands += name16("__asar_integrity") + name16("__DATA_CONST")
        commands += le64(0) + le64(UInt64(slot.count)) + le32(UInt32(32 + commandSize)) + le32(0) + le32(0) + le32(0)
        commands += le32(0) + le32(0) + le32(0) + le32(0)
        let header = le32(0xFEED_FACF) + le32(cpu) + le32(0) + le32(6) + le32(1) + le32(UInt32(commands.count)) + le32(0) + le32(0)
        return header + commands + slot
    }

    /// fat из x86_64 и arm64, как у Claude; бинарь — в `.framework` через симлинк `Versions/Current`.
    @discardableResult
    private func framework(in app: URL, version: UInt8 = 1, digest: Data) throws -> URL {
        var header = be32(0xCAFE_BABE) + be32(2)
        var body: [UInt8] = []
        var offset = 4096
        for cpu: UInt32 in [0x0100_0007, 0x0100_000C] {
            let bytes = slice(cpu: cpu, version: version, digest: digest)
            header += be32(cpu) + be32(0) + be32(UInt32(offset)) + be32(UInt32(bytes.count)) + be32(12)
            let padded = bytes + [UInt8](repeating: 0, count: 4096 - bytes.count % 4096)
            body += padded
            offset += padded.count
        }
        let fm = FileManager.default
        let framework = Patcher.electronFramework(of: app)
        let versionA = framework.appendingPathComponent("Versions/A", isDirectory: true)
        try fm.createDirectory(at: versionA, withIntermediateDirectories: true)
        try Data(header + [UInt8](repeating: 0, count: 4096 - header.count) + body)
            .write(to: versionA.appendingPathComponent("Electron Framework"))
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Electron Framework").path,
                                  withDestinationPath: "Versions/Current/Electron Framework")
        return framework
    }

    /// Digest обоих срезов, прочитанный заново с диска.
    private func slotDigests(_ framework: URL) throws -> [String] {
        let binary = framework.appendingPathComponent("Electron Framework").resolvingSymlinksInPath()
        let handle = try FileHandle(forReadingFrom: binary)
        defer { try? handle.close() }
        return MachOIntegrity(handle: handle).slots().compactMap { hex($0.digest) }
    }

    private func isRefuse(_ verdict: AsarIntegrityVerdict) -> Bool { if case .refuse = verdict { return true }; return false }

    // ---------------------------------------------------------------- формула и разбор

    func testDigestIsElectronFormulaOnClaude429() {
        XCTAssertEqual(hex(Patcher.asarIntegrityDigest(claude429)), claude429Digest)
        XCTAssertNil(Patcher.asarIntegrityDigest(["Resources/app.asar": ["algorithm": "SHA256"]]), "без hash digest не считается")
    }

    func testVerdictDigestOnlyWhenSlotMatchesInfoPlist() throws {
        let digest = try XCTUnwrap(Patcher.asarIntegrityDigest(claude429))
        let ours = try framework(in: scratch.appendingPathComponent("A.app"), digest: digest)
        XCTAssertEqual(Patcher.asarIntegrityVerdict(framework: ours, integrity: claude429), .digest)
        XCTAssertTrue(isRefuse(Patcher.asarIntegrityVerdict(framework: ours, integrity: nil)), "Info.plist без словаря — не наша формула")

        let other = try framework(in: scratch.appendingPathComponent("B.app"), digest: Data(repeating: 0xAB, count: 32))
        XCTAssertTrue(isRefuse(Patcher.asarIntegrityVerdict(framework: other, integrity: claude429)))

        let future = try framework(in: scratch.appendingPathComponent("C.app"), version: 2, digest: digest)
        let verdict = Patcher.asarIntegrityVerdict(framework: future, integrity: claude429)
        XCTAssertTrue(isRefuse(verdict), "\(verdict)")
        if case .refuse(let why) = verdict { XCTAssertTrue(why.contains("версия 2"), why) }
    }

    func testWriteReplacesBinaryAndRewritesEverySlice() throws {
        let framework = try framework(in: scratch.appendingPathComponent("Claude.app"), digest: try XCTUnwrap(Patcher.asarIntegrityDigest(claude429)))
        let binary = framework.appendingPathComponent("Electron Framework").resolvingSymlinksInPath()
        let inode = try FileManager.default.attributesOfItem(atPath: binary.path)[.systemFileNumber] as? Int
        var patched = claude429
        patched["Resources/app.asar"] = ["algorithm": "SHA256", "hash": String(repeating: "0", count: 64)]

        XCTAssertEqual(try Patcher.writeAsarIntegrityDigest(framework: framework, integrity: patched), 2)
        let want = try XCTUnwrap(hex(Patcher.asarIntegrityDigest(patched)))
        XCTAssertEqual(try slotDigests(framework), [want, want])
        XCTAssertEqual(Patcher.asarIntegrityVerdict(framework: framework, integrity: patched), .digest)
        XCTAssertNotEqual(try FileManager.default.attributesOfItem(atPath: binary.path)[.systemFileNumber] as? Int, inode,
                          "бинарь переписан на месте — подпись старого файла легла бы на новый")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: binary.deletingLastPathComponent().path), ["Electron Framework"],
                       "клон не убран")
        XCTAssertEqual(try Patcher.writeAsarIntegrityDigest(framework: framework, integrity: patched), 0, "digest уже свой — не трогаем")
    }

    /// Обновление Claude: версия с замком по известной формуле качается и готовится, в `refused.json` не попадает.
    func testUpdaterPreparesClaudeWithKnownDigest() throws {
        let apps = scratch.appendingPathComponent("Applications", isDirectory: true)
        var updater = ClaudeUpdater(appURL: apps.appendingPathComponent("Claude.app"),
                                    supportDirectory: scratch.appendingPathComponent("Support"), resourcesDirectory: nil)
        updater.signsApp = false
        updater.managesClaudeProcess = false
        updater.checksSignature = false
        func plist(_ app: URL, version: String, integrity: [String: Any]? = nil) throws {
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            var body: [String: Any] = ["CFBundleIdentifier": Patcher.claudeBundleID, "CFBundleShortVersionString": version]
            body["ElectronAsarIntegrity"] = integrity
            try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
        }
        try plist(updater.appURL, version: "3.6556.2")
        let new = scratch.appendingPathComponent("src/Claude.app", isDirectory: true)
        try plist(new, version: "4.29.0", integrity: claude429)
        try framework(in: new, digest: try XCTUnwrap(Patcher.asarIntegrityDigest(claude429)))
        let zip = scratch.appendingPathComponent("src/Claude.zip")
        try Shell.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", new.path, zip.path])
        let size = (try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as! NSNumber).int64Value
        let release = ClaudeRelease(version: "4.29.0", url: zip, sha256: try ClaudeUpdater.sha256(of: zip), size: size)

        let prepared = try updater.prepare(release)
        XCTAssertEqual(prepared.release.version, "4.29.0")
        XCTAssertNil(updater.refusedReason(for: release))
    }

    // ---------------------------------------------------------------- патч и «Снять патч» на копии

    /// Копия архива и Info.plist живого Claude (как в PatcherTests), Electron Framework — синтетический с включённым
    /// замком: патч вписывает digest нового хэша, «Снять патч…» возвращает digest оригинала.
    func testInstallAndRestoreKeepDigestInStepWithInfoPlist() throws {
        guard let source = Patcher.locateClaude().first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Resources/app.asar").path)
        }) else { throw XCTSkip("Claude.app не найден") }
        let app = scratch.appendingPathComponent("Claude.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source.appendingPathComponent("Contents/Resources/app.asar"),
                                         to: app.appendingPathComponent("Contents/Resources/app.asar"))
        try FileManager.default.copyItem(at: source.appendingPathComponent("Contents/Info.plist"),
                                         to: app.appendingPathComponent("Contents/Info.plist"))
        _ = try Asar.removeLoader(app.appendingPathComponent("Contents/Resources/app.asar"))
        var patcher = ClaudePatcher(appURL: app, supportDirectory: scratch.appendingPathComponent("Support"), resourcesDirectory: nil)
        patcher.signsApp = false
        patcher.managesClaudeProcess = false
        patcher.claudeCopies = { [] }
        try patcher.setInfoPlistHash(try Asar.status(of: patcher.asarURL).headerSHA256)
        let original = try XCTUnwrap(Patcher.asarIntegrity(of: app))
        let framework = try framework(in: app, digest: try XCTUnwrap(Patcher.asarIntegrityDigest(original)))

        var log: [String] = []
        _ = try patcher.install(progress: { log.append($0) })
        let patched = try XCTUnwrap(Patcher.asarIntegrity(of: app))
        XCTAssertEqual(patcher.infoPlistHash(), try Asar.status(of: patcher.asarURL).headerSHA256)
        let want = try XCTUnwrap(hex(Patcher.asarIntegrityDigest(patched)))
        XCTAssertNotEqual(want, hex(Patcher.asarIntegrityDigest(original)))
        XCTAssertEqual(try slotDigests(framework), [want, want], "digest не пошёл за новым хэшем")
        XCTAssertTrue(log.contains { $0.contains("срезов: 2") }, "\(log)")

        try patcher.restore()
        let back = try XCTUnwrap(hex(Patcher.asarIntegrityDigest(original)))
        XCTAssertEqual(try slotDigests(framework), [back, back], "«Снять патч…» не вернул digest оригинала")
    }
}
