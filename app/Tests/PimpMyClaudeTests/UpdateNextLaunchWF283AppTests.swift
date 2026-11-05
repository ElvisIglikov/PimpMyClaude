import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #10765, WF283: строка «Обновления» в настройках у отложенного и кадры карточки — две кнопки, предупреждение,
/// свёрнуто, ставится, сбой — для проверки глазами (правило №1 `INTERFACES.md`). Кадры пишутся, только когда задан
/// `PMP_SNAPSHOT_DIR`.
final class UpdateNextLaunchWF283AppTests: XCTestCase {
    private static let version = "3.1623.1"

    func testSettingsRowKeepsUpdateButton() {
        let row = SettingsText.update(.planned(version: Self.version))
        XCTAssertEqual(row.text, "3.1623.1 — при запуске")
        XCTAssertTrue(row.ready, "«Обновить» в настройках ставит отложенное сейчас")
    }

    func testPlannedRowTakesItsBlock() {
        let model = PanelModel()
        model.update = .planned(version: Self.version)
        XCTAssertFalse(model.updateCardHidden, "свёрнутая строка видна: человек понимает, что обновление ждёт")
    }

    // MARK: кадры

    private var dir: URL? {
        ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func render(_ update: PimpPanelText.UpdateBlock, height: CGFloat, name: String,
                        opensClaude: Bool = true) throws {
        let now = Date()
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.78"
        model.patch = .installed(version: "3.1623.0", loader: 8)
        model.loader = 8
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 24, resetsAt: now.addingTimeInterval(4 * 3600 + 300)),
                                    weekly: .init(used: 39, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    fable: .init(used: 0, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    source: "api")
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.layout = .standard
        model.readySize = "374 МБ"
        model.update = update
        model.installOpensClaude = opensClaude
        let view = NSHostingView(rootView: PanelRoot(model: model))
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: height)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.backgroundColor = .black
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let url = dir?.appendingPathComponent(name) else { return }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    func testSnapshotNextLaunchStates() throws {
        let work = WorkNow(chats: 0, workflows: 0, terminals: 2)
        try render(.ready(version: Self.version, question: nil), height: 520, name: "1-dve-knopki.png")
        try render(.busy(version: Self.version, work: try XCTUnwrap(PimpPanelText.workShort(work))), height: 520,
                   name: "2-idet-rabota.png")
        try render(.ready(version: Self.version, question: PimpPanelText.confirmQuestion(work: work)), height: 540,
                   name: "3-preduprezhdenie.png")
        try render(.planned(version: Self.version), height: 480, name: "4-svernuto.png")
        try render(.installing(version: Self.version, step: 1), height: 760, name: "5-stavitsya.png")
        try render(.failed("Claude не закрылся"), height: 520, name: "6-sboy.png")
        try render(.installing(version: Self.version, step: 1), height: 520, name: "7-stavitsya-pri-zakrytom.png",
                   opensClaude: false)
    }
}
