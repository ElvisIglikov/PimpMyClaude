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

/// Генератор палитр «🌈 Автопокраски» (план WF10). Наборы «Раскрасить по кругу» и их память сняты вместе с меню
/// жёлтой кнопки (WF237, #9524); генератор остался цвету проекта (`projectTheme`) и сводке проектов. Чистая
/// арифметика: ни AX, ни файлов, ни команд.
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
    /// 0 ≤ hue < 360.
    static func normalized(_ hue: Double) -> Double {
        let value = hue.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
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
        let tone = hue
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
            accent = HSL(tone, 70, 42)
        } else {
            let lightness = 16 - 4 * force
            background = capped(HSL(hue, min(maxBackgroundSaturation, 45 + 15 * force), lightness))
            let saturation = background.saturation
            sidebar = HSL(hue, saturation, lightness - 3)
            panel = HSL(hue, saturation, lightness + 6)
            foreground = HSL(hue, 25, 92)
            muted = HSL(hue, 20, 65)
            // «Неон» — тёмный с ярким акцентом (план п. 2): сила поднимает насыщенность.
            accent = HSL(tone, 70 + 20 * force, 62)
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

    // MARK: - цвет проекта по имени папки (решение 3.1 плана WF20)

    /// Начало FNV-1a 64 и её множитель. Хэш СВОЙ, а не `hashValue`: тот солится на каждый
    /// запуск процесса — цвет проекта менялся бы после каждого перезапуска приложения
    /// и не совпадал бы у Элвиса с командой.
    static let fnvOffset: UInt64 = 14_695_981_039_346_656_037
    static let fnvPrime: UInt64 = 1_099_511_628_211

    /// Устойчивый тон проекта из имени папки: FNV-1a 64 над `name.lowercased()` в UTF-8,
    /// остаток от 360. Регистр не важен, число одно и то же на любой машине и в любом запуске.
    static func hue(forName name: String) -> Int {
        var hash = fnvOffset
        for byte in name.lowercased().utf8 { hash = (hash ^ UInt64(byte)) &* fnvPrime }
        return Int(hash % 360)
    }

    /// Тема проекта, которой окно красится САМО, пока в папке нет `.pimpmyclaude.json`
    /// (решение 3.1 плана WF20): id `project-<hue>`, имя «<Папка> · <hue>°». Читаемость держат
    /// те же `capped`/`pulled`/`banded`, что у автопокраски. Тон тёмный: рабочая тема Элвиса
    /// и команды тёмная, а светлый цвет проекта задаётся выбором светлой темы в его окне.
    static func projectTheme(folderName: String, light: Bool = false) -> Theme {
        let degrees = hue(forName: folderName)
        return Theme(id: "project-\(degrees)",
                     name: "\(folderName) · \(degrees)°",
                     type: light ? "light" : "dark",
                     palette: palette(hue: Double(degrees), light: light))
    }

    // MARK: - контраст WCAG

    static func luminance(r: Int, g: Int, b: Int) -> Double {
        ColorMath.luminance(ColorMath.value(r: r, g: g, b: b))
    }

    static func contrast(_ a: HSL, _ b: HSL) -> Double {
        ColorMath.contrast(luminance: a.luminance, b.luminance)
    }

    /// Контраст двух цветов палитры по hex — так его проверяет тест: на глаза попадает
    /// именно hex, а не то, что генератор думал в HSL.
    static func contrast(hex a: String, hex b: String) -> Double? {
        guard let first = ColorMath.rgb(hex: a), let second = ColorMath.rgb(hex: b) else { return nil }
        return ColorMath.contrast(first, second)
    }

    /// «#rrggbb» → каналы 0–255; всё остальное — nil.
    static func channels(hex: String) -> (r: Int, g: Int, b: Int)? {
        guard let value = ColorMath.rgb(hex: hex) else { return nil }
        return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
    }

    /// Насыщенность цвета в процентах (обратный ход из hex) — потолок фона проверяет тест.
    static func saturation(hex: String) -> Double? {
        ColorMath.rgb(hex: hex).map { ColorMath.hsl($0).saturation * 100 }
    }
}
