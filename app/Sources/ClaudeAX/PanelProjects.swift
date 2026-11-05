import Foundation

// Проекты в панели PMP (WF126, `docs/wf126-spec.md` §3–4): снимок сводок проектов для плиток «Идёт Workflow сейчас»
// и `/digest` (списки WF126 сняты в WF129/WF171). Чистая часть — разбор `status.md` (порт `statusParse` страницы,
// чтобы панель и полоска не спорили), правило готового слова и текст отправки; тесты — `PanelProjectsTests`.

/// Отрезок полосы фаз Workflow.
public struct PanelPhase: Equatable {
    public enum State: Equatable { case done, current, future, failed }
    /// Короткое имя («план», «кодинг»; длиннее 9 знаков — «…»).
    public let name: String
    public let state: State
    /// Полная строка роли — подсказка отрезка.
    public let help: String
}

/// Роль Workflow целиком — этап карточки блока Workflow (#10239, порт `FlowRole` PMP Tray для Windows):
/// «кодинг · 2 агента · Opus 5.5 high 💭».
public struct PanelRole: Equatable {
    public let name: String
    /// Модель с эффортом как записана («Opus 5.5 high»), без 🔴 и `**`.
    public let model: String
    /// Агентов числом; «я» или не записано — 0.
    public let agents: Int
    /// Роль ведёт сам оркестратор («я»).
    public let me: Bool
    /// Пометка 💭 — идёт сейчас.
    public let running: Bool
    /// Из строки «прошлые шаги».
    public let past: Bool
    /// Пометка 🔴 (Fable, max) в status.md.
    public let red: Bool

    public init(name: String, model: String = "", agents: Int = 0, me: Bool = false, running: Bool = false,
                past: Bool = false, red: Bool = false) {
        self.name = name
        self.model = model
        self.agents = agents
        self.me = me
        self.running = running
        self.past = past
        self.red = red
    }
}

/// Блок Workflow сводки.
public struct PanelWorkflow: Equatable {
    public enum State: Equatable { case running, waiting, failed, done, planned }
    public let about: String
    public let state: State
    /// «шаги N из M»; нет — nil.
    public let stepsDone: Int?
    public let stepsTotal: Int?
    /// Строка времени как есть («01:11 → закончит в 03:30 · идёт 1,4 ч»).
    public let time: String
    public let phases: [PanelPhase]
    /// Роли по порядку: прошлые шаги (которых нет среди записанных ролей), потом роли (#10239).
    public var roles: [PanelRole] = []

    /// Длительность для списка готовых: хвост строки времени после последнего « · », иначе вся строка.
    public var duration: String {
        guard let range = time.range(of: " · ", options: .backwards) else { return time }
        return String(time[range.upperBound...])
    }
}

/// Разобранная сводка проекта.
public struct PanelStatus: Equatable {
    public var name = ""
    public var marker = ""
    public var now = ""
    public var waitFor = ""
    public var workflows: [PanelWorkflow] = []
    /// Строка шапки «марафон «…», волна 2 из 4» как есть (WF129, #9077); нет — пусто.
    public var marathon = ""
    /// Строка «обновлено 06:10» под заголовком (#10239): часы того, кто писал, — по ним считается «идёт 25 мин».
    public var stamp = ""
}

/// Проект в панели.
public struct PanelProject: Equatable, Identifiable {
    public var id: String { folder }
    /// Абсолютный путь папки.
    public let folder: String
    public let name: String
    public let marker: String
    public let isMain: Bool
    /// Когда изменилось содержимое `status.md` (#10315, `FlowSeen`; без памяти — дата правки файла); сводки нет — nil.
    public let updated: Date?
    public let now: String
    /// Готовые слова — кнопки «Отправить» (до трёх).
    public let words: [String]
    /// Пояснение к «Ждёт Элвиса» (всё, кроме готовых слов).
    public let note: String
    public let waits: Bool
    /// Идут и упали.
    public let running: [PanelWorkflow]
    /// Все Workflow сводки по порядку и строка марафона — плитки «Идут Workflow» (WF129).
    public var workflows: [PanelWorkflow] = []
    public var marathon = ""
    /// Строка «обновлено 06:10» сводки (#10239); нет — пусто.
    public var stamp = ""
    /// «Ждёт Элвиса: …» как записано (свежее 7 суток, `freshWait`) — «Ждёт тебя: …» в карточке блока Workflow.
    public var waitFor = ""
    /// Путь прочитанной сводки (`readStatus`): рядом с ней run-файлы — цена Workflow (#6282); сводки нет — пусто.
    public var statusFile = ""
}

/// Снимок панели: три раздела.
public struct PanelSnapshot: Equatable {
    public let waiting: [PanelProject]
    public let working: [PanelProject]
    public let others: [PanelProject]
    /// Живые tmux-сессии `rick-<проект>` — имена после «rick-» (WF129); tmux нет — пусто.
    public var terminals: Set<String> = []
    /// Из них — с движением за 45 мин (#10315, `PanelTiles.activeTerminals`); nil — не спрашивали, считаются все.
    public var activeTerminals: Set<String>?

    public var isEmpty: Bool { waiting.isEmpty && working.isEmpty && others.isEmpty }
}

public enum PanelProjects {
    /// «Ждут тебя»: сводка правилась не раньше 7 суток.
    public static let waitFreshSeconds: TimeInterval = 7 * 86_400
    /// «Сейчас:» сводки и потолок живого правила (#10315, `isLive`): содержимое старше 12 ч живым не бывает.
    public static let runFreshSeconds: TimeInterval = 12 * 3600

    /// Свежесть всего, что панель и `/digest` берут из сводки (#9846: карточка терминалов показала «Сейчас:» от 11.10
    /// как живое): «Сейчас:» — только пока сводка моложе `runFreshSeconds`, как идущие Workflow; «Ждёт Элвиса:» — моложе
    /// `waitFreshSeconds`, как раздел «Ждут тебя». Старше — строки нет: старое не выдаётся за «сейчас».
    public static func freshNow(_ status: PanelStatus, age: TimeInterval) -> String {
        age <= runFreshSeconds ? status.now : ""
    }

    public static func freshWait(_ status: PanelStatus, age: TimeInterval) -> String {
        age <= waitFreshSeconds && !isNothing(status.waitFor) ? status.waitFor : ""
    }
    public static let wordLimit = 60
    public static let wordsPerProject = 3
    public static let phasesLimit = 5

    // MARK: разбор status.md

    public static func parse(_ text: String) -> PanelStatus {
        var status = PanelStatus()
        var blocks: [Block] = []
        var current: Block?
        var sawHeading = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !sawHeading, line.hasPrefix("# ") {
                sawHeading = true
                let head = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let marker = String(head.prefix { !($0.isLetter || $0.isNumber) })
                status.marker = marker.trimmingCharacters(in: .whitespaces)
                status.name = String(head.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if sawHeading, current == nil, blocks.isEmpty, status.marathon.isEmpty,
               line.lowercased().hasPrefix("марафон") {
                status.marathon = line
                continue
            }
            // «обновлено 06:10» до первого блока (#10239, как `Parse` PMP Tray).
            if current == nil, status.stamp.isEmpty, line.lowercased().hasPrefix("обновлено") {
                status.stamp = line
                continue
            }
            if StatusFeed.isWorkflowHeading(line) {
                if let block = current { blocks.append(block) }
                current = Block(state: blockState(line))
                continue
            }
            if let tail = tailLine(line) {
                if !tail.value.isEmpty { if tail.now { status.now = tail.value } else { status.waitFor = tail.value } }
                continue
            }
            guard current != nil, line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { continue }
            current?.take(item)
        }
        if let block = current { blocks.append(block) }
        status.workflows = blocks.map { $0.workflow }
        return status
    }

    /// Строка «Сейчас: …» / «Ждёт Элвиса: …» / «Ждёт пользователя: …» (как `STATUS_TAIL_LINE_RE` страницы).
    static func tailLine(_ line: String) -> (now: Bool, value: String)? {
        var body = Substring(line)
        if body.hasPrefix("- ") || body.hasPrefix("* ") { body = body.dropFirst(2).drop { $0 == " " } }
        if body.hasPrefix("**") { body = body.dropFirst(2) }
        let now: Bool
        if body.hasPrefix("Сейчас:") { now = true; body = body.dropFirst("Сейчас:".count) }
        else if body.hasPrefix("Ждёт Элвиса:") { now = false; body = body.dropFirst("Ждёт Элвиса:".count) }
        else if body.hasPrefix("Ждёт пользователя:") { now = false; body = body.dropFirst("Ждёт пользователя:".count) }
        else { return nil }
        let value = String(body).replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        return (now, value)
    }

    /// Значки состояния Workflow в заголовке — по порядку силы (WF145: одно правило всех разборщиков status.md —
    /// панель, `/digest`, срез StatusFeed, `pimp.py digest` `DIGEST_MARKS`, страница `statusParse`). Значок сильнее слова.
    static let stateMarks: [(marks: [String], state: PanelWorkflow.State)] = [
        (["🛑", "❌"], .failed),
        (["✋", "⚠", "❓", "🙋", "⏸"], .waiting),
        (["⬜"], .planned),
        (["✅", "🟢"], .done),
        (["💭", "⏳"], .running),
    ]
    /// Слова, когда значка нет (строчными, кусок слова): «запланирован» — впереди раньше «планирования» — идёт.
    static let stateWords: [(words: [String], state: PanelWorkflow.State)] = [
        (["упал", "стоп", "сломал"], .failed),
        (["заплан", "впереди", "в очереди"], .planned),
        (["ждёт", "жду", "пауз"], .waiting),
        (["готов", "выложен"], .done),
        (["идёт", "кодинг", "критик", "проверк", "исследов", "планирован", "ревизи"], .running),
    ]

    /// Состояние Workflow по заголовку («1️⃣ Workflow ⏳ идёт»): ⏳ и 💭 — идёт (до WF145 ⏳ было «запланирован»,
    /// и `/digest` звал идущий проект «ждут»), ⬜ — впереди, не «ждёт Элвиса»; ни значка, ни слова — впереди.
    static func blockState(_ heading: String) -> PanelWorkflow.State {
        // `.literal` — по кодовым единицам: «⚠» находится и в «⚠️» (с FE0F).
        for rule in stateMarks where rule.marks.contains(where: { heading.range(of: $0, options: .literal) != nil }) {
            return rule.state
        }
        let text = heading.lowercased()
        for rule in stateWords where rule.words.contains(where: { text.contains($0) }) { return rule.state }
        return .planned
    }

    /// Роль «роль · агенты · модель усилие [💭]» — как `statusRole` страницы.
    struct Role {
        var name: String
        let agents: String
        let model: String
        let effort: String
        let running: Bool
        let line: String
        /// Для блока Workflow (#10239, `Role` PMP Tray): модель — первая часть после имени, что не «агенты», без 🔴
        /// и `**`; 🔴 — пометка Fable и max.
        let shownModel: String
        let red: Bool

        init(_ item: String) {
            line = item
            var text = item.trimmingCharacters(in: .whitespaces)
            running = text.hasSuffix("💭")
            if running { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
            let parts = text.components(separatedBy: CharacterSet(charactersIn: "·•"))
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            name = parts.first ?? ""
            let rest = Array(parts.dropFirst())
            let agentsAt = rest.firstIndex { $0.lowercased().contains("аген") || $0 == "я" || $0.hasPrefix("я ") }
            agents = agentsAt.map { rest[$0] } ?? ""
            var who = rest.enumerated().filter { $0.offset != agentsAt }.map { $0.element }.joined(separator: " · ")
                .replacingOccurrences(of: "**", with: "")
            who = String(who.drop { !($0.isLetter || $0.isNumber) }).trimmingCharacters(in: .whitespaces)
            let words = who.split(separator: " ")
            if words.count > 1, let last = words.last,
               ["low", "medium", "high", "xhigh", "extra", "max"].contains(last.lowercased()) {
                effort = last.lowercased()
                model = words.dropLast().joined(separator: " ")
            } else {
                effort = ""
                model = who
            }
            let first = rest.enumerated().first { $0.offset != agentsAt }?.element ?? ""
            red = first.contains("🔴")
            shownModel = first.replacingOccurrences(of: "🔴", with: "").replacingOccurrences(of: "**", with: "")
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }

        /// Роль для карточки блока Workflow: агентов числом, «я», прошлая ли.
        func flow(past: Bool) -> PanelRole {
            let count = agents.range(of: "\\d+", options: .regularExpression).flatMap { Int(agents[$0]) } ?? 0
            return PanelRole(name: name, model: shownModel, agents: count, me: agents == "я" || agents.hasPrefix("я "),
                             running: running, past: past, red: red)
        }
    }

    /// Блок в разборе: «о чём», шаги, время, прошлые шаги и роли.
    struct Block {
        let state: PanelWorkflow.State
        var about = ""
        var stepsDone: Int?
        var stepsTotal: Int?
        var time = ""
        var past: [String] = []
        /// Прошлые шаги ролями целиком («планирование · 1 агент · Opus 5.5 high — итог»), имя — первое слово.
        var pastRoles: [Role] = []
        var roles: [Role] = []

        init(state: PanelWorkflow.State) { self.state = state }

        mutating func take(_ item: String) {
            if stepsTotal == nil, let steps = PanelProjects.steps(item) {
                stepsDone = steps.done
                stepsTotal = steps.total
            }
            let lower = item.lowercased()
            if lower.hasPrefix("прошл"), lower.contains("шаг") {
                let body = item.firstIndex(of: ":").map { String(item[item.index(after: $0)...]) } ?? ""
                past = []
                pastRoles = []
                for chunk in body.components(separatedBy: ";") {
                    guard let word = PanelProjects.pastName(chunk) else { continue }
                    past.append(word)
                    var was = Role(chunk.components(separatedBy: "—")[0])
                    was.name = word
                    pastRoles.append(was)
                }
                return
            }
            let hasClock = PanelProjects.hasClock(item)
            if about.isEmpty, !lower.hasPrefix("шаги"), !hasClock {
                about = item
                if let range = about.range(of: "^о\\s+чём\\s*:\\s*", options: [.regularExpression, .caseInsensitive]) {
                    about.removeSubrange(range)
                }
                return
            }
            if time.isEmpty, hasClock { time = item; return }
            // Несколько ролей одной строкой через «;» («критик · 1 агент · high; кодинг · 3 агента · high» — так пишут
            // сводки на Маке, #10239) — каждая своей ролью.
            for chunk in item.components(separatedBy: ";") {
                let part = chunk.trimmingCharacters(in: .whitespaces)
                let role = part.components(separatedBy: CharacterSet(charactersIn: "·•")).first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if part.contains("·"), !part.contains("→"), !role.isEmpty, !role.contains(where: { $0.isNumber }) {
                    roles.append(Role(part))
                }
            }
        }

        var workflow: PanelWorkflow {
            let own = Set(roles.map { $0.name.lowercased() })
            return PanelWorkflow(about: about, state: state, stepsDone: stepsDone, stepsTotal: stepsTotal, time: time,
                                 phases: PanelProjects.phases(past: past, roles: roles, state: state),
                                 roles: pastRoles.filter { !own.contains($0.name.lowercased()) }.map { $0.flow(past: true) }
                                    + roles.map { $0.flow(past: false) })
        }
    }

    static func steps(_ item: String) -> (done: Int, total: Int)? {
        let parts = item.lowercased().split(separator: " ")
        guard parts.count >= 4, parts[0] == "шаги", parts[2] == "из",
              let done = Int(parts[1]), let total = Int(parts[3].prefix { $0.isNumber }) else { return nil }
        return (done, total)
    }

    /// «ЧЧ:ММ» где-то в строке (как `/\d\s*:\s*\d/` страницы).
    static func hasClock(_ item: String) -> Bool {
        item.range(of: "\\d\\s*:\\s*\\d", options: .regularExpression) != nil
    }

    /// Имя прошлой фазы: первое слово куска до «—», «·», «,» или «:».
    static func pastName(_ chunk: String) -> String? {
        let head = chunk.components(separatedBy: CharacterSet(charactersIn: "—·,:")).first ?? ""
        let word = head.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        return word.isEmpty ? nil : word
    }

    /// Полоса фаз (§3.2): прошлые, потом роли; одно имя — один отрезок; текущий — первая роль с 💭, иначе последняя.
    static func phases(past: [String], roles: [Role], state: PanelWorkflow.State) -> [PanelPhase] {
        var names: [String] = []
        for name in past + roles.map({ $0.name }) where !name.isEmpty {
            if !names.contains(where: { $0.lowercased() == name.lowercased() }) { names.append(name) }
        }
        let currentRole = roles.first { $0.running } ?? roles.last
        let currentIndex = currentRole.flatMap { role in names.firstIndex { $0.lowercased() == role.name.lowercased() } }
        var out: [PanelPhase] = []
        for (index, name) in names.prefix(phasesLimit).enumerated() {
            let role = index == currentIndex ? currentRole : roles.first { $0.name.lowercased() == name.lowercased() }
            let phaseState: PanelPhase.State
            switch state {
            case .done: phaseState = .done
            case .planned: phaseState = .future
            case .running, .waiting, .failed:
                if let current = currentIndex {
                    if index < current { phaseState = .done }
                    else if index == current { phaseState = state == .failed ? .failed : .current }
                    else { phaseState = .future }
                } else {
                    phaseState = .done
                }
            }
            out.append(PanelPhase(name: shortName(name), state: phaseState, help: role?.line ?? name))
        }
        return out
    }

    /// «планирование» → «план»; длиннее 9 знаков — «…».
    static func shortName(_ name: String) -> String {
        if name.lowercased() == "планирование" { return "план" }
        return name.count > 9 ? String(name.prefix(8)) + "…" : name
    }

    // MARK: готовые слова (§3.4)

    /// Значение «Ждёт Элвиса», которое значит «ничего не ждёт».
    public static func isNothing(_ value: String) -> Bool {
        var clean = value.trimmingCharacters(in: .whitespaces)
        if clean.hasSuffix(".") { clean.removeLast() }
        return ["", "ничего", "нет", "—", "-"].contains(clean.lowercased())
    }

    /// Пункт — готовое слово, если в нём нет ничего, кроме фраз в «ёлочках», связок « и », «, », « или » и точки.
    public static func words(_ waitFor: String) -> (words: [String], note: String) {
        var words: [String] = []
        var notes: [String] = []
        for raw in waitFor.components(separatedBy: ";") {
            let item = raw.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { continue }
            if let phrases = readyPhrases(item), words.count + phrases.count <= wordsPerProject {
                words += phrases
            } else {
                notes.append(item)
            }
        }
        return (words, notes.joined(separator: "; "))
    }

    static func readyPhrases(_ item: String) -> [String]? {
        var phrases: [String] = []
        var rest = ""
        var inside: String?
        for character in item {
            if character == "«" {
                guard inside == nil else { return nil }
                inside = ""
            } else if character == "»" {
                guard let phrase = inside else { return nil }
                phrases.append(phrase.trimmingCharacters(in: .whitespaces))
                inside = nil
            } else if inside != nil {
                inside?.append(character)
            } else {
                rest.append(character)
            }
        }
        guard inside == nil, !phrases.isEmpty,
              phrases.allSatisfy({ !$0.isEmpty && $0.count <= wordLimit }) else { return nil }
        let leftover = rest.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ".", with: " ")
            .split(separator: " ").filter { $0 != "и" && $0 != "или" }
        return leftover.isEmpty ? phrases : nil
    }

    // MARK: снимок (§3.1, §3.3)

    /// Папка — копия-рабочее дерево: `.git` у неё файл («gitdir: …»), а не каталог.
    static func isWorktree(_ folder: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let git = folder.appendingPathComponent(".git").path
        return fileManager.fileExists(atPath: git, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    /// Рабочая копия (WF202): worktree или имя с хвостом `-wf<N>`/`-rev`/`-inst<N>` — как у сводки проектов
    /// (`StatusFeed.isWorkingCopy`), чтобы панель, `/digest` и карточка Workflow видели одни и те же проекты.
    static func isWorkingCopy(_ folder: URL, fileManager: FileManager) -> Bool {
        StatusFeed.isWorkingCopy(name: folder.lastPathComponent, at: folder, fileManager: fileManager)
    }

    /// Сводка папки — `ownStatusFile`; у папки с рабочими деревьями git — самая свежая из её и их (#9519: Workflow
    /// сайта кафе идёт в копии `VkusnoffKz-iiko1019`, Пимпа — в `PimpMyClaude-wf269`, а сводки главных папок стоят, и
    /// панель, `/digest` и сводка проектов их не видели). Копии сами проектами не становятся (`isWorkingCopy`).
    static func statusFile(in folder: URL, fileManager: FileManager) -> URL? {
        let files = ([folder] + worktrees(of: folder, fileManager: fileManager)).compactMap { ownStatusFile(in: $0, fileManager: fileManager) }
        guard files.count > 1 else { return files.first }
        let changed = { (url: URL) in (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? .distantPast }
        return files.max { changed($0) < changed($1) }
    }

    /// Рабочие деревья папки по `.git/worktrees/*/gitdir` (там путь к `<дерево>/.git`); пропавшие с диска — мимо.
    static func worktrees(of folder: URL, fileManager: FileManager) -> [URL] {
        let list = folder.appendingPathComponent(".git", isDirectory: true).appendingPathComponent("worktrees", isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: list.path) else { return [] }
        return names.sorted().compactMap { name in
            guard let line = try? String(contentsOf: list.appendingPathComponent(name).appendingPathComponent("gitdir"), encoding: .utf8)
            else { return nil }
            let git = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard git.hasSuffix("/.git") else { return nil }
            let tree = URL(fileURLWithPath: String(git.dropLast(5)), isDirectory: true)
            return fileManager.fileExists(atPath: tree.path) ? tree : nil
        }
    }

    /// Первый `{docs,audit,work}/status.md`, чей настоящий файл лежит в ЭТОЙ папке.
    static func ownStatusFile(in folder: URL, fileManager: FileManager) -> URL? {
        let own = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for sub in StatusFeed.statusFolders {
            let url = folder.appendingPathComponent(sub, isDirectory: true).appendingPathComponent(StatusFeed.statusFileName)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let real = url.resolvingSymlinksInPath().standardizedFileURL.path
            return real.hasPrefix(own) ? url : nil
        }
        return nil
    }

    /// Обход: папки `root` (без скрытых и рабочих деревьев) и недавние проекты; кто куда — по §3.3. Идущие и упавшие —
    /// только у живых проектов (#10315, `isLive`): `terminals` — живые сессии tmux, `activeTerminals` — с движением
    /// (nil — все), `pages` — работающие страницы, `seen` — память времени содержимого (nil — по mtime), `muted` —
    /// заглушённые «Ждёт Элвиса:» (#9820, `MutedWaits`: такой строки как будто нет).
    public static func snapshot(root: URL, recent: [(folder: URL, name: String)], mainEntry: String?, now: Date,
                                fileManager: FileManager = .default, terminals: Set<String> = [],
                                activeTerminals: Set<String>? = nil, pages: [FlowPage] = [],
                                seen memory: FlowSeen? = nil, muted: MutedWaits? = nil) -> PanelSnapshot {
        var folders: [(url: URL, name: String, recent: Bool)] = []
        var seen = Set<String>()
        func add(_ url: URL, _ name: String, recent: Bool) {
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else {
                if recent, let index = folders.firstIndex(where: { $0.url.standardizedFileURL.path == key }) {
                    folders[index].recent = true
                }
                return
            }
            seen.insert(key)
            folders.append((url, name, recent))
        }
        for item in recent where !isWorkingCopy(item.folder, fileManager: fileManager) {
            add(item.folder, item.name, recent: true)
        }
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names.sorted() where !name.hasPrefix(".") {
            let url = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  !isWorkingCopy(url, fileManager: fileManager) else { continue }
            add(url, name, recent: false)
        }
        // Первый проход — сводки; второй — кто живой (терминал и страница ищут хозяина среди всех проектов) и кто куда.
        let reads = folders.map { readStatus(in: $0.url, fileManager: fileManager, seen: memory, now: now) }
        memory?.flush(now: now)
        var statuses = reads.map { $0.map { parse($0.text) } ?? PanelStatus() }
        if let muted = muted {
            for index in statuses.indices
            where muted.isMuted(folder: folders[index].url, text: statuses[index].waitFor, now: now) {
                statuses[index].waitFor = ""
            }
        }
        let candidates: [LiveCandidate] = folders.indices.map { index in
            (key: folders[index].url.standardizedFileURL.path, folder: folders[index].url.lastPathComponent,
             name: statuses[index].name, updated: reads[index]?.changed, trees: reads[index]?.trees ?? [])
        }
        let named = candidates.map { (key: $0.key, folder: $0.folder, name: $0.name, updated: $0.updated) }
        let busyTerminals = PanelTiles.terminalOwners(named, sessions: activeTerminals ?? terminals)
        let busyPages = pageOwners(pages, candidates: candidates)
        var waiting: [PanelProject] = [], working: [PanelProject] = [], others: [PanelProject] = []
        for (index, folder) in folders.enumerated() {
            let status = statuses[index]
            // Время изменения содержимого, а не правки файла (#10315): checkout старой сводки свежей её не делает.
            let updated = reads[index]?.changed
            let age = updated.map { now.timeIntervalSince($0) } ?? .infinity
            let path = folder.url.standardizedFileURL.path
            let waitsLine = !status.waitFor.isEmpty && !isNothing(status.waitFor)
            let waitBlocks = status.workflows.filter { $0.state == .waiting }
            let waits = age <= waitFreshSeconds && (waitsLine || !waitBlocks.isEmpty)
            let live = isLive(changedAge: age, terminal: busyTerminals.contains(path), page: busyPages.contains(path))
            let running = live ? status.workflows.filter { $0.state == .running || $0.state == .failed } : []
            var split: (words: [String], note: String) = waitsLine ? words(status.waitFor) : (words: [], note: "")
            if waits, !waitsLine, let block = waitBlocks.first {
                split.note = "Workflow «\(block.about)» ждёт тебя"
            }
            let project = PanelProject(
                folder: path, name: status.name.isEmpty ? folder.name : status.name, marker: status.marker,
                isMain: PimpChannel.isMainProject(folder: path, entry: mainEntry), updated: updated, now: freshNow(status, age: age),
                words: split.words, note: split.note, waits: waits, running: running,
                workflows: status.workflows, marathon: status.marathon, stamp: status.stamp,
                waitFor: freshWait(status, age: age), statusFile: reads[index]?.url.path ?? "")
            if waits { waiting.append(project) }
            if !running.isEmpty { working.append(project) }
            // Главный — всегда плашкой, даже без своей сводки (у Rick она ссылка на чужую).
            if !waits, running.isEmpty, folder.recent || age <= waitFreshSeconds || project.isMain {
                others.append(project)
            }
        }
        let fresh: (PanelProject, PanelProject) -> Bool = {
            ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast)
        }
        waiting.sort(by: fresh)
        working.sort(by: fresh)
        // Главный — первым, дальше как пришли (недавние, потом папки по имени).
        others = others.filter { $0.isMain } + others.filter { !$0.isMain }
        // Сверх двадцати — только сводки за сутки (#10239): по ним блок Workflow считает «готово» и «впереди».
        let day = others.dropFirst(20).filter { $0.updated.map { now.timeIntervalSince($0) <= 86_400 } ?? false }
        return PanelSnapshot(waiting: waiting, working: working, others: Array(others.prefix(20)) + day,
                             terminals: terminals, activeTerminals: activeTerminals)
    }
}

/// Кружок темы в ряду «Окна» панели: цвет основы и акцента из каталога.
public struct WindowColorChip: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let background: String
    public let accent: String
    /// Светлая тема (`type` «light») — полоса светлых в «Цвет Claude» (WF174).
    public let light: Bool

    init(_ theme: Theme) {
        self.init(id: theme.id, name: theme.name, background: theme.palette["background"] ?? "#2b2a27",
                  accent: theme.palette["accent"] ?? "#9b9ba1", light: theme.type == "light")
    }

    public init(id: String, name: String, background: String, accent: String, light: Bool) {
        self.id = id
        self.name = name
        self.background = background
        self.accent = accent
        self.light = light
    }
}

/// Цвет окон Claude: у каждого проекта свой, одна тема всем окнам, или как у Claude.
public enum WindowColorChoice: Equatable {
    case byProject
    case theme(String)
    case plain
}
