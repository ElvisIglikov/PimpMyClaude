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

    /// Рабочая область экрана, на котором СТОЯТ окна (по центрам рамок, большинство) — по ней
    /// «Расставить» считает сетку. `mainUsableFrame` для этого не годится: `NSScreen.main` —
    /// экран с активным окном, и с ним окна Claude уезжали на второй монитор, стоило Элвису
    /// щёлкнуть там что-то (08.09 03:10). Окна ни на одном экране — экран с меню-баром.
    static func usableFrame(holding frames: [CGRect]) -> CGRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let index = pick(screens: screens.map { flip(rect: $0.frame) }, for: frames)
        return flip(rect: screens[index].visibleFrame)
    }

    /// Чистый выбор экрана (его гоняют тесты): индекс экрана, где центров рамок больше всего;
    /// ничья — меньший индекс; ни одного попадания или рамок нет — 0 (экран с меню-баром).
    static func pick(screens: [CGRect], for frames: [CGRect]) -> Int {
        var counts = [Int](repeating: 0, count: screens.count)
        for frame in frames {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if let hit = screens.firstIndex(where: { $0.contains(center) }) { counts[hit] += 1 }
        }
        var best = 0
        for (index, count) in counts.enumerated() where count > counts[best] { best = index }
        return best
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

    /// Служебное окно Electron, а не окно чата (#5791). У КАЖДОГО экземпляра Claude в выдаче
    /// оконного сервера лежит пара безымянных окон 800×600 по координатам 335,164, и по
    /// одному размеру их от настоящего чата не отличить (замер ElvisOS); имя окна сервер
    /// отдаёт только при разрешении «Запись экрана», значит решать по имени нельзя вовсе.
    /// Заодно мимо идут прозрачные (палитры Electron держат alpha 0) и мелочь меньше 200×150 —
    /// прежний порог 120×120 пускал сюда и то, и другое, а «Обкэшить» отдаёт рамку донора
    /// ПЕРВОМУ незнакомому окну и потом закрывает донора. Чистая — её и гоняют тесты.
    static let serviceWindowFrame = CGRect(x: 335, y: 164, width: 800, height: 600)
    static let minWindowSize = CGSize(width: 200, height: 150)
    static let minWindowAlpha: CGFloat = 0.05

    static func isServiceWindow(frame: CGRect, alpha: CGFloat) -> Bool {
        if alpha < minWindowAlpha { return true }
        if frame.width < minWindowSize.width || frame.height < minWindowSize.height { return true }
        return abs(frame.minX - serviceWindowFrame.minX) < 1
            && abs(frame.minY - serviceWindowFrame.minY) < 1
            && abs(frame.width - serviceWindowFrame.width) < 1
            && abs(frame.height - serviceWindowFrame.height) < 1
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
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1
            guard !isServiceWindow(frame: rect, alpha: alpha) else { continue }
            out.append(ClaudeWindowFrame(id: number, frame: rect))
        }
        return out
    }

    /// Шаг подъёма окна вперёд.
    enum FocusStep: Equatable {
        /// Активировать сам Claude.
        case activate
        /// `kAXRaiseAction` — поднять окно среди окон Claude.
        case raise
        /// `kAXMain` + `kAXFocused`.
        case main
        case focused
    }

    /// Порядок подъёма окна вперёд. Чистая величина — её и гоняют тесты.
    ///
    /// Активация ПЕРВОЙ (#5791): `kAXRaiseAction` поднимает окно только среди окон своего
    /// приложения, и пока Claude не активирован, его окна так и остаются под чужими — у
    /// ElvisOS это выглядело как «нажимаю, появляется одно окно, надо жать раза три».
    /// Одного подъёма мало и внутри Claude: без `kAXMain` и `kAXFocused` Electron возвращает
    /// вперёд своё прежнее ключевое окно.
    static let focusSteps: [FocusStep] = [.activate, .raise, .main, .focused]

    /// `hs.window:focus()` — поднять приложение и сделать окно главным.
    func focus(window: AXUIElement) {
        for step in ClaudeApp.focusSteps {
            switch step {
            case .activate: running()?.activate(options: [])
            case .raise: AX.perform(window, kAXRaiseAction)
            case .main: AX.set(window, kAXMainAttribute, bool: true)
            case .focused: AX.set(window, kAXFocusedAttribute, bool: true)
            }
        }
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
