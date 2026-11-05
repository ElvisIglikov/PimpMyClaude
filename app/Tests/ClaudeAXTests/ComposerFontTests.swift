import AppKit
import XCTest
@testable import ClaudeAX

/// Размер шрифта в поле ввода, сторона приложения (WF107 #8126, контракт К2; пункт меню снят в WF237): байты команды,
/// ручка порта `/composer-font`, зеркало и возврат после переустановки Claude.
final class ComposerFontTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ComposerFontTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - байты команды

    func testCommandBytes() {
        let at = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(CommandChannel.payload(action: ComposerFont.action, fields: ComposerFont.fields(px: 18),
                                              id: "1", at: at),
                       #"{"id":"1","action":"composer-font","at":"1970-01-01T00:00:00Z","px":18}"#)
        XCTAssertEqual(CommandChannel.payload(action: ComposerFont.action, fields: ComposerFont.fields(px: nil),
                                              id: "1", at: at),
                       #"{"id":"1","action":"composer-font","at":"1970-01-01T00:00:00Z","px":null}"#)
    }

    // MARK: - ручка порта

    private func head(_ query: String) -> String { "GET /composer-font?\(query) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\nOrigin: https://claude.ai\r\n\r\n" }

    func testParse() {
        XCTAssertEqual(ComposerFont.parse(head("px=18&chat=local_a")), ComposerFont.Ping(px: 18, chat: "local_a"))
        XCTAssertEqual(ComposerFont.parse(head("px=11&chat=local_a"))?.px, 11)
        XCTAssertEqual(ComposerFont.parse(head("px=32&chat=local_a"))?.px, 32)
        XCTAssertEqual(ComposerFont.parse(head("px=none&chat=local_a")), ComposerFont.Ping(px: nil, chat: "local_a"))
        for bad in ["px=10&chat=local_a", "px=33&chat=local_a", "px=abc&chat=local_a", "px=-5&chat=local_a",
                    "px=18.5&chat=local_a", "px=&chat=local_a", "chat=local_a", "px=18", "px=18&chat=",
                    "px=18&chat=evil"] {
            XCTAssertNil(ComposerFont.parse(head(bad)), bad)
        }
        XCTAssertNil(ComposerFont.parse("POST /composer-font?px=18&chat=local_a HTTP/1.1\r\n"))
        XCTAssertNil(ComposerFont.parse("GET /context?chat=local_a HTTP/1.1\r\n"))
    }

    func testPortOnlyForKnownChat() {
        let opener = HtmlChromeOpener()
        var pings: [ComposerFont.Ping] = []
        opener.isKnownChat = { $0 == "local_a" }
        opener.onComposerFont = { pings.append($0) }
        opener.handleOld(head("px=18&chat=local_a"))
        opener.handleOld(head("px=20&chat=local_zzz"))
        opener.handleOld(head("px=99&chat=local_a"))
        opener.handleOld(head("px=none&chat=local_a"))
        XCTAssertEqual(pings, [ComposerFont.Ping(px: 18, chat: "local_a"), ComposerFont.Ping(px: nil, chat: "local_a")])
        // Индекса нет — никого не знаем.
        let blind = HtmlChromeOpener()
        blind.onComposerFont = { pings.append($0) }
        blind.handleOld(head("px=18&chat=local_a"))
        XCTAssertEqual(pings.count, 2)
    }

    // MARK: - зеркало

    func testMirrorClamp() {
        XCTAssertNil(ComposerFont.mirror(in: defaults))
        ComposerFont.setMirror(18, in: defaults)
        XCTAssertEqual(ComposerFont.mirror(in: defaults), 18)
        defaults.set(40, forKey: ComposerFont.defaultsKey)
        XCTAssertEqual(ComposerFont.mirror(in: defaults), 32)
        defaults.set(3, forKey: ComposerFont.defaultsKey)
        XCTAssertEqual(ComposerFont.mirror(in: defaults), 11)
        defaults.set("мусор", forKey: ComposerFont.defaultsKey)
        XCTAssertNil(ComposerFont.mirror(in: defaults))
        ComposerFont.setMirror(nil, in: defaults)
        XCTAssertNil(defaults.object(forKey: ComposerFont.defaultsKey))
    }

    /// Колесо — в зеркало без ответа (петли нет); `none` при непустом зеркале — возврат, не чаще раза в 10 с;
    /// пустое зеркало — ничего.
    func testReceiveAndRestore() {
        var clock = Date(timeIntervalSince1970: 1000)
        let mirror = ComposerFontMirror(defaults: defaults, now: { clock })
        let none = ComposerFont.Ping(px: nil, chat: "local_a")
        XCTAssertNil(mirror.receive(none), "пустое зеркало — ничего")
        XCTAssertNil(mirror.receive(ComposerFont.Ping(px: 18, chat: "local_a")))
        XCTAssertEqual(mirror.px, 18)
        XCTAssertEqual(mirror.receive(none), 18)
        clock.addTimeInterval(5)
        XCTAssertNil(mirror.receive(none), "не чаще раза в 10 с")
        XCTAssertEqual(mirror.px, 18, "none зеркало не стирает")
        clock.addTimeInterval(6)
        XCTAssertEqual(mirror.receive(none), 18)
    }
}
