@testable import ClaudeAX
import XCTest

/// #6282: цена Workflow по ценам API. Фикстуры — транскрипты Claude Code во временной папке: две модели, кэш на 5 мин и
/// на 1 ч, повторы одного ответа с растущим выходом, вложенный агент, `<synthetic>`, журнал прогона; run-файл с
/// `runs.*`; запасная привязка по времени, чужое время вне окна и спорный прогон; кэш сумм и тексты.
final class WorkflowCostTests: XCTestCase {
    private var root: URL!
    private var projects: URL!
    private let fm = FileManager.default
    /// Сегодня 12:00 — у строк сводки «10:00» начало сегодня.
    private let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("wfcost-\(UUID().uuidString)", isDirectory: true)
        projects = root.appendingPathComponent("claude-projects", isDirectory: true)
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    // MARK: помощники

    private func iso(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: date)
    }

    private func clock(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.startOfDay(for: now).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private func user(_ at: Date) -> String {
        #"{"type":"user","timestamp":"\#(iso(at))","message":{"role":"user","content":"задача"}}"#
    }

    private func reply(_ id: String, _ model: String, at: Date, input: Int = 0, output: Int = 0, w5: Int = 0, w1: Int = 0,
                       read: Int = 0, speed: String = "standard") -> String {
        #"{"type":"assistant","timestamp":"\#(iso(at))","message":{"id":"\#(id)","model":"\#(model)","usage":"#
            + #"{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(w5 + w1),"#
            + #""cache_read_input_tokens":\#(read),"cache_creation":{"ephemeral_5m_input_tokens":\#(w5),"#
            + #""ephemeral_1h_input_tokens":\#(w1)},"speed":"\#(speed)"}}}"#
    }

    /// Папка проекта со сводкой `docs/status.md`.
    private func project(_ name: String, _ text: String) throws -> (folder: URL, status: URL) {
        let folder = root.appendingPathComponent("code", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        let docs = folder.appendingPathComponent("docs", isDirectory: true)
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        let status = docs.appendingPathComponent("status.md")
        try Data(text.utf8).write(to: status)
        return (folder, status)
    }

    private func transcripts(_ folder: URL) -> URL {
        projects.appendingPathComponent(WorkflowCost.encoded(folder.standardizedFileURL.path), isDirectory: true)
    }

    /// Каталог прогона `<транскрипты>/<сессия>/subagents/workflows/<id>` и его файлы (путь внутри → строки).
    @discardableResult
    private func run(_ folder: URL, session: String, id: String, files: [String: [String]]) throws -> URL {
        let dir = transcripts(folder).appendingPathComponent(session, isDirectory: true)
            .appendingPathComponent("subagents/workflows", isDirectory: true).appendingPathComponent(id, isDirectory: true)
        for (path, lines) in files {
            let file = dir.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        }
        return dir
    }

    private func flowRows(_ folder: URL, _ status: URL) throws -> [WorkflowBlock.Row] {
        let text = try String(contentsOf: status, encoding: .utf8)
        let parsed = PanelProjects.parse(text)
        let project = PanelProject(folder: folder.standardizedFileURL.path, name: parsed.name, marker: parsed.marker,
                                   isMain: false, updated: now, now: "", words: [], note: "", waits: false, running: [],
                                   workflows: parsed.workflows, marathon: "", stamp: parsed.stamp, waitFor: "",
                                   statusFile: status.path)
        return parsed.workflows.indices.map { WorkflowBlock.Row(project: project, index: $0) }
    }

    private func store() -> WorkflowCostStore {
        WorkflowCostStore(file: root.appendingPathComponent(WorkflowCostCache.fileName), projects: projects, now: { self.now })
    }

    private func compute(_ rows: [WorkflowBlock.Row], store: WorkflowCostStore? = nil) -> WorkflowCosts {
        WorkflowCost.compute(rows: rows, shown: Set(rows.map(WorkflowCosts.key)), now: now, store: store ?? self.store())
    }

    private func usd(_ price: TokenPrice, input: Int = 0, output: Int = 0, w5: Int = 0, w1: Int = 0, read: Int = 0) -> Double {
        (Double(input) * price.input + Double(output) * price.output + Double(w5) * price.write5m
            + Double(w1) * price.write1h + Double(read) * price.read) / 1_000_000
    }

    // MARK: точная привязка и сумма

    /// Run-файл `run-wf12-…json`: верхний прогон по `script_path`, второй (`runs.b`) — без пути, найден в сессиях папки
    /// проекта. Opus 5.5 и Sonnet 5.5, кэш 5 мин и 1 ч, повтор ответа с растущим выходом, вложенный агент,
    /// `<synthetic>`, журнал прогона — не в счёт; `run-wf120-…` — чужой.
    func testExactSumFromRunFile() throws {
        let shop = try project("Shop", "# Shop\n\n1️⃣ Workflow ✅ готово\n- о чём: WF12 — корзина\n- 10:00 → 11:00 · 1 ч\n")
        let script = transcripts(shop.folder).appendingPathComponent("s1/workflows/scripts/wf12.js").path
        let runFile = #"{"run_id":"wf_aaaa-111","script_path":"\#(script)","runs":{"b":{"run_id":"wf_bbbb-222"},"#
            + #""bad":{"run_id":"../wf_x"}}}"#
        try Data(runFile.utf8).write(to: shop.status.deletingLastPathComponent().appendingPathComponent("run-wf12-2026-10-20.json"))
        try Data(#"{"run_id":"wf_cccc-333"}"#.utf8)
            .write(to: shop.status.deletingLastPathComponent().appendingPathComponent("run-wf120-2026-10-20.json"))
        let start = clock(10, 1)
        try run(shop.folder, session: "s1", id: "wf_aaaa-111", files: [
            "agent-1.jsonl": [user(start),
                              reply("m1", "claude-opus-5-5", at: start.addingTimeInterval(10), input: 3, output: 5, w5: 1000, read: 20_000),
                              reply("m1", "claude-opus-5-5", at: start.addingTimeInterval(12), input: 3, output: 500, w5: 1000, read: 20_000),
                              reply("m2", "claude-sonnet-5-5", at: start.addingTimeInterval(30), input: 7, output: 40, w1: 2000, read: 5000),
                              reply("m3", "<synthetic>", at: start.addingTimeInterval(40), output: 9999)],
            "sub/agent-2.jsonl": [user(start.addingTimeInterval(60)),
                                  reply("m4", "claude-opus-5-5", at: start.addingTimeInterval(70), input: 1, output: 100, w5: 300, w1: 700, read: 1000)],
            "journal.jsonl": [#"{"type":"result","agentId":"x","result":"\"assistant\" \"usage\""}"#],
        ])
        try run(shop.folder, session: "s2", id: "wf_bbbb-222", files: [
            "agent-3.jsonl": [user(start.addingTimeInterval(600)),
                              reply("m5", "claude-haiku-5-5", at: start.addingTimeInterval(610), input: 50, output: 60, read: 1000)],
        ])
        try run(shop.folder, session: "s3", id: "wf_cccc-333", files: [
            "agent-9.jsonl": [user(start), reply("m9", "claude-opus-5-5", at: start, output: 1_000_000)],
        ])
        let opus = try XCTUnwrap(ModelPrices.row("claude-opus-5-5")).standard
        let sonnet = try XCTUnwrap(ModelPrices.row("claude-sonnet-5-5")).standard
        let haiku = try XCTUnwrap(ModelPrices.row("claude-haiku-5-5")).standard
        let expected = usd(opus, input: 3, output: 500, w5: 1000, read: 20_000) + usd(sonnet, input: 7, output: 40, w1: 2000, read: 5000)
            + usd(opus, input: 1, output: 100, w5: 300, w1: 700, read: 1000) + usd(haiku, input: 50, output: 60, read: 1000)

        let rows = try flowRows(shop.folder, shop.status)
        let costs = compute(rows)
        let item = try XCTUnwrap(costs.cost(rows[0]))
        XCTAssertEqual(item.totals.usd, expected, accuracy: 1e-9)
        XCTAssertEqual(item.totals.input, 61)
        XCTAssertEqual(item.totals.output, 700)
        XCTAssertEqual(item.totals.write, 4000)
        XCTAssertEqual(item.totals.read, 27_000)
        XCTAssertFalse(item.partial)
        XCTAssertEqual(costs.week(rows[0])?.totals.usd ?? 0, expected, accuracy: 1e-9, "за 7 дней — те же прогоны")
    }

    func testUnknownModelGivesFrom() throws {
        let shop = try project("Shop", "# Shop\n\n1️⃣ Workflow 💭 идёт\n- о чём: корзина\n- 10:00 → …\n")
        try run(shop.folder, session: "s1", id: "wf_a-1", files: [
            "agent-1.jsonl": [user(clock(10, 2)), reply("m1", "claude-opus-5-5", at: clock(10, 3), output: 100_000),
                              reply("m2", "claude-opus-9", at: clock(10, 4), output: 100_000)],
        ])
        let rows = try flowRows(shop.folder, shop.status)
        let item = try XCTUnwrap(compute(rows).cost(rows[0]))
        XCTAssertTrue(item.partial)
        XCTAssertEqual(item.label, "≈ от $2,00")
        XCTAssertTrue(item.help.contains("Не все модели известны"), item.help)
    }

    func testNoDataNoPrice() throws {
        let shop = try project("Shop", "# Shop\n\n1️⃣ Workflow ✅ готово\n- о чём: корзина\n- 10:00 → 11:00\n"
            + "2️⃣ Workflow ✅ готово\n- о чём: WF7 — склад\n- 10:30 → 11:00\n")
        try Data(#"{"run_id":"wf_gone-1","script_path":"/Users/dev/.claude/projects/x/s/workflows/scripts/a.js"}"#.utf8)
            .write(to: shop.status.deletingLastPathComponent().appendingPathComponent("run-wf7.json"))
        let rows = try flowRows(shop.folder, shop.status)
        let costs = compute(rows)
        XCTAssertNil(costs.cost(rows[0]), "транскриптов нет — цены нет")
        XCTAssertNil(costs.cost(rows[1]), "прогон run-файла не на этом Маке — цены нет, запасная не гадает")
        XCTAssertTrue(costs.week.isEmpty)
        // Транскрипт есть, а ответов с расходом нет (прогон только начался) — тоже без цены.
        try run(shop.folder, session: "s1", id: "wf_b-1", files: ["agent-1.jsonl": [user(clock(10, 1))]])
        XCTAssertNil(compute(rows).cost(rows[0]))
    }

    // MARK: кэш

    func testCacheSkipsUnchangedFiles() throws {
        let shop = try project("Shop", "# Shop\n\n1️⃣ Workflow 💭 идёт\n- о чём: корзина\n- 10:00 → …\n")
        let dir = try run(shop.folder, session: "s1", id: "wf_a-1", files: [
            "agent-1.jsonl": [user(clock(10, 2)), reply("m1", "claude-opus-5-5", at: clock(10, 3), output: 1000)],
            "agent-2.jsonl": [user(clock(10, 2)), reply("m2", "claude-opus-5-5", at: clock(10, 3), output: 2000)],
        ])
        let rows = try flowRows(shop.folder, shop.status)
        let store = store()
        let first = compute(rows, store: store).cost(rows[0])
        XCTAssertEqual(store.reads, 2)
        XCTAssertEqual(compute(rows, store: store).cost(rows[0]), first)
        XCTAssertEqual(store.reads, 2, "второй проход файлы не перечитывает")
        // Новый ответ в одном файле — перечитан только он.
        let file = dir.appendingPathComponent("agent-2.jsonl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((reply("m3", "claude-opus-5-5", at: clock(10, 5), output: 3000) + "\n").utf8))
        try handle.close()
        let next = try XCTUnwrap(compute(rows, store: store).cost(rows[0]))
        XCTAssertEqual(store.reads, 3)
        XCTAssertEqual(next.totals.output, 6000)
        // Кэш на диске: 0600, другой процесс берёт суммы оттуда.
        store.flush()
        let cacheFile = root.appendingPathComponent(WorkflowCostCache.fileName)
        let mode = try XCTUnwrap(fm.attributesOfItem(atPath: cacheFile.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue & 0o777, 0o600)
        let again = self.store()
        XCTAssertEqual(compute(rows, store: again).cost(rows[0]), next)
        XCTAssertEqual(again.reads, 0)
    }

    func testCacheFormat() throws {
        var cache = WorkflowCostCache()
        cache.files["/a.jsonl"] = .init(mtime: 10, size: 20, seen: now.timeIntervalSince1970,
                                        totals: CostTotals(input: 1, output: 2, write: 3, read: 4, usd: 0.5, unpriced: 1))
        cache.files["/old.jsonl"] = .init(mtime: 1, size: 1, seen: now.timeIntervalSince1970 - 31 * 86_400, totals: CostTotals())
        XCTAssertEqual(WorkflowCostCache.parse(cache.encode()), cache)
        XCTAssertEqual(Array(cache.pruned(now: now).files.keys), ["/a.jsonl"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: cache.encode()) as? [String: Any])
        XCTAssertEqual(body["prices"] as? Int, ModelPrices.version)
        var stale = body
        stale["prices"] = ModelPrices.version + 1
        XCTAssertEqual(WorkflowCostCache.parse(try JSONSerialization.data(withJSONObject: stale)), WorkflowCostCache(),
                       "цены сменились — суммы пересчитать")
        XCTAssertEqual(WorkflowCostCache.parse(Data("мусор".utf8)), WorkflowCostCache())
    }

    // MARK: run-файлы

    func testRunRefsAndPaths() throws {
        let raw = #"""
        {"run_id":"wf_a-1","script_path":"/s/a.js","runs":{"x":{"run_id":"wf_b-2"},"y":{"run_id":"wf_a-1"}},
         "wave2":{"script_path":"/s/c.js","run_id":"wf_c-3"},
         "bad":[{"run_id":"../../etc"},{"run_id":"wf_d/../e"},{"run_id":"wf_"},{"run_id":42}]}
        """#
        let refs = WorkflowCost.runRefs(Data(raw.utf8))
        XCTAssertEqual(refs.map(\.id), ["wf_a-1", "wf_b-2", "wf_c-3"])
        XCTAssertEqual(refs.first?.script, "/s/a.js")
        XCTAssertNil(refs[1].script)
        XCTAssertEqual(WorkflowCost.runRefs(Data(repeating: 32, count: WorkflowCost.runFileLimit + 1)), [], "больше 1 МБ — мимо")

        try fm.createDirectory(at: projects.appendingPathComponent("-p/sess/workflows/scripts"), withIntermediateDirectories: true)
        let good = projects.appendingPathComponent("-p/sess/workflows/scripts/a.js").path
        XCTAssertEqual(WorkflowCost.sessionDir(script: good, projects: projects)?.lastPathComponent, "sess")
        XCTAssertNil(WorkflowCost.sessionDir(script: "/Users/dev/.claude/projects/-p/s/workflows/scripts/a.js", projects: projects))
        XCTAssertNil(WorkflowCost.sessionDir(script: projects.path + "/-p/../../x/s/workflows/scripts/a.js", projects: projects),
                     "«..» уводит наружу")
        XCTAssertNil(WorkflowCost.sessionDir(script: projects.path + "/-p/sess/other/a.js", projects: projects))
        XCTAssertNil(WorkflowCost.sessionDir(script: "relative/a.js", projects: projects))
        // Ссылка внутри projects, что ведёт наружу, — не наша.
        let outside = root.appendingPathComponent("outside/sess/workflows/scripts", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: projects.appendingPathComponent("-link"), withDestinationURL: root.appendingPathComponent("outside"))
        XCTAssertNil(WorkflowCost.sessionDir(script: projects.path + "/-link/sess/workflows/scripts/a.js", projects: projects))
    }

    func testWFNumberAndRunFileNames() throws {
        XCTAssertEqual(WorkflowCost.wfNumber("WF247 — ревизия"), 247)
        XCTAssertEqual(WorkflowCost.wfNumber("WF248 К1–К3 — гейт"), 248)
        XCTAssertNil(WorkflowCost.wfNumber("ревизия как в WF240"))
        XCTAssertNil(WorkflowCost.wfNumber("WFX — что-то"))
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        for name in ["run-wf24.json", "run-wf24-2026-10-11.json", "run-wf247-2026-10-11.json", "run-wf24-x.txt", "status.md"] {
            try Data("{}".utf8).write(to: docs.appendingPathComponent(name))
        }
        XCTAssertEqual(WorkflowCost.runFiles(statusFolder: docs, wf: 24, fileManager: fm).map(\.lastPathComponent),
                       ["run-wf24-2026-10-11.json", "run-wf24.json"])
    }

    func testEncodedFolderName() {
        XCTAssertEqual(WorkflowCost.encoded("/Users/dev/Код/Инструменты для ИИ/PimpMyClaude-dev"),
                       "-Users-dev------------------------PimpMyClaude-dev")
        XCTAssertEqual(WorkflowCost.encoded("/Users/dev/Projects/Rick"), "-Users-dev-Projects-Rick")
    }

    // MARK: запасная привязка

    /// Без run-файла: единственный прогон папки проекта, начавшийся в 15 мин от начала строки; чужое время — мимо.
    func testFallbackByTimeWindow() throws {
        let cafe = try project("Cafe", "# Cafe\n\n1️⃣ Workflow ✅ готово\n- о чём: меню\n- 10:00 → 10:40\n"
            + "2️⃣ Workflow ✅ готово\n- о чём: касса\n- 11:30 → 11:50\n")
        try run(cafe.folder, session: "s1", id: "wf_a-1", files: [
            "agent-1.jsonl": [user(clock(10, 5)), reply("m1", "claude-opus-5-5", at: clock(10, 6), output: 1000)],
        ])
        try run(cafe.folder, session: "s1", id: "wf_far-1", files: [
            "agent-1.jsonl": [user(clock(8, 0)), reply("m2", "claude-opus-5-5", at: clock(8, 1), output: 5000)],
        ])
        let rows = try flowRows(cafe.folder, cafe.status)
        let costs = compute(rows)
        XCTAssertEqual(costs.cost(rows[0])?.totals.output, 1000)
        XCTAssertNil(costs.cost(rows[1]), "в 11:30 ± 15 мин прогонов нет; чужой в 08:00 — вне окна")
    }

    func testTwoCandidatesOrTwoRowsGiveNothing() throws {
        let cafe = try project("Cafe", "# Cafe\n\n1️⃣ Workflow ✅ готово\n- о чём: меню\n- 10:00 → 10:40\n")
        for (id, minute) in [("wf_a-1", 3), ("wf_b-2", 8)] {
            try run(cafe.folder, session: "s1", id: id, files: [
                "agent-1.jsonl": [user(clock(10, minute)), reply("m\(minute)", "claude-opus-5-5", at: clock(10, minute), output: 10)],
            ])
        }
        var rows = try flowRows(cafe.folder, cafe.status)
        XCTAssertNil(compute(rows).cost(rows[0]), "два прогона в окне — не угадываем")

        let shop = try project("Shop", "# Shop\n\n1️⃣ Workflow ✅ готово\n- о чём: склад\n- 13:00 → 13:20\n"
            + "2️⃣ Workflow ✅ готово\n- о чём: касса\n- 13:10 → 13:30\n")
        try run(shop.folder, session: "s1", id: "wf_c-3", files: [
            "agent-1.jsonl": [user(clock(13, 5)), reply("m1", "claude-opus-5-5", at: clock(13, 5), output: 10)],
        ])
        rows = try flowRows(shop.folder, shop.status)
        let costs = compute(rows)
        XCTAssertNil(costs.cost(rows[0]), "прогон в окнах двух строк — цены нет у обеих")
        XCTAssertNil(costs.cost(rows[1]))
    }

    func testWeekSumsRecentRunsByProject() throws {
        let shop = try project("Shop", "# Shop\n\n1️⃣ Workflow ✅ готово\n- о чём: WF3 — склад\n- 10:00 → 10:20\n")
        let old = now.addingTimeInterval(-8 * 86_400)
        try Data(#"{"run_id":"wf_new-1","runs":{"a":{"run_id":"wf_old-1"}}}"#.utf8)
            .write(to: shop.status.deletingLastPathComponent().appendingPathComponent("run-wf3.json"))
        try run(shop.folder, session: "s1", id: "wf_new-1", files: [
            "agent-1.jsonl": [user(clock(10, 1)), reply("m1", "claude-opus-5-5", at: clock(10, 2), output: 1000)],
        ])
        try run(shop.folder, session: "s1", id: "wf_old-1", files: [
            "agent-1.jsonl": [user(old), reply("m2", "claude-opus-5-5", at: old, output: 9000)],
        ])
        let rows = try flowRows(shop.folder, shop.status)
        let costs = compute(rows)
        XCTAssertEqual(costs.cost(rows[0])?.totals.output, 10_000, "строке — все её прогоны")
        XCTAssertEqual(costs.week(rows[0])?.totals.output, 1000, "за 7 дней — только свежий")
    }

    /// Окно «Токены» (#6282, «графики по Workflow»): у каждой строки — её прогоны за 7 дней, дорогие первыми; строка
    /// только со старыми прогонами и спорная — мимо.
    func testWeekFlowsPerWorkflowNewestRunsOnly() throws {
        let shop = try project("Shop", "# Shop\n\n1️⃣ Workflow ✅ готово\n- о чём: WF3 — склад\n- 10:00 → 10:20\n"
            + "2️⃣ Workflow ✅ готово\n- о чём: WF4 — касса\n- 11:00 → 11:30\n"
            + "3️⃣ Workflow ✅ готово\n- о чём: WF5 — архив\n- 09:00 → 09:10\n")
        let docs = shop.status.deletingLastPathComponent()
        let old = now.addingTimeInterval(-8 * 86_400)
        try Data(#"{"run_id":"wf_new-1","runs":{"a":{"run_id":"wf_old-1"}}}"#.utf8).write(to: docs.appendingPathComponent("run-wf3.json"))
        try Data(#"{"run_id":"wf_kassa-1"}"#.utf8).write(to: docs.appendingPathComponent("run-wf4.json"))
        try Data(#"{"run_id":"wf_arch-1"}"#.utf8).write(to: docs.appendingPathComponent("run-wf5.json"))
        try run(shop.folder, session: "s1", id: "wf_new-1", files: [
            "agent-1.jsonl": [user(clock(10, 1)), reply("m1", "claude-opus-5-5", at: clock(10, 2), output: 1000)],
        ])
        try run(shop.folder, session: "s1", id: "wf_old-1", files: [
            "agent-1.jsonl": [user(old), reply("m2", "claude-opus-5-5", at: old, output: 9000)],
        ])
        try run(shop.folder, session: "s1", id: "wf_kassa-1", files: [
            "agent-1.jsonl": [user(clock(11, 1)), reply("m3", "claude-opus-5-5", at: clock(11, 2), output: 4000)],
        ])
        try run(shop.folder, session: "s1", id: "wf_arch-1", files: [
            "agent-1.jsonl": [user(old), reply("m4", "claude-opus-5-5", at: old, output: 7000)],
        ])
        let rows = try flowRows(shop.folder, shop.status)
        let flows = compute(rows).flows
        XCTAssertEqual(flows.map(\.about), ["WF4 — касса", "WF3 — склад"], "дорогие первыми; WF5 — только старый прогон")
        XCTAssertEqual(flows.map(\.item.totals.output), [4000, 1000], "WF3 — без прогона 8-дневной давности")
        XCTAssertEqual(flows.map(\.project), ["Shop", "Shop"])
        XCTAssertEqual(flows.last?.start, clock(10, 1), "начало — первая строка прогона")
        XCTAssertEqual(flows.map(\.key), [WorkflowCosts.key(rows[1]), WorkflowCosts.key(rows[0])])
    }

    /// Прогоны папки проекта за 7 дней, что не встали ни в одну строку, — в окне «Токены» под своим именем: по файлу
    /// скрипта, по `workflowName` файла состояния, иначе «Workflow без имени»; старый — мимо.
    func testWeekFlowsShowUnboundRunsByOwnName() throws {
        let cafe = try project("Cafe", "# Cafe\n\n1️⃣ Workflow ✅ готово\n- о чём: меню\n- 10:00 → 10:40\n")
        let old = now.addingTimeInterval(-8 * 86_400)
        try run(cafe.folder, session: "s1", id: "wf_menu-1", files: [
            "agent-1.jsonl": [user(clock(10, 5)), reply("m1", "claude-opus-5-5", at: clock(10, 6), output: 1000)],
        ])
        try run(cafe.folder, session: "s1", id: "wf_night-2", files: [
            "agent-1.jsonl": [user(clock(3, 0)), reply("m2", "claude-opus-5-5", at: clock(3, 1), output: 8000)],
        ])
        try run(cafe.folder, session: "s2", id: "wf_state-3", files: [
            "agent-1.jsonl": [user(clock(5, 0)), reply("m3", "claude-opus-5-5", at: clock(5, 1), output: 6000)],
        ])
        try run(cafe.folder, session: "s2", id: "wf_bare-4", files: [
            "agent-1.jsonl": [user(clock(6, 0)), reply("m4", "claude-opus-5-5", at: clock(6, 1), output: 3000)],
        ])
        try run(cafe.folder, session: "s2", id: "wf_old-5", files: [
            "agent-1.jsonl": [user(old), reply("m5", "claude-opus-5-5", at: old, output: 9000)],
        ])
        let s1 = transcripts(cafe.folder).appendingPathComponent("s1/workflows", isDirectory: true)
        let s2 = transcripts(cafe.folder).appendingPathComponent("s2/workflows", isDirectory: true)
        try fm.createDirectory(at: s1.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try fm.createDirectory(at: s2, withIntermediateDirectories: true)
        try Data("// meta".utf8).write(to: s1.appendingPathComponent("scripts/nout-kassa-night-wf_night-2.js"))
        try Data(#"{"runId":"wf_state-3","logs":[],"workflowName":"cafe-review"}"#.utf8).write(to: s2.appendingPathComponent("wf_state-3.json"))
        let rows = try flowRows(cafe.folder, cafe.status)
        let flows = compute(rows).flows
        XCTAssertEqual(flows.map(\.about), ["nout-kassa-night", "cafe-review", "Workflow без имени", "меню"])
        XCTAssertEqual(flows.map(\.item.totals.output), [8000, 6000, 3000, 1000], "строке — свой прогон, старый — мимо")
        XCTAssertEqual(Set(flows.map(\.project)), ["Cafe"])
        XCTAssertEqual(flows.first?.start, clock(3, 0))
    }

    // MARK: тексты

    func testTexts() {
        XCTAssertEqual(WorkflowCost.dollars(4.2), "$4,20")
        XCTAssertEqual(WorkflowCost.dollars(1234.5), "$1\u{00A0}235")
        let item = WorkflowCostItem(totals: CostTotals(input: 1_200_000, output: 80_000, write: 1_000_000, read: 8_000_000, usd: 4.2))
        XCTAssertEqual(item.label, "≈ $4,20")
        XCTAssertEqual(item.help, "По ценам API: вход 1,2 млн, выход 80 тыс, кэш 9,0 млн. По подписке за это отдельно не платят")
        XCTAssertEqual(WorkflowCostItem(totals: CostTotals(output: 10, usd: 0.0002)).label, "< $0,01")
        XCTAssertEqual(WorkflowCostItem(totals: CostTotals(output: 10, usd: 3.1), missing: true).label, "≈ от $3,10")
        XCTAssertTrue(WorkflowCostItem(totals: CostTotals(output: 10, usd: 3.1), missing: true).help.contains("Не все прогоны"))
    }

    // MARK: сверка с настоящим прогоном (только по переменным окружения)

    /// `PMP_COST_RUN_DIR` — каталог прогона, `PMP_COST_EXPECT_USD` — ручной подсчёт (python, уборка повторов по всему
    /// прогону): расхождение не больше 1 %.
    func testRealRunMatchesManualCount() throws {
        let env = ProcessInfo.processInfo.environment
        // Без переменных — проверять нечего (в гейте не пропуск, а пустой проход: настоящих прогонов там нет).
        guard let dir = env["PMP_COST_RUN_DIR"], let expect = env["PMP_COST_EXPECT_USD"].flatMap(Double.init) else { return }
        let store = WorkflowCostStore(file: nil, projects: projects)
        let files = WorkflowCost.runFiles(URL(fileURLWithPath: dir, isDirectory: true), fileManager: fm)
        let sum = files.reduce(CostTotals()) { $0 + (store.totals($1) ?? CostTotals()) }
        print("WorkflowCost: \(files.count) файлов, $\(sum.usd), вход \(sum.input), выход \(sum.output), запись \(sum.write), чтение \(sum.read)")
        XCTAssertEqual(sum.usd, expect, accuracy: expect * 0.01)
    }
}
