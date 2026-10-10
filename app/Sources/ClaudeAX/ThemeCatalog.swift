import Foundation

/// Набор меню: три коротких списка цветов вместо одного длинного (слово Элвиса 12.09:
/// «мне надо будет три списка, не один длинный», задача #5801). Признак ТОЛЬКО для
/// приложения: в команду `theme` набор не уезжает и страница про наборы не знает — яркие
/// «Лимонад» и «Апельсин» остаются для неё светлыми по `type`, как любая светлая тема.
enum ThemeSet: String, CaseIterable {
    case dark
    case light
    case bright
    /// «Opus 5.5» (#7181, слово Элвиса 23.09: «Opus 5.5 — четвёртая категория темы, и все свои
    /// новые темы туда засунь») — десять тёмных тем по вкусу Элвиса вместо двенадцати «Ночных»
    /// (#7106: прежние темы Элвису не нравились — скучные). Четвёртый список последним, три прежних на своих
    /// местах. Окна с ночной темой не ломаются: палитра лежит в записи окна целиком.
    case opus
}

/// Тема окна Claude из `claude-patch/themes.json` (каталог пишет батч A). Формат sol из ElvisOS:
/// `{"version":1,"themes":[{"id","name","type","set"?,"palette":{accent,background,foreground,sidebar,panel,muted}}]}`.
/// Палитру Swift не разбирает: она целиком уезжает в command.json, CSS делает страница.
struct Theme: Equatable {
    let id: String
    let name: String
    /// «dark» или «light» — по нему страница ставит `color-scheme`.
    let type: String
    /// В каком списке меню тема живёт. Поля нет — набор берётся из `type`: так все
    /// двадцать четыре старых цвета остались там же, где стояли.
    let set: ThemeSet
    let palette: [String: String]

    init(id: String, name: String, type: String, set: ThemeSet? = nil,
         palette: [String: String]) {
        self.id = id
        self.name = name
        self.type = type
        self.set = set ?? (type == "light" ? .light : .dark)
        self.palette = palette
    }

    /// Порядок ключей палитры в команде — как в контракте (п. 5 плана WF6); неизвестные идут
    /// следом по алфавиту.
    static let paletteOrder = ["accent", "background", "foreground", "sidebar", "panel", "muted"]

    /// Палитра как объект команды (её же пишет my-themes.json).
    var paletteValue: CommandValue {
        var keys = Theme.paletteOrder.filter { palette[$0] != nil }
        keys += palette.keys.filter { !Theme.paletteOrder.contains($0) }.sorted()
        return .object(keys.map { (key: $0, value: .string(palette[$0] ?? "")) })
    }

    /// Тема как вложенный объект command.json: `{id, name, type, palette}`.
    var commandValue: CommandValue {
        .object([
            (key: "id", value: .string(id)),
            (key: "name", value: .string(name)),
            (key: "type", value: .string(type)),
            (key: "palette", value: paletteValue),
        ])
    }

    /// Светлая ли тема для СТРАНИЦЫ (`color-scheme`). Со списком меню не путать: яркие
    /// «Лимонад» и «Апельсин» светлые и при этом лежат в наборе «Яркие».
    var isLight: Bool { type == "light" }
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
            return Theme(id: id, name: name, type: item["type"] as? String ?? "dark",
                         set: (item["set"] as? String).flatMap(ThemeSet.init(rawValue:)),
                         palette: palette)
        }
    }
}

/// Слой `look` (план WF83, #7178–#7180): независимые эффекты окна — «Живой фон» (`aurora`) и
/// «Плотный текст» (`dense`). В команде `theme` идёт сразу после `frame`, объектом ЦЕЛИКОМ
/// (отсутствующий ключ страница читает как false), а «ни одного эффекта» — это сброс слоя
/// (`"look":null`), не одни false.
///
/// «Неон и ретро-экран» (`neon`) снят в WF220 (слово Элвиса 10.10.2026, #9440): ключ в объекте
/// команды остаётся по контракту и всегда false, из старых файлов и defaults не читается — у кого
/// он был включён, тот получает вид без него.
struct Look: Equatable {
    var aurora = false
    var dense = false
    /// Схема цвета живого фона (WF146, `look.scheme`): id из `LookScheme.all`; nil — умолчание («violet»),
    /// и ключа в объекте нет. Не эффект: пустоту вида не меняет.
    var scheme: String?

    /// Эффект — он же ключ объекта в команде, в `window-themes.json` и в `.pimpmyclaude.json`.
    enum Effect: String, CaseIterable {
        case aurora, dense
    }

    /// Порядок ключей объекта — как в контракте плана WF83; `neon` — снятый эффект, всегда false.
    static let keys = ["aurora", "neon", "dense"]

    var isEmpty: Bool { !aurora && !dense }

    subscript(effect: Effect) -> Bool {
        get {
            switch effect {
            case .aurora: return aurora
            case .dense: return dense
            }
        }
        set {
            switch effect {
            case .aurora: aurora = newValue
            case .dense: dense = newValue
            }
        }
    }

    /// Тот же вид с одним эффектом, поставленным в `on`.
    func with(_ effect: Effect, _ on: Bool) -> Look {
        var copy = self
        copy[effect] = on
        return copy
    }

    /// Слой из вида: пустой вид — сброс, как у выключенной рамки.
    var layer: Layer<Look> { isEmpty ? .reset : .set(self) }

    /// Ключ схемы в объекте вида — последним, после трёх эффектов (контракт WF146).
    static let schemeKey = "scheme"

    /// Вид как объект команды: все три ключа, по порядку контракта, и `scheme` последним — только если задана.
    var commandValue: CommandValue {
        var fields = Self.keys.map { key in
            (key: key, value: CommandValue.bool(Effect(rawValue: key).map { self[$0] } ?? false))
        }
        if let scheme = scheme { fields.append((key: Self.schemeKey, value: .string(scheme))) }
        return .object(fields)
    }

    /// Вид из JSON или defaults: объект с булевыми; не объект — nil, чужой тип у ключа — false; схема — только
    /// известная и не умолчание (как `normalizeLook` страницы).
    static func from(_ raw: Any?) -> Look? {
        guard let values = raw as? [String: Any] else { return nil }
        var look = Look()
        for effect in Effect.allCases { look[effect] = values[effect.rawValue] as? Bool ?? false }
        look.scheme = LookScheme.normalized(values[schemeKey] as? String)
        return look
    }

    /// Вид для defaults: только включённые эффекты и схема, если задана.
    var defaultsValue: [String: Any] {
        var out: [String: Any] = [:]
        for effect in Effect.allCases where self[effect] { out[effect.rawValue] = true }
        if let scheme = scheme { out[Self.schemeKey] = scheme }
        return out
    }

    /// Тот же вид с живым фоном и схемой `id` (умолчание и чужое — без ключа): пункт «🎨 Схема ▸» и образцы панели
    /// включают живой фон вместе с выбором.
    func withScheme(_ id: String) -> Look {
        var copy = with(.aurora, true)
        copy.scheme = LookScheme.normalized(id)
        return copy
    }

    /// Действующая схема для галки: нет ключа — умолчание.
    var schemeID: String { scheme ?? LookScheme.defaultID }
}

/// Схемы цвета живого фона (WF146, #9107) — копия `LOOK_SCHEMES` страницы (`claude-patch/inject.js`), порядок —
/// порядок меню; сверку держит `LookSchemeWF145Tests`. Тона — четыре пятна (a, b, c, d); у «Как у темы» их нет:
/// страница берёт акцент темы окна.
public struct LookScheme: Equatable {
    public let id: String
    public let name: String
    public let tones: [String]?

    public static let defaultID = "violet"

    public static let all: [LookScheme] = [
        LookScheme(id: "violet", name: "Фиолетовые сумерки", tones: ["#a47cf0", "#6f80ea", "#cf82c8", "#8a84b8"]),
        LookScheme(id: "aurora", name: "Северное сияние", tones: ["#4ccfb2", "#68c98e", "#4f8fe0", "#6aa9a2"]),
        LookScheme(id: "sea", name: "Глубокое море", tones: ["#2f7fb8", "#2a5f9a", "#3fa3a8", "#56728e"]),
        LookScheme(id: "lavender", name: "Лаванда", tones: ["#b29ee6", "#98a4e0", "#d4a6d6", "#a69bc0"]),
        LookScheme(id: "sunset", name: "Закат", tones: ["#e6a07c", "#d68a9e", "#c79fc2", "#b08a82"]),
        LookScheme(id: "forest", name: "Лес", tones: ["#7f9f6a", "#9cb89a", "#5f8f7a", "#8a9a78"]),
        LookScheme(id: "graphite", name: "Графит", tones: ["#8a929c", "#a3a7ae", "#767e88", "#9a9590"]),
        LookScheme(id: "theme", name: "Как у темы", tones: nil),
    ]

    /// Id для записи: известная схема, кроме умолчания; иначе nil (ключа нет).
    public static func normalized(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespaces), id != defaultID,
              all.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}

/// Минимум от UserDefaults — чтобы тесты не писали в живые настройки приложения.
protocol ThemeDefaults: AnyObject {
    func string(forKey key: String) -> String?
    func dictionary(forKey key: String) -> [String: Any]?
    /// Слой рамки — булев, и «записи нет» надо отличать от «выключена»: `bool(forKey:)`
    /// у UserDefaults вернул бы false в обоих случаях.
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: ThemeDefaults {}

/// Что выбрано в подменю «Тема», «Шрифт», «Размер…» и в пунктах вида — только для галки
/// в меню; красит страница. Слои независимы, у каждого своя пара ключей:
/// `themeByWindow`/`themeAll`, `fontByWindow`/`fontAll`, `sizeByWindow`/`sizeAll`,
/// `lookByWindow`/`lookAll`. Production window keys are stable `c:<chat>` or `n:<CGID>`;
/// old title keys migrate only after a unique current native identity is proven.
final class ThemeStore {
    static let byWindowKey = "themeByWindow"
    static let allKey = "themeAll"
    static let fontByWindowKey = "fontByWindow"
    static let fontAllKey = "fontAll"
    /// Размер — слой с двумя половинами, поэтому в defaults он лежит словарём
    /// `{заголовок: {answer, question}}`, а «всем окнам» — просто `{answer, question}`.
    static let sizeByWindowKey = "sizeByWindow"
    static let sizeAllKey = "sizeAll"
    /// Вид (план WF83): в карте окна — словарь включённых эффектов, пустой вид выпадает.
    static let lookByWindowKey = "lookByWindow"
    static let lookAllKey = "lookAll"
    /// Последняя раскладка «Расставить» (план WF21): строка `Mode.rawValue`.
    static let arrangeModeKey = "arrangeMode"

    private let defaults: ThemeDefaults

    init(defaults: ThemeDefaults = UserDefaults.standard) { self.defaults = defaults }

    /// Called only after a current native census proves the old title belongs to one window.
    func migrateWindow(title: String, to identity: String) {
        guard !title.isEmpty, !identity.isEmpty, title != identity else { return }
        for key in [Self.byWindowKey, Self.fontByWindowKey, Self.sizeByWindowKey, Self.lookByWindowKey] {
            var values = rawMap(key)
            guard let old = values[title] else { continue }
            if values[identity] == nil { values[identity] = old }
            values.removeValue(forKey: title)
            defaults.set(values, forKey: key)
        }
    }

    /// Карта «заголовок окна → значение слоя»: у темы и шрифта это id, у размера — словарь
    /// половин, у рамки — булево.
    private func rawMap(_ key: String) -> [String: Any] { defaults.dictionary(forKey: key) ?? [:] }

    private func map(_ key: String) -> [String: String] {
        rawMap(key).compactMapValues { $0 as? String }
    }

    /// Окно без заголовка адресуется страницей как «то, что в фокусе» — запоминать его нечем.
    private func windowID(_ key: String, title: String) -> String? {
        title.isEmpty ? nil : map(key)[title]
    }

    private func windowValue(_ key: String, title: String) -> Any? {
        title.isEmpty ? nil : rawMap(key)[title]
    }

    private func setWindow(_ value: Any?, title: String, key: String) {
        guard !title.isEmpty else { return }
        var values = rawMap(key)
        if let value = value { values[title] = value } else { values.removeValue(forKey: title) }
        if values.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(values, forKey: key)
        }
    }

    private func setAll(_ id: String?, key: String) {
        if let id = id {
            defaults.set(id, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func windowThemeID(title: String) -> String? { windowID(ThemeStore.byWindowKey, title: title) }
    func windowFontID(title: String) -> String? { windowID(ThemeStore.fontByWindowKey, title: title) }

    var allThemeID: String? { defaults.string(forKey: ThemeStore.allKey) }
    var allFontID: String? { defaults.string(forKey: ThemeStore.fontAllKey) }

    func setWindowTheme(_ id: String?, title: String) {
        setWindow(id, title: title, key: ThemeStore.byWindowKey)
    }

    func setWindowFont(_ id: String?, title: String) {
        setWindow(id, title: title, key: ThemeStore.fontByWindowKey)
    }

    /// «Всем окнам» на странице чистит в карте ТОЛЬКО свой слой (контракт п. 5 плана WF6):
    /// тема всем окнам не трогает их шрифты и наоборот. Галки обязаны это повторить.
    func clearWindowThemes() { defaults.removeObject(forKey: ThemeStore.byWindowKey) }
    func clearWindowFonts() { defaults.removeObject(forKey: ThemeStore.fontByWindowKey) }
    func clearWindowSizes() { defaults.removeObject(forKey: ThemeStore.sizeByWindowKey) }
    func clearWindowLooks() { defaults.removeObject(forKey: ThemeStore.lookByWindowKey) }

    func setAllTheme(_ id: String?) { setAll(id, key: ThemeStore.allKey) }
    func setAllFont(_ id: String?) { setAll(id, key: ThemeStore.fontAllKey) }

    // MARK: - размер (план WF12)

    /// Кегль из записи defaults; половины без годного числа выпадают, пустая запись — nil.
    static func size(_ raw: Any?) -> Size? {
        guard let values = raw as? [String: Any] else { return nil }
        func px(_ key: String) -> Int? {
            (values[key] as? NSNumber)?.intValue ?? values[key] as? Int
        }
        let size = Size(answer: px(Size.answerKey), question: px(Size.questionKey))
        return size.isEmpty ? nil : size
    }

    private static func values(_ size: Size) -> [String: Int] {
        var out: [String: Int] = [:]
        if let answer = size.answer { out[Size.answerKey] = answer }
        if let question = size.question { out[Size.questionKey] = question }
        return out
    }

    func windowSize(title: String) -> Size? {
        ThemeStore.size(windowValue(ThemeStore.sizeByWindowKey, title: title))
    }

    var allSize: Size? { ThemeStore.size(defaults.dictionary(forKey: ThemeStore.sizeAllKey)) }

    /// nil — записи о размере больше нет («Как у Claude» снимает слой целиком).
    func setWindowSize(_ size: Size?, title: String) {
        setWindow(size.map { ThemeStore.values($0) }, title: title, key: ThemeStore.sizeByWindowKey)
    }

    func setAllSize(_ size: Size?) {
        if let size = size {
            defaults.set(ThemeStore.values(size), forKey: ThemeStore.sizeAllKey)
        } else {
            defaults.removeObject(forKey: ThemeStore.sizeAllKey)
        }
    }

    // MARK: - вид (план WF83)

    /// Вид окна: записи нет — все эффекты выключены.
    func windowLook(title: String) -> Look {
        Look.from(windowValue(ThemeStore.lookByWindowKey, title: title)) ?? Look()
    }

    var allLook: Look { Look.from(defaults.dictionary(forKey: ThemeStore.lookAllKey)) ?? Look() }

    /// Вид, который окно носит сейчас: своя запись, а её нет — «всем окнам» (страница так же: окно, иначе `*`).
    /// От него меню окна ставит галки и шлёт вид целиком — иначе «Плотный текст» в окне снимал «Живой» (#9182).
    func effectiveWindowLook(title: String) -> Look {
        let own = windowLook(title: title)
        return own.isEmpty ? allLook : own
    }

    /// nil или пустой вид — записи окна больше нет.
    func setWindowLook(_ look: Look?, title: String) {
        let value = look.flatMap { $0.isEmpty ? nil : $0.defaultsValue }
        setWindow(value, title: title, key: ThemeStore.lookByWindowKey)
    }

    func setAllLook(_ look: Look?) {
        if let look = look, !look.isEmpty {
            defaults.set(look.defaultsValue, forKey: ThemeStore.lookAllKey)
        } else {
            defaults.removeObject(forKey: ThemeStore.lookAllKey)
        }
    }

    // MARK: - раскладка окон (план WF21)

    /// Последняя выбранная раскладка: её повторяют ⌥⌘A и «▦ Расставить», её же берёт канал
    /// на `layout: "last"`. Закрепляют выбор плитка меню и запрос канала с конкретной
    /// раскладкой. Записи нет или в ней чужое слово — лента, как было до WF21.
    var arrangeMode: ArrangeLayout.Mode {
        get {
            defaults.string(forKey: ThemeStore.arrangeModeKey)
                .flatMap(ArrangeLayout.Mode.init(rawValue:)) ?? .ribbon
        }
        set { defaults.set(newValue.rawValue, forKey: ThemeStore.arrangeModeKey) }
    }
}
