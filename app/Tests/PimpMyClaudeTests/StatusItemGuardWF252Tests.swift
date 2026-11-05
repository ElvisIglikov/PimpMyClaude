import AppKit
import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// #10016 (WF252): значок PMP за вырезом. Геометрия — по замеру на Маке с вырезом (macOS 26, 17.10.2026): экран
/// 1440×932, строка меню слева от выреза до 642, справа — с 798; спрятанный значок стоял на x 663 (под вырезом),
/// видимый — на x 1123.
final class StatusItemGuardWF252Tests: XCTestCase {
    private let notched = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 932),
                                        leftArea: CGRect(x: 0, y: 904, width: 642, height: 28),
                                        rightArea: CGRect(x: 798, y: 904, width: 642, height: 28))
    private let plain = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(x: CGFloat, width: CGFloat = 48, top: CGFloat = 932) -> CGRect {
        CGRect(x: x, y: top - 29, width: width, height: 29)
    }

    // MARK: геометрия

    func testNotchIsBetweenMenuBarAreas() {
        XCTAssertEqual(notched.notch, CGRect(x: 642, y: 904, width: 156, height: 28))
        XCTAssertNil(plain.notch, "у экрана без выреза выреза нет")
    }

    func testItemRightOfNotchIsVisible() {
        XCTAssertEqual(StatusItemPlace.of(item(x: 1123), shown: true, screens: [notched]), .visible)
        XCTAssertEqual(StatusItemPlace.of(item(x: 798, width: 38), shown: true, screens: [notched]), .visible,
                       "вплотную к вырезу — ещё виден")
    }

    func testItemUnderOrLeftOfNotchIsHidden() {
        XCTAssertEqual(StatusItemPlace.of(item(x: 663), shown: true, screens: [notched]), .hidden(.notch),
                       "замер: спрятанный значок стоит под вырезом")
        XCTAssertEqual(StatusItemPlace.of(item(x: 784, width: 38), shown: true, screens: [notched]), .hidden(.notch),
                       "задел вырез краем — macOS его не рисует")
        XCTAssertEqual(StatusItemPlace.of(item(x: 500, width: 40), shown: true, screens: [notched]), .hidden(.notch),
                       "левее выреза значки не рисуются")
    }

    func testOffscreenAndNotShown() {
        XCTAssertEqual(StatusItemPlace.of(item(x: 5000), shown: true, screens: [notched]), .hidden(.offscreen))
        XCTAssertEqual(StatusItemPlace.of(item(x: 1123), shown: false, screens: [notched]), .hidden(.notShown))
        XCTAssertEqual(StatusItemPlace.of(item(x: 1900, width: 48, top: 1080), shown: true, screens: [plain]),
                       .hidden(.offscreen), "вылез за правый край экрана без выреза")
    }

    func testNoFrameYetIsUnknown() {
        XCTAssertEqual(StatusItemPlace.of(nil, shown: true, screens: [notched]), .unknown)
        XCTAssertEqual(StatusItemPlace.of(.zero, shown: true, screens: [notched]), .unknown)
    }

    func testMacWithoutNotchAlwaysVisible() {
        for x in stride(from: CGFloat(0), through: 1860, by: 60) {
            XCTAssertEqual(StatusItemPlace.of(item(x: x, top: 1080), shown: true, screens: [plain]), .visible,
                           "без выреза значок на экране — виден (x \(x))")
        }
    }

    /// Ноутбук и монитор: строка меню на мониторе без выреза — вырез ноутбука значку не мешает.
    func testMenuBarOnExternalDisplayIgnoresLaptopNotch() {
        let external = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        let laptop = MenuBarScreen(frame: CGRect(x: 2560, y: 0, width: 1440, height: 932),
                                   leftArea: CGRect(x: 2560, y: 904, width: 642, height: 28),
                                   rightArea: CGRect(x: 3358, y: 904, width: 642, height: 28))
        XCTAssertEqual(StatusItemPlace.of(item(x: 1800, top: 1440), shown: true, screens: [external, laptop]), .visible)
        XCTAssertEqual(StatusItemPlace.of(item(x: 3223, top: 932), shown: true, screens: [external, laptop]),
                       .hidden(.notch), "на ноутбуке — под его вырезом")
    }

    func testWiderIconFitsOnlyWhenRoomLeftOfIt() {
        XCTAssertTrue(StatusItemPlace.fits(item(x: 900, width: 33), extra: 20, screens: [notched]))
        XCTAssertFalse(StatusItemPlace.fits(item(x: 805, width: 33), extra: 20, screens: [notched]),
                       "шире на 20 — заедет под вырез")
        XCTAssertFalse(StatusItemPlace.fits(nil, extra: 0, screens: [notched]))
    }

    // MARK: решение

    func testShrinkThenTabThenBack() {
        var logic = StatusItemGuardLogic()
        XCTAssertEqual(logic.observe(.hidden(.notch), canShrink: true, fitsFull: true, now: now), [.compact, .recheckSoon],
                       "сперва ужать")
        XCTAssertTrue(logic.compact)
        XCTAssertEqual(logic.observe(.hidden(.notch), canShrink: true, fitsFull: true, now: now), [.showTab],
                       "узкий не помог — плашка")
        XCTAssertEqual(logic.observe(.hidden(.notch), canShrink: true, fitsFull: true, now: now), [],
                       "плашка уже стоит — ничего")
        XCTAssertEqual(logic.observe(.visible, canShrink: true, fitsFull: false, now: now), [.hideTab],
                       "значок виден — плашка уходит, широкий не влезет — остаётся узкий")
        XCTAssertTrue(logic.compact)
        XCTAssertEqual(logic.observe(.visible, canShrink: true, fitsFull: true, now: now), [.full, .recheckSoon],
                       "место есть — вид человека вернулся")
        XCTAssertFalse(logic.compact)
        XCTAssertEqual(logic.observe(.visible, canShrink: true, fitsFull: true, now: now), [])
    }

    func testShrinkingHelpsNoTab() {
        var logic = StatusItemGuardLogic()
        _ = logic.observe(.hidden(.notch), canShrink: true, fitsFull: true, now: now)
        XCTAssertEqual(logic.observe(.visible, canShrink: true, fitsFull: false, now: now), [])
        XCTAssertFalse(logic.tabShown)
        XCTAssertTrue(logic.compact)
    }

    func testAlreadyNarrowWaitsOneReadingThenTab() {
        var logic = StatusItemGuardLogic()
        XCTAssertEqual(logic.observe(.hidden(.notch), canShrink: false, fitsFull: true, now: now), [.recheckSoon])
        XCTAssertFalse(logic.tabShown, "один замер мог застать перекладку строки меню")
        XCTAssertEqual(logic.observe(.hidden(.notch), canShrink: false, fitsFull: true, now: now), [.showTab])
    }

    func testOneHiddenReadingBetweenVisibleNeverShowsTab() {
        var logic = StatusItemGuardLogic()
        for _ in 0..<5 {
            XCTAssertEqual(logic.observe(.hidden(.notch), canShrink: false, fitsFull: true, now: now), [.recheckSoon])
            XCTAssertEqual(logic.observe(.visible, canShrink: false, fitsFull: true, now: now), [])
        }
        XCTAssertFalse(logic.tabShown)
    }

    /// Широкий вид по расчёту влез, а значок снова пропал: назад в узкий, час не пробуем — значок не мигает.
    func testFailedExpandDoesNotFlap() {
        var logic = StatusItemGuardLogic()
        _ = logic.observe(.hidden(.notch), canShrink: true, fitsFull: true, now: now)
        XCTAssertEqual(logic.observe(.visible, canShrink: true, fitsFull: true, now: now), [.full, .recheckSoon])
        XCTAssertEqual(logic.observe(.hidden(.notch), canShrink: true, fitsFull: true, now: now), [.compact, .recheckSoon])
        XCTAssertFalse(logic.tabShown, "это наша перемена, не повод для плашки")
        let later = now.addingTimeInterval(600)
        XCTAssertEqual(logic.observe(.visible, canShrink: true, fitsFull: true, now: later), [], "час не пробуем")
        let hourLater = now.addingTimeInterval(StatusItemGuardLogic.retryFullAfter + 1)
        XCTAssertEqual(logic.observe(.visible, canShrink: true, fitsFull: true, now: hourLater), [.full, .recheckSoon])
    }

    func testScreensChangedLiftsBlock() {
        var logic = StatusItemGuardLogic()
        _ = logic.observe(.hidden(.notch), canShrink: true, fitsFull: true, now: now)
        _ = logic.observe(.visible, canShrink: true, fitsFull: true, now: now)
        _ = logic.observe(.hidden(.notch), canShrink: true, fitsFull: true, now: now)
        logic.screensChanged()
        XCTAssertEqual(logic.observe(.visible, canShrink: true, fitsFull: true, now: now), [.full, .recheckSoon])
    }

    func testUnknownDoesNothing() {
        var logic = StatusItemGuardLogic()
        XCTAssertEqual(logic.observe(.unknown, canShrink: true, fitsFull: true, now: now), [])
        XCTAssertEqual(logic, StatusItemGuardLogic())
    }

    /// Мак без выреза: замеры всегда «виден» — ни узкого вида, ни плашки.
    func testNoTabOnMacWithoutNotch() {
        var logic = StatusItemGuardLogic()
        for x in stride(from: CGFloat(200), through: 1800, by: 100) {
            let place = StatusItemPlace.of(item(x: x, top: 1080), shown: true, screens: [plain])
            XCTAssertEqual(logic.observe(place, canShrink: true, fitsFull: true, now: now), [])
        }
        XCTAssertFalse(logic.tabShown)
        XCTAssertFalse(logic.compact)
    }

    /// Узкий вид — плашка PMP без числа: уже любого выбранного с числом, полосками или сводкой. «Только PMP» и
    /// однозначные «5%» (22 pt) и так не шире — их сторож не ужимает (`canShrink` ложь), сразу плашка.
    func testCompactLookIsNarrowest() {
        let installed = StatusIcon.Patch.installed(version: "2.9939.2", loader: 8)
        let limits = ClaudeLimits(at: now, plan: nil, fiveHour: nil,
                                  weekly: ClaudeLimits.Limit(used: 84, resetsAt: now.addingTimeInterval(86_400)),
                                  fable: nil, source: "api")
        for variant in StatusIcon.Variant.allCases where variant != .pmp {
            var look = StatusIcon.look(mode: variant.mode, limits: limits, patch: installed, phase: .idle, now: now)
            look = StatusIcon.compose(look, variant: variant, summary: "⏳2 ✋1", toolTip: "")
            let narrow = StatusIcon.badgeOnly(look)
            XCTAssertLessThan(StatusIconArt.width(narrow), StatusIconArt.width(look), "\(variant)")
        }
    }

    // MARK: уведомление

    func testNoticeAtMostOncePerDay() throws {
        XCTAssertTrue(StatusItemNotice.due(last: nil, now: now))
        XCTAssertFalse(StatusItemNotice.due(last: now.addingTimeInterval(-23 * 3600), now: now))
        XCTAssertTrue(StatusItemNotice.due(last: now.addingTimeInterval(-StatusItemNotice.every), now: now))

        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(StatusItemNotice.claim(defaults: defaults, now: now))
        XCTAssertFalse(StatusItemNotice.claim(defaults: defaults, now: now.addingTimeInterval(60)), "через минуту — молчим")
        XCTAssertFalse(StatusItemNotice.claim(defaults: defaults, now: now.addingTimeInterval(20 * 3600)))
        XCTAssertTrue(StatusItemNotice.claim(defaults: defaults, now: now.addingTimeInterval(24 * 3600)))
    }

    func testNoticeSaysWhere() {
        XCTAssertEqual(StatusItemNotice.title(.notch), "Значок PMP спрятан за вырезом экрана")
        XCTAssertEqual(StatusItemNotice.title(.offscreen), "Значок PMP не поместился в строке меню")
        XCTAssertTrue(StatusItemNotice.body.contains("⌘"))
    }

    // MARK: плашка

    func testTabDefaultPlaceRightUnderMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 932)
        let size = StatusItemTabButton.size
        let origin = StatusItemTab.origin(offset: nil, size: size, screen: screen, menuBar: 28)
        XCTAssertEqual(origin, CGPoint(x: 1440 - 10 - size.width, y: 932 - 28 - 6 - size.height))
    }

    func testTabOffsetRoundTripsAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 932)
        let size = StatusItemTabButton.size
        let dropped = CGPoint(x: 700, y: 860)
        let offset = StatusItemTab.offset(of: dropped, size: size, screen: screen)
        XCTAssertEqual(StatusItemTab.origin(offset: offset, size: size, screen: screen, menuBar: 28), dropped)

        // Тот же отступ на экране побольше — от его правого верхнего угла.
        let big = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(StatusItemTab.origin(offset: offset, size: size, screen: big, menuBar: 25),
                       CGPoint(x: 2560 - offset.x - size.width, y: 1440 - offset.y - size.height))

        // Отступ больше экрана — плашка прижата к краю, а не потеряна.
        let lost = StatusItemTab.origin(offset: CGPoint(x: 5000, y: -300), size: size, screen: screen, menuBar: 28)
        XCTAssertEqual(lost, CGPoint(x: 0, y: 932 - size.height))
    }

    func testTabButtonPressedFollowsPanelHighlight() {
        let button = StatusItemTabButton(frame: NSRect(origin: .zero, size: StatusItemTabButton.size))
        XCTAssertFalse(button.pressed)
        button.highlight(true)
        XCTAssertTrue(button.pressed, "панель открыта от плашки — плашка подсвечена")
        button.highlight(false)
        XCTAssertFalse(button.pressed)
    }

    func testTabToolTipTellsHowToGetIconBack() {
        XCTAssertTrue(StatusItemGuard.tabToolTip(.notch).contains("за вырезом"))
        XCTAssertTrue(StatusItemGuard.tabToolTip(.notch).contains("⌘"))
    }
}
