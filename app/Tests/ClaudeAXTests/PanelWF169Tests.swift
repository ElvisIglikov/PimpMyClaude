import XCTest
@testable import ClaudeAX

/// WF169 (#9178, слово Элвиса 09.10 00:15): «Цвет Claude» простой — живые заставки и цвета без «Больше/Меньше
/// цветов», точек и градиентов; «Отсчёт: 🚀 Взлёт ▸» — в этом же блоке, в настройках его нет. С WF174 порядок и
/// полосы цветов — `PanelWF174Tests`.
final class PanelWF169Tests: XCTestCase {
    private var panelSource: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
            return try String(contentsOf: root.appendingPathComponent("Sources/PimpMyClaude/PimpPanel.swift"),
                              encoding: .utf8)
        }
    }

    /// Тело `private struct <name>` до следующего объявления верхнего уровня.
    private func body(of name: String, in source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: "private struct \(name)"), "нет \(name)")
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\nprivate struct ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    func testEightLiveSchemesStayForWindowMenu() {
        // WF180: в панели схем нет (живой фон — в тонах цвета), но меню жёлтой кнопки «🎨 Схема ▸» их держит.
        XCTAssertEqual(LookScheme.all.count, 8)
        XCTAssertEqual(LookScheme.all.first?.name, "Фиолетовые сумерки")
        XCTAssertTrue(LookScheme.all.contains { $0.id == PanelColorTiles.liveScheme && $0.tones == nil },
                      "схема панели — «Как у темы»")
        let look = Look().withScheme("sea")
        XCTAssertTrue(look.aurora)
        XCTAssertEqual(look.scheme, "sea")
        XCTAssertEqual(Look().withScheme("violet").schemeID, "violet")
    }

    func testDefaultCountdownIsRocket() {
        XCTAssertEqual(SendLook.name(SendLook.defaultStyle), "Ракета", "WF180: «это не взлёт, это ракета»")
        XCTAssertEqual(SendLook.menuItems(selected: "").count, 8)
    }

    func testColorsCardIsSimpleAndOwnsCountdownLook() throws {
        let source = try panelSource
        let card = try body(of: "ColorsCard", in: source)
        for gone in ["Меньше цветов", "Больше цветов", "Ещё цвета", "moreColors", "SchemeDot", "ColorDot",
                     "LinearGradient", "AngularGradient", "windowColor(.byProject)"] {
            XCTAssertFalse(card.contains(gone), "в «Цвет Claude» осталось «\(gone)»")
        }
        XCTAssertFalse(source.contains("moreColors"), "состояния «Ещё цвета» больше нет")
        // WF180: сверху вниз — «Живой» в заголовке, полосы цветов, отсчёт картинками; рядов схем нет.
        let live = try XCTUnwrap(card.range(of: "liveToggle\n"))
        let strips = try XCTUnwrap(card.range(of: "                    strips\n"))
        let countdown = try XCTUnwrap(card.range(of: "CountdownRow(model: model)"))
        XCTAssertLessThan(live.lowerBound, strips.lowerBound)
        XCTAssertLessThan(strips.lowerBound, countdown.lowerBound)
        XCTAssertFalse(card.contains("LookScheme.all"), "схем в панели нет")
        XCTAssertTrue(card.contains("PanelColorTiles.strips("))
        // Один источник выбора вида — ряд картинок в «Отсчёт»; выпадающего списка нет нигде.
        XCTAssertFalse(source.contains("SendLook.menuItems("))
        XCTAssertTrue(try body(of: "CountdownRow", in: source).contains("SendLook.styles"))
        XCTAssertFalse(try body(of: "EnterGroup", in: source).contains("sendLookStyle"), "дубль в настройках Enter")
        XCTAssertFalse(source.contains("struct SendLookMenu"))
    }
}
