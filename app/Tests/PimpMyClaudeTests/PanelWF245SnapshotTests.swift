import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF245: кадры панели для проверки глазами (правило №1 `INTERFACES.md`) — полосы цветов после чистки набора тем
/// (17 тем, «Как у Claude» не плитка), строка «Как у Claude» за шестерёнкой, группа «Закреплённые чаты» без
/// выключателя таймера. Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelWF245SnapshotTests: XCTestCase {
    /// Темы полос — из живого каталога репозитория, как их получит панель.
    private func chips() -> [WindowColorChip] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("claude-patch")
        let themes = ThemeCatalog.load(directory: root)
        return ClaudeAXController.panelThemeIDs.compactMap { id in themes.first { $0.id == id } }.map(WindowColorChip.init)
    }

    private func model(_ choice: WindowColorChoice) -> PanelModel {
        let model = PanelModel()
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.21"
        model.maxCardHeight = 1400
        model.patch = .installed(version: "2.31226.0", loader: 8)
        model.windowThemes = chips()
        model.allThemes = model.windowThemes
        model.windowColor = choice
        model.liveBackground = true
        model.layout = .standard
        model.foldSections()
        model.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        return model
    }

    private func render(_ model: PanelModel, _ name: String, height: CGFloat = 560) throws {
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

    func testSnapshotWF245() throws {
        // 1. Полоса цветов: 17 плиток одной ширины в ряд, выбрана «Фиолетовая».
        try render(model(.theme("violet")), "panel-1-colors")
        // 2. Шестерёнка: «Живой фон» и «Как у Claude · Вернуть».
        let gear = model(.theme("violet"))
        gear.colorsExtraOpen = true
        try render(gear, "panel-2-gear-plain-row")
        // 3. Обычный вид Claude уже стоит: плитка не выделена, строка говорит «стоит сейчас».
        let plain = model(.plain)
        plain.colorsExtraOpen = true
        plain.liveBackground = false
        try render(plain, "panel-3-plain-now")
        // 4. У окон стоит тема, которой больше нет в наборе («Красная»): панель цела, плитка не выделена.
        let gone = model(.theme("red"))
        gone.colorsExtraOpen = true
        try render(gone, "panel-4-removed-theme")
        // 5. Настройки → «Закреплённые чаты»: один выключатель, таймеров нет.
        let pinned = model(.theme("violet"))
        pinned.sheet = .settings
        pinned.settingsGroup = .pinned
        try render(pinned, "panel-5-pinned-no-timer", height: 760)
    }
}
