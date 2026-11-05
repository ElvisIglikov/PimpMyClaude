import XCTest
@testable import ClaudeAX

/// WF169 (#9178, слово Элвиса 09.10 00:15): «Цвет Claude» простой — живые заставки и цвета без «Больше/Меньше
/// цветов», точек и градиентов; «Отсчёт» — в этом же блоке. С WF174 порядок и полосы цветов — `PanelWF174Tests`;
/// вид блока — снимками (`PMP_SNAPSHOT_DIR`), проверки по тексту исходника сняты ревизией 16.10. С WF237 в блоке и то, что
/// жило в меню жёлтой кнопки: «Схема», «Размер» (кадры — `PanelWF237SnapshotTests`).
final class PanelWF169Tests: XCTestCase {
    func testLiveSchemesAreChosenInPanel() throws {
        // WF237: меню жёлтой кнопки «🎨 Схема ▸» снято — те же схемы строкой «Схема» под «Живым фоном» панели.
        XCTAssertEqual(LookScheme.all.count, 9, "восемь WF146 и «Тёплое свечение» WF251")
        XCTAssertEqual(LookScheme.all.first?.name, "Фиолетовые сумерки")
        XCTAssertTrue(LookScheme.all.contains { $0.id == PanelColorTiles.liveScheme && $0.tones == nil },
                      "«Как у темы» — тона выбранного цвета")
        XCTAssertTrue(LookScheme.all.contains { $0.id == "warm" }, "«Тёплое свечение» — тоже в списке")
        // Выбрать схему значит включить живой фон; движение и плотность остаются.
        var moving = Look(aurora: true, dense: true)
        moving.motion = .live
        let sea = try XCTUnwrap(PanelColorTiles.schemeLook(moving, id: "sea"))
        XCTAssertEqual(sea.scheme, "sea")
        XCTAssertEqual(sea.motion, .live)
        XCTAssertTrue(sea.dense)
        XCTAssertEqual(PanelColorTiles.schemeLook(Look(), id: "forest")?.aurora, true)
        XCTAssertNil(PanelColorTiles.schemeLook(sea, id: "sea"), "та же схема — слать нечего")
        XCTAssertNil(PanelColorTiles.schemeLook(Look(), id: "мусор"))
        XCTAssertEqual(Look().withScheme("violet").schemeID, "violet")
    }

    /// «Размер −  +» (WF237, лист 48): шаги прежнего меню, «как у Claude» между 15 и 16; на краях кнопка неактивна;
    /// размер не со ступени (17 — от колеса или старого меню) идёт к ближайшей ступени в свою сторону.
    func testSizeStepperWalksTheLadder() {
        XCTAssertEqual(PanelColorTiles.sizeStep(from: nil, up: false), .some(15))
        XCTAssertEqual(PanelColorTiles.sizeStep(from: nil, up: true), .some(16))
        XCTAssertEqual(PanelColorTiles.sizeStep(from: 15, up: true), .some(nil), "15 + = как у Claude")
        XCTAssertEqual(PanelColorTiles.sizeStep(from: 16, up: false), .some(nil), "16 − = как у Claude")
        XCTAssertEqual(PanelColorTiles.sizeStep(from: 18, up: true), .some(20))
        XCTAssertNil(PanelColorTiles.sizeStep(from: 12, up: false), "край — кнопка неактивна")
        XCTAssertNil(PanelColorTiles.sizeStep(from: 20, up: true))
        XCTAssertEqual(PanelColorTiles.sizeStep(from: 17, up: true), .some(18))
        XCTAssertEqual(PanelColorTiles.sizeStep(from: 17, up: false), .some(16))
        XCTAssertEqual(PanelColorTiles.sizeStep(from: 11, up: true), .some(12))
        XCTAssertNil(PanelColorTiles.sizeStep(from: 11, up: false))
        XCTAssertEqual(PanelColorTiles.sizeStep(from: 24, up: false), .some(20))
        XCTAssertNil(PanelColorTiles.sizeStep(from: 24, up: true))
    }

    func testDefaultCountdownIsRocket() {
        XCTAssertEqual(SendLook.name(SendLook.defaultStyle), "Ракета", "WF180: «это не взлёт, это ракета»")
        XCTAssertEqual(SendLook.menuItems(selected: "").count, 8)
    }
}
