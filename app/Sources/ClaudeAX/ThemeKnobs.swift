import Foundation

/// Ручки своей темы (решение 1.1 плана WF20): «Цвет», «Акцент», «Сила цвета» и «Тёмная/Светлая» — поле `knobs`
/// в `my-themes.json`. Редактор («Своя тема…») снят вместе с меню жёлтой кнопки (WF237, #9524): ручки только
/// читаются из файла и подбираются по палитре.
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
        guard let value = ColorMath.rgb(hex: hex), let degrees = ColorMath.hsl(value).hue else { return nil }
        return wrapped(Int(degrees.rounded()))
    }

    /// Светлота цвета в процентах (обратный ход из hex).
    static func lightness(hex: String) -> Double? {
        ColorMath.rgb(hex: hex).map { ColorMath.hsl($0).lightness * 100 }
    }
}
