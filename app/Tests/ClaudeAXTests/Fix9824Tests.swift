import XCTest
@testable import ClaudeAX

/// #9824 (слово Элвиса 11.10.2026: «показывать последнее значение подписки, а не минус… Надо как-то помечать, что там
/// неизвестно»): свежих лимитов нет — значок и панель показывают последнее известное значение бледным и с давностью;
/// оно переживает перезапуск PMP (`LimitsMemory`).
final class Fix9824Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let installed = StatusIcon.Patch.installed(version: "2.9939.2", loader: 8)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func limits(age: TimeInterval, week: Int = 85, source: String? = "api") -> ClaudeLimits {
        ClaudeLimits(at: now.addingTimeInterval(-age), plan: "Max 20x",
                     fiveHour: .init(used: 24, resetsAt: now.addingTimeInterval(4 * 3600)),
                     weekly: .init(used: week, resetsAt: now.addingTimeInterval(3 * 86_400)),
                     fable: .init(used: 0, resetsAt: nil), source: source)
    }

    func testStaleLimitsShowLastKnownNumberQuietly() {
        let look = StatusIcon.look(mode: .week, limits: limits(age: 25 * 60, week: 95), patch: installed, phase: .idle,
                                   now: now, calendar: utc)
        XCTAssertEqual(look.number, 95, "последнее известное вместо «—»")
        XCTAssertTrue(look.stale)
        XCTAssertEqual(look.level, .normal, "тревогу по старой цифре не поднимаем")
        XCTAssertTrue(look.toolTip.hasPrefix("PMP — неделя: израсходовано 95 % — 25 мин назад, свежие придут"), look.toolTip)

        let fresh = StatusIcon.look(mode: .week, limits: limits(age: 60, week: 95), patch: installed, phase: .idle, now: now)
        XCTAssertFalse(fresh.stale)
        XCTAssertEqual(fresh.level, .critical)
        XCTAssertFalse(fresh.toolTip.contains("назад"))

        let three = StatusIcon.look(mode: .three, limits: limits(age: 3600, week: 95), patch: installed, phase: .idle, now: now)
        XCTAssertEqual(three.bars, [24, 95, 0])
        XCTAssertEqual(three.barLevels, [.normal, .normal, .normal])
        XCTAssertTrue(three.stale)

        // Ни источника, ни времени — знать нечего: честный прочерк.
        XCTAssertNil(StatusIcon.look(mode: .week, limits: limits(age: 3600, source: nil), patch: installed, phase: .idle,
                                     now: now).number)
        XCTAssertNil(StatusIcon.look(mode: .week, limits: nil, patch: installed, phase: .idle, now: now).number)
    }

    func testStaleText() {
        XCTAssertNil(StatusIcon.staleText(limits(age: 600), now: now, calendar: utc), "10 минут — ещё свежие")
        XCTAssertEqual(StatusIcon.staleText(limits(age: 601), now: now, calendar: utc), "10 мин назад")
        XCTAssertEqual(StatusIcon.staleText(limits(age: 3 * 3600 + 120), now: now, calendar: utc), "3 ч назад")
        // now = 2027-01-15 08:00 UTC.
        XCTAssertEqual(StatusIcon.staleText(limits(age: 13 * 3600), now: now, calendar: utc), "вчера в 19:00")
        XCTAssertEqual(StatusIcon.staleText(limits(age: 3 * 86_400), now: now, calendar: utc), "12.01 в 08:00")
        XCTAssertNil(StatusIcon.staleText(nil, now: now))
    }

    func testMemorySurvivesRestartAndKeepsTheNewest() throws {
        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(LimitsMemory.load(defaults))
        let old = limits(age: 3600, week: 40)
        XCTAssertEqual(LimitsMemory.remember(old, defaults)?.weekly?.used, 40)
        // «Перезапуск»: читаем с диска то же.
        let loaded = try XCTUnwrap(LimitsMemory.load(defaults))
        XCTAssertEqual(loaded.weekly?.used, 40)
        XCTAssertEqual(loaded.fiveHour?.used, 24)
        XCTAssertEqual(loaded.plan, "Max 20x")
        XCTAssertEqual(loaded.source, "api")
        XCTAssertEqual(loaded.at?.timeIntervalSince1970 ?? 0, old.at?.timeIntervalSince1970 ?? 1, accuracy: 0.01)

        // Страница молчит (nil) — остаётся сохранённое; пришло новее — запоминается; старее — нет.
        XCTAssertEqual(LimitsMemory.remember(nil, defaults)?.weekly?.used, 40)
        XCTAssertEqual(LimitsMemory.remember(limits(age: 60, week: 41), defaults)?.weekly?.used, 41)
        XCTAssertEqual(LimitsMemory.remember(limits(age: 7200, week: 39), defaults)?.weekly?.used, 41)
        XCTAssertEqual(LimitsMemory.load(defaults)?.weekly?.used, 41)
        // Без источника — не цифры подписки, не запоминаются.
        XCTAssertEqual(LimitsMemory.remember(limits(age: 1, week: 1, source: nil), defaults)?.weekly?.used, 41)
    }
}
