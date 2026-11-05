import CoreGraphics
import Foundation

// MARK: - значок у часов

public enum StatusIcon {
    /// Цифры старше — уже не «сейчас»: показываем последнее известное значение бледным и с давностью (#9824).
    public static let staleSeconds: TimeInterval = 600

    public enum Mode: String, CaseIterable {
        case week, fiveHour, fable, three, plain, percent
    }

    /// `accessLost` (#10252) — у Claude слетели доступы macOS: метка-точка, как у слетевшего патча, только оранжевая.
    /// `guardLost` (пожелания 03.11.2026, раздел 0) — сторож контекста не стоит: та же оранжевая точка, слабее доступов.
    public enum Mark: Equatable { case none, patchLost, updateReady, accessLost, guardLost }

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
        /// Каких доступов Claude не хватает (#10252) — названиями для подсказки; не пусто — метка `accessLost`.
        public var access: [String] = []
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
        /// Число — последнее известное, не «сейчас» (#9824): рисуется бледным, давность — в подсказке.
        public var stale = false
        /// Вид «Claude» (WF269, #10220): искра слева, проценты недели «24%», градусы справа — без плашки и полоски.
        public var spark = false
        /// Температура Мака, °C округлённо (WF269); nil — монитор выключен или данных нет: градусов на значке нет.
        public var degrees: Int? = nil
        /// Цвет градусов по `thermalState`: normal — цвет строки меню, low — жёлтый, critical — красный.
        public var heat: Level = .normal

        public init(mode: Mode) { self.mode = mode }
    }

    /// Нагрев словом macOS → цвет градусов (как точка температуры в панели).
    public static func heat(_ state: ProcessInfo.ThermalState) -> Level {
        switch state {
        case .nominal: return .normal
        case .fair: return .low
        default: return .critical
        }
    }

    /// Градусы для значка: последняя точка истории, не старше `maxAge`; nil — без градусов. Холоднее `minimum` и
    /// macOS не говорит «перегрев» (serious/critical) — тоже без градусов (#10289, слово Элвиса 19.10: «если температура у мака ниже 60°
    /// или даже 70. То вообще не надо показывать… только внимание отвлекает»).
    public static func degrees(_ last: MacTemperatureSample?, enabled: Bool, now: Date,
                               maxAge: TimeInterval = 300, minimum: Int = 0) -> (degrees: Int, heat: Level)? {
        guard enabled, let sample = last, let value = sample.value, now.timeIntervalSince(sample.at) <= maxAge else {
            return nil
        }
        let level = heat(sample.state)
        let rounded = Int(value.rounded())
        guard rounded >= minimum || level == .critical else { return nil }
        return (rounded, level)
    }

    /// С какой температуры градусы видны у часов: UserDefaults, умолчание 70; 0 — всегда.
    public static let tempMinKey = "statusIconTempMinWF271"
    public static let tempMinDefault = 70
    public static let tempMinChoices = [0, 50, 60, 70, 80]
    public static func tempMin(_ defaults: UserDefaults = .standard) -> Int {
        guard let value = defaults.object(forKey: tempMinKey) as? Int, tempMinChoices.contains(value) else { return tempMinDefault }
        return value
    }
    public static func tempMinName(_ value: Int) -> String { value == 0 ? "всегда" : "от \(value)°" }

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
        case claude, week, pmpBar, percentBar, percent, pmp, bars, fiveHour, fable, projects, digits

        public var name: String {
            switch self {
            case .claude: return "Claude: подписка и температура"
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
            case .claude, .week, .pmpBar: return .week
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
    /// Перевод на «Claude» (WF269, #10220): сохранённый выбор один раз становится `.claude`; дальше выбор человека.
    public static let claudeMigratedKey = "statusIconClaudeWF269"

    /// true — перевели сейчас.
    @discardableResult
    public static func migrateToClaude(_ defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: claudeMigratedKey) else { return false }
        defaults.set(true, forKey: claudeMigratedKey)
        saveVariant(.claude, defaults)
        return true
    }

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
        if defaults.object(forKey: lettersKey) == nil { return .claude }
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
        case .claude:
            out.spark = true
            out.badge = false
            out.underline = false
            // Оценка ширины; точную считает кисть по тексту (`StatusIconArt.width`).
            let label = look.number.map { "\($0)%" } ?? "—"
            let temp = look.degrees.map { "\($0)°" }
            let labelWidth: CGFloat = CGFloat(label.count) * 8
            let tempWidth: CGFloat = temp.map { CGFloat($0.count) * 8 + 4 } ?? 0
            out.width = 19 + labelWidth + tempWidth
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
        out.spark = false
        out.degrees = nil
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
        out.toolTip = markNote(look) + toolTip
        return out
    }

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

    /// Последние известные цифры любой давности (#9824, слово Элвиса 11.10.2026: «показывать последнее значение
    /// подписки, а не минус… Минус — непонятно»): есть источник и время. Нет — честный прочерк.
    public static func known(_ limits: ClaudeLimits?) -> ClaudeLimits? {
        guard let limits = limits, limits.source != nil, limits.at != nil else { return nil }
        return limits
    }

    /// Давность несвежих цифр: «25 мин назад», «3 ч назад», «вчера в 21:40», «11.10 в 21:40»; свежие — nil.
    public static func staleText(_ limits: ClaudeLimits?, now: Date, calendar: Calendar = .current) -> String? {
        guard !isFresh(limits, now: now), let at = known(limits)?.at else { return nil }
        let minutes = max(1, Int(now.timeIntervalSince(at) / 60))
        if minutes < 60 { return "\(minutes) мин назад" }
        if minutes < 12 * 60 || calendar.isDate(at, inSameDayAs: now) { return "\(minutes / 60) ч назад" }
        let parts = calendar.dateComponents([.day, .month, .hour, .minute], from: at)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(at, inSameDayAs: yesterday) {
            return "вчера в \(time)"
        }
        return String(format: "%02d.%02d в ", parts.day ?? 0, parts.month ?? 0) + time
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
                            now: Date, calendar: Calendar = .current, access: [String] = [],
                            guardMissing: Bool = false) -> Look {
        var look = Look(mode: mode)
        look.access = access
        if mode == .percent { look.width = 22 }
        // Свежих цифр нет — последние известные, бледным (#9824); тревогу цветом по ним не поднимаем.
        let fresh = isFresh(limits, now: now) ? limits : known(limits)
        let stale = fresh != nil && !isFresh(limits, now: now)
        look.stale = stale
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
            if !access.isEmpty {
                look.mark = .accessLost
            } else if guardMissing {
                look.mark = .guardLost
            } else if case .ready = phase {
                look.mark = .updateReady
            }
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
            look.barLevels = three.map { stale ? .normal : level(remaining($0, now: now)) }
        case .week, .fiveHour, .fable, .percent:
            let kind = mainKind(mode, fresh)
            look.showsNumber = true
            look.number = used(limit(kind, in: fresh), now: now)
            look.level = stale ? .normal : level(remaining(limit(kind, in: fresh), now: now))
            if mode == .percent {
                let label = look.number.map { "\($0)%" } ?? "—"
                look.width = max(22, CGFloat(label.count) * 8.5 + 4) + (look.mark == .none ? 0 : 10)
            } else { look.width = look.number == 100 ? 52 : 45 }
        }
        look.toolTip = toolTip(mode: mode, limits: fresh, now: now, calendar: calendar)
        look.toolTip = markNote(look) + look.toolTip
        return look
    }

    /// Начало подсказки значка о беде с меткой: патч слетел, у Claude слетели доступы или не стоит сторож контекста.
    static func markNote(_ look: Look) -> String {
        switch look.mark {
        case .patchLost: return "PMP — патч слетел. "
        case .accessLost: return "PMP — у Claude слетели доступы: \(look.access.joined(separator: ", ")). "
        case .guardLost: return "PMP — сторож контекста не стоит. "
        case .none, .updateReady: return ""
        }
    }

    /// «PMP — неделя: израсходовано 77 % · сброс пт 08:00»; нет цифр — «лимиты придут…».
    public static func toolTip(mode: Mode, limits: ClaudeLimits?, now: Date, calendar: Calendar = .current) -> String {
        let kind = mainKind(mode, limits)
        guard let lim = limit(kind, in: limits), let spent = used(lim, now: now) else {
            return "PMP — лимиты придут, когда откроется окно Claude"
        }
        let reset = resetText(lim.resetsAt, now: now, calendar: calendar).map { " · \($0)" } ?? ""
        // Несвежие (#9824): число то же, но сказано, когда оно было и почему не сейчас.
        let age = staleText(limits, now: now, calendar: calendar)
            .map { " — \($0), свежие придут, когда откроется окно Claude" } ?? ""
        return "PMP — \(name(kind)): израсходовано \(spent) %\(age)\(reset)"
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

    /// Время сброса недели у «Сброса» (слово Элвиса 22.10.2026: «где сброс, там писалось ещё время сброса… 08—00»):
    /// «пт 08:00», до ближайшей минуты, как «сброс пт 08:00» у `resetText`. Нет времени или прошло — nil.
    public static func resetClock(_ date: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let raw = date, raw > now else { return nil }
        let date = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let days = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return String(format: "%@ %02d:%02d", days[((parts.weekday ?? 1) - 1 + 7) % 7], parts.hour ?? 0, parts.minute ?? 0)
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
