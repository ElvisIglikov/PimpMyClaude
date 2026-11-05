import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #10308: плитки «Процессор» и «Видеокарта» в панели — в половинке любым из семи наборов шрифтов без ужатия и «…»;
/// плитка есть, только когда есть число; графики сворачиваются вместе со всеми разделами; кадры панели и листа
/// настроек (пишутся, только когда задан `PMP_SNAPSHOT_DIR`).
final class PanelLoad10308AppTests: XCTestCase {
    private static let half: CGFloat = (PimpPanelController.width - 24 - 8) / 2 - 24

    private func width(_ text: Text) -> CGFloat { NSHostingView(rootView: text.fixedSize()).fittingSize.width }

    /// Нагрузка за 2 ч с рябью; последняя точка — `cpu` и `gpu`.
    private func load(now: Date, cpu: Double, gpu: Double?) -> [MacLoadSample] {
        (0..<120).map { index -> MacLoadSample in
            let ripple = Double((index * 7919) % 17)
            let last = index == 119
            let past: (Double) -> Double = { max(0, $0 - 10 + ripple / 2) }
            return MacLoadSample(at: now.addingTimeInterval(Double(index - 119) * 60),
                                 cpu: last ? cpu : past(cpu), gpu: gpu.map { last ? $0 : past($0) })
        }
    }

    func testLoadTilesFitInHalfEveryType() {
        let mark: CGFloat = 8 + width(Text(Image(systemName: "chevron.right")).font(.system(size: 10, weight: .semibold)))
        for type in PanelTypography.all {
            for label in [PanelWidget.cpu.title, PanelWidget.gpu.title] {
                let stacked = max(width(type.label.text(label)), width(type.reading.text(MacLoad.percentText(100)))) + mark
                XCTAssertLessThanOrEqual(stacked, Self.half, "\(type.number): \(label) 100 % в половинке")
            }
        }
        let now = Date()
        for type in PanelTypography.all {
            let model = PanelWF253Scenes.evil(now: now)
            model.macLoad = load(now: now, cpu: 100, gpu: 100)
            let forms = PanelWF253Scenes.forms(model, type: type)
            for id in [PanelWidget.cpu.rawValue, PanelWidget.gpu.rawValue] {
                XCTAssertNotNil(forms[id], "\(type.number): \(id) в панели")
                XCTAssertNotEqual(forms[id], .squeezed, "\(type.number): \(id)")
            }
        }
    }

    func testTilesOnlyWithNumbersAndFoldTogether() {
        let now = Date()
        let model = PanelWF253Scenes.elvis(now: now)
        model.macLoad = load(now: now, cpu: 26, gpu: nil)
        let forms = PanelWF253Scenes.forms(model, type: .standard)
        XCTAssertNotNil(forms[PanelWidget.cpu.rawValue])
        XCTAssertNil(forms[PanelWidget.gpu.rawValue], "нет «Device Utilization %» — плитки «Видеокарта» нет")
        XCTAssertEqual(model.collapsedValue(.cpu), "26\u{00A0}%")
        XCTAssertNil(model.collapsedValue(.gpu))

        // 22.10.2026 (файл 53): график — это развёрнутый блок раскладки, каждый свой; открытие панели его не сворачивает.
        model.layout = .standard
        model.layout.setCollapsed(PanelWidget.cpu.rawValue, false)
        model.foldSections()
        XCTAssertTrue(model.opened(.cpu))
        XCTAssertFalse(model.opened(.gpu), "видеокарта своя — не раскрылась вместе с процессором")
    }

    /// Кадры: панель (порядок как у PimpTray, процессор и видеокарта раскрыты) и лист настроек с первой группой.
    func testSnapshot10308() throws {
        let now = Date()
        let model = PanelWF253Scenes.elvis(now: now)
        model.macLoad = load(now: now, cpu: 26, gpu: 16)
        try PanelWF253Scenes.render(model, type: .standard, name: "10308-1-panel")
        model.loadOpen = true
        try PanelWF253Scenes.render(model, type: .standard, name: "10308-2-load-open")
        let settings = PanelWF253Scenes.elvis(now: now)
        settings.sheet = .settings
        settings.settingsGroup = .text
        try PanelWF253Scenes.render(settings, type: .standard, name: "10308-3-settings")
    }
}
