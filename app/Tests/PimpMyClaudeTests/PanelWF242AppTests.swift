@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF242 (слово Элвиса 11.10.2026: «по умолчанию ты открываешь разделы все свёрнутые… просто все свёрнутые открываем
/// пока»; «у них выравнивания нету двух графиков… чтоб они справа сходились»).
final class PanelWF242AppTests: XCTestCase {
    private static let t0 = Date(timeIntervalSince1970: 1_791_500_000)

    func testPanelOpensWithEverySectionFolded() {
        let model = PanelModel()
        model.layout = .standard // 22.10.2026: своей свёртки у «Оформления» нет — оно строкой раскладки
        model.colorsExtraOpen = true
        model.countdownSettingsOpen = true
        model.temperatureOpen = true
        model.memoryOpen = true
        model.memoryStarterNote = "Открой окно Claude — вставить некуда"
        model.countdownHover.enter("1.8")
        model.foldSections()
        XCTAssertFalse(model.colorsExtraOpen, "дополнительное оформление за шестерёнкой — тоже")
        XCTAssertFalse(model.countdownSettingsOpen)
        // Развёрнутый блок с графиком — раскладка, она помнится (22.10.2026, файл 53): открытие панели его не трогает.
        XCTAssertTrue(model.temperatureOpen)
        XCTAssertTrue(model.memoryOpen)
        XCTAssertNil(model.memoryStarterNote)
        XCTAssertEqual(model.countdownHover, CountdownHover())
        XCTAssertEqual(model.expandedWidgets, ["temperature", "memory"])
    }

    func testExpandedWidgetsAreOpenCharts() {
        let model = PanelModel()
        model.layout = .standard // #10461: в умолчании графики свёрнуты
        XCTAssertTrue(model.expandedWidgets.isEmpty)
        model.memoryOpen = true
        XCTAssertEqual(model.expandedWidgets, ["memory"])
        model.temperatureOpen = true
        XCTAssertEqual(model.expandedWidgets, ["memory", "temperature"])
        // «Оформление», процессор и видеокарта развёрнутыми — тоже своим рядом (22.10.2026).
        model.layout = .unfolded
        XCTAssertEqual(model.expandedWidgets, ["memory", "temperature", "cpu", "gpu", "colors"])
    }

    /// Два графика — на одной оси времени: правый край и подписи часов стоят друг под другом, даже когда история
    /// одного короче (память копится с запуска, температуру включили позже).
    func testChartsShareTimeAxisAndRightEdge() {
        let model = PanelModel()
        XCTAssertNil(model.chartDomain)
        model.temperature = (0..<30).map {
            MacTemperatureSample(at: Self.t0.addingTimeInterval(Double($0 + 30) * 60), chipAverage: 50, chipMax: 60,
                                 battery: 30, state: .nominal)
        }
        model.memory = (0..<60).map {
            MacMemorySample(at: Self.t0.addingTimeInterval(Double($0) * 60), pressure: 50, level: .normal, used: 1, total: 2)
        }
        let domain = try? XCTUnwrap(model.chartDomain)
        XCTAssertEqual(domain?.first, Self.t0)
        XCTAssertEqual(domain?.last, Self.t0.addingTimeInterval(59 * 60))
        let x1: CGFloat = 300
        let temperatureEnd = domain?.x(model.temperature.last!.at, from: ChartFrame.left, to: x1)
        let memoryEnd = domain?.x(model.memory.last!.at, from: ChartFrame.left, to: x1)
        XCTAssertEqual(temperatureEnd, x1, "последняя точка — на правом краю")
        XCTAssertEqual(memoryEnd, temperatureEnd, "правые края сходятся")
        // Одна и та же минута — на одном X у обоих; короткая история начинается не с левого края, а со своего времени.
        let sameMinute = domain?.x(Self.t0.addingTimeInterval(30 * 60), from: ChartFrame.left, to: x1) ?? 0
        XCTAssertEqual(domain?.x(model.temperature[0].at, from: ChartFrame.left, to: x1), sameMinute)
        XCTAssertEqual(domain?.x(model.memory[30].at, from: ChartFrame.left, to: x1), sameMinute)
        XCTAssertGreaterThan(sameMinute, ChartFrame.left + 100)
        // Наведение: точка под курсором — ближайшая по времени на общей оси.
        XCTAssertEqual(domain?.nearest(model.memory.map { $0.at }, x: sameMinute, from: ChartFrame.left, to: x1), 30)
        XCTAssertEqual(domain?.nearest(model.temperature.map { $0.at }, x: sameMinute, from: ChartFrame.left, to: x1), 0)
        XCTAssertEqual(domain?.nearest(model.temperature.map { $0.at }, x: x1, from: ChartFrame.left, to: x1), 29)
        XCTAssertNil(domain?.nearest(model.memory.map { $0.at }, x: 2, from: ChartFrame.left, to: x1), "курсор над шкалой — не точка")
        XCTAssertNil(domain?.nearest([], x: sameMinute, from: ChartFrame.left, to: x1))
    }

    func testMemoryTipsAreShort() {
        XCTAssertTrue((3...5).contains(MemoryTipsText.tips.count), "три — пять коротких советов, без простыни")
        XCTAssertTrue(MemoryTipsText.tips.allSatisfy { $0.count <= 70 })
        XCTAssertTrue(MemoryTipsText.tips.contains { $0.contains("PimpViewer") })
    }
}
