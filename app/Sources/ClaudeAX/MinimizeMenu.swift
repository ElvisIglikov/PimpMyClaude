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
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in MenuModel.entries {
            let item = BlockMenuItem(title: entry.menuTitle) { [weak self] in
                // Пункт срабатывает внутри цикла popUp: откладываем на ход вперёд, чтобы
                // сначала закрылось меню и вернулся фокус окну Claude.
                DispatchQueue.main.async { self?.actions.perform(entry.command, on: window) }
            }
            item.image = MinimizeMenu.icon(entry.icon)
            menu.addItem(item)
            if MenuModel.separatorsAfter.contains(entry.command) { menu.addItem(.separator()) }
        }

        shows += 1
        menuOpen = true
        // popUp требует активного приложения, иначе меню не получает событий.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        let origin = Screens.flip(point: CGPoint(x: rect.minX, y: rect.maxY + 2))
        menu.popUp(positioning: nil, at: origin, in: nil)
        menuOpen = false
        // Меню закрылось — фокус обратно окну Claude (решение 7 плана).
        app.focus(window: window)
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
