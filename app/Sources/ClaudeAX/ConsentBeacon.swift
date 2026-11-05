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
// (`ConsentWater.swift`, `ConsentWaterView.swift`). На ОДНОМ мониторе до 11.10.2026 не показывали ничего
// (слово Элвиса 26.09 ~07:05); с его слова 11.10 02:25 (#9661) пузырёк со стрелкой — и на одном мониторе.
// Запасная оранжевая рамка WF91 (включалась скрытым ключом без ручки) снята по ревизии 16.10 (вопрос 12): Metal не
// завёлся — маяк ничего не рисует. Звук «бульк» — `consentBeaconSound` (нет ключа — включён).

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
    /// Системные настройки (#9844, слово Элвиса 12.10.2026 ~01:25: «стрелочка не слипается вот этого разрешение на
    /// управление… системного окна»): вопросы права — «Закрыть и открыть снова» после «Управления приложениями»,
    /// пароль к переключателю — macOS ставит листом самих Настроек, их владелец не из `processes`, и стрелка тянулась к
    /// другому окну. Берём только маленькие окна Настроек — лист и алерт; главное окно (от ~700 pt) — не запрос.
    static let settingsProcess = "system settings"
    static let settingsMaxSide: CGFloat = 560
    static let settingsMinSide: CGFloat = 120

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
        // Меню, подсказки и всплывашки Настроек (слои выше 8, мелкие) — не запрос.
        if [0, 8].contains(layer), bounds.width >= settingsMinSide, bounds.height >= settingsMinSide,
           bounds.width <= settingsMaxSide, bounds.height <= settingsMaxSide { wanted.insert(settingsProcess) }
        let candidates = [processName(pid), info[kCGWindowOwnerName as String] as? String].compactMap { $0 }
        guard let process = candidates.first(where: { wanted.contains($0.lowercased()) }) else { return nil }
        return ConsentWindow(number: number, pid: pid, process: process, layer: layer, bounds: bounds)
    }

    /// Исполняемый файл процесса по pid; не узнали — nil.
    static func executableName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return (String(cString: buffer) as NSString).lastPathComponent
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

/// Маяк окон доступа: опрос и «окошко из воды».
public final class ConsentBeacon {
    /// Выключатель (UserDefaults). Нет ключа — включено.
    public static let enabledKey = "consentBeaconEnabled"
    /// Имя процесса окна-двойника для проверки живьём (например, `osascript` с `display dialog`).
    public static let testOwnerKey = "consentBeaconTestOwner"
    /// Звук «бульк» (UserDefaults). Нет ключа — включён.
    public static let soundKey = "consentBeaconSound"
    static let pollInterval: TimeInterval = 1

    private let defaults: UserDefaults
    private var pollTimer: Timer?
    private var windows: [ConsentWindow] = []
    private var names: [pid_t: String] = [:]
    private var water: ConsentWaterOverlay?
    /// Metal не завёлся — до перезапуска маяк ничего не рисует.
    private var waterFailed = false
    private var style = ConsentBeaconStyle.idle

    /// Сколько раз появлялось окно запроса и сколько раз переводили курсор — для диагностики.
    public private(set) var appearances = 0
    public private(set) var warps = 0
    /// `<появлений>/<on|off>/<окон сейчас>[:процесс@слой][/<water|no-metal>]` — вид, пока висит запрос.
    public var status: String {
        let first = windows.first.map { ":\($0.process)@\($0.layer)" } ?? ""
        let shown = style == .idle ? "" : "/\(style.rawValue)"
        return "\(appearances)/\(isEnabled ? "on" : "off")/\(windows.count)\(first)\(shown)"
    }

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Висит окно запроса macOS — маяк входа на сайт (WF302) на это время уступает.
    public var isShowing: Bool { !windows.isEmpty }

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
        guard let name = ConsentWindow.executableName(pid) else { return nil }
        names[pid] = name
        return name
    }

    private func update(_ found: [ConsentWindow]) {
        if windows.isEmpty && !found.isEmpty { appearances += 1 }
        // Пока окно запроса висит, спрашиваем чаще: ответил — маяк гаснет почти сразу (#8122).
        retime(fast: !found.isEmpty)
        windows = found
        style = ConsentBeaconStyle.choose(hasTargets: !found.isEmpty, waterAvailable: !waterFailed)
        switch style {
        case .idle:
            water?.fade()
        case .water:
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
        case .noMetal:
            break
        }
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    // MARK: - окна запроса

    /// Окна запроса в координатах Cocoa, по порядку `windows`.
    private var targetRects: [NSRect] {
        let primary = primaryHeight
        return windows.map { ConsentBeaconGeometry.cocoaRect(fromCG: $0.bounds, primaryHeight: primary) }
    }

    /// Клик по плашке: курсор — в центр окна запроса. Кнопку жмёт человек.
    private func warpToTarget() {
        guard let nearest = ConsentBeaconGeometry.nearest(to: NSEvent.mouseLocation, among: targetRects) else { return }
        CGWarpMouseCursorPosition(ConsentBeaconGeometry.warpPoint(forCG: windows[nearest].bounds))
        // Warp глушит мышь на четверть секунды — возвращаем сразу.
        CGAssociateMouseAndMouseCursorPosition(1)
        warps += 1
    }
}
