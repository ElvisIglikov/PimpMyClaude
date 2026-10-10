import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF187 (#9247, #9250): снимки панели для проверки глазами (правило №1 `INTERFACES.md`) — «Токены» половинкой с числом
/// целиком, одинокая половинка во всю ширину. Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelWF187SnapshotTests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824

    private func model(now: Date, today: Int) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.colorsOpen = false
        model.appVersion = "1.10.11"
        model.patch = .installed(version: "2.26454.2", loader: 8)
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 24, resetsAt: now.addingTimeInterval(4 * 3600 + 300)),
                                    weekly: .init(used: 39, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    fable: .init(used: 100, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    source: "api")
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.temperature = (0..<20).map {
            MacTemperatureSample(at: now.addingTimeInterval(Double($0 - 19) * 60), chipAverage: 90 + Double($0 % 7),
                                 chipMax: 100, battery: 30, state: .nominal)
        }
        model.memory = (0..<20).map {
            MacMemorySample(at: now.addingTimeInterval(Double($0 - 19) * 60), pressure: 47 + Double($0 % 4),
                            level: .normal, used: 15 * Self.gb + UInt64($0) * Self.gb / 60, total: 16 * Self.gb)
        }
        model.tokenSpark = TokenSpark(values: [120, 300, 280, 500, 410, 390].map { $0 * 1_000_000 } + [today], scanned: now)
        return model
    }

    func render(_ model: PanelModel, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        let view = NSHostingView(rootView: PanelRoot(model: model))
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: 760)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.backgroundColor = .black
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    /// Раскладка с «Токенами» половинкой и «Fable» без пары («Сброс» скрыт).
    private var narrowTokens: PanelWidgetLayout {
        var layout = PanelWidgetLayout.standard
        layout.toggleWidth(PanelWidget.tokens.rawValue)
        layout.move(PanelWidget.tokens.rawValue, over: PanelWidget.memory.rawValue)
        layout.setHidden(PanelWidget.reset.rawValue, true)
        return layout
    }

    func testSnapshotWF187() throws {
        let now = Date()
        let standard = model(now: now, today: 944_000_000)
        standard.layout = .standard
        try render(standard, "panel-default")
        let narrow = model(now: now, today: 944_000_000)
        narrow.layout = narrowTokens
        try render(narrow, "panel-tokens-half-944")
        let billion = model(now: now, today: 1_234_000_000)
        billion.layout = narrowTokens
        try render(billion, "panel-tokens-half-1-2-mlrd")
        // Одинокая половинка: «Сброс» скрыт — «Память» без пары встаёт во всю ширину.
        let lone = model(now: now, today: 944_000_000)
        var layout = PanelWidgetLayout.standard
        layout.setHidden(PanelWidget.reset.rawValue, true)
        lone.layout = layout
        try render(lone, "panel-lone-half")
        // Значки управления на месте заголовка (как после 0,8 с наведения): половинка, широкий блок, «Оформление».
        for id in [PanelWidget.limits, .tokens, .colors, .fable] {
            let chrome = model(now: now, today: 944_000_000)
            chrome.layout = .standard
            chrome.widgetChrome = id.rawValue
            try render(chrome, "panel-chrome-" + id.rawValue)
        }
    }
}
