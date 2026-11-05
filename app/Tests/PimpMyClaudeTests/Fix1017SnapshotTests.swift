import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// Кадры правок 17.10 для проверки глазами (правило №1 `INTERFACES.md`): последнее известное значение подписки
/// (#9824), графики цветом состояния, общее левое поле и советы у температуры (#9818), плашка разрешения со стрелкой
/// (#9841). Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class Fix1017SnapshotTests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824
    private static let mb: UInt64 = 1_048_576

    /// Память за 3 ч: спокойно, потом своп растёт (красный), держится высоко (жёлтый) и уходит (зелёный).
    private func memory(now: Date, total: UInt64 = 16 * Fix1017SnapshotTests.gb) -> [MacMemorySample] {
        (0..<180).map { index -> MacMemorySample in
            let ripple = Double((index * 7919) % 13) / 13 - 0.5
            let hill = index > 95 && index < 150 ? 3.2 * sin(Double(index - 95) / 55 * .pi) : 0
            let used = 9.2 + 0.5 * ripple + hill + Double(index) / 180
            let swap: Double = index < 105 ? 300 : index < 125 ? 300 + Double(index - 105) * 230 : index < 150 ? 4900
                : 4900 - Double(index - 150) * 90
            return MacMemorySample(at: now.addingTimeInterval(Double(index - 179) * 60), pressure: 50, level: .normal,
                                   used: UInt64(used * Double(Self.gb)), total: total, swap: UInt64(swap) * Self.mb)
        }
    }

    /// Температура за 2 ч: спокойно, слегка нагрет и сильно нагрет на горячем участке.
    private func temperature(now: Date) -> [MacTemperatureSample] {
        (0..<120).map { index -> MacTemperatureSample in
            let ripple = Double((index * 104_729) % 11) - 5
            let hot = index > 60 && index < 90 ? 32 * sin(Double(index - 60) / 30 * .pi) : 0
            let state: ProcessInfo.ThermalState = hot > 26 ? .serious : hot > 14 ? .fair : .nominal
            return MacTemperatureSample(at: now.addingTimeInterval(Double(index - 119) * 60),
                                        chipAverage: 55 + ripple + hot, chipMax: 59 + ripple + hot, battery: 31, state: state)
        }
    }

    private func model(now: Date, limitsAge: TimeInterval) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.30"
        model.maxCardHeight = 1400
        model.patch = .installed(version: "2.31226.0", loader: 8)
        model.limits = ClaudeLimits(at: now.addingTimeInterval(-limitsAge), plan: "Max 20x",
                                    fiveHour: .init(used: 24, resetsAt: now.addingTimeInterval(4 * 3600 + 300)),
                                    weekly: .init(used: 85, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    fable: .init(used: 0, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    source: "api")
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.temperature = temperature(now: now)
        model.memory = memory(now: now)
        model.layout = .standard
        return model
    }

    private func save(_ view: NSView, _ name: String) throws {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    private func render(_ model: PanelModel, _ name: String, height: CGFloat) throws {
        let view = NSHostingView(rootView: PanelRoot(model: model))
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: height)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.backgroundColor = .black
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        try save(view, name)
    }

    func testSnapshotFix1017() throws {
        let now = Date()
        // #9824: окно Claude молчит 25 минут и двое суток — числа те же, бледным, под неделей давность.
        try render(model(now: now, limitsAge: 25 * 60), "9824-1-stale-25min", height: 560)
        try render(model(now: now, limitsAge: 2 * 86_400 + 3600), "9824-2-stale-days", height: 560)
        try render(model(now: now, limitsAge: 60), "9824-0-fresh", height: 560)

        // #9818: оба графика раскрыты — зелёный, жёлтый, красный; советы у обоих.
        let both = model(now: now, limitsAge: 60)
        both.temperatureOpen = true
        both.memoryOpen = true
        try render(both, "9818-1-both-charts", height: 1180)
        // Большой Мак: «128 ГБ» шире «100°» — поле обоих графиков шире, начало на одной линии.
        let big = model(now: now, limitsAge: 60)
        big.memory = memory(now: now, total: 128 * Self.gb)
        big.temperatureOpen = true
        big.memoryOpen = true
        try render(big, "9818-2-wide-label", height: 1180)
    }

    func testSnapshotPermissionPlaqueWithPointer() throws {
        for (pointer, name) in [(HintPull.Side.left, "9841-1-permission-left"), (.right, "9841-2-permission-right")] {
            let view = NSHostingView(rootView: PermissionHintView(openSettings: {}, relaunch: {}, cancel: {},
                                                                  pointer: pointer))
            view.appearance = NSAppearance(named: .darkAqua)
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            XCTAssertEqual(view.fittingSize.width, PermissionHintView.width + 2 * HintPointer.inset)
            try save(view, name)
        }
    }
}
