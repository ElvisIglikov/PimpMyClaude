@testable import ClaudeAX
import XCTest

/// #10239 (слово Элвиса 19.10.2026 04:55: «Блок Workflow… вернуть таким, как он на Windows был»): разбор status.md
/// для блока (роли, модели, «обновлено»), группы и счёт, слова строк и карточки, страницы и листание — порт
/// `pimp-tray/PimpTray.cs`. Сводки — формат README PMP Tray и настоящие сводки Мака.
final class WorkflowBlockTests: XCTestCase {
    private let nb = "\u{00A0}"

    /// Сегодня в чч:мм — часы сводок «обновлено 14:05» считаются от этого дня.
    private func today(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    /// Пример README PMP Tray (по-русски).
    private let readme = """
    # 🔰 Мой проект
    обновлено 14:05

    1️⃣ Workflow — идёт 💭
    - о чём: офлайн-кеш прогноза
    - 13:40 → … · идёт 25 мин
    - шаги 2 из 3
    - прошлые шаги: планирование · 1 агент · Opus 4.1 high — план принят
    - кодинг · 2 агента · Sonnet 4.5 high 💭

    2️⃣ Workflow — запланирован ⬜
    - о чём: виджет для экрана блокировки
    - шаги 0 из 3

    Сейчас: подключаю кеш к экрану прогноза
    Ждёт пользователя: выбрать срок жизни кеша
    """

    /// Блоки настоящей сводки PimpMyClaude (docs/status.md WF269): роли одной строкой через «;».
    private let mac = """
    # ⚪PimpMyClaude
    обновлено 23:50

    1️⃣ Workflow ✅ готово
    - о чём: WF247 — ревизия всего Пимпа: 211 находок, задачи #10019–#10046, план чистки
    - 22:59 → 00:15 · 1,3 ч
    - ревизия · 11 агентов · Opus 5.5 xhigh; оспаривание · 10 агентов · xhigh; синтез · 1 агент · xhigh

    1️⃣4️⃣ Workflow ✅ готово
    - о чём: WF260 — Swift-ошибки: карточка терминалов, пузырьки, подписка, графики (1.10.31)
    - 10:47 → 11:10 (до разреза времён — см. run-файл)
    - кодинг · 1 агент · Opus 5.5 high

    2️⃣1️⃣ Workflow ✅ готово
    - о чём: WF269 — падение панели и «за 9 мин»
    - 22:31 → 23:50 · 1,3 ч
    - критик · 1 агент · Opus 5.5 high; кодинг · 5 агентов · Opus 5.5 medium; гейт · я · 🔴 **Fable 5.1 max**
    """

    private func project(_ text: String, folder: String = "/p/X", updated: Date) -> PanelProject {
        let status = PanelProjects.parse(text)
        return PanelProject(folder: folder, name: status.name, marker: status.marker, isMain: false, updated: updated,
                            now: status.now, words: [], note: "", waits: false,
                            running: status.workflows.filter { $0.state == .running || $0.state == .failed },
                            workflows: status.workflows, marathon: "", stamp: status.stamp, waitFor: status.waitFor)
    }

    // MARK: разбор

    func testReadmeRolesStampAndWords() throws {
        let now = today(14, 10)
        let p = project(readme, updated: now.addingTimeInterval(-300))
        XCTAssertEqual(p.stamp, "обновлено 14:05")
        XCTAssertEqual(p.workflows.count, 2)
        let flow = p.workflows[0]
        XCTAssertEqual(flow.state, .running)
        XCTAssertEqual(flow.roles, [
            PanelRole(name: "планирование", model: "Opus 4.1 high", agents: 1, past: true),
            PanelRole(name: "кодинг", model: "Sonnet 4.5 high", agents: 2, running: true),
        ])
        XCTAssertEqual(WorkflowBlock.currentRole(flow)?.name, "кодинг")
        XCTAssertEqual(WorkflowBlock.stages(flow), [
            .init(title: "план", who: "Opus 4.1 high", mark: .done, hot: false),
            .init(title: "кодинг", who: "Sonnet 4.5 high ×2", mark: .run, hot: false),
        ])
        let row = WorkflowBlock.Row(project: p, index: 0)
        XCTAssertEqual(WorkflowBlock.rowName(row), "офлайн-кеш прогноза")
        XCTAssertEqual(WorkflowBlock.rowRight(row, now: now).text, "кодинг · Sonnet 4.5 high")
        // «идёт 25 мин» записано в 14:05, сейчас 14:10 — 30 мин.
        XCTAssertEqual(WorkflowBlock.rowTail(row, now: now), "2 из 3 · 30\(nb)мин")
        XCTAssertEqual(WorkflowBlock.steps(row), [.done, .done, .run])
        XCTAssertEqual(WorkflowBlock.when(p, flow, now: now), "Начался 30\(nb)мин назад, в 13:40")
        XCTAssertFalse(WorkflowBlock.slim(row))

        let plan = WorkflowBlock.Row(project: p, index: 1)
        XCTAssertTrue(WorkflowBlock.slim(plan))
        XCTAssertEqual(WorkflowBlock.rowRight(plan, now: now).text, "3 шага")
        XCTAssertEqual(WorkflowBlock.when(p, plan.flow, now: now), "Ещё не начат")
        XCTAssertEqual(WorkflowBlock.steps(plan), [.plan, .plan, .plan])
        XCTAssertEqual(p.waitFor, "выбрать срок жизни кеша")
    }

    func testMacRolesBySemicolonHotAndDone() throws {
        let now = today(23, 55)
        let p = project(mac, updated: now)
        XCTAssertEqual(p.workflows.count, 3)
        XCTAssertEqual(p.workflows[0].roles.map { $0.name }, ["ревизия", "оспаривание", "синтез"],
                       "роли одной строкой через «;» — каждая своей")
        XCTAssertEqual(p.workflows[0].roles.map { $0.agents }, [11, 10, 1])
        let gate = try XCTUnwrap(p.workflows[2].roles.last)
        XCTAssertTrue(gate.me)
        XCTAssertTrue(gate.red)
        XCTAssertEqual(gate.model, "Fable 5.1 max", "без 🔴 и **")
        XCTAssertEqual(WorkflowBlock.who(gate), "я · Fable 5.1 max")
        XCTAssertTrue(WorkflowBlock.hot(gate))
        XCTAssertFalse(WorkflowBlock.hot(PanelRole(name: "x", model: "Opus 5.5 xhigh")), "xhigh — не max")
        XCTAssertTrue(WorkflowBlock.hot(PanelRole(name: "x", model: "Opus 5.5 max")))
        XCTAssertTrue(WorkflowBlock.hot(PanelRole(name: "x", model: "Fable 5.1 high")))
        XCTAssertEqual(WorkflowBlock.who(PanelRole(name: "x")), "—")

        XCTAssertEqual(WorkflowBlock.when(p, p.workflows[0], now: now), "Завершился в 00:15 · занял 1,3\(nb)ч")
        XCTAssertEqual(WorkflowBlock.when(p, p.workflows[1], now: now), "Завершился в 11:10",
                       "хвост в скобках — не длительность")
        XCTAssertEqual(WorkflowBlock.rowRight(WorkflowBlock.Row(project: p, index: 0), now: now).text, "в 00:15")
        XCTAssertEqual(WorkflowBlock.stages(p.workflows[2]).map { $0.mark }, [.done, .done, .done])

        // «WF247 — …» и «WF260 — Swift-ошибки: …» — метка Workflow, не проект-приставка.
        XCTAssertNil(WorkflowBlock.prefix(p, 0))
        XCTAssertNil(WorkflowBlock.prefix(p, 1))
        XCTAssertEqual(WorkflowBlock.rowName(WorkflowBlock.Row(project: p, index: 0)), "ревизия всего Пимпа")
        XCTAssertEqual(WorkflowBlock.rowName(WorkflowBlock.Row(project: p, index: 1)), "Swift-ошибки")
    }

    func testShortNameAndPrefix() {
        XCTAssertEqual(WorkflowBlock.shortName("offline cache for the last forecast"), "offline cache for the last")
        XCTAssertEqual(WorkflowBlock.shortName("охота за ошибками в разделе оплаты и доставки"),
                       "охота за ошибками в разделе", "не длиннее 28 знаков — по целому слову, без «…»")
        XCTAssertEqual(WorkflowBlock.shortName("проверка всех кнопок и в окнах панели"), "проверка всех кнопок",
                       "предлог и союз в хвосте — долой")
        XCTAssertEqual(WorkflowBlock.shortName("RSS feed and sitemap, Atom"), "RSS feed and sitemap")
        XCTAssertEqual(WorkflowBlock.shortName("тёмная тема (редактор)"), "тёмная тема")

        let text = """
        # Пимп
        1️⃣ Workflow ⏳ идёт
        - о чём: PMP: новая шапка панели
        2️⃣ Workflow ⬜
        - о чём: Сайт: меню
        3️⃣ Workflow ⬜
        - о чём: Сайт: корзина
        4️⃣ Workflow ⬜
        - о чём: сайт: оплата
        5️⃣ Workflow ⬜
        - о чём: разрезка 4: страница
        6️⃣ Workflow ⬜
        - о чём: Пимп: своё имя
        """
        let p = project(text, updated: Date())
        XCTAssertEqual(WorkflowBlock.prefix(p, 0), "PMP", "латинская заглавная — проект")
        XCTAssertEqual(WorkflowBlock.prefix(p, 1), "Сайт", "кириллица — проект, только когда стоит у двух и больше")
        XCTAssertEqual(WorkflowBlock.prefix(p, 2), "Сайт")
        XCTAssertNil(WorkflowBlock.prefix(p, 3), "у одного — не проект")
        XCTAssertNil(WorkflowBlock.prefix(p, 4), "разовая приставка — не проект")
        XCTAssertNil(WorkflowBlock.prefix(p, 5), "своё имя — не приставка")
        let row = WorkflowBlock.Row(project: p, index: 0)
        XCTAssertEqual(row.projectName, "PMP")
        XCTAssertEqual(WorkflowBlock.rowName(row), "новая шапка панели")
    }

    func testTimes() {
        XCTAssertEqual(WorkflowBlock.duration(1), "1\(nb)мин")
        XCTAssertEqual(WorkflowBlock.duration(59), "59\(nb)мин")
        XCTAssertEqual(WorkflowBlock.duration(60), "1\(nb)ч")
        XCTAssertEqual(WorkflowBlock.duration(102), "1,7\(nb)ч")
        XCTAssertEqual(WorkflowBlock.took("13:05 → 13:50 · 45 мин"), 45)
        XCTAssertEqual(WorkflowBlock.took("13:05 · 1 ч 20 мин"), 80)
        XCTAssertEqual(WorkflowBlock.took("13:05 · 0,5 ч"), 30)
        XCTAssertEqual(WorkflowBlock.took("13:05 → 13:50"), 0)

        let now = today(14, 0)
        // Начало впереди не дальше 3 ч — «только начат»; дальше — со вчера.
        XCTAssertEqual(WorkflowBlock.elapsed("14:30 → …", written: now, now: now), WorkflowBlock.justStarted)
        XCTAssertEqual(WorkflowBlock.elapsed("13:15 → …", written: now, now: now), "45\(nb)мин")
        XCTAssertEqual(WorkflowBlock.elapsed("без времени", written: now, now: now), "")
        XCTAssertEqual(WorkflowBlock.elapsed("13:00 → … · идёт 1,5 ч", written: now.addingTimeInterval(-600), now: now),
                       "1,7\(nb)ч", "«идёт 1,5 ч» записано 10 мин назад")

        // Одно время и длительность: конец — начало плюс длительность.
        let p = project("# A\n1️⃣ Workflow ✅\n- о чём: x\n- 12:00 · 45 мин", updated: now)
        XCTAssertEqual(WorkflowBlock.finishedAt(p, p.workflows[0], now: now), today(12, 45))
        // «обновлено 23:50», сейчас 00:10 — запись вчерашняя.
        let late = project("# B\nобновлено 23:50\n1️⃣ Workflow ✅\n- о чём: y\n- 22:00 → 23:30", updated: now)
        let midnight = today(0, 10)
        XCTAssertEqual(WorkflowBlock.written(late, now: midnight), today(23, 50).addingTimeInterval(-86_400))
        XCTAssertEqual(WorkflowBlock.finishedAt(late, late.workflows[0], now: midnight),
                       today(23, 30).addingTimeInterval(-86_400))
    }

    // MARK: группы и счёт

    private func groups(now: Date) -> (WorkflowBlock.Groups, [String: PanelProject]) {
        let blog = project("""
        # Blog Engine
        1️⃣ Workflow ✅ готово
        - о чём: импорт
        - 09:00 → 10:00
        2️⃣ Workflow 💭 идёт
        - о чём: RSS feed and sitemap
        - 11:00 → … · идёт 12 мин
        - шаги 1 из 2
        - кодинг · 1 агент · Sonnet 4.5 high
        3️⃣ Workflow ✋ ждёт
        - о чём: выбор темы
        4️⃣ Workflow ⬜
        - о чём: dark theme for the editor
        """, folder: "/p/Blog", updated: now.addingTimeInterval(-60))
        let weather = project("""
        # Weather App
        1️⃣ Workflow ✅ готово
        - о чём: каркас
        - 08:00 → 12:30
        2️⃣ Workflow 🛑 упал
        - о чём: офлайн-кеш
        3️⃣ Workflow ⬜
        - о чём: widget for the lock screen
        """, folder: "/p/Weather", updated: now.addingTimeInterval(-120))
        // Готово 2 ч назад, ничего не идёт: в «готово», не в «идут».
        let shop = project("""
        # Shop
        1️⃣ Workflow ✅ готово
        - о чём: корзина
        - 11:00 → 13:00
        """, folder: "/p/Shop", updated: now.addingTimeInterval(-2 * 3600))
        // Сводка старше суток — ни в одной группе.
        let old = project("""
        # Old
        1️⃣ Workflow ✅ готово
        - о чём: давнее
        - 10:00 → 11:00
        2️⃣ Workflow ⬜
        - о чём: когда-нибудь
        """, folder: "/p/Old", updated: now.addingTimeInterval(-30 * 3600))
        // «Идёт», но не живое (#10315): не идущий проект, и его «впереди» — не в счёте.
        let stale = PanelProject(folder: "/p/Stale", name: "Stale", marker: "", isMain: false,
                                 updated: now.addingTimeInterval(-13 * 3600), now: "", words: [], note: "", waits: false,
                                 running: [], workflows: PanelProjects.parse("""
                                 # Stale
                                 1️⃣ Workflow 💭 идёт
                                 - о чём: забытый
                                 2️⃣ Workflow ⬜
                                 - о чём: потом
                                 """).workflows)
        let snapshot = PanelSnapshot(waiting: [], working: [blog, weather], others: [shop, old, stale])
        return (WorkflowBlock.groups(snapshot, now: now), ["blog": blog, "weather": weather])
    }

    func testGroupsCountsStripAndOrder() {
        let now = today(14, 0)
        let (groups, _) = groups(now: now)
        XCTAssertEqual(groups[.run]?.map { $0.id }, ["/p/Blog#1", "/p/Blog#2", "/p/Weather#1"],
                       "идущие проекты, свежие первыми, с их ждущими и упавшими")
        XCTAssertEqual(groups[.wait]?.map { $0.id }, ["/p/Blog#2"])
        XCTAssertEqual(groups[.fail]?.map { $0.id }, ["/p/Weather#1"])
        XCTAssertEqual(groups[.done]?.map { $0.id }, ["/p/Shop#0", "/p/Weather#0", "/p/Blog#0"],
                       "готовые — по времени окончания, свежие сверху")
        XCTAssertEqual(groups[.plan]?.map { $0.id }, ["/p/Blog#3", "/p/Weather#2"], "#10315: впереди — только у идущих")

        let counts = WorkflowBlock.counts(groups)
        XCTAssertEqual(counts.map { "\($0.number) \($0.word)" }, ["3 готово", "1 идёт", "1 ждёт", "1 упал", "2 впереди"])
        XCTAssertEqual(WorkflowBlock.countsLine(groups), "3 готово · 1 идёт · 1 ждёт · 1 упал · 2 впереди")
        XCTAssertEqual(WorkflowBlock.strip(groups), [.done, .done, .done, .run, .wait, .fail, .plan, .plan])
        XCTAssertTrue(WorkflowBlock.picked(.wait, filter: .run))
        XCTAssertFalse(WorkflowBlock.picked(.done, filter: .run))

        XCTAssertEqual(WorkflowBlock.legend(counts, motion: true).map { $0.mark }, [.done, .run, .wait, .fail, .plan])
        XCTAssertEqual(WorkflowBlock.legend(counts, motion: false)[1].text, "идёт — рамочка")
        XCTAssertEqual(WorkflowBlock.legendHint(counts, under: nil, filter: .run, open: true),
                       "Нажми число — покажу только эти")
        XCTAssertEqual(WorkflowBlock.legendHint(counts, under: .done, filter: .done, open: true),
                       "Нажми выбранное ещё раз — снова идущие")
        XCTAssertEqual(WorkflowBlock.legendHint(counts, under: .run, filter: .done, open: true),
                       "Нажми число — покажу только эти; выбранное — снова идущие")

        let empty = WorkflowBlock.groups(PanelSnapshot(waiting: [], working: [], others: []), now: now)
        let zero = WorkflowBlock.counts(empty)
        XCTAssertEqual(zero.map { $0.filter }, [.done, .run, .plan], "ждёт и упал — только когда есть")
        XCTAssertTrue(zero.allSatisfy { !$0.on })
        XCTAssertEqual(WorkflowBlock.legendHint(zero, under: .done, filter: .run, open: false), "За 24 часа готовых нет")
        XCTAssertEqual(WorkflowBlock.legendHint(zero, under: nil, filter: .run, open: false), "Пока нечего показать")
    }

    func testPagesAndProjectHeads() {
        let now = today(14, 0)
        func many(_ name: String, _ count: Int, age: TimeInterval) -> PanelProject {
            let text = "# \(name)\n" + (1...count).map { "\($0)️⃣ Workflow ⏳ идёт\n- о чём: дело \($0)" }
                .joined(separator: "\n")
            return project(text, folder: "/p/" + name, updated: now.addingTimeInterval(-age))
        }
        let rows = WorkflowBlock.groups(PanelSnapshot(waiting: [], working: [many("A", 7, age: 60), many("B", 6, age: 120)],
                                                      others: []), now: now)[.run] ?? []
        XCTAssertEqual(rows.count, 13)
        XCTAssertEqual(WorkflowBlock.pages(13), 3)
        XCTAssertEqual(WorkflowBlock.pages(0), 1)
        XCTAssertEqual(WorkflowBlock.pageLabel(page: 0, count: 13), "1–5 из 13")
        XCTAssertEqual(WorkflowBlock.pageLabel(page: 2, count: 13), "11–13 из 13")
        let first = WorkflowBlock.portion(rows, page: 0)
        XCTAssertEqual(first.first, .head(name: "A", count: 7, group: "/p/A|A"), "группа начинается — со счётом")
        XCTAssertEqual(first.count, 6)
        let second = WorkflowBlock.portion(rows, page: 1)
        XCTAssertEqual(second.first, .head(name: "A", count: 0, group: "/p/A|A"), "продолжение — одно имя")
        XCTAssertEqual(second.filter { if case .head = $0 { return true } else { return false } }.count, 2)
        XCTAssertTrue(second.contains(.head(name: "B", count: 6, group: "/p/B|B")))
    }

    // MARK: состояние блока

    func testFilterPickAndCardPaging() {
        let now = today(14, 0)
        let (groups, _) = groups(now: now)
        var state = WorkflowBlock.State()
        XCTAssertTrue(state.pick(.done, open: false), "свёрнутый — раскрыть с этой группой")
        XCTAssertEqual(state.filter, .done)
        XCTAssertFalse(state.pick(.done, open: true))
        XCTAssertEqual(state.filter, .run, "то же ещё раз — снова «идут»")
        _ = state.pick(.fail, open: true)
        XCTAssertEqual(state.filter, .fail)
        state.page = 2
        _ = state.pick(.plan, open: true)
        XCTAssertEqual(state.page, 0, "другой фильтр — с первой порции")

        // Карточка «идут» листается по идущим; запланированная под «Впереди» — по запланированным.
        state = WorkflowBlock.State()
        state.card = "/p/Blog#1"
        let running = state.cardGroup(groups) ?? []
        XCTAssertEqual(running.map { $0.id }, groups[.run]?.map { $0.id })
        XCTAssertFalse(state.turn(-1, in: running), "на первой — назад никуда")
        XCTAssertTrue(state.turn(1, in: running))
        XCTAssertEqual(state.card, "/p/Blog#2")
        XCTAssertEqual(state.slide, 1)
        XCTAssertTrue(state.turn(to: 0, in: running))
        XCTAssertEqual(state.slide, -1)
        XCTAssertTrue(state.turn(to: 2, in: running))
        XCTAssertFalse(state.turn(1, in: running), "на последней — дальше не идёт")
        state.card = "/p/Weather#2"
        XCTAssertEqual(state.cardGroup(groups)?.map { $0.id }, groups[.plan]?.map { $0.id })
        state.filter = .done
        XCTAssertNil(state.cardGroup(groups), "не из группы фильтра — карточки нет")
        state.card = "/p/Gone#0"
        state.filter = .run
        XCTAssertNil(state.cardGroup(groups))

        var settle = WorkflowBlock.State()
        settle.filter = .wait
        settle.settle(WorkflowBlock.groups(PanelSnapshot(waiting: [], working: [], others: []), now: now))
        XCTAssertEqual(settle.filter, .run, "пустая группа — снова «идут»")
    }

    // MARK: обход папок

    /// Свежие за сутки не теряются за двадцатью «прочими»: по ним блок считает «готово» и «впереди». Время — днём
    /// (#10315: «готово» — только сегодняшнее, и с `Date()` тест краснел бы в первый час суток).
    func testSnapshotKeepsDayFreshBeyondTwenty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkflowBlockTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let now = today(14, 0)
        for index in 0..<24 {
            let docs = root.appendingPathComponent(String(format: "P%02d", index)).appendingPathComponent("docs")
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            let file = docs.appendingPathComponent("status.md")
            try "# P\(index)\n1️⃣ Workflow ✅ готово\n- о чём: дело\n- 10:00 → 11:00\n".write(to: file, atomically: true,
                                                                                             encoding: .utf8)
            // Первые 20 по имени — неделю назад, последние 4 — час назад.
            let age: TimeInterval = index < 20 ? 5 * 86_400 : 3600
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        let snapshot = PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: now)
        XCTAssertEqual(snapshot.others.count, 24)
        XCTAssertEqual(WorkflowBlock.groups(snapshot, now: now)[.done]?.count, 4)
    }

    /// Настоящие сводки этого Мака разбираются без падений, и у каждой строки блока — имя (кадры — в
    /// `WorkflowBlockSnapshotTests`).
    func testLiveStatusFilesParse() {
        let now = Date()
        let snapshot = PanelProjects.snapshot(root: StatusFeed.projectsRoot(), recent: [], mainEntry: nil, now: now)
        let groups = WorkflowBlock.groups(snapshot, now: now)
        for rows in groups.values {
            for row in rows {
                XCTAssertFalse(WorkflowBlock.rowName(row).isEmpty)
                _ = WorkflowBlock.when(row.project, row.flow, now: now)
                _ = WorkflowBlock.stages(row.flow)
            }
        }
    }
}
