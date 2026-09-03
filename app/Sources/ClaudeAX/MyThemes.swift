import Foundation

/// «Моя тема» — пара «встроенная палитра + шрифт» под своим именем (план п. 4).
/// Редактора цветов нет: палитра копируется из каталога в момент сохранения, поэтому
/// своя тема живёт дальше, даже если каталог сменится.
struct MyTheme: Equatable {
    /// `user-<миллисекунды>` — по нему же ставится галка в меню (ThemeStore ключуется по id).
    let id: String
    let name: String
    let type: String
    let palette: [String: String]
    /// Шрифта может не быть: тогда своя тема слой шрифта не трогает.
    let font: Font?
    /// Размера тоже может не быть — слой не трогаем (план WF12 п. 1).
    let size: Size?
    /// Рамка сохраняется только включённой: `false` значит «в паре её нет», и применение
    /// своей темы чужую рамку не гасит — как и с пустым шрифтом.
    let frame: Bool

    init(id: String, name: String, type: String, palette: [String: String],
         font: Font?, size: Size? = nil, frame: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.palette = palette
        self.font = font
        self.size = size
        self.frame = frame
    }

    /// Тема для команды: id свой, `user-…`, палитра скопированная.
    var theme: Theme { Theme(id: id, name: name, type: type, palette: palette) }
}

/// Файл `~/Library/Application Support/MyClaude/my-themes.json`:
/// `{"version":1,"themes":[{id,name,type,palette,font,size,frame}]}`. Читается на каждый показ меню
/// (файл правит и сам Элвис), битый файл → пустой список: меню обязано остаться живым.
final class MyThemesStore {
    static let fileName = "my-themes.json"
    /// Больше двадцати своих тем меню не переживёт: самая старая уступает место новой.
    static let limit = 20
    /// Имя — как `themeText` в inject.js, не длиннее 80 знаков.
    static let nameLimit = 80
    /// Рядом с command.json: папку MyClaude заводит патч (и writeAtomic, если её ещё нет).
    static var defaultURL: URL { CommandChannel.directory.appendingPathComponent(fileName) }

    private let url: URL

    init(url: URL = MyThemesStore.defaultURL) { self.url = url }

    func load() -> [MyTheme] { MyThemesStore.parse(try? Data(contentsOf: url)) }

    /// Сохранить последний применённый набор слоёв под именем (цвет, шрифт, размер, рамка).
    /// Возвращает новый список (nil — не записалось).
    @discardableResult
    func add(name: String, theme: Theme, font: Font?, size: Size? = nil, frame: Bool = false,
             now: TimeInterval = Date().timeIntervalSince1970) -> [MyTheme]? {
        let my = MyTheme(id: MyThemesStore.makeID(now: now), name: MyThemesStore.clean(name: name),
                         type: theme.type, palette: theme.palette, font: font, size: size, frame: frame)
        guard !my.name.isEmpty else { return nil }
        let list = MyThemesStore.appending(my, to: load())
        return write(list) ? list : nil
    }

    @discardableResult
    func delete(id: String) -> [MyTheme]? {
        let list = load().filter { $0.id != id }
        return write(list) ? list : nil
    }

    private func write(_ list: [MyTheme]) -> Bool {
        CommandChannel.writeAtomic(url, MyThemesStore.json(list))
    }

    // MARK: - чистая часть (её же гоняют тесты)

    static func makeID(now: TimeInterval) -> String { "user-\(Int(now * 1000))" }

    static func clean(name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
    }

    /// Новая тема в конец; за лимитом уходит самая старая.
    static func appending(_ theme: MyTheme, to list: [MyTheme]) -> [MyTheme] {
        Array((list.filter { $0.id != theme.id } + [theme]).suffix(limit))
    }

    /// Запись без id, имени или палитры пропускается — из-за одной кривой строки не должен
    /// пропасть весь список. Шрифт без годного имени семейства просто не читается.
    static func parse(_ data: Data?) -> [MyTheme] {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["themes"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let id = item["id"] as? String, !id.isEmpty,
                  let name = item["name"] as? String, !clean(name: name).isEmpty,
                  let palette = item["palette"] as? [String: String], !palette.isEmpty else { return nil }
            var font: Font?
            if let raw = item["font"] as? [String: Any],
               let family = raw["family"] as? String,
               let clean = FontCatalog.sanitize(family: family) {
                let mono = raw["mono"] as? Bool ?? false
                font = Font(id: raw["id"] as? String ?? FontCatalog.id(for: clean), family: clean,
                            category: FontCatalog.category(family: clean, mono: mono),
                            displayName: FontCatalog.localizedName(clean))
            }
            return MyTheme(id: id, name: clean(name: name), type: item["type"] as? String ?? "dark",
                           palette: palette, font: font, size: ThemeStore.size(item["size"]),
                           frame: item["frame"] as? Bool ?? false)
        }
    }

    /// Тот же порядок ключей, что в команде: id, name, type, palette, font, size, frame.
    static func json(_ list: [MyTheme]) -> String {
        let items = list.map { my -> String in
            CommandValue.object([
                (key: "id", value: .string(my.id)),
                (key: "name", value: .string(my.name)),
                (key: "type", value: .string(my.type)),
                (key: "palette", value: my.theme.paletteValue),
                (key: "font", value: my.font?.commandValue ?? .null),
                (key: "size", value: my.size?.commandValue ?? .null),
                (key: "frame", value: .bool(my.frame)),
            ]).json
        }
        return "{\"version\":1,\"themes\":[" + items.joined(separator: ",") + "]}"
    }
}
