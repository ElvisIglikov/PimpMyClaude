import Foundation

// Панель PMP, WF129 (#9043, #9077): «Идут Workflow» плиткой по проектам, блоки-виджеты и сводка всех проектов
// для значка у часов. Чистая часть — группы плиток, раскладка виджетов, строка сводки, разбор `tmux ls`;
// вид — `Panel/*.swift`, тесты — `PanelTilesWF129Tests`.

/// Плитка проекта в «Идут Workflow».
public struct PanelTile: Equatable, Identifiable {
    public enum Group: Equatable { case running, waiting, doneToday }

    public var id: String { folder }
    public let folder: String
    public let name: String
    public let marker: String
    /// Строка марафона из шапки сводки; нет — пусто.
    public let marathon: String
    /// «Workflow 1, 2 из 3» (идут) / «готово 3 из 3»; Workflow нет — пусто.
    public let count: String
    /// О чём идущий (ждущий, последний готовый) Workflow.
    public let about: String
    /// «кодинг · шаг 1 из 3» / «ждёт Элвиса» / «готово · 1 ч» / «чат в терминале».
    public let phase: String
    /// Состояния всех Workflow по порядку — тонкая полоска.
    public let segments: [PanelWorkflow.State]
    /// Живой чат в терминале (tmux `rick-<проект>`).
    public let terminal: Bool
    /// Идёт и при этом ждёт Элвиса (строка «Ждёт Элвиса» или блок ✋).
    public let waits: Bool
    /// Идущий упал — фаза красным.
    public let failed: Bool
    /// Подсказка: «сейчас» сводки и что ждёт.
    public let help: String
}

public struct PanelTileGroup: Equatable, Identifiable {
    public var id: String { title }
    public let group: PanelTile.Group
    public let title: String
    public let tiles: [PanelTile]
}

public enum PanelTiles {
    public static let numbersLimit = 3

    /// Группы сверху вниз: «Идут», «Ждут Элвиса», «Готово сегодня»; пустых нет. Проект — в одной группе:
    /// идёт — «Идут» (даже если и ждёт), только ждёт — «Ждут Элвиса», всё готово и сводка сегодняшняя —
    /// «Готово сегодня». Живой чат в терминале без своей группы — тоже «Идут». Внутри группы свежие (сводка правлена
    /// позже) — наверх (WF141, Рик: «в ячейках и списках новые — наверх»).
    public static func groups(_ snapshot: PanelSnapshot, now: Date, calendar: Calendar = .current) -> [PanelTileGroup] {
        var seen = Set<String>()
        var running: [PanelTile] = [], waiting: [PanelTile] = [], done: [PanelTile] = []
        let all = snapshot.working + snapshot.waiting + snapshot.others
        let order = all.indices.sorted { left, right in
            let a = all[left].updated ?? .distantPast, b = all[right].updated ?? .distantPast
            return a != b ? a > b : left < right
        }
        let named = all.map {
            (key: $0.folder, folder: URL(fileURLWithPath: $0.folder).lastPathComponent, name: $0.name, updated: $0.updated)
        }
        let owners = terminalOwners(named, sessions: snapshot.terminals)
        // «Чат в терминале» без идущего Workflow — в «Идут» только с движением за 45 мин (#10315): забытая сессия tmux
        // живёт сутками, а «⏳» у значка — только живое.
        let busy = snapshot.activeTerminals.map { terminalOwners(named, sessions: $0) } ?? owners
        for project in order.map({ all[$0] }) where !seen.contains(project.folder) {
            seen.insert(project.folder)
            let terminal = owners.contains(project.folder)
            if !project.running.isEmpty {
                running.append(tile(project, .running, terminal: terminal))
            } else if project.waits {
                waiting.append(tile(project, .waiting, terminal: terminal))
            } else if let updated = project.updated, calendar.isDate(updated, inSameDayAs: now),
                      !project.workflows.isEmpty, project.workflows.allSatisfy({ $0.state == .done }) {
                done.append(tile(project, .doneToday, terminal: terminal))
            } else if terminal, busy.contains(project.folder) {
                running.append(tile(project, .running, terminal: true))
            }
        }
        return [(PanelTile.Group.running, "Идут", running), (.waiting, "Ждут Элвиса", waiting),
                (.doneToday, "Готово сегодня", done)]
            .filter { !$0.2.isEmpty }
            .map { PanelTileGroup(group: $0.0, title: $0.1, tiles: $0.2) }
    }

    /// Чьи сессии `rick-<имя>` (без учёта регистра): одна сессия — одна строка (#9846: сайт показался дважды — сессию
    /// получили и папка `VkusnoffKz`, и вторая папка со сводкой того же имени). Держит её папка с тем же именем; такой
    /// нет — самая свежая сводка с этим именем (при равенстве — первая по порядку). Ответ — `key` владельцев.
    public static func terminalOwners(_ candidates: [(key: String, folder: String, name: String, updated: Date?)],
                                      sessions: Set<String>) -> Set<String> {
        var owners = Set<String>()
        for session in Set(sessions.map { $0.lowercased() }) {
            if let byFolder = candidates.first(where: { $0.folder.lowercased() == session }) {
                owners.insert(byFolder.key)
                continue
            }
            let byName = candidates.enumerated().filter { !$0.element.name.isEmpty && $0.element.name.lowercased() == session }
            let freshest = byName.min { left, right in
                let a = left.element.updated ?? .distantPast, b = right.element.updated ?? .distantPast
                return a != b ? a > b : left.offset < right.offset
            }
            if let owner = freshest { owners.insert(owner.element.key) }
        }
        return owners
    }

    static func tile(_ project: PanelProject, _ group: PanelTile.Group, terminal: Bool) -> PanelTile {
        // Плитка одного терминала (ничего живого в сводке, #10315) — без Workflow: старое «идёт» сводки не выдаётся за
        // идущее ни в подсказке, ни в «WF N/M» значка.
        let all = group == .running && project.running.isEmpty ? [] : project.workflows
        let live: [Int] = group == .doneToday ? [] : all.indices.filter {
            [.running, .waiting, .failed].contains(all[$0].state)
        }
        let doneCount = all.filter { $0.state == .done }.count
        var count = ""
        if !live.isEmpty {
            var numbers = live.prefix(numbersLimit).map { String($0 + 1) }.joined(separator: ", ")
            if live.count > numbersLimit { numbers += "…" }
            count = "Workflow \(numbers) из \(all.count)"
        } else if !all.isEmpty {
            count = "готово \(doneCount) из \(all.count)"
        }
        let current = project.running.first ?? live.first.map { all[$0] }
        let failed = current?.state == .failed
        let about: String
        let phase: String
        switch group {
        case .running:
            guard let workflow = current else {
                about = project.now
                phase = "чат в терминале"
                break
            }
            about = workflow.about
            let name = workflow.phases.first { $0.state == .current || $0.state == .failed }?.name ?? ""
            let steps = workflow.stepsDone.flatMap { done in workflow.stepsTotal.map { "шаг \(done) из \($0)" } }
            phase = failed ? ([name, "упал"].filter { !$0.isEmpty }.joined(separator: " · "))
                : [name, steps ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        case .waiting:
            about = current?.about ?? (project.note.isEmpty ? project.words.joined(separator: " · ") : project.note)
            phase = "ждёт Элвиса"
        case .doneToday:
            let last = all.last { $0.state == .done }
            about = last?.about ?? ""
            phase = last.map { $0.duration.isEmpty ? "готово" : "готово · \($0.duration)" } ?? "готово"
        }
        let waitsToo = group == .running && project.waits
        // Что идёт — в подсказке (31.1): «10 · о чём · 1/3», номера вразбивку в квадрат не влезают.
        var lines = live.map { index -> String in
            let workflow = all[index]
            let steps = workflow.stepsDone.flatMap { done in workflow.stepsTotal.map { "\(done)/\($0)" } }
            let mark = workflow.state == .failed ? "упал" : workflow.state == .waiting ? "ждёт" : steps
            return ["\(index + 1)", workflow.about, mark ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        lines.append(project.now)
        let what = project.note.isEmpty ? project.words.map { "«\($0)»" }.joined(separator: "; ") : project.note
        if waitsToo || group == .waiting, !what.isEmpty { lines.append("Ждёт Элвиса: " + what) }
        let help = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        return PanelTile(folder: project.folder, name: project.name, marker: project.marker,
                         marathon: project.marathon, count: count, about: about, phase: phase,
                         segments: all.map { $0.state }, terminal: terminal, waits: waitsToo, failed: failed,
                         help: help)
    }

    // MARK: блок Workflow

    /// Имя блока в меню правого клика и в строке «Скрытые»; с #10239 — «Workflow», как шапка блока на Windows.
    public static let nowTitle = "Workflow"
    /// Шапка блока (#10395): период готовых виден сразу — «Workflow · 24 ч».
    public static let dayTitle = "Workflow · 24 ч"

    /// Число в подписи блока: идущие Workflow всех плиток «Идут».
    public static func runningCount(_ groups: [PanelTileGroup]) -> Int {
        (groups.first { $0.group == .running }?.tiles ?? []).reduce(0) { $0 + $1.segments.filter { $0 == .running }.count }
    }

    /// «идёт» / «идут» по числу: 1, 21 — «идёт».
    public static func goes(_ count: Int) -> String { Plural.ru(count, "идёт", "идут", "идут") }

    // MARK: сводка у часов (#9077)

    /// «⏳ 3 · ✋ 1 · WF 4/11»: идут, ждут, готово из всех Workflow идущих и ждущих проектов; ничего не идёт —
    /// «✅ 2» (готово сегодня) или «—».
    public static func summary(_ groups: [PanelTileGroup]) -> String {
        let running = groups.first { $0.group == .running }?.tiles ?? []
        let waiting = groups.first { $0.group == .waiting }?.tiles ?? []
        let done = groups.first { $0.group == .doneToday }?.tiles ?? []
        let active = running + waiting
        let total = active.reduce(0) { $0 + $1.segments.count }
        let finished = active.reduce(0) { $0 + $1.segments.filter { $0 == .done }.count }
        var parts: [String] = []
        if !running.isEmpty { parts.append("⏳ \(running.count)") }
        if !waiting.isEmpty { parts.append("✋ \(waiting.count)") }
        if total > 0 { parts.append("WF \(finished)/\(total)") }
        if parts.isEmpty { return done.isEmpty ? "—" : "✅ \(done.count)" }
        return parts.joined(separator: " · ")
    }

    /// Подсказка значка: по строке на группу — «Идут: PimpMyClaude — Workflow 1, 2 из 3 · кодинг; …».
    public static func summaryHelp(_ groups: [PanelTileGroup]) -> String {
        guard !groups.isEmpty else { return "PMP — Workflow сейчас не идут" }
        return (["PMP — проекты"] + groups.map { group in
            group.title + ": " + group.tiles.map { tile in
                tile.name + ([tile.count, tile.phase].filter { !$0.isEmpty }.isEmpty ? ""
                    : " — " + [tile.count, tile.phase].filter { !$0.isEmpty }.joined(separator: " · "))
            }.joined(separator: "; ")
        }).joined(separator: "\n")
    }

    // MARK: терминальные чаты

    /// Имена проектов из `tmux ls -F '#{session_name}'` (или обычного `tmux ls`): сессии `rick-<проект>`.
    public static func terminals(_ output: String) -> Set<String> {
        var names = Set<String>()
        for line in output.components(separatedBy: "\n") {
            let session = line.split(separator: ":", maxSplits: 1).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard session.hasPrefix("rick-"), session.count > 5 else { continue }
            names.insert(String(session.dropFirst(5)))
        }
        return names
    }

    /// Где искать tmux: у приложения из Finder в PATH нет Homebrew.
    static let tmuxPaths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    /// Живые сессии `rick-…` (в фоне, не дольше 2 с). tmux нет, сервер не запущен — пусто.
    public static func liveTerminals(fileManager: FileManager = .default) -> Set<String> {
        guard let tmux = tmuxPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = ["ls", "-F", "#{session_name}"]
        process.environment = FlowShell.environment() // #11620: без UTF-8 локали tmux портит не-ASCII имена
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationStatus == 0 else { return [] }
        return terminals(String(decoding: data, as: UTF8.self))
    }
}
