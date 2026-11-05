import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// Правки меню по слову Элвиса 11.10.2026 07:00 — кадры для проверки глазами (правило №1 `INTERFACES.md`):
/// «Задержка» с выбором, что делает Enter во время отсчёта, и подсказкой про клавиши; «Дополнительно» без
/// «Allow once» и «Запросов команды», пункт про новый чат назван понятно. Пишутся, только когда задан
/// `PMP_SNAPSHOT_DIR`.
final class PanelMenu1011SnapshotTests: XCTestCase {
    private func model(_ group: SettingsGroup) -> PanelModel {
        let model = PanelModel()
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.23"
        model.maxCardHeight = 1400
        model.patch = .installed(version: "2.31226.0", loader: 8)
        model.layout = .standard
        model.foldSections()
        model.sendDelay = SendDelaySetting(on: true, seconds: 3)
        model.toggles = [PanelToggle(id: AutomationDefaults.continueKey, title: SettingsText.continueTitle,
                                     on: true, needsAccess: false, toolTip: "")]
        model.sheet = .settings
        model.settingsGroup = group
        return model
    }

    private func render(_ model: PanelModel, _ name: String, height: CGFloat = 760) throws {
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
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func testSnapshotMenu1011() throws {
        // 1. «Задержка»: Enter во время отсчёта отменяет (с завода).
        try render(model(.enter), "menu-1-enter-otmenyaet")
        // 2. Тот же выбор, вторая половина: Enter во время отсчёта отправляет сразу.
        let send = model(.enter)
        send.enterKeys = EnterKeys(second: .send)
        try render(send, "menu-2-enter-otpravlyaet")
        // 3. Задержки нет — ни выбора, ни подсказки про клавиши.
        let off = model(.enter)
        off.sendDelay = SendDelaySetting(on: false, seconds: 3)
        try render(off, "menu-3-zaderzhki-net")
        // 4. «Дополнительно»: без «Allow once» и «Запросов команды».
        try render(model(.more), "menu-4-dopolnitelno")
    }

    func testEnterChoiceHasBothHalvesAndHintIsNotASetting() {
        XCTAssertEqual(EnterGroupText.secondItems.map { $0.value }, [.cancel, .send])
        XCTAssertEqual(EnterGroupText.secondItems.map { $0.title }, ["отменяет", "отправляет сразу"])
        XCTAssertTrue(EnterGroupText.keysHint.hasPrefix("Подсказка:"))
    }
}
