@testable import ClaudeAX
import XCTest

/// #10215: история графиков переживает перезапуск Пимпа.
final class ChartHistoryWF269Tests: XCTestCase {
    func testTemperatureAndMemoryRowsRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let temperature = ChartHistoryFile<TemperatureRow>(url: dir.appendingPathComponent("t.json"))
        XCTAssertTrue(temperature.load().isEmpty, "нет файла — пусто")
        let hot = MacTemperatureSample(at: at, chipAverage: 55, chipMax: 61, battery: nil, state: .fair)
        temperature.save([TemperatureRow(hot)])
        XCTAssertEqual(temperature.load().map { $0.sample }, [hot])

        let memory = ChartHistoryFile<MemoryRow>(url: dir.appendingPathComponent("m.json"))
        let busy = MacMemorySample(at: at, pressure: 49, level: .warn, used: 8, total: 16, swap: nil)
        memory.save([MemoryRow(busy)])
        XCTAssertEqual(memory.load().map { $0.sample }, [busy])

        try Data("мусор".utf8).write(to: dir.appendingPathComponent("t.json"))
        XCTAssertTrue(temperature.load().isEmpty, "мусор — пусто")
    }
}
