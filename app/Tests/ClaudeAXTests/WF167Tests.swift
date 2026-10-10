import XCTest
@testable import ClaudeAX

/// WF167 (#9168): блок «Текст» панели — выравнивание `text-justify` всем страницам и поля 0…40 в claude.json.
final class WF167Tests: XCTestCase {
    private typealias Sent = (action: String, json: String)

    private func makeSettings(_ defaults: UserDefaults? = nil) -> (PageLookSettings, UserDefaults, () -> [Sent]) {
        let store: UserDefaults
        if let defaults = defaults {
            store = defaults
        } else {
            let suite = "wf167-\(UUID().uuidString)"
            store = UserDefaults(suiteName: suite)!
            addTeardownBlock { store.removePersistentDomain(forName: suite) }
        }
        let settings = PageLookSettings(defaults: store)
        var sent: [Sent] = []
        settings.write = { action, fields, _ in
            sent.append((action, CommandValue.object(fields).json))
            return true
        }
        // Тик шлёт и другие выборы (dim, send-look) — здесь смотрим только text-justify.
        return (settings, store, { sent.filter { $0.action == TextLook.justifyAction } })
    }

    private static let at = Date(timeIntervalSince1970: 1_790_300_000)

    func testJustifyWireMatchesPageContract() {
        XCTAssertEqual(TextLook.justifyKey, "textJustifyWF167")
        for (on, word) in [(true, "true"), (false, "false")] {
            XCTAssertEqual(CommandChannel.payload(action: TextLook.justifyAction, fields: TextLook.fields(justify: on),
                                                  id: "wf167-justify", at: PimpChannel.date("2026-10-09T00:00:00Z")!),
                           "{\"id\":\"wf167-justify\",\"action\":\"text-justify\",\"at\":\"2026-10-09T00:00:00Z\",\"on\":\"\(word)\"}")
        }
    }

    func testNoKeyNoCommandAndShowsJustified() {
        let (settings, defaults, sent) = makeSettings()
        settings.beginGeneration()
        for n in 0..<4 { settings.tick(titles: ["\(n)"], at: Self.at.addingTimeInterval(Double(n) * 6)) }
        XCTAssertTrue(sent().isEmpty, "ключа нет — страница живёт своим умолчанием")
        XCTAssertTrue(settings.textJustify, "показываем умолчание страницы — по ширине")
        XCTAssertNil(defaults.object(forKey: TextLook.justifyKey), "показ и тики ключ не создают")
    }

    func testSwitchSendsAtOnceAndRepeatsToNewGeneration() {
        let (settings, defaults, sent) = makeSettings()
        settings.setTextJustify(false)
        XCTAssertEqual(defaults.object(forKey: TextLook.justifyKey) as? Bool, false)
        XCTAssertFalse(settings.textJustify)
        XCTAssertEqual(sent().map { "\($0.action) \($0.json)" }, ["text-justify {\"on\":\"false\"}"])
        settings.tick(titles: [], at: Self.at)
        XCTAssertEqual(sent().count, 1, "окон нет — слать некому")
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertEqual(sent().count, 2)
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(6))
        XCTAssertEqual(sent().count, 2, "тот же состав — повтора нет")

        // Новое поколение страниц (смена pid Claude, перезапуск PMP) получает сохранённое значение.
        let (fresh, _, again) = makeSettings(defaults)
        fresh.beginGeneration()
        fresh.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(again().map(\.json), ["{\"on\":\"false\"}"])

        settings.setTextJustify(true)
        XCTAssertEqual(sent().last.map { "\($0.action) \($0.json)" }, "text-justify {\"on\":\"true\"}")
        settings.tick(titles: ["Б"], at: Self.at.addingTimeInterval(20))
        XCTAssertEqual(sent().last.map { "\($0.action) \($0.json)" }, "text-justify {\"on\":\"true\"}")
    }

    /// WF214: смена pid Claude — то же поколение настроек, что и перезапуск PMP: выравнивание уходит новым страницам.
    func testSameSettingsRepeatJustifyAfterNewGeneration() {
        let (settings, _, sent) = makeSettings()
        settings.setTextJustify(false)
        settings.tick(titles: ["А"], at: Self.at)
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(6))
        XCTAssertEqual(sent().count, 2)
        settings.beginGeneration()
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(12))
        XCTAssertEqual(sent().count, 3, "новый Claude с теми же окнами получает выбор заново")
        XCTAssertEqual(sent().last?.json, "{\"on\":\"false\"}")
    }

    func testPanelSliderWritesSidePaddingClamped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wf167-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let suite = "wf167-pad-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let config = directory.appendingPathComponent("claude.json")
        try "{\n  \"minWindowWidth\" : 280,\n  \"projectsRoot\" : \"/Users/dev/Projects\",\n  \"sidePadding\" : 24\n}\n"
            .write(to: config, atomically: true, encoding: .utf8)

        XCTAssertEqual(TextLook.paddingRange, 0...40)
        XCTAssertEqual(TextLook.paddingMarks, [24, 32, 40])
        func saved() -> Int? { LiveStyle.number(try? String(contentsOf: config, encoding: .utf8), key: "sidePadding") }

        for (asked, written) in [(32, 32), (41, 40), (99, 40), (-3, 0), (0, 0), (40, 40)] {
            XCTAssertEqual(TextLook.setSidePadding(asked, directory: directory, defaults: defaults), written)
            XCTAssertEqual(saved(), written, "claude.json.sidePadding после \(asked)")
            XCTAssertEqual(LiveStyle.currentSidePadding(directory: directory, defaults: defaults), written)
        }
        let text = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(text.contains("\"projectsRoot\" : \"/Users/dev/Projects\""), "чужие ключи целы")
        let css = try String(contentsOf: directory.appendingPathComponent("claude.css"), encoding: .utf8)
        XCTAssertTrue(css.contains(LiveStyle.markerStart), "блок PimpMyClaude:auto переписан тем же путём, что «↔️ Поля»")
    }
}
