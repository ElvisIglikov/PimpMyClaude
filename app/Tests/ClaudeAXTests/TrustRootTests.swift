import XCTest
@testable import ClaudeAX

/// WF108: корень автодоверия (`trust-root`), умолчание `projectsRoot` и выбор браузера (#8146).
final class TrustRootTests: XCTestCase {
    private func root(_ json: String, home: String = "/Users/tester") -> String? {
        TrustRoot.root(config: Data(json.utf8), home: home)
    }

    func testTildeKeyExpandsAndEndsWithSlash() {
        XCTAssertEqual(root(#"{"projectsRoot":"~/Projects"}"#), "/Users/tester/Projects/")
        XCTAssertEqual(root(#"{"projectsRoot":" ~/Projects/ "}"#), "/Users/tester/Projects/")
        XCTAssertEqual(root(#"{"projectsRoot":"~"}"#), "/Users/tester/")
    }

    func testAbsolutePathIsStandardized() {
        XCTAssertEqual(root(#"{"projectsRoot":"/Users/tester/a/../Projects//"}"#), "/Users/tester/Projects/")
        XCTAssertEqual(root(#"{"projectsRoot":"/Users/tester/Projects"}"#), "/Users/tester/Projects/")
    }

    func testNoKeyIsNil() {
        XCTAssertNil(root(#"{"minWindowWidth":280}"#))
        XCTAssertNil(TrustRoot.root(config: nil))
    }

    func testGarbageIsNil() {
        XCTAssertNil(root("не json"))
        XCTAssertNil(root("[]"))
        XCTAssertNil(root(#"{"projectsRoot":42}"#))
        XCTAssertNil(root(#"{"projectsRoot":"  "}"#))
        XCTAssertNil(root(#"{"projectsRoot":"Projects"}"#))
        XCTAssertNil(root(#"{"projectsRoot":"/"}"#))
    }

    func testCommandBytes() {
        let at = Date(timeIntervalSince1970: 0)
        let on = CommandChannel.payload(action: TrustRoot.action, fields: TrustRoot.fields(root: "/Users/tester/Projects/"),
                                        id: "1-0001", at: at)
        XCTAssertTrue(on.hasPrefix(#"{"id":"1-0001","action":"trust-root","at":"#), on)
        let tail = on.components(separatedBy: #","root":"#).last ?? ""
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data("[\(tail.dropLast())]".utf8)) as? [String],
                       ["/Users/tester/Projects/"], on)
        let off = CommandChannel.payload(action: TrustRoot.action, fields: TrustRoot.fields(root: nil),
                                         id: "1-0002", at: at)
        XCTAssertTrue(off.hasSuffix(#","root":null}"#), off)
    }

    func testBrowserRoute() {
        let app = URL(fileURLWithPath: "/Applications/X.app")
        XCTAssertEqual(HtmlChromeOpener.route(app: app, bundleID: "com.vivaldi.Vivaldi"), .script(name: "Vivaldi", app: app))
        XCTAssertEqual(HtmlChromeOpener.route(app: app, bundleID: "com.google.Chrome"), .script(name: "Google Chrome", app: app))
        XCTAssertEqual(HtmlChromeOpener.route(app: app, bundleID: "com.brave.Browser"), .script(name: "Brave Browser", app: app))
        XCTAssertEqual(HtmlChromeOpener.route(app: app, bundleID: "com.apple.Safari"), .open(app: app))
        XCTAssertEqual(HtmlChromeOpener.route(app: app, bundleID: nil), .open(app: app))
        XCTAssertEqual(HtmlChromeOpener.route(app: nil, bundleID: "com.vivaldi.Vivaldi"), .system)
    }

    func testProjectsRootDefaultAndTilde() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("claude.json")
        XCTAssertEqual(StatusFeed.projectsRoot(configURL: config).path,
                       NSString(string: "~/Projects").expandingTildeInPath)
        try Data(#"{"projectsRoot":"~/Projects"}"#.utf8).write(to: config)
        XCTAssertEqual(StatusFeed.projectsRoot(configURL: config).path,
                       NSString(string: "~/Projects").expandingTildeInPath)
    }
}
