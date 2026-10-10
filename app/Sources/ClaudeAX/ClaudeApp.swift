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

    /// Экраны для умной расстановки (план WF77): полная рамка — по ней ловится центр окна,
    /// рабочая область — по ней считается сетка. Обе в перевёрнутых координатах.
    /// Разделять их обязательно (критик WF77 зам. 13): окно, заехавшее под док, по
    /// `visibleFrame` оказалось бы «ни на одном экране».
    static func all() -> [(full: CGRect, usable: CGRect)] {
        NSScreen.screens.map { (full: flip(rect: $0.frame), usable: flip(rect: $0.visibleFrame)) }
    }

    /// Кому какой экран (план WF77): для каждой рамки — индекс экрана, внутри которого
    /// лежит её ЦЕНТР; ни одного попадания — 0, экран с меню-баром. Чистая — её и гоняют
    /// тесты. Окна между экранами не переезжают, каждая группа расставляется у себя.
    static func assign(screens: [CGRect], frames: [CGRect]) -> [Int] {
        frames.map { frame in
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return screens.firstIndex { $0.contains(center) } ?? 0
        }
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
    /// `kCGWindowIsOnscreen` (WF111): спрятанное окно Electron (закрытое главное, закрытый попап)
    /// лежит в выдаче всех Spaces, но не на экране. Выдача «только на экране» — всегда true.
    var onScreen = true
}

/// Запущенный процесс Claude глазами выбора экземпляра (#7096): живьём его собирает
/// `ClaudeApp.liveInstances()` из `NSRunningApplication`, в тестах — руками.
struct ClaudeInstance: Equatable {
    let pid: pid_t
    /// Путь бандла, приведённый как у `Patcher.runningClaude` (симлинки раскрыты, путь
    /// нормализован); nil — система его не сказала.
    let path: String?
    let launchDate: Date?
}

/// Поиск Claude и его окон. Приложение ищется по bundle id (решение 1 плана), имя —
/// запасной вариант, как в `claude_noquit.lua`.
final class ClaudeApp {
    static let bundleID = "com.anthropic.claudefordesktop"
    static let name = "Claude"

    /// Вызывается, когда Claude перезапустился (сменился pid) или выбор переехал на другой
    /// запущенный Claude (#7096): кэши прямоугольников стали мусором (грабли из
    /// claude_minimize_menu.lua, «windows=0» после ⌘Q).
    var onRestart: (() -> Void)?

    /// Запущенные Claude (#7096). Живьём — `NSWorkspace`, тест подаёт свой список.
    var instances: () -> [ClaudeInstance] = ClaudeApp.liveInstances
    /// У каких процессов есть окна на экране. Спрашивается, только когда выбирать есть из кого.
    var windowOwners: () -> Set<pid_t> = ClaudeApp.liveWindowOwners
    /// Часы сверки выбора — тест подставляет свои.
    var clock: () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    /// Рядом появился лишний Claude — не тот, с которым работаем: его процесс и сколько Claude
    /// запущено всего. Зовётся один раз на каждое появление; плашку ставит `ClaudeAXController`
    /// (критик WF82 п. 4). Чужой процесс приложение не закрывает.
    var onDuplicate: ((ClaudeInstance, Int) -> Void)?

    /// Тот Claude, с которым работаем, и сколько их запущено всего — на последней сверке.
    private(set) var chosen: ClaudeInstance?
    private(set) var instanceCount = 0
    /// Лишние процессы, о которых уже сказали плашкой. Ушедший забывается: запустят снова —
    /// скажем снова.
    private var announced: Set<pid_t> = []

    private var cachedApp: NSRunningApplication?
    private var cachedElement: AXUIElement?
    private var lastPID: pid_t?
    private var checkedAt: TimeInterval = -.infinity
    private let recheckInterval: TimeInterval = 2

    private var axWindows: [AXUIElement] = []
    private var axWindowsAt: TimeInterval = 0
    private let windowCacheSeconds: TimeInterval = 1.0

    /// Тот самый Claude (#7096). Выбор сверяется раз в `recheckInterval` и сразу, как только
    /// выбранный процесс вышел. До WF82 кэш держал первый найденный процесс, пока тот жив:
    /// забытая скрытая копия Claude стала им в 01:24, настоящий Claude, запущенный рядом
    /// в 01:57, так и не был замечен — и меню на кнопке молчало.
    func running() -> NSRunningApplication? {
        refreshChoice()
        guard let chosen = chosen else { return nil }
        if let app = cachedApp, app.processIdentifier == chosen.pid { return app }
        cachedApp = NSRunningApplication(processIdentifier: chosen.pid)
        return cachedApp
    }

    /// Сверка выбора. `running()` зовут восемь раз в секунду, поэтому список процессов
    /// перечитывается не чаще раза в `recheckInterval` — и сразу, если выбранный процесс вышел.
    /// Выбор сменился — кэши AX сбрасываются и `onRestart` зовётся ровно один раз.
    private func refreshChoice() {
        let now = clock()
        if now - checkedAt < recheckInterval, chosen == nil || cachedApp?.isTerminated != true { return }
        checkedAt = now

        let list = instances()
        let next = ClaudeApp.choose(current: chosen?.pid, among: list,
                                    folders: ClaudeApp.installFolders, windowOwners: windowOwners)
        if next?.pid != chosen?.pid {
            cachedApp = nil
            cachedElement = nil
            axWindows = []
            axWindowsAt = 0
            if let next = next {
                if let last = lastPID, last != next.pid { onRestart?() }
                lastPID = next.pid
            }
        }
        chosen = next
        instanceCount = list.count

        let extras = list.filter { $0.pid != next?.pid }
        for extra in extras where !announced.contains(extra.pid) { onDuplicate?(extra, list.count) }
        announced = Set(extras.map { $0.pid })
    }

    var pid: pid_t? { running()?.processIdentifier }

    /// Когда запущен выбранный Claude (#7065, контракт К5): «окна как были» возвращаются,
    /// только если Claude запущен ПОЗЖЕ снимка окон — подмена самого Пимпа на живом Claude
    /// окна по второму разу не открывает (критик WF84 Б4).
    var launchDate: Date? {
        _ = running()
        return chosen?.launchDate
    }

    /// Поле `claude=` строки диагностики (критик WF82 п. 4): pid выбранного Claude и сколько
    /// их запущено всего — `49762/2` сразу говорит, что рядом живёт лишний.
    var statusField: String {
        _ = running()
        guard let chosen = chosen else { return "нет" }
        return "\(chosen.pid)/\(instanceCount)"
    }

    // MARK: - выбор экземпляра (#7096)

    /// Папки настоящих установок: «Программы» системы и свои. Путь к самому Claude не зашит
    /// (критик WF82 п. 3): у команды он бывает и в `~/Applications`.
    static let installFolders: [String] = {
        let own = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        return [URL(fileURLWithPath: "/Applications", isDirectory: true), own]
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
    }()

    /// Насколько копии можно верить по месту: 0 — `.app` прямо в «Программах» (системных или
    /// своих), 1 — видимая копия где-то ещё или путь неизвестен, 2 — скрытая (имя или папка
    /// с точкой: `.Claude-before-….app`, корзина) или не `.app` (`….app.failed`).
    static func placement(of path: String?, folders: [String]) -> Int {
        guard let path = path else { return 1 }
        let url = URL(fileURLWithPath: path)
        if url.pathExtension != "app" || url.pathComponents.contains(where: { $0.hasPrefix(".") }) {
            return 2
        }
        return folders.contains(url.deletingLastPathComponent().path) ? 0 : 1
    }

    /// Какой из запущенных Claude «тот самый» (порядок — критик WF82 п. 3). Чистая, её гоняют
    /// тесты. Сперва место бандла (`placement`); среди равных — у кого есть окна на экране
    /// (оконный сервер спрашиваем, только если кандидатов больше одного); дальше позже
    /// запущенный, а без даты запуска — больший pid.
    static func pick(_ list: [ClaudeInstance], folders: [String],
                     windowOwners: () -> Set<pid_t>) -> ClaudeInstance? {
        guard let best = list.map({ placement(of: $0.path, folders: folders) }).min() else { return nil }
        var pool = list.filter { placement(of: $0.path, folders: folders) == best }
        if pool.count > 1 {
            let owners = windowOwners()
            let shown = pool.filter { owners.contains($0.pid) }
            if !shown.isEmpty { pool = shown }
        }
        return pool.max { a, b in
            let da = a.launchDate ?? .distantPast, db = b.launchDate ?? .distantPast
            return da != db ? da < db : a.pid < b.pid
        }
    }

    /// Выбор с памятью. Живой выбор уступает только копии, что стоит на месте лучше (скрытая →
    /// из «Программ»); окна и возраст решают лишь новый выбор. Иначе два Claude с окнами на
    /// разных столах перекидывали бы выбор при каждом переключении стола — и каждый раз
    /// `onRestart` сбрасывал бы кэши и заново возвращал темы.
    static func choose(current: pid_t?, among list: [ClaudeInstance], folders: [String],
                       windowOwners: () -> Set<pid_t>) -> ClaudeInstance? {
        if let current = current, let kept = list.first(where: { $0.pid == current }) {
            let place = placement(of: kept.path, folders: folders)
            guard list.contains(where: { placement(of: $0.path, folders: folders) < place }) else {
                return kept
            }
        }
        return pick(list, folders: folders, windowOwners: windowOwners)
    }

    /// Живой список: процессы с bundle id Claude, а нет ни одного — обычное приложение с именем
    /// «Claude» (запасной путь, как был).
    static func liveInstances() -> [ClaudeInstance] {
        let apps = NSWorkspace.shared.runningApplications
        var found = apps.filter { $0.bundleIdentifier == bundleID }
        if found.isEmpty {
            found = apps.filter { $0.localizedName == name && $0.activationPolicy == .regular }
        }
        return found.map {
            ClaudeInstance(pid: $0.processIdentifier,
                           path: $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path,
                           launchDate: $0.launchDate)
        }
    }

    /// Владельцы окон на экране: те же окна, что у `onScreenFrames` (слой 0, без служебных),
    /// и рамка хоть краем на каком-то мониторе — у забытого Claude окна стояли за экраном.
    static func liveWindowOwners() -> Set<pid_t> {
        let screens = NSScreen.screens.map { Screens.flip(rect: $0.frame) }
        return Set(layerZeroWindows().filter { window in
            screens.contains { $0.intersects(window.frame.frame) }
        }.map { $0.owner })
    }

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
        // Сверка выбора первой: сменился Claude — `refreshChoice` уже сбросил кэш элемента.
        guard let pid = running()?.processIdentifier else { return nil }
        if let element = cachedElement { return element }
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

    /// Сбросить кэш AX-окон (z3-r02): опрос рождения увидел свежий номер окна, и список,
    /// освежённый за миг до рождения, пары ему не даст до конца окна поиска.
    func forgetWindows() { axWindowsAt = 0 }

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
        let hits = windows().filter { element in
            guard let f = AX.frame(element) else { return false }
            return abs(f.minX - frame.minX) <= 2 && abs(f.minY - frame.minY) <= 2
                && abs(f.width - frame.width) <= 2 && abs(f.height - frame.height) <= 2
        }
        return hits.count == 1 ? hits[0] : nil
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
        layerZeroWindows().filter { $0.owner == pid }.map { $0.frame }
    }

    /// All Spaces for the selected process. Service filtering follows AX pairing so a
    /// real named chat at Electron's usual service-window coordinates is not discarded.
    static func allFrames(pid: pid_t) -> [ClaudeWindowFrame] {
        layerZeroWindows(allSpaces: true).filter { $0.owner == pid }.map { $0.frame }
    }

    /// Окна слоя 0 на экране, спереди назад, без служебных — у всех владельцев сразу: один
    /// вызов оконного сервера и для рамок окон Claude, и для выбора экземпляра (#7096).
    private static func layerZeroWindows(allSpaces: Bool = false) -> [(owner: pid_t, frame: ClaudeWindowFrame)] {
        let options: CGWindowListOption = allSpaces ? [.optionAll, .excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [(owner: pid_t, frame: ClaudeWindowFrame)] = []
        for info in list {
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { continue }
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            guard let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1
            guard allSpaces ? alpha >= minWindowAlpha : !isServiceWindow(frame: rect, alpha: alpha) else { continue }
            let onScreen = !allSpaces || (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
            out.append((owner: owner, frame: ClaudeWindowFrame(id: number, frame: rect, onScreen: onScreen)))
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

    /// `hs.window:focus()` — поднять приложение и сделать окно главным. Открыто меню PMP — после его закрытия
    /// (`MenuHold`, WF145): активация Claude закрыла бы меню.
    func focus(window: AXUIElement) {
        MenuHold.shared.run { [weak self] in self?.focusNow(window: window) }
    }

    /// Вывести Claude вперёд (без окна) — тоже через замок меню (WF145).
    func activate(options: NSApplication.ActivationOptions = []) {
        MenuHold.shared.run { [weak self] in _ = self?.running()?.activate(options: options) }
    }

    private func focusNow(window: AXUIElement) {
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
