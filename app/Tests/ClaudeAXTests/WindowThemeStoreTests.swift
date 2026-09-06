import XCTest
@testable import ClaudeAX

/// Часы под рукой: `at` записей и зазор рассылки проверяются по секундам, а не по живому времени.
private final class ThemeClock {
    var now = Date(timeIntervalSince1970: 1_757_100_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Темы окон на диске (план WF35, задача #5473): файл `window-themes.json`, зеркало
/// закрепляющих команд `theme`, карта страницы из ответа probe и возврат командой
/// `themes-restore`. Живого Claude тут нет — файл лежит во временной папке, часы подставные.
final class WindowThemeStoreTests: XCTestCase {
    // MARK: - песочница

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themestore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeStore(_ clock: ThemeClock, in box: URL? = nil)
        -> (store: WindowThemeStore, url: URL) {
        let url = (box ?? makeTemp()).appendingPathComponent(WindowThemeStore.fileName)
        return (WindowThemeStore(url: url, now: { clock.now }), url)
    }

    private func text(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static let ocean = Theme(id: "ocean", name: "Океан", type: "dark",
                                     palette: ["accent": "#3af", "background": "#012"])
    private static let sand = Theme(id: "sand", name: "Песок", type: "light",
                                    palette: ["accent": "#a71", "background": "#fed"])
    private static let menlo = Font(id: "menlo", family: "Menlo", category: .mono,
                                    displayName: "Menlo")

    /// Полная запись: палитра, шрифт, обе половины размера и рамка — та самая, по которой
    /// считался байтовый потолок (≈ 360 байт, решение 1 плана WF35).
    private func fullEntry(at: Int) -> WindowThemeEntry {
        WindowThemeEntry(layers: [
            "theme": .value(Theme(id: "long-theme-id", name: "Тема с длинным именем",
                                  type: "dark",
                                  palette: ["accent": "#3af8c1", "background": "#01122a",
                                            "foreground": "#e8f0ff", "sidebar": "#061a33",
                                            "panel": "#0a2140", "muted": "#7f93ad"]).commandValue),
            "font": .value(WindowThemeStoreTests.menlo.commandValue),
            "size": .value(Size(answer: 16, question: 14).commandValue),
            "frame": .value(.bool(true)),
        ], at: at)
    }

    // MARK: - 19. байты файла

    func testWindowThemeStoreJSONIsByteExact() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis", chat: "local_ab12",
            theme: .set(WindowThemeStoreTests.ocean), font: .set(WindowThemeStoreTests.menlo),
            size: .halves(answer: .set(16), question: .keep), frame: .set(true)))

        let entry = """
        {"theme":{"id":"ocean","name":"Океан","type":"dark",\
        "palette":{"accent":"#3af","background":"#012"}},\
        "font":{"id":"menlo","family":"Menlo","mono":true},\
        "size":{"answer":16},"frame":true,"at":1757100000000}
        """
        // Порядок побайтно: version, at, entries; внутри записи — theme, font, size, frame, at.
        // Ключей два: id чата главный, заголовок — тень для окна, которое id ещё не знает.
        XCTAssertEqual(text(of: rig.url), """
        {"version":1,"at":"2025-09-05T19:20:00Z","entries":\
        {"chat:Trelvis":\(entry),"id:local_ab12":\(entry)}}
        """)

        // «Как у Claude» хранится маркером "none" — но только когда у слоя есть запись «всем
        // окнам»: иначе запись лишняя, и слой просто уходит (то же правило, что у страницы).
        clock.advance(60)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeAll, title: "", theme: .keep,
            font: .set(WindowThemeStoreTests.menlo)))
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis", chat: "local_ab12",
            theme: .keep, font: .reset))
        XCTAssertTrue(text(of: rig.url).contains("\"id:local_ab12\":{\"theme\":"),
                      "тема осталась на месте")
        XCTAssertTrue(text(of: rig.url).contains("\"font\":\"none\""), "сброс пишется маркером")
        XCTAssertEqual(text(of: rig.url).components(separatedBy: "\"font\":\"none\"").count - 1, 2,
                       "сброс лёг в оба ключа окна")
    }

    // MARK: - 20. круг «записали → прочитали»

    func testWindowThemeStoreParsesOwnOutput() {
        let clock = ThemeClock()
        let box = makeTemp()
        let first = makeStore(clock, in: box)
        first.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis", chat: "local_ab12",
            theme: .set(WindowThemeStoreTests.ocean), font: .set(WindowThemeStoreTests.menlo),
            size: .halves(answer: .set(16), question: .set(14)), frame: .set(true)))
        first.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeAll, title: "", theme: .set(WindowThemeStoreTests.sand),
            font: .keep))

        // Новый запуск приложения читает файл — и получает ровно то, что записал.
        let second = makeStore(clock, in: box)
        XCTAssertEqual(second.store.entries, first.store.entries)
        XCTAssertEqual(WindowThemeStore.body(second.store.entries, at: clock.now),
                       text(of: first.url), "перезапись тем же содержимым даёт те же байты")

        // Битый файл читается как пустой и НЕ удаляется: в нём могли остаться чужие ключи.
        let broken = makeTemp().appendingPathComponent(WindowThemeStore.fileName)
        try? Data("{\"version\":1,\"entries\":".utf8).write(to: broken)
        let store = WindowThemeStore(url: broken, now: { clock.now })
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path))
    }

    // MARK: - 21. ключи по полям команды

    func testWindowThemeStoreKeysFromCommand() {
        let isMain: (String) -> Bool = { $0 == "Claude" || $0 == "Главное" }

        // 1. Окно назвало свой чат: id главный, `main` — потому что это главное окно,
        //    заголовок — тень.
        XCTAssertEqual(WindowThemeStore.keys(title: "Главное", match: nil, chat: "local_ab12",
                                             isMainWindow: isMain),
                       ["id:local_ab12", "main", "chat:Главное"])
        // 2. Попап с чатом: id и тень, `main` тут не при чём.
        XCTAssertEqual(WindowThemeStore.keys(title: "Trelvis", match: nil, chat: "local_ab12",
                                             isMainWindow: isMain),
                       ["id:local_ab12", "chat:Trelvis"])
        // 3. Главное окно адресовано путём страницы, id неизвестен: заголовок пустой — только `main`.
        XCTAssertEqual(WindowThemeStore.keys(title: "", match: "/epitaxy/local_ab12", chat: nil,
                                             isMainWindow: isMain),
                       ["main"])
        // 4. Обычный заголовок без id — ключ чата по заголовку.
        XCTAssertEqual(WindowThemeStore.keys(title: "Trelvis", match: nil, chat: nil,
                                             isMainWindow: isMain),
                       ["chat:Trelvis"])
        // 5. Заголовок-заглушка: у главного окна это `main`, у безымянного попапа — ничего.
        XCTAssertEqual(WindowThemeStore.keys(title: "Claude", match: nil, chat: nil,
                                             isMainWindow: isMain), ["main"])
        XCTAssertEqual(WindowThemeStore.keys(title: "New chat", match: nil, chat: nil,
                                             isMainWindow: isMain), [])
        // 6. Адресация фокусом (заголовка нет вовсе) — какое это окно, неизвестно.
        XCTAssertEqual(WindowThemeStore.keys(title: "", match: nil, chat: nil,
                                             isMainWindow: isMain), [])

        // Третья точка зеркала: «Раскрасить по кругу» собирает команду сама, мимо applyTheme —
        // и обязана доходить до файла ровно так же.
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis",
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))
        XCTAssertEqual(Array(rig.store.entries.keys), ["chat:Trelvis"])
        XCTAssertEqual(rig.store.entries["chat:Trelvis"]?.layers["theme"],
                       .value(WindowThemeStoreTests.ocean.commandValue))
    }

    // MARK: - 22. примерка в файл не идёт

    func testWindowThemeStorePreviewIsNotRecorded() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis", preview: true,
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis", preview: false,
            theme: .keep, font: .keep))
        XCTAssertTrue(rig.store.entries.isEmpty, "примерка это экран, а не выбор")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.url.path),
                       "пустого файла не заводим вовсе")
    }

    // MARK: - 23. «всем окнам» снимает слой у остальных

    func testWindowThemeStoreAllScopeStripsLayerEverywhere() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis",
            theme: .set(WindowThemeStoreTests.ocean), font: .set(WindowThemeStoreTests.menlo)))
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Dictatorik",
            theme: .set(WindowThemeStoreTests.sand), font: .keep))

        clock.advance(10)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeAll, title: "", theme: .set(WindowThemeStoreTests.sand),
            font: .keep))
        // Тема теперь общая: у окон свой слой снят, а запись без слоёв выброшена целиком.
        XCTAssertEqual(rig.store.entries.keys.sorted(), ["*", "chat:Trelvis"])
        XCTAssertNil(rig.store.entries["chat:Trelvis"]?.layers["theme"])
        XCTAssertEqual(rig.store.entries["chat:Trelvis"]?.layers["font"],
                       .value(WindowThemeStoreTests.menlo.commandValue))
        XCTAssertEqual(rig.store.entries["*"]?.layers["theme"],
                       .value(WindowThemeStoreTests.sand.commandValue))

        // «Как у Claude (все окна)» убирает слой и из общей записи — ровно как страница.
        clock.advance(10)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeAll, title: "", theme: .reset, font: .keep))
        XCTAssertEqual(rig.store.entries.keys.sorted(), ["chat:Trelvis"])
    }

    // MARK: - 24. вытеснение по потолку

    func testWindowThemeStoreEvictsOldest() {
        var map: [String: WindowThemeEntry] = [:]
        for index in 0..<200 {
            map[String(format: "id:local_%04d", index)] = fullEntry(at: 1_757_100_000_000 + index)
        }
        XCTAssertGreaterThan(WindowThemeStore.bodySize(map), WindowThemeStore.bodyLimit,
                             "200 полных записей заведомо больше 32 КБ — иначе проверка пустая")
        WindowThemeStore.trim(&map)
        XCTAssertLessThanOrEqual(WindowThemeStore.bodySize(map), WindowThemeStore.bodyLimit)
        XCTAssertFalse(map.keys.contains("id:local_0000"), "самое старое по at ушло первым")
        XCTAssertTrue(map.keys.contains("id:local_0199"), "свежие записи целы")
        XCTAssertGreaterThan(map.count, 50, "потолок байтовый, а не «пять записей»")

        // Страховочный потолок: ровно столько ключей принимает страница.
        var many: [String: WindowThemeEntry] = [:]
        for index in 0..<250 {
            many[String(format: "id:local_%04d", index)] =
                WindowThemeEntry(layers: ["frame": .value(.bool(true))], at: 1_000 + index)
        }
        WindowThemeStore.trim(&many)
        XCTAssertEqual(many.count, WindowThemeStore.keyLimit)
        XCTAssertFalse(many.keys.contains("id:local_0000"))
    }

    // MARK: - 25, 26, 26а. карта страницы

    func testWindowThemeStoreAbsorbReplacesWhenPageNotEmpty() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.beginGeneration()
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis",
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))

        // Карта страницы — источник правды: в ней и то, что Элвис выбирал до этого воркфлоу,
        // и то, что он снял руками. Она заменяет записи ЦЕЛИКОМ, а не доливается.
        let page = WindowThemeStore.map(from: [
            "id:local_ab12": ["theme": ["id": "sand", "name": "Песок", "type": "light",
                                        "palette": ["accent": "#a71", "background": "#fed"]],
                              "frame": true],
            "main": ["font": "none"],
            "hack": ["theme": "none"],
        ])
        clock.advance(5)
        rig.store.absorb(page: page, at: clock.now)
        XCTAssertEqual(rig.store.entries.keys.sorted(), ["id:local_ab12", "main"],
                       "чужой ключ отброшен, старая запись зеркала заменена")
        XCTAssertEqual(rig.store.entries["id:local_ab12"]?.layers["theme"],
                       .value(WindowThemeStoreTests.sand.commandValue))
        XCTAssertEqual(rig.store.entries["main"]?.layers["font"], .reset)
        XCTAssertEqual(rig.store.entries["id:local_ab12"]?.at, 1_757_100_005_000)

        // Поля `themes` в круге не было вовсе — файл не трогаем и ответом это не считаем.
        rig.store.absorb(page: nil, at: clock.now)
        XCTAssertEqual(rig.store.entries.count, 2)
    }

    func testWindowThemeStoreAbsorbKeepsFileWhenFirstAnswerEmpty() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis",
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))
        rig.store.beginGeneration()

        // Первый ответ поколения пустой — это и есть переустановка Claude: терять нечего,
        // возвращать есть что.
        rig.store.absorb(page: [:], at: clock.now)
        XCTAssertEqual(rig.store.entries.keys.sorted(), ["chat:Trelvis"])
        XCTAssertTrue(text(of: rig.url).contains("chat:Trelvis"))
    }

    func testWindowThemeStoreAbsorbClearsFileWhenLaterAnswerEmpty() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.beginGeneration()
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis",
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))
        rig.store.absorb(page: WindowThemeStore.map(from: ["chat:Trelvis": ["frame": true]]),
                         at: clock.now)

        // Пусто на живом Claude значит «Элвис снял всё сам»: два клика «Как у Claude (все окна)»
        // доводят карту страницы до нуля ключей, и файл обязан это повторить.
        clock.advance(5)
        rig.store.absorb(page: [:], at: clock.now)
        XCTAssertTrue(rig.store.entries.isEmpty)
        XCTAssertEqual(text(of: rig.url),
                       "{\"version\":1,\"at\":\"2025-09-05T19:20:05Z\",\"entries\":{}}")

        // Смена pid Claude открывает новое поколение — и следующий пустой ответ снова
        // считается переустановкой.
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis",
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))
        rig.store.beginGeneration()
        rig.store.absorb(page: [:], at: clock.now)
        XCTAssertEqual(rig.store.entries.keys.sorted(), ["chat:Trelvis"])
    }

    // MARK: - 26б. `themes` только у claude.ai

    func testChatProbeTakesThemesOnlyFromClaudeAi() {
        let at = Date(timeIntervalSince1970: 1_757_100_000)
        let themes: [String: Any] = ["chat:Trelvis": ["frame": true]]
        func result(_ url: String, _ kind: String, withThemes: Bool) -> [String: Any] {
            var payload: [String: Any] = ["v": 1, "nonce": "n1", "kind": kind, "title": "Trelvis",
                                          "store": "ok"]
            if withThemes { payload["themes"] = themes }
            return ["id": 1, "url": url, "result": payload]
        }
        func answer(_ results: [[String: Any]]) -> Data {
            (try? JSONSerialization.data(withJSONObject: ["at": "2026-09-06T04:07:00Z",
                                                          "results": results])) ?? Data()
        }

        // Карту берём только у страницы claude.ai: probe лоадер гоняет во ВСЕХ страницах,
        // и пустая карта чужого origin запустила бы очистку файла.
        let mixed = ChatProbe.parseAnswer(answer([
            result("about:blank", "popout", withThemes: true),
            result("data:text/html,x", "other", withThemes: true),
            result("https://claude.ai/epitaxy/local_a1", "main", withThemes: true),
        ]), nonce: "n1", at: at)
        XCTAssertEqual(mixed.pages.count, 3)
        XCTAssertEqual(mixed.themes?.keys.sorted(), ["chat:Trelvis"])

        // Тот же ответ без claude.ai — поля нет вовсе, и это не «пустая карта».
        let foreign = ChatProbe.parseAnswer(answer([
            result("about:blank", "popout", withThemes: true),
            result("data:text/html,x", "other", withThemes: true),
        ]), nonce: "n1", at: at)
        XCTAssertNil(foreign.themes)

        // Главное окно ответило без карты (страница старой версии) — тоже nil.
        let silent = ChatProbe.parseAnswer(answer([
            result("https://claude.ai/epitaxy/local_a1", "main", withThemes: false),
        ]), nonce: "n1", at: at)
        XCTAssertNil(silent.themes)
        XCTAssertEqual(silent.pages.count, 1)
    }

    // MARK: - 27. байты команды возврата

    func testThemesRestoreCommandFields() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis", chat: "local_ab12",
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))

        var sent: [String] = []
        rig.store.beginGeneration()
        rig.store.restoreTick(titles: ["Trelvis"], at: clock.now) { fields in
            sent.append(CommandChannel.payload(action: WindowThemeStore.restoreAction,
                                               fields: fields, id: "1757100000000-0001",
                                               at: clock.now))
            return true
        }
        let entry = """
        {"theme":{"id":"ocean","name":"Океан","type":"dark",\
        "palette":{"accent":"#3af","background":"#012"}}}
        """
        XCTAssertEqual(sent, ["""
        {"id":"1757100000000-0001","action":"themes-restore","at":"2025-09-05T19:20:00Z",\
        "scope":"all","entries":{"chat:Trelvis":\(entry),"id:local_ab12":\(entry)}}
        """], "`at` записей странице не нужен — он бухгалтерия файла")
    }

    // MARK: - 28, 29. рассылка по поколениям

    func testThemesRestoreGenerationSendsAtMostThree() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis",
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))
        rig.store.beginGeneration()

        var sent = 0
        func tick(_ titles: [String]) {
            rig.store.restoreTick(titles: titles, at: clock.now) { _ in
                sent += 1
                return true
            }
        }

        // Первый тик поколения, где Claude есть на экране.
        tick(["Trelvis"])
        XCTAssertEqual(sent, 1)
        // Окно открылось, но с прошлой команды не прошло и 5 с — ждём.
        clock.advance(2)
        tick(["Trelvis", "Dictatorik"])
        XCTAssertEqual(sent, 1)
        clock.advance(4)
        tick(["Trelvis", "Dictatorik"])
        XCTAssertEqual(sent, 2)
        // Набор окон не менялся — молчим, сколько бы тиков ни прошло.
        clock.advance(10)
        tick(["Trelvis", "Dictatorik"])
        XCTAssertEqual(sent, 2)
        clock.advance(6)
        tick(["Trelvis", "Dictatorik", "Vkusnoff"])
        XCTAssertEqual(sent, 3)
        // Больше трёх за поколение — это шторм, а не восстановление.
        clock.advance(6)
        tick(["Trelvis"])
        XCTAssertEqual(sent, 3)

        // Смена pid Claude открывает новое поколение — счёт начинается заново.
        rig.store.beginGeneration()
        clock.advance(6)
        tick(["Trelvis"])
        XCTAssertEqual(sent, 4)
    }

    func testThemesRestoreSilentWhenEmpty() {
        let clock = ThemeClock()
        let rig = makeStore(clock)
        rig.store.beginGeneration()

        var sent = 0
        let send: ([(key: String, value: CommandValue)]) -> Bool = { _ in
            sent += 1
            return true
        }
        // Файла нет вовсе.
        rig.store.restoreTick(titles: ["Trelvis"], at: clock.now, send: send)
        XCTAssertEqual(sent, 0)

        // Записи есть, но Claude не запущен — окон на экране нет.
        rig.store.record(fields: ClaudeActions.themeFields(
            scope: MenuModel.themeScopeWindow, title: "Trelvis",
            theme: .set(WindowThemeStoreTests.ocean), font: .keep))
        rig.store.restoreTick(titles: [], at: clock.now, send: send)
        XCTAssertEqual(sent, 0)

        // Команда не записалась (диск, права) — попытку не засчитываем, попробуем на следующем тике.
        rig.store.restoreTick(titles: ["Trelvis"], at: clock.now) { _ in false }
        rig.store.restoreTick(titles: ["Trelvis"], at: clock.now, send: send)
        XCTAssertEqual(sent, 1)
    }

    // MARK: - 30. `ProjectPaint.forget()`

    func testProjectPaintForgetDropsMarksWithoutCommands() {
        let box = makeTemp()
        let root = box.appendingPathComponent("_ElvisProjects", isDirectory: true)
        let alpha = root.appendingPathComponent("Alpha", isDirectory: true)
        try? FileManager.default.createDirectory(at: alpha.appendingPathComponent(".git"),
                                                 withIntermediateDirectories: true)
        let sessions = box.appendingPathComponent("sessions/4646c58f/8cb117af", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session: [String: Any] = ["sessionId": "local_a1", "title": "Alpha",
                                      "titleSource": "user", "cwd": alpha.path,
                                      "originCwd": alpha.path, "lastFocusedAt": 3000,
                                      "lastActivityAt": 3000, "isArchived": false]
        try? (try? JSONSerialization.data(withJSONObject: session))?
            .write(to: sessions.appendingPathComponent("local_a1.json"))
        let status = box.appendingPathComponent("status.json")
        let statusBody: [String: Any] = [
            "at": "2026-09-06T04:07:00Z", "loader": 7, "windows": [],
            "webContents": [["id": 2, "url": "https://claude.ai/epitaxy/local_a1"]],
        ]
        try? (try? JSONSerialization.data(withJSONObject: statusBody))?.write(to: status)

        let clock = ThemeClock()
        let index = ProjectIndex(sessionsDirectory: box.appendingPathComponent("sessions"),
                                 statusURL: status, projectsRoot: root, home: box,
                                 now: { clock.now })
        let paint = ProjectPaint(index: index,
                                 store: ProjectSettingsStore(
                                     registryURL: box.appendingPathComponent("projects.json")),
                                 defaults: MemoryThemeDefaults(), now: { clock.now })
        var sent: [ProjectPaintCommand] = []
        paint.send = { command in
            sent.append(command)
            return true
        }
        paint.tick()
        XCTAssertEqual(sent.count, 1, "окно проекта покрашено — отпечаток на месте")
        clock.advance(10)
        paint.tick()
        XCTAssertEqual(sent.count, 1, "ни папка, ни вид не изменились")

        // Claude перезапустился: страницы голые, а отпечатки прежние. Забываем их МОЛЧА —
        // команд снятия тут быть не должно (в отличие от выключения тумблера).
        paint.forget()
        XCTAssertEqual(sent.count, 1)
        clock.advance(10)
        paint.tick()
        XCTAssertEqual(sent.count, 2, "ближайший тик красит окно заново")
    }
}

/// UserDefaults в памяти: тумблер покраски не должен попадать в живые настройки приложения.
private final class MemoryThemeDefaults: ThemeDefaults {
    private var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
