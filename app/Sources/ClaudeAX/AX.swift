import ApplicationServices
import Foundation

/// Тонкие обёртки над AXUIElement — то, что в Lua-модулях делал `hs.axuielement`.
/// Все вызовы синхронные и блокирующие, поэтому у элемента приложения выставлен
/// таймаут (см. `ClaudeApp.element()`): зависший Electron не должен вешать меню-бар.
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &out) == .success else { return nil }
        return out
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute) as? Bool
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (value(element, attribute) as? [AXUIElement]) ?? []
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        guard AXValueGetValue((v as! AXValue), .cgPoint, &p) else { return nil }
        return p
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue((v as! AXValue), .cgSize, &s) else { return nil }
        return s
    }

    /// Прямоугольник окна/кнопки в экранных координатах Quartz (начало — левый верхний угол
    /// главного экрана, y вниз). Те же координаты, что у `CGWindowListCopyWindowInfo`.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = point(element, kAXPositionAttribute), let s = size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, bool: Bool) -> Bool {
        set(element, attribute, bool ? kCFBooleanTrue : kCFBooleanFalse)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, point: CGPoint) -> Bool {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return set(element, attribute, v)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, size: CGSize) -> Bool {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return set(element, attribute, v)
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// Свой срок ответа отдельному элементу (обычно окну). От элемента приложения таймаут
    /// НЕ наследуется — замер ElvisOS, #5784: там его ставили отдельно приложению и отдельно
    /// найденному окну, потому что постановка рамки идёт уже через окно. Системный таймаут
    /// (6 с) менять нельзя: он общий на процесс и возвращает подтормаживание мыши.
    static func timeout(_ element: AXUIElement, _ seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    /// Закрыть окно — нажать его красную кнопку (#5768, замена окна на «Обкэшить»).
    /// Кнопка берётся тем же путём, что жёлтая у меню (`kAXMinimizeButtonAttribute`):
    /// у окна её может не быть вовсе (Electron ещё не отдал AX-дерево) — тогда `false`,
    /// и окно остаётся на экране.
    @discardableResult
    static func close(_ window: AXUIElement) -> Bool {
        guard let button = element(window, kAXCloseButtonAttribute) else { return false }
        return perform(button, kAXPressAction)
    }

    /// Есть ли у процесса доверие Accessibility. Без промпта: окно с просьбой показывает
    /// приложение (батч C), модуль без доверия работает вхолостую.
    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    private static var trustCache = false
    private static var trustCheckedAt: TimeInterval = 0

    /// То же с кэшем на секунду — таймер меню спрашивает 8 раз в секунду.
    static var isTrustedCached: Bool {
        let now = Date.timeIntervalSinceReferenceDate
        if now - trustCheckedAt > 1 {
            trustCache = isTrusted
            trustCheckedAt = now
        }
        return trustCache
    }
}
