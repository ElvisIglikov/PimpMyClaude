import XCTest
@testable import Patcher

/// #10568: пока патч стоит, папка закачки Squirrel — только для чтения; снят — права обратно.
final class ShipItCache10568Tests: XCTestCase {
    private func mode(_ url: URL) -> Int {
        (((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
    }

    func testLockedWhilePatchedAndOpenedAfter() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shipit-\(UUID().uuidString)")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("c").path)
            try? FileManager.default.removeItem(at: root)
        }
        let folder = root.appendingPathComponent("c")
        XCTAssertTrue(ShipItCache.hold(patched: true, folder: folder), "папки нет — заводим и закрываем")
        XCTAssertEqual(mode(folder), 0o555)
        XCTAssertThrowsError(try FileManager.default.createDirectory(at: folder.appendingPathComponent("update.x"),
                                                                     withIntermediateDirectories: false),
                             "временную папку обновления не завести")
        XCTAssertFalse(ShipItCache.hold(patched: true, folder: folder), "уже закрыта — ничего")
        XCTAssertTrue(ShipItCache.hold(patched: false, folder: folder))
        XCTAssertEqual(mode(folder), 0o755)
        XCTAssertFalse(ShipItCache.hold(patched: false, folder: folder), "уже открыта — ничего")
    }
}
