import XCTest
@testable import PimpMyClaude

/// WF227 (#9406): окно «Поддержать автора» живёт в тёмной и светлой теме, а цвет PMP человек выбирает сам —
/// ссылки и подписи на заливке обязаны читаться при любом выборе (контраст числом, не на глаз).
final class DonateWF227AppTests: XCTestCase {
    func testEveryAccentReadsAsLinkOnBothBackgrounds() {
        for accent in PMPAccent.allCases {
            for background in [DonateTone.darkBackground, DonateTone.lightBackground] {
                let link = DonateTone.readable(accent.hex, on: background)
                XCTAssertGreaterThanOrEqual(DonateTone.contrast(link, background), DonateTone.textContrast,
                                            "\(accent) на \(String(background, radix: 16))")
            }
        }
        // Уже читаемый цвет не трогаем: фиолетовый на тёмном окне остаётся собой.
        XCTAssertEqual(DonateTone.readable(PMPAccent.violet.hex, on: DonateTone.darkBackground), PMPAccent.violet.hex)
    }

    func testInkOnAccentFillReads() {
        for accent in PMPAccent.allCases {
            for fill in [accent.hex, accent.lightBarHex] {
                XCTAssertGreaterThanOrEqual(DonateTone.contrast(DonateTone.ink(on: fill), fill), DonateTone.textContrast,
                                            "\(accent) \(String(fill, radix: 16))")
            }
        }
    }

    func testContrastMath() {
        XCTAssertEqual(DonateTone.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(DonateTone.contrast(0x777777, 0x777777), 1, accuracy: 0.001)
    }
}
