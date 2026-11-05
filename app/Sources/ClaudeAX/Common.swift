import Foundation

/// Штамп `at` каналов (`command.json`, `pimp/`, карта тем окон): `2026-10-17T09:30:00Z`, всегда UTC.
enum Stamp {
    static let utc: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()
}

/// Русское множественное число: 1, 21 — `one`; 2–4, 22–24 — `few`; 0, 5–20, 11–14 — `many`. Только слово, без числа.
public enum Plural {
    public static func ru(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if (11...14).contains(n % 100) { return many }
        switch n % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
