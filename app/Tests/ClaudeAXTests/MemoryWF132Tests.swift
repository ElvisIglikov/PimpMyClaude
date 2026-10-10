import XCTest
@testable import ClaudeAX

/// Нагрузка на память в панели (#9082, WF132 «Память»): разбор чисел ядра, история 3 ч, подпись, полосы по цвету.
final class MemoryWF132Tests: XCTestCase {
    private static let t0 = Date(timeIntervalSince1970: 1_791_000_000)
    private static let gb: UInt64 = 1_073_741_824

    private func sample(_ minute: Double, _ pressure: Double?, _ level: MemoryPressureLevel? = .normal,
                        used: UInt64? = 6 * MemoryWF132Tests.gb) -> MacMemorySample {
        MacMemorySample(at: Self.t0.addingTimeInterval(minute * 60), pressure: pressure, level: level,
                        used: used, total: 8 * Self.gb)
    }

    func testLevelAndPressureFromKernel() {
        XCTAssertEqual(MacMemory.level(raw: 1), .normal)
        XCTAssertEqual(MacMemory.level(raw: 2), .warn)
        XCTAssertEqual(MacMemory.level(raw: 4), .critical)
        XCTAssertNil(MacMemory.level(raw: 3))
        XCTAssertNil(MacMemory.level(raw: nil))
        XCTAssertEqual(MacMemory.pressure(available: 45), 55)
        XCTAssertEqual(MacMemory.pressure(available: 100), 0)
        XCTAssertNil(MacMemory.pressure(available: -1))
        XCTAssertNil(MacMemory.pressure(available: 101))
        XCTAssertNil(MacMemory.pressure(available: nil))
    }

    func testUsedLikeActivityMonitor() {
        // vm_stat этого Мака 08.10: внутренние 147 591, очищаемые 52, неперемещаемые 95 181, сжатые 171 353, страница 16 КБ.
        let used = MacMemory.used(internalPages: 147_591, purgeable: 52, wired: 95_181, compressed: 171_353, pageSize: 16_384)
        XCTAssertEqual(used, (147_539 + 95_181 + 171_353) * 16_384)
        XCTAssertEqual(MacMemory.gigabytes(used), "6,3")
        XCTAssertEqual(MacMemory.used(internalPages: 10, purgeable: 20, wired: 1, compressed: 1, pageSize: 1), 2,
                       "очищаемых больше внутренних — без переполнения")
        XCTAssertEqual(MacMemory.gigabytes(8 * Self.gb), "8")
    }

    func testValueFallsBackToUsedShare() {
        XCTAssertEqual(sample(0, 55).value, 55)
        XCTAssertEqual(sample(0, nil, used: 2 * Self.gb).value, 25)
        XCTAssertNil(sample(0, nil, used: nil).value)
    }

    func testHistoryKeepsThreeHoursAndSkipsEmpty() {
        var history: [MacMemorySample] = []
        for minute in 0..<200 { history = MacMemory.append(sample(Double(minute), 50), to: history) }
        XCTAssertEqual(history.count, 180)
        XCTAssertEqual(history.first?.at, Self.t0.addingTimeInterval(20 * 60))
        XCTAssertEqual(MacMemory.append(sample(300, nil, used: nil), to: history).count, 180, "нет чисел — точки нет")
        XCTAssertEqual(MacMemory.append(sample(500, 50), to: history).count, 1, "после долгого сна старое уходит")
    }

    func testWordsAndCaptionAgree() {
        XCTAssertEqual(MacMemory.word(.normal), "в норме")
        XCTAssertEqual(MacMemory.word(.warn), "под нагрузкой")
        XCTAssertEqual(MacMemory.word(.critical), "не хватает")
        let history = [sample(0, 40.4), sample(90, 61.6, .warn), sample(180, 55.2, .warn)]
        // WF164 (31.5): число «сейчас» одно — в строке плитки, в подписи его нет. WF177: подпись — в ГБ занятого.
        XCTAssertEqual(MacMemory.caption(history), "под нагрузкой · за 3 ч без изменений")
        XCTAssertEqual(MacMemory.captionParts(history).word, "под нагрузкой", "слово рисуется цветом уровня")
        let growing = [sample(0, 55, used: 5 * Self.gb), sample(12, 55.4, used: 6 * Self.gb + Self.gb * 3 / 10)]
        XCTAssertEqual(MacMemory.caption(growing), "в норме · за 12 мин от 5 до 6,3 ГБ")
        XCTAssertEqual(MacMemory.caption([sample(0, 30, nil)]), "", "одна точка, уровня не знаем — подписи нет")
        XCTAssertEqual(MacMemory.caption([sample(0, 40, used: nil), sample(30, 62, used: nil)]),
                       "в норме · за 30 мин от 40 до 62 %", "занятого не знаем — как раньше, проценты нагрузки")
        XCTAssertEqual(MacMemory.caption([]), "")
    }

    func testCaptionRangeAlwaysHoldsRowNumber() {
        // Число строки — `nowText` (десятые ГБ), «от A до B» — по тем же округлённым точкам: противоречия нет.
        let first = 5 * Self.gb + Self.gb / 2
        for step in 0...160 {
            let used = UInt64(Double(step) / 20 * Double(Self.gb))
            let history = [sample(0, 50, used: first), sample(1, 50, used: used)]
            let caption = MacMemory.caption(history)
            XCTAssertEqual(MacMemory.nowText(history), MacMemory.gigabytes(used) + " ГБ")
            let a = MacMemory.tenths(first), b = MacMemory.tenths(used)
            let low = MacMemory.tenthsText(min(a, b)), high = MacMemory.tenthsText(max(a, b))
            XCTAssertTrue(a == b ? caption.contains("без изменений") : caption.contains("от \(low) до \(high) ГБ"), caption)
        }
    }

    func testBandsSplitByLevelAndGap() {
        let history = [sample(0, 40), sample(1, 42), sample(2, 60, .warn), sample(3, 61, .warn), sample(4, 45),
                       sample(30, 50, nil), sample(31, 90, .critical)]
        let bands = MacMemory.bands(history)
        XCTAssertEqual(bands.map { $0.level }, [.normal, .warn, .normal, .normal, .critical])
        XCTAssertEqual(bands.map { $0.indices }, [[0, 1, 2], [2, 3, 4], [4], [5, 6], [6]],
                       "соседние полосы делят точку смены; сон Мака — разрыв")
        XCTAssertEqual(MacMemory.segments(history), [[0, 1, 2, 3, 4], [5, 6]])
        XCTAssertTrue(MacMemory.bands([]).isEmpty)
    }

    func testNearest() {
        let history = [sample(0, 50), sample(1, 51), sample(30, 60)]
        XCTAssertEqual(MacMemory.nearest(history, fraction: 0), 0)
        XCTAssertEqual(MacMemory.nearest(history, fraction: 1), 2)
        XCTAssertEqual(MacMemory.nearest([sample(0, 50)], fraction: 0.5), 0)
        XCTAssertNil(MacMemory.nearest([], fraction: 0.5))
    }

    func testLiveReadIsPlausibleAndCheap() {
        let read = MacMemoryMonitor().measureOnce()
        XCTAssertNotNil(read.sample.level, "kern.memorystatus_vm_pressure_level читается без прав")
        XCTAssertNotNil(read.sample.pressure)
        XCTAssertTrue((0...100).contains(read.sample.value ?? -1))
        XCTAssertGreaterThan(read.sample.total, 0)
        XCTAssertTrue((1...(read.sample.total)).contains(read.sample.used ?? 0))
        XCTAssertLessThan(read.milliseconds, 50)
    }
}
