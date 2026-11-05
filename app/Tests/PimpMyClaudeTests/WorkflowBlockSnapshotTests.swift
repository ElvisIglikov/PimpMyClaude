import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #10239: блок Workflow — порт PMP Tray для Windows. Кадры для глаз (правило №1 `INTERFACES.md`): свёрнут со
/// счётом, раскрыт («идут» и «Впереди»), фильтр «готово» с порциями, легенда, карточка, живые сводки этого Мака
/// и панель целиком. Пишутся, только когда задан `PMP_SNAPSHOT_DIR`; панель тёмная всегда (`PanelRoot`), светлой нет.
final class WorkflowBlockSnapshotTests: XCTestCase {
    private let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(14 * 3600 + 10 * 60)

    private func project(_ text: String, _ folder: String, age minutes: Double) -> PanelProject {
        let status = PanelProjects.parse(text)
        return PanelProject(folder: "/p/" + folder, name: status.name, marker: status.marker, isMain: false,
                            updated: now.addingTimeInterval(-60 * minutes), now: status.now, words: [], note: "",
                            waits: false, running: status.workflows.filter { $0.state == .running || $0.state == .failed },
                            workflows: status.workflows, marathon: "", stamp: status.stamp, waitFor: status.waitFor)
    }

    /// День как на листе Windows (Blog Engine, Weather App) и сводки Мака: идут, ждёт, упал, готово, впереди.
    private var day: PanelSnapshot {
        let pimp = project("""
        # ⚪PimpMyClaude
        обновлено 14:05
        1️⃣ Workflow ✅ готово
        - о чём: WF269 — падение панели и «за 9 мин», совет про подставку
        - 09:31 → 10:50 · 1,3 ч
        - критик · 1 агент · Opus 5.5 high; кодинг · 5 агентов · Opus 5.5 medium; гейт · я · Opus 5.5 high
        2️⃣ Workflow 💭 идёт
        - о чём: WF272 — блок Workflow как на Windows: счёт, полоса, порции, карточка
        - 13:05 → закончит в 14:50 · идёт 55 мин
        - шаги 2 из 3
        - прошлые шаги: планирование · я · Opus 5.5 high — план принят
        - критик · 1 агент · 🔴 Fable 5.1 high
        - кодинг · 3 агента · Opus 5.5 high 💭
        - гейт · я · Opus 5.5 high
        3️⃣ Workflow ✋ ждёт
        - о чём: WF273 — меню на жёлтой кнопке, проверка глазами
        - 12:40 → 13:20
        - шаги 1 из 2
        - кодинг · 1 агент · Opus 5.5 high
        4️⃣ Workflow ⬜ впереди
        - о чём: WF274 — ревизия после серии
        - шаги 0 из 3
        Ждёт Элвиса: посмотреть кадры меню и сказать «да»
        """, "PimpMyClaude", age: 5)
        let viewer = project("""
        # 🖼PimpViewer
        обновлено 13:40
        1️⃣ Workflow ✅ готово
        - о чём: страница проверяется в Chromium и WebKit на каждой сборке
        - 12:38 → 13:02 · 24 мин
        - кодинг · я · Opus 5.5 xhigh
        2️⃣ Workflow 💭 идёт
        - о чём: листание и подписи в галерее
        - 13:30 → … · идёт 10 мин
        - шаги 1 из 2
        - кодинг · 1 агент · Opus 5.5 xhigh
        3️⃣ Workflow 🛑 упал
        - о чём: сборка для команды
        - 13:00 → 13:20
        - шаги 1 из 2
        - тест · 1 агент · Opus 5.5 high
        """, "PimpViewer", age: 30)
        let blog = project("""
        # Blog Engine
        обновлено 14:00
        1️⃣ Workflow ✅ готово
        - о чём: импорт старых записей
        - 10:00 → 11:15 · 1,3 ч
        - кодинг · 1 агент · Sonnet 4.5 high
        2️⃣ Workflow ⬜
        - о чём: dark theme for the editor
        - шаги 0 из 2
        """, "Blog", age: 10)
        let vkusnoff = project("""
        # 🟠VkusnoffKz
        обновлено 12:45
        1️⃣ Workflow ✅ готово
        - о чём: рулетка «Кто платит» — «однорукий бандит» с тремя барабанами котиков; готово к выкладке
        - шаги 3 из 3
        - 12:20 → 12:45 · 0,4 ч
        - кодинг · я · Opus 5.5 medium
        2️⃣ Workflow ✅ готово
        - о чём: баннер кафе «60 минут» — шторка с условиями кафе
        - шаги 3 из 3
        - 11:50 → 12:20 · 0,5 ч
        - кодинг · я · Opus 5.5 medium
        3️⃣ Workflow ✅ готово
        - о чём: ошибки сайта из проверки — касса по точкам, распродажи и витрина
        - 08:20 → 10:00 · 1,7 ч
        - планирование · я · Opus 5.5 high
        - критика · 1 агент · Opus 5.5 high
        - кодинг · 5 агентов · Opus 5.5 medium/high
        - проверка · 4 агента · Opus 5.5 high
        4️⃣ Workflow ✅ готово
        - о чём: шторка «Как вам заказ?» с фото блюд и звёздами
        - 08:20 → 10:00 · 1,7 ч
        - кодинг · 1 агент · Opus 5.5 high
        5️⃣ Workflow ⬜
        - о чём: «Маргарита» в iiko
        """, "VkusnoffKz", age: 85)
        return PanelSnapshot(waiting: [pimp], working: [pimp, viewer], others: [blog, vkusnoff])
    }

    private func model(_ projects: PanelSnapshot?, open: Bool = false, setup: (PanelModel) -> Void = { _ in }) -> PanelModel {
        let model = PanelWF253Scenes.elvis(now: now)
        model.update = .none
        model.projects = projects
        model.workflowOpen = open
        model.accent = .violet
        setup(model)
        return model
    }

    /// Блок один, шириной во всю панель, на её подложке.
    /// `below` — запас под блоком: легенда ложится поверх соседних блоков.
    private func render(_ model: PanelModel, _ name: String, type: PanelTypography = .newYork,
                        below: CGFloat = 0) throws {
        let width = PimpPanelController.width - 24
        let view = NSHostingView(rootView: WorkflowBlockView(model: model)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, below)
            .frame(width: width, alignment: .top)
            .padding(12)
            .background(PanelColor.ink)
            .environment(\.colorScheme, .dark)
            .environment(\.pmpAccent, PanelColor.hex(model.shownAccent.hex))
            .environment(\.panelType, type))
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
        let day = day
        let groups = WorkflowBlock.groups(day, now: now)
        XCTAssertEqual(WorkflowBlock.countsLine(groups), "7 готово · 2 идут · 1 ждёт · 1 упал · 1 впереди",
                       "#10315: впереди — только у идущих")

        try render(model(day), "workflow-1-svernuto")
        try render(model(day, open: true) { $0.aheadOpen = false }, "workflow-2-idut")
        try render(model(day, open: true) { $0.aheadOpen = true }, "workflow-3-idut-vperedi")
        try render(model(day, open: true) { $0.flow.filter = .done }, "workflow-4-gotovo-porcii")
        try render(model(day) { $0.workflowLegend = true }, "workflow-5-legenda", below: 170)
        try render(model(day, open: true) { $0.flow.card = "/p/PimpMyClaude#1" }, "workflow-6-kartochka")
        try render(model(day, open: true) { $0.flow.card = "/p/PimpMyClaude#2" }, "workflow-7-kartochka-zhdet")
        try render(model(day, open: true) { $0.flow.filter = .done; $0.flow.card = "/p/VkusnoffKz#2" },
                   "workflow-8-kartochka-gotovo")
        try render(model(day, open: true) { $0.aheadOpen = true }, "workflow-9-idut-49.2", type: .italic)
        try render(model(nil, open: true), "workflow-10-chitayu")
        try render(model(PanelSnapshot(waiting: [], working: [], others: []), open: true), "workflow-11-pusto")

        // Живые сводки этого Мака (папка проектов из claude.json) — как увидит Элвис сейчас.
        let live = PanelProjects.snapshot(root: StatusFeed.projectsRoot(), recent: [], mainEntry: nil, now: Date())
        let liveModel = { (open: Bool, filter: WorkflowBlock.Filter) -> PanelModel in
            let model = self.model(live, open: open) { $0.flow.filter = filter }
            model.now = Date()
            return model
        }
        try render(liveModel(false, .run), "workflow-12-zhivye-svernuto")
        try render(liveModel(true, .run), "workflow-13-zhivye-idut")
        try render(liveModel(true, .done), "workflow-14-zhivye-gotovo")

        // Панель целиком: блок на своём месте среди остальных.
        try PanelWF253Scenes.render(model(day, open: true), type: .newYork, name: "workflow-15-panel")
    }
}
