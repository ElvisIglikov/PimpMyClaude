import AppKit
import ApplicationServices

/// Меню на жёлтой кнопке «Свернуть» — порт `claude_minimize_menu.lua` (решение 7 плана).
/// Таймер 8 Гц читает `NSEvent.mouseLocation` и сравнивает с рамками окон Claude из
/// `CGWindowListCopyWindowInfo`; AX спрашиваем только про прямоугольник AXMinimizeButton,
/// и только когда курсор в верхней полосе окна. Никаких event tap.
final class MinimizeMenu: NSObject {
    var enabled = true
    /// Опрос курсора, 8 Гц.
    let interval: TimeInterval = 0.125
    /// Полоса от верха рамки, где может жить кнопка (кнопка на y+16..34; 30 обрезало низ).
    let topBand: CGFloat = 48
    /// Сколько курсор должен простоять на кнопке.
    let hoverSeconds: TimeInterval = 0.3
    /// Кэш геометрии кнопки (и промахов) на окно.
    let buttonCacheSeconds: TimeInterval = 0.5

    private let app: ClaudeApp
    private let actions: ClaudeActions
    private var timer: Timer?

    /// Кэш на окно: AX-элемент, прямоугольник кнопки и рамка, при которой их читали.
    /// Промахи кэшируются тоже — иначе AX опрашивался бы на каждом тике.
    private struct ButtonCache {
        let element: AXUIElement?
        let rect: CGRect?
        let frame: CGRect
        let at: TimeInterval
    }

    private var buttons: [CGWindowID: ButtonCache] = [:]
    private var hoverID: CGWindowID?
    private var hoverSince: TimeInterval = 0
    private var suppressed = false
    private var menuOpen = false
    private(set) var shows = 0
    /// Меню сейчас всплывёт — самое время перечитать сводки проектов (решение 2 плана WF9).
    var onWillShow: (() -> Void)?

    init(app: ClaudeApp, actions: ClaudeActions) {
        self.app = app
        self.actions = actions
        super.init()
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        clearCache()
        hoverID = nil
        hoverSince = 0
        suppressed = false
        menuOpen = false
    }

    var isRunning: Bool { timer != nil }

    /// Окна переехали или Claude перезапустился — прямоугольники кнопок протухли.
    func clearCache() { buttons = [:] }

    private func tick() {
        guard enabled, !menuOpen, AX.isTrustedCached, let pid = app.pid else { return }
        let point = Screens.flip(point: NSEvent.mouseLocation)

        var target: (window: AXUIElement, id: CGWindowID, rect: CGRect)?
        // Окна перекрываются: решает первое (самое переднее) под курсором.
        for window in ClaudeApp.onScreenFrames(pid: pid) {
            let f = window.frame
            guard point.x >= f.minX, point.x <= f.maxX,
                  point.y >= f.minY, point.y <= f.minY + topBand else { continue }
            if let hit = minimizeButton(of: window), hit.rect.contains(point) {
                target = (hit.element, window.id, hit.rect)
            }
            break
        }

        guard let hit = target else {
            hoverID = nil
            hoverSince = 0
            suppressed = false
            return
        }
        if hoverID != hit.id {
            hoverID = hit.id
            hoverSince = Date.timeIntervalSinceReferenceDate
            suppressed = false
            return
        }
        if suppressed { return } // меню уже показывали: ждём, пока курсор уйдёт с кнопки
        if Date.timeIntervalSinceReferenceDate - hoverSince >= hoverSeconds {
            suppressed = true // до блокирующего popUp, а не после
            show(for: hit.window, at: hit.rect)
        }
    }

    /// AX-окно и прямоугольник его AXMinimizeButton в экранных координатах.
    /// Кэш живёт buttonCacheSeconds и сбрасывается, как только окно переехало, — обращение
    /// к AX выходит не чаще двух раз в секунду и только для окна под курсором.
    private func minimizeButton(of window: ClaudeWindowFrame) -> (element: AXUIElement, rect: CGRect)? {
        let now = Date.timeIntervalSinceReferenceDate
        if let hit = buttons[window.id], now - hit.at < buttonCacheSeconds, hit.frame == window.frame {
            guard let element = hit.element, let rect = hit.rect else { return nil }
            return (element, rect)
        }
        let element = app.window(matching: window.frame)
        var rect: CGRect?
        if let element = element, let button = AX.element(element, kAXMinimizeButtonAttribute) {
            rect = AX.frame(button)
        }
        buttons[window.id] = ButtonCache(element: element, rect: rect, frame: window.frame, at: now)
        guard let element = element, let rect = rect else { return nil }
        return (element, rect)
    }

    // MARK: - меню

    private func show(for window: AXUIElement, at rect: CGRect) {
        onWillShow?()
        // Заголовок окна нужен и команде темы (адресация, как у «Обкэшить»), и галке в подменю.
        let title = AX.string(window, kAXTitleAttribute) ?? ""
        var config = MenuConfig()
        config.themes = actions.themes
        config.fonts = actions.fonts
        // Файл своих тем читаем на каждый показ: его правит и сам Элвис (план п. 4).
        config.myThemes = actions.myThemes.load()
        config.windowThemeID = actions.themeStore.windowThemeID(title: title)
        config.allThemeID = actions.themeStore.allThemeID
        config.windowFontID = actions.themeStore.windowFontID(title: title)
        config.allFontID = actions.themeStore.allFontID
        // Была ли примерка и закрепили ли её выбором — оба флага живут до конца popUp
        // (замыкания меню срабатывают внутри его цикла).
        var previewed = false
        var committed = false
        // Пункт срабатывает внутри цикла popUp: откладываем на ход вперёд, чтобы
        // сначала закрылось меню и вернулся фокус окну Claude.
        config.perform = { [weak self] command in
            committed = true
            DispatchQueue.main.async { self?.actions.perform(command, on: window) }
        }
        config.apply = { [weak self] scope, theme, font in
            committed = true
            DispatchQueue.main.async {
                self?.actions.applyTheme(scope: scope, theme: theme, font: font, window: window)
            }
        }
        config.applyMyTheme = { [weak self] scope, my in
            committed = true
            DispatchQueue.main.async { self?.actions.apply(myTheme: my, scope: scope, window: window) }
        }
        // Примерка уходит в страницу сразу, без отсрочки: пока Элвис ведёт мышью, окно должно
        // перекрашиваться под курсором. Хранилища примерка не касается — ни на странице, ни здесь.
        config.previewTheme = { [weak self] theme in
            guard let self = self, self.actions.previewTheme(theme, window: window) else { return }
            previewed = true
        }
        config.previewMyTheme = { [weak self] my in
            guard let self = self, self.actions.preview(myTheme: my, window: window) else { return }
            previewed = true
        }
        config.previewFont = { [weak self] font in
            guard let self = self, self.actions.previewFont(font, window: window) else { return }
            previewed = true
        }
        config.saveMyTheme = { [weak self] in
            DispatchQueue.main.async { self?.saveMyTheme(window: window) }
        }
        config.deleteMyTheme = { [weak self] my in
            DispatchQueue.main.async { self?.actions.myThemes.delete(id: my.id) }
        }
        let menu = MinimizeMenu.build(config: config)

        shows += 1
        menuOpen = true
        // popUp требует активного приложения, иначе меню не получает событий и закрывается
        // при первом же движении мыши (03.09: подменю тем «схлопывалось»). Кооперативный
        // activate() на macOS 14+ без yield со стороны Claude приложение не активирует —
        // нужен именно ignoringOtherApps, как делает Hammerspoon перед popupMenu.
        NSApp.activate(ignoringOtherApps: true)
        let origin = Screens.flip(point: CGPoint(x: rect.minX, y: rect.maxY + 2))
        menu.popUp(positioning: nil, at: origin, in: nil)
        menuOpen = false
        // Ушли из меню, ничего не выбрав, — вернуть окну сохранённое. Синхронно, сразу после
        // popUp: замыкания выбора отложены на ход вперёд, и «конец предпросмотра», посланный
        // после них, перекрыл бы закрепление — лоадер читает command.json раз в 500 мс и
        // берёт последнюю команду.
        if previewed && !committed { actions.endPreview(window: window) }
        // Меню закрылось — фокус обратно окну Claude (решение 7 плана).
        app.focus(window: window)
    }

    /// «Сохранить как мою тему…»: имя спрашиваем модально, пару берём из последней команды
    /// этого приложения. Тему ни разу не выбирали — сохранять нечего, показываем алерт.
    /// После диалога фокус возвращается окну Claude, как после самого меню.
    private func saveMyTheme(window: AXUIElement) {
        // Пока висит диалог, тик наведения не должен всплывать меню поверх него.
        menuOpen = true
        defer { menuOpen = false; app.focus(window: window) }
        guard let theme = actions.lastAppliedTheme else {
            MinimizeMenu.warn(MenuModel.myThemeEmptyAlert)
            return
        }
        guard let name = MinimizeMenu.askThemeName(default: theme.name) else { return }
        if actions.saveMyTheme(name: name) == nil {
            MinimizeMenu.warn("Не удалось записать my-themes.json в Application Support/MyClaude")
        }
    }

    // MARK: - сборка меню (без AX и popUp — так его и проверяют тесты)

    /// Всё, что меню знает о мире: каталоги, галки и что делать по нажатию.
    /// Одним struct — параметров стало слишком много для списка аргументов (план п. 2).
    struct MenuConfig {
        var themes: [Theme] = []
        var fonts: [Font] = []
        var myThemes: [MyTheme] = []
        var windowThemeID: String?
        var allThemeID: String?
        var windowFontID: String?
        var allFontID: String?
        var perform: (ClaudeCommand) -> Void = { _ in }
        /// scope, слой темы, слой шрифта — одна команда на оба слоя (контракт п. 5).
        var apply: (String, Layer<Theme>, Layer<Font>) -> Void = { _, _, _ in }
        var applyMyTheme: (String, MyTheme) -> Void = { _, _ in }
        /// Наведение на пункт списка окна: примерить слой, ничего не запоминая (план WF8 п. 2).
        /// `nil` — примерка сброса слоя («Как у Claude» / «Системный»).
        var previewTheme: (Theme?) -> Void = { _ in }
        var previewMyTheme: (MyTheme) -> Void = { _ in }
        var previewFont: (Font?) -> Void = { _ in }
        var saveMyTheme: () -> Void = {}
        var deleteMyTheme: (MyTheme) -> Void = { _ in }
    }

    /// Меню кнопки: семь пунктов с разделителями, затем — если каталог тем не пуст — разделитель
    /// и подменю «Тема ▸» и «Шрифт ▸». Собрано отдельно от show(), чтобы проверять его в тестах.
    static func build(config: MenuConfig) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in MenuModel.entries {
            let item = BlockMenuItem(title: entry.menuTitle) { config.perform(entry.command) }
            item.image = icon(entry.icon)
            // Клавишу справа серым AppKit рисует сам — в заголовке её больше нет (решение 4 WF9).
            // Маску ставим и пустую: по умолчанию у NSMenuItem она ⌘, а у «Workflow» клавиши нет.
            item.keyEquivalent = entry.key?.keyEquivalent ?? ""
            item.keyEquivalentModifierMask = entry.key?.modifierMask ?? []
            menu.addItem(item)
            if MenuModel.separatorsAfter.contains(entry.command) { menu.addItem(.separator()) }
        }
        // Каталога нет (старый бандл без themes.json) — меню остаётся прежним, семь пунктов.
        guard !config.themes.isEmpty || !config.fonts.isEmpty else { return menu }
        menu.addItem(.separator())
        if !config.themes.isEmpty { menu.addItem(themeItem(config)) }
        if !config.fonts.isEmpty { menu.addItem(fontItem(config)) }
        return menu
    }

    /// «🎨 Тема ▸»: список окна, вложенное «Всем окнам ▸» и свои темы.
    static func themeItem(_ config: MenuConfig) -> NSMenuItem {
        let submenu = themeList(config, scope: MenuModel.themeScopeWindow)
        submenu.addItem(.separator())
        submenu.addItem(submenuItem(title: MenuModel.allWindowsTitle,
                                    submenu: themeList(config, scope: MenuModel.themeScopeAll)))
        submenu.addItem(BlockMenuItem(title: MenuModel.saveMyThemeTitle) { config.saveMyTheme() })
        if !config.myThemes.isEmpty {
            let deletes = NSMenu(title: MenuModel.deleteMyThemeTitle)
            deletes.autoenablesItems = false
            for my in config.myThemes {
                deletes.addItem(BlockMenuItem(title: my.name) { config.deleteMyTheme(my) })
            }
            submenu.addItem(submenuItem(title: MenuModel.deleteMyThemeTitle, submenu: deletes))
        }
        return submenuItem(title: MenuModel.themeTitle, icon: MenuModel.themeIcon, submenu: submenu)
    }

    /// Список тем одного адресата: свои темы, тёмные, светлые, «Как у Claude».
    /// У «всем окнам» сверху disabled-заголовок — иначе список не отличить от списка окна.
    static func themeList(_ config: MenuConfig, scope: String) -> NSMenu {
        let all = scope == MenuModel.themeScopeAll
        let selected = all ? config.allThemeID : config.windowThemeID
        let submenu = NSMenu(title: all ? MenuModel.allWindowsTitle : MenuModel.themeTitle)
        submenu.autoenablesItems = false
        // Предпросмотр по наведению — только в списке окна: красить все окна на наведении
        // шумно (план WF8 п. 2), поэтому у «Всем окнам ▸» ни делегата, ни примерок у пунктов.
        if !all { submenu.delegate = PreviewMenuDelegate.shared }
        if all { submenu.addItem(header(MenuModel.allWindowsHeader)) }

        if !config.myThemes.isEmpty {
            submenu.addItem(header(MenuModel.myThemesHeader))
            for my in config.myThemes {
                let item = BlockMenuItem(title: my.name) { config.applyMyTheme(scope, my) }
                // Примеряем только тему своей темы: в команде предпросмотра один слой.
                item.preview = all ? nil : { config.previewMyTheme(my) }
                item.image = swatch(palette: my.palette)
                item.state = my.id == selected ? .on : .off
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
        }

        for (title, themes) in [(MenuModel.darkThemesHeader, config.themes.filter { !$0.isLight }),
                                (MenuModel.lightThemesHeader, config.themes.filter { $0.isLight })]
        where !themes.isEmpty {
            submenu.addItem(header(title))
            for theme in themes {
                let item = BlockMenuItem(title: theme.name) { config.apply(scope, .set(theme), .keep) }
                item.preview = all ? nil : { config.previewTheme(theme) }
                item.image = swatch(palette: theme.palette)
                item.state = theme.id == selected ? .on : .off
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())
        // Сбрасываем только свой слой: шрифт окна тема «Как у Claude» не трогает.
        let reset = BlockMenuItem(title: MenuModel.themeResetTitle) { config.apply(scope, .reset, .keep) }
        reset.preview = all ? nil : { config.previewTheme(nil) }
        // У окна память по заголовку неточна (главное окно меняет заголовок с чатом):
        // без записи галку не ставим никуда, чтобы не врать «Как у Claude».
        reset.state = (all && selected == nil) ? .on : .off
        submenu.addItem(reset)
        return submenu
    }

    /// «🔤 Шрифт ▸»: список окна и вложенное «Всем окнам ▸».
    static func fontItem(_ config: MenuConfig) -> NSMenuItem {
        let submenu = fontList(config, scope: MenuModel.themeScopeWindow)
        submenu.addItem(submenuItem(title: MenuModel.allWindowsTitle,
                                    submenu: fontList(config, scope: MenuModel.themeScopeAll)))
        return submenuItem(title: MenuModel.fontTitle, icon: MenuModel.fontIcon, submenu: submenu)
    }

    /// Обычные, моноширинные, «Системный (как у Claude)». Каждый пункт нарисован своим
    /// шрифтом — чтобы видеть, как он выглядит, до применения.
    static func fontList(_ config: MenuConfig, scope: String) -> NSMenu {
        let all = scope == MenuModel.themeScopeAll
        let selected = all ? config.allFontID : config.windowFontID
        let submenu = NSMenu(title: all ? MenuModel.allWindowsTitle : MenuModel.fontTitle)
        submenu.autoenablesItems = false
        if !all { submenu.delegate = PreviewMenuDelegate.shared }
        if all { submenu.addItem(header(MenuModel.allWindowsHeader)) }

        // Четыре секции по категориям (решение 7 плана WF9), в порядке FontCategory.
        for (title, fonts) in FontCategory.allCases.map({ category in
            (MenuModel.fontsHeader(category), config.fonts.filter { $0.category == category })
        }) where !fonts.isEmpty {
            submenu.addItem(header(title))
            for font in fonts {
                let item = BlockMenuItem(title: font.displayName) { config.apply(scope, .keep, .set(font)) }
                item.preview = all ? nil : { config.previewFont(font) }
                item.attributedTitle = NSAttributedString(string: font.displayName, attributes: [
                    .font: NSFont(name: font.family, size: 13) ?? NSFont.systemFont(ofSize: 13),
                ])
                item.state = font.id == selected ? .on : .off
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())
        let reset = BlockMenuItem(title: MenuModel.fontResetTitle) { config.apply(scope, .keep, .reset) }
        reset.preview = all ? nil : { config.previewFont(nil) }
        reset.state = (all && selected == nil) ? .on : .off
        submenu.addItem(reset)
        return submenu
    }

    /// Disabled-заголовок секции (меню с autoenablesItems = false, иначе AppKit включит его сам).
    static func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static func submenuItem(title: String, icon emoji: String? = nil, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let emoji = emoji { item.image = icon(emoji) }
        item.submenu = submenu
        return item
    }

    // MARK: - картинки и диалоги

    /// Кружок темы 14 px: заливка background, ободок accent. Не `icon()` — там эмодзи текстом,
    /// а тут нужна цветная картинка (`isTemplate = false`, иначе macOS перекрасит её в цвет метки).
    static func swatch(palette: [String: String], size: CGFloat = 14) -> NSImage {
        let fill = color(palette["background"]) ?? .windowBackgroundColor
        let ring = color(palette["accent"]) ?? .labelColor
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            fill.setFill()
            path.fill()
            ring.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// «#a78bfa» или «#abc» → NSColor; всё остальное — nil (кружок возьмёт системный цвет).
    static func color(_ hex: String?) -> NSColor? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// Имя своей темы. Приложение — LSUIElement: без activate(ignoringOtherApps:) окно алерта
    /// уходит за Claude, а без initialFirstResponder курсор не встаёт в поле.
    static func askThemeName(default value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = MenuModel.myThemeNamePrompt
        alert.informativeText = MenuModel.myThemeNameHint
        alert.addButton(withTitle: MenuModel.myThemeSaveButton)
        alert.addButton(withTitle: MenuModel.myThemeCancelButton)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = MyThemesStore.clean(name: field.stringValue)
        return name.isEmpty ? nil : name
    }

    static func warn(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Эмодзи → картинка 18×18. Монохромный ▦ берёт цвет метки, цветные эмодзи рисуются как есть.
    static func icon(_ emoji: String, size: CGFloat = 18) -> NSImage? {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let text = NSAttributedString(string: emoji, attributes: [
                .font: NSFont.systemFont(ofSize: size * 0.78),
                .paragraphStyle: style,
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let height = text.size().height
            text.draw(in: NSRect(x: 0, y: (rect.height - height) / 2, width: rect.width, height: height))
            return true
        }
        return image
    }
}

/// Наведение на пункт подменю тем и шрифтов — предпросмотр (план WF8 п. 2): окно красится
/// сразу, ничего не запоминая. Что примерять, знает сам пункт (`BlockMenuItem.preview`),
/// поэтому делегат без состояния и один на все меню — заодно снимается вопрос времени жизни:
/// `NSMenu.delegate` — слабая ссылка. Заголовки секций, разделители и пункты с подменю
/// примерок не имеют: наведение на них предпросмотр не трогает.
final class PreviewMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = PreviewMenuDelegate()

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        (item as? BlockMenuItem)?.preview?()
    }
}

/// NSMenuItem с замыканием: цели-селекторы здесь только мешают.
final class BlockMenuItem: NSMenuItem {
    /// Что примерить при наведении (план WF8 п. 2); nil — пункт предпросмотра не делает.
    var preview: (() -> Void)?

    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) не используется") }

    @objc private func fire() { handler() }
}
