import CoreGraphics
import Foundation

// Пимп у часов (WF87, батч C, выбор `docs/10-choice.md`): чистая часть значка и вылетающей
// панели — что рисовать и какими словами. Рисует и показывает таргет PimpMyClaude
// (`StatusIcon.swift`, `Panel/*.swift`); здесь только решения, их и гоняют тесты
// (`PanelWF87Tests`).

/// Лимиты подписки из ответа `chats()` главного окна (контракт B:
/// `{v, at, plan, fiveHour, weekly, fable, source}`, лимит — `{used, resetsAt}`).
public struct ClaudeLimits: Equatable {
    public struct Limit: Equatable {
        /// Сколько ИЗРАСХОДОВАНО, 0…100.
        public let used: Int
        public let resetsAt: Date?

        public init(used: Int, resetsAt: Date?) {
            self.used = used
            self.resetsAt = resetsAt
        }
    }

    public let at: Date?
    public let plan: String?
    public let fiveHour: Limit?
    public let weekly: Limit?
    public let fable: Limit?
    /// `api` / `cache` / `label` / `panel`; nil — цифр нет.
    public let source: String?

    public init(at: Date?, plan: String?, fiveHour: Limit?, weekly: Limit?, fable: Limit?, source: String?) {
        self.at = at
        self.plan = plan
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.fable = fable
        self.source = source
    }

    /// Разбор поля `limits` из ответа страницы. Не объект — nil; кривое поле лимита — nil у
    /// этого лимита, остальные живут. Строки обрезаны: они пришли из чужой страницы.
    public static func parse(_ value: Any?) -> ClaudeLimits? {
        guard let map = value as? [String: Any] else { return nil }
        func date(_ raw: Any?) -> Date? {
            guard let ms = (raw as? NSNumber)?.doubleValue, ms.isFinite, ms > 0 else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }
        func limit(_ raw: Any?) -> Limit? {
            guard let lim = raw as? [String: Any], let number = lim["used"] as? NSNumber,
                  number.doubleValue.isFinite else { return nil }
            return Limit(used: min(100, max(0, Int(number.doubleValue.rounded()))), resetsAt: date(lim["resetsAt"]))
        }
        func text(_ raw: Any?, limit: Int) -> String? {
            guard let value = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, value.count <= limit else { return nil }
            return value
        }
        return ClaudeLimits(at: date(map["at"]), plan: text(map["plan"], limit: 40),
                            fiveHour: limit(map["fiveHour"]), weekly: limit(map["weekly"]),
                            fable: limit(map["fable"]), source: text(map["source"], limit: 16))
    }
}

/// Последние известные лимиты (#9824): переживают перезапуск PMP и закрытое окно Claude — вместо «—» панель и значок
/// показывают их бледным и с давностью (`StatusIcon.known`, `staleText`). Хранятся в UserDefaults словарём в формате
/// ответа страницы (`ClaudeLimits.parse` читает его же); новее — то, у чего позже `at`.
public enum LimitsMemory {
    public static let key = "lastLimits9824"

    /// Новее из сохранённых и пришедших: у пришедших без времени или без источника — сохранённые.
    public static func newer(_ stored: ClaudeLimits?, _ live: ClaudeLimits?) -> ClaudeLimits? {
        guard let live = StatusIcon.known(live) else { return StatusIcon.known(stored) ?? live }
        guard let stored = StatusIcon.known(stored), let old = stored.at, let new = live.at else { return live }
        return new >= old ? live : stored
    }

    /// Словарь в формате ответа страницы; пустые поля не пишутся (UserDefaults не берёт NSNull).
    public static func encode(_ limits: ClaudeLimits) -> [String: Any] {
        var out: [String: Any] = [:]
        func put(_ key: String, _ value: Any?, into map: inout [String: Any]) { if let value = value { map[key] = value } }
        func limit(_ value: ClaudeLimits.Limit?) -> [String: Any]? {
            guard let value = value else { return nil }
            var map: [String: Any] = ["used": value.used]
            put("resetsAt", value.resetsAt.map { $0.timeIntervalSince1970 * 1000 }, into: &map)
            return map
        }
        put("at", limits.at.map { $0.timeIntervalSince1970 * 1000 }, into: &out)
        put("plan", limits.plan, into: &out)
        put("fiveHour", limit(limits.fiveHour), into: &out)
        put("weekly", limit(limits.weekly), into: &out)
        put("fable", limit(limits.fable), into: &out)
        put("source", limits.source, into: &out)
        return out
    }

    public static func load(_ defaults: UserDefaults = .standard) -> ClaudeLimits? {
        StatusIcon.known(ClaudeLimits.parse(defaults.dictionary(forKey: key)))
    }

    /// Запомнить, если это новее сохранённого; ответ — что теперь известно.
    @discardableResult
    public static func remember(_ live: ClaudeLimits?, _ defaults: UserDefaults = .standard) -> ClaudeLimits? {
        let stored = load(defaults)
        let best = newer(stored, live)
        if let best = StatusIcon.known(best), best != stored { defaults.set(encode(best), forKey: key) }
        return best
    }
}

/// Что приложение знает о страницах Claude из канала probe: лимиты главного окна и
/// «работает ли чат». Сессии Claude Code без окна сюда не попадают — их не видно.
public struct PageSignals: Equatable {
    public var limits: ClaudeLimits?
    /// Сколько страниц сейчас работает (кнопка стопа видна); nil — свежего ответа нет.
    public var workingChats: Int?
    /// Когда какая-то страница последний раз работала; nil — работы не видели.
    public var lastWorkingAt: Date?
    /// Первый круг после старта Пимпа, где никто не работал (гейт 2 WF87): от него считается тишина,
    /// пока работы не видели ни разу. nil — такого круга ещё не было.
    public var quietSince: Date?
    /// Когда пришёл ответ о работе, из которого `workingChats`; nil — не приходил.
    public var workingAt: Date?
    /// Страницы отвечают только со старым лоадером (WF111): окна не опознаются, нужен «Вернуть патч».
    public var needsRepatch: Bool

    public init(limits: ClaudeLimits? = nil, workingChats: Int? = nil, lastWorkingAt: Date? = nil,
                quietSince: Date? = nil, workingAt: Date? = nil, needsRepatch: Bool = false) {
        self.limits = limits
        self.workingChats = workingChats
        self.lastWorkingAt = lastWorkingAt
        self.quietSince = quietSince
        self.workingAt = workingAt
        self.needsRepatch = needsRepatch
    }

    /// Секунды тишины: с последнего «работает», а работы не видели — с первого тихого круга после
    /// старта. nil — не наблюдали вовсе (это не «давно никто не работает»).
    public func idleSeconds(at now: Date) -> TimeInterval? {
        (lastWorkingAt ?? quietSince).map { max(0, now.timeIntervalSince($0)) }
    }

    /// Только ответ о работе, пришедший не раньше `since` (кнопка «Обновить», гейт 2 WF87): старый —
    /// «не знаем», решать по нему нельзя.
    public func answered(after since: Date) -> PageSignals {
        var copy = self
        if let at = workingAt, at >= since { return copy }
        copy.workingChats = nil
        return copy
    }
}
