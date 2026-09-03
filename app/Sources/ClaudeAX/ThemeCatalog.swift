import Foundation

/// Тема окна Claude из `claude-patch/themes.json` (каталог пишет батч A). Формат sol из ElvisOS:
/// `{"version":1,"themes":[{"id","name","type","palette":{accent,background,foreground,sidebar,panel,muted}}]}`.
/// Палитру Swift не разбирает: она целиком уезжает в command.json, CSS делает страница.
struct Theme: Equatable {
    let id: String
    let name: String
    /// «dark» или «light» — по нему страница ставит `color-scheme`.
    let type: String
    let palette: [String: String]

    /// Порядок ключей палитры в команде — как в контракте (п. 3 плана); неизвестные идут следом по алфавиту.
    static let paletteOrder = ["accent", "background", "foreground", "sidebar", "panel", "muted"]

    /// Тема как вложенный объект command.json: `{id, name, type, palette}`.
    var commandValue: CommandValue {
        var keys = Theme.paletteOrder.filter { palette[$0] != nil }
        keys += palette.keys.filter { !Theme.paletteOrder.contains($0) }.sorted()
        return .object([
            (key: "id", value: .string(id)),
            (key: "name", value: .string(name)),
            (key: "type", value: .string(type)),
            (key: "palette", value: .object(keys.map { (key: $0, value: .string(palette[$0] ?? "")) })),
        ])
    }
}

/// Каталог тем: `themes.json` из ресурсов .app (кладёт tools/bundle.sh рядом с inject.js).
/// Файла нет или он битый — каталог пуст, подменю тем в меню кнопки не появляется.
enum ThemeCatalog {
    static let fileName = "themes.json"

    /// Ресурсы .app; PIMPMYCLAUDE_RESOURCES — та же подмена, что у патчера (удобно на гейте).
    static var resourcesDirectory: URL? {
        if let override = ProcessInfo.processInfo.environment["PIMPMYCLAUDE_RESOURCES"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Bundle.main.resourceURL
    }

    /// Каталог из бандла. Читается один раз за запуск: меню всплывает по наведению, файл там не место.
    static let bundled: [Theme] = load()

    static func load(directory: URL? = resourcesDirectory) -> [Theme] {
        guard let url = directory?.appendingPathComponent(fileName) else {
            NSLog("PimpMyClaude: папка ресурсов не найдена — темы недоступны")
            return []
        }
        guard let data = try? Data(contentsOf: url) else {
            NSLog("PimpMyClaude: нет %@ — темы недоступны", url.path)
            return []
        }
        let themes = parse(data)
        if themes.isEmpty { NSLog("PimpMyClaude: %@ не дал ни одной темы", url.path) }
        return themes
    }

    /// Разбор каталога. Запись без id, имени или палитры пропускаем: из-за одной кривой темы
    /// меню не должно остаться без всех остальных.
    static func parse(_ data: Data) -> [Theme] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["themes"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let id = item["id"] as? String, !id.isEmpty,
                  let name = item["name"] as? String, !name.isEmpty,
                  let palette = item["palette"] as? [String: String], !palette.isEmpty else { return nil }
            return Theme(id: id, name: name, type: item["type"] as? String ?? "dark", palette: palette)
        }
    }
}

/// Минимум от UserDefaults — чтобы тесты не писали в живые настройки приложения.
protocol ThemeDefaults: AnyObject {
    func string(forKey key: String) -> String?
    func dictionary(forKey key: String) -> [String: Any]?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: ThemeDefaults {}

/// Что выбрано в подменю тем — только для галки в меню; тему применяет страница.
/// Ключи: `themeByWindow` — карта [заголовок окна: id темы], `themeAll` — id темы для всех окон.
///
/// Страница хранит тему главного окна под ключом «main» (его заголовок меняется вместе с чатом),
/// а Swift знает про окно только AX-заголовок — значит, у главного окна галка может разойтись
/// с реальной темой. На саму команду это не влияет: тема применяется всё равно.
final class ThemeStore {
    static let byWindowKey = "themeByWindow"
    static let allKey = "themeAll"

    private let defaults: ThemeDefaults

    init(defaults: ThemeDefaults = UserDefaults.standard) { self.defaults = defaults }

    private var byWindow: [String: String] {
        (defaults.dictionary(forKey: ThemeStore.byWindowKey) ?? [:]).compactMapValues { $0 as? String }
    }

    /// Окно без заголовка адресуется страницей как «то, что в фокусе» — запоминать его нечем.
    func windowThemeID(title: String) -> String? {
        title.isEmpty ? nil : byWindow[title]
    }

    var allThemeID: String? { defaults.string(forKey: ThemeStore.allKey) }

    func setWindowTheme(_ id: String?, title: String) {
        guard !title.isEmpty else { return }
        var map = byWindow
        if let id = id { map[title] = id } else { map.removeValue(forKey: title) }
        if map.isEmpty {
            defaults.removeObject(forKey: ThemeStore.byWindowKey)
        } else {
            defaults.set(map, forKey: ThemeStore.byWindowKey)
        }
    }

    /// «Тема всех окон» на странице стирает карту окон целиком (runThemeCommand в inject.js) —
    /// галки в подменю обязаны это повторить, иначе покажут тему, которой уже нет.
    func clearWindowThemes() { defaults.removeObject(forKey: ThemeStore.byWindowKey) }

    func setAllTheme(_ id: String?) {
        if let id = id {
            defaults.set(id, forKey: ThemeStore.allKey)
        } else {
            defaults.removeObject(forKey: ThemeStore.allKey)
        }
    }
}
