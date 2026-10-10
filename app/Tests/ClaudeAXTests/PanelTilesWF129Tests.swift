import XCTest
@testable import ClaudeAX

/// WF129 (#9043, #9077): плитки «Идут Workflow» по группам, сводка у часов, tmux, раскладка виджетов.
final class PanelTilesWF129Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let pimp = """
    # ⚪PimpMyClaude
    обновлено 21:35

    3 воркфлоу
    0 готово
    марафон «PMP в продукт», волна 2 из 4

    1️⃣ Workflow ✅ готово
    - о чём: WF128 вид будущего
    - шаги 3 из 3
    - 20:40 → 21:40 · 1 ч

    2️⃣ Workflow 💭 идёт
    - о чём: WF129 панель PMP
    - шаги 1 из 4
    - 20:40 → закончит в 23:00 · идёт 1 ч
    - кодинг · 1 агент · Opus 5.5 medium 💭
    - проверка · я · Opus 5.5 high

    3️⃣ Workflow ⬜ запланирован
    - о чём: WF130 донаты
    - шаги 0 из 2

    Сейчас: волна 2.
    Ждёт Элвиса: посмотреть файл 29
    """

    private func project(_ text: String, folder: String, updated: Date? = nil, running: Bool = true,
                         waits: Bool = false) -> PanelProject {
        let status = PanelProjects.parse(text)
        let split = PanelProjects.words(status.waitFor)
        return PanelProject(
            folder: folder, name: status.name.isEmpty ? URL(fileURLWithPath: folder).lastPathComponent : status.name,
            marker: status.marker, isMain: false, updated: updated ?? now, now: status.now, words: split.words,
            note: split.note, waits: waits,
            running: running ? status.workflows.filter { $0.state == .running || $0.state == .failed } : [],
            finished: status.workflows.filter { $0.state == .done },
            planned: status.workflows.filter { $0.state == .planned },
            workflows: status.workflows, marathon: status.marathon)
    }

    private func snapshot(working: [PanelProject] = [], waiting: [PanelProject] = [], others: [PanelProject] = [],
                          terminals: Set<String> = []) -> PanelSnapshot {
        var snapshot = PanelSnapshot(waiting: waiting, working: working, others: others, mainEntry: nil, mainName: nil)
        snapshot.terminals = terminals
        return snapshot
    }

    // MARK: разбор

    func testMarathonLineFromHeadOnly() {
        let status = PanelProjects.parse(Self.pimp)
        XCTAssertEqual(status.marathon, "марафон «PMP в продукт», волна 2 из 4")
        XCTAssertEqual(status.workflows.count, 3)
        XCTAssertEqual(PanelProjects.parse("# A\n\n1️⃣ Workflow 💭 идёт\n- марафон не тут\n").marathon, "",
                       "строка внутри блока — не марафон")
    }

    // MARK: плитки

    func testRunningTileCountPhaseAndSegments() {
        let pimp = project(Self.pimp, folder: "/p/PimpMyClaude", waits: true)
        let groups = PanelTiles.groups(snapshot(working: [pimp], terminals: ["PimpMyClaude"]), now: now,
                                       calendar: calendar)
        XCTAssertEqual(groups.map { $0.title }, ["Идут"])
        let tile = groups[0].tiles[0]
        XCTAssertEqual(tile.name, "PimpMyClaude")
        XCTAssertEqual(tile.marker, "⚪")
        XCTAssertEqual(tile.count, "Workflow 2 из 3")
        XCTAssertEqual(tile.about, "WF129 панель PMP")
        XCTAssertEqual(tile.phase, "кодинг · шаг 1 из 4")
        XCTAssertEqual(tile.segments, [.done, .running, .planned])
        XCTAssertTrue(tile.terminal)
        XCTAssertTrue(tile.waits, "идёт и ждёт — плитка в «Идут» с пометкой")
        XCTAssertEqual(tile.help, "2 · WF129 панель PMP · 1/4\nволна 2.\nЖдёт Элвиса: посмотреть файл 29",
                       "что идёт — номер, о чём, шаг (31.1)")
    }

    func testSeveralRunningNumbersAndFailedPhase() {
        let text = """
        # Dictator
        1️⃣ Workflow 💭 идёт
        - о чём: а
        2️⃣ Workflow 🛑 упал
        - о чём: б
        - кодинг · 1 агент · Opus 5.5 medium
        3️⃣ Workflow 💭 идёт
        - о чём: в
        4️⃣ Workflow 💭 идёт
        - о чём: г
        5️⃣ Workflow 💭 идёт
        - о чём: д
        """
        let tile = PanelTiles.groups(snapshot(working: [project(text, folder: "/p/Dictator")]), now: now,
                                     calendar: calendar)[0].tiles[0]
        XCTAssertEqual(tile.count, "Workflow 1, 2, 3… из 5")
        XCTAssertFalse(tile.failed, "первый идущий не упал")
        let failedFirst = """
        # X
        1️⃣ Workflow 🛑 упал
        - о чём: б
        - кодинг · 1 агент · Opus 5.5 medium
        """
        let failed = PanelTiles.groups(snapshot(working: [project(failedFirst, folder: "/p/X")]), now: now,
                                       calendar: calendar)[0].tiles[0]
        XCTAssertTrue(failed.failed)
        XCTAssertEqual(failed.phase, "кодинг · упал")
    }

    func testGroupsWaitingDoneTodayTerminalAndOrder() {
        let pimp = project(Self.pimp, folder: "/p/PimpMyClaude")
        let waiter = project("# Waiter\n1️⃣ Workflow ✅ готово\n- о чём: макет\n\nЖдёт Элвиса: «да»\n",
                             folder: "/p/Waiter", running: false, waits: true)
        let doneText = "# 🟢Done\n1️⃣ Workflow ✅ готово\n- о чём: всё\n- 10:00 → 11:00 · 1 ч\n"
        let done = project(doneText, folder: "/p/Done", running: false)
        let yesterday = project(doneText, folder: "/p/Old", updated: now.addingTimeInterval(-2 * 86_400), running: false)
        let idle = project("# Idle\n", folder: "/p/Idle", running: false)
        let shell = project("# Shell\n", folder: "/p/Shell", running: false)
        let groups = PanelTiles.groups(
            snapshot(working: [pimp], waiting: [waiter], others: [done, yesterday, idle, shell, pimp],
                     terminals: ["shell", "Nobody"]),
            now: now, calendar: calendar)
        XCTAssertEqual(groups.map { $0.title }, ["Идут", "Ждут Элвиса", "Готово сегодня"])
        XCTAssertEqual(groups[0].tiles.map { $0.name }, ["PimpMyClaude", "Shell"], "проект — один раз; терминал — в «Идут»")
        XCTAssertEqual(groups[0].tiles[1].phase, "чат в терминале")
        XCTAssertTrue(groups[0].tiles[1].terminal, "без учёта регистра")
        XCTAssertEqual(groups[1].tiles[0].phase, "ждёт Элвиса")
        XCTAssertEqual(groups[1].tiles[0].about, "да", "ждёт готового слова — оно и есть «о чём»")
        XCTAssertEqual(groups[2].tiles.map { $0.name }, ["Done"], "вчерашнее — не «сегодня»")
        XCTAssertEqual(groups[2].tiles[0].phase, "готово · 1 ч")
        XCTAssertEqual(groups[2].tiles[0].count, "готово 1 из 1")
        XCTAssertTrue(PanelTiles.groups(snapshot(others: [idle]), now: now, calendar: calendar).isEmpty)
    }

    // MARK: сводка у часов

    func testSummaryLine() {
        let pimp = project(Self.pimp, folder: "/p/PimpMyClaude")
        let waiter = project("# Waiter\n1️⃣ Workflow ✅ готово\n- о чём: макет\n\nЖдёт Элвиса: «да»\n",
                             folder: "/p/Waiter", running: false, waits: true)
        let groups = PanelTiles.groups(snapshot(working: [pimp], waiting: [waiter]), now: now, calendar: calendar)
        XCTAssertEqual(PanelTiles.summary(groups), "⏳ 1 · ✋ 1 · WF 2/4")
        XCTAssertEqual(PanelTiles.summary([]), "—")
        let done = project("# D\n1️⃣ Workflow ✅ готово\n- о чём: всё\n", folder: "/p/D", running: false)
        XCTAssertEqual(PanelTiles.summary(PanelTiles.groups(snapshot(others: [done]), now: now, calendar: calendar)), "✅ 1")
        let help = PanelTiles.summaryHelp(groups)
        XCTAssertTrue(help.hasPrefix("PMP — проекты\nИдут: PimpMyClaude — Workflow 2 из 3 · кодинг · шаг 1 из 4"), help)
        XCTAssertTrue(help.contains("Ждут Элвиса: Waiter — готово 1 из 1 · ждёт Элвиса"), help)
        XCTAssertEqual(PanelTiles.summaryHelp([]), "PMP — Workflow сейчас не идут")
    }

    func testIconProjectsLook() {
        XCTAssertFalse(StatusIcon.showsProjects(nil), "по умолчанию — неделя")
        XCTAssertTrue(StatusIcon.showsProjects("projects"))
        var base = StatusIcon.Look(mode: .week)
        base.showsNumber = true
        base.number = 40
        let look = StatusIcon.withProjects(base, summary: "⏳ 1", toolTip: "PMP — проекты")
        XCTAssertEqual(look.text, "⏳ 1")
        XCTAssertFalse(look.showsNumber)
        XCTAssertNil(look.number)
        var lost = base
        lost.mark = .patchLost
        XCTAssertEqual(StatusIcon.withProjects(lost, summary: "x", toolTip: "PMP — проекты").toolTip,
                       "PMP — патч слетел. PMP — проекты")
        var outlined = base
        outlined.outlined = true
        XCTAssertEqual(StatusIcon.withProjects(outlined, summary: "x", toolTip: "t"), outlined, "без патча — как было")
        var spinner = base
        spinner.spinner = true
        XCTAssertNil(StatusIcon.withProjects(spinner, summary: "x", toolTip: "t").text)
    }

    // MARK: tmux

    func testTerminalsFromTmuxOutput() {
        let plain = """
        rick-Dictator: 1 windows (created Thu Oct  8 20:37:34 2026)
        rick-PimpMyClaude: 1 windows (created Thu Oct  8 20:37:33 2026)
        work: 2 windows (created Thu Oct  8 20:37:32 2026)
        rick-: 1 windows
        """
        XCTAssertEqual(PanelTiles.terminals(plain), ["Dictator", "PimpMyClaude"])
        XCTAssertEqual(PanelTiles.terminals("rick-VkusnoffKz\nother\n"), ["VkusnoffKz"])
        XCTAssertEqual(PanelTiles.terminals(""), [])
    }

    // MARK: раскладка виджетов

    private func defaults() -> UserDefaults {
        let name = "PanelTilesWF129Tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testLayoutStandardLoadSaveAndGarbage() {
        let store = defaults()
        XCTAssertEqual(PanelWidgetLayout.load(store), .standard)
        XCTAssertEqual(PanelWidgetLayout.standard.items.map { $0.id },
                       ["workflow", "week", "reset", "limits", "fable", "temperature", "memory", "tokens", "colors"],
                       "WF181: как снимок 37; WF177: «Цвет Claude» — внизу; WF214: «Идёт Workflow сейчас» — сверху")
        XCTAssertEqual(PanelWidgetLayout.standard.items.filter { $0.wide }.map { $0.id }, ["workflow", "tokens", "colors"],
                       "WF181: плитки половинками по двое, «Токены» и «Цвет Claude» во всю ширину")
        var layout = PanelWidgetLayout.standard
        layout.toggleWidth("week")
        layout.move("tokens", over: "colors")
        layout.save(store)
        XCTAssertNotNil(store.string(forKey: PanelWidgetLayout.key))
        XCTAssertEqual(PanelWidgetLayout.load(store), layout)
        PanelWidgetLayout.standard.save(store)
        XCTAssertNil(store.string(forKey: PanelWidgetLayout.key), "«как было» — ключ снят")
        store.set("не json", forKey: PanelWidgetLayout.key)
        XCTAssertEqual(PanelWidgetLayout.load(store), .standard)
    }

    func testLayoutNormalizes() {
        let layout = PanelWidgetLayout(items: [
            .init(id: "temperature", wide: false), .init(id: "чужой"), .init(id: "temperature"),
            .init(id: "memory", wide: false), .init(id: "colors"),
        ])
        XCTAssertEqual(layout.items.map { $0.id },
                       ["workflow", "week", "limits", "fable", "reset", "temperature", "memory", "tokens", "colors"])
        XCTAssertEqual(layout.item("temperature")?.wide, false)
        XCTAssertEqual(layout.item("memory")?.wide, false)
    }

    /// Раскладка до WF181 — механику перестановки, ширины и рядов проверяем на ней.
    private let legacy = PanelWidgetLayout(items: PanelWidget.allCases.map { .init(id: $0.rawValue, wide: $0.defaultWide) })

    func testLayoutMoveWidthAndRows() {
        var layout = legacy
        XCTAssertTrue(layout.move("tokens", over: "week"))
        XCTAssertEqual(layout.items.prefix(3).map { $0.id }, ["workflow", "tokens", "week"])
        XCTAssertFalse(layout.move("week", over: "week"))
        XCTAssertFalse(layout.move("week", over: "нет"))
        layout = legacy
        layout.toggleWidth("week")
        layout.toggleWidth("temperature")
        let visible: Set<String> = ["colors", "week", "limits", "reset", "temperature"]
        XCTAssertEqual(layout.rows(visible: visible).map { $0.map { $0.id } },
                       [["week", "limits"], ["reset"], ["temperature"], ["colors"]])
        XCTAssertEqual(layout.rows(visible: ["week", "temperature"]).map { $0.map { $0.id } },
                       [["week", "temperature"]], "скрытый между ними не мешает паре")
        XCTAssertEqual(layout.rows(visible: ["colors", "week", "reset"]).map { $0.map { $0.id } },
                       [["week"], ["reset"], ["colors"]], "одинокий узкий — свой ряд")
        XCTAssertFalse(layout.isStandard)
    }

    func testDragStepHysteresisAndCancel() {
        let start = legacy
        var drag = PanelWidgetDrag(id: "week", before: start)
        var layout = start
        XCTAssertNil(drag.step(over: nil, in: layout))
        layout = drag.step(over: "limits", in: layout) ?? layout
        XCTAssertEqual(layout.items.prefix(3).map { $0.id }, ["workflow", "limits", "week"])
        XCTAssertNil(drag.step(over: "limits", in: layout), "пока над тем же — второй раз не меняемся")
        XCTAssertNil(drag.step(over: nil, in: layout))
        layout = drag.step(over: "limits", in: layout) ?? layout
        XCTAssertEqual(layout.items.prefix(3).map { $0.id }, ["workflow", "week", "limits"], "ушёл и вернулся — меняемся")
        drag.cancelled = true
        XCTAssertNil(drag.step(over: "week", in: layout), "после Esc не двигается")
        XCTAssertEqual(drag.before, start)
    }
}
