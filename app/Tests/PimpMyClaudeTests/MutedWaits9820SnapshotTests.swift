import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #9820: «Не напоминать» у «Ждёт тебя». Кадры для глаз: карточка Workflow со строкой «Ждёт тебя» и «Не напоминать ▾»,
/// та же карточка с плашкой «Не буду напоминать · Отменить 5», блок без идущих со строкой «Ждёт тебя · Rick» и с
/// плашкой «Не вышло записать». Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class MutedWaits9820SnapshotTests: XCTestCase {
    private let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(14 * 3600 + 10 * 60)
    private let limit = "Постоянный лимит 99 %, доплата или ждём пятницы"

    private func project(_ text: String, _ folder: String, live: Bool) -> PanelProject {
        let status = PanelProjects.parse(text)
        let running = live ? status.workflows.filter { $0.state == .running || $0.state == .failed } : []
        return PanelProject(folder: "/p/" + folder, name: status.name, marker: status.marker, isMain: false,
                            updated: now.addingTimeInterval(-300), now: status.now, words: [], note: "",
                            waits: !status.waitFor.isEmpty, running: running, workflows: status.workflows, marathon: "",
                            stamp: status.stamp, waitFor: status.waitFor)
    }

    private var pimp: PanelProject {
        project("""
        # ⚪PimpMyClaude
        обновлено 14:05
        1️⃣ Workflow 💭 идёт
        - о чём: WF271 — блок Workflow только живое
        - 13:05 → закончит в 14:50 · идёт 55 мин
        - шаги 2 из 3
        - кодинг · 3 агента · Opus 5.5 xhigh 💭
        Ждёт Элвиса: посмотреть кадры меню и сказать «да»
        """, "PimpMyClaude", live: true)
    }

    private var rick: PanelProject { project("# 🧠Rick\nЖдёт Элвиса: \(limit)\n", "Rick", live: false) }

    private func model(_ projects: PanelSnapshot, setup: (PanelModel) -> Void = { _ in }) -> PanelModel {
        let model = PanelWF253Scenes.elvis(now: now)
        model.update = .none
        model.projects = projects
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
        let live = PanelSnapshot(waiting: [pimp, rick], working: [pimp], others: [])
        let card = WorkflowBlock.Row(project: pimp, index: 0).id
        // Карточка идущего Workflow: «Ждёт тебя: …» и «Не напоминать ▾» (раньше строка была только у ✋).
        try render(model(live) { model in
            model.workflowOpen = true
            model.flow.card = card
        }, "9820-1-kartochka")
        // После выбора «До завтра»: строка ушла, на её месте 5 с «Отменить».
        let key = MutedWaits.key(folder: pimp.folder, text: pimp.waitFor)
        try render(model(live) { model in
            model.workflowOpen = true
            model.flow.card = card
            model.flow.waitUndo = WaitUndo(key: key, folder: pimp.folder, choice: .tomorrow, at: Date(), failed: false,
                                           inCard: true)
            model.flow.hiddenWaits = [key]
        }, "9820-2-otmenit")
        // Ничего не идёт: строка блока и под ней «Ждёт тебя · Rick: …» — кнопке есть где встать.
        let idle = PanelSnapshot(waiting: [rick], working: [], others: [])
        XCTAssertEqual(PanelProjects.loneWaits(idle).map(\.name), ["Rick"])
        try render(model(idle), "9820-3-zhdet-bez-workflow")
        // Записать не вышло: 3 с «Не вышло записать», строка осталась.
        try render(model(idle) { model in
            model.flow.waitUndo = WaitUndo(key: MutedWaits.key(folder: self.rick.folder, text: self.limit),
                                           folder: self.rick.folder, choice: .hour, at: Date(), failed: true,
                                           inCard: false)
        }, "9820-4-ne-vyshlo")
    }

    /// Нажатие: запись сразу, строка уходит, «Отменить» снимает запись и возвращает строку; ошибка — строка остаётся.
    func testMuteAndUndoFlow() {
        let live = PanelSnapshot(waiting: [rick], working: [], others: [])
        let model = model(live)
        var written: [String] = []
        var removed: [String] = []
        model.actions.muteWait = { key, until in
            written.append(key)
            XCTAssertNotNil(until)
            return true
        }
        model.actions.unmuteWait = { removed.append($0) }
        XCTAssertTrue(model.waitShown(rick))
        model.muteWait(rick, .week, inCard: false)
        let key = MutedWaits.key(folder: rick.folder, text: limit)
        XCTAssertEqual(written, [key])
        XCTAssertFalse(model.waitShown(rick), "строка уходит сразу, снимок ещё не перечитан")
        XCTAssertEqual(model.flow.waitUndo?.key, key)
        XCTAssertEqual(PanelProjects.loneWaits(live, hidden: model.flow.hiddenWaits).count, 0)
        model.undoMuteWait()
        XCTAssertEqual(removed, [key])
        XCTAssertNil(model.flow.waitUndo)
        XCTAssertTrue(model.waitShown(rick))

        model.actions.muteWait = { _, _ in false }
        model.muteWait(rick, .hour, inCard: false)
        XCTAssertEqual(model.flow.waitUndo?.failed, true)
        XCTAssertTrue(model.waitShown(rick), "не записалось — строка остаётся")
        model.undoMuteWait()
        XCTAssertEqual(removed, [key], "у ошибки отменять нечего")
        model.foldSections()
        XCTAssertNil(model.flow.waitUndo, "панель открылась заново — плашки нет")
    }
}
