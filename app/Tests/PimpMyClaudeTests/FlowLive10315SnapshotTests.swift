import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #10315: блок Workflow — только живое. Кадры для глаз: простой одной строкой («Сейчас ничего не идёт · сегодня
/// готово 2»), пусто и «только живое» (раскрыт: идущий проект, старое «идёт» соседа не в счёте). Пишутся, только когда
/// задан `PMP_SNAPSHOT_DIR`.
final class FlowLive10315SnapshotTests: XCTestCase {
    private let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(14 * 3600 + 10 * 60)

    private func project(_ text: String, _ folder: String, age minutes: Double, live: Bool) -> PanelProject {
        let status = PanelProjects.parse(text)
        let running = live ? status.workflows.filter { $0.state == .running || $0.state == .failed } : []
        return PanelProject(folder: "/p/" + folder, name: status.name, marker: status.marker, isMain: false,
                            updated: now.addingTimeInterval(-60 * minutes), now: status.now, words: [], note: "",
                            waits: false, running: running, workflows: status.workflows, marathon: "",
                            stamp: status.stamp, waitFor: status.waitFor)
    }

    private var shop: String {
        """
        # Shop
        обновлено 13:05
        1️⃣ Workflow ✅ готово
        - о чём: корзина
        - 11:00 → 12:00 · 1 ч
        - кодинг · 1 агент · Opus 5.5 high
        2️⃣ Workflow ✅ готово
        - о чём: оплата
        - 12:10 → 13:00 · 50 мин
        - кодинг · 1 агент · Opus 5.5 high
        3️⃣ Workflow 💭 идёт
        - о чём: доставка — забыта со вчера
        - 13:10 → … · идёт 40 мин
        """
    }

    private var pimp: String {
        """
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
        - прошлые шаги: планирование · я · Opus 5.5 high — план принят
        - кодинг · 3 агента · Opus 5.5 xhigh 💭
        - гейт · я · Opus 5.5 high
        3️⃣ Workflow ⬜ впереди
        - о чём: WF272 — ревизия
        - шаги 0 из 3
        """
    }

    private func model(_ projects: PanelSnapshot, open: Bool) -> PanelModel {
        let model = PanelWF253Scenes.elvis(now: now)
        model.update = .none
        model.projects = projects
        model.workflowOpen = open
        model.aheadOpen = true
        model.accent = .violet
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
        // Простой: «идёт» в сводке Shop забыто (не живое), сегодня готово 2 — одна строка, раскрыть нечего.
        let idle = PanelSnapshot(waiting: [], working: [], others: [project(shop, "Shop", age: 65, live: false)])
        let idleGroups = WorkflowBlock.groups(idle, now: now)
        XCTAssertEqual(WorkflowBlock.countsLine(idleGroups), "Сейчас ничего не идёт · готово 2")
        try render(model(idle, open: true), "flow-10315-1-prostoy")
        try render(model(PanelSnapshot(waiting: [], working: [], others: []), open: false), "flow-10315-2-pusto")

        // Только живое: PMP идёт; у Shop — только сегодняшнее готовое, его «идёт» и впереди не в счёте.
        let live = PanelSnapshot(waiting: [], working: [project(pimp, "PimpMyClaude", age: 5, live: true)],
                                 others: [project(shop, "Shop", age: 65, live: false)])
        let groups = WorkflowBlock.groups(live, now: now)
        XCTAssertEqual(WorkflowBlock.countsLine(groups), "3 готово · 1 идёт · 1 впереди")
        try render(model(live, open: false), "flow-10315-3-zhivoe-svernuto")
        try render(model(live, open: true), "flow-10315-4-zhivoe-raskryto")
    }
}
