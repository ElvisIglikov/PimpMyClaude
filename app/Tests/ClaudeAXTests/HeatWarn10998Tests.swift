import XCTest
@testable import ClaudeAX

/// Перегрев Мака (#10998): панель показывает самый горячий датчик, баннер — по thermalState или 95° два чтения
/// подряд, не чаще раза в 30 мин, с тремя верхними процессами из `ps`.
final class HeatWarn10998Tests: XCTestCase {
    private static let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func sample(_ minute: Double, average: Double? = 52, max: Double?, battery: Double? = 30,
                        state: ProcessInfo.ThermalState = .nominal) -> MacTemperatureSample {
        MacTemperatureSample(at: Self.t0.addingTimeInterval(minute * 60), chipAverage: average, chipMax: max,
                             battery: battery, state: state)
    }

    private func at(_ minute: Double) -> Date { Self.t0.addingTimeInterval(minute * 60) }

    func testValueIsHottestSensorNotAverage() {
        XCTAssertEqual(sample(0, average: 52, max: 88).value, 88, "Элвис: «52 — вовсе не 52»")
        XCTAssertEqual(sample(0, average: 52, max: nil).value, 52, "старая строка файла без максимума — среднее")
        XCTAssertEqual(sample(0, average: nil, max: nil, battery: 33).value, 33)
        XCTAssertFalse(sample(0, average: nil, max: nil, battery: 33).isChip)
        XCTAssertTrue(sample(0, average: nil, max: 70).isChip)
    }

    func testReasonByMacOSStateRightAway() {
        XCTAssertEqual(MacHeatWarn.reason([sample(0, max: 80, state: .serious)], now: at(0)), .state(.serious, degrees: 80))
        XCTAssertEqual(MacHeatWarn.reason([sample(0, average: nil, max: nil, battery: 40, state: .critical)], now: at(1)),
                       .state(.critical, degrees: nil), "без чипа — словом macOS, без градусов батареи")
        XCTAssertNil(MacHeatWarn.reason([sample(0, max: 80, state: .fair)], now: at(0)), "«слегка нагрет» — не повод")
    }

    func testReasonByDegreesNeedsTwoReadingsInARow() {
        XCTAssertNil(MacHeatWarn.reason([sample(0, max: 99)], now: at(0)), "одно чтение — миг, не перегрев")
        XCTAssertEqual(MacHeatWarn.reason([sample(0, max: 96), sample(1, max: 97.4)], now: at(1)), .degrees(97))
        XCTAssertNil(MacHeatWarn.reason([sample(0, max: 96), sample(1, max: 94.9)], now: at(1)), "ниже 95 — тихо")
        XCTAssertNil(MacHeatWarn.reason([sample(0, max: 80), sample(1, max: 99)], now: at(1)))
        XCTAssertNil(MacHeatWarn.reason([sample(0, max: 99), sample(10, max: 99)], now: at(10)), "между ними сон — не подряд")
        XCTAssertNil(MacHeatWarn.reason([sample(0, average: nil, max: nil, battery: 99),
                                         sample(1, average: nil, max: nil, battery: 99)], now: at(1)),
                     "батарея порогом не служит")
        XCTAssertEqual(MacHeatWarn.reason([sample(0, average: 60, max: 96), sample(1, average: 60, max: 96)], now: at(1)),
                       .degrees(96), "среднее 60 не прячет горячий датчик")
    }

    func testStaleSampleIsNotAReason() {
        XCTAssertNil(MacHeatWarn.reason([sample(0, max: 80, state: .critical)], now: at(6)), "точке 6 мин — Мак спал")
        XCTAssertNil(MacHeatWarn.reason([], now: at(0)))
    }

    func testCooldown() {
        XCTAssertTrue(MacHeatWarn.allowed(last: nil, now: at(0)))
        XCTAssertFalse(MacHeatWarn.allowed(last: at(0), now: at(29)))
        XCTAssertTrue(MacHeatWarn.allowed(last: at(0), now: at(30)))
        XCTAssertTrue(MacHeatWarn.allowed(last: at(10), now: at(0)), "часы ушли назад — не молчим вечно")
    }

    func testWarnerPostsOnceInThirtyMinutes() {
        let suite = testSuiteName()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = DispatchQueue(label: "heat-test")
        let top = [MacHeatWarn.ProcessLoad(name: "WindowServer (экран и окна)", cpu: 40)]
        let warner = MacHeatWarner(defaults: defaults, readTop: { top }, background: queue)
        let hot = [sample(0, max: 90, state: .serious)]
        var posted: [(String, String)] = []
        XCTAssertNotNil(warner.check(hot, gpu: 76, now: at(0)) { posted.append(($0, $1)) })
        XCTAssertNil(warner.check(hot + [sample(1, max: 90, state: .serious)], gpu: 76, now: at(1)) { posted.append(($0, $1)) },
                     "через минуту — молчим")
        XCTAssertEqual(warner.last, at(0))
        let again = MacHeatWarner(defaults: defaults, readTop: { top }, background: queue)
        XCTAssertNil(again.check([sample(10, max: 90, state: .serious)], gpu: nil, now: at(10)) { _, _ in },
                     "перезапуск Пимпа баннер не повторяет")
        XCTAssertNotNil(again.check([sample(31, max: 90, state: .serious)], gpu: nil, now: at(31)) { _, _ in })
        let done = expectation(description: "баннер")
        queue.async { DispatchQueue.main.async { done.fulfill() } }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(posted.count, 1)
        XCTAssertEqual(posted.first?.0, "Мак перегрелся")
        XCTAssertEqual(posted.first?.1,
                       "macOS: сильно нагрет, чип 90° — Мак сбавляет частоту. Грузят: WindowServer (экран и окна) 40\u{00A0}%. Видеокарта 76\u{00A0}%.")
    }

    func testNotHotNoMark() {
        let suite = testSuiteName()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let warner = MacHeatWarner(defaults: defaults, readTop: { [] })
        XCTAssertNil(warner.check([sample(0, max: 70)], gpu: 90, now: at(0)) { _, _ in XCTFail("не горячо") })
        XCTAssertNil(warner.last)
    }

    func testHumanNames() {
        XCTAssertEqual(MacHeatWarn.humanName("/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
                       "WindowServer (экран и окна)")
        XCTAssertEqual(MacHeatWarn.humanName("/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)"),
                       "Claude")
        XCTAssertEqual(MacHeatWarn.humanName("/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)"),
                       "Chrome")
        XCTAssertEqual(MacHeatWarn.humanName("/Applications/Windows App.app/Contents/MacOS/Windows App"), "Windows App")
        XCTAssertEqual(MacHeatWarn.humanName("kernel_task"), "kernel_task (macOS гасит жар)")
        XCTAssertEqual(MacHeatWarn.humanName("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend"),
                       "сборка Swift", "известная программа сильнее .app вокруг")
        XCTAssertEqual(MacHeatWarn.humanName("/opt/homebrew/bin/node"), "node (скрипты и тесты)")
        XCTAssertEqual(MacHeatWarn.humanName("/usr/local/bin/someTool"), "someTool")
    }

    func testParsePSGroupsHelpersAndSorts() {
        let output = """
          0.0 /sbin/launchd
         45.2 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
         25.0 kernel_task
         20.1 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)
         15,5 /Applications/Claude.app/Contents/Frameworks/Claude Helper (GPU).app/Contents/MacOS/Claude Helper (GPU)
         30.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
          9.0 /bin/ps
        мусор
        """
        let loads = MacHeatWarn.parse(output)
        XCTAssertEqual(loads.map(\.name), ["WindowServer (экран и окна)", "Claude", "Chrome", "kernel_task (macOS гасит жар)"])
        XCTAssertEqual(loads[1].cpu, 35.6, accuracy: 0.001, "помощники Claude сложены, запятая — тоже число")
        let text = MacHeatWarn.text(.degrees(97), top: loads, gpu: 30)
        XCTAssertEqual(text.body, "Чип 97° уже две минуты. Грузят: WindowServer (экран и окна) 45\u{00A0}%, Claude 36\u{00A0}%, Chrome 30\u{00A0}%.",
                       "три верхних; видеокарта ниже 50 % не пишется")
        XCTAssertEqual(MacHeatWarn.text(.degrees(97), top: [], gpu: nil).body, "Чип 97° уже две минуты.", "ps не ответил")
        XCTAssertTrue(MacHeatWarn.parse("").isEmpty)
    }
}
