import Foundation

// Ряд «Отсчёт» блока «Оформление» (WF242; слово Элвиса 11.10.2026: «если он на них наводит, они тогда анимируются,
// ну, с задержкой небольшой. А если не наводят, то не анимируются, ну, чтоб не пестрили… должны выглядеть в этих
// окошках-превьюшках так, как они будут выглядеть в этой теме установленной… Первый раз нажимаешь, а второй раз на
// неё нажимаешь — в настройках»). Чистая часть: цвета плитки от темы окон, кадр вида на момент времени, что делает
// нажатие. Вид — `CountdownRow` в `Panel/PanelColors.swift`, тесты — `PanelWF242Tests`.

/// Цвета плитки отсчёта — те же роли, что у страницы (раздел 12у `inject.js`, `sendLookColors`): акцент темы, фон
/// окна, фон поля ввода и цвет текста. `0xRRGGBB`.
public struct CountdownPalette: Equatable {
    public let accent: UInt32
    public let background: UInt32
    public let field: UInt32
    public let ink: UInt32
}

public enum PanelCountdown {
    /// Курсор над плиткой — вид оживает через столько секунд покоя; ушёл раньше — не оживает.
    public static let hoverDelay: TimeInterval = 0.3

    static let claudeAccent: UInt32 = 0xD97757
    static let darkInk: UInt32 = 0xECECEE
    static let lightInk: UInt32 = 0x1F1E1D

    /// Цвета по выбору «Оформления»: тема всем окнам — её акцент и фон; «как у Claude» и «свой цвет каждому
    /// проекту» (у окон цвета разные, одного нет) — оранжевый Claude на его фоне, тёмном или светлом по macOS.
    public static func palette(_ choice: WindowColorChoice, themes: [WindowColorChip], dark: Bool) -> CountdownPalette {
        if case .theme(let id) = choice, let chip = themes.first(where: { $0.id == id }),
           let background = ColorMath.rgb(hex: chip.background), let accent = ColorMath.rgb(hex: chip.accent) {
            return make(accent: accent, background: background, ink: chip.light ? lightInk : darkInk)
        }
        return make(accent: claudeAccent, background: dark ? 0x262624 : 0xFAF9F5, ink: dark ? darkInk : lightInk)
    }

    private static func make(accent: UInt32, background: UInt32, ink: UInt32) -> CountdownPalette {
        CountdownPalette(accent: accent, background: background, field: ColorMath.mix(ink, background, 0.08), ink: ink)
    }

    // MARK: кадр вида

    /// Секунда отсчёта в плитке, пуск и пауза перед повтором. Счёт в плитке идёт быстрее настоящего (0,8 с на
    /// цифру): показать вид, а не заставить ждать три секунды.
    public static let second: TimeInterval = 0.8
    public static let launch: TimeInterval = 0.9
    public static let rest: TimeInterval = 0.4
    public static var loop: TimeInterval { loop(count: 3) }
    public static func loop(count: Int) -> TimeInterval { Double(count) * second + launch + rest }
    /// Момент неподвижного кадра: первая секунда, первая цифра. Оживая, вид играет с него же — без скачка.
    public static let stillTime: TimeInterval = 0.5 * second

    public struct Frame: Equatable {
        /// 3, 2, 1; после счёта (пуск и пауза) — 0.
        public let digit: Int
        /// Доля текущей секунды 0…1.
        public let beat: Double
        /// Доля всего счёта 0…1.
        public let passed: Double
        /// Доля пуска 0…1 (ракета ушла, волна); идёт счёт — nil.
        public let flight: Double?
    }

    /// Кадр на момент `time` от начала круга; круг повторяется. `seconds` — с какой цифры счёт.
    public static func frame(at time: TimeInterval, seconds: Int = 3) -> Frame {
        let circle = loop(count: seconds)
        let t = time.truncatingRemainder(dividingBy: circle) + (time < 0 ? circle : 0)
        let count = Double(seconds) * second
        if t < count {
            let index = Int(t / second)
            return Frame(digit: seconds - index, beat: t / second - Double(index), passed: t / count, flight: nil)
        }
        return Frame(digit: 0, beat: 0, passed: 1, flight: min(1, (t - count) / launch))
    }

    public static var still: Frame { frame(at: stillTime) }

    /// Плитка считает с настоящего таймера (слово 03.11.2026: «2 секунды надо, а не три»); таймер выключен — с трёх.
    public static func tileSeconds(_ delay: SendDelaySetting) -> Int { delay.on ? delay.seconds : 3 }

    /// Таймер отсчёта: 0 — выключен (слово 03.11.2026: «чтобы была возможность отключить вообще»).
    public static let delayItems: [(value: Int, title: String)] = [(0, "Нет"), (2, "2 с"), (5, "5 с"), (10, "10 с")]

    // MARK: нажатие и размер

    public enum Tap: Equatable {
        /// Первое нажатие — выбрать вид (настройки прежнего вида закрываются).
        case select
        /// Второе нажатие по выбранному — показать или убрать его настройки под рядом.
        case settings(open: Bool)
    }

    public static func tap(style: String, selected: String, settingsOpen: Bool) -> Tap {
        style == selected ? .settings(open: !settingsOpen) : .select
    }

    /// Метки ползунка размера: 60…200 %, шаг — `SendLook.step`.
    public static let sizeMarks = [60, 100, 150, 200]
    public static var sizeRange: ClosedRange<Int> { SendLook.minSize...SendLook.maxSize }

    /// Размер ползунка → на шаг и в границы (как примет страница).
    public static func size(_ raw: Int) -> Int { SendLook.clamp(raw) }

    /// Масштаб цифры и ракеты в плитке: размер 60…200 % ужат в 0,8…1,5 — в плитке 34 pt вдвое большее не встанет,
    /// а «побольше — поменьше» видно.
    public static func tileScale(size: Int) -> Double {
        let k = Double(SendLook.clamp(size)) / 100
        return k <= 1 ? 0.8 + (k - 0.6) / 0.4 * 0.2 : 1 + (k - 1) * 0.5
    }
}

/// Курсор над рядом плиток отсчёта: над какой он сейчас и какая играет свой вид. Играет одна — та, над которой
/// курсор простоял `PanelCountdown.hoverDelay`; ушёл с плитки — она замирает, поздний сигнал «простоял» от прошлой
/// плитки ничего не оживляет.
public struct CountdownHover: Equatable {
    public private(set) var hovered: String?
    public private(set) var playing: String?

    public init() {}

    public mutating func enter(_ style: String) {
        hovered = style
        if playing != style { playing = nil }
    }

    public mutating func leave(_ style: String) {
        guard hovered == style else { return }
        hovered = nil
        playing = nil
    }

    /// Задержка наведения вышла.
    public mutating func rested(_ style: String) {
        if hovered == style { playing = style }
    }
}
