import XCTest
@testable import ClaudeAX

/// Окно, в которое говорят (#8112, слово Элвиса 29.09: «в чат, который я говорю, сделай свечение поярче»):
/// приложение говорит страницам `dictating {on}`, только когда Диктатор начал или перестал писать.
final class TalkGlowTests: XCTestCase {
    func testDictatingGoesToPagesOnlyOnChangeAndAgainForNewGeneration() {
        let monitor = MicMonitor()
        monitor.windowLight = { true }
        var state = DictatorState.idle
        var sent: [Bool] = []
        monitor.dictatorState = { state }
        monitor.sendDictating = { sent.append($0); return true }
        let t0 = Date(timeIntervalSince1970: 1_000)
        // Диктатора нет — пишет или нет, не спрашиваем; страницам — «не пишет» один раз.
        monitor.tickDictating(at: t0)
        XCTAssertEqual(sent, [false])
        monitor.noteDictator(true)
        state = .recording
        monitor.tickDictating(at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(sent, [false], "чаще раза в полсекунды Диктатора не спрашиваем")
        monitor.tickDictating(at: t0.addingTimeInterval(0.6))
        XCTAssertEqual(sent, [false, true])
        monitor.tickDictating(at: t0.addingTimeInterval(1.2))
        XCTAssertEqual(sent, [false, true], "без перемены — без команды")
        // Пауза и «не прочесть» — не пишет: ложный свет хуже.
        state = .unknown
        monitor.tickDictating(at: t0.addingTimeInterval(1.8))
        XCTAssertEqual(sent, [false, true, false])
        // Новое поколение страниц — состояние заново.
        state = .recording
        monitor.tickDictating(at: t0.addingTimeInterval(2.4))
        monitor.beginGeneration()
        monitor.tickDictating(at: t0.addingTimeInterval(3.0))
        XCTAssertEqual(sent, [false, true, false, true, true])
    }

    func testNotSentKeepsTrying() {
        let monitor = MicMonitor()
        monitor.windowLight = { true }
        monitor.dictatorState = { .recording }
        monitor.noteDictator(true)
        var ok = false
        var calls = 0
        monitor.sendDictating = { _ in calls += 1; return ok }
        let t0 = Date(timeIntervalSince1970: 2_000)
        monitor.tickDictating(at: t0)
        ok = true
        monitor.tickDictating(at: t0.addingTimeInterval(0.6))
        monitor.tickDictating(at: t0.addingTimeInterval(1.2))
        XCTAssertEqual(calls, 2, "не ушла — пробуем на следующем шаге, ушла — молчим")
    }

    /// «Свет окна» Диктатора выключен — Пимп окно не подсвечивает (#8115); включили — снова светит.
    func testWindowLightSwitchOfDictatorRules() {
        let monitor = MicMonitor()
        var light = false
        var sent: [Bool] = []
        monitor.windowLight = { light }
        monitor.dictatorState = { .recording }
        monitor.sendDictating = { sent.append($0); return true }
        monitor.noteDictator(true)
        let t0 = Date(timeIntervalSince1970: 3_000)
        monitor.tickDictating(at: t0)
        XCTAssertEqual(sent, [false], "свет окна выключен — не светим")
        light = true
        monitor.tickDictating(at: t0.addingTimeInterval(0.6))
        XCTAssertEqual(sent, [false, true])
        XCTAssertTrue(DictatorLight.windowOn(nil), "ключа нет — свет включён, как у Диктатора с завода")
        XCTAssertFalse(DictatorLight.windowOn(false))
        XCTAssertFalse(DictatorLight.windowOn(NSNumber(value: false)))
    }
}
