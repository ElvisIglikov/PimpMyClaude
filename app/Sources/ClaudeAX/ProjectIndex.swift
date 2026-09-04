import Foundation

/// Один чат Claude Code из индекса Claude Desktop.
struct ProjectSession: Equatable {
    /// `local_<uuid>` — он же хвост адреса страницы главного окна.
    let sessionId: String
    /// Заголовок чата: у попап-окна ровно он лежит в `document.title`, им и адресуется команда.
    let title: String
    /// «user» — заголовок дал Элвис, «auto» — придумал Claude (такие повторяются: «Привет»).
    let titleSource: String
    /// Рабочая папка чата. Корнем проекта она быть не обязана — Claude Code запускают
    /// и из подпапки, поэтому наверх поднимает `ProjectFolder.root` (решение 3 плана WF15).
    let cwd: URL
    /// Когда в чат смотрели в последний раз, миллисекунды эпохи (0 — поля в файле не было).
    let lastFocusedAt: Double
    /// Чат в архиве: папку по нему спросить можно, а в список проектов он не идёт.
    let isArchived: Bool
}

/// Проект — папка (корень) и когда в ней работали в последний раз. Имя — последний
/// компонент пути: его же показывает пункт меню «🗂 Проект: PimpMyClaude».
struct Project: Equatable {
    let folder: URL
    let name: String
    let lastFocusedAt: Double
}

/// Индекс чатов Claude Code — внутренние файлы Claude Desktop:
/// `~/Library/Application Support/Claude/claude-code-sessions/<аккаунт>/<рабочее место>/local_<uuid>.json`
/// (два промежуточных каталога — GUID-ы, берём глобом). В каждом файле рядом лежат `sessionId`,
/// `cwd`, `title`, `titleSource`, `lastFocusedAt` — этого хватает, чтобы узнать папку чата,
/// не трогая ни лоадер, ни страницу (разведка Ш1 плана WF15, снято 04.09 21:00: 11 сессий,
/// у всех `cwd`).
///
/// Какой чат показывает главное окно, видно из диагностики лоадера
/// `~/Library/Application Support/MyClaude/status.json`: страница `https://claude.ai/epitaxy/local_<id>`
/// адресуется своим путём, и он же уходит в необязательное поле `match` команды `theme`
/// (решение 1 плана WF15) — по заголовку главное окно не адресовать: там заглушка «Claude»,
/// и такую же носят безымянные попапы. Попап-окна адресуются заголовком, как и раньше.
///
/// **Путь и формат — чужие**: обновление Claude Desktop может сменить и то и другое. Поэтому весь
/// разбор здесь, а «не разобралось» значит «папки не знаю»: приложение молчит (ни команд, ни
/// ошибок), остальные его функции не ломаются.
///
/// Класс не потокобезопасен — зовут его с одной очереди (у покраски это общий тик 2 с
/// `ClaudeAXController`). Файлы перечитываются по mtime и размеру: разбор идёт, только когда
/// чат правда изменился.
final class ProjectIndex {
    /// Индекс чатов внутри домашней папки.
    static let sessionsPath = "Library/Application Support/Claude/claude-code-sessions"
    /// Имя файла сессии: `local_<uuid>.json`.
    static let sessionPrefix = "local_"
    static let sessionExtension = "json"
    /// Диагностика лоадера (v7) — рядом с command.json, переписывается раз в 2 с.
    static let statusFileName = "status.json"
    static let pageHost = "claude.ai"
    /// Начало пути страницы чата: `/epitaxy/local_<id>`.
    static let pagePrefix = "/epitaxy/"
    /// Заглушки заголовка — тот же список, что `THEME_TITLE_STUBS` в inject.js (:776):
    /// по такому заголовку окно не опознать, значит и папку по нему не искать.
    static let titleStubs: Set<String> = ["claude", "new chat", "новый чат"]
    /// Чаще, чем раз в 2 с, каталог обходить незачем: status.json лоадер пишет с тем же шагом.
    static let reloadInterval: TimeInterval = 2

    /// Страница чата в диагностике лоадера.
    struct Page: Equatable {
        let sessionId: String
        /// `location.pathname` страницы — поле `match` команды `theme`.
        let match: String
    }

    /// Главное окно Claude: чем адресовать команду и какая у чата папка.
    struct MainWindow: Equatable {
        /// Путь страницы для поля `match`.
        let match: String
        /// Запись чата из индекса; nil — индекс его не знает (обычный чат claude.ai,
        /// индекс исчез, формат сменился).
        let session: ProjectSession?
        /// Корень проекта; nil — папку не знаем, красить нечем.
        let folder: URL?
    }

    private struct Entry {
        let stamp: String
        let session: ProjectSession
    }

    private let sessionsDirectory: URL
    private let statusURL: URL
    private let projectsRoot: URL
    private let home: URL
    private let now: () -> Date
    private let fileManager: FileManager

    /// Разобранные файлы по пути: mtime+размер не изменились — JSON заново не читаем.
    private var entries: [String: Entry] = [:]
    private var loadedAt: Date?
    private var loaded: [ProjectSession] = []

    /// Что известно об открытых чатах, свежие первыми. Обращение перечитывает индекс, если
    /// с прошлого раза прошло больше `reloadInterval`.
    var sessions: [ProjectSession] {
        reloadIfNeeded()
        return loaded
    }

    init(sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(ProjectIndex.sessionsPath, isDirectory: true),
         statusURL: URL = CommandChannel.directory
            .appendingPathComponent(ProjectIndex.statusFileName),
         projectsRoot: URL = StatusFeed.projectsRoot(),
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         now: @escaping () -> Date = Date.init,
         fileManager: FileManager = .default) {
        self.sessionsDirectory = sessionsDirectory
        self.statusURL = statusURL
        self.projectsRoot = projectsRoot
        self.home = home
        self.now = now
        self.fileManager = fileManager
    }

    // MARK: - публичный API (его зовут покраска WF15 и «новое окно в папке» WF16)

    /// Папка проекта чата по его id (`local_<uuid>`); чата нет в индексе — nil.
    func folder(for sessionId: String) -> URL? { session(for: sessionId).map(folder(of:)) }

    /// Папка проекта по заголовку окна — так адресуются попапы. Заголовок пустой или
    /// заглушка — nil; тот же заголовок нашёлся в РАЗНЫХ папках — тоже nil: лучше не
    /// покрасить, чем покрасить чужим цветом (решение 2 п. 2 плана WF15). Одинаковые
    /// заголовки внутри одной папки неопределённостью не считаются — папка-то одна.
    func folder(forTitle title: String) -> URL? {
        reloadIfNeeded()
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, !ProjectIndex.isStub(wanted) else { return nil }
        var found: URL?
        for session in loaded where session.title == wanted {
            let folder = self.folder(of: session)
            if let known = found, known.path != folder.path { return nil }
            found = folder
        }
        return found
    }

    /// Запись чата по id.
    func session(for sessionId: String) -> ProjectSession? {
        reloadIfNeeded()
        let wanted = sessionId.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        return loaded.first { $0.sessionId == wanted }
    }

    /// Проекты, о которых знает индекс: по одному на папку, свежие первыми. Архивные чаты
    /// в список не идут.
    func projects() -> [Project] {
        reloadIfNeeded()
        var seen = Set<String>()
        var out: [Project] = []
        // Чаты уже лежат свежими вперёд — первая встреча папки и есть её место в списке.
        for session in loaded where !session.isArchived {
            let folder = self.folder(of: session)
            guard seen.insert(folder.path).inserted else { continue }
            out.append(Project(folder: folder, name: folder.lastPathComponent,
                               lastFocusedAt: session.lastFocusedAt))
        }
        return out
    }

    /// Последние папки — «новое окно в папке» (WF16) берёт список отсюда, своего сканера
    /// сессий не заводит (критик В6 плана WF15).
    func recentProjects(limit: Int) -> [Project] {
        guard limit > 0 else { return [] }
        return Array(projects().prefix(limit))
    }

    /// Главное окно по диагностике лоадера. Страница claude.ai одна — она и есть главное окно;
    /// оказалось несколько (допущение WF13) — берём чат с наибольшим `lastFocusedAt` и красим
    /// только его; ни одна страница не сошлась с индексом — nil, не красим ничего
    /// (решение 2 п. 3 плана WF15).
    func mainWindow() -> MainWindow? {
        reloadIfNeeded()
        let pages = ProjectIndex.pages(try? Data(contentsOf: statusURL))
        guard !pages.isEmpty else { return nil }
        if pages.count == 1, let page = pages.first {
            let session = self.session(for: page.sessionId)
            return MainWindow(match: page.match, session: session,
                              folder: session.map(folder(of:)))
        }
        let known = pages.compactMap { page -> (Page, ProjectSession)? in
            session(for: page.sessionId).map { (page, $0) }
        }
        guard let best = known.max(by: { $0.1.lastFocusedAt < $1.1.lastFocusedAt }) else { return nil }
        return MainWindow(match: best.0.match, session: best.1, folder: folder(of: best.1))
    }

    /// Корень проекта чата: подъём от `cwd` до первой папки с `.git` или `AGENTS.md`.
    func folder(of session: ProjectSession) -> URL {
        ProjectFolder.root(for: session.cwd, projectsRoot: projectsRoot, home: home,
                           fileManager: fileManager)
    }

    // MARK: - чтение индекса

    /// Перечитать индекс. Возвращает, изменился ли состав чатов: покраске это повод оглядеться.
    @discardableResult
    func reload() -> Bool {
        loadedAt = now()
        var fresh: [String: Entry] = [:]
        for url in ProjectIndex.sessionFiles(in: sessionsDirectory, fileManager: fileManager) {
            let stamp = ProjectIndex.stamp(of: url)
            if let known = entries[url.path], known.stamp == stamp {
                fresh[url.path] = known
                continue
            }
            // Битый или чужой файл просто пропускаем — из-за одного не должен пропасть индекс.
            guard let session = ProjectIndex.parseSession(try? Data(contentsOf: url)) else { continue }
            fresh[url.path] = Entry(stamp: stamp, session: session)
        }
        entries = fresh
        let updated = fresh.values.map { $0.session }
            .sorted { $0.lastFocusedAt > $1.lastFocusedAt }
        guard updated != loaded else { return false }
        loaded = updated
        return true
    }

    private func reloadIfNeeded() {
        if let loadedAt = loadedAt,
           now().timeIntervalSince(loadedAt) < ProjectIndex.reloadInterval { return }
        reload()
    }

    // MARK: - чистая часть (её же гоняют тесты)

    static func isStub(_ title: String) -> Bool {
        titleStubs.contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Файлы сессий: `<индекс>/<аккаунт>/<рабочее место>/local_*.json`. Оба промежуточных
    /// каталога — GUID-ы, поэтому обходим их, а не гадаем имена; чужие файлы и лишняя
    /// вложенность отсеиваются именем.
    static func sessionFiles(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        func children(_ url: URL) -> [URL] {
            (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles])) ?? []
        }
        var files: [URL] = []
        for account in children(directory) {
            for place in children(account) {
                files += children(place).filter {
                    $0.lastPathComponent.hasPrefix(sessionPrefix) && $0.pathExtension == sessionExtension
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Отпечаток файла для кэша: время правки и размер.
    static func stamp(of url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let at = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(at):\(values?.fileSize ?? 0)"
    }

    /// Разбор файла сессии. Без `sessionId` или `cwd` запись бесполезна — папку она не даёт.
    static func parseSession(_ data: Data?) -> ProjectSession? {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = (root["sessionId"] as? String)?.trimmingCharacters(in: .whitespaces),
              !sessionId.isEmpty,
              let cwd = (root["cwd"] as? String)?.trimmingCharacters(in: .whitespaces),
              cwd.hasPrefix("/") else { return nil }
        let title = (root["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let at = (root["lastFocusedAt"] as? NSNumber)?.doubleValue
            ?? (root["lastActivityAt"] as? NSNumber)?.doubleValue ?? 0
        return ProjectSession(sessionId: sessionId, title: title,
                              titleSource: root["titleSource"] as? String ?? "",
                              cwd: URL(fileURLWithPath: cwd, isDirectory: true),
                              lastFocusedAt: at,
                              isArchived: root["isArchived"] as? Bool ?? false)
    }

    /// Страницы чатов из status.json лоадера: `webContents[].url`. Попапы (`about:blank`),
    /// артефакты (`data:`) и рамка окна (`file://`) сюда не попадают.
    static func pages(_ data: Data?) -> [Page] {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["webContents"] as? [[String: Any]] else { return [] }
        return list.compactMap { page(url: $0["url"] as? String ?? "") }
    }

    /// Адрес страницы → id чата и путь для поля `match`. Путь сверяется со страничным
    /// `location.pathname`, поэтому в id пускаем только буквы, цифры, дефис и подчёркивание:
    /// всё прочее страница показала бы percent-кодировкой, и сверка бы не сошлась.
    static func page(url: String) -> Page? {
        guard url.hasPrefix("https://"), let parts = URLComponents(string: url),
              parts.host == pageHost, parts.path.hasPrefix(pagePrefix) else { return nil }
        let id = String(parts.path.dropFirst(pagePrefix.count))
        guard id.hasPrefix(sessionPrefix),
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        return Page(sessionId: id, match: parts.path)
    }
}

/// Корень проекта. `cwd` чата корнем быть не обязан: Claude Code запускают и из подпапки
/// (`…/PimpMyClaude/app`) — тогда файл вида лёг бы в подпапку и у двух чатов одного проекта
/// были бы разные цвета (критик В2 плана WF15).
enum ProjectFolder {
    /// Приметы корня: репозиторий или памятка агенту.
    static let markers = [".git", "AGENTS.md"]
    /// Потолок на всякий случай: путь из чужого файла может оказаться каким угодно.
    static let maxDepth = 24

    /// Подъём от `cwd` до первой папки с `.git` или `AGENTS.md`. Потолок — `projectsRoot`
    /// из claude.json и домашняя папка (в них самих примету не ищем: `~/_ElvisProjects`
    /// проектом не является, а в домашней папке `.git` вполне может лежать). Ничего не
    /// нашли — сам `cwd`.
    static func root(for cwd: URL, projectsRoot: URL?, home: URL,
                     fileManager: FileManager = .default) -> URL {
        let start = cwd.standardizedFileURL
        var ceilings: Set<String> = [home.standardizedFileURL.path, "/"]
        if let projectsRoot = projectsRoot { ceilings.insert(projectsRoot.standardizedFileURL.path) }
        var current = start
        for _ in 0..<maxDepth {
            if ceilings.contains(current.path) { break }
            if hasMarker(current, fileManager: fileManager) { return current }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return start
    }

    static func hasMarker(_ folder: URL, fileManager: FileManager = .default) -> Bool {
        markers.contains { fileManager.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }
}
