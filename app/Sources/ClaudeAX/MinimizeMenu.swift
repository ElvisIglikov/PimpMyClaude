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
        // Заголовок окна нужен и команде темы (адресация, как у «Обкэшить»), и галке в подменю.
        let title = AX.string(window, kAXTitleAttribute) ?? ""
        let menu = MinimizeMenu.build(
            themes: actions.themes,
            windowThemeID: actions.themeStore.windowThemeID(title: title),
            allThemeID: actions.themeStore.allThemeID,
            // Пункт срабатывает внутри цикла popUp: откладываем на ход вперёд, чтобы
            // сначала закрылось меню и вернулся фокус окну Claude.
            perform: { [weak self] command in
                DispatchQueue.main.async { self?.actions.perform(command, on: window) }
            },
            applyTheme: { [weak self] scope, theme in
                DispatchQueue.main.async {
                    self?.actions.applyTheme(scope: scope, theme: theme, window: window)
                }
            })

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
        // Меню закрылось — фокус обратно окну Claude (решение 7 плана).
        app.focus(window: window)
    }

    /// Меню кнопки: семь пунктов с разделителями, затем — если каталог тем не пуст — разделитель
    /// и два подменю тем. Собрано отдельно от show(), чтобы проверять его в тестах без AX и popUp.
    static func build(themes: [Theme], windowThemeID: String?, allThemeID: String?,
                      perform: @escaping (ClaudeCommand) -> Void,
                      applyTheme: @escaping (String, Theme?) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in MenuModel.entries {
            let item = BlockMenuItem(title: entry.menuTitle) { perform(entry.command) }
            item.image = icon(entry.icon)
            menu.addItem(item)
            if MenuModel.separatorsAfter.contains(entry.command) { menu.addItem(.separator()) }
        }
        // Каталога нет (старый бандл без themes.json) — меню остаётся прежним, семь пунктов.
        guard !themes.isEmpty else { return menu }
        menu.addItem(.separator())
        menu.addItem(themeItem(title: MenuModel.windowThemeTitle, themes: themes, selected: windowThemeID, resetWhenNone: false) {
            applyTheme(MenuModel.themeScopeWindow, $0)
        })
        menu.addItem(themeItem(title: MenuModel.allWindowsThemeTitle, themes: themes, selected: allThemeID) {
            applyTheme(MenuModel.themeScopeAll, $0)
        })
        return menu
    }

    /// Подменю: темы каталога, разделитель, «Как у Claude» (сброс). Галка — у выбранной темы,
    /// а если не выбрано ничего, у «Как у Claude».
    static func themeItem(title: String, themes: [Theme], selected: String?, resetWhenNone: Bool = true,
                          apply: @escaping (Theme?) -> Void) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        for theme in themes {
            let item = BlockMenuItem(title: theme.name) { apply(theme) }
            item.state = theme.id == selected ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let reset = BlockMenuItem(title: MenuModel.themeResetTitle) { apply(nil) }
        // У окна память по заголовку неточна (главное окно меняет заголовок с чатом):
        // без записи галку не ставим никуда, чтобы не врать «Как у Claude».
        reset.state = (selected == nil && resetWhenNone) ? .on : .off
        submenu.addItem(reset)

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = icon(MenuModel.themeIcon)
        item.submenu = submenu
        return item
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

/// NSMenuItem с замыканием: цели-селекторы здесь только мешают.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) не используется") }

    @objc private func fire() { handler() }
}
