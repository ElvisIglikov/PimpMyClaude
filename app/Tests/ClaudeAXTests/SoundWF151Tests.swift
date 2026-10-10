import XCTest
@testable import ClaudeAX

/// Звук отсчёта (WF151, #9108): подменю «🔊 Звук отсчёта ▸», ключ `countdownSound` живого claude.json и поле
/// `sound` команды `send-delay` — сразу и раз на поколение страниц. Живого диска нет: свой claude.json во временной папке.
final class SoundWF151Tests: XCTestCase {
    private typealias Sent = (action: String, json: String)
    private static let at = Date(timeIntervalSince1970: 1_790_200_000)

    private func makeSettings(config: String? = "{\n  \"minWindowWidth\" : 280,\n  \"projectsRoot\" : \"~/Projects\"\n}\n")
        -> (PageLookSettings, UserDefaults, URL, () -> [Sent]) {
        let suite = "wf151-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dir)
        }
        let url = dir.appendingPathComponent("claude.json")
        if let config = config { try? config.write(to: url, atomically: true, encoding: .utf8) }
        let settings = PageLookSettings(defaults: defaults, configURL: url)
        var sent: [Sent] = []
        settings.write = { action, fields, _ in
            sent.append((action, CommandValue.object(fields).json))
            return true
        }
        return (settings, defaults, url, { sent })
    }

    private func config(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) ?? [:]
    }

    func testMenuHasFiveItemsWithCheckOnCurrent() {
        let items = CountdownSound.menuItems(selected: .drop)
        XCTAssertEqual(items.map(\.title), ["🔔 Мягкий колокольчик", "🕰 Тик", "💧 Капля", "👾 Ретро-бип", "🔇 Без звука"])
        XCTAssertEqual(items.map(\.sound.rawValue), ["bell", "tick", "drop", "retro", "off"])
        XCTAssertEqual(items.filter(\.checked).map(\.sound), [.drop])
        XCTAssertEqual(CountdownSound.menuItems(selected: .bell).filter(\.checked).map(\.sound), [.bell])
    }

    func testPickWritesConfigKeyAndSendsSoundOnly() throws {
        let (settings, _, url, sent) = makeSettings()
        settings.setCountdownSound(.retro)
        let root = config(url)
        XCTAssertEqual(root["countdownSound"] as? String, "retro")
        XCTAssertEqual(root["minWindowWidth"] as? Int, 280, "остальные ключи не теряются")
        XCTAssertEqual(root["projectsRoot"] as? String, "~/Projects")
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("\\/"), "пути без экранирования")
        XCTAssertEqual(sent().map(\.action), ["send-delay"])
        XCTAssertEqual(sent()[0].json, "{\"sound\":\"retro\"}")
        XCTAssertEqual(settings.countdownSound, .retro)
        XCTAssertEqual(CountdownSound.menuItems(selected: settings.countdownSound).filter(\.checked).map(\.sound), [.retro])
    }

    func testWireMatchesContract() {
        XCTAssertEqual(CommandChannel.payload(action: SendDelaySetting.action, fields: CountdownSound.tick.fields,
                                              id: "wf151-sound", at: PimpChannel.date("2026-10-08T00:00:00Z")!),
                       "{\"id\":\"wf151-sound\",\"action\":\"send-delay\",\"at\":\"2026-10-08T00:00:00Z\",\"sound\":\"tick\"}")
    }

    func testMissingOrGarbageIsBell() {
        let (settings, _, url, _) = makeSettings()
        XCTAssertEqual(settings.countdownSound, .bell)
        XCTAssertNil(settings.chosenCountdownSound, "не выбирали — не выбор")
        for garbage in ["\"loud\"", "42", "null", "true", "\"\""] {
            try? "{\"countdownSound\": \(garbage)}".write(to: url, atomically: true, encoding: .utf8)
            XCTAssertEqual(settings.countdownSound, .bell, garbage)
        }
        XCTAssertEqual(CountdownSound.parse(nil), .bell)
        XCTAssertEqual(CountdownSound.parse("off"), .off)
    }

    func testHandEditedConfigWinsOverMemory() {
        let (settings, defaults, url, _) = makeSettings()
        defaults.set("tick", forKey: CountdownSound.defaultsKey)
        XCTAssertEqual(settings.countdownSound, .tick, "файла с ключом нет — память")
        try? "{\"countdownSound\":\"drop\"}".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(settings.countdownSound, .drop)
    }

    func testBrokenConfigIsNotTouchedButChoiceStillSent() throws {
        let (settings, _, url, sent) = makeSettings(config: "{ broken")
        settings.setCountdownSound(.off)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ broken")
        XCTAssertEqual(sent().last?.json, "{\"sound\":\"off\"}")
        XCTAssertEqual(settings.countdownSound, .off, "память приложения держит выбор")
    }

    func testNoConfigFileIsNotCreated() {
        let (settings, _, url, sent) = makeSettings(config: nil)
        settings.setCountdownSound(.drop)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "claude.json заводит «Пропатчить Claude»")
        XCTAssertEqual(sent().last?.json, "{\"sound\":\"drop\"}")
    }

    /// Новые страницы получают выбор: поколение — повтор `sound`, не чаще правила trust-root.
    func testNewPagesGetChoiceOncePerGeneration() {
        let (settings, _, _, sent) = makeSettings()
        settings.beginGeneration()
        settings.tick(titles: ["Claude"], at: Self.at)
        XCTAssertFalse(sent().contains { $0.action == "send-delay" }, "не выбирали — рассылки нет")
        settings.setCountdownSound(.tick)
        let before = sent().count
        settings.beginGeneration()
        settings.tick(titles: [], at: Self.at)
        XCTAssertEqual(sent().count, before, "окон нет — слать некому")
        settings.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(sent().dropFirst(before).filter { $0.action == "send-delay" }.map(\.json), ["{\"sound\":\"tick\"}"])
        settings.tick(titles: ["Claude"], at: Self.at.addingTimeInterval(10))
        XCTAssertEqual(sent().dropFirst(before).filter { $0.action == "send-delay" }.count, 1,
                       "состав окон тот же — повтора нет")
    }

    func testHandEditedKeyAlsoReachesNewPages() {
        let (settings, _, _, sent) = makeSettings(config: "{\"countdownSound\":\"loud\"}")
        settings.beginGeneration()
        settings.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(sent().filter { $0.action == "send-delay" }.map(\.json), ["{\"sound\":\"bell\"}"], "мусор — bell")
    }
}
