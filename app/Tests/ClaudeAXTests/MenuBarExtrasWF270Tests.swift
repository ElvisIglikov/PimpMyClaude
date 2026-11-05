import XCTest
@testable import ClaudeAX

/// WF270 (#10264): какие значки строки меню спрятаны и почему.
final class MenuBarExtrasWF270Tests: XCTestCase {
    private let bar = MenuBarExtras.Bar(notch: 562...718, height: 37, width: 1280)

    func testUnderNotch() {
        XCTAssertEqual(MenuBarExtras.reason(frame: CGRect(x: 600, y: 0, width: 30, height: 37), bar: bar), .notch)
    }

    func testPartlyUnderNotch() {
        XCTAssertEqual(MenuBarExtras.reason(frame: CGRect(x: 545, y: 0, width: 30, height: 37), bar: bar), .notch)
        XCTAssertEqual(MenuBarExtras.reason(frame: CGRect(x: 710, y: 0, width: 30, height: 37), bar: bar), .notch)
    }

    func testTouchingNotchEdgeIsVisible() {
        XCTAssertNil(MenuBarExtras.reason(frame: CGRect(x: 532, y: 0, width: 30, height: 37), bar: bar))
        XCTAssertNil(MenuBarExtras.reason(frame: CGRect(x: 718, y: 0, width: 30, height: 37), bar: bar))
        XCTAssertNil(MenuBarExtras.reason(frame: CGRect(x: 1100, y: 0, width: 30, height: 37), bar: bar))
    }

    func testOffScreen() {
        XCTAssertEqual(MenuBarExtras.reason(frame: CGRect(x: 7, y: 831, width: 30, height: 37), bar: bar), .off)
        XCTAssertEqual(MenuBarExtras.reason(frame: CGRect(x: 1300, y: 0, width: 30, height: 37), bar: bar), .off)
    }

    func testZeroSizeNotShown() {
        XCTAssertNil(MenuBarExtras.reason(frame: CGRect(x: 600, y: 0, width: 0, height: 0), bar: bar))
        XCTAssertNil(MenuBarExtras.reason(frame: CGRect(x: 7, y: 831, width: 0, height: 0), bar: bar))
    }

    func testNoNotchNothingUnderIt() {
        let plain = MenuBarExtras.Bar(notch: nil, height: 24, width: 1440)
        XCTAssertNil(MenuBarExtras.reason(frame: CGRect(x: 600, y: 0, width: 30, height: 24), bar: plain))
    }

    func testOwnAppSkippedAndPressCodes() {
        let own = ProcessInfo.processInfo.processIdentifier
        XCTAssertFalse(MenuBarExtras.hidden(force: true).contains { $0.pid == own })
        XCTAssertTrue(MenuBarExtras.pressWorked(0))
        XCTAssertTrue(MenuBarExtras.pressWorked(-25204))
        XCTAssertFalse(MenuBarExtras.pressWorked(-25205))
    }

    func testHint() {
        let item = MenuBarExtras.Item(pid: 1, bundleId: nil, appName: "Karabiner", title: "Karabiner", frame: .zero, reason: .notch)
        XCTAssertEqual(item.hint, "Karabiner")
        let other = MenuBarExtras.Item(pid: 1, bundleId: nil, appName: "Mail", title: "Почта", frame: .zero, reason: .off)
        XCTAssertEqual(other.hint, "Mail — Почта")
    }
}
