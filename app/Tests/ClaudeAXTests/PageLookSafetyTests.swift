import XCTest
@testable import ClaudeAX

final class PageLookSafetyTests: XCTestCase {
    func testUnboundedNumbersAreClampedBeforeIntegerConversion() {
        XCTAssertEqual(DimSetting.percent(level: 1e308), 80)
        XCTAssertEqual(DimSetting.percent(level: -1e308), 20)
        XCTAssertEqual(DimSetting.percent(level: .infinity), 50)
        XCTAssertEqual(DimSetting.clamp(Int.max), 80)
        XCTAssertEqual(DimSetting.clamp(Int.min), 20)
        XCTAssertEqual(SendLook.clamp(Int.max), 200)
        XCTAssertEqual(SendLook.clamp(Int.min), 60)
        let suite = "look-safety-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PageLookSettings(defaults: defaults)
        XCTAssertEqual(settings.setLook(grow: Int.max).look.size, 200)
        XCTAssertEqual(settings.setLook(grow: Int.min).look.size, 60)
    }

    func testDimRequestRejectsLargeAndOutOfRangeDoublesWithoutTrapping() {
        for level in ["1e100", "1e308", "-1e308", "0.199", "0.801"] {
            let request = Data("{\"id\":\"1-1\",\"at\":\"2026-09-29T20:10:00Z\",\"action\":\"dim\",\"from\":\"\",\"on\":true,\"level\":\(level)}".utf8)
            XCTAssertNil(PimpRequest.parse(request), level)
        }
    }

    func testMainProjectCannotBeHiddenWhileItsIdentityIsUnknown() {
        let main = WindowHide.Seen(title: "Claude", isMain: true, fullScreen: false)
        let unresolved = WindowHide.Seen(title: "Rick", isMain: false, fullScreen: false,
                                         projectKnown: false)
        XCTAssertEqual(WindowHide.plan([main, unresolved], minimized: 0), .refuse(.windowMissing))
        let rick = WindowHide.Seen(title: "Rick", isMain: false, fullScreen: false, keep: true)
        XCTAssertEqual(WindowHide.plan([main, rick], minimized: 0), .hide([], skipped: 0))
    }
}
