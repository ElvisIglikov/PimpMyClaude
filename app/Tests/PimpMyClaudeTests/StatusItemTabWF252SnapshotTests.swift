import AppKit
import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// #10016 (WF252): кадры плашки PMP для проверки глазами (правило №1 `INTERFACES.md`) — на своём месте под строкой
/// меню Мака с вырезом, в трёх состояниях и узкий значок рядом с обычным. Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class StatusItemTabWF252SnapshotTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var weekLook: StatusIcon.Look {
        let limits = ClaudeLimits(at: now, plan: nil, fiveHour: nil,
                                  weekly: ClaudeLimits.Limit(used: 84, resetsAt: now.addingTimeInterval(86_400)),
                                  fable: nil, source: "api")
        return StatusIcon.look(mode: .week, limits: limits, patch: .installed(version: "2.9939.2", loader: 8),
                               phase: .idle, now: now)
    }

    private func tab(hovered: Bool = false, pressed: Bool = false) -> StatusItemTabButton {
        let button = StatusItemTabButton(frame: NSRect(origin: .zero, size: StatusItemTabButton.size))
        let accent = PMPAccent.violet.nsColor
        button.badge = StatusIconArt.image(StatusIcon.badgeOnly(weekLook), dark: true, accent: accent)
        button.accent = accent
        button.show(hovered: hovered, pressed: pressed)
        return button
    }

    private func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// Холст в точках, `scale` пикселей на точку; рисуем снизу вверх, как AppKit.
    private func canvas(_ size: CGSize, scale: CGFloat, name: String, draw: () throws -> Void) throws {
        let out = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        out.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: out))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        try draw()
        NSGraphicsContext.restoreGraphicsState()
        guard let dir = dir else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try XCTUnwrap(out.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    private func desktop(_ rect: CGRect) {
        NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.12, blue: 0.27, alpha: 1),
                            NSColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 1)])?.draw(in: rect, angle: -60)
    }

    /// Строка меню справа от выреза: часы, системные значки и `icon` (вид значка PMP) левее них. `notchRight` — где
    /// кончается вырез.
    private func menuBar(_ rect: CGRect, notchRight: CGFloat, icon: NSImage?) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        rect.fill()
        // Вырез: чёрный, нижние углы скруглены.
        let notch = NSBezierPath(roundedRect: CGRect(x: rect.minX - 40, y: rect.minY - 1, width: notchRight - rect.minX + 40,
                                                     height: rect.height + 12), xRadius: 9, yRadius: 9)
        NSColor.black.setFill()
        notch.fill()
        let fg = NSColor.white.withAlphaComponent(0.92)
        let clock = NSAttributedString(string: "Пт 17 окт.  00:12", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: fg])
        var x = rect.maxX - 12 - clock.size().width
        clock.draw(at: CGPoint(x: x, y: rect.midY - clock.size().height / 2))
        let symbols = ["switch.2", "magnifyingglass", "battery.75percent", "wifi", "moon.fill", "speaker.wave.2.fill",
                       "bluetooth", "mic.fill", "display", "keyboard", "cloud.fill", "clock.fill", "headphones",
                       "bolt.fill", "camera.fill", "lock.fill", "airplane", "sun.max.fill", "cup.and.saucer.fill",
                       "printer.fill", "music.note", "drop.fill", "globe"]
        for name in symbols {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [fg]))) else { continue }
            let next = x - 22 - image.size.width / 2
            if next - 12 < notchRight { break }
            x = next
            image.draw(in: CGRect(x: x - image.size.width / 2 + 11, y: rect.midY - image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
        }
        guard let icon = icon else { return }
        let left = x - 10 - icon.size.width
        icon.draw(in: CGRect(x: left, y: rect.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// Правый верх экрана 1440×932 с вырезом: значки заняли всё место справа, PMP не влез — плашка на своём месте.
    func testSnapshotTabUnderMenuBar() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 932)
        let region = CGRect(x: 600, y: 932 - 120, width: 840, height: 120)
        let size = StatusItemTabButton.size
        let origin = StatusItemTab.origin(offset: nil, size: size, screen: screen, menuBar: 28)
        let button = try bitmap(tab())
        try canvas(region.size, scale: 2, name: "1-plashka-pod-vyrezom.png") {
            let local = CGRect(origin: .zero, size: region.size)
            desktop(local)
            menuBar(CGRect(x: 0, y: local.maxY - 28, width: local.width, height: 28), notchRight: 798 - region.minX,
                    icon: nil)
            _ = button.draw(in: CGRect(x: origin.x - region.minX, y: origin.y - region.minY, width: size.width,
                                       height: size.height), from: .zero, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: nil)
        }
    }

    /// Покой, под курсором, панель открыта (рамка цветом PMP) — крупно.
    func testSnapshotTabStates() throws {
        let size = StatusItemTabButton.size
        let states = [tab(), tab(hovered: true), tab(pressed: true)]
        let images = try states.map(bitmap)
        try canvas(CGSize(width: 3 * size.width + 4 * 24, height: size.height + 48), scale: 4,
                   name: "2-plashka-sostoyaniya.png") {
            desktop(CGRect(x: 0, y: 0, width: 3 * size.width + 4 * 24, height: size.height + 48))
            for (index, image) in images.enumerated() {
                _ = image.draw(in: CGRect(x: 24 + CGFloat(index) * (size.width + 24), y: 24, width: size.width,
                                          height: size.height), from: .zero, operation: .sourceOver, fraction: 1,
                               respectFlipped: true, hints: nil)
            }
        }
    }

    /// Строка меню: обычный значок «PMP 84» и узкий — та же плашка без числа (первый шаг сторожа).
    func testSnapshotCompactIcon() throws {
        let accent = PMPAccent.violet.nsColor
        let full = StatusIconArt.image(weekLook, dark: true, accent: accent)
        let narrow = StatusIconArt.image(StatusIcon.badgeOnly(weekLook), dark: true, accent: accent)
        try canvas(CGSize(width: 640, height: 72), scale: 2, name: "3-uzkiy-znachok.png") {
            desktop(CGRect(x: 0, y: 0, width: 640, height: 72))
            menuBar(CGRect(x: 0, y: 40, width: 640, height: 28), notchRight: 60, icon: full)
            menuBar(CGRect(x: 0, y: 4, width: 640, height: 28), notchRight: 60, icon: narrow)
        }
    }
}
