import AppKit
import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #10301–#10304: кадры полосы «Не влезли» для проверки глазами (правило №1 `INTERFACES.md`) — в покое, с чертой
/// вставки, с подсказкой при переносе и на запасном пути (нет «Записи экрана» — иконки программ серым). Пишутся,
/// только когда задан `PMP_SNAPSHOT_DIR`.
final class MenuExtrasStripSnapshotTests: XCTestCase {
    /// Четыре значка; pid — запущенных программ с иконкой (запасной путь рисует их иконки), нет таких — свой.
    private let items: [MenuBarExtras.Item] = {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.icon != nil }
        return ["Dropbox", "Karabiner", "1Password", "Gemini"].enumerated().map { index, name in
            let pid = index < apps.count ? apps[index].processIdentifier : own
            return MenuBarExtras.Item(pid: pid, bundleId: nil, appName: name, title: name,
                                      frame: CGRect(x: 600 + CGFloat(index) * 30, y: 2, width: 24, height: 24), reason: .notch)
        }
    }()

    /// Белый глиф строки меню 16 pt из символа — как снимок окна значка после `whiten`.
    private func glyph(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white])))
    }

    private func model(glyphs: Bool, note: String? = nil) -> PanelModel {
        let model = PanelModel()
        model.menuExtras = items
        model.extraNote = note
        guard glyphs else { return model }
        let names = ["shippingbox.fill", "keyboard", "key.fill", "sparkle"]
        for (item, name) in zip(items, names) { model.extraImages[item.id] = glyph(name) }
        return model
    }

    /// Полоса на фоне рабочего стола под строкой меню; ширина — как у окна полосы (`fittingSize`).
    @discardableResult
    private func render(_ model: PanelModel, state: ExtrasStripState = ExtrasStripState(), name: String) throws -> CGSize {
        let strip = MenuExtrasStripView(model: model, state: state)
        let size = NSHostingView(rootView: strip).fittingSize
        let height: CGFloat = 37
        let pad: CGFloat = 24
        let scene = ZStack {
            Color(.sRGB, red: 0.04, green: 0.08, blue: 0.19)
            strip.frame(width: size.width, height: height)
        }
        let view = NSHostingView(rootView: scene.frame(width: size.width + pad * 2, height: height + pad * 2))
        view.frame = NSRect(x: 0, y: 0, width: size.width + pad * 2, height: height + pad * 2)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return size }
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        return size
    }

    func testSnapshotRest() throws {
        let size = try render(model(glyphs: true), name: "10301-1-pokoy")
        XCTAssertGreaterThan(size.width, MenuExtrasStrip.iconsWidth(slots: [24, 24, 24, 24]) - 1)
    }

    func testSnapshotInsertLine() throws {
        let state = ExtrasStripState()
        state.insert = 2
        state.dragging = items[0].id
        try render(model(glyphs: true), state: state, name: "10301-2-cherta-vstavki")
    }

    func testSnapshotNote() throws {
        try render(model(glyphs: true, note: "Отпусти в строке меню правее выреза — или здесь, между значками"),
                   name: "10301-3-podskazka")
    }

    func testSnapshotFallback() throws {
        try render(model(glyphs: false), name: "10301-4-zapasnoy-put")
    }
}
