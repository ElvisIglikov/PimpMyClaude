import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #6282: цена Workflow. Кадры для глаз: список «идут» с ценой во второй строке и у готового справа, «≈ от» у
/// неизвестной модели, карточка с «≈ $… по ценам API» и суммой проекта за 7 дней. Без цен (`flowCosts` nil) блок —
/// как был. Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class WorkflowCost6282SnapshotTests: XCTestCase {
    private let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(14 * 3600 + 10 * 60)

    private func project(_ text: String, _ folder: String) -> PanelProject {
        let status = PanelProjects.parse(text)
        return PanelProject(folder: "/p/" + folder, name: status.name, marker: status.marker, isMain: false,
                            updated: now.addingTimeInterval(-300), now: status.now, words: [], note: "", waits: false,
                            running: status.workflows.filter { $0.state == .running || $0.state == .failed },
                            workflows: status.workflows, marathon: "", stamp: status.stamp, waitFor: status.waitFor)
    }

    private var pimp: PanelProject {
        project("""
        # ⚪PimpMyClaude
        обновлено 14:05
        1️⃣ Workflow ✅ готово
        - о чём: WF270 — ручка панели
        - 09:31 → 10:50 · 1,3 ч
        - кодинг · 1 агент · Opus 5.5 xhigh
        2️⃣ Workflow 💭 идёт
        - о чём: WF271 — блок Workflow только живое
        - 13:05 → закончит в 14:50 · идёт 55 мин
        - шаги 2 из 3
        - кодинг · 3 агента · Opus 5.5 xhigh 💭
        3️⃣ Workflow 💭 идёт
        - о чём: WF272 — цена Workflow
        - 13:40 → … · идёт 25 мин
        - шаги 1 из 4
        - кодинг · 1 агент · Opus 5.5 xhigh 💭
        """, "PimpMyClaude")
    }

    private func costs(_ project: PanelProject) -> WorkflowCosts {
        let rows = project.workflows.indices.map { WorkflowBlock.Row(project: project, index: $0) }
        let known = CostTotals(input: 3170, output: 1_457_953, write: 14_196_502, read: 239_975_045, usd: 148.15)
        return WorkflowCosts(
            rows: [WorkflowCosts.key(rows[0]): WorkflowCostItem(totals: CostTotals(input: 1008, output: 385_871,
                                                                                   write: 3_299_963, read: 82_497_340, usd: 40.72)),
                   WorkflowCosts.key(rows[1]): WorkflowCostItem(totals: known),
                   WorkflowCosts.key(rows[2]): WorkflowCostItem(totals: CostTotals(output: 9000, usd: 3.1, unpriced: 2))],
            week: ["PimpMyClaude": WorkflowCostItem(totals: CostTotals(output: 3_000_000, read: 500_000_000, usd: 312.4))])
    }

    private func model(_ project: PanelProject, costs: WorkflowCosts?, setup: (PanelModel) -> Void = { _ in }) -> PanelModel {
        let model = PanelWF253Scenes.elvis(now: now)
        model.update = .none
        model.projects = PanelSnapshot(waiting: [], working: [project], others: [])
        model.flowCosts = costs
        model.accent = .violet
        setup(model)
        return model
    }

    private func render(_ model: PanelModel, _ name: String) throws {
        let width = PimpPanelController.width - 24
        let view = NSHostingView(rootView: WorkflowBlockView(model: model)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(PanelColor.ink)
            .environment(\.colorScheme, .dark)
            .environment(\.pmpAccent, PanelColor.hex(model.shownAccent.hex))
            .environment(\.panelType, .newYork))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: NSSize(width: width + 24, height: 10))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.frame.size = view.fittingSize
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        XCTAssertGreaterThan(view.bounds.height, 30, name)
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func testSnapshots() throws {
        let pimp = self.pimp
        let costs = costs(pimp)
        try render(model(pimp, costs: costs) { $0.workflowOpen = true }, "6282-1-spisok")
        try render(model(pimp, costs: costs) { model in
            model.workflowOpen = true
            model.flow.filter = .done
        }, "6282-2-gotovo")
        try render(model(pimp, costs: costs) { model in
            model.workflowOpen = true
            model.flow.card = WorkflowBlock.Row(project: pimp, index: 1).id
        }, "6282-3-kartochka")
        try render(model(pimp, costs: nil) { $0.workflowOpen = true }, "6282-4-bez-ceny")
    }
}
