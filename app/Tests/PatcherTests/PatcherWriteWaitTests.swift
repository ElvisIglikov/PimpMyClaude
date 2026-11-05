import XCTest
@testable import Patcher

/// #9842: шаг записи в Claude.app не ждёт молча окна macOS, которого не будет.
final class PatcherWriteWaitTests: XCTestCase {
    func testPosixWritableByOwnerGroupAndOthers() {
        let me: uid_t = 501, staff: gid_t = 20
        XCTAssertTrue(Patcher.posixWritable(mode: 0o755, owner: me, group: 80, uid: me, groups: [staff]))
        XCTAssertFalse(Patcher.posixWritable(mode: 0o555, owner: me, group: 80, uid: me, groups: [staff]))
        XCTAssertFalse(Patcher.posixWritable(mode: 0o755, owner: 0, group: 80, uid: me, groups: [staff]), "чужой, root:admin 755")
        XCTAssertTrue(Patcher.posixWritable(mode: 0o775, owner: 0, group: 80, uid: me, groups: [staff, 80]), "группа admin пишет")
        XCTAssertTrue(Patcher.posixWritable(mode: 0o777, owner: 0, group: 0, uid: me, groups: [staff]))
        XCTAssertTrue(Patcher.posixWritable(mode: 0o555, owner: me, group: 80, uid: 0, groups: [0]), "root пишет всюду")
    }

    /// POSIX не пускает — это не «Управление приложениями»: ни строки ожидания, ни минуты ожидания, сразу понятная ошибка.
    func testReadOnlyCopyFailsFastWithoutAppManagementWait() throws {
        let fm = FileManager.default
        let app = fm.temporaryDirectory.appendingPathComponent("wait-\(UUID().uuidString)/Claude.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: resources.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resources.path)
            try? fm.removeItem(at: app.deletingLastPathComponent())
        }
        guard getuid() != 0 else { throw XCTSkip("под root права не мешают") }
        var patcher = ClaudePatcher(appURL: app, supportDirectory: app.deletingLastPathComponent(), resourcesDirectory: nil)
        patcher.signsApp = false
        patcher.managesClaudeProcess = false
        var lines: [String] = []
        let started = Date()
        XCTAssertThrowsError(try patcher.waitForWritable(timeout: 30, progress: { lines.append($0) })) { error in
            guard case PatchError.ownershipFailed(let owner, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(owner, NSUserName())
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(lines.contains(Patcher.appManagementWaitLine))
        XCTAssertEqual(patcher.posixBlocker(), NSUserName())
    }

    func testWritableCopyPassesAtOnce() throws {
        let fm = FileManager.default
        let app = fm.temporaryDirectory.appendingPathComponent("wait-\(UUID().uuidString)/Claude.app", isDirectory: true)
        try fm.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: app.deletingLastPathComponent()) }
        var patcher = ClaudePatcher(appURL: app, supportDirectory: app.deletingLastPathComponent(), resourcesDirectory: nil)
        patcher.managesClaudeProcess = false
        var lines: [String] = []
        Patcher.cancelPermissionWait() // взведённая с прошлого раза отмена не мешает новому шагу
        XCTAssertNoThrow(try patcher.waitForWritable(timeout: 1, progress: { lines.append($0) }))
        XCTAssertEqual(lines, [])
        XCTAssertNil(patcher.posixBlocker())
        XCTAssertFalse(fm.fileExists(atPath: app.appendingPathComponent("Contents/Resources/.pimpmyclaude-write-test").path))
    }

    func testTextsTellWhatToPress() {
        XCTAssertTrue(PatchError.needsAppManagement(appPath: "/Applications/Claude.app", admin: true)
            .errorDescription!.contains("«Открыть настройки»"))
        XCTAssertTrue(PatchError.ownershipFailed(owner: "root", why: "пароль не ввели").errorDescription!.contains("«Ещё раз»"))
        XCTAssertTrue(PatchError.claudeWontQuit.errorDescription!.contains("«Ещё раз»"))
    }
}
