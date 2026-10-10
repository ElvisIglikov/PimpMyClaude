import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF189: снимки для проверки глазами (правила №1 и №3 `INTERFACES.md`) — шапка панели с открытым «Цвет PMP»,
/// каждый вариант значка у часов в строке меню (тёмной и светлой) среди соседей. Пишутся, только когда задан
/// `PMP_SNAPSHOT_DIR`.
final class PanelWF189SnapshotTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func model(now: Date) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.colorsOpen = false
        model.appVersion = "1.10.12"
        model.patch = .installed(version: "2.26454.2", loader: 8)
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 24, resetsAt: now.addingTimeInterval(4 * 3600)),
                                    weekly: .init(used: 37, resetsAt: now.addingTimeInterval(2 * 86400)),
                                    fable: .init(used: 8, resetsAt: now.addingTimeInterval(2 * 86400)),
                                    source: "api")
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.layout = .standard
        return model
    }

    private func render(_ model: PanelModel, height: CGFloat, name: String) throws {
        guard let dir = dir else { return }
        let view = NSHostingView(rootView: PanelRoot(model: model))
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: height)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.backgroundColor = .black
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    func testSnapshotAccentCard() throws {
        let now = Date()
        let open = model(now: now)
        open.accentOpen = true
        try render(open, height: 560, name: "panel-accent-open.png")
        let closed = model(now: now)
        try render(closed, height: 300, name: "panel-header.png")
        // Запасная плашка (до первого вида значка, WF193) — с той же точкой-подсказкой.
        let fallback = model(now: now)
        fallback.iconLook = nil
        try render(fallback, height: 300, name: "panel-header-fallback.png")
    }

    /// Строка меню: соседи (микрофон, звук, батарея, Wi‑Fi) и значок каждого варианта; номер варианта крупно слева.
    func testSnapshotMenuBar() throws {
        guard let dir = dir else { return }
        let variants = StatusIcon.Variant.allCases
        let rowH: CGFloat = 30, width: CGFloat = 520, scale: CGFloat = 2
        let height = rowH * CGFloat(variants.count) * 2 + 20
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
                                                  pixelsHigh: Int(height * scale), bitsPerSample: 8,
                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: width, height: height)
        let base = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        base.cgContext.translateBy(x: 0, y: height)
        base.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: base.cgContext, flipped: true)
        NSColor(white: 0.5, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (half, dark) in [false, true].enumerated() {
            let top = CGFloat(half) * (rowH * CGFloat(variants.count) + 20)
            for (index, variant) in variants.enumerated() {
                let y = top + CGFloat(index) * rowH
                (dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
                      : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)).setFill()
                NSRect(x: 0, y: y, width: width, height: rowH - 2).fill()
                let fg = StatusIconArt.foreground(dark: dark)
                NSAttributedString(string: "\(index + 1)", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold),
                                                                        .foregroundColor: fg])
                    .draw(at: NSPoint(x: 10, y: y + 5))
                var x: CGFloat = 50
                func symbol(_ name: String) {
                    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) else { return }
                    let tinted = NSImage(size: base.size, flipped: false) { rect in
                        base.draw(in: rect)
                        fg.set()
                        rect.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: NSRect(x: x, y: y + (rowH - 2 - base.size.height) / 2,
                                           width: base.size.width, height: base.size.height),
                                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    x += base.size.width + 18
                }
                symbol("mic.fill")
                let look = IconSample.look(variant)
                let drawn = StatusIconArt.image(look, dark: dark, accent: PMPAccent.amber.nsColor)
                drawn.draw(in: NSRect(x: x, y: y + (rowH - 2 - drawn.size.height) / 2, width: drawn.size.width,
                                      height: drawn.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                x += drawn.size.width + 18
                symbol("speaker.wave.2.fill")
                symbol("battery.75percent")
                symbol("wifi")
                NSAttributedString(string: "\(variant)", attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                                      .foregroundColor: fg.withAlphaComponent(0.5)])
                    .draw(at: NSPoint(x: 400, y: y + 7))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("menubar-variants.png"))
    }

    /// Каждый цвет PMP на плашке PMP в строке меню — тёмной и светлой.
    func testSnapshotAccents() throws {
        guard let dir = dir else { return }
        let accents = PMPAccent.allCases
        let cell: CGFloat = 96, width = cell * CGFloat(accents.count) + 20, height: CGFloat = 80, scale: CGFloat = 2
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
                                                  pixelsHigh: Int(height * scale), bitsPerSample: 8,
                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: width, height: height)
        let base = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        base.cgContext.translateBy(x: 0, y: height)
        base.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: base.cgContext, flipped: true)
        for (row, dark) in [true, false].enumerated() {
            (dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
                  : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)).setFill()
            NSRect(x: 0, y: CGFloat(row) * 40, width: width, height: 40).fill()
            let fg = StatusIconArt.foreground(dark: dark)
            // Соседи по строке меню (правило №3): микрофон слева, Wi‑Fi справа от каждой плашки.
            func symbol(_ name: String, x: CGFloat) {
                guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) else { return }
                let tinted = NSImage(size: base.size, flipped: false) { rect in
                    base.draw(in: rect)
                    fg.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: x, y: CGFloat(row) * 40 + (40 - base.size.height) / 2,
                                       width: base.size.width, height: base.size.height),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            for (index, accent) in accents.enumerated() {
                let look = StatusIcon.look(mode: .week, limits: nil, patch: .unknown, phase: .idle, now: Date())
                let image = StatusIconArt.image(StatusIcon.badgeOnly(look), dark: dark, accent: accent.nsColor)
                let left = 10 + CGFloat(index) * cell
                symbol("mic.fill", x: left)
                image.draw(in: NSRect(x: left + 22, y: CGFloat(row) * 40 + 9, width: image.size.width,
                                      height: image.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                symbol("wifi", x: left + 22 + image.size.width + 10)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("menubar-accents.png"))
    }
}
