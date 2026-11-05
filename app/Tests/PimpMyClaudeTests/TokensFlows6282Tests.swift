import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #6282: окно «Токены», раздел «Workflow за 7 дней» — полосы цены по API, сумма сверху, «≈ от» у неполной, «Ещё N».
/// Кадр — только когда задан `PMP_SNAPSHOT_DIR`.
final class TokensFlows6282Tests: XCTestCase {
    private let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(14 * 3600 + 10 * 60)

    private func flow(_ about: String, _ project: String, hoursAgo: Double, usd: Double, unpriced: Int = 0) -> WorkflowWeekFlow {
        WorkflowWeekFlow(key: project + "#" + about, project: project, about: about, start: now.addingTimeInterval(-hoursAgo * 3600),
                         item: WorkflowCostItem(totals: CostTotals(output: Int(usd * 20_000), read: Int(usd * 900_000), usd: usd,
                                                                   unpriced: unpriced)))
    }

    private var flows: [WorkflowWeekFlow] {
        [flow("WF303 — бесшовная лента #11201", "PimpMyClaude", hoursAgo: 3, usd: 48.3),
         flow("WF302 — марафон ноута, волны 2–4", "PimpMyClaude", hoursAgo: 14, usd: 31.75),
         flow("WF120 — оплата Kaspi в меню", "VkusnoffKz", hoursAgo: 30, usd: 12.4),
         flow("WF88 — ночная сверка задач", "TrelvisCom", hoursAgo: 52, usd: 6.05, unpriced: 3),
         flow("WF41 — диктовка по-казахски", "Dictator", hoursAgo: 80, usd: 2.2),
         flow("WF19 — сторож смены", "Rick", hoursAgo: 100, usd: 0.004)]
    }

    func testWhen() {
        XCTAssertEqual(TokensFlows.when(now.addingTimeInterval(-3600), now: now), "сегодня, 13:10")
        XCTAssertEqual(TokensFlows.when(now.addingTimeInterval(-86_400), now: now), "вчера, 14:10")
        let old = now.addingTimeInterval(-3 * 86_400)
        let day = Calendar.current.component(.day, from: old), month = Calendar.current.component(.month, from: old)
        XCTAssertEqual(TokensFlows.when(old, now: now), String(format: "%02d.%02d, 14:10", day, month))
    }

    func testSnapshot() throws {
        try render(TokensFlows(flows: flows, accent: PanelColor.hex(PMPAccent.violet.hex), now: now), "6282-tokens-flows")
        // Больше восьми — «Ещё N Workflow».
        let many = (0..<11).map { flow("WF\(200 + $0) — задача \($0)", "PimpMyClaude", hoursAgo: Double($0) * 6, usd: 20 - Double($0)) }
        try render(TokensFlows(flows: many, accent: PanelColor.hex(PMPAccent.violet.hex), now: now), "6282-tokens-flows-more")
    }

    private func render<V: View>(_ content: V, _ name: String) throws {
        let width: CGFloat = TokensWindowController.defaultSize.width
        let view = NSHostingView(rootView: content
            .frame(width: width - 36)
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .background(PanelColor.panel)
            .environment(\.colorScheme, .dark))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 10))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.frame.size = view.fittingSize
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        XCTAssertGreaterThan(view.bounds.height, 100, name)
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
}
