import XCTest
@testable import ClaudeAX

/// #11120: окно «Повтор iPhone» влезает по высоте. Числа — замер 29.10.2026 на Odyssey (2560×720 pt, видимая часть
/// AX 41,30 2519×690): окно 354×781 в (1406, 30); после «Уменьшить» — 236×524 в (1465, 159) или (1583, 288).
final class PhoneMirrorFit11120Tests: XCTestCase {
    private let visible = CGRect(x: 41, y: 30, width: 2519, height: 690)

    func testTallWindowShrinks() {
        let window = CGRect(x: 1406, y: 30, width: 354, height: 781)
        XCTAssertEqual(PhoneMirrorFit.decide(window: window, visible: visible, canShrink: true), .shrink)
    }

    func testShrunkWindowInsideIsLeftAlone() {
        let window = CGRect(x: 1465, y: 159, width: 236, height: 524)
        XCTAssertEqual(PhoneMirrorFit.decide(window: window, visible: visible, canShrink: true), .none)
    }

    /// Уменьшенное окно программа ставит по старой середине — низ ушёл за экран: поднять к низу видимой части.
    func testShrunkWindowBelowEdgeMovesUp() {
        let window = CGRect(x: 1583, y: 288, width: 236, height: 524)
        XCTAssertEqual(PhoneMirrorFit.decide(window: window, visible: visible, canShrink: true),
                       .move(CGPoint(x: 1583, y: 196)))
    }

    /// Уменьшать больше нельзя, а окно всё выше экрана — верх окна к верху видимой части.
    func testCannotShrinkTopAligned() {
        let window = CGRect(x: 1406, y: 120, width: 354, height: 781)
        XCTAssertEqual(PhoneMirrorFit.decide(window: window, visible: visible, canShrink: false),
                       .move(CGPoint(x: 1406, y: 30)))
        XCTAssertEqual(PhoneMirrorFit.decide(window: CGRect(x: 1406, y: 30, width: 354, height: 781), visible: visible,
                                             canShrink: false), .none)
    }

    func testWindowRightOfScreenPulledIn() {
        let window = CGRect(x: 2450, y: 100, width: 236, height: 524)
        XCTAssertEqual(PhoneMirrorFit.decide(window: window, visible: visible, canShrink: true),
                       .move(CGPoint(x: 2324, y: 100)))
    }

    /// Экраны M4 (Cocoa): Odyssey главный 2560×720, встроенный правее и выше. Окно на Odyssey — его видимая часть;
    /// на встроенном — его (AX y = 720 − (−415 + 804) = 331).
    func testVisibleAreaPicksWindowScreen() {
        let screens: [(frame: CGRect, visible: CGRect)] = [
            (CGRect(x: 0, y: 0, width: 2560, height: 720), CGRect(x: 41, y: 0, width: 2519, height: 690)),
            (CGRect(x: 2560, y: -415, width: 1280, height: 832), CGRect(x: 2560, y: -415, width: 1280, height: 804)),
        ]
        XCTAssertEqual(PhoneMirrorFit.visibleArea(for: CGRect(x: 1406, y: 30, width: 354, height: 781),
                                                  screens: screens, primaryHeight: 720), visible)
        XCTAssertEqual(PhoneMirrorFit.visibleArea(for: CGRect(x: 3000, y: 400, width: 354, height: 781),
                                                  screens: screens, primaryHeight: 720),
                       CGRect(x: 2560, y: 331, width: 1280, height: 804))
    }
}
