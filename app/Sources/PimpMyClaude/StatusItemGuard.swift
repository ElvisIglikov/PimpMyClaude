import AppKit
import ClaudeAX
import UserNotifications

/// Сторож значка PMP у часов (#10016, слово Элвиса 16.10.2026: «в трее не видно… за ней прячется всё, иконки не
/// влезают»). На Маке с вырезом macOS молча прячет значки, которым не хватило места справа от выреза. Сторож замечает
/// это по геометрии окна кнопки, сперва ужимает значок до плашки «PMP», не помогло — ставит плашку PMP под строкой
/// меню (нажатие — та же панель) и раз в сутки говорит уведомлением, как вернуть значок. Значок снова виден — плашка
/// уходит, вид значка возвращается к выбранному, как только он помещается.
///
/// Замер на Маке с вырезом, macOS 26 (17.10.2026): спрятанный значок стоит под вырезом (окно кнопки x 663 при вырезе
/// 642…798), `occlusionState` без `.visible`; видимый — справа от выреза, `.visible`. Решает геометрия: занавес
/// `occlusionState` падает и у видимого значка, когда строка меню спрятана (полный экран, «скрывать строку меню»), —
/// по нему плашка выскакивала бы зря. Уведомления окна (заслонено, сдвинуто) только будят проверку.

// MARK: - геометрия

/// Экран глазами сторожа: кадр и области строки меню слева и справа от выреза (`auxiliaryTopLeftArea` /
/// `auxiliaryTopRightArea`; у экрана без выреза обеих нет).
struct MenuBarScreen: Equatable {
    var frame: CGRect
    var leftArea: CGRect?
    var rightArea: CGRect?

    init(frame: CGRect, leftArea: CGRect? = nil, rightArea: CGRect? = nil) {
        self.frame = frame
        self.leftArea = leftArea
        self.rightArea = rightArea
    }

    init(_ screen: NSScreen) {
        self.init(frame: screen.frame, leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }

    /// Вырез: между левой и правой областью, по их высоте.
    var notch: CGRect? {
        guard let left = leftArea, let right = rightArea, right.minX > left.maxX else { return nil }
        let bottom = min(left.minY, right.minY)
        return CGRect(x: left.maxX, y: bottom, width: right.minX - left.maxX, height: frame.maxY - bottom)
    }
}

/// Виден ли значок в строке меню.
enum StatusItemPlace: Equatable {
    enum Reason: Equatable {
        /// Под вырезом или левее него: справа места не хватило.
        case notch
        /// Окно кнопки вне всех экранов.
        case offscreen
        /// Окно кнопки или сам значок не показаны.
        case notShown
    }

    case visible
    case hidden(Reason)
    /// Окна ещё нет или у него нулевой размер — строка меню не разложила значок, судить рано.
    case unknown

    /// Допуск на дробные края кадра.
    static let slack: CGFloat = 2

    /// Значок справа от выреза целиком — виден; задел вырез или левее — спрятан (macOS не рисует значки левее
    /// выреза). Экран без выреза — виден, пока кадр на экране.
    static func of(_ frame: CGRect?, shown: Bool, screens: [MenuBarScreen]) -> StatusItemPlace {
        guard shown else { return .hidden(.notShown) }
        guard let frame = frame, frame.width > 0, frame.height > 0 else { return .unknown }
        // Экран, на котором больше всего кадра.
        var host: MenuBarScreen?
        var best: CGFloat = 0
        for screen in screens {
            let common = screen.frame.intersection(frame)
            guard !common.isNull else { continue }
            let area: CGFloat = common.width * common.height
            if area > best {
                best = area
                host = screen
            }
        }
        guard let screen = host else { return .hidden(.offscreen) }
        if let right = screen.rightArea, screen.notch != nil {
            let inside = frame.minX >= right.minX - slack && frame.maxX <= right.maxX + slack
            return inside ? .visible : .hidden(.notch)
        }
        let inside = frame.minX >= screen.frame.minX - slack && frame.maxX <= screen.frame.maxX + slack
        return inside ? .visible : .hidden(.offscreen)
    }

    /// Поместится ли значок шире на `extra` pt: правый край стоит (значки справа не двигаются), растёт влево.
    static func fits(_ frame: CGRect?, extra: CGFloat, screens: [MenuBarScreen]) -> Bool {
        guard let frame = frame else { return false }
        let grow = max(0, extra) + slack
        let wider = CGRect(x: frame.minX - grow, y: frame.minY, width: frame.width + grow, height: frame.height)
        return of(wider, shown: true, screens: screens) == .visible
    }
}

// MARK: - решение

/// Что делать по замеру: ужать значок, поставить или убрать плашку, вернуть вид. Чистая логика — тесты гоняют её
/// без строки меню.
struct StatusItemGuardLogic: Equatable {
    /// Широкий вид вытолкнул значок обратно — столько не пробуем снова (или до смены экранов).
    static let retryFullAfter: TimeInterval = 3600

    enum Action: Equatable {
        /// Значок — одна плашка PMP (самый узкий вид).
        case compact
        /// Вид, выбранный человеком.
        case full
        case showTab
        case hideTab
        /// Проверить ещё раз, когда строка меню разложит значок по-новому.
        case recheckSoon
    }

    private(set) var compact = false
    private(set) var tabShown = false
    /// Сколько замеров подряд значок спрятан: плашка — со второго, один замер мог застать перекладку.
    private(set) var hiddenStreak = 0
    /// Только что вернули широкий вид — следующий замер покажет, поместился ли он.
    private(set) var expanding = false
    private(set) var fullBlockedUntil: Date?

    /// `canShrink` — узкий вид уже выбранного; `fitsFull` — в узком виде и виден: широкий тоже поместится.
    mutating func observe(_ place: StatusItemPlace, canShrink: Bool, fitsFull: Bool, now: Date) -> [Action] {
        switch place {
        case .unknown:
            return []
        case .visible:
            hiddenStreak = 0
            expanding = false
            var out: [Action] = []
            if tabShown {
                tabShown = false
                out.append(.hideTab)
            }
            if compact, fitsFull, fullBlockedUntil.map({ now >= $0 }) ?? true {
                compact = false
                expanding = true
                fullBlockedUntil = nil
                out += [.full, .recheckSoon]
            }
            return out
        case .hidden:
            if expanding {
                // Широкий вид не влез, хотя по расчёту должен был: назад в узкий и час не пробуем.
                expanding = false
                compact = true
                fullBlockedUntil = now.addingTimeInterval(Self.retryFullAfter)
                return [.compact, .recheckSoon]
            }
            hiddenStreak += 1
            if !compact, canShrink {
                compact = true
                return [.compact, .recheckSoon]
            }
            if tabShown { return [] }
            if hiddenStreak >= 2 {
                tabShown = true
                return [.showTab]
            }
            return [.recheckSoon]
        }
    }

    /// Экраны сменились: прежний отказ широкому виду больше ничего не значит.
    mutating func screensChanged() {
        fullBlockedUntil = nil
    }
}

// MARK: - уведомление

/// Одно уведомление в сутки, когда встала плашка: где значок и как его вернуть.
enum StatusItemNotice {
    static let lastKey = "statusItemHiddenNoticeAt"
    static let category = "statusItemHidden"
    static let every: TimeInterval = 86_400
    private static let requestID = "status-item-hidden"

    static func due(last: Date?, now: Date) -> Bool {
        guard let last = last else { return true }
        return now.timeIntervalSince(last) >= every
    }

    static func title(_ reason: StatusItemPlace.Reason) -> String {
        reason == .notch ? "Значок PMP спрятан за вырезом экрана" : "Значок PMP не поместился в строке меню"
    }

    /// Сам спрятанный значок не перетащить — место освобождают соседи: ненужный уходит под вырез или выключается.
    static let body = "Освободи место: держи ⌘ и перетащи ненужный значок левее, под вырез, или выключи его "
        + "в Системных настройках → Строка меню. Пока панель открывают плашка PMP справа вверху "
        + "и кнопка PMP в окне Claude."

    /// Пора — помечаем срок сразу и отвечаем «да»: без разрешения на уведомления не пробуем каждую минуту.
    static func claim(defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        guard due(last: defaults.object(forKey: lastKey) as? Date, now: now) else { return false }
        defaults.set(now, forKey: lastKey)
        return true
    }

    static func postIfDue(_ reason: StatusItemPlace.Reason) {
        guard claim(), let center = Notifier.center else { return }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional: break
            default: return
            }
            let content = UNMutableNotificationContent()
            content.title = title(reason)
            content.body = body
            content.categoryIdentifier = category
            center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: nil))
        }
    }

    static func clear() {
        Notifier.center?.removeDeliveredNotifications(withIdentifiers: [requestID])
    }
}

// MARK: - плашка

/// Кнопка плашки. Наследник `NSStatusBarButton`, чтобы панель открывалась от неё тем же `open(from:)`, что от значка:
/// панель берёт кадр окна кнопки и подсвечивает её `highlight`. Нажатие — панель, перетаскивание — новое место,
/// правый клик или ⌃ — короткое меню значка.
final class StatusItemTabButton: NSStatusBarButton {
    static let size = NSSize(width: 40, height: 26)
    /// Дальше этого — уже перетаскивание, а не нажатие.
    static let dragThreshold: CGFloat = 3

    var badge: NSImage? { didSet { needsDisplay = true } }
    var accent = PMPAccent.current.nsColor { didSet { needsDisplay = true } }
    private(set) var hovered = false { didSet { needsDisplay = true } }
    /// Панель открыта от плашки (`highlight`).
    private(set) var pressed = false { didSet { needsDisplay = true } }

    var onClick: () -> Void = {}
    var onMenu: (NSEvent) -> Void = { _ in }
    /// Отпустили после перетаскивания — запомнить место.
    var onMoved: (NSPoint) -> Void = { _ in }
    /// Куда окно может встать (в пределах экрана).
    var clampOrigin: (NSPoint) -> NSPoint = { $0 }

    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = ""
        imagePosition = .noImage
        setAccessibilityLabel("PMP — открыть панель")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не нужен") }

    override var wantsUpdateLayer: Bool { false }
    override var allowsVibrancy: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func highlight(_ flag: Bool) {
        pressed = flag
    }

    /// Состояния для кадров (тесты): наведение и «панель открыта».
    func show(hovered: Bool, pressed: Bool) {
        self.hovered = hovered
        self.pressed = pressed
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: hovered || pressed ? 0.94 : 0.8).setFill()
        path.fill()
        path.lineWidth = 1
        (pressed ? accent : NSColor.white.withAlphaComponent(hovered ? 0.24 : 0.13)).setStroke()
        path.stroke()
        guard let badge = badge else { return }
        let place = NSRect(x: round((bounds.width - badge.size.width) / 2), y: round((bounds.height - badge.size.height) / 2),
                           width: badge.size.width, height: badge.size.height)
        badge.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onMenu(event)
            return
        }
        guard let window = window else { return }
        let start = NSEvent.mouseLocation
        let origin = window.frame.origin
        var dragged = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type != .leftMouseUp {
            let now = NSEvent.mouseLocation
            let dx = now.x - start.x, dy = now.y - start.y
            if !dragged, hypot(dx, dy) < Self.dragThreshold { continue }
            dragged = true
            window.setFrameOrigin(clampOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)))
        }
        if dragged { onMoved(window.frame.origin) } else { onClick() }
    }

    override func rightMouseDown(with event: NSEvent) {
        onMenu(event)
    }
}

/// Окно плашки: поверх окон, на всех рабочих столах (кроме полноэкранных — там строки меню и так нет),
/// фокус не берёт.
final class StatusItemTabWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Плашка PMP под строкой меню справа: место — отступ от правого верхнего угла экрана, перетащили — запоминается.
final class StatusItemTab {
    static let offsetKey = "statusItemTabOffset"
    /// Отступ от правого края экрана и от низа строки меню по умолчанию.
    static let edge: CGFloat = 10
    static let gap: CGFloat = 6

    let button = StatusItemTabButton(frame: NSRect(origin: .zero, size: StatusItemTabButton.size))
    private var window: StatusItemTabWindow?
    private var screenFrame: CGRect = .zero
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        button.onMoved = { [weak self] origin in self?.remember(origin) }
        button.clampOrigin = { [weak self] origin in
            guard let self = self else { return origin }
            return Self.clamp(origin, size: StatusItemTabButton.size, screen: self.screenFrame)
        }
    }

    var isShown: Bool { window?.isVisible == true }

    func update(badge: NSImage, accent: NSColor, toolTip: String) {
        button.badge = badge
        button.accent = accent
        button.toolTip = toolTip
    }

    func show(on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.screens.first else { return }
        screenFrame = screen.frame
        let window = self.window ?? make()
        self.window = window
        let size = StatusItemTabButton.size
        let origin = Self.origin(offset: savedOffset, size: size, screen: screen.frame,
                                 menuBar: Self.menuBarHeight(screen))
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        guard !window.isVisible else { return }
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        button.highlight(false)
        window?.orderOut(nil)
    }

    private func make() -> StatusItemTabWindow {
        let window = StatusItemTabWindow(contentRect: NSRect(origin: .zero, size: StatusItemTabButton.size),
                                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = button
        return window
    }

    // MARK: место

    /// Высота строки меню: по видимой области экрана; строка прячется сама — по вырезу (`safeAreaInsets`), иначе 24.
    static func menuBarHeight(_ screen: NSScreen) -> CGFloat {
        max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, 24)
    }

    /// Отступ хранится от правого верхнего угла экрана — переживает смену разрешения и другой экран.
    private var savedOffset: CGPoint? {
        guard let pair = defaults.array(forKey: Self.offsetKey) as? [Double], pair.count == 2 else { return nil }
        return CGPoint(x: pair[0], y: pair[1])
    }

    private func remember(_ origin: NSPoint) {
        let offset = Self.offset(of: origin, size: StatusItemTabButton.size, screen: screenFrame)
        defaults.set([Double(offset.x), Double(offset.y)], forKey: Self.offsetKey)
    }

    /// Отступ правого верхнего угла плашки от правого верхнего угла экрана.
    static func offset(of origin: CGPoint, size: CGSize, screen: CGRect) -> CGPoint {
        CGPoint(x: screen.maxX - (origin.x + size.width), y: screen.maxY - (origin.y + size.height))
    }

    /// Место плашки: сохранённый отступ или справа под строкой меню; всегда целиком на экране.
    static func origin(offset: CGPoint?, size: CGSize, screen: CGRect, menuBar: CGFloat) -> CGPoint {
        let offset = offset ?? CGPoint(x: edge, y: menuBar + gap)
        let origin = CGPoint(x: screen.maxX - offset.x - size.width, y: screen.maxY - offset.y - size.height)
        return clamp(origin, size: size, screen: screen)
    }

    static func clamp(_ origin: CGPoint, size: CGSize, screen: CGRect) -> CGPoint {
        guard screen.width > size.width, screen.height > size.height else { return origin }
        return CGPoint(x: min(max(origin.x, screen.minX), screen.maxX - size.width),
                       y: min(max(origin.y, screen.minY), screen.maxY - size.height))
    }
}

// MARK: - сторож

/// Проводка: замер на старте, при смене экранов, после пробуждения, при смене ширины значка, по уведомлениям окна
/// кнопки (заслонено, сдвинуто) и раз в минуту.
final class StatusItemGuard {
    static let checkEvery: TimeInterval = 60
    /// Строка меню раскладывает значок не сразу — столько ждём после своей перемены.
    static let settle: TimeInterval = 1.5

    private weak var item: NSStatusItem?
    private var logic = StatusItemGuardLogic()
    private let tab = StatusItemTab()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var wakeObserver: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    /// Что нарисовано на плашке — новая картинка только при смене вида или цвета.
    private var tabLook: (look: StatusIcon.Look, accent: NSColor)?
    private var fullWidth: CGFloat = 0
    private var compactWidth: CGFloat = 0
    private var reason: StatusItemPlace.Reason = .notch

    /// Узкий вид встал или ушёл — перерисовать значок.
    var onCompactChange: () -> Void = {}
    /// Нажали плашку — панель от её кнопки.
    var onTabClick: (NSStatusBarButton) -> Void = { _ in }
    /// Правый клик по плашке — короткое меню значка.
    var onTabMenu: (NSEvent, NSView) -> Void = { _, _ in }

    init(item: NSStatusItem) {
        self.item = item
        tab.button.onClick = { [weak self] in
            guard let self = self else { return }
            self.onTabClick(self.tab.button)
        }
        tab.button.onMenu = { [weak self] event in
            guard let self = self else { return }
            self.onTabMenu(event, self.tab.button)
        }
    }

    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        wakeObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    /// Плашка стоит — панель открывается от неё, иначе от значка.
    var anchor: NSStatusBarButton? { tab.isShown ? tab.button : nil }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            self?.logic.screensChanged()
            self?.schedule(after: Self.settle)
        })
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self = self, let window = note.object as? NSWindow,
                      window === self.item?.button?.window else { return }
                self.schedule(after: 0.3)
            })
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.schedule(after: Self.settle)
        }
        let tick = Timer(timeInterval: Self.checkEvery, repeats: true) { [weak self] _ in self?.check() }
        tick.tolerance = 15
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        schedule(after: 2)
    }

    /// Вид для значка: узкий, пока сторож его держит. Ширина вида сменилась — замер заново.
    func shown(_ look: StatusIcon.Look, accent: NSColor) -> StatusIcon.Look {
        let narrow = StatusIcon.badgeOnly(look)
        let full = StatusIconArt.width(look)
        let compact = StatusIconArt.width(narrow)
        if full != fullWidth || compact != compactWidth {
            let first = fullWidth == 0
            fullWidth = full
            compactWidth = compact
            if !first { schedule(after: 0.6) }
        }
        if tabLook?.look != narrow || tabLook?.accent != accent {
            tabLook = (narrow, accent)
            tab.update(badge: StatusIconArt.image(narrow, dark: true, accent: accent), accent: accent,
                       toolTip: Self.tabToolTip(reason))
        }
        return logic.compact ? narrow : look
    }

    static func tabToolTip(_ reason: StatusItemPlace.Reason) -> String {
        let place = reason == .notch ? "спрятан за вырезом экрана" : "не поместился в строке меню"
        return "Значок PMP \(place). Нажми — откроется панель. Вернуть значок: держи ⌘ и перетащи ненужный значок "
            + "левее, под вырез, или выключи его в Системных настройках → Строка меню."
    }

    private func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func check() {
        guard let item = item, let button = item.button else { return }
        let window = button.window
        let screens = NSScreen.screens.map(MenuBarScreen.init)
        let shown = item.isVisible && window?.isVisible != false
        let place = StatusItemPlace.of(window?.frame, shown: shown, screens: screens)
        let fits = !logic.compact || StatusItemPlace.fits(window?.frame, extra: fullWidth - compactWidth, screens: screens)
        if case .hidden(let why) = place { reason = why }
        let wasCompact = logic.compact
        for action in logic.observe(place, canShrink: compactWidth < fullWidth - 0.5, fitsFull: fits, now: Date()) {
            switch action {
            case .compact, .full:
                break
            case .showTab:
                tab.button.toolTip = Self.tabToolTip(reason)
                tab.show(on: window?.screen)
                StatusItemNotice.postIfDue(reason)
            case .hideTab:
                tab.hide()
                StatusItemNotice.clear()
            case .recheckSoon:
                schedule(after: Self.settle)
            }
        }
        if logic.compact != wasCompact { onCompactChange() }
    }
}
