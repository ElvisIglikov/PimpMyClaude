import AppKit
import ApplicationServices

// Окно «Повтор iPhone» влезает по высоте (#11120, слово Элвиса 29.10: «Телефон не влезает на экран… сделать как-то
// покомпактнее, чтоб оно влезало у меня по высоте»). Замер 29.10 на Odyssey (видимая часть 690 pt): окно 354×781 в
// (1406, 30) — ниже экрана; размер AX не меняется (`AXSize` не settable), а «Вид → Уменьшить» (⌘−) даёт 236×524 и
// окно встаёт само в (1465, 159); шаг один — пункт гаснет. Масштаб программа помнит между запусками.
// Пимп смотрит окно только когда оно появилось (запуск программы или её активация с новым окном): выше видимой части
// своего экрана — жмёт «Уменьшить», пока не влезет (не больше `maxSteps`), и ставит окно в видимую часть. Влезает — не
// трогает. Человек увеличил потом то же окно — Пимп с ним не спорит: окно уже знакомое.
public final class PhoneMirrorFit {
    public static let shared = PhoneMirrorFit()
    public static let bundleID = "com.apple.ScreenContinuity"
    /// Больше шагов «Уменьшить» не жмём, даже если пункт ещё горит.
    static let maxSteps = 4
    /// Пауза после нажатия — окно меняет размер с анимацией (замер: к 1 с уже новый).
    static let stepPause: TimeInterval = 0.5
    /// Сколько ждать, пока «Уменьшить» загорится после появления окна.
    static let menuWait: TimeInterval = 8

    public enum Action: Equatable {
        /// Влезает и стоит в видимой части — не трогаем.
        case none
        /// Выше видимой части — жать «Уменьшить».
        case shrink
        /// По высоте влезает (или уменьшать больше нельзя), но торчит — поставить сюда (AX, сверху слева).
        case move(CGPoint)
    }

    /// Что делать с окном `window` на видимой части экрана `visible` (оба — AX, начало сверху слева главного экрана).
    /// `canShrink` — пункт «Уменьшить» горит и шагов меньше `maxSteps`. Не влезает и уменьшать нельзя — верх окна к
    /// верху видимой части (низ уйдёт за край, но верх с «островом» и кнопками виден).
    public static func decide(window: CGRect, visible: CGRect, canShrink: Bool) -> Action {
        if window.height > visible.height + 0.5, canShrink { return .shrink }
        let x = min(max(window.minX, visible.minX), max(visible.minX, visible.maxX - window.width))
        let y = min(max(window.minY, visible.minY), max(visible.minY, visible.maxY - window.height))
        let target = CGPoint(x: x.rounded(), y: y.rounded())
        return abs(target.x - window.minX) < 1 && abs(target.y - window.minY) < 1 ? .none : .move(target)
    }

    /// Видимая часть экрана окна (AX): экран, где середина окна, иначе где его верх, иначе главный.
    /// `screens` — `visibleFrame` и `frame` в координатах Cocoa, `primaryHeight` — высота главного экрана.
    public static func visibleArea(for window: CGRect, screens: [(frame: CGRect, visible: CGRect)],
                                   primaryHeight: CGFloat) -> CGRect? {
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }
        let all = screens.map { (full: flip($0.frame), visible: flip($0.visible)) }
        let top = CGPoint(x: window.midX, y: window.minY + 1)
        return (all.first { $0.full.contains(CGPoint(x: window.midX, y: window.midY)) }
            ?? all.first { $0.full.contains(top) } ?? all.first)?.visible
    }

    // MARK: живая часть

    private var observers: [NSObjectProtocol] = []
    /// Окна, что Пимп уже видел (сравнение — `CFEqual`): их больше не трогаем.
    private var known: [AXUIElement] = []
    private var busy = false

    public func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.bundleID else { return }
                // Окно появляется не сразу после запуска (соединение с телефоном) — смотрим несколько раз.
                for delay in [0.5, 1.5, 3.0] { self?.check(app, after: delay) }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Self.bundleID { self?.known = [] }
        })
        // Уже открытое при запуске Пимпа окно — знакомое: его показывал человек.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first {
            known = windows(of: app)
        }
    }

    private func check(_ app: NSRunningApplication, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard !busy, !app.isTerminated, AXIsProcessTrusted() else { return }
            let fresh = windows(of: app).filter { window in !known.contains { CFEqual($0, window) } }
            guard let window = fresh.first else { return }
            known.append(contentsOf: fresh)
            busy = true
            let pid = app.processIdentifier
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                fit(window, pid: pid)
                DispatchQueue.main.async { self.busy = false }
            }
        }
    }

    /// Уменьшает и ставит окно; не на главной нитке (паузы между шагами).
    private func fit(_ window: AXUIElement, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var steps = 0, waited: TimeInterval = 0
        while steps <= Self.maxSteps, let frame = Self.frame(window), let visible = visibleArea(frame) {
            let shrink = steps < Self.maxSteps ? Self.shrinkItem(app) : nil
            // Сразу после запуска «Уменьшить» погашен, пока картинка телефона не пришла (замер 29.10: в 0,5 с — нет).
            if shrink == nil, steps == 0, frame.height > visible.height + 0.5, waited < Self.menuWait {
                Thread.sleep(forTimeInterval: Self.stepPause)
                waited += Self.stepPause
                continue
            }
            switch Self.decide(window: frame, visible: visible, canShrink: shrink != nil) {
            case .none:
                return
            case .shrink:
                guard let item = shrink, AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                else { return }
                steps += 1
                Thread.sleep(forTimeInterval: Self.stepPause)
            case .move(let point):
                var p = point
                if let value = AXValueCreate(.cgPoint, &p) {
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
                }
                return
            }
        }
    }

    private func visibleArea(_ frame: CGRect) -> CGRect? {
        let screens: [(frame: CGRect, visible: CGRect)] = DispatchQueue.main.sync {
            NSScreen.screens.map { ($0.frame, $0.visibleFrame) }
        }
        let primary = screens.first?.frame.height ?? 0
        return Self.visibleArea(for: frame, screens: screens, primaryHeight: primary)
    }

    private func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.5)
        let all = (Self.copy(el, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return all.filter { (Self.copy($0, kAXSubroleAttribute) as? String) == (kAXStandardWindowSubrole as String) }
    }

    static func frame(_ window: AXUIElement) -> CGRect? {
        var p = CGPoint.zero, s = CGSize.zero
        guard let pv = copy(window, kAXPositionAttribute), let sv = copy(window, kAXSizeAttribute),
              AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s),
              s.width > 0, s.height > 0 else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Пункт «Уменьшить» строки меню программы, если горит: ищем не по названию (язык системы бывает любой), а по
    /// клавише — ⌘− без других модификаторов.
    static func shrinkItem(_ app: AXUIElement) -> AXUIElement? {
        guard let bar = copy(app, kAXMenuBarAttribute) else { return nil }
        for top in (copy(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            for menu in (copy(top, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                for item in (copy(menu, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                    guard (copy(item, kAXMenuItemCmdCharAttribute) as? String) == "-",
                          (copy(item, kAXMenuItemCmdModifiersAttribute) as? Int) == 0 else { continue }
                    return (copy(item, kAXEnabledAttribute) as? Bool) == true ? item : nil
                }
            }
        }
        return nil
    }

    private static func copy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success ? value : nil
    }
}
