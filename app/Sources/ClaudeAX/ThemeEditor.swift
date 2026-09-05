import AppKit
import ApplicationServices

/// Панель «Своя тема» (решение 1.3 плана WF20): три ползунка, тумблер «Тёмная/Светлая»
/// и две кнопки. Логики здесь нет вовсе — она в `ThemeEditorModel`; это проводка AppKit:
/// окно, позиция, сторож окна и `endPreview` на всех выходах.
///
/// Поля имени в панели НЕТ (критик В1): приложение — `LSUIElement`, панель `.nonactivatingPanel`,
/// и набранные буквы уехали бы в Claude. Имя спрашивает готовый `MinimizeMenu.askThemeName`.
final class ThemeEditor: NSObject, NSWindowDelegate {
    /// Панель одна на приложение, и ссылка СИЛЬНАЯ (критик В2): слабая освободила бы контроллер
    /// сразу после выхода из обработчика пункта меню.
    static var current: ThemeEditor?

    static let panelSize = NSSize(width: 300, height: 262)
    /// Отступ панели от окна Claude.
    static let gap: CGFloat = 12
    /// Сторож окна: раз в секунду смотрим, живо ли оно и как теперь называется — заголовок
    /// меняется вместе с чатом, а им адресуется примерка.
    static let watchSeconds: TimeInterval = 1

    private let window: AXUIElement
    private let actions: ClaudeActions
    private let app: ClaudeApp
    private let model: ThemeEditorModel

    private var panel: NSPanel?
    private var watchdog: Timer?
    private var finished = false

    private let mode = NSSegmentedControl(labels: [MenuModel.themeEditorDarkTitle,
                                                   MenuModel.themeEditorLightTitle],
                                          trackingMode: .selectOne, target: nil, action: nil)
    private let hue = NSSlider()
    private let accent = NSSlider()
    private let strength = NSSlider()
    private let hueValue = NSTextField(labelWithString: "")
    private let accentValue = NSTextField(labelWithString: "")
    private let strengthValue = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")

    /// Открыть панель на этом окне. Была открыта другая — она закрывается со своим
    /// `endPreview`, примерка в приложении ровно одна.
    @discardableResult
    static func open(window: AXUIElement, knobs: ThemeKnobs, editing: MyTheme?,
                     actions: ClaudeActions, app: ClaudeApp) -> ThemeEditor {
        current?.close()
        let editor = ThemeEditor(window: window, knobs: knobs, editing: editing,
                                 actions: actions, app: app)
        current = editor
        editor.show()
        return editor
    }

    private init(window: AXUIElement, knobs: ThemeKnobs, editing: MyTheme?,
                 actions: ClaudeActions, app: ClaudeApp) {
        self.window = window
        self.actions = actions
        self.app = app
        self.model = ThemeEditorModel(knobs: knobs, editing: editing)
        super.init()
        model.onPreview = { [weak self] knobs in
            guard let self = self else { return }
            // Заголовок окна `sendPreview` перечитывает сам — у главного окна он меняется
            // вместе с чатом (открытый риск плана).
            _ = self.actions.previewTheme(knobs.theme(), window: self.window)
        }
        model.onEndPreview = { [weak self] in
            guard let self = self else { return }
            _ = self.actions.endPreview(window: self.window)
        }
    }

    // MARK: - положение (чистая часть)

    /// Куда встать панели: слева от окна Claude, а слева места нет — справа; не влезло нигде —
    /// прижимаемся к краю рабочей области. Координаты перевёрнутые (Quartz), точка — ЛЕВЫЙ
    /// ВЕРХНИЙ угол, как у `MinimizeMenu.origin`.
    static func origin(window frame: CGRect, size: NSSize, area: CGRect?) -> CGPoint {
        var x = frame.minX - gap - size.width
        var y = frame.minY
        guard let area = area else { return CGPoint(x: x, y: y) }
        if x < area.minX {
            let right = frame.maxX + gap
            x = right + size.width <= area.maxX ? right : area.minX
        }
        y = min(max(y, area.minY), max(area.minY, area.maxY - size.height))
        return CGPoint(x: x, y: y)
    }

    // MARK: - показ

    private func show() {
        let panel = makePanel()
        self.panel = panel
        let frame = AX.frame(window) ?? Screens.mainUsableFrame ?? .zero
        let point = ThemeEditor.origin(window: frame, size: ThemeEditor.panelSize,
                                       area: Screens.mainUsableFrame)
        // `flip` даёт левый ВЕРХНИЙ угол в координатах AppKit, а окну нужен левый НИЖНИЙ.
        let top = Screens.flip(point: point)
        panel.setFrameOrigin(NSPoint(x: top.x, y: top.y - ThemeEditor.panelSize.height))

        MinimizeMenu.editorOpen = true
        ClaudeActions.themeEditorTitle = AX.string(window, kAXTitleAttribute)
        draw()
        panel.orderFrontRegardless()
        panel.makeKey()

        let timer = Timer(timeInterval: ThemeEditor.watchSeconds, repeats: true) { [weak self] _ in
            self?.watch()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    /// Окно ещё живо? Закрыли его при открытой панели — панель уходит следом, и примерка
    /// не залипает. Заодно освежаем заголовок: им адресуются и примерка, и молчание проекта.
    private func watch() {
        guard AX.value(window, kAXRoleAttribute) != nil else { return close() }
        ClaudeActions.themeEditorTitle = AX.string(window, kAXTitleAttribute)
        drawStatus()
    }

    // MARK: - выходы

    /// Единственный выход панели: гасит примерку, снимает сторожа и отпускает флаги.
    func close() {
        guard let panel = panel else { return finish() }
        panel.close() // → windowWillClose → finish()
    }

    func windowWillClose(_ notification: Notification) { finish() }

    private func finish() {
        guard !finished else { return }
        finished = true
        watchdog?.invalidate()
        watchdog = nil
        // Сперва конец примерки, потом отпускаем себя (критик В2): иначе окно осталось бы
        // в цвете ползунка и перестало перекрашиваться при смене чата.
        model.cancel()
        MinimizeMenu.editorOpen = false
        ClaudeActions.themeEditorTitle = nil
        panel?.delegate = nil
        panel = nil
        if ThemeEditor.current === self { ThemeEditor.current = nil }
        app.focus(window: window)
    }

    // MARK: - кнопки и ручки

    @objc private func knobMoved(_ sender: NSSlider) {
        let step = Int(sender.doubleValue.rounded())
        switch sender {
        case hue: model.set(hue: step)
        case accent: model.set(accent: step)
        default: model.set(strength: step)
        }
        draw()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        model.set(light: sender.selectedSegment == 1)
        draw()
    }

    @objc private func cancel() { close() }

    @objc private func save() {
        // Пока висит модальный диалог имени, сторож не должен закрыть панель под ним.
        let timer = watchdog
        watchdog = nil
        timer?.invalidate()
        let result = model.save(into: actions.myThemes, font: actions.lastAppliedFont,
                                size: actions.lastAppliedSize,
                                frame: actions.lastAppliedFrame == true,
                                ask: { MinimizeMenu.askThemeName(default: $0) },
                                confirm: { MinimizeMenu.confirmOverwrite(name: $0) })
        switch result {
        case .cancelled:
            // Передумали — панель остаётся рабочей, сторожа заводим заново.
            let again = Timer(timeInterval: ThemeEditor.watchSeconds, repeats: true) { [weak self] _ in
                self?.watch()
            }
            RunLoop.main.add(again, forMode: .common)
            watchdog = again
        case .failed:
            MinimizeMenu.warn(MenuModel.themeEditorWriteFailed)
            close()
        case .saved(let my):
            // Обычная команда: она же гасит примерку на странице и ставит галку в меню.
            // В окне проекта она молча станет и темой проекта (решение 3.2 плана WF20).
            actions.apply(myTheme: my, scope: MenuModel.themeScopeWindow, window: window)
            close()
        }
    }

    // MARK: - отрисовка

    private func draw() {
        let knobs = model.knobs
        hueValue.stringValue = "\(knobs.hue)°"
        accentValue.stringValue = (knobs.accent >= 0 ? "+" : "") + "\(knobs.accent)°"
        strengthValue.stringValue = "\(knobs.strength) %"
        mode.selectedSegment = knobs.light ? 1 : 0
        drawStatus()
    }

    /// Строка под ручками: сперва то, что мешает работать (нет заголовка — нет примерки),
    /// потом честное «ручки подобраны по цветам», а дальше — контрасты, как в макете.
    private func drawStatus() {
        let palette = model.knobs.palette()
        let text = AutoPaint.contrast(hex: palette["foreground"] ?? "",
                                      hex: palette["background"] ?? "") ?? 0
        let accent = AutoPaint.contrast(hex: palette["accent"] ?? "",
                                        hex: palette["background"] ?? "") ?? 0
        if (ClaudeActions.themeEditorTitle ?? "").isEmpty {
            status.stringValue = MenuModel.themeEditorNoTitleHint
        } else if model.knobsAreGuessed && model.previews.isEmpty {
            status.stringValue = MenuModel.themeEditorGuessedHint
        } else {
            status.stringValue = MenuModel.themeEditorContrast(text: text, accent: accent)
        }
    }

    // MARK: - сборка панели

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: ThemeEditor.panelSize),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.title = MenuModel.themeEditorPanel
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // По умолчанию `true` — крестик дал бы обращение к освобождённой памяти (критик В2).
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let box = NSView(frame: NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size))
        box.autoresizingMask = [.width, .height]
        let width = box.frame.width
        let pad: CGFloat = 16
        var y = box.frame.height - pad - 24

        mode.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 24)
        mode.segmentDistribution = .fillEqually
        mode.target = self
        mode.action = #selector(modeChanged(_:))
        box.addSubview(mode)
        y -= 16

        for (slider, title, value) in [(hue, MenuModel.themeEditorHueTitle, hueValue),
                                       (accent, MenuModel.themeEditorAccentTitle, accentValue),
                                       (strength, MenuModel.themeEditorStrengthTitle, strengthValue)] {
            y -= 18
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.frame = NSRect(x: pad, y: y, width: width - pad * 2 - 70, height: 16)
            box.addSubview(label)

            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            value.textColor = .secondaryLabelColor
            value.alignment = .right
            value.frame = NSRect(x: width - pad - 70, y: y, width: 70, height: 16)
            box.addSubview(value)

            y -= 22
            slider.isContinuous = true
            slider.controlSize = .small
            slider.target = self
            slider.action = #selector(knobMoved(_:))
            slider.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 18)
            box.addSubview(slider)
        }
        hue.minValue = 0
        hue.maxValue = 359
        hue.doubleValue = Double(model.knobs.hue)
        accent.minValue = Double(ThemeKnobs.accentRange.lowerBound)
        accent.maxValue = Double(ThemeKnobs.accentRange.upperBound)
        accent.doubleValue = Double(model.knobs.accent)
        strength.minValue = Double(ThemeKnobs.strengthRange.lowerBound)
        strength.maxValue = Double(ThemeKnobs.strengthRange.upperBound)
        strength.doubleValue = Double(model.knobs.strength)

        y -= 24
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 15)
        box.addSubview(status)

        y -= 38
        let save = NSButton(title: MenuModel.themeEditorSaveButton, target: self,
                            action: #selector(self.save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: width - pad - 110, y: y, width: 110, height: 30)
        box.addSubview(save)

        let cancel = NSButton(title: MenuModel.themeEditorCancelButton, target: self,
                              action: #selector(self.cancel))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: width - pad - 110 - 8 - 90, y: y, width: 90, height: 30)
        box.addSubview(cancel)

        panel.contentView = box
        return panel
    }
}
