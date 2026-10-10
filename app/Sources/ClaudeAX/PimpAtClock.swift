import CoreGraphics
import Foundation

// Пимп у часов (WF87, батч C, выбор `docs/10-choice.md`): чистая часть значка и вылетающей
// панели — что рисовать и какими словами. Рисует и показывает таргет PimpMyClaude
// (`StatusIcon.swift`, `PimpPanel.swift`); здесь только решения, их и гоняют тесты
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

    /// Для `ClaudeUpdateMenu.shouldOffer` и `needsConfirm`: nil — не знаем (это не «не работает»).
    public var anyPageWorking: Bool? { workingChats.map { $0 > 0 } }

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

// MARK: - значок у часов

public enum StatusIcon {
    /// UserDefaults: что на значке. По умолчанию — неделя.
    public static let modeKey = "statusIconMode"
    /// Цифры старше — «нет цифр».
    public static let staleSeconds: TimeInterval = 600

    public enum Mode: String, CaseIterable {
        case week, fiveHour, fable, three, plain, percent
    }

    public enum Mark: Equatable { case none, patchLost, updateReady }

    /// Состояние патча глазами значка и панели (зеркало `ClaudeState` из Patcher).
    public enum Patch: Equatable {
        case claudeNotFound
        case notInstalled(version: String)
        /// `reason` — причина из `Patcher.state()` («Claude обновился», «старый лоадер v6»…).
        case lost(version: String, reason: String = PimpPanelText.claudeUpdatedReason)
        case installed(version: String, loader: Int)
        /// Ещё не проверяли — рисуем как «стоит», чтобы значок не мигал на старте.
        case unknown
    }

    public enum Level: Equatable { case normal, low, critical }

    /// Что рисует значок (`StatusIconView` в таргете приложения).
    public struct Look: Equatable {
        public var mode: Mode
        /// Не пропатчен / Claude не найден: бейдж контуром, числа нет.
        public var outlined = false
        /// Ставлю обновление — крутилка вместо числа.
        public var spinner = false
        public var mark: Mark = .none
        /// Число «израсходовано», как пишет сам Claude (#7863); nil при `showsNumber` — прочерк.
        public var number: Int?
        public var showsNumber = false
        /// Режим «три полоски»: 5 часов, неделя, Fable — израсходовано (#7863, как число), nil — только дорожка.
        public var bars: [Int?] = []
        /// Цвет каждой из трёх полосок — по остатку (как у числа, 8adc156).
        public var barLevels: [Level] = []
        public var level: Level = .normal
        public var width: CGFloat = 26
        public var toolTip = ""
        /// Вид «Проекты» (WF129, #9077): строка сводки вместо числа, ширину считает кисть по тексту.
        public var text: String?
        /// Плашка «PMP» слева (WF174): false — только цифры строки `text`.
        public var badge = true
        /// Полоска под процентами без плашки (WF189, «проценты с полоской»).
        public var underline = false
    }

    /// UserDefaults: вид значка — `week` (умолчание, «PMP + неделя») или `projects` (сводка всех проектов).
    public static let viewKey = "statusIconViewWF129"

    public static func showsProjects(_ raw: String?) -> Bool { raw == "projects" }

    public static let weekKey = "statusIconWeekWF174"
    public static let lettersKey = "statusIconLettersWF174"

    /// Вариант значка (WF180: «нужен просто выбор значков, несколько вариантов, как раньше было»; WF189, слово Элвиса
    /// 09.10 04:00: проценты из строки меню пропали — вернуть выбор, вариантов было много: «только проценты с полоской,
    /// надпись PMP с полоской, только недельная, PMP и недельная»): картинка из нескольких, человек выбирает; по умолчанию — `week`
    /// («PMP и неделя», как с WF126). Порядок — рядами сетки по четыре: неделя, другие лимиты, проекты.
    /// Сырые значения `pmp`, `bars`, `projects`, `digits` — те же, что у WF180.
    public enum Variant: String, CaseIterable {
        case week, pmpBar, percentBar, percent, pmp, bars, fiveHour, fable, projects, digits

        public var name: String {
            switch self {
            case .week: return "PMP и неделя"
            case .pmpBar: return "PMP с полоской недели"
            case .percentBar: return "Проценты недели с полоской"
            case .percent: return "Только проценты недели"
            case .pmp: return "Только PMP"
            case .bars: return "Три полоски: 5 часов, неделя, Fable"
            case .fiveHour: return "PMP и 5 часов"
            case .fable: return "PMP и Fable"
            case .projects: return "PMP и проекты"
            case .digits: return "Только проекты"
            }
        }

        /// Режим картинки до `compose`: число лимита — `week`/`fiveHour`/`fable`, проценты без плашки — `percent`,
        /// полоски — `three`, плашка без числа — `plain`.
        public var mode: Mode {
            switch self {
            case .week, .pmpBar: return .week
            case .percentBar, .percent: return .percent
            case .bars: return .three
            case .fiveHour: return .fiveHour
            case .fable: return .fable
            case .pmp, .projects, .digits: return .plain
            }
        }

        public var showsProjects: Bool { self == .projects || self == .digits }
    }

    public static let variantKey = "statusIconWF189"
    /// Выбор WF180 (без числа недели) — переводится в ближайший вариант WF189.
    public static let variantKeyWF180 = "statusIconWF180"

    /// Выбор; ключа нет — по прежним настройкам: WF180 `pmp` (плашка без числа — так было у всех, число сняли
    /// насильно) — «PMP и неделя», остальные WF180 — те же; без WF180 — по выключателям WF174 (проекты — с буквами или
    /// без, неделя выключена — «Только PMP», без букв — «Только проценты»); ничего — «PMP и неделя».
    public static func variant(_ defaults: UserDefaults = .standard) -> Variant {
        if let raw = defaults.string(forKey: variantKey), let variant = Variant(rawValue: raw) { return variant }
        switch defaults.string(forKey: variantKeyWF180) {
        case "pmp": return .week
        case "bars": return .bars
        case "projects": return .projects
        case "digits": return .digits
        default: break
        }
        let letters = (defaults.object(forKey: lettersKey) as? Bool) ?? true
        if showsProjects(defaults.string(forKey: viewKey)) { return letters ? .projects : .digits }
        if (defaults.object(forKey: weekKey) as? Bool) == false { return .pmp }
        return letters ? .week : .percent
    }

    public static func saveVariant(_ variant: Variant, _ defaults: UserDefaults = .standard) {
        defaults.set(variant.rawValue, forKey: variantKey)
    }

    /// Значок по варианту. Без патча и во время установки Claude — как был (плашка говорит о беде). Проекты — сводка
    /// справа от плашки (`digits` — без плашки); `summary` nil — проекты ещё не читали («…»). «PMP с полоской» —
    /// одна полоска недели вместо числа; «проценты с полоской» — полоска под процентами.
    public static func compose(_ look: Look, variant: Variant, summary: String?, toolTip: String) -> Look {
        guard !look.outlined, !look.spinner else { return look }
        var out = look
        switch variant {
        case .projects, .digits:
            out = withProjects(look, summary: summary ?? "…", toolTip: toolTip)
            out.badge = variant == .projects
        case .pmpBar:
            out.bars = [look.number]
            out.barLevels = [look.level]
            out.showsNumber = false
            out.number = nil
            out.width = 47
        case .percentBar:
            out.underline = true
        default:
            break
        }
        return out
    }

    /// Значок шапки панели (WF181, #9217: «Убери „PMP 39“ — зачем дублировать, просто значок отобрази»): только
    /// плашка PMP — без числа, полосок и сводки проектов; беда (контур, метка, крутилка установки) остаётся.
    public static func badgeOnly(_ look: Look) -> Look {
        guard !look.outlined, !look.spinner else { return look }
        var out = look
        out.mode = .plain
        out.showsNumber = false
        out.number = nil
        out.bars = []
        out.barLevels = []
        out.text = nil
        out.badge = true
        out.width = look.mark == .none ? 25 : 28
        return out
    }

    /// Сводка проектов вместо числа недели; без патча и во время установки Claude — значок как был.
    public static func withProjects(_ look: Look, summary: String, toolTip: String) -> Look {
        guard !look.outlined, !look.spinner else { return look }
        var out = look
        out.showsNumber = false
        out.number = nil
        out.bars = []
        out.text = summary
        out.toolTip = look.mark == .patchLost ? "PMP — патч слетел. " + toolTip : toolTip
        return out
    }

    public static func mode(_ raw: String?) -> Mode { raw.flatMap(Mode.init(rawValue:)) ?? .week }

    /// Осталось = 100 − used, зажато 0…100; сброс уже прошёл — 100.
    public static func remaining(_ limit: ClaudeLimits.Limit?, now: Date) -> Int? {
        guard let limit = limit else { return nil }
        if let reset = limit.resetsAt, reset <= now { return 100 }
        return min(100, max(0, 100 - limit.used))
    }

    /// Израсходовано = 100 − осталось (слово Элвиса 26.09, #7863: «у Claude показывается 44 % — и мы так же»):
    /// зажато 0…100, сброс уже прошёл — 0.
    public static func used(_ limit: ClaudeLimits.Limit?, now: Date) -> Int? {
        remaining(limit, now: now).map { 100 - $0 }
    }

    /// Цифры годятся: есть источник и они не старше 10 минут.
    public static func isFresh(_ limits: ClaudeLimits?, now: Date) -> Bool {
        guard let limits = limits, limits.source != nil, let at = limits.at else { return false }
        return now.timeIntervalSince(at) <= staleSeconds
    }

    /// Какой лимит главный в режиме: `three` и `plain` — неделя; Fable на тарифе без Fable
    /// (`source == "api"`, поля нет) — тоже неделя.
    public static func mainKind(_ mode: Mode, _ limits: ClaudeLimits?) -> Mode {
        switch mode {
        case .fiveHour: return .fiveHour
        case .fable:
            if let limits = limits, limits.fable == nil, limits.source == "api" { return .week }
            return .fable
        case .week, .three, .plain, .percent: return .week
        }
    }

    public static func limit(_ kind: Mode, in limits: ClaudeLimits?) -> ClaudeLimits.Limit? {
        guard let limits = limits else { return nil }
        switch kind {
        case .fiveHour: return limits.fiveHour
        case .fable: return limits.fable
        default: return limits.weekly
        }
    }

    public static func level(_ remaining: Int?) -> Level {
        guard let left = remaining else { return .normal }
        if left <= 10 { return .critical }
        if left <= 20 { return .low }
        return .normal
    }

    /// Имя лимита строчными — подсказка и меню.
    public static func name(_ kind: Mode) -> String {
        switch kind {
        case .fiveHour: return "5 часов"
        case .fable: return "Fable"
        default: return "неделя"
        }
    }

    public static func look(mode: Mode, limits: ClaudeLimits?, patch: Patch, phase: ClaudeUpdateMenu.Phase,
                            now: Date, calendar: Calendar = .current) -> Look {
        var look = Look(mode: mode)
        if mode == .percent { look.width = 22 }
        let fresh = isFresh(limits, now: now) ? limits : nil
        switch patch {
        case .claudeNotFound:
            look.outlined = true
            look.toolTip = "PMP — Claude не найден"
            return look
        case .notInstalled(let version):
            look.outlined = true
            look.toolTip = "PMP — Claude \(version) пока без патча"
            return look
        case .lost:
            look.mark = .patchLost
        case .installed, .unknown:
            if case .ready = phase { look.mark = .updateReady }
        }
        if case .installing(let version) = phase {
            look.spinner = true
            look.width = mode == .percent ? 22 + (look.mark == .none ? 0 : 10) : 41
            look.toolTip = "PMP — ставлю Claude \(version)"
            return look
        }
        switch mode {
        case .plain:
            // Плашка 23 pt и по пикселю с краёв (WF180: «много пустоты слева и справа»); метке в углу — место справа.
            look.width = look.mark == .none ? 25 : 28
        case .three:
            look.width = 47
            let three = [fresh?.fiveHour, fresh?.weekly, fresh?.fable]
            look.bars = three.map { used($0, now: now) }
            look.barLevels = three.map { level(remaining($0, now: now)) }
        case .week, .fiveHour, .fable, .percent:
            let kind = mainKind(mode, fresh)
            look.showsNumber = true
            look.number = used(limit(kind, in: fresh), now: now)
            look.level = level(remaining(limit(kind, in: fresh), now: now))
            if mode == .percent {
                let label = look.number.map { "\($0)%" } ?? "—"
                look.width = max(22, CGFloat(label.count) * 8.5 + 4) + (look.mark == .none ? 0 : 10)
            } else { look.width = look.number == 100 ? 52 : 45 }
        }
        look.toolTip = toolTip(mode: mode, limits: fresh, now: now, calendar: calendar)
        if look.mark == .patchLost { look.toolTip = "PMP — патч слетел. " + look.toolTip }
        return look
    }

    /// «PMP — неделя: израсходовано 77 % · сброс пт 08:00»; нет цифр — «лимиты придут…».
    public static func toolTip(mode: Mode, limits: ClaudeLimits?, now: Date, calendar: Calendar = .current) -> String {
        let kind = mainKind(mode, limits)
        guard let lim = limit(kind, in: limits), let spent = used(lim, now: now) else {
            return "PMP — лимиты придут, когда откроется окно Claude"
        }
        let reset = resetText(lim.resetsAt, now: now, calendar: calendar).map { " · \($0)" } ?? ""
        return "PMP — \(name(kind)): израсходовано \(spent) %\(reset)"
    }

    /// Пункт правого меню: «Неделя — 77 %» (израсходовано); нет цифр — без « — N %».
    public static func menuTitle(_ mode: Mode, limits: ClaudeLimits?, now: Date) -> String {
        let fresh = isFresh(limits, now: now) ? limits : nil
        let base: String
        switch mode {
        case .week: base = "Неделя"
        case .fiveHour: base = "5 часов"
        case .fable: base = "Fable"
        case .three: return "Три полоски"
        case .plain: return "Только PMP"
        case .percent: return "Только % · неделя"
        }
        guard let spent = used(limit(mode, in: fresh), now: now) else { return base }
        return "\(base) — \(spent) %"
    }

    /// «сброс через 58 мин» / «сброс через 3 ч 12 мин» (меньше суток) / «сброс пт 08:00».
    /// Нет времени или сброс прошёл — nil.
    public static func resetText(_ date: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let raw = date, raw > now else { return nil }
        // До ближайшей минуты (#8896): 07:59:59 и 08:00:00 — один сброс, а писались как 07:59 и 08:00.
        let date = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let seconds = raw.timeIntervalSince(now)
        if seconds < 24 * 3600 {
            let minutes = max(1, Int((seconds / 60).rounded(.up)))
            if minutes < 60 { return "сброс через \(minutes) мин" }
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "сброс через \(hours) ч" : "сброс через \(hours) ч \(rest) мин"
        }
        let days = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let day = days[((parts.weekday ?? 1) - 1 + 7) % 7]
        return String(format: "сброс %@ %02d:%02d", day, parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Полоса недели (#8881): семь суточных отрезков до сброса недельного лимита и срок словами — тот же
    /// счёт, что страница рисует в панели лимитов Claude (`usageWeekParts`, `usageLong` в inject.js).
    public struct WeekStrip: Equatable {
        /// Доля прошедшего в каждом из семи отрезков, 0…1.
        public let fills: [Double]
        /// Подписи дней: день, с которого отрезок начинается («Пт» … «Чт»).
        public let days: [String]
        /// Отрезок, в котором «сейчас».
        public let today: Int?
        /// «2 дня 7 часов» / «5 часов» / «12 минут».
        public let left: String
    }

    /// Нет времени сброса или он прошёл — nil.
    public static func weekStrip(_ date: Date?, now: Date, calendar: Calendar = .current) -> WeekStrip? {
        guard let date = date, date > now else { return nil }
        let names = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
        let edges = (0...7).map { calendar.date(byAdding: .day, value: $0 - 7, to: date) ?? date.addingTimeInterval(Double($0 - 7) * 86_400) }
        var fills: [Double] = [], days: [String] = [], today: Int?
        for index in 0..<7 {
            let from = edges[index], span = edges[index + 1].timeIntervalSince(from)
            fills.append(span > 0 ? min(1, max(0, now.timeIntervalSince(from) / span)) : 0)
            days.append(names[(calendar.component(.weekday, from: from) - 1 + 7) % 7])
            if now >= from && now < edges[index + 1] { today = index }
        }
        return WeekStrip(fills: fills, days: days, today: today, left: longText(date.timeIntervalSince(now)))
    }

    private static func longText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int((seconds / 60).rounded()))
        let days = total / 1440, hours = (total % 1440) / 60, minutes = total % 60
        func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
            let tens = n % 100, ones = n % 10
            if tens >= 11 && tens <= 14 { return many }
            return ones == 1 ? one : (ones >= 2 && ones <= 4 ? few : many)
        }
        var parts: [String] = []
        if days > 0 { parts.append("\(days) \(plural(days, "день", "дня", "дней"))") }
        if hours > 0 { parts.append("\(hours) \(plural(hours, "час", "часа", "часов"))") }
        if days == 0 && minutes > 0 { parts.append("\(minutes) \(plural(minutes, "минута", "минуты", "минут"))") }
        return parts.isEmpty ? "меньше минуты" : parts.joined(separator: " ")
    }
}

// MARK: - вылетающая панель

public enum PimpPanelText {
    /// Карточка «одна кнопка» (не пропатчен, слетел, Claude не найден). У «всё хорошо» — nil.
    public struct PatchCard: Equatable {
        public let title: String
        public let text: String
        public let button: String
        public let footnote: String
    }

    /// Предупреждение перед обновлением и патчем Claude (WF210, #9382; смысл — `docs/audit-security-2026-10-10.md`,
    /// раздел «Окно „Claude хочет…“»): патч заменяет подпись Claude локальной, и macOS заново спрашивает доступ к
    /// записи «Claude Safe Storage». Коротко — панель лёгкая; без ссылок (репозиторий закрыт).
    public static let keychainNote = "Потом macOS спросит про «Claude Safe Storage» в связке ключей — это нормально: "
        + "PMP заново подписывает Claude, и macOS переспрашивает. Пароль получает macOS, не PMP. "
        + "Нажми «Разрешать всегда»."

    public static func patchCard(_ patch: StatusIcon.Patch) -> PatchCard? {
        switch patch {
        case .notInstalled:
            return PatchCard(title: "Claude пока без патча PMP",
                             text: "Узкие окна, темы, полоска работы и отсчёт отправки — после одного нажатия.",
                             button: "Пропатчить Claude", footnote: "Claude закроется и откроется сам · ~10 с")
        case .lost(_, let reason) where reason == oldLoaderReason:
            return PatchCard(title: "Окна не опознаются — нужен «Вернуть патч» (старый лоадер)",
                             text: "Страницы Claude отвечают без печати нового лоадера, и PMP им не верит: темы окна, "
                                 + "новый чат, отправка и раскладки молчат.",
                             button: "Вернуть патч",
                             footnote: "Claude закроется и откроется сам · ~10 с · окна вернутся")
        case .lost(_, let reason):
            return PatchCard(title: reason == claudeUpdatedReason ? "Claude обновился — патч слетел"
                                                                  : "Патч слетел: \(reason)",
                             text: "Темы, узкие окна и полоска работы сейчас молчат. Настройки целы.",
                             button: "Вернуть патч",
                             footnote: "Claude закроется и откроется сам · ~10 с · окна вернутся")
        case .claudeNotFound:
            return PatchCard(title: "Claude не найден",
                             text: "Поставь Claude с claude.ai/download или покажи, где он лежит.",
                             button: "Найти Claude…", footnote: "Скачать Claude")
        case .installed, .unknown:
            return nil
        }
    }

    /// Строка шапки (#8894): «Max 20x · Claude 2.19675.0 · PimpMyClaude 1.9.23» — план первым, номера лоадера
    /// нет. С WF126 о беде с патчем говорит только карточка патча — в шапке тогда одни версии, без плана
    /// (Claude не найден — только версия приложения). `app` пуст — без версии приложения.
    public static func headerLine(_ patch: StatusIcon.Patch, plan: String?, app: String = "") -> String {
        let claude: String?
        var first = plan
        switch patch {
        case .claudeNotFound: claude = nil; first = nil
        case .notInstalled(let version), .lost(let version, _): claude = "Claude \(version)"; first = nil
        // Ещё не проверили — ни слова в строке (WF181, #9217: без «…»), «Проверяю Claude» — в подсказке.
        case .unknown: claude = nil; first = nil
        case .installed(let version, _): claude = "Claude \(version)"
        }
        return [first, claude, app.isEmpty ? nil : "PMP \(app)"].compactMap { $0 }.joined(separator: " · ")
    }

    /// Подсказка строки шапки: пока Claude не проверен — «Проверяю Claude»; иначе подсказки нет.
    public static func headerHelp(_ patch: StatusIcon.Patch) -> String {
        if case .unknown = patch { return "Проверяю Claude" }
        return ""
    }

    public static func loaderText(_ loader: Int) -> String { "\(loader).0" }

    /// Причина `.lost`, при которой говорим «Claude обновился» (как пишет `Patcher.state()`).
    public static let claudeUpdatedReason = "Claude обновился"
    /// Причина `.lost` по ответам самих страниц (WF111): отвечает только старый лоадер — патч на
    /// диске мог и встать, а Claude живёт прежним (не перезапущен, перепатч сорвался).
    public static let oldLoaderReason = "старый лоадер"

    /// Вид патча с поправкой на ответы страниц: они говорят «старый лоадер» — это `.lost`,
    /// что бы ни лежало на диске. Не найден и не пропатчен — как есть.
    public static func patch(_ patch: StatusIcon.Patch, needsRepatch: Bool) -> StatusIcon.Patch {
        guard needsRepatch else { return patch }
        switch patch {
        case .installed(let version, _), .lost(let version, _): return .lost(version: version, reason: oldLoaderReason)
        case .claudeNotFound, .notInstalled, .unknown: return patch
        }
    }

    /// Уведомление «патч слетел» — по причине (z7-s03): «обновился» только когда Claude и правда обновился.
    public static func patchLostNotice(version: String, reason: String) -> String {
        let what = reason == claudeUpdatedReason ? "Claude \(version) обновился — патч слетел"
                                                 : "Патч слетел (\(reason)) · Claude \(version)"
        return what + ". Одно нажатие — всё вернётся."
    }

    // MARK: подсказки выключателей

    /// Как ведёт себя маяк окон доступа (`ConsentBeaconStyle.choose`): вода — только на втором мониторе.
    public static let consentToolTip = "На втором мониторе окно «приложение запрашивает доступ» обводит фиолетовая вода, "
        + "у курсора — окошко, клик ведёт курсор к окну. На одном мониторе окно и так на виду — ничего не показываю. "
        + "Нажимаешь в нём ты."

    /// Гигабайты с одной десятичной через запятую: 2 800 000 000 → «2,8».
    public static func gigabytesText(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(max(0, bytes)) / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
    }

    /// Фоновой загрузке обновления не хватило места (z6-r06).
    public static func noSpaceText(needed: Int64, free: Int64) -> String {
        "мало места на диске: нужно \(gigabytesText(needed)) ГБ, свободно \(gigabytesText(free)) ГБ"
    }

    /// Текст кнопки патча по строке журнала `Patcher`; nil — строка не про шаг.
    public static func patchStep(_ line: String, loader: Int) -> String? {
        if line.contains("Открываю Claude") { return "Открываю Claude…" }
        // Промпт macOS «Управление приложениями» (`Patcher.waitForWritable`) — шаг ждёт человека.
        if line.contains("Управление приложениями") { return "Нажми «Разрешить» в окне macOS…" }
        if line.hasPrefix("Ставлю лоадер") || line.hasPrefix("Сохраняю оригинал") || line.hasPrefix("Ставлю патч")
            || line.hasPrefix("Возвращаю оригинальные") { return "Ставлю патч \(loaderText(loader))…" }
        if line.hasPrefix("Закрываю Claude") { return "Закрываю Claude…" }
        return nil
    }

    // MARK: блок обновления Claude

    /// Что показывает блок обновления (§3.3 выбора).
    public enum UpdateBlock: Equatable {
        case none
        /// Вышло новее; `canWrite == false` — кнопки нет, «поставь сам»; `note` — почему фон не скачал.
        case available(version: String, canWrite: Bool, note: String?)
        case downloading(ClaudeUpdateMenu.Race)
        /// Гонка кончилась, идёт проверка подписи; `from` — чья дорожка победила.
        case verifying(version: String, from: String?)
        /// Скачалось; `question` — вопрос «идёт работа…» прямо в блоке.
        case ready(version: String, question: String?)
        /// «Самое время» и причина словами.
        case timely(version: String, reason: String)
        case snoozed
        case installing(version: String, step: Int)
        case done(version: String)
        case failed(String)
    }

    /// Состояние панели поверх машины `ClaudeUpdateMenu`: что добавляет сама панель —
    /// «самое время», вопрос перед закрытием, «Позже», шаг установки, «готово» и сбой установки.
    public struct UpdateExtras: Equatable {
        public var offerReason: String?
        public var question: String?
        public var snoozedShown = false
        public var installStep = 0
        public var doneVersion: String?
        public var installFailure: String?

        public init(offerReason: String? = nil, question: String? = nil, snoozedShown: Bool = false,
                    installStep: Int = 0, doneVersion: String? = nil, installFailure: String? = nil) {
            self.offerReason = offerReason
            self.question = question
            self.snoozedShown = snoozedShown
            self.installStep = installStep
            self.doneVersion = doneVersion
            self.installFailure = installFailure
        }
    }

    public static func updateBlock(_ menu: ClaudeUpdateMenu, _ extras: UpdateExtras) -> UpdateBlock {
        if extras.snoozedShown { return .snoozed }
        switch menu.phase {
        case .installing(let version):
            return .installing(version: version, step: extras.installStep)
        case .downloading(let race):
            if let won = race.lanes.first(where: { $0.state == .won }) {
                return .verifying(version: race.version, from: laneName(won))
            }
            return .downloading(race)
        default:
            break
        }
        // Сбой установки виден, пока его не сняли «Ещё раз» — и поверх вернувшегося готового.
        if let why = extras.installFailure { return .failed(why) }
        switch menu.phase {
        case .ready(let version):
            if extras.question == nil, let reason = extras.offerReason { return .timely(version: version, reason: reason) }
            return .ready(version: version, question: extras.question)
        case .available(let version):
            return .available(version: version, canWrite: menu.canWrite,
                              note: menu.lastError.map { "Фоновая загрузка не вышла: \($0)" })
        default:
            if let version = extras.doneVersion { return .done(version: version) }
            return .none
        }
    }

    /// Почему «самое время» — зелёная пилюля.
    public static func offerReason(claudeRunning: Bool, windowCount: Int, idleSeconds: TimeInterval?) -> String {
        if !claudeRunning { return "Claude не запущен" }
        if windowCount == 0 { return "окна Claude закрыты" }
        // Наблюдали меньше 2 минут — минут не называем: «2 мин» было бы неправдой (гейт 2 WF87).
        guard let idle = idleSeconds, idle >= ClaudeUpdateMenu.offerIdleSeconds else { return "никто не работает" }
        return "\(Int(idle / 60)) мин никто не работает"
    }

    /// Вопрос в блоке перед закрытием Claude: работа видна — «Идёт работа в N чатах…»;
    /// работы не видно, но и сказать наверняка нельзя (окна есть, ответа страниц нет).
    public static func confirmQuestion(workingChats: Int?) -> String {
        if let chats = workingChats, chats > 0 { return ClaudeUpdateMenu.confirmWorkingTitle(chats: chats) }
        return "Claude закроется вместе с окнами — обновить сейчас?"
    }

    /// Одно уведомление «Скачалось» на версию: в первый момент «самое время», а не наступил он
    /// за сутки после готовности — всё равно одно.
    public static let notifyAfter: TimeInterval = 24 * 3600

    public static func shouldNotifyReady(version: String, notified: String?, offer: Bool, readySince: Date?,
                                         now: Date) -> Bool {
        guard notified != version else { return false }
        if offer { return true }
        guard let since = readySince else { return false }
        return now.timeIntervalSince(since) >= notifyAfter
    }

    public static func installSteps(version: String, loader: Int) -> [String] {
        ["Закрываю Claude", "Ставлю Claude \(version)", "Ставлю патч \(loaderText(loader))", "Открываю Claude",
         "Окна встают на места"]
    }

    /// Шаг установки по строке журнала `ClaudeUpdater.install`; шаги только растут.
    public static func installStep(_ line: String, current: Int) -> Int {
        let step: Int
        if line.contains("Открываю Claude") {
            step = 3
        } else if line.hasPrefix("Ставлю патч") || line.hasPrefix("Ставлю лоадер") {
            step = 2
        } else if line.hasPrefix("Меняю Claude") {
            step = 1
        } else {
            step = 0
        }
        return max(current, step)
    }

    // MARK: гонка

    /// Имя дорожки вместо `title` контракта.
    public static func laneName(_ lane: ClaudeUpdateMenu.Lane) -> String {
        switch lane.id {
        case "r2": return "Cloudflare"
        case "anthropic": return "Anthropic"
        case "github": return "GitHub"
        case "file": return "С диска"
        default: return lane.title
        }
    }

    /// Дорожки в постоянном порядке.
    public static func orderedLanes(_ lanes: [ClaudeUpdateMenu.Lane]) -> [ClaudeUpdateMenu.Lane] {
        let order = ["r2", "anthropic", "github", "file"]
        return lanes.enumerated().sorted { a, b in
            let x = order.firstIndex(of: a.element.id) ?? order.count
            let y = order.firstIndex(of: b.element.id) ?? order.count
            return x != y ? x < y : a.offset < b.offset
        }.map { $0.element }
    }

    /// Подстрока гонки: первые 5 с — «наперегонки из трёх мест», дальше «осталось ~N мин» по лидеру.
    public static func raceSubtitle(_ race: ClaudeUpdateMenu.Race, elapsed: TimeInterval) -> String {
        if elapsed < 5 {
            let places = [1: "одного места", 2: "двух мест", 3: "трёх мест", 4: "четырёх мест"]
            return "наперегонки из \(places[race.lanes.count] ?? "\(race.lanes.count) мест")"
        }
        let leader = race.lanes.first { $0.state == .leading } ?? race.lanes.filter {
            if case .running = $0.state { return true }
            return false
        }.max { $0.bytesPerSec < $1.bytesPerSec }
        guard let lane = leader, let total = lane.total, lane.bytesPerSec > 0 else { return "наперегонки" }
        let left = Double(max(0, total - lane.bytes)) / lane.bytesPerSec
        if left < 90 { return "наперегонки · осталось ~\(max(5, Int((left / 5).rounded()) * 5)) с" }
        return "наперегонки · осталось ~\(Int((left / 60).rounded())) мин"
    }

    /// «0:36» — время с начала гонки.
    public static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// «212 из 374 МБ»; меньше 10 МБ — с десятыми: «2,7 из 374 МБ».
    public static func bytesText(_ bytes: Int64, total: Int64?) -> String {
        let mb = Double(max(0, bytes)) / 1_000_000
        let done = mb < 10 ? String(format: "%.1f", mb).replacingOccurrences(of: ".", with: ",")
                           : "\(Int(mb))"
        guard let total = total, total > 0 else { return "\(done) МБ" }
        return "\(done) из \(Int((Double(total) / 1_000_000).rounded())) МБ"
    }

    /// Метка дорожки: «лидер», «победил», «ожил — лидер сполз», причина отсева, «сорвался».
    public static func laneBadge(_ lane: ClaudeUpdateMenu.Lane, revived: Bool) -> String? {
        switch lane.state {
        case .leading: return revived ? "ожил — лидер сполз" : "лидер"
        case .running: return revived ? "ожил — лидер сполз" : nil
        case .won: return "победил"
        case .dropped(let why): return why
        case .failed: return "сорвался"
        }
    }
}

/// Память панели о дорожках: «ожила» та, что была отключена и снова бежит (6 с метки).
public struct LaneMemory: Equatable {
    public static let revivedSeconds: TimeInterval = 6
    private var dropped: Set<String> = []
    private var revivedAt: [String: Date] = [:]

    public init() {}

    public mutating func note(_ race: ClaudeUpdateMenu.Race, at now: Date) {
        for lane in race.lanes {
            switch lane.state {
            case .dropped, .failed:
                dropped.insert(lane.id)
            case .running, .leading:
                if dropped.remove(lane.id) != nil { revivedAt[lane.id] = now }
            case .won:
                dropped.remove(lane.id)
            }
        }
    }

    public func isRevived(_ id: String, at now: Date) -> Bool {
        guard let at = revivedAt[id] else { return false }
        return now.timeIntervalSince(at) < Self.revivedSeconds
    }

    public mutating func reset() { self = LaneMemory() }
}
