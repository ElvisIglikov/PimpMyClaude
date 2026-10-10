import XCTest
@testable import ClaudeAX

/// Виды отсчёта К1 v3 (WF128, #9041): восемь разных видов, умолчание «1.8», «1.3»/«1.7» не принимаются.
final class SendLookWF111Tests: XCTestCase {
    func testV3StylesInMenuOrder() {
        XCTAssertEqual(SendLook.styles.map { $0.id }, ["1.8", "1.9", "1.10", "1.1", "1.2", "1.4", "1.6", "1.5"])
        XCTAssertEqual(SendLook.styles.map { $0.name },
                       ["Ракета", "Пульс", "Мерцание", "Штрих по кругу", "Удар", "Кольцо", "Шнур", "Спокойная цифра"])
        XCTAssertEqual(SendLook.defaultStyle, "1.8")
        XCTAssertEqual(SendLook.styleKey, "sendLookStyleWF128")
        for refused in ["1.3", "1.7", "1.11", "2.1", ""] { XCTAssertFalse(SendLook.isStyle(refused), refused) }
    }

    func testMenuChecksDefaultWhenNoKey() {
        let suite = "wf161-look-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set("1.5", forKey: "sendLookStyle") // старый ключ WF119 не читается
        let settings = PageLookSettings(defaults: defaults)
        XCTAssertEqual(settings.current.style, "1.8")
        let items = SendLook.menuItems(selected: settings.current.style)
        XCTAssertEqual(items.map(\.style), SendLook.styles.map { $0.id })
        XCTAssertEqual(items.filter(\.checked).map(\.title), ["Ракета"])
        XCTAssertFalse(items.contains { $0.style == "1.3" || $0.style == "1.7" })
        XCTAssertEqual(SendLook.menuItems(selected: "1.3").filter(\.checked).map(\.style), ["1.8"])
        defaults.set("1.7", forKey: SendLook.styleKey)
        XCTAssertEqual(settings.current.style, "1.8", "негодное в ключе — умолчание")
    }

    func testChosenStyleRememberedBroadcastAndPreviewed() {
        let suite = "wf161-look-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = PageLookSettings(defaults: defaults)
        var sent: [String] = []
        settings.write = { _, fields, _ in sent.append(CommandValue.object(fields).json); return true }
        settings.isRunning = { true }
        XCTAssertEqual(settings.setLook(style: "1.10").look.style, "1.10")
        XCTAssertEqual(settings.setLook(style: "1.7").look.style, "1.10", "1.7 — мимо, выбор прежний")
        XCTAssertEqual(defaults.string(forKey: SendLook.styleKey), "1.10")
        XCTAssertEqual(settings.current.style, "1.10")
        XCTAssertTrue(settings.previewSendDelay(seconds: 5, match: nil, chat: "local_a"))
        XCTAssertEqual(sent, ["{\"style\":\"1.10\",\"size\":100,\"preview\":false}",
                              "{\"style\":\"1.10\",\"size\":100,\"preview\":false}",
                              "{\"style\":\"1.10\",\"size\":100,\"preview\":true,\"seconds\":5,\"chat\":\"local_a\"}"])
        XCTAssertEqual(CommandChannel.payload(action: SendLook.action,
            fields: SendLook.fields(style: "1.9", size: 100, preview: false, match: nil),
            id: "wf161-look", at: PimpChannel.date("2026-10-08T00:00:00Z")!),
            "{\"id\":\"wf161-look\",\"action\":\"send-look\",\"at\":\"2026-10-08T00:00:00Z\",\"style\":\"1.9\",\"size\":100,\"preview\":false}")
    }

    func testChannelAcceptsOnlyV3Styles() {
        func parse(_ style: String) -> PimpRequest? {
            PimpRequest.parse(Data(("{\"id\":\"1-1\",\"at\":\"2026-10-01T10:00:00Z\",\"action\":\"look\","
                + "\"from\":\"\",\"style\":\"\(style)\"}").utf8))
        }
        XCTAssertEqual(parse("1.5")?.style, "1.5")
        XCTAssertEqual(parse("1.9")?.style, "1.9")
        XCTAssertEqual(parse("1.10")?.style, "1.10")
        XCTAssertNil(parse("1.3"))
        XCTAssertNil(parse("1.7"))
    }
}
