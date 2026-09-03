import AppKit
import ApplicationServices
import CoreGraphics

/// Экранные координаты. AX и `CGWindowListCopyWindowInfo` живут в перевёрнутых координатах
/// Quartz (начало — левый верхний угол главного экрана, y вниз), AppKit — в своих
/// (левый нижний, y вверх). Lua-модули работали целиком в перевёрнутых, поэтому вся
/// геометрия внутри модуля перевёрнутая, и только `NSMenu`/`NSWindow` переводятся обратно.
enum Screens {
    /// Верх главного экрана (того, что с меню-баром) в координатах AppKit.
    static var flipBase: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func flip(point p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: flipBase - p.y) }

    static func flip(rect r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: flipBase - r.maxY, width: r.width, height: r.height)
    }

    /// Рабочая область главного экрана (без меню-бара и дока) в перевёрнутых координатах —
    /// это `hs.screen.mainScreen():frame()` из Lua.
    static var mainUsableFrame: CGRect? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return flip(rect: screen.visibleFrame)
    }
}

/// Окно Claude на экране: номер (CGWindowID) и рамка в перевёрнутых координатах.
struct ClaudeWindowFrame {
    let id: CGWindowID
    let frame: CGRect
}

/// Поиск Claude и его окон. Приложение ищется по bundle id (решение 1 плана), имя —
/// запасной вариант, как в `claude_noquit.lua`.
final class ClaudeApp {
    static let bundleID = "com.anthropic.claudefordesktop"
    static let name = "Claude"

    /// Вызывается, когда Claude перезапустился (сменился pid): кэши прямоугольников стали
    /// мусором (грабли из claude_minimize_menu.lua, «windows=0» после ⌘Q).
    var onRestart: (() -> Void)?

    private var cachedApp: NSRunningApplication?
    private var cachedElement: AXUIElement?
    private var lastPID: pid_t?
    private var checkedAt: TimeInterval = 0
    private let recheckInterval: TimeInterval = 2

    private var axWindows: [AXUIElement] = []
    private var axWindowsAt: TimeInterval = 0
    private let windowCacheSeconds: TimeInterval = 1.0

    func running() -> NSRunningApplication? {
        if let app = cachedApp, !app.isTerminated { return app }
        let now = Date.timeIntervalSinceReferenceDate
        if cachedApp == nil && now - checkedAt < recheckInterval { return nil }
        checkedAt = now

        cachedApp = nil
        cachedElement = nil
        axWindows = []
        axWindowsAt = 0

        let apps = NSWorkspace.shared.runningApplications
        let found = apps.first { $0.bundleIdentifier == ClaudeApp.bundleID }
            ?? apps.first { $0.localizedName == ClaudeApp.name && $0.activationPolicy == .regular }
        cachedApp = found
        if let found = found {
            if let last = lastPID, last != found.processIdentifier { onRestart?() }
            lastPID = found.processIdentifier
        }
        return found
    }

    var pid: pid_t? { running()?.processIdentifier }

    var isFrontmost: Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        return front.bundleIdentifier == ClaudeApp.bundleID || front.localizedName == ClaudeApp.name
    }

    static func isClaude(_ app: NSRunningApplication?) -> Bool {
        guard let app = app else { return false }
        return app.bundleIdentifier == ClaudeApp.bundleID || app.localizedName == ClaudeApp.name
    }

    /// AX-элемент приложения. Таймаут — чтобы зависший Electron не подвешивал наш процесс
    /// (в Hammerspoon таймаут системный, 6 с; здесь короче — таймеры идут в главном потоке).
    func element() -> AXUIElement? {
        if let element = cachedElement, cachedApp?.isTerminated == false { return element }
        guard let pid = running()?.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 1.0)
        cachedElement = element
        return element
    }

    /// Все окна Claude по AX (кэш 1 с, как `M.windowCacheSeconds`).
    func windows() -> [AXUIElement] {
        let now = Date.timeIntervalSinceReferenceDate
        if now - axWindowsAt < windowCacheSeconds { return axWindows }
        axWindowsAt = now
        guard let app = element() else { axWindows = []; return axWindows }
        axWindows = AX.elements(app, kAXWindowsAttribute)
        return axWindows
    }

    /// Видимые (не свёрнутые, приложение не спрятано) окна — `w:isVisible() and not w:isMinimized()`.
    func visibleWindows() -> [AXUIElement] {
        guard running()?.isHidden == false else { return [] }
        return windows().filter { AX.bool($0, kAXMinimizedAttribute) != true }
    }

    func focusedWindow() -> AXUIElement? {
        guard let app = element() else { return nil }
        return AX.element(app, kAXFocusedWindowAttribute)
    }

    /// AX-окно с такой же рамкой, как у окна из `CGWindowListCopyWindowInfo`.
    /// Совпадение по геометрии: `_AXUIElementGetWindow` — приватный вызов, обходимся без него.
    func window(matching frame: CGRect) -> AXUIElement? {
        windows().first { element in
            guard let f = AX.frame(element) else { return false }
            return abs(f.minX - frame.minX) <= 2 && abs(f.minY - frame.minY) <= 2
                && abs(f.width - frame.width) <= 2 && abs(f.height - frame.height) <= 2
        }
    }

    /// Рамки окон Claude спереди назад (решение 7 плана: геометрия из CGWindowList, а не из AX —
    /// один вызов на тик вместо двух AX-обращений на каждое окно).
    /// Заголовки окон отсюда не берём: `kCGWindowName` требует разрешения на запись экрана.
    static func onScreenFrames(pid: pid_t) -> [ClaudeWindowFrame] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [ClaudeWindowFrame] = []
        for info in list {
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, owner == pid else { continue }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { continue }
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            guard let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            // Служебные окошки Electron мимо: настоящее окно Claude не уже 360 px.
            guard rect.width >= 120, rect.height >= 120 else { continue }
            out.append(ClaudeWindowFrame(id: number, frame: rect))
        }
        return out
    }

    /// `hs.window:focus()` — сделать окно главным и поднять приложение.
    func focus(window: AXUIElement) {
        AX.set(window, kAXMainAttribute, bool: true)
        AX.perform(window, kAXRaiseAction)
        running()?.activate(options: [])
    }

    /// `hs.eventtap.keyStroke(mods, key, 0, app)` — событие адресуется процессу Claude,
    /// а не системе: это не event tap (правило init.lua), только posting.
    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let pid = pid, let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.postToPid(pid)
        up.postToPid(pid)
    }
}
