import Foundation

/// Цвет в HSL: hue 0–360°, насыщенность и светлота — проценты 0–100.
/// Генератор палитры живёт в HSL (крутить hue по кругу и подтягивать светлоту так проще),
/// а в страницу уезжает hex — его же читают и тесты.
struct HSL: Equatable {
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(_ hue: Double, _ saturation: Double, _ lightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }

    /// Каналы 0–255 — ровно те, что уедут в hex. Контраст считается по ним, а не по «точному»
    /// HSL: иначе проверка внутри генератора и проверка в тесте (она читает hex) разошлись бы.
    var channels: (r: Int, g: Int, b: Int) {
        let h = AutoPaint.normalized(hue) / 360
        let s = min(max(saturation, 0), 100) / 100
        let l = min(max(lightness, 0), 100) / 100
        guard s > 0 else {
            let gray = Int((l * 255).rounded())
            return (gray, gray, gray)
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ offset: Double) -> Int {
            var t = offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            let value: Double
            if t < 1.0 / 6 {
                value = p + (q - p) * 6 * t
            } else if t < 1.0 / 2 {
                value = q
            } else if t < 2.0 / 3 {
                value = p + (q - p) * (2.0 / 3 - t) * 6
            } else {
                value = p
            }
            return Int((value * 255).rounded())
        }
        return (channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
    }

    /// «#rrggbb» строчными — как в themes.json.
    var hex: String {
        let c = channels
        return String(format: "#%02x%02x%02x", c.r, c.g, c.b)
    }

    /// Относительная яркость WCAG.
    var luminance: Double {
        let c = channels
        return AutoPaint.luminance(r: c.r, g: c.g, b: c.b)
    }
}

/// Набор автопокраски — правило генерации, а не список готовых тем (план WF10 п. 2):
/// схема раскладки hue по окнам, режим (тёмная/светлая) и «сила» палитры.
struct AutoPaintPreset: Equatable {
    /// Как раскидать hue по N окнам.
    enum Scheme: Equatable {
        /// Весь круг равномерно — «Радуга», «Пастель», «Неон».
        case wheel
        /// Сектор круга [from, to]; to может быть больше 360 («Закат»: 350°–420°).
        case sector(Double, Double)
        /// Один hue на все окна, разная светлота фона — «Монохром».
        case mono
        /// Относительные сдвиги от старта — схемы «Случайно» (триада, тетрада и т. п.).
        case offsets([Double])
    }

    /// Кусок id темы: `auto-<id набора>-<hue>`.
    let id: String
    let title: String
    let icon: String
    let scheme: Scheme
    /// nil — «по большинству окон»: так решает «Случайно» (план п. 2).
    let light: Bool?
    /// «Сила» палитры 0–1: 0,5 — обычная, 1 — «Неон» (акцент ярче, фон глубже).
    let strength: Double
    /// «Случайно» выбирает схему заново на каждый запуск.
    let picksScheme: Bool

    init(id: String, title: String, icon: String, scheme: Scheme,
         light: Bool?, strength: Double = 0.5, picksScheme: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.scheme = scheme
        self.light = light
        self.strength = strength
        self.picksScheme = picksScheme
    }
}

/// «🌈 Автопокраска» (план WF10): одно нажатие — и все окна Claude красятся гармонично по
/// цветовому кругу. Здесь чистая арифметика: ни AX, ни файлов, ни команд — так её и гоняют
/// тесты. Кто эти темы разошлёт по окнам, знает `ClaudeActions.autoPaint`.
enum AutoPaint {
    /// «Трендовые, не кричащие» (слово Элвиса): насыщенность фона выше не поднимаем.
    /// Первая редакция ставила 45 % — и фон выходил серым: у живых тем каталога он 49–66 %
    /// (Красная 49, Синяя 59, Жёлтая 66). Потолок 60 % — как план п. 3 и писал светлому фону;
    /// сами формулы фона подняты в ту же полосу, иначе потолка они не касались бы вовсе.
    static let maxBackgroundSaturation: Double = 60
    /// Контраст текста и фона по WCAG — не ниже AAA.
    static let textContrast: Double = 7
    /// Приглушённый текст и акцент — не ниже AA (у них своя роль: подписи и кнопки).
    static let accentContrast: Double = 4.5
    /// Верх полосы контраста для акцента (см. `banded`): жёлтому и зелёному на тёмном фоне
    /// иначе достаётся контраст за 10 — они кричат, а синий с фиолетовым еле дотягивают до
    /// пола. У светлой темы полоса шире: тёмный акцент на светлом фоне глаза не режет.
    static func accentContrastCap(light: Bool) -> Double { light ? 7 : 6 }
    /// «🔁 Ещё раз» — тот же набор, старт на 37° дальше (план п. 5): число взаимно простое
    /// с 360, поэтому круг обходится целиком и цвета не повторяются подряд.
    static let againStep: Double = 37

    // MARK: - наборы

    static let presets: [AutoPaintPreset] = [
        AutoPaintPreset(id: "rainbow", title: "Радуга", icon: "🌈", scheme: .wheel, light: false),
        AutoPaintPreset(id: "pastel", title: "Пастель", icon: "🍭", scheme: .wheel, light: true, strength: 0.35),
        AutoPaintPreset(id: "sunset", title: "Закат", icon: "🌅", scheme: .sector(350, 420), light: false, strength: 0.55),
        AutoPaintPreset(id: "ocean", title: "Океан", icon: "🌊", scheme: .sector(180, 260), light: false),
        AutoPaintPreset(id: "forest", title: "Лес", icon: "🌲", scheme: .sector(70, 160), light: false),
        AutoPaintPreset(id: "berry", title: "Ягоды", icon: "🫐", scheme: .sector(280, 350), light: false, strength: 0.55),
        AutoPaintPreset(id: "neon", title: "Неон", icon: "⚡️", scheme: .wheel, light: false, strength: 1),
        AutoPaintPreset(id: "mono", title: "Монохром", icon: "🌓", scheme: .mono, light: false),
    ]

    /// «🎲 Случайно» стоит в меню отдельно, за разделителем (план п. 1): схема у него каждый
    /// раз своя, а тёмная или светлая — по большинству окон.
    static let random = AutoPaintPreset(id: "random", title: "Случайно", icon: "🎲",
                                        scheme: .wheel, light: nil, picksScheme: true)

    static var all: [AutoPaintPreset] { presets + [random] }

    static func preset(id: String) -> AutoPaintPreset? { all.first { $0.id == id } }

    /// Четыре гармонии, из которых выбирает «Случайно» (план п. 2).
    static let randomSchemes: [AutoPaintPreset.Scheme] = [
        .offsets([-30, 0, 30]),      // аналоговая ±30°
        .offsets([0, 120, 240]),     // триада
        .offsets([0, 150, 210]),     // сплит-комплементарная
        .offsets([0, 90, 180, 270]), // тетрада
    ]

    /// Индекс схемы на запуск: у «Случайно» — новый случайный или заданный («🔁 Ещё раз»
    /// повторяет ту же схему, план п. 5), у остальных наборов схема своя всегда — nil.
    static func schemeIndex(for preset: AutoPaintPreset, repeating: Int? = nil,
                            pick: () -> Int = { Int.random(in: 0..<AutoPaint.randomSchemes.count) })
        -> Int? {
        guard preset.picksScheme else { return nil }
        return min(max(repeating ?? pick(), 0), randomSchemes.count - 1)
    }

    /// Схема по индексу из `schemeIndex`: nil — своя схема набора.
    static func scheme(for preset: AutoPaintPreset, index: Int?) -> AutoPaintPreset.Scheme {
        guard preset.picksScheme, let index = index else { return preset.scheme }
        return randomSchemes[min(max(index, 0), randomSchemes.count - 1)]
    }

    // MARK: - раскладка hue по окнам

    /// 0 ≤ hue < 360.
    static func normalized(_ hue: Double) -> Double {
        let value = hue.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func wrapped(_ value: Double, _ span: Double) -> Double {
        guard span > 0 else { return 0 }
        let rest = value.truncatingRemainder(dividingBy: span)
        return rest < 0 ? rest + span : rest
    }

    /// N окон → N hue. `start` — случайный старт (и он же крутится на +37° у «Ещё раз»).
    static func hues(scheme: AutoPaintPreset.Scheme, count: Int, start: Double) -> [Double] {
        guard count > 0 else { return [] }
        switch scheme {
        case .wheel:
            return (0..<count).map { normalized(start + 360 * Double($0) / Double(count)) }
        case .sector(let from, let to):
            // Шаг сектора считаем от середины ячейки: у одного окна выходит середина
            // диапазона (план п. 4), у N окон — N разных цветов, и края не слипаются.
            let span = max(to - from, 1)
            return (0..<count).map { index in
                let step = span * (Double(index) + 0.5) / Double(count)
                return normalized(from + wrapped(step + start, span))
            }
        case .mono:
            return Array(repeating: normalized(start), count: count)
        case .offsets(let offsets):
            guard !offsets.isEmpty else { return Array(repeating: normalized(start), count: count) }
            // Схема короче, чем окон, — второй круг сдвигается на 12°, чтобы цвета не повторились.
            return (0..<count).map { index in
                normalized(start + offsets[index % offsets.count]
                    + Double(index / offsets.count) * 12)
            }
        }
    }

    /// Сила палитры на каждое окно. «Монохром» — один hue, разная светлота фона (план п. 2):
    /// сила растёт от окна к окну, остальные наборы красят все окна одинаково.
    static func strengths(preset: AutoPaintPreset, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard case .mono = preset.scheme, count > 1 else {
            return Array(repeating: preset.strength, count: count)
        }
        return (0..<count).map { Double($0) / Double(count - 1) }
    }

    // MARK: - генератор палитры (план п. 3)

    /// Палитра {accent, background, foreground, sidebar, panel, muted} в hex.
    /// Тёмная: фон HSL(hue, 45–60 %, 12–16 %), боковина −3 по светлоте, панель +6,
    /// текст HSL(hue, 25 %, 92 %), приглушённый HSL(hue, 20 %, 65 %), акцент HSL(hue, 80 %, 62 %).
    /// Светлая: фон HSL(hue, 40–60 %, 92–96 %), панель +4, боковина −4, текст HSL(hue, 40 %, 14 %),
    /// приглушённый HSL(hue, 25 %, 42 %), акцент HSL(hue, 70 %, 42 %).
    /// Всё, что читают глазами, потом подтягивается по контрасту (см. `pulled`), а акцент
    /// кладётся в полосу контраста (см. `banded`).
    static func palette(hue: Double, light: Bool, strength: Double = 0.5) -> [String: String] {
        let force = min(max(strength, 0), 1)
        let background: HSL, sidebar: HSL, panel: HSL
        var foreground: HSL, muted: HSL, accent: HSL
        if light {
            let lightness = 96 - 4 * force
            background = capped(HSL(hue, min(maxBackgroundSaturation, 40 + 20 * force), lightness))
            let saturation = background.saturation
            panel = HSL(hue, saturation, min(99, lightness + 4))
            sidebar = HSL(hue, saturation, lightness - 4)
            foreground = HSL(hue, 40, 14)
            muted = HSL(hue, 25, 42)
            accent = HSL(hue, 70, 42)
        } else {
            let lightness = 16 - 4 * force
            background = capped(HSL(hue, min(maxBackgroundSaturation, 45 + 15 * force), lightness))
            let saturation = background.saturation
            sidebar = HSL(hue, saturation, lightness - 3)
            panel = HSL(hue, saturation, lightness + 6)
            foreground = HSL(hue, 25, 92)
            muted = HSL(hue, 20, 65)
            // «Неон» — тёмный с ярким акцентом (план п. 2): сила поднимает насыщенность.
            accent = HSL(hue, 70 + 20 * force, 62)
        }
        foreground = pulled(foreground, to: textContrast, on: background)
        muted = pulled(muted, to: accentContrast, on: background)
        accent = banded(accent, from: accentContrast, to: accentContrastCap(light: light),
                        on: background)
        return ["accent": accent.hex, "background": background.hex, "foreground": foreground.hex,
                "sidebar": sidebar.hex, "panel": panel.hex, "muted": muted.hex]
    }

    /// Потолок насыщенности фона держим по hex — по тому, что реально увидят: у очень светлого
    /// фона округление каналов до 0–255 поднимает насыщенность на пару процентов, и потолок
    /// в HSL оказался бы превышен на экране. Шаг 0,5 %, дальше нуля не идём.
    static func capped(_ color: HSL, to limit: Double = maxBackgroundSaturation) -> HSL {
        var color = color
        for _ in 0..<100 {
            guard (saturation(hex: color.hex) ?? 0) > limit, color.saturation > 0 else { break }
            color.saturation = max(0, color.saturation - 0.5)
        }
        return color
    }

    /// Подтяжка светлоты, пока контраст с фоном не дотянет до цели (план п. 3): на тёмном фоне
    /// цвет светлеет, на светлом — темнеет. Шаг 1 %, за границы 0/100 не выходим.
    static func pulled(_ color: HSL, to target: Double, on background: HSL) -> HSL {
        var color = color
        let up = background.luminance < 0.5
        for _ in 0..<100 {
            guard contrast(color, background) < target else { break }
            let next = color.lightness + (up ? 1 : -1)
            guard next >= 0, next <= 100 else { break }
            color.lightness = next
        }
        return color
    }

    /// Акцент — в полосу контраста, а не в пол: сперва подтяжка от фона (`pulled`), затем
    /// обратный ход к фону — жёлтый и зелёный сами по себе дают за 10 и кричат, а синий с
    /// фиолетовым еле дотягивают до 4,5 и тонут.
    ///
    /// Целимся в середину полосы, а не в её верхний край: если просто останавливать обратный
    /// ход на потолке, жёлтый останется у пола (4,5), синий — у потолка (7,0), и по кругу
    /// яркость акцента разъедется в 2,2 раза — ровно то, от чего полосу и заводили. От середины
    /// же остаётся один разброс фонов, вдвое меньше. Ниже пола шаг не пускаем.
    static func banded(_ color: HSL, from lower: Double, to upper: Double, on background: HSL) -> HSL {
        let aim = (lower + upper) / 2
        var color = pulled(color, to: aim, on: background)
        // Фон тёмный — подтяжка вела акцент вверх, значит обратно к фону это вниз.
        let back = background.luminance < 0.5 ? -1.0 : 1.0
        for _ in 0..<100 {
            guard contrast(color, background) > aim else { break }
            let next = color.lightness + back
            guard next >= 0, next <= 100 else { break }
            let stepped = HSL(color.hue, color.saturation, next)
            guard contrast(stepped, background) >= lower else { break }
            color = stepped
        }
        return color
    }

    /// Тема одного окна: id `auto-<набор>-<hue>`, имя «Набор · hue°» (план п. 4).
    static func theme(preset: AutoPaintPreset, hue: Double, light: Bool,
                      strength: Double = 0.5) -> Theme {
        let degrees = Int(normalized(hue).rounded()) % 360
        return Theme(id: "auto-\(preset.id)-\(degrees)",
                     name: "\(preset.title) · \(degrees)°",
                     type: light ? "light" : "dark",
                     palette: palette(hue: Double(degrees), light: light, strength: strength))
    }

    /// Темы на N окон подряд — то, что уедет по одной команде на окно.
    static func themes(preset: AutoPaintPreset, scheme: AutoPaintPreset.Scheme,
                       count: Int, start: Double, light: Bool) -> [Theme] {
        let force = strengths(preset: preset, count: count)
        return zip(hues(scheme: scheme, count: count, start: start), force).map {
            theme(preset: preset, hue: $0, light: light, strength: $1)
        }
    }

    // MARK: - контраст WCAG

    static func luminance(r: Int, g: Int, b: Int) -> Double {
        func channel(_ value: Int) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    static func contrast(_ a: HSL, _ b: HSL) -> Double {
        contrast(a.luminance, b.luminance)
    }

    private static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Контраст двух цветов палитры по hex — так его проверяет тест: на глаза попадает
    /// именно hex, а не то, что генератор думал в HSL.
    static func contrast(hex a: String, hex b: String) -> Double? {
        guard let first = channels(hex: a), let second = channels(hex: b) else { return nil }
        return contrast(luminance(r: first.r, g: first.g, b: first.b),
                        luminance(r: second.r, g: second.g, b: second.b))
    }

    /// «#rrggbb» → каналы 0–255; всё остальное — nil.
    static func channels(hex: String) -> (r: Int, g: Int, b: Int)? {
        var text = hex.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
    }

    /// Насыщенность цвета в процентах (обратный ход из hex) — потолок фона проверяет тест.
    static func saturation(hex: String) -> Double? {
        guard let c = channels(hex: hex) else { return nil }
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        guard high != low else { return 0 }
        let delta = high - low
        return delta / (1 - abs(2 * lightness - 1)) * 100
    }
}

/// Последний запуск автопокраски (план п. 5): «🔁 Ещё раз» повторяет его со сдвигом +37°.
/// Схему храним индексом, а режим — флагом: у «Случайно» и гармония, и тёмная/светлая
/// выбираются на запуск, и без памяти «Ещё раз» после него дал бы другой набор — а обещано
/// «то же самое, только повёрнутое». Режим тем важнее, что галки покрашенных окон снимаются
/// и `prefersLightWindows` после покраски уже ничего не помнит.
/// Живёт в UserDefaults под ключом `autoPaint.last`; в тестах — в памяти.
final class AutoPaintStore {
    static let key = "autoPaint.last"
    static let presetKey = "preset"
    static let startKey = "start"
    static let schemeKey = "scheme"
    static let lightKey = "light"

    private let defaults: ThemeDefaults

    init(defaults: ThemeDefaults = UserDefaults.standard) { self.defaults = defaults }

    var last: (preset: String, start: Double, scheme: Int?, light: Bool?)? {
        guard let values = defaults.dictionary(forKey: AutoPaintStore.key),
              let preset = values[AutoPaintStore.presetKey] as? String, !preset.isEmpty else { return nil }
        let start = (values[AutoPaintStore.startKey] as? NSNumber)?.doubleValue
            ?? values[AutoPaintStore.startKey] as? Double ?? 0
        let scheme = (values[AutoPaintStore.schemeKey] as? NSNumber)?.intValue
            ?? values[AutoPaintStore.schemeKey] as? Int
        let light = (values[AutoPaintStore.lightKey] as? NSNumber)?.boolValue
            ?? values[AutoPaintStore.lightKey] as? Bool
        return (preset, start, scheme, light)
    }

    func remember(preset: String, start: Double, scheme: Int? = nil, light: Bool? = nil) {
        var values: [String: Any] = [AutoPaintStore.presetKey: preset,
                                     AutoPaintStore.startKey: AutoPaint.normalized(start)]
        if let scheme = scheme { values[AutoPaintStore.schemeKey] = scheme }
        if let light = light { values[AutoPaintStore.lightKey] = light }
        defaults.set(values, forKey: AutoPaintStore.key)
    }
}
