import Foundation

/// Свой список недавних проектов — файл `~/Library/Application Support/MyClaude/projects.json`:
/// `{"version":1,"projects":[{"name","folder","lastUsed"}]}` (план WF36, он же WF30 часть 2,
/// задача #5451).
///
/// Зачем он, когда есть индекс чатов Claude: индекс — ЧУЖИЕ файлы
/// (`~/Library/Application Support/Claude/claude-code-sessions/…`), и переустановка Claude
/// стирает их вместе с чатами. После неё «🪟 Новое окно ▸» пустело, и открыть окно в проекте
/// было нечем. Файл рядом с `command.json` переустановку переживает.
///
/// Пополняется сам: на общем тике и на каждый показ меню приложение доливает сюда папки из
/// индекса (`absorb`), а клик по пункту меню и запрос канала «Пимп» отмечают папку свежей
/// (`note`). Папка, пропавшая с диска, из ответов уходит, но из файла НЕ удаляется: диск
/// мог отвалиться, а список — единственная память о проектах.
///
/// Класс не потокобезопасен — живёт на главной очереди, как и всё остальное.
final class ProjectsStore {
    static let fileName = "projects.json"
    /// Больше сотни папок в файле не держим: вытесняется самая старая по `lastUsed`.
    static let limit = 100
    /// Насколько свежее должна быть отметка индекса, чтобы переписать файл: без порога
    /// `lastFocusedAt` дёргался бы на каждом тике, и файл переписывался бы раз в 2 с.
    static let refreshSeconds: TimeInterval = 60
    static let versionKey = "version"
    static let projectsKey = "projects"
    static let version = 1
    /// Рядом с command.json (папку заводит патч, а если её нет — `writeAtomic`).
    static var defaultURL: URL { CommandChannel.directory.appendingPathComponent(fileName) }

    private let url: URL
    private let fileManager: FileManager

    init(url: URL = ProjectsStore.defaultURL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    /// Всё, что записано, свежие первыми. Файл битый — пустой список: меню обязано остаться живым.
    func load() -> [Project] { ProjectsStore.parse(try? Data(contentsOf: url)) }

    /// Список для меню и ответа канала: пропавшие с диска папки не показываем — пункт меню
    /// молча открыл бы чат в несуществующем каталоге (то же правило, что у `ProjectIndex`).
    func recent(limit: Int) -> [Project] {
        guard limit > 0 else { return [] }
        var out: [Project] = []
        for project in load() where ProjectIndex.isDirectory(project.folder, fileManager) {
            out.append(project)
            if out.count == limit { break }
        }
        return out
    }

    /// Папку открыли (клик по пункту меню или запрос `new-window`) — она самая свежая.
    @discardableResult
    func note(_ project: Project, at: Date) -> Bool {
        let fresh = Project(folder: project.folder.standardizedFileURL, name: project.name,
                            lastFocusedAt: ProjectsStore.milliseconds(at))
        return write(ProjectsStore.merge([fresh], into: load(), refresh: 0))
    }

    /// Долить папки из индекса чатов Claude. Пишем, только когда что-то правда изменилось:
    /// новая папка или отметка индекса свежее записанной больше чем на минуту.
    @discardableResult
    func absorb(_ projects: [Project], at: Date) -> Bool {
        let stored = load()
        let merged = ProjectsStore.merge(projects, into: stored,
                                         refresh: ProjectsStore.refreshSeconds)
        guard merged != stored else { return false }
        return write(merged)
    }

    private func write(_ list: [Project]) -> Bool {
        CommandChannel.writeAtomic(url, ProjectsStore.json(list))
    }

    // MARK: - чистая часть (её же гоняют тесты)

    /// Слить свежие записи со старыми: незнакомая папка добавляется, знакомая обновляется,
    /// только если стала свежее на `refresh` секунд (у клика порог нулевой — он и есть
    /// событие). Порядок на выходе — по `lastUsed` убыв., за лимитом уходит самая старая.
    static func merge(_ fresh: [Project], into stored: [Project],
                      refresh: TimeInterval) -> [Project] {
        var byFolder: [String: Project] = [:]
        var order: [String] = []
        for project in stored {
            let key = project.folder.standardizedFileURL.path
            if byFolder[key] == nil { order.append(key) }
            byFolder[key] = project
        }
        for project in fresh {
            let folder = project.folder.standardizedFileURL
            let key = folder.path
            let name = project.name.isEmpty ? folder.lastPathComponent : project.name
            guard let known = byFolder[key] else {
                order.append(key)
                byFolder[key] = Project(folder: folder, name: name,
                                        lastFocusedAt: project.lastFocusedAt)
                continue
            }
            guard project.lastFocusedAt >= known.lastFocusedAt + refresh * 1000 else { continue }
            byFolder[key] = Project(folder: folder, name: name,
                                    lastFocusedAt: project.lastFocusedAt)
        }
        let all = order.compactMap { byFolder[$0] }
        return Array(all.sorted { $0.lastFocusedAt > $1.lastFocusedAt }.prefix(limit))
    }

    /// Миллисекунды эпохи (в них же `ProjectSession.lastFocusedAt`) ↔ дата.
    static func milliseconds(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }
    static func date(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds.isFinite ? milliseconds / 1000 : 0)
    }

    /// Запись без пути пропускается — из-за одной кривой строки не должен пропасть весь список.
    /// `lastUsed` нечитаемый — считаем «давно» (0), запись не теряем.
    static func parse(_ data: Data?) -> [Project] {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root[projectsKey] as? [[String: Any]] else { return [] }
        var out: [Project] = []
        var seen = Set<String>()
        for item in list {
            guard let raw = (item["folder"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !raw.isEmpty else { continue }
            let folder = URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath,
                             isDirectory: true).standardizedFileURL
            guard seen.insert(folder.path).inserted else { continue }
            let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let at = (item["lastUsed"] as? String).flatMap(PimpChannel.date)
            out.append(Project(folder: folder,
                               name: (name?.isEmpty == false ? name! : folder.lastPathComponent),
                               lastFocusedAt: at.map(milliseconds) ?? 0))
        }
        return out.sorted { $0.lastFocusedAt > $1.lastFocusedAt }
    }

    /// Порядок ключей побайтно: version, projects; в записи — name, folder, lastUsed
    /// (контракт плана WF36, эталон `tests/fixtures/pimp/projects.result.json`).
    static func json(_ list: [Project]) -> String {
        let items = list.map { project in
            CommandValue.object([
                (key: "name", value: .string(project.name)),
                (key: "folder", value: .string(project.folder.path)),
                (key: "lastUsed", value: .string(PimpChannel.stampText(date(project.lastFocusedAt)))),
            ]).json
        }
        return "{\"\(versionKey)\":\(version),\"\(projectsKey)\":[" + items.joined(separator: ",") + "]}"
    }
}
