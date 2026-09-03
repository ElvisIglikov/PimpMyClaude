import AppKit

/// Шрифт интерфейса Claude — второй слой темы (контракт п. 5 плана WF6):
/// `"font":{"id":"…","family":"SF Mono","mono":true}`. `family` — голое имя семейства,
/// стек и кавычки дописывает страница; `mono: true` — тот же шрифт уходит и на код.
struct Font: Equatable {
    /// Ключ для галки в меню и для ThemeStore: имя семейства в нижнем регистре через дефис.
    let id: String
    /// Имя семейства как его знает система (сюда же санитайзер контракта).
    let family: String
    let mono: Bool
    /// Как показывать в меню: `localizedNameForFamily` (в команду не уезжает).
    let displayName: String

    /// Шрифт как вложенный объект command.json: `{id, family, mono}`.
    var commandValue: CommandValue {
        .object([
            (key: "id", value: .string(id)),
            (key: "family", value: .string(family)),
            (key: "mono", value: .bool(mono)),
        ])
    }
}

/// Каталог шрифтов: белый список из плана п. 3, отфильтрованный по факту установки
/// (`NSFontManager.shared.availableFontFamilies`) и по кириллице (в семействе есть «Ж»).
/// «Системный» отдельным пунктом каталога нет: это сброс слоя (`"font":null`).
enum FontCatalog {
    /// Обычные — порядок из плана; чего нет в системе или без кириллицы, в меню не попадает.
    static let regularFamilies = [
        "Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Optima", "Georgia", "Palatino",
        "Baskerville", "Didot", "Hoefler Text", "Iowan Old Style", "Times New Roman", "Verdana",
        "Trebuchet MS", "Arial", "Tahoma", "American Typewriter", "Copperplate", "Comic Sans MS",
        "Chalkboard SE", "Noteworthy", "Marker Felt", "Bradley Hand", "Snell Roundhand", "Papyrus",
    ]

    /// Моноширинные — свой белый список, дальше добираем установленные по регулярке.
    static let monoFamilies = ["SF Mono", "Menlo", "Monaco", "Courier New", "Andale Mono", "PT Mono"]

    /// JetBrains Mono, Fira Code, Cascadia Code, IBM Plex Mono, Source Code Pro — если стоят.
    static let monoPattern = "\\b(Mono|Code|Plex)\\b"
    /// Секция «МОНОШИРИННЫЕ» — не длиннее десяти пунктов (план п. 3), белый список идёт первым.
    static let monoLimit = 10
    /// Кириллица в семействе: без «Ж» шрифт в меню не показываем.
    static let cyrillicProbe: Unicode.Scalar = "Ж"

    /// Каталог считается один раз за запуск: меню всплывает по наведению, опрашивать
    /// NSFontManager на каждый показ незачем (список шрифтов при работе не меняется).
    static let available: [Font] = build()

    /// Санитайзер имени семейства из контракта: только `[A-Za-z0-9 -]`, не длиннее 60 знаков.
    /// Не прошло — семейства в меню нет (в команду кривое имя не уедет).
    static func sanitize(family: String) -> String? {
        let trimmed = family.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return nil }
        let allowed = trimmed.allSatisfy { char in
            char == " " || char == "-" || (char.isASCII && (char.isLetter || char.isNumber))
        }
        return allowed ? trimmed : nil
    }

    /// Ключ семейства: «SF Mono» → «sf-mono».
    static func id(for family: String) -> String {
        var out = ""
        for char in family.lowercased() {
            if char.isLetter || char.isNumber {
                out.append(char)
            } else if !out.isEmpty, !out.hasSuffix("-") {
                out.append("-")
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    static func hasCyrillic(_ family: String) -> Bool {
        guard let font = NSFont(name: family, size: 13) else { return false }
        return font.coveredCharacterSet.contains(cyrillicProbe)
    }

    static func localizedName(_ family: String) -> String {
        let name = NSFontManager.shared.localizedName(forFamily: family, face: nil)
        return name.isEmpty ? family : name
    }

    static func matchesMono(_ family: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: monoPattern) else { return false }
        let range = NSRange(family.startIndex..<family.endIndex, in: family)
        return regex.firstMatch(in: family, range: range) != nil
    }

    /// Обычные (в порядке белого списка), затем моноширинные — секции меню режет по флагу `mono`.
    static func build(installed: [String] = NSFontManager.shared.availableFontFamilies,
                      coversCyrillic: (String) -> Bool = FontCatalog.hasCyrillic,
                      displayName: (String) -> String = FontCatalog.localizedName) -> [Font] {
        let present = Set(installed)
        func make(_ family: String, mono: Bool) -> Font? {
            // SF Mono — системный, в availableFontFamilies его нет, но NSFont по имени его находит
            // (SFMono-Regular); Chromium резолвит «SF Mono» так же. Пускаем, если шрифт отвечает.
            let installed = present.contains(family) || (family == "SF Mono" && NSFont(name: "SFMono-Regular", size: 13) != nil)
            guard installed, let clean = sanitize(family: family),
                  coversCyrillic(family) else { return nil }
            return Font(id: id(for: clean), family: clean, mono: mono, displayName: displayName(clean))
        }

        var fonts = regularFamilies.compactMap { make($0, mono: false) }
        var mono = monoFamilies.compactMap { make($0, mono: true) }
        if mono.count < monoLimit {
            let known = Set(monoFamilies)
            for family in installed.filter({ !known.contains($0) && matchesMono($0) }).sorted() {
                guard mono.count < monoLimit else { break }
                if let font = make(family, mono: true) { mono.append(font) }
            }
        }
        fonts += mono
        return fonts
    }
}
