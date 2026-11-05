import Foundation

// Блок «Workflow» панели у часов (#10239, слово Элвиса 19.10.2026 04:55: «Блок Workflow, там надо его вернуть таким,
// как он на Windows был. Там грамотно всё… Вот оттуда нужно взять наработки»): порт блока Workflow PMP Tray для
// Windows (`pimp-tray/PimpTray.cs`: FlowGroups, FlowPrefix, FinishedAt, Took, FlowCountItems, легенда, ShortName,
// StageName, Who, Hot, Stages, When, Elapsed, Duration, листание карточки). Чистая часть — группы строк по
// состоянию, счёт в шапке, слова строк и карточки, страницы; вид — `Panel/PanelWorkflow.swift`, тесты —
// `WorkflowBlockTests`. Данные — тот же снимок `PanelProjects.snapshot`, что у значка у часов и `/digest`.

public enum WorkflowBlock {
    /// Группа строк — она же фильтр по счёту в шапке: идут (с ждущими и упавшими), ждут, упали, готово, впереди.
    public enum Filter: String, CaseIterable { case run, wait, fail, done, plan }

    /// Знак единой схемы (пожелание 17.10.2026 08:50): готово — залитый зелёный, идёт — рамочка цвета PMP с пульсом,
    /// ждёт тебя — жёлтый, упал — красный, впереди — серый тусклый. Одна схема у полосы, ячейки номера, шагов, точек
    /// и кружков карточки, легенды.
    public enum Mark: Equatable { case done, run, wait, fail, plan }

    /// Строки на странице списка (пожелание 17.10.2026: «не списком… порциями, компактно, и по проектам»).
    public static let pageSize = 5

    public static func mark(_ state: PanelWorkflow.State) -> Mark {
        switch state {
        case .running: return .run
        case .waiting: return .wait
        case .failed: return .fail
        case .done: return .done
        case .planned: return .plan
        }
    }

    /// Строка блока: Workflow `index` сводки `project`.
    public struct Row: Equatable, Identifiable {
        public let project: PanelProject
        public let index: Int
        /// Проект строки: приставка «PMP: …» в «о чём» или имя сводки (`prefix`).
        public let projectName: String

        public init(project: PanelProject, index: Int) {
            self.project = project
            self.index = index
            projectName = WorkflowBlock.prefix(project, index) ?? project.name
        }

        /// «папка#номер» — ключ карточки.
        public var id: String { project.folder + "#\(index)" }
        /// Строки одного проекта идут подряд под одним заголовком.
        public var group: String { project.folder + "|" + projectName }
        public var flow: PanelWorkflow { project.workflows[index] }
        public var mark: Mark { WorkflowBlock.mark(flow.state) }
    }

    public typealias Groups = [Filter: [Row]]

    // MARK: группы (FlowGroups)

    /// Группы строк по состоянию (#10315, только живое): идущие — проекты, где Workflow идёт или упал прямо сейчас
    /// (`PanelProjects.isLive`, свежие первыми), с их ждущими; готовые — законченные за последние 24 часа (#10395,
    /// `dayWindow`; `finishedAt`, без времени — когда менялась сводка), проекты и строки — свежие сверху; впереди — только у проектов, где что-то идёт. Счёт в шапке и полоса
    /// считаются по этим же строкам — число всегда равно списку.
    /// Окно «готово» (#10395, слово Элвиса 20.10: «показывать за сутки, за последние 24 часа… подписать»); на
    /// час вперёд — запас на неточное время в сводке.
    public static let dayWindow: TimeInterval = 24 * 3600

    public static func groups(_ snapshot: PanelSnapshot, now: Date, calendar: Calendar = .current) -> Groups {
        var seen = Set<String>()
        let all = (snapshot.working + snapshot.waiting + snapshot.others).filter { seen.insert($0.folder).inserted }
        // Свежие сверху, при равенстве — по имени папки (`Scan` PMP Tray).
        let ordered = all.enumerated().sorted { left, right in
            let a = left.element.updated ?? .distantPast, b = right.element.updated ?? .distantPast
            if a != b { return a > b }
            return left.element.folder != right.element.folder ? left.element.folder < right.element.folder
                : left.offset < right.offset
        }.map { $0.element }
        var active: [Row] = []
        for project in ordered where !project.running.isEmpty {
            for index in project.workflows.indices where [.running, .waiting, .failed].contains(project.workflows[index].state) {
                active.append(Row(project: project, index: index))
            }
        }
        var finished: [(row: Row, at: Date?)] = []
        var planned: [Row] = []
        for project in ordered {
            let starts = self.starts(project, now: now, calendar: calendar)
            let day = anchor(project, now: now)
            for index in project.workflows.indices {
                switch project.workflows[index].state {
                case .done:
                    let end = finishedAt(project, index: index, now: now, starts: starts)
                    // #10395 (слово Элвиса 20.10): за последние 24 часа, а не с полуночи.
                    let at = end ?? day
                    if at <= now.addingTimeInterval(dayWindow / 24), now.timeIntervalSince(at) <= dayWindow {
                        finished.append((Row(project: project, index: index), end))
                    }
                case .planned where !project.running.isEmpty:
                    planned.append(Row(project: project, index: index))
                default:
                    continue
                }
            }
        }
        active = byProject(active)
        // Готовые — свежие сверху, по времени окончания; без времени — в самый низ.
        let done = finished.enumerated().sorted { left, right in
            let a = left.element.at ?? .distantPast, b = right.element.at ?? .distantPast
            return a != b ? a > b : left.offset < right.offset
        }.map { $0.element.row }
        return [
            .run: active,
            .wait: active.filter { $0.flow.state == .waiting },
            .fail: active.filter { $0.flow.state == .failed },
            .done: byProject(done),
            .plan: byProject(planned),
        ]
    }

    /// Строки одного проекта — подряд (порядок проектов — по первой строке), чтобы заголовок шёл один раз.
    static func byProject(_ rows: [Row]) -> [Row] {
        var order: [String] = []
        var buckets: [String: [Row]] = [:]
        for row in rows {
            if buckets[row.group] == nil { order.append(row.group) }
            buckets[row.group, default: []].append(row)
        }
        return order.flatMap { buckets[$0] ?? [] }
    }

    /// Проект строки. Поля «проект» у Workflow в status.md нет: Workflow других проектов ведутся в одном файле
    /// с приставкой в «о чём» — «PMP: …». Приставка до «:» — проект, если начинается с латинской заглавной или стоит
    /// у двух и больше Workflow файла («разрезка 4:», «сбор:» — разовые, не проекты). На Маке «о чём» начинается
    /// с «WF247 — …»: метка Workflow и всё, что с « — », — не проект.
    public static func prefix(_ project: PanelProject, _ index: Int) -> String? {
        let about = project.workflows[index].about
        guard let colon = about.firstIndex(of: ":") else { return nil }
        let offset = about.distance(from: about.startIndex, to: colon)
        guard offset > 0, offset <= 24 else { return nil }
        let pre = about[..<colon].trimmingCharacters(in: .whitespaces)
        guard let first = pre.unicodeScalars.first, pre != project.name else { return nil }
        if pre.contains(" — ") || pre.contains(" – ") || pre.range(of: "^WF\\d", options: .regularExpression) != nil {
            return nil
        }
        if first.value >= 0x41 && first.value <= 0x5A { return pre }
        let same = project.workflows.filter { $0.about.hasPrefix(pre + ":") }.count
        return same >= 2 ? pre : nil
    }

    /// «о чём» без приставки-проекта: она стоит заголовком над строками.
    public static func aboutText(_ row: Row) -> String {
        let about = row.flow.about
        guard prefix(row.project, row.index) != nil, let colon = about.firstIndex(of: ":") else { return about }
        return about[about.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    // MARK: время (FinishedAt, Took, Written, Elapsed, Duration)

    /// Часы «13:05» в строке; выражение одно на всех — блок пересчитывается на каждом тике панели.
    private static let clockPattern = try? NSRegularExpression(pattern: "(\\d{1,2})\\s*:\\s*(\\d{2})")

    static func clocks(_ text: String) -> [(hour: Int, minute: Int, text: String)] {
        guard let regex = clockPattern, !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let h = Range(match.range(at: 1), in: text), let m = Range(match.range(at: 2), in: text),
                  let whole = Range(match.range, in: text),
                  let hour = Int(text[h]), let minute = Int(text[m]) else { return nil }
            return (hour, minute, text[whole].replacingOccurrences(of: " ", with: ""))
        }
    }

    static func at(_ hour: Int, _ minute: Int, dayOf date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    /// Часы строки «обновлено 06:10» — в день `base` (впереди него больше чем на 3 ч — накануне); часов нет — nil.
    static func stampDate(_ stamp: String, base: Date) -> Date? {
        guard let clock = clocks(stamp).first, clock.hour <= 23, clock.minute <= 59 else { return nil }
        let at = at(clock.hour, clock.minute, dayOf: base)
        return at > base.addingTimeInterval(3 * 3600) ? at.addingTimeInterval(-86_400) : at
    }

    /// Когда записано «идёт N»: по строке «обновлено 06:10» (те же часы, что у «идёт») в день, когда изменилось
    /// содержимое сводки (#10315; до него — в сегодняшний: вчерашняя сводка со штампом «23:50» читалась сегодняшней),
    /// без неё — время изменения содержимого.
    public static func written(_ project: PanelProject, now: Date) -> Date {
        let base = project.updated ?? now
        return stampDate(project.stamp, base: base) ?? base
    }

    /// День записи сводки — от него считаются часы строк: позднее из штампа и времени содержимого (штамп забыли
    /// поправить — правка всё равно сегодняшняя).
    static func anchor(_ project: PanelProject, now: Date) -> Date {
        max(written(project, now: now), project.updated ?? .distantPast)
    }

    /// Начала строк сводки по дням (#10315): часы в строках без даты, а сводка-журнал тянется через полночь, и все
    /// её «✅» читались сегодняшними. Самая свежая строка — день записи (`anchor`; впереди него больше чем на 3 ч —
    /// накануне); дальше от свежих к старым: начало позже начала более свежей строки больше чем на 3 ч — строка на
    /// сутки раньше. Свежие внизу (так пишут сводки) или вверху — по большинству соседних пар. Ключ — номер Workflow
    /// в сводке; строки без часов — мимо.
    static func starts(_ project: PanelProject, now: Date, calendar: Calendar = .current) -> [Int: Date] {
        var rows: [(index: Int, minutes: Int)] = []
        for (index, flow) in project.workflows.enumerated() {
            guard let clock = clocks(flow.time).first, clock.hour <= 23, clock.minute <= 59 else { continue }
            rows.append((index, clock.hour * 60 + clock.minute))
        }
        guard !rows.isEmpty else { return [:] }
        let pairs = Array(zip(rows, rows.dropFirst()))
        let up = pairs.filter { $0.1.minutes > $0.0.minutes }.count
        let down = pairs.filter { $0.1.minutes < $0.0.minutes }.count
        let order = down > up ? rows : Array(rows.reversed())
        let anchor = self.anchor(project, now: now)
        let today = calendar.startOfDay(for: anchor)
        var back = 0
        var newer: Int?
        var out: [Int: Date] = [:]
        for row in order {
            if let next = newer {
                if row.minutes > next + 180 { back += 1 }
            } else if today.addingTimeInterval(TimeInterval(row.minutes * 60)) > anchor.addingTimeInterval(3 * 3600) {
                back = 1
            }
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            out[row.index] = at(row.minutes / 60, row.minutes % 60, dayOf: day, calendar: calendar)
            newer = row.minutes
        }
        return out
    }

    /// Когда кончился готовый Workflow `index`: второе время строки («13:05 → 13:50») — от её начала (`starts`; раньше
    /// начала — назавтра); одно время и длительность («13:05 · 45 мин») — начало плюс длительность. Времени нет —
    /// nil (в самый низ).
    public static func finishedAt(_ project: PanelProject, index: Int, now: Date, starts: [Int: Date]? = nil) -> Date? {
        guard project.workflows.indices.contains(index),
              let start = (starts ?? self.starts(project, now: now))[index] else { return nil }
        let flow = project.workflows[index]
        let times = clocks(flow.time)
        guard times.count > 1 else { return start.addingTimeInterval(TimeInterval(took(flow.time) * 60)) }
        let end = times[1]
        guard end.hour <= 23, end.minute <= 59 else { return start }
        let at = at(end.hour, end.minute, dayOf: start)
        guard at < start else { return at }
        return Calendar.current.date(byAdding: .day, value: 1, to: at) ?? at.addingTimeInterval(86_400)
    }

    /// То же по самому Workflow (первый такой в сводке).
    public static func finishedAt(_ project: PanelProject, _ flow: PanelWorkflow, now: Date) -> Date? {
        project.workflows.firstIndex(of: flow).flatMap { finishedAt(project, index: $0, now: now) }
    }

    /// Хвост строки времени после последнего «·»: «1,7 ч», «45 мин»; нет — nil.
    static func tail(_ time: String) -> String? {
        guard let range = time.range(of: "·\\s*([^·]+)$", options: .regularExpression) else { return nil }
        return String(time[range].dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// Сколько занял, минут, по хвосту строки времени: «· 1,7 ч», «· 45 мин», «· 1 ч 20 мин»; нет — 0.
    public static func took(_ time: String) -> Int {
        guard let tail = tail(time) else { return 0 }
        var minutes = 0.0
        if let range = tail.range(of: "(\\d+(?:[.,]\\d+)?)\\s*ч", options: .regularExpression) {
            let number = tail[range].prefix { $0.isNumber || $0 == "," || $0 == "." }
            minutes += 60 * (Double(number.replacingOccurrences(of: ",", with: ".")) ?? 0)
        }
        if let range = tail.range(of: "(\\d+)\\s*мин", options: .regularExpression) {
            minutes += Double(tail[range].prefix { $0.isNumber }) ?? 0
        }
        return Int(min(minutes, 24 * 60).rounded())
    }

    /// «25 мин», «1,7 ч» — минуты до часа, дальше часы с одним знаком, как в status.md.
    public static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)\u{00A0}мин" }
        var hours = String(format: "%.1f", Double(minutes) / 60)
        if hours.hasSuffix(".0") { hours.removeLast(2) }
        return hours.replacingOccurrences(of: ".", with: ",") + "\u{00A0}ч"
    }

    public static let justStarted = "только начат"

    /// Сколько Workflow идёт. Есть в строке «13:05 → … · идёт 40 мин» — берём его (то же число, что в status.md
    /// и /digest) и прибавляем, сколько прошло с «обновлено». Нет — от первого времени строки до сейчас; начало
    /// впереди не дальше 3 ч — «только начат», дальше — со вчера. Времени нет — пусто.
    public static func elapsed(_ time: String, written: Date, now: Date) -> String {
        let minutes: Int
        if let range = time.range(of: "идёт\\s+(\\d+(?:[.,]\\d+)?)\\s*(мин|ч)",
                                  options: [.regularExpression, .caseInsensitive]) {
            let body = time[range].dropFirst(4).trimmingCharacters(in: .whitespaces)
            let number = Double(body.prefix { $0.isNumber || $0 == "," || $0 == "." }
                .replacingOccurrences(of: ",", with: ".")) ?? 0
            let since = written > now ? 0 : now.timeIntervalSince(written) / 60
            minutes = Int(((body.hasSuffix("ч") ? number * 60 : number) + since).rounded())
        } else {
            guard let clock = clocks(time).first, clock.hour <= 23, clock.minute <= 59 else { return "" }
            var start = at(clock.hour, clock.minute, dayOf: now)
            if start > now.addingTimeInterval(60) {
                if start <= now.addingTimeInterval(3 * 3600) { return justStarted }
                start = start.addingTimeInterval(-86_400)
            }
            minutes = Int(now.timeIntervalSince(start) / 60)
        }
        return duration(max(1, minutes))
    }

    // MARK: имена (ShortName, StageName, Who, Hot)

    /// Короткое имя строки: до «:», «;», «,» или « — », не длиннее 28 знаков — по целому слову, без «…»; предлог
    /// в хвосте — долой. На Маке «о чём» начинается с метки «WF250 — …»: имя — то, что после неё.
    public static func shortName(_ about: String) -> String {
        var text = about.trimmingCharacters(in: .whitespaces)
        if let dash = text.range(of: " — "),
           text[..<dash.lowerBound].range(of: "^WF[0-9–-]+", options: .regularExpression) != nil {
            let rest = text[dash.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { text = rest }
        }
        var cut = text.endIndex
        for mark in [":", ";", ",", " — ", " – ", " ("] {
            if let range = text.range(of: mark), range.lowerBound > text.startIndex, range.lowerBound < cut {
                cut = range.lowerBound
            }
        }
        text = text[..<cut].trimmingCharacters(in: .whitespaces)
        guard text.count > 28 else { return text }
        let head = String(text.prefix(29))
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) > 8 {
            text = String(head[..<space])
        } else {
            text = String(text.prefix(28))
        }
        let small: Set<String> = ["в", "во", "и", "на", "по", "за", "с", "со", "к", "о", "об", "от", "до", "для", "из",
                                  "у", "а", "но", "или", "—", "–"]
        var words = text.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, small.contains(last.lowercased()) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// Этап по роли: «планирование» — план, «критика/ревизия/ревью» — критик, «проверка/тест/гейт» — тест,
    /// «кодинг», «исследование»; прочие — как записаны.
    public static func stageName(_ role: String) -> String {
        let r = role.lowercased()
        if r.hasPrefix("план") { return "план" }
        if r.hasPrefix("критик") || r.hasPrefix("ревизи") || r.hasPrefix("ревью") { return "критик" }
        if r.hasPrefix("провер") || r.hasPrefix("тест") || r.hasPrefix("гейт") { return "тест" }
        if r.hasPrefix("кодинг") { return "кодинг" }
        if r.hasPrefix("исследов") { return "исследование" }
        return r
    }

    /// Кто: «я · Opus 5.5 high», «Opus 5.5 high ×2»; не записано — «—».
    public static func who(_ role: PanelRole) -> String {
        let me = role.me ? "я" + (role.model.isEmpty ? "" : " · ") : ""
        let text = me + role.model + (role.agents > 1 ? " ×\(role.agents)" : "")
        return text.isEmpty ? "—" : text
    }

    /// Fable и max — с пометкой 🔴 в status.md: красным и жирным.
    public static func hot(_ role: PanelRole) -> Bool {
        let model = role.model.lowercased()
        return role.red || model.contains("fable") || model.range(of: "\\bmax\\b", options: .regularExpression) != nil
            || model.contains("extra")
    }

    /// Идущая роль: с 💭, иначе последняя записанная (формат status.md: без пометки идёт последняя).
    public static func currentRole(_ flow: PanelWorkflow) -> PanelRole? {
        flow.roles.first { $0.running && !$0.past } ?? flow.roles.last { !$0.past }
    }

    // MARK: строка (FlowRow)

    /// Готовые и запланированные — тонкой строкой без шагов («компактно»).
    public static func slim(_ row: Row) -> Bool { row.mark == .done || row.mark == .plan }

    /// Имя строки: короткое «о чём» без приставки; пусто — «Workflow N».
    public static func rowName(_ row: Row) -> String {
        let text = aboutText(row)
        return text.isEmpty ? "Workflow \(row.index + 1)" : shortName(text)
    }

    public enum Tone: Equatable { case plain, wait, fail, hot }

    /// Справа в строке: этап · модель (Fable и max — красным), «ждёт тебя», «упал», у готового «в 01:20»,
    /// у впереди — «3 шага». `brief` — у идущего один этап: строке не хватило места, модель — в карточке.
    public static func rowRight(_ row: Row, now: Date, brief: Bool = false) -> (text: String, tone: Tone) {
        let flow = row.flow
        switch row.mark {
        case .wait: return ("ждёт тебя", .wait)
        case .fail: return ("упал", .fail)
        case .done: return (when(row.project, flow, now: now, brief: true), .plain)
        case .plan:
            let steps = flow.stepsTotal ?? 0
            return (steps > 0 ? "\(steps) " + Plural.ru(steps, "шаг", "шага", "шагов") : "", .plain)
        case .run:
            guard let role = currentRole(flow) else { return ("", .plain) }
            let model = brief || role.model.isEmpty ? "" : " · " + role.model
            return (stageName(role.name) + model, hot(role) ? .hot : .plain)
        }
    }

    /// Под строкой справа: «2 из 3 · 25 мин» — пройдено шагов из всех и сколько идёт (ждёт и упал — без времени).
    public static func rowTail(_ row: Row, now: Date) -> String {
        let flow = row.flow
        var parts: [String] = []
        let total = flow.stepsTotal ?? 0
        if total > 0 { parts.append("\(max(0, min(flow.stepsDone ?? 0, total))) из \(total)") }
        if row.mark == .run {
            let time = elapsed(flow.time, written: written(row.project, now: now), now: now)
            if !time.isEmpty { parts.append(time) }
        }
        return parts.joined(separator: " · ")
    }

    /// Шаги отрезками: пройденные — готово, текущий — идёт (ждёт, упал), дальше — впереди; у готового все пройдены.
    public static func steps(_ row: Row) -> [Mark] {
        let flow = row.flow
        let total = flow.stepsTotal ?? 0
        let done = max(0, min(flow.stepsDone ?? 0, total))
        return (0..<total).map { index in
            if row.mark == .done || index < done { return .done }
            if index == done, row.mark != .plan { return row.mark == .wait ? .wait : row.mark == .fail ? .fail : .run }
            return .plan
        }
    }

    // MARK: карточка (Stages, When)

    public struct Stage: Equatable {
        public let title: String
        public let who: String
        public let mark: Mark
        public let hot: Bool
    }

    /// Этапы — только записанные ролью (и строкой «прошлые шаги»): прошлые и стоящие до идущей — пройдены, идущая —
    /// идёт (ждёт, упал), дальше — впереди; готовый — все пройдены, запланированный — все впереди.
    public static func stages(_ flow: PanelWorkflow) -> [Stage] {
        let current = currentRole(flow)
        let at = current.flatMap { role in flow.roles.firstIndex(of: role) } ?? -1
        return flow.roles.enumerated().map { index, role in
            let mark: Mark
            switch flow.state {
            case .done: mark = .done
            case .planned: mark = .plan
            default:
                if role.past || index < at { mark = .done }
                else if index == at { mark = flow.state == .waiting ? .wait : flow.state == .failed ? .fail : .run }
                else { mark = .plan }
            }
            return Stage(title: stageName(role.name), who: who(role), mark: mark, hot: hot(role))
        }
    }

    /// Когда: «Начался 25 мин назад, в 13:05 · закончит в 13:50», «Завершился в 01:20 · занял 1 ч»,
    /// «Ещё не начат». `brief` — для строки готового: «в 01:20».
    public static func when(_ project: PanelProject, _ flow: PanelWorkflow, now: Date, brief: Bool = false) -> String {
        if flow.state == .planned { return brief ? "" : "Ещё не начат" }
        let times = clocks(flow.time)
        guard let first = times.first else { return "" }
        if flow.state == .done {
            let end = times.count > 1 ? times[1].text : first.text
            if brief { return "в " + end }
            var took = ""
            if let tail = tail(flow.time), !PanelProjects.hasClock(tail) {
                let minutes = self.took(flow.time)
                took = minutes > 0 ? duration(minutes) : tail
            }
            return "Завершился в " + end + (took.isEmpty ? "" : " · занял " + took)
        }
        var finish = ""
        if let range = flow.time.range(of: "закончит\\s+в\\s+\\d{1,2}\\s*:\\s*\\d{2}", options: .regularExpression) {
            finish = clocks(String(flow.time[range])).first?.text ?? ""
        }
        let going = elapsed(flow.time, written: written(project, now: now), now: now)
        let start = going.isEmpty ? "Начался в " + first.text
            : going == justStarted ? "Только начат, в " + first.text
            : "Начался \(going) назад, в " + first.text
        return start + (finish.isEmpty ? "" : " · закончит в " + finish)
    }

    // MARK: счёт в шапке и легенда (FlowCountItems, DrawLegend)

    public struct Count: Equatable, Identifiable {
        public let filter: Filter
        public let number: Int
        public let word: String
        /// Пояснение нуля («Сегодня готовых нет»): ноль не нажимается.
        public let zeroTip: String?
        public var id: Filter { filter }
        public var on: Bool { number > 0 }
    }

    /// Счёт слева направо: готово · идут (ждут, упали) · впереди. «Идут» — без ждущих и упавших; ждут и упали — только
    /// когда есть.
    public static func counts(_ groups: Groups) -> [Count] {
        let wait = groups[.wait]?.count ?? 0, fail = groups[.fail]?.count ?? 0
        let run = (groups[.run]?.count ?? 0) - wait - fail
        let done = groups[.done]?.count ?? 0, plan = groups[.plan]?.count ?? 0
        var items = [Count(filter: .done, number: done, word: "готово", zeroTip: "За 24 часа готовых нет"),
                     Count(filter: .run, number: run, word: Plural.ru(run, "идёт", "идут", "идут"),
                           zeroTip: "Сейчас ничего не идёт")]
        if wait > 0 { items.append(Count(filter: .wait, number: wait, word: Plural.ru(wait, "ждёт", "ждут", "ждут"), zeroTip: nil)) }
        if fail > 0 { items.append(Count(filter: .fail, number: fail, word: Plural.ru(fail, "упал", "упали", "упали"), zeroTip: nil)) }
        items.append(Count(filter: .plan, number: plan, word: "впереди", zeroTip: "Запланированных нет"))
        return items
    }

    /// Строки легенды: знак и что он значит; ждёт и упал — только когда они есть в счёте.
    public static func legend(_ counts: [Count], motion: Bool) -> [(mark: Mark, text: String)] {
        var lines: [(Mark, String)] = [(.done, "готово — залитая полоска"),
                                       (.run, motion ? "идёт — рамочка, мерцает" : "идёт — рамочка")]
        if counts.contains(where: { $0.filter == .wait }) { lines.append((.wait, "ждёт тебя — жёлтая")) }
        if counts.contains(where: { $0.filter == .fail }) { lines.append((.fail, "упал — красная")) }
        lines.append((.plan, "впереди — серая"))
        return lines
    }

    /// Подпись внизу легенды: курсор на нуле — его пояснение, иначе — что делает нажатие. «Ещё раз — снова идущие» —
    /// только когда выбранное видно подсвеченным (блок раскрыт и фильтр не «идут»).
    public static func legendHint(_ counts: [Count], under: Filter?, filter: Filter, open: Bool) -> String {
        if let under = under, let count = counts.first(where: { $0.filter == under }), !count.on, let tip = count.zeroTip {
            return tip
        }
        if !counts.contains(where: { $0.on }) { return "Пока нечего показать" }
        let pickedShown = open && filter != .run && counts.contains { $0.on && $0.filter == filter }
        if pickedShown {
            return under == filter ? "Нажми выбранное ещё раз — снова идущие"
                : "Нажми число — покажу только эти; выбранное — снова идущие"
        }
        return "Нажми число — покажу только эти"
    }

    /// Полоса над списком — по отрезку на Workflow: готовые, идущие (ждут, упали), впереди.
    public static func strip(_ groups: Groups) -> [Mark] {
        let order: [Mark] = [.done, .run, .wait, .fail, .plan]
        let marks = ((groups[.done] ?? []) + (groups[.run] ?? []) + (groups[.plan] ?? [])).map { $0.mark }
        return marks.enumerated().sorted { left, right in
            let a = order.firstIndex(of: left.element) ?? 0, b = order.firstIndex(of: right.element) ?? 0
            return a != b ? a < b : left.offset < right.offset
        }.map { $0.element }
    }

    /// Знак из выбранной фильтром группы — в полный цвет, остальные бледнее.
    public static func picked(_ mark: Mark, filter: Filter) -> Bool {
        switch filter {
        case .run: return mark == .run || mark == .wait || mark == .fail
        case .wait: return mark == .wait
        case .fail: return mark == .fail
        case .done: return mark == .done
        case .plan: return mark == .plan
        }
    }

    // MARK: страницы (FlowRows, PortionRows, PageRow)

    public static func pages(_ count: Int) -> Int { max(1, (count + pageSize - 1) / pageSize) }

    /// «6–10 из 13».
    public static func pageLabel(page: Int, count: Int) -> String {
        "\(page * pageSize + 1)–\(min(count, (page + 1) * pageSize)) из \(count)"
    }

    /// Элемент порции: заголовок проекта (имя и счёт его строк — только там, где группа начинается) или строка.
    public enum Item: Equatable, Identifiable {
        case head(name: String, count: Int, group: String)
        case row(Row)

        public var id: String {
            switch self {
            case .head(_, _, let group): return "head|" + group
            case .row(let row): return row.id
            }
        }
    }

    /// Порция `page`: над строками каждого проекта — его имя заголовком, строки имя не повторяют.
    public static func portion(_ rows: [Row], page: Int) -> [Item] {
        var items: [Item] = []
        var previous: String?
        for row in rows.dropFirst(page * pageSize).prefix(pageSize) {
            if row.group != previous {
                let starts = (rows.firstIndex { $0.group == row.group } ?? 0) >= page * pageSize
                items.append(.head(name: row.projectName, count: starts ? rows.filter { $0.group == row.group }.count : 0,
                                   group: row.group))
            }
            items.append(.row(row))
            previous = row.group
        }
        return items
    }

    // MARK: состояние блока

    /// Что открыто в блоке: фильтр по счёту, карточка, страницы списков. Не помнится: панель открылась — снова
    /// «идут» и список, как на Windows.
    public struct State: Equatable {
        public var filter = Filter.run
        /// Открытая карточка («папка#номер»); nil — список.
        public var card: String?
        /// Куда листали карточку последний раз: +1 — вперёд, −1 — назад (въезд новой страницы).
        public var slide = 1
        public var page = 0
        public var aheadPage = 0
        /// «Не напоминать» (#9820): плашка отмены и строки, заглушённые в этом открытии (снимок ещё не перечитан).
        public var waitUndo: WaitUndo?
        public var hiddenWaits: Set<String> = []

        public init() {}

        /// Нажатие счёта: блок свёрнут — раскрыть с этой группой (`open` вернёт true); другой — показать его группу,
        /// тот же ещё раз — снова «идут».
        public mutating func pick(_ key: Filter, open: Bool) -> Bool {
            page = 0
            if !open {
                filter = key
                return true
            }
            filter = filter == key ? .run : key
            return false
        }

        /// Группа, которую листает карточка: выбранная фильтром, у «идут» — и запланированные под «Впереди».
        public func cardGroup(_ groups: Groups) -> [Row]? {
            guard let card = card else { return nil }
            let shown = groups[filter] ?? []
            if shown.contains(where: { $0.id == card }) { return shown }
            let planned = groups[.plan] ?? []
            if filter == .run, planned.contains(where: { $0.id == card }) { return planned }
            return nil
        }

        /// На соседнюю карточку (−1 / +1) или на точку; за край — никуда. true — перелистнули.
        @discardableResult
        public mutating func turn(to index: Int, in group: [Row]) -> Bool {
            guard let at = group.firstIndex(where: { $0.id == card }), index >= 0, index < group.count, index != at else {
                return false
            }
            slide = index > at ? 1 : -1
            card = group[index].id
            return true
        }

        @discardableResult
        public mutating func turn(_ step: Int, in group: [Row]) -> Bool {
            guard let at = group.firstIndex(where: { $0.id == card }) else { return false }
            return turn(to: at + step, in: group)
        }

        /// Пустая группа фильтра — снова «идут» (`WorkflowBody`).
        public mutating func settle(_ groups: Groups) {
            if (groups[filter] ?? []).isEmpty { filter = .run }
        }
    }

    /// Ничего не идёт (#10315: «Нужно выводить только актуальное») — блок одной строкой: «Сейчас ничего не идёт ·
    /// сегодня готово 2», без готовых — «Сейчас ничего не идёт»; что-то идёт (ждёт, упал) — nil.
    public static func idleLine(_ groups: Groups) -> String? {
        guard (groups[.run] ?? []).isEmpty else { return nil }
        let done = groups[.done]?.count ?? 0
        return done > 0 ? "Сейчас ничего не идёт · готово \(done)" : "Сейчас ничего не идёт"
    }

    /// Свёрнутый блок одной строкой для «Свернуть всё»: «2 готово · 2 идут · 2 впереди»; ничего не идёт — `idleLine`.
    public static func countsLine(_ groups: Groups) -> String {
        idleLine(groups) ?? counts(groups).map { "\($0.number) \($0.word)" }.joined(separator: " · ")
    }
}
