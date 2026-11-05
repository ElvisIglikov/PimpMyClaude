import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF298 (батч A): свёрнутое «Оформление» в половинке без «…» (#11180), раскрытые «Токены» в половинке с неделей по
/// дням (#11167). #11181 (AXPress у заголовка Workflow) деревом доступности под XCTest не проверить (см. `PanelButtonsTests`).
/// Снимки пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelWF298Tests: XCTestCase {
    private func model(now: Date) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.91"
        model.patch = .installed(version: "2.26454.2", loader: 9)
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 10, resetsAt: now.addingTimeInterval(4 * 3600)),
                                    weekly: .init(used: 95, resetsAt: now.addingTimeInterval(9 * 3600)),
                                    fable: .init(used: 0, resetsAt: now.addingTimeInterval(9 * 3600)),
                                    source: "api")
        model.tokenSpark = TokenSpark(values: [120, 300, 280, 500, 410, 390, 274].map { $0 * 1_000_000 }, scanned: now)
        model.windowColor = .byProject
        model.layout = .standard
        return model
    }

    private func collapse(_ model: PanelModel, except open: Set<PanelWidget> = []) {
        var layout = model.layout
        for widget in PanelWidget.allCases { layout.setCollapsed(widget.rawValue, !open.contains(widget)) }
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

    // MARK: #11180 — «Оформление» в половинке

    func testColorsValueHasMark() {
        let model = model(now: Date())
        // «Свой цвет у каждого проекта» из панели убран (решение 03.11.2026): у кого он стоит — строка без названия.
        XCTAssertNil(model.collapsedValue(.colors))
        XCTAssertEqual(CollapsedWidget.colorMark(PanelColorTiles.byProjectName), .byProject)
        XCTAssertEqual(CollapsedWidget.colorMark(PanelColorTiles.plainName), .plain)
        // Длинный счёт Workflow кружка не получает — он ужимается сам, как раньше.
        XCTAssertNil(CollapsedWidget.colorMark("3 идут · 2 ждут · 5 готово"))
        XCTAssertNil(CollapsedWidget.colorMark(nil))
    }

    func testColorsLineDoesNotShrinkThePanel() {
        // В раскладке Элвиса (#10704) «Оформление» — половинкой: его строка общую долю подписей не задаёт.
        XCTAssertFalse(CollapsedWidget.measured(value: PanelColorTiles.byProjectName, swatch: false, spark: false))
        XCTAssertFalse(CollapsedWidget.measured(value: PanelColorTiles.plainName, swatch: false, spark: false))
        XCTAssertTrue(CollapsedWidget.measured(value: "274 млн", swatch: false, spark: false))
        XCTAssertFalse(CollapsedWidget.measured(value: "3 идут · 2 ждут · 5 готово", swatch: false, spark: false))
        XCTAssertFalse(CollapsedWidget.measured(value: "Серая", swatch: true, spark: false), "кружок темы — своя дорога")
        XCTAssertFalse(CollapsedWidget.measured(value: "47°", swatch: false, spark: true))
    }

    func testLabelAndMarkFitHalfInEveryType() {
        // «ОФОРМЛЕНИЕ», шеврон и кружок входят в половинку любым набором — подписи хватает своего ужатия (до 0,6),
        // многоточия нет.
        let half = (PimpPanelController.width - 32 - 8) / 2 - 24
        for type in PanelTypography.all {
            let label = NSAttributedString(string: "ОФОРМЛЕНИЕ", attributes: [
                .font: NSFont.systemFont(ofSize: type.label.size * 0.6, weight: .medium),
                .kern: type.label.tracking * 0.6]).size().width
            XCTAssertLessThan(label + 20 + 8 + 12, half, type.number)
        }
    }

    // MARK: #11167 — раскрытые «Токены» в половинке

    func testTokensWeekBelowOnlyInHalfWithData() {
        let spark = model(now: Date()).tokenSpark
        XCTAssertTrue(TokensTileText.weekBelow(spark, narrow: true))
        XCTAssertFalse(TokensTileText.weekBelow(spark, narrow: false), "во всю ширину линия стоит в строке")
        XCTAssertFalse(TokensTileText.weekBelow(TokenSpark(values: Array(repeating: 0, count: 7), scanned: nil), narrow: true))
        XCTAssertFalse(TokensTileText.weekBelow(nil, narrow: true))
    }

    // MARK: снимки

    func testSnapshotCollapsed() throws {
        let model = model(now: Date())
        collapse(model)
        try render(model, to: "A-11180-collapsed.png")
        model.windowColor = .plain
        try render(model, to: "A-11180-plain.png")
    }

    func testSnapshotTokensOpen() throws {
        let model = model(now: Date())
        collapse(model, except: [.tokens])
        try render(model, to: "A-11167-tokens.png")
    }
}
