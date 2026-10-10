import XCTest
@testable import ClaudeAX

/// Приложение у часов после ревизии WF100 (WF101 Б3b): три полоски — израсходовано, цвет по
/// остатку (z6-r02); «патч слетел» по причине (z7-s03, С5 `.lost`); гигабайты с десятыми (z6-r06).
final class AppClockWF101Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func limits(five: Int?, week: Int?, fable: Int?) -> ClaudeLimits {
        ClaudeLimits(at: now.addingTimeInterval(-30), plan: nil,
                     fiveHour: five.map { .init(used: $0, resetsAt: nil) },
                     weekly: week.map { .init(used: $0, resetsAt: nil) },
                     fable: fable.map { .init(used: $0, resetsAt: nil) }, source: "api")
    }

    func testThreeBarsFillUsedAndColorByRemaining() {
        let look = StatusIcon.look(mode: .three, limits: limits(five: 44, week: 85, fable: 92),
                                   patch: .installed(version: "2.9939.2", loader: 7), phase: .idle, now: now)
        XCTAssertEqual(look.bars, [44, 85, 92], "залито израсходованное, как число на значке")
        XCTAssertEqual(look.barLevels, [.normal, .low, .critical], "цвет — по остатку: 56, 15, 8")
        let week = StatusIcon.look(mode: .week, limits: limits(five: 44, week: 85, fable: 92),
                                   patch: .installed(version: "2.9939.2", loader: 7), phase: .idle, now: now)
        XCTAssertEqual(week.number, look.bars[1], "значок «Неделя» и средняя полоска — одно число")

        let empty = StatusIcon.look(mode: .three, limits: nil, patch: .unknown, phase: .idle, now: now)
        XCTAssertEqual(empty.bars, [nil, nil, nil], "нет цифр — только дорожки")
        XCTAssertEqual(empty.barLevels, [.normal, .normal, .normal])
    }

    func testPatchLostSaysUpdatedOnlyWhenClaudeUpdated() {
        let updated = StatusIcon.Patch.lost(version: "2.9939.2", reason: "Claude обновился")
        XCTAssertEqual(StatusIcon.Patch.lost(version: "2.9939.2"), updated, "по умолчанию — «Claude обновился»")
        XCTAssertEqual(PimpPanelText.patchCard(updated)?.title, "Claude обновился — патч слетел")
        XCTAssertEqual(PimpPanelText.patchLostNotice(version: "2.9939.2", reason: "Claude обновился"),
                       "Claude 2.9939.2 обновился — патч слетел. Одно нажатие — всё вернётся.")

        let hash = StatusIcon.Patch.lost(version: "2.9939.2", reason: "хэш в Info.plist не сходится")
        XCTAssertEqual(PimpPanelText.patchCard(hash)?.title, "Патч слетел: хэш в Info.plist не сходится")
        XCTAssertEqual(PimpPanelText.patchCard(hash)?.button, "Вернуть патч")
        XCTAssertEqual(PimpPanelText.patchLostNotice(version: "2.9939.2", reason: "старый лоадер v6"),
                       "Патч слетел (старый лоадер v6) · Claude 2.9939.2. Одно нажатие — всё вернётся.")
        XCTAssertEqual(PimpPanelText.headerLine(hash, plan: nil), "Claude 2.9939.2")
        XCTAssertEqual(StatusIcon.look(mode: .week, limits: nil, patch: hash, phase: .idle, now: now).mark, .patchLost)
    }

    func testNoSpaceTextKeepsTenths() {
        XCTAssertEqual(PimpPanelText.noSpaceText(needed: 2_800_000_000, free: 700_000_000),
                       "мало места на диске: нужно 2,8 ГБ, свободно 0,7 ГБ")
        XCTAssertEqual(PimpPanelText.gigabytesText(12_000_000_000), "12,0")
        XCTAssertEqual(PimpPanelText.gigabytesText(-1), "0,0")
    }
}
