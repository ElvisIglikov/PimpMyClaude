import XCTest
@testable import ClaudeAX

/// WF181 (#9217, слово Элвиса 09.10 03:05): умолчание как на снимке 37 — плитки половинками по двое; шапка — только значок
/// PMP; без «…» в строках; «Память» — ГБ и процент одной формулой.
final class PanelWF181Tests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824

    func testDefaultLayoutPairsTilesLikeShot37() {
        let all = Set(PanelWidget.allCases.map { $0.rawValue })
        XCTAssertEqual(PanelWidgetLayout.standard.rows(visible: all).map { $0.map { $0.id } },
                       [["workflow"], ["week", "reset"], ["limits", "fable"], ["temperature", "memory"], ["tokens"],
                        ["colors"]])
        // Сохранённая раскладка человека — своя, умолчание её не трогает.
        let mine = PanelWidgetLayout(items: PanelWidget.allCases.map { .init(id: $0.rawValue, wide: true) })
        XCTAssertFalse(mine.isStandard)
        XCTAssertTrue(mine.rows(visible: all).allSatisfy { $0.count == 1 })
    }

    func testHeaderBadgeHasNoNumberBarsOrSummary() {
        let now = Date()
        let limits = ClaudeLimits(at: now, plan: "Max 20x", fiveHour: nil,
                                  weekly: .init(used: 39, resetsAt: nil), fable: nil, source: "api")
        let week = StatusIcon.look(mode: .week, limits: limits, patch: .installed(version: "2", loader: 8),
                                   phase: .idle, now: now)
        XCTAssertTrue(week.showsNumber, "у часов в виде «неделя» число было")
        let badge = StatusIcon.badgeOnly(week)
        XCTAssertFalse(badge.showsNumber)
        XCTAssertNil(badge.number)
        XCTAssertEqual(badge.width, 25)
        var projects = StatusIcon.withProjects(week, summary: "3 ✓ 2", toolTip: "")
        projects.badge = false
        let fromProjects = StatusIcon.badgeOnly(projects)
        XCTAssertNil(fromProjects.text)
        XCTAssertTrue(fromProjects.badge)
        let bars = StatusIcon.badgeOnly(StatusIcon.look(mode: .three, limits: limits, patch: .installed(version: "2", loader: 8),
                                                        phase: .idle, now: now))
        XCTAssertTrue(bars.bars.isEmpty)
        // Беда остаётся: точка «патч слетел» — место под метку.
        let lost = StatusIcon.badgeOnly(StatusIcon.look(mode: .week, limits: limits, patch: .lost(version: "2"),
                                                        phase: .idle, now: now))
        XCTAssertEqual(lost.mark, .patchLost)
        XCTAssertEqual(lost.width, 28)
    }

    func testHeaderLineHasNoEllipsis() {
        for patch: StatusIcon.Patch in [.unknown, .claudeNotFound, .notInstalled(version: "2.1"), .lost(version: "2.1"),
                                        .installed(version: "2.1", loader: 8)] {
            let line = PimpPanelText.headerLine(patch, plan: "Max 20x", app: "1.10.10")
            XCTAssertFalse(line.contains("…"), line)
        }
    }

    func testMemoryGigabytesAndPercentOneFormula() {
        let sample = MacMemorySample(at: Date(), pressure: 50, level: .normal,
                                     used: 6 * Self.gb + 3 * Self.gb / 10, total: 8 * Self.gb)
        XCTAssertEqual(MacMemory.amount(sample), "6,3 ГБ")
        XCTAssertEqual(MacMemory.usedPercent(sample), 79, "6,3 из 8 — 79 %, а не нагрузка macOS 50 %")
        XCTAssertEqual(MacMemory.help([sample]), "Память: занято 6,3 из 8 ГБ — 79 % · зелёная, в норме")
        XCTAssertFalse(MacMemory.caption([sample]).contains("…"))
        // Занятого не знаем — процент честно назван нагрузкой macOS.
        let blind = MacMemorySample(at: Date(), pressure: 47, level: .normal, used: nil, total: 8 * Self.gb)
        XCTAssertNil(MacMemory.usedPercent(blind))
        XCTAssertEqual(MacMemory.help([blind]), "Память: нагрузка по macOS 47 % · зелёная, в норме")
    }
}
