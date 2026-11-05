import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF237 (#9524): меню жёлтой кнопки снято, оформление окон — в «Оформлении» панели (лист 48, ответ 2.1). Кадры для
/// проверки глазами (правило №1 `INTERFACES.md`): «Оформление» с шестерёнкой и «Окна и Mac» в настройках. Пишутся,
/// только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelWF237SnapshotTests: XCTestCase {
    private static let themes = [
        WindowColorChip(id: "teal", name: "Бирюзовая", background: "#0f2a2a", accent: "#2dd4bf", light: false),
        WindowColorChip(id: "electric", name: "Электрик", background: "#0e1b33", accent: "#4da3ff", light: false),
        WindowColorChip(id: "violet", name: "Фиолетовая", background: "#1b1230", accent: "#b57bff", light: false),
        WindowColorChip(id: "gray", name: "Нуар", background: "#1c1c1e", accent: "#d0d0d4", light: false),
        WindowColorChip(id: "mint", name: "Мятная", background: "#e6f7ee", accent: "#1f9d6b", light: true),
        WindowColorChip(id: "sky", name: "Небесная", background: "#e6f1fb", accent: "#2f7fd6", light: true),
    ]

    private func model() -> PanelModel {
        let model = PanelModel()
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.27"
        model.maxCardHeight = 1400
        model.patch = .installed(version: "2.31226.0", loader: 8)
        model.layout = .standard
        model.windowThemes = Self.themes
        model.allThemes = Self.themes
        model.windowColor = .theme("violet")
        model.liveBackground = true
        model.liveMotion = .live
        model.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        model.colorsExtraOpen = true
        model.liveScheme = "sea"
        model.windowFonts = [WindowFontChip(id: "avenir-next", name: "Avenir Next", family: "Avenir Next", section: "sans"),
                             WindowFontChip(id: "menlo", name: "Menlo", family: "Menlo", section: "mono")]
        model.windowFontID = "avenir-next"
        model.windowTextSize = 15
        model.denseText = true
        model.hideTools = true
        return model
    }

    private func render(_ model: PanelModel, _ name: String, height: CGFloat = 900) throws {
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

    func testSnapshotWF237() throws {
        // 1. «Оформление» с шестерёнкой: живой фон движется, схема «Глубокое море», текст окон.
        try render(model(), "wf237-1-oformlenie")
        // 1b. Фона нет — строки «Схема» нет; шрифт и размер как у Claude, цвет по проектам.
        let plain = model()
        plain.liveBackground = false
        plain.windowFontID = nil
        plain.windowTextSize = nil
        plain.denseText = false
        plain.windowColor = .byProject
        try render(plain, "wf237-1b-oformlenie-bez-fona")
        // 1c. Без патча — строки бледные и не нажимаются.
        let lost = model()
        lost.patch = .notInstalled(version: "2.31226.0")
        try render(lost, "wf237-1c-bez-patcha")
        // 2. «Окна и Mac» в настройках.
        let windows = model()
        windows.colorsExtraOpen = false
        windows.sheet = .settings
        windows.settingsGroup = .windows
        windows.toggles = [
            PanelToggle(id: "pmpKeysEnabled", title: SettingsText.pmpKeysTitle, on: true, needsAccess: false,
                        toolTip: SettingsText.pmpKeysHelp),
            PanelToggle(id: "blockQuitEnabled", title: "⌘Q не закрывает Claude", on: true, needsAccess: false, toolTip: ""),
            PanelToggle(id: "login", title: "Запускать вместе с Mac", on: true, needsAccess: false, toolTip: ""),
        ]
        try render(windows, "wf237-2-okna-i-mac")
    }
}
