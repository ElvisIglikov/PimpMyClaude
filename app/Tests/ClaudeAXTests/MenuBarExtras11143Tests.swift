import XCTest
@testable import ClaudeAX

/// #11143: на Odyssey (главный, 2560×720 pt, строка меню 30, выреза нет) Пимп звал «не влезшими» Telegram, Claude и
/// Hammerspoon. Числа — замер AX 29.10.2026 на M4 Элвиса: эти три выключены в «Строке меню» настроек (`isAllowed =
/// false`) и стоят у левого нижнего угла главного экрана; видимые значки — в строке, x 1805…2552.
final class MenuBarExtras11143Tests: XCTestCase {
    private let odyssey = MenuBarExtras.Bar(notch: nil, height: 30, width: 2560)
    private let laptop = MenuBarExtras.Bar(notch: 562...718, height: 37, width: 1280)

    private let switchedOff: [(String, CGRect)] = [
        ("Telegram", CGRect(x: 7, y: 719, width: 24, height: 24)),
        ("Claude", CGRect(x: -1, y: 718, width: 42, height: 26)),
        ("Hammerspoon", CGRect(x: 7, y: 719, width: 24, height: 24)),
    ]

    private let visible: [(String, CGRect)] = [
        ("LooperShot", CGRect(x: 1848, y: 3, width: 50, height: 24)),
        ("Dictator", CGRect(x: 1904, y: 3, width: 22, height: 24)),
        ("BetterDisplay", CGRect(x: 2041, y: 3, width: 34, height: 24)),
        ("PimpMyClaude", CGRect(x: 2272, y: 3, width: 66, height: 24)),
        ("Часы", CGRect(x: 2425, y: 4, width: 127, height: 22)),
    ]

    func testSwitchedOffIconsAreNotInStrip() {
        for (name, frame) in switchedOff {
            XCTAssertEqual(MenuBarExtras.reason(frame: frame, bar: odyssey), .off, name)
            XCTAssertFalse(MenuBarExtras.didNotFit(frame: frame, bar: odyssey), name)
        }
    }

    func testVisibleIconsOnOdysseyStayVisible() {
        for (name, frame) in visible {
            XCTAssertNil(MenuBarExtras.reason(frame: frame, bar: odyssey), name)
            XCTAssertFalse(MenuBarExtras.didNotFit(frame: frame, bar: odyssey), name)
        }
    }

    /// Мак с вырезом без второго экрана (WF270): значок под вырезом — в полосе, выключенный Hammerspoon (7, 831) — нет.
    func testLaptopNotchStillInStrip() {
        XCTAssertTrue(MenuBarExtras.didNotFit(frame: CGRect(x: 600, y: 0, width: 30, height: 37), bar: laptop))
        XCTAssertTrue(MenuBarExtras.didNotFit(frame: CGRect(x: 545, y: 0, width: 30, height: 37), bar: laptop))
        XCTAssertFalse(MenuBarExtras.didNotFit(frame: CGRect(x: 1100, y: 0, width: 30, height: 37), bar: laptop))
        XCTAssertFalse(MenuBarExtras.didNotFit(frame: CGRect(x: 7, y: 831, width: 24, height: 24), bar: laptop))
    }
}
