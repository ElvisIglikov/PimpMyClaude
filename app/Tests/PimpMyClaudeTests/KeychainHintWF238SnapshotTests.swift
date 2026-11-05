import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF238: кадры подсказки у окна macOS «Claude Safe Storage» — для проверки глазами (правило №1 `INTERFACES.md`).
/// Пример окна и плашка — те же виды, что в приложении; своей рамки у подсказки нет с WF246 (слово Элвиса 11.10).
/// Живых окон тест не открывает. Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class KeychainHintWF238SnapshotTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    /// Вид в своём размере — в растр с прозрачным фоном.
    private func bitmap<Content: View>(_ view: Content) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    /// Кусок экрана: пример окна macOS (пока его не закрыли), под ним плашка.
    private func scene(dialog shown: Bool, _ content: KeychainHintPlaque.Content, name: String) throws {
        let canvas = CGRect(x: 0, y: 0, width: 760, height: 640)
        let dialog = try bitmap(KeychainDialogExample())
        XCTAssertEqual(dialog.size.width, KeychainDialogExample.fullWidth)
        let window = CGRect(x: (canvas.width - dialog.size.width) / 2, y: 64, width: dialog.size.width,
                            height: dialog.size.height)
        // Окно плашки — плашка и поле под стрелку со всех сторон (#9841, `hintPointer`); место — по самой плашке.
        let edge = HintPointer.inset
        let bare = try bitmap(KeychainHintPlaque(content: content, width: KeychainHint.plaqueWidth(window: window)))
        let size = CGSize(width: bare.size.width - 2 * edge, height: bare.size.height - 2 * edge)
        let place = KeychainHint.plaqueFrame(window: window, size: size, visible: canvas)
        XCTAssertEqual(place.minX, window.minX, "плашка и окно macOS — по одной левой грани")
        XCTAssertEqual(place.maxX, window.maxX)
        var pointed = KeychainHintPlaque(content: content, width: KeychainHint.plaqueWidth(window: window))
        if shown { pointed.pointer = HintPull.side(of: window, from: place) }
        XCTAssertEqual(pointed.pointer, shown ? .top : nil, "плашка под окном — стрелка вверх, к нему")
        let plaque = try bitmap(pointed)

        let scale: CGFloat = 2
        let out = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        out.size = canvas.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: out))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // «Рабочий стол»: тёмное окно чата под окном macOS.
        NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1).setFill()
        canvas.fill()
        let cocoa = { (rect: CGRect) in KeychainHint.flipped(rect, primaryHeight: canvas.height) }
        let draw = { (rep: NSBitmapImageRep, rect: CGRect) in
            _ = rep.draw(in: cocoa(rect), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        }
        if shown { draw(dialog, window) }
        draw(plaque, place.insetBy(dx: -edge, dy: -edge))
        NSGraphicsContext.restoreGraphicsState()
        guard let dir = dir else { return }
        try XCTUnwrap(out.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    func testSnapshotHintUnderMacWindow() throws {
        try scene(dialog: true, .hint(.update), name: "1-plashka.png")
    }

    func testSnapshotDone() throws {
        try scene(dialog: false, .done(.update), name: "2-gotovo.png")
    }
}
