import XCTest
@testable import ClaudeAX

/// #9818 (слово Элвиса 11.10.2026: «Температура зелёным нужно показывать, память тоже… эта штука его должна
/// успокаивать… зелёная, жёлтая и красная, когда всё плохо»): цвет каждой точки графиков — по смыслу macOS.
final class Fix9818Tests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824
    private static let mb: UInt64 = 1_048_576
    private static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func memory(_ minute: Double, swap: UInt64?, level: MemoryPressureLevel? = .normal,
                        total: UInt64 = 16 * Fix9818Tests.gb) -> MacMemorySample {
        MacMemorySample(at: Self.t0.addingTimeInterval(minute * 60), pressure: 50, level: level,
                        used: 10 * Self.gb, total: total, swap: swap)
    }

    func testMemoryColorsFollowSwapLikeActivityMonitor() {
        let history = [
            memory(0, swap: 300 * Self.mb),           // старый хвост — зелёный
            memory(1, swap: 500 * Self.mb),           // вытесняется прямо сейчас — красный
            memory(2, swap: 500 * Self.mb),           // встал, немного — зелёный
            memory(3, swap: 4 * Self.gb),             // скачок до четверти памяти — растёт: красный
            memory(4, swap: 4 * Self.gb),             // держится высоко — жёлтый
            memory(5, swap: 3 * Self.gb),             // убывает, ниже четверти — зелёный
        ]
        XCTAssertEqual(MacMemory.health(history), [.good, .bad, .good, .bad, .warn, .good])
        // «Нагружена» для старых мест — всё, что не зелёное.
        XCTAssertEqual(MacMemory.loaded(history), [false, true, false, true, true, false])
        // Своп известен — решает он: давление macOS при спокойном свопе цвета не даёт (WF242).
        XCTAssertEqual(MacMemory.health([memory(0, swap: 0, level: .critical)]), [.good])
        // Своп не читается — давление памяти macOS, как в Мониторинге системы.
        XCTAssertEqual(MacMemory.health([memory(0, swap: nil, level: .normal), memory(1, swap: nil, level: .warn),
                                         memory(2, swap: nil, level: .critical), memory(3, swap: nil, level: nil)]),
                       [.good, .warn, .bad, .good])
        XCTAssertTrue(MacMemory.health([]).isEmpty)
    }

    func testTemperatureColorsFollowMacOSThermalState() {
        XCTAssertEqual(MacTemperature.health(.nominal), .good)
        XCTAssertEqual(MacTemperature.health(.fair), .warn)
        XCTAssertEqual(MacTemperature.health(.serious), .bad)
        XCTAssertEqual(MacTemperature.health(.critical), .bad)
        let history = [ProcessInfo.ThermalState.nominal, .fair, .serious].enumerated().map {
            MacTemperatureSample(at: Self.t0.addingTimeInterval(Double($0.offset) * 60), chipAverage: 50, chipMax: 55,
                                 battery: 30, state: $0.element)
        }
        XCTAssertEqual(MacTemperature.health(history), [.good, .warn, .bad])
        // С 03.11.2026 и по градусам (`docs/decisions/2026-11-03-oformlenie.md`, «Нагрев»): с 70° жёлтый, с 90° красный,
        // даже когда macOS спокойна; оценка macOS хуже градусов — берётся она.
        let hot = { (max: Double, state: ProcessInfo.ThermalState) in
            MacTemperature.health(MacTemperatureSample(at: Self.t0, chipAverage: max - 5, chipMax: max, battery: 30, state: state))
        }
        XCTAssertEqual(hot(69, .nominal), .good)
        XCTAssertEqual(hot(70, .nominal), .warn)
        XCTAssertEqual(hot(90, .nominal), .bad)
        XCTAssertEqual(hot(60, .serious), .bad)
        XCTAssertLessThan(MacHealth.good, MacHealth.warn)
        XCTAssertLessThan(MacHealth.warn, MacHealth.bad)
    }
}
