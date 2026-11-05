@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// Слово Элвиса 22.10.2026: хорошие показатели в свёрнутых строках — цветом (с 03.11.2026 цветом акцента), «Терминалы» по умолчанию свёрнуты.
final class PanelGreen1022Tests: XCTestCase {
    func testCollapsedToneByHealth() {
        let model = PanelModel()
        let now = Date()
        let good = PanelColor.hex(model.shownAccent.hex)
        XCTAssertNil(model.collapsedTone(.cpu), "числа нет — цветом текста")
        model.macLoad = [MacLoadSample(at: now, cpu: 20, gpu: 37)]
        XCTAssertEqual(model.collapsedTone(.cpu), good)
        XCTAssertEqual(model.collapsedTone(.gpu), good)
        model.macLoad = [MacLoadSample(at: now, cpu: 75, gpu: 95)]
        XCTAssertEqual(model.collapsedTone(.cpu), PanelColor.warn)
        XCTAssertEqual(model.collapsedTone(.gpu), PanelColor.bad)
        model.temperature = [MacTemperatureSample(at: now, chipAverage: 36, chipMax: 40, battery: nil, state: .nominal)]
        XCTAssertEqual(model.collapsedTone(.temperature), good)
        model.temperature = [MacTemperatureSample(at: now, chipAverage: 80, chipMax: 95, battery: nil, state: .serious)]
        XCTAssertEqual(model.collapsedTone(.temperature), PanelColor.bad)
        XCTAssertNil(model.collapsedTone(.tokens), "токены и лимиты не красим")
    }

    func testGoodStaysApartFromAlarmColors() {
        for accent in PMPAccent.allCases {
            let color = PanelColor.hex(accent.hex)
            let alarm = accent == .red || accent == .amber
            XCTAssertEqual(PanelColor.good(color), alarm ? PanelColor.text : color, accent.rawValue)
            XCTAssertEqual(chartColor(.good, good: color), PanelColor.good(color), accent.rawValue)
        }
    }

    func testTerminalsFoldedByDefault() {
        XCTAssertEqual(PanelWidgetLayout.standard.item(PanelWidget.terminals.rawValue)?.collapsed, true)
    }
}
