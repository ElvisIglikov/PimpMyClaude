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
    /// Канал probe (план WF29): страницы сами говорят, какой в них чат. Тикает на том же
    /// таймере и молчит, пока выключен тумблер «🗂 Цвет по проекту».
    private let chatProbe = ChatProbe()
    /// Темы окон на диске (план WF35, задача #5473): переустановка Claude стирает localStorage
    /// страниц, и все окна становились серыми. Файл живёт рядом с `command.json`.
    private let windowThemes = WindowThemeStore()
    /// Свой список недавних проектов (план WF36, WF30 ч. 2, задача #5451): индекс чатов Claude
    /// переустановку не переживает, а файл рядом с `command.json` — переживает.
    private let projects = ProjectsStore()
    /// Канал «Пимп» (план WF36, задача #5531): окна Claude из любого чата — файлами.
    /// Тикает на общем таймере, своего не заводит.
    private let pimp = PimpChannel()

    private var observers: [NSObjectProtocol] = []
    /// Заголовки окон, снятые в этом тике: их читает и канал probe, и покраска — второй
    /// обход AX за те же 2 с не нужен.
    private var tickTitles: [String]?
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
        // Claude перезапустился — вместе с ним умер localStorage страниц: темы, цвет проекта
        // и живые цвета жили только там (решение 8 плана WF35). Кэш прямоугольников кнопки
        // «Свернуть» тоже стал мусором (грабли claude_minimize_menu.lua).
        app.onRestart = { [weak self] in
            guard let self = self else { return }
            self.menu.clearCache()
            // Новое поколение: три попытки возврата тем и снова «первый пустой ответ probe
            // значит переустановку».
            self.windowThemes.beginGeneration()
            // Отпечатки покраски стали враньём — окна голые, а мы считаем их покрашенными.
            self.projectPaint.forget()
            // Крутёж живых цветов страница тоже забыла.
            self.actions.resendLiveColors()
        }
        // Сводки перечитываются и по таймеру, и когда меню вот-вот всплывёт (решение 2 WF9).
        menu.onWillShow = { [weak self] in self?.statusFeed.refresh() }

        // Цвет проекта: папку окна знает ProjectIndex, красит та же команда `theme`, а память
        // приложения покраска не трогает — галки ставит только ручной выбор (план WF15).
        projectPaint.send = { [weak self] command in self?.actions.applyProject(command) ?? false }
        projectPaint.windowTitles = { [weak self] in
            guard let self = self else { return [] }
            return self.tickTitles ?? self.actions.paintableTitles()
        }
        // Какой чат в окне, знает сама страница (план WF29): без этого попап красится по
        // заголовку, а заголовок попапа — снимок имени чата на момент выноса в окно (#5455).
        // Связь сиденьями, а не через `init`: `ProjectPaint` собирают напрямую тесты.
        chatProbe.isEnabled = { [weak self] in self?.projectPaint.enabled ?? false }
        projectPaint.chatPages = { [weak self] in self?.chatProbe.pages ?? [] }
        projectPaint.chatForTitle = { [weak self] title in self?.chatProbe.chat(forTitle: title) }
        // Темы на диске (план WF35): зеркало закрепляющих команд и повод спросить probe.
        // Главное окно опознаётся тем же резолвером, что и цели покраски: у него ключ `main`.
        actions.windowThemes = windowThemes
        actions.onThemeRecorded = { [weak self] in self?.chatProbe.noteMirror() }
        windowThemes.isMainWindowTitle = { [weak self] title in
            self?.projectPaint.windowKey(forTitle: title) == ProjectPaint.mainKey
        }
        // Ключ окна для панели «Своя тема» (находка 5 проверки WF20).
        ClaudeActions.windowKeyForTitle = { [weak self] title in
            self?.projectPaint.windowKey(forTitle: title) ?? ProjectPaint.windowPrefix + title
        }
        // Себя нет — считаем окно занятым и молчим: лучше не покрасить, чем покрасить лишнее.
        projectPaint.isWindowBusy = { [weak self] title in
            self?.actions.isWindowAutoPainted(title: title) ?? true
        }
        projectPaint.isAllWindowsSet = { [weak self] in self?.actions.hasAllWindowsView ?? true }
        // Живые цвета сильнее цвета проекта (критик Б2 плана WF18): пока они крутятся, проект
        // не шлёт команд — иначе окно мигало бы между проектным цветом и живым. Себя нет —
        // считаем, что крутятся, и молчим.
        projectPaint.isLiveColorsOn = { [weak self] in self?.actions.liveColors.on ?? true }
        projectPaint.isMenuOpen = { [weak self] in self?.menu.isMenuOpen ?? true }
        projectPaint.lastMenuCommand = { [weak self] in self?.actions.lastUserCommandAt }
        projectPaint.showNotice = { [weak self] text in self?.hud.show(text, seconds: 3) }
        // Ручной выбор в окне проекта молча становится видом проекта (решение 3.2 плана WF20):
        // крючок висит на `remember`, поэтому ни примерка мышью, ни «Раскрасить по кругу»
        // в файл проекта не пишут.
        actions.onWindowViewChanged = { [weak self] title, theme, font, size, frame in
            self?.projectPaint.noteManualChoice(title: title, theme: theme, font: font,
                                                size: size, frame: frame)
        }
        menu.project = projectPaint

        // «🪟 Новое окно ▸ <проект>» (план WF16): папки — из индекса чатов, имя чата уникально
        // по ВСЕМ его заголовкам (критик В4), вид — из файла проекта. Страница ничего этого
        // не знает: ей всё приходит готовым в команде.
        // Список читается из СВОЕГО файла (план WF36): индекс Claude доливает его на каждом
        // тике и здесь же, перед показом меню, — а переустановку Claude переживает файл.
        menu.recentProjects = { [weak self] in
            self?.knownProjects(limit: MenuModel.newWindowProjectsLimit) ?? []
        }
        // Открыли папку (клик по пункту меню или запрос канала) — она самая свежая.
        actions.onProjectUsed = { [weak self] project in
            self?.projects.note(project, at: Date())
        }
        // Авто-цвет нового окна — на тех же условиях, что цвет проекта (план WF36 п. 4).
        actions.isProjectColorOn = { [weak self] in self?.projectPaint.enabled ?? false }
        actions.chatName = { [weak self] project in
            self?.index.uniqueChatName(project.name) ?? project.name
        }
        // Адрес главного окна для «Новое окно»/«В отдельное окно» с любого окна (WF19, verify п. 4):
        // индекс умеет и случай двух страниц claude.ai; нет ответа — запасной статик в ClaudeActions.
        actions.mainWindowMatch = { [weak self] in
            self?.index.mainWindow()?.match ?? ClaudeActions.mainWindowMatch()
        }
        actions.projectView = { [weak self] project in
            self?.projectSettings.settings(in: project.folder)
        }
        // Канал «Пимп» (план WF36): окна Claude из любого чата — файлами, без клавиатуры.
        connectPimp()
    }

    // MARK: - канал «Пимп» (план WF36)

    /// Недавние проекты для меню и канала: свой файл, долитый из индекса Claude. Файл не
    /// записался (папки нет, прав нет) — отдаём индекс: список обязан остаться живым, как
    /// до WF36.
    private func knownProjects(limit: Int) -> [Project] {
        projects.absorb(index.projects(), at: Date())
        let stored = projects.recent(limit: limit)
        return stored.isEmpty ? index.recentProjects(limit: limit) : stored
    }

    /// Сиденья канала: всё, что он спрашивает у приложения. AX наружу не отдаём — канал
    /// говорит номерами окон Quartz, а окна двигает `ClaudeActions`.
    private func connectPimp() {
        pimp.seats = PimpSeats(
            claudeRunning: { [weak self] in self?.app.running() != nil },
            windows: { [weak self] in
                guard let self = self else { return [] }
                return self.actions.pimpWindows().map {
                    self.pimpWindow(id: $0.id, title: $0.title, frame: $0.frame)
                }
            },
            minimized: { [weak self] in self?.actions.minimizedCount() ?? 0 },
            projects: { [weak self] in self?.knownProjects(limit: ProjectsStore.limit) ?? [] },
            openNewWindow: { [weak self] project, origin in
                // Тот же путь, что пункт меню «🪟 Новое окно ▸ проект»: окно берётся то,
                // что в фокусе у Claude, а команда всё равно адресуется главному (`match`).
                self?.actions.newWindow(in: project, on: nil, origin: origin)
            },
            arrange: { [weak self] ids in
                guard let self = self else { return [] }
                return self.actions.arrange(ids: ids).map {
                    self.pimpWindow(id: $0.id, title: $0.title, frame: $0.frame)
                }
            },
            place: { [weak self] moves in self?.actions.place(moves) },
            titleForChat: { [weak self] chat in self?.pimpTitle(forChat: chat) },
            newWindowLayers: { [weak self] in self?.actions.lastNewWindowLayers ?? false })
    }

    /// Окно канала: к заголовку и рамке добавляются чат и папка — их знает индекс Claude
    /// и карта probe. Карта молчит (тумблер выключен, канал занят агентом) — обе строки пусты.
    private func pimpWindow(id: CGWindowID, title: String, frame: CGRect) -> PimpWindow {
        let chat = pimpChat(forTitle: title)
        let folder = chat.flatMap { index.folder(for: $0) }?.path ?? ""
        return PimpWindow(id: id, title: title, chat: chat ?? "", folder: folder, frame: frame)
    }

    /// Какой чат в окне с таким заголовком: главное окно носит заголовок своего чата
    /// (тот же путь, что `ProjectPaint.windowKey`), попапы — по карте probe.
    private func pimpChat(forTitle title: String) -> String? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        // Свежий ответ самой страницы сильнее адреса из status.json (решение 8 плана WF29).
        if let page = chatProbe.pages.first(where: { $0.kind == .main
            && $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == clean }),
            let chat = page.chat, ChatProbe.isRecent(page, at: Date()) {
            return chat
        }
        if let session = index.mainWindow()?.session, session.title == clean {
            return session.sessionId
        }
        if let popout = chatProbe.chat(forTitle: clean) { return popout }
        // Главное окно носит заглушку «Claude», а не имя чата (гейт WF36, живой результат
        // `fromResolved:false` на запрос из главного окна): чат берём из индекса.
        if ProjectIndex.isStub(clean) { return index.mainWindow()?.session?.sessionId }
        return nil
    }

    /// Обратный ход: в каком окне чат `from` (поле запроса). Заголовок главного окна берём
    /// из индекса — он живёт и без probe; попап знает только карта probe, а она замирает
    /// вместе с тумблером «🗂 Цвет по проекту» (п. 7 «Что выяснено»), и тогда «под этим»
    /// честно вырождается в «справа».
    private func pimpTitle(forChat chat: String) -> String? {
        let wanted = chat.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        if let session = index.mainWindow()?.session, session.sessionId == wanted,
           !session.title.isEmpty, !ProjectIndex.isStub(session.title) {
            return session.title
        }
        let titles = Set(chatProbe.pages
            .filter { $0.kind == .popout && $0.chat == wanted }
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        return titles.count == 1 ? titles.first : nil
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
        // Поколение возврата тем (решение 5 плана WF35): приложение только что поднялось,
        // и Claude мог за это время переустановиться.
        windowThemes.beginGeneration()
        // Каталог канала «Пимп»: по нему CLI видит, что приложение вообще есть (план WF36).
        pimp.start()
        observeActivation()
        claudeFrontmost = app.isFrontmost
        refreshHotkeys()

        let watchdog = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.isAccessibilityTrusted = AX.isTrusted
            self.refreshHotkeys()
            // Цвет проекта — на этом же таймере, своего заводить не надо (критик М2 плана WF15).
            // Сперва канал probe: покраска берёт из него, какой чат в каком окне.
            self.tickTitles = self.actions.paintableTitles()
            self.chatProbe.tick(windowTitles: self.tickTitles ?? [],
                                indexRevision: self.index.revision)
            // Карта тем страницы приезжает тем же кругом probe (решение 3 плана WF35):
            // файл догоняет ею правду, а зеркало остаётся страховкой на время, пока канал
            // занят агентом на гейте.
            self.windowThemes.absorb(page: self.chatProbe.takeThemes(), at: Date())
            // Возврат после переустановки Claude: одна команда на все окна, не больше трёх
            // за поколение (решение 5 плана WF35).
            self.windowThemes.restoreTick(titles: self.tickTitles ?? [], at: Date()) { fields in
                self.actions.sendThemesRestore(fields: fields)
            }
            self.projectPaint.tick()
            // Свой список проектов доливается из индекса (план WF36, WF30 ч. 2): файл пишется,
            // только когда состав или свежесть папок правда изменились.
            self.projects.absorb(self.index.projects(), at: Date())
            // Канал «Пимп» — на этом же тике: запросы из любого чата лежат файлами.
            self.pimp.tick()
            self.tickTitles = nil
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
        project=\(projectPaint.status) chats=\(chatProbe.status) themes=\(windowThemes.status) \
        pimp=\(pimp.status) live=\(liveColorsStatus) lastCommand=\(actions.lastCommand)
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
