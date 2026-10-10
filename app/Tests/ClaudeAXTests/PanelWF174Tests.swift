import XCTest
@testable import ClaudeAX

/// WF174 (#9182, слово Элвиса 09.10 02:00): «Цвет Claude» — живой фон отдельным выключателем, цвета полосами по кругу
/// (светлая с «Как у Claude» первой, две тёмные), образец — фон темы; виджеты «5 часов» и «Fable» раздельно, блок
/// скрывается и возвращается; значок у часов — три выключателя (неделя, проекты, буквы PMP).
final class PanelWF174Tests: XCTestCase {
    private func defaults(_ name: String = #function) -> UserDefaults {
        let store = UserDefaults(suiteName: "PanelWF174Tests.\(name)")!
        store.removePersistentDomain(forName: "PanelWF174Tests.\(name)")
        return store
    }

    private var catalogChips: [WindowColorChip] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("claude-patch")
        let themes = ThemeCatalog.load(directory: root)
        return ClaudeAXController.panelThemeIDs.compactMap { id in themes.first { $0.id == id } }.map(WindowColorChip.init)
    }

    // MARK: цвета

    func testStripsDarkFirstThenLightTwoEvenRows() throws {
        // WF177: «в одну или в две строчки поплотнее, выравнивание по ширине» — две полосы поровну.
        let chips = catalogChips
        XCTAssertEqual(chips.count, ClaudeAXController.panelThemeIDs.count, "все темы полос есть в каталоге")
        let strips = PanelColorTiles.strips(chips)
        XCTAssertEqual(strips.count, 2, "две строки")
        XCTAssertEqual(strips.map { $0.count }, [15, 15], "поровну — плитки одной ширины")
        XCTAssertEqual(PanelColorTiles.perStrip(chips), 15)
        XCTAssertEqual(strips.first?.first, .plain, "первым — «Как у Claude»")
        let light = Set(chips.filter { $0.light }.map { $0.id })
        func ids(_ strip: [PanelColorTiles.Tile]) -> [String] {
            strip.compactMap { if case .theme(let id) = $0 { return id } else { return nil } }
        }
        let all = strips.flatMap(ids)
        // WF210 (#9378, слово Элвиса 10.10): «светлые темы куда-то в конец убрать и начать с тёмных».
        let firstLight = try XCTUnwrap(all.firstIndex { light.contains($0) })
        XCTAssertTrue(all[..<firstLight].allSatisfy { !light.contains($0) }, "сначала тёмные")
        XCTAssertTrue(all[firstLight...].allSatisfy { light.contains($0) }, "светлые — в конце")
        XCTAssertEqual(Set(all), Set(ClaudeAXController.panelThemeIDs), "ни одна тема не потерялась")
        XCTAssertEqual(all.count, ClaudeAXController.panelThemeIDs.count, "без повторов")
    }

    func testStripsFollowColorWheelGraysLast() {
        let chips = catalogChips
        let byID = Dictionary(uniqueKeysWithValues: chips.map { ($0.id, $0) })
        let all = PanelColorTiles.strips(chips).flatMap { $0 }
        for light in [true, false] {
            let keys = all.compactMap { tile -> (hue: Double, saturation: Double)? in
                guard case .theme(let id) = tile, let chip = byID[id], chip.light == light else { return nil }
                return PanelColorTiles.hue(chip.background)
            }
            let colored = keys.prefix { $0.saturation >= 0.15 }
            XCTAssertTrue(keys.dropFirst(colored.count).allSatisfy { $0.saturation < 0.15 }, "серые — в конце группы")
            XCTAssertEqual(colored.map { $0.hue }, colored.map { $0.hue }.sorted(), "по цветовому кругу")
        }
        let dark = all.filter { if case .theme(let id) = $0 { return byID[id]?.light == false } else { return false } }
        XCTAssertEqual(dark.last, .theme("gray"), "серая — последней из тёмных")
    }

    func testHue() {
        XCTAssertEqual(PanelColorTiles.hue("#ff0000").hue, 0, accuracy: 0.01)
        XCTAssertEqual(PanelColorTiles.hue("#00ff00").hue, 120, accuracy: 0.01)
        XCTAssertEqual(PanelColorTiles.hue("#0000ff").hue, 240, accuracy: 0.01)
        XCTAssertEqual(PanelColorTiles.hue("#808080").saturation, 0)
        XCTAssertEqual(PanelColorTiles.hue("мусор").saturation, 0)
    }

    func testExactlyOneSwatchSelected() {
        let strips = PanelColorTiles.strips(catalogChips).flatMap { $0 }
        for choice in [WindowColorChoice.plain, .theme("mint"), .theme("lemonade"), .theme("ultra"), .theme("blue")] {
            XCTAssertEqual(strips.filter { PanelColorTiles.isSelected($0, choice) }.count, 1, "\(choice)")
        }
        XCTAssertEqual(strips.filter { PanelColorTiles.isSelected($0, .byProject) }.count, 0, "по проектам — ни один")
        XCTAssertEqual(strips.filter { PanelColorTiles.isSelected($0, .theme("cobalt")) }.count, 0, "тема из меню — ни один")
    }

    func testSwatchShowsWindowBackgroundNotAccent() {
        // #9182 п. 11: «лимонад… ярко-оранжевый», «мятный темнее, чем в жизни» — образец берёт фон темы.
        let chips = Dictionary(uniqueKeysWithValues: catalogChips.map { ($0.id, $0) })
        XCTAssertEqual(chips["lemonade"]?.background.lowercased(), "#ffeb85")
        XCTAssertEqual(chips["mint"]?.background.lowercased(), "#e9f8f1")
        XCTAssertEqual(chips["mint"]?.light, true)
        XCTAssertEqual(chips["ultra"]?.light, false)
    }

    // MARK: виджеты

    func testFiveHourAndFableAreSeparateWidgetsSideBySide() {
        XCTAssertEqual(PanelWidget.limits.title, "5 часов")
        XCTAssertEqual(PanelWidget.fable.title, "Fable")
        let rows = PanelWidgetLayout.standard.rows(visible: Set(PanelWidget.allCases.map { $0.rawValue }))
        XCTAssertTrue(rows.contains { $0.map { $0.id } == ["limits", "fable"] }, "по умолчанию — два рядом")
    }

    func testOldLayoutWithWideLimitsSplitsIntoPair() {
        // До WF174 широкий «5 часов и Fable» держал обе плитки в ряд.
        let layout = PanelWidgetLayout(items: [.init(id: "colors"), .init(id: "limits", wide: true), .init(id: "week")])
        XCTAssertEqual(Array(layout.items.map { $0.id }.prefix(4)), ["workflow", "colors", "limits", "fable"])
        XCTAssertEqual(layout.item("limits")?.wide, false)
        XCTAssertEqual(layout.item("fable")?.wide, false)
    }

    func testHideAndRestoreWidget() {
        let store = defaults()
        var layout = PanelWidgetLayout.standard
        layout.setHidden("fable", true)
        XCTAssertFalse(layout.isStandard)
        let visible = Set(PanelWidget.allCases.map { $0.rawValue })
        XCTAssertFalse(layout.rows(visible: visible).flatMap { $0 }.contains { $0.id == "fable" }, "скрытый — не в рядах")
        XCTAssertEqual(layout.hidden(visible: visible).map { $0.id }, ["fable"])
        XCTAssertEqual(layout.hidden(visible: visible.subtracting(["fable"])).map { $0.id }, [], "нет данных — нет и строки")
        layout.save(store)
        XCTAssertTrue(store.string(forKey: PanelWidgetLayout.key)?.contains(#""hidden":true"#) == true)
        XCTAssertEqual(PanelWidgetLayout.load(store), layout, "переживает перезапуск")
        layout.setHidden("fable", false)
        XCTAssertEqual(layout, .standard, "вернул — снова как было")
        // Старая запись без поля — не скрыт.
        store.set(#"[{"id":"week","wide":false}]"#, forKey: PanelWidgetLayout.key)
        XCTAssertEqual(PanelWidgetLayout.load(store).item("week")?.hidden, false)
        XCTAssertEqual(PanelWidgetLayout.load(store).item("week")?.wide, false)
    }

    // Значок у часов: выключатели WF174 заменены вариантами WF180 (`PanelWF180Tests`).
}
