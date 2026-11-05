import AppKit
import XCTest
@testable import ClaudeAX

/// Explicit file writes use a private pasteboard; no polling of the user clipboard.
final class CopyFileRelayTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var file: URL!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("pimpmyclaude-copy-test-\(UUID().uuidString)"))
        file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("копия \(UUID().uuidString).html")
        try? Data("<p>ok</p>".utf8).write(to: file)
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: file)
        super.tearDown()
    }

    func testExplicitCopyWritesFileURLFilenamesAndPath() {
        XCTAssertTrue(CopyFileRelay.write(path: file.path, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .fileURL), file.absoluteString)
        XCTAssertEqual(pasteboard.propertyList(forType: CopyFileRelay.filenamesType) as? [String], [file.path])
        XCTAssertEqual(pasteboard.string(forType: .string), file.path)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.map(\.path), [file.path])
    }

    /// Путь просит любая страница (z5-r03): скрытые папки, связки ключей и cookies — буфер не трогаем.
    func testClosedPathsAreRefused() {
        let home = "/Users/e"
        for path in ["/Users/e/.ssh/id_ed25519", "/Users/e/proj/.env", "/Users/e/Library/Keychains/login.keychain-db",
                     "/Users/e/library/cookies/Cookies.binarycookies", "/Users/e/x/../.aws/credentials",
                     "/Users/e/Library/Keychains"] {
            XCTAssertTrue(CopyFileRelay.isRefused(path, home: home), path)
        }
        for path in ["/Users/e/Library/Application Support/a.png", "/Users/dev/Не удалять/после установки.command",
                     "/Users/e/Library/KeychainsBackup/a.txt"] {
            XCTAssertFalse(CopyFileRelay.isRefused(path, home: home), path)
        }
    }
}
