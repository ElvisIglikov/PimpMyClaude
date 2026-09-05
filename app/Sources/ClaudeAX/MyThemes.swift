import Foundation

/// «Моя тема» — пара «палитра + шрифт» под своим именем (план п. 4). Палитра копируется
/// целиком в момент сохранения, поэтому своя тема живёт дальше, даже если каталог сменится.
/// Взять её можно из каталога («💾 Сохранить как мою тему…») или собрать ползунками
/// («🎚 Своя тема…», план WF20) — во втором случае рядом ложатся и сами ручки.
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
/// `{"version":1,"themes":[{id,name,type,palette,font,size,frame[,knobs]}]}`. Читается на каждый
/// показ меню (файл правит и сам Элвис), битый файл → пустой список: меню обязано остаться живым.
/// `knobs` необязательно и пишется последним; `"knobs":null` не пишется никогда.
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
    /// Имя занято своей темой (после `clean`, регистронезависимо) — перезаписываем её слои,
    /// сохраняя id и место в списке: это и есть «изменить свою тему» (задача #5364), галка
    /// в меню не съезжает, а применённая тема остаётся применённой. Спрашивает про перезапись
    /// вызывающий (`MinimizeMenu.saveMyTheme`), здесь только запись.
    /// Возвращает новый список (nil — не записалось).
    @discardableResult
    func add(name: String, theme: Theme, font: Font?, size: Size? = nil, frame: Bool = false,
             knobs: ThemeKnobs? = nil,
             now: TimeInterval = Date().timeIntervalSince1970) -> [MyTheme]? {
        let clean = MyThemesStore.clean(name: name)
        guard !clean.isEmpty else { return nil }
        let stored = load()
        let my = MyTheme(id: MyThemesStore.matching(name: clean, in: stored)?.id
                             ?? MyThemesStore.makeID(now: now),
                         name: clean, type: theme.type, palette: theme.palette,
                         font: font, size: size, frame: frame, knobs: knobs)
        let list = MyThemesStore.appending(my, to: stored)
        return write(list) ? list : nil
    }

    /// «✏️ Изменить мою тему» (решение 1.4 плана WF20): слои записи с этим id меняются
    /// НА МЕСТЕ — id и позиция в списке сохраняются, в том числе при переименовании.
    ///
    /// Правило имени то же, что у «Сохранить как мою тему…» (критик В8): новое имя занято
    /// ДРУГОЙ записью — сливаемся в неё (её id и место), а правленую убираем, чтобы не осталось
    /// двух строк с одним именем. Спрашивает подтверждение вызывающий, здесь только запись.
    /// Возвращает записанную тему (nil — имя пустое или файл не записался).
    @discardableResult
    func update(id: String, name: String, theme: Theme, font: Font?, size: Size? = nil,
                frame: Bool = false, knobs: ThemeKnobs? = nil) -> MyTheme? {
        let clean = MyThemesStore.clean(name: name)
        guard !clean.isEmpty else { return nil }
        var stored = load()
        // Имя занято чужой записью — она и становится целью слияния.
        let owner = MyThemesStore.matching(name: clean, in: stored)?.id
        let target = owner ?? id
        if target != id { stored.removeAll { $0.id == id } }
        let my = MyTheme(id: target, name: clean, type: theme.type, palette: theme.palette,
                         font: font, size: size, frame: frame, knobs: knobs)
        return write(MyThemesStore.appending(my, to: stored)) ? my : nil
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

    /// Своя тема с таким именем (после `clean`, регистронезависимо) — её и перезаписываем.
    static func matching(name: String, in list: [MyTheme]) -> MyTheme? {
        let wanted = clean(name: name).lowercased()
        guard !wanted.isEmpty else { return nil }
        return list.first { clean(name: $0.name).lowercased() == wanted }
    }

    /// Тема с известным id — на своё место (перезапись слоёв «изменить»: галка в меню не
    /// съезжает); новая — в конец, и за лимитом уходит самая старая.
    static func appending(_ theme: MyTheme, to list: [MyTheme]) -> [MyTheme] {
        if let index = list.firstIndex(where: { $0.id == theme.id }) {
            var updated = list
            updated[index] = theme
            return updated
        }
        return Array((list + [theme]).suffix(limit))
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

    /// Тот же порядок ключей, что в команде: id, name, type, palette, font, size, frame,
    /// а `knobs` (план WF20) — последним и только когда они есть: `"knobs":null` не пишем
    /// вовсе (критик В4), иначе `contains`-проверки старых тестов и глаз Элвиса спотыкались бы
    /// о пустое поле.
    static func json(_ list: [MyTheme]) -> String {
        let items = list.map { my -> String in
            var fields: [(key: String, value: CommandValue)] = [
                (key: "id", value: .string(my.id)),
                (key: "name", value: .string(my.name)),
                (key: "type", value: .string(my.type)),
                (key: "palette", value: my.theme.paletteValue),
                (key: "font", value: my.font?.commandValue ?? .null),
                (key: "size", value: my.size?.commandValue ?? .null),
                (key: "frame", value: .bool(my.frame)),
            ]
            if let knobs = my.knobs { fields.append((key: "knobs", value: knobs.commandValue)) }
            return CommandValue.object(fields).json
        }
        return "{\"version\":1,\"themes\":[" + items.joined(separator: ",") + "]}"
    }
}
