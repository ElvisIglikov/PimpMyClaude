import AppKit
import Darwin

// Окна доступа macOS не пропустить (WF91, #7691, #7506). Слово Элвиса 25.09: окно «приложение
// запрашивает доступ» нажимать нельзя (macOS защищает его от программных нажатий — и мы не
// пробуем), но пусть его будет не пропустить на нескольких мониторах: «мигало, за мышкой».
//
// Раз в секунду `CGWindowListCopyWindowInfo` ищет окно системного запроса: владелец — процесс
// `UserNotificationCenter` (TCC: файлы, Автоматизация, камера…), `universalAccessAuthWarn`
// (Универсальный доступ), `SecurityAgent` (пароль администратора, связка ключей), `coreautha`
// (Touch ID), `tccd`. Узнаём по ИСПОЛНЯЕМОМУ файлу процесса: имя владельца в записи
// локализовано и обрезано до 16 символов («Универсальный до»), заголовка окна без права
// «Запись экрана» нет вовсе. Разведка 25.09: живого окна запроса не было — признаки взяты из
// путей на диске (`/System/Library/CoreServices/UserNotificationCenter.app`,
// `LaunchAgents/com.apple.universalaccessAuthWarn.plist`, `Security.framework/…/SecurityAgent`),
// поэтому слой окна не фильтруем (любой ≥ 0), только размер и видимость.
//
// Пока окно висит: вокруг него мигает яркая рамка — четыре тонкие окна-полосы СТРОГО снаружи
// окна запроса (клики насквозь): macOS глушит клики по окну запроса, если его перекрывает чужое
// окно, поэтому над его прямоугольником нашего нет ничего, и плашка на него не ложится. У
// курсора — плашка «macOS ждёт твоего ответа ↗», она едет за курсором на привязи (подойти и
// кликнуть можно); клик переводит курсор в ЦЕНТР ближайшего окна запроса, не на кнопку — жмёт человек.
// Ответил — всё гаснет на следующем опросе. Само окно запроса не двигаем.
// Выключатель — `consentBeaconEnabled` в UserDefaults (нет ключа — включено).
//
// WF98 (#7766, макет 12, кадры 2.1 и 3.1): вместо мигающей рамки и плашки — «окошко из воды» у курсора
// и жидкая фиолетовая рамка вокруг окна запроса, тянутся друг к другу, свёл — «бульк»
// (`ConsentWater.swift`, `ConsentWaterView.swift`). На ОДНОМ мониторе не показываем ничего — окно
// запроса и так на виду (слово Элвиса 26.09 ~07:05). Рамка WF91 осталась запасной: выключатель
// `consentBeaconClassic` или Metal не завёлся. Звук «бульк» — `consentBeaconSound` (нет ключа — включён).

/// Окно системного запроса из записи `CGWindowListCopyWindowInfo`.
struct ConsentWindow: Equatable {
    let number: Int
    let pid: pid_t
    /// Исполняемый файл владельца, по нему узнали.
    let process: String
    let layer: Int
    /// Рамка в координатах CG: начало — левый верхний угол главного монитора, y вниз.
    let bounds: CGRect

    /// Исполняемые файлы системных окон запроса.
    static let processes: Set<String> = ["usernotificationcenter", "universalaccessauthwarn",
                                         "securityagent", "coreautha", "tccd"]
    /// Меньше — служебные окошки владельца (у AccessibilityUIServer, например, окно 0×0).
    static let minSide: CGFloat = 40

    /// Запись окна → окно запроса или nil. `processName` — исполняемый файл по pid (живьём
    /// `proc_pidpath`); не вышло — пробуем имя владельца из записи. `extra` — ещё одно имя
    /// процесса для проверки на окне-двойнике (ключ `consentBeaconTestOwner`).
    static func parse(_ info: [String: Any], ownPID: pid_t, extra: String? = nil,
                      processName: (pid_t) -> String?) -> ConsentWindow? {
        guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
              let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue else { return nil }
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer >= 0 else { return nil }
        if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0.05 { return nil }
        if let onscreen = info[kCGWindowIsOnscreen as String] as? NSNumber, !onscreen.boolValue { return nil }
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
              bounds.width >= minSide, bounds.height >= minSide else { return nil }
        var wanted = processes
        if let extra = extra?.trimmingCharacters(in: .whitespaces).lowercased(), !extra.isEmpty { wanted.insert(extra) }
        let candidates = [processName(pid), info[kCGWindowOwnerName as String] as? String].compactMap { $0 }
        guard let process = candidates.first(where: { wanted.contains($0.lowercased()) }) else { return nil }
        return ConsentWindow(number: number, pid: pid, process: process, layer: layer, bounds: bounds)
    }
}

/// Геометрия рамки и плашки — чистые функции, координаты Cocoa (y вверх), кроме оговорённых.
enum ConsentBeaconGeometry {
    /// Зазор между окном запроса и рамкой и толщина рамки.
    static let gap: CGFloat = 6
    static let thickness: CGFloat = 7
    /// Плашка стоит по диагонали от курсора на этом расстоянии…
    static let offset: CGFloat = 22
    /// …и не двигается, пока курсор ближе к ней этого: к ней можно подойти и кликнуть.
    static let leash: CGFloat = 90
    /// Курсор уже на окне запроса (с этим запасом) — плашка не нужна.
    static let targetMargin: CGFloat = 24
    /// Плашка не подходит к окну запроса ближе этого (с запасом на её тень).
    static let avoidMargin: CGFloat = 16

    /// CG (y вниз от верха главного монитора) → Cocoa (y вверх от низа главного монитора).
    static func cocoaRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Четыре полосы рамки: верх, низ, лево, право — все снаружи окна запроса, через зазор.
    static func ringStrips(around target: NSRect) -> [NSRect] {
        let outer = target.insetBy(dx: -(gap + thickness), dy: -(gap + thickness))
        let sideHeight = target.height + gap * 2
        return [
            NSRect(x: outer.minX, y: target.maxY + gap, width: outer.width, height: thickness),
            NSRect(x: outer.minX, y: outer.minY, width: outer.width, height: thickness),
            NSRect(x: outer.minX, y: target.minY - gap, width: thickness, height: sideHeight),
            NSRect(x: target.maxX + gap, y: target.minY - gap, width: thickness, height: sideHeight),
        ]
    }

    /// Номер окна запроса, ближайшего к курсору; окон нет — nil.
    static func nearest(to cursor: NSPoint, among targets: [NSRect]) -> Int? {
        targets.indices.min { distance(from: cursor, to: targets[$0]) < distance(from: cursor, to: targets[$1]) }
    }

    /// Куда переводить курсор по клику: центр окна запроса, координаты CG (как у Warp).
    static func warpPoint(forCG bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Расстояние от точки до прямоугольника (0 — внутри).
    static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Курсор у ЛЮБОГО окна запроса (с запасом) — плашка не нужна.
    static func showsPlaque(cursor: NSPoint, targets: [NSRect]) -> Bool {
        !targets.contains { $0.insetBy(dx: -targetMargin, dy: -targetMargin).contains(cursor) }
    }

    /// Место плашки. Стоит на мониторе курсора, курсор рядом и окна запроса не задевает —
    /// остаётся (привязь). Иначе — справа-снизу от курсора, у края — с другой стороны, целиком в
    /// `visible`. Запретная зона — окна запроса `avoid` с запасом: задели — другая сторона
    /// курсора, потом сдвиг вдоль края зоны; не выходит — nil, плашку не показываем.
    static func plaqueFrame(current: NSRect?, cursor: NSPoint, size: NSSize, visible: NSRect,
                            avoid: [NSRect] = []) -> NSRect? {
        let zones = avoid.map { $0.insetBy(dx: -avoidMargin, dy: -avoidMargin) }
        let clear = { (rect: NSRect) in visible.contains(rect) && !zones.contains { $0.intersects(rect) } }
        if let current = current, current.size == size, clear(current), distance(from: cursor, to: current) <= leash {
            return current
        }
        let clamp = { (rect: NSRect) -> NSRect in
            NSRect(x: min(max(rect.minX, visible.minX), visible.maxX - size.width),
                   y: min(max(rect.minY, visible.minY), visible.maxY - size.height),
                   width: size.width, height: size.height)
        }
        let right = cursor.x + offset, left = cursor.x - offset - size.width
        let below = cursor.y - offset - size.height, above = cursor.y + offset
        let sides = [(right, below), (left, below), (right, above), (left, above)]
            .map { NSRect(x: $0.0, y: $0.1, width: size.width, height: size.height) }
        var shifted: [NSRect] = []
        for side in sides {
            for zone in zones where zone.intersects(side) {
                shifted += [NSRect(x: zone.maxX, y: side.minY, width: size.width, height: size.height),
                            NSRect(x: zone.minX - size.width, y: side.minY, width: size.width, height: size.height),
                            NSRect(x: side.minX, y: zone.maxY, width: size.width, height: size.height),
                            NSRect(x: side.minX, y: zone.minY - size.height, width: size.width, height: size.height)]
            }
        }
        shifted = shifted.map(clamp).sorted { distance(from: cursor, to: $0) < distance(from: cursor, to: $1) }
        let candidates = sides + sides.map(clamp) + shifted
        return candidates.first { clear($0) && !$0.contains(cursor) }
    }

    /// Стрелка от курсора к окну запроса, восемь сторон.
    static func arrow(from cursor: NSPoint, to target: NSPoint) -> String {
        let dx = target.x - cursor.x, dy = target.y - cursor.y
        guard dx * dx + dy * dy > 1 else { return "↗" }
        let degrees = atan2(dy, dx) * 180 / .pi
        let arrows = ["→", "↗", "↑", "↖", "←", "↙", "↓", "↘"]
        let sector = Int(((degrees + 360 + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return arrows[sector % 8]
    }

    /// Номер монитора, на котором точка; нет такого — nil.
    static func screenIndex(of point: NSPoint, in screens: [NSRect]) -> Int? {
        screens.firstIndex { NSMouseInRect(point, $0, false) }
    }

    /// Строки плашки: главная и подсказка.
    static func lines(arrow: String, otherScreen: Bool) -> [String] {
        ["macOS ждёт твоего ответа \(arrow)" + (otherScreen ? " на соседнем мониторе" : ""),
         "клик — курсор к окну запроса"]
    }
}

/// Маяк окон доступа: опрос, рамки, плашка.
public final class ConsentBeacon {
    /// Выключатель (UserDefaults). Нет ключа — включено.
    public static let enabledKey = "consentBeaconEnabled"
    /// Имя процесса окна-двойника для проверки живьём (например, `osascript` с `display dialog`).
    public static let testOwnerKey = "consentBeaconTestOwner"
    /// Звук «бульк» (UserDefaults). Нет ключа — включён.
    public static let soundKey = "consentBeaconSound"
    /// Вернуть рамку и плашку WF91 вместо воды. Нет ключа — вода.
    public static let classicKey = "consentBeaconClassic"
    static let pollInterval: TimeInterval = 1
    static let followInterval: TimeInterval = 1.0 / 18

    private let defaults: UserDefaults
    private var pollTimer: Timer?
    private var followTimer: Timer?
    private var windows: [ConsentWindow] = []
    private var rings: [Int: [NSWindow]] = [:]
    private var plaque: ConsentPlaquePanel?
    private var plaqueText = ""
    private var names: [pid_t: String] = [:]
    private var water: ConsentWaterOverlay?
    /// Metal не завёлся — до перезапуска рамка WF91.
    private var waterFailed = false
    private var style = ConsentBeaconStyle.idle

    /// Сколько раз появлялось окно запроса и сколько раз переводили курсор — для диагностики.
    public private(set) var appearances = 0
    public private(set) var warps = 0
    /// `<появлений>/<on|off>/<окон сейчас>[:процесс@слой][/<single|water|classic>]` — вид, пока висит запрос.
    public var status: String {
        let first = windows.first.map { ":\($0.process)@\($0.layer)" } ?? ""
        let shown = style == .idle ? "" : "/\(style.rawValue)"
        return "\(appearances)/\(isEnabled ? "on" : "off")/\(windows.count)\(first)\(shown)"
    }

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool { ConsentBeacon.isEnabled(in: defaults) }

    /// Включён ли маяк: нет ключа — включено. Одно правило на маяк и выключатель у часов.
    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    public func start() {
        stop()
        let timer = Timer(timeInterval: ConsentBeacon.pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Опрос раз в `pollInterval` в покое и раз в `pollFast`, пока висит окно запроса.
    static let pollFast: TimeInterval = 0.25
    private func retime(fast: Bool) {
        guard let current = pollTimer else { return }
        let wanted = fast ? ConsentBeacon.pollFast : ConsentBeacon.pollInterval
        guard current.timeInterval != wanted else { return }
        current.invalidate()
        let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        update([])
        water?.stop()
    }

    // MARK: - опрос

    private func poll() {
        guard isEnabled else { return update([]) }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let own = getpid()
        let extra = defaults.string(forKey: ConsentBeacon.testOwnerKey)
        let found = list.compactMap { ConsentWindow.parse($0, ownPID: own, extra: extra, processName: processName) }
        let alive = Set(list.compactMap { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value })
        names = names.filter { alive.contains($0.key) }
        update(found)
    }

    /// Исполняемый файл процесса по pid; кэш живёт, пока процесс в списке окон.
    private func processName(_ pid: pid_t) -> String? {
        if let name = names[pid] { return name }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = (String(cString: buffer) as NSString).lastPathComponent
        names[pid] = name
        return name
    }

    private func update(_ found: [ConsentWindow]) {
        if windows.isEmpty && !found.isEmpty { appearances += 1 }
        // Пока окно запроса висит, спрашиваем чаще: ответил — маяк гаснет почти сразу (#8122).
        retime(fast: !found.isEmpty)
        windows = found
        style = ConsentBeaconStyle.choose(hasTargets: !found.isEmpty, screenCount: NSScreen.screens.count,
                                          classic: defaults.bool(forKey: ConsentBeacon.classicKey),
                                          waterAvailable: !waterFailed)
        switch style {
        case .idle:
            hideClassic()
            water?.fade()
        case .single:
            hideClassic()
            water?.stop()
        case .water:
            hideClassic()
            if water == nil {
                guard let overlay = ConsentWaterOverlay() else {
                    waterFailed = true
                    return update(found)
                }
                overlay.onClick = { [weak self] in self?.warpToTarget() }
                overlay.soundEnabled = { [weak self] in
                    self?.defaults.object(forKey: ConsentBeacon.soundKey) as? Bool ?? true
                }
                water = overlay
            }
            water?.show(found, calm: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        case .classic:
            water?.stop()
            updateClassic(found)
        }
    }

    /// Рамка и плашка WF91 — убрать.
    private func hideClassic() {
        rings.values.forEach { $0.forEach { $0.orderOut(nil) } }
        rings = [:]
        followTimer?.invalidate()
        followTimer = nil
        plaque?.orderOut(nil)
        plaque = nil
        plaqueText = ""
    }

    /// Рамка и плашка WF91 (запасной вид).
    private func updateClassic(_ found: [ConsentWindow]) {
        let numbers = Set(found.map { $0.number })
        for (number, strips) in rings where !numbers.contains(number) {
            strips.forEach { $0.orderOut(nil) }
            rings[number] = nil
        }
        guard !found.isEmpty else {
            followTimer?.invalidate()
            followTimer = nil
            plaque?.orderOut(nil)
            plaque = nil
            plaqueText = ""
            return
        }
        let primary = primaryHeight
        for window in found {
            let frames = ConsentBeaconGeometry.ringStrips(
                around: ConsentBeaconGeometry.cocoaRect(fromCG: window.bounds, primaryHeight: primary))
            let strips = rings[window.number] ?? frames.map { _ in makeStrip() }
            rings[window.number] = strips
            for (strip, frame) in zip(strips, frames) {
                if strip.frame != frame { strip.setFrame(frame, display: true) }
                strip.orderFrontRegardless()
            }
        }
        if followTimer == nil {
            let timer = Timer(timeInterval: ConsentBeacon.followInterval, repeats: true) { [weak self] _ in self?.follow() }
            RunLoop.main.add(timer, forMode: .common)
            followTimer = timer
        }
        follow()
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    // MARK: - плашка у курсора

    /// Окна запроса в координатах Cocoa, по порядку `windows`.
    private var targetRects: [NSRect] {
        let primary = primaryHeight
        return windows.map { ConsentBeaconGeometry.cocoaRect(fromCG: $0.bounds, primaryHeight: primary) }
    }

    private func follow() {
        let cursor = NSEvent.mouseLocation
        let targets = targetRects
        guard let nearest = ConsentBeaconGeometry.nearest(to: cursor, among: targets) else { return }
        let targetRect = targets[nearest]
        let screens = NSScreen.screens
        guard ConsentBeaconGeometry.showsPlaque(cursor: cursor, targets: targets),
              let index = ConsentBeaconGeometry.screenIndex(of: cursor, in: screens.map { $0.frame }) else {
            plaque?.orderOut(nil)
            return
        }
        let other = ConsentBeaconGeometry.screenIndex(
            of: NSPoint(x: targetRect.midX, y: targetRect.midY), in: screens.map { $0.frame }) != index
        let arrow = ConsentBeaconGeometry.arrow(from: cursor, to: NSPoint(x: targetRect.midX, y: targetRect.midY))
        let lines = ConsentBeaconGeometry.lines(arrow: arrow, otherScreen: other)
        let panel = plaque ?? makePlaque()
        plaque = panel
        let text = lines.joined(separator: "\n")
        if text != plaqueText {
            plaqueText = text
            panel.show(lines: lines)
        }
        let current: NSRect? = panel.isVisible ? panel.frame : nil
        guard let frame = ConsentBeaconGeometry.plaqueFrame(current: current, cursor: cursor, size: panel.frame.size,
                                                            visible: screens[index].visibleFrame, avoid: targets) else {
            panel.orderOut(nil)
            return
        }
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Клик по плашке: курсор — в центр окна запроса. Кнопку жмёт человек.
    private func warpToTarget() {
        guard let nearest = ConsentBeaconGeometry.nearest(to: NSEvent.mouseLocation, among: targetRects) else { return }
        CGWarpMouseCursorPosition(ConsentBeaconGeometry.warpPoint(forCG: windows[nearest].bounds))
        // Warp глушит мышь на четверть секунды — возвращаем сразу.
        CGAssociateMouseAndMouseCursorPosition(1)
        warps += 1
        if style == .classic { follow() }
    }

    // MARK: - окна

    /// Одна полоса рамки: своё окно, клики насквозь.
    private func makeStrip() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = ConsentStripView(frame: .zero)
        return window
    }

    private func makePlaque() -> ConsentPlaquePanel {
        let panel = ConsentPlaquePanel()
        panel.onClick = { [weak self] in self?.warpToTarget() }
        return panel
    }
}

/// Мигающая полоса рамки: залита целиком, без тени (тень за край окна не выходит, а на мигании
/// без `shadowPath` её пересчёт — лишняя работа каждый кадр).
private final class ConsentStripView: NSView {
    private let fill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        fill.backgroundColor = NSColor.systemOrange.cgColor
        layer?.addSublayer(fill)
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0.15
        blink.duration = 0.45
        blink.autoreverses = true
        blink.repeatCount = .infinity
        fill.add(blink, forKey: "blink")
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        CATransaction.commit()
    }
}

/// Плашка у курсора: не забирает фокус у окна запроса, ловит только клик.
private final class ConsentPlaquePanel: NSPanel {
    var onClick: () -> Void = {}
    private let box = ConsentPlaqueView(frame: .zero)

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = false
        // Без тени окна: защита macOS от перекрытия может считать и её — ничего нашего рядом с окном запроса.
        hasShadow = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        box.onClick = { [weak self] in self?.onClick() }
        contentView = box
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(lines: [String]) {
        let text = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let head = index == 0
            text.append(NSAttributedString(string: (head ? "" : "\n") + line, attributes: [
                .font: head ? NSFont.systemFont(ofSize: 16, weight: .bold) : NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: head ? NSColor.white : NSColor.white.withAlphaComponent(0.85),
            ]))
        }
        let label = NSTextField(labelWithAttributedString: text)
        label.maximumNumberOfLines = 0
        label.sizeToFit()
        let padding = NSSize(width: 16, height: 10)
        let size = NSSize(width: ceil(label.frame.width) + padding.width * 2,
                          height: ceil(label.frame.height) + padding.height * 2)
        box.subviews.forEach { $0.removeFromSuperview() }
        label.frame = NSRect(origin: NSPoint(x: padding.width, y: padding.height), size: label.frame.size)
        box.addSubview(label)
        setContentSize(size)
    }
}

private final class ConsentPlaqueView: NSView {
    var onClick: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 10
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 2
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
