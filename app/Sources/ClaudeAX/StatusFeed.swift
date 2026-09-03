import CryptoKit
import Foundation

/// Сводка одного проекта: имя папки и сырой markdown его status.md.
struct StatusProject: Equatable {
    let name: String
    let text: String
}

/// Сводки проектов для подсказки полоски прогресса (решение 2 плана WF9). Страница файлов
/// не читает — приложение раз в 60 с (и при показе меню) обходит
/// `<projectsRoot>/*/{docs,audit,work}/status.md` и, когда содержимое изменилось, пишет команду
/// `{"id","action":"status","at","scope":"all","projects":[{"name","text"}]}`.
///
/// Сводка — единственная команда, которую пишет не Элвис, поэтому она обязана уступать дорогу
/// меню: лоадер опрашивает command.json раз в 500 мс и берёт последнюю команду.
final class StatusFeed {
    /// Опрос файлов.
    static let interval: TimeInterval = 60
    /// Тишина после любой другой команды, пока сводку слать нельзя.
    static let quietSeconds: TimeInterval = 2
    /// Не больше 6 КБ сырого markdown на проект.
    static let limit = 6 * 1024
    static let configFileName = "claude.json"
    static let configKey = "projectsRoot"
    static let defaultProjectsRoot = "~/_ElvisProjects"
    static let statusFileName = "status.md"
    /// Где у проекта может лежать сводка — в этом порядке (первая найденная и идёт в команду).
    static let statusFolders = ["docs", "audit", "work"]

    private let commands: CommandChannel
    private var timer: Timer?
    /// Хэш последней посланной сводки: без изменений содержимого команда не повторяется.
    private var sentDigest: String?
    private var sentAt: Date?
    private var scanning = false
    private var retry: DispatchWorkItem?

    private(set) var sentCount = 0
    private(set) var projectCount = 0

    init(commands: CommandChannel) { self.commands = commands }

    /// Таймер в `.common`: пока открыто меню на кнопке «Свернуть», runloop сидит в режиме
    /// отслеживания и `.default` не тикал бы.
    func start() {
        stop()
        let timer = Timer(timeInterval: StatusFeed.interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        retry?.cancel()
        retry = nil
    }

    var isRunning: Bool { timer != nil }

    /// Прочитать сводки и, если изменились, послать. Зовётся таймером и показом меню.
    func refresh() {
        guard !scanning else { return }
        let root = StatusFeed.projectsRoot()
        // Папки проектов нет — ничего не шлём (у Маши, Аллы и Дениса её и не будет).
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let projects = StatusFeed.scan(root: root)
            DispatchQueue.main.async { self?.publish(projects) }
        }
    }

    private func publish(_ projects: [StatusProject]) {
        scanning = false
        projectCount = projects.count
        guard !projects.isEmpty else { return }
        let digest = StatusFeed.digest(projects)
        guard digest != sentDigest else { return }
        // Команду меню сводка перебивать не имеет права — ждём, пока пройдут две секунды.
        let quiet = StatusFeed.quietSeconds - commands.secondsSinceOtherCommand
        if quiet > 0 { return schedule(after: quiet) }
        let at = Date()
        guard commands.write(action: CommandChannel.statusAction,
                             fields: StatusFeed.fields(projects)) else { return }
        sentDigest = digest
        sentAt = at
        sentCount += 1
        // Обратный случай: команда меню, посланная сразу после сводки, затрёт её в файле
        // раньше, чем лоадер успеет прочитать. Проверяем через ту же паузу и шлём заново.
        schedule(after: StatusFeed.quietSeconds)
    }

    private func schedule(after delay: TimeInterval) {
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recheck() }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Сводку затёрли — забываем хэш и шлём её ещё раз.
    private func recheck() {
        retry = nil
        if let sentAt = sentAt, let other = commands.lastOtherCommandAt, other > sentAt {
            sentDigest = nil
        }
        refresh()
    }

    // MARK: - чистая часть (её же гоняют тесты)

    /// `projectsRoot` из claude.json; ключа нет — `~/_ElvisProjects`.
    static func projectsRoot(configURL: URL = CommandChannel.directory
        .appendingPathComponent(configFileName)) -> URL {
        let data = try? Data(contentsOf: configURL)
        let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let raw = (json?[configKey] as? String)?.trimmingCharacters(in: .whitespaces)
        let path = (raw?.isEmpty == false ? raw! : defaultProjectsRoot)
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    /// Проекты по алфавиту; у проекта берётся первая найденная сводка из docs/audit/work.
    static func scan(root: URL, fileManager: FileManager = .default) -> [StatusProject] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        var projects: [StatusProject] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let project = root.appendingPathComponent(name, isDirectory: true)
            let candidates = statusFolders.map {
                project.appendingPathComponent($0, isDirectory: true)
                    .appendingPathComponent(statusFileName)
            }
            guard let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            projects.append(StatusProject(name: name, text: slice(text)))
        }
        return projects
    }

    /// Поля команды после id, action, at: scope, projects (контракт п. 2 плана WF9).
    static func fields(_ projects: [StatusProject]) -> [(key: String, value: CommandValue)] {
        let items = projects.map { project in
            CommandValue.object([
                (key: "name", value: .string(project.name)),
                (key: "text", value: .string(project.text)),
            ])
        }
        return [(key: "scope", value: .string(MenuModel.themeScopeAll)),
                (key: "projects", value: .array(items))]
    }

    static func digest(_ projects: [StatusProject]) -> String {
        var hasher = SHA256()
        for project in projects {
            hasher.update(data: Data(project.name.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(project.text.utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Срез до 6 КБ по границе блоков «N️⃣ Workflow»: половинчатый блок в подсказке ни к чему.
    /// Ни один блок целиком не влез — режем по знакам, чтобы не порвать UTF-8.
    static func slice(_ text: String, limit: Int = limit) -> String {
        guard text.utf8.count > limit else { return text }
        let lines = text.components(separatedBy: "\n")
        var bytes = 0
        var cut = 0 // сколько строк точно влезает: граница перед последним уместившимся блоком
        for (index, line) in lines.enumerated() {
            let size = line.utf8.count + (index > 0 ? 1 : 0)
            if bytes + size > limit { break }
            if index > 0, isWorkflowHeading(line) { cut = index }
            bytes += size
        }
        guard cut > 0 else { return prefix(text, bytes: limit) }
        return lines[0..<cut].joined(separator: "\n")
    }

    /// Начало блока: строка вроде «3️⃣ Workflow ✅ готово» — цифра-клавиша (или 🔟) с начала.
    static func isWorkflowHeading(_ line: String) -> Bool {
        var scalars = Array(line.trimmingCharacters(in: .whitespaces).unicodeScalars.prefix(2))
        guard let first = scalars.first else { return false }
        if first == "\u{1F51F}" { return true } // 🔟
        guard first.value >= 0x30, first.value <= 0x39, scalars.count > 1 else { return false }
        scalars.removeFirst()
        return scalars[0] == "\u{FE0F}" || scalars[0] == "\u{20E3}"
    }

    /// Обрезка по знакам, не по байтам: разрезанный посередине символ уехал бы в команду мусором.
    static func prefix(_ text: String, bytes limit: Int) -> String {
        var out = ""
        var count = 0
        for character in text {
            let size = String(character).utf8.count
            if count + size > limit { break }
            out.append(character)
            count += size
        }
        return out
    }
}
