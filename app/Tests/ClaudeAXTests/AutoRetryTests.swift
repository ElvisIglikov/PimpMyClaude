import XCTest
@testable import ClaudeAX

/// «Повторять при ошибке сервера» (#6936, К-AR): команда `auto-retry`, умолчание «выключено», интервал 2/5/10.
final class AutoRetryTests: XCTestCase {
    /// Поля после id, action, at — on, every; значения строками, как у `hide-tools`.
    func testFieldsOrder() {
        let body = CommandChannel.payload(action: AutoRetry.action, fields: AutoRetry.fields(on: true, every: 10),
                                          id: "1-0001", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(body, #"{"id":"1-0001","action":"auto-retry","at":"1970-01-01T00:00:00Z","on":"true","every":"10"}"#)
        let off = CommandChannel.payload(action: AutoRetry.action, fields: AutoRetry.fields(on: false, every: 5))
        let json = try? JSONSerialization.jsonObject(with: Data(off.utf8)) as? [String: Any]
        XCTAssertEqual(json?["on"] as? String, "false")
        XCTAssertEqual(json?["every"] as? String, "5")
        let at = off.range(of: #""at""#)!.lowerBound
        let on = off.range(of: #""on""#)!.lowerBound
        let every = off.range(of: #""every""#)!.lowerBound
        XCTAssertTrue(at < on && on < every, "порядок полей: at, on, every")
    }

    /// Нет ключа — выключено (решение WF108), интервал — 5 минут.
    func testDefaultOff() throws {
        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(AutoRetry.isOn(defaults))
        XCTAssertEqual(AutoRetry.every(defaults), 5)
        defaults.set(true, forKey: AutoRetry.onKey)
        defaults.set(2, forKey: AutoRetry.everyKey)
        XCTAssertTrue(AutoRetry.isOn(defaults))
        XCTAssertEqual(AutoRetry.every(defaults), 2)
        defaults.set(7, forKey: AutoRetry.everyKey)
        XCTAssertEqual(AutoRetry.every(defaults), 5)
    }

    /// Вне 2/5/10 — 5: и в чтении, и в команде.
    func testMinutesOutsideChoices() {
        XCTAssertEqual(AutoRetry.minutes(3), 5)
        XCTAssertEqual(AutoRetry.minutes(0), 5)
        XCTAssertEqual(AutoRetry.minutes(nil), 5)
        XCTAssertEqual(AutoRetry.minutes("ten"), 5)
        XCTAssertEqual(AutoRetry.minutes("10"), 10)
        XCTAssertEqual(AutoRetry.minutes(2), 2)
        XCTAssertEqual(AutoRetry.fields(on: true, every: 7).last?.key, "every")
        if case .string(let value)? = AutoRetry.fields(on: true, every: 7).last?.value {
            XCTAssertEqual(value, "5")
        } else {
            XCTFail("every — строкой")
        }
    }

    /// Выбор уходит страницам до трёх раз за поколение; «выкл» тоже уходит — новым поколением.
    func testSwitchResendsPerGeneration() {
        let sender = AutoRetrySwitch()
        let t0 = Date(timeIntervalSince1970: 1_000)
        var sent: [[String: Any]] = []
        func send(_ fields: [(key: String, value: CommandValue)]) -> Bool {
            let json = CommandChannel.payload(action: AutoRetry.action, fields: fields)
            sent.append((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:])
            return true
        }
        XCTAssertFalse(sender.configure(on: false, every: 5), "умолчание: выкл, 5 — выбор не сменился")
        sender.tick(titles: ["A"], at: t0, send: send)
        XCTAssertEqual(sent.last?["on"] as? String, "false", "«выкл» тоже уходит: старое true страницы не переживёт выбор")
        XCTAssertTrue(sender.configure(on: true, every: 10))
        XCTAssertFalse(sender.configure(on: true, every: 10), "тот же выбор — нового поколения нет")
        sender.tick(titles: ["A"], at: t0.addingTimeInterval(1), send: send)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.last?["on"] as? String, "true")
        XCTAssertEqual(sent.last?["every"] as? String, "10")
        // Тот же состав окон — не повторяем; новые окна — повтор, но не больше трёх за поколение.
        sender.tick(titles: ["A"], at: t0.addingTimeInterval(10), send: send)
        XCTAssertEqual(sent.count, 2)
        sender.tick(titles: ["A", "B"], at: t0.addingTimeInterval(20), send: send)
        sender.tick(titles: ["A", "B", "C"], at: t0.addingTimeInterval(30), send: send)
        sender.tick(titles: ["A", "B", "C", "D"], at: t0.addingTimeInterval(40), send: send)
        XCTAssertEqual(sent.count, 4, "не больше трёх за поколение")
        sender.beginGeneration()
        sender.tick(titles: ["A"], at: t0.addingTimeInterval(50), send: send)
        XCTAssertEqual(sent.count, 5, "новое поколение страниц получает выбор снова")
        XCTAssertTrue(sender.configure(on: false, every: 10))
        sender.tick(titles: ["A"], at: t0.addingTimeInterval(60), send: send)
        XCTAssertEqual(sent.last?["on"] as? String, "false")
    }
}
