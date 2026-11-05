import AppKit
@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// #9818: два графика — общее левое поле по самой широкой подписи шкалы обоих; советы у температуры, как у памяти.
final class Fix9818AppTests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testChartsShareLeftEdgeWhateverTheLabels() {
        XCTAssertEqual(ChartFrame.left(labels: []), ChartFrame.left)
        XCTAssertEqual(ChartFrame.left(labels: ["100°", "16 ГБ", "0"]), ChartFrame.left, "обычные подписи — прежнее поле")
        let wide = ChartFrame.left(labels: ["128 ГБ", "100°"])
        XCTAssertGreaterThan(wide, ChartFrame.left, "«128 ГБ» не вылезает за край — поле шире")

        let model = PanelModel()
        model.temperature = [MacTemperatureSample(at: now, chipAverage: 55, chipMax: 60, battery: 30, state: .nominal)]
        model.memory = [MacMemorySample(at: now, pressure: 50, level: .normal, used: 60 * Self.gb, total: 128 * Self.gb)]
        XCTAssertEqual(model.chartLeft, wide, "поле одно на оба графика — по подписи памяти")
        model.memory = [MacMemorySample(at: now, pressure: 50, level: .normal, used: 6 * Self.gb, total: 16 * Self.gb)]
        XCTAssertEqual(model.chartLeft, ChartFrame.left)
    }

    /// #10206: «закрой вкладки» и «останови сборки» сняты словом Элвиса — один совет про подставку.
    func testTemperatureTipsAreShortLikeMemoryTips() {
        XCTAssertEqual(TemperatureTipsText.tips.count, 1)
        XCTAssertFalse(TemperatureTipsText.tips.contains { $0.contains("вкладк") || $0.contains("сборк") })
        XCTAssertTrue(TemperatureTipsText.tips.allSatisfy { $0.count <= 50 })
        XCTAssertFalse(TemperatureTipsText.title.isEmpty)
        XCTAssertFalse(TemperatureTipsText.tips.contains { $0.contains("42") || $0.contains("остыл") },
                       "#10994: «у нас Мак остыл до 42°» снято словом Элвиса")
    }
}
