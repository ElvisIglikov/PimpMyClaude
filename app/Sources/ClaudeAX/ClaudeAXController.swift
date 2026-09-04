import AppKit
import ApplicationServices

/// Всё, что раньше делали три Lua-модуля: авто-Allow (`claude_autoallow`), меню на кнопке
/// «Свернуть» с хоткеями (`claude_minimize_menu`) и блокировка ⌘Q (`claude_noquit`).
///
/// Хоткеи и ⌘Q — Carbon `RegisterEventHotKey` (решение 1 плана): они регистрируются, когда
/// Claude выходит вперёд, и снимаются, когда уходит назад, поэтому в остальных приложениях
/// клавиши обычные. Без доверия Accessibility модуль работает вхолостую и держит флаг.
public final class ClaudeAXController: ClaudeAXControlling {
    private let app = ClaudeApp()
    private let commands = CommandChannel()
    private let hud = HUD()
    private let hotkeys = CarbonHotkeys()
    private let actions: ClaudeActions
    private let autoAllow: AutoAllow
    private let menu: MinimizeMenu
    private let statusFeed: StatusFeed
    /// Индекс чатов Claude Code — единственный источник правды «папка ↔ сессия» (критик Б2
    /// плана WF16): из него живёт и покраска по проекту, и список папок «🪟 Новое окно ▸»,
    /// и уникальное имя чата. Второго сканера тех же файлов в приложении нет.
    private let index = ProjectIndex()
    /// Вид проекта (`.pimpmyclaude.json`) — чтение для нового окна; файлов не пишет.
    private let projectSettings = ProjectSettingsStore()
    /// Цвет проекта (план WF15): своего таймера у покраски нет — она тикает вместе с
    /// watchdog'ом, раз в 2 с (критик М2).
    private let projectPaint: ProjectPaint

    private var observers: [NSObjectProtocol] = []
    private var watchdog: Timer?
    private var started = false
    private var claudeFrontmost = false

    /// Есть ли доверие Accessibility. Промпт показывает приложение (батч C), модуль только читает.
    public private(set) var isAccessibilityTrusted = false
    /// Сколько раз ⌘Q был проглочен, и когда в последний раз.
    public private(set) var blockedQuits = 0
    public private(set) var lastBlockedQuit = "(none)"

    public init() {
        projectPaint = ProjectPaint(index: index)
        actions = ClaudeActions(app: app, commands: commands)
        autoAllow = AutoAllow(app: app, hud: hud)
        menu = MinimizeMenu(app: app, actions: actions)
        statusFeed = StatusFeed(commands: commands)
        actions.onWindowsMoved = { [weak self] in self?.menu.clearCache() }
        // «Workflow» на сборке без комплекта — плашкой на экран (критик п. 3 фикс-батча WF9).
        actions.onWarning = { [weak self] text in self?.hud.show(text, seconds: 2.5) }
        // «🪟 Новое окно» держит плашку дольше: работа идёт до 40 с (план WF13).
        actions.onNotice = { [weak self] text, seconds in self?.hud.show(text, seconds: seconds) }
        app.onRestart = { [weak self] in self?.menu.clearCache() }
        // Сводки перечитываются и по таймеру, и когда меню вот-вот всплывёт (решение 2 WF9).
        menu.onWillShow = { [weak self] in self?.statusFeed.refresh() }

        // Цвет проекта: папку окна знает ProjectIndex, красит та же команда `theme`, а память
        // приложения покраска не трогает — галки ставит только ручной выбор (план WF15).
        projectPaint.send = { [weak self] command in self?.actions.applyProject(command) ?? false }
        projectPaint.windowTitles = { [weak self] in self?.actions.paintableTitles() ?? [] }
        // Себя нет — считаем окно занятым и молчим: лучше не покрасить, чем покрасить лишнее.
        projectPaint.isWindowBusy = { [weak self] title in
            self?.actions.isWindowPainted(title: title) ?? true
        }
        projectPaint.isAllWindowsSet = { [weak self] in self?.actions.hasAllWindowsView ?? true }
        // Живые цвета сильнее цвета проекта (критик Б2 плана WF18): пока они крутятся, проект
        // не шлёт команд — иначе окно мигало бы между проектным цветом и живым. Себя нет —
        // считаем, что крутятся, и молчим.
        projectPaint.isLiveColorsOn = { [weak self] in self?.actions.liveColors.on ?? true }
        projectPaint.isMenuOpen = { [weak self] in self?.menu.isMenuOpen ?? true }
        projectPaint.lastMenuCommand = { [weak self] in self?.actions.lastUserCommandAt }
        projectPaint.showNotice = { [weak self] text in self?.hud.show(text, seconds: 3) }
        // «Записать этот вид в проект» берёт слои окна там же, где меню берёт галки, — и там же,
        // где их берёт новое окно без своего вида проекта (план WF16).
        projectPaint.currentView = { [weak self] title in
            self?.actions.windowView(title: title) ?? ProjectSettings()
        }
        menu.project = projectPaint

        // «🪟 Новое окно ▸ <проект>» (план WF16): папки — из индекса чатов, имя чата уникально
        // по ВСЕМ его заголовкам (критик В4), вид — из файла проекта. Страница ничего этого
        // не знает: ей всё приходит готовым в команде.
        menu.recentProjects = { [weak self] in
            self?.index.recentProjects(limit: MenuModel.newWindowProjectsLimit) ?? []
        }
        actions.chatName = { [weak self] project in
            self?.index.uniqueChatName(project.name) ?? project.name
        }
        actions.projectView = { [weak self] project in
            self?.projectSettings.settings(in: project.folder)
        }
    }

    // MARK: - ClaudeAXControlling

    public func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.start() }
            return
        }
        guard !started else { return }
        started = true
        isAccessibilityTrusted = AX.isTrusted

        autoAllow.start()
        menu.start()
        statusFeed.start()
        // Живые цвета крутились до перезапуска приложения — шлём команду заново (решение 4
        // плана WF18): окна могли открыться, пока приложение не работало, и список заголовков
        // в них устарел. Выключены — команды нет вовсе.
        actions.resendLiveColors()
        observeActivation()
        claudeFrontmost = app.isFrontmost
        refreshHotkeys()

        let watchdog = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.isAccessibilityTrusted = AX.isTrusted
            self.refreshHotkeys()
            // Цвет проекта — на этом же таймере, своего заводить не надо (критик М2 плана WF15).
            self.projectPaint.tick()
        }
        RunLoop.main.add(watchdog, forMode: .common)
        self.watchdog = watchdog
    }

    public func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stop() }
            return
        }
        started = false
        autoAllow.stop()
        menu.stop()
        statusFeed.stop()
        hotkeys.removeAll()
        watchdog?.invalidate()
        watchdog = nil
        hud.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
    }

    public var autoAllowEnabled: Bool {
        get { autoAllow.enabled }
        set { autoAllow.enabled = newValue }
    }

    public var minimizeMenuEnabled: Bool {
        get { menu.enabled }
        set {
            menu.enabled = newValue
            refreshHotkeys()
        }
    }

    public var blockQuitEnabled: Bool = true {
        didSet { refreshHotkeys() }
    }

    /// Команда меню снаружи (меню-бар приложения). Страничные уходят в command.json,
    /// оконные выполняются сразу; окно берётся то, что в фокусе у Claude.
    public func send(_ command: ClaudeCommand) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.send(command) }
            return
        }
        actions.perform(command, on: nil)
    }

    /// Блок стилей в живом `claude.css` (радиус неоновой рамки и поля по бокам) — на запуске
    /// приложения и после «Поставить»/«Снять»: `Patcher.installLiveFiles` копирует claude.css
    /// из бандла ЦЕЛИКОМ и затирает его (решение 1 плана WF14).
    public func refreshLiveStyle() {
        LiveStyle.refresh()
    }

    // MARK: - статус (для меню-бара и живой проверки на гейте)

    public var statusText: String {
        let claude = app.running() != nil ? "есть" : "нет"
        return """
        accessibility=\(isAccessibilityTrusted) claude=\(claude) front=\(claudeFrontmost) \
        autoAllow=\(autoAllowEnabled)/\(autoAllow.isRunning) presses=\(autoAllow.pressCount) \
        menu=\(minimizeMenuEnabled)/\(menu.isRunning) menus=\(menu.shows) \
        blockQuit=\(blockQuitEnabled) blocks=\(blockedQuits) hotkeys=\(hotkeys.count) \
        status=\(statusFeed.isRunning)/\(statusFeed.projectCount)/\(statusFeed.sentCount) \
        project=\(projectPaint.status) live=\(liveColorsStatus) \
        lastCommand=\(actions.lastCommand)
        """
    }

    /// Живые цвета в строке диагностики: «off» или «solo/300/dark» (план WF18) — на гейте по
    /// ней видно, что приложение думает о крутёже, не открывая меню.
    private var liveColorsStatus: String {
        let state = actions.liveColors
        guard state.on else { return "off" }
        return "\(state.mode.rawValue)/\(state.period)/\(state.tone.rawValue)"
    }

    public func autoAllowHistory() -> [String] {
        autoAllow.history.map { "\($0.at)  \($0.heading)  [\($0.button)] ok=\($0.ok)" }
    }

    /// Заголовки диалогов, которые авто-Allow никогда не подтверждает (M.blockHeadingPatterns).
    public var blockedHeadings: [String] {
        get { autoAllow.blockHeadingPatterns }
        set { autoAllow.blockHeadingPatterns = newValue }
    }

    // MARK: - хоткеи по активации Claude

    private func observeActivation() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                           object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.claudeFrontmost = ClaudeApp.isClaude(app)
            self?.refreshHotkeys()
        })
        // Claude закрылся — впереди уже кто-то другой; спрашиваем систему, кто именно.
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.claudeFrontmost = self.app.isFrontmost
            self.refreshHotkeys()
        })
    }

    private func refreshHotkeys() {
        // Carbon-хоткеи доверия Accessibility не требуют; без доверия остаётся только блок ⌘Q
        // (действия меню без AX не работают). Тумблер «Меню на кнопке» клавиши не гасит — как в Lua.
        guard started, claudeFrontmost else {
            hotkeys.apply([])
            return
        }
        var bindings: [HotkeyBinding] = []
        if isAccessibilityTrusted {
            for (index, entry) in MenuModel.entries.enumerated() {
                guard entry.registersHotkey, let key = entry.key else { continue }
                bindings.append(HotkeyBinding(id: UInt32(index + 1), key: key) { [weak self] in
                    self?.actions.perform(entry.command, on: nil)
                })
            }
        }
        if blockQuitEnabled {
            bindings.append(HotkeyBinding(id: 100, key: MenuModel.quitKey) { [weak self] in
                self?.onBlockedQuit()
            })
        }
        hotkeys.apply(bindings)
    }

    /// ⌘Q проглочен (Carbon перехватил его до Claude) — показываем, как выйти по-настоящему.
    private func onBlockedQuit() {
        blockedQuits += 1
        lastBlockedQuit = ClaudeAXController.clock.string(from: Date())
        hud.show(MenuModel.quitMessage, seconds: 1.5)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
