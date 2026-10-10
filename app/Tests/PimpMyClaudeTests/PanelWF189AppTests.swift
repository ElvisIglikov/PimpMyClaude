import AppKit
import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF189: цвета PMP — по цветовому кругу, ровно по ширине блока; картинка каждого варианта значка — без пустых полей.
final class PanelWF189AppTests: XCTestCase {
    private func hue(_ hex: UInt32) -> (hue: CGFloat, saturation: CGFloat) {
        let color = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        return (color.hueComponent, color.saturationComponent)
    }

    func testAccentsGoAroundColorWheelGraphiteLast() {
        let all = PMPAccent.allCases
        XCTAssertEqual(all, [.red, .orange, .amber, .green, .teal, .blue, .violet, .pink, .graphite])
        XCTAssertEqual(all.last, .graphite)
        XCTAssertLessThan(hue(PMPAccent.graphite.hex).saturation, 0.1, "графит — без цвета")
        let hues = all.dropLast().map { hue($0.hex).hue }
        XCTAssertEqual(hues, hues.sorted(), "красный → … → розовый — по кругу")
        for accent in all.dropLast() { XCTAssertGreaterThan(hue(accent.hex).saturation, 0.35, accent.name) }
        // Девять плиток по 28 pt встают в блок (296 pt) с промежутками не меньше 4 pt — рамке выбранного есть место.
        let inner = PimpPanelController.width - 24 - 20
        XCTAssertGreaterThanOrEqual((inner - CGFloat(all.count) * 28) / CGFloat(all.count - 1), 4)
    }

    /// Непрозрачные столбцы картинки: от края до края не больше 1,5 pt пустоты (как WF180/WF181).
    func testEveryVariantImageHasNoEmptyMargins() throws {
        for variant in StatusIcon.Variant.allCases where !variant.showsProjects {
            let image = StatusIconArt.image(IconSample.look(variant), dark: true, accent: PMPAccent.amber.nsColor)
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2),
                                                      pixelsHigh: 44, bitsPerSample: 8, samplesPerPixel: 4,
                                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                      bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            var columns: [Int] = []
            for x in 0..<rep.pixelsWide {
                if (0..<rep.pixelsHigh).contains(where: { (rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.1 }) {
                    columns.append(x)
                }
            }
            let left = CGFloat(columns.first ?? 0) / 2
            let right = image.size.width - CGFloat((columns.last ?? 0) + 1) / 2
            XCTAssertLessThanOrEqual(left, 1.5, "\(variant): слева пусто \(left)")
            XCTAssertLessThanOrEqual(right, 1.5, "\(variant): справа пусто \(right)")
        }
    }
}
