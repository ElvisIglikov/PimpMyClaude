import Foundation

/// «🌊 Живые цвета» (план WF18) сняты вместе с меню жёлтой кнопки (WF237, #9524, лист 48 — ответ 2.1): «один раз
/// выключатся у всех». Крутёж страница держит в своём `localStorage` (`myclaude-live-v1`) и поднимает его сама, поэтому
/// у кого он был включён (`liveColors.on` в `UserDefaults`), всем окнам уходит `live-colors {scope:"all", on:false}` —
/// страница возвращает окну прежнюю тему (`restoreTheme`). Правило гашения неона (`WindowThemeStore.retireTick`):
/// Claude не на экране — молчим; не чаще раза в `interval` и не больше `limit` за поколение. Ключи `liveColors.*`
/// стираются, когда за поколение ушли все `limit` отправок; Claude не был запущен — ключи ждут следующего поколения.
/// Снимок настроек для миграций (`AutomationDefaults.migrate`) берётся на запуске раньше — гашение его не трогает.
final class LiveColorsRetire {
    static let action = "live-colors"
    static let onKey = "liveColors.on"
    static let keys = [onKey, "liveColors.mode", "liveColors.period", "liveColors.tone", "liveColors.epoch"]
    /// Выключение — только `scope` и `on:false` (контракт п. 3 плана WF18).
    static func fields() -> [(key: String, value: CommandValue)] {
        [(key: "scope", value: .string(Notices.themeScopeAll)), (key: "on", value: .bool(false))]
    }
    static let limit = 3
    static let interval: TimeInterval = 5

    private let defaults: ThemeDefaults
    private var sent = 0
    private var sentAt: Date?

    init(defaults: ThemeDefaults = UserDefaults.standard) { self.defaults = defaults }

    /// Живые цвета были включены, а гашение не кончилось.
    var pending: Bool { (defaults.object(forKey: LiveColorsRetire.onKey) as? Bool) == true }

    /// Новое поколение: старт приложения или новый Claude.
    func beginGeneration() {
        sent = 0
        sentAt = nil
    }

    @discardableResult
    func tick(titles: [String], at: Date, send: () -> Bool) -> Bool {
        guard pending, sent < LiveColorsRetire.limit, !titles.isEmpty else { return false }
        if let last = sentAt, at.timeIntervalSince(last) < LiveColorsRetire.interval { return false }
        guard send() else { return false }
        sent += 1
        sentAt = at
        if sent >= LiveColorsRetire.limit { LiveColorsRetire.keys.forEach(defaults.removeObject) }
        return true
    }
}
