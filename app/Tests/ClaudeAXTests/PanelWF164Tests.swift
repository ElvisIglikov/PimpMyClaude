import XCTest
@testable import ClaudeAX

/// WF164 (#9082, #9083, `docs/31.html` 31.1 + 31.5): плитка «Нагрузка на память» в панели и плитки «Идут Workflow».
final class PanelWF164Tests: XCTestCase {
    private static let t0 = Date(timeIntervalSince1970: 1_791_000_000)
    private static let gb: UInt64 = 1_073_741_824

    private func sample(_ minute: Double, _ pressure: Double, _ level: MemoryPressureLevel? = .normal) -> MacMemorySample {
        MacMemorySample(at: Self.t0.addingTimeInterval(minute * 60), pressure: pressure, level: level,
                        used: 6 * Self.gb, total: 8 * Self.gb)
    }

    // MARK: память — место среди виджетов

    func testMemoryWidgetBetweenTemperatureAndTokens() {
        let ids = PanelWidget.allCases.map { $0.rawValue }
        XCTAssertEqual(Array(ids[ids.firstIndex(of: "temperature")!...].prefix(3)), ["temperature", "memory", "tokens"])
        XCTAssertEqual(PanelWidget.memory.title, "Память")
        XCTAssertTrue(PanelWidget.memory.canNarrow, "сужается, как остальные")
        // Раскладка, сохранённая до WF164 (памяти в ней нет), — память встаёт сразу под температуру.
        let old = PanelWidgetLayout(items: [.init(id: "tokens"), .init(id: "temperature", wide: false), .init(id: "colors")])
        let ids2 = old.items.map { $0.id }
        XCTAssertEqual(ids2.firstIndex(of: "memory"), ids2.firstIndex(of: "temperature")! + 1)
        XCTAssertEqual(old.item("memory")?.wide, true)
        // Раскладка до WF181 (температура и память во всю ширину) — их сужение ставит их в один ряд.
        var layout = PanelWidgetLayout(items: PanelWidget.allCases.map { .init(id: $0.rawValue, wide: $0.defaultWide) })
        layout.toggleWidth("temperature")
        layout.toggleWidth("memory")
        XCTAssertEqual(layout.rows(visible: ["temperature", "memory", "tokens"]).map { $0.map { $0.id } },
                       [["temperature", "memory"], ["tokens"]], "узкие температура и память — в один ряд")
    }

    // MARK: память — тикает в панель, только пока она открыта

    func testMonitorDeliversOnlyWhileWatched() {
        let monitor = MacMemoryMonitor()
        var delivered: [[MacMemorySample]] = []
        monitor.onUpdate = { delivered.append($0) }
        monitor.tickNow()
        monitor.tickNow()
        drainMain()
        XCTAssertTrue(delivered.isEmpty, "панель закрыта — главный поток не трогаем")
        XCTAssertEqual(monitor.watch(true).count, 2, "открыли — история за время закрытия сразу есть")
        monitor.tickNow()
        drainMain()
        XCTAssertEqual(delivered.map { $0.count }, [3], "открыта — каждое чтение уходит в панель")
        monitor.watch(false)
        monitor.tickNow()
        drainMain()
        XCTAssertEqual(delivered.count, 1, "закрыли — снова молчит")
        XCTAssertEqual(monitor.watch(true).count, 4, "но копит")
        monitor.watch(false)
    }

    private func drainMain() {
        let done = expectation(description: "main")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    // MARK: память — подписи по уровню

    func testHelpLikeActivityMonitorAndColorWords() {
        XCTAssertEqual(MacMemory.color(.normal), "зелёная")
        XCTAssertEqual(MacMemory.color(.warn), "жёлтая")
        XCTAssertEqual(MacMemory.color(.critical), "красная")
        // WF177: в ГБ занятого из всей памяти Мака.
        XCTAssertEqual(MacMemory.help([sample(0, 40), sample(1, 65.4, .warn)]),
                       "Память: занято 6 из 8 ГБ — 75 % · жёлтая, под нагрузкой")
        XCTAssertEqual(MacMemory.help([sample(0, 91, .critical)]),
                       "Память: занято 6 из 8 ГБ — 75 % · красная, не хватает")
        XCTAssertEqual(MacMemory.help([sample(0, 30, nil)]), "Память: занято 6 из 8 ГБ — 75 %")
        XCTAssertEqual(MacMemory.help([]), "Память")
        // Слово подписи — уровень последней точки, тот же, что цвет точки «сейчас» на графике.
        let mixed = [sample(0, 93, .critical), sample(60, 70, .warn), sample(120, 48, .normal)]
        XCTAssertEqual(MacMemory.captionParts(mixed).word, "в норме")
        XCTAssertEqual(MacMemory.captionParts(mixed).rest, "за 2 ч 0 мин без изменений")
    }

    func testFreshProjectsFirst() {
        func project(_ name: String, minutesAgo: Double) -> PanelProject {
            let status = PanelProjects.parse("# \(name)\n1️⃣ Workflow 💭 идёт\n- о чём: x\n")
            return PanelProject(folder: "/p/\(name)", name: name, marker: "", isMain: false,
                                updated: Self.t0.addingTimeInterval(-minutesAgo * 60), now: "", words: [], note: "",
                                waits: false, running: status.workflows, finished: [], planned: [],
                                workflows: status.workflows, marathon: "")
        }
        let snapshot = PanelSnapshot(waiting: [], working: [project("Old", minutesAgo: 90), project("New", minutesAgo: 1),
                                                            project("Mid", minutesAgo: 30)],
                                     others: [], mainEntry: nil, mainName: nil)
        XCTAssertEqual(PanelTiles.groups(snapshot, now: Self.t0)[0].tiles.map { $0.name }, ["New", "Mid", "Old"])
    }
}
