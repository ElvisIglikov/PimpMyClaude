import XCTest
@testable import ClaudeAX

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
}
