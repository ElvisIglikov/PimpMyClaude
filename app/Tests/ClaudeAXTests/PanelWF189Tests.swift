import XCTest
@testable import ClaudeAX

/// WF189 (слово Элвиса 09.10 04:00: проценты из строки меню пропали — «сделай варианты отображения в строке меню,
/// как раньше»): варианты значка у часов, по умолчанию «PMP и неделя», перевод прежних выборов WF180/WF174.
final class PanelWF189Tests: XCTestCase {
    private func defaults(_ name: String = #function) -> UserDefaults {
        let store = UserDefaults(suiteName: "PanelWF189Tests.\(name)")!
        store.removePersistentDomain(forName: "PanelWF189Tests.\(name)")
        return store
    }

    private let now = Date()
    private var limits: ClaudeLimits {
        ClaudeLimits(at: now, plan: nil, fiveHour: .init(used: 12, resetsAt: nil),
                     weekly: .init(used: 37, resetsAt: now.addingTimeInterval(86_400)),
                     fable: .init(used: 3, resetsAt: nil), source: "api")
    }

    private func look(_ variant: StatusIcon.Variant, patch: StatusIcon.Patch = .unknown) -> StatusIcon.Look {
        let base = StatusIcon.look(mode: variant.mode, limits: limits, patch: patch, phase: .idle, now: now)
        return StatusIcon.compose(base, variant: variant, summary: "⏳ 2", toolTip: "p")
    }

    func testVariantsAsBefore() {
        XCTAssertEqual(StatusIcon.Variant.allCases,
                       [.week, .pmpBar, .percentBar, .percent, .pmp, .bars, .fiveHour, .fable, .projects, .digits])
        XCTAssertEqual(Set(StatusIcon.Variant.allCases.map { $0.name }).count, StatusIcon.Variant.allCases.count)
    }

    func testDefaultIsPMPAndWeekWithNumber() {
        let store = defaults()
        XCTAssertEqual(StatusIcon.variant(store), .week, "ключа нет — PMP и неделя")
        let week = look(.week)
        XCTAssertTrue(week.badge)
        XCTAssertTrue(week.showsNumber)
        XCTAssertEqual(week.number, 37, "проценты недели вернулись на значок")
        XCTAssertEqual(week.width, 45, "плашка, число и полоска — без пустых полей")
    }

    func testEachVariantDrawsWhatItSays() {
        let percentBar = look(.percentBar)
        XCTAssertEqual(percentBar.mode, .percent)
        XCTAssertEqual(percentBar.number, 37)
        XCTAssertTrue(percentBar.underline, "проценты с полоской")
        let percent = look(.percent)
        XCTAssertEqual(percent.number, 37)
        XCTAssertFalse(percent.underline, "только недельная — без полоски")
        let pmpBar = look(.pmpBar)
        XCTAssertFalse(pmpBar.showsNumber)
        XCTAssertEqual(pmpBar.bars, [37], "PMP с одной полоской недели")
        XCTAssertEqual(pmpBar.width, 47)
        XCTAssertNil(look(.pmp).number)
        XCTAssertEqual(look(.pmp).width, 25)
        XCTAssertEqual(look(.bars).bars, [12, 37, 3])
        XCTAssertEqual(look(.fiveHour).number, 12)
        XCTAssertEqual(look(.fable).number, 3)
        XCTAssertEqual(look(.projects).text, "⏳ 2")
        XCTAssertTrue(look(.projects).badge)
        XCTAssertFalse(look(.digits).badge)
        // Без патча — бейдж контуром, вариант его не трогает.
        let outlined = look(.pmpBar, patch: .claudeNotFound)
        XCTAssertTrue(outlined.outlined)
        XCTAssertTrue(outlined.bars.isEmpty)
    }

    func testMigrationFromWF180AndWF174() {
        let wf180: [String: StatusIcon.Variant] = ["pmp": .week, "bars": .bars, "projects": .projects,
                                                   "digits": .digits]
        for (raw, expected) in wf180 {
            let store = defaults("wf180-\(raw)")
            store.set(raw, forKey: StatusIcon.variantKeyWF180)
            XCTAssertEqual(StatusIcon.variant(store), expected, raw)
        }
        let projects = defaults("wf174-projects")
        projects.set("projects", forKey: StatusIcon.viewKey)
        XCTAssertEqual(StatusIcon.variant(projects), .projects)
        projects.set(false, forKey: StatusIcon.lettersKey)
        XCTAssertEqual(StatusIcon.variant(projects), .digits)
        let noWeek = defaults("wf174-no-week")
        noWeek.set(false, forKey: StatusIcon.weekKey)
        XCTAssertEqual(StatusIcon.variant(noWeek), .pmp, "неделя была выключена — только PMP")
        let noLetters = defaults("wf174-no-letters")
        noLetters.set(false, forKey: StatusIcon.lettersKey)
        XCTAssertEqual(StatusIcon.variant(noLetters), .percent, "без букв — только проценты, как в WF174")
        // Новый выбор сильнее старых ключей; мусор — как без выбора.
        let store = defaults()
        store.set("bars", forKey: StatusIcon.variantKeyWF180)
        StatusIcon.saveVariant(.percentBar, store)
        XCTAssertEqual(StatusIcon.variant(store), .percentBar)
        store.set("мусор", forKey: StatusIcon.variantKey)
        XCTAssertEqual(StatusIcon.variant(store), .bars)
    }
}
