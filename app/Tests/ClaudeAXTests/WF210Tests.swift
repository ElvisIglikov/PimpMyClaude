import XCTest
@testable import ClaudeAX

/// WF210: «Чистые ответы» (#9398, К-CA) — команда `clean-answers` всем страницам; умолчания новой установки (#9378) —
/// «Живой» и тема «Фиолетовая».
final class WF210Tests: XCTestCase {
    private typealias Sent = (action: String, json: String)

    private func makeSettings(_ defaults: UserDefaults? = nil) -> (PageLookSettings, UserDefaults, () -> [Sent]) {
        let store: UserDefaults
        if let defaults = defaults {
            store = defaults
        } else {
            let suite = "wf210-\(UUID().uuidString)"
            store = UserDefaults(suiteName: suite)!
            addTeardownBlock { store.removePersistentDomain(forName: suite) }
        }
        let settings = PageLookSettings(defaults: store)
        var sent: [Sent] = []
        settings.write = { action, fields, _ in
            sent.append((action, CommandValue.object(fields).json))
            return true
        }
        return (settings, store, { sent.filter { $0.action == CleanAnswers.action } })
    }

    private static let at = Date(timeIntervalSince1970: 1_790_400_000)

    // MARK: К-CA

    func testCleanAnswersWireMatchesContract() {
        for (on, word) in [(true, "true"), (false, "false")] {
            XCTAssertEqual(CommandChannel.payload(action: CleanAnswers.action, fields: CleanAnswers.fields(on: on),
                                                  id: "wf210-clean", at: PimpChannel.date("2026-10-10T00:00:00Z")!),
                           "{\"id\":\"wf210-clean\",\"action\":\"clean-answers\",\"at\":\"2026-10-10T00:00:00Z\",\"on\":\"\(word)\"}")
        }
    }

    func testNoKeyNoCommandAndShowsOn() {
        let (settings, defaults, sent) = makeSettings()
        settings.beginGeneration()
        for n in 0..<4 { settings.tick(titles: ["\(n)"], at: Self.at.addingTimeInterval(Double(n) * 6)) }
        XCTAssertTrue(sent().isEmpty, "ключа нет — страница живёт своим умолчанием (включено)")
        XCTAssertTrue(settings.cleanAnswers, "по умолчанию включено")
        XCTAssertNil(defaults.object(forKey: CleanAnswers.key), "показ и тики ключ не создают")
    }

    func testSwitchSendsAtOnceAndRepeatsToNewGeneration() {
        let (settings, defaults, sent) = makeSettings()
        settings.setCleanAnswers(false)
        XCTAssertEqual(defaults.object(forKey: CleanAnswers.key) as? Bool, false)
        XCTAssertFalse(settings.cleanAnswers)
        XCTAssertEqual(sent().map { "\($0.action) \($0.json)" }, ["clean-answers {\"on\":\"false\"}"])
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertEqual(sent().count, 2, "страницам этого поколения — повтор")
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(6))
        XCTAssertEqual(sent().count, 2, "тот же состав — повтора нет")

        // Новое поколение страниц (перезапуск PMP, смена pid Claude) получает сохранённый выбор.
        let (fresh, _, again) = makeSettings(defaults)
        fresh.beginGeneration()
        fresh.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(again().map(\.json), ["{\"on\":\"false\"}"])
        settings.beginGeneration()
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(30))
        XCTAssertEqual(sent().count, 3, "смена pid Claude у того же приложения — тоже повтор")

        settings.setCleanAnswers(true)
        XCTAssertEqual(sent().last.map { "\($0.action) \($0.json)" }, "clean-answers {\"on\":\"true\"}")
    }

    // MARK: умолчания новой установки (#9378)

    func testNewInstallIsEmptyDefaultsAndNoInstalledFile() {
        XCTAssertTrue(PanelColorTiles.isNewInstall(values: [:], installed: nil))
        XCTAssertFalse(PanelColorTiles.isNewInstall(values: ["minimizeMenu": true], installed: nil), "уже запускал")
        XCTAssertFalse(PanelColorTiles.isNewInstall(values: [:], installed: Data("{}".utf8)), "Claude уже патчили")
    }

    func testNewInstallLookIsVioletAndLiveForAllWindows() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf210-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("claude-patch")
        let themes = ThemeCatalog.load(directory: root)
        let violet = try XCTUnwrap(themes.first { $0.id == PanelColorTiles.newInstallThemeID })
        XCTAssertEqual(violet.name, "Фиолетовая")
        XCTAssertEqual(violet.type, "dark")
        let suite = "wf210-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = ThemeStore(defaults: defaults)
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                    commands: CommandChannel(path: dir.appendingPathComponent("command.json"),
                                                             now: Date.init, schedule: { _, _ in }),
                                    themes: themes, fonts: [], themeStore: store,
                                    myThemes: MyThemesStore(url: dir.appendingPathComponent("my.json")),
                                    autoPaintStore: AutoPaintStore(defaults: defaults),
                                    liveColorsStore: LiveColorsStore(defaults: defaults))
        let mirror = WindowThemeStore(url: dir.appendingPathComponent("window-themes.json"))
        actions.windowThemes = mirror
        XCTAssertNil(store.allThemeID)
        XCTAssertFalse(store.allLook.aurora, "до умолчаний «Живой» выключен")

        actions.applyNewInstallLook(theme: violet, look: PanelColorTiles.liveLook(Look(), on: true))

        XCTAssertEqual(store.allThemeID, "violet")
        XCTAssertTrue(store.allLook.aurora, "«Живой» включён")
        XCTAssertEqual(store.allLook.schemeID, PanelColorTiles.liveScheme, "в тонах темы")
        // Страницы ещё нет (Claude не пропатчен): выбор ждёт её в файле и уедет возвратом `themes-restore`.
        let all = try XCTUnwrap(mirror.entries[WindowThemeStore.allKey])
        XCTAssertNotNil(all.layers["theme"])
        XCTAssertNotNil(all.layers["look"])
    }
}
