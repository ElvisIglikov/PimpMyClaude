import XCTest
@testable import ClaudeAX

/// WF214 (#9404): «Идёт Workflow сейчас» кольцами 31.2 — что на плитке и место нового блока в раскладке виджетов
/// (первым, только во всю ширину, скрывается и переставляется, как прочие). «Ждут тебя» и точки в углу сняты словом
/// Элвиса 10.10 (#9520, #9521).
final class PanelWF214Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func flow(_ state: PanelWorkflow.State, _ about: String = "о чём") -> PanelWorkflow {
        PanelWorkflow(about: about, state: state, stepsDone: 1, stepsTotal: 3, time: "", phases: [])
    }

    private func project(_ name: String, _ flows: [PanelWorkflow], waits: Bool = false, note: String = "",
                         now text: String = "") -> PanelProject {
        PanelProject(folder: "/p/" + name, name: name, marker: "🟣", isMain: false, updated: now, now: text,
                     words: [], note: note, waits: waits,
                     running: flows.filter { $0.state == .running || $0.state == .failed },
                     workflows: flows)
    }

    private func groups(_ projects: [PanelProject], terminals: Set<String> = []) -> [PanelTileGroup] {
        var snapshot = PanelSnapshot(waiting: projects.filter { $0.running.isEmpty && $0.waits },
                                     working: projects.filter { !$0.running.isEmpty },
                                     others: projects.filter { $0.running.isEmpty && !$0.waits })
        snapshot.terminals = terminals
        return PanelTiles.groups(snapshot, now: now)
    }

    func testRunningCount() throws {
        let all = groups([
            project("Dictator", Array(repeating: flow(.done), count: 9) + Array(repeating: flow(.running), count: 3)),
            project("Pimp", [flow(.running)], waits: true, note: "файл 29"),
            project("Broken", [flow(.done), flow(.failed)]),
            project("Shell", []),
            project("Hand", [flow(.done), flow(.waiting, "макет")], waits: true),
            project("Quiet", [flow(.planned)]),
        ], terminals: ["shell"])
        let running = try XCTUnwrap(all.first { $0.group == .running }).tiles
        let tile: (String) throws -> PanelTile = { name in try XCTUnwrap(running.first { $0.name == name }) }
        XCTAssertEqual(Set(running.map { $0.name }), ["Dictator", "Pimp", "Broken", "Shell"])
        XCTAssertEqual(PanelTiles.runningCount(all), 4, "идущие Workflow всех плиток")
        XCTAssertTrue(try tile("Pimp").waits, "идёт и ждёт — пометка в подсказке")
        XCTAssertEqual([1, 2, 5, 11, 21, 22].map(PanelTiles.goes), ["идёт", "идут", "идут", "идут", "идёт", "идут"])
        XCTAssertEqual(PanelTiles.runningCount([]), 0)
    }

    func testWorkflowWidgetIsFirstWideOnlyHidableAndMovable() {
        let id = PanelWidget.workflow.rawValue
        XCTAssertEqual(PanelWidget.workflow.title, "Workflow", "#10239: имя блока — как шапка на Windows")
        // #10461: по умолчанию — свёрнутой полосой внизу, как у коллеги; под ней только «Терминалы» (#10464).
        let standard = PanelWidgetLayout.standard.items
        // С 03.11.2026 — скрыт (`docs/decisions/2026-11-03-oformlenie.md`), место то же.
        XCTAssertEqual(standard.dropLast().last, PanelWidgetLayout.Item(id: id, wide: true, hidden: true, collapsed: true))
        XCTAssertFalse(PanelWidget.workflow.canNarrow)

        // Раскладка, сохранённая до WF214 (и со снятым в WF171 блоком `tiles`): новый блок встаёт сверху, широким.
        let saved = PanelWidgetLayout(items: [.init(id: "tiles"), .init(id: "colors"), .init(id: "week", wide: false),
                                              .init(id: "limits", wide: false)])
        XCTAssertEqual(saved.items.first, PanelWidgetLayout.Item(id: id, wide: true))
        XCTAssertFalse(saved.items.contains { $0.id == "tiles" })

        var layout = PanelWidgetLayout.standard
        layout.setHidden(id, false)
        layout.toggleWidth(id)
        XCTAssertEqual(layout.item(id)?.wide, true, "уже не становится")
        let visible = Set(PanelWidget.allCases.map { $0.rawValue })
        XCTAssertTrue(layout.rows(visible: visible).contains { $0.map { $0.id } == [id] }, "своим рядом")

        layout.setHidden(id, true)
        XCTAssertFalse(layout.rows(visible: visible).contains { $0.contains { $0.id == id } })
        XCTAssertEqual(layout.hidden(visible: visible).map { $0.id }, [id])
        layout.setHidden(id, false)

        // Перетаскивание вниз, под «Токены», и Esc — как у прочих блоков.
        var drag = PanelWidgetDrag(id: id, before: layout)
        let moved = drag.step(over: PanelWidget.tokens.rawValue, in: layout)
        XCTAssertEqual(moved?.items.firstIndex { $0.id == id }, layout.items.firstIndex { $0.id == "tokens" })
        XCTAssertEqual(drag.before, layout)
    }

    /// Перетаскивание влево-вправо (31.4): половинки одного ряда меняются местами в обе стороны.
    func testHalvesSwapLeftAndRight() {
        let visible = Set(PanelWidget.allCases.map { $0.rawValue })
        let layout = PanelWidgetLayout.standard
        XCTAssertEqual(layout.rows(visible: visible)[0].map { $0.id }, ["week", "reset"])

        var right = PanelWidgetDrag(id: "week", before: layout)
        let toRight = right.step(over: "reset", in: layout)
        XCTAssertEqual(toRight?.rows(visible: visible)[0].map { $0.id }, ["reset", "week"])
        XCTAssertNil(right.step(over: "reset", in: toRight ?? layout), "над тем же соседом второй раз не меняемся")

        var left = PanelWidgetDrag(id: "reset", before: layout)
        let toLeft = left.step(over: "week", in: layout)
        XCTAssertEqual(toLeft?.rows(visible: visible)[0].map { $0.id }, ["reset", "week"])
        // Остальные ряды на месте.
        XCTAssertEqual(toLeft?.rows(visible: visible)[1].map { $0.id }, ["limits", "fable"])
    }
}
