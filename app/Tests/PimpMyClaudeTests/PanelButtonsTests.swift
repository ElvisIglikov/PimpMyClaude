import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// Сторожа панели у часов (#10527, план 3.5; слово Элвиса 22.10.2026: «То кнопка какая-нибудь отвалится»).
///
/// Проводка: каждое действие `PanelActions` после `wirePanel()` подключено — пустая заглушка зовёт
/// `PanelActions.unwired`, и тест это видит. Нажатия через дерево доступности под XCTest недоступны (разведка
/// 22.10.2026: `NSHostingView` в процессе тестов отдаёт пустой `accessibilityChildren()`, а AX-запрос к своему pid
/// без запущенного `NSApplication` не отвечает), поэтому кнопки проверяются моделью: каждый блок раскрывается и
/// не пуст.
final class PanelButtonsTests: XCTestCase {
    // MARK: проводка

    /// Все действия панели по имени поля `PanelActions` — вызов с безобидным значением. Новое поле без строки
    /// здесь — красный `testEveryActionHasPressInTable`.
    private static let presses: [(name: String, press: (PanelActions) -> Void)] = [
        ("patch", { $0.patch() }),
        ("findClaude", { $0.findClaude() }),
        ("patchLog", { $0.patchLog() }),
        ("download", { $0.download() }),
        ("update", { $0.update() }),
        ("updateAnyway", { $0.updateAnyway() }),
        ("wait", { $0.wait() }),
        ("updateNow", { $0.updateNow() }),
        ("nextLaunch", { $0.nextLaunch() }),
        ("cancelNextLaunch", { $0.cancelNextLaunch() }),
        ("cancelRace", { $0.cancelRace() }),
        ("retryUpdate", { $0.retryUpdate() }),
        ("toggle", { $0.toggle("test-10527") }),
        ("sendDelay", { $0.sendDelay(true, 3) }),
        ("previewSendDelay", { $0.previewSendDelay(3) }),
        ("pinnedLook", { $0.pinnedLook(PinnedLook()) }),
        ("archiveChats", { $0.archiveChats() }),
        ("showViewer", { $0.showViewer() }),
        ("installRick", { $0.installRick() }),
        ("installKontekst", { $0.installKontekst() }),
        ("revealRick", { $0.revealRick() }),
        ("selfUpdate", { $0.selfUpdate(true) }),
        ("setup", { $0.setup() }),
        ("donate", { $0.donate() }),
        ("about", { $0.about() }),
        ("uninstall", { $0.uninstall() }),
        ("quit", { $0.quit() }),
        ("windowColor", { $0.windowColor(.byProject) }),
        ("previewWindowColor", { $0.previewWindowColor(nil) }),
        ("live", { $0.live(.still) }),
        ("scheme", { $0.scheme(LookScheme.defaultID) }),
        ("dense", { $0.dense(false) }),
        ("windowFont", { $0.windowFont(nil) }),
        ("textSize", { $0.textSize(nil) }),
        ("zoom", { $0.zoom(.actual) }),
        ("hideTools", { $0.hideTools(true) }),
        ("hideCode", { $0.hideCode(false) }),
        ("setAccent", { $0.setAccent(.violet) }),
        ("escape", { _ = $0.escape() }),
        ("enterKeys", { $0.enterKeys(EnterKeys()) }),
        ("countdownSound", { $0.countdownSound(.fallback) }),
        ("sendLookStyle", { $0.sendLookStyle(SendLook.defaultStyle) }),
        ("sendLookSize", { $0.sendLookSize(SendLook.defaultSize) }),
        ("memoryAnalysis", { $0.memoryAnalysis() }),
        ("editMemoryPrompt", { $0.editMemoryPrompt() }),
        ("bypassNew", { $0.bypassNew(false) }),
        ("textJustify", { $0.textJustify(true) }),
        ("sidePadding", { $0.sidePadding(24) }),
        ("cleanAnswers", { $0.cleanAnswers(true) }),
        ("openClaudeSettings", { $0.openClaudeSettings() }),
        ("iconVariant", { $0.iconVariant(.claude) }),
        ("accessWizard", { $0.accessWizard(.later) }),
        ("muteWait", { _ = $0.muteWait("test-10527", nil) }),
        // Ключа нет в `muted-waits.json` — снятие ничего не пишет.
        ("unmuteWait", { $0.unmuteWait("test-10527-none") }),
    ]

    /// Подключены, но делают своё и без `AppDelegate` — их не жмём (выход из тестов, Finder, запись файла
    /// «Не напоминать»): у них нет `[weak self]`, которым тест их глушит.
    private static let selfless: Set<String> = ["quit", "revealRick", "muteWait"]

    func testEveryActionHasPressInTable() {
        let fields = Mirror(reflecting: PanelActions()).children.compactMap { $0.label }
        XCTAssertFalse(fields.isEmpty)
        XCTAssertEqual(Set(fields), Set(Self.presses.map { $0.name }),
                       "новое действие панели — строку в таблицу нажатий")
        XCTAssertEqual(fields.count, Self.presses.count)
    }

    /// Заглушка по умолчанию — не тишина: каждая пишет своё имя в `unwiredLog`.
    func testDefaultStubsReportUnwired() {
        PanelActions.unwiredLog = []
        let blank = PanelActions()
        for entry in Self.presses { entry.press(blank) }
        XCTAssertEqual(PanelActions.unwiredLog, Self.presses.map { $0.name })
        PanelActions.unwiredLog = []
    }

    /// `wirePanel()` и мастер доступов подключают каждое действие. `AppDelegate` отпускается до нажатий: подключённое
    /// действие держит его `[weak self]` и молчит, а неподключённое пишет своё имя в `unwiredLog`.
    func testWirePanelLeavesNoActionUnwired() throws {
        _ = NSApplication.shared
        var actions = PanelActions()
        weak var gone: AppDelegate?
        autoreleasepool {
            let delegate = AppDelegate()
            delegate.wirePanel()
            delegate.wireAccessWizard()
            actions = delegate.panel.model.actions
            gone = delegate
        }
        XCTAssertNil(gone, "AppDelegate отпущен — нажатия ниже ничего не делают по-настоящему")
        guard gone == nil else { return }
        PanelActions.unwiredLog = []
        for entry in Self.presses where !Self.selfless.contains(entry.name) { entry.press(actions) }
        XCTAssertEqual(PanelActions.unwiredLog, [], "кнопки панели без проводки")
        PanelActions.unwiredLog = []
    }

    // MARK: блоки раскрываются и не пусты

    private func chips() -> [WindowColorChip] {
        let themes = ThemeCatalog.load(directory: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude-patch"))
        return ClaudeAXController.panelThemeIDs.compactMap { id in themes.first { $0.id == id } }.map(WindowColorChip.init)
    }

    /// Панель Элвиса со всеми данными: у каждого блока есть что показать.
    private func scene(now: Date) -> PanelModel {
        let model = PanelWF253Scenes.evil(now: now)
        model.update = .none
        model.windowThemes = chips()
        model.allThemes = model.windowThemes
        model.windowColor = .theme("violet")
        model.macLoad = (0..<120).map { MacLoadSample(at: now.addingTimeInterval(Double($0 - 119) * 60), cpu: 24, gpu: 21) }
        model.terminals = [
            PanelTerminal(session: "PimpMyClaude", title: "⚪ PimpMyClaude", turning: true, coolsAt: now),
            PanelTerminal(session: "VkusSES", title: "🧼 VkusSES", turning: false,
                          coolsAt: now.addingTimeInterval(PanelTerminals.cacheSeconds - 236)),
        ]
        return model
    }

    /// Высота карточки панели — та, что `PanelRoot` отдаёт окну (`cardHeight`).
    private func height(_ model: PanelModel) -> CGFloat {
        let view = NSHostingView(rootView: PanelRoot(model: model))
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: 1600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        view.layoutSubtreeIfNeeded()
        return model.cardHeight
    }

    private static let oneLine: Set<PanelWidget> = [.tokens, .workflow]

    /// Только блок `widget` на панели: свёрнут или развёрнут.
    private func only(_ widget: PanelWidget, collapsed: Bool, now: Date) -> PanelModel {
        let model = scene(now: now)
        var layout = PanelWidgetLayout.standard
        for other in PanelWidget.allCases where other != widget { layout.setHidden(other.rawValue, true) }
        layout.setHidden(widget.rawValue, false)
        layout.setCollapsed(widget.rawValue, collapsed)
        model.layout = layout
        return model
    }

    /// Каждый блок `PanelWidget.allCases` есть на панели строкой, раскрывается и раскрытым выше строки («кнопка
    /// отвалилась» — блок раскрылся пустым). «Оформление» раскрытым — с плитками цветов и отсчётом (П5, #10515).
    func testEveryWidgetExpandsAndIsNotEmpty() {
        _ = NSApplication.shared
        let now = Date()
        let none = scene(now: now)
        var empty = PanelWidgetLayout.standard
        for widget in PanelWidget.allCases { empty.setHidden(widget.rawValue, true) }
        none.layout = empty
        let bare = height(none)
        var grown: [String: CGFloat] = [:]
        for widget in PanelWidget.allCases {
            let folded = height(only(widget, collapsed: true, now: now))
            let opened = height(only(widget, collapsed: false, now: now))
            grown[widget.rawValue] = opened - folded
            XCTAssertGreaterThan(folded, bare + 10, "\(widget.title): блок есть на панели")
            // «Токены» и шапка Workflow — одной строкой и раскрытыми (график — окном, список — нажатием шапки).
            if Self.oneLine.contains(widget) {
                XCTAssertGreaterThanOrEqual(opened, folded - 1, "\(widget.title): раскрытый не пустой")
            } else {
                XCTAssertGreaterThan(opened, folded + 4, "\(widget.title): раскрытый выше свёрнутого")
            }
        }
        // «Оформление» (П5): плитки цветов — те, что есть в данных; без тем ряд плиток пропадает, отсчёт остаётся.
        let bareColors = only(.colors, collapsed: false, now: now)
        bareColors.windowThemes = []
        bareColors.allThemes = []
        let tilesShare = height(only(.colors, collapsed: false, now: now)) - height(bareColors)
        XCTAssertGreaterThanOrEqual(tilesShare, 2 * ColorsCard.swatchHeight, "«Оформление»: плитки цветов на месте")
        XCTAssertGreaterThanOrEqual((grown[PanelWidget.colors.rawValue] ?? 0) - tilesShare, 40,
                                    "«Оформление»: ряд отсчёта на месте")
        print("PanelButtonsTests colors tiles \(tilesShare)")
        // Шапка Workflow раскрывает список (`toggleWorkflow`).
        let header = only(.workflow, collapsed: false, now: now)
        let closed = height(header)
        header.toggleWorkflow()
        XCTAssertTrue(header.workflowOpen)
        XCTAssertGreaterThan(height(header), closed + 4, "Workflow: нажатие шапки раскрывает список")
        print("PanelButtonsTests grown \(grown.sorted { $0.key < $1.key })")
        PanelWidgetLayout.standard.save()
    }

    /// Нажатие по свёрнутой строке раскрывает блок (то же, что делает строка в `WidgetCell`), шапка «Свернуть всё» и
    /// «Изменить виджеты» / «Готово» меняют модель.
    func testWidgetTapsChangeModel() {
        let model = scene(now: Date())
        model.reduceMotion = true
        model.layout = .standard
        for widget in PanelWidget.allCases {
            model.setCollapsed(widget.rawValue, true)
            model.widgetDragEnded = .distantPast
            model.tapCollapsed(widget.rawValue)
            XCTAssertTrue(model.opened(widget), "\(widget.title): нажатие по строке раскрывает")
        }
        let visible = Set(PanelWidget.allCases.map { $0.rawValue })
        model.setAllCollapsed(true, visible: visible)
        // Скрытые блоки (с 03.11.2026 — Workflow) «Свернуть всё» не трогает.
        XCTAssertTrue(PanelWidget.allCases.filter { model.layout.item($0.rawValue)?.hidden != true }
            .allSatisfy { !model.opened($0) }, "«Свернуть всё»")
        model.setEditingWidgets(true)
        XCTAssertTrue(model.editingWidgets, "«Изменить виджеты»")
        model.setEditingWidgets(false)
        XCTAssertFalse(model.editingWidgets, "«Готово»")
        PanelWidgetLayout.standard.save()
    }
}
