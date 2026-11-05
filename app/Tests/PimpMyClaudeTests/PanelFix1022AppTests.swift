import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// Панель у часов, слова Элвиса 22.10.2026: счёт терминала часами, «Открыт NightWolf» — только правдой, «Оформление»
/// с цветами и отсчётом сразу. Кадры для глаз — `testSnapshot1022`, пишутся при `PMP_SNAPSHOT_DIR`.
final class PanelFix1022AppTests: XCTestCase {
    // MARK: счёт терминала

    func testTimerClock() {
        XCTAssertEqual(TerminalsText.clock(0), "0:00")
        XCTAssertEqual(TerminalsText.clock(7), "0:07")
        XCTAssertEqual(TerminalsText.clock(236), "3:56", "минуты без нуля впереди, секунды двумя цифрами")
        XCTAssertEqual(TerminalsText.clock(236.9), "3:56", "доли секунды не округляют вперёд")
        XCTAssertEqual(TerminalsText.clock(59 * 60 + 59), "59:59")
        XCTAssertEqual(TerminalsText.clock(3600), "1:00:00")
        XCTAssertEqual(TerminalsText.clock(3600 + 3 * 60 + 56), "1:03:56")
        XCTAssertEqual(TerminalsText.clock(-5), "0:00")
    }

    func testTimerCountsUpEverySecond() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let terminal = PanelTerminal(session: "VkusSES", title: "🧼 VkusSES", turning: false,
                                     coolsAt: now.addingTimeInterval(PanelTerminals.cacheSeconds - 236))
        XCTAssertEqual(TerminalsText.timer(terminal, now: now), "3:56")
        XCTAssertEqual(TerminalsText.timer(terminal, now: now.addingTimeInterval(1)), "3:57", "тик вперёд, а не назад")
        XCTAssertNil(TerminalsText.timer(PanelTerminal(session: "x", title: "x", turning: false), now: now))
        // Свёрнутая строка — смысл прежний: сколько тёплых.
        XCTAssertEqual(TerminalsText.collapsed([terminal], now: now), "1 · тёплых 1")
    }

    // MARK: NightWolf

    func testRivalOnlyWhenReallyRunning() {
        XCTAssertNil(NightLightRival.running([]), "никто не запущен — надписи «Открыт NightWolf» нет")
        XCTAssertNil(NightLightRival.running([nil, "com.apple.finder", "com.elvis.pimpmyclaude"]))
        XCTAssertEqual(NightLightRival.running(["com.apple.finder", "local.nightwolf.app"])?.name, "NightWolf")
        XCTAssertEqual(NightLightRival.running(["com.jessedacri.MidKey"])?.name, "Midnight Keyboard")
        let wolf = NightLightRival.apps[0]
        XCTAssertEqual(NightLightRival.note(wolf), "Открыт NightWolf — подсветкой правит он")
    }

    /// Под XCTest движок подсветки не встаёт: прогон тестов не держит замок клавиатуры живого Пимпа (из-за него в
    /// живой панели и висела ложная «Открыт NightWolf»).
    func testTestsDoNotTakeKeyboardLock() {
        XCTAssertTrue(NightLight.underTests)
        NightLight.shared.attach()
        XCTAssertNil(NightLight.shared.session)
        XCTAssertNil(NightLight.shared.note)
    }

    // MARK: «Оформление»

    func testCollapsedRowTapExpandsButNotAfterDrag() {
        let model = PanelModel()
        model.layout = .standard
        let id = PanelWidget.colors.rawValue
        let now = Date()
        model.widgetDragEnded = now
        model.tapCollapsed(id, now: now.addingTimeInterval(0.1))
        XCTAssertEqual(model.layout.item(id)?.collapsed, true, "отпустили мышь после переноса — не нажатие")
        model.layout = .standard
        model.widgetDragEnded = .distantPast
        model.tapCollapsed(id, now: now)
        XCTAssertEqual(model.layout.item(id)?.collapsed, false)
        PanelWidgetLayout.standard.save() // нажатие сохранило раскладку — тестовые настройки как были
    }

    func testColorsExpandedTakesWholeRow() {
        let model = PanelModel()
        model.layout = .standard
        XCTAssertFalse(model.expandedWidgets.contains(PanelWidget.colors.rawValue), "строкой — половинкой рядом с «Токенами»")
        model.layout.setCollapsed(PanelWidget.colors.rawValue, false)
        XCTAssertTrue(model.expandedWidgets.contains(PanelWidget.colors.rawValue))
        let visible: Set<String> = [PanelWidget.tokens.rawValue, PanelWidget.colors.rawValue]
        XCTAssertEqual(model.layout.rows(visible: visible, expanded: model.expandedWidgets).map { $0.map(\.id) },
                       [["tokens"], ["colors"]])
    }

    // MARK: волна 2 (файл 53)

    func testPanelClickOpensStaleAndIgnoresQueued() {
        XCTAssertEqual(PanelClick.action(isOpen: false, shown: false, pressedAt: 10, openedAt: 5), .open)
        XCTAssertEqual(PanelClick.action(isOpen: true, shown: false, pressedAt: 10, openedAt: 5), .open,
                       "считалась открытой, а окна нет — первое же нажатие открывает")
        XCTAssertEqual(PanelClick.action(isOpen: true, shown: true, pressedAt: 4.9, openedAt: 5), .ignore,
                       "нажатие из очереди, пока панель открывалась, её не закрывает")
        XCTAssertEqual(PanelClick.action(isOpen: true, shown: true, pressedAt: 6, openedAt: 5), .close)
        XCTAssertEqual(PanelClick.action(isOpen: true, shown: true, pressedAt: nil, openedAt: 5), .close)
    }

    func testShiftUpDownAmongVisible() {
        var layout = PanelWidgetLayout.standard
        let visible: Set<String> = ["week", "reset", "limits", "temperature"]
        XCTAssertNil(layout.neighbor("week", by: -1, visible: visible), "первый — выше некуда")
        XCTAssertEqual(layout.neighbor("limits", by: 1, visible: visible), "temperature", "невидимые блоки пропускаются")
        XCTAssertTrue(layout.shift("limits", by: -1, visible: visible))
        XCTAssertEqual(layout.items.prefix(3).map { $0.id }, ["week", "limits", "reset"])
        XCTAssertFalse(layout.shift("temperature", by: 1, visible: visible), "последний — ниже некуда")
    }

    func testResetClock() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000) // пт 15 янв 2027 08:00 UTC
        let sunday = now.addingTimeInterval(2 * 86_400 - 1) // вс 07:59:59 — до минуты 08:00
        XCTAssertEqual(StatusIcon.resetClock(sunday, now: now, calendar: utc), "вс 08:00")
        XCTAssertNil(StatusIcon.resetClock(now.addingTimeInterval(-60), now: now, calendar: utc))
        XCTAssertNil(StatusIcon.resetClock(nil, now: now))
    }

    func testEditModeAndFold() {
        let model = PanelModel()
        model.reduceMotion = true
        model.layout = .standard
        model.setEditingWidgets(true)
        XCTAssertTrue(model.editingWidgets)
        XCTAssertTrue(model.escapeEditing(), "Esc — выйти из правки")
        XCTAssertFalse(model.editingWidgets)
        XCTAssertFalse(model.escapeEditing(), "не в правке — Esc дальше")
        model.editingWidgets = true
        model.foldSections()
        XCTAssertFalse(model.editingWidgets, "панель открылась — не в правке")
        model.layout.setCollapsed(PanelWidget.gpu.rawValue, false)
        XCTAssertTrue(model.opened(.gpu))
        XCTAssertFalse(model.opened(.cpu), "каждый блок раскрывается сам")
        XCTAssertTrue(model.expandedWidgets.contains("gpu"), "развёрнутый график — своим рядом")
        PanelWidgetLayout.standard.save()
    }

    func testCollapsedColorsShowTheme() {
        let model = PanelModel()
        model.allThemes = chips()
        model.windowColor = .theme("violet")
        XCTAssertEqual(model.collapsedValue(.colors), "Фиолетовая")
        XCTAssertEqual(model.colorsSwatch?.id, "violet")
        model.windowColor = .plain
        XCTAssertEqual(model.collapsedValue(.colors), PanelColorTiles.plainName)
        XCTAssertNil(model.colorsSwatch)
    }

    // MARK: кадры

    private func chips() -> [WindowColorChip] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("claude-patch")
        let themes = ThemeCatalog.load(directory: root)
        return ClaudeAXController.panelThemeIDs.compactMap { id in themes.first { $0.id == id } }.map(WindowColorChip.init)
    }

    /// Раскладка Элвиса из его настроек 22.10 01:20: температура во всю ширину развёрнута, «Оформление» развёрнуто.
    private func elvisLayout() -> PanelWidgetLayout {
        let text = #"[{"id":"week","wide":false},{"id":"reset","wide":false},{"id":"limits","collapsed":true,"wide":false},{"id":"fable","collapsed":true,"wide":false},{"id":"temperature","wide":true},{"id":"memory","collapsed":true,"wide":false},{"id":"cpu","collapsed":true,"wide":false},{"id":"gpu","collapsed":true,"wide":false},{"id":"tokens","collapsed":true,"wide":false},{"id":"colors","wide":false},{"id":"workflow","collapsed":true,"wide":true},{"id":"terminals","collapsed":true,"wide":true}]"#
        let items = (try? JSONDecoder().decode([PanelWidgetLayout.Item].self, from: Data(text.utf8))) ?? []
        return PanelWidgetLayout(items: items)
    }

    private func scene(now: Date) -> PanelModel {
        let model = PanelWF253Scenes.elvis(now: now)
        model.update = .none
        model.layout = elvisLayout()
        model.windowThemes = chips()
        model.allThemes = model.windowThemes
        model.windowColor = .theme("violet")
        // Как у Элвиса: одна точка до сна (22:24), полчаса крышка закрыта, дальше раз в минуту.
        let wake = now.addingTimeInterval(-149 * 60)
        model.temperature = [MacTemperatureSample(at: wake.addingTimeInterval(-1820), chipAverage: 38, chipMax: 40,
                                                  battery: 30, state: .nominal)]
            + (0..<150).map { index in
                let value = 40 + 4 * sin(Double(index) / 14) + Double(index) / 60
                return MacTemperatureSample(at: wake.addingTimeInterval(Double(index) * 60), chipAverage: value,
                                            chipMax: value + 3, battery: 30, state: index > 120 && index < 135 ? .fair : .nominal)
            }
        model.macLoad = (0..<150).map { MacLoadSample(at: wake.addingTimeInterval(Double($0) * 60), cpu: 24, gpu: 21) }
        model.terminals = [
            PanelTerminal(session: "Bambubek", title: "Bambubek", turning: false,
                          coolsAt: now.addingTimeInterval(-25 * 60)),
            PanelTerminal(session: "Elblog", title: "Elblog", turning: false,
                          coolsAt: now.addingTimeInterval(PanelTerminals.cacheSeconds - 236)),
            PanelTerminal(session: "PimpMyClaude", title: "⚪ PimpMyClaude", turning: true, coolsAt: now),
            PanelTerminal(session: "PowerPont", title: "PowerPont", turning: false,
                          coolsAt: now.addingTimeInterval(PanelTerminals.cacheSeconds - 3836)),
            PanelTerminal(session: "VkusSES", title: "🧼 VkusSES", turning: false,
                          coolsAt: now.addingTimeInterval(PanelTerminals.cacheSeconds - 3 * 60 - 7)),
        ]
        return model
    }

    func testSnapshot1022() throws {
        let now = Date()
        let type = PanelTypography.all.first { $0.number == "49.4" } ?? .standard
        // 1. Панель Элвиса: линия температуры сплошная, «Оформление» с цветами и отсчётом сразу.
        try PanelWF253Scenes.render(scene(now: now), type: type, name: "1022-1-oformlenie")
        // 2. Те же блоки, «Терминалы» развёрнуты: счёт с последней активности часами.
        let terminals = scene(now: now)
        terminals.layout.setCollapsed(PanelWidget.terminals.rawValue, false)
        terminals.layout.setCollapsed(PanelWidget.colors.rawValue, true)
        try PanelWF253Scenes.render(terminals, type: type, name: "1022-2-terminaly")
        // 3. Раскладка по умолчанию: «Оформление» строкой рядом с «Токенами».
        let standard = scene(now: now)
        standard.layout = .standard
        try PanelWF253Scenes.render(standard, type: type, name: "1022-3-standard")
        // 4. Раскрытый график температуры: сон — разрывом по оси часов, одинокой точки нет.
        let chart = scene(now: now)
        chart.temperatureOpen = true
        chart.layout.setCollapsed(PanelWidget.colors.rawValue, true)
        try PanelWF253Scenes.render(chart, type: type, name: "1022-4-temperatura-otkryta")
        // 5. Волна 2: все блоки с графиком и лимиты развёрнуты — каждый своим рядом, как температура.
        let all = scene(now: now)
        all.layout = .unfolded
        all.layout.setCollapsed(PanelWidget.colors.rawValue, true)
        all.layout.setCollapsed(PanelWidget.terminals.rawValue, true)
        try PanelWF253Scenes.render(all, type: type, name: "1022-5-vse-raskryty")
        // 6. Свёрнуто по умолчанию: шевроны у названий, «Оформление» — кружок цвета и «Фиолетовая», внизу «Изменить виджеты».
        let folded = scene(now: now)
        folded.layout = .standard
        folded.layout.setHidden(PanelWidget.fable.rawValue, true)
        try PanelWF253Scenes.render(folded, type: type, name: "1022-6-svernuto")
        // 7. Правка: «−» и ширина на углах, «Готово» в шапке и внизу, «Скрытые: + Fable».
        let edit = scene(now: now)
        edit.layout = .standard
        edit.layout.setHidden(PanelWidget.fable.rawValue, true)
        edit.editingWidgets = true
        try PanelWF253Scenes.render(edit, type: type, name: "1022-7-pravka")
    }
}
