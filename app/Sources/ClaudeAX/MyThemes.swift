import Foundation

/// «Моя тема» — пара «палитра + шрифт» под своим именем (план п. 4). Палитра копируется
/// целиком в момент сохранения, поэтому своя тема живёт дальше, даже если каталог сменится.
/// Сохранять и править свои темы было в меню жёлтой кнопки — с WF237 (#9524) нечем; надетые на окна и проекты
/// остаются, файл только читается.
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
    /// Положения ручек редактора (план WF20). Есть — панель откроется ровно там, где её
    /// оставили; нет — ручки подберутся по палитре, и панель об этом скажет.
    /// Пишутся ТОЛЬКО когда палитра получена этими же ручками (критик В4): для темы каталога
    /// ручки — догадка, и `ThemeKnobs.palette()` от них дал бы ДРУГИЕ цвета.
    let knobs: ThemeKnobs?

    init(id: String, name: String, type: String, palette: [String: String],
         font: Font?, size: Size? = nil, frame: Bool = false, knobs: ThemeKnobs? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.palette = palette
        self.font = font
        self.size = size
        self.frame = frame
        self.knobs = knobs
    }

    /// Тема для команды: id свой, `user-…`, палитра скопированная.
    var theme: Theme { Theme(id: id, name: name, type: type, palette: palette) }
}

/// Файл `~/Library/Application Support/MyClaude/my-themes.json`:
/// `{"version":1,"themes":[{id,name,type,palette,font,size,frame[,knobs]}]}`. Битый файл → пустой список.
final class MyThemesStore {
    static let fileName = "my-themes.json"
    /// Имя — как `themeText` в inject.js, не длиннее 80 знаков.
    static let nameLimit = 80
    /// Рядом с command.json: папку MyClaude заводит патч (и writeAtomic, если её ещё нет).
    static var defaultURL: URL { CommandChannel.directory.appendingPathComponent(fileName) }

    private let url: URL

    init(url: URL = MyThemesStore.defaultURL) { self.url = url }

    func load() -> [MyTheme] { MyThemesStore.parse(try? Data(contentsOf: url)) }

    // MARK: - чистая часть (её же гоняют тесты)

    static func clean(name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
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
                           frame: item["frame"] as? Bool ?? false,
                           knobs: ThemeKnobs.parse(item["knobs"]))
        }
    }
}
