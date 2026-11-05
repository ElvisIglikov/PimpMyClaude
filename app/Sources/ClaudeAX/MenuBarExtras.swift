import AppKit
import ApplicationServices

/// Значки других программ, что не влезли в строку меню (WF270, #10264): на Маке с вырезом macOS прячет их под вырез
/// или убирает совсем. Пимп показывает их рядом в панели у часов, клик — `AXPress` по самому значку.
/// Координаты — AX: начало сверху слева главного экрана.
public enum MenuBarExtras {
    public enum Reason: String, Equatable {
        /// Рамка значка заходит под вырез.
        case notch
        /// Значок убран: за экраном (ниже строки меню, правее края). На macOS 26 так стоят значки, выключенные в
        /// «Системных настройках → Строка меню → Разрешить в строке меню» (замер 29.10, #11143): в полосу не идут.
        case off
    }

    /// Строка меню главного экрана: промежуток выреза по x (nil — выреза нет), высота строки, ширина экрана.
    public struct Bar: Equatable {
        public var notch: ClosedRange<CGFloat>?
        public var height: CGFloat
        public var width: CGFloat
        public init(notch: ClosedRange<CGFloat>?, height: CGFloat, width: CGFloat) {
            self.notch = notch; self.height = height; self.width = width
        }
    }

    public struct Item: Identifiable {
        public var id: String { "\(pid)|\(title)|\(Int(frame.minX))|\(Int(frame.minY))" }
        public let pid: pid_t
        public let bundleId: String?
        public let appName: String
        /// Заголовок или описание значка (что есть).
        public let title: String
        public let frame: CGRect
        public let reason: Reason
        let element: AXUIElement?
        public init(pid: pid_t, bundleId: String?, appName: String, title: String, frame: CGRect, reason: Reason,
                    element: AXUIElement? = nil) {
            self.pid = pid; self.bundleId = bundleId; self.appName = appName; self.title = title
            self.frame = frame; self.reason = reason; self.element = element
        }
        /// Подсказка при наведении: «Karabiner-Elements — Karabiner».
        public var hint: String { title.isEmpty || title == appName ? appName : "\(appName) — \(title)" }
    }

    // MARK: чистая часть

    /// Спрятан ли значок и почему; nil — виден (или пустой нулевой, как у «Пункта управления», — такие не показываем).
    public static func reason(frame: CGRect, bar: Bar) -> Reason? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        if frame.minY >= bar.height || frame.minX >= bar.width || frame.maxX <= 0 || frame.maxY <= 0 { return .off }
        if let notch = bar.notch, frame.maxX > notch.lowerBound, frame.minX < notch.upperBound { return .notch }
        return nil
    }

    /// Идёт ли значок в полосу «Не влезли» (#11143): только под вырезом. Убранный (`.off`) не «не влез» — его
    /// выключили в настройках: Telegram, Claude, Hammerspoon на Odyssey 2560×720 стоят в (7, 719) и (−1, 718), окна в
    /// строке меню у них нет, а в списке «Пункта управления» у них `isAllowed = false`; места в строке — 1800 pt.
    public static func didNotFit(frame: CGRect, bar: Bar) -> Bool { reason(frame: frame, bar: bar) == .notch }

    /// Строка меню по экрану: вырез — между `auxiliaryTopLeftArea.maxX` и `auxiliaryTopRightArea.minX`.
    public static func bar(screen: NSScreen?) -> Bar {
        guard let screen = screen else { return Bar(notch: nil, height: 24, width: 1440) }
        let frame = screen.frame
        var notch: ClosedRange<CGFloat>?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            notch = (left.maxX - frame.minX)...(right.minX - frame.minX)
        }
        var height = screen.safeAreaInsets.top
        if height <= 0 { height = frame.maxY - screen.visibleFrame.maxY }
        if height <= 0 { height = NSStatusBar.system.thickness }
        return Bar(notch: notch, height: height, width: frame.width)
    }

    // MARK: сбор (AX)

    private static let lock = NSLock()
    private static var cached: (at: TimeInterval, items: [Item])?

    /// Спрятанные значки всех программ, кроме своих. Зовётся при открытии панели; чаще раза в 2 с — прошлый ответ.
    public static func hidden(force: Bool = false) -> [Item] {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if !force, let cached = cached, now - cached.at < 2 { lock.unlock(); return cached.items }
        lock.unlock()
        let items = collect().hidden
        lock.lock(); cached = (now, items); lock.unlock()
        return items
    }

    static func collect() -> (hidden: [Item], shown: [CGRect]) {
        guard AXIsProcessTrusted() else { return ([], []) }
        // AX-координаты считаются от главного (первого) экрана; строка меню с вырезом — встроенный, обычно он же.
        let bar = bar(screen: NSScreen.screens.first)
        let own = ProcessInfo.processInfo.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier
        var out: [Item] = []
        var shown: [CGRect] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != own {
            if let id = app.bundleIdentifier, id == ownBundle || id.hasPrefix("com.elvis.pimpmyclaude") { continue }
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, 0.25)
            guard let extras = copy(el, kAXExtrasMenuBarAttribute) else { continue }
            let kids = (copy(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            for kid in kids {
                var p = CGPoint.zero, s = CGSize.zero
                if let v = copy(kid, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
                if let v = copy(kid, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
                let frame = CGRect(origin: p, size: s)
                guard let why = reason(frame: frame, bar: bar) else {
                    if frame.width > 0, frame.height > 0 { shown.append(frame) }
                    continue
                }
                guard didNotFit(frame: frame, bar: bar) else { continue }
                let title = (copy(kid, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (copy(kid, kAXDescriptionAttribute) as? String) ?? ""
                out.append(Item(pid: app.processIdentifier, bundleId: app.bundleIdentifier,
                                appName: app.localizedName ?? app.bundleIdentifier ?? "?", title: title,
                                frame: frame, reason: why, element: kid))
            }
        }
        return (out.sorted { $0.frame.minX < $1.frame.minX }, shown)
    }

    private static func copy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success ? value : nil
    }

    // MARK: перенос в строку меню (#10280)

    /// Куда класть значок, отпущенный в точке `drop` (AX): в строке меню правее выреза, в пределах видимых значков
    /// других программ — точка на их линии (macOS ставит значок туда, куда его ⌘-перетащили). Ниже строки, в вырезе,
    /// левее всех видимых значков (там меню программ) или видимых нет — nil: класть некуда.
    public static func dropPoint(_ drop: CGPoint, bar: Bar, shown: [CGRect]) -> CGPoint? {
        guard drop.y >= 0, drop.y <= bar.height + dropSlack, drop.x >= 0, drop.x < bar.width else { return nil }
        if let notch = bar.notch, notch.contains(drop.x) { return nil }
        let row = shown.filter { reason(frame: $0, bar: bar) == nil && $0.minX >= (bar.notch?.upperBound ?? 0) }
        guard let left = row.map(\.minX).min(), let right = row.map(\.maxX).max(),
              drop.x >= left - dropSlack, drop.x <= right else { return nil }
        return CGPoint(x: max(drop.x, left + 1).rounded(), y: (bar.height / 2).rounded())
    }

    /// Рамки видимых значков других программ (для `dropPoint`); сбор AX — не на главной нитке.
    public static func shownFrames() -> [CGRect] { collect().shown }

    /// Запас вокруг строки меню, pt: отпустил чуть ниже строки или чуть левее крайнего значка — всё равно туда.
    static let dropSlack: CGFloat = 8

    /// Окно значка в WindowServer — его номер идёт в поле события: значок под вырезом не виден, и событие без адреса
    /// досталось бы строке меню. С macOS 26 окна значков всех программ — у «Пункта управления» (замер 19.10: Диктатор,
    /// Karabiner, YouFast — окна pid 630, слой 25), и рамка окна не равна рамке AX (Диктатор AX 557+53, окно 581+36):
    /// берём окно строки меню (слой 25), в котором лежит середина рамки AX. Таких бывает несколько: Диктатор во время
    /// записи держит над вырезом своё широкое окно на том же слое (замер 19.10: 562+156 поверх Gemini 637+38), и ⌘-нажатие
    /// в него открыло Диктатора вместо переноса — берём самое узкое.
    static func windowID(for frame: CGRect, in windows: [(id: CGWindowID, layer: Int, frame: CGRect)]) -> CGWindowID? {
        let mid = frame.midX
        return windows.filter { $0.layer == 25 && $0.frame.minX <= mid && mid < $0.frame.maxX && $0.frame.minY < 5 }
            .min { $0.frame.width < $1.frame.width }?.id
    }

    /// Владелец окна. Окно значка под вырезом не на экране, и `.optionIncludingWindow` его не отдаёт — ищем во всех.
    static func windowOwner(_ id: CGWindowID) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let info = list.first { ($0[kCGWindowNumber as String] as? Int) == Int(id) }
        return (info?[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) }
    }

    static func barWindows() -> [(id: CGWindowID, layer: Int, frame: CGRect)] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return (CGWindowID(number), info[kCGWindowLayer as String] as? Int ?? 0, rect)
        }
    }

    /// Переносит значок ⌘-перетаскиванием в точку строки меню (`dropPoint`): курсор прячется на время шагов и
    /// возвращается на место. `done` — на главной нитке: true — значок больше не спрятан.
    /// Переносится только значок под вырезом, чьё окно в строке меню нашлось (#10285: у убранного значка рамка AX —
    /// посреди экрана, y 831, и ⌘-нажатие туда сбило Элвису строку меню). Иначе — ни одного события, отказ.
    public static func movable(_ item: Item) -> Bool { item.reason == .notch }

    public static func move(_ item: Item, to point: CGPoint, done: @escaping (Bool) -> Void) {
        queue.async {
            let ok = movable(item) && AXIsProcessTrusted() && drag(item, to: point)
            Thread.sleep(forTimeInterval: 0.4)
            let still = ok && collect().hidden.contains { $0.pid == item.pid && $0.title == item.title }
            lock.lock(); cached = nil; lock.unlock()
            DispatchQueue.main.async { done(ok && !still) }
        }
    }

    /// ⌘-перенос событиями прямо окну значка, как у Ice (замер 19.10, macOS 26): нажатие — с полями окна значка и
    /// процесса-владельца окна («Пункт управления») в сессию и этому процессу, отпускание — в точке строки меню с окном
    /// значка под ней. Ход мыши по прямой спрятанный под вырезом значок не брал: в вырезе окна значка нет на экране,
    /// а сверху лежит окно записи Диктатора.
    private static func drag(_ item: Item, to point: CGPoint) -> Bool {
        let windows = barWindows()
        guard let source = CGEventSource(stateID: .hidSystemState),
              let window = windowID(for: item.frame, in: windows),
              let target = windowID(for: CGRect(x: point.x, y: 2, width: 0, height: 20), in: windows),
              let owner = windowOwner(window) else { return false }
        let steps: [Step] = [(.leftMouseDown, CGPoint(x: 20_000, y: 20_000), window), (.leftMouseUp, point, target)]
        return post(steps, button: .left, flags: .maskCommand, owner: owner, toSession: true, source: source,
                    back: point)
    }

    /// Шаг мыши: тип, точка (CG, начало сверху слева), окно значка в поле события.
    private typealias Step = (type: CGEventType, at: CGPoint, window: CGWindowID)

    /// Шаги мыши прямо окну значка (общая часть переноса и правого клика, #10304): курсор прячется на время шагов и
    /// возвращается в `back` (или туда, где был); каждое событие — с полями окна и процесса-владельца окна, процессу,
    /// а с `toSession` — сначала ещё и в сессию (так берёт ⌘-перенос, #10280).
    private static func post(_ steps: [Step], button: CGMouseButton, flags: CGEventFlags, owner: pid_t, toSession: Bool,
                             source: CGEventSource, back fallback: CGPoint) -> Bool {
        if let session = CGEventSource(stateID: .combinedSessionState) {
            let all: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
            session.setLocalEventsFilterDuringSuppressionState(all, state: .eventSuppressionStateRemoteMouseDrag)
            session.setLocalEventsFilterDuringSuppressionState(all, state: .eventSuppressionStateSuppressionInterval)
            session.localEventsSuppressionInterval = 0
        }
        let back = CGEvent(source: nil)?.location ?? fallback
        let display = CGMainDisplayID()
        CGDisplayHideCursor(display)
        defer {
            CGWarpMouseCursorPosition(back)
            CGAssociateMouseAndMouseCursorPosition(1)
            CGDisplayShowCursor(display)
        }
        for step in steps {
            guard let event = CGEvent(mouseEventSource: source, mouseType: step.type, mouseCursorPosition: step.at,
                                      mouseButton: button) else { return false }
            event.flags = flags
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(owner))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(step.window))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(step.window))
            event.setIntegerValueField(windowField, value: Int64(step.window))
            if toSession {
                event.post(tap: .cgSessionEventTap)
                Thread.sleep(forTimeInterval: 0.01)
            }
            event.postToPid(owner)
            Thread.sleep(forTimeInterval: 0.15)
        }
        return true
    }

    /// Поле номера окна в событии (0x33) — его нет в заголовках, Ice берёт его так же.
    static let windowField = CGEventField(rawValue: 0x33)!

    // MARK: порядок внутри полосы (#10304)

    /// Переставить можно только значок под вырезом рядом с другим значком под вырезом: у убранного окна в строке меню
    /// нет (#10285), ⌘-нажатие туда сбило бы строку меню.
    public static func reorderable(_ item: Item, neighbor: Item) -> Bool {
        movable(item) && movable(neighbor) && !(item.pid == neighbor.pid && item.title == neighbor.title)
    }

    /// Куда отпустить значок, чтобы он встал до соседа или после: 2 pt внутрь от левого или правого края ОКНА соседа
    /// (рамка окна не равна рамке AX — у Диктатора AX 557+53, окно 581+36; Ice тоже бросает на край окна цели).
    public static func reorderPoint(beside window: CGRect, after: Bool) -> CGPoint {
        CGPoint(x: (after ? window.maxX - 2 : window.minX + 2).rounded(), y: window.midY.rounded())
    }

    /// Встал ли значок рядом с соседом в свежем списке спрятанных (по порядку x). Значка в списке больше нет — он
    /// вышел из-под выреза в строку меню: тоже переехал.
    public static func placed(_ item: Item, beside neighbor: Item, after: Bool, in fresh: [Item]) -> Bool {
        guard let i = fresh.firstIndex(where: { $0.pid == item.pid && $0.title == item.title }) else { return true }
        guard let j = fresh.firstIndex(where: { $0.pid == neighbor.pid && $0.title == neighbor.title }) else { return false }
        return after ? i == j + 1 : i + 1 == j
    }

    /// Переставляет значок в строке меню до или после соседа тем же ⌘-переносом, что `move`. `done` — на главной
    /// нитке: true — порядок в свежем списке тот, что просили. Не под вырезом (сам или сосед) — ни одного события.
    public static func reorder(_ item: Item, beside neighbor: Item, after: Bool, done: @escaping (Bool) -> Void) {
        queue.async {
            var ok = reorderable(item, neighbor: neighbor) && AXIsProcessTrusted()
            if ok {
                let windows = barWindows()
                if let id = windowID(for: neighbor.frame, in: windows),
                   let frame = windows.first(where: { $0.id == id })?.frame {
                    ok = drag(item, to: reorderPoint(beside: frame, after: after))
                } else {
                    ok = false
                }
            }
            Thread.sleep(forTimeInterval: 0.4)
            let moved = ok && placed(item, beside: neighbor, after: after, in: collect().hidden)
            lock.lock(); cached = nil; lock.unlock()
            DispatchQueue.main.async { done(moved) }
        }
    }

    // MARK: снимок значка (#10301)

    /// Настоящий значок из строки меню — снимок его окна, глиф белым (`glyph(from:)`). Только значок под вырезом
    /// (у убранного рамка AX посреди экрана, и по ней нашлось бы окно чужого видимого значка) и только с «Записью
    /// экрана» у PMP: доступ не спрашиваем (`CGPreflightScreenCaptureAccess` молчит), нет — nil, полоса рисует иконку
    /// программы. Не на главной нитке.
    public static func glyph(_ item: Item) -> CGImage? {
        guard movable(item), captureAllowed(), let create = createImage,
              let id = windowID(for: item.frame, in: barWindows()) else { return nil }
        let options = CGWindowImageOption([.boundsIgnoreFraming, .bestResolution]).rawValue
        guard let shot = create(.null, CGWindowListOption.optionIncludingWindow.rawValue, id, options) else { return nil }
        return glyph(from: shot.takeRetainedValue())
    }

    /// Есть ли у PMP «Запись экрана» — без запроса.
    public static func captureAllowed() -> Bool { CGPreflightScreenCaptureAccess() }

    /// `CGWindowListCreateImage` — через `dlsym`: в SDK 15 она «obsoleted 15.0» (ScreenCaptureKit), в новом SDK
    /// может стать недоступной для сборки, а в системе она есть (macOS 26.6, замер 19.10). Нет символа — снимков нет.
    private typealias CreateImage = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImage? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()

    /// Снимок окна → глиф: пиксели RGBA, `whiten`, обрезка по рамке. Пусто или залито — nil.
    static func glyph(from image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width * height <= 1_000_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let box = whiten(&pixels, width: width, height: height) else { return nil }
        let white: CGImage? = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: space, bitmapInfo: info)?.makeImage()
        }
        return white?.cropping(to: box)
    }

    /// Глиф строки меню белым (слово Элвиса 19.10 14:30 «исправить цвет»): серые и чёрные пиксели (разброс каналов
    /// до 64 из 255, после деления на альфу — буфер premultiplied) становятся белыми той же прозрачности, цветные
    /// (красная точка записи, цветной значок) — как есть. Возвращает рамку видимых пикселей (альфа больше 16) в
    /// пикселях, начало сверху слева; пусто или залито больше чем на 85% (снялся фон, а не глиф) — nil.
    public static func whiten(_ rgba: inout [UInt8], width: Int, height: Int) -> CGRect? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1, solid = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let alpha = Int(rgba[i + 3])
                guard alpha > 0 else { continue }
                if alpha > 16 {
                    solid += 1
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
                let r = min(255, Int(rgba[i]) * 255 / alpha)
                let g = min(255, Int(rgba[i + 1]) * 255 / alpha)
                let b = min(255, Int(rgba[i + 2]) * 255 / alpha)
                guard max(r, g, b) - min(r, g, b) <= 64 else { continue }
                rgba[i] = UInt8(alpha); rgba[i + 1] = UInt8(alpha); rgba[i + 2] = UInt8(alpha)
            }
        }
        guard maxX >= 0, solid * 100 <= width * height * 85 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: нажатие

    private static let queue = DispatchQueue(label: "pimp.menubar-extras", qos: .userInitiated)

    /// Жмёт значок на фоновой очереди (`AXPress` держит нитку, пока меню открыто, и отвечает −25204 — это норма).
    /// Не открылся (другая ошибка, или элемента нет) — открывается само приложение.
    public static func press(_ item: Item, after delay: TimeInterval = 0.15) {
        queue.asyncAfter(deadline: .now() + delay) {
            let code = item.element.map { AXUIElementPerformAction($0, kAXPressAction as CFString).rawValue } ?? -1
            guard !pressWorked(code) else { return }
            DispatchQueue.main.async { openApp(item) }
        }
    }

    /// Нажатие сработало: успех или −25204 (меню открылось и держало вызов до закрытия).
    public static func pressWorked(_ code: Int32) -> Bool { code == 0 || code == -25204 }

    // MARK: правая кнопка (#10304)

    /// Каким путём открылось меню по правой кнопке.
    public enum SecondaryPath: Equatable {
        /// `AXShowMenu` у самого значка.
        case showMenu
        /// Правая кнопка событиями окну значка — и меню программы появилось.
        case rightClick
        /// Ни то ни другое — левое нажатие (`press`): открывается то же, что левым.
        case left
    }

    /// Порядок путей правой кнопки: `AXShowMenu` (успех — как у `pressWorked`), не вышло — правая кнопка событиями,
    /// не вышло и это — левое нажатие. Без элемента `AXShowMenu` не зовётся.
    public static func secondaryPath(hasElement: Bool, showMenu: () -> Int32, rightClick: () -> Bool) -> SecondaryPath {
        if hasElement, pressWorked(showMenu()) { return .showMenu }
        if rightClick() { return .rightClick }
        return .left
    }

    /// Правая кнопка по значку, как у значков в Доке: меню программы. На фоновой очереди, как `press`; зависшая
    /// программа держит `AXShowMenu` не дольше 1 с (по умолчанию — 6).
    public static func pressSecondary(_ item: Item, after delay: TimeInterval = 0.15) {
        queue.asyncAfter(deadline: .now() + delay) {
            let path = secondaryPath(hasElement: item.element != nil, showMenu: {
                guard let element = item.element else { return -1 }
                AXUIElementSetMessagingTimeout(element, 1)
                return AXUIElementPerformAction(element, kAXShowMenuAction as CFString).rawValue
            }, rightClick: { rightClick(item) })
            if path == .left { press(item, after: 0) }
        }
    }

    /// Окно на экране: номер, процесс, слой.
    public typealias ShownWindow = (id: CGWindowID, pid: pid_t, layer: Int)

    /// Появилось ли меню программы: новое окно на экране у её процесса, не на слое строки меню (25). Окна
    /// «Пункта управления», владельца окон значков, не в счёт: на macOS 26 он сам меняет окна строки меню на клик.
    public static func menuAppeared(before: Set<CGWindowID>, after: [ShownWindow], pid: pid_t) -> Bool {
        after.contains { $0.pid == pid && $0.layer != 25 && !before.contains($0.id) }
    }

    static func shownWindows() -> [ShownWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int else { return nil }
            return (CGWindowID(number), pid_t(pid), info[kCGWindowLayer as String] as? Int ?? 0)
        }
    }

    /// Правая кнопка событиями прямо окну значка: нажатие и отпускание в середину его окна, только процессу-владельцу
    /// окна (без сессии: двойная пара «нажал — отпустил» открыла бы меню и тут же закрыла; в сессии событие с
    /// настоящей точкой под вырезом досталось бы окну записи Диктатора). Меню ждём до 0,6 с, раз в 0,1 с
    /// (Electron-программы открывают его дольше). Только значок под вырезом — у убранного окна нет.
    private static func rightClick(_ item: Item) -> Bool {
        guard movable(item), AXIsProcessTrusted() else { return false }
        let windows = barWindows()
        guard let source = CGEventSource(stateID: .hidSystemState),
              let window = windowID(for: item.frame, in: windows),
              let frame = windows.first(where: { $0.id == window })?.frame,
              let owner = windowOwner(window) else { return false }
        let before = Set(shownWindows().map(\.id))
        let at = CGPoint(x: frame.midX.rounded(), y: frame.midY.rounded())
        let steps: [Step] = [(.rightMouseDown, at, window), (.rightMouseUp, at, window)]
        guard post(steps, button: .right, flags: [], owner: owner, toSession: false, source: source, back: at) else {
            return false
        }
        for _ in 0..<6 {
            if menuAppeared(before: before, after: shownWindows(), pid: item.pid) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return menuAppeared(before: before, after: shownWindows(), pid: item.pid)
    }

    private static func openApp(_ item: Item) {
        guard let url = NSRunningApplication(processIdentifier: item.pid)?.bundleURL
            ?? item.bundleId.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
