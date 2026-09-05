import Foundation

/// Ручки редактора своей темы (решение 1.1 плана WF20): «Цвет», «Акцент», «Сила цвета»
/// и тумблер «Тёмная/Светлая». Числа целые — `CommandValue` дробей не знает, а в
/// `my-themes.json` ручки уезжают полем `knobs` тем же порядком.
///
/// Своей цветовой математики здесь НЕТ: палитру считает тот же `AutoPaint.palette`, что и
/// «Раскрасить по кругу», — поэтому нечитаемую тему ползунками не собрать (`pulled` тянет
/// текст до контраста 7, `banded` кладёт акцент в полосу 4,5…6 тёмной и 4,5…7 светлой).
/// Ручкам нужен ровно один новый параметр генератора — отдельный тон акцента.
struct ThemeKnobs: Equatable {
    static let accentRange = -180...180
    static let strengthRange = 0...100
    /// С чего открывается панель, когда подбирать не по чему.
    static let defaultHue = 262
    static let defaultStrength = 50

    /// Ключи поля `knobs` в `my-themes.json` — порядок побайтный.
    static let hueKey = "hue"
    static let accentKey = "accent"
    static let strengthKey = "strength"
    static let lightKey = "light"

    /// Id и имя темы, которой идёт ПРИМЕРКА: в хранилища она не попадает (`preview:true`),
    /// а у сохранённой темы id и имя свои — их даёт `MyThemesStore`.
    static let previewID = "user-knobs"
    static let previewName = "Своя тема"

    /// Тон фона, 0…359°: круг замкнут, 360 — это снова 0.
    var hue: Int { didSet { hue = ThemeKnobs.wrapped(hue) } }
    /// Сдвиг акцента от тона фона, −180…+180°.
    var accent: Int { didSet { accent = ThemeKnobs.clamped(accent, ThemeKnobs.accentRange) } }
    /// «Сила цвета» 0…100 % — та же `strength` автопокраски (0…1).
    var strength: Int { didSet { strength = ThemeKnobs.clamped(strength, ThemeKnobs.strengthRange) } }
    var light: Bool

    /// `didSet` при инициализации не зовётся — границы держим здесь же.
    init(hue: Int = ThemeKnobs.defaultHue, accent: Int = 0,
         strength: Int = ThemeKnobs.defaultStrength, light: Bool = false) {
        self.hue = ThemeKnobs.wrapped(hue)
        self.accent = ThemeKnobs.clamped(accent, ThemeKnobs.accentRange)
        self.strength = ThemeKnobs.clamped(strength, ThemeKnobs.strengthRange)
        self.light = light
    }

    static func wrapped(_ degrees: Int) -> Int {
        let rest = degrees % 360
        return rest < 0 ? rest + 360 : rest
    }

    static func clamped(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// «Сила» в том виде, в каком её ждёт `AutoPaint.palette`.
    var force: Double { Double(strength) / 100 }

    /// Тон акцента: сдвиг от тона фона по кругу.
    var accentHue: Double { Double(ThemeKnobs.wrapped(hue + accent)) }

    /// Палитра ручек — генератор автопокраски плюс отдельный тон акцента.
    func palette() -> [String: String] {
        AutoPaint.palette(hue: Double(hue), light: light, strength: force, accentHue: accentHue)
    }

    /// Тема для примерки и для записи в `my-themes.json`.
    func theme(id: String = ThemeKnobs.previewID, name: String = ThemeKnobs.previewName) -> Theme {
        Theme(id: id, name: name, type: light ? "light" : "dark", palette: palette())
    }

    /// Имя, которое панель предложит в диалоге: у каждого тона своё, чтобы два сохранения
    /// подряд не упирались в вопрос «перезаписать?».
    var suggestedName: String { "Своя · \(hue)°" }

    /// Поле `knobs`: hue, accent, strength, light — порядок побайтный.
    var commandValue: CommandValue {
        .object([
            (key: ThemeKnobs.hueKey, value: .number(hue)),
            (key: ThemeKnobs.accentKey, value: .number(accent)),
            (key: ThemeKnobs.strengthKey, value: .number(strength)),
            (key: ThemeKnobs.lightKey, value: .bool(light)),
        ])
    }

    /// Ручки из записи `my-themes.json`. Читаем ТОЛЬКО полный набор: половина ключей дала бы
    /// ручки, палитра от которых не совпадает с записанной, и первое же «Изменить» молча
    /// перекрасило бы тему (критик В4). Нет всех четырёх — считаем, что ручек нет вовсе,
    /// и подбираем их по палитре.
    static func parse(_ raw: Any?) -> ThemeKnobs? {
        guard let values = raw as? [String: Any] else { return nil }
        func number(_ key: String) -> Int? {
            (values[key] as? NSNumber)?.intValue ?? values[key] as? Int
        }
        guard let hue = number(hueKey), let accent = number(accentKey),
              let strength = number(strengthKey),
              let light = values[lightKey] as? Bool else { return nil }
        return ThemeKnobs(hue: hue, accent: accent, strength: strength, light: light)
    }

    /// Ручки своей темы: записанные в файл, а их нет (тема пришла из каталога или её правили
    /// руками) — подобранные по палитре.
    static func of(_ my: MyTheme) -> ThemeKnobs {
        my.knobs ?? from(palette: my.palette, type: my.type)
    }

    /// Приблизительный обратный ход из палитры (п. 4 «Что выяснено» плана WF20): тон и сила —
    /// из фона, сдвиг акцента — разницей тонов. Точности тут быть не может: светлота фона
    /// зажата в четыре пункта, а каналы квантованы до 0…255 — шаг силы ≈5 %, тон ±2°.
    /// Ровно поэтому такие ручки в файл и НЕ пишутся: они годятся только на то, чтобы открыть
    /// панель примерно там, где тема стоит сейчас.
    static func from(palette: [String: String], type: String) -> ThemeKnobs {
        let light = type == "light"
        let background = palette["background"] ?? ""
        let tone = hue(hex: background) ?? defaultHue
        // Тёмная: l = 16 − 4·сила; светлая: l = 96 − 4·сила.
        let base = light ? 96.0 : 16.0
        let strength = lightness(hex: background)
            .map { Int(((base - $0) / 4 * 100).rounded()) } ?? defaultStrength
        let shift = hue(hex: palette["accent"] ?? "").map { turn(from: tone, to: $0) } ?? 0
        return ThemeKnobs(hue: tone, accent: shift, strength: strength, light: light)
    }

    /// Кратчайший поворот от одного тона к другому: −180…+180°.
    static func turn(from: Int, to: Int) -> Int {
        let step = wrapped(to - from)
        return step > 180 ? step - 360 : step
    }

    /// Тон цвета в градусах (обратный ход из hex); у серого тона нет — nil.
    static func hue(hex: String) -> Int? {
        guard let c = AutoPaint.channels(hex: hex) else { return nil }
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let high = max(r, g, b), low = min(r, g, b)
        let delta = high - low
        guard delta > 0 else { return nil }
        let degrees: Double
        if high == r {
            degrees = 60 * ((g - b) / delta)
        } else if high == g {
            degrees = 60 * (2 + (b - r) / delta)
        } else {
            degrees = 60 * (4 + (r - g) / delta)
        }
        return wrapped(Int(degrees.rounded()))
    }

    /// Светлота цвета в процентах (обратный ход из hex).
    static func lightness(hex: String) -> Double? {
        guard let c = AutoPaint.channels(hex: hex) else { return nil }
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        return (max(r, g, b) + min(r, g, b)) / 2 * 100
    }
}
