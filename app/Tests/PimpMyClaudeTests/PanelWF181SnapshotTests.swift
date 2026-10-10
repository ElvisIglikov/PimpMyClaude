import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF181 (#9217): снимок панели с данными — раскладка по умолчанию, шапка, ряды плиток, «Память» — для проверки глазами
/// (правило №1 `INTERFACES.md`). Пишется, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelWF181SnapshotTests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824

    private func model(now: Date) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.colorsOpen = false
        model.appVersion = "1.10.10"
        model.patch = .installed(version: "2.26454.2", loader: 8)
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 24, resetsAt: now.addingTimeInterval(4 * 3600 + 300)),
                                    weekly: .init(used: 39, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    fable: .init(used: 0, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    source: "api")
        // Значок у часов — с числом недели: шапка панели не должна его повторять.
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.temperature = (0..<20).map {
            MacTemperatureSample(at: now.addingTimeInterval(Double($0 - 19) * 60), chipAverage: 50 + Double($0 % 7),
                                 chipMax: 60, battery: 30, state: .nominal)
        }
        model.memory = (0..<20).map {
            MacMemorySample(at: now.addingTimeInterval(Double($0 - 19) * 60), pressure: 47 + Double($0 % 4),
                            level: .normal, used: 6 * Self.gb + UInt64($0) * Self.gb / 60, total: 8 * Self.gb)
        }
        model.tokenSpark = TokenSpark(values: [120, 300, 280, 500, 410, 390, 643].map { $0 * 1_000_000 }, scanned: now)
        model.layout = .standard
        return model
    }

    private func render(_ model: PanelModel, to url: URL) throws {
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
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    func testSnapshotDefaultPanel() throws {
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        let now = Date()
        try render(model(now: now), to: URL(fileURLWithPath: dir).appendingPathComponent("panel-default.png"))
        let open = model(now: now)
        open.memoryOpen = true
        try render(open, to: URL(fileURLWithPath: dir).appendingPathComponent("panel-memory-open.png"))
    }
}
