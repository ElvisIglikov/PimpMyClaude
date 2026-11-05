@testable import ClaudeAX
import XCTest

/// #10315 (слово Элвиса 19.10.2026: «Нужно выводить только актуальное»): блок Workflow — только живое. Свежесть сводки —
/// по времени изменения содержимого (`FlowSeen`), «идёт сейчас» — `PanelProjects.isLive` (содержимое за 45 мин, или за
/// 12 ч с терминалом в движении или живой страницей), «готово» — только сегодняшнее, «впереди» — только у идущих,
/// простой — одной строкой; `/digest` — поле `live`, страница — `chats().flow`.
final class FlowLive10315Tests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("flow-live-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    // MARK: помощники

    /// `<folder>/docs/status.md` с текстом и временем правки файла.
    @discardableResult
    private func status(_ folder: URL, _ text: String, mtime: Date) throws -> URL {
        let docs = folder.appendingPathComponent("docs", isDirectory: true)
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        let file = docs.appendingPathComponent("status.md")
        try Data(text.utf8).write(to: file)
        try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        return file
    }

    /// Сводка: один готовый Workflow и один идущий.
    private func running(_ name: String) -> String {
        "# \(name)\n\n1️⃣ Workflow ✅ готово\n- о чём: каркас\n- 10:00 → 11:00\n\n"
            + "2️⃣ Workflow 💭 идёт\n- о чём: дело \(name)\n- шаги 1 из 2\n- кодинг · 1 агент · Opus 5.5 high\n"
    }

    /// Память без файла; время незнакомого текста — из `origin` (живьём — git).
    private func memory(_ origin: @escaping (URL) -> Date? = { _ in nil }) -> FlowSeen {
        FlowSeen(file: nil, origin: origin)
    }

    private func snapshot(now: Date, seen: FlowSeen? = nil, terminals: Set<String> = [],
                          active: Set<String>? = nil, pages: [FlowPage] = []) -> PanelSnapshot {
        PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: now, terminals: terminals,
                               activeTerminals: active, pages: pages, seen: seen)
    }

    private func project(_ text: String, folder: String, updated: Date, live: Bool) -> PanelProject {
        let status = PanelProjects.parse(text)
        return PanelProject(folder: folder, name: status.name, marker: status.marker, isMain: false, updated: updated,
                            now: status.now, words: [], note: "", waits: false,
                            running: live ? status.workflows.filter { $0.state == .running || $0.state == .failed } : [],
                            workflows: status.workflows, marathon: "", stamp: status.stamp, waitFor: status.waitFor)
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private func day(_ offset: Int, _ hour: Int, _ minute: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return calendar.startOfDay(for: base).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    // MARK: живое правило

    func testIsLiveRule() {
        XCTAssertTrue(PanelProjects.isLive(changedAge: 44 * 60, terminal: false, page: false))
        XCTAssertFalse(PanelProjects.isLive(changedAge: 46 * 60, terminal: false, page: false), "45 мин без признаков")
        XCTAssertTrue(PanelProjects.isLive(changedAge: 11 * 3600, terminal: true, page: false))
        XCTAssertTrue(PanelProjects.isLive(changedAge: 11 * 3600, terminal: false, page: true))
        XCTAssertFalse(PanelProjects.isLive(changedAge: 13 * 3600, terminal: true, page: true),
                       "старше 12 ч не оживляют ни терминал, ни страница")
        XCTAssertFalse(PanelProjects.isLive(changedAge: .infinity, terminal: true, page: true))
    }

    /// Критерий ТЗ: свежий по содержимому; старый с новым mtime (как после checkout); старый с живым терминалом;
    /// старый без признаков. «Идут» — только первый и третий, в блоке и у значка.
    func testFourProjectsOnlyLiveRun() throws {
        let now = Date()
        let old = now.addingTimeInterval(-3 * 86_400)
        try status(root.appendingPathComponent("Fresh"), running("Fresh"), mtime: now.addingTimeInterval(-60))
        try status(root.appendingPathComponent("Checkout"), running("Checkout"), mtime: now.addingTimeInterval(-30))
        try status(root.appendingPathComponent("Terminal"), running("Terminal"), mtime: now.addingTimeInterval(-3 * 3600))
        try status(root.appendingPathComponent("Idle"), running("Idle"), mtime: now.addingTimeInterval(-3 * 3600))
        // Checkout: текст из коммита трёхдневной давности, mtime — только что.
        let seen = memory { $0.path.contains("/Checkout/") ? old : nil }
        // Сессия Idle жива, но в ней давно тихо.
        let shot = snapshot(now: now, seen: seen, terminals: ["Terminal", "Idle"], active: ["Terminal"])
        XCTAssertEqual(shot.working.map { $0.name }, ["Fresh", "Terminal"])
        let checkout = try XCTUnwrap(shot.others.first { $0.name == "Checkout" })
        XCTAssertEqual(checkout.updated?.timeIntervalSince1970 ?? 0, old.timeIntervalSince1970, accuracy: 0.01,
                       "время — содержимого, не mtime")
        XCTAssertTrue(checkout.running.isEmpty)
        XCTAssertTrue(shot.others.first { $0.name == "Idle" }?.running.isEmpty ?? false)

        let groups = WorkflowBlock.groups(shot, now: now)
        XCTAssertEqual(groups[.run]?.map { $0.project.name }, ["Fresh", "Terminal"])
        XCTAssertNil(WorkflowBlock.idleLine(groups))
        let tiles = PanelTiles.groups(shot, now: now)
        XCTAssertEqual(PanelTiles.summary(tiles), "⏳ 2 · WF 2/4", "значок — те же двое; тихая сессия Idle не «⏳»")
    }

    /// Сводка трёхдневной давности и живой терминал — не «идёт»: терминал оживляет только за 12 ч.
    func testOldStatusWithTerminalStaysQuiet() throws {
        let now = Date()
        try status(root.appendingPathComponent("Week"), running("Week"), mtime: now.addingTimeInterval(-3 * 86_400))
        let shot = snapshot(now: now, seen: memory(), terminals: ["Week"], active: ["Week"])
        XCTAssertTrue(shot.working.isEmpty)
        let groups = WorkflowBlock.groups(shot, now: now)
        XCTAssertEqual(WorkflowBlock.idleLine(groups), "Сейчас ничего не идёт")
        // Сам терминал в движении — плитка «чат в терминале» у значка, но не Workflow.
        let tiles = PanelTiles.groups(shot, now: now)
        XCTAssertEqual(tiles.first?.tiles.first?.phase, "чат в терминале")
        XCTAssertEqual(tiles.first?.tiles.first?.segments, [], "старые Workflow сводки — не в плитке терминала")
        XCTAssertEqual(PanelTiles.summary(tiles), "⏳ 1")
    }

    func testWorktreeAddWithOldStatusNotLive() throws {
        let now = Date()
        let then = now.addingTimeInterval(-2 * 86_400)
        let main = root.appendingPathComponent("Cafe", isDirectory: true)
        let tree = root.appendingPathComponent("Cafe-iiko", isDirectory: true)
        let text = running("Cafe")
        let mainFile = try status(main, text, mtime: then)
        let seen = memory()
        // Пимп видел этот текст двое суток назад.
        _ = seen.changed(text: text, url: mainFile, mtime: then, now: then)
        // `git worktree add`: тот же текст, mtime — сейчас.
        try status(tree, text, mtime: now)
        let link = main.appendingPathComponent(".git/worktrees/iiko", isDirectory: true)
        try fm.createDirectory(at: link, withIntermediateDirectories: true)
        try Data("\(tree.path)/.git\n".utf8).write(to: link.appendingPathComponent("gitdir"))
        try Data("gitdir: \(link.path)\n".utf8).write(to: tree.appendingPathComponent(".git"))

        let read = try XCTUnwrap(PanelProjects.readStatus(in: main, seen: seen, now: now))
        XCTAssertEqual(read.changed?.timeIntervalSince1970 ?? 0, then.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(read.trees, [main.standardizedFileURL.path, tree.standardizedFileURL.path])
        XCTAssertTrue(snapshot(now: now, seen: seen).working.isEmpty, "дерево со старой сводкой — не «идёт»")
        // Памяти нет (первый запуск) — git знает коммит: тот же ответ.
        XCTAssertTrue(snapshot(now: now, seen: memory { _ in then }).working.isEmpty)
        // В дереве правят сводку — идёт, и проект — главная папка.
        try status(tree, text.replacingOccurrences(of: "шаги 1 из 2", with: "шаги 2 из 2"), mtime: now)
        let live = snapshot(now: now, seen: seen)
        XCTAssertEqual(live.working.map { $0.folder }, [main.standardizedFileURL.path])
    }

    /// «Живьём»: touch без изменения содержимого через час — строки нет; правка содержимого — строка есть.
    func testTouchWithoutChangeVsEdit() throws {
        let t0 = Date().addingTimeInterval(-7200)
        let file = try status(root.appendingPathComponent("Mine"), running("Mine"), mtime: t0)
        let seen = memory()
        XCTAssertEqual(snapshot(now: t0, seen: seen).working.count, 1, "свежая правка — идёт")
        let later = t0.addingTimeInterval(3600)
        try fm.setAttributes([.modificationDate: later], ofItemAtPath: file.path)
        XCTAssertEqual(snapshot(now: later, seen: seen).working.count, 0, "touch — содержимое то же, ему час")
        try Data(running("Mine").replacingOccurrences(of: "шаги 1 из 2", with: "шаги 2 из 2").utf8).write(to: file)
        try fm.setAttributes([.modificationDate: later], ofItemAtPath: file.path)
        XCTAssertEqual(snapshot(now: later, seen: seen).working.count, 1, "правка — снова идёт")
    }

    /// Незнакомый текст: самое раннее из коммита (git), mtime и «сейчас»; знакомый — из памяти, git больше не зовётся.
    func testSeedTakesEarliestOfGitMtimeAndNow() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let url = URL(fileURLWithPath: "/p/A/docs/status.md")
        let commit = now.addingTimeInterval(-86_400)
        XCTAssertEqual(memory { _ in commit }.changed(text: "a", url: url, mtime: now, now: now), commit)
        XCTAssertEqual(memory().changed(text: "a", url: url, mtime: now.addingTimeInterval(-600), now: now),
                       now.addingTimeInterval(-600), "не в git (или правлен) — mtime")
        XCTAssertEqual(memory().changed(text: "a", url: url, mtime: now.addingTimeInterval(600), now: now), now,
                       "mtime из будущего — сейчас")
        XCTAssertEqual(memory { _ in now.addingTimeInterval(300) }.changed(text: "a", url: url,
                                                                           mtime: now.addingTimeInterval(-600), now: now),
                       now.addingTimeInterval(-600), "правлен раньше коммита — время правки")

        var calls = 0
        let seen = memory { _ in
            calls += 1
            return commit
        }
        _ = seen.changed(text: "b", url: url, mtime: now, now: now)
        let again = seen.changed(text: "b", url: URL(fileURLWithPath: "/wt/flow/docs/status.md"),
                                 mtime: now.addingTimeInterval(3600), now: now.addingTimeInterval(3600))
        XCTAssertEqual(calls, 1, "знакомый текст — из памяти")
        XCTAssertEqual(again.timeIntervalSince1970, commit.timeIntervalSince1970, accuracy: 0.01,
                       "тот же текст по другому пути — то же время")
    }

    func testFlowSeenPersistsPrunesAndSurvivesJunk() throws {
        let file = root.appendingPathComponent(FlowSeen.fileName)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let url = URL(fileURLWithPath: "/p/A/docs/status.md")
        let first = FlowSeen(file: file, origin: { _ in nil })
        let at = first.changed(text: "old", url: url, mtime: now.addingTimeInterval(-3600), now: now)
        first.flush(now: now)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
        XCTAssertEqual((try fm.attributesOfItem(atPath: file.path))[.posixPermissions] as? Int, 0o600)

        let again = FlowSeen(file: file, origin: { _ in
            XCTFail("память пережила перезапуск — git не нужен")
            return nil
        })
        XCTAssertEqual(again.changed(text: "old", url: url, mtime: now, now: now.addingTimeInterval(60)).timeIntervalSince1970,
                       at.timeIntervalSince1970, accuracy: 0.01)

        try Data("{не json".utf8).write(to: file)
        let junk = FlowSeen(file: file, origin: { _ in nil })
        XCTAssertEqual(junk.changed(text: "old", url: url, mtime: now, now: now), now, "битый файл — пустая память")

        let dayLength = 86_400.0
        let t = now.timeIntervalSince1970
        let pruned = FlowSeen.pruned(["a": FlowSeen.Entry(changed: t - 40 * dayLength, seen: t - 31 * dayLength),
                                      "b": FlowSeen.Entry(changed: t - 40 * dayLength, seen: t - dayLength)], now: now)
        XCTAssertEqual(Set(pruned.keys), ["b"], "не виденная 30 суток запись — долой, давняя, но виденная — остаётся")
        var many: [String: FlowSeen.Entry] = [:]
        for index in 0...FlowSeen.limit { many["k\(index)"] = FlowSeen.Entry(changed: t, seen: t - Double(index)) }
        let capped = FlowSeen.pruned(many, now: now)
        XCTAssertEqual(capped.count, FlowSeen.limit)
        XCTAssertNil(capped["k\(FlowSeen.limit)"], "сверх потолка уходит самая давно виденная")
    }

    // MARK: страницы и терминалы

    func testPageSignals() throws {
        let now = Date()
        let pmp = root.appendingPathComponent("PimpMyClaude")
        let rick = root.appendingPathComponent("Rick")
        try status(pmp, running("PimpMyClaude"), mtime: now.addingTimeInterval(-3 * 3600))
        try status(rick, running("Rick"), mtime: now.addingTimeInterval(-3 * 3600))
        let names = { (pages: [FlowPage]) -> [String] in
            self.snapshot(now: now, pages: pages).working.map { $0.name }
        }
        XCTAssertEqual(names([]), [], "3 ч без признаков — не идёт")
        XCTAssertEqual(names([FlowPage(folder: pmp.standardizedFileURL.path, working: true)]), ["PimpMyClaude"],
                       "работает чат в папке проекта")
        XCTAssertEqual(names([FlowPage(folder: rick.standardizedFileURL.path, project: "PimpMyClaude", running: true)]),
                       ["PimpMyClaude"], "чат Рика ведёт Workflow PMP — живой PMP, а не Rick")
        XCTAssertEqual(names([FlowPage(project: "rick", running: true)]), ["Rick"], "имя — без учёта регистра")
        XCTAssertEqual(names([FlowPage(folder: pmp.standardizedFileURL.path)]), [], "не работает и не «идёт» — не признак")
        try status(pmp, running("PimpMyClaude"), mtime: now.addingTimeInterval(-13 * 3600))
        XCTAssertEqual(names([FlowPage(project: "PimpMyClaude", running: true)]), [],
                       "сводка старше 12 ч — строка «идёт» в старом чате не оживляет")

        let candidates: [PanelProjects.LiveCandidate] = [
            (key: "/p/PMP", folder: "PimpMyClaude-dev", name: "PimpMyClaude", updated: nil, trees: ["/p/PMP", "/wt/flow"]),
            (key: "/p/Rick", folder: "Rick", name: "Rick", updated: nil, trees: ["/p/Rick"]),
        ]
        XCTAssertEqual(PanelProjects.pageOwners([FlowPage(folder: "/wt/flow", working: true)], candidates: candidates),
                       ["/p/PMP"], "чат в рабочем дереве — его проект")
        XCTAssertEqual(PanelProjects.pageOwners([FlowPage(folder: "/p/Rick", project: "Чужой", working: true)],
                                                candidates: candidates), ["/p/Rick"], "проекта из строки нет — по папке")
        XCTAssertEqual(PanelProjects.pageOwners([FlowPage(folder: "/elsewhere", working: true)], candidates: candidates), [])
    }

    func testFlowPagesBoxForgetsStale() {
        let box = FlowPagesBox()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        box.set([FlowPage(project: "A", running: true)], at: now)
        XCTAssertEqual(box.pages(now: now.addingTimeInterval(60)).count, 1)
        XCTAssertEqual(box.pages(now: now.addingTimeInterval(ChatProbe.workingSeconds + 1)), [],
                       "страницы давно молчат — не знаем, а не «идёт»")
    }

    func testTerminalActivity() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let seconds = Int(now.timeIntervalSince1970)
        let output = "rick-PimpMyClaude\t\(seconds - 600)\nrick-Rick\t\(seconds - 3 * 3600)\nrick-Old\nother\t\(seconds)\nrick-\t1\n"
        let activity = PanelTiles.terminalActivity(output)
        XCTAssertEqual(Set(activity.keys), ["PimpMyClaude", "Rick", "Old"])
        XCTAssertEqual(PanelTiles.activeTerminals(activity, now: now), ["PimpMyClaude"],
                       "движение за 45 мин; без времени — тихо")
    }

    func testProbeParsesFlow() throws {
        func entry(_ url: String, _ result: [String: Any]) -> [String: Any] {
            ["id": 1, "source": ProbeSourceFixture.metadata(url: url), "url": url, "result": result]
        }
        let answer: [String: Any] = ["at": 1, "results": [
            entry("https://claude.ai/epitaxy/local_a", ["v": 1, "nonce": "n", "kind": "main", "title": "PMP", "store": "ok",
                                                         "working": false,
                                                         "flow": ["state": "run", "project": "PimpMyClaude"]]),
            entry("about:blank", ["v": 1, "nonce": "n", "kind": "popout", "title": "Rick", "store": "ok",
                                  "flow": ["state": "done", "project": NSNull()]]),
            entry("https://claude.ai/artifact", ["v": 1, "nonce": "n", "kind": "other", "store": "skip",
                                                 "flow": ["state": "run", "project": "X"]]),
        ]]
        let pages = ChatProbe.parse(try JSONSerialization.data(withJSONObject: answer), nonce: "n", at: Date())
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].flow, PageFlow(state: "run", project: "PimpMyClaude"))
        XCTAssertEqual(pages[1].flow, PageFlow(state: "done", project: nil), "project: null — без имени")
        XCTAssertNil(pages[2].flow, "чужая страница")
        XCTAssertNil(PageFlow.parse(["state": "going"]))
        XCTAssertNil(PageFlow.parse("run"))
        XCTAssertEqual(PageFlow.parse(["state": "wait", "project": String(repeating: "я", count: 81)]),
                       PageFlow(state: "wait", project: nil), "длиннее 80 — без имени")
        XCTAssertNil(PageFlow.parse(["state": "fail", "project": "a\nb"])?.project)
    }

    // MARK: блок

    /// «Готово» — только сегодняшнее: сводка-журнал через две полуночи (как docs/status.md PMP), свежие сверху (как
    /// у кафе), вчерашняя; «впереди» и «упал» — только у живых.
    func testDoneOnlyTodayAheadOnlyLive() throws {
        let now = day(0, 9, 0)
        let log = project("""
        # ⚪PimpMyClaude
        обновлено 23:50

        1️⃣ Workflow ✅ готово
        - о чём: WF247 — ревизия
        - 22:59 → 00:15 · 1,3 ч
        2️⃣ Workflow ✅ готово
        - о чём: WF248 — гейт
        - 23:59 → 07:00 (пауза лимита 01:20–06:00)
        3️⃣ Workflow ✅ готово
        - о чём: WF249 — меню
        - 00:01 → 00:16 · 15 мин
        4️⃣ Workflow ✅ готово
        - о чём: WF250 — шапка
        - 09:25 → 09:55
        5️⃣ Workflow ✅ готово
        - о чём: WF251 — падение
        - 22:31 → 23:50 · 1,3 ч
        6️⃣ Workflow ✅ готово
        - о чём: WF252 — ночь
        - 23:58 → 00:40 · 42 мин
        """, folder: "/p/Log", updated: day(0, 0, 45), live: false)
        let cafe = project("""
        # 🟠VkusnoffKz
        обновлено 08:45
        1️⃣ Workflow ✅ готово
        - о чём: рулетка
        - 08:20 → 08:45 · 0,4 ч
        2️⃣ Workflow ✅ готово
        - о чём: баннер
        - 07:50 → 08:20 · 0,5 ч
        3️⃣ Workflow ✅ готово
        - о чём: ошибки сайта
        - 04:20 → 06:00 · 1,7 ч
        """, folder: "/p/Cafe", updated: day(0, 8, 50), live: false)
        let yesterday = project("""
        # Old
        1️⃣ Workflow ✅ готово
        - о чём: давнее
        - 10:00 → 11:00
        2️⃣ Workflow 🛑 упал
        - о чём: сборка
        3️⃣ Workflow ⬜
        - о чём: когда-нибудь
        """, folder: "/p/Old", updated: day(-1, 18, 0), live: false)
        let live = project("""
        # Live
        1️⃣ Workflow 💭 идёт
        - о чём: дело
        - 08:30 → … · идёт 20 мин
        2️⃣ Workflow ⬜
        - о чём: потом
        3️⃣ Workflow ✅ готово
        - о чём: без времени
        """, folder: "/p/Live", updated: day(0, 8, 50), live: true)
        let groups = WorkflowBlock.groups(PanelSnapshot(waiting: [], working: [live], others: [log, cafe, yesterday]),
                                          now: now)
        XCTAssertEqual(groups[.run]?.map { $0.id }, ["/p/Live#0"])
        XCTAssertEqual(groups[.fail]?.count, 0, "вчерашнего «упал» нет")
        XCTAssertEqual(groups[.plan]?.map { $0.id }, ["/p/Live#1"], "впереди — только у идущих")
        XCTAssertEqual(Set(groups[.done]?.map { $0.id } ?? []),
                       ["/p/Log#3", "/p/Log#4", "/p/Log#5", "/p/Cafe#0", "/p/Cafe#1", "/p/Cafe#2", "/p/Old#0", "/p/Live#2"],
                       "#10395: за последние 24 часа — и вчерашние позже этого часа; без времени — по времени сводки")

        let calendar = Calendar.current
        let night = try XCTUnwrap(WorkflowBlock.finishedAt(log, index: 5, now: now))
        XCTAssertTrue(calendar.isDate(night, inSameDayAs: now))
        XCTAssertEqual(calendar.component(.hour, from: night), 0)
        let paused = try XCTUnwrap(WorkflowBlock.finishedAt(log, index: 1, now: now))
        XCTAssertTrue(calendar.isDate(paused, inSameDayAs: day(-1, 12, 0)), "23:59 → 07:00 позавчера — кончился вчера")
        let first = try XCTUnwrap(WorkflowBlock.finishedAt(log, index: 0, now: now))
        XCTAssertTrue(calendar.isDate(first, inSameDayAs: day(-1, 12, 0)))
        XCTAssertNil(WorkflowBlock.finishedAt(live, index: 2, now: now), "без времени — nil")
    }

    func testIdleLineAndCountsLine() {
        let now = day(0, 14, 0)
        let empty = WorkflowBlock.groups(PanelSnapshot(waiting: [], working: [], others: []), now: now)
        XCTAssertEqual(WorkflowBlock.idleLine(empty), "Сейчас ничего не идёт")
        XCTAssertEqual(WorkflowBlock.countsLine(empty), "Сейчас ничего не идёт")
        XCTAssertEqual(WorkflowBlock.legendHint(WorkflowBlock.counts(empty), under: .done, filter: .run, open: false),
                       "За 24 часа готовых нет")

        let text = "# Shop\n1️⃣ Workflow ✅ готово\n- о чём: корзина\n- 11:00 → 12:00\n"
            + "2️⃣ Workflow ✅ готово\n- о чём: оплата\n- 12:10 → 13:00\n3️⃣ Workflow 💭 идёт\n- о чём: доставка\n"
            + "- 13:10 → … · идёт 40 мин\n4️⃣ Workflow ⬜\n- о чём: отзывы\n"
        let quiet = project(text, folder: "/p/Shop", updated: day(0, 13, 50), live: false)
        let idle = WorkflowBlock.groups(PanelSnapshot(waiting: [], working: [], others: [quiet]), now: now)
        XCTAssertEqual(WorkflowBlock.idleLine(idle), "Сейчас ничего не идёт · готово 2")
        XCTAssertEqual(WorkflowBlock.countsLine(idle), "Сейчас ничего не идёт · готово 2")

        let busy = project(text, folder: "/p/Shop", updated: day(0, 13, 50), live: true)
        let going = WorkflowBlock.groups(PanelSnapshot(waiting: [], working: [busy], others: []), now: now)
        XCTAssertNil(WorkflowBlock.idleLine(going))
        XCTAssertEqual(WorkflowBlock.countsLine(going), "2 готово · 1 идёт · 1 впереди")
    }

    /// Штамп «обновлено 10:00» — в день изменения содержимого, а не сегодняшний.
    func testWrittenAnchorsStampToContentDay() {
        let now = day(0, 14, 0)
        let stamped = project("# A\nобновлено 10:00\n1️⃣ Workflow 💭 идёт\n- о чём: x\n- 09:00 → … · идёт 60 мин\n",
                              folder: "/p/A", updated: day(-2, 10, 5), live: true)
        XCTAssertTrue(Calendar.current.isDate(WorkflowBlock.written(stamped, now: now), inSameDayAs: day(-2, 12, 0)),
                      "до #10315 «10:00» читалось сегодняшним")
        let bare = project("# B\n1️⃣ Workflow ✅\n- о чём: y\n", folder: "/p/B", updated: now.addingTimeInterval(-60),
                           live: false)
        XCTAssertEqual(WorkflowBlock.written(bare, now: now), now.addingTimeInterval(-60), "без штампа — время содержимого")
        // Штамп забыли поправить — день записи всё равно по содержимому.
        let late = project("# C\nобновлено 23:50\n1️⃣ Workflow ✅\n- о чём: z\n- 23:58 → 00:40\n", folder: "/p/C",
                           updated: day(0, 0, 45), live: false)
        let end = WorkflowBlock.finishedAt(late, index: 0, now: now)
        XCTAssertTrue(end.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false)
    }

    // MARK: `/digest`

    func testDigestLiveFieldAndWork() throws {
        let now = Date()
        try status(root.appendingPathComponent("Fresh"), running("Fresh"), mtime: now.addingTimeInterval(-60))
        try status(root.appendingPathComponent("Stale"), running("Stale"), mtime: now.addingTimeInterval(-3 * 3600))
        let store = ProjectSettingsStore(registryURL: root.appendingPathComponent("no-registry.json"))
        let items = try XCTUnwrap(ProjectsDigest.projects(root: root, now: now, settings: { store.settings(in: $0) },
                                                          terminals: [], seen: memory()))
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        XCTAssertEqual(byName["Fresh"]?.live, true)
        XCTAssertEqual(byName["Stale"]?.live, false)
        XCTAssertEqual(byName["Stale"]?.group, "идут", "старые поля и их смысл — прежние")

        let busy = try XCTUnwrap(ProjectsDigest.projects(root: root, now: now, settings: { store.settings(in: $0) },
                                                         terminals: ["Stale"], active: ["Stale"]))
        XCTAssertEqual(busy.first { $0.name == "Stale" }?.live, true, "терминал с движением")
        let idle = try XCTUnwrap(ProjectsDigest.projects(root: root, now: now, settings: { store.settings(in: $0) },
                                                         terminals: ["Stale"], active: []))
        XCTAssertEqual(idle.first { $0.name == "Stale" }?.live, false, "тихая сессия")
        XCTAssertEqual(idle.first { $0.name == "Stale" }?.terminal, true, "`terminal` — по-прежнему «сессия жива»")

        let plain = try XCTUnwrap(ProjectsDigest.projects(root: root, now: now, settings: { store.settings(in: $0) }))
        XCTAssertTrue(plain.allSatisfy { $0.live == nil })
        XCTAssertFalse(String(decoding: ProjectsDigest.json(ProjectsDigest.body(plain, now: now)), as: UTF8.self)
            .contains("\"live\""), "терминалы не спрашивали — поля нет, JSON прежний")
        let json = String(decoding: ProjectsDigest.json(ProjectsDigest.body(items, now: now)), as: UTF8.self)
        XCTAssertTrue(json.contains("\"live\":true"))
        XCTAssertTrue(json.contains("\"live\":false"))

        // Ворота обновления Claude (`WorkNow`) с #10460 — только живой прогон: застывшее «идёт» Stale — простой.
        let work = ProjectsDigest.work(ProjectsDigest.body(items, now: now), rootExists: true, now: now)
        XCTAssertEqual(work?.workflows, 1)
        XCTAssertEqual(work?.projects, 1)
    }
}
