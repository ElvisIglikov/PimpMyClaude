import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF242: кадры панели для проверки глазами (правило №1 `INTERFACES.md`) — при открытии всё свёрнуто, «Оформление»
/// раскрыто и с шестерёнкой, ряд отсчётов в покое, под курсором и с настройками, память со свопом и советами,
/// температура, оба графика вместе. Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelWF242SnapshotTests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824
    private static let mb: UInt64 = 1_048_576

    private static let themes = [
        WindowColorChip(id: "red", name: "Красная", background: "#2a1214", accent: "#ff5c5c", light: false),
        WindowColorChip(id: "coral", name: "Коралл", background: "#2a1512", accent: "#ff7a66", light: false),
        WindowColorChip(id: "teal", name: "Бирюзовая", background: "#0f2a2a", accent: "#2dd4bf", light: false),
        WindowColorChip(id: "electric", name: "Электрик", background: "#0e1b33", accent: "#4da3ff", light: false),
        WindowColorChip(id: "blue", name: "Синяя", background: "#111a36", accent: "#5b8cff", light: false),
        WindowColorChip(id: "violet", name: "Фиолетовая", background: "#1b1230", accent: "#b57bff", light: false),
        WindowColorChip(id: "fuchsia", name: "Фуксия", background: "#2a1030", accent: "#f062d6", light: false),
        WindowColorChip(id: "gray", name: "Нуар", background: "#1c1c1e", accent: "#d0d0d4", light: false),
        WindowColorChip(id: "lemon", name: "Лимонная", background: "#fbf8dc", accent: "#b59a00", light: true),
        WindowColorChip(id: "mint", name: "Мятная", background: "#e6f7ee", accent: "#1f9d6b", light: true),
        WindowColorChip(id: "sky", name: "Небесная", background: "#e6f1fb", accent: "#2f7fd6", light: true),
        WindowColorChip(id: "lavender", name: "Лавандовая", background: "#efeafb", accent: "#7a5bd6", light: true),
        WindowColorChip(id: "sakura", name: "Сакура", background: "#fbe9ef", accent: "#d6497f", light: true),
    ]

    /// Память за 3 ч с рябью, подъёмом и участком, где своп рос и потом держался высоко.
    private func memory(now: Date) -> [MacMemorySample] {
        (0..<180).map { index -> MacMemorySample in
            let ripple = Double((index * 7919) % 13) / 13 - 0.5
            let hill = index > 95 && index < 150 ? 3.2 * sin(Double(index - 95) / 55 * .pi) : 0
            let used = 9.2 + 0.5 * ripple + hill + Double(index) / 180
            let swap: Double = index < 105 ? 300 : index < 125 ? 300 + Double(index - 105) * 230 : index < 150 ? 4900 : 4900 - Double(index - 150) * 90
            return MacMemorySample(at: now.addingTimeInterval(Double(index - 179) * 60), pressure: 50, level: .normal,
                                   used: UInt64(used * Double(Self.gb)), total: 16 * Self.gb,
                                   swap: UInt64(swap) * Self.mb)
        }
    }

    /// Температура за 2 ч (история короче, чем у памяти) — рваная по минутам, с одним горячим участком.
    private func temperature(now: Date) -> [MacTemperatureSample] {
        (0..<120).map { index -> MacTemperatureSample in
            let ripple = Double((index * 104_729) % 11) - 5
            let hot = index > 60 && index < 90 ? 22 * sin(Double(index - 60) / 30 * .pi) : 0
            return MacTemperatureSample(at: now.addingTimeInterval(Double(index - 119) * 60),
                                        chipAverage: 55 + ripple + hot, chipMax: 59 + ripple + hot, battery: 31, state: .nominal)
        }
    }

    private func model(now: Date) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.21"
        model.maxCardHeight = 1400
        model.patch = .installed(version: "2.31226.0", loader: 8)
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 24, resetsAt: now.addingTimeInterval(4 * 3600 + 300)),
                                    weekly: .init(used: 85, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    fable: .init(used: 0, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    source: "api")
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.temperature = temperature(now: now)
        model.memory = memory(now: now)
        model.tokenSpark = TokenSpark(values: [120, 300, 280, 500, 410, 390, 643].map { $0 * 1_000_000 }, scanned: now)
        model.windowThemes = Self.themes
        model.allThemes = Self.themes
        model.windowColor = .theme("violet")
        model.liveBackground = true
        model.layout = .standard
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

    func testSnapshotWF242() throws {
        let now = Date()
        // 1. Панель при открытии: всё свёрнуто.
        let folded = model(now: now)
        folded.foldSections()
        try render(folded, "1-panel-opened-folded")

        // 2. «Оформление» раскрыто; 3. с настройками по шестерёнке.
        let colors = model(now: now)
        colors.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        try render(colors, "2-colors-open")
        let extra = model(now: now)
        extra.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        extra.colorsExtraOpen = true
        try render(extra, "3-colors-gear")

        // 4. Отсчёты под курсором: плитка «Ракета» играет (пуск), имя — в строке «Отсчёт».
        let hover = model(now: now)
        hover.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        hover.countdownHover.enter("1.8")
        hover.countdownHover.rested("1.8")
        // Кадр снимается через ~0,6 с после сборки вида: к этому моменту идёт пуск.
        hover.countdownSince = Date().addingTimeInterval(-(3 * PanelCountdown.second - PanelCountdown.stillTime - 0.25))
        try render(hover, "4-countdown-hover-rocket")
        let pulse = model(now: now)
        pulse.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        pulse.countdownHover.enter("1.1")
        pulse.countdownHover.rested("1.1")
        pulse.countdownSince = Date().addingTimeInterval(-0.9)
        try render(pulse, "4b-countdown-hover-stroke")

        // 5. Второе нажатие по выбранной: настройки под рядом, размер 160 %.
        let settings = model(now: now)
        settings.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        settings.countdownSettingsOpen = true
        settings.sendLookSize = 160
        try render(settings, "5-countdown-settings")
        // Светлая тема окон — плитки отсчёта в её цветах.
        let light = model(now: now)
        light.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        light.windowColor = .theme("mint")
        try render(light, "5b-countdown-light-theme")

        // 6. Память раскрыта: красный участок свопа и советы; 7. температура; 8. обе вместе — правый край.
        let memory = model(now: now)
        memory.memoryOpen = true
        try render(memory, "6-memory-open", height: 900)
        let temperature = model(now: now)
        temperature.temperatureOpen = true
        try render(temperature, "7-temperature-open")
        let both = model(now: now)
        both.temperatureOpen = true
        both.memoryOpen = true
        try render(both, "8-both-charts", height: 1000)
        let failed = model(now: now)
        failed.memoryOpen = true
        failed.memoryStarterNote = "Открой окно Claude — вставить некуда"
        try render(failed, "6b-memory-no-claude", height: 900)
    }
}
