import AppKit
import XCTest
@testable import ClaudeAX

/// Часы под рукой: индекс перечитывает файлы сессий не чаще раза в 2 с, а тесту надо
/// переключить чат сразу.
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_756_900_000)
    func advance(_ seconds: TimeInterval = 10) { now = now.addingTimeInterval(seconds) }
}

/// UserDefaults в памяти: тумблер «Красить чаты по проекту» и показанные подсказки не должны
/// попадать в живые настройки приложения.
private final class ProjectDefaults: ThemeDefaults {
    private var values: [String: Any] = [:]

    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

/// Стенд покраски: индекс и файлы во временной папке, команды складываются в `sent`,
/// а всё, что живьём приходит из AX и меню, ставится полями стенда.
private final class PaintRig {
    let box: URL
    let root: URL
    let sessions: URL
    let status: URL
    let clock = Clock()
    let defaults = ProjectDefaults()
    let store: ProjectSettingsStore
    let index: ProjectIndex
    let paint: ProjectPaint

    /// Что ушло в страницу.
    var sent: [ProjectPaintCommand] = []
    /// Заголовки окон Claude на экране (AX).
    var titles: [String] = []
    /// Окна с ручным выбором или после «Раскрасить по кругу».
    var busy: Set<String> = []
    var allWindows = false
    var menuOpen = false
    var lastMenuCommand: Date?
    var notices: [String] = []
    /// Что «применено к окну» — из этого «Записать этот вид в проект» делает файл.
    var view = ProjectSettings()
    /// Запись команды не удалась (диск, права): покраска должна попробовать снова.
    var writes = true

    init(box: URL) {
        self.box = box
        root = box.appendingPathComponent("_ElvisProjects", isDirectory: true)
        sessions = box.appendingPathComponent("sessions", isDirectory: true)
        status = box.appendingPathComponent("status.json")
        let clock = self.clock
        store = ProjectSettingsStore(registryURL: box.appendingPathComponent("projects.json"))
        index = ProjectIndex(sessionsDirectory: sessions, statusURL: status, projectsRoot: root,
                             home: box, now: { clock.now })
        paint = ProjectPaint(index: index, store: store, defaults: defaults, now: { clock.now })

        paint.send = { [unowned self] command in
            guard self.writes else { return false }
            self.sent.append(command)
            return true
        }
        paint.windowTitles = { [unowned self] in self.titles }
        paint.isWindowBusy = { [unowned self] title in self.busy.contains(title) }
        paint.isAllWindowsSet = { [unowned self] in self.allWindows }
        paint.isMenuOpen = { [unowned self] in self.menuOpen }
        paint.lastMenuCommand = { [unowned self] in self.lastMenuCommand }
        paint.showNotice = { [unowned self] text in self.notices.append(text) }
        paint.currentView = { [unowned self] _ in self.view }
    }

    func folder(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    /// Слои последней ушедшей команды: «t» — тема, «f» — шрифт, «s» — размер, «r» — рамка;
    /// заглавная буква — слой сняли (`null`).
    static func layers(_ command: ProjectPaintCommand) -> String {
        mark(command.theme, "t") + mark(command.font, "f")
            + mark(command.size, "s") + mark(command.frame, "r")
    }

    private static func mark<Value>(_ layer: Layer<Value>, _ letter: String) -> String {
        switch layer {
        case .keep: return ""
        case .reset: return letter.uppercased()
        case .set: return letter
        }
    }
}

/// Цвет проекта (план WF15): индекс чатов Claude Code, корень проекта и файл `.pimpmyclaude.json`.
/// Живого Claude тут нет — всё на временных папках: индекс это чужие файлы, и единственное, чем
/// мы от их смены защищены, — «не разобралось значит папки не знаю».
final class ProjectTests: XCTestCase {
    // MARK: - песочница

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeFolder(_ url: URL, marker: String? = nil) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard let marker = marker else { return }
        if marker == ".git" {
            try? FileManager.default.createDirectory(at: url.appendingPathComponent(marker),
                                                     withIntermediateDirectories: true)
        } else {
            try? Data("# памятка".utf8).write(to: url.appendingPathComponent(marker))
        }
    }

    /// Файл сессии в индексе: два промежуточных каталога — GUID-ы, как у живого Claude.
    @discardableResult
    private func putSession(_ index: URL, id: String, title: String, source: String = "user",
                            cwd: URL, at: Double, archived: Bool = false,
                            place: String = "8cb117af-92f2-453d-ad18-11d918093495") -> URL {
        let dir = index.appendingPathComponent("4646c58f-1c97-4640-a633-4c31d7b44584")
            .appendingPathComponent(place)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body: [String: Any] = [
            "sessionId": id, "title": title, "titleSource": source, "cwd": cwd.path,
            "originCwd": cwd.path, "lastFocusedAt": at, "lastActivityAt": at,
            "isArchived": archived, "model": "claude-fable-5-1",
        ]
        let url = dir.appendingPathComponent("\(id).json")
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        try? data.write(to: url)
        return url
    }

    private func putStatus(_ url: URL, urls: [String]) {
        let body: [String: Any] = [
            "at": "2026-09-04T21:00:00Z", "loader": 6,
            "windows": [["id": 1, "min": [320, 320], "size": [353, 922]]],
            "webContents": urls.map { ["id": 2, "url": $0, "css": "inserted", "inject": "wf15"] },
        ]
        try? (try? JSONSerialization.data(withJSONObject: body))?.write(to: url)
    }

    private func index(_ sessions: URL, status: URL, root: URL, home: URL) -> ProjectIndex {
        ProjectIndex(sessionsDirectory: sessions, statusURL: status, projectsRoot: root, home: home)
    }

    // MARK: - индекс чатов

    func testProjectIndexReadsCwdAndTitle() {
        let box = makeTemp()
        let root = box.appendingPathComponent("_ElvisProjects", isDirectory: true)
        let sessions = box.appendingPathComponent("sessions", isDirectory: true)
        let status = box.appendingPathComponent("status.json")
        let pimp = root.appendingPathComponent("PimpMyClaude", isDirectory: true)
        let dictatorik = root.appendingPathComponent("Dictatorik", isDirectory: true)
        makeFolder(pimp.appendingPathComponent("app/Sources"), marker: nil)
        makeFolder(pimp, marker: ".git")
        makeFolder(dictatorik, marker: "AGENTS.md")
        makeFolder(root.appendingPathComponent("TrelvisCom", isDirectory: true))
        makeFolder(root.appendingPathComponent("Старьё", isDirectory: true))

        // Чат запущен из ПОДПАПКИ проекта — папка всё равно должна выйти корневая.
        putSession(sessions, id: "local_a1", title: "PimpMyClaude",
                   cwd: pimp.appendingPathComponent("app/Sources"), at: 3000)
        // Авто-заголовок «Привет» (его ставит «Новое окно» WF13) в ДВУХ разных папках.
        putSession(sessions, id: "local_b2", title: "Привет", source: "auto", cwd: pimp, at: 2500)
        putSession(sessions, id: "local_c3", title: "Привет", source: "auto",
                   cwd: dictatorik, at: 2000)
        // Тот же заголовок внутри ОДНОЙ папки неопределённостью не считается.
        putSession(sessions, id: "local_d4", title: "Одинаково",
                   cwd: pimp.appendingPathComponent("app"), at: 1500)
        putSession(sessions, id: "local_e5", title: "Одинаково", cwd: pimp, at: 1400)
        putSession(sessions, id: "local_f6", title: "Claude", source: "auto",
                   cwd: root.appendingPathComponent("TrelvisCom"), at: 1000)
        putSession(sessions, id: "local_g7", title: "Старое", cwd: root.appendingPathComponent("Старьё"),
                   at: 900, archived: true)

        let index = self.index(sessions, status: status, root: root, home: box)
        XCTAssertEqual(index.sessions.count, 7)

        // Папка по id: подъём от cwd до .git.
        XCTAssertEqual(index.folder(for: "local_a1")?.path, pimp.path)
        XCTAssertEqual(index.session(for: "local_a1")?.cwd.path,
                       pimp.appendingPathComponent("app/Sources").path, "cwd читается как есть")
        XCTAssertEqual(index.session(for: "local_b2")?.titleSource, "auto")
        XCTAssertEqual(index.session(for: "local_a1")?.lastFocusedAt, 3000)
        XCTAssertNil(index.folder(for: "local_нет"))

        // Папка по заголовку — так адресуются попап-окна.
        XCTAssertEqual(index.folder(forTitle: "PimpMyClaude")?.path, pimp.path)
        XCTAssertEqual(index.folder(forTitle: " PimpMyClaude ")?.path, pimp.path)
        XCTAssertEqual(index.folder(forTitle: "Одинаково")?.path, pimp.path)
        XCTAssertNil(index.folder(forTitle: "Привет"), "две папки на один заголовок — не красим")
        XCTAssertNil(index.folder(forTitle: "Claude"), "заглушка заголовка")
        XCTAssertNil(index.folder(forTitle: "  "))
        XCTAssertNil(index.folder(forTitle: "Нет такого чата"))

        // Список проектов: по одному на папку, свежие первыми, архивные не в счёт.
        XCTAssertEqual(index.projects().map { $0.name }, ["PimpMyClaude", "Dictatorik", "TrelvisCom"])
        XCTAssertEqual(index.projects().first?.lastFocusedAt, 3000)
        XCTAssertEqual(index.recentProjects(limit: 2).map { $0.name }, ["PimpMyClaude", "Dictatorik"])
        XCTAssertTrue(index.recentProjects(limit: 0).isEmpty)

        // Главное окно — по адресу страницы из status.json лоадера, а не по заголовку.
        putStatus(status, urls: ["about:blank", "data:text/html,%3Chtml%3E",
                                 "file:///Applications/Claude.app/Contents/Resources/app.asar/index.html",
                                 "https://claude.ai/epitaxy/local_b2"])
        let main = index.mainWindow()
        XCTAssertEqual(main?.match, "/epitaxy/local_b2")
        XCTAssertEqual(main?.session?.sessionId, "local_b2")
        XCTAssertEqual(main?.folder?.path, pimp.path)

        // Страниц claude.ai две (допущение WF13 не сбылось) — ведём ту, в которой были позже.
        putStatus(status, urls: ["https://claude.ai/epitaxy/local_c3",
                                 "https://claude.ai/epitaxy/local_a1"])
        XCTAssertEqual(index.mainWindow()?.match, "/epitaxy/local_a1")
        XCTAssertEqual(index.mainWindow()?.folder?.path, pimp.path)
    }

    /// Список папок для «🪟 Новое окно ▸» и уникальное имя чата (план WF16, решения 2 и 4):
    /// свежие первыми, по одной записи на папку, архивные и исчезнувшие каталоги — вон,
    /// потолок — сколько попросили.
    func testProjectIndexRecentSortsDedupesAndCaps() {
        let box = makeTemp()
        let root = box.appendingPathComponent("_ElvisProjects", isDirectory: true)
        let sessions = box.appendingPathComponent("sessions", isDirectory: true)
        let status = box.appendingPathComponent("status.json")
        let clock = Clock()

        // Десять живых папок: «Проект1» самая свежая, «Проект10» самая старая.
        for number in 1...10 {
            let folder = root.appendingPathComponent("Проект\(number)", isDirectory: true)
            makeFolder(folder, marker: ".git")
            putSession(sessions, id: "local_p\(number)", title: "Проект\(number)", cwd: folder,
                       at: Double(10_000 - number * 10))
        }
        // Второй чат того же проекта, да ещё из подпапки: папка в списке остаётся одна,
        // и место у неё по самому свежему чату — «Проект3» уходит в начало.
        makeFolder(root.appendingPathComponent("Проект3/app", isDirectory: true))
        putSession(sessions, id: "local_dup", title: "Ещё один",
                   cwd: root.appendingPathComponent("Проект3/app", isDirectory: true), at: 9_999)
        // Архивный чат в список не идёт вовсе, даже самый свежий.
        let archived = root.appendingPathComponent("Архивный", isDirectory: true)
        makeFolder(archived, marker: ".git")
        putSession(sessions, id: "local_arch", title: "Архивный", cwd: archived, at: 20_000,
                   archived: true)
        // Папку снесли, а чат в индексе остался: пункт меню открыл бы окно в никуда.
        putSession(sessions, id: "local_gone", title: "Снесённый",
                   cwd: root.appendingPathComponent("Снесённый", isDirectory: true), at: 30_000)

        let index = ProjectIndex(sessionsDirectory: sessions, statusURL: status, projectsRoot: root,
                                 home: box, now: { clock.now })
        XCTAssertEqual(index.recentProjects(limit: MenuModel.newWindowProjectsLimit).map { $0.name },
                       ["Проект3", "Проект1", "Проект2", "Проект4", "Проект5", "Проект6",
                        "Проект7", "Проект8"])
        XCTAssertEqual(index.recentProjects(limit: 3).map { $0.name },
                       ["Проект3", "Проект1", "Проект2"])
        XCTAssertTrue(index.recentProjects(limit: 0).isEmpty)
        XCTAssertTrue(index.recentProjects(limit: -1).isEmpty)
        XCTAssertEqual(index.recentProjects(limit: 50).count, 10, "по одной записи на папку")
        XCTAssertNil(index.recentProjects(limit: 50).first { $0.name == "Снесённый" },
                     "папки нет на диске — и пункта быть не должно")
        XCTAssertNil(index.recentProjects(limit: 50).first { $0.name == "Архивный" })
        // Полный путь есть у каждой записи — он уходит и в команду, и в подсказку пункта.
        XCTAssertEqual(index.recentProjects(limit: 1).first?.folder.path,
                       root.appendingPathComponent("Проект3").path)

        // Имя чата: занятое имя получает номер, свободное остаётся как есть (критик В4).
        XCTAssertEqual(index.uniqueChatName("Проект1"), "Проект1 2")
        XCTAssertEqual(index.uniqueChatName("  Проект1  "), "Проект1 2")
        XCTAssertEqual(index.uniqueChatName("Свежий"), "Свежий")
        XCTAssertEqual(index.uniqueChatName("   "), "", "пустое имя — переименовывать нечем")
        XCTAssertEqual(index.uniqueChatName("Архивный"), "Архивный 2", "архивные заголовки заняты тоже")

        // Занятый номер пропускается, а не затирается.
        putSession(sessions, id: "local_n2", title: "Проект1 2",
                   cwd: root.appendingPathComponent("Проект1", isDirectory: true), at: 50)
        clock.advance()
        XCTAssertEqual(index.uniqueChatName("Проект1"), "Проект1 3")
        // Номера кончились — отдаём имя как есть: уникальность и так не абсолютная.
        XCTAssertEqual(index.uniqueChatName("Проект1", limit: 2), "Проект1")

        // Индекса нет вовсе (не Claude Code, чужая машина) — пустой список, а не падение.
        let empty = ProjectIndex(sessionsDirectory: box.appendingPathComponent("нет"),
                                 statusURL: status, projectsRoot: root, home: box)
        XCTAssertTrue(empty.recentProjects(limit: 8).isEmpty)
        XCTAssertEqual(empty.uniqueChatName("Проект1"), "Проект1")
    }

    func testProjectIndexIgnoresBrokenJSON() {
        let box = makeTemp()
        let root = box.appendingPathComponent("_ElvisProjects", isDirectory: true)
        let sessions = box.appendingPathComponent("sessions", isDirectory: true)
        let status = box.appendingPathComponent("status.json")
        let good = root.appendingPathComponent("Живой", isDirectory: true)
        makeFolder(good, marker: ".git")
        putSession(sessions, id: "local_ok", title: "Живой", cwd: good, at: 100)

        let dir = sessions.appendingPathComponent("4646c58f-1c97-4640-a633-4c31d7b44584")
            .appendingPathComponent("8cb117af-92f2-453d-ad18-11d918093495")
        try? Data("{".utf8).write(to: dir.appendingPathComponent("local_broken.json"))
        try? Data().write(to: dir.appendingPathComponent("local_empty.json"))
        try? Data("{\"sessionId\":\"local_nocwd\"}".utf8)
            .write(to: dir.appendingPathComponent("local_nocwd.json"))
        try? Data("{\"cwd\":\"/tmp\"}".utf8).write(to: dir.appendingPathComponent("local_noid.json"))
        // Чужие файлы каталога в индекс не идут вовсе.
        try? Data("{\"sessionId\":\"x\",\"cwd\":\"/tmp\"}".utf8)
            .write(to: dir.appendingPathComponent("recents.json"))

        let index = self.index(sessions, status: status, root: root, home: box)
        XCTAssertEqual(index.sessions.map { $0.sessionId }, ["local_ok"])
        XCTAssertEqual(index.folder(for: "local_ok")?.path, good.path)

        // Разбор одной записи.
        XCTAssertNil(ProjectIndex.parseSession(nil))
        XCTAssertNil(ProjectIndex.parseSession(Data("[]".utf8)))
        XCTAssertNil(ProjectIndex.parseSession(Data("{\"sessionId\":\"a\",\"cwd\":\"отн/путь\"}".utf8)))

        // Индекса нет вовсе (не Claude Code, чужая машина) — молчим, а не падаем.
        let empty = self.index(box.appendingPathComponent("нет"), status: status,
                               root: root, home: box)
        XCTAssertTrue(empty.sessions.isEmpty)
        XCTAssertNil(empty.folder(forTitle: "Живой"))
        XCTAssertTrue(empty.projects().isEmpty)
        XCTAssertTrue(ProjectIndex.sessionFiles(in: box.appendingPathComponent("нет")).isEmpty)

        // status.json лоадера: нет, битый, без наших страниц.
        XCTAssertNil(index.mainWindow())
        try? Data("не json".utf8).write(to: status)
        XCTAssertTrue(ProjectIndex.pages(try? Data(contentsOf: status)).isEmpty)
        XCTAssertNil(index.mainWindow())
        putStatus(status, urls: ["about:blank", "https://claude.ai/new",
                                 "https://claude.ai/epitaxy/",
                                 "https://claude.ai/epitaxy/local_ok/settings",
                                 "https://example.com/epitaxy/local_ok",
                                 "http://claude.ai/epitaxy/local_ok",
                                 "https://claude.ai/epitaxy/%D0%BB%D0%BE%D0%BA"])
        XCTAssertTrue(ProjectIndex.pages(try? Data(contentsOf: status)).isEmpty,
                      "адресуем только страницу чата, и только точным путём")
        XCTAssertNil(index.mainWindow())
        // Страница чата есть, а чата в индексе нет — путь для match знаем, папку нет.
        putStatus(status, urls: ["https://claude.ai/epitaxy/local_чужой"])
        XCTAssertTrue(ProjectIndex.pages(try? Data(contentsOf: status)).isEmpty)
        putStatus(status, urls: ["https://claude.ai/epitaxy/local_unknown"])
        XCTAssertEqual(index.mainWindow()?.match, "/epitaxy/local_unknown")
        XCTAssertNil(index.mainWindow()?.folder)
    }

    // MARK: - корень проекта

    func testProjectRootClimbsToGitOrAgents() {
        let home = makeTemp()
        let projects = home.appendingPathComponent("_ElvisProjects", isDirectory: true)
        let git = projects.appendingPathComponent("PimpMyClaude", isDirectory: true)
        let agents = projects.appendingPathComponent("SkilZZZ", isDirectory: true)
        let bare = projects.appendingPathComponent("Голая", isDirectory: true)
        let outside = home.appendingPathComponent("Вне проектов/sub", isDirectory: true)
        makeFolder(git, marker: ".git")
        makeFolder(git.appendingPathComponent("app/Sources/ClaudeAX"))
        makeFolder(agents, marker: "AGENTS.md")
        makeFolder(agents.appendingPathComponent("docs"))
        makeFolder(bare.appendingPathComponent("sub"))
        makeFolder(outside)
        // Приметы есть и у потолков — подниматься до них всё равно нельзя.
        makeFolder(projects, marker: ".git")
        makeFolder(home, marker: "AGENTS.md")
        XCTAssertTrue(ProjectFolder.hasMarker(projects))
        XCTAssertTrue(ProjectFolder.hasMarker(home))

        func climb(_ cwd: URL, projectsRoot: URL?) -> String {
            ProjectFolder.root(for: cwd, projectsRoot: projectsRoot, home: home).path
        }

        // Claude Code запущен из подпапки — вид всё равно берётся из корня проекта.
        XCTAssertEqual(climb(git.appendingPathComponent("app/Sources/ClaudeAX"), projectsRoot: projects),
                       git.path)
        XCTAssertEqual(climb(git, projectsRoot: projects), git.path)
        XCTAssertEqual(climb(agents.appendingPathComponent("docs"), projectsRoot: projects), agents.path)
        // Ни .git, ни AGENTS.md — сама папка чата; выше projectsRoot не поднимаемся.
        XCTAssertEqual(climb(bare.appendingPathComponent("sub"), projectsRoot: projects),
                       bare.appendingPathComponent("sub").path)
        XCTAssertEqual(climb(bare, projectsRoot: projects), bare.path)
        XCTAssertEqual(climb(projects, projectsRoot: projects), projects.path)
        // Домашняя папка — потолок и без projectsRoot: её AGENTS.md корнем проекта не делает.
        XCTAssertEqual(climb(outside, projectsRoot: nil), outside.path)
        XCTAssertEqual(climb(home, projectsRoot: nil), home.path)
    }

    // MARK: - файл настроек проекта

    /// Контракт файла побайтно (решение 3 плана WF15).
    private static let canonical = """
    {
      "pimpmyclaude": 1,
      "name": "PimpMyClaude",
      "theme": {
        "id": "indigo",
        "name": "Индиго",
        "type": "dark",
        "palette": {
          "accent": "#7c8cff",
          "background": "#171a2b",
          "foreground": "#e8e9f5",
          "sidebar": "#12142230",
          "panel": "#1e2238",
          "muted": "#9aa0c0"
        }
      },
      "font": {
        "id": "menlo",
        "family": "Menlo",
        "mono": true
      },
      "size": {
        "answer": 16,
        "question": 14
      },
      "frame": true
    }

    """

    func testProjectSettingsRoundTripsBytewise() throws {
        let settings = try XCTUnwrap(ProjectSettings.parse(Data(ProjectTests.canonical.utf8)))
        XCTAssertEqual(settings.name, "PimpMyClaude")
        XCTAssertEqual(settings.theme.value?.palette["accent"], "#7c8cff")
        XCTAssertEqual(settings.theme.value?.name, "Индиго")
        XCTAssertEqual(settings.font.value?.family, "Menlo")
        XCTAssertEqual(settings.font.value?.mono, true)
        XCTAssertEqual(settings.size.value, Size(answer: 16, question: 14))
        XCTAssertEqual(settings.frame, .set(true))
        // Порядок ключей, отступ и перевод строки в конце — те же байты.
        XCTAssertEqual(settings.json(), ProjectTests.canonical)

        // Слоя нет — не трогаем, null — сброс; «рамки нет» пишется как сброс, не как false.
        let mixed = try XCTUnwrap(ProjectSettings.parse(Data("""
        {"pimpmyclaude":1,"name":"Свой","theme":null,"size":{"answer":18},"frame":false}
        """.utf8)))
        XCTAssertEqual(mixed.theme, .reset)
        XCTAssertTrue(mixed.font.isKeep)
        XCTAssertEqual(mixed.size.value, Size(answer: 18))
        XCTAssertEqual(mixed.frame, .reset)
        XCTAssertEqual(mixed.json(), """
        {
          "pimpmyclaude": 1,
          "name": "Свой",
          "theme": null,
          "size": {
            "answer": 18
          },
          "frame": null
        }

        """)
        XCTAssertEqual(ProjectSettings.parse(Data(mixed.json().utf8)), mixed, "второй круг тот же")

        // Мусор в слое равен его отсутствию; битый файл — «настроек нет».
        let junk = try XCTUnwrap(ProjectSettings.parse(Data("""
        {"pimpmyclaude":7,"theme":{"id":"indigo"},"font":{"family":"Не шрифт, а стек"},"size":{}}
        """.utf8)))
        XCTAssertTrue(junk.isEmpty, "одним id тему не восстановить, кривой шрифт не берём")
        XCTAssertNil(ProjectSettings.parse(Data("{".utf8)))
        XCTAssertNil(ProjectSettings.parse(nil))

        // Диск: пишем в папку проекта, читаем назад теми же байтами.
        let box = makeTemp()
        let folder = box.appendingPathComponent("PimpMyClaude", isDirectory: true)
        makeFolder(folder, marker: ".git")
        let store = ProjectSettingsStore(registryURL: box.appendingPathComponent("projects.json"))
        XCTAssertNil(store.settings(in: folder))
        XCTAssertEqual(store.write(settings, to: folder), .written)
        XCTAssertEqual(try String(contentsOf: store.url(in: folder), encoding: .utf8),
                       ProjectTests.canonical)
        XCTAssertEqual(store.settings(in: folder), settings)
        XCTAssertEqual(store.settings(in: folder)?.digest, settings.digest)
        // «Убрать настройки из проекта».
        XCTAssertTrue(store.remove(from: folder))
        XCTAssertNil(store.settings(in: folder))
        // Папки нет — писать некуда.
        XCTAssertEqual(store.write(settings, to: box.appendingPathComponent("нет")), .failed)

        // В папку писать нельзя (нет прав, том только для чтения) — вид уходит в реестр.
        let locked = box.appendingPathComponent("Только чтение", isDirectory: true)
        makeFolder(locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: locked.path)
        }
        XCTAssertEqual(store.write(settings, to: locked), .registry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(in: locked).path))
        XCTAssertEqual(store.settings(in: locked), settings)
        XCTAssertEqual(store.registry().keys.sorted(), [locked.standardizedFileURL.path])
    }

    func testProjectSettingsKeepsForeignKeys() throws {
        let box = makeTemp()
        let folder = box.appendingPathComponent("Чужой", isDirectory: true)
        makeFolder(folder, marker: "AGENTS.md")
        let store = ProjectSettingsStore(registryURL: box.appendingPathComponent("projects.json"))
        let url = store.url(in: folder)
        let old = """
        {
          "pimpmyclaude": 1,
          "name": "Старое имя",
          "frame": true,
          "заметка": "руками писал Элвис",
          "editor": { "b": 2, "a": [1, 2] },
          "version": 3
        }

        """
        try Data(old.utf8).write(to: url)

        let settings = ProjectSettings(name: "Чужой", size: .set(Size(answer: 15)))
        XCTAssertEqual(store.write(settings, to: folder), .written)
        let text = try String(contentsOf: url, encoding: .utf8)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8))
                                     as? [String: Any])
        XCTAssertEqual(root["заметка"] as? String, "руками писал Элвис", "чужой ключ потерян")
        XCTAssertEqual((root["editor"] as? [String: Any])?["b"] as? Int, 2)
        XCTAssertEqual((root["editor"] as? [String: Any])?["a"] as? [Int], [1, 2])
        XCTAssertEqual(root["version"] as? Int, 3)
        XCTAssertEqual(root["name"] as? String, "Чужой", "наш ключ переписан")
        XCTAssertNil(root["frame"], "слой сняли — ключа больше нет")
        // Наши ключи идут первыми и в порядке контракта, чужие — следом по алфавиту.
        XCTAssertTrue(text.hasPrefix("{\n  \"pimpmyclaude\": 1,\n  \"name\": \"Чужой\",\n  \"size\""), text)
        XCTAssertTrue(text.hasSuffix("}\n"))
        let order = ["\"pimpmyclaude\"", "\"name\"", "\"size\"", "\"editor\"", "\"version\"", "\"заметка\""]
        var cursor = text.startIndex
        for key in order {
            let found = try XCTUnwrap(text.range(of: key, range: cursor..<text.endIndex),
                                      "ключ \(key) не на своём месте")
            cursor = found.upperBound
        }
        // Второй круг ничего не двигает: файл сам собой не меняется.
        XCTAssertEqual(store.write(settings, to: folder), .written)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)

        // Битый файл сами не переписываем — только по явному «да» из пункта меню.
        try Data("{ это не json".utf8).write(to: url)
        XCTAssertEqual(store.write(settings, to: folder), .broken)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ это не json")
        XCTAssertNil(store.settings(in: folder), "битый файл — «настроек нет», реестр не подменяет")
        XCTAssertEqual(store.write(settings, to: folder, force: true), .written)
        XCTAssertEqual(store.settings(in: folder), settings)
    }

    // MARK: - покраска по проекту (батч S2 плана WF15)

    private static let indigo = Theme(id: "indigo", name: "Индиго", type: "dark",
                                      palette: ["accent": "#7c8cff", "background": "#171a2b",
                                                "foreground": "#e8e9f5", "sidebar": "#12142230",
                                                "panel": "#1e2238", "muted": "#9aa0c0"])
    private static let arctic = Theme(id: "arctic", name: "Арктика", type: "light",
                                      palette: ["accent": "#2563eb", "background": "#eef2f8",
                                                "foreground": "#1f2430", "sidebar": "#dfe6f1",
                                                "panel": "#ffffff", "muted": "#5b6478"])
    private static let menlo = Font(id: "menlo", family: "Menlo", category: .mono, displayName: "Menlo")

    /// Песочница покраски: `~/_ElvisProjects` с двумя проектами, чат PimpMyClaude запущен из
    /// подпапки, а главное окно смотрит именно в него.
    private func makeRig() -> PaintRig {
        let rig = PaintRig(box: makeTemp())
        makeFolder(rig.folder("PimpMyClaude"), marker: ".git")
        makeFolder(rig.folder("PimpMyClaude").appendingPathComponent("app"))
        makeFolder(rig.folder("Dictatorik"), marker: "AGENTS.md")
        putSession(rig.sessions, id: "local_a1", title: "PimpMyClaude",
                   cwd: rig.folder("PimpMyClaude").appendingPathComponent("app"), at: 3000)
        putSession(rig.sessions, id: "local_b2", title: "Dictatoric",
                   cwd: rig.folder("Dictatorik"), at: 2000)
        putStatus(rig.status, urls: ["https://claude.ai/epitaxy/local_a1"])
        return rig
    }

    private func click(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target else {
            return XCTFail("пункт «\(item.title)» ничего не делает")
        }
        _ = target.perform(action, with: item)
    }

    func testProjectPaintFingerprintSkipsRepeat() throws {
        let rig = makeRig()
        let pimp = rig.folder("PimpMyClaude")
        rig.store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(ProjectTests.indigo),
                                        font: .set(ProjectTests.menlo)), to: pimp)

        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 1)
        let first = try XCTUnwrap(rig.sent.first)
        // Главное окно адресуется ПУТЁМ страницы, а не заголовком (критик Б1): заголовок у него
        // заглушка «Claude», и по ней команда ушла бы веером безымянным попапам.
        XCTAssertEqual(first.match, "/epitaxy/local_a1")
        XCTAssertEqual(first.title, "")
        XCTAssertEqual(first.key, "main")
        XCTAssertEqual(first.theme.value?.id, "indigo")
        XCTAssertEqual(first.font.value?.family, "Menlo")
        XCTAssertEqual(PaintRig.layers(first), "tf")

        // Тот же проект и тот же вид — команда не повторяется (иначе забьётся очередь канала).
        rig.clock.advance()
        rig.paint.tick()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 1)

        // Файл правят руками — окно перекрашивается без перезапуска приложения.
        rig.store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(ProjectTests.arctic)), to: pimp)
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 2)
        XCTAssertEqual(rig.sent[1].theme.value?.id, "arctic")
        // Шрифт новый вид не задаёт, а прошлый ставил — слой снимаем (критик Б2).
        XCTAssertEqual(PaintRig.layers(rig.sent[1]), "tF")

        // Команда не записалась — отпечаток не запомнили, пробуем на следующем тике.
        rig.writes = false
        rig.store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(ProjectTests.indigo)), to: pimp)
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 2)
        rig.writes = true
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 3)
        XCTAssertEqual(rig.sent[2].theme.value?.id, "indigo")
    }

    func testProjectPaintResetsLayersWhenProjectHasNoSettings() throws {
        let rig = makeRig()
        rig.store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(ProjectTests.indigo),
                                        size: .set(Size(answer: 16)), frame: .set(true)),
                        to: rig.folder("PimpMyClaude"))
        rig.paint.tick()
        XCTAssertEqual(rig.sent.map { PaintRig.layers($0) }, ["tsr"])

        // Главное окно ушло в проект БЕЗ настроек: слои прошлого проекта снимаем, иначе окно
        // осталось бы в чужом цвете — а у главного окна навсегда (запись `main`).
        putStatus(rig.status, urls: ["https://claude.ai/epitaxy/local_b2"])
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 2)
        XCTAssertEqual(PaintRig.layers(rig.sent[1]), "TSR")
        XCTAssertEqual(rig.sent[1].key, "main", "ключ окна переживает смену чата")
        XCTAssertEqual(rig.sent[1].match, "/epitaxy/local_b2")
        // И один раз на папку — подсказка «своего вида нет».
        XCTAssertEqual(rig.notices, [MenuModel.projectHint("Dictatorik")])

        // Снимать второй раз нечего, приставать второй раз тоже.
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 2)
        XCTAssertEqual(rig.notices.count, 1)

        // Вернулись в проект с настройками — красим снова.
        putStatus(rig.status, urls: ["https://claude.ai/epitaxy/local_a1"])
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 3)
        XCTAssertEqual(PaintRig.layers(rig.sent[2]), "tsr")

        // Чата нет в индексе вовсе — папку не знаем, чужой цвет всё равно снимаем.
        putStatus(rig.status, urls: ["https://claude.ai/epitaxy/local_unknown"])
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(PaintRig.layers(try XCTUnwrap(rig.sent.last)), "TSR")
        XCTAssertEqual(rig.sent.count, 4)
    }

    func testProjectPaintClearsOnToggleOff() throws {
        let rig = makeRig()
        rig.store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(ProjectTests.indigo),
                                        font: .set(ProjectTests.menlo)), to: rig.folder("PimpMyClaude"))
        XCTAssertTrue(rig.paint.enabled, "тумблер по умолчанию включён")
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 1)

        // Выключили тумблер — слои, которые ставил проект, снимаются сразу и одной командой.
        rig.paint.setEnabled(false)
        XCTAssertFalse(rig.paint.enabled)
        XCTAssertEqual(rig.sent.count, 2)
        XCTAssertEqual(PaintRig.layers(rig.sent[1]), "TF")
        XCTAssertEqual(rig.sent[1].key, "main")
        XCTAssertEqual(rig.sent[1].match, "/epitaxy/local_a1")

        // Выключено — тик молчит.
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 2)

        // Включили назад: сам щелчок ничего не шлёт, красит ближайший тик.
        rig.paint.setEnabled(true)
        XCTAssertEqual(rig.sent.count, 2)
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 3)
        XCTAssertEqual(PaintRig.layers(rig.sent[2]), "tf")
    }

    func testProjectPaintSkipsManuallyAndAutoPaintedWindows() throws {
        let rig = makeRig()
        // Главное окно смотрит в обычный чат — проверяем ровно попап.
        putStatus(rig.status, urls: ["about:blank"])
        rig.store.write(ProjectSettings(name: "Dictatorik", theme: .set(ProjectTests.arctic)),
                        to: rig.folder("Dictatorik"))
        rig.titles = ["Dictatoric"]
        rig.busy = ["Dictatoric"]
        rig.paint.tick()
        XCTAssertTrue(rig.sent.isEmpty, "цвет выбран руками или это «по кругу» — окно не трогаем")

        // Память об окне очистили («Всё как у Claude») — проект красит его ближайшим тиком.
        rig.busy = []
        rig.clock.advance()
        rig.paint.tick()
        let command = try XCTUnwrap(rig.sent.first)
        XCTAssertEqual(command.key, "w:Dictatoric")
        XCTAssertNil(command.match, "попап адресуется заголовком, как и раньше")
        XCTAssertEqual(command.title, "Dictatoric")
        XCTAssertEqual(command.theme.value?.id, "arctic")

        // Задан вид «всем окнам» — проект не перебивает его вовсе (критик Б3).
        rig.allWindows = true
        rig.store.write(ProjectSettings(name: "Dictatorik", theme: .set(ProjectTests.indigo)),
                        to: rig.folder("Dictatorik"))
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 1)
        rig.allWindows = false
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 2)
        XCTAssertEqual(rig.sent[1].theme.value?.id, "indigo")
    }

    func testProjectPaintSkipsDuplicateTitles() throws {
        let rig = makeRig()
        putStatus(rig.status, urls: ["about:blank"])
        // Авто-заголовок «Привет» (его ставит «Новое окно») сразу в двух папках и заглушка
        // «Claude»: по таким заголовкам красить нельзя — попадёшь в чужое окно.
        putSession(rig.sessions, id: "local_c3", title: "Привет", source: "auto",
                   cwd: rig.folder("PimpMyClaude"), at: 1800)
        putSession(rig.sessions, id: "local_d4", title: "Привет", source: "auto",
                   cwd: rig.folder("Dictatorik"), at: 1700)
        putSession(rig.sessions, id: "local_e5", title: "Claude", source: "auto",
                   cwd: rig.folder("Dictatorik"), at: 1600)
        for name in ["PimpMyClaude", "Dictatorik"] {
            rig.store.write(ProjectSettings(name: name, theme: .set(ProjectTests.indigo)),
                            to: rig.folder(name))
        }
        rig.titles = ["Привет", "Привет", "Claude", "", "Dictatoric", "Dictatoric"]
        rig.paint.tick()
        XCTAssertEqual(rig.sent.map { $0.title }, ["Dictatoric"],
                       "красим только окно с непустым уникальным заголовком")
    }

    func testProjectPaintWaitsWhileMenuIsOpen() throws {
        let rig = makeRig()
        rig.store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(ProjectTests.indigo)),
                        to: rig.folder("PimpMyClaude"))
        rig.menuOpen = true
        XCTAssertTrue(rig.paint.isQuiet)
        rig.paint.tick()
        XCTAssertTrue(rig.sent.isEmpty, "меню открыто — команда не ушла")

        // Меню закрылось, но его команда ещё в пути: не-preview команда сбила бы примерку темы
        // мышью (критик В1) — ждём 2 с.
        rig.menuOpen = false
        rig.lastMenuCommand = rig.clock.now.addingTimeInterval(-1)
        XCTAssertTrue(rig.paint.isQuiet)
        rig.paint.tick()
        XCTAssertTrue(rig.sent.isEmpty)

        rig.lastMenuCommand = rig.clock.now.addingTimeInterval(-ProjectPaint.quietSeconds - 0.5)
        XCTAssertFalse(rig.paint.isQuiet)
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 1)
    }

    func testProjectThemePayloadCarriesMatch() {
        // Побайтно: id, action, at, scope, title, match, затем слои — тема, шрифт, размер, рамка.
        let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow, title: "",
                                               match: "/epitaxy/local_f44e46bb",
                                               theme: .set(ProjectTests.indigo), font: .keep,
                                               size: .keep, frame: .reset)
        XCTAssertEqual(CommandChannel.payload(action: "theme", fields: fields, id: "1-0001",
                                              at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"theme\",\"at\":\"1970-01-01T00:00:00Z\","
                       + "\"scope\":\"window\",\"title\":\"\",\"match\":\"/epitaxy/local_f44e46bb\","
                       + "\"theme\":{\"id\":\"indigo\",\"name\":\"Индиго\",\"type\":\"dark\","
                       + "\"palette\":{\"accent\":\"#7c8cff\",\"background\":\"#171a2b\","
                       + "\"foreground\":\"#e8e9f5\",\"sidebar\":\"#12142230\",\"panel\":\"#1e2238\","
                       + "\"muted\":\"#9aa0c0\"}},\"frame\":null}")
        // Поля match нет вовсе — команда прежняя до байта (адресация заголовком).
        let plain = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow, title: "Dictatoric",
                                              theme: .reset, font: .keep)
        XCTAssertEqual(CommandChannel.payload(action: "theme", fields: plain, id: "1-0001",
                                              at: Date(timeIntervalSince1970: 0)),
                       "{\"id\":\"1-0001\",\"action\":\"theme\",\"at\":\"1970-01-01T00:00:00Z\","
                       + "\"scope\":\"window\",\"title\":\"Dictatoric\",\"theme\":null}")
    }

    func testProjectMenuActionsWriteAgentsAndRemove() throws {
        let rig = makeRig()
        let pimp = rig.folder("PimpMyClaude")
        // «💾 Записать этот вид в проект»: в файл ложатся ровно слои этого окна.
        rig.view = ProjectSettings(theme: .set(ProjectTests.indigo), size: .set(Size(answer: 16)))
        rig.paint.writeCurrentView(title: ProjectPaint.mainWindowTitle)
        XCTAssertEqual(rig.notices, [MenuModel.projectWritten("PimpMyClaude")])
        let settings = try XCTUnwrap(rig.store.settings(in: pimp))
        XCTAssertEqual(settings.name, "PimpMyClaude")
        XCTAssertEqual(settings.theme.value?.id, "indigo")
        XCTAssertEqual(settings.size.value, Size(answer: 16))

        // «🎨 Взять цвет проекта» идёт мимо проверок «занято» и «ничего не изменилось».
        rig.busy = [ProjectPaint.mainWindowTitle]
        rig.paint.applyNow(title: ProjectPaint.mainWindowTitle)
        XCTAssertEqual(rig.sent.count, 1)
        XCTAssertEqual(rig.sent[0].match, "/epitaxy/local_a1")
        XCTAssertEqual(PaintRig.layers(rig.sent[0]), "ts")

        // «📝 Вписать строку в AGENTS.md»: файла нет — заводим одной строкой.
        rig.paint.writeAgentsLine(title: ProjectPaint.mainWindowTitle)
        XCTAssertEqual(try String(contentsOf: pimp.appendingPathComponent("AGENTS.md"), encoding: .utf8),
                       "<!-- pimpmyclaude: {\"theme\":\"indigo\",\"size\":{\"answer\":16}} -->\n")
        // Прежняя памятка заменяется на месте, чужой текст не трогаем.
        XCTAssertEqual(ProjectPaint.agents(file: "# Проект\n\n<!-- pimpmyclaude: {\"theme\":\"старое\"} -->\nхвост\n",
                                           line: "<!-- pimpmyclaude: {} -->"),
                       "# Проект\n\n<!-- pimpmyclaude: {} -->\nхвост\n")
        XCTAssertEqual(ProjectPaint.agents(file: "# Проект", line: "<!-- pimpmyclaude: {} -->"),
                       "# Проект\n\n<!-- pimpmyclaude: {} -->\n")

        // «🗑 Убрать настройки»: файл ушёл, AGENTS.md на месте, окна назад не перекрашиваем.
        rig.paint.removeSettings(title: ProjectPaint.mainWindowTitle)
        XCTAssertNil(rig.store.settings(in: pimp))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pimp.appendingPathComponent("AGENTS.md").path))
        rig.clock.advance()
        rig.paint.tick()
        XCTAssertEqual(rig.sent.count, 1, "цвет остаётся, пока Элвис не выберет «Как у Claude»")

        // Пункты меню на папке без настроек: брать и вписывать нечего, и мы об этом говорим.
        rig.notices = []
        rig.paint.applyNow(title: ProjectPaint.mainWindowTitle)
        rig.paint.writeAgentsLine(title: ProjectPaint.mainWindowTitle)
        XCTAssertEqual(rig.notices, [MenuModel.projectNoSettings, MenuModel.projectNoSettings])
        XCTAssertEqual(rig.sent.count, 1)
        // Вид окна пуст — записывать в проект нечего.
        rig.view = ProjectSettings()
        rig.notices = []
        rig.paint.writeCurrentView(title: ProjectPaint.mainWindowTitle)
        XCTAssertEqual(rig.notices, [MenuModel.projectNothingToWrite])
        XCTAssertNil(rig.store.settings(in: pimp))

        // Состояние подменю: папка, путь и «настроек нет».
        let state = rig.paint.menuState(title: ProjectPaint.mainWindowTitle)
        XCTAssertEqual(state.name, "PimpMyClaude")
        XCTAssertEqual(state.path, ProjectPaint.short(path: pimp))
        XCTAssertFalse(state.hasSettings)
        XCTAssertTrue(state.painting)
        XCTAssertEqual(ProjectPaint.short(path: URL(fileURLWithPath: "/Users/elvis/_ElvisProjects/Trelvis"),
                                          home: URL(fileURLWithPath: "/Users/elvis")),
                       "~/_ElvisProjects/Trelvis")
    }

    func testMenuHasProjectItem() throws {
        var toggled: [Bool] = []
        var clicks: [String] = []
        var config = MinimizeMenu.MenuConfig()
        config.project = ProjectMenuState(folder: URL(fileURLWithPath: "/Users/elvis/_ElvisProjects/PimpMyClaude"),
                                          path: "~/_ElvisProjects/PimpMyClaude",
                                          hasSettings: true, painting: true)
        config.projectPaint = { toggled.append($0) }
        config.projectApply = { clicks.append("взять") }
        config.projectWrite = { clicks.append("записать") }
        config.projectAgents = { clicks.append("памятка") }
        config.projectRemove = { clicks.append("убрать") }

        let appearance = try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        // «🗂 Проект ▸» — первым разделом «Оформление ▸», за ним разделитель (план WF15 п. 5).
        XCTAssertEqual(Array(appearance.items.map { $0.isSeparatorItem ? "—" : $0.title }.prefix(2)),
                       ["Проект: PimpMyClaude", "—"])
        let item = try XCTUnwrap(appearance.items.first)
        XCTAssertNotNil(item.image)
        let project = try XCTUnwrap(item.submenu)
        XCTAssertEqual(project.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["~/_ElvisProjects/PimpMyClaude", "Красить чаты по проекту", "—",
                        "Взять цвет проекта", "Записать этот вид в проект",
                        "Вписать строку в AGENTS.md", "Убрать настройки из проекта"])
        // Путь папки — подпись, а не кнопка.
        XCTAssertFalse(try XCTUnwrap(project.items.first).isEnabled)
        let toggle = try XCTUnwrap(project.items.first { $0.title == MenuModel.projectPaintTitle })
        XCTAssertEqual(toggle.state, .on)
        click(toggle)
        XCTAssertEqual(toggled, [false], "клик переключает тумблер")
        for title in [MenuModel.projectApplyTitle, MenuModel.projectWriteTitle,
                      MenuModel.projectAgentsTitle, MenuModel.projectRemoveTitle] {
            let row = try XCTUnwrap(project.items.first { $0.title == title })
            XCTAssertTrue(row.isEnabled)
            XCTAssertNotNil(row.image)
            click(row)
        }
        XCTAssertEqual(clicks, ["взять", "записать", "памятка", "убрать"])

        // Настроек у проекта ещё нет: «Записать» становится «Завести», брать и убирать нечего.
        config.project = ProjectMenuState(folder: URL(fileURLWithPath: "/Users/elvis/_ElvisProjects/Новый"),
                                          path: "~/_ElvisProjects/Новый", hasSettings: false,
                                          painting: false)
        let empty = try XCTUnwrap(try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu).items.first?.submenu)
        XCTAssertEqual(empty.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["~/_ElvisProjects/Новый", "Красить чаты по проекту", "—",
                        "Взять цвет проекта", "Завести настройки проекта",
                        "Вписать строку в AGENTS.md", "Убрать настройки из проекта"])
        XCTAssertEqual(try XCTUnwrap(empty.items.first { $0.title == MenuModel.projectPaintTitle }).state, .off)
        XCTAssertFalse(try XCTUnwrap(empty.items.first { $0.title == MenuModel.projectApplyTitle }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(empty.items.first { $0.title == MenuModel.projectCreateTitle }).isEnabled)
        XCTAssertFalse(try XCTUnwrap(empty.items.first { $0.title == MenuModel.projectRemoveTitle }).isEnabled)

        // Папку не узнали — пункт остаётся, но погашен и без подменю: Элвис должен видеть,
        // что приложение не знает папку, а не гадать, почему не красит.
        config.project = ProjectMenuState(folder: nil, path: "", hasSettings: false, painting: true)
        let unknown = try XCTUnwrap(try XCTUnwrap(MinimizeMenu.build(config: config).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu).items.first)
        XCTAssertEqual(unknown.title, MenuModel.projectUnknownTitle)
        XCTAssertFalse(unknown.isEnabled)
        XCTAssertNil(unknown.submenu)

        // Меню собрано без сведений о проекте — пункта нет вовсе и лишнего разделителя тоже.
        var without = config
        without.project = nil
        let bare = try XCTUnwrap(MinimizeMenu.build(config: without).items
            .first { $0.title == MenuModel.appearanceTitle }?.submenu)
        XCTAssertNil(bare.items.first { $0.title.hasPrefix("Проект") })
        XCTAssertFalse(try XCTUnwrap(bare.items.first).isSeparatorItem)
    }
}
