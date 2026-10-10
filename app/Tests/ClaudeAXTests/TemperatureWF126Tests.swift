import XCTest
@testable import ClaudeAX

/// Температура в панели (#8898, WF126 «Кодинг 3»): какие датчики считаются чипом, история 3 ч, подписи, шкала.
final class TemperatureWF126Tests: XCTestCase {
    private static let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    private func sample(_ minute: Double, _ chip: Double?, battery: Double? = 30, hot: Double? = nil,
                        state: ProcessInfo.ThermalState = .nominal) -> MacTemperatureSample {
        MacTemperatureSample(at: Self.t0.addingTimeInterval(minute * 60), chipAverage: chip,
                             chipMax: chip.map { hot ?? $0 + 4 }, battery: battery, state: state)
    }

    func testChipUsesDieSensorsOnly() {
        let sensors: [(name: String, value: Double)] = [
            ("PMU tdie1", 50), ("PMU tdie2", 58), ("PMU tdev1", 40), ("PMU tcal", 51.8),
            ("gas gauge battery", 31), ("NAND CH0 temp", 39), ("PMU tdie3", -127),
        ]
        let chip = MacTemperature.chip(sensors)
        XCTAssertEqual(chip?.count, 2, "мусор −127, tcal, батарея и NAND не в счёт")
        XCTAssertEqual(chip?.average, 54)
        XCTAssertEqual(chip?.max, 58)
    }

    func testChipFallsBackToOtherPMUWithoutDie() {
        let chip = MacTemperature.chip([("PMU tdev1", 40), ("PMU tdev2", 44), ("PMU tcal", 51.8), ("NAND CH0 temp", 39)])
        XCTAssertEqual(chip?.average, 42)
        XCTAssertNil(MacTemperature.chip([("NAND CH0 temp", 39), ("gas gauge battery", 30)]), "без PMU чипа нет")
        XCTAssertNil(MacTemperature.chip([]))
    }

    func testBatteryRaw() {
        XCTAssertEqual(MacTemperature.battery(raw: 3050), 30.5)
        XCTAssertNil(MacTemperature.battery(raw: 0))
        XCTAssertNil(MacTemperature.battery(raw: nil))
    }

    func testHistoryKeepsThreeHoursAndSkipsEmpty() {
        var history: [MacTemperatureSample] = []
        for minute in 0..<200 { history = MacTemperature.append(sample(Double(minute), 50), to: history) }
        XCTAssertEqual(history.count, 180)
        XCTAssertEqual(history.first?.at, Self.t0.addingTimeInterval(20 * 60))
        let empty = MacTemperatureSample(at: Self.t0.addingTimeInterval(300 * 60), chipAverage: nil, chipMax: nil,
                                         battery: nil, state: .fair)
        XCTAssertEqual(MacTemperature.append(empty, to: history).count, 180, "нет градусов — точки нет")
        let late = MacTemperature.append(sample(500, 50), to: history)
        XCTAssertEqual(late.count, 1, "после долгого сна старое старше 3 ч уходит")
    }

    func testBatteryIsFallbackValue() {
        let point = sample(0, nil, battery: 33)
        XCTAssertEqual(point.value, 33)
        XCTAssertFalse(point.isChip)
        XCTAssertEqual(sample(0, 54).value, 54)
    }

    func testWordsAndCaption() {
        XCTAssertEqual(MacTemperature.word(.nominal), "не нагрет")
        XCTAssertEqual(MacTemperature.word(.fair), "слегка нагрет")
        XCTAssertEqual(MacTemperature.word(.serious), "сильно нагрет")
        XCTAssertEqual(MacTemperature.word(.critical), "перегрет")
        let history = [sample(0, 47.2), sample(90, 70.6), sample(180, 54, battery: 34.4, hot: 58, state: .fair)]
        XCTAssertEqual(MacTemperature.caption(history),
                       "за 3 ч: 47–71° · батарея 34° · macOS: слегка нагрет")
        XCTAssertEqual(MacTemperature.caption([sample(0, nil, battery: 33)]), "", "«macOS: не нагрет» не пишем (#9020)")
        XCTAssertEqual(MacTemperature.caption([sample(0, 50), sample(12, 50)]),
                       "за 12 мин: 50° · батарея 30°")
        XCTAssertEqual(MacTemperature.caption([]), "")
    }

    func testScaleStepsOfTwenty() {
        let scale = MacTemperature.scale([sample(0, 47), sample(1, 71)])
        XCTAssertEqual(scale.low, 40)
        XCTAssertEqual(scale.high, 80)
        XCTAssertEqual(scale.ticks, [40, 60, 80])
        XCTAssertEqual(MacTemperature.scale([sample(0, 60)]).ticks, [60, 80], "ровная линия — не уже 20°")
    }

    func testSegmentsBreakOnGapAndNearest() {
        let history = [sample(0, 50), sample(1, 51), sample(2, 52), sample(30, 60), sample(31, 61)]
        XCTAssertEqual(MacTemperature.segments(history), [[0, 1, 2], [3, 4]])
        XCTAssertEqual(MacTemperature.nearest(history, fraction: 0), 0)
        XCTAssertEqual(MacTemperature.nearest(history, fraction: 1), 4)
        XCTAssertEqual(MacTemperature.nearest(history, fraction: 0.9), 3)
        XCTAssertEqual(MacTemperature.nearest([sample(0, 50)], fraction: 0.5), 0)
        XCTAssertNil(MacTemperature.nearest([], fraction: 0.5))
    }
}
