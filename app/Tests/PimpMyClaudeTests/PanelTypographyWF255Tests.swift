import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF255 (слово Элвиса 17.10.2026 06:00 по листу 47: «Два.4, журнальный… его берём… ещё 2.3… возможность выбора
/// сделай… варианты только посмелее»): по умолчанию 2.4, выбор в «Настройках» помнится и меняет панель сразу,
/// смелые наборы листа 49 не вылезают из плиток. Строки блоков без «…» для всех наборов проверяет WF253.
final class PanelTypographyWF255Tests: XCTestCase {
    private static let half: CGFloat = (PimpPanelController.width - 24 - 8) / 2 - 24

    private func suite() -> UserDefaults {
        let name = testSuiteName()
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDefaultIs24ThenListOrder() {
        XCTAssertEqual(PanelTypography.standard, PanelTypography.giant, "по умолчанию с 03.11.2026 — 49.4 «Тонкий гигант»")
        let numbers = PanelTypography.all.map { $0.number }
        // WF267: выбранные Элвисом 49.2 и 49.4 — сразу за 2.4 и 2.3, остальные смелые — в конце.
        XCTAssertEqual(Array(numbers.prefix(4)), ["2.4", "2.3", "49.2", "49.4"], "2.4, 2.3, затем 49.2 и 49.4")
        let bold = numbers.filter { $0.hasPrefix("49.") }
        XCTAssertEqual(bold.sorted(), (1...bold.count).map { "49.\($0)" }, "номера смелых — номера листа 49")
        XCTAssertTrue(PanelTypography.all.allSatisfy { !$0.hint.isEmpty }, "у каждого набора подсказка")
    }

    func testChoiceIsRemembered() {
        let defaults = suite()
        XCTAssertEqual(PanelTypography.saved(defaults), .giant, "не выбирали — 49.4")
        for type in PanelTypography.all {
            PanelTypography.save(type, defaults)
            XCTAssertEqual(PanelTypography.saved(defaults), type)
        }
        // Набора с таким номером больше нет (прежние 2.1, 2.2, 2.5, 2.6) — умолчание 49.4, а не пустая панель.
        defaults.set("2.1", forKey: PanelTypography.key)
        XCTAssertEqual(PanelTypography.saved(defaults), .giant)
        defaults.set(5, forKey: PanelTypography.key)
        XCTAssertEqual(PanelTypography.saved(defaults), .giant)
    }

    /// Нажатие в «Настройках» — модель и UserDefaults сразу; тот же набор второй раз ничего не пишет.
    func testChooseUpdatesModelAndDefaults() {
        let defaults = suite()
        let model = PanelModel()
        model.reduceMotion = true
        model.chooseTypography(.italic, defaults: defaults)
        XCTAssertEqual(model.typography, .italic)
        XCTAssertEqual(defaults.string(forKey: PanelTypography.key), "49.2")
        defaults.removeObject(forKey: PanelTypography.key)
        model.chooseTypography(.italic, defaults: defaults)
        XCTAssertNil(defaults.string(forKey: PanelTypography.key), "тот же набор — без записи")
    }

    /// Смена без перезапуска: та же открытая панель с крупным набором выше — шрифт дошёл до плиток через `PanelRoot`.
    func testPanelSwitchesLive() {
        let model = PanelWF253Scenes.elvis(now: Date())
        model.typography = .newYork
        let view = NSHostingView(rootView: PanelRoot(model: model))
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: 1400)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        func settle() {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            view.layoutSubtreeIfNeeded()
        }
        settle()
        let before = model.cardHeight
        model.chooseTypography(.giant, defaults: suite())
        settle()
        XCTAssertGreaterThan(model.cardHeight, before + 10, "проценты 58 выше, чем 34")
    }

    /// Самые широкие проценты «100 %» героем каждого набора входят в половинку плитки — смелые кегли не вылезают.
    func testHeroFitsHalfTile() {
        for type in PanelTypography.all {
            let hero = NSHostingView(rootView: HStack(alignment: .firstTextBaseline, spacing: 1) {
                type.hero.text("100").fixedSize()
                type.unit.text("%").fixedSize()
            }.fixedSize())
            XCTAssertLessThanOrEqual(hero.fittingSize.width, Self.half, "\(type.number) \(type.name)")
        }
    }

    /// Имя набора в списке «Шрифт панели» встаёт его же подписью — запасной вид (обычный текст) не нужен никому.
    func testPickerNamesFitInOwnStyle() {
        // Строка: поля группы 10 + 10, образец 64, зазоры 10 + 6, галка 11.
        let room = PimpPanelController.width - 24 - 20 - 64 - 10 - 6 - 11
        for type in PanelTypography.all {
            let name = NSHostingView(rootView: type.label.text(type.name).fixedSize())
            XCTAssertLessThanOrEqual(name.fittingSize.width, room, "\(type.number) \(type.name)")
        }
    }

    // MARK: кадры листа 49

    func testSnapshotWF255() throws {
        let now = Date()
        for type in PanelTypography.all {
            try PanelWF253Scenes.render(PanelWF253Scenes.elvis(now: now), type: type, name: "\(type.number)-1-elvis-dark")
        }
        for type in PanelTypography.all.dropFirst(2) {
            try PanelWF253Scenes.render(PanelWF253Scenes.evil(now: now), type: type, name: "\(type.number)-3-zloy")
        }
        // «Настройки» → «Шрифт панели» открыта: стоит 2.4.
        let settings = PanelWF253Scenes.elvis(now: now)
        settings.sheet = .settings
        settings.settingsGroup = .font
        try PanelWF253Scenes.render(settings, type: .newYork, name: "0-settings-font")
        // ★ листа 49 на светлом столе и злой набор во всю ширину со сбросом через 6 дней.
        let star = PanelTypography.italic
        try PanelWF253Scenes.render(PanelWF253Scenes.elvis(now: now), type: star, name: "\(star.number)-2-elvis-light",
                                    light: true)
        let wide = PanelWF253Scenes.evil(now: now, weekReset: 6 * 86400 + 23 * 3600 + 59 * 60)
        wide.layout = PanelWidgetLayout(items: PanelWidgetLayout.unfolded.items.map {
            PanelWidgetLayout.Item(id: $0.id, wide: true)
        })
        try PanelWF253Scenes.render(wide, type: star, name: "\(star.number)-5-zloy-wide")
    }
}
