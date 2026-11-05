import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #9358: выключатель «Фото с AirDrop — в поле Рика» в «Настройках ▸ Окна и Mac» — включён, выключен и без доступа.
/// Кадры для проверки глазами (правило №1 `INTERFACES.md`); пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class AirDropSettings9358SnapshotTests: XCTestCase {
    private func model(airDrop: Bool, access: Bool = true) -> PanelModel {
        let model = PanelModel()
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.33"
        model.maxCardHeight = 1400
        model.patch = .installed(version: "2.31226.0", loader: 8)
        model.layout = .standard
        model.sheet = .settings
        model.settingsGroup = .windows
        model.toggles = [
            PanelToggle(id: "pmpKeysEnabled", title: SettingsText.pmpKeysTitle, on: true, needsAccess: false,
                        toolTip: SettingsText.pmpKeysHelp),
            PanelToggle(id: "blockQuitEnabled", title: "⌘Q не закрывает Claude", on: true, needsAccess: false, toolTip: ""),
            PanelToggle(id: ConsentBeacon.enabledKey, title: "Подсвечивать окна разрешений macOS", on: true,
                        needsAccess: false, toolTip: ""),
            PanelToggle(id: AirDropWatch.enabledKey, title: "Фото с AirDrop — в поле Рика", on: airDrop,
                        needsAccess: !access, toolTip: ""),
            PanelToggle(id: MacTemperature.enabledKey, title: "Температура в панели", on: true, needsAccess: false, toolTip: ""),
            PanelToggle(id: MacMemory.enabledKey, title: "Память в панели", on: true, needsAccess: false, toolTip: ""),
            PanelToggle(id: "login", title: "Запускать вместе с Mac", on: true, needsAccess: false, toolTip: ""),
        ]
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

    func testSnapshot9358() throws {
        try render(model(airDrop: true), "9358-1-airdrop-vkl")
        try render(model(airDrop: false), "9358-2-airdrop-vykl")
        try render(model(airDrop: true, access: false), "9358-3-airdrop-net-dostupa")
    }
}
