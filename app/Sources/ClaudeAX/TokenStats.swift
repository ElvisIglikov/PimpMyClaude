import Foundation

// Токены по дням (WF157, #9149; переделка WF170, #9179). Слово Элвиса 09.10 00:15: «Зачем по проектам разделено?
// Никаких накопительных диаграмм… не накапливать по проектам». Окно — итог периода крупно, ОДИН ряд общего расхода
// по дням и отдельно ранжир проектов за период; стопок по проектам нет.
//
// Источник — копилка Рика `Rick/data/tokens-daily.json` (`Rick/tools/token_stats.py`): `hosts.<мак>.days.<день>.
// <проект>` = {in, cw, cr, out, n}; токены = in + cw + cr + out (как у Рика), `hosts.<мак>.scanned` — когда Рик
// собрал. Копилка пополняется только запуском Рика, поэтому дни позже сбора — «ещё не собрано», а не ноль (WF170).
// Пимп файл только читает: Маки складываются. Вид — `TokensWindow.swift`, тесты — `TokensWF157Tests`.

/// Копилка: день («ГГГГ-ММ-ДД») → проект → токены всех Маков.
public struct TokensDaily: Equatable {
    public var days: [String: [String: Int]]
    /// Последний сбор Рика (самый свежий `scanned` среди Маков); нет — неизвестно.
    public var scanned: Date?

    public init(days: [String: [String: Int]] = [:], scanned: Date? = nil) {
        self.days = days
        self.scanned = scanned
    }

    public static let empty = TokensDaily()
    public var isEmpty: Bool { !days.values.contains { $0.values.contains { $0 > 0 } } }

    /// Разбор файла Рика; нет файла или мусор — пусто.
    public static func parse(_ data: Data?) -> TokensDaily {
        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hosts = json["hosts"] as? [String: Any] else { return .empty }
        var out: [String: [String: Int]] = [:]
        var scanned: Date?
        let iso = ISO8601DateFormatter()
        for case let host as [String: Any] in hosts.values {
            if let raw = host["scanned"] as? String, let date = iso.date(from: raw) {
                scanned = max(scanned ?? date, date)
            }
            guard let days = host["days"] as? [String: Any] else { continue }
            for (day, value) in days {
                guard TokenStats.date(day) != nil, let projects = value as? [String: Any] else { continue }
                for (project, raw) in projects {
                    guard let bucket = raw as? [String: Any] else { continue }
                    let sum = ["in", "cw", "cr", "out"].reduce(0) { $0 + max(0, (bucket[$1] as? NSNumber)?.intValue ?? 0) }
                    guard sum > 0 else { continue }
                    out[day, default: [:]][project, default: 0] += sum
                }
            }
        }
        return TokensDaily(days: out, scanned: scanned)
    }

    /// Сумма дня по проектам.
    public func total(_ day: String) -> Int { days[day]?.values.reduce(0, +) ?? 0 }

    /// День ещё не собран: Рик собирал раньше, чем этот день начался. Сбор неизвестен — считаем собранным.
    public func isPending(_ day: String, calendar: Calendar = .current) -> Bool {
        guard let scanned = scanned, let date = TokenStats.date(day, calendar: calendar) else { return false }
        return scanned < calendar.startOfDay(for: date)
    }
}

/// Период сверху окна.
public enum TokenPeriod: String, CaseIterable {
    case today, yesterday, week, month

    public var title: String {
        switch self {
        case .today: return "Сегодня"
        case .yesterday: return "Вчера"
        case .week: return "7 дней"
        case .month: return "Месяц"
        }
    }

    /// Для сравнения: «против …».
    public var previousTitle: String {
        switch self {
        case .today: return "вчера"
        case .yesterday: return "позавчера"
        case .week: return "прошлых 7 дней"
        case .month: return "прошлых 30 дней"
        }
    }

    public var isSingleDay: Bool { self == .today || self == .yesterday }

    private var span: (offset: Int, length: Int) {
        switch self {
        case .today: return (0, 1)
        case .yesterday: return (1, 1)
        case .week: return (0, 7)
        case .month: return (0, 30)
        }
    }

    private func days(back: Int, now: Date, calendar: Calendar) -> [String] {
        let today = calendar.startOfDay(for: now)
        let first = span.offset + back
        return (first..<(first + span.length)).reversed()
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .map { TokenStats.key($0, calendar: calendar) }
    }

    /// Дни периода по порядку; «7 дней» и «Месяц» (30 дней) кончаются сегодня.
    public func days(now: Date, calendar: Calendar = .current) -> [String] {
        days(back: 0, now: now, calendar: calendar)
    }

    /// Прошлый такой же период: вчера → позавчера, 7 дней → 7 дней до них.
    public func previousDays(now: Date, calendar: Calendar = .current) -> [String] {
        days(back: span.length, now: now, calendar: calendar)
    }
}

/// Столбик — день или неделя (только для «Месяца»).
public enum TokenGrouping: String, CaseIterable {
    case days, weeks
    public var title: String { self == .days ? "Дни" : "Недели" }
}

/// Столбик главного графика: общий расход дня (недели), без деления на проекты.
public struct TokenPoint: Equatable, Identifiable {
    /// Первый день столбика.
    public let id: String
    /// Подпись под столбиком: «8» или «29 сен – 5 окт».
    public let label: String
    /// День недели под числом («чт»); у недели — пусто.
    public let weekday: String
    /// Для подсказки: «8 октября, чт» или «29 сентября – 5 октября».
    public let title: String
    public let value: Int
    /// Ни один день столбика ещё не собран Риком — не ноль, а «ещё не собрано».
    public let pending: Bool
}

/// Строка ранжира: проект за период.
public struct TokenRank: Equatable {
    public let project: String
    public let value: Int
    /// Доля от итога периода, 0…1.
    public let share: Double
    /// «47%», «<1%» — ноль у ненулевого проекта не пишем.
    public var percent: String { TokenStats.percent(share) }
}

public struct TokenSummary: Equatable {
    public let period: TokenPeriod
    public let total: Int
    /// Итог прошлого такого же периода.
    public let previous: Int
    public let points: [TokenPoint]
    /// Проекты по убыванию за период, все.
    public let ranking: [TokenRank]
    /// Столбик с наибольшим расходом (подпись числа над пиком).
    public let peak: String?
    /// В периоде есть дни, которые Рик ещё не собрал.
    public let pending: Bool
    /// Весь период ещё не собран (итог «—», не «0»).
    public var allPending: Bool { !points.isEmpty && points.allSatisfy { $0.pending } }
}

/// Плитка в панели: 7 дней общего расхода, nil — день ещё не собран.
public struct TokenSpark: Equatable {
    public let values: [Int?]
    public let scanned: Date?
    public var today: Int? { values.last ?? nil }
    /// За 7 дней ни одного токена (файл пуст или Рик давно не собирал) — линии нет, в плитке «нет данных».
    public var isEmpty: Bool { !values.contains { ($0 ?? 0) > 0 } }
    /// «68 млн»; пока Рик сегодня не собирал — «не собрано», за неделю пусто — «нет данных» (WF177, #9182 п. 8:
    /// «токены показывают ноль… графика нет» — прочерк и ноль понятны не были).
    public var todayText: String {
        if isEmpty { return "нет данных" }
        return today.map(TokenStats.human) ?? "не собрано"
    }
}

public enum TokenStats {
    /// Путь к копилке — настройка (UserDefaults); нет — `<корень проектов>/Rick/data/tokens-daily.json`.
    public static let pathKey = "tokensDailyPathWF157"
    public static let relativePath = "Rick/data/tokens-daily.json"

    public static func url(defaults: UserDefaults = .standard, root: URL) -> URL {
        if let raw = defaults.string(forKey: pathKey)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
        }
        return root.appendingPathComponent(relativePath)
    }

    /// Живой путь: настройка или папка Рика в корне проектов (`projectsRoot` из claude.json).
    public static func liveURL(defaults: UserDefaults = .standard) -> URL {
        url(defaults: defaults, root: StatusFeed.projectsRoot())
    }

    // MARK: дни

    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd"
        return format
    }

    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar).string(from: date)
    }

    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        guard key.count == 10 else { return nil }
        return formatter(calendar).date(from: key)
    }

    static let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября",
                         "октября", "ноября", "декабря"]
    static let shortMonths = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    static let weekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]

    /// «8 октября, чт».
    public static func dayTitle(_ key: String, calendar: Calendar = .current) -> String {
        guard let date = date(key, calendar: calendar) else { return key }
        let parts = calendar.dateComponents([.day, .month, .weekday], from: date)
        return "\(parts.day ?? 0) \(months[(parts.month ?? 1) - 1]), \(weekdays[(parts.weekday ?? 1) - 1])"
    }

    private static func short(_ key: String, calendar: Calendar, long: Bool) -> String {
        guard let date = date(key, calendar: calendar) else { return key }
        let parts = calendar.dateComponents([.day, .month], from: date)
        let month = (long ? months : shortMonths)[(parts.month ?? 1) - 1]
        return "\(parts.day ?? 0) \(month)"
    }

    /// «собрано в 23:19» (сегодня), «собрано вчера в 23:19», «собрано 6 окт в 12:00»; сбор неизвестен — пусто.
    public static func scannedText(_ scanned: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let scanned = scanned else { return "" }
        let time = DateFormatter()
        time.locale = Locale(identifier: "ru_RU")
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"
        let at = "в " + time.string(from: scanned)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: scanned),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "собрано " + at }
        if days == 1 { return "собрано вчера " + at }
        return "собрано " + short(key(scanned, calendar: calendar), calendar: calendar, long: false) + " " + at
    }

    // MARK: числа

    /// «1,2 млн», «340 млн», «2,4 млрд», «12 тыс» — как у Рика (`fmt`).
    public static func human(_ value: Int) -> String {
        let v = Double(value)
        func one(_ x: Double) -> String { String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",") }
        if v >= 1e9 { return one(v / 1e9) + " млрд" }
        if v >= 1e8 { return String(format: "%.0f", v / 1e6) + " млн" }
        if v >= 1e6 { return one(v / 1e6) + " млн" }
        if v >= 1e3 { return String(format: "%.0f", v / 1e3) + " тыс" }
        return String(value)
    }

    /// Доля в процентах; ненулевая, но меньше полпроцента — «<1%», не «0%» (WF170: «почему там ноль?»).
    public static func percent(_ share: Double) -> String {
        guard share > 0 else { return "0%" }
        let rounded = Int((share * 100).rounded())
        return rounded == 0 ? "<1%" : "\(rounded)%"
    }

    /// Сравнение с прошлым таким же периодом: «▲ 18% против прошлых 7 дней · было 6,4 млрд». «Сегодня» день не
    /// закончен — без процента, только сколько было вчера; раньше данных нет — пусто.
    public static func comparison(_ summary: TokenSummary) -> String {
        let period = summary.period
        guard summary.previous > 0, !summary.allPending else { return "" }
        let before = human(summary.previous)
        if period == .today { return "вчера за весь день — " + before }
        let change = Int((Double(summary.total - summary.previous) / Double(summary.previous) * 100).rounded())
        let head = change > 0 ? "▲ \(change)%" : change < 0 ? "▼ \(-change)%" : "столько же"
        return head + " против " + period.previousTitle + " · было " + before
    }

    /// Плитка: суммы последних 7 дней, сегодня — последним; не собранный Риком день — nil, не 0.
    public static func spark(_ data: TokensDaily, now: Date, calendar: Calendar = .current) -> TokenSpark {
        let values = TokenPeriod.week.days(now: now, calendar: calendar).map { day -> Int? in
            data.isPending(day, calendar: calendar) ? nil : data.total(day)
        }
        return TokenSpark(values: values, scanned: data.scanned)
    }

    // MARK: итог периода

    /// Итог периода, столбики общего расхода (каждый день сам по себе — не накопительно, без деления на проекты)
    /// и ранжир проектов. Недели (пн–вс, только дни периода) — только у «Месяца».
    public static func summary(_ data: TokensDaily, period: TokenPeriod, grouping: TokenGrouping, now: Date,
                               calendar: Calendar = .current) -> TokenSummary {
        let days = period.days(now: now, calendar: calendar)
        var sums: [String: Int] = [:]
        for day in days { for (project, value) in data.days[day] ?? [:] { sums[project, default: 0] += value } }
        let total = sums.values.reduce(0, +)
        let ranking = sums.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { TokenRank(project: $0.key, value: $0.value, share: Double($0.value) / Double(max(1, total))) }
        let previous = period.previousDays(now: now, calendar: calendar).reduce(0) { $0 + data.total($1) }

        var groups: [[String]] = []
        if grouping == .weeks && period == .month {
            var monday = calendar
            monday.firstWeekday = 2
            var current: [String] = []
            var currentWeek: Date?
            for day in days {
                guard let date = date(day, calendar: calendar),
                      let week = monday.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
                if week != currentWeek, !current.isEmpty { groups.append(current); current = [] }
                currentWeek = week
                current.append(day)
            }
            if !current.isEmpty { groups.append(current) }
        } else {
            groups = days.map { [$0] }
        }

        let points = groups.map { group -> TokenPoint in
            let first = group.first ?? "", last = group.last ?? ""
            let value = group.reduce(0) { $0 + data.total($1) }
            let pending = group.allSatisfy { data.isPending($0, calendar: calendar) }
            if group.count == 1, let date = date(first, calendar: calendar) {
                let parts = calendar.dateComponents([.day, .weekday], from: date)
                return TokenPoint(id: first, label: String(parts.day ?? 0), weekday: weekdays[(parts.weekday ?? 1) - 1],
                                  title: dayTitle(first, calendar: calendar), value: value, pending: pending)
            }
            return TokenPoint(id: first,
                              label: short(first, calendar: calendar, long: false) + " – " + short(last, calendar: calendar, long: false),
                              weekday: "",
                              title: short(first, calendar: calendar, long: true) + " – " + short(last, calendar: calendar, long: true),
                              value: value, pending: pending)
        }
        let peak = points.filter { $0.value > 0 }.max { $0.value < $1.value }?.id
        return TokenSummary(period: period, total: total, previous: previous, points: points, ranking: ranking,
                            peak: peak, pending: points.contains { $0.pending })
    }
}

/// Чтение копилки с кэшем по mtime: файл не менялся — тот же разбор.
public final class TokensDailyStore {
    public let url: URL
    private var stamp: Date?
    private var cached = TokensDaily.empty
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public func load(fileManager: FileManager = .default) -> TokensDaily {
        lock.lock(); defer { lock.unlock() }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let mtime = attributes[.modificationDate] as? Date else {
            stamp = nil
            cached = .empty
            return cached
        }
        if mtime != stamp {
            cached = TokensDaily.parse(try? Data(contentsOf: url))
            stamp = mtime
        }
        return cached
    }
}
