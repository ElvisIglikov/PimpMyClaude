import XCTest
@testable import ClaudeAX

/// #10308 (слово Элвиса 19.10.2026: панель у часов — как PimpTray на Windows): шапка без тарифа, порядок блоков,
/// разовая перестановка сохранённой раскладки, датчики процессора и видеокарты; #10307 — карточка обновления в три
/// строки; #10305 — «идёт работа» коротко.
final class PanelLikeWindows10308Tests: XCTestCase {
    private let installed = StatusIcon.Patch.installed(version: "2.42304.0", loader: 8)
    private let all = Set(PanelWidget.allCases.map { $0.rawValue })

    private func suite() -> UserDefaults {
        let name = testSuiteName()
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    // MARK: шапка

    func testHeaderLineHasNoPlan() {
        XCTAssertEqual(PimpPanelText.headerLine(installed, app: "1.10.47"), "Claude 2.42304.0 · PMP 1.10.47")
        let states: [StatusIcon.Patch] = [.unknown, .claudeNotFound, .notInstalled(version: "2.42304.0"),
                                          .lost(version: "2.42304.0"), installed]
        for patch in states {
            for short in [false, true] {
                let line = PimpPanelText.headerLine(patch, app: "1.10.47", short: short)
                for word in ["Max", "Pro", "20x", "Team", "…"] { XCTAssertFalse(line.contains(word), line) }
                XCTAssertTrue(line.hasSuffix("PMP 1.10.47"), line)
            }
        }
        XCTAssertEqual(PimpPanelText.headerLine(.claudeNotFound, app: "1.10.47"), "PMP 1.10.47")
        XCTAssertEqual(PimpPanelText.headerLine(.unknown, app: "1.10.47"), "PMP 1.10.47")
        XCTAssertEqual(PimpPanelText.headerLine(.lost(version: "2.42304.0")), "Claude 2.42304.0")
    }

    func testHeaderShortVersion() {
        XCTAssertEqual(PimpPanelText.shortVersion("2.42304.0"), "2.42304")
        XCTAssertEqual(PimpPanelText.shortVersion("2.142304.10"), "2.142304")
        XCTAssertEqual(PimpPanelText.shortVersion("2.1"), "2.1", "двух чисел не трогаем")
        XCTAssertEqual(PimpPanelText.shortVersion("2"), "2")
        XCTAssertEqual(PimpPanelText.headerLine(installed, app: "1.10.47", short: true), "Claude 2.42304 · PMP 1.10.47")
        XCTAssertEqual(PimpPanelText.headerLine(.notInstalled(version: "2.42304.0"), app: "1.10.47", short: true),
                       "Claude 2.42304 · PMP 1.10.47")
    }

    // MARK: порядок блоков

    func testStandardOrderLikeWindows() {
        let standard = PanelWidgetLayout.standard
        // #10461: раскладка коллеги — «Неделя · Сброс» развёрнуты сверху, прочее свёрнутыми строками, Workflow внизу.
        XCTAssertEqual(standard.items.map { $0.id }, ["week", "reset", "limits", "fable", "temperature", "memory", "cpu", "gpu", "tokens", "colors", "workflow", "terminals"])
        XCTAssertEqual(standard.items.filter { $0.wide }.map { $0.id }, ["workflow", "terminals"])
        // С 03.11.2026 Workflow в умолчании скрыт (`docs/decisions/2026-11-03-oformlenie.md`); вернуть — «Изменить виджеты».
        XCTAssertEqual(standard.items.filter { $0.hidden }.map { $0.id }, ["workflow"])
        XCTAssertEqual(standard.items.filter { !$0.collapsed }.map { $0.id }, ["week", "reset"])
        XCTAssertEqual(standard.rows(visible: all).map { $0.map { $0.id } },
                       [["week", "reset"], ["limits", "fable"], ["temperature", "memory"], ["cpu", "gpu"],
                        ["tokens", "colors"], ["terminals"]])
        XCTAssertEqual(Set(standard.items.map { $0.id }), all, "в умолчании есть каждый блок")
    }

    func testReorderKeepsHiddenOnce() throws {
        let store = suite()
        // Раскладка до #10308 (порядок WF214): Workflow сверху, Fable скрыт, Память свёрнута, Неделя во всю ширину.
        store.set(#"[{"id":"workflow","wide":true},{"id":"week","wide":true},{"id":"reset","wide":false},"#
                  + #"{"id":"limits","wide":false},{"id":"fable","wide":false,"hidden":true},"#
                  + #"{"id":"temperature","wide":false},{"id":"memory","wide":false,"collapsed":true},"#
                  + #"{"id":"tokens","wide":true},{"id":"colors","wide":true}]"#, forKey: PanelWidgetLayout.key)
        store.set(true, forKey: PanelWidgetLayout.colorsLastKey)
        XCTAssertTrue(PanelWidgetLayout.reorderOnce(store))
        XCTAssertEqual(store.integer(forKey: PanelWidgetLayout.orderKey), PanelWidgetLayout.order)
        let moved = PanelWidgetLayout.load(store)
        XCTAssertEqual(moved.items.map { $0.id }, PanelWidgetLayout.standard.items.map { $0.id }, "новый порядок")
        XCTAssertEqual(moved.items.map { $0.wide }, PanelWidgetLayout.standard.items.map { $0.wide }, "ширины умолчания")
        XCTAssertEqual(moved.item("fable")?.hidden, true, "скрытый остаётся скрытым")
        // Workflow скрыт один раз и у сохранённых раскладок (решение 03.11.2026).
        XCTAssertEqual(moved.hidden(visible: all).map { $0.id }, ["fable", "workflow"], "и стоит в «Скрытые»")
        XCTAssertEqual(moved.items.map { $0.collapsed }, PanelWidgetLayout.standard.items.map { $0.collapsed },
                       "#10461: свёрнутость — как у коллеги")
        XCTAssertFalse(moved.items.contains { !["fable", "workflow"].contains($0.id) && $0.hidden })

        // Второй запуск — без перестановки.
        XCTAssertFalse(PanelWidgetLayout.reorderOnce(store))
        XCTAssertEqual(PanelWidgetLayout.load(store), moved)

        // Дальше порядок выбирает человек: поднял Workflow наверх — так и остаётся.
        var mine = moved
        XCTAssertTrue(mine.move("workflow", over: "week"))
        mine.save(store)
        XCTAssertFalse(PanelWidgetLayout.reorderOnce(store))
        XCTAssertEqual(PanelWidgetLayout.load(store).items.first?.id, "workflow")
    }

    func testOrderThreeOnlyFoldsTerminals() {
        let store = suite()
        store.set(3, forKey: PanelWidgetLayout.orderKey)
        // Раскладка Элвиса 22.10: «Температура» раскрыта во всю ширину, «Терминалы» развёрнуты.
        var mine = PanelWidgetLayout.standard
        mine.setCollapsed("temperature", false)
        mine.toggleWidth("temperature")
        mine.setCollapsed("terminals", false)
        mine.save(store)
        XCTAssertTrue(PanelWidgetLayout.reorderOnce(store))
        let next = PanelWidgetLayout.load(store)
        XCTAssertEqual(next.item("terminals")?.collapsed, true, "«Терминалы» свёрнуты")
        XCTAssertEqual(next.item("temperature")?.collapsed, false, "остальное — как у человека")
        XCTAssertEqual(next.item("temperature")?.wide, true)
        XCTAssertFalse(PanelWidgetLayout.reorderOnce(store), "один раз")
    }

    func testFreshInstallGetsStandard() {
        let store = suite()
        XCTAssertFalse(PanelWidgetLayout.reorderOnce(store), "переставлять нечего")
        XCTAssertEqual(store.integer(forKey: PanelWidgetLayout.orderKey), PanelWidgetLayout.order)
        XCTAssertEqual(PanelWidgetLayout.load(store), .standard)
        // Старая раскладка без скрытых и свёрнутых переезжает ровно в умолчание — ключ раскладки снимается.
        let old = suite()
        old.set(#"[{"id":"colors","wide":true},{"id":"week","wide":false}]"#, forKey: PanelWidgetLayout.key)
        XCTAssertTrue(PanelWidgetLayout.reorderOnce(old))
        XCTAssertNil(old.string(forKey: PanelWidgetLayout.key))
        XCTAssertEqual(PanelWidgetLayout.load(old), .standard)
    }

    // MARK: процессор и видеокарта

    func testCpuPercentFromTwoSnapshots() throws {
        let before = MacLoad.CPUTicks(user: 100, system: 50, idle: 300, nice: 50)
        let after = MacLoad.CPUTicks(user: 200, system: 100, idle: 600, nice: 100)
        XCTAssertEqual(try XCTUnwrap(MacLoad.cpuPercent(previous: before, current: after)), 40, accuracy: 0.001)
        XCTAssertNil(MacLoad.cpuPercent(previous: after, current: after), "тиков нет — процента нет")
        // Счётчик перешёл через ноль.
        let edge = MacLoad.CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let wrapped = MacLoad.CPUTicks(user: 10, system: 0, idle: 80, nice: 0)
        XCTAssertEqual(try XCTUnwrap(MacLoad.cpuPercent(previous: edge, current: wrapped)), 20, accuracy: 0.001)
        let idle = MacLoad.CPUTicks(user: 0, system: 0, idle: 500, nice: 0)
        XCTAssertEqual(MacLoad.cpuPercent(previous: MacLoad.CPUTicks(user: 0, system: 0, idle: 0, nice: 0), current: idle), 0)
    }

    func testGpuPercentFromIOKitDictionary() {
        let key = MacLoad.gpuKey
        XCTAssertEqual(key, "Device Utilization %")
        XCTAssertEqual(MacLoad.gpuPercent([[key: NSNumber(value: 16), "Renderer Utilization %": NSNumber(value: 12)],
                                           [key: NSNumber(value: 42)]]), 42, "самая занятая из видеокарт")
        XCTAssertEqual(MacLoad.gpuPercent([[key: NSNumber(value: 140)]]), 100)
        XCTAssertEqual(MacLoad.gpuPercent([[key: NSNumber(value: -3)]]), 0)
        XCTAssertNil(MacLoad.gpuPercent([["Renderer Utilization %": NSNumber(value: 5)]]), "ключа нет — плитки нет")
        XCTAssertNil(MacLoad.gpuPercent([]))
        XCTAssertNil(MacLoad.gpuPercent([[key: "16"]]), "не число — не читаем")
    }

    func testLoadHealthThresholds() {
        XCTAssertEqual(MacLoad.health(0), .good)
        XCTAssertEqual(MacLoad.health(69.9), .good)
        XCTAssertEqual(MacLoad.health(70), .warn)
        XCTAssertEqual(MacLoad.health(89.9), .warn)
        XCTAssertEqual(MacLoad.health(90), .bad)
        XCTAssertEqual(MacLoad.health(100), .bad)
    }

    func testLoadHistoryAppend() {
        let t0 = Date(timeIntervalSince1970: 1_791_000_000)
        func sample(_ minute: Double, _ cpu: Double?, _ gpu: Double?) -> MacLoadSample {
            MacLoadSample(at: t0.addingTimeInterval(minute * 60), cpu: cpu, gpu: gpu)
        }
        var history: [MacLoadSample] = []
        history = MacLoad.append(sample(0, nil, nil), to: history)
        XCTAssertTrue(history.isEmpty, "точка без чисел не добавляется")
        for minute in 0..<200 { history = MacLoad.append(sample(Double(minute), Double(minute % 50), nil), to: history) }
        XCTAssertEqual(history.count, MacLoad.capacity)
        XCTAssertLessThan(history.last!.at.timeIntervalSince(history.first!.at), MacLoad.window)
        // Старше 3 ч — прочь.
        let late = MacLoad.append(sample(199 + 200, 5, 5), to: history)
        XCTAssertEqual(late.count, 1)

        let short = [sample(0, 12, nil), sample(1, 30, 7), sample(2, 18, nil), sample(9, 68, 7)]
        XCTAssertEqual(MacLoad.series(short, .gpu).map { $0.value }, [7, 7])
        XCTAssertEqual(MacLoad.segments(MacLoad.series(short, .cpu).map { $0.at }), [[0, 1, 2], [3]], "сон Мака — разрыв")
        XCTAssertEqual(MacLoad.caption(short, .cpu), "за 9 мин: 12–68\u{00A0}%", "после перезапуска — не «за 3 ч»")
        XCTAssertEqual(MacLoad.caption(short, .gpu), "за 8 мин: 7\u{00A0}%")
        XCTAssertEqual(MacLoad.caption([sample(0, 12, nil)], .cpu), "")
        let full = (0...180).map { sample(Double($0), 41, nil) }
        XCTAssertEqual(MacLoad.caption(full, .cpu), "за 3 ч: 41\u{00A0}%")
        XCTAssertEqual(MacLoad.percentText(26.4), "26\u{00A0}%")
        XCTAssertEqual(MacLoad.help(short, .cpu), "Процессор: 68\u{00A0}% · опрос раз в минуту")
        XCTAssertEqual(MacLoad.help([], .gpu), "Видеокарта")
    }

    func testLoadWidgetsTitles() {
        // #10704: имена плиток короткие («Видюха»); #10993 — «Процессор» снова полным словом.
        XCTAssertEqual(PanelWidget.cpu.title, "Процессор")
        XCTAssertEqual(PanelWidget.gpu.title, "Видюха")
        for widget in [PanelWidget.cpu, .gpu] {
            XCTAssertTrue(widget.canNarrow)
            XCTAssertFalse(widget.defaultWide)
        }
        XCTAssertEqual(PanelWidget.allCases.last, .colors)
        XCTAssertEqual(MacLoad.enabledKey, "loadInPanel")
        // Раскладка без новых блоков (сохранена до #10308 и уже переставлена): они встают за «Токенами» парой.
        let layout = PanelWidgetLayout(items: [.init(id: "tokens"), .init(id: "colors")])
        let ids = layout.items.map { $0.id }
        XCTAssertEqual(ids.firstIndex(of: "cpu"), (ids.firstIndex(of: "tokens") ?? -9) + 1)
        XCTAssertEqual(ids.firstIndex(of: "gpu"), (ids.firstIndex(of: "cpu") ?? -9) + 1)
        XCTAssertTrue(layout.rows(visible: ["cpu", "gpu"]).contains { $0.map { $0.id } == ["cpu", "gpu"] })
    }

    // MARK: карточка обновления (#10307)

    func testUpdateCardButtons() {
        typealias Card = PimpPanelText.UpdateCard
        let ready = PimpPanelText.updateCard(.ready(version: "2.42304.2", question: nil), size: "374 МБ")
        XCTAssertEqual(ready, Card(version: "2.42304.2", reason: "подпись Anthropic ✓ · 374 МБ", tone: .quiet, main: .update,
                                    second: .nextLaunch))
        XCTAssertEqual(PimpPanelText.updateCard(.ready(version: "2", question: nil), size: nil)?.reason, "подпись Anthropic ✓")
        let asked = PimpPanelText.updateCard(.ready(version: "2", question: "Обновить всё равно?"), size: "374 МБ")
        XCTAssertEqual(asked?.reason, "Обновить всё равно?")
        XCTAssertEqual(asked?.tone, .warn)
        XCTAssertEqual(asked?.main, .updateAnyway)
        XCTAssertEqual(asked?.second, .wait)
        let busy = PimpPanelText.updateCard(.busy(version: "2", work: "3 Workflow · 4 терминала"), size: nil)
        XCTAssertEqual(busy?.reason, "идёт работа: 3 Workflow · 4 терминала")
        XCTAssertEqual(busy?.tone, .warn)
        XCTAssertEqual(busy?.main, .updateNow)
        XCTAssertEqual(busy?.second, .nextLaunch, "WF283: и при работе можно отложить до запуска")
        XCTAssertEqual(busy?.help, PimpPanelText.updateCardBusyHelp)
        let timely = PimpPanelText.updateCard(.timely(version: "2", reason: "окна Claude закрыты"), size: nil)
        XCTAssertEqual(timely?.reason, "самое время: окна Claude закрыты")
        XCTAssertEqual(timely?.tone, .good)
        XCTAssertEqual(timely?.main, .updateNow)
        XCTAssertEqual(timely?.second, .nextLaunch, "WF283: «При запуске» заменила «Позже»")
        XCTAssertEqual(timely?.help, PimpPanelText.updateCardHelp)
        // Подписи кнопок; все действия — те же, что были.
        XCTAssertEqual([Card.Action.update, .updateNow, .updateAnyway, .wait, .nextLaunch].map { $0.title },
                       ["Обновить сейчас", "Обновить сейчас", "Обновить всё равно", "Подождать", "При запуске"])
        // Прочие состояния — свой вид, не карточка.
        for block: PimpPanelText.UpdateBlock in [.none, .snoozed, .done(version: "2"), .failed("x"),
                                                 .installing(version: "2", step: 1), .verifying(version: "2", from: nil),
                                                 .available(version: "2", canWrite: true, note: nil)] {
            XCTAssertNil(PimpPanelText.updateCard(block, size: "374 МБ"), "\(block)")
        }
    }

    func testWorkShort() {
        let work = WorkNow(chats: 2, workflows: 3, projects: 2, terminals: 4)
        XCTAssertEqual(PimpPanelText.workShort(work), "3 Workflow · 4 терминала · 2 чата")
        XCTAssertEqual(PimpPanelText.workShort(WorkNow(chats: 1, workflows: 0, terminals: 0)), "1 чат")
        XCTAssertEqual(PimpPanelText.workShort(WorkNow(chats: 5, workflows: nil, terminals: 1)), "1 терминал · 5 чатов")
        XCTAssertNil(PimpPanelText.workShort(WorkNow(chats: 0, workflows: 0, terminals: 0)))
        XCTAssertNil(PimpPanelText.workShort(WorkNow()))
        // Карточка берёт короткую строку, когда она есть; длинная остаётся для сравнения «что идёт».
        var menu = ClaudeUpdateMenu()
        menu.downloaded(version: "2.42304.2")
        let line = PimpPanelText.workLine(work)
        let extras = PimpPanelText.UpdateExtras(workLine: line, workShort: PimpPanelText.workShort(work))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, extras),
                       .busy(version: "2.42304.2", work: "3 Workflow · 4 терминала · 2 чата"))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(workLine: line)), .busy(version: "2.42304.2", work: line ?? ""))
    }
}
