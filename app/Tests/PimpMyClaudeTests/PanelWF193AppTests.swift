import AppKit
import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF193: графит и бледные цвета на светлой строке меню — темнее; в сводке проектов на значке нет эмодзи (плоские
/// знаки цветом букв); у запасной плашки в шапке — та же точка-подсказка.
final class PanelWF193AppTests: XCTestCase {
    private func hex(_ color: NSColor) -> UInt32 {
        let c = color.usingColorSpace(.sRGB)!
        return UInt32((c.redComponent * 255).rounded()) << 16 | UInt32((c.greenComponent * 255).rounded()) << 8
            | UInt32((c.blueComponent * 255).rounded())
    }

    func testGraphiteIsDarkOnLightBarOnly() {
        XCTAssertEqual(hex(PMPAccent.onBar(PMPAccent.graphite.nsColor, dark: false)), 0x3A3A3C)
        XCTAssertEqual(hex(PMPAccent.onBar(PMPAccent.graphite.nsColor, dark: true)), 0xECECEE)
        for accent in [PMPAccent.teal, .blue, .violet] {
            let light = PMPAccent.onBar(accent.nsColor, dark: false)
            XCTAssertLessThan(light.usingColorSpace(.sRGB)!.brightnessComponent,
                              accent.nsColor.usingColorSpace(.sRGB)!.brightnessComponent, accent.name)
            XCTAssertEqual(hex(PMPAccent.onBar(accent.nsColor, dark: true)), accent.hex, accent.name)
        }
        for accent in [PMPAccent.red, .orange, .amber, .green, .pink] {
            XCTAssertEqual(hex(PMPAccent.onBar(accent.nsColor, dark: false)), accent.hex, accent.name)
        }
        XCTAssertEqual(hex(PMPAccent.onBar(.systemRed, dark: false)), hex(.systemRed), "чужой цвет — как есть")
    }

    /// Плашка графита, нарисованная для светлой полосы, — тёмная (заливка слева от букв).
    func testGraphiteBadgePixelOnLightBar() throws {
        let look = StatusIcon.badgeOnly(StatusIcon.look(mode: .week, limits: nil, patch: .unknown, phase: .idle,
                                                        now: Date()))
        for (dark, check) in [(false, { (b: CGFloat) in b < 0.35 }), (true, { (b: CGFloat) in b > 0.85 })] {
            let image = StatusIconArt.image(look, dark: dark, accent: PMPAccent.graphite.nsColor)
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2),
                                                      pixelsHigh: 44, bitsPerSample: 8, samplesPerPixel: 4,
                                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                      bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            // x 2 pt, середина плашки по высоте — заливка до буквы «P».
            let pixel = try XCTUnwrap(rep.colorAt(x: 4, y: 22))
            XCTAssertGreaterThan(pixel.alphaComponent, 0.9)
            XCTAssertTrue(check(pixel.brightnessComponent), "dark=\(dark): яркость \(pixel.brightnessComponent)")
        }
    }

    /// Варианты «PMP и проекты» и «Только проекты»: сводка на значке без эмодзи — знаки вложены картинками.
    func testProjectSummaryHasNoEmoji() {
        for summary in [IconSample.projects, "⏳ 3 · ✋ 1 · WF 4/11", "✅ 2", "—"] {
            let line = StatusIconArt.summaryText(summary, color: .black)
            let emoji = line.string.unicodeScalars.filter { $0.properties.isEmojiPresentation }
            XCTAssertTrue(emoji.isEmpty, "\(summary): \(line.string)")
            var attachments = 0
            line.enumerateAttribute(.attachment, in: NSRange(location: 0, length: line.length)) { value, _, _ in
                if value != nil { attachments += 1 }
            }
            XCTAssertEqual(attachments, summary.filter { StatusIconArt.summarySymbols[$0] != nil }.count, summary)
        }
        for variant in StatusIcon.Variant.allCases where variant.showsProjects {
            let look = IconSample.look(variant)
            XCTAssertGreaterThan(StatusIconArt.width(look), 30, "\(variant): сводка видна")
        }
    }

    func testFallbackBadgeShowsHintDot() {
        XCTAssertTrue(BadgeHint.shows(nil, patch: .unknown), "запасная плашка — с точкой")
        XCTAssertTrue(BadgeHint.shows(nil, patch: .notInstalled(version: "2.0")))
        XCTAssertFalse(BadgeHint.shows(nil, patch: .lost(version: "2.0")), "беда — красная точка рядом, подсказки нет")
        let look = StatusIcon.look(mode: .week, limits: nil, patch: .unknown, phase: .idle, now: Date())
        XCTAssertTrue(BadgeHint.shows(look, patch: .unknown))
        var lost = look
        lost.mark = .patchLost
        XCTAssertFalse(BadgeHint.shows(lost, patch: .unknown))
        XCTAssertGreaterThan(BadgeHint.badgeOffset.width, 0, "к углу плашки 32 × 20")
    }
}
