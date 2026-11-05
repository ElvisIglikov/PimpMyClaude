import AppKit
@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF258 (слово Элвиса 17.10.2026 00:37 по листу `docs/48.html`: «делай по рекомендациям», 1.2): блок «Идёт Workflow»
/// одной строкой «Идут 7 · PimpMyClaude 2/3 · …», не влезло — «+2»; нажал — список по проектам; пусто — «Тихо».
/// Кадры свёрнуто/раскрыто с данными листа 48 пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class WorkflowLineWF258Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func flow(_ state: PanelWorkflow.State, _ about: String = "") -> PanelWorkflow {
        PanelWorkflow(about: about, state: state, stepsDone: 1, stepsTotal: 3, time: "", phases: [])
    }

    /// Проект: `done` готовых, `running` идущих о `about`, остальное до `total` — впереди; `age` — сколько минут назад
    /// правлена сводка (свежие — выше).
    private func project(_ name: String, done: Int, running: Int, total: Int, about: String,
                         age: Int) -> PanelProject {
        let flows = Array(repeating: flow(.done, "готовое"), count: done)
            + Array(repeating: flow(.running, about), count: running)
            + Array(repeating: flow(.planned, "впереди"), count: max(0, total - done - running))
        return PanelProject(folder: "/p/" + name, name: name, marker: "⚪", isMain: false,
                            updated: now.addingTimeInterval(TimeInterval(-60 * age)), now: "", words: [], note: "",
                            waits: false, running: flows.filter { $0.state == .running }, workflows: flows)
    }

    /// Проекты и числа листа 48 (картинка 1.2): 7 идущих в четырёх проектах.
    private var sheet48: PanelSnapshot {
        PanelSnapshot(waiting: [], working: [
            project("PimpMyClaude", done: 2, running: 1, total: 3, about: "ревизия всего Пимпа", age: 1),
            project("PimpViewer", done: 6, running: 3, total: 16, about: "листание и подписи в галерее", age: 2),
            project("VkusnoffKz", done: 1, running: 2, total: 4, about: "касса и распродажа", age: 3),
            project("Dictator", done: 5, running: 1, total: 8, about: "плашки и свет", age: 4),
        ], others: [])
    }

    /// Панель открывается свёрнутой: раскрытый список сворачивает `foldSections`, как графики.
    func testPanelOpensCollapsed() {
        let model = PanelModel()
        model.workflowOpen = true
        model.foldSections()
        XCTAssertFalse(model.workflowOpen)
    }

    // MARK: кадры для глаз (правило №1 INTERFACES.md)

    private func scene(_ projects: PanelSnapshot?, open: Bool = false) -> PanelModel {
        let model = PanelWF253Scenes.elvis(now: now)
        model.update = .none
        model.projects = projects
        model.workflowOpen = open
        return model
    }

    func testSnapshots() throws {
        try PanelWF253Scenes.render(scene(sheet48), type: .newYork, name: "wf258-1-svernuto")
        try PanelWF253Scenes.render(scene(sheet48, open: true), type: .newYork, name: "wf258-2-raskryto")
        try PanelWF253Scenes.render(scene(PanelSnapshot(waiting: [], working: [], others: [])), type: .newYork,
                                    name: "wf258-3-tiho")
        // Проектов больше, чем входит в строку: хвост «+N».
        var crowded = sheet48
        crowded = PanelSnapshot(waiting: [], working: crowded.working + [
            project("Rick", done: 4, running: 2, total: 9, about: "марафон чистки", age: 5),
            project("TrelvisCom", done: 0, running: 1, total: 2, about: "задачник", age: 6),
        ], others: [])
        try PanelWF253Scenes.render(scene(crowded), type: .newYork, name: "wf258-4-hvost")
        try PanelWF253Scenes.render(scene(crowded, open: true), type: .newYork, name: "wf258-5-hvost-raskryto")
        try PanelWF253Scenes.render(scene(nil), type: .newYork, name: "wf258-6-chitayu")
        try PanelWF253Scenes.render(scene(sheet48), type: .ultralight, name: "wf258-7-svernuto-2.3")
    }
}
