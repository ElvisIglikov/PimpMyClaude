import Foundation

/// Цветовая арифметика sRGB одним местом (ревизия WF247, Z7-DU1): разбор `#rrggbb`, HSL, яркость и контраст
/// WCAG, смешение. Ею считают автопокраска, ручки тем, плитки цветов, отсчёт, окно файла и окно поддержки.
public enum ColorMath {
    /// `#rrggbb` или `rrggbb` (пробелы по краям не мешают) → 0xRRGGBB; другое — nil.
    public static func rgb(hex: String) -> UInt32? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 else { return nil }
        return UInt32(text, radix: 16)
    }

    /// Каналы 0…1.
    public static func components(_ value: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// Каналы 0…255 — в 0xRRGGBB.
    public static func value(r: Int, g: Int, b: Int) -> UInt32 {
        UInt32(r & 0xFF) << 16 | UInt32(g & 0xFF) << 8 | UInt32(b & 0xFF)
    }

    /// HSL: тон в градусах 0..<360 (у серого — nil), насыщенность и светлота 0…1.
    public static func hsl(_ value: UInt32) -> (hue: Double?, saturation: Double, lightness: Double) {
        let (r, g, b) = components(value)
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        let lightness = (high + low) / 2
        guard delta > 0 else { return (nil, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if high == r { hue = (g - b) / delta } else if high == g { hue = (b - r) / delta + 2 } else { hue = (r - g) / delta + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }

    /// Относительная яркость WCAG.
    public static func luminance(_ value: UInt32) -> Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = components(value)
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// Контраст WCAG двух яркостей.
    public static func contrast(luminance a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Контраст WCAG двух цветов.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        contrast(luminance: luminance(a), luminance(b))
    }

    /// Смесь двух цветов, как `color-mix(in srgb, a share, b)` страницы: `share` — доля первого, 0…1.
    public static func mix(_ a: UInt32, _ b: UInt32, _ share: Double) -> UInt32 {
        let part = min(max(share, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x * part + y * (1 - part)).rounded())
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }
}
