import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF267 (#10095, слово Элвиса 17.10.2026 11:21 по листу 49: «этот 492… берём, только скачалось обновление, должно
/// писаться капсом, вот как Неделя… таким же цветом… этим же шрифтом везде во всех темах… 49.4… возьми его тоже…
/// где температура и память… чтобы они побольше были»; 11:24: «память с точкой»): 49.2 и 49.4 — сразу за 2.4 и 2.3,
/// заголовки карточек — подписью набора, температура и память — крупным показанием, память — с точкой.
final class PanelTypographyWF267Tests: XCTestCase {
    private static let half: CGFloat = (PimpPanelController.width - 24 - 8) / 2 - 24
    private static let wide: CGFloat = PimpPanelController.width - 24 - 24

    private func suite() -> UserDefaults {
        let name = testSuiteName()
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func width(_ text: Text) -> CGFloat { NSHostingView(rootView: text.fixedSize()).fittingSize.width }

    func testOrderAndSavedChoiceSurvive() {
        XCTAssertEqual(PanelTypography.all.map { $0.number }, ["2.4", "2.3", "49.2", "49.4", "49.1", "49.3", "49.5"])
        XCTAssertEqual(PanelTypography.standard, .giant, "по умолчанию с 03.11.2026 — 49.4")
        // Выбор, сохранённый до перестановки, — тот же набор по прежнему ключу: номер, а не место в списке.
        let defaults = suite()
        for (number, type) in [("49.2", PanelTypography.italic), ("49.4", .giant), ("49.1", .cover), ("49.5", .letterpress)] {
            defaults.set(number, forKey: "panelTypography")
            XCTAssertEqual(PanelTypography.saved(defaults), type, number)
        }
    }

    /// 49.2 — подписи тёплой капителью вразрядку, тем же цветом, что «%»; 49.4 — плотными заглавными. Заголовок
    /// карточки обновления своего стиля больше не имеет: «Скачалось обновление» пишется подписью, как «Неделя».
    func testLabelsCapsIn492And494() {
        let italic = PanelTypography.italic.label
        XCTAssertEqual(italic.letters, .smallCaps)
        XCTAssertEqual(italic.color, PanelTypography.warm)
        XCTAssertEqual(italic.color, PanelTypography.italic.unit.color, "подписи и «%» одним тёплым цветом")
        XCTAssertGreaterThanOrEqual(italic.tracking, 2)
        let giant = PanelTypography.giant.label
        XCTAssertEqual(giant.letters, .upper)
        XCTAssertEqual(giant.weight, Font.Weight.semibold)
        // Капс — по-настоящему заглавными: строка 49.4 шире той же строки без капса.
        let title = "Скачалось обновление"
        var plain = giant
        plain.letters = .asIs
        XCTAssertGreaterThan(width(giant.text(title)), width(plain.text(title)) + 10)
        // Во всех наборах подпись помещает самый длинный заголовок карточки в две строки карточки, не больше.
        let card = PimpPanelController.width - 24 - 24
        for type in PanelTypography.all {
            XCTAssertLessThanOrEqual(width(type.label.text(title)), card, "\(type.number): «\(title)» одной строкой")
            XCTAssertLessThanOrEqual(width(type.label.text("PMP пока не патчит Claude 2.142304.10")), 2 * card,
                                     type.number)
        }
    }

    /// Показание крупнее вторичного значения и мельче героя, в лице героя набора.
    func testReadingIsBiggerThanValues() {
        for type in PanelTypography.all {
            XCTAssertGreaterThan(type.reading.size, type.value.size + 6, type.number)
            XCTAssertLessThan(type.reading.size, type.hero.size, type.number)
            XCTAssertEqual(type.reading.face, type.hero.face, type.number)
            XCTAssertEqual(type.reading.italic, type.hero.italic, type.number)
        }
    }

    /// «105°» и «127.9 ГБ» показанием: в половинке — под подписью со стрелкой, во всю ширину — строкой рядом
    /// с «Нагрузкой на память»; без ужатия и «…» на всей панели (данные Элвиса и злые, половинки и во всю ширину).
    func testReadingsFitWithoutCut() {
        let mark: CGFloat = 8 + width(Text(Image(systemName: "chevron.right")).font(.system(size: 10, weight: .semibold)))
        for type in PanelTypography.all {
            for (label, value) in [("Память", "127.9 ГБ"), ("Температура", "105°")] {
                let stacked = max(width(type.label.text(label)), width(type.reading.text(value))) + mark
                XCTAssertLessThanOrEqual(stacked, Self.half, "\(type.number): \(label) \(value) в половинке")
            }
            let row = width(type.label.text("Нагрузка на память")) + 16 + width(type.reading.text("127.9 ГБ")) + mark
            XCTAssertLessThanOrEqual(row, Self.wide, "\(type.number): строкой во всю ширину")
            let now = Date()
            let evil = PanelWF253Scenes.forms(PanelWF253Scenes.evil(now: now), type: type)
            for id in [PanelWidget.temperature.rawValue, PanelWidget.memory.rawValue] {
                XCTAssertNotNil(evil[id], "\(type.number): \(id)")
                XCTAssertNotEqual(evil[id], .squeezed, "\(type.number): \(id)")
            }
            let wide = PanelWF253Scenes.evil(now: now)
            wide.layout = PanelWidgetLayout(items: PanelWidgetLayout.unfolded.items.map {
                PanelWidgetLayout.Item(id: $0.id, wide: true)
            })
            let forms = PanelWF253Scenes.forms(wide, type: type)
            for id in [PanelWidget.temperature.rawValue, PanelWidget.memory.rawValue] {
                let form = forms[id]
                XCTAssertTrue(form == .row || form == .bare, "\(type.number): \(id) — \(String(describing: form))")
            }
        }
    }

    /// Память — с точкой везде: строка плитки, подсказка, подпись под графиком, своп, ось.
    func testMemoryUsesDot() {
        let gb = PanelWF253Scenes.gb
        let history = PanelWF253Scenes.memory(now: Date(), usedGB: 127.9, totalGB: 128)
        XCTAssertEqual(MacMemory.nowText(history), "127.9 ГБ")
        XCTAssertEqual(MacMemory.gigabytes(UInt64(20.8 * Double(gb))), "20.8")
        XCTAssertEqual(MacMemory.gigabytes(8 * gb), "8", "целое — без «.0»")
        let sample = MacMemorySample(at: Date(), pressure: 50, level: .normal, used: UInt64(6.3 * Double(gb)),
                                     total: 8 * gb, swap: UInt64(1.2 * Double(gb)))
        XCTAssertEqual(MacMemory.help([sample]), "Память: занято 6.3 из 8 ГБ — 79 % · в норме · в свопе 1.2 ГБ")
        XCTAssertEqual(MacMemory.swapText(sample), "в свопе 1.2 ГБ")
        let texts = [MacMemory.nowText(history), MacMemory.help(history), MacMemory.caption(history)]
            + MacMemory.axis(total: 24 * gb + gb / 2).map { $0.label }
        for text in texts { XCTAssertFalse(text.range(of: #"\d,\d"#, options: .regularExpression) != nil, text) }
    }

    // MARK: кадры листа 50

    func testSnapshotWF267() throws {
        let now = Date()
        for type in [PanelTypography.newYork, .italic, .giant] {
            try PanelWF253Scenes.render(PanelWF253Scenes.elvis(now: now), type: type, name: "\(type.number)-1-elvis-dark")
            try PanelWF253Scenes.render(PanelWF253Scenes.evil(now: now), type: type, name: "\(type.number)-3-zloy")
        }
        let star = PanelTypography.italic
        try PanelWF253Scenes.render(PanelWF253Scenes.elvis(now: now), type: star, name: "\(star.number)-2-elvis-light",
                                    light: true)
        let wide = PanelWF253Scenes.evil(now: now)
        wide.layout = PanelWidgetLayout(items: PanelWidgetLayout.unfolded.items.map {
            PanelWidgetLayout.Item(id: $0.id, wide: true)
        })
        try PanelWF253Scenes.render(wide, type: star, name: "\(star.number)-5-zloy-wide")
        // Температура раскрыта: заголовок советов — тоже подписью.
        for type in [star, PanelTypography.giant] {
            let open = PanelWF253Scenes.elvis(now: now)
            open.temperatureOpen = true
            try PanelWF253Scenes.render(open, type: type, name: "\(type.number)-6-temperature-open")
        }
    }
}
