import AppKit
import XCTest
@testable import ClaudeAX

/// Размер шрифта в поле ввода, сторона приложения (WF107 #8126, контракт К2): пункт меню, байты команды,
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

    // MARK: - меню

    private func submenu(_ config: MinimizeMenu.MenuConfig) throws -> NSMenu {
        let menu = MinimizeMenu.build(config: config)
        let item = try XCTUnwrap(menu.items.first { $0.title == MenuModel.composerFontTitle })
        XCTAssertNotNil(item.image)
        // Сразу под «🔠 Размер шрифта ▸».
        XCTAssertEqual(menu.items.firstIndex(of: item).map { $0 - 1 },
                       menu.items.firstIndex { $0.title == MenuModel.answerSizeTitle })
        return try XCTUnwrap(item.submenu)
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    private func checked(_ menu: NSMenu) -> [String] {
        menu.items.filter { $0.state == .on }.map(\.title)
    }

    func testSubmenuNothingChosen() throws {
        let list = try submenu(MinimizeMenu.MenuConfig())
        XCTAssertEqual(titles(list), ["ВО ВСЕХ ОКНАХ", "Как у Claude", "—",
                                      "12", "13", "14", "15", "16", "18", "20", "22", "24"])
        XCTAssertFalse(list.items[0].isEnabled, "шапка — не пункт")
        XCTAssertEqual(checked(list), ["Как у Claude"])
        XCTAssertTrue(list.delegate === PreviewMenuDelegate.shared, "наведение — примерка")
    }

    func testCheckAndExtraValueInPlace() throws {
        var config = MinimizeMenu.MenuConfig()
        config.composerFont = 18
        XCTAssertEqual(checked(try submenu(config)), ["18"])
        config.composerFont = 17
        let list = try submenu(config)
        XCTAssertEqual(titles(list), ["ВО ВСЕХ ОКНАХ", "Как у Claude", "—",
                                      "12", "13", "14", "15", "16", "17", "18", "20", "22", "24"])
        XCTAssertEqual(checked(list), ["17"])
        config.composerFont = 30
        XCTAssertEqual(titles(try submenu(config)).suffix(2), ["24", "30"])
        config.composerFont = 11
        XCTAssertEqual(titles(try submenu(config))[3], "11")
    }

    func testClickAndPreview() throws {
        var config = MinimizeMenu.MenuConfig()
        var set: [Int?] = []
        var previews: [Int?] = []
        config.setComposerFont = { set.append($0) }
        config.previewComposerFont = { previews.append($0) }
        let list = try submenu(config)
        for title in ["20", "Как у Claude"] {
            let item = try XCTUnwrap(list.items.first { $0.title == title } as? BlockMenuItem)
            item.preview?()
            item.target?.perform(item.action)
        }
        XCTAssertEqual(set, [20, nil])
        XCTAssertEqual(previews, [20, nil])
    }

    /// В «🖥 Всем окнам ▸» пункт не дублируется (выбор 3 плана): он и так на все окна.
    func testNotInAllWindows() throws {
        let menu = MinimizeMenu.build(config: MinimizeMenu.MenuConfig())
        let more = try XCTUnwrap(menu.items.first { $0.title == MenuModel.moreTitle }?.submenu)
        let all = try XCTUnwrap(more.items.first { $0.title == MenuModel.allWindowsTitle }?.submenu)
        XCTAssertNil(all.items.first { $0.title == MenuModel.composerFontTitle })
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
        // Примерка: адрес как у примерки темы — заголовок и match либо chat, без frame.
        XCTAssertEqual(CommandChannel.payload(action: ComposerFont.action,
                                              fields: ComposerFont.previewFields(title: "Ожидание задачи", match: nil,
                                                                                 chat: "local_a", px: 22),
                                              id: "2", at: at),
                       #"{"id":"2","action":"composer-font","at":"1970-01-01T00:00:00Z","title":"Ожидание задачи","chat":"local_a","preview":true,"px":22}"#)
        XCTAssertEqual(CommandChannel.payload(action: ComposerFont.action,
                                              fields: ComposerFont.previewFields(title: "Claude", match: "/epitaxy/x",
                                                                                 chat: nil, px: nil),
                                              id: "3", at: at),
                       #"{"id":"3","action":"composer-font","at":"1970-01-01T00:00:00Z","title":"Claude","match":"/epitaxy/x","preview":true,"px":null}"#)
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
