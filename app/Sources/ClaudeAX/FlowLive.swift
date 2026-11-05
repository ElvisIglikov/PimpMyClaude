import CryptoKit
import Foundation
import Patcher

// Блок Workflow — только живое (#10315, слово Элвиса 19.10.2026 12:25 и 14:30: «пишется, что какие-то Workflow идут, —
// это актуально или устаревшее? Нужно выводить только актуальное»). Свежесть сводки — по времени, когда изменилось её
// СОДЕРЖИМОЕ (`FlowSeen`, память по хэшу текста), а не по mtime: `git worktree add`, checkout и pull ставят свежий
// mtime старому тексту. «Идёт сейчас» — одна функция `PanelProjects.isLive`; её признаки — свежее содержимое,
// терминал с движением, работающая страница или строка состояния «идёт». Контракт — `docs/contracts/510-10315-flow-live.md`,
// решения — `docs/decisions/2026-10-19-workflow-zhivoe-10315.md`, тесты — `FlowLive10315Tests`.

/// Память «когда содержимое сводки стало таким»: хэш текста → время. Один и тот же текст в любом дереве git — одно
/// время, поэтому новое дерево со старой сводкой старым и остаётся. Файл `flow-seen.json` в папке MyClaude переживает
/// перезапуск; лоадер его не читает. Ходят к памяти снимок панели и `/digest` со своих очередей — всё под замком.
public final class FlowSeen {
    public static let fileName = "flow-seen.json"
    public static let shared = FlowSeen(file: SupportFiles.directory.appendingPathComponent(fileName))
    /// Запись, которую не видели столько, — долой.
    static let keepSeconds: TimeInterval = 30 * 86_400
    /// Потолок записей: сверх — уходят давно не виденные.
    static let limit = 4000
    /// Без нового текста файл перезаписывается не чаще — ради свежести `seen` у живых записей.
    static let refreshSeconds: TimeInterval = 86_400

    struct Entry: Codable, Equatable {
        /// Когда содержимое стало таким, секунды с 1970.
        var changed: Double
        /// Когда его видели в последний раз.
        var seen: Double
    }

    struct Body: Codable {
        var version: Int
        var entries: [String: Entry]
    }

    private let lock = NSLock()
    private let file: URL?
    private let origin: (URL) -> Date?
    private var entries: [String: Entry]?
    private var dirty = false
    private var writtenAt: Date?

    /// `file` nil — память только в процессе. `origin` — время текста, которого память ещё не видела (живьём — git:
    /// время коммита, если файл не правлен после него).
    public init(file: URL?, origin: @escaping (URL) -> Date? = { FlowSeen.gitTime($0) }) {
        self.file = file
        self.origin = origin
    }

    static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Когда содержимое `text` (файл `url` с временем правки `mtime`) стало таким. Видели — время из памяти;
    /// нет — самое раннее из времени коммита (git, файл не правлен после него), mtime и `now`.
    public func changed(text: String, url: URL, mtime: Date?, now: Date) -> Date {
        let key = Self.key(text)
        lock.lock()
        load()
        if var entry = entries?[key] {
            entry.seen = max(entry.seen, now.timeIntervalSince1970)
            entries?[key] = entry
            lock.unlock()
            return Date(timeIntervalSince1970: entry.changed)
        }
        lock.unlock()
        // git — вне замка: до 2 с на вызов, а к памяти в это время ходит вторая очередь.
        let fallback = min(now, mtime ?? now)
        let first = origin(url).map { min($0, fallback) } ?? fallback
        lock.lock()
        defer { lock.unlock() }
        if let known = entries?[key] { return Date(timeIntervalSince1970: known.changed) }
        entries?[key] = Entry(changed: first.timeIntervalSince1970, seen: now.timeIntervalSince1970)
        dirty = true
        return first
    }

    /// Записать память: появился новый текст — сразу, иначе не чаще раза в сутки; старое и сверх потолка — долой.
    public func flush(now: Date) {
        lock.lock()
        defer { lock.unlock() }
        guard let file = file, let all = entries else { return }
        let due = writtenAt.map { now.timeIntervalSince($0) >= Self.refreshSeconds } ?? true
        guard dirty || due else { return }
        let kept = Self.pruned(all, now: now)
        entries = kept
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Body(version: 1, entries: kept)),
              SupportFiles.writeAtomic(file, data) else { return }
        dirty = false
        writtenAt = now
    }

    /// Без записей, не виденных `keepSeconds`; сверх `limit` — остаются самые недавно виденные.
    static func pruned(_ entries: [String: Entry], now: Date) -> [String: Entry] {
        let edge = now.timeIntervalSince1970 - keepSeconds
        var kept = entries.filter { $0.value.seen >= edge }
        if kept.count > limit {
            let order = kept.sorted { $0.value.seen != $1.value.seen ? $0.value.seen > $1.value.seen : $0.key < $1.key }
            kept = Dictionary(uniqueKeysWithValues: order.prefix(limit).map { ($0.key, $0.value) })
        }
        return kept
    }

    /// Память из файла — один раз; файла нет или он битый — пустая.
    private func load() {
        guard entries == nil else { return }
        guard let file = file, let data = try? Data(contentsOf: file),
              let body = try? JSONDecoder().decode(Body.self, from: data) else {
            entries = [:]
            return
        }
        entries = body.entries.filter { $0.value.changed.isFinite && $0.value.seen.isFinite }
    }

    // MARK: git

    /// Где искать git: без Command Line Tools `/usr/bin/git` — заглушка, которая зовёт окно установки.
    static let gitPaths = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git",
                           "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]

    /// Время последнего коммита файла, если в рабочей копии он такой же, как в HEAD; не git, файл правлен или не в
    /// git — nil.
    public static func gitTime(_ file: URL, fileManager: FileManager = .default) -> Date? {
        guard let git = gitPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) else { return nil }
        let folder = file.deletingLastPathComponent().path
        let name = file.lastPathComponent
        guard FlowShell.run(git, ["-C", folder, "diff", "--quiet", "HEAD", "--", name])?.status == 0,
              let log = FlowShell.run(git, ["-C", folder, "log", "-1", "--format=%ct", "--", name]), log.status == 0,
              let seconds = Double(log.text.trimmingCharacters(in: .whitespacesAndNewlines)), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

/// Запуск git и tmux в фоне — не дольше `timeout`, ответ — код выхода и вывод.
enum FlowShell {
    /// Окружение с UTF-8 локалью (#11620). Пимп из launchd — без LANG, а tmux 3.7 без UTF-8 локали меняет в выводе
    /// табуляцию и не-ASCII на «_»: `ls -F '#{session_name}\t…'` приходил «pimp-hub_1793763434», и сторож терминалов
    /// не видел ни hub, ни чатов — новые окна не связывались, старые не уходили. Локаль своя у человека — не трогаем.
    static func environment(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let locale = [base["LC_ALL"], base["LC_CTYPE"], base["LANG"]].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        guard !locale.lowercased().replacingOccurrences(of: "-", with: "").contains("utf8") else { return base }
        var out = base
        out[(base["LC_ALL"] ?? "").isEmpty ? "LC_CTYPE" : "LC_ALL"] = "en_US.UTF-8"
        return out
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 2) -> (status: Int32, text: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

// MARK: страницы

/// Страница Claude, по которой проект может быть живым: работает (видна кнопка «стоп») или строка состояния её
/// последнего ответа говорит «идёт» (`chats().flow`, #10315).
public struct FlowPage: Equatable {
    /// Папка проекта чата (корень, как у покраски), стандартный путь; не знаем — nil.
    public var folder: String?
    /// Проект из строки состояния («⚪[PimpMyClaude](docs/status.md) · …» — «PimpMyClaude»); нет — пусто.
    public var project: String
    public var working: Bool
    public var running: Bool

    public init(folder: String? = nil, project: String = "", working: Bool = false, running: Bool = false) {
        self.folder = folder
        self.project = project
        self.working = working
        self.running = running
    }
}

/// Живые страницы — от тика контроллера (главная нить) к сборкам панели и `/digest` (свои очереди).
public final class FlowPagesBox {
    public static let shared = FlowPagesBox()
    private let lock = NSLock()
    private var stored: [FlowPage] = []
    private var at: Date?

    public init() {}

    public func set(_ pages: [FlowPage], at: Date) {
        lock.lock()
        defer { lock.unlock() }
        stored = pages
        self.at = at
    }

    /// Страницы, записанные не раньше `ChatProbe.workingSeconds` назад; старше — пусто (страницы молчат — не знаем).
    public func pages(now: Date) -> [FlowPage] {
        lock.lock()
        defer { lock.unlock() }
        guard let at = at, abs(now.timeIntervalSince(at)) < ChatProbe.workingSeconds else { return [] }
        return stored
    }
}

// MARK: правило «идёт сейчас»

extension PanelProjects {
    /// Содержимое сводки менялось не раньше — проект живой и без других признаков.
    public static let liveSeconds: TimeInterval = 45 * 60

    /// Идёт ли Workflow проекта сейчас (#10315): содержимое сводки менялось за 45 мин, или за 12 ч
    /// (`runFreshSeconds`) — и при этом в его терминале было движение за 45 мин, или его страница работает либо
    /// говорит «идёт». Без 12 ч старый открытый чат или забытая сессия tmux оживляли бы сводку недельной давности.
    public static func isLive(changedAge: TimeInterval, terminal: Bool, page: Bool) -> Bool {
        changedAge <= liveSeconds || (changedAge <= runFreshSeconds && (terminal || page))
    }

    /// Сводка папки, прочитанная для живого правила.
    public struct StatusRead {
        public let url: URL
        public let text: String
        public let mtime: Date?
        /// Когда содержимое стало таким (`FlowSeen`); без памяти — mtime.
        public let changed: Date?
        /// Папка и её рабочие деревья — стандартные пути: по ним страница находит свой проект.
        public let trees: [String]
    }

    /// Сводка папки и её рабочих деревьев git с самым свежим изменением СОДЕРЖИМОГО (#10315; до него — самая свежая по
    /// mtime, `statusFile`); при равенстве — по mtime, дальше — главная папка. Без памяти (`seen` nil) время
    /// содержимого — mtime. Сводки нет или не читается — nil.
    public static func readStatus(in folder: URL, fileManager: FileManager = .default, seen: FlowSeen?,
                                  now: Date) -> StatusRead? {
        let trees = [folder] + worktrees(of: folder, fileManager: fileManager)
        let paths = trees.map { $0.standardizedFileURL.path }
        var best: StatusRead?
        for tree in trees {
            guard let url = ownStatusFile(in: tree, fileManager: fileManager),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let mtime = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            let changed = seen.map { $0.changed(text: text, url: url, mtime: mtime, now: now) } ?? mtime
            let read = StatusRead(url: url, text: text, mtime: mtime, changed: changed, trees: paths)
            if let current = best, !fresher(read, than: current) { continue }
            best = read
        }
        return best
    }

    static func fresher(_ read: StatusRead, than other: StatusRead) -> Bool {
        let a = read.changed ?? .distantPast, b = other.changed ?? .distantPast
        if a != b { return a > b }
        return (read.mtime ?? .distantPast) > (other.mtime ?? .distantPast)
    }

    /// Проект-кандидат живого правила: ключ, имя папки, имя сводки, время содержимого и папки-деревья.
    public typealias LiveCandidate = (key: String, folder: String, name: String, updated: Date?, trees: [String])

    /// Чьи страницы живые (#10315). Есть проект в строке состояния — по нему (имя папки или имя сводки, как у сессий
    /// терминалов: чат Рика, что ведёт Workflow PMP, оживляет PMP, а не Rick); нет или такого проекта нет — по папке
    /// чата (сама папка проекта или её рабочее дерево). Ответ — `key` проектов.
    public static func pageOwners(_ pages: [FlowPage], candidates: [LiveCandidate]) -> Set<String> {
        let named = candidates.map { (key: $0.key, folder: $0.folder, name: $0.name, updated: $0.updated) }
        var owners = Set<String>()
        for page in pages where page.working || page.running {
            if !page.project.isEmpty {
                let byName = PanelTiles.terminalOwners(named, sessions: [page.project])
                if !byName.isEmpty {
                    owners.formUnion(byName)
                    continue
                }
            }
            guard let folder = page.folder else { continue }
            if let hit = candidates.first(where: { $0.trees.contains(folder) }) { owners.insert(hit.key) }
        }
        return owners
    }
}

// MARK: терминалы

extension PanelTiles {
    /// Живые сессии `rick-<проект>` и когда в них было последнее движение (#10315): `tmux ls -F
    /// '#{session_name}\t#{session_activity}'`, в фоне, не дольше 2 с. tmux нет, сервер не запущен — пусто.
    public static func terminalActivity(fileManager: FileManager = .default) -> [String: Date] {
        guard let tmux = tmuxPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }),
              let out = FlowShell.run(tmux, ["ls", "-F", "#{session_name}\t#{session_activity}"]), out.status == 0
        else { return [:] }
        return terminalActivity(out.text)
    }

    /// Разбор вывода: «rick-PimpMyClaude⇥1790000000» → «PimpMyClaude» и время; времени нет — давно (движения не было).
    public static func terminalActivity(_ output: String) -> [String: Date] {
        var out: [String: Date] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            let session = parts[0].trimmingCharacters(in: .whitespaces)
            guard session.hasPrefix("rick-"), session.count > 5 else { continue }
            let seconds = parts.count > 1 ? Double(parts[1].trimmingCharacters(in: .whitespaces)) : nil
            let at = seconds.map { Date(timeIntervalSince1970: $0) } ?? .distantPast
            let name = String(session.dropFirst(5))
            out[name] = max(out[name] ?? .distantPast, at)
        }
        return out
    }

    /// Признак хода Claude Code (#10460): пока модель работает, в строке под полем ввода стоит «esc to interrupt»;
    /// стоящий чат (ход кончился, поле пустое или с недописанным) его не показывает. Тот же признак у сторожа
    /// лимита Рика (`Rick/tools/limit_watch.py`, BUSY).
    public static let turnMark = "esc to interrupt"

    /// Сессии `rick-<проект>` из `sessions`, где сейчас идёт ход (#10460): низ экрана каждой — `tmux capture-pane`,
    /// в фоне, не дольше 2 с на сессию. tmux нет — пусто.
    public static func turningTerminals(_ sessions: Set<String>, fileManager: FileManager = .default) -> Set<String> {
        guard !sessions.isEmpty, let tmux = tmuxPaths.first(where: { fileManager.isExecutableFile(atPath: $0) })
        else { return [] }
        return sessions.filter { name in
            guard let out = FlowShell.run(tmux, ["capture-pane", "-p", "-J", "-t", "=rick-\(name):"]), out.status == 0
            else { return false }
            return inTurn(out.text)
        }
    }

    /// Ход виден в последних строках экрана (под полем ввода); пустые строки низа не в счёт.
    public static func inTurn(_ pane: String) -> Bool {
        pane.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(4)
            .contains { $0.contains(turnMark) }
    }

    /// Сессии, где движение было не раньше `PanelProjects.liveSeconds` назад: забытая сессия tmux живёт сутками, но
    /// проект живым не делает.
    public static func activeTerminals(_ activity: [String: Date], now: Date) -> Set<String> {
        Set(activity.filter { now.timeIntervalSince($0.value) <= PanelProjects.liveSeconds }.keys)
    }
}
