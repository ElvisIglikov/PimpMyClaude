import AppKit

/// Шрифт интерфейса Claude — второй слой темы (контракт п. 5 плана WF6):
/// `"font":{"id":"…","family":"SF Mono","mono":true}`. `family` — голое имя семейства,
/// стек и кавычки дописывает страница; `mono: true` — тот же шрифт уходит и на код.
struct Font: Equatable {
    /// Ключ для галки в меню и для ThemeStore: имя семейства в нижнем регистре через дефис.
    let id: String
    /// Имя семейства как его знает система (сюда же санитайзер контракта).
    let family: String
    /// Секция подменю (решение 7 плана WF9); в команду не уезжает — там только `mono`.
    let category: FontCategory
    /// Как показывать в меню: `localizedNameForFamily` (в команду не уезжает).
    let displayName: String

    /// В контракте остаётся булево `mono`: моноширинный шрифт страница ставит и на код.
    var mono: Bool { category == .mono }

    /// Шрифт как вложенный объект command.json: `{id, family, mono}`.
    var commandValue: CommandValue {
        .object([
            (key: "id", value: .string(id)),
            (key: "family", value: .string(family)),
            (key: "mono", value: .bool(mono)),
        ])
    }
}

/// Секция подменю «Шрифт» (решение 7 плана WF9). Порядок case — порядок секций в меню.
enum FontCategory: String, CaseIterable {
    case serif, sans, hand, mono
}

/// Кегль текста сообщений — третий слой темы (контракт п. 1 плана WF12):
/// `"size":{"answer":15,"question":14}` в пикселях. Половинки независимы: половины, которой
/// в команде нет, страница не трогает (`runThemeCommand` доклеивает её из хранилища).
///
/// Здесь это тип ХРАНЕНИЯ: галки меню, `ThemeStore`, «моя тема», вид проекта. Слой команды —
/// `SizeLayer` (решение 1 плана WF19): он умеет и снять ОДНУ половину (`{"answer":null}`),
/// поэтому «Как у Claude» в «Размер ответов ▸» больше не уносит с собой размер вопросов.
struct Size: Equatable {
    /// Ответы Claude и свои вопросы; nil — половину не трогаем.
    let answer: Int?
    let question: Int?

    /// Границы контракта (SIZE_MIN…SIZE_MAX в inject.js): мельче 11 не прочесть,
    /// крупнее 24 — уже не текст, а плакат.
    static let minPx = 11
    static let maxPx = 24
    /// Что предлагает меню (план WF12 п. 2).
    static let steps = [12, 13, 14, 15, 16, 18, 20]
    /// Ключи половин — и в команде, и в UserDefaults.
    static let answerKey = "answer"
    static let questionKey = "question"

    init(answer: Int? = nil, question: Int? = nil) {
        self.answer = answer.map(Size.clamp)
        self.question = question.map(Size.clamp)
    }

    static func clamp(_ px: Int) -> Int { min(max(px, minPx), maxPx) }

    /// Ни одной половины: слать нечего — страница поняла бы пустой объект как «сброс».
    var isEmpty: Bool { answer == nil && question == nil }

    /// Слой поверх запомненного: половина, которой в команде нет, остаётся прежней —
    /// ровно так же слой склеивает страница.
    func merging(_ other: Size) -> Size {
        Size(answer: other.answer ?? answer, question: other.question ?? question)
    }

    /// Слой как вложенный объект command.json: только заданные половины, ответы первыми.
    var commandValue: CommandValue {
        var fields: [(key: String, value: CommandValue)] = []
        if let answer = answer { fields.append((key: Size.answerKey, value: .number(answer))) }
        if let question = question { fields.append((key: Size.questionKey, value: .number(question))) }
        return .object(fields)
    }

    /// Половина слоя: у каждой своё подменю («Размер ответов ▸», «Размер вопросов ▸»),
    /// свои галки и своя примерка.
    enum Half: CaseIterable {
        case answer, question
    }

    /// Слой из одной половины — пункт меню трогает ровно её.
    static func one(_ half: Half, _ px: Int) -> Size {
        half == .answer ? Size(answer: px) : Size(question: px)
    }

    func value(_ half: Half) -> Int? { half == .answer ? answer : question }
}

/// Слой размера в КОМАНДЕ (решение 1 плана WF19). У размера две половины, и «Как у Claude»
/// в «Размер ответов ▸» обязан снимать только свою. Пара `Layer<Int>` вместо `Layer<Size>`
/// потому, что `"size":null` (сброс слоя целиком, «🧹 Всё как у Claude») — это ДРУГИЕ байты,
/// чем `{"answer":null,"question":null}` (критик Б1).
///
/// - `keep` — поля `size` в команде нет вовсе, слой не трогаем;
/// - `reset` — `"size":null`, снять обе половины;
/// - `halves` — объект: половина `.keep` в него не пишется, `.set` уходит числом, `.reset` —
///   `null` («снять эту половину»). Обе половины `.keep` — поля снова нет вовсе: пустой
///   объект страница прочитала бы как полный сброс.
enum SizeLayer {
    case keep
    case reset
    case halves(answer: Layer<Int>, question: Layer<Int>)

    /// Слой из готового размера («моя тема», вид проекта, «всем окнам»): заданные половины —
    /// числами, пустые — «не трогать».
    init(_ size: Size) {
        self = .halves(answer: size.answer.map { Layer.set($0) } ?? .keep,
                       question: size.question.map { Layer.set($0) } ?? .keep)
    }

    /// Слой-значение (`.pimpmyclaude.json`, покраска по проекту) как слой команды.
    init(_ layer: Layer<Size>) {
        switch layer {
        case .keep: self = .keep
        case .reset: self = .reset
        case .set(let size): self = SizeLayer(size)
        }
    }

    /// Пункт меню трогает ровно свою половину: «Размер ответов ▸ 16» или «… → Как у Claude».
    static func one(_ half: Size.Half, _ value: Layer<Int>) -> SizeLayer {
        half == .answer ? .halves(answer: value, question: .keep)
                        : .halves(answer: .keep, question: value)
    }

    /// Что слой делает с одной половиной.
    func half(_ half: Size.Half) -> Layer<Int> {
        switch self {
        case .keep: return .keep
        case .reset: return .reset
        case .halves(let answer, let question): return half == .answer ? answer : question
        }
    }

    /// Слоя в команде нет: ни одной половины не трогаем.
    var isKeep: Bool {
        switch self {
        case .keep: return true
        case .reset: return false
        case .halves(let answer, let question): return answer.isKeep && question.isKeep
        }
    }

    /// Поле `size` команды: nil — поля нет вовсе; `null` — сброс слоя; объект — только заданные
    /// половины, `answer` первым, снятая половина как `null`.
    var commandValue: CommandValue? {
        switch self {
        case .keep: return nil
        case .reset: return .null
        case .halves:
            var fields: [(key: String, value: CommandValue)] = []
            for (key, layer) in [(Size.answerKey, half(.answer)),
                                 (Size.questionKey, half(.question))] {
                switch layer {
                case .keep: continue
                case .reset: fields.append((key: key, value: .null))
                case .set(let px): fields.append((key: key, value: .number(Size.clamp(px))))
                }
            }
            return fields.isEmpty ? nil : .object(fields)
        }
    }

    /// Что останется в памяти приложения после этой команды: `keep` — прежнее, `reset` —
    /// ничего, половины — поверх базы, а снятая половина из неё уходит. Обе половины сняты —
    /// записи нет вовсе (пустой слой страница читает так же, решение 1 плана WF19).
    func applied(to base: Size?) -> Size? {
        switch self {
        case .keep: return base
        case .reset: return nil
        case .halves:
            func value(_ side: Size.Half) -> Int? {
                switch half(side) {
                case .keep: return base?.value(side)
                case .reset: return nil
                case .set(let px): return px
                }
            }
            let size = Size(answer: value(.answer), question: value(.question))
            return size.isEmpty ? nil : size
        }
    }
}

/// Каталог шрифтов: белые списки по категориям (решение 7 плана WF9), отфильтрованные по факту
/// установки (`NSFontManager.shared.availableFontFamilies`) и по кириллице (в семействе есть «Ж»).
/// «Системный» отдельным пунктом каталога нет: это сброс слоя (`"font":null`).
enum FontCatalog {
    /// С засечками — порядок из плана; чего нет в системе или без кириллицы, в меню не попадает.
    static let serifFamilies = [
        "Georgia", "Palatino", "Baskerville", "Didot", "Hoefler Text", "Iowan Old Style",
        "Times New Roman",
    ]

    /// Без засечек.
    static let sansFamilies = [
        "Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Optima", "Verdana",
        "Trebuchet MS", "Arial", "Tahoma",
    ]

    /// Рукописные и весёлые.
    static let handFamilies = [
        "Comic Sans MS", "Chalkboard SE", "Noteworthy", "Marker Felt", "Bradley Hand",
        "Snell Roundhand", "Papyrus", "Copperplate", "American Typewriter",
    ]

    /// Моноширинные — свой белый список, дальше добираем установленные по регулярке.
    static let monoFamilies = ["SF Mono", "Menlo", "Monaco", "Courier New", "Andale Mono", "PT Mono"]

    /// Белый список категории.
    static func families(_ category: FontCategory) -> [String] {
        switch category {
        case .serif: return serifFamilies
        case .sans: return sansFamilies
        case .hand: return handFamilies
        case .mono: return monoFamilies
        }
    }

    /// Категория известного семейства; неизвестное (шрифт из my-themes.json) — по флагу `mono`.
    static func category(family: String, mono: Bool) -> FontCategory {
        FontCategory.allCases.first { families($0).contains(family) } ?? (mono ? .mono : .sans)
    }

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

    /// Категории подряд, каждая в порядке своего белого списка — секции меню режет по `category`.
    static func build(installed: [String] = NSFontManager.shared.availableFontFamilies,
                      coversCyrillic: (String) -> Bool = FontCatalog.hasCyrillic,
                      displayName: (String) -> String = FontCatalog.localizedName) -> [Font] {
        let present = Set(installed)
        func make(_ family: String, _ category: FontCategory) -> Font? {
            // SF Mono — системный, в availableFontFamilies его нет, но NSFont по имени его находит
            // (SFMono-Regular); Chromium резолвит «SF Mono» так же. Пускаем, если шрифт отвечает.
            let installed = present.contains(family) || (family == "SF Mono" && NSFont(name: "SFMono-Regular", size: 13) != nil)
            guard installed, let clean = sanitize(family: family),
                  coversCyrillic(family) else { return nil }
            return Font(id: id(for: clean), family: clean, category: category, displayName: displayName(clean))
        }

        var fonts: [Font] = []
        for category in FontCategory.allCases where category != .mono {
            fonts += families(category).compactMap { make($0, category) }
        }
        var mono = monoFamilies.compactMap { make($0, .mono) }
        if mono.count < monoLimit {
            let known = Set(monoFamilies)
            for family in installed.filter({ !known.contains($0) && matchesMono($0) }).sorted() {
                guard mono.count < monoLimit else { break }
                if let font = make(family, .mono) { mono.append(font) }
            }
        }
        fonts += mono
        return fonts
    }
}
