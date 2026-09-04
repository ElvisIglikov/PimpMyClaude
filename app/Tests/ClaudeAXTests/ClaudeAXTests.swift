import AppKit
import XCTest
@testable import ClaudeAX

/// Хранилище-заглушка: тесты не должны писать в живые настройки приложения.
private final class MemoryDefaults: ThemeDefaults {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

/// Только чистая логика: раскладка «Расставить», клавиши меню и формат command.json.
/// Живой AX (окна Claude, авто-Allow, popUp) проверяется руками на гейте.
final class ClaudeAXTests: XCTestCase {
    // Десять команд: восемь исходных плюс «Новое окно» и «В отдельное окно» (план WF13).
    func testSkeleton() { XCTAssertEqual(ClaudeCommand.allCases.count, 10) }

    // MARK: - «Расставить»

    func testColumnsKeepOneRowWhileCellsAreWideEnough() {
        // 1920/4 = 480 ≥ 340 — четыре столбца во всю высоту, а не 2×2.
        XCTAssertEqual(ArrangeLayout.columns(count: 4, width: 1920), 4)
        XCTAssertEqual(ArrangeLayout.columns(count: 1, width: 1920), 1)
        // 1920/6 = 320 < 340 — столбец отбрасывается, появляется второй ряд.
        XCTAssertEqual(ArrangeLayout.columns(count: 6, width: 1920), 5)
        XCTAssertEqual(ArrangeLayout.columns(count: 8, width: 1000), 2)
    }

    func testFramesTileAreaWithoutGaps() {
        let area = CGRect(x: 100, y: 25, width: 1710, height: 1055)
        let cells = ArrangeLayout.frames(count: 5, in: area)
        XCTAssertEqual(cells.count, 5)
        XCTAssertEqual(cells[0].minX, area.minX)
        XCTAssertEqual(cells[4].maxX, area.maxX)
        for i in 1..<cells.count {
            XCTAssertEqual(cells[i].minX, cells[i - 1].maxX, "щель между ячейками \(i - 1) и \(i)")
            XCTAssertEqual(cells[i].height, area.height)
        }
        XCTAssertTrue(ArrangeLayout.frames(count: 0, in: area).isEmpty)
    }

    func testFramesFillRowsTopDown() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let cells = ArrangeLayout.frames(count: 3, in: area) // 1000/3 = 333 < 340 → 2×2
        XCTAssertEqual(cells[0], CGRect(x: 0, y: 0, width: 500, height: 400))
        XCTAssertEqual(cells[1], CGRect(x: 500, y: 0, width: 500, height: 400))
        XCTAssertEqual(cells[2], CGRect(x: 0, y: 400, width: 500, height: 400))
    }

    func testOrderKeepsRowsLeftToRight() {
        let frames = [
            CGRect(x: 800, y: 0, width: 400, height: 400),   // 0 — правое верхнее
            CGRect(x: 0, y: 40, width: 400, height: 400),    // 1 — левое верхнее (тот же ряд, Δy < 60)
            CGRect(x: 0, y: 500, width: 400, height: 400),   // 2 — нижнее
        ]
        XCTAssertEqual(ArrangeLayout.order(of: frames), [1, 0, 2])
    }

    // MARK: - клавиши

    func testMenuKeysMatchReadme() {
        // Решение 4 плана WF9: заголовок — голое название, клавиша живёт в keyEquivalent,
        // подсказку справа серым AppKit рисует сам.
        let down = String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!)
        let up = String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)
        let expected: [(ClaudeCommand, String, UInt32, String, NSEvent.ModifierFlags, Bool)] = [
            (.cashout, "Обкэшить", 0x2D, "n", [.command, .shift], true),
            // ⌘N — штатная клавиша Claude: показываем, но не регистрируем.
            (.newChat, "Новый чат", 0x2D, "n", [.command], false),
            // ⌥⌘N у Claude свободна — её мы регистрируем сами (план WF13).
            (.newWindow, "Новое окно", 0x2D, "n", [.command, .option], true),
            (.collapse, "Свернуть", 0x7D, down, [.command, .option], true),
            (.expand, "Развернуть", 0x7E, up, [.command, .option], true),
            (.arrange, "Расставить", 0x00, "a", [.command, .option], true),
            (.show, "Показать", 0x01, "s", [.command, .option], true),
            (.scroll, "Прокрутить", 0x02, "d", [.command, .option], true),
        ]
        // Порядок пунктов — экранный (вариант А плана WF14): «🚀 Workflow» первым, оконная
        // тройка WF13 сразу за ним, «Развернуть выше, свернуть ниже», а редкая четвёрка
        // (moreCommands) — в хвосте, она рисуется внутри «⋯ Ещё ▸».
        XCTAssertEqual(MenuModel.entries.map { $0.command },
                       [.workflow, .newChat, .newWindow, .popoutWindow, .expand, .collapse,
                        .cashout, .arrange, .show, .scroll])
        // Блокер Б1: спрятанные пункты обязаны остаться в entries — хоткеи регистрируются
        // перебором именно его (id = индекс+1), и вынести пункт отсюда значит убить клавишу.
        XCTAssertEqual(MenuModel.moreCommands, [.cashout, .arrange, .show, .scroll])
        for command in MenuModel.moreCommands {
            let entry = MenuModel.entry(for: command)
            XCTAssertNotNil(entry?.key, "\(command) выпал из entries — с ним умрёт его клавиша")
            XCTAssertEqual(entry?.registersHotkey, true, "\(command) перестал регистрировать хоткей")
        }
        // Разделители: после «В отдельное окно» и после «Свернуть» (мелочь М3 критика).
        XCTAssertEqual(MenuModel.separatorsAfter, [.popoutWindow, .collapse])
        // Без клавиш два пункта: «Workflow» (⌘⌥W занят самим Claude) и «В отдельное окно».
        for (command, title) in [(ClaudeCommand.workflow, "Workflow"),
                                 (.popoutWindow, "В отдельное окно")] {
            let entry = MenuModel.entry(for: command)
            XCTAssertEqual(entry?.menuTitle, title)
            XCTAssertNil(entry?.key)
            XCTAssertEqual(entry?.registersHotkey, false)
        }

        for (command, title, code, equivalent, mask, registers) in expected {
            let entry = MenuModel.entry(for: command)
            XCTAssertEqual(entry?.menuTitle, title)
            XCTAssertFalse(entry?.menuTitle.contains("⌘") ?? true, "клавиша осталась в заголовке")
            XCTAssertEqual(entry?.key?.keyCode, code)
            XCTAssertEqual(entry?.key?.keyEquivalent, equivalent)
            XCTAssertEqual(entry?.key?.modifierMask, mask)
            XCTAssertEqual(entry?.registersHotkey, registers)
        }
        XCTAssertEqual(MenuModel.entries.map { $0.icon },
                       ["🚀", "💬", "🪟", "🪟", "⬆️", "⬇️", "💰", "▦", "👀", "⏬"])
    }

    /// Клавиши обязаны доехать до самих пунктов меню — и у тех четырёх, что уехали
    /// в «⋯ Ещё ▸» (блокер Б1): прячем их только с глаз.
    func testMenuItemsCarryKeyEquivalents() throws {
        let menu = MinimizeMenu.build(config: MinimizeMenu.MenuConfig())
        // Верхний уровень — пять пунктов-команд из entries; «Новое окно ▸» (план WF16),
        // «Оформление ▸» и «Ещё ▸» — с подменю, и клавиш сами не носят: ⌥⌘N уехала на
        // «Здесь же» внутри подменю (сторож — testNewWindowKeepsHotkeyEntry).
        let items = menu.items.filter { !$0.isSeparatorItem && !$0.hasSubmenu }
        XCTAssertEqual(items.count, MenuModel.entries.count - MenuModel.moreCommands.count - 1)
        XCTAssertEqual(items.map { $0.title },
                       ["Workflow", "Новый чат", "В отдельное окно", "Развернуть", "Свернуть"])
        XCTAssertEqual(items.map { $0.keyEquivalent },
                       ["", "n", "", String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!),
                        String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!)])
        XCTAssertEqual(items.map { $0.keyEquivalentModifierMask },
                       [[], [.command], [], [.command, .option], [.command, .option]])

        // Четыре клавиши — внутри «⋯ Ещё ▸», в том же порядке, что в макете.
        let more = try XCTUnwrap(menu.items.first { $0.title == MenuModel.moreTitle }?.submenu)
        XCTAssertEqual(more.items.map { $0.title },
                       ["Обкэшить", "Расставить", "Показать", "Прокрутить"])
        XCTAssertEqual(more.items.map { $0.keyEquivalent }, ["n", "a", "s", "d"])
        XCTAssertEqual(more.items.map { $0.keyEquivalentModifierMask },
                       [[.command, .shift], [.command, .option], [.command, .option],
                        [.command, .option]])
        XCTAssertNotNil(menu.items.first { $0.title == MenuModel.moreTitle }?.image)
    }

    func testCarbonModifiers() {
        XCTAssertEqual(KeyMods([.command, .shift]).carbon, 0x0100 | 0x0200)
        XCTAssertEqual(KeyMods([.command, .option]).carbon, 0x0100 | 0x0800)
        XCTAssertEqual(MenuModel.quitKey.keyCode, 0x0C)
        XCTAssertEqual(MenuModel.quitKey.hint, "⌘Q")
    }

    // MARK: - command.json

    func testPayloadMatchesLoaderContract() throws {
        let at = Date(timeIntervalSince1970: 1_756_900_000) // 2025-09-03T11:46:40Z
        let body = CommandChannel.payload(action: "cashout", extra: ["title": "Чат \"один\""],
                                          id: "1756900000123-0042", at: at)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "1756900000123-0042")
        XCTAssertEqual(json["action"] as? String, "cashout")
        XCTAssertEqual(json["at"] as? String, "2025-09-03T11:46:40Z")
        XCTAssertEqual(json["title"] as? String, "Чат \"один\"")
        XCTAssertTrue(body.hasPrefix("{\"id\":"), body)
    }

    func testJSONStringEscapesControls() {
        XCTAssertEqual(CommandChannel.jsonString("a\"b\\c"), "\"a\\\"b\\\\c\"")
        XCTAssertEqual(CommandChannel.jsonString("a\nb"), "\"a\\u000ab\"")
    }

    func testAtomicWriteReplacesFile() throws {
        // Живой ~/Library не трогаем: пишем во временную папку.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        let file = dir.appendingPathComponent("command.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(CommandChannel.writeAtomic(file, "{\"id\":\"1\"}")) // папки ещё нет
        XCTAssertTrue(CommandChannel.writeAtomic(file, "{\"id\":\"2\"}")) // поверх существующего
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{\"id\":\"2\"}")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.appendingPathExtension("tmp").path))
    }

    /// Тест гонки (критик п. 1 плана WF9): лоадер читает command.json раз в 500 мс, поэтому
    /// две записи подряд потеряли бы первую. Часы и таймер подставлены, живой ~/Library не трогаем.
    func testQueueKeepsSixHundredMillisecondsBetweenWrites() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        let file = dir.appendingPathComponent("command.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = Date(timeIntervalSince1970: 1_756_900_000)
        var now = start
        var timers: [(at: Date, block: () -> Void)] = []
        let channel = CommandChannel(path: file, now: { now },
                                     schedule: { delay, block in
                                         timers.append((now.addingTimeInterval(delay), block))
                                     })
        func action() throws -> String {
            let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: file))
            return try XCTUnwrap((json as? [String: Any])?["action"] as? String)
        }
        /// Прокрутить часы до ближайшего таймера и выполнить его — как сделал бы главный поток.
        func tick() throws {
            let timer = try XCTUnwrap(timers.first, "таймер не поставлен")
            timers.removeFirst()
            now = max(now, timer.at)
            timer.block()
        }

        // Две команды меню за 100 мс: первая на диске сразу, вторая ждёт своей очереди.
        XCTAssertTrue(channel.write(action: "collapse"))
        XCTAssertEqual(try action(), "collapse")
        now = now.addingTimeInterval(0.1)
        XCTAssertTrue(channel.write(action: "expand"))
        XCTAssertEqual(try action(), "collapse", "вторая запись затёрла первую")
        try tick()
        XCTAssertEqual(try action(), "expand")
        XCTAssertGreaterThanOrEqual(now.timeIntervalSince(start), CommandChannel.minInterval)

        // Сводка — низший приоритет: ждёт очереди и пропадает, когда пришла команда меню.
        var statusWritten: Bool?
        let expandAt = now
        channel.write(action: "status", fields: [], completion: { statusWritten = $0 })
        XCTAssertEqual(try action(), "expand")
        XCTAssertNil(statusWritten)
        channel.write(action: "scroll")
        XCTAssertEqual(statusWritten, false, "сводку не вытеснила команда меню")

        // Предпросмотр — вне очереди, пишется сразу; после него «Прокрутить» ждёт те же 600 мс.
        now = now.addingTimeInterval(0.1)
        let previewAt = now
        XCTAssertTrue(channel.write(action: "theme",
                                    fields: [(key: "preview", value: .bool(true))],
                                    priority: .preview))
        XCTAssertEqual(try action(), "theme")
        try tick()
        XCTAssertEqual(try action(), "theme", "«Прокрутить» затёрла примерку раньше срока")
        try tick()
        XCTAssertEqual(try action(), "scroll")
        XCTAssertGreaterThanOrEqual(now.timeIntervalSince(previewAt), CommandChannel.minInterval)
        XCTAssertGreaterThanOrEqual(now.timeIntervalSince(expandAt), CommandChannel.minInterval)
        XCTAssertEqual(channel.lastCommand.hasPrefix("scroll @"), true, channel.lastCommand)
    }

    func testIDsDifferWithinTheSameMillisecond() {
        // Лоадер отбрасывает команду с прежним id, поэтому две подряд обязаны отличаться.
        let ids = Set((0..<200).map { _ in CommandChannel.makeID() })
        XCTAssertGreaterThan(ids.count, 150)
    }

    // MARK: - темы

    /// Мини-каталог формата themes.json: две годные темы и две кривые (без id, без палитры).
    private static let miniCatalog = """
    {"version":1,"themes":[
      {"id":"violet","name":"Фиолетовая","type":"dark","palette":{"accent":"#a78bfa",\
    "background":"#1b1626","foreground":"#ece9f5","sidebar":"#151021","panel":"#241d33","muted":"#8b81a6"}},
      {"id":"arctic","name":"Арктика","type":"light","palette":{"accent":"#2563eb",\
    "background":"#f7f9fc","foreground":"#101828","sidebar":"#eef2f8","panel":"#ffffff","muted":"#667085"}},
      {"id":"","name":"Без id","type":"dark","palette":{"accent":"#000000"}},
      {"id":"broken","name":"Без палитры","type":"dark"}
    ]}
    """

    private func catalog() -> [Theme] { ThemeCatalog.parse(Data(ClaudeAXTests.miniCatalog.utf8)) }

    func testCatalogParsesThemesAndSkipsBroken() {
        let themes = catalog()
        XCTAssertEqual(themes.map { $0.id }, ["violet", "arctic"])
        XCTAssertEqual(themes[0].name, "Фиолетовая")
        XCTAssertEqual(themes[0].palette["background"], "#1b1626")
        XCTAssertEqual(themes[1].type, "light")
        XCTAssertTrue(ThemeCatalog.parse(Data("не json".utf8)).isEmpty)
        XCTAssertTrue(ThemeCatalog.parse(Data("{\"version\":1}".utf8)).isEmpty)
        // Нет файла — пустой каталог, а не падение.
        XCTAssertTrue(ThemeCatalog.load(directory: URL(fileURLWithPath: "/nope/\(UUID().uuidString)")).isEmpty)
    }

    func testCatalogLoadsFileFromResourcesDirectory() throws {
        // Так же приложение читает themes.json из Contents/Resources (его кладёт tools/bundle.sh).
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(ClaudeAXTests.miniCatalog.utf8).write(to: dir.appendingPathComponent(ThemeCatalog.fileName))
        XCTAssertEqual(ThemeCatalog.load(directory: dir).map { $0.id }, ["violet", "arctic"])
    }

    /// Живой каталог из репозитория: `claude-patch/themes.json` кладёт в бандл tools/bundle.sh.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    func testBundledThemesGoAroundTheColourWheel() throws {
        // Решение 5 плана WF9: имена по-русски, порядок — по цветовому кругу, id не меняются.
        let themes = ThemeCatalog.load(directory: ClaudeAXTests.repositoryRoot
            .appendingPathComponent("claude-patch", isDirectory: true))
        XCTAssertEqual(themes.map { $0.id },
                       ["red", "orange", "yellow", "green", "matrix", "teal", "tokyo", "blue",
                        "violet", "dracula", "lilac", "pink", "crimson", "brown", "gray",
                        "peach", "lemon", "cream", "mint", "sky", "arctic", "lavender", "sakura",
                        "powder"])
        // Меню режет каталог на две секции — порядок внутри каждой обязан остаться тем же.
        XCTAssertEqual(themes.filter { !$0.isLight }.map { $0.name },
                       ["Красная", "Оранжевая", "Жёлтая", "Зелёная", "Матрица", "Бирюзовая",
                        "Токийская ночь", "Синяя", "Фиолетовая", "Дракула", "Сиреневая", "Розовая",
                        "Малиновая", "Коричневая", "Серая"])
        XCTAssertEqual(themes.filter { $0.isLight }.map { $0.name },
                       ["Персиковая", "Лимонная", "Кремовая", "Мятная", "Небесная", "Светлая",
                        "Лавандовая", "Сакура", "Пудровая"])
        // Английских имён не осталось (Matrix, Dracula, Tokyo Night), палитра у всех полная.
        for theme in themes {
            XCTAssertEqual(Set(theme.palette.keys), Set(Theme.paletteOrder), theme.id)
            let first = try XCTUnwrap(theme.name.unicodeScalars.first)
            XCTAssertTrue((0x410...0x44F).contains(Int(first.value)), "имя «\(theme.name)» не по-русски")
        }
    }

    /// Шрифт для команды: моноширинный, семейство — голым именем (контракт п. 5).
    private static let monoFont = Font(id: "sf-mono", family: "SF Mono", category: .mono, displayName: "SF Mono")

    private func themeBody(theme: Layer<Theme>, font: Layer<Font>,
                           size: Layer<Size> = .keep, frame: Layer<Bool> = .keep,
                           scope: String = MenuModel.themeScopeWindow, title: String = "Vkusnoff",
                           preview: Bool? = nil,
                           id: String = "1756900000123-0042",
                           at: TimeInterval = 1_756_900_000) -> String {
        CommandChannel.payload(action: "theme",
                               fields: ClaudeActions.themeFields(scope: scope, title: title,
                                                                 preview: preview,
                                                                 theme: theme, font: font,
                                                                 size: size, frame: frame),
                               id: id, at: Date(timeIntervalSince1970: at))
    }

    func testThemePayloadMatchesContract() throws {
        // Побайтно, контракт п. 5 плана WF6: id, action, at, scope, title, theme, font;
        // слоя, которого не трогаем, в команде нет вовсе.
        let head = "{\"id\":\"1756900000123-0042\",\"action\":\"theme\",\"at\":\"2025-09-03T11:46:40Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\""
        let themeField = ",\"theme\":{\"id\":\"violet\",\"name\":\"Фиолетовая\",\"type\":\"dark\","
            + "\"palette\":{\"accent\":\"#a78bfa\",\"background\":\"#1b1626\",\"foreground\":\"#ece9f5\","
            + "\"sidebar\":\"#151021\",\"panel\":\"#241d33\",\"muted\":\"#8b81a6\"}}"
        let fontField = ",\"font\":{\"id\":\"sf-mono\",\"family\":\"SF Mono\",\"mono\":true}"
        let violet = catalog()[0]
        let font = ClaudeAXTests.monoFont

        // 1. Только тема.
        XCTAssertEqual(themeBody(theme: .set(violet), font: .keep), head + themeField + "}")
        // 2. Только шрифт.
        XCTAssertEqual(themeBody(theme: .keep, font: .set(font)), head + fontField + "}")
        // 3. Оба слоя (своя тема) — тема всегда перед шрифтом.
        XCTAssertEqual(themeBody(theme: .set(violet), font: .set(font)), head + themeField + fontField + "}")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(themeBody(theme: .set(violet), font: .set(font)).utf8)) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "theme")
        XCTAssertEqual(json["scope"] as? String, "window")
        XCTAssertEqual(json["title"] as? String, "Vkusnoff")
        let theme = try XCTUnwrap(json["theme"] as? [String: Any])
        XCTAssertEqual(theme["id"] as? String, "violet")
        XCTAssertEqual(theme["type"] as? String, "dark")
        XCTAssertEqual((theme["palette"] as? [String: String])?["background"], "#1b1626")
        let fontJSON = try XCTUnwrap(json["font"] as? [String: Any])
        XCTAssertEqual(fontJSON["family"] as? String, "SF Mono")
        XCTAssertEqual(fontJSON["mono"] as? Bool, true)
    }

    func testThemeResetPayloadCarriesNull() throws {
        // Сброс обоих слоёв «всем окнам».
        let body = themeBody(theme: .reset, font: .reset, scope: MenuModel.themeScopeAll, title: "",
                             id: "1-0001", at: 0)
        XCTAssertTrue(body.hasSuffix("\"scope\":\"all\",\"title\":\"\",\"theme\":null,\"font\":null}"), body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertTrue(json["theme"] is NSNull)
        XCTAssertTrue(json["font"] is NSNull)

        // Сброс ОДНОГО слоя: «Системный (как у Claude)» не должен трогать тему окна.
        let fontOnly = themeBody(theme: .keep, font: .reset, id: "1-0001", at: 0)
        XCTAssertEqual(fontOnly, "{\"id\":\"1-0001\",\"action\":\"theme\",\"at\":\"1970-01-01T00:00:00Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\",\"font\":null}")
        // И наоборот — «Как у Claude» в теме не трогает шрифт.
        XCTAssertEqual(themeBody(theme: .reset, font: .keep, id: "1-0001", at: 0),
                       "{\"id\":\"1-0001\",\"action\":\"theme\",\"at\":\"1970-01-01T00:00:00Z\","
                       + "\"scope\":\"window\",\"title\":\"Vkusnoff\",\"theme\":null}")
        // Оба слоя «не трогать» — команды нет вообще.
        XCTAssertEqual(ClaudeActions.themeFields(scope: "window", title: "", theme: .keep, font: .keep).count, 2)

        // Старые команды не поехали: extra по-прежнему пишет строки по алфавиту.
        XCTAssertEqual(CommandChannel.payload(action: "scroll", extra: [:], id: "1-0001",
                                              at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"scroll\",\"at\":\"1970-01-01T00:00:00Z\"}")
    }

    func testSizeAndFramePayloadMatchContract() throws {
        // Побайтно, контракт п. 1 плана WF12: id, action, at, scope, title, theme, font, size, frame.
        // Размер — числа, а не строки; рамка — true. Слоя, которого не трогаем, в команде нет.
        let head = "{\"id\":\"1756900000123-0042\",\"action\":\"theme\",\"at\":\"2025-09-03T11:46:40Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\""
        let themeField = ",\"theme\":{\"id\":\"violet\",\"name\":\"Фиолетовая\",\"type\":\"dark\","
            + "\"palette\":{\"accent\":\"#a78bfa\",\"background\":\"#1b1626\",\"foreground\":\"#ece9f5\","
            + "\"sidebar\":\"#151021\",\"panel\":\"#241d33\",\"muted\":\"#8b81a6\"}}"
        let fontField = ",\"font\":{\"id\":\"sf-mono\",\"family\":\"SF Mono\",\"mono\":true}"
        let violet = catalog()[0]
        let font = ClaudeAXTests.monoFont

        // 1. Только размер — и только та половина, которую выбрали в меню.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .set(Size(answer: 16))),
                       head + ",\"size\":{\"answer\":16}}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .set(Size(question: 13))),
                       head + ",\"size\":{\"question\":13}}")
        // 2. Только рамка.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, frame: .set(true)), head + ",\"frame\":true}")
        // 3. Все четыре слоя (своя тема со всем сохранённым) — порядок тема, шрифт, размер, рамка.
        let sizeField = ",\"size\":{\"answer\":16,\"question\":14}"
        let full = themeBody(theme: .set(violet), font: .set(font),
                             size: .set(Size(answer: 16, question: 14)), frame: .set(true))
        XCTAssertEqual(full, head + themeField + fontField + sizeField + ",\"frame\":true}")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(full.utf8)) as? [String: Any])
        let size = try XCTUnwrap(json["size"] as? [String: Any])
        XCTAssertEqual(size["answer"] as? Int, 16)   // именно число, а не строка
        XCTAssertEqual(size["question"] as? Int, 14)
        XCTAssertEqual(json["frame"] as? Bool, true)

        // 4. Сброс слоя — null; размер снимается целиком, обеими половинами.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .reset), head + ",\"size\":null}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, frame: .reset), head + ",\"frame\":null}")
        let reset = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(themeBody(theme: .keep, font: .keep, size: .reset, frame: .reset).utf8)) as? [String: Any])
        XCTAssertTrue(reset["size"] is NSNull)
        XCTAssertTrue(reset["frame"] is NSNull)
        // Тема и шрифт при этом не поехали.
        XCTAssertNil(reset["theme"])
        XCTAssertNil(reset["font"])

        // 5. Примерка размера — то же тело плюс preview перед слоями.
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, size: .set(Size(answer: 20)), preview: true),
                       head + ",\"preview\":true,\"size\":{\"answer\":20}}")
        XCTAssertEqual(themeBody(theme: .keep, font: .keep, frame: .set(true), preview: true),
                       head + ",\"preview\":true,\"frame\":true}")

        // 6. Границы контракта 11…24 и склейка половин (страница склеивает слой так же).
        XCTAssertEqual(Size(answer: 40, question: 3).commandValue.json,
                       "{\"answer\":24,\"question\":11}")
        XCTAssertEqual(Size(answer: 16).merging(Size(question: 14)), Size(answer: 16, question: 14))
        XCTAssertEqual(Size(answer: 16).merging(Size(answer: 12)), Size(answer: 12))
        XCTAssertTrue(Size().isEmpty)
        XCTAssertFalse(Size(question: 12).isEmpty)
        XCTAssertEqual(Size.one(.answer, 15), Size(answer: 15))
        XCTAssertEqual(Size.one(.question, 15), Size(question: 15))
        XCTAssertEqual(Size(answer: 15, question: 12).value(.question), 12)
        XCTAssertEqual(CommandValue.number(12).json, "12")
    }

    func testPreviewPayloadMatchesContract() throws {
        // Побайтно, контракт п. 1 плана WF8: preview стоит между title и слоями,
        // в примерке слой ровно один, «конец предпросмотра» — без слоёв вовсе.
        let head = "{\"id\":\"1756900000123-0042\",\"action\":\"theme\",\"at\":\"2025-09-03T11:46:40Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\""
        let violet = catalog()[0]

        // 1. Примерка темы — тело закрепляющей команды плюс "preview":true перед слоем.
        let preview = themeBody(theme: .set(violet), font: .keep, preview: true)
        XCTAssertEqual(preview, themeBody(theme: .set(violet), font: .keep)
            .replacingOccurrences(of: head, with: head + ",\"preview\":true"))
        XCTAssertTrue(preview.hasPrefix(head + ",\"preview\":true,\"theme\":{\"id\":\"violet\","), preview)

        // 2. Примерка сброса шрифта («Системный») — слой уходит как null.
        XCTAssertEqual(themeBody(theme: .keep, font: .reset, preview: true),
                       head + ",\"preview\":true,\"font\":null}")

        // 3. Конец предпросмотра — preview: false и ни одного слоя.
        let end = themeBody(theme: .keep, font: .keep, preview: false)
        XCTAssertEqual(end, head + ",\"preview\":false}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(end.utf8)) as? [String: Any])
        XCTAssertEqual(json["preview"] as? Bool, false)
        XCTAssertEqual(json["scope"] as? String, "window")
        XCTAssertNil(json["theme"])
        XCTAssertNil(json["font"])

        // Закрепляющая команда поля preview не носит вовсе.
        XCTAssertFalse(themeBody(theme: .set(violet), font: .keep).contains("\"preview\""))
    }

    func testCommandValueWritesBooleans() {
        XCTAssertEqual(CommandValue.bool(true).json, "true")
        XCTAssertEqual(CommandValue.bool(false).json, "false")
        XCTAssertEqual(CommandValue.object([(key: "mono", value: .bool(false))]).json, "{\"mono\":false}")
        XCTAssertEqual(Font(id: "georgia", family: "Georgia", category: .serif, displayName: "Джорджия")
            .commandValue.json, "{\"id\":\"georgia\",\"family\":\"Georgia\",\"mono\":false}")
    }

    /// Своя тема из my-themes.json: фиолетовая палитра + моноширинный шрифт.
    private func myTheme() -> MyTheme {
        MyTheme(id: "user-1756900000000", name: "Моя тёплая", type: "dark",
                palette: catalog()[0].palette, font: ClaudeAXTests.monoFont)
    }

    private func menuConfig() -> MinimizeMenu.MenuConfig {
        var config = MinimizeMenu.MenuConfig()
        config.themes = catalog()
        config.fonts = [Font(id: "georgia", family: "Georgia", category: .serif, displayName: "Georgia"),
                        ClaudeAXTests.monoFont]
        config.myThemes = [myTheme()]
        config.windowThemeID = "arctic"
        config.windowFontID = "sf-mono"
        config.windowSize = Size(answer: 16, question: 13)
        return config
    }

    /// Какие слои пункт НЕ трогает: t — тема, f — шрифт, s — размер, r — рамка.
    private func keptLayers(_ theme: Layer<Theme>, _ font: Layer<Font>,
                            _ size: Layer<Size>, _ frame: Layer<Bool>) -> String {
        (theme.isKeep ? "t" : "") + (font.isKeep ? "f" : "")
            + (size.isKeep ? "s" : "") + (frame.isKeep ? "r" : "")
    }

    /// Структура меню варианта А (план WF14 п. 5): верхний уровень короткий, всё оформление —
    /// в «🎨 Оформление ▸», редкое — в «⋯ Ещё ▸», «всем окнам» — одним подменю с ОДНОЙ шапкой.
    func testAppearanceMenuStructure() throws {
        var applied: [(scope: String, theme: String?, font: String?, keep: String)] = []
        var saved = 0
        var deleted: [String] = []
        var config = menuConfig()
        config.apply = { scope, theme, font, size, frame in
            applied.append((scope: scope, theme: theme.value?.id, font: font.value?.id,
                            keep: self.keptLayers(theme, font, size, frame)))
        }
        config.applyMyTheme = { scope, my in
            applied.append((scope: scope, theme: my.id, font: my.font?.id, keep: ""))
        }
        config.saveMyTheme = { saved += 1 }
        config.deleteMyTheme = { deleted.append($0.id) }
        let menu = MinimizeMenu.build(config: config)

        // MARK: верхний уровень — шесть команд, «Оформление ▸» и «Ещё ▸», три разделителя
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Workflow", "Новый чат", "Новое окно", "В отдельное окно", "—",
                        "Развернуть", "Свернуть", "—", "Оформление", "—", "Ещё"])
        // «Новое окно» стало подменю в WF16 — верхний уровень при этом не вырос ни на пункт.
        XCTAssertEqual(menu.items.filter { $0.hasSubmenu }.map { $0.title },
                       ["Новое окно", "Оформление", "Ещё"])
        // Двух разделителей подряд быть не должно — AppKit нарисовал бы две линии.
        for (index, item) in menu.items.enumerated() where item.isSeparatorItem {
            XCTAssertFalse(index > 0 && menu.items[index - 1].isSeparatorItem, "двойной разделитель")
        }

        // MARK: «🎨 Оформление ▸» — всё про вид этого окна
        let appearance = try XCTUnwrap(menu.items.first { $0.title == MenuModel.appearanceTitle }?.submenu)
        XCTAssertEqual(appearance.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["МОИ ТЕМЫ", "Моя тёплая", "—", "Цвет", "Шрифт", "Размер ответов",
                        "Размер вопросов", "Неоновая рамка", "Поля по бокам", "—", "Всем окнам",
                        "—", "Сохранить как мою тему…", "Удалить мою тему", "Всё как у Claude"])
        XCTAssertFalse(try XCTUnwrap(appearance.items.first).isEnabled) // «МОИ ТЕМЫ» — заголовок

        // MARK: «🎨 Цвет ▸» — один список: сброс, полоска, ТЁМНЫЕ, полоска, СВЕТЛЫЕ
        let color = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.colorTitle }?.submenu)
        XCTAssertEqual(color.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Как у Claude", "—", "ТЁМНЫЕ", "Фиолетовая", "—", "СВЕТЛЫЕ", "Арктика"])
        for title in ["ТЁМНЫЕ", "СВЕТЛЫЕ"] {
            let header = try XCTUnwrap(color.items.first { $0.title == title })
            XCTAssertFalse(header.isEnabled, "заголовок «\(title)» кликабелен")
            XCTAssertFalse(header.hasSubmenu)
        }
        let violet = try XCTUnwrap(color.items.first { $0.title == "Фиолетовая" })
        XCTAssertNotNil(violet.image) // кружок цвета
        XCTAssertEqual(violet.image?.size, NSSize(width: 14, height: 14))
        XCTAssertEqual(violet.image?.isTemplate, false)
        XCTAssertNotNil(violet.image?.tiffRepresentation) // кружок рисуется, а не падает
        // Цвета кружка — из палитры; кривой цвет не должен ронять меню.
        XCTAssertEqual(MinimizeMenu.color("#abc"), MinimizeMenu.color("#AABBCC"))
        XCTAssertNil(MinimizeMenu.color("не цвет"))
        XCTAssertNil(MinimizeMenu.color(nil))
        XCTAssertEqual(violet.state, .off)
        XCTAssertEqual(try XCTUnwrap(color.items.first { $0.title == "Арктика" }).state, .on) // выбрана
        // У окна своя запись есть — «Как у Claude» не отмечено (правило галок — отдельный тест).
        XCTAssertEqual(try XCTUnwrap(color.items.first { $0.title == "Как у Claude" }).state, .off)
        // Свои темы уехали на уровень «Оформление ▸» — в списке окна их больше нет.
        XCTAssertNil(color.items.first { $0.title == MenuModel.myThemesHeader })
        let my = try XCTUnwrap(appearance.items.first { $0.title == "Моя тёплая" })
        XCTAssertNotNil(my.image)
        XCTAssertEqual(my.state, .off)

        // MARK: «🖥 Всем окнам ▸» — шапка ровно одна, у него самого (критик В4)
        let all = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.allWindowsTitle }?.submenu)
        // «🌊 Живые цвета ▸» встали сразу под «🌈 Раскрасить по кругу ▸» (план WF18, вариант А).
        XCTAssertEqual(all.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["ВСЕМ ОКНАМ", "Цвет", "Шрифт", "Размер ответов", "Размер вопросов",
                        "Неоновая рамка", "—", "Раскрасить по кругу", "Живые цвета"])
        XCTAssertFalse(try XCTUnwrap(all.items.first).isEnabled)
        XCTAssertNotNil(appearance.items.first { $0.title == MenuModel.allWindowsTitle }?.image) // 🖥
        // МОИ ТЕМЫ остались в «Всем окнам ▸ → Цвет ▸» (блокер Б2): свою тему можно дать всем окнам.
        let colorAll = try XCTUnwrap(all.items.first { $0.title == MenuModel.colorTitle }?.submenu)
        XCTAssertEqual(colorAll.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["МОИ ТЕМЫ", "Моя тёплая", "—", "Как у Claude", "—", "ТЁМНЫЕ", "Фиолетовая",
                        "—", "СВЕТЛЫЕ", "Арктика"])
        // Шапки «ВСЕМ ОКНАМ» во вложенных списках больше нет — иначе она задвоилась бы.
        for nested in [colorAll,
                       try XCTUnwrap(all.items.first { $0.title == MenuModel.fontTitle }?.submenu),
                       try XCTUnwrap(all.items.first { $0.title == MenuModel.answerSizeTitle }?.submenu)] {
            XCTAssertNil(nested.items.first { $0.title == MenuModel.allWindowsHeader },
                         "шапка «ВСЕМ ОКНАМ» задвоилась в «\(nested.title)»")
        }
        // всем окнам ничего не задано → «Как у Claude»
        XCTAssertEqual(colorAll.items.first { $0.title == MenuModel.themeResetTitle }?.state, .on)

        // MARK: «🔤 Шрифт ▸» — сброс первым, дальше секции категорий
        let font = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.fontTitle }?.submenu)
        XCTAssertEqual(font.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Системный (как у Claude)", "—", "С ЗАСЕЧКАМИ", "Georgia", "—",
                        "МОНОШИРИННЫЕ", "SF Mono"])
        XCTAssertFalse(try XCTUnwrap(font.items.first { $0.title == "С ЗАСЕЧКАМИ" }).isEnabled)
        // Каждый пункт нарисован своим шрифтом.
        let georgia = try XCTUnwrap(font.items.first { $0.title == "Georgia" })
        XCTAssertEqual((georgia.attributedTitle?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 13)
        XCTAssertEqual(try XCTUnwrap(font.items.first { $0.title == "SF Mono" }).state, .on)
        let fontAll = try XCTUnwrap(all.items.first { $0.title == MenuModel.fontTitle }?.submenu)
        XCTAssertEqual(fontAll.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Системный (как у Claude)", "—", "С ЗАСЕЧКАМИ", "Georgia", "—",
                        "МОНОШИРИННЫЕ", "SF Mono"])

        // MARK: нажатия — каждый пункт трогает ровно свой слой
        click(try XCTUnwrap(color.items.first { $0.title == "Фиолетовая" }))
        click(try XCTUnwrap(color.items.first { $0.title == "Как у Claude" }))
        click(try XCTUnwrap(colorAll.items.first { $0.title == "Арктика" }))
        click(try XCTUnwrap(font.items.first { $0.title == "SF Mono" }))
        click(try XCTUnwrap(font.items.first { $0.title == "Системный (как у Claude)" }))
        click(try XCTUnwrap(fontAll.items.first { $0.title == "Georgia" }))
        click(try XCTUnwrap(appearance.items.first { $0.title == "Моя тёплая" }))
        click(try XCTUnwrap(colorAll.items.first { $0.title == "Моя тёплая" }))
        XCTAssertEqual(applied.map { $0.scope },
                       ["window", "window", "all", "window", "window", "all", "window", "all"])
        XCTAssertEqual(applied.map { $0.theme },
                       ["violet", nil, "arctic", nil, nil, nil, "user-1756900000000", "user-1756900000000"])
        XCTAssertEqual(applied.map { $0.font }, [nil, nil, nil, "sf-mono", nil, "georgia", "sf-mono", "sf-mono"])
        // Тема не трогает ни шрифт, ни размер, ни рамку — и наоборот (в команде полей просто нет).
        XCTAssertEqual(applied.map { $0.keep }, ["fsr", "fsr", "fsr", "tsr", "tsr", "tsr", "", ""])

        // «🧹 Всё как у Claude» — сброс всех четырёх слоёв одной командой.
        applied = []
        click(try XCTUnwrap(appearance.items.first { $0.title == MenuModel.resetAllTitle }))
        XCTAssertEqual(applied.map { $0.scope }, ["window"])
        XCTAssertEqual(applied.map { $0.keep }, [""])
        XCTAssertEqual(applied.map { $0.theme }, [nil])

        click(try XCTUnwrap(appearance.items.first { $0.title == MenuModel.saveMyThemeTitle }))
        let deletes = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.deleteMyThemeTitle }?.submenu)
        XCTAssertEqual(deletes.items.map { $0.title }, ["Моя тёплая"])
        click(deletes.items[0])
        XCTAssertEqual(saved, 1)
        XCTAssertEqual(deleted, ["user-1756900000000"])

        // Своих тем нет — ни секции сверху, ни «Удалить мою тему»; «Сохранить» остаётся.
        var without = menuConfig()
        without.myThemes = []
        let plain = try XCTUnwrap(MinimizeMenu.build(config: without).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        XCTAssertEqual(plain.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Цвет", "Шрифт", "Размер ответов", "Размер вопросов", "Неоновая рамка",
                        "Поля по бокам", "—", "Всем окнам", "—", "Сохранить как мою тему…",
                        "Всё как у Claude"])

        // Каталога нет — «Цвет» и «Шрифт» пропадают, остальное оформление на месте, а
        // «Раскрасить по кругу» палитры считает само и в themes.json не заглядывает (критик В10).
        let bare = MinimizeMenu.build(config: MinimizeMenu.MenuConfig())
        XCTAssertEqual(bare.items.filter { $0.hasSubmenu }.map { $0.title },
                       ["Новое окно", "Оформление", "Ещё"])
        let bareAppearance = try XCTUnwrap(bare.items.first { $0.title == MenuModel.appearanceTitle }?.submenu)
        XCTAssertEqual(bareAppearance.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Размер ответов", "Размер вопросов", "Неоновая рамка", "Поля по бокам",
                        "—", "Всем окнам", "—", "Сохранить как мою тему…", "Всё как у Claude"])
        let bareAll = try XCTUnwrap(bareAppearance.items
            .first { $0.title == MenuModel.allWindowsTitle }?.submenu)
        XCTAssertEqual(bareAll.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["ВСЕМ ОКНАМ", "Размер ответов", "Размер вопросов", "Неоновая рамка", "—",
                        "Раскрасить по кругу", "Живые цвета"])
    }

    func testHoverPreviewsThemeAndFont() throws {
        // План WF8 п. 2: наведение примеряет слой — и только в списках окна. Свои темы
        // переехали на уровень «Оформление ▸», значит делегат нужен и на нём (план п. 10).
        var previews: [String] = []
        var applied = 0
        var config = menuConfig()
        config.previewTheme = { previews.append("тема:" + ($0?.id ?? "—")) }
        config.previewFont = { previews.append("шрифт:" + ($0?.id ?? "—")) }
        config.previewMyTheme = { previews.append("тема:" + $0.id) }
        config.apply = { _, _, _, _, _ in applied += 1 }
        config.applyMyTheme = { _, _ in applied += 1 }
        let menu = MinimizeMenu.build(config: config)
        let appearance = try XCTUnwrap(menu.items.first { $0.title == MenuModel.appearanceTitle }?.submenu)
        let color = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.colorTitle }?.submenu)
        let font = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.fontTitle }?.submenu)
        let all = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.allWindowsTitle }?.submenu)
        let colorAll = try XCTUnwrap(all.items.first { $0.title == MenuModel.colorTitle }?.submenu)

        // Делегат стоит на «Оформление ▸» и на списках окна, но не на «Всем окнам ▸».
        XCTAssertTrue(appearance.delegate === PreviewMenuDelegate.shared)
        XCTAssertTrue(color.delegate === PreviewMenuDelegate.shared)
        XCTAssertTrue(font.delegate === PreviewMenuDelegate.shared)
        XCTAssertNil(all.delegate)
        XCTAssertNil(colorAll.delegate)

        highlight(color, color.items.first { $0.title == "Фиолетовая" })
        highlight(appearance, appearance.items.first { $0.title == "Моя тёплая" })
        highlight(color, color.items.first { $0.title == MenuModel.themeResetTitle })
        highlight(font, font.items.first { $0.title == "SF Mono" })
        highlight(font, font.items.first { $0.title == MenuModel.fontResetTitle })
        XCTAssertEqual(previews, ["тема:violet", "тема:user-1756900000000", "тема:—",
                                  "шрифт:sf-mono", "шрифт:—"])

        // Заголовок секции, разделитель, подменю, «Сохранить…», пустое наведение и пункты
        // внутри «Всем окнам» примерок не делают.
        previews = []
        highlight(color, color.items.first { $0.title == MenuModel.darkThemesHeader })
        highlight(color, color.items.first { $0.isSeparatorItem })
        highlight(appearance, appearance.items.first { $0.title == MenuModel.allWindowsTitle })
        highlight(appearance, appearance.items.first { $0.title == MenuModel.colorTitle })
        highlight(appearance, appearance.items.first { $0.title == MenuModel.saveMyThemeTitle })
        highlight(appearance, appearance.items.first { $0.title == MenuModel.deleteMyThemeTitle })
        highlight(appearance, nil)
        for item in colorAll.items { PreviewMenuDelegate.shared.menu(colorAll, willHighlight: item) }
        XCTAssertEqual(previews, [])
        // И ничего не закрепляют.
        XCTAssertEqual(applied, 0)
    }

    func testMenuHasSizeSubmenusWithChecksAndPreview() throws {
        // План WF12 п. 2 + план WF14: «Размер ответов ▸» и «Размер вопросов ▸» лежат прямо
        // в «🎨 Оформление ▸» (у окна) и в «🖥 Всем окнам ▸», сброс первым, галка — по своей
        // ПОЛОВИНЕ слоя (критик В3).
        var applied: [(scope: String, size: String, keep: String)] = []
        var previews: [String] = []
        var config = menuConfig()          // у окна: ответы 16, вопросы 13
        config.allSize = Size(question: 12) // всем окнам задан только размер вопросов
        config.apply = { scope, theme, font, size, frame in
            let value = size.value.map { "\($0.answer.map(String.init) ?? "—")/\($0.question.map(String.init) ?? "—")" }
            applied.append((scope: scope, size: value ?? "сброс",
                            keep: self.keptLayers(theme, font, size, frame)))
        }
        config.previewSize = { previews.append($0.map { "\($0.answer.map(String.init) ?? "—")/\($0.question.map(String.init) ?? "—")" } ?? "сброс") }
        let appearance = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        let all = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.allWindowsTitle }?.submenu)

        let answers = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.answerSizeTitle }?.submenu)
        XCTAssertEqual(answers.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Как у Claude", "—", "12", "13", "14", "15", "16", "18", "20"])
        XCTAssertNotNil(appearance.items.first { $0.title == MenuModel.answerSizeTitle }?.image) // 🔠
        // Галка — на своей половине слоя: у ответов 16, у вопросов 13.
        XCTAssertEqual(answers.items.filter { $0.state == .on }.map { $0.title }, ["16"])
        let questions = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.questionSizeTitle }?.submenu)
        XCTAssertEqual(questions.items.filter { $0.state == .on }.map { $0.title }, ["13"])
        // «Как у Claude» у «всем окнам» — когда записи нет: размер ответов всем окнам не задан,
        // размер вопросов задан.
        let answersAll = try XCTUnwrap(all.items.first { $0.title == MenuModel.answerSizeTitle }?.submenu)
        let questionsAll = try XCTUnwrap(all.items.first { $0.title == MenuModel.questionSizeTitle }?.submenu)
        XCTAssertEqual(answersAll.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Как у Claude", "—", "12", "13", "14", "15", "16", "18", "20"])
        XCTAssertEqual(answersAll.items.filter { $0.state == .on }.map { $0.title }, ["Как у Claude"])
        XCTAssertEqual(questionsAll.items.filter { $0.state == .on }.map { $0.title }, ["12"])
        // У окна обе половины заняты своей записью — сброс не отмечен.
        XCTAssertEqual(answers.items.first { $0.title == MenuModel.sizeResetTitle }?.state, .off)
        XCTAssertEqual(questions.items.first { $0.title == MenuModel.sizeResetTitle }?.state, .off)

        // Примерка — только в списке окна; «Всем окнам ▸» её не делает.
        XCTAssertTrue(answers.delegate === PreviewMenuDelegate.shared)
        XCTAssertNil(answersAll.delegate)
        highlight(answers, answers.items.first { $0.title == "18" })
        highlight(answers, answers.items.first { $0.title == MenuModel.sizeResetTitle })
        highlight(questions, questions.items.first { $0.title == "14" })
        for item in answersAll.items { PreviewMenuDelegate.shared.menu(answersAll, willHighlight: item) }
        XCTAssertEqual(previews, ["18/—", "сброс", "—/14"])

        // Нажатия: половина слоя своя у каждого подменю, остальные слои не трогаются.
        click(try XCTUnwrap(answers.items.first { $0.title == "18" }))
        click(try XCTUnwrap(questions.items.first { $0.title == "14" }))
        click(try XCTUnwrap(answers.items.first { $0.title == MenuModel.sizeResetTitle }))
        click(try XCTUnwrap(questionsAll.items.first { $0.title == "20" }))
        XCTAssertEqual(applied.map { $0.scope }, ["window", "window", "window", "all"])
        XCTAssertEqual(applied.map { $0.size }, ["18/—", "—/14", "сброс", "—/20"])
        XCTAssertEqual(applied.map { $0.keep }, ["tfr", "tfr", "tfr", "tfr"])
    }

    func testMenuFrameToggleFlipsAndPreviewsOn() throws {
        // План WF12 п. 4: галка — рамка включена, клик переключает, наведение примеряет
        // включённую. Такой же пункт — в «🖥 Всем окнам ▸», но без примерки.
        var applied: [(scope: String, frame: Bool?, reset: Bool, keep: String)] = []
        var previews = 0
        var config = menuConfig()
        config.apply = { scope, theme, font, size, frame in
            applied.append((scope: scope, frame: frame.value, reset: !frame.isKeep && frame.value == nil,
                            keep: self.keptLayers(theme, font, size, frame)))
        }
        config.previewFrame = { previews += 1 }

        // Выключена: галки нет, клик включает.
        let off = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        let toggle = try XCTUnwrap(off.items.first { $0.title == MenuModel.frameTitle })
        XCTAssertEqual(toggle.state, .off)
        XCTAssertNotNil(toggle.image) // ✨ картинкой, как у остальных пунктов с иконкой
        // Тумблер стоит между «Размер вопросов ▸» и ползунком полей (макет WF14).
        XCTAssertEqual(try XCTUnwrap(off.items.firstIndex(of: toggle)) - 1,
                       off.items.firstIndex { $0.title == MenuModel.questionSizeTitle })
        XCTAssertEqual(try XCTUnwrap(off.items.firstIndex(of: toggle)) + 1,
                       off.items.firstIndex { $0.title == MenuModel.sidePaddingTitle })
        click(toggle)
        highlight(off, toggle)

        // Включена у окна и у «всем окнам»: галка стоит, клик снимает слой (`"frame":null`).
        config.windowFrame = true
        config.allFrame = true
        let on = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        let lit = try XCTUnwrap(on.items.first { $0.title == MenuModel.frameTitle })
        XCTAssertEqual(lit.state, .on)
        click(lit)
        let allList = try XCTUnwrap(on.items.first { $0.title == MenuModel.allWindowsTitle }?.submenu)
        let allToggle = try XCTUnwrap(allList.items.first { $0.title == MenuModel.frameTitle })
        // Последний пункт перед разделителем и «Раскрасить по кругу ▸».
        XCTAssertEqual(try XCTUnwrap(allList.items.firstIndex(of: allToggle)) + 1,
                       allList.items.firstIndex { $0.isSeparatorItem })
        XCTAssertEqual(allToggle.state, .on)
        XCTAssertNil((allToggle as? BlockMenuItem)?.preview) // на всех окнах не примеряем
        click(allToggle)

        XCTAssertEqual(applied.map { $0.scope }, ["window", "window", "all"])
        XCTAssertEqual(applied.map { $0.frame }, [true, nil, nil])   // включили, потом сняли
        XCTAssertEqual(applied.map { $0.reset }, [false, true, true])
        XCTAssertEqual(applied.map { $0.keep }, ["tfs", "tfs", "tfs"])
        // Наведение примеряет включённую рамку, чем бы она сейчас ни была.
        XCTAssertEqual(previews, 1)
    }

    func testThemeStoreRemembersChoicePerWindow() {
        let defaults = MemoryDefaults()
        let store = ThemeStore(defaults: defaults)
        XCTAssertNil(store.windowThemeID(title: "Vkusnoff"))
        store.setWindowTheme("orange", title: "Vkusnoff")
        store.setWindowTheme("blue", title: "Trelvis")
        store.setAllTheme("matrix")
        XCTAssertEqual(store.windowThemeID(title: "Vkusnoff"), "orange")
        XCTAssertEqual(store.allThemeID, "matrix")
        XCTAssertEqual(defaults.values[ThemeStore.byWindowKey] as? [String: String],
                       ["Vkusnoff": "orange", "Trelvis": "blue"])
        store.setWindowTheme(nil, title: "Vkusnoff") // «Как у Claude»
        XCTAssertNil(store.windowThemeID(title: "Vkusnoff"))
        XCTAssertEqual(store.windowThemeID(title: "Trelvis"), "blue")
        store.setAllTheme(nil)
        XCTAssertNil(store.allThemeID)
        // «Тема всех окон» стирает карту окон — как runThemeCommand в inject.js.
        store.clearWindowThemes()
        XCTAssertNil(store.windowThemeID(title: "Trelvis"))
        // Окно без заголовка запоминать нечем: страница адресует его как «в фокусе».
        store.setWindowTheme("blue", title: "")
        XCTAssertNil(store.windowThemeID(title: ""))
    }

    func testThemeStoreKeepsThemeAndFontApart() {
        let defaults = MemoryDefaults()
        let store = ThemeStore(defaults: defaults)
        store.setWindowTheme("violet", title: "Vkusnoff")
        store.setWindowFont("sf-mono", title: "Vkusnoff")
        store.setAllTheme("matrix")
        store.setAllFont("georgia")
        XCTAssertEqual(store.windowThemeID(title: "Vkusnoff"), "violet")
        XCTAssertEqual(store.windowFontID(title: "Vkusnoff"), "sf-mono")
        XCTAssertEqual(defaults.values[ThemeStore.fontByWindowKey] as? [String: String],
                       ["Vkusnoff": "sf-mono"])

        // «Тема всем окнам» чистит только карту тем — шрифты окон остаются (контракт п. 5).
        store.clearWindowThemes()
        XCTAssertNil(store.windowThemeID(title: "Vkusnoff"))
        XCTAssertEqual(store.windowFontID(title: "Vkusnoff"), "sf-mono")
        store.clearWindowFonts()
        XCTAssertNil(store.windowFontID(title: "Vkusnoff"))

        // Слои «всем окнам» тоже независимы.
        store.setAllFont(nil)
        XCTAssertNil(store.allFontID)
        XCTAssertEqual(store.allThemeID, "matrix")
        // Окно без заголовка запоминать нечем.
        store.setWindowFont("sf-mono", title: "")
        XCTAssertNil(store.windowFontID(title: ""))
    }

    func testThemeStoreRemembersSizeAndFrame() {
        // План WF12 п. 1: размер и рамка — такие же независимые слои, со своими ключами.
        let defaults = MemoryDefaults()
        let store = ThemeStore(defaults: defaults)
        XCTAssertNil(store.windowSize(title: "Vkusnoff"))
        XCTAssertNil(store.allSize)
        XCTAssertFalse(store.windowFrame(title: "Vkusnoff"))
        XCTAssertFalse(store.allFrame)

        store.setWindowSize(Size(answer: 16, question: 13), title: "Vkusnoff")
        store.setWindowSize(Size(answer: 20), title: "Trelvis")
        store.setAllSize(Size(question: 12))
        store.setWindowFrame(true, title: "Vkusnoff")
        store.setAllFrame(true)
        XCTAssertEqual(store.windowSize(title: "Vkusnoff"), Size(answer: 16, question: 13))
        XCTAssertEqual(store.windowSize(title: "Trelvis"), Size(answer: 20))
        XCTAssertEqual(store.allSize, Size(question: 12))
        XCTAssertTrue(store.windowFrame(title: "Vkusnoff"))
        XCTAssertFalse(store.windowFrame(title: "Trelvis"))
        XCTAssertTrue(store.allFrame)
        // Ключи — те, что читает живое приложение; половины лежат числами.
        XCTAssertEqual((defaults.values[ThemeStore.sizeByWindowKey] as? [String: Any])?.keys.sorted(),
                       ["Trelvis", "Vkusnoff"])
        XCTAssertEqual(ThemeStore.size(defaults.values[ThemeStore.sizeAllKey])?.question, 12)
        XCTAssertEqual(defaults.values[ThemeStore.frameByWindowKey] as? [String: Bool],
                       ["Vkusnoff": true])
        XCTAssertEqual(defaults.values[ThemeStore.frameAllKey] as? Bool, true)

        // Сброс слоя: запись пропадает целиком, а не половиной.
        store.setWindowSize(nil, title: "Vkusnoff")
        XCTAssertNil(store.windowSize(title: "Vkusnoff"))
        XCTAssertEqual(store.windowSize(title: "Trelvis"), Size(answer: 20))
        store.setWindowFrame(false, title: "Vkusnoff")
        XCTAssertFalse(store.windowFrame(title: "Vkusnoff"))
        XCTAssertNil(defaults.values[ThemeStore.frameByWindowKey], "пустая карта осталась в defaults")
        store.setAllSize(nil)
        store.setAllFrame(false)
        XCTAssertNil(store.allSize)
        XCTAssertFalse(store.allFrame)

        // «Всем окнам» чистит карту только своего слоя (контракт п. 5 плана WF6).
        store.setWindowTheme("violet", title: "Trelvis")
        store.setWindowFrame(true, title: "Trelvis")
        store.clearWindowSizes()
        XCTAssertNil(store.windowSize(title: "Trelvis"))
        XCTAssertTrue(store.windowFrame(title: "Trelvis"))
        XCTAssertEqual(store.windowThemeID(title: "Trelvis"), "violet")
        store.clearWindowFrames()
        XCTAssertFalse(store.windowFrame(title: "Trelvis"))
        XCTAssertEqual(store.windowThemeID(title: "Trelvis"), "violet")

        // Окно без заголовка запоминать нечем; мусор в записи — как будто записи нет.
        store.setWindowSize(Size(answer: 16), title: "")
        store.setWindowFrame(true, title: "")
        XCTAssertNil(store.windowSize(title: ""))
        XCTAssertFalse(store.windowFrame(title: ""))
        XCTAssertNil(ThemeStore.size(nil))
        XCTAssertNil(ThemeStore.size("15"))
        XCTAssertNil(ThemeStore.size(["answer": "большой"]))
        XCTAssertEqual(ThemeStore.size(["answer": 99]), Size(answer: Size.maxPx))
    }

    // MARK: - шрифты

    func testFontCatalogKeepsInstalledCyrillicFamilies() {
        let installed = ["Georgia", "Verdana", "Papyrus", "Menlo", "Fira Code", "Weird*Mono",
                         "Иван Mono", "Monaco"]
        // Без кириллицы шрифт в меню не показываем.
        let fonts = FontCatalog.build(installed: installed,
                                      coversCyrillic: { !["Papyrus", "Fira Code"].contains($0) },
                                      displayName: { $0 == "Menlo" ? "Менло" : $0 })
        // Обычные — в порядке белого списка; моноширинные следом, тоже по списку.
        XCTAssertEqual(fonts.map { $0.family }, ["Georgia", "Verdana", "Menlo", "Monaco"])
        XCTAssertEqual(fonts.map { $0.mono }, [false, false, true, true])
        XCTAssertEqual(fonts.map { $0.id }, ["georgia", "verdana", "menlo", "monaco"])
        XCTAssertEqual(fonts[2].displayName, "Менло") // localizedNameForFamily только для меню
        // Helvetica Neue из белого списка не стоит — в каталоге её нет.
        XCTAssertFalse(fonts.contains { $0.family == "Helvetica Neue" })

        // Санитайзер контракта: только [A-Za-z0-9 -], ≤ 60 знаков.
        XCTAssertEqual(FontCatalog.sanitize(family: "Comic Sans MS"), "Comic Sans MS")
        XCTAssertNil(FontCatalog.sanitize(family: "Weird*Mono"))
        XCTAssertNil(FontCatalog.sanitize(family: "Иван Mono"))
        XCTAssertNil(FontCatalog.sanitize(family: String(repeating: "a", count: 61)))
        XCTAssertEqual(FontCatalog.id(for: "SF Mono"), "sf-mono")

        // Секция «МОНОШИРИННЫЕ» не разрастается: не больше десяти пунктов.
        let many = (1...14).map { "Test\($0) Mono" }
        let capped = FontCatalog.build(installed: many, coversCyrillic: { _ in true }, displayName: { $0 })
        XCTAssertEqual(capped.count, FontCatalog.monoLimit)
        XCTAssertTrue(capped.allSatisfy { $0.mono })
    }

    func testFontCatalogSplitsFamiliesIntoFourSections() {
        // Решение 7 плана WF9: четыре секции, каждая в порядке своего белого списка.
        XCTAssertEqual(FontCategory.allCases, [.serif, .sans, .hand, .mono])
        XCTAssertEqual(FontCategory.allCases.map { MenuModel.fontsHeader($0) },
                       ["С ЗАСЕЧКАМИ", "БЕЗ ЗАСЕЧЕК", "РУКОПИСНЫЕ И ВЕСЁЛЫЕ", "МОНОШИРИННЫЕ"])
        XCTAssertEqual(FontCatalog.serifFamilies,
                       ["Georgia", "Palatino", "Baskerville", "Didot", "Hoefler Text",
                        "Iowan Old Style", "Times New Roman"])
        XCTAssertEqual(FontCatalog.sansFamilies,
                       ["Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Optima", "Verdana",
                        "Trebuchet MS", "Arial", "Tahoma"])
        XCTAssertEqual(FontCatalog.handFamilies,
                       ["Comic Sans MS", "Chalkboard SE", "Noteworthy", "Marker Felt", "Bradley Hand",
                        "Snell Roundhand", "Papyrus", "Copperplate", "American Typewriter"])
        // Ни одно семейство не попало в две секции сразу.
        let all = FontCategory.allCases.flatMap { FontCatalog.families($0) }
        XCTAssertEqual(all.count, Set(all).count)

        let installed = ["Georgia", "Times New Roman", "Arial", "Futura", "Papyrus", "Marker Felt",
                         "Menlo", "Monaco"]
        let fonts = FontCatalog.build(installed: installed, coversCyrillic: { _ in true },
                                      displayName: { $0 })
        XCTAssertEqual(fonts.map { $0.family },
                       ["Georgia", "Times New Roman", "Futura", "Arial", "Marker Felt", "Papyrus",
                        "Menlo", "Monaco"])
        XCTAssertEqual(fonts.map { $0.category },
                       [.serif, .serif, .sans, .sans, .hand, .hand, .mono, .mono])
        // В команду по-прежнему уезжает булево mono, а не категория (контракт п. 5 WF6).
        XCTAssertEqual(fonts.map { $0.mono }, [false, false, false, false, false, false, true, true])
        XCTAssertFalse(fonts[0].commandValue.json.contains("serif"))

        // Незнакомое семейство (шрифт из my-themes.json) — по флагу mono.
        XCTAssertEqual(FontCatalog.category(family: "Papyrus", mono: false), .hand)
        XCTAssertEqual(FontCatalog.category(family: "SF Mono", mono: false), .mono)
        XCTAssertEqual(FontCatalog.category(family: "Fira Code", mono: true), .mono)
        XCTAssertEqual(FontCatalog.category(family: "Fira Code", mono: false), .sans)
    }

    // MARK: - Workflow и сводки (план WF9)

    func testWorkflowPayloadMatchesContract() throws {
        // Побайтно, контракт п. 3 плана WF9: id, action, at, scope, title, text.
        let body = CommandChannel.payload(action: "workflow",
                                          fields: ClaudeActions.workflowFields(title: "Vkusnoff",
                                                                               text: "Работаем\nдальше"),
                                          id: "1756900000123-0042",
                                          at: Date(timeIntervalSince1970: 1_756_900_000))
        XCTAssertEqual(body, "{\"id\":\"1756900000123-0042\",\"action\":\"workflow\","
            + "\"at\":\"2025-09-03T11:46:40Z\",\"scope\":\"window\",\"title\":\"Vkusnoff\","
            + "\"text\":\"Работаем\\u000aдальше\"}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["text"] as? String, "Работаем\nдальше")
        XCTAssertEqual(json["scope"] as? String, "window")
        // Без доверия Accessibility заголовка нет — страница поймёт это как «окно в фокусе».
        XCTAssertTrue(CommandChannel.payload(action: "workflow",
                                             fields: ClaudeActions.workflowFields(title: "", text: "x"),
                                             id: "1-0001", at: Date(timeIntervalSince1970: 0))
            .hasSuffix("\"scope\":\"window\",\"title\":\"\",\"text\":\"x\"}"))
    }

    // MARK: - новое окно (план WF13)

    func testNewWindowPayloadMatchesContract() throws {
        // Побайтно, контракт п. 1 плана WF13, расширенный решением 1 плана WF16:
        // id, action, at, scope, title, x, y, text, folder, name, затем слои — тема, шрифт,
        // размер, рамка. `folder` и `name` есть всегда, пустая строка = «не трогать».
        let violet = catalog()[0]
        let body = CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "Vkusnoff", x: 586, y: 303,
                                                  text: "PimpMyClaude 2",
                                                  folder: "/Users/elvis/_ElvisProjects/PimpMyClaude",
                                                  name: "PimpMyClaude 2",
                                                  theme: .set(violet), font: .keep,
                                                  size: .set(Size(answer: 16)), frame: .set(true)),
            id: "1756900000123-0042", at: Date(timeIntervalSince1970: 1_756_900_000))
        XCTAssertEqual(body, "{\"id\":\"1756900000123-0042\",\"action\":\"new-window\","
            + "\"at\":\"2025-09-03T11:46:40Z\",\"scope\":\"window\",\"title\":\"Vkusnoff\","
            + "\"x\":586,\"y\":303,\"text\":\"PimpMyClaude 2\","
            + "\"folder\":\"/Users/elvis/_ElvisProjects/PimpMyClaude\",\"name\":\"PimpMyClaude 2\","
            + "\"theme\":{\"id\":\"violet\",\"name\":\"Фиолетовая\",\"type\":\"dark\","
            + "\"palette\":{\"accent\":\"#a78bfa\",\"background\":\"#1b1626\",\"foreground\":\"#ece9f5\","
            + "\"sidebar\":\"#151021\",\"panel\":\"#241d33\",\"muted\":\"#8b81a6\"}},"
            + "\"size\":{\"answer\":16},\"frame\":true}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["scope"] as? String, "window")
        XCTAssertEqual(json["folder"] as? String, "/Users/elvis/_ElvisProjects/PimpMyClaude")
        // Имя чата приходит на страницу ГОТОВЫМ, с номером: сайдбар на совпадения она не
        // проверяет — номер считает приложение по всем сессиям (критик В4).
        XCTAssertEqual(json["name"] as? String, "PimpMyClaude 2")
        XCTAssertEqual(json["text"] as? String, "PimpMyClaude 2")
        XCTAssertNil(json["font"], "слоя, который не трогаем, в команде нет вовсе")
        // Координаты — числа, а не строки: страница проверяет их Number.isFinite.
        XCTAssertEqual(json["x"] as? Int, 586)
        XCTAssertEqual(json["y"] as? Int, 303)
        XCTAssertNil(json["x"] as? String)

        // «Здесь же» (и хоткей ⌥⌘N) — поведение WF13 до буквы: папки и имени нет, слоёв нет,
        // первое сообщение прежнее «Привет» — только приветствие, в сессии работает авто-Allow.
        XCTAssertFalse(MenuModel.newWindowText.isEmpty)
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "", x: 120, y: 120,
                                                  text: MenuModel.newWindowText),
            id: "1-0001", at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"new-window\",\"at\":\"1970-01-01T00:00:00Z\","
                       + "\"scope\":\"window\",\"title\":\"\",\"x\":120,\"y\":120,\"text\":\"Привет\","
                       + "\"folder\":\"\",\"name\":\"\"}")
        // Сброс слоя уходит как null — правило слоёв то же, что у команды `theme`.
        XCTAssertTrue(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "", x: 0, y: 0, text: "Проект",
                                                  folder: "/tmp/Проект", name: "Проект",
                                                  theme: .reset, frame: .reset),
            id: "1-0001", at: Date(timeIntervalSince1970: 0))
            .hasSuffix("\"folder\":\"/tmp/Проект\",\"name\":\"Проект\",\"theme\":null,\"frame\":null}"))

        // Чем красить новое окно (вопрос 2 макета WF16, ответ Элвиса «1»): вид проекта, а пока
        // его нет — вид окна, из которого нажали.
        let project = ProjectSettings(theme: .set(violet))
        let window = ProjectSettings(size: .set(Size(answer: 16)))
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: project, window: window).theme.value?.id,
                       "violet")
        XCTAssertTrue(ClaudeActions.newWindowLayers(project: project, window: window).size.isKeep,
                      "вид проекта берётся целиком, а не смешивается с окном")
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: nil, window: window).size.value,
                       Size(answer: 16))
        // Файл проекта есть, а слоёв в нём нет — это не «не красить», а «как у окна».
        XCTAssertEqual(ClaudeActions.newWindowLayers(project: ProjectSettings(name: "Проект"),
                                                     window: window).size.value, Size(answer: 16))
        XCTAssertTrue(ClaudeActions.newWindowLayers(project: nil, window: ProjectSettings()).isEmpty)
    }

    /// Сторож (критик В2 плана WF16 — повтор блокера Б1 из WF14): подменю не должно стоить
    /// клавиши ⌥⌘N. Carbon-хоткеи регистрируются перебором `MenuModel.entries` (id = индекс+1),
    /// поэтому `.newWindow` обязан остаться в списке И на своём месте; рисуется клавиша на
    /// пункте «Здесь же» — у родителя с подменю AppKit её не отрабатывает.
    func testNewWindowKeepsHotkeyEntry() throws {
        let index = try XCTUnwrap(MenuModel.entries.firstIndex { $0.command == .newWindow })
        XCTAssertEqual(index, 2, "индекс .newWindow съехал — вместе с ним съедет id Carbon-хоткея")
        let entry = try XCTUnwrap(MenuModel.entry(for: .newWindow))
        XCTAssertEqual(entry.registersHotkey, true, ".newWindow перестал регистрировать хоткей")
        XCTAssertEqual(entry.key?.keyCode, 0x2D)
        XCTAssertEqual(entry.key?.keyEquivalent, "n")
        XCTAssertEqual(entry.key?.modifierMask, [.command, .option])

        var config = MinimizeMenu.MenuConfig()
        config.projects = [ClaudeAXTests.project("PimpMyClaude")]
        let parent = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == "Новое окно" })
        XCTAssertNotNil(parent.submenu, "«Новое окно» — подменю (вариант А макета WF16)")
        XCTAssertEqual(parent.keyEquivalent, "", "у пункта с подменю AppKit клавишу не отработает")
        XCTAssertEqual(parent.keyEquivalentModifierMask, [])
        let here = try XCTUnwrap(parent.submenu?.items.first)
        XCTAssertEqual(here.title, MenuModel.newWindowHereTitle)
        XCTAssertEqual(here.keyEquivalent, "n")
        XCTAssertEqual(here.keyEquivalentModifierMask, [.command, .option])
    }

    /// «🪟 Новое окно ▸» — «Здесь же» первым, за ним «НЕДАВНИЕ ПРОЕКТЫ» и папки (план WF16).
    func testNewWindowSubmenuListsProjects() throws {
        var performed: [ClaudeCommand] = []
        var opened: [String] = []
        var config = MinimizeMenu.MenuConfig()
        config.perform = { performed.append($0) }
        config.newWindowInProject = { opened.append($0.folder.path) }
        config.projects = [ClaudeAXTests.project("PimpMyClaude"),
                           ClaudeAXTests.project("Dictatorik", at: 2000)]

        let submenu = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == "Новое окно" }?.submenu)
        XCTAssertEqual(submenu.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       [MenuModel.newWindowHereTitle, "—", MenuModel.recentProjectsHeader,
                        "PimpMyClaude", "Dictatorik"])
        let header = try XCTUnwrap(submenu.items.first { $0.title == MenuModel.recentProjectsHeader })
        XCTAssertFalse(header.isEnabled, "«НЕДАВНИЕ ПРОЕКТЫ» — заголовок секции, а не кнопка")
        // Имя пункта — имя папки, полный путь — подсказкой при наведении: у двух проектов
        // папки могут зваться одинаково.
        let pimp = try XCTUnwrap(submenu.items.first { $0.title == "PimpMyClaude" })
        XCTAssertNotNil(pimp.image)
        XCTAssertEqual(pimp.toolTip,
                       ProjectPaint.short(path: ClaudeAXTests.project("PimpMyClaude").folder))
        click(pimp)
        XCTAssertEqual(opened, [ClaudeAXTests.project("PimpMyClaude").folder.path])
        // «Здесь же» — прежняя команда WF13, ничего про папки не знающая.
        click(try XCTUnwrap(submenu.items.first))
        XCTAssertEqual(performed, [.newWindow])

        // Папок не знаем — подменю из одного пункта: раздел «НЕДАВНИЕ ПРОЕКТЫ» без списка
        // хуже, чем его отсутствие (условие ветвления, критик Б1).
        config.projects = []
        let bare = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == "Новое окно" }?.submenu)
        XCTAssertEqual(bare.items.map { $0.title }, [MenuModel.newWindowHereTitle])
        // Длина списка — ответ Элвиса на вопрос 3 макета.
        XCTAssertEqual(MenuModel.newWindowProjectsLimit, 8)
    }

    /// Проект из индекса чатов: папка в ~/_ElvisProjects, имя — её последний компонент.
    private static func project(_ name: String, at: Double = 3000) -> Project {
        Project(folder: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("_ElvisProjects", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true), name: name, lastFocusedAt: at)
    }

    func testPopoutWindowPayloadMatchesContract() throws {
        // Побайтно, решение Элвиса 04.09: те же поля без text.
        let body = CommandChannel.payload(
            action: ClaudeCommand.popoutWindow.rawValue,
            fields: ClaudeActions.popoutWindowFields(title: "Привет", x: 120, y: 120),
            id: "1-0001", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(body, "{\"id\":\"1-0001\",\"action\":\"popout-window\","
            + "\"at\":\"1970-01-01T00:00:00Z\",\"scope\":\"window\",\"title\":\"Привет\","
            + "\"x\":120,\"y\":120}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertNil(json["text"])
        XCTAssertEqual(json["x"] as? Int, 120)

        // Координаты — точки Quartz: угол окна под кнопкой + 40/40, обрезанные по экрану так,
        // чтобы окно 900×700 влезло целиком; окна нет — 120/120.
        let area = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(ClaudeActions.popoutOrigin(near: nil, area: area).x, 120)
        XCTAssertEqual(ClaudeActions.popoutOrigin(near: nil, area: area).y, 120)
        // На большом экране уступ ничем не обрезан.
        let wide = CGRect(x: 0, y: 25, width: 1920, height: 1175)
        let near = ClaudeActions.popoutOrigin(near: CGRect(x: 546, y: 263, width: 900, height: 700),
                                              area: wide)
        XCTAssertEqual(near.x, 586)
        XCTAssertEqual(near.y, 303)
        // Окно у правого нижнего угла — уступ уехал бы за экран.
        let corner = ClaudeActions.popoutOrigin(near: CGRect(x: 1000, y: 800, width: 400, height: 300),
                                                area: area)
        XCTAssertEqual(corner.x, 540) // 1440 − 900
        XCTAssertEqual(corner.y, 200) // 25 + 875 − 700
        // И за левый верхний край тоже не пускаем.
        let above = ClaudeActions.popoutOrigin(near: CGRect(x: -100, y: -100, width: 400, height: 300),
                                               area: area)
        XCTAssertEqual(above.x, 0)
        XCTAssertEqual(above.y, 25)
    }

    func testWorkflowKitLandsInApplicationSupport() throws {
        // Комплект из бандла (в тесте — из репозитория) ложится рядом с command.json.
        let source = ClaudeAXTests.repositoryRoot
            .appendingPathComponent("resources/workflow-kit", isDirectory: true)
        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: target) }
        XCTAssertTrue(WorkflowKit.install(from: source, to: target))
        for name in WorkflowKit.files {
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent(name)),
                           try Data(contentsOf: source.appendingPathComponent(name)), name)
        }
        // В поле ввода уходит кикофф из бандла, и он ссылается на разложенные правила.
        let kickoff = try XCTUnwrap(WorkflowKit.kickoff(directory: source))
        XCTAssertTrue(kickoff.contains(WorkflowKit.rulesName), kickoff)
        XCTAssertTrue(kickoff.contains("MyClaude/\(WorkflowKit.installedFolderName)"), kickoff)
        // Комплекта нет — ни падения, ни текста.
        XCTAssertFalse(WorkflowKit.install(from: nil, to: target))
        XCTAssertNil(WorkflowKit.kickoff(directory: URL(fileURLWithPath: "/nope/\(UUID().uuidString)")))
    }

    func testStatusPayloadMatchesContract() throws {
        // Побайтно, контракт п. 2 плана WF9: id, action, at, scope, projects[{name,text}].
        let projects = [StatusProject(name: "PimpMyClaude", text: "# ⚪PimpMyClaude\n1️⃣ Workflow ✅"),
                        StatusProject(name: "SkilZZZ", text: "# 🟣SkilZZZ")]
        let body = CommandChannel.payload(action: "status", fields: StatusFeed.fields(projects),
                                          id: "1-0001", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(body, "{\"id\":\"1-0001\",\"action\":\"status\","
            + "\"at\":\"1970-01-01T00:00:00Z\",\"scope\":\"all\",\"projects\":["
            + "{\"name\":\"PimpMyClaude\",\"text\":\"# ⚪PimpMyClaude\\u000a1️⃣ Workflow ✅\"},"
            + "{\"name\":\"SkilZZZ\",\"text\":\"# 🟣SkilZZZ\"}]}")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["scope"] as? String, "all")
        let list = try XCTUnwrap(json["projects"] as? [[String: String]])
        XCTAssertEqual(list.map { $0["name"] }, ["PimpMyClaude", "SkilZZZ"])
        XCTAssertEqual(list.first?["text"], "# ⚪PimpMyClaude\n1️⃣ Workflow ✅")
        // Проектов нет — пустой список, а не сломанный JSON (такую команду StatusFeed не шлёт).
        XCTAssertEqual(CommandValue.array([]).json, "[]")
        // Содержимое не менялось — хэш тот же; поменялось хоть в одном проекте — другой.
        XCTAssertEqual(StatusFeed.digest(projects), StatusFeed.digest(projects))
        XCTAssertNotEqual(StatusFeed.digest(projects),
                          StatusFeed.digest([projects[0], StatusProject(name: "SkilZZZ", text: "!")]))

        // Общий потолок 32 КБ (критик п. 6): проекты кладутся по порядку, хвост отбрасывается.
        let heavy = { (name: String) in
            StatusProject(name: name, text: String(repeating: "строка сводки\n", count: 500))
        }
        let many = (1...9).map { heavy("Проект \($0)") }
        let capped = StatusFeed.cap(many)
        XCTAssertLessThanOrEqual(StatusFeed.payloadSize(capped), StatusFeed.totalLimit)
        XCTAssertGreaterThan(capped.count, 0)
        XCTAssertLessThan(capped.count, many.count)
        XCTAssertEqual(capped.map { $0.name }, many.prefix(capped.count).map { $0.name })
        // Влезают все — не трогаем ни байта.
        XCTAssertEqual(StatusFeed.cap(projects), projects)
        // Не влез даже первый — режем ему текст, но проект остаётся.
        let alone = StatusFeed.cap([heavy("Один")], limit: 500)
        XCTAssertEqual(alone.count, 1)
        XCTAssertLessThanOrEqual(StatusFeed.payloadSize(alone), 500)
        XCTAssertTrue(heavy("Один").text.hasPrefix(alone[0].text))
    }

    func testStatusScanReadsProjectSummaries() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func put(_ project: String, _ folder: String, _ text: String) throws {
            let dir = root.appendingPathComponent(project).appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: dir.appendingPathComponent(StatusFeed.statusFileName))
        }
        try put("PimpMyClaude", "docs", "# ⚪PimpMyClaude")
        try put("PimpMyClaude", "work", "не эта")        // docs идёт первым
        try put("Audited", "audit", "# аудит")
        try put("Empty", "docs", "   \n")                 // пустая сводка не едет
        try FileManager.default.createDirectory(at: root.appendingPathComponent("NoStatus/src"),
                                                withIntermediateDirectories: true)

        let projects = StatusFeed.scan(root: root)
        XCTAssertEqual(projects.map { $0.name }, ["Audited", "PimpMyClaude"]) // по алфавиту
        XCTAssertEqual(projects.last?.text, "# ⚪PimpMyClaude")
        // Папки проектов нет — ничего не читаем.
        XCTAssertTrue(StatusFeed.scan(root: root.appendingPathComponent("нет")).isEmpty)

        // projectsRoot из claude.json; ключа/файла нет — ~/_ElvisProjects.
        let config = root.appendingPathComponent("claude.json")
        try Data("{\"minWindowWidth\":360,\"projectsRoot\":\"~/Projects\"}".utf8).write(to: config)
        XCTAssertEqual(StatusFeed.projectsRoot(configURL: config).path,
                       NSString(string: "~/Projects").expandingTildeInPath)
        try Data("{\"minWindowWidth\":360}".utf8).write(to: config)
        XCTAssertEqual(StatusFeed.projectsRoot(configURL: config).path,
                       NSString(string: StatusFeed.defaultProjectsRoot).expandingTildeInPath)
        XCTAssertEqual(StatusFeed.projectsRoot(configURL: root.appendingPathComponent("нет.json")).path,
                       NSString(string: StatusFeed.defaultProjectsRoot).expandingTildeInPath)
    }

    func testStatusSliceCutsOnWorkflowBlocks() {
        let head = "# ⚪PimpMyClaude\nобновлено 01:55\n"
        let block = { (index: Int) in "\(index)️⃣ Workflow ✅ готово\n" + String(repeating: "- строка сводки\n", count: 40) }
        let text = head + (1...9).map(block).joined()
        XCTAssertGreaterThan(text.utf8.count, StatusFeed.limit)

        let slice = StatusFeed.slice(text)
        XCTAssertLessThanOrEqual(slice.utf8.count, StatusFeed.limit)
        XCTAssertTrue(slice.hasPrefix(head), slice)
        // Режем по границе блока: последний блок в срезе — целый, следующего нет вовсе.
        XCTAssertTrue(slice.hasSuffix("- строка сводки"), String(slice.suffix(40)))
        let kept = (1...9).filter { slice.contains("\($0)️⃣ Workflow") }
        XCTAssertEqual(kept, Array(1...kept.count))
        XCTAssertGreaterThan(kept.count, 1)

        // Влезает целиком — не трогаем ни байта.
        XCTAssertEqual(StatusFeed.slice(head + block(1)), head + block(1))
        // Ни один блок не влез — режем по знакам, UTF-8 не рвём.
        let single = StatusFeed.slice(head + block(1), limit: 20)
        XCTAssertLessThanOrEqual(single.utf8.count, 20)
        XCTAssertTrue(head.hasPrefix(single), single)
        XCTAssertTrue(StatusFeed.isWorkflowHeading("1️⃣ Workflow ✅ готово"))
        XCTAssertTrue(StatusFeed.isWorkflowHeading("🔟 Workflow"))
        XCTAssertFalse(StatusFeed.isWorkflowHeading("1. Workflow"))
        XCTAssertFalse(StatusFeed.isWorkflowHeading("- строка сводки"))
        XCTAssertFalse(StatusFeed.isWorkflowHeading(""))
    }

    // MARK: - мои темы

    func testMyThemesSaveLoadAndLimit() throws {
        XCTAssertTrue(MyThemesStore.parse(nil).isEmpty)
        XCTAssertTrue(MyThemesStore.parse(Data("не json".utf8)).isEmpty)
        XCTAssertTrue(MyThemesStore.parse(Data("{\"version\":1}".utf8)).isEmpty)
        // Запись без палитры пропускается, остальные читаются.
        XCTAssertEqual(MyThemesStore.parse(Data("""
        {"version":1,"themes":[{"id":"user-1","name":"Без палитры"},
        {"id":"user-2","name":"Годная","type":"light","palette":{"accent":"#fff"}}]}
        """.utf8)).map { $0.id }, ["user-2"])
        // Размер и рамка читаются из файла (его правит и сам Элвис); мусор в размере —
        // как будто половины нет, кегли зажаты в границы контракта.
        let hand = MyThemesStore.parse(Data("""
        {"version":1,"themes":[{"id":"user-3","name":"Крупная","palette":{"accent":"#fff"},
        "size":{"answer":40,"question":"много"},"frame":true}]}
        """.utf8))
        XCTAssertEqual(hand.first?.size, Size(answer: Size.maxPx))
        XCTAssertEqual(hand.first?.frame, true)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(MyThemesStore.fileName)
        let store = MyThemesStore(url: url)
        XCTAssertTrue(store.load().isEmpty) // файла ещё нет — не падаем

        let saved = try XCTUnwrap(store.add(name: "  Моя тёплая  ", theme: catalog()[0],
                                            font: ClaudeAXTests.monoFont,
                                            size: Size(answer: 16, question: 13), frame: true,
                                            now: 1_756_900_000))
        XCTAssertEqual(saved.map { $0.id }, ["user-1756900000000"])
        let loaded = store.load()
        XCTAssertEqual(loaded.map { $0.name }, ["Моя тёплая"]) // пробелы срезаны
        XCTAssertEqual(loaded[0].palette["background"], "#1b1626") // палитра скопирована
        XCTAssertEqual(loaded[0].font?.family, "SF Mono")
        XCTAssertEqual(loaded[0].font?.mono, true)
        // Размер и рамка запоминаются той же парой (план WF12 п. 1).
        XCTAssertEqual(loaded[0].size, Size(answer: 16, question: 13))
        XCTAssertTrue(loaded[0].frame)
        XCTAssertEqual(loaded[0].theme.id, "user-1756900000000") // команда уходит со своим id
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.hasPrefix("{\"version\":1,\"themes\":[{\"id\":\"user-1756900000000\","), raw)
        XCTAssertTrue(raw.contains("\"font\":{\"id\":\"sf-mono\",\"family\":\"SF Mono\",\"mono\":true},"
            + "\"size\":{\"answer\":16,\"question\":13},\"frame\":true"), raw)

        // Тема без шрифта, размера и рамки — обрезка имени по 80 знакам.
        let long = try XCTUnwrap(store.add(name: String(repeating: "я", count: 100),
                                           theme: catalog()[1], font: nil, now: 1_756_900_001))
        XCTAssertEqual(long.count, 2)
        XCTAssertEqual(long.last?.name.count, MyThemesStore.nameLimit)
        XCTAssertNil(store.load().last?.font)
        XCTAssertNil(store.load().last?.size)
        XCTAssertFalse(try XCTUnwrap(store.load().last).frame)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8)
            .contains("\"font\":null,\"size\":null,\"frame\":false"))
        // Пустое имя не сохраняется.
        XCTAssertNil(store.add(name: "   ", theme: catalog()[0], font: nil))

        // Имя занято (другой регистр и пробелы) — слои перезаписываются, id и место в списке
        // сохраняются, длина списка не растёт (задача #5364, «изменить свою тему»).
        let again = try XCTUnwrap(store.add(name: "  моя ТЁПЛАЯ  ", theme: catalog()[1], font: nil,
                                            size: Size(answer: 20), frame: false,
                                            now: 1_756_900_009))
        XCTAssertEqual(again.count, 2, "перезапись не должна плодить дубли")
        XCTAssertEqual(again.map { $0.id }, ["user-1756900000000", "user-1756900001000"])
        XCTAssertEqual(again[0].name, "моя ТЁПЛАЯ")     // имя пишется тем, что ввели
        XCTAssertEqual(again[0].palette["background"], "#f7f9fc") // слои — новые
        XCTAssertNil(again[0].font)
        XCTAssertEqual(again[0].size, Size(answer: 20))
        XCTAssertFalse(again[0].frame)
        XCTAssertEqual(store.load().map { $0.id }, again.map { $0.id })
        // Само совпадение имён — чистая функция: её же спрашивает меню перед вопросом
        // «Перезаписать?» (критик В2).
        XCTAssertEqual(MyThemesStore.matching(name: " МОЯ тёплая ", in: again)?.id, "user-1756900000000")
        XCTAssertNil(MyThemesStore.matching(name: "Такой нет", in: again))
        XCTAssertNil(MyThemesStore.matching(name: "   ", in: again))
        // Возвращаем список к прежнему виду, чтобы дальше проверять удаление и лимит.
        _ = store.add(name: "Моя тёплая", theme: catalog()[0], font: ClaudeAXTests.monoFont,
                      size: Size(answer: 16, question: 13), frame: true, now: 1_756_900_010)

        let after = try XCTUnwrap(store.delete(id: "user-1756900000000"))
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(store.load().map { $0.id }, after.map { $0.id })

        // Лимит: двадцать первая тема вытесняет самую старую.
        var list: [MyTheme] = []
        for index in 0..<25 {
            list = MyThemesStore.appending(MyTheme(id: "user-\(index)", name: "Тема \(index)",
                                                   type: "dark", palette: ["accent": "#fff"], font: nil),
                                           to: list)
        }
        XCTAssertEqual(list.count, MyThemesStore.limit)
        XCTAssertEqual(list.first?.id, "user-5")
        XCTAssertEqual(list.last?.id, "user-24")
    }

    // MARK: - автопокраска (план WF10)

    /// Двенадцать hue по кругу — как раз то, что раскладывает «Радуга» на дюжине окон.
    private static let wheelHues: [Double] = (0..<12).map { Double($0) * 30 }

    func testAutoPaintPaletteIsValidAndReadable() throws {
        for light in [false, true] {
            for hue in ClaudeAXTests.wheelHues {
                // Крайние силы — «Пастель»/«Неон» и края «Монохрома».
                for strength in [0.0, 0.35, 0.5, 1.0] {
                    let where_ = "hue \(Int(hue))° \(light ? "светлая" : "тёмная") сила \(strength)"
                    let palette = AutoPaint.palette(hue: hue, light: light, strength: strength)
                    XCTAssertEqual(Set(palette.keys), Set(Theme.paletteOrder), where_)
                    for key in Theme.paletteOrder {
                        let hex = try XCTUnwrap(palette[key], where_)
                        XCTAssertNotNil(hex.range(of: "^#[0-9a-f]{6}$", options: .regularExpression),
                                        "\(where_): \(key) = \(hex)")
                    }
                    let background = try XCTUnwrap(palette["background"])
                    // Текст на фоне — AAA (≥ 7), приглушённый текст и акцент — AA (≥ 4,5).
                    let text = try XCTUnwrap(AutoPaint.contrast(hex: try XCTUnwrap(palette["foreground"]),
                                                                hex: background))
                    XCTAssertGreaterThanOrEqual(text, AutoPaint.textContrast, "\(where_): текст на фоне")
                    for key in ["muted", "accent"] {
                        let value = try XCTUnwrap(AutoPaint.contrast(hex: try XCTUnwrap(palette[key]),
                                                                     hex: background))
                        XCTAssertGreaterThanOrEqual(value, AutoPaint.accentContrast, "\(where_): \(key)")
                    }
                    // «Трендовые, не кричащие»: насыщенность фона ≤ 60 % (фикс-батч п. 2 — на
                    // 45 % выходило серо). Считаем её обратно из hex — по нему цвет и увидят.
                    let saturation = try XCTUnwrap(AutoPaint.saturation(hex: background))
                    XCTAssertLessThanOrEqual(saturation, AutoPaint.maxBackgroundSaturation, where_)
                    // Боковина темнее фона, панель светлее (у светлой темы — наоборот).
                    XCTAssertNotEqual(palette["sidebar"], background, where_)
                    XCTAssertNotEqual(palette["panel"], background, where_)
                }
            }
        }
    }

    func testAutoPaintAccentStaysInContrastBand() throws {
        // Акцент кладём в полосу контраста, а не в пол (фикс-батч п. 1): иначе жёлтый с зелёным
        // на тёмном фоне уходят за 10 и кричат, а синий с фиолетовым висят на 4,5 и тонут.
        // Проверка — весь круг с шагом 10°, в обоих режимах.
        for light in [false, true] {
            let mode = light ? "светлая" : "тёмная"
            let cap = AutoPaint.accentContrastCap(light: light)
            var luminances: [Double] = []
            for step in 0..<36 {
                let hue = Double(step) * 10
                let palette = AutoPaint.palette(hue: hue, light: light)
                let accent = try XCTUnwrap(palette["accent"])
                let value = try XCTUnwrap(AutoPaint.contrast(hex: accent,
                                                             hex: try XCTUnwrap(palette["background"])))
                XCTAssertGreaterThanOrEqual(value, AutoPaint.accentContrast, "\(mode) hue \(Int(hue))°")
                XCTAssertLessThanOrEqual(value, cap, "\(mode) hue \(Int(hue))°")
                let channels = try XCTUnwrap(AutoPaint.channels(hex: accent))
                luminances.append(AutoPaint.luminance(r: channels.r, g: channels.g, b: channels.b))
            }
            // Полоса держит и яркость: по кругу акцент разъезжается не больше чем вдвое —
            // иначе одно окно из четырёх било бы в глаза, а другое пряталось.
            let spread = try XCTUnwrap(luminances.max()) / max(try XCTUnwrap(luminances.min()), 0.0001)
            XCTAssertLessThanOrEqual(spread, 2, "\(mode): яркость акцента разъехалась в \(spread) раза")
        }
    }

    func testAutoPaintSpreadsHuesAroundTheWheelLeftToRight() throws {
        // Четыре окна в ряд, перемешанные: красим слева направо (тот же порядок, что «Расставить»).
        let frames = [
            CGRect(x: 900, y: 30, width: 440, height: 900),   // 0 — третье слева
            CGRect(x: 20, y: 0, width: 440, height: 900),     // 1 — первое
            CGRect(x: 1360, y: 10, width: 440, height: 900),  // 2 — четвёртое
            CGRect(x: 460, y: 20, width: 440, height: 900),   // 3 — второе
        ]
        XCTAssertEqual(ArrangeLayout.order(of: frames), [1, 3, 0, 2])

        let rainbow = try XCTUnwrap(AutoPaint.preset(id: "rainbow"))
        let themes = AutoPaint.themes(preset: rainbow, scheme: rainbow.scheme,
                                      count: frames.count, start: 100, light: false)
        XCTAssertEqual(themes.map { $0.id },
                       ["auto-rainbow-100", "auto-rainbow-190", "auto-rainbow-280", "auto-rainbow-10"])
        XCTAssertEqual(themes.map { $0.name },
                       ["Радуга · 100°", "Радуга · 190°", "Радуга · 280°", "Радуга · 10°"])
        // Четыре окна — четыре разных цвета, разведённых ровно на четверть круга.
        XCTAssertEqual(Set(themes.map { $0.palette["background"] }).count, 4)
        let hues = AutoPaint.hues(scheme: .wheel, count: 4, start: 100)
        for index in 1..<hues.count {
            XCTAssertEqual(AutoPaint.normalized(hues[index] - hues[index - 1]), 90, accuracy: 0.001)
        }
        // Одно окно — середина диапазона (план п. 4); сектор «Заката» обходит 0°.
        XCTAssertEqual(AutoPaint.hues(scheme: .sector(180, 260), count: 1, start: 0), [220])
        XCTAssertEqual(AutoPaint.hues(scheme: .sector(350, 420), count: 2, start: 0), [7.5, 42.5])
        // «Ещё раз» крутит старт внутри сектора, наружу не выпуская.
        for hue in AutoPaint.hues(scheme: .sector(180, 260), count: 3, start: AutoPaint.againStep) {
            XCTAssertTrue((180...260).contains(hue), "\(hue)° вышел из «Океана»")
        }
        // «Монохром» — один hue на все окна, но фон у каждого своей светлоты.
        let mono = try XCTUnwrap(AutoPaint.preset(id: "mono"))
        let shades = AutoPaint.themes(preset: mono, scheme: mono.scheme, count: 3, start: 210, light: false)
        XCTAssertEqual(shades.map { $0.id }, Array(repeating: "auto-mono-210", count: 3))
        XCTAssertEqual(Set(shades.map { $0.palette["background"] }).count, 3)
        XCTAssertEqual(AutoPaint.hues(scheme: .wheel, count: 0, start: 0), [])
    }

    func testAutoPaintRandomSchemesGiveOneHuePerWindow() throws {
        // «Случайно» берёт схему из четырёх (аналоговая, триада, сплит, тетрада) — и на N окон
        // обязана дать N разных цветов, даже когда окон больше, чем углов в схеме.
        for (index, scheme) in AutoPaint.randomSchemes.enumerated() {
            for count in [1, 3, 5] {
                let hues = AutoPaint.hues(scheme: scheme, count: count, start: 200)
                XCTAssertEqual(hues.count, count, "схема \(index)")
                XCTAssertEqual(Set(hues.map { Int($0.rounded()) }).count, count,
                               "схема \(index) повторила цвет на \(count) окнах")
                for hue in hues { XCTAssertTrue((0..<360).contains(hue), "\(hue)° вне круга") }
            }
        }
        // Схема «Случайно» выбирается на каждый запуск, у остальных наборов она своя всегда.
        let ocean = try XCTUnwrap(AutoPaint.preset(id: "ocean"))
        XCTAssertEqual(AutoPaint.schemeIndex(for: AutoPaint.random, pick: { 2 }), 2)
        XCTAssertNil(AutoPaint.schemeIndex(for: ocean, pick: { 2 }))
        XCTAssertEqual(AutoPaint.scheme(for: AutoPaint.random, index: 2), AutoPaint.randomSchemes[2])
        XCTAssertEqual(AutoPaint.scheme(for: ocean, index: 2), .sector(180, 260))
        // «🔁 Ещё раз» повторяет ту же схему (фикс-батч п. 5): индекс из памяти, а не новый.
        XCTAssertEqual(AutoPaint.schemeIndex(for: AutoPaint.random, repeating: 1, pick: { 3 }), 1)
        XCTAssertEqual(AutoPaint.schemeIndex(for: AutoPaint.random, repeating: 99, pick: { 3 }),
                       AutoPaint.randomSchemes.count - 1)
        // «Случайно» решает тёмная/светлая по окнам, поэтому своего режима у него нет.
        XCTAssertNil(AutoPaint.random.light)
        XCTAssertEqual(AutoPaint.presets.map { $0.light }, [false, true, false, false, false, false, false, false])
    }

    func testAutoPaintThemePayloadMatchesContract() throws {
        // Тема уезжает обычной командой на окно (план п. 4): scope window, адресация заголовком,
        // слой шрифта не трогаем.
        let rainbow = try XCTUnwrap(AutoPaint.preset(id: "rainbow"))
        let theme = AutoPaint.theme(preset: rainbow, hue: 137, light: false)
        let body = themeBody(theme: .set(theme), font: .keep, id: "1-0001", at: 0)
        XCTAssertTrue(body.hasPrefix("{\"id\":\"1-0001\",\"action\":\"theme\",\"at\":\"1970-01-01T00:00:00Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\",\"theme\":{\"id\":\"auto-rainbow-137\","
            + "\"name\":\"Радуга · 137°\",\"type\":\"dark\",\"palette\":{\"accent\":\"#"), body)
        XCTAssertFalse(body.contains("\"font\""))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let payload = try XCTUnwrap(json["theme"] as? [String: Any])
        XCTAssertEqual(payload["type"] as? String, "dark")
        XCTAssertEqual(Set(try XCTUnwrap(payload["palette"] as? [String: String]).keys),
                       Set(Theme.paletteOrder))
        // Светлый набор помечает тему светлой — по типу страница ставит color-scheme.
        XCTAssertEqual(AutoPaint.theme(preset: try XCTUnwrap(AutoPaint.preset(id: "pastel")),
                                       hue: 359.7, light: true).id, "auto-pastel-0")
    }

    func testAutoPaintRemembersPresetStartAndScheme() throws {
        // План п. 5: последний запуск (набор, старт, схема, режим) живёт в UserDefaults,
        // «Ещё раз» = старт +37°.
        let defaults = MemoryDefaults()
        let store = AutoPaintStore(defaults: defaults)
        XCTAssertNil(store.last?.preset)
        store.remember(preset: "ocean", start: 350)
        XCTAssertEqual(store.last?.preset, "ocean")
        XCTAssertEqual(try XCTUnwrap(store.last?.start), 350, accuracy: 0.001)
        XCTAssertNil(try XCTUnwrap(store.last).scheme) // у набора со своей схемой индекса нет
        XCTAssertNil(try XCTUnwrap(store.last).light)
        store.remember(preset: "ocean", start: 350 + AutoPaint.againStep)
        XCTAssertEqual(try XCTUnwrap(store.last?.start), 27, accuracy: 0.001) // круг замкнулся
        // «Случайно» кладёт индекс схемы и режим — «Ещё раз» повторит ту же гармонию и не
        // перевернёт светлые окна в тёмные (фикс-батч п. 5): галки-то с них уже сняты.
        store.remember(preset: "random", start: 10, scheme: 3, light: true)
        XCTAssertEqual(try XCTUnwrap(store.last).scheme, 3)
        XCTAssertEqual(try XCTUnwrap(store.last).light, true)
        XCTAssertEqual(AutoPaint.scheme(for: AutoPaint.random,
                                        index: AutoPaint.schemeIndex(for: AutoPaint.random,
                                                                     repeating: store.last?.scheme ?? nil)),
                       AutoPaint.randomSchemes[3])
        XCTAssertEqual(AutoPaint.preset(id: "ocean")?.title, "Океан")
        XCTAssertNil(AutoPaint.preset(id: "нет такого"))
        // Ключ — тот, что читает живое приложение.
        XCTAssertNotNil(defaults.values[AutoPaintStore.key])
    }

    func testAutoPaintHUDCountsWindowsAndUnnamedChats() {
        // Строка перед покраской (фикс-батч п. 4): окон на экране столько же, сколько цветов, —
        // говорим просто, сколько красим.
        XCTAssertEqual(MenuModel.autoPaintStart(windows: 1), "Крашу 1 окно…")
        XCTAssertEqual(MenuModel.autoPaintStart(windows: 4), "Крашу 4 окна…")
        XCTAssertEqual(MenuModel.autoPaintStart(windows: 5), "Крашу 5 окон…")
        XCTAssertEqual(MenuModel.autoPaintStart(windows: 11), "Крашу 11 окон…")
        XCTAssertEqual(MenuModel.autoPaintStart(windows: 22), "Крашу 22 окна…")
        // Окна с одинаковым заголовком делят один ключ темы — им достанется один цвет, и это
        // не сбой; счёт идёт от того, скольким окнам своего цвета не досталось (хвост WF10).
        XCTAssertEqual(MenuModel.autoPaintStart(windows: 4, shared: 2),
                       "Крашу 4 окна; 2 без имени чата — одним цветом")
        // Окно без AX-заголовка не красим вовсе — про это говорим отдельно.
        XCTAssertEqual(MenuModel.autoPaintStart(windows: 4, skipped: 1),
                       "Крашу 4 окна; 1 без заголовка — пропущено")
        XCTAssertEqual(MenuModel.autoPaintStart(windows: 6, shared: 1, skipped: 2),
                       "Крашу 6 окон; 1 без имени чата — одним цветом; 2 без заголовка — пропущены")
        XCTAssertEqual(MenuModel.skippedWord(1), "пропущено")
        XCTAssertEqual(MenuModel.skippedWord(11), "пропущены")
        XCTAssertEqual(MenuModel.skippedWord(21), "пропущено")
    }

    func testAutoPaintMenuHasPresetsRandomAgainAndReset() throws {
        var painted: [String] = []
        var again = 0
        var reset = 0
        var config = menuConfig()
        config.autoPaint = { painted.append($0.id) }
        config.autoPaintAgain = { again += 1 }
        config.autoPaintReset = { reset += 1 }
        // Путь новый (решение Элвиса 04.09): «🎨 Оформление ▸ → 🖥 Всем окнам ▸ →
        // 🌈 Раскрасить по кругу ▸». С верхнего уровня и из меню-бара пункт снят.
        let menu = MinimizeMenu.build(config: config)
        XCTAssertNil(menu.items.first { $0.title == MenuModel.autoPaintTitle })
        let appearance = try XCTUnwrap(menu.items.first { $0.title == MenuModel.appearanceTitle }?.submenu)
        XCTAssertNil(appearance.items.first { $0.title == MenuModel.autoPaintTitle })
        let all = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.allWindowsTitle }?.submenu)
        let submenu = try XCTUnwrap(all.items.first { $0.title == MenuModel.autoPaintTitle }?.submenu)
        XCTAssertEqual(MenuModel.autoPaintTitle, "Раскрасить по кругу")

        // Наборы, разделитель, «Случайно», «Ещё раз», сброс всем окнам (план п. 1).
        XCTAssertEqual(submenu.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Радуга", "Пастель", "Закат", "Океан", "Лес", "Ягоды", "Неон", "Монохром",
                        "—", "Случайно", "Ещё раз", "Как у Claude (все окна)"])
        XCTAssertTrue(submenu.items.allSatisfy { !$0.hasSubmenu })
        // Предпросмотра у автопокраски нет: набор красит все окна разом.
        XCTAssertNil(submenu.delegate)
        XCTAssertTrue(submenu.items.compactMap { ($0 as? BlockMenuItem)?.preview }.isEmpty)

        for item in submenu.items where !item.isSeparatorItem { click(item) }
        XCTAssertEqual(painted, AutoPaint.presets.map { $0.id } + ["random"])
        XCTAssertEqual(again, 1)
        XCTAssertEqual(reset, 1)
    }

    // MARK: - галки «Как у Claude» (задача #5363, критик В1 и В3)

    /// Состояния пунктов сброса во всех четырёх списках ОКНА.
    private func windowResets(_ config: MinimizeMenu.MenuConfig) throws -> [String] {
        let appearance = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        func state(_ submenu: String, _ item: String) throws -> Bool {
            let list = try XCTUnwrap(appearance.items.first { $0.title == submenu }?.submenu)
            return try XCTUnwrap(list.items.first { $0.title == item }).state == .on
        }
        var on: [String] = []
        if try state(MenuModel.colorTitle, MenuModel.themeResetTitle) { on.append("цвет") }
        if try state(MenuModel.fontTitle, MenuModel.fontResetTitle) { on.append("шрифт") }
        if try state(MenuModel.answerSizeTitle, MenuModel.sizeResetTitle) { on.append("ответы") }
        if try state(MenuModel.questionSizeTitle, MenuModel.sizeResetTitle) { on.append("вопросы") }
        return on
    }

    func testClaudeCheckStandsOnlyWhenMemoryIsTrusted() throws {
        // Пусто во всех слоях — галка «Как у Claude» стоит у окна во всех четырёх списках.
        // Это и есть #5363: раньше у окна её не ставили никогда.
        var empty = menuConfig()
        empty.windowThemeID = nil
        empty.windowFontID = nil
        empty.windowSize = nil
        XCTAssertEqual(try windowResets(empty), ["цвет", "шрифт", "ответы", "вопросы"])

        // Своя запись есть — галка у сброса не стоит (она на выбранном пункте).
        XCTAssertEqual(try windowResets(menuConfig()), [])

        // Есть запись «всем окнам»: окно её наследует, поэтому у окна не отмечено ничего,
        // а галка стоит внутри «🖥 Всем окнам ▸» только там, где записи нет.
        var inherited = empty
        inherited.allThemeID = "violet"
        inherited.allFontID = "georgia"
        inherited.allSize = Size(answer: 18)
        XCTAssertEqual(try windowResets(inherited), ["вопросы"])
        let all = try XCTUnwrap(try XCTUnwrap(MinimizeMenu.build(config: inherited).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu).items
            .first { $0.title == MenuModel.allWindowsTitle }?.submenu)
        let colorAll = try XCTUnwrap(all.items.first { $0.title == MenuModel.colorTitle }?.submenu)
        XCTAssertEqual(colorAll.items.first { $0.title == MenuModel.themeResetTitle }?.state, .off)
        let questionsAll = try XCTUnwrap(all.items.first { $0.title == MenuModel.questionSizeTitle }?.submenu)
        XCTAssertEqual(questionsAll.items.first { $0.title == MenuModel.sizeResetTitle }?.state, .on)

        // Половина слоя своя (критик В3): у окна задан только размер ответов — в «Размер
        // вопросов ▸» галка обязана встать, эта половина пуста.
        var half = empty
        half.windowSize = Size(answer: 16)
        XCTAssertEqual(try windowResets(half), ["цвет", "шрифт", "вопросы"])

        // Окно без AX-заголовка: память по заголовку пуста ВСЕГДА — галку не ставим (В1).
        var untitled = empty
        untitled.windowTitled = false
        XCTAssertEqual(try windowResets(untitled), [])

        // Окно после автопокраски: оно цветное, а ThemeStore пуст — галка соврала бы (В1).
        var painted = empty
        painted.windowAutoPainted = true
        XCTAssertEqual(try windowResets(painted), [])
    }

    // MARK: - живой блок claude.css и merge claude.json (план WF14, решение 1)

    /// Блок контракта побайтно — тем же текстом он лежит в репозиторном claude-patch/claude.css.
    private static let expectedBlock = """
    /* PimpMyClaude:auto */
    #myclaude-window-frame{border-radius:15px !important}
    .epitaxy-titlebar span[class*="w-[var(--chat-gutter-start"]{width:32px !important}
    .tiles-shell{min-width:0 !important}
    [class*="--chat-column-gutter-start"]{--chat-column-gutter-start:5px !important;--chat-column-gutter-end:5px !important}
    [class*="ps-[var(--chat-gutter"],[class*="pe-[var(--chat-gutter"],.epitaxy-transcript-width,.epitaxy-composer-width{padding-inline-start:5px !important;padding-inline-end:5px !important;padding-left:5px !important;padding-right:5px !important}
    [class*="ps-[var(--chat"],[class*="pe-[var(--chat"]{padding-inline-start:5px !important;padding-inline-end:5px !important}
    /* /PimpMyClaude:auto */
    """

    func testLiveStyleBlockMatchesContract() throws {
        XCTAssertEqual(LiveStyle.block(padding: 5, radius: 15), ClaudeAXTests.expectedBlock)
        // Радиус — по версии macOS: у Tahoe (26+) угол ≈ 17 pt, у 13–15 — 10.
        XCTAssertEqual(LiveStyle.frameRadius(majorVersion: 26), 15)
        XCTAssertEqual(LiveStyle.frameRadius(majorVersion: 15), 10)
        // Необязательный ключ frameRadius в claude.json перебивает порог; мусор — нет.
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":12}", majorVersion: 26), 12)
        XCTAssertEqual(LiveStyle.frameRadius(config: "{\"frameRadius\":999}", majorVersion: 26), 15)
        XCTAssertEqual(LiveStyle.frameRadius(config: "не json", majorVersion: 15), 10)
        XCTAssertEqual(LiveStyle.frameRadius(config: nil, majorVersion: 26), 15)
        // Ползунок зажат в 0…24, умолчание — 5 (решение Элвиса, вопрос 4 макета).
        XCTAssertEqual(LiveStyle.clamp(-5), 0)
        XCTAssertEqual(LiveStyle.clamp(40), 24)
        XCTAssertEqual(LiveStyle.clamp(5), 5)
        XCTAssertEqual(LiveStyle.defaultSidePadding, 5)
        // Тот же блок лежит в репозиторном claude-patch/claude.css: свежая установка правильна
        // ещё до первого запуска приложения (критик В5).
        let repo = try String(contentsOf: ClaudeAXTests.repositoryRoot
            .appendingPathComponent("claude-patch").appendingPathComponent("claude.css"),
                              encoding: .utf8)
        XCTAssertTrue(repo.contains(ClaudeAXTests.expectedBlock), repo)
        XCTAssertTrue(repo.hasSuffix(LiveStyle.markerEnd + "\n"), repo)
        // Умолчание полей — то же и в репозиторном claude.json (мелочь М6: цифра в двух таргетах).
        let config = try String(contentsOf: ClaudeAXTests.repositoryRoot
            .appendingPathComponent("claude-patch").appendingPathComponent("claude.json"),
                                encoding: .utf8)
        XCTAssertEqual(LiveStyle.number(config, key: LiveStyle.sidePaddingKey),
                       LiveStyle.defaultSidePadding)
    }

    func testLiveStyleBlockKeepsForeignRules() throws {
        let block = LiveStyle.block(padding: 5, radius: 15)
        let old = LiveStyle.block(padding: 16, radius: 10)
        let mine = "/* Элвис */\n.a{color:red}\n"

        // 1. Маркеров нет — блок дописан в КОНЕЦ, чужое дословно цело.
        let appended = LiveStyle.applying(block: block, to: mine)
        XCTAssertEqual(appended, mine + block + "\n")
        // 2. Повторный вызов даёт байт-в-байт тот же файл (иначе mtime дёргается каждую секунду).
        XCTAssertEqual(LiveStyle.applying(block: block, to: appended), appended)
        // 3. Блок в СЕРЕДИНЕ файла — заменяется на месте, порядок строк не меняется.
        XCTAssertEqual(LiveStyle.applying(block: block, to: "/* до */\n" + old + "\n/* после */\n"),
                       "/* до */\n" + block + "\n/* после */\n")
        // 4. Блок дважды — мусор от первого маркера до последнего вырезан, свежий блок в конце.
        XCTAssertEqual(LiveStyle.applying(block: block, to: "/* до */\n" + old + "\n" + old + "\n/* после */\n"),
                       "/* до */\n/* после */\n" + block + "\n")
        // 5. Только один из маркеров — та же уборка.
        XCTAssertEqual(LiveStyle.applying(block: block, to: "/* до */\n" + LiveStyle.markerStart + "\n.b{color:blue}\n"),
                       "/* до */\n.b{color:blue}\n" + block + "\n")
        // 6. Файла нет и 7. файл пустой — в файле остаётся один блок.
        XCTAssertEqual(LiveStyle.applying(block: block, to: ""), block + "\n")
        XCTAssertEqual(LiveStyle.applying(block: block, to: "\n\n"), block + "\n")
        // 8. Файл без финального перевода строки — блок всё равно отдельными строками.
        XCTAssertEqual(LiveStyle.applying(block: block, to: "/* хвост */"),
                       "/* хвост */\n" + block + "\n")
    }

    func testLiveStyleWritesBlockAndConfigOnDisk() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let css = dir.appendingPathComponent(LiveStyle.cssFileName)
        let config = dir.appendingPathComponent(LiveStyle.configFileName)
        // Живой claude.json Элвиса: minWindowWidth 300 (не 360 из репозитория) и projectsRoot.
        try Data("""
        {
          "minWindowWidth" : 300,
          "projectsRoot" : "/Users/elvis/_ElvisProjects",
          "sidePadding" : 16
        }

        """.utf8).write(to: config)
        try Data("/* Элвис */\n.a{color:red}\n".utf8).write(to: css)

        XCTAssertEqual(LiveStyle.currentSidePadding(directory: dir), 16)
        XCTAssertTrue(LiveStyle.writeBlock(padding: 5, directory: dir, majorVersion: 26))
        XCTAssertTrue(LiveStyle.writeConfig(sidePadding: 5, directory: dir))
        XCTAssertEqual(try String(contentsOf: css, encoding: .utf8),
                       "/* Элвис */\n.a{color:red}\n" + ClaudeAXTests.expectedBlock + "\n")
        XCTAssertEqual(LiveStyle.currentSidePadding(directory: dir), 5)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(json["minWindowWidth"] as? Int, 300, "merge потерял ширину окна")
        XCTAssertEqual(json["projectsRoot"] as? String, "/Users/elvis/_ElvisProjects")
        XCTAssertEqual(json["sidePadding"] as? Int, 5)
        // Путь остаётся читаемым: без withoutEscapingSlashes вышло бы «\/Users\/elvis\/…».
        XCTAssertTrue(try String(contentsOf: config, encoding: .utf8)
            .contains("\"/Users/elvis/_ElvisProjects\""))

        // Повторный вызов с тем же значением записи НЕ делает — иначе лоадер каждую секунду
        // переставляет CSS во всех страницах.
        let past = Date(timeIntervalSince1970: 0)
        for url in [css, config] {
            try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        }
        XCTAssertTrue(LiveStyle.writeBlock(padding: 5, directory: dir, majorVersion: 26))
        XCTAssertTrue(LiveStyle.writeConfig(sidePadding: 5, directory: dir))
        for url in [css, config] {
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
                           past, "лишняя запись дёрнула mtime у \(url.lastPathComponent)")
        }

        // Битый claude.json не трогаем вовсе (критик В8), а claude.css при этом пишем.
        try Data("{сломано".utf8).write(to: config)
        XCTAssertFalse(LiveStyle.writeConfig(sidePadding: 8, directory: dir))
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "{сломано")
        XCTAssertTrue(LiveStyle.writeBlock(padding: 8, directory: dir, majorVersion: 26))
        XCTAssertTrue(try String(contentsOf: css, encoding: .utf8).contains("border-radius:15px"))
        XCTAssertTrue(try String(contentsOf: css, encoding: .utf8).contains("--chat-column-gutter-start:8px"))

        // Файла claude.json нет — создаём из умолчаний, ничего не теряя.
        try FileManager.default.removeItem(at: config)
        XCTAssertTrue(LiveStyle.writeConfig(sidePadding: 99, directory: dir))
        let fresh = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(fresh["sidePadding"] as? Int, LiveStyle.maxSidePadding) // зажали 99 → 24
        XCTAssertEqual(fresh["minWindowWidth"] as? Int, LiveStyle.defaultMinWindowWidth)
        XCTAssertTrue(try String(contentsOf: config, encoding: .utf8).hasSuffix("}\n"))

        // Пустой claude.json — как «настроек ещё нет»: пишем свой ключ и не падаем.
        XCTAssertNil(LiveStyle.merged(config: "{сломано", sidePadding: 5))
        XCTAssertEqual(LiveStyle.number(LiveStyle.merged(config: "", sidePadding: 7),
                                        key: LiveStyle.sidePaddingKey), 7)
        // Ключи по алфавиту (sortedKeys) — тот же порядок, что у Patcher.ensureConfig.
        let merged = try XCTUnwrap(LiveStyle.merged(config: "{\"projectsRoot\":\"/tmp\",\"minWindowWidth\":300}",
                                                    sidePadding: 5))
        XCTAssertLessThan(try XCTUnwrap(merged.range(of: "minWindowWidth")).lowerBound,
                          try XCTUnwrap(merged.range(of: "projectsRoot")).lowerBound)
    }

    // MARK: - ползунок «Поля по бокам» (задача #5360)

    func testSidePaddingSliderItemCarriesViewAndDebounces() throws {
        var changed: [Int] = []
        let done = expectation(description: "дебаунс ползунка")
        var config = menuConfig()
        config.sidePadding = 40 // зажмётся в 24
        config.setSidePadding = {
            changed.append($0)
            done.fulfill()
        }
        let appearance = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        let item = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.sidePaddingTitle })
        XCTAssertNil(item.submenu)
        // Ползунок — общий компонент: им же сделана «⏱ Скорость» живых цветов (план WF18).
        let view = try XCTUnwrap(item.view as? SliderMenuView)
        XCTAssertEqual(view.slider.minValue, Double(LiveStyle.minSidePadding))
        XCTAssertEqual(view.slider.maxValue, Double(LiveStyle.maxSidePadding))
        XCTAssertEqual(view.slider.doubleValue, 24, accuracy: 0.001)
        XCTAssertTrue(view.slider.isContinuous)
        XCTAssertEqual(view.slider.numberOfTickMarks, 0) // делений не рисуем — была бы гребёнка

        // Ползунок тащат: несколько событий подряд дают ОДНУ запись, значение округляется.
        let action = try XCTUnwrap(view.slider.action)
        for value in [7.4, 7.6] {
            view.slider.doubleValue = value
            _ = (view.slider.target as? NSObject)?.perform(action, with: view.slider)
        }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(changed, [8])
    }

    // MARK: - живые цвета (план WF18)

    private func liveBody(_ state: LiveColorsState, titles: [String] = [],
                          id: String = "1-0001", at: TimeInterval = 0) -> String {
        CommandChannel.payload(action: LiveColors.action,
                               fields: LiveColors.fields(state: state, titles: titles),
                               id: id, at: Date(timeIntervalSince1970: at))
    }

    func testLiveColorsPayloadMatchesContract() throws {
        // Контракт п. 3 плана WF18, побайтно: id, action, at, scope, on, mode, period, epoch,
        // light, titles, ring. Числа — числами, не строками.
        let state = LiveColorsState(on: true, mode: .sync, period: 300, tone: .dark,
                                    epoch: 1_757_000_000_000)
        let body = liveBody(state, titles: ["Trelvis", "Dictatorik"])
        XCTAssertTrue(body.hasPrefix("{\"id\":\"1-0001\",\"action\":\"live-colors\","
            + "\"at\":\"1970-01-01T00:00:00Z\",\"scope\":\"all\",\"on\":true,\"mode\":\"sync\","
            + "\"period\":300,\"epoch\":1757000000000,\"light\":false,"
            + "\"titles\":[\"Trelvis\",\"Dictatorik\"],\"ring\":{\"dark\":[{\"accent\":\"#"), body)
        XCTAssertTrue(body.hasSuffix("}]}}"), body)

        // Порядок ключей внутри каждой палитры кольца — accent, background, foreground, sidebar,
        // panel, muted (критик В6): обход словаря в Swift непредсказуем, поэтому палитры идут
        // через Theme.paletteValue, и контракт не плывёт от запуска к запуску.
        for light in [false, true] {
            for palette in LiveColors.palettes(light: light) {
                let literal = "{" + Theme.paletteOrder.map { "\"\($0)\":\"\(palette[$0] ?? "")\"" }
                    .joined(separator: ",") + "}"
                XCTAssertTrue(body.contains(literal), literal)
            }
        }
        // Оба кольца целиком: 12 тёмных палитр и 12 светлых.
        XCTAssertEqual(body.components(separatedBy: "\"accent\":").count - 1, LiveColors.ringCount * 2)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let ring = try XCTUnwrap(json["ring"] as? [String: Any])
        XCTAssertEqual((ring["dark"] as? [[String: String]])?.count, LiveColors.ringCount)
        XCTAssertEqual((ring["light"] as? [[String: String]])?.count, LiveColors.ringCount)
        // Команда одна на всё и не бесконечная: 24 палитры по шесть hex — около 3,5 КБ.
        XCTAssertLessThan(body.count, 5000, "команда распухла: \(body.count) байт")

        // Выключение — только scope и on: страница сама вернёт окну прежнюю тему.
        var off = state
        off.on = false
        XCTAssertEqual(liveBody(off), "{\"id\":\"1-0001\",\"action\":\"live-colors\","
            + "\"at\":\"1970-01-01T00:00:00Z\",\"scope\":\"all\",\"on\":false}")

        // «🪟 Как окно сейчас» — light: null; в режиме «все одним цветом» он невозможен (М2).
        var window = state
        window.mode = .solo
        window.tone = .window
        XCTAssertTrue(liveBody(window).contains("\"light\":null,\"titles\":[]"), liveBody(window))
        window.mode = .sync
        XCTAssertTrue(liveBody(window).contains("\"light\":false"))
        // Светлые — true.
        var light = state
        light.tone = .light
        XCTAssertTrue(liveBody(light).contains("\"light\":true"))
    }

    func testLiveColorsRingKeepsContrastBetweenAnchors() throws {
        // Критик В14: контраст WF10 гарантирован в опорных точках, а страница идёт между ними
        // по хорде в sRGB, и просадка возможна ровно в середине шага. Проверяем середины
        // ВСЕХ хорд обоих колец — не уложились бы, кольцо стало бы из 24 точек.
        for light in [false, true] {
            let ring = LiveColors.palettes(light: light)
            XCTAssertEqual(ring.count, LiveColors.ringCount)
            for (index, palette) in ring.enumerated() {
                XCTAssertEqual(Set(palette.keys), Set(Theme.paletteOrder))
                let next = ring[(index + 1) % ring.count]
                for share in [0.0, 0.5] {
                    func mixed(_ key: String) -> String {
                        LiveColors.mix(palette[key] ?? "", next[key] ?? "", share)
                    }
                    let where_ = "кольцо \(light ? "светлое" : "тёмное") \(index)+\(share)"
                    let text = try XCTUnwrap(AutoPaint.contrast(hex: mixed("foreground"),
                                                                hex: mixed("background")))
                    XCTAssertGreaterThanOrEqual(text, AutoPaint.accentContrast, "текст, \(where_)")
                    let accent = try XCTUnwrap(AutoPaint.contrast(hex: mixed("accent"),
                                                                  hex: mixed("background")))
                    XCTAssertGreaterThanOrEqual(accent, AutoPaint.accentContrast, "акцент, \(where_)")
                    XCTAssertLessThanOrEqual(accent, AutoPaint.accentContrastCap(light: light),
                                             "акцент кричит, \(where_)")
                    // Фон остаётся «трендовым, не кричащим» и между опорными точками.
                    let saturation = try XCTUnwrap(AutoPaint.saturation(hex: mixed("background")))
                    XCTAssertLessThanOrEqual(saturation, AutoPaint.maxBackgroundSaturation + 0.5,
                                             "фон кричит, \(where_)")
                }
            }
        }
        // Смешение — как на странице: половина хорды между чёрным и белым.
        XCTAssertEqual(LiveColors.mix("#000000", "#ffffff", 0.5), "#808080")
        XCTAssertEqual(LiveColors.mix("#102030", "#102030", 1), "#102030")
        XCTAssertEqual(LiveColors.mix("не цвет", "#ffffff", 0.5), "не цвет")
    }

    func testLiveColorsScaleAndEpochKeepTheHue() {
        // Шкала: восемь делений, 30…1 минута, по умолчанию 5 минут (решение 5, критик В4).
        XCTAssertEqual(LiveColors.periods, [1800, 1200, 900, 600, 300, 180, 120, 60])
        XCTAssertEqual(LiveColors.defaultPeriod, 300)
        XCTAssertEqual(LiveColors.defaultMode, .solo)
        XCTAssertEqual(LiveColors.defaultTone, .dark)
        XCTAssertEqual(LiveColors.period(at: 0), 1800)
        XCTAssertEqual(LiveColors.period(at: 99), 60) // быстрее минуты не даём
        XCTAssertEqual(LiveColors.period(at: -3), 1800)
        XCTAssertEqual(LiveColors.index(of: 300), 4)
        XCTAssertEqual(LiveColors.index(of: 310), 4) // правленое руками — ближайшее деление
        XCTAssertEqual(LiveColors.period(clamping: 45), 60)
        XCTAssertEqual(MenuModel.liveColorsSpeed(300), "круг за 5 мин")
        XCTAssertEqual(MenuModel.liveColorsSpeed(1800), "круг за 30 мин")

        // Цвет считается от стенных часов (решение 1): четверть круга — 90°.
        let now = 1_757_000_000_000
        XCTAssertEqual(LiveColors.hue(epoch: now, period: 300, now: now), 0, accuracy: 0.001)
        XCTAssertEqual(LiveColors.hue(epoch: now - 75_000, period: 300, now: now), 90, accuracy: 0.001)
        // Круг замкнулся — тот же цвет, а не 450°.
        XCTAssertEqual(LiveColors.hue(epoch: now - 375_000, period: 300, now: now), 90, accuracy: 0.001)

        // Смена скорости не дёргает цвет (решение 3): hue до и после совпадает.
        let before = LiveColorsState(on: true, mode: .solo, period: 300, tone: .dark,
                                     epoch: now - 75_000)
        let after = LiveColors.state(before, period: 60, now: now)
        XCTAssertEqual(after.period, 60)
        XCTAssertEqual(LiveColors.hue(epoch: after.epoch, period: after.period, now: now), 90,
                       accuracy: 0.01)
        XCTAssertEqual(LiveColors.state(before, period: 7, now: now).period, 60)

        // «Как окно сейчас» живёт только в режиме «каждое своим» (критик М2).
        XCTAssertEqual(LiveColors.tone(.window, mode: .solo), .window)
        XCTAssertEqual(LiveColors.tone(.window, mode: .sync), .dark)
        XCTAssertEqual(LiveColors.tone(.light, mode: .sync), .light)
        XCTAssertEqual(LiveColorsTone.dark.lightValue, false)
        XCTAssertEqual(LiveColorsTone.light.lightValue, true)
        XCTAssertNil(LiveColorsTone.window.lightValue)
    }

    func testLiveColorsStoreRemembersRunAndDefaults() {
        let defaults = MemoryDefaults()
        let store = LiveColorsStore(defaults: defaults)
        // Пусто — выключено, «каждое своим», круг за 5 минут, тёмные.
        XCTAssertEqual(store.state, LiveColorsState())
        XCTAssertFalse(store.state.on)

        let state = LiveColorsState(on: true, mode: .sync, period: 120, tone: .window,
                                    epoch: 1_757_000_000_000)
        store.save(state)
        XCTAssertEqual(store.state, state)
        // Ключи — те, что читает живое приложение (решение 4 плана).
        XCTAssertEqual(defaults.values[LiveColorsStore.onKey] as? Bool, true)
        XCTAssertEqual(defaults.values[LiveColorsStore.modeKey] as? String, "sync")
        XCTAssertEqual(defaults.values[LiveColorsStore.periodKey] as? Int, 120)
        XCTAssertEqual(defaults.values[LiveColorsStore.toneKey] as? String, "window")
        XCTAssertEqual(defaults.values[LiveColorsStore.epochKey] as? Int, 1_757_000_000_000)

        // Настройки правят и руками: мусор даёт умолчания, а не падение.
        defaults.values[LiveColorsStore.modeKey] = "неведомо"
        defaults.values[LiveColorsStore.toneKey] = 42
        defaults.values[LiveColorsStore.periodKey] = 7
        XCTAssertEqual(store.state.mode, .solo)
        XCTAssertEqual(store.state.tone, .dark)
        XCTAssertEqual(store.state.period, 60)
    }

    func testLiveColorsMenuHasOffModesSpeedAndTones() throws {
        var modes: [String] = []
        var tones: [String] = []
        var periods: [Int] = []
        let dragged = expectation(description: "дебаунс ползунка скорости")
        var config = menuConfig()
        config.liveColors = LiveColorsState(on: true, mode: .solo, period: 120, tone: .light,
                                            epoch: 1)
        config.setLiveColorsMode = { modes.append($0?.rawValue ?? "off") }
        config.setLiveColorsTone = { tones.append($0.rawValue) }
        config.setLiveColorsPeriod = {
            periods.append($0)
            dragged.fulfill()
        }
        let appearance = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        let all = try XCTUnwrap(appearance.items.first { $0.title == MenuModel.allWindowsTitle }?.submenu)
        let live = try XCTUnwrap(all.items.first { $0.title == MenuModel.liveColorsTitle }?.submenu)

        // Вариант А макета: выключатель, два режима, ползунок, три режима света.
        XCTAssertEqual(live.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Выключить", "—", "Все окна одним цветом", "Каждое окно своим цветом",
                        "—", "Скорость", "—", "Тёмные", "Светлые", "Как окно сейчас"])
        XCTAssertEqual(live.items.filter { $0.state == .on }.map { $0.title },
                       ["Каждое окно своим цветом", "Светлые"])
        // Предпросмотра нет: команда одна на все окна, примерять нечего.
        XCTAssertNil(live.delegate)
        XCTAssertTrue(live.items.compactMap { ($0 as? BlockMenuItem)?.preview }.isEmpty)
        // «🪟 Как окно сейчас» доступен в режиме «каждое своим» (критик М2).
        XCTAssertTrue(try XCTUnwrap(live.items.first { $0.title == MenuModel.liveColorsWindowTitle }).isEnabled)

        // Ползунок — тот же компонент, что «Поля по бокам»: восемь делений шкалы.
        let speed = try XCTUnwrap(live.items.first { $0.title == MenuModel.liveColorsSpeedTitle })
        XCTAssertNil(speed.submenu)
        let view = try XCTUnwrap(speed.view as? SliderMenuView)
        XCTAssertEqual(view.slider.minValue, 0)
        XCTAssertEqual(view.slider.maxValue, Double(LiveColors.periods.count - 1))
        XCTAssertEqual(view.slider.doubleValue, Double(LiveColors.index(of: 120)), accuracy: 0.001)

        for item in live.items where !item.isSeparatorItem && item.view == nil { click(item) }
        XCTAssertEqual(modes, ["off", "sync", "solo"])
        XCTAssertEqual(tones, ["dark", "light", "window"])

        // Тащим ползунок: одна запись после дебаунса, значение — с деления шкалы.
        let action = try XCTUnwrap(view.slider.action)
        view.slider.doubleValue = 0.4
        _ = (view.slider.target as? NSObject)?.perform(action, with: view.slider)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(periods, [1800])

        // Выключено — галка у «⏹ Выключить»; в режиме «все одним цветом» «Как окно сейчас» погашен.
        var off = menuConfig()
        off.liveColors = LiveColorsState(on: false, mode: .sync, period: 300, tone: .dark, epoch: 0)
        let offAppearance = try XCTUnwrap(MinimizeMenu.build(config: off).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        let offLive = try XCTUnwrap(offAppearance.items
            .first { $0.title == MenuModel.allWindowsTitle }?.submenu?.items
            .first { $0.title == MenuModel.liveColorsTitle }?.submenu)
        XCTAssertEqual(offLive.items.filter { $0.state == .on }.map { $0.title },
                       ["Выключить", "Тёмные"])
        XCTAssertFalse(try XCTUnwrap(offLive.items
            .first { $0.title == MenuModel.liveColorsWindowTitle }).isEnabled)
    }

    func testAutoPaintDimsWhileLiveColorsRun() throws {
        // Критик В13: пока живые цвета крутятся, «🌈 Раскрасить по кругу ▸» гаснет — иначе
        // покраска пишет темы окнам, а живой слой перекрывает их через четверть секунды.
        var config = menuConfig()
        config.liveColors = LiveColorsState(on: true, mode: .solo, period: 300, tone: .dark, epoch: 1)
        func autoPaint(_ config: MinimizeMenu.MenuConfig) throws -> NSMenu {
            let appearance = try XCTUnwrap(MinimizeMenu.build(config: config).items
                .first { $0.title == MenuModel.appearanceTitle }?.submenu)
            return try XCTUnwrap(appearance.items
                .first { $0.title == MenuModel.allWindowsTitle }?.submenu?.items
                .first { $0.title == MenuModel.autoPaintTitle }?.submenu)
        }
        let dimmed = try autoPaint(config)
        XCTAssertEqual(dimmed.items.first?.title, MenuModel.autoPaintLiveHint)
        XCTAssertTrue(dimmed.items.filter { !$0.isSeparatorItem }.allSatisfy { !$0.isEnabled })

        // Живые выключены — подсказки нет, пункты работают.
        let plain = try autoPaint(menuConfig())
        XCTAssertNil(plain.items.first { $0.title == MenuModel.autoPaintLiveHint })
        XCTAssertTrue(plain.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled })
    }

    func testLiveColorsGoOutAsOneCommandAndAreRemembered() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("command.json")
        var now = Date(timeIntervalSince1970: 1_757_000_000)
        // Таймер не нужен: между записями часы двигаем сами, зазор канала выдержан.
        let channel = CommandChannel(path: file, now: { now }, schedule: { _, _ in })
        let defaults = MemoryDefaults()
        let actions = ClaudeActions(app: ClaudeApp(), commands: channel, themes: [], fonts: [],
                                    themeStore: ThemeStore(defaults: MemoryDefaults()),
                                    myThemes: MyThemesStore(url: dir.appendingPathComponent("my.json")),
                                    autoPaintStore: AutoPaintStore(defaults: MemoryDefaults()),
                                    liveColorsStore: LiveColorsStore(defaults: defaults))
        actions.clock = { now }
        func command() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: file)) as? [String: Any])
        }

        XCTAssertTrue(actions.startLiveColors(mode: .solo))
        var json = try command()
        XCTAssertEqual(json["action"] as? String, LiveColors.action)
        XCTAssertEqual(json["scope"] as? String, "all")
        XCTAssertEqual(json["on"] as? Bool, true)
        XCTAssertEqual(json["mode"] as? String, "solo")
        XCTAssertEqual(json["period"] as? Int, LiveColors.defaultPeriod)
        XCTAssertEqual(json["epoch"] as? Int, LiveColors.milliseconds(now))
        XCTAssertNotNil(json["ring"])
        XCTAssertTrue(actions.liveColors.on) // запомнили в настройках приложения

        // Скорость меняется без прыжка цвета: за 75 с круга по 300 с прошло 90°.
        now = now.addingTimeInterval(75)
        XCTAssertTrue(actions.setLiveColors(period: 60))
        json = try command()
        XCTAssertEqual(json["period"] as? Int, 60)
        XCTAssertEqual(LiveColors.hue(epoch: try XCTUnwrap(json["epoch"] as? Int), period: 60,
                                      now: LiveColors.milliseconds(now)), 90, accuracy: 0.01)
        XCTAssertEqual(actions.liveColors.period, 60)

        // Режим света запоминается и уезжает той же одной командой.
        now = now.addingTimeInterval(1)
        XCTAssertTrue(actions.setLiveColors(tone: .light))
        XCTAssertEqual(try command()["light"] as? Bool, true)
        XCTAssertEqual(actions.liveColors.tone, .light)

        // Выключение — короткая команда; кольца в ней нет вовсе.
        now = now.addingTimeInterval(1)
        XCTAssertTrue(actions.stopLiveColors())
        json = try command()
        XCTAssertEqual(json["on"] as? Bool, false)
        XCTAssertNil(json["ring"])
        XCTAssertFalse(actions.liveColors.on)
        // Выключенные живые цвета при старте приложения молчат, а включённые — пересылаются.
        XCTAssertFalse(actions.resendLiveColors())
        now = now.addingTimeInterval(1)
        XCTAssertTrue(actions.startLiveColors(mode: .sync))
        // «Как окно сейчас» в «синхронно» невозможен: свет садится на тёмные (критик М2).
        now = now.addingTimeInterval(1)
        XCTAssertTrue(actions.setLiveColors(tone: .window))
        XCTAssertEqual(actions.liveColors.tone, .dark)
        now = now.addingTimeInterval(1)
        XCTAssertTrue(actions.resendLiveColors())
        XCTAssertEqual(try command()["mode"] as? String, "sync")
    }

    func testProjectPaintStaysSilentWhileLiveColorsRun() throws {
        // Блокер Б2 плана WF18: живой слой перекрывает цвет проекта — пока живые цвета
        // крутятся, ProjectPaint не шлёт ни одной команды. Выключили — красит как обычно.
        let box = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: box) }
        let root = box.appendingPathComponent("_ElvisProjects", isDirectory: true)
        let sessions = box.appendingPathComponent("sessions", isDirectory: true)
        let folder = root.appendingPathComponent("PimpMyClaude", isDirectory: true)
        let place = sessions.appendingPathComponent("4646c58f/8cb117af", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        let session: [String: Any] = ["sessionId": "local_a1", "title": "Vkusnoff",
                                      "titleSource": "user", "cwd": folder.path,
                                      "originCwd": folder.path, "lastFocusedAt": 3000,
                                      "lastActivityAt": 3000, "isArchived": false]
        try JSONSerialization.data(withJSONObject: session)
            .write(to: place.appendingPathComponent("local_a1.json"))

        let index = ProjectIndex(sessionsDirectory: sessions,
                                 statusURL: box.appendingPathComponent("status.json"),
                                 projectsRoot: root, home: box)
        let store = ProjectSettingsStore(registryURL: box.appendingPathComponent("projects.json"))
        store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(catalog()[0])), to: folder)
        let paint = ProjectPaint(index: index, store: store, defaults: MemoryDefaults())
        var sent = 0
        var live = true
        paint.send = { _ in
            sent += 1
            return true
        }
        paint.windowTitles = { ["Vkusnoff"] }
        paint.isLiveColorsOn = { live }

        paint.tick()
        XCTAssertEqual(sent, 0, "цвет проекта заговорил поверх живых цветов")
        live = false
        paint.tick()
        XCTAssertEqual(sent, 1)
    }

    /// Наведение на пункт без popUp: так его зовёт AppKit — через делегата подменю.
    private func highlight(_ menu: NSMenu, _ item: NSMenuItem?) {
        guard let delegate = menu.delegate else {
            return XCTFail("у подменю «\(menu.title)» нет делегата")
        }
        delegate.menu?(menu, willHighlight: item)
    }

    /// Нажатие на пункт меню без popUp: BlockMenuItem держит замыкание на себе.
    private func click(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target as? NSObject else {
            return XCTFail("у пункта «\(item.title)» нет действия")
        }
        target.perform(action)
    }
}
