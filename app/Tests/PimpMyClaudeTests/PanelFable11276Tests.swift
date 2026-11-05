@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// #11276 (слово Элвиса 30.10.2026: «у Фейбл тоже должен быть развёрнут так же, как 68 %»): сохранённая пара вразнобой
/// («5 часов» развёрнут, Fable строкой) выравнивается по рядам, что на экране (доска виджетов); развёрнутая Fable — с той же строкой сброса,
/// что у «5 часов». Кадр пары пишется, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelFable11276Tests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = testSuiteName()
        defaults = UserDefaults(suiteName: suite)
        defaults.set(true, forKey: PanelWidgetLayout.colorsLastKey)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func saved(_ change: (inout PanelWidgetLayout) -> Void) -> PanelWidgetLayout {
        var layout = PanelWidgetLayout.standard
        change(&layout)
        let data = try! JSONEncoder().encode(layout.items)
        defaults.set(String(decoding: data, as: UTF8.self), forKey: PanelWidgetLayout.key)
        return layout
    }

    private let all = Set(PanelWidget.allCases.map { $0.rawValue })

    private func aligned(visible: Set<String>) -> PanelWidgetLayout {
        var layout = PanelWidgetLayout.load(defaults)
        layout.alignRowFolds(visible: visible)
        return layout
    }

    func testLoadUnfoldsMixedPair() {
        _ = saved { $0.setCollapsed("limits", false) }   // как на снимке: «5 часов» развёрнут, Fable свёрнута
        XCTAssertEqual(PanelWidgetLayout.load(defaults).item("fable")?.collapsed, true, "чтение раскладку не меняет")
        let layout = aligned(visible: all)
        XCTAssertEqual(layout.item("limits")?.collapsed, false)
        XCTAssertEqual(layout.item("fable")?.collapsed, false, "Fable разворачивается вместе с «5 часов»")
        XCTAssertEqual(layout.item("temperature")?.collapsed, true, "свёрнутые целиком ряды не трогаем")
        XCTAssertEqual(layout.item("week")?.collapsed, false, "развёрнутые целиком — как были")
        XCTAssertEqual(layout.item("workflow")?.collapsed, true, "широкий одиночка — как был")
    }

    func testLoadAlignsEitherHalfAndKeepsHidden() {
        _ = saved {
            $0.setCollapsed("gpu", false)            // развёрнута правая половинка
            $0.setHidden("colors", true)             // «Оформление» скрыто — «Токены» одни, их не трогаем
        }
        let layout = aligned(visible: all)
        XCTAssertEqual(layout.item("cpu")?.collapsed, false, "«Процессор» разворачивается с «Видеокартой»")
        XCTAssertEqual(layout.item("tokens")?.collapsed, true)
        XCTAssertEqual(layout.item("colors")?.hidden, true)
    }

    func testLoadLeavesConsistentLayoutAsIs() {
        let folded = saved { $0.setAllCollapsed(true, visible: all) }
        XCTAssertEqual(aligned(visible: all), folded)
        defaults.removeObject(forKey: PanelWidgetLayout.key)
        XCTAssertEqual(PanelWidgetLayout.load(defaults), .standard)
    }

    /// Находка проверки: без Fable на экране «5 часов» стоит в паре с «Температурой», «Память» — с «Процессором»;
    /// выравнивание по всем блокам развернуло бы «Память» и оставило бы её пару вразнобой при каждом запуске.
    func testAlignsByRowsOnScreenWithoutFable() {
        _ = saved { $0.setCollapsed("limits", false) }
        let layout = aligned(visible: all.subtracting(["fable"]))
        XCTAssertEqual(layout.item("limits")?.collapsed, false)
        XCTAssertEqual(layout.item("temperature")?.collapsed, false, "сосед по ряду на экране — «Температура»")
        XCTAssertEqual(layout.item("memory")?.collapsed, true, "«Память» в другом ряду — не трогаем")
        XCTAssertEqual(layout.item("cpu")?.collapsed, true)
    }

    func testFableResetNote() {
        let now = Date(timeIntervalSinceReferenceDate: 815_000_000)
        let soon = now.addingTimeInterval(3 * 3600 + 31 * 60)
        let week = now.addingTimeInterval(5 * 3600)
        let full = ClaudeLimits(at: now, plan: nil, fiveHour: .init(used: 68, resetsAt: soon),
                                weekly: .init(used: 65, resetsAt: week), fable: .init(used: 22, resetsAt: soon),
                                source: "api")
        // Слово 03.11.2026: у Fable вместо срока — что он входит в недельный лимит; срок остаётся у «5 часов».
        XCTAssertEqual(LimitTile.resetNote(.fable, in: full, now: now), "Входит в лимит недели и уменьшает его")
        XCTAssertEqual(LimitTile.resetNote(.fiveHour, in: full, now: now), "сброс через 3 ч 31 мин")

        let noOwn = ClaudeLimits(at: now, plan: nil, fiveHour: nil, weekly: .init(used: 65, resetsAt: week),
                                 fable: .init(used: 22, resetsAt: nil), source: "api")
        XCTAssertNil(LimitTile.resetNote(.fiveHour, in: noOwn, now: now), "у «5 часов» срок недели не подставляется")
        XCTAssertEqual(LimitTile.resetNote(.fable, in: nil, now: now), LimitTile.fableNote, "строка не зависит от сроков")
    }

    /// Кадр: «Неделя · Сброс» и «5 часов · Fable» развёрнутыми, набор 49.4 (у Элвиса).
    func testSnapshot11276() throws {
        let model = PanelWF253Scenes.elvis(now: Date())
        var layout = PanelWidgetLayout.standard
        layout.setCollapsed("limits", false)
        layout.setCollapsed("fable", false)
        model.layout = layout
        try PanelWF253Scenes.render(model, type: .giant, name: "11276-limits-fable")
    }
}
