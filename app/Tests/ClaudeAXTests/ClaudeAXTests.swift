import AppKit
import XCTest
@testable import ClaudeAX

/// Хранилище-заглушка: тесты не должны писать в живые настройки приложения.
private final class MemoryDefaults: ThemeDefaults {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

/// Только чистая логика: раскладка «Расставить», клавиши меню и формат command.json.
/// Живой AX (окна Claude, авто-Allow, popUp) проверяется руками на гейте.
final class ClaudeAXTests: XCTestCase {
    func testSkeleton() { XCTAssertEqual(ClaudeCommand.allCases.count, 7) }

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
        let expected: [(ClaudeCommand, String, UInt32, Bool)] = [
            (.cashout, "Обкэшить   ⌘⇧N", 0x2D, true),
            (.newChat, "Новый чат   ⌘N", 0x2D, false), // ⌘N — штатная клавиша Claude, не регистрируем
            (.collapse, "Свернуть   ⌘⌥↓", 0x7D, true),
            (.expand, "Развернуть   ⌘⌥↑", 0x7E, true),
            (.arrange, "Расставить   ⌘⌥A", 0x00, true),
            (.show, "Показать   ⌘⌥S", 0x01, true),
            (.scroll, "Прокрутить   ⌘⌥D", 0x02, true),
        ]
        XCTAssertEqual(MenuModel.entries.map { $0.command }, expected.map { $0.0 })
        for (command, title, code, registers) in expected {
            let entry = MenuModel.entry(for: command)
            XCTAssertEqual(entry?.menuTitle, title)
            XCTAssertEqual(entry?.key.keyCode, code)
            XCTAssertEqual(entry?.registersHotkey, registers)
        }
        XCTAssertEqual(MenuModel.entries.map { $0.icon }, ["💰", "💬", "⬇️", "⬆️", "▦", "👀", "⏬"])
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

    /// Шрифт для команды: моноширинный, семейство — голым именем (контракт п. 5).
    private static let monoFont = Font(id: "sf-mono", family: "SF Mono", mono: true, displayName: "SF Mono")

    private func themeBody(theme: Layer<Theme>, font: Layer<Font>,
                           scope: String = MenuModel.themeScopeWindow, title: String = "Vkusnoff",
                           id: String = "1756900000123-0042",
                           at: TimeInterval = 1_756_900_000) -> String {
        CommandChannel.payload(action: "theme",
                               fields: ClaudeActions.themeFields(scope: scope, title: title,
                                                                 theme: theme, font: font),
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

    func testCommandValueWritesBooleans() {
        XCTAssertEqual(CommandValue.bool(true).json, "true")
        XCTAssertEqual(CommandValue.bool(false).json, "false")
        XCTAssertEqual(CommandValue.object([(key: "mono", value: .bool(false))]).json, "{\"mono\":false}")
        XCTAssertEqual(Font(id: "georgia", family: "Georgia", mono: false, displayName: "Джорджия")
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
        config.fonts = [Font(id: "georgia", family: "Georgia", mono: false, displayName: "Georgia"),
                        ClaudeAXTests.monoFont]
        config.myThemes = [myTheme()]
        config.windowThemeID = "arctic"
        config.windowFontID = "sf-mono"
        return config
    }

    func testMenuHasTwoThemeSubmenus() throws {
        var applied: [(scope: String, theme: String?, font: String?, keep: String)] = []
        var saved = 0
        var deleted: [String] = []
        var config = menuConfig()
        config.apply = { scope, theme, font in
            let keep = (theme.isKeep ? "t" : "") + (font.isKeep ? "f" : "")
            applied.append((scope: scope, theme: theme.value?.id, font: font.value?.id, keep: keep))
        }
        config.applyMyTheme = { scope, my in
            applied.append((scope: scope, theme: my.id, font: my.font?.id, keep: ""))
        }
        config.saveMyTheme = { saved += 1 }
        config.deleteMyTheme = { deleted.append($0.id) }
        let menu = MinimizeMenu.build(config: config)

        // Семь пунктов и два подменю; разделителей три — после «Новый чат», «Развернуть» и перед темами.
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.count, MenuModel.entries.count + 2)
        XCTAssertEqual(menu.items.filter { $0.isSeparatorItem }.count, 3)
        XCTAssertTrue(menu.items[MenuModel.entries.count + 2].isSeparatorItem)
        let submenus = menu.items.filter { $0.hasSubmenu }
        XCTAssertEqual(submenus.map { $0.title }, ["Тема", "Шрифт"])

        // MARK: подменю «Тема» — секции, «Всем окнам ▸» внутри, свои темы
        let theme = try XCTUnwrap(submenus.first?.submenu)
        XCTAssertEqual(theme.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["МОИ ТЕМЫ", "Моя тёплая", "—", "ТЁМНЫЕ", "Фиолетовая", "СВЕТЛЫЕ", "Арктика",
                        "—", "Как у Claude", "—", "Всем окнам", "Сохранить как мою тему…",
                        "Удалить мою тему"])
        for title in ["МОИ ТЕМЫ", "ТЁМНЫЕ", "СВЕТЛЫЕ"] {
            let header = try XCTUnwrap(theme.items.first { $0.title == title })
            XCTAssertFalse(header.isEnabled, "заголовок «\(title)» кликабелен")
            XCTAssertFalse(header.hasSubmenu)
        }
        let violet = try XCTUnwrap(theme.items.first { $0.title == "Фиолетовая" })
        XCTAssertNotNil(violet.image) // кружок цвета
        XCTAssertEqual(violet.image?.size, NSSize(width: 14, height: 14))
        XCTAssertEqual(violet.image?.isTemplate, false)
        XCTAssertNotNil(violet.image?.tiffRepresentation) // кружок рисуется, а не падает
        // Цвета кружка — из палитры; кривой цвет не должен ронять меню.
        XCTAssertEqual(MinimizeMenu.color("#abc"), MinimizeMenu.color("#AABBCC"))
        XCTAssertNil(MinimizeMenu.color("не цвет"))
        XCTAssertNil(MinimizeMenu.color(nil))
        XCTAssertEqual(violet.state, .off)
        XCTAssertEqual(try XCTUnwrap(theme.items.first { $0.title == "Арктика" }).state, .on) // выбрана
        // У окна записи «Как у Claude» нет — галку не ставим никуда.
        XCTAssertEqual(try XCTUnwrap(theme.items.first { $0.title == "Как у Claude" }).state, .off)

        let themeAll = try XCTUnwrap(theme.items.first { $0.title == "Всем окнам" }?.submenu)
        XCTAssertEqual(themeAll.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["ВСЕМ ОКНАМ", "МОИ ТЕМЫ", "Моя тёплая", "—", "ТЁМНЫЕ", "Фиолетовая",
                        "СВЕТЛЫЕ", "Арктика", "—", "Как у Claude"])
        XCTAssertFalse(try XCTUnwrap(themeAll.items.first).isEnabled) // заголовок «ВСЕМ ОКНАМ»
        XCTAssertEqual(themeAll.items.last?.state, .on) // всем окнам ничего не задано → «Как у Claude»

        // MARK: подменю «Шрифт»
        let font = try XCTUnwrap(submenus.last?.submenu)
        XCTAssertEqual(font.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["ОБЫЧНЫЕ", "Georgia", "МОНОШИРИННЫЕ", "SF Mono", "—",
                        "Системный (как у Claude)", "Всем окнам"])
        XCTAssertFalse(try XCTUnwrap(font.items.first).isEnabled)
        // Каждый пункт нарисован своим шрифтом.
        let georgia = try XCTUnwrap(font.items.first { $0.title == "Georgia" })
        XCTAssertEqual((georgia.attributedTitle?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 13)
        XCTAssertEqual(try XCTUnwrap(font.items.first { $0.title == "SF Mono" }).state, .on)
        let fontAll = try XCTUnwrap(font.items.first { $0.title == "Всем окнам" }?.submenu)
        XCTAssertEqual(fontAll.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["ВСЕМ ОКНАМ", "ОБЫЧНЫЕ", "Georgia", "МОНОШИРИННЫЕ", "SF Mono", "—",
                        "Системный (как у Claude)"])

        // MARK: нажатия — каждый пункт трогает ровно свой слой
        click(try XCTUnwrap(theme.items.first { $0.title == "Фиолетовая" }))
        click(try XCTUnwrap(theme.items.first { $0.title == "Как у Claude" }))
        click(try XCTUnwrap(themeAll.items.first { $0.title == "Арктика" }))
        click(try XCTUnwrap(font.items.first { $0.title == "SF Mono" }))
        click(try XCTUnwrap(font.items.first { $0.title == "Системный (как у Claude)" }))
        click(try XCTUnwrap(fontAll.items.first { $0.title == "Georgia" }))
        click(try XCTUnwrap(theme.items.first { $0.title == "Моя тёплая" }))
        XCTAssertEqual(applied.map { $0.scope }, ["window", "window", "all", "window", "window", "all", "window"])
        XCTAssertEqual(applied.map { $0.theme }, ["violet", nil, "arctic", nil, nil, nil, "user-1756900000000"])
        XCTAssertEqual(applied.map { $0.font }, [nil, nil, nil, "sf-mono", nil, "georgia", "sf-mono"])
        // Тема не трогает слой шрифта и наоборот (в команде поля просто нет).
        XCTAssertEqual(applied.map { $0.keep }, ["f", "f", "f", "t", "t", "t", ""])

        click(try XCTUnwrap(theme.items.first { $0.title == "Сохранить как мою тему…" }))
        let deletes = try XCTUnwrap(theme.items.first { $0.title == "Удалить мою тему" }?.submenu)
        XCTAssertEqual(deletes.items.map { $0.title }, ["Моя тёплая"])
        click(deletes.items[0])
        XCTAssertEqual(saved, 1)
        XCTAssertEqual(deleted, ["user-1756900000000"])

        // Своих тем нет — ни секции, ни «Удалить мою тему»; «Сохранить» остаётся.
        var without = menuConfig()
        without.myThemes = []
        let plainTheme = try XCTUnwrap(MinimizeMenu.build(config: without).items
            .first { $0.title == "Тема" }?.submenu)
        XCTAssertEqual(plainTheme.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["ТЁМНЫЕ", "Фиолетовая", "СВЕТЛЫЕ", "Арктика", "—", "Как у Claude", "—",
                        "Всем окнам", "Сохранить как мою тему…"])

        // Каталога нет — меню прежнее, из семи пунктов.
        XCTAssertTrue(MinimizeMenu.build(config: MinimizeMenu.MenuConfig()).items.allSatisfy { !$0.hasSubmenu })
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

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(MyThemesStore.fileName)
        let store = MyThemesStore(url: url)
        XCTAssertTrue(store.load().isEmpty) // файла ещё нет — не падаем

        let saved = try XCTUnwrap(store.add(name: "  Моя тёплая  ", theme: catalog()[0],
                                            font: ClaudeAXTests.monoFont, now: 1_756_900_000))
        XCTAssertEqual(saved.map { $0.id }, ["user-1756900000000"])
        let loaded = store.load()
        XCTAssertEqual(loaded.map { $0.name }, ["Моя тёплая"]) // пробелы срезаны
        XCTAssertEqual(loaded[0].palette["background"], "#1b1626") // палитра скопирована
        XCTAssertEqual(loaded[0].font?.family, "SF Mono")
        XCTAssertEqual(loaded[0].font?.mono, true)
        XCTAssertEqual(loaded[0].theme.id, "user-1756900000000") // команда уходит со своим id
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.hasPrefix("{\"version\":1,\"themes\":[{\"id\":\"user-1756900000000\","), raw)
        XCTAssertTrue(raw.contains("\"font\":{\"id\":\"sf-mono\",\"family\":\"SF Mono\",\"mono\":true}"), raw)

        // Тема без шрифта и обрезка имени по 80 знакам.
        let long = try XCTUnwrap(store.add(name: String(repeating: "я", count: 100),
                                           theme: catalog()[1], font: nil, now: 1_756_900_001))
        XCTAssertEqual(long.count, 2)
        XCTAssertEqual(long.last?.name.count, MyThemesStore.nameLimit)
        XCTAssertNil(store.load().last?.font)
        // Пустое имя не сохраняется.
        XCTAssertNil(store.add(name: "   ", theme: catalog()[0], font: nil))

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

    /// Нажатие на пункт меню без popUp: BlockMenuItem держит замыкание на себе.
    private func click(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target as? NSObject else {
            return XCTFail("у пункта «\(item.title)» нет действия")
        }
        target.perform(action)
    }
}
