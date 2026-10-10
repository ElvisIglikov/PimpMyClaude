import XCTest
@testable import ClaudeAX

/// WF133 (К6 `GET /digest`): сводка проектов для ячеек Workflow в поле Рика — разбор, порядок, цвет, форма JSON,
/// ручка порта и кэш на 10 с.
final class DigestWF133Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("digest-wf133-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func project(_ name: String, _ status: String?, age: TimeInterval = 60, worktree: Bool = false,
                         settings: String? = nil) throws {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("docs"), withIntermediateDirectories: true)
        if worktree { try "gitdir: /elsewhere".write(to: folder.appendingPathComponent(".git"), atomically: true, encoding: .utf8) }
        if let settings = settings {
            try settings.write(to: folder.appendingPathComponent(".pimpmyclaude.json"), atomically: true, encoding: .utf8)
        }
        guard let status = status else { return }
        let file = folder.appendingPathComponent("docs/status.md")
        try status.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
    }

    private func digest(terminals: Set<String>? = nil) -> [DigestProject] {
        let store = ProjectSettingsStore(registryURL: root.appendingPathComponent("no-registry.json"))
        return ProjectsDigest.projects(root: root, now: now, settings: { store.settings(in: $0) },
                                       terminals: terminals) ?? []
    }

    private static let running = """
    # 🟠VkusnoffKz
    1️⃣ Workflow ✅ готово
    - о чём: корзина
    - шаги 3 из 3
    2️⃣ Workflow 💭 идёт
    - о чём: Kimi K3 и GLM читают весь код по модулям, зона за зоной, с судьёй на каждую зону и стендом
    - шаги 1 из 4
    - 01:32 → закончит в 11:00 · идёт 28 мин
    - прошлые шаги: кодинг — 1 агент
    - проверка · судья · Opus 5.5 xhigh 💭
    3️⃣ Workflow 🛑 упал
    - о чём: выкладка
    4️⃣ Workflow запланирован
    - о чём: релиз
    Сейчас: идёт проверка
    """

    func testProjectCellsStatesStepsPhaseAndClip() throws {
        try project("VkusnoffKz", Self.running)
        let item = try XCTUnwrap(digest().first)
        XCTAssertEqual(item.name, "VkusnoffKz")
        XCTAssertEqual(item.title, "VkusnoffKz")
        XCTAssertEqual(item.marker, "🟠")
        XCTAssertEqual(item.group, "идут")
        XCTAssertEqual(item.done, 1)
        XCTAssertEqual(item.total, 4)
        XCTAssertEqual(item.workflows.map { $0.n }, [1, 2, 3, 4])
        XCTAssertEqual(item.workflows.map { $0.state }, ["готово", "идёт", "упал", "впереди"])
        XCTAssertEqual(item.workflows.map { $0.steps }, ["3/3", "1/4", "", ""])
        XCTAssertEqual(item.workflows[1].phase, "проверка")
        XCTAssertEqual(item.workflows[0].phase, "", "у готового текущей фазы нет")
        XCTAssertEqual(item.workflows[1].about.count, 60)
        XCTAssertTrue(item.workflows[1].about.hasSuffix("…"))
        XCTAssertEqual(item.workflows[0].about, "корзина")
    }

    func testGroupsOrderWorktreesAndStale() throws {
        try project("bravo", Self.running)
        try project("Alpha", Self.running)
        try project("Old", Self.running, age: 2 * 86_400)
        try project("Waits", "# Waits\n1️⃣ Workflow ✅ готово\n- о чём: x\nЖдёт Элвиса: «да»\n")
        try project("Hand", "# Hand\n1️⃣ Workflow ✋ ждёт\n- о чём: y\n")
        try project("Calm", "# Calm\nЖдёт Элвиса: ничего\n")
        try project("Alpha-wf9", Self.running, worktree: true)
        try project(".hidden", Self.running)
        try project("NoStatus", nil)
        let items = digest()
        XCTAssertEqual(items.map { $0.name }, ["Alpha", "bravo", "Hand", "Waits", "Calm", "Old"])
        XCTAssertEqual(items.map { $0.group }, ["идут", "идут", "ждут", "ждут", "тихо", "тихо"])
    }

    func testColorFromProjectThemeElseStableAutoColor() throws {
        try project("Painted", "# Painted\n", settings: ##"{"pimpmyclaude":1,"theme":{"id":"x","palette":{"accent":"#A1B2C3"}}}"##)
        try project("Plain", "# Plain\n")
        try project("Junk", "# Junk\n", settings: #"{"theme":{"id":"x","palette":{"accent":"red"}}}"#)
        let items = Dictionary(uniqueKeysWithValues: digest().map { ($0.name, $0.color) })
        XCTAssertEqual(items["Painted"], "#a1b2c3")
        let auto = AutoPaint.projectTheme(folderName: "Plain").palette["accent"]
        XCTAssertEqual(items["Plain"], auto)
        XCTAssertEqual(items["Junk"], AutoPaint.projectTheme(folderName: "Junk").palette["accent"])
        for color in items.values { XCTAssertNotNil(color.range(of: "^#[0-9a-f]{6}$", options: .regularExpression)) }
    }

    func testJsonShapeAndReadError() throws {
        try project("VkusnoffKz", Self.running)
        let data = ProjectsDigest.json(ProjectsDigest.body(digest(), now: now))
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(top.keys), ["v", "at", "projects"])
        XCTAssertEqual(top["v"] as? Int, 1)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: top["at"] as? String ?? ""))
        let item = try XCTUnwrap((top["projects"] as? [[String: Any]])?.first)
        // К-DG (WF214): у сводки есть «Сейчас:» — добавилось `now`; терминалы не спрашивали — `terminal` нет.
        XCTAssertEqual(Set(item.keys), ["name", "title", "marker", "color", "group", "done", "total", "workflows", "at",
                                        "now"])
        let cell = try XCTUnwrap((item["workflows"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(cell.keys), ["n", "state", "about", "steps", "phase"])

        let missing = ProjectsDigest.projects(root: root.appendingPathComponent("nope"), now: now, settings: { _ in nil })
        XCTAssertNil(missing)
        let error = try XCTUnwrap(JSONSerialization.jsonObject(
            with: ProjectsDigest.json(ProjectsDigest.body(missing, now: now))) as? [String: Any])
        XCTAssertEqual(error["v"] as? Int, 1)
        XCTAssertEqual((error["projects"] as? [Any])?.count, 0)
        XCTAssertNil(error["at"])
    }

    // MARK: К-DG (WF214) — необязательные поля

    func testDigestAdditionNowWaitWhenRoleAndTerminal() throws {
        try project("VkusnoffKz", Self.running)
        try project("Coding", """
        # ⚪Coding
        1️⃣ Workflow 💭 идёт
        - о чём: плитка
        - шаги 1 из 3
        - 13:05 → закончит в 13:50 · идёт 25 мин
        - планирование · я · Opus 5.5 high
        - кодинг · 2 агента · Opus 5.5 medium 💭
        Сейчас: кодинг идёт.
        Ждёт Элвиса: «да» макету.
        """)
        try project("Calm", "# Calm\nЖдёт Элвиса: ничего\n")
        try project("OnlyTerminal", nil)
        try project("NoTerminal", nil)
        let items = Dictionary(uniqueKeysWithValues: digest(terminals: ["coding", "OnlyTerminal"]).map { ($0.name, $0) })
        XCTAssertEqual(Set(items.keys), ["VkusnoffKz", "Coding", "Calm", "OnlyTerminal"])

        let coding = try XCTUnwrap(items["Coding"])
        XCTAssertEqual(coding.now, "кодинг идёт.")
        XCTAssertEqual(coding.wait, "«да» макету.")
        XCTAssertEqual(coding.terminal, true, "сессия rick-coding — регистр не важен")
        XCTAssertEqual(coding.workflows[0].when, "13:05 → закончит в 13:50 · идёт 25 мин")
        XCTAssertEqual(coding.workflows[0].role, "кодинг · 2 агента", "без модели и эффорта")
        XCTAssertEqual(coding.workflows[0].phase, "кодинг")

        let vkusnoff = try XCTUnwrap(items["VkusnoffKz"])
        XCTAssertEqual(vkusnoff.terminal, false)
        XCTAssertEqual(vkusnoff.now, "идёт проверка")
        XCTAssertNil(vkusnoff.wait)
        XCTAssertEqual(vkusnoff.workflows.map { $0.when }, [nil, "01:32 → закончит в 11:00 · идёт 28 мин", nil, nil])
        XCTAssertEqual(vkusnoff.workflows.map { $0.role }, [nil, "проверка", nil, nil])

        XCTAssertNil(items["Calm"]?.wait, "«ничего» — не ждёт")
        XCTAssertNil(items["Calm"]?.now)

        // Терминал жив, сводки нет — проект в ответе, без Workflow.
        let bare = try XCTUnwrap(items["OnlyTerminal"])
        XCTAssertEqual(bare.terminal, true)
        XCTAssertEqual(bare.title, "OnlyTerminal")
        XCTAssertEqual(bare.group, "тихо")
        XCTAssertEqual(bare.total, 0)
        XCTAssertTrue(bare.workflows.isEmpty)
        XCTAssertEqual(bare.at, "")
    }

    /// Прежние поля — те же значения и те же ключи; новое только добавляется, пустое в JSON не попадает.
    func testDigestAdditionKeepsOldShape() throws {
        try project("VkusnoffKz", Self.running)
        try project("Bare", "# Bare\n1️⃣ Workflow ✅ готово\n- о чём: x\n")
        let old = digest(), new = digest(terminals: [])
        for (before, after) in zip(old, new) {
            XCTAssertEqual([before.name, before.title, before.marker, before.color, before.group, before.at],
                           [after.name, after.title, after.marker, after.color, after.group, after.at])
            XCTAssertEqual([before.done, before.total], [after.done, after.total])
            XCTAssertEqual(before.workflows, after.workflows)
            XCTAssertNil(before.terminal)
            XCTAssertEqual(after.terminal, false)
        }
        let top = try XCTUnwrap(JSONSerialization.jsonObject(
            with: ProjectsDigest.json(ProjectsDigest.body(old, now: now))) as? [String: Any])
        XCTAssertEqual(top["v"] as? Int, 1)
        let bare = try XCTUnwrap((top["projects"] as? [[String: Any]])?.first { $0["name"] as? String == "Bare" })
        XCTAssertEqual(Set(bare.keys), ["name", "title", "marker", "color", "group", "done", "total", "workflows", "at"])
        XCTAssertEqual(Set(try XCTUnwrap((bare["workflows"] as? [[String: Any]])?.first).keys),
                       ["n", "state", "about", "steps", "phase"])
        // Старый читатель (без новых полей в типе) и JSON без них читаются одинаково.
        let plain = ##"{"v":1,"projects":[{"name":"A","title":"A","marker":"","color":"#000000","group":"тихо","done":0,"##
            + ##""total":1,"workflows":[{"n":1,"state":"идёт","about":"x","steps":"","phase":""}],"at":""}]}"##
        let decoded = try JSONDecoder().decode(DigestBody.self, from: Data(plain.utf8))
        XCTAssertNil(decoded.projects[0].terminal)
        XCTAssertNil(decoded.projects[0].workflows[0].when)
    }

    // MARK: К-KO (WF214) — `GET /kickoff`

    func testKickoffRouteAccessAndResponse() throws {
        XCTAssertTrue(HtmlChromeOpener.parseKickoff(head("/kickoff")))
        XCTAssertFalse(HtmlChromeOpener.parseKickoff(head("/kickoffs")))
        XCTAssertFalse(HtmlChromeOpener.parseKickoff(head("/kickoff", method: "POST")))
        XCTAssertFalse(HtmlChromeOpener.parseDigest(head("/kickoff")))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/kickoff"), token: nil), .browser(preflight: false))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/kickoff", origin: "https://evil.test"), token: nil), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/kickoff", origin: nil), token: nil), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/kickoff", method: "POST"), token: nil), .reject(405))
        XCTAssertEqual(HtmlChromeOpener.checkPage("OPTIONS /kickoff HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n"
            + "Origin: https://claude.ai\r\nAccess-Control-Request-Method: GET\r\n\r\n", token: nil), .browser(preflight: true))

        // Текст — тот, что отдаёт `WorkflowKit.kickoff` (здесь из своей папки), байт в байт.
        try "Кикофф 🚀\nстрока".write(to: root.appendingPathComponent(WorkflowKit.kickoffName), atomically: true, encoding: .utf8)
        let kickoff = try XCTUnwrap(WorkflowKit.kickoff(directory: root))
        let text = String(decoding: HtmlChromeOpener.kickoffResponse(kickoff, access: .browser(preflight: false)), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Type: text/plain; charset=utf-8\r\n"))
        XCTAssertTrue(text.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"))
        XCTAssertTrue(text.contains("Content-Length: \(kickoff.utf8.count)\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\nКикофф 🚀\nстрока"))
        XCTAssertFalse(String(decoding: HtmlChromeOpener.kickoffResponse(kickoff, access: .native), as: UTF8.self)
            .contains("Access-Control"))

        // Текста нет — 404 без тела.
        XCTAssertNil(WorkflowKit.kickoff(directory: root.appendingPathComponent("nope")))
        let missing = String(decoding: HtmlChromeOpener.kickoffResponse(nil, access: .browser(preflight: false)), as: UTF8.self)
        XCTAssertTrue(missing.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(missing.contains("Content-Length: 0\r\n"))
        XCTAssertFalse(missing.contains("Content-Type"))
        XCTAssertTrue(missing.hasSuffix("\r\n\r\n"))
    }

    // MARK: ручка порта

    private func head(_ target: String = "/digest", origin: String? = "https://claude.ai", method: String = "GET") -> String {
        "\(method) \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n" } ?? "") + "\r\n"
    }

    func testDigestRouteAccessAndResponse() {
        XCTAssertTrue(HtmlChromeOpener.parseDigest(head()))
        XCTAssertFalse(HtmlChromeOpener.parseDigest(head("/digests")))
        XCTAssertFalse(HtmlChromeOpener.parseDigest(head(method: "POST")))
        XCTAssertFalse(HtmlChromeOpener.parsePanel(head()))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(), token: nil), .browser(preflight: false))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(origin: "https://evil.test"), token: nil), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(origin: nil), token: nil), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(method: "POST"), token: nil), .reject(405))
        XCTAssertEqual(HtmlChromeOpener.checkPage("OPTIONS /digest HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n"
            + "Origin: https://claude.ai\r\nAccess-Control-Request-Method: GET\r\n\r\n", token: nil), .browser(preflight: true))

        let body = Data(#"{"v":1}"#.utf8)
        let text = String(decoding: HtmlChromeOpener.digestResponse(body, access: .browser(preflight: false)), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Type: application/json; charset=utf-8\r\n"))
        XCTAssertTrue(text.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 7\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{\"v\":1}"))
        let native = String(decoding: HtmlChromeOpener.digestResponse(body, access: .native), as: UTF8.self)
        XCTAssertFalse(native.contains("Access-Control"))
    }

    // MARK: кэш

    func testCacheBuildsAtMostOncePerTenSecondsOffTheCaller() {
        let cache = ProjectsDigestCache()
        var clock = now
        var builds = 0
        cache.now = { clock }
        cache.build = { builds += 1; return Data("\(builds)".utf8) }
        var got: [String] = []
        let lock = NSLock()
        let take: (Data) -> Void = { data in lock.lock(); got.append(String(decoding: data, as: UTF8.self)); lock.unlock() }
        cache.get(take)
        cache.get(take)
        cache.drain()
        XCTAssertEqual(builds, 1, "запросы во время сборки ждут её же")
        cache.get(take)
        clock = now.addingTimeInterval(9)
        cache.get(take)
        XCTAssertEqual(builds, 1)
        clock = now.addingTimeInterval(11)
        cache.get(take)
        cache.drain()
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(got, ["1", "1", "1", "1", "2"])
    }
}
