@testable import ClaudeAX
import XCTest

/// WF245 (слово Элвиса 11.10.2026 01:40): набор тем почищен — двенадцать тем ушли из `themes.json`, плитки «Как у
/// Claude» в полосах нет. У кого убранная тема стоит, окно показывает её дальше: палитра лежит в записи окна
/// целиком (страница и `window-themes.json`), а приложение по незнакомому id ничего не сбрасывает.
final class ThemesWF245Tests: XCTestCase {
    private static let gone = ["red", "orange", "yellow", "brown", "pink", "peach", "mango", "honey", "lemonade",
                               "orangeade", "lime", "ultra"]
    /// «Красная», какой она была в каталоге: так она лежит в записи окна у того, кто её выбрал.
    private static let red = Theme(id: "red", name: "Красная", type: "dark",
                                   palette: ["accent": "#ff5c5c", "background": "#3b1414", "foreground": "#ffe4e4",
                                             "sidebar": "#2a0e0e", "panel": "#4e1d1d", "muted": "#d69a9a"])

    private var catalog: [Theme] {
        let root = Repo.root.appendingPathComponent("claude-patch")
        return ThemeCatalog.load(directory: root)
    }

    private var chips: [WindowColorChip] {
        let themes = catalog
        return ClaudeAXController.panelThemeIDs.compactMap { id in themes.first { $0.id == id } }.map(WindowColorChip.init)
    }

    func testNamedThemesLeftTheCatalogDisputedStay() {
        let ids = Set(catalog.map { $0.id })
        XCTAssertEqual(catalog.count, 33, "+ «Винная» (#9683, лист 43 ★3.3)")
        for id in Self.gone { XCTAssertFalse(ids.contains(id), "\(id) — убрана по слову Элвиса") }
        // «Зелёная» не названа однозначно, «Сиреневая» и «Фиолетовая» — с тихим фоном по листу 43, «Малиновая» и «Магма»
        // ушли из плиток (их сменила «Винная», #9683), но в каталоге остаются; тема новой установки на месте.
        for id in ["green", "crimson", "magma", "wine", "lilac", "violet", PanelColorTiles.newInstallThemeID] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertTrue(Set(ClaudeAXController.panelThemeIDs).isDisjoint(with: Self.gone))
    }

    func testStripsHaveNoPlainTileAndKeepEvenWidth() {
        let strips = PanelColorTiles.strips(chips)
        let all = strips.flatMap { $0 }
        XCTAssertEqual(all.count, 16, "#9683: «Малиновая» и «Магма» → одна «Винная»")
        XCTAssertFalse(all.contains(.plain), "«Как у Claude» — строка дополнительного оформления, не плитка")
        XCTAssertEqual(strips.map { $0.count }, [10, 6], "слово Элвиса 11.10 06:20: ряд тёмных сверху, ряд светлых снизу")
        // Группа одной полосой до потолка; сверх него — две полосы поровну, короткая последняя.
        let chip = { (index: Int) in WindowColorChip(id: "t\(index)", name: "Т", background: "#102030", accent: "#fff", light: false) }
        XCTAssertEqual(PanelColorTiles.strips((0..<18).map(chip)).map { $0.count }, [18])
        XCTAssertEqual(PanelColorTiles.strips((0..<29).map(chip)).map { $0.count }, [15, 14])
        XCTAssertEqual(all.first, .theme("coral"), "первой — «Коралл», не коричневая «Как у Claude»")
        // Обычный вид по-прежнему называется и выбирается — только не плиткой.
        XCTAssertEqual(PanelColorTiles.picked(.plain), .plain)
        XCTAssertEqual(PanelColorTiles.shownName(hovered: nil, choice: .plain, themes: chips), "Как у Claude")
        XCTAssertEqual(PanelColorTiles.plainAction, "Вернуть")
    }

    func testRemovedThemeOnWindowsBreaksNothing() {
        let themes = catalog
        // Тема всем окнам — убранная «Красная»: в полосах не выделено ничего, имя пустое, отсчёт — в цветах Claude.
        let choice = WindowColorChoice.theme("red")
        let all = PanelColorTiles.strips(chips).flatMap { $0 }
        XCTAssertEqual(all.filter { PanelColorTiles.isSelected($0, choice) }.count, 0)
        XCTAssertEqual(PanelColorTiles.shownName(hovered: nil, choice: choice, themes: themes.map(WindowColorChip.init)), "")
        XCTAssertEqual(PanelCountdown.palette(choice, themes: themes.map(WindowColorChip.init), dark: true).accent, 0xD97757)
        // Память галок её id хранит и не теряет; вид окна для файла проекта — «слой не трогаем», а не сброс.
        let store = ThemeStore(defaults: MemoryThemeDefaults())
        store.setAllTheme("red")
        store.setWindowTheme("ultra", title: "Rick")
        XCTAssertEqual(store.allThemeID, "red")
        XCTAssertEqual(store.windowThemeID(title: "Rick"), "ultra")
        let view = ProjectPaint.view(title: "Rick", themeStore: store, themes: themes, fonts: [], myThemes: [],
                                     autoPainted: nil)
        XCTAssertEqual(view.theme, .keep, "незнакомая тема в файл проекта не пишется и не сбрасывается")
    }

    func testWindowThemesFileCarriesRemovedThemeWholeForRestore() throws {
        // Зеркало тем окон держит палитру целиком — `themes-restore` вернёт «Красную» и без каталога.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf245-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(WindowThemeStore.fileName)
        let first = WindowThemeStore(url: url, now: { Date(timeIntervalSince1970: 1_790_000_000) })
        first.record(fields: ClaudeActions.themeFields(scope: MenuModel.themeScopeAll, title: "",
                                                       theme: .set(Self.red), font: .keep))
        let second = WindowThemeStore(url: url, now: { Date(timeIntervalSince1970: 1_790_000_100) })
        XCTAssertEqual(second.entries, first.entries)
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(body.contains("\"id\":\"red\""))
        XCTAssertTrue(body.contains("\"background\":\"#3b1414\""), "палитра — в файле, каталог не нужен")
    }
}
