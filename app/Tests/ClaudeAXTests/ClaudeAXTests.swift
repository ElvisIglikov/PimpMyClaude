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

    func testThemePayloadMatchesContract() throws {
        let at = Date(timeIntervalSince1970: 1_756_900_000) // 2025-09-03T11:46:40Z
        let body = CommandChannel.payload(action: "theme", fields: [
            (key: "scope", value: .string(MenuModel.themeScopeWindow)),
            (key: "title", value: .string("Vkusnoff")),
            (key: "theme", value: catalog()[0].commandValue),
        ], id: "1756900000123-0042", at: at)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "theme")
        XCTAssertEqual(json["scope"] as? String, "window")
        XCTAssertEqual(json["title"] as? String, "Vkusnoff")
        let theme = try XCTUnwrap(json["theme"] as? [String: Any])
        XCTAssertEqual(theme["id"] as? String, "violet")
        XCTAssertEqual(theme["type"] as? String, "dark")
        XCTAssertEqual((theme["palette"] as? [String: String])?["background"], "#1b1626")

        // Побайтно как в контракте п. 3 плана WF5: порядок полей id, action, at, scope, title, theme.
        let expected = "{\"id\":\"1756900000123-0042\",\"action\":\"theme\",\"at\":\"2025-09-03T11:46:40Z\","
            + "\"scope\":\"window\",\"title\":\"Vkusnoff\",\"theme\":{\"id\":\"violet\","
            + "\"name\":\"Фиолетовая\",\"type\":\"dark\",\"palette\":{\"accent\":\"#a78bfa\","
            + "\"background\":\"#1b1626\",\"foreground\":\"#ece9f5\",\"sidebar\":\"#151021\","
            + "\"panel\":\"#241d33\",\"muted\":\"#8b81a6\"}}}"
        XCTAssertEqual(body, expected)
    }

    func testThemeResetPayloadCarriesNull() throws {
        let body = CommandChannel.payload(action: "theme", fields: [
            (key: "scope", value: .string(MenuModel.themeScopeAll)),
            (key: "title", value: .string("")),
            (key: "theme", value: .null),
        ], id: "1-0001", at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(body.hasSuffix("\"scope\":\"all\",\"title\":\"\",\"theme\":null}"), body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertTrue(json["theme"] is NSNull)
        // Старые команды не поехали: extra по-прежнему пишет строки по алфавиту.
        XCTAssertEqual(CommandChannel.payload(action: "scroll", extra: [:], id: "1-0001",
                                              at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"scroll\",\"at\":\"1970-01-01T00:00:00Z\"}")
    }

    func testMenuHasTwoThemeSubmenus() throws {
        let themes = catalog()
        var applied: [(scope: String, theme: String?)] = []
        let menu = MinimizeMenu.build(themes: themes, windowThemeID: "arctic", allThemeID: nil,
                                      perform: { _ in },
                                      applyTheme: { applied.append((scope: $0, theme: $1?.id)) })
        // Семь пунктов и два подменю; разделителей три — после «Новый чат», «Развернуть» и перед темами.
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.count, MenuModel.entries.count + 2)
        XCTAssertEqual(menu.items.filter { $0.isSeparatorItem }.count, 3)
        let submenus = menu.items.filter { $0.hasSubmenu }
        XCTAssertEqual(submenus.map { $0.title }, ["Тема окна", "Тема всех окон"])
        XCTAssertTrue(menu.items[MenuModel.entries.count + 2].isSeparatorItem)

        let windowItems = try XCTUnwrap(submenus.first?.submenu).items
        XCTAssertEqual(windowItems.filter { !$0.isSeparatorItem }.map { $0.title },
                       ["Фиолетовая", "Арктика", "Как у Claude"]) // N тем + сброс
        XCTAssertEqual(windowItems[0].state, .off)
        XCTAssertEqual(windowItems[1].state, .on) // галка у выбранной arctic
        let allItems = try XCTUnwrap(submenus.last?.submenu).items
        XCTAssertEqual(allItems.last?.state, .on) // ничего не выбрано → галка у «Как у Claude»

        click(windowItems[0])
        click(try XCTUnwrap(allItems.last))
        XCTAssertEqual(applied.map { $0.scope }, ["window", "all"])
        XCTAssertEqual(applied.map { $0.theme }, ["violet", nil])

        // Каталога нет — меню прежнее, из семи пунктов.
        let plain = MinimizeMenu.build(themes: [], windowThemeID: nil, allThemeID: nil,
                                       perform: { _ in }, applyTheme: { _, _ in })
        XCTAssertTrue(plain.items.allSatisfy { !$0.hasSubmenu })
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

    /// Нажатие на пункт меню без popUp: BlockMenuItem держит замыкание на себе.
    private func click(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target as? NSObject else {
            return XCTFail("у пункта «\(item.title)» нет действия")
        }
        target.perform(action)
    }
}
