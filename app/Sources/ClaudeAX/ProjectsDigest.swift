import Foundation

// Сводка всех проектов для страницы (WF133, контракт К6 `GET /digest`): ячейки Workflow в поле Рика.
// Источники те же, что у `pimp.py digest` и панели: `status.md` проектов (`PanelProjects.parse`), рабочие деревья
// git не считаются, цвет проекта — тема `.pimpmyclaude.json` (ProjectPaint), нет — авто-цвет по имени папки.
// Чистая часть — `projects`/`json`; кэш на 10 с — `ProjectsDigestCache`; тесты — `DigestWF133Tests`.

/// Ячейка Workflow.
struct DigestWorkflow: Codable, Equatable {
    /// Номер по порядку в status.md, с 1.
    let n: Int
    /// «идёт» / «готово» / «ждёт» (ждёт Элвиса) / «впереди» (запланирован, WF145) / «упал».
    let state: String
    /// «О чём», не длиннее 60 знаков.
    let about: String
    /// «1/3»; шагов нет — пусто.
    let steps: String
    /// Текущая фаза («кодинг»); нет — пусто.
    let phase: String
    /// К-DG (WF214): строка времени status.md как есть («13:05 → закончит в 13:50 · идёт 25 мин»); нет — поля нет.
    var when: String? = nil
    /// К-DG: идущая роль словами status.md без модели и эффорта («кодинг · 2 агента»); нет — поля нет.
    var role: String? = nil
}

/// Проект сводки.
struct DigestProject: Codable, Equatable {
    /// Имя папки.
    let name: String
    /// Заголовок status.md без значка; нет — имя папки.
    let title: String
    let marker: String
    /// `#rrggbb` строчными.
    let color: String
    /// «идут» / «ждут» / «тихо».
    let group: String
    let done: Int
    let total: Int
    let workflows: [DigestWorkflow]
    /// Когда проект менялся (WF141): mtime status.md или run-файла рядом (`run-*.json`) — что свежее, ISO 8601.
    /// Нет времени — пусто. Страница по нему ставит свежие наверх.
    let at: String
    /// К-DG (WF214): строки «Сейчас:» и «Ждёт Элвиса:» сводки; пусто (или «ничего») — поля нет.
    var now: String? = nil
    var wait: String? = nil
    /// К-DG: жива ли сессия tmux `rick-<проект>`; nil (поля нет) — терминалы не спрашивали.
    var terminal: Bool? = nil
}

/// Ответ `GET /digest`; `at` нет — сводку прочесть не вышло.
struct DigestBody: Codable, Equatable {
    let v: Int
    let at: String?
    let projects: [DigestProject]
}

enum ProjectsDigest {
    static let version = 1
    /// «идут» — только при сводке свежее суток (как `DIGEST_STALE_S` у `pimp.py digest`).
    static let staleSeconds: TimeInterval = 24 * 3600
    static let aboutLimit = 60
    static let groups = ["идут", "ждут", "тихо"]

    static func state(_ state: PanelWorkflow.State) -> String {
        switch state {
        case .running: return "идёт"
        case .done: return "готово"
        case .failed: return "упал"
        case .waiting: return "ждёт"
        // WF145: ⬜ «запланирован» — не «ждёт Элвиса».
        case .planned: return "впереди"
        }
    }

    static func clip(_ text: String) -> String {
        text.count > aboutLimit ? String(text.prefix(aboutLimit - 1)) + "…" : text
    }

    /// Цвет проекта: акцент темы из вида проекта, а его нет (или не `#rrggbb`) — акцент авто-цвета по имени папки.
    static func color(folderName: String, settings: ProjectSettings?) -> String {
        if case .set(let theme)? = settings?.theme, let accent = theme.palette["accent"]?.lowercased(),
           accent.range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil {
            return accent
        }
        return AutoPaint.projectTheme(folderName: folderName).palette["accent"] ?? "#9b9ba1"
    }

    /// Проект из разобранной сводки.
    static func project(folderName: String, status: PanelStatus, updated: Date?, now: Date,
                        settings: ProjectSettings?, changed: Date? = nil, terminal: Bool? = nil) -> DigestProject {
        let flows = status.workflows
        let fresh = updated.map { now.timeIntervalSince($0) <= staleSeconds } ?? false
        let waits = (!status.waitFor.isEmpty && !PanelProjects.isNothing(status.waitFor))
            || flows.contains { $0.state == .waiting }
        let group = fresh && flows.contains { $0.state == .running } ? "идут" : (waits ? "ждут" : "тихо")
        let cells = flows.enumerated().map { index, flow -> DigestWorkflow in
            let current = flow.phases.first { $0.state == .current || $0.state == .failed }
            let steps = flow.stepsDone.flatMap { done in flow.stepsTotal.map { "\(done)/\($0)" } } ?? ""
            return DigestWorkflow(n: index + 1, state: state(flow.state), about: clip(flow.about),
                                  steps: steps, phase: current?.name ?? "",
                                  when: flow.time.isEmpty ? nil : flow.time, role: current.flatMap(role))
        }
        let wait = status.waitFor.isEmpty || PanelProjects.isNothing(status.waitFor) ? nil : status.waitFor
        return DigestProject(name: folderName, title: status.name.isEmpty ? folderName : status.name,
                             marker: status.marker, color: color(folderName: folderName, settings: settings),
                             group: group, done: flows.filter { $0.state == .done }.count, total: flows.count,
                             workflows: cells, at: (changed ?? updated).map { ISO8601DateFormatter().string(from: $0) } ?? "",
                             now: status.now.isEmpty ? nil : status.now, wait: wait, terminal: terminal)
    }

    /// Роль фазы словами сводки: имя и «сколько агентов» из её строки (`help`), без модели и эффорта.
    static func role(_ phase: PanelPhase) -> String? {
        let role = PanelProjects.Role(phase.help)
        let text = [role.name, role.agents].filter { !$0.isEmpty }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    /// Свежее из mtime сводки и run-файлов (`run-*.json`) в её папке (WF141).
    static func changed(status file: URL, updated: Date?, fileManager: FileManager) -> Date? {
        let folder = file.deletingLastPathComponent()
        let runs = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("run-") && $0.hasSuffix(".json") }
            .compactMap { (try? fileManager.attributesOfItem(atPath: folder.appendingPathComponent($0).path))?[.modificationDate] as? Date }
        return ([updated].compactMap { $0 } + runs).max()
    }

    /// Обход `root`: папки со сводкой, без скрытых и рабочих деревьев; порядок — идут → ждут → тихо, внутри свежие
    /// (`at`) наверх, при равенстве по имени (WF141: «новые — наверх»).
    /// Папку прочесть не вышло — nil. `terminals` (К-DG) — имена живых сессий `rick-<проект>`: проект с живым
    /// терминалом попадает в ответ и без сводки (без Workflow); nil — терминалы не спрашивали, поля `terminal` нет.
    static func projects(root: URL, now: Date, settings: (URL) -> ProjectSettings?,
                         fileManager: FileManager = .default, terminals: Set<String>? = nil) -> [DigestProject]? {
        let sessions = terminals.map { Set($0.map { $0.lowercased() }) }
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return nil }
        var out: [DigestProject] = []
        for name in names where !name.hasPrefix(".") {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  !PanelProjects.isWorkingCopy(folder, fileManager: fileManager) else { continue }
            let file = PanelProjects.statusFile(in: folder, fileManager: fileManager)
            let text = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            let status = PanelProjects.parse(text ?? "")
            // Сессия зовётся по папке или по имени сводки — как `PanelTiles.hasTerminal`.
            let terminal = sessions.map { $0.contains(name.lowercased())
                || (!status.name.isEmpty && $0.contains(status.name.lowercased())) }
            guard let file = file, text != nil else {
                if terminal == true {
                    out.append(project(folderName: name, status: status, updated: nil, now: now,
                                       settings: settings(folder), terminal: true))
                }
                continue
            }
            let updated = (try? fileManager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
            out.append(project(folderName: name, status: status, updated: updated, now: now,
                               settings: settings(folder),
                               changed: changed(status: file, updated: updated, fileManager: fileManager),
                               terminal: terminal))
        }
        return out.sorted {
            let left = groups.firstIndex(of: $0.group) ?? 0, right = groups.firstIndex(of: $1.group) ?? 0
            if left != right { return left < right }
            // ISO 8601 в UTC одной длины — строки сравниваются как время; пустое — в конец.
            if $0.at != $1.at { return $0.at > $1.at }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    static func body(_ projects: [DigestProject]?, now: Date) -> DigestBody {
        guard let projects = projects else { return DigestBody(v: version, at: nil, projects: []) }
        let format = ISO8601DateFormatter()
        return DigestBody(v: version, at: format.string(from: now), projects: projects)
    }

    static func json(_ body: DigestBody) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(body)) ?? Data("{\"projects\":[],\"v\":1}".utf8)
    }

    /// Живой ответ: корень из claude.json, вид проекта — `ProjectSettingsStore` (своя на сборку: стор не потокобезопасен).
    static func live(now: Date = Date()) -> Data {
        let store = ProjectSettingsStore()
        return json(body(projects(root: StatusFeed.projectsRoot(), now: now, settings: { store.settings(in: $0) },
                                  terminals: PanelTiles.liveTerminals()),
                         now: now))
    }
}

/// Ответ `/digest` не чаще раза в 10 с: сборка — на своей очереди (диск не на главной и не на очереди порта),
/// запросы, пришедшие во время сборки, ждут её же.
final class ProjectsDigestCache {
    static let interval: TimeInterval = 10

    var now: () -> Date = Date.init
    var build: () -> Data = { ProjectsDigest.live() }

    private let lock = NSLock()
    private var body: Data?
    private var builtAt: Date?
    private var building = false
    private var waiters: [(Data) -> Void] = []
    private let queue = DispatchQueue(label: "pimpmyclaude.digest", qos: .utility)

    /// Ответ — на очереди сборки или сразу, если кэш свежий.
    func get(_ done: @escaping (Data) -> Void) {
        lock.lock()
        if let body = body, let at = builtAt, now().timeIntervalSince(at) < Self.interval, now() >= at {
            lock.unlock()
            return done(body)
        }
        waiters.append(done)
        guard !building else { return lock.unlock() }
        building = true
        lock.unlock()
        queue.async { [self] in
            let data = build()
            lock.lock()
            body = data
            builtAt = now()
            building = false
            let ready = waiters
            waiters = []
            lock.unlock()
            ready.forEach { $0(data) }
        }
    }

    /// Дождаться идущей сборки — тестам.
    func drain() { queue.sync {} }
}
