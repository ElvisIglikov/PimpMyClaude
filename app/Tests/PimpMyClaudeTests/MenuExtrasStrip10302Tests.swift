import AppKit
import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #10301–#10304: полоса «Не влезли» — место под значком PMP (по центру, на его экране, в пределах экрана), высота,
/// размер глифов, точка вставки и перестановка при перетаскивании, отмена переноса закрытием панели.
final class MenuExtrasStrip10302Tests: XCTestCase {
    /// Мак с вырезом: экран 1512×982, строка меню 37; значок PMP — окно 1200…1240 в строке меню.
    private let notched = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let notchedVisible = CGRect(x: 0, y: 0, width: 1512, height: 945)
    private func icon(midX: CGFloat, minY: CGFloat = 945) -> CGRect {
        CGRect(x: midX - 20, y: minY, width: 40, height: 37)
    }

    // MARK: рамка

    func testCenteredUnderIcon() {
        let frame = MenuExtrasStrip.stripFrame(width: 200, lead: 0, anchor: icon(midX: 1220), screen: notched,
                                               visible: notchedVisible)
        XCTAssertEqual(frame, CGRect(x: 1120, y: 908, width: 200, height: 37))
        XCTAssertEqual(frame.midX, 1220, "середина полосы — под серединой значка")
        XCTAssertEqual(frame.maxY, notched.maxY - 37, "верх — низ строки меню")
    }

    func testClampedAtRightEdge() {
        let frame = MenuExtrasStrip.stripFrame(width: 200, lead: 0, anchor: icon(midX: 1490), screen: notched,
                                               visible: notchedVisible)
        XCTAssertEqual(frame.maxX, notchedVisible.maxX - 8, "не вылезает за правый край, поле 8")
        XCTAssertEqual(frame.width, 200)
    }

    func testClampedAtLeftEdge() {
        let frame = MenuExtrasStrip.stripFrame(width: 200, lead: 0, anchor: icon(midX: 50), screen: notched,
                                               visible: notchedVisible)
        XCTAssertEqual(frame.minX, 8, "не вылезает за левый край, поле 8")
    }

    /// Второй экран правее и ниже главного, строка меню 24 (без выреза): полоса — на нём, высота 34.
    func testSecondScreenWithOffsetOrigin() {
        let screen = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let visible = CGRect(x: 1512, y: -200, width: 1920, height: 1056)
        let frame = MenuExtrasStrip.stripFrame(width: 200, lead: 0, anchor: icon(midX: 2900, minY: 856), screen: screen,
                                               visible: visible)
        XCTAssertEqual(frame, CGRect(x: 2800, y: 822, width: 200, height: 34))
        XCTAssertTrue(screen.contains(frame), "на экране значка")
    }

    func testWiderThanScreen() {
        let frame = MenuExtrasStrip.stripFrame(width: 2000, lead: 0, anchor: icon(midX: 1220), screen: notched,
                                               visible: notchedVisible)
        XCTAssertEqual(frame.width, notchedVisible.width - 16)
        XCTAssertEqual(frame.minX, 8)
    }

    func testHeight() {
        let notch = MenuExtrasStrip.stripFrame(width: 100, lead: 0, anchor: icon(midX: 700), screen: notched,
                                               visible: notchedVisible)
        XCTAssertEqual(notch.height, 37, "у выреза — высота строки меню")
        let plain = MenuExtrasStrip.stripFrame(width: 100, lead: 0, anchor: CGRect(x: 680, y: 1056, width: 40, height: 24),
                                               screen: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                               visible: CGRect(x: 0, y: 0, width: 1920, height: 1056))
        XCTAssertEqual(plain.height, 34, "на обычной строке меню — не ниже 34")
        XCTAssertEqual(plain.maxY, 1056)
    }

    /// Строка-подсказка слева от значков не сдвигает значки: их середина — под значком PMP.
    func testNoteDoesNotMoveIcons() {
        let frame = MenuExtrasStrip.stripFrame(width: 300, lead: 100, anchor: icon(midX: 1000), screen: notched,
                                               visible: notchedVisible)
        XCTAssertEqual(frame.minX, 800)
        XCTAssertEqual(frame.minX + 100 + 200 / 2, 1000, "середина значков — под значком PMP")
    }

    /// Плашка PMP под строкой меню (значок за вырезом, #10016): полоса — под плашкой.
    func testUnderTab() {
        let tab = CGRect(x: 1400, y: 900, width: 60, height: 28)
        let frame = MenuExtrasStrip.stripFrame(width: 100, lead: 0, anchor: tab, screen: notched, visible: notchedVisible)
        XCTAssertEqual(frame.maxY, 900)
        XCTAssertEqual(frame.midX, 1430)
    }

    // MARK: размер значков

    func testGlyphSize() {
        XCTAssertEqual(MenuExtrasStrip.glyphSize(CGSize(width: 16, height: 14)), CGSize(width: 20, height: 18),
                       "мелкий глиф растягивается не больше чем в 1,25 раза — не мылится")
        XCTAssertEqual(MenuExtrasStrip.glyphSize(CGSize(width: 30, height: 30)), CGSize(width: 24, height: 24))
        XCTAssertEqual(MenuExtrasStrip.glyphSize(CGSize(width: 100, height: 16)), CGSize(width: 64, height: 10),
                       "широкий текстовый значок — не шире 64")
        XCTAssertEqual(MenuExtrasStrip.glyphSize(.zero), CGSize(width: 24, height: 24))
        XCTAssertEqual(MenuExtrasStrip.glyphSize(CGSize(width: 24, height: 24), height: 28),
                       CGSize(width: 28, height: 28), "копия под курсором — 28")
    }

    func testSlotAndRowWidth() {
        XCTAssertEqual(MenuExtrasStrip.slotWidth(CGSize(width: 18, height: 18)), 24, "слот не уже квадрата")
        XCTAssertEqual(MenuExtrasStrip.slotWidth(CGSize(width: 50, height: 12)), 50)
        XCTAssertEqual(MenuExtrasStrip.iconsWidth(slots: [24, 24]), 88, "поля 8 + (24 + 4 + 4) × 2 + промежуток 8")
        XCTAssertEqual(MenuExtrasStrip.iconsWidth(slots: []), 16)
    }

    /// Ширина, что считает полоса, — та же, что у нарисованного ряда (без подсказки).
    func testRowWidthMatchesView() {
        let model = PanelModel()
        model.menuExtras = [extra(1, "Dropbox"), extra(2, "Karabiner")]
        let view = NSHostingView(rootView: MenuExtrasStripView(model: model, state: ExtrasStripState()))
        XCTAssertEqual(view.fittingSize.width, MenuExtrasStrip.iconsWidth(slots: [24, 24]), accuracy: 0.5)
    }

    // MARK: перенос внутри полосы

    func testZoneHasNoSlackAbove() {
        let zone = MenuExtrasStrip.zone(CGRect(x: 100, y: 900, width: 200, height: 37))
        XCTAssertEqual(zone, CGRect(x: 96, y: 896, width: 208, height: 41))
        XCTAssertEqual(zone.maxY, 937, "сверху запаса нет — там строка меню (#10280)")
    }

    func testInsertion() {
        let slots = [CGRect(x: 8, y: 2, width: 32, height: 32), CGRect(x: 48, y: 2, width: 32, height: 32),
                     CGRect(x: 88, y: 2, width: 32, height: 32)]
        XCTAssertEqual(MenuExtrasStrip.insertion(x: 5, slots: slots), 0, "левее первого")
        XCTAssertEqual(MenuExtrasStrip.insertion(x: 30, slots: slots), 1, "между первым и вторым")
        XCTAssertEqual(MenuExtrasStrip.insertion(x: 70, slots: slots), 2)
        XCTAssertEqual(MenuExtrasStrip.insertion(x: 200, slots: slots), 3, "правее последнего")
    }

    func testReorderTarget() {
        XCTAssertNil(MenuExtrasStrip.reorderTarget(count: 3, from: 1, insert: 1), "своё место — слева от себя")
        XCTAssertNil(MenuExtrasStrip.reorderTarget(count: 3, from: 1, insert: 2), "своё место — справа от себя")
        XCTAssertEqual(MenuExtrasStrip.reorderTarget(count: 3, from: 1, insert: 0), ExtraReorder(neighbor: 0, after: false))
        XCTAssertEqual(MenuExtrasStrip.reorderTarget(count: 3, from: 1, insert: 3), ExtraReorder(neighbor: 2, after: true))
        XCTAssertEqual(MenuExtrasStrip.reorderTarget(count: 3, from: 0, insert: 3), ExtraReorder(neighbor: 2, after: true))
        XCTAssertEqual(MenuExtrasStrip.reorderTarget(count: 3, from: 2, insert: 0), ExtraReorder(neighbor: 0, after: false))
        XCTAssertNil(MenuExtrasStrip.reorderTarget(count: 3, from: 0, insert: 4))
        XCTAssertNil(MenuExtrasStrip.reorderTarget(count: 3, from: 3, insert: 0))
    }

    /// Панель закрыли посреди переноса: отпускание ничего не делает, следующий перенос — как обычно.
    func testCloseCancelsDrag() {
        let state = ExtrasStripState()
        var begun = 0, ended = 0
        state.begin = { item in begun += 1; state.active = item }
        state.end = { _ in ended += 1 }
        state.dragChanged(extra(1, "Dropbox"))
        XCTAssertEqual(begun, 1)
        state.reset()
        state.dragChanged(extra(1, "Dropbox"))
        XCTAssertEqual(begun, 1, "жест после закрытия не начинает перенос заново")
        state.dragEnded()
        XCTAssertEqual(ended, 0, "отпустил после закрытия — значок не переезжает")
        state.dragChanged(extra(1, "Dropbox"))
        state.dragEnded()
        XCTAssertEqual(begun, 2)
        XCTAssertEqual(ended, 1)
    }

    /// Нет значка PMP — полосы нет, панель не сдвигается.
    func testNoAnchorHides() {
        let model = PanelModel()
        model.menuExtras = [extra(1, "Dropbox")]
        let strip = MenuExtrasStrip(model: model)
        strip.anchor = { nil }
        XCTAssertEqual(strip.update(open: true), 0)
        XCTAssertEqual(strip.update(open: false), 0)
    }

    private func extra(_ pid: pid_t, _ name: String) -> MenuBarExtras.Item {
        MenuBarExtras.Item(pid: pid, bundleId: nil, appName: name, title: name,
                           frame: CGRect(x: 600 + CGFloat(pid) * 30, y: 2, width: 24, height: 24), reason: .notch)
    }
}
