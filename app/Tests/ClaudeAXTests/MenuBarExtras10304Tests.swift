import CoreGraphics
import XCTest
@testable import ClaudeAX

/// #10301–#10304: правая кнопка по значку «Не влезли» (порядок путей), порядок значков внутри полосы, глиф из снимка
/// окна значка белым.
final class MenuBarExtras10304Tests: XCTestCase {
    private func item(_ pid: pid_t, _ name: String, _ frame: CGRect, _ reason: MenuBarExtras.Reason = .notch) -> MenuBarExtras.Item {
        MenuBarExtras.Item(pid: pid, bundleId: nil, appName: name, title: name, frame: frame, reason: reason)
    }

    private var dictator: MenuBarExtras.Item { item(11, "Dictator", CGRect(x: 557, y: 2, width: 53, height: 24)) }
    private var gemini: MenuBarExtras.Item { item(12, "Gemini", CGRect(x: 624, y: 2, width: 24, height: 24)) }
    private var karabiner: MenuBarExtras.Item { item(13, "Karabiner", CGRect(x: 654, y: 2, width: 31, height: 24)) }
    private var hammerspoon: MenuBarExtras.Item { item(14, "Hammerspoon", CGRect(x: 7, y: 831, width: 24, height: 24), .off) }

    // MARK: правая кнопка

    func testShowMenuWorks() {
        for code: Int32 in [0, -25204] {
            var clicked = false
            let path = MenuBarExtras.secondaryPath(hasElement: true, showMenu: { code },
                                                   rightClick: { clicked = true; return true })
            XCTAssertEqual(path, .showMenu, "код \(code)")
            XCTAssertFalse(clicked, "AXShowMenu сработал — правой кнопки событиями нет")
        }
    }

    func testFallsToRightClick() {
        XCTAssertEqual(MenuBarExtras.secondaryPath(hasElement: true, showMenu: { -25206 }, rightClick: { true }), .rightClick)
    }

    func testFallsToLeft() {
        XCTAssertEqual(MenuBarExtras.secondaryPath(hasElement: true, showMenu: { -25206 }, rightClick: { false }), .left)
        var asked = false
        let path = MenuBarExtras.secondaryPath(hasElement: false, showMenu: { asked = true; return 0 }, rightClick: { false })
        XCTAssertEqual(path, .left)
        XCTAssertFalse(asked, "без элемента AXShowMenu не зовётся")
    }

    func testMenuAppeared() {
        let before: Set<CGWindowID> = [1, 2, 3]
        XCTAssertTrue(MenuBarExtras.menuAppeared(before: before, after: [(1, 630, 25), (40, 13, 101)], pid: 13),
                      "новое окно программы — меню")
        XCTAssertFalse(MenuBarExtras.menuAppeared(before: before, after: [(1, 630, 25), (41, 630, 101)], pid: 13),
                       "новое окно «Пункта управления» — не в счёт")
        XCTAssertFalse(MenuBarExtras.menuAppeared(before: before, after: [(42, 13, 25)], pid: 13),
                       "новое окно программы в строке меню — не меню")
        XCTAssertFalse(MenuBarExtras.menuAppeared(before: before, after: [(2, 13, 101), (3, 13, 0)], pid: 13),
                       "новых окон нет")
    }

    // MARK: порядок внутри полосы

    func testReorderPoint() {
        let window = CGRect(x: 617, y: 0, width: 38, height: 29)
        XCTAssertEqual(MenuBarExtras.reorderPoint(beside: window, after: false), CGPoint(x: 619, y: 15))
        XCTAssertEqual(MenuBarExtras.reorderPoint(beside: window, after: true), CGPoint(x: 653, y: 15))
    }

    func testReorderable() {
        XCTAssertTrue(MenuBarExtras.reorderable(dictator, neighbor: karabiner))
        XCTAssertFalse(MenuBarExtras.reorderable(hammerspoon, neighbor: karabiner), "убранный значок")
        XCTAssertFalse(MenuBarExtras.reorderable(karabiner, neighbor: hammerspoon), "сосед убран")
        XCTAssertFalse(MenuBarExtras.reorderable(karabiner, neighbor: karabiner), "сам с собой")
    }

    /// #10285: убранный значок не переставляется — ни одного события, сразу отказ.
    func testReorderRefusesOff() {
        let done = expectation(description: "отказ")
        MenuBarExtras.reorder(hammerspoon, beside: gemini, after: true) { ok in
            XCTAssertFalse(ok)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testPlaced() {
        let order = [dictator, gemini, karabiner]
        XCTAssertFalse(MenuBarExtras.placed(karabiner, beside: dictator, after: true, in: order), "не переехал")
        XCTAssertTrue(MenuBarExtras.placed(karabiner, beside: dictator, after: true, in: [dictator, karabiner, gemini]))
        XCTAssertTrue(MenuBarExtras.placed(dictator, beside: karabiner, after: false, in: [gemini, dictator, karabiner]))
        XCTAssertFalse(MenuBarExtras.placed(dictator, beside: karabiner, after: true, in: [gemini, dictator, karabiner]))
        XCTAssertTrue(MenuBarExtras.placed(karabiner, beside: dictator, after: true, in: [dictator, gemini]),
                      "вышел из-под выреза в строку меню — тоже переехал")
        XCTAssertFalse(MenuBarExtras.placed(karabiner, beside: dictator, after: true, in: [gemini, karabiner]),
                       "соседа нет — проверить нечем")
    }

    // MARK: глиф

    /// RGBA premultiplied, `width × height`, все пиксели прозрачны; `set` — пиксель (x, y сверху).
    private func buffer(_ width: Int, _ height: Int) -> [UInt8] { [UInt8](repeating: 0, count: width * height * 4) }

    private func set(_ px: inout [UInt8], _ width: Int, _ x: Int, _ y: Int, _ rgba: [UInt8]) {
        let i = (y * width + x) * 4
        for k in 0..<4 { px[i + k] = rgba[k] }
    }

    private func pixel(_ px: [UInt8], _ width: Int, _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * width + x) * 4
        return Array(px[i..<i + 4])
    }

    func testWhitenEmptyAndFilled() {
        var empty = buffer(6, 4)
        XCTAssertNil(MenuBarExtras.whiten(&empty, width: 6, height: 4), "пустой снимок — запасной путь")
        var filled = [UInt8](repeating: 255, count: 6 * 4 * 4)
        XCTAssertNil(MenuBarExtras.whiten(&filled, width: 6, height: 4), "залит целиком — снялся фон, а не глиф")
    }

    func testWhiteGlyphWithSoftEdges() {
        var px = buffer(6, 4)
        set(&px, 6, 2, 1, [255, 255, 255, 255])
        set(&px, 6, 3, 2, [255, 255, 255, 255])
        set(&px, 6, 1, 1, [8, 8, 8, 8])       // мягкий край — в рамку не входит
        set(&px, 6, 4, 2, [60, 60, 60, 120])  // полупрозрачный серый край
        XCTAssertEqual(MenuBarExtras.whiten(&px, width: 6, height: 4), CGRect(x: 2, y: 1, width: 3, height: 2))
        XCTAssertEqual(pixel(px, 6, 2, 1), [255, 255, 255, 255])
        XCTAssertEqual(pixel(px, 6, 4, 2), [120, 120, 120, 120], "край белый той же прозрачности")
        XCTAssertEqual(pixel(px, 6, 1, 1), [8, 8, 8, 8])
    }

    func testGrayAndBlackBecomeWhite() {
        var px = buffer(4, 4)
        set(&px, 4, 1, 1, [128, 128, 128, 255]) // серый 50 %
        set(&px, 4, 2, 2, [0, 0, 0, 255])       // чёрный глиф светлой строки меню
        XCTAssertEqual(MenuBarExtras.whiten(&px, width: 4, height: 4), CGRect(x: 1, y: 1, width: 2, height: 2))
        XCTAssertEqual(pixel(px, 4, 1, 1), [255, 255, 255, 255])
        XCTAssertEqual(pixel(px, 4, 2, 2), [255, 255, 255, 255])
    }

    func testRedDotStaysRed() {
        var px = buffer(4, 4)
        set(&px, 4, 1, 1, [0, 0, 0, 255])      // чёрный глиф
        set(&px, 4, 2, 1, [255, 0, 0, 255])    // красная точка записи
        set(&px, 4, 2, 2, [64, 0, 0, 64])      // её мягкий край
        XCTAssertNotNil(MenuBarExtras.whiten(&px, width: 4, height: 4))
        XCTAssertEqual(pixel(px, 4, 1, 1), [255, 255, 255, 255])
        XCTAssertEqual(pixel(px, 4, 2, 1), [255, 0, 0, 255])
        XCTAssertEqual(pixel(px, 4, 2, 2), [64, 0, 0, 64])
    }

    /// Снимок 8×8 с чёрным квадратом 4×4 посередине → белый глиф 4×4.
    func testGlyphFromImageCropsAndWhitens() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 2, y: 2, width: 4, height: 4))
        let shot = try XCTUnwrap(context.makeImage())
        let glyph = try XCTUnwrap(MenuBarExtras.glyph(from: shot))
        XCTAssertEqual(glyph.width, 4)
        XCTAssertEqual(glyph.height, 4)
        let read = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                           space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        read.draw(glyph, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        let data = try XCTUnwrap(read.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual([data[0], data[1], data[2], data[3]], [255, 255, 255, 255])
    }

    /// Убранный значок не снимается вовсе: по его рамке нашлось бы окно чужого видимого значка.
    func testOffItemHasNoGlyph() {
        XCTAssertNil(MenuBarExtras.glyph(hammerspoon))
    }
}
