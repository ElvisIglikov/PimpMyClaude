import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF297 (батч A): панель у часов — признак «ниже есть ещё» (#11164), короткий срок свёрнутого «Сброса» (#11165),
/// одна мера «Памяти» свёрнутой и раскрытой (#11166). Снимки пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelWF297Tests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824

    private func model(now: Date, reset: TimeInterval = 9 * 3600 + 40 * 60) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.90"
        model.patch = .installed(version: "2.26454.2", loader: 9)
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 10, resetsAt: now.addingTimeInterval(4 * 3600)),
                                    weekly: .init(used: 95, resetsAt: now.addingTimeInterval(reset)),
                                    fable: .init(used: 0, resetsAt: now.addingTimeInterval(reset)),
                                    source: "api")
        model.temperature = (0..<20).map {
            MacTemperatureSample(at: now.addingTimeInterval(Double($0 - 19) * 60), chipAverage: 46 + Double($0 % 5),
                                 chipMax: 60, battery: 30, state: .nominal)
        }
        // Как на S1-07/S1-10: нагрузка macOS 51 %, занято 20 из 24 ГБ.
        model.memory = (0..<20).map {
            MacMemorySample(at: now.addingTimeInterval(Double($0 - 19) * 60), pressure: 51, level: .normal,
                            used: 20 * Self.gb, total: 24 * Self.gb)
        }
        model.tokenSpark = TokenSpark(values: [120, 300, 280, 500, 410, 390, 274].map { $0 * 1_000_000 }, scanned: now)
        model.layout = .standard
        return model
    }

    private func collapseAll(_ model: PanelModel) {
        var layout = model.layout
        for widget in PanelWidget.allCases { layout.setCollapsed(widget.rawValue, true) }
        model.layout = layout
    }

    private func render(_ model: PanelModel, height: CGFloat = 760, to name: String) throws {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    // MARK: #11164 — ниже есть ещё

    func testMoreBelowOnlyWhenContentHidden() {
        XCTAssertTrue(PanelMoreBelow.shown(content: 900, card: 560, scrolled: 0))
        XCTAssertTrue(PanelMoreBelow.shown(content: 900, card: 560, scrolled: 300))
        XCTAssertFalse(PanelMoreBelow.shown(content: 900, card: 560, scrolled: 340), "долистали до конца")
        XCTAssertFalse(PanelMoreBelow.shown(content: 500, card: 500, scrolled: 0), "всё влезло")
    }

    // MARK: #11165 — свёрнутый «Сброс» коротко

    func testCollapsedResetIsShort() {
        let now = Date()
        let model = model(now: now)
        XCTAssertEqual(model.collapsedValue(.reset), "9\u{00A0}ч 40\u{00A0}мин")
        // Самый длинный срок в часах — тоже короткой записью, не «23 часа 59 минут».
        XCTAssertEqual(self.model(now: now, reset: 23 * 3600 + 59 * 60).collapsedValue(.reset), "23\u{00A0}ч 59\u{00A0}мин")
        XCTAssertEqual(self.model(now: now, reset: 2 * 86400 + 21 * 3600).collapsedValue(.reset), "2\u{00A0}дн 21\u{00A0}ч")
    }

    // MARK: #11166 — «Память» одной мерой

    func testCollapsedMemoryMatchesExpanded() {
        let model = model(now: Date())
        XCTAssertEqual(model.collapsedValue(.memory), MacMemory.nowText(model.memory))
        XCTAssertEqual(model.collapsedValue(.memory), "20 ГБ")
        // Занятого не знаем — как и в раскрытом виде, нагрузка macOS в процентах.
        model.memory = [MacMemorySample(at: Date(), pressure: 51, level: .normal, used: nil, total: 0)]
        XCTAssertEqual(model.collapsedValue(.memory), MacMemory.nowText(model.memory))
    }

    // MARK: снимки

    func testSnapshotCollapsed() throws {
        let model = model(now: Date())
        collapseAll(model)
        try render(model, to: "A-11165-collapsed.png")
    }

    func testSnapshotTallPanel() throws {
        let model = model(now: Date())
        model.memoryOpen = true
        model.maxCardHeight = 560
        try render(model, height: 600, to: "A-11164-tall.png")
    }
}
