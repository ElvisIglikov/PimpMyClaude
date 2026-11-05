import XCTest
@testable import Patcher

/// Папка MyClaude и запись в неё (ревизия WF247, С5б; аудит 10.10, В2): свежая папка — 0700, файлы — 0600, уже
/// стоящую папку права не трогают; файл читает другой процесс того же пользователя (так читают лоадер и PimpViewer).
final class SupportFilesTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("support-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func mode(_ url: URL) throws -> Int {
        try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue)
    }

    func testFreshFolderIs0700AndFilesAre0600() throws {
        let folder = scratch.appendingPathComponent("MyClaude", isDirectory: true)
        let file = folder.appendingPathComponent("command.json")
        try SupportFiles.write(Data("{}".utf8), to: file)
        XCTAssertEqual(try mode(folder), 0o700)
        XCTAssertEqual(try mode(file), 0o600)
        XCTAssertEqual(try Data(contentsOf: file), Data("{}".utf8))
        // Перезапись — тот же файл 0600, временного рядом не остаётся.
        try SupportFiles.write(Data("[1]".utf8), to: file)
        XCTAssertEqual(try mode(file), 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["command.json"])
        // Другой процесс того же пользователя файл читает.
        let cat = Process()
        cat.executableURL = URL(fileURLWithPath: "/bin/cat")
        cat.arguments = [file.path]
        let pipe = Pipe()
        cat.standardOutput = pipe
        try cat.run()
        cat.waitUntilExit()
        XCTAssertEqual(cat.terminationStatus, 0)
        XCTAssertEqual(pipe.fileHandleForReading.readDataToEndOfFile(), Data("[1]".utf8))
    }

    func testExistingFolderKeepsItsMode() throws {
        let folder = scratch.appendingPathComponent("MyClaude", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        try SupportFiles.ensureDirectory(folder)
        XCTAssertTrue(SupportFiles.writeAtomic(folder.appendingPathComponent("claude.css"), Data("a{}".utf8)))
        XCTAssertEqual(try mode(folder), 0o755)
        XCTAssertEqual(try mode(folder.appendingPathComponent("claude.css")), 0o600)
        // Чужие права по просьбе — файл в папке проекта остаётся 0644.
        XCTAssertTrue(SupportFiles.writeAtomic(folder.appendingPathComponent("p.json"), Data("{}".utf8), permissions: 0o644))
        XCTAssertEqual(try mode(folder.appendingPathComponent("p.json")), 0o644)
    }

    func testWriteFailsLoudlyWhenParentIsAFile() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let blocker = scratch.appendingPathComponent("file")
        try Data().write(to: blocker)
        XCTAssertThrowsError(try SupportFiles.write(Data("x".utf8), to: blocker.appendingPathComponent("inner.json")))
        XCTAssertFalse(SupportFiles.writeAtomic(blocker.appendingPathComponent("inner.json"), Data("x".utf8)))
    }

    func testHumanTextPrefersOwnDescription() {
        struct Own: LocalizedError { var errorDescription: String? { "своё" } }
        XCTAssertEqual(Own().humanText, "своё")
        XCTAssertFalse(POSIXError(.EACCES).humanText.isEmpty)
    }
}
