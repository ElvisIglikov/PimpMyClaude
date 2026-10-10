import AppKit
import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF174 (#9182); WF180: сводка группы «Значок» и снимок панели для проверки глазами (правило №1 `INTERFACES.md`):
/// снимок пишется, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelWF174AppTests: XCTestCase {
    func testIconSamples() {
        // Образцы вариантов под «Цвет PMP» — той же кистью, что у часов (WF189: числа вернулись).
        for variant in StatusIcon.Variant.allCases {
            XCTAssertGreaterThan(IconSample.image(variant, accent: PMPAccent.violet.nsColor).size.width, 20)
        }
        XCTAssertTrue(IconSample.look(.week).showsNumber)
        XCTAssertFalse(IconSample.look(.pmp).showsNumber)
    }

    private func chips() throws -> [WindowColorChip] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("claude-patch/themes.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let themes = try XCTUnwrap(root["themes"] as? [[String: Any]])
        return ClaudeAXController.panelThemeIDs.compactMap { id in
            guard let theme = themes.first(where: { $0["id"] as? String == id }),
                  let palette = theme["palette"] as? [String: String] else { return nil }
            return WindowColorChip(id: id, name: theme["name"] as? String ?? id,
                                   background: palette["background"] ?? "#000000",
                                   accent: palette["accent"] ?? "#ffffff", light: theme["type"] as? String == "light")
        }
    }

    func testSnapshotIcons() throws {
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        let images = StatusIcon.Variant.allCases.map { IconSample.image($0, accent: PMPAccent.violet.nsColor) }
        let width = images.map { $0.size.width }.max() ?? 60
        let canvas = NSImage(size: NSSize(width: width * 4 + 20, height: 30 * CGFloat(images.count)), flipped: true) { _ in
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: width * 4 + 20, height: 30 * CGFloat(images.count)).fill()
            for (index, image) in images.enumerated() {
                image.draw(in: NSRect(x: 10, y: CGFloat(index) * 30 + 4, width: image.size.width, height: image.size.height))
            }
            return true
        }
        let tiff = try XCTUnwrap(canvas.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icons.png"))
    }

    func testSnapshotPanel() throws {
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        let chips = try chips()
        for (name, live, choice) in [("live-on", true, WindowColorChoice.theme("mint")),
                                     ("live-off", false, WindowColorChoice.theme("lemonade")),
                                     ("settings-icon", false, WindowColorChoice.plain),
                                     ("settings-enter", false, WindowColorChoice.plain)] {
            let model = PanelModel()
            if name == "settings-icon" {
                model.accentOpen = true
                model.iconVariant = .projects
            }
            if name == "settings-enter" {
                model.sheet = .settings
                model.settingsGroup = .enter
            }
            model.phase = .open
            model.colorsOpen = true
            model.windowThemes = chips
            model.allThemes = chips
            model.windowColor = choice
            model.liveBackground = live
            model.liveScheme = live ? "theme" : "sea"
            model.reduceMotion = true
            let view = NSHostingView(rootView: PanelRoot(model: model))
            view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin,
                                height: 900)
            view.appearance = NSAppearance(named: .darkAqua)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            window.backgroundColor = .black
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            view.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("panel-\(name).png"))
        }
    }
}
