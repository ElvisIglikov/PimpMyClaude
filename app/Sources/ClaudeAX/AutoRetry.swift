import Foundation

/// «Повторять при ошибке сервера» (#6936, К-AR, `docs/contracts/485-6936-avtopovtor.md`): ход Claude упал с ошибкой
/// сети или сервера — страница сама жмёт «Try again» раз в N минут, не дольше часа (раздел 12е² страницы). Приложение
/// хранит выбор и шлёт его всем страницам: `{"id","action":"auto-retry","at","on":"true"|"false","every":"2"|"5"|"10"}`
/// строками, без адреса окна (как `hide-tools`). Нет ключа — выключено (решение WF108: автонажатие — только по выбору
/// человека); интервал вне 2/5/10 — 5.
public enum AutoRetry {
    public static let onKey = "autoRetryEnabled"
    public static let everyKey = "autoRetryEveryMinutes"
    public static let choices = [2, 5, 10]
    public static let defaultEvery = 5
    static let action = "auto-retry"

    public static let title = "Повторять при ошибке сервера"
    public static let caption = "Ошибка сети или сервера — PMP сам жмёт «Try again» раз в выбранный срок, не дольше часа. Лимит подписки и длинный запрос не повторяет."
    public static let help = "Первый повтор — через выбранный срок после ошибки. 2 минуты — кэш промпта ещё жив, повтор дешевле; неудачный запрос подписку не тратит. Пока ты печатаешь — ждёт."

    /// Интервал в минутах: 2, 5 или 10; всё прочее (нет ключа, 3, 0, мусор) — 5.
    public static func minutes(_ raw: Any?) -> Int {
        let value: Int?
        switch raw {
        case let number as NSNumber: value = number.intValue
        case let text as String: value = Int(text.trimmingCharacters(in: .whitespaces))
        default: value = nil
        }
        guard let minutes = value, choices.contains(minutes) else { return defaultEvery }
        return minutes
    }

    public static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: onKey) }

    public static func every(_ defaults: UserDefaults = .standard) -> Int { minutes(defaults.object(forKey: everyKey)) }

    /// Поля после id, action, at: on, every — строками.
    static func fields(on: Bool, every: Int) -> [(key: String, value: CommandValue)] {
        [(key: "on", value: .string(on ? "true" : "false")), (key: "every", value: .string(String(minutes(every))))]
    }
}

/// Доставка выбора страницам по поколениям — как `AutoContinueSwitch`: до трёх отправок за поколение, «выкл» тоже
/// уходит, чтобы старое `true` в localStorage страницы не пережило выбор человека.
final class AutoRetrySwitch {
    private let delivery = AutoAllowSwitch()
    private(set) var on = false
    private(set) var every = AutoRetry.defaultEvery

    /// true — выбор сменился (и началось новое поколение).
    @discardableResult
    func configure(on: Bool, every: Int) -> Bool {
        let minutes = AutoRetry.minutes(every)
        guard self.on != on || self.every != minutes else { return false }
        self.on = on
        self.every = minutes
        beginGeneration()
        return true
    }

    func beginGeneration() { delivery.beginGeneration() }

    func tick(titles: [String], at: Date, send: ([(key: String, value: CommandValue)]) -> Bool) {
        delivery.tick(titles: titles, at: at) { _ in send(AutoRetry.fields(on: self.on, every: self.every)) }
    }
}

extension AutoRetrySwitch: Generational {}
