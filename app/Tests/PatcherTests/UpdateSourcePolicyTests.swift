import XCTest
@testable import Patcher

final class UpdateSourcePolicyTests: XCTestCase {
    private let official = URL(string: "https://downloads.claude.ai/releases/darwin/universal/2.0.0/Claude-test.dmg")!
    private let mirror = URL(string: "https://claudeapp.agentsmirror.com/latest/mac")!

    func testFreshCheckNeverContactsMirrorAndReturnsOfficialFailureHonestly() throws {
        let box = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let app = box.appendingPathComponent("Claude.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: box) }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "1.0.0", "CFBundleIdentifier": Patcher.claudeBundleID],
                                          format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        var updater = ClaudeUpdater(appURL: app, supportDirectory: box.appendingPathComponent("Support"))
        var mirrorCalls = 0
        updater.fetchMetadata = { _, _ in mirrorCalls += 1; throw ClaudeUpdateError.feed("unexpected mirror") }
        updater.resolveRedirect = { _, _ in self.official }
        guard case .available(_, let release) = try updater.check() else { return XCTFail() }
        XCTAssertEqual(release.url, official)
        updater.resolveRedirect = { _, _ in throw ClaudeUpdateError.feed("official offline") }
        XCTAssertThrowsError(try updater.check())
        XCTAssertEqual(mirrorCalls, 0)
        // A previously found mirror-only release cannot get to network/cache unpack through prepare.
        let stale = ClaudeRelease(version: "2.0.0", url: mirror, sha256: "", size: 0, format: .dmg)
        XCTAssertThrowsError(try updater.prepare(stale))
        XCTAssertFalse(FileManager.default.fileExists(atPath: updater.stagingDirectory.path))
    }

    func testSourcePolicyRechecksEveryURLInStaleReleaseAndFallbacks() {
        let stale = ClaudeRelease(version: "2.0.0", url: mirror, sha256: "", size: 0, format: .dmg,
                                  mirrors: [official, ClaudeUpdater.githubPinned("2.0.0")])
        let admitted = ClaudeUpdater.allowedReleases([stale], allowMirrors: false)
        XCTAssertEqual(admitted.map { $0.url }, [official])
        XCTAssertEqual(ClaudeUpdater.sources(admitted, allowMirrors: false).map { $0.url }, [official])
        XCTAssertEqual(ClaudeUpdater.sources([stale], allowMirrors: false).map { $0.url }, [official])
        XCTAssertEqual(ClaudeUpdater.sources([stale], allowMirrors: true).count, 3)
        for url in ["http://downloads.claude.ai/releases/darwin/universal/2.0.0/Claude.dmg",
                    "https://downloads.claude.ai.evil.test/releases/darwin/universal/2.0.0/Claude.dmg",
                    "https://user@downloads.claude.ai/releases/darwin/universal/2.0.0/Claude.dmg"] {
            XCTAssertFalse(ClaudeUpdater.allowedSource(URL(string: url)!, allowMirrors: false))
        }
    }

    func testOfficialOnlyRaceRejectsRedirectToThirdPartyBeforeRequest() {
        let race = ClaudeDownloadRace(sources: [], directory: URL(fileURLWithPath: NSTemporaryDirectory()))
        race.allowsRedirect = { ClaudeUpdater.allowedSource($0, allowMirrors: false) }
        let task = URLSession.shared.dataTask(with: official) // Never resumed.
        let response = HTTPURLResponse(url: official, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var followed: URLRequest?
        race.urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                        newRequest: URLRequest(url: mirror)) { followed = $0 }
        XCTAssertNil(followed)
        race.urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                        newRequest: URLRequest(url: official)) { followed = $0 }
        XCTAssertEqual(followed?.url, official)
        task.cancel()
    }
}
