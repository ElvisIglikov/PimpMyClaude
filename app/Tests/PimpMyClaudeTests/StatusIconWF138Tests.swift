import AppKit
import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF138 (#9112): значок у часов не ест CPU — кадры крутилки из кэша, картинка сама берёт тему в момент рисования.
final class StatusIconWF138Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let installed = StatusIcon.Patch.installed(version: "2.9939.2", loader: 7)

    private func look(_ phase: ClaudeUpdateMenu.Phase) -> StatusIcon.Look {
        StatusIcon.look(mode: .week, limits: nil, patch: installed, phase: phase, now: now)
    }

    func testSpinnerFramesComeFromCache() {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 60, height: 22))
        let painter = StatusIconPainter(button: button)
        let accent = PMPAccent.violet.nsColor
        painter.apply(look(.installing(version: "2.9941.0")), accent: accent)
        XCTAssertTrue(painter.isSpinning)

        var firstTurn: [NSImage] = []
        for _ in 0..<StatusIconPainter.spinFrames {
            painter.step()
            firstTurn.append(try! XCTUnwrap(button.image))
        }
        XCTAssertEqual(painter.frames.count, StatusIconPainter.spinFrames, "кадров на оборот — не больше")
        XCTAssertEqual(Set(firstTurn.map(ObjectIdentifier.init)).count, StatusIconPainter.spinFrames)
        for i in 0..<StatusIconPainter.spinFrames {
            painter.step()
            XCTAssertTrue(button.image === firstTurn[i], "второй оборот — те же картинки, без нового рендера")
        }

        // Тот же вид ещё раз — ничего не пересобираем.
        let shown = button.image
        painter.apply(look(.installing(version: "2.9941.0")), accent: accent)
        XCTAssertTrue(button.image === shown)

        painter.apply(look(.idle), accent: accent)
        XCTAssertFalse(painter.isSpinning, "крутилка не нужна — таймер стоит")
        XCTAssertEqual(painter.frames.count, 1)
    }

    /// Одна картинка рисуется светлой и тёмной — по теме, в которой её рисуют (копии значка на разных экранах).
    func testImageFollowsDrawingAppearance() throws {
        let image = StatusIconArt.image(look(.idle), accent: PMPAccent.violet.nsColor)
        func luminance(_ name: NSAppearance.Name) throws -> CGFloat {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let size = image.size
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
                                                     pixelsHigh: Int(size.height), bitsPerSample: 8,
                                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            appearance.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                image.draw(in: NSRect(origin: .zero, size: size))
                NSGraphicsContext.restoreGraphicsState()
            }
            var sum: CGFloat = 0
            var count: CGFloat = 0
            // Правая часть — полоски лимитов цветом строки меню (плашка слева — акцентом, от темы не зависит).
            for x in 28..<Int(size.width) {
                for y in 0..<Int(size.height) {
                    guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.1 else { continue }
                    sum += (c.redComponent + c.greenComponent + c.blueComponent) / 3
                    count += 1
                }
            }
            return count > 0 ? sum / count : -1
        }
        let dark = try luminance(.darkAqua)
        let light = try luminance(.aqua)
        XCTAssertGreaterThan(dark, 0)
        XCTAssertGreaterThanOrEqual(light, 0, "в светлой строке есть что рисовать")
        XCTAssertGreaterThan(dark, light + 0.3, "в тёмной строке меню — светлый, в светлой — тёмный")
    }
}

/// WF164 (31.1): идущие Workflow в плитках — цветом PMP; зелёный, бирюзовый и янтарь — белым.
final class TileRunColorWF164Tests: XCTestCase {
    func testRunColorAvoidsDoneAndWaitColors() {
        XCTAssertEqual(PMPAccent.violet.runHex, 0xA98BFA)
        XCTAssertEqual(PMPAccent.blue.runHex, 0x7AA2F7)
        XCTAssertEqual(PMPAccent.graphite.runHex, 0xECECEE)
        for accent in [PMPAccent.red, .orange, .green, .teal, .amber] { XCTAssertEqual(accent.runHex, 0xECECEE, accent.name) }
    }
}
