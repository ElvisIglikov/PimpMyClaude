import XCTest
@testable import PimpMyClaude

/// #10962 (слово Элвиса: «подсветка начиналась с четырёх… минимальным значением… Четыре будет начальное значение»):
/// ползунок «Подсветка · ночь N из 10» — от 4, стартует с 4; у «Подсветка · macOS» видно, что выставит ползунок.
final class NightLightMin10962Tests: XCTestCase {
    func testMinimumAndStartAreFour() {
        XCTAssertEqual(NightLight.minLevel, 4)
        XCTAssertEqual(NightLight.startLevel, 4)
        XCTAssertEqual(NightLight.startSlider(nil), 4, "чистая установка — 4")
        XCTAssertEqual(NightLight.startSlider(.nan), 4)
        XCTAssertEqual(NightLight.startSlider(0), 4, "было «выкл.» — встаёт на 4")
        XCTAssertEqual(NightLight.startSlider(2), 4)
        XCTAssertEqual(NightLight.startSlider(7), 7)
        XCTAssertEqual(NightLight.startSlider(60), 60)
        XCTAssertEqual(NightLight.startSlider(500), 110)
    }

    func testLabels() {
        var state = LightState()
        XCTAssertEqual(NightLight.label(state, slider: 4), "Подсветка · macOS · ползунок: ночь 4 из 10")
        XCTAssertEqual(NightLight.label(state, slider: 1), "Подсветка · macOS · ползунок: ночь 4 из 10")
        XCTAssertEqual(NightLight.label(state, slider: 47), "Подсветка · macOS · ползунок: 37 %")
        state.mode = .night(5)
        XCTAssertEqual(NightLight.label(state, slider: 5), "Подсветка · ночь 5 из 10")
        state.mode = .normal(40)
        XCTAssertEqual(NightLight.label(state, slider: 50), "Подсветка · 40 %")
        state.mode = .off
        XCTAssertEqual(NightLight.label(state, slider: 4), "Подсветка · выкл.")
        state.idle = true
        XCTAssertEqual(NightLight.label(state, slider: 4), "Подсветка · пауза")
    }
}
