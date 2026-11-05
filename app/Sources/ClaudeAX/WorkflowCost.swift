import Foundation
import Patcher

// Цена Workflow в долларах (#6282, слово Элвиса: «Можешь вычислить по ценам API, сколько он занял, потратил этот workflow
// денег… Чтоб люди видели. По проектам на какой сколько токенов тратится»). Строке блока Workflow — прогоны Workflow
// Claude Code (`~/.claude/projects/<папка>/<сессия>/subagents/workflows/<run_id>/*.jsonl`): точно — по run-файлу
// `run-wf<N>*.json` рядом со сводкой, иначе — единственный прогон из папок проекта, начавшийся в пределах 15 мин от
// строки. Деньги — по ценам API (`ModelPrices`), суммы файлов — в кэше `workflow-cost.json` по (путь, mtime, размер).
// Нет данных или спорно — цены нет совсем. Контракт — `docs/contracts/535-6282-workflow-cost.md`, решения —
// `docs/decisions/2026-10-19-cena-workflow-6282.md`, тесты — `WorkflowCostTests`, вид — `Panel/PanelWorkflowCost.swift`.

// MARK: суммы

/// Токены и деньги файла, прогона, строки или проекта.
public struct CostTotals: Equatable {
    /// Вход без кэша, выход, запись кэша (5 мин и 1 ч), чтение кэша.
    public var input = 0
    public var output = 0
    public var write = 0
    public var read = 0
    public var usd = 0.0
    /// Ответов без цены: модели нет в таблице или быстрый режим у модели без его цен — сумма тогда «от».
    public var unpriced = 0

    public init(input: Int = 0, output: Int = 0, write: Int = 0, read: Int = 0, usd: Double = 0, unpriced: Int = 0) {
        self.input = input
        self.output = output
        self.write = write
        self.read = read
        self.usd = usd
        self.unpriced = unpriced
    }

    public static func + (a: CostTotals, b: CostTotals) -> CostTotals {
        CostTotals(input: a.input + b.input, output: a.output + b.output, write: a.write + b.write, read: a.read + b.read,
                   usd: a.usd + b.usd, unpriced: a.unpriced + b.unpriced)
    }

    public static func += (a: inout CostTotals, b: CostTotals) { a = a + b }

    public var tokens: Int { input + output + write + read }
}

/// Цена строки или проекта для вида.
public struct WorkflowCostItem: Equatable {
    public var totals: CostTotals
    /// Не все прогоны run-файла нашлись на этом Маке.
    public var missing = false

    public init(totals: CostTotals, missing: Bool = false) {
        self.totals = totals
        self.missing = missing
    }

    /// «От»: что-то не посчитано (неизвестная модель, пропавший прогон).
    public var partial: Bool { totals.unpriced > 0 || missing }

    /// «≈ $4,20», «≈ от $3,10», меньше цента — «< $0,01».
    public var label: String {
        if partial { return "≈ от " + WorkflowCost.dollars(max(totals.usd, 0.01)) }
        return totals.usd < 0.01 ? "< $0,01" : "≈ " + WorkflowCost.dollars(totals.usd)
    }

    /// «По ценам API: вход 1,2 млн, выход 80 тыс, кэш 9 млн. По подписке за это отдельно не платят» (+ почему «от»).
    public var help: String {
        var text = "По ценам API: вход \(TokenStats.human(totals.input)), выход \(TokenStats.human(totals.output)), "
            + "кэш \(TokenStats.human(totals.write + totals.read)). По подписке за это отдельно не платят"
        if totals.unpriced > 0 { text += "\nНе все модели известны — сумма не меньше этой" }
        if missing { text += "\nНе все прогоны нашлись на этом Маке — сумма не меньше этой" }
        return text
    }
}

/// Workflow за 7 дней для окна «Токены» (#6282, «графики по Workflow»): строка сводки и её прогоны, начавшиеся за 7 дней.
public struct WorkflowWeekFlow: Equatable {
    public var key: String
    public var project: String
    /// «о чём» без приставки проекта (`WorkflowBlock.aboutText`).
    public var about: String
    /// Начало самого раннего её прогона за 7 дней.
    public var start: Date
    public var item: WorkflowCostItem

    public init(key: String, project: String, about: String, start: Date, item: WorkflowCostItem) {
        self.key = key
        self.project = project
        self.about = about
        self.start = start
        self.item = item
    }
}

/// Цены блока Workflow: строкам (`key`) и проектам за 7 дней (`Row.projectName`); `flows` — Workflow за 7 дней,
/// дорогие первыми.
public struct WorkflowCosts: Equatable {
    public var rows: [String: WorkflowCostItem]
    public var week: [String: WorkflowCostItem]
    public var flows: [WorkflowWeekFlow]

    public init(rows: [String: WorkflowCostItem] = [:], week: [String: WorkflowCostItem] = [:], flows: [WorkflowWeekFlow] = []) {
        self.rows = rows
        self.week = week
        self.flows = flows
    }

    /// Ключ строки: «папка#номер» и «о чём» — сводку переписали, номер съехал — чужая цена не встанет.
    public static func key(_ row: WorkflowBlock.Row) -> String { row.id + "|" + row.flow.about }

    public func cost(_ row: WorkflowBlock.Row) -> WorkflowCostItem? { rows[Self.key(row)] }
    public func week(_ row: WorkflowBlock.Row) -> WorkflowCostItem? { week[row.projectName] }
}

// MARK: подсчёт

public enum WorkflowCost {
    /// Запасная привязка: прогон начался не дальше от начала строки.
    public static let windowSeconds: TimeInterval = 15 * 60
    /// Сумма проекта — прогоны, начавшиеся за столько.
    public static let weekSeconds: TimeInterval = 7 * 86_400
    /// Run-файл больше — не читается (приходят через git, чужие).
    static let runFileLimit = 1 << 20
    /// Первая строка транскрипта длиннее — начало прогона по ней не ищется.
    static let firstLineLimit = 4 << 20
    static let runIDPattern = "^wf_[A-Za-z0-9-]{1,40}$"

    /// «$4,20»; от тысячи — целыми, тысячи через неразрывный пробел: «$1 235».
    public static func dollars(_ usd: Double) -> String {
        guard usd >= 1000 else { return "$" + String(format: "%.2f", usd).replacingOccurrences(of: ".", with: ",") }
        var digits = String(Int(usd.rounded()))
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        return "$" + ([digits] + groups).joined(separator: "\u{00A0}")
    }

    // MARK: файлы и папки Claude Code

    /// Папка транскриптов Claude Code для пути проекта: всё, кроме латиницы и цифр, — «-» (по единицам UTF-16, как
    /// у Claude Code). Длиннее 200 — Claude Code режет и дописывает хэш: такие ищутся по началу (`transcriptDirs`).
    public static func encoded(_ path: String) -> String {
        String(path.utf16.map { unit -> Character in
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return Character(UnicodeScalar(unit)!)
            default: return "-"
            }
        })
    }

    /// Папки транскриптов проекта и его рабочих деревьев git, что есть на диске: путь как записан и без ссылок
    /// (Claude Code берёт настоящий путь папки).
    static func transcriptDirs(_ folder: String, projects: URL, fileManager: FileManager) -> [URL] {
        let base = URL(fileURLWithPath: folder, isDirectory: true)
        let trees = [base] + PanelProjects.worktrees(of: base, fileManager: fileManager)
        var paths: [String] = []
        for tree in trees {
            for path in [tree.standardizedFileURL.path, real(tree.path)].compactMap({ $0 }) where !paths.contains(path) {
                paths.append(path)
            }
        }
        var listing: [String]?
        var out: [URL] = []
        for path in paths {
            let name = encoded(path)
            var found: [URL] = []
            if name.count <= 200 {
                found = [projects.appendingPathComponent(name, isDirectory: true)].filter { fileManager.fileExists(atPath: $0.path) }
            } else {
                if listing == nil { listing = (try? fileManager.contentsOfDirectory(atPath: projects.path)) ?? [] }
                let head = String(name.prefix(200)) + "-"
                found = (listing ?? []).filter { $0.hasPrefix(head) }.map { projects.appendingPathComponent($0, isDirectory: true) }
            }
            for dir in found where !out.contains(dir) { out.append(dir) }
        }
        return out
    }

    /// Каталоги прогонов `<сессия>/subagents/workflows/wf_*` папки транскриптов; `since` — только менявшиеся с тех пор.
    static func runDirs(in transcripts: URL, since: Date?, fileManager: FileManager) -> [URL] {
        let sessions = (try? fileManager.contentsOfDirectory(atPath: transcripts.path)) ?? []
        var out: [URL] = []
        for session in sessions.sorted() where !session.hasPrefix(".") {
            let workflows = transcripts.appendingPathComponent(session, isDirectory: true)
                .appendingPathComponent("subagents/workflows", isDirectory: true)
            guard let runs = try? fileManager.contentsOfDirectory(atPath: workflows.path) else { continue }
            for run in runs.sorted() where run.range(of: runIDPattern, options: .regularExpression) != nil {
                let dir = workflows.appendingPathComponent(run, isDirectory: true)
                if let since = since,
                   let mtime = (try? fileManager.attributesOfItem(atPath: dir.path))?[.modificationDate] as? Date,
                   mtime < since { continue }
                out.append(dir)
            }
        }
        return out
    }

    /// Транскрипты прогона: все `*.jsonl` в его каталоге и вложенных (агенты агентов), кроме `journal.jsonl`.
    static func runFiles(_ dir: URL, fileManager: FileManager) -> [URL] {
        guard let walker = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker {
            if walker.level > 3 { walker.skipDescendants(); continue }
            guard url.pathExtension == "jsonl", url.lastPathComponent != "journal.jsonl",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            out.append(url)
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Время первой строки транскрипта (`timestamp` верхнего уровня); не прочесть — nil.
    static func firstTimestamp(_ url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var line = Data()
        while line.count < firstLineLimit {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            if let end = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                line.append(chunk[chunk.startIndex..<end])
                break
            }
            line.append(chunk)
        }
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let raw = record["timestamp"] as? String else { return nil }
        return ClaudeUsage.date(raw)
    }

    /// Начало прогона: самая ранняя первая строка его транскриптов (файл состояния прогона пишется только в конце).
    static func runStart(_ dir: URL, fileManager: FileManager) -> Date? {
        runFiles(dir, fileManager: fileManager).compactMap(firstTimestamp).min()
    }

    // MARK: run-файлы

    /// Ссылка на прогон из run-файла: `run_id` и `script_path` того же объекта.
    struct RunRef: Equatable {
        let id: String
        let script: String?
    }

    /// Номер Workflow из «о чём»: «WF247 — …» → 247 (только в начале — «как в WF240» не в счёт).
    static func wfNumber(_ about: String) -> Int? {
        let text = about.trimmingCharacters(in: .whitespaces)
        guard let range = text.range(of: "^WF[0-9]+(?![0-9])", options: .regularExpression) else { return nil }
        return Int(text[range].dropFirst(2))
    }

    /// Run-файлы Workflow `wf` рядом со сводкой: `run-wf<N>.json` и `run-wf<N>-*.json` (не `run-wf<N>7…`).
    static func runFiles(statusFolder: URL, wf: Int, fileManager: FileManager) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: statusFolder.path)) ?? []
        let exact = "run-wf\(wf).json", head = "run-wf\(wf)-"
        return names.filter { $0 == exact || ($0.hasPrefix(head) && $0.hasSuffix(".json")) }.sorted()
            .map { statusFolder.appendingPathComponent($0) }
    }

    /// Все пары `run_id`/`script_path` run-файла (верхний уровень, `runs.*`, волны — до 4 уровней); плохой `run_id` —
    /// мимо.
    static func runRefs(_ data: Data) -> [RunRef] {
        guard data.count <= runFileLimit, let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [RunRef] = []
        func walk(_ value: Any, depth: Int) {
            guard depth <= 4 else { return }
            if let object = value as? [String: Any] {
                if let id = object["run_id"] as? String, id.range(of: runIDPattern, options: .regularExpression) != nil,
                   !out.contains(where: { $0.id == id }) {
                    out.append(RunRef(id: id, script: object["script_path"] as? String))
                }
                for key in object.keys.sorted() { walk(object[key]!, depth: depth + 1) }
            } else if let list = value as? [Any] {
                list.forEach { walk($0, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return out
    }

    /// Путь без ссылок (`realpath`); файла нет — nil.
    static func real(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Каталог прогона одним путём, как бы его ни нашли (по `script_path` или обходом папок).
    static func canonical(_ dir: URL) -> URL {
        real(dir.path).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? dir.standardizedFileURL
    }

    /// Каталог сессии по `script_path` (`<projects>/<папка>/<сессия>/workflows/scripts/<файл>`): только если каталог
    /// сессии есть и после раскрытия ссылок лежит прямо в `<projects>/<папка>/`; иначе nil (run-файлы чужие, приходят
    /// через git — путь не берём на веру).
    static func sessionDir(script: String, projects: URL) -> URL? {
        guard script.hasPrefix("/") else { return nil }
        let file = URL(fileURLWithPath: script).standardizedFileURL
        let parts = file.pathComponents
        guard parts.count >= 6, parts[parts.count - 3] == "workflows", parts[parts.count - 2] == "scripts" else { return nil }
        let session = file.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let realSession = real(session.path), let realRoot = real(projects.path),
              realSession.hasPrefix(realRoot + "/") else { return nil }
        let tail = realSession.dropFirst(realRoot.count + 1).split(separator: "/")
        guard tail.count == 2, !tail[0].hasPrefix("."), !tail[1].hasPrefix(".") else { return nil }
        return URL(fileURLWithPath: realSession, isDirectory: true)
    }

    // MARK: привязка и суммы

    /// Цены строк `shown` и суммы проектов за 7 дней. `rows` — все строки сводок (по ним и спорность прогонов), читаются
    /// только прогоны показанных строк и начавшиеся за 7 дней.
    public static func compute(rows: [WorkflowBlock.Row], shown: Set<String>, now: Date, store: WorkflowCostStore,
                               fileManager: FileManager = .default) -> WorkflowCosts {
        let weekStart = now.addingTimeInterval(-weekSeconds)
        let horizon = weekStart.addingTimeInterval(-86_400)
        var starts: [String: [Int: Date]] = [:]
        var transcripts: [String: [URL]] = [:]
        var candidates: [String: [URL]] = [:]
        func rowStart(_ row: WorkflowBlock.Row) -> Date? {
            if starts[row.project.folder] == nil { starts[row.project.folder] = WorkflowBlock.starts(row.project, now: now) }
            return starts[row.project.folder]?[row.index]
        }
        func dirs(_ folder: String) -> [URL] {
            if let known = transcripts[folder] { return known }
            let found = transcriptDirs(folder, projects: store.projects, fileManager: fileManager)
            transcripts[folder] = found
            return found
        }
        // Прогон run-файла: по `script_path`, иначе — в сессиях папок проекта.
        func locate(_ ref: RunRef, folder: String) -> URL? {
            if let script = ref.script, let session = sessionDir(script: script, projects: store.projects) {
                let dir = session.appendingPathComponent("subagents/workflows", isDirectory: true)
                    .appendingPathComponent(ref.id, isDirectory: true)
                if fileManager.fileExists(atPath: dir.path) { return dir }
            }
            for transcript in dirs(folder) {
                let sessions = (try? fileManager.contentsOfDirectory(atPath: transcript.path)) ?? []
                for session in sessions.sorted() where !session.hasPrefix(".") {
                    let dir = transcript.appendingPathComponent(session, isDirectory: true)
                        .appendingPathComponent("subagents/workflows", isDirectory: true)
                        .appendingPathComponent(ref.id, isDirectory: true)
                    if fileManager.fileExists(atPath: dir.path) { return dir }
                }
            }
            return nil
        }

        // 1. Точная привязка — run-файлы; запасная — после, из прогонов, никем не взятых точно.
        var claims: [String: [URL]] = [:]
        var missing: [String: Bool] = [:]
        var loose: [(key: String, row: WorkflowBlock.Row, start: Date)] = []
        var byKey: [String: WorkflowBlock.Row] = [:]
        for row in rows {
            let key = WorkflowCosts.key(row)
            let start = rowStart(row)
            guard shown.contains(key) || (start.map { $0 >= horizon } ?? false), byKey[key] == nil else { continue }
            byKey[key] = row
            if let wf = wfNumber(WorkflowBlock.aboutText(row)), !row.project.statusFile.isEmpty {
                let folder = URL(fileURLWithPath: row.project.statusFile).deletingLastPathComponent()
                let refs = runFiles(statusFolder: folder, wf: wf, fileManager: fileManager)
                    .flatMap { store.runRefs($0, fileManager: fileManager) }
                if !refs.isEmpty {
                    let found = refs.compactMap { locate($0, folder: row.project.folder) }.map(canonical)
                    claims[key] = found
                    missing[key] = found.count < refs.count
                    continue
                }
            }
            if let start = start { loose.append((key, row, start)) }
        }
        let taken = Set(claims.values.flatMap { $0.map(\.path) })
        for item in loose {
            let folder = item.row.project.folder
            if candidates[folder] == nil {
                candidates[folder] = dirs(folder).flatMap { runDirs(in: $0, since: horizon, fileManager: fileManager) }
                    .map(canonical)
            }
            let near = (candidates[folder] ?? []).filter { dir in
                guard !taken.contains(dir.path), let start = store.runStart(dir, fileManager: fileManager) else { return false }
                return abs(start.timeIntervalSince(item.start)) <= windowSeconds
            }
            // Два кандидата — не угадываем.
            if near.count == 1 { claims[item.key] = near }
        }

        // 2. Прогон у двух строк — спорный: цены нет у обеих.
        var owners: [String: Int] = [:]
        for runs in claims.values { for run in Set(runs.map(\.path)) { owners[run, default: 0] += 1 } }
        let contested = Set(owners.filter { $0.value > 1 }.keys)

        // 3. Суммы: строкам на виду — все их прогоны, проектам — прогоны за 7 дней.
        var runTotals: [String: CostTotals] = [:]
        func totals(_ dir: URL) -> CostTotals {
            if let known = runTotals[dir.path] { return known }
            let sum = runFiles(dir, fileManager: fileManager).reduce(CostTotals()) { $0 + (store.totals($1) ?? CostTotals()) }
            runTotals[dir.path] = sum
            return sum
        }
        var out = WorkflowCosts()
        var weekSums: [String: CostTotals] = [:]
        var listedRuns = Set<String>()
        for (key, runs) in claims where !runs.isEmpty && !runs.contains(where: { contested.contains($0.path) }) {
            guard let row = byKey[key] else { continue }
            if shown.contains(key) {
                let sum = runs.reduce(CostTotals()) { $0 + totals($1) }
                if worth(sum) { out.rows[key] = WorkflowCostItem(totals: sum, missing: missing[key] ?? false) }
            }
            var flowSum = CostTotals()
            var flowStart: Date?
            for run in runs {
                guard let start = store.runStart(run, fileManager: fileManager), start >= weekStart else { continue }
                weekSums[row.projectName, default: CostTotals()] += totals(run)
                flowSum += totals(run)
                flowStart = min(flowStart ?? start, start)
            }
            if let start = flowStart, worth(flowSum) {
                out.flows.append(WorkflowWeekFlow(key: key, project: row.projectName, about: WorkflowBlock.aboutText(row),
                                                  start: start, item: WorkflowCostItem(totals: flowSum, missing: missing[key] ?? false)))
                listedRuns.formUnion(runs.map(\.path))
            }
        }
        // 4. Окно «Токены»: прогоны папок проектов за 7 дней, что не встали ни в одну строку (марафон со своим run-файлом,
        // спорный, без сводки), — под своим именем (`runName`).
        for row in rows {
            let folder = row.project.folder
            if candidates[folder] == nil {
                candidates[folder] = dirs(folder).flatMap { runDirs(in: $0, since: horizon, fileManager: fileManager) }
                    .map(canonical)
            }
            for run in candidates[folder] ?? [] where listedRuns.insert(run.path).inserted {
                guard let start = store.runStart(run, fileManager: fileManager), start >= weekStart else { continue }
                let sum = totals(run)
                guard worth(sum) else { continue }
                out.flows.append(WorkflowWeekFlow(key: run.path, project: row.project.name,
                                                  about: runName(run, fileManager: fileManager) ?? "Workflow без имени",
                                                  start: start, item: WorkflowCostItem(totals: sum)))
            }
        }
        out.week = weekSums.filter { worth($0.value) }.mapValues { WorkflowCostItem(totals: $0) }
        out.flows.sort { $0.item.totals.usd != $1.item.totals.usd ? $0.item.totals.usd > $1.item.totals.usd : $0.start > $1.start }
        return out
    }

    /// Имя прогона для окна «Токены»: скрипт `<сессия>/workflows/scripts/<имя>-<run_id>.js`, иначе `workflowName` файла
    /// состояния `<сессия>/workflows/<run_id>.json` (пишется в конце, до 8 МБ); нет — nil.
    static func runName(_ dir: URL, fileManager: FileManager) -> String? {
        let id = dir.lastPathComponent
        let workflows = dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("workflows", isDirectory: true)
        let suffix = "-" + id + ".js"
        let scripts = (try? fileManager.contentsOfDirectory(atPath: workflows.appendingPathComponent("scripts").path)) ?? []
        if let file = scripts.first(where: { $0.hasSuffix(suffix) && $0.count > suffix.count }) {
            return String(file.dropLast(suffix.count))
        }
        let state = workflows.appendingPathComponent(id + ".json")
        guard let size = (try? fileManager.attributesOfItem(atPath: state.path))?[.size] as? Int, size <= 8_000_000,
              let data = fileManager.contents(atPath: state.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = (json["workflowName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        return String(name.prefix(120))
    }

    /// Есть что показать: токены есть и хоть что-то оценено (всё без цены — цены нет совсем, не «от $0»).
    static func worth(_ totals: CostTotals) -> Bool {
        totals.tokens > 0 && (totals.usd > 0 || totals.unpriced == 0)
    }

    /// Суммы одного файла: ответ — один раз по `message.id` (строка с самым поздним временем), `<synthetic>` — мимо.
    static func scan(_ url: URL) -> CostTotals {
        var byId: [String: ClaudeUsageLine] = [:]
        ClaudeUsage.read(url, since: .distantPast, into: &byId)
        var out = CostTotals()
        for line in byId.values where line.model != "<synthetic>" {
            let hour = min(max(0, line.cacheWrite1h), line.cacheCreate)
            out.input += line.input
            out.output += line.output
            out.write += line.cacheCreate
            out.read += line.cacheRead
            if let usd = ModelPrices.cost(model: line.model, input: line.input, output: line.output,
                                          write5m: line.cacheCreate - hour, write1h: hour, read: line.cacheRead,
                                          fast: line.fast, usGeo: line.usGeo) {
                out.usd += usd
            } else {
                out.unpriced += 1
            }
        }
        return out
    }

    /// Все строки сводок снимка по порядку и ключи строк, что видны в блоке Workflow.
    public static func rows(_ snapshot: PanelSnapshot, now: Date) -> (all: [WorkflowBlock.Row], shown: Set<String>) {
        var seen = Set<String>()
        let projects = (snapshot.working + snapshot.waiting + snapshot.others).filter { seen.insert($0.folder).inserted }
        let all = projects.flatMap { project in project.workflows.indices.map { WorkflowBlock.Row(project: project, index: $0) } }
        let groups = WorkflowBlock.groups(snapshot, now: now)
        let shown = Set(((groups[.run] ?? []) + (groups[.done] ?? []) + (groups[.plan] ?? [])).map(WorkflowCosts.key))
        return (all, shown)
    }
}

// MARK: кэш сумм

/// Кэш сумм файлов `workflow-cost.json`: путь → (mtime, размер, когда видели, суммы). Цены сменились (`prices`) или
/// формат чужой — пустой.
public struct WorkflowCostCache: Equatable {
    public static let fileName = "workflow-cost.json"
    static let version = 1
    /// Не виденные столько — долой.
    static let keepSeconds: TimeInterval = 30 * 86_400
    static let limit = 20_000

    struct Entry: Equatable {
        var mtime: Double
        var size: Int
        var seen: Double
        var totals: CostTotals
    }

    var files: [String: Entry] = [:]

    static func parse(_ data: Data?) -> WorkflowCostCache {
        guard let data = data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["version"] as? NSNumber)?.intValue == version,
              (root["prices"] as? NSNumber)?.intValue == ModelPrices.version,
              let files = root["files"] as? [String: Any] else { return WorkflowCostCache() }
        var out = WorkflowCostCache()
        for (path, raw) in files {
            guard let entry = raw as? [String: Any],
                  let mtime = (entry["mtime"] as? NSNumber)?.doubleValue, mtime.isFinite,
                  let size = (entry["size"] as? NSNumber)?.intValue,
                  let seen = (entry["seen"] as? NSNumber)?.doubleValue, seen.isFinite,
                  let usd = (entry["usd"] as? NSNumber)?.doubleValue, usd.isFinite, usd >= 0 else { continue }
            func int(_ key: String) -> Int { max(0, (entry[key] as? NSNumber)?.intValue ?? 0) }
            out.files[path] = Entry(mtime: mtime, size: size, seen: seen,
                                    totals: CostTotals(input: int("in"), output: int("out"), write: int("write"),
                                                       read: int("read"), usd: usd, unpriced: int("unpriced")))
        }
        return out
    }

    func encode() -> Data {
        var files: [String: Any] = [:]
        for (path, entry) in self.files {
            files[path] = ["mtime": entry.mtime, "size": entry.size, "seen": entry.seen, "in": entry.totals.input,
                           "out": entry.totals.output, "write": entry.totals.write, "read": entry.totals.read,
                           "usd": entry.totals.usd, "unpriced": entry.totals.unpriced]
        }
        let body: [String: Any] = ["version": Self.version, "prices": ModelPrices.version, "files": files]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    func pruned(now: Date) -> WorkflowCostCache {
        let edge = now.timeIntervalSince1970 - Self.keepSeconds
        var kept = files.filter { $0.value.seen >= edge }
        if kept.count > Self.limit {
            let order = kept.sorted { $0.value.seen != $1.value.seen ? $0.value.seen > $1.value.seen : $0.key < $1.key }
            kept = Dictionary(uniqueKeysWithValues: order.prefix(Self.limit).map { ($0.key, $0.value) })
        }
        return WorkflowCostCache(files: kept)
    }
}

/// Кэш на диске и в памяти: суммы файлов, начала прогонов, ссылки run-файлов. Ходит к нему одна очередь
/// (`WorkflowCostRunner`), замок — на всякий случай.
public final class WorkflowCostStore {
    public static let shared = WorkflowCostStore(
        file: SupportFiles.directory.appendingPathComponent(WorkflowCostCache.fileName), projects: ChatContext.projectsRoot)

    /// `~/.claude/projects`.
    public let projects: URL
    private let file: URL?
    private let lock = NSLock()
    private var cache: WorkflowCostCache?
    private var dirty = false
    private let now: () -> Date
    private var starts: [String: (mtime: Date?, start: Date?)] = [:]
    private var refs: [String: (mtime: Date?, refs: [WorkflowCost.RunRef])] = [:]
    /// Сколько файлов прочитано целиком (не из кэша) — тестам.
    public private(set) var reads = 0

    public init(file: URL?, projects: URL, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.projects = projects
        self.now = now
    }

    private static func stamp(_ url: URL) -> (mtime: Date?, size: Int)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.modificationDate] as? Date, (attributes[.size] as? NSNumber)?.intValue ?? 0)
    }

    /// Суммы файла: тот же путь, mtime и размер — из кэша, иначе — прочитать. Файла нет — nil.
    func totals(_ url: URL) -> CostTotals? {
        guard let stamp = Self.stamp(url) else { return nil }
        let mtime = stamp.mtime?.timeIntervalSince1970 ?? 0
        let seen = now().timeIntervalSince1970
        lock.lock()
        if cache == nil { cache = WorkflowCostCache.parse(file.flatMap { try? Data(contentsOf: $0) }) }
        if var entry = cache?.files[url.path], abs(entry.mtime - mtime) < 0.001, entry.size == stamp.size {
            if seen - entry.seen > 86_400 {
                entry.seen = seen
                cache?.files[url.path] = entry
                dirty = true
            }
            lock.unlock()
            return entry.totals
        }
        lock.unlock()
        let totals = autoreleasepool { WorkflowCost.scan(url) }
        lock.lock()
        reads += 1
        cache?.files[url.path] = WorkflowCostCache.Entry(mtime: mtime, size: stamp.size, seen: seen, totals: totals)
        dirty = true
        lock.unlock()
        return totals
    }

    /// Начало прогона; каталог не менялся — из памяти.
    func runStart(_ dir: URL, fileManager: FileManager) -> Date? {
        let mtime = Self.stamp(dir)?.mtime
        lock.lock()
        if let known = starts[dir.path], known.mtime == mtime {
            lock.unlock()
            return known.start
        }
        lock.unlock()
        let start = WorkflowCost.runStart(dir, fileManager: fileManager)
        lock.lock()
        starts[dir.path] = (mtime, start)
        lock.unlock()
        return start
    }

    /// Ссылки run-файла; файл не менялся — из памяти.
    func runRefs(_ url: URL, fileManager: FileManager) -> [WorkflowCost.RunRef] {
        guard let stamp = Self.stamp(url), stamp.size <= WorkflowCost.runFileLimit else { return [] }
        lock.lock()
        if let known = refs[url.path], known.mtime == stamp.mtime {
            lock.unlock()
            return known.refs
        }
        lock.unlock()
        let found = (try? Data(contentsOf: url)).map(WorkflowCost.runRefs) ?? []
        lock.lock()
        refs[url.path] = (stamp.mtime, found)
        lock.unlock()
        return found
    }

    /// Записать кэш, если было новое (0600, временный рядом и `rename`); старое и сверх потолка — долой.
    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        guard dirty, let file = file, let current = cache else { return }
        let kept = current.pruned(now: now())
        cache = kept
        if SupportFiles.writeAtomic(file, kept.encode()) { dirty = false }
    }
}

/// Подсчёт в фоне (qos `.utility`, одна очередь): пока идёт — новый не начинается; те же строки — не чаще раза в 60 с
/// (ответ — прошлый). Ответ — на главной нити.
public final class WorkflowCostRunner {
    public static let shared = WorkflowCostRunner(store: .shared)
    static let minGap: TimeInterval = 60

    private let store: WorkflowCostStore
    private let queue = DispatchQueue(label: "pimpmyclaude.workflow-cost", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    private var last: (signature: String, at: Date, costs: WorkflowCosts)?

    public init(store: WorkflowCostStore) { self.store = store }

    public func request(_ snapshot: PanelSnapshot, now: Date = Date(), done: @escaping (WorkflowCosts) -> Void) {
        let (rows, shown) = WorkflowCost.rows(snapshot, now: now)
        let signature = rows.map(WorkflowCosts.key).joined(separator: "\n") + "\u{0}" + shown.sorted().joined(separator: "\n")
        lock.lock()
        if let last = last, last.signature == signature, now.timeIntervalSince(last.at) < Self.minGap, now >= last.at {
            let costs = last.costs
            lock.unlock()
            DispatchQueue.main.async { done(costs) }
            return
        }
        guard !busy else { return lock.unlock() }
        busy = true
        lock.unlock()
        queue.async { [self] in
            let costs = WorkflowCost.compute(rows: rows, shown: shown, now: now, store: store)
            store.flush()
            lock.lock()
            last = (signature, now, costs)
            busy = false
            lock.unlock()
            DispatchQueue.main.async { done(costs) }
        }
    }
}
