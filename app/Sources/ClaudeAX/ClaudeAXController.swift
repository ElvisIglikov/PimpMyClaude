import AppKit
import ApplicationServices

/// Меню на кнопке «Свернуть» с хоткеями (`claude_minimize_menu`) и блокировка ⌘Q (`claude_noquit`).
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
    private let menu: MinimizeMenu
    private let statusFeed: StatusFeed
    /// Индекс чатов Claude Code — единственный источник правды «папка ↔ сессия» (критик Б2
    /// плана WF16): из него живёт и покраска по проекту, и список папок «🪟 Новое окно ▸»,
    /// и уникальное имя чата. Второго сканера тех же файлов в приложении нет.
    private let index = ProjectIndex()
    private let chatLookupLock = NSLock()
    private var chatLookup: [String: (cwd: String, cli: String?)] = [:]

    /// Publish on main; HTTP readers copy one value under a short lock without waiting for AX.
    private func refreshChatLookup() {
        var next: [String: (cwd: String, cli: String?)] = [:]
        for session in index.sessions { next[session.sessionId] = (session.cwd.path, session.cliSessionId) }
        chatLookupLock.lock()
        chatLookup = next
        chatLookupLock.unlock()
    }

    private func knownChat(_ chat: String) -> (cwd: String, cli: String?)? {
        chatLookupLock.lock()
        defer { chatLookupLock.unlock() }
        return chatLookup[chat]
    }
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
    /// Раскладки проектов (план WF41, задача #5620): файл рядом с `projects.json` — «Утро»,
    /// «Разбор» и прочее, что Элвис запомнил.
    private let layouts = LayoutsStore()
    /// Канал «Пимп» (план WF36, задача #5531): окна Claude из любого чата — файлами.
    /// Тикает на общем таймере, своего не заводит.
    private let pimp = PimpChannel()
    /// «Окна как были» (#7065, контракт К5): снимок окон в `windows-snapshot.json` и возврат
    /// после запуска Claude. Тикает на общем таймере, окна возвращает очередью канала «Пимп».
    private let windowSnapshots = WindowSnapshotKeeper()
    /// «📋 Копировать в буфер» (WF69, #6236): страница кладёт путь и метку, приложение подменяет
    /// буфер самим файлом. Свой таймер 0,25 с — общий тик в 2 с опоздал бы к «вставить» в Telegram.
    private let htmlOpener = HtmlChromeOpener()
    /// Зеркало размера шрифта поля и возврат после переустановки Claude (WF107 К2).
    private let composerFont = ComposerFontMirror()
    /// Просмотр файла поверх монитора чата (WF103, маршрут `view` порта 47615).
    private let fileView = FileView()
    /// Галерея — своё приложение PimpViewer.app (WF104, К-V8): клиент к нему, всё — на своей очереди.
    private let viewerClient = ViewerClient()
    /// Gallery counts retry within a bounded page generation until probe confirms a counter increment.
    /// State and callbacks stay on the main queue.
    private let viewerCounts = ViewerCountsSync()
    /// К3: состояние тумблера и ограниченный повтор страницам; кнопки жмёт только страница.
    private let autoAllowSwitch = AutoAllowSwitch()
    private let autoContinueSwitch = AutoContinueSwitch()
    /// Корень автодоверия страниц (WF108, `trust-root`): тем же правилом поколений; новое поколение —
    /// и когда `projectsRoot` в claude.json сменился. `trustRoot` — последний прочитанный корень.
    private let trustRootSwitch = AutoAllowSwitch()
    private var trustRoot: String?
    /// Притемнение окон (WF113, #8256) и ракета отправки (WF114, #8226): UserDefaults и рассылка поколениями.
    private let pageLook = PageLookSettings(configURL: CommandChannel.directory.appendingPathComponent("claude.json"))
    /// Кнопка «💬 Новый чат» в самом чате (#7246): метка в заголовке окна.
    private let continueWatch = ContinueWatch()
    /// Кружок-микрофон (#7054, К4): клик — клавиша Диктатора, правый — меню «🎙 Рик».
    private let micMonitor = MicMonitor()
    /// Окна доступа macOS не пропустить (WF91, #7691): мигающая рамка и плашка у курсора.
    private let consentBeacon = ConsentBeacon()
    /// Окна при смене мониторов (#7740, WF94): расстановка на каждый набор экранов в
    /// `windows-by-screens.json` и возврат, когда набор сменился на знакомый.
    private let screenLayouts = ScreenLayoutKeeper()

    private var observers: [NSObjectProtocol] = []
    /// Заголовки окон, снятые в этом тике: их читает и канал probe, и покраска — второй
    /// обход AX за те же 2 с не нужен.
    private var tickTitles: [String]?
    /// Плашка «старый лоадер» уже сказана за это появление (WF111).
    private var repatchNoticed = false
    private var watchdog: Timer?
    private var layoutGuard = OneShotLayoutGuard()
    private var layoutGlobalMonitor: Any?
    private var layoutLocalMonitor: Any?
    private var layoutMonitorAttempted = false
    private var restoreConfirmationUntil: Date?
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
        menu = MinimizeMenu(app: app, actions: actions)
        statusFeed = StatusFeed(commands: commands)
        // Окна переехали: кэш кнопки «Свернуть» протух, и вместе с ним протухли рамки в
        // карте probe — по ним различаются окна-однофамильцы (план WF77, критик блокер 6б).
        actions.onWindowsMoved = { [weak self] in
            self?.layoutGuard.disarm()
            self?.menu.clearCache()
            self?.chatProbe.noteWindowsMoved()
        }
        actions.onExplicitLayout = { [weak self] moves in self?.armLayoutGuard(moves) }
        chatProbe.isLayoutGuardWanted = { [weak self] in
            guard let self = self else { return false }
            let now = Date()
            return self.layoutGuard.wantsProbe(at: now) || self.screenLayouts.wantsWakeProbe || self.restoreConfirmationUntil.map { now <= $0 } == true
        }
        // «Workflow» на сборке без комплекта — плашкой на экран (критик п. 3 фикс-батча WF9).
        actions.onWarning = { [weak self] text in self?.hud.show(text, seconds: 2.5) }
        // «🪟 Новое окно» держит плашку дольше: работа идёт до 65 с (план WF13, срок WF102).
        actions.onNotice = { [weak self] text, seconds in self?.hud.show(text, seconds: seconds) }
        // Claude перезапустился — вместе с ним умер localStorage страниц: темы, цвет проекта
        // и живые цвета жили только там (решение 8 плана WF35). Кэш прямоугольников кнопки
        // «Свернуть» тоже стал мусором (грабли claude_minimize_menu.lua).
        app.onRestart = { [weak self] in
            guard let self = self else { return }
            self.menu.clearCache()
            self.layoutGuard.disarm()
            self.restoreConfirmationUntil = nil
            // Новое поколение: три попытки возврата тем и снова «первый пустой ответ probe
            // значит переустановку».
            self.windowThemes.beginGeneration()
            // Отпечатки покраски стали враньём — окна голые, а мы считаем их покрашенными.
            self.projectPaint.forget()
            // Крутёж живых цветов страница тоже забыла.
            self.actions.resendLiveColors()
            // И выключатель Авто-Allow (К3), и «Новый чат сам».
            self.autoAllowSwitch.beginGeneration()
            self.autoContinueSwitch.beginGeneration()
            // И режим кружка-микрофона (К4) — по тому же правилу.
            self.micMonitor.beginGeneration()
            // И счёт кнопки «▦ Галерея» (К-V7).
            self.viewerCounts.beginGeneration()
            // И корень автодоверия (WF108).
            self.trustRootSwitch.beginGeneration()
            // И притемнение с ракетой отправки (WF113/WF114).
            self.pageLook.beginGeneration()
        }
        // Рядом запущен второй Claude (#7096): работаем с настоящим, а про лишний говорим
        // плашкой — один раз на появление. Закрывать чужой процесс не наше дело (критик WF82 п. 4).
        // Ходом вперёд: зовут изнутри `running()`, посреди тика меню.
        app.onDuplicate = { [weak self] extra, count in
            DispatchQueue.main.async {
                self?.hud.show(MenuModel.duplicateClaudeNotice(path: extra.path, pid: extra.pid, count: count),
                               seconds: MenuModel.duplicateClaudeNoticeSeconds)
            }
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
        // Пока идёт перенос «Обкэшить», канал probe работает при любом тумблере и спрашивает
        // страницы чаще: по их ответу закрывается окно Элвиса с его текстом (#5779).
        // С WF94 (K-N) — и пока канал «Пимп» ждёт окно «Нового окна»: исход цепочки страницы
        // (`status().newWindow`) приходит тем же кругом, и отказ страницы виден сразу.
        // С WF103 — и пока идёт `send`: её исход (`status().send`) несёт тот же круг.
        chatProbe.isCashoutPending = { [weak self] in
            (self?.actions.cashoutPending ?? false) || (self?.pimp.isWaitingPage ?? false)
                || (self?.actions.isAwaitingNewWindowActual ?? false)
        }
        actions.cashoutAnswers = { [weak self] in self?.chatProbe.pages ?? [] }
        projectPaint.chatPages = { [weak self] in self?.chatProbe.pages ?? [] }
        projectPaint.chatForTitle = { [weak self] title, frame in
            self?.windowIdentity(title: title, frame: frame).page?.chat
        }
        // Темы на диске (план WF35): зеркало закрепляющих команд и повод спросить probe.
        // Главное окно опознаётся тем же резолвером, что и цели покраски: у него ключ `main`.
        let identity: (String, CGRect?) -> WindowIdentity = { [weak self] title, frame in
            self?.windowIdentity(title: title, frame: frame) ?? .unknown
        }
        actions.windowIdentity = identity
        // Клик человека по неопознанному окну (WF111): спросить страницы сразу, без минутного тормоза.
        actions.demandPages = { [weak self] in self?.chatProbe.demand() }
        actions.pagesNeedRepatch = { [weak self] in self?.chatProbe.needsRepatch ?? false }
        actions.uniqueLegacyTitle = { [weak self] title in
            self?.actions.windowCensus().native.filter { ChatProbe.clean($0.title) == ChatProbe.clean(title) }.count == 1
        }
        projectPaint.windowIdentity = identity
        projectPaint.pageIdentity = { [weak self] page in
            guard let id = page.windowId else { return .unknown }
            return self?.windowIdentity(id: id, title: page.title, frame: nil) ?? .unknown
        }
        actions.windowThemes = windowThemes
        actions.onThemeRecorded = { [weak self] in self?.chatProbe.noteMirror() }
        windowThemes.isMainWindowTitle = { [weak self] title in
            self?.projectPaint.windowKey(forTitle: title) == ProjectPaint.mainKey
        }
        // «Обкэшить» из попапа (план WF37, #5575): тем же резолвером решается, бить ли ⌘N
        // на месте или рождать новое окно рядом — заголовок главного окна бывает и именем
        // чата, и заглушкой «Claude», по нему одному эти два окна не различить.
        actions.isMainWindowTitle = { [weak self] title in
            self?.projectPaint.windowKey(forTitle: title) == ProjectPaint.mainKey
        }
        actions.chatForTitle = { [weak self] title, frame in
            self?.windowIdentity(title: title, frame: frame).page?.chat
        }
        // «💬 Новый чат» (#7378): главное окно узнаётся и по рамке своей страницы — донором
        // «Нового чата» окно со списком чатов не станет, даже если резолвер заголовка промолчал.
        actions.isMainFrame = { [weak self] frame in
            self?.windowIdentity(title: "", frame: frame).isMain ?? false
        }
        // Замок в обе стороны (проверка S): ⌥⌘N, «🪟 Новое окно ▸», «💬 Новый чат» ждут пустое окно.
        actions.blankBusy = { [weak self] in self?.pimp.isBlankBusy ?? false }
        // Проект чата: папку знает индекс Claude Code, и новое окно родится в ней — с именем,
        // цветом и записью в `projects.json`, как у пункта «🪟 Новое окно ▸ проект».
        actions.projectForChat = { [weak self] chat in
            // Папки нет на диске — проект не отдаём: цепочка встала бы молча, «Здесь же»
            // честнее (проверка WF37, находка 6; то же сито, что у recentProjects).
            guard let self = self, let folder = self.index.folder(for: chat),
                  ProjectIndex.isDirectory(folder) else { return nil }
            return Project(folder: folder, name: folder.lastPathComponent,
                           lastFocusedAt: self.index.session(for: chat)?.lastFocusedAt ?? 0)
        }
        // Ключ окна для панели «Своя тема» (находка 5 проверки WF20).
        ClaudeActions.windowKeyForTitle = { [weak self] title, frame in
            self?.projectPaint.windowKey(forTitle: title, frame: frame) ?? ProjectPaint.windowPrefix + title
        }
        // Себя нет — считаем окно занятым и молчим: лучше не покрасить, чем покрасить лишнее.
        projectPaint.isWindowBusy = { [weak self] title in
            self?.actions.isWindowAutoPainted(title: title) ?? true
        }
        projectPaint.isTargetBusy = { [weak self] target in
            guard let self = self, let key = target.memoryKey else { return true }
            return self.actions.autoPaintedThemes[key] != nil
        }
        projectPaint.isAllWindowsSet = { [weak self] in self?.actions.hasAllWindowsView ?? true }
        projectPaint.allLook = { [weak self] in self?.actions.themeStore.allLook ?? Look() }
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
        actions.onWindowViewChanged = { [weak self] title, windowFrame, theme, font, size, frame, look in
            self?.projectPaint.noteManualChoice(title: title, windowFrame: windowFrame,
                                                theme: theme, font: font,
                                                size: size, frame: frame, look: look)
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
        // «🗂 Раскладки ▸» в «⋯ Ещё ▸» (план WF41): список читаем на каждый показ меню —
        // файл правит и сам Элвис. Возврат идёт очередью канала «Пимп»: работа там одна,
        // и пункт меню не должен спорить с запросом из чата.
        menu.savedLayouts = { [weak self] in self?.layouts.load() ?? [] }
        menu.startSaveLayout = { [weak self] in self?.prepareLayoutSave() ?? "" }
        menu.saveLayout = { [weak self] name in self?.saveLayout(named: name) }
        menu.restoreLayout = { [weak self] layout, fresh in
            guard let self = self else { return }
            // Окна открываются по одному и работа идёт минуту и дольше: молчащий пункт
            // выглядит сломанным (тот же довод, что у плашки «Нового окна»).
            let started = self.pimp.startRestore(layout, fresh: fresh)
            self.hud.show(started ? MenuModel.layoutRestoreNotice : MenuModel.layoutBusyNotice,
                          seconds: MenuModel.newWindowNoticeSeconds)
        }
        menu.deleteLayout = { [weak self] layout in self?.layouts.delete(name: layout.name) }
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
        connectWindowSnapshots()
        connectWF84Menus()
        connectMic()
        connectScreens()
        connectChatArchive()
        connectWindowHide()
        connectPageLook()
    }

    // MARK: - окна WF94: мониторы, ChatGPT, исход «Нового окна»

    /// Сиденья окон WF94. Расстановка по мониторам (#7740) — окна те же, что у снимка К5;
    /// не начинается, пока занят канал «Пимп» или идёт возврат К5. Каналу — окно ChatGPT
    /// для ответа `windows` (#7732), исход цепочки главной страницы (K-N) и ручной возврат
    /// `screens-restore`.
    private func connectScreens() {
        screenLayouts.screens = {
            NSScreen.screens.map { ScreenSpec(name: $0.localizedName, frame: Screens.flip(rect: $0.frame)) }
        }
        screenLayouts.windows = { [weak self] in
            guard let self = self else { return [] }
            return WindowSnapshotStore.windows(from: self.pimpWindowList(),
                                               isMain: self.actions.isMainWindowTitle,
                                               screen: ClaudeAXController.screenName)
        }
        screenLayouts.observation = { [weak self] in
            self?.snapshotObservation() ?? SnapshotObservation(windows: [], complete: false)
        }
        screenLayouts.adaptFrame = { [weak self] in self?.restoreFrame($0) ?? $0 }
        screenLayouts.adaptChatGPTFrame = { [weak self] in
            RestoreFrame.adaptChatGPT($0, screens: Screens.all().map { $0.usable },
                                     minWidth: self?.actions.chatGPTWindows.learnedMinWidth ?? 0)
        }
        screenLayouts.processID = { [weak self] in self?.app.pid }
        screenLayouts.wakeInputReady = { [weak self] in
            guard let self = self else { return false }
            return self.started && AX.isTrusted && self.layoutGlobalMonitor != nil && self.layoutLocalMonitor != nil
                && NSEvent.pressedMouseButtons == 0
                && self.actions.windowCensus().windows.allSatisfy {
                    AX.bool($0.window, kAXMinimizedAttribute) == false
                        && AX.bool($0.window, MinimizeMenu.fullScreenAttribute) == false
                }
        }
        screenLayouts.live = { [weak self] in self?.allWindowObservation().windows ?? [] }
        screenLayouts.isMain = { [weak self] title in self?.actions.isMainWindowTitle(title) ?? false }
        screenLayouts.chatGPT = { [weak self] in self?.actions.chatGPTWindows.front()?.frame }
        screenLayouts.busy = { [weak self] in
            guard let self = self else { return true }
            return self.pimp.isBusy || self.actions.newWindowBusy || self.windowSnapshots.phase != .keeping
        }
        screenLayouts.apply = { [weak self] moves, chatGPT in
            guard let self = self else { return }
            self.actions.place(moves)
            if let frame = chatGPT, let gpt = self.actions.chatGPTWindows.front() {
                _ = self.actions.chatGPTWindows.setFrame(gpt, frame)
            }
        }
        // Наблюдатель живёт весь процесс: `observers` снимает `stop()` с центра NSWorkspace.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil,
            queue: .main) { [weak self] _ in self?.screenLayouts.noteScreensChanged() }
        // Сон Мака или мониторов (#7975): набор тот же, а окна macOS могла сжать — тоже весь процесс.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            _ = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.screenLayouts.noteWake()
                    if self?.screenLayouts.wantsWakeProbe == true { self?.chatProbe.demand() }
                }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            _ = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in self?.screenLayouts.noteSleep() }
        }
        pimp.seats.chatGPT = { [weak self] in
            self?.actions.chatGPTWindows.front().map {
                PimpWindow(id: 0, title: $0.title, frame: $0.frame)
            }
        }
        pimp.seats.newWindowRun = { [weak self] in
            self?.chatProbe.pages.first { $0.kind == .main && $0.newWindow != nil }?.newWindow
        }
        actions.newWindowRun = { [weak self] in self?.pimp.seats.newWindowRun() }
        pimp.seats.newWindowStarting = { [weak self] in self?.actions.newWindowStarting ?? false }
        pimp.seats.restoreScreens = { [weak self] in self?.screenLayouts.restoreNow() }
        // WF108, #8148: «чат в главное окно» и настройка `mainChat` живого claude.json.
        pimp.seats.sendMainChat = { [weak self] chat, origin in self?.actions.mainChat(chat: chat, origin: origin) }
        pimp.seats.mainChatSetting = {
            PimpChannel.mainChatSetting(try? Data(contentsOf: CommandChannel.directory
                .appendingPathComponent(StatusFeed.configFileName)))
        }
        // WF102: замена окна (#7917) и «главный по центру» (#7904).
        pimp.seats.openRenewWindow = { [weak self] project, origin, text, handoff in
            guard let self = self else { return }
            // Замена чата главного окна (WF181, #9225): ⌘N — именно в главном окне, чат остаётся в нём.
            let main: AXUIElement? = handoff.stay ? {
                let listed = self.actions.pimpWindows()
                return listed.first { self.windowIdentity(title: $0.title, frame: $0.frame).isMain }?.window
            }() : nil
            self.actions.newWindow(in: project, on: main, origin: origin, text: text, handoff: handoff)
        }
        pimp.seats.screens = { Screens.all() }
        pimp.seats.cellWidth = { [weak self] in self?.actions.cellWidth() ?? 0 }
        // WF103 (#7953): «отправь текст в чат» — команда окну и исход страницы из круга `cash`.
        pimp.seats.sendText = { [weak self] chat, text, id in self?.actions.sendText(chat: chat, text: text, id: id) }
        pimp.seats.sendState = { [weak self] id in
            self?.chatProbe.pages.lazy.compactMap { $0.send }.first { $0.id == id }?.state
        }
        // WF105 (#8071): `arrange --order` не нашёл окно с неопознанным чатом — переспросить
        // карту чатов один раз, как `waitForChats`, только без сна: ответ ждёт канал на тиках.
        pimp.seats.demandChats = { [weak self] at in self?.chatProbe.demand(at: at) }
        pimp.seats.chatsAnswered = { [weak self] since in self?.chatProbe.answered(after: since) ?? true }
        actions.menuNewWindow = { [weak self] project in self?.pimp.startNewWindow(project: project) ?? false }
        // WF98 (#7841): новое окно сразу на месте — ячейка до команды, опрос рождения 0,1 с.
        actions.connectNewWindowPlace(&pimp.seats)
        pimp.seats.isRestoring = { [weak self] in self?.windowSnapshots.phase == .restoring }
        actions.isRestoringWindows = { [weak self] in self?.windowSnapshots.phase == .restoring || self?.pimp.isRestoring == true }
    }

    // MARK: - «🙈 Спрятать окна» (WF112, #8255)

    /// Канал `hide`/`show` и заморозка снимков: пока есть окна, спрятанные Пимпом, снимок К5 и
    /// раскладка мониторов не пишутся — свёрнутых нет в списке окон, и оба затёрлись бы главным.
    private func connectWindowHide() {
        pimp.seats.hideWindows = { [weak self] in self?.hideOthers() ?? WindowHideResult(failure: .noWindows) }
        pimp.seats.showWindows = { [weak self] in self?.showHidden() ?? WindowHideResult(failure: .noWindows) }
        // Новый чат при свёрнутом или закрытом главном окне (01.10.2026): выносит чаты только оно.
        pimp.seats.showMain = { [weak self] in self?.showMainWindow() ?? false }
        // Замерзают только на спрятанных Пимпом (гейт 1 WF111): свёрнутое руками окно снимки не держит.
        windowSnapshots.minimized = { [weak self] in self?.hiddenByPimp.count ?? 0 }
        screenLayouts.minimized = { [weak self] in self?.hiddenByPimp.count ?? 0 }
        // Возврат снимка или раскладки при спрятанных окнах (гейт 1 WF111): свёрнутых нет в списке
        // окон, и их чаты вынеслись бы заново дублями — сперва показываем, возврат ждёт анимацию.
        pimp.seats.showHiddenForRestore = { [weak self] in
            guard let self = self, self.hiddenByPimp.count > 0 else { return false }
            return !self.unhideAll().isEmpty
        }
        // #8282: пока окна спрятаны, канал probe спрашивает страницы, ждёт ли чат Элвиса.
        chatProbe.isWaitWanted = { [weak self] in (self?.hiddenByPimp.count ?? 0) > 0 }
    }

    /// Окна, которые свернул Пимп (`hideOthers`); `showHidden` список чистит.
    private let hiddenByPimp = HiddenWindows<AXUIElement> { AX.bool($0, kAXMinimizedAttribute) }

    /// Окна двигает другая работа: канал «Пимп», цепочка «Нового окна» или возврат снимка К5.
    private var windowsBusy: Bool {
        pimp.isBusy || actions.newWindowBusy || windowSnapshots.phase == .restoring
    }

    /// Канал «Пимп» занят, идёт цепочка «Нового окна» или окна Claude ещё не «как были»: Claude закрыт или только
    /// что запущен (сторож снимка К5 его ещё не видел), снимок заморожен, возврат ждёт или идёт. Автообновление
    /// Пимпа в такой момент себя не подменяет (WF217, К-SU, находка R2 проверки 10.10.2026): выход оборвал бы
    /// возврат, а запрос канала (`restart-claude` ждёт окна до 130 с) получил бы от нового Пимпа `stale`.
    public var isSettlingWindows: Bool { windowsBusy || windowSnapshots.outcome == .pending }

    /// Окна Claude на экране глазами «спрятать»: главное — по заголовку или по рамке его страницы;
    /// `keep` — окно главного проекта (`mainProject` живого claude.json, гейт WF111: там Рик).
    private func hideSeen() -> (listed: [(id: CGWindowID, window: AXUIElement, title: String, frame: CGRect)],
                                seen: [WindowHide.Seen]) {
        actions.beginWindowBatch()
        defer { actions.endWindowBatch() }
        let listed = actions.pimpWindows()
        let entry = mainProjectSetting()
        return (listed, listed.map {
            let folder = pimpWindow(id: $0.id, title: $0.title, frame: $0.frame).folder
            return WindowHide.Seen(title: $0.title,
                            isMain: windowIdentity(title: $0.title, frame: $0.frame).isMain,
                            fullScreen: AX.bool($0.window, MinimizeMenu.fullScreenAttribute) == true,
                            keep: entry != nil && PimpChannel.isMainProject(folder: folder, entry: entry),
                            projectKnown: entry == nil || !folder.isEmpty)
        })
    }

    /// `mainProject` живого claude.json (гейт WF111, #8284); файл крошечный — читаем, когда нужен.
    private func mainProjectSetting() -> String? {
        PimpChannel.mainProjectSetting(try? Data(contentsOf: CommandChannel.directory
            .appendingPathComponent(StatusFeed.configFileName)))
    }

    /// Тик: чаты окон главного проекта — полю `keep` команды `dim` (вуаль и рамка их не трогают).
    /// Нет ключа — `keep` пуст. Ключ есть, а ни одного чата не опознали (карта probe молчит) — прежний
    /// набор держим: иначе на миг молчания вуаль легла бы на Рика.
    private var dimMainProject: String?

    private func updateMainProjectKeep() {
        let entry = mainProjectSetting()
        // Явная смена проекта не является временно неполным ответом probe: прежние исключения снимаем.
        if entry != dimMainProject {
            dimMainProject = entry
            pageLook.setKeep([])
        }
        guard let entry = entry else { pageLook.setKeep([]); return }
        let chats = PimpChannel.mainProjectChats(pimpWindowList(), entry: entry)
        if !chats.isEmpty { pageLook.setKeep(chats) }
    }

    /// Свернуть все окна Claude, кроме главного (AX `kAXMinimizedAttribute`). Главное не трогаем
    /// и не двигаем; ChatGPT и прочие программы — тоже. Окно, которое не свернулось, в итог не идёт.
    public func hideOthers() -> WindowHideResult {
        guard app.running() != nil else { return WindowHideResult(failure: .noWindows) }
        guard !windowsBusy else { return WindowHideResult(failure: .busy) }
        let (listed, seen) = hideSeen()
        if seen.contains(where: { !$0.projectKnown }) { chatProbe.demand(at: Date()) }
        switch WindowHide.plan(seen, minimized: actions.minimizedCount()) {
        case .refuse(let failure):
            return WindowHideResult(failure: failure)
        case .hide(let indices, let skipped):
            let done = indices.filter { AX.set(listed[$0].window, kAXMinimizedAttribute, bool: true) }
            hiddenByPimp.add(done.map { listed[$0].window })
            return WindowHideResult(titles: done.map { listed[$0].title }, skipped: skipped)
        }
    }

    /// Развернуть все свёрнутые окна Claude; когда кончится анимация — фокус главному окну
    /// (приём `showAll`: развёрнутое окно встаёт поверх и забирает клавиатуру у Рика).
    public func showHidden() -> WindowHideResult {
        guard app.running() != nil else { return WindowHideResult(failure: .noWindows) }
        app.forgetWindows()
        let all = app.windows()
        guard !all.isEmpty else { return WindowHideResult(failure: .noWindows) }
        guard !windowsBusy else { return WindowHideResult(failure: .busy) }
        return WindowHideResult(titles: unhideAll(all))
    }

    /// Главное окно Claude — на экран: свёрнутое развернуть, закрытое показать. Красная кнопка главное
    /// окно не закрывает, а прячет, и «открыть приложение» (reopen, как клик по значку в Доке) показывает
    /// его снова; свёрнутое при других окнах на экране reopen не трогает — его разворачиваем сами.
    private func showMainWindow() -> Bool {
        guard let running = app.running() else { return false }
        app.forgetWindows()
        if let main = app.windows().first(where: {
            AX.bool($0, kAXMinimizedAttribute) == true
                && ClaudeActions.isMainWindowTitle(AX.string($0, kAXTitleAttribute) ?? "")
        }) {
            return AX.set(main, kAXMinimizedAttribute, bool: false)
        }
        guard let url = running.bundleURL else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    /// Развернуть свёрнутые окна Claude (все, не только спрятанные Пимпом) и забыть список Пимпа;
    /// фокус — главному, когда кончится анимация. Без проверки занятости: её делают звавшие.
    private func unhideAll(_ known: [AXUIElement]? = nil) -> [String] {
        let all: [AXUIElement]
        if let known = known { all = known } else {
            app.forgetWindows()
            all = app.windows()
        }
        hiddenByPimp.clear()
        let titles = all.filter { AX.bool($0, kAXMinimizedAttribute) == true }.compactMap { window in
            AX.set(window, kAXMinimizedAttribute, bool: false) ? AX.string(window, kAXTitleAttribute) ?? "" : nil
        }
        if !titles.isEmpty { focusMainSoon() }
        return titles
    }

    /// Фокус — окну Рика, когда кончится анимация разворота (приём `showAll`): окну главного проекта,
    /// а нет такого — главному окну.
    private func focusMainSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + WindowHide.focusDelay) { [weak self] in
            guard let self = self else { return }
            let (listed, seen) = self.hideSeen()
            guard let main = seen.firstIndex(where: { $0.keep }) ?? seen.firstIndex(where: { $0.isMain }) else { return }
            self.app.focus(window: listed[main].window)
        }
    }

    /// Окно, которое развернул разворот «ждёт Элвиса» (#8282); пока оно на экране и его чат всё ждёт,
    /// следующее не разворачиваем — по одному.
    private var waitShown: AXUIElement?

    /// Тик 2 с (#8282, слово Рика 30.09: «окно, где ждут Элвиса, должно быть видно»): спрятанное Пимпом
    /// окно, чей чат ждёт слова Элвиса (`status().attention.want` страницы), разворачивается само, одно; остальные
    /// спрятаны. Claude впереди — клавиатура возвращается главному окну (там Рик).
    private func showWaitingTick() {
        let resolve: (String, CGRect?) -> WindowIdentity = { [weak self] title, frame in
            self?.windowIdentity(title: title, frame: frame) ?? .unknown
        }
        if let shown = waitShown {
            // Снова свёрнуто или закрыто — забыли; на экране и чат всё ждёт (или круг без ответа) — ждём и мы.
            if AX.bool(shown, kAXMinimizedAttribute) == false,
               let page = WindowHide.page(for: (AX.string(shown, kAXTitleAttribute) ?? "", AX.frame(shown)),
                                          in: chatProbe.pages, resolve: resolve),
               page.waiting != false { return }
            waitShown = nil
        }
        guard hiddenByPimp.count > 0, !windowsBusy else { return }
        let hidden = hiddenByPimp.current
        let seen = hidden.map { (title: AX.string($0, kAXTitleAttribute) ?? "", frame: AX.frame($0)) }
        guard let index = WindowHide.waiting(seen, pages: chatProbe.pages, resolve: resolve),
              AX.set(hidden[index], kAXMinimizedAttribute, bool: false) else { return }
        let window = hidden[index]
        hiddenByPimp.remove { CFEqual($0, window) }
        waitShown = window
        if app.isFrontmost { focusMainSoon() }
    }

    // MARK: - вид страницы и отсчёт отправки

    private func connectPageLook() {
        pageLook.write = { [weak self] action, fields, priority in
            self?.commands.write(action: action, fields: fields, priority: priority) ?? false
        }
        // Прежний CLI show адресует главное окно; кнопка панели выбирает видимое ниже.
        pageLook.mainMatch = { [weak self] in self?.actions.mainWindowMatch() }
        pageLook.isRunning = { [weak self] in self?.app.running() != nil }
        pimp.seats.bypassNew = { UserDefaults.standard.bool(forKey: BypassNew.key) }
        pimp.seats.setDim = { [weak self] on, percent in
            self?.pageLook.setDim(on: on, percent: percent) ?? PageLook()
        }
        pimp.seats.setLook = { [weak self] style, size, grow, show in
            self?.pageLook.setLook(style: style, size: size, grow: grow, show: show) ?? (PageLook(), false)
        }
    }

    public var sendDelaySetting: SendDelaySetting { pageLook.sendDelaySetting(pages: chatProbe.pages) }

    public func setSendDelay(on: Bool, seconds: Int) { pageLook.setSendDelay(on: on, seconds: seconds) }

    public var pinnedLook: PinnedLook {
        get { pageLook.pinned }
        set { pageLook.setPinned(newValue) }
    }

    /// Звук отсчёта (WF151, #9108): `countdownSound` живого claude.json, нет/мусор — `bell`.
    public var countdownSound: CountdownSound { pageLook.countdownSound }

    public func setCountdownSound(_ sound: CountdownSound) { pageLook.setCountdownSound(sound) }

    /// Второй Enter и ⇧Enter во время отсчёта (WF126 §7.2).
    public var enterKeys: EnterKeys { pageLook.enterKeys }

    public func setEnterKeys(second: EnterKeys.Second? = nil, shift: EnterKeys.Shift? = nil) {
        pageLook.setEnterKeys(second: second, shift: shift)
    }

    /// «Bypass permissions во всех чатах» (WF126 §7.3 путь А, WF161 путь Б #9060): черновикам, что открывает PMP,
    /// и командой `bypass-chats` — каждой странице; новое поколение страниц получает выбор повтором.
    public var bypassNewChats: Bool {
        get { pageLook.bypassChats }
        set { pageLook.setBypassChats(newValue) }
    }

    /// Блок «Текст» панели (WF167, #9168): по ширине или влево — команда `text-justify` всем страницам,
    /// новое поколение страниц получает выбор повтором; ключа нет — показываем «по ширине», команды нет.
    public var textJustify: Bool {
        get { pageLook.textJustify }
        set { pageLook.setTextJustify(newValue) }
    }

    /// «Чистые ответы» (WF210, #9398, К-CA): строки расхода и состояния под ответами спрятаны — команда
    /// `clean-answers` всем страницам, новое поколение получает выбор повтором; ключа нет — включено, команды нет.
    public var cleanAnswers: Bool {
        get { pageLook.cleanAnswers }
        set { pageLook.setCleanAnswers(newValue) }
    }

    /// Вид отсчёта (К1 v3, #9041): выбранный из восьми, ключа нет — «1.8» «Ракета».
    public var sendLookStyle: String { pageLook.current.style }

    /// Выбор вида в панели: память и рассылка `send-look` всем страницам без показа. Нажатие уже выбранного вида тоже
    /// шлёт команду (WF180): страница, пропустившая прошлую, получает выбор сразу, а не на следующем поколении.
    public func setSendLookStyle(_ style: String) {
        guard SendLook.isStyle(style) else { return }
        pageLook.setLook(style: style)
    }

    /// Разрешён ли Bypass в самом Claude — только чтение его файла настроек.
    public var bypassPermission: BypassNew.Permission { BypassNew.permission() }

    /// Окно настроек Claude (пункт «Settings…» его меню); false — пункта не нашли.
    @discardableResult
    public func openClaudeSettings() -> Bool { actions.pressClaudeSettings() }

    private func sendDelayPreviewTarget() -> ClaudeActions.SendDelayPreviewTarget? {
        guard let pid = app.pid else { return nil }
        // Один свежий AX-снимок на подбор; через focusDelay он не переносится.
        actions.beginWindowBatch()
        defer { actions.endWindowBatch() }
        let windows = actions.pimpWindows()
        let focused = app.isFrontmost ? app.focusedWindow() : nil
        let focusedID = windows.first { entry in focused.map { CFEqual(entry.window, $0) } ?? false }?.id
        let visible = ClaudeApp.onScreenFrames(pid: pid).compactMap { frame -> (id: CGWindowID, page: ChatPage?)? in
            guard let window = windows.first(where: { $0.id == frame.id }) else { return nil }
            return (window.id, windowIdentity(id: window.id, title: window.title, frame: window.frame).page)
        }
        return ClaudeActions.sendDelayPreviewTarget(visible: visible, focused: focusedID, pages: chatProbe.pages)
    }

    /// «Показать» без опознанного окна (WF180, слово Элвиса 09.10 02:50: «"Показать" нажимаю — ничего, "Окно ещё не
    /// опознано"»): карта чатов бывает пустой — страница ещё не ответила или канал probe держит агент на гейте
    /// (ChatProbe уступает). Тогда спрашиваем опознание и сами повторяем `sendDelayPreviewRetries` раз через
    /// `sendDelayPreviewRetrySeconds`, а не опознали — показываем главному окну Claude на экране (команда без адреса,
    /// страница играет в главном). Отказ человеку — только когда окна Claude правда нет.
    static let sendDelayPreviewRetries = 3
    static let sendDelayPreviewRetrySeconds: TimeInterval = 0.7

    /// Поздний отказ показа (после повторов): строка для панели. Главная нить.
    public var onSendDelayPreviewFailed: ((String) -> Void)?

    public func previewSendDelay(seconds: Int) -> String? {
        guard SendDelaySetting.validSeconds(seconds) else { return "Выбери 3, 5 или 10 секунд" }
        guard let pid = app.pid, !actions.pimpWindows().isEmpty else {
            return "Открой окно Claude, чтобы показать отсчёт"
        }
        if let target = sendDelayPreviewTarget() {
            playSendDelayPreview(seconds: seconds, target: target, pid: pid)
        } else {
            chatProbe.demandIdentity(native: actions.windowCensus().native)
            retrySendDelayPreview(seconds: seconds, pid: pid, attempt: 1)
        }
        return nil
    }

    private func retrySendDelayPreview(seconds: Int, pid: pid_t, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sendDelayPreviewRetrySeconds) { [weak self] in
            guard let self = self, self.app.pid == pid else { return }
            if let target = self.sendDelayPreviewTarget() {
                return self.playSendDelayPreview(seconds: seconds, target: target, pid: pid)
            }
            if attempt < Self.sendDelayPreviewRetries {
                self.chatProbe.demandIdentity(native: self.actions.windowCensus().native)
                return self.retrySendDelayPreview(seconds: seconds, pid: pid, attempt: attempt + 1)
            }
            let windows = self.actions.pimpWindows()
            let focused = self.app.isFrontmost ? self.app.focusedWindow() : nil
            let candidates = windows.map { entry in
                (id: entry.id, main: self.windowIdentity(id: entry.id, title: entry.title, frame: entry.frame).isMain
                    || self.actions.isMainWindowTitle(entry.title),
                 focused: focused.map { CFEqual(entry.window, $0) } ?? false)
            }
            guard let id = ClaudeActions.sendDelayFallbackWindow(candidates) else {
                self.onSendDelayPreviewFailed?(windows.isEmpty ? "Открой окно Claude, чтобы показать отсчёт"
                                                               : "Открой главное окно Claude, чтобы показать отсчёт")
                return
            }
            self.actions.raise(id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + self.actions.focusDelay) { [weak self] in
                guard let self = self, self.app.pid == pid else { return }
                _ = self.pageLook.previewSendDelayMain(seconds: seconds)
            }
        }
    }

    private func playSendDelayPreview(seconds: Int, target: ClaudeActions.SendDelayPreviewTarget, pid: pid_t) {
        // Панель успевает закрыться; после подъёма ещё раз сверяем видимость и тот же адрес (М1 критика).
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.app.pid == pid,
                  self.actions.pimpWindows().contains(where: { $0.id == target.id }) else { return }
            self.actions.raise(id: target.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + self.actions.focusDelay) { [weak self] in
                guard let self = self, self.app.pid == pid, self.sendDelayPreviewTarget() == target else { return }
                _ = self.pageLook.previewSendDelay(seconds: seconds, match: target.match, chat: target.chat)
            }
        }
    }

    // MARK: - «📦 Архив чатов» (#7729, план WF94 Б2)

    private lazy var chatArchive = ChatArchive.standard()

    private func connectChatArchive() {
        menu.archiveChats = { [weak self] in self?.archiveChats() }
        menu.archiveBusy = { [weak self] in self?.archiveBusy ?? false }
    }

    /// Бэкап собирается прямо сейчас: пункт меню и строка панели пишут «идёт…» (WF97 Б5s).
    public var archiveBusy: Bool { chatArchive.isBusy }
    /// Бэкап кончился (успех или отказ) — панели у часов вернуть подпись. Главная нить.
    public var onArchiveDone: (() -> Void)?
    /// Кнопка «PMP» в окне Claude (WF125 #8894): открыть панель у часов. Главная нить.
    public var onPanelRequest: (() -> Void)?

    /// Все чаты Claude Code одним zip на склад — в фоне; второй клик во время сборки ничего не
    /// делает. Итог — алертом с «Показать в Finder», отказ — плашкой.
    public func archiveChats() {
        let started = chatArchive.start { [weak self] outcome in
            self?.onArchiveDone?()
            switch outcome {
            case .success(let summary): ChatArchive.presentDone(summary)
            case .failure(let failure):
                self?.hud.show(failure.notice, seconds: MenuModel.archiveChatsFailSeconds)
            }
        }
        // Второй клик во время сборки — второго zip нет, но и молчать нельзя (#7772): «уже идёт».
        hud.show(started ? MenuModel.archiveChatsNotice : MenuModel.archiveChatsBusyNotice,
                 seconds: started ? MenuModel.archiveChatsNoticeSeconds : MenuModel.repeatNoticeSeconds)
    }

    // MARK: - Pimp Viewer (WF97, #7719–#7724; с WF104 — PimpViewer.app, К-V8)

    /// Маршрут из чата в галерею и её ручки на порту 47615 (К-V1, К-V2, К-V7, К-V8). Зовут из `start()`.
    private func connectViewer() {
        htmlOpener.toViewer = { [weak self] request, done in
            guard let self = self else { return done(false) }
            self.viewerClient.accept(path: request.path, mode: request.mode, chat: request.chat, done: done)
        }
        htmlOpener.onViewer = { [weak self] request in self?.viewerClient.gallery(chat: request.chat, on: request.on) }
        htmlOpener.onNudge = { [weak self] chat, counts in self?.sendViewerState(chat: chat, counts: counts) }
        // «в чат» из галереи: индекс и окна — на главной, ответ галерее — после работы.
        htmlOpener.onOpenChat = { [weak self] chat, reply in
            DispatchQueue.main.async {
                guard let self = self, let chat = chat else { return reply("chat-closed") }
                reply(self.viewerOpenChat(chat) ?? "ok")
            }
        }
        viewerClient.onMissing = { [weak self] in
            DispatchQueue.main.async { self?.hud.show("🖼 Галерея не установлена", seconds: 2.5) }
        }
        connectFileView()
        menu.showViewer = { [weak self] in self?.showViewer() }
        viewerClient.start()
    }

    /// `/state` галереи → страницам `viewer-chat` (К-V2) и/или `viewer-counts` (К-V7). Запрос — на очереди
    /// клиента, запись команды — на главной: у `CommandChannel` нет замка.
    private func sendViewerState(chat: Bool, counts: Bool, completion: ((Bool) -> Void)? = nil) {
        viewerClient.state { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self, let state = state else { completion?(false); return }
                if chat {
                    _ = self.commands.write(action: "viewer-chat", fields: [
                        (key: "scope", value: .string("all")),
                        (key: "chat", value: state.filterChat.map { .string($0) } ?? .null)])
                }
                if counts {
                    let value = CommandValue.object(state.counts.sorted { $0.key < $1.key }.map {
                        (key: $0.key, value: CommandValue.array($0.value.map { .number($0) }))
                    })
                    _ = self.commands.write(action: "viewer-counts", fields: [
                        (key: "scope", value: .string("all")), (key: "chats", value: value)], completion: completion)
                } else { completion?(true) }
            }
        }
    }

    /// Число токенов остывшего чата (WF106 #8103) → страницам `chat-context`. Зовут на очереди порта: индекс —
    /// берётся из опубликованного снимка, расшифровка — на фоне, запись команды — на главной.
    private func sendChatContext(_ chat: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self,
                  let cli = self.knownChat(chat)?.cli,
                  let tokens = ChatContext.tokens(cliSessionId: cli) else { return }
            DispatchQueue.main.async { ChatContext.send(chat: chat, tokens: tokens, via: self.commands) }
        }
    }

    /// HTTP readers use the latest index snapshot; UI work remains on main.
    private func connectFileView() {
        refreshChatLookup()
        htmlOpener.isKnownChat = { [weak self] chat in self?.knownChat(chat) != nil }
        htmlOpener.onView = { [weak self] request in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let cwd = request.chat.flatMap { self.index.session(for: $0) }?.cwd.path
                self.fileView.show(request, cwd: cwd)
            }
        }
        fileView.onReturn = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self = self, let pid = self.app.pid else { return }
                let windows = frame == nil ? [] : self.app.visibleWindows()
                guard let frame = frame, let best = FileView.nearest(frame, among: windows.map { AX.frame($0) }) else {
                    self.app.activate()
                    return
                }
                let window = windows[best]
                self.app.focus(window: window)
                // Activation may raise the previous key window. Retry once without blocking
                // the main queue, and only while this process and AX window still exist.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self = self, self.app.pid == pid,
                          AX.value(window, kAXRoleAttribute) != nil else { return }
                    self.app.forgetWindows()
                    guard self.app.windows().contains(where: { CFEqual($0, window) }) else { return }
                    self.app.focus(window: window)
                }
            }
        }
        // «в галерею»: `click` — галерея раскрывает карточку и выходит вперёд; не взяла — браузер.
        fileView.toGallery = { [weak self] path, chat in
            guard let self = self else { return }
            let request = HtmlChromeOpener.Request(path: path, mode: .click, chat: chat)
            guard let toViewer = self.htmlOpener.toViewer else { return self.htmlOpener.openInBrowser(path) }
            toViewer(request) { [weak self] taken in
                if !taken { self?.htmlOpener.openInBrowser(path) }
            }
        }
        fileView.toBrowser = { [weak self] path in self?.htmlOpener.openInBrowser(path) }
    }

    /// «💛 Поддержать автора» последним пунктом меню жёлтой кнопки (WF108, #8179): видимость
    /// (окну есть что показать и не выключено) и окно — у приложения.
    public func setDonate(visible: @escaping () -> Bool, open: @escaping () -> Void) {
        menu.donateVisible = visible
        menu.showDonate = open
    }

    /// «🖼 Pimp Viewer» из меню жёлтой кнопки и панели у часов: окно галереи вперёд; приложения нет — плашка.
    public func showViewer() {
        viewerClient.show()
    }

    /// «в чат» из Viewer: окно чата открыто — вперёд; нет — вынести тем же путём, что
    /// `pimp.py open --last` (главное окно выносит чат отдельным окном).
    private func viewerOpenChat(_ chat: String) -> String? {
        guard app.running() != nil else { return "chat-closed" }
        let windows = pimp.seats.windows()
        if let open = PimpChannel.window(chat: chat, title: pimpTitle(forChat: chat), in: windows) {
            actions.raise(id: open.id)
            return nil
        }
        guard let session = index.session(for: chat), !session.isArchived,
              windows.contains(where: { $0.isMain(using: actions.isMainWindowTitle) }) else { return "chat-closed" }
        pimp.seats.openChat(chat, session.title, PimpChannel.popoutOrigin(.right, near: windows.first?.frame))
        return nil
    }

    // MARK: - кружок-микрофон (#7054, контракт К4, батч M2 WF84)

    /// Диктатор сейчас пишет (или запись на паузе) — автообновление Пимпа в такой момент себя не
    /// перезапускает (WF217, К-SU). Спрашиваем самого Диктатора: `dictating` страницам зависит ещё и от «Света окна».
    public var isDictating: Bool { micMonitor.dictatorRunning && micMonitor.dictatorState().isRecording }

    private func connectMic() {
        micMonitor.pages = { [weak self] in self?.chatProbe.pages ?? [] }
        micMonitor.claudePID = { [weak self] in self?.app.pid }
        micMonitor.windowTitle = { [weak self] frame in
            self?.app.window(matching: frame).flatMap { AX.string($0, kAXTitleAttribute) }
        }
        micMonitor.sendMode = { [weak self] mode in self?.actions.sendMic(mode) ?? false }
        micMonitor.sendDictating = { [weak self] on in self?.actions.sendDictating(on) ?? false }
        micMonitor.sendRefused = { [weak self] chat, match in
            self?.actions.sendMicRefused(chat: chat, match: match) ?? false
        }
        micMonitor.notice = { [weak self] text in self?.hud.show(text, seconds: 2.5) }
        micMonitor.focusClaude = { [weak self] in self?.app.activate() }
        actions.micMode = { [weak self] in self?.micMonitor.mode ?? .claude }
        // Место значка меняется молча — пока кружок нужен, карта страниц освежается сама.
        chatProbe.isMicWanted = { [weak self] in self?.micMonitor.wantsPages ?? false }
        // Режим `dictator` и кружок виден — раз в 5 с, а не 15 (контракт WF92 (в)).
        chatProbe.isMicFast = { [weak self] in self?.micMonitor.wantsFastPages ?? false }
        // Значок у часов показывает лимиты всегда (WF87): свой круг раз в минуту при любом тумблере.
        chatProbe.isLimitsWanted = { true }
    }

    // MARK: - меню WF84: «Новый чат», Авто-Allow, замок, «Вернуть окна»

    private func connectWF84Menus() {
        // «💬 Новый чат» (#7072): модель донора — из его файла сессии, чат главного окна — из индекса.
        actions.chatModel = { [weak self] chat in self?.index.session(for: chat)?.model }
        actions.mainChat = { [weak self] in self?.index.mainWindow()?.session?.sessionId }
        actions.autoAllowOn = { [weak self] in self?.autoAllowSwitch.on ?? false }
        // Кнопка в чате (#7246): окна с заголовками, у каждого свой короткий срок ответа; клик — тот же
        // путь, что пункт меню ⌘B «💬 Новый чат».
        // Главное окно (гейт 26.09): метку ставит вложенная страница claude.ai, а заголовок окна
        // остаётся «Claude» — к заголовкам окон добавляются заголовки их страниц (`ContinueWebAreas`).
        continueWatch.windows = { [weak self] in
            guard let self = self, AX.isTrustedCached else { return [] }
            let windows = self.app.windows().compactMap { window -> (window: AXUIElement, title: String)? in
                AX.timeout(window, PimpLock.titleTimeout)
                return AX.string(window, kAXTitleAttribute).map { (window: window, title: $0) }
            }
            return self.continueWatch.pages.titles(of: windows, now: Date.timeIntervalSinceReferenceDate)
        }
        continueWatch.onContinue = { [weak self] window in self?.actions.handoffNewChat(window) }
        // «↩️ Вернуть окна» (#7065): метод батча W, плашка — здесь, где известно, начали ли.
        menu.restoreWindows = { [weak self] in
            guard let self = self else { return }
            let restoring = self.windowSnapshots.phase == .restoring
            let started = self.restoreWindows()
            self.hud.show(started ? MenuModel.restoreWindowsNotice
                                  : restoring ? MenuModel.restoreWindowsBusyNotice : MenuModel.restoreWindowsNothingNotice,
                          seconds: MenuModel.newWindowNoticeSeconds)
        }
    }

    // MARK: - окна как были (#7065, контракт К5)

    /// Сиденья снимка окон. Окна — те же, что у канала «Пимп»; возврат — его очередью, так
    /// что пункт меню, запрос из чата и автовозврат друг с другом не спорят.
    private func connectWindowSnapshots() {
        windowSnapshots.claude = { [weak self] in
            guard let self = self, let pid = self.app.pid else { return nil }
            return (pid: pid, launch: self.app.launchDate, version: self.claudeVersion(pid: pid))
        }
        windowSnapshots.windows = { [weak self] in
            guard let self = self else { return [] }
            return WindowSnapshotStore.windows(from: self.pimpWindowList(),
                                               isMain: self.actions.isMainWindowTitle,
                                               screen: ClaudeAXController.screenName)
        }
        windowSnapshots.observation = { [weak self] in
            self?.snapshotObservation() ?? SnapshotObservation(windows: [], complete: false)
        }
        windowSnapshots.busy = { [weak self] in
            guard let self = self else { return true }
            return self.pimp.isBusy || self.actions.newWindowBusy
        }
        windowSnapshots.adaptFrame = { [weak self] in self?.restoreFrame($0) ?? $0 }
        windowSnapshots.pageReady = { [weak self] launch in
            guard let self = self else { return false }
            let since = launch ?? .distantPast
            return self.chatProbe.pages.contains { $0.kind == .main && $0.at >= since }
        }
        windowSnapshots.demandPages = { [weak self] in self?.chatProbe.demand() }
        windowSnapshots.startRestore = { [weak self] snapshot in
            self?.pimp.startRestore(snapshot: snapshot, name: WindowSnapshotStore.restoreName) ?? false
        }
        windowSnapshots.isRestoring = { [weak self] in self?.pimp.isRestoring ?? false }
        // WF108 (#8176): `restart-claude` — кто работает, путь «Обновить Claude» (его ведёт приложение,
        // `restartClaude`) и ждёт ли снимок свой Claude; окна вернёт автовозврат выше.
        pimp.seats.restoreWindows = { [weak self] in
            self?.allWindowObservation() ?? ([], false)
        }
        pimp.seats.restoreFrame = { [weak self] in self?.restoreFrame($0) ?? $0 }
        let namedGuard: ([SnapshotWindow]) -> Bool = { [weak self] expected in
            guard let self = self else { return false }
            return self.windowSnapshots.prepareNamedRestore(expected: expected)
                && self.screenLayouts.prepareNamedRestore(expected: expected)
        }
        pimp.seats.prepareNamedRestore = namedGuard
        pimp.seats.finishNamedRestore = namedGuard
        pimp.seats.restoreFinished = { [weak self] in self?.restoreConfirmationUntil = Date() + OneShotLayoutGuard.lifetimeSeconds }
        screenLayouts.onRestorePlaced = { [weak self] in self?.restoreConfirmationUntil = Date() + OneShotLayoutGuard.lifetimeSeconds }
        pimp.seats.explicitLayout = { [weak self] moves in self?.armLayoutGuard(moves) }
        pimp.seats.explicitNamedLayout = { [weak self] moves in self?.armLayoutGuard(moves, waitForRestore: true) }
        windowSnapshots.prepareOtherRestore = { [weak self] expected in
            self?.screenLayouts.prepareNamedRestore(expected: expected) ?? false
        }
        screenLayouts.prepareOtherRestore = { [weak self] expected in
            self?.windowSnapshots.prepareNamedRestore(expected: expected) ?? false
        }
        pimp.seats.workingChats = { [weak self] since in self?.workingChats(since: since) }
        pimp.seats.restartClaude = { [weak self] done in
            guard let self = self, let restart = self.restartClaude else { return done("перезапуск не подключён") }
            restart(self.app.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleURL }, done)
        }
        pimp.seats.snapshotOutcome = { [weak self] in self?.windowSnapshots.outcome ?? .notNeeded }
        // Гейт 2 WF108: чаты без окна — по свежести транскриптов Claude Code и индексу Desktop.
        pimp.seats.transcriptsRoot = { ChatContext.projectsRoot }
        pimp.seats.desktopSessions = { [weak self] in
            guard let self = self else { return nil }
            return self.index.sessions.compactMap { session in
                session.cliSessionId.map { cli in
                    let title = session.title.isEmpty ? session.sessionId : session.title
                    return (chat: session.sessionId, cli: cli,
                            name: self.index.folder(of: session).lastPathComponent + " / " + title)
                }
            }
        }
    }

    /// Перезапуск Claude для канала (WF108): копия Claude (nil — не знаем, какая запущена) и ответ
    /// `nil` — снова запущен, иначе причина. Вешает приложение — `Patcher` модулю не виден.
    public var restartClaude: ((URL?, @escaping (String?) -> Void) -> Void)?

    /// Чаты, где идёт ответ (кнопка стопа, WF87), — «папка / заголовок». nil — ответа страниц о работе
    /// не раньше `since` нет (как `waitForPages` «Обновить Claude») или карта чатов не наша (probe держит агент).
    private func workingChats(since: Date) -> [(chat: String, name: String)]? {
        guard chatProbe.signals.answered(after: since).workingChats != nil, chatProbe.answered(after: since)
        else { return nil }
        let windows = pimpWindowList()
        return chatProbe.pages.filter { $0.working == true }.map { page in
            let chat = page.chat ?? ""
            let title = ChatProbe.clean(page.title)
            let folder = chat.isEmpty ? "" : windows.first { $0.chat == chat }?.folder ?? ""
            return (chat: chat, name: folder.isEmpty ? title
                        : URL(fileURLWithPath: folder).lastPathComponent + " / " + title)
        }
    }

    /// «↩️ Вернуть окна» (пункт вешает меню, батч M1 WF84): окна, какими они были до запуска
    /// этого Claude, а нет такого снимка — последний записанный. false — вернуть нечего или
    /// канал «Пимп» занят другой работой.
    @discardableResult
    public func restoreWindows() -> Bool {
        windowSnapshots.restoreNow()
    }

    /// Снять окна прямо сейчас — перед тем как закрыть Claude (обновление, батч M2 WF84).
    /// Возврат после нового запуска сработает сам: триггер один, звать `restoreWindows` не надо.
    @discardableResult
    public func saveWindowSnapshot() -> Bool {
        windowSnapshots.saveNow()
    }

    public var pageSignals: PageSignals { chatProbe.signals }

    public func refreshPageSignals() { chatProbe.demand() }

    public func freezeWindowSnapshot(_ frozen: Bool) {
        if frozen { windowSnapshots.freeze() } else { windowSnapshots.thaw() }
    }

    /// Версия выбранного Claude — поле `claude` снимка; бандл читается раз на процесс.
    private func claudeVersion(pid: pid_t) -> String {
        if let known = claudeVersionCache, known.pid == pid { return known.version }
        let version = app.running()?.bundleURL
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? ""
        claudeVersionCache = (pid: pid, version: version)
        return version
    }

    private var claudeVersionCache: (pid: pid_t, version: String)?

    /// Имя экрана, где лежит центр рамки (перевёрнутые координаты), — справка в снимке.
    private static func screenName(_ frame: CGRect) -> String {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { Screens.flip(rect: $0.frame).contains(center) }?
            .localizedName ?? ""
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
                return self.pimpWindowList()
            },
            minimized: { [weak self] in self?.actions.minimizedCount() ?? 0 },
            projects: { [weak self] in self?.knownProjects(limit: ProjectsStore.limit) ?? [] },
            openNewWindow: { [weak self] project, origin in
                // Тот же путь, что пункт меню «🪟 Новое окно ▸ проект»: окно берётся то,
                // что в фокусе у Claude, а команда всё равно адресуется главному (`match`).
                self?.actions.newWindow(in: project, on: nil, origin: origin)
            },
            arrange: { [weak self] ids, mode, hub in
                guard let self = self else { return ([], 0) }
                // Названная плитка становится последней (план WF21): её повторяет полоса
                // раскладок в меню. С WF77 сюда приходит ТОЛЬКО явный `--layout 4|5|5x2|row`
                // — умный путь плитку не трогает (критик блокер 2). «Главный по центру» (WF102)
                // последней не становится: у плитки нет id главного окна.
                if mode != .center { self.actions.themeStore.arrangeMode = mode }
                let done = self.actions.arrange(ids: ids, mode: mode, hub: hub)
                return (windows: done.placed.map {
                    self.pimpWindow(id: $0.id, title: $0.title, frame: $0.frame)
                }, skipped: done.skipped)
            },
            arrangeSmart: { [weak self] ids, ordered, anchor in
                guard let self = self else { return [] }
                return self.actions.arrangeSmart(ids: ids, ordered: ordered, anchor: anchor).map {
                    self.pimpWindow(id: $0.id, title: $0.title, frame: $0.frame)
                }
            },
            arrangeMode: { [weak self] in self?.actions.themeStore.arrangeMode ?? .ribbon },
            fitsLayout: { [weak self] mode in self?.actions.arrangeFits(mode) ?? true },
            place: { [weak self] moves in self?.actions.place(moves) },
            titleForChat: { [weak self] chat in self?.pimpTitle(forChat: chat) },
            newWindowLayers: { [weak self] in self?.actions.lastNewWindowLayers ?? false },
            // Раскладки проектов (план WF41): файл наш, ячейки считает та же арифметика,
            // что «Расставить», а закрытый чат выносит отдельным окном главное окно.
            layouts: { [weak self] in self?.layouts.load() ?? [] },
            saveLayout: { [weak self] layout in self?.layouts.save(layout) ?? false },
            cells: { [weak self] mode, count in
                self?.actions.arrangeCells(mode: mode, count: count) ?? []
            },
            // Умная сетка для снимка и возврата раскладки (#6747, WF84).
            smartGrid: { [weak self] frames in self?.actions.smartGrid(frames: frames) },
            gridCells: { [weak self] grid in self?.actions.gridCells(grid) ?? [] },
            // «Под этим»/«над этим» — с тем же зазором, что между столбцами (#7062).
            gap: { [weak self] in self?.actions.cellGap() ?? 0 },
            isMainWindow: { [weak self] title in self?.actions.isMainWindowTitle(title) ?? false },
            openChat: { [weak self] chat, name, origin in
                self?.actions.popoutChat(chat: chat, name: name, origin: origin)
            },
            // Возврат раскладки из МЕНЮ ответа не пишет никому: без этой плашки пункт
            // «↩︎ Вернуть эти чаты» молчал до конца работы и после неё (#5689). Той же
            // плашкой канал говорит «сделал 2 из 3» (действие `hud`, план WF75).
            notice: { [weak self] text in
                self?.hud.show(text, seconds: MenuModel.newWindowNoticeSeconds)
            },
            // Голосовой Пимп (план WF75): поднять окно, закрыть окно, окно в фокусе и ⌘V.
            raise: { [weak self] id in self?.actions.raise(id: id) },
            close: { [weak self] id in self?.actions.close(id: id) ?? false },
            frontWindow: { [weak self] in self?.actions.frontWindowID() },
            paste: { [weak self] id, paths, done in
                guard let self = self else {
                    done(false)
                    return
                }
                self.actions.paste(into: id, paths: paths, done: done)
            },
            lastChat: { [weak self] folder in self?.lastChat(in: folder) },
            // Пустое окно проекта (план WF88, К17): пункт меню выбранного Claude, окна по AX,
            // команда черновику и свой опрос 0,25 с.
            newWindowBusy: { [weak self] in self?.actions.newWindowBusy ?? false },
            blankWindows: { [weak self] in
                self?.actions.blankWindows().map { PimpWindow(id: $0.id, title: $0.title, frame: $0.frame) } ?? []
            },
            pressDraftItem: { [weak self] project in self?.actions.pressDraftItem(project: project) ?? false },
            draftSetup: { [weak self] fields in self?.actions.sendDraftSetup(fields) },
            chatModel: { [weak self] chat in self?.index.session(for: chat)?.model },
            schedule: { delay, block in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block) })
    }

    /// Последний чат папки (контракт WF75): свежайшая НЕ архивная сессия индекса Claude
    /// с этой папкой. Карта probe тут ни при чём — она знает только чаты, уже открытые
    /// окнами, и молчит при выключенном тумблере «🗂 Цвет по проекту» (критик Б1).
    /// Чаты индекс отдаёт свежими вперёд, поэтому первая же подходящая и есть последняя.
    private func lastChat(in folder: URL) -> (chat: String, title: String)? {
        let wanted = folder.standardizedFileURL.path
        for session in index.sessions where !session.isArchived {
            guard index.folder(of: session).standardizedFileURL.path == wanted else { continue }
            return (chat: session.sessionId, title: session.title)
        }
        return nil
    }

    /// Сколько ждём круг опознания чатов (#5770): лоадер читает `probe.js` раз в 500 мс,
    /// а ответ забирает СЛЕДУЮЩИЙ тик — это два тика по 2 с плюс запас. Не дождались (канал
    /// занял агент на гейте) — работаем как раньше: чат окна неизвестен, и снимок скажет
    /// об этом плашкой.
    static let chatsWaitSeconds: TimeInterval = 8

    /// Начинается «💾 Сохранить эту раскладку…» (зовётся ДО вопроса об имени): просим страницы
    /// назвать свои чаты и ждём ответа (#5770) — иначе при выключенном тумблере «🗂 Цвет по
    /// проекту» карта чатов пуста, и снимок отказывал плашкой «не знаю, какие чаты в окнах»,
    /// хотя к раскладкам тумблер отношения не имеет. По той же карте считается имя по
    /// проектам окон (#5769) — его приложение подставляет в поле диалога.
    private func prepareLayoutSave() -> String {
        waitForChats()
        return LayoutsStore.suggestedName(for: pimpWindowList())
    }

    /// Спросить страницы и дождаться круга. Главный цикл крутим сами: круг уезжает и приезжает
    /// на общем тике 2 с, а он живёт на этой же нити — обычный сон заморозил бы и его.
    private func waitForChats() {
        let since = Date()
        chatProbe.demand(at: since)
        let deadline = since.addingTimeInterval(ClaudeAXController.chatsWaitSeconds)
        while !chatProbe.answered(after: since), Date() < deadline {
            // Цикл вернул «крутить нечего» (таймера тика нет — приложение не запущено):
            // ждать бессмысленно, круга всё равно не будет.
            guard RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) else { break }
        }
    }

    /// Окна Claude для раскладок: то же, что отдаёт канал «Пимп».
    private func pimpWindowList() -> [PimpWindow] {
        actions.beginWindowBatch()
        defer { actions.endWindowBatch() }
        return actions.pimpWindows().map { pimpWindow(id: $0.id, title: $0.title, frame: $0.frame) }
    }

    private func allWindowObservation() -> (windows: [PimpWindow], complete: Bool) {
        actions.beginWindowBatch()
        defer { actions.endWindowBatch() }
        let census = actions.windowCensus()
        let windows = census.windows.map { pimpWindow(id: $0.id, title: $0.title, frame: $0.frame) }
        let checked = WindowSnapshotStore.observe(from: windows, complete: census.complete,
                                                   isMain: { _ in false }, screen: { _ in "" })
        return (windows, checked.complete)
    }

    private func snapshotObservation() -> SnapshotObservation {
        let census = allWindowObservation()
        return WindowSnapshotStore.observe(from: census.windows, complete: census.complete,
                                            isMain: actions.isMainWindowTitle, screen: Self.screenName)
    }

    private func restoreFrame(_ frame: CGRect) -> CGRect {
        RestoreFrame.adapt(frame, screens: Screens.all().map { $0.usable }, minWidth: ClaudeActions.minFrameWidth())
    }

    /// «💾 Сохранить эту раскладку…» (план WF41): тот же снимок, что у канала. Окно, чей чат
    /// приложение не знает, отменяет запись целиком — вернулись бы не те чаты (#5455);
    /// возвращаем строку для плашки, nil — записано.
    private func saveLayout(named name: String) -> String? {
        let census = allWindowObservation()
        guard census.complete else { return MenuModel.layoutChatUnknownAlert(census.windows.map { $0.title }) }
        let windows = census.windows
        guard !windows.isEmpty else { return MenuModel.layoutNoWindowsAlert }
        let mode = actions.themeStore.arrangeMode
        // Сетка — плитка или умная расстановка, где окон стоит больше (#6747, WF84).
        let snapshot = LayoutsStore.bestSnapshot(
            name: name, at: Date(), mode: mode, windows: windows,
            tileCells: actions.arrangeCells(mode: mode,
                                            count: ArrangeLayout.capacity(of: mode) ?? windows.count),
            smart: actions.smartGrid(frames: windows.map { $0.frame }),
            isMain: actions.isMainWindowTitle)
        guard snapshot.unknown.isEmpty else {
            return MenuModel.layoutChatUnknownAlert(snapshot.unknown)
        }
        // Every saved record needs a valid absolute frame or a legacy grid cell.
        guard LayoutsStore.placedCells(snapshot.layout) > 0 else {
            return MenuModel.layoutNotArrangedAlert
        }
        return layouts.save(snapshot.layout) ? nil : MenuModel.layoutWriteFailed
    }

    /// Окно канала: к заголовку и рамке добавляются чат и папка — их знает индекс Claude
    /// и карта probe. Карта молчит (тумблер выключен, канал занят агентом) — обе строки пусты.
    private func pimpWindow(id: CGWindowID, title: String, frame: CGRect) -> PimpWindow {
        let identity = windowIdentity(id: id, title: title, frame: frame)
        let chat = identity.page?.chat
        let folder = chat.flatMap { index.folder(for: $0) }?.path ?? ""
        return PimpWindow(id: id, title: title, chat: chat ?? "", folder: folder, frame: frame,
                          main: identity.isMain)
    }

    /// Какой чат в окне с таким заголовком и рамкой: главное окно носит заголовок своего
    /// чата (тот же путь, что `ProjectPaint.windowKey`), попапы — по карте probe, а среди
    /// однофамильцев нужного находит рамка окна (план WF77): без неё оба окна «Ожидание
    /// задачи» назывались одним чатом, и раскладка возвращала не те окна (#6734).
    private func windowIdentity(id: CGWindowID? = nil, title: String, frame: CGRect?) -> WindowIdentity {
        let native = actions.windowCensus().native
        let result = WindowIdentity.resolveNative(id: id, title: title, frame: frame, pages: chatProbe.pages,
                                                  nativeWindows: native, at: Date())
        if result.page == nil { chatProbe.demandIdentity(native: native) }
        return result
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

    // Passive input invalidates the one shot even if an entire drag happens between ticks.
    // Missing monitor registration is not evidence of user inactivity.
    private func startLayoutInputMonitors() {
        guard started, isAccessibilityTrusted, !layoutMonitorAttempted else { return }
        layoutMonitorAttempted = true
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .keyDown, .scrollWheel]
        layoutGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.layoutGuard.disarm()
            self?.screenLayouts.cancelWake()
        }
        layoutLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.layoutGuard.disarm()
            self?.screenLayouts.cancelWake()
            return event
        }
        if layoutGlobalMonitor == nil || layoutLocalMonitor == nil {
            if let token = layoutGlobalMonitor { NSEvent.removeMonitor(token) }
            if let token = layoutLocalMonitor { NSEvent.removeMonitor(token) }
            layoutGlobalMonitor = nil; layoutLocalMonitor = nil
            layoutGuard.disarm()
            screenLayouts.cancelWake()
        }
    }

    private func stopLayoutInputMonitors() {
        if let token = layoutGlobalMonitor { NSEvent.removeMonitor(token) }
        if let token = layoutLocalMonitor { NSEvent.removeMonitor(token) }
        layoutGlobalMonitor = nil; layoutLocalMonitor = nil; layoutMonitorAttempted = false
        layoutGuard.disarm()
        screenLayouts.cancelWake()
    }

    private func layoutGuardObservation() -> OneShotLayoutGuard.Observation {
        actions.beginWindowBatch()
        defer { actions.endWindowBatch() }
        let census = allWindowObservation()
        let records = actions.windowCensus().windows
        let safeWindows = records.allSatisfy {
            AX.bool($0.window, kAXMinimizedAttribute) == false
                && AX.bool($0.window, MinimizeMenu.fullScreenAttribute) == false
        }
        let safe = started && AX.isTrusted && layoutGlobalMonitor != nil && layoutLocalMonitor != nil
            && NSEvent.pressedMouseButtons == 0 && safeWindows && !pimp.isBusy
            && !actions.cashoutPending && !actions.newWindowStarting && !actions.blankBusy()
        let screens = NSScreen.screens.map { ScreenSpec(name: $0.localizedName, frame: Screens.flip(rect: $0.frame)) }
        return OneShotLayoutGuard.Observation(pid: app.pid, screens: ScreenLayoutKeeper.key(screens),
            windows: census.windows, complete: census.complete, safe: safe,
            restorePending: windowSnapshots.hasPendingRestore || screenLayouts.hasPendingRestore,
            nativeComplete: actions.windowCensus().complete)
    }

    private func armLayoutGuard(_ moves: [PimpMove], waitForRestore: Bool = false) {
        let desired = moves.map { PimpMove(id: $0.id, frame: restoreFrame($0.frame)) }
        layoutGuard.arm(desired, observation: layoutGuardObservation(), at: Date(), waitForRestore: waitForRestore)
    }

    private func layoutGuardTick() {
        if !windowSnapshots.hasPendingRestore && !screenLayouts.hasPendingRestore { restoreConfirmationUntil = nil }
        guard layoutGuard.active else { return }
        let correction = layoutGuard.tick(layoutGuardObservation(), at: Date())
        // The guard has already consumed itself. place/onWindowsMoved cannot rearm it.
        if !correction.isEmpty { actions.place(correction) }
    }

    // MARK: - панель PMP: проекты, «Отправить», цвета (WF126)

    /// Снимок проектов панели: обход папок — в фоне, ответ — на главной нити.
    public func panelProjects(_ done: @escaping (PanelSnapshot) -> Void) {
        let recent = knownProjects(limit: 20).filter { ProjectIndex.isDirectory($0.folder) }
            .map { (folder: $0.folder, name: $0.name) }
        let main = mainProjectSetting()
        let root = StatusFeed.projectsRoot()
        DispatchQueue.global(qos: .utility).async {
            var snapshot = PanelProjects.snapshot(root: root, recent: recent, mainEntry: main, now: Date())
            // Терминальные чаты (WF129, #9077): живые tmux-сессии `rick-<проект>`; tmux нет — пусто.
            snapshot.terminals = PanelTiles.liveTerminals()
            DispatchQueue.main.async { done(snapshot) }
        }
    }

    /// Темы развёрнутого «Оформления» (WF174, #9182): `PanelColorTiles.strips` раскладывает их по цветовому кругу,
    /// с WF210 — сперва тёмные, светлые в конце. Тем нет в каталоге — не рисуются; остальные — меню жёлтой кнопки.
    public static let panelThemeIDs = PanelColorTiles.lightIDs + PanelColorTiles.darkIDs

    public var panelThemes: [WindowColorChip] {
        Self.panelThemeIDs.compactMap { id in actions.themes.first { $0.id == id } }.map(WindowColorChip.init)
    }

    /// Все темы каталога по его порядку — имя выбранной в строке «Цвет Claude» (#9040).
    public var panelAllThemes: [WindowColorChip] { actions.themes.map(WindowColorChip.init) }

    /// Что выбрано у окон сейчас: тема всем окнам, «по проектам» или «как у Claude».
    public var windowColor: WindowColorChoice {
        if let id = actions.themeStore.allThemeID { return .theme(id) }
        return projectPaint.enabled ? .byProject : .plain
    }

    /// Имя темы всем окнам (для подписи «Сейчас: … — из меню окна»).
    public func themeName(_ id: String) -> String? { actions.themes.first { $0.id == id }?.name }

    /// Клик по кружку. «По проектам» снимает вид всем окнам, только если он стоит (иначе слои проекта
    /// снялись бы, а отпечатки остались — поправка критика 7).
    public func chooseWindowColor(_ choice: WindowColorChoice) {
        switch choice {
        case .byProject:
            if actions.hasAllWindowsView { actions.autoPaintReset() }
            projectPaint.setEnabled(true)
        case .plain:
            projectPaint.setEnabled(false)
            actions.autoPaintReset()
        case .theme(let id):
            guard let theme = actions.themes.first(where: { $0.id == id }) else { return }
            actions.applyTheme(scope: MenuModel.themeScopeAll, theme: .set(theme), window: nil)
        }
    }

    /// Живой фон всем окнам (#9115) — слой `look.aurora` scope `all`, тот же путь, что «Живой фон» в «Всем окнам ▸».
    public var liveBackground: Bool { actions.themeStore.allLook.aurora }

    /// Схема живого фона всем окнам (WF145, схемы WF146): живой фон включается вместе с выбором.
    public var liveScheme: String { actions.themeStore.allLook.schemeID }

    /// Переключатель «Живой» блока «Оформление» (WF180): живой фон в тонах цвета окон или тот же цвет без движения.
    public func setLive(_ on: Bool) {
        applyLiveLook(PanelColorTiles.liveLook(actions.themeStore.allLook, on: on))
    }

    /// Умолчания новой установки (WF210, #9378; слово Элвиса 10.10.2026: «Как только Пимп устанавливается, сразу же
    /// включается живое оформление»): тема «Фиолетовая» и «Живой» всем окнам. Зовёт `AppDelegate` один раз — когда
    /// `PanelColorTiles.isNewInstall`.
    public func applyNewInstallLook() {
        guard let theme = actions.themes.first(where: { $0.id == PanelColorTiles.newInstallThemeID }) else { return }
        actions.applyNewInstallLook(theme: theme, look: PanelColorTiles.liveLook(Look(), on: true))
    }

    private func applyLiveLook(_ look: Look) {
        actions.applyTheme(scope: MenuModel.themeScopeAll, look: look.layer, window: nil)
    }

    /// Примерка наведением в окне Claude в фокусе (путь меню жёлтой кнопки); nil — снять примерку.
    public func previewWindowColor(_ choice: WindowColorChoice?) {
        switch choice {
        case nil: actions.endPreview(window: nil)
        case .plain?: actions.previewTheme(nil, window: nil)
        case .theme(let id)?:
            if let theme = actions.themes.first(where: { $0.id == id }) { actions.previewTheme(theme, window: nil) }
        case .byProject?: break
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
        // Замок «меню открыто» (WF145): фоновый фокус Claude ждёт закрытия меню PMP.
        MenuHold.shared.start()
        isAccessibilityTrusted = AX.isTrusted
        startLayoutInputMonitors()

        // Авто-Allow работает на странице; AX-кликер и замок К6 не запускаем (#7850).
        // окна доступа macOS по-прежнему подсвечивает `consentBeacon`.
        autoAllowSwitch.beginGeneration()
        autoContinueSwitch.beginGeneration()
        viewerCounts.beginGeneration()
        trustRoot = TrustRoot.current()
        trustRootSwitch.beginGeneration()
        pageLook.beginGeneration()
        continueWatch.start()
        micMonitor.start()
        consentBeacon.start()
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
        // «📋 Копировать в буфер» (WF106 #8102): страница шлёт путь на порт, файл кладём сами. `CopyFileRelay`
        // (опрос и ЧТЕНИЕ буфера — от него вопрос macOS 26) не запускаем. Без имени файла (слово Элвиса
        // 17.09 12:50: «просто „файл в буфере обмена, вставляй“»).
        htmlOpener.onCopyFile = { [weak self] path in
            DispatchQueue.main.async {
                guard CopyFileRelay.write(path: path, to: .general) else { return }
                self?.hud.show("📋 Файл в буфере обмена — вставляй", seconds: 2.5)
            }
        }
        htmlOpener.onContext = { [weak self] chat in self?.sendChatContext(chat) }
        htmlOpener.onPanel = { [weak self] in DispatchQueue.main.async { self?.onPanelRequest?() } }
        // Размер шрифта поля (WF107 К2): страница сменила колесом — в зеркало; потеряла (`none`) — вернуть.
        htmlOpener.onComposerFont = { [weak self] ping in
            DispatchQueue.main.async {
                guard let self = self, let px = self.composerFont.receive(ping) else { return }
                self.actions.sendComposerFont(px)
            }
        }
        htmlOpener.onScriptFailed = { [weak self] in
            self?.hud.show("Разреши Пимпу управлять браузером — тогда вкладки не будут плодиться", seconds: 4)
        }
        htmlOpener.start()
        connectViewer()
        observeActivation()
        claudeFrontmost = app.isFrontmost
        refreshHotkeys()

        let watchdog = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.actions.beginWindowBatch()
            defer { self.actions.endWindowBatch() }
            self.isAccessibilityTrusted = AX.isTrusted
            if self.isAccessibilityTrusted { self.startLayoutInputMonitors() }
            else { self.stopLayoutInputMonitors() }
            self.refreshHotkeys()
            // Цвет проекта — на этом же таймере, своего заводить не надо (критик М2 плана WF15).
            // Сперва канал probe: покраска берёт из него, какой чат в каком окне.
            // Один обход окон на тик: заголовки — покраске и возврату тем, те же окна
            // с рамками — каналу probe (план WF77, батч B2).
            let onScreen = self.actions.paintableSnapshot()
            self.tickTitles = onScreen.titles
            self.refreshChatLookup()
            self.chatProbe.tick(windows: onScreen.windows, indexRevision: self.index.revision)
            // Карта тем страницы приезжает тем же кругом probe (решение 3 плана WF35):
            // файл догоняет ею правду, а зеркало остаётся страховкой на время, пока канал
            // занят агентом на гейте.
            self.windowThemes.absorb(page: self.chatProbe.takeThemes(), at: Date())
            // Снятые в WF220 рамка и неон (#9440): у кого они ещё включены — гасим, выключателя в меню нет.
            self.windowThemes.retireTick(titles: self.tickTitles ?? [], at: Date(), send: { found in
                self.actions.retireEffects(frame: found.frame, look: found.neon ? found.all.layer : .keep)
            }, restore: { fields in
                self.actions.sendThemesRestore(fields: fields)
            })
            // Возврат после переустановки Claude: одна команда на все окна, не больше трёх
            // за поколение (решение 5 плана WF35).
            self.windowThemes.restoreTick(titles: self.tickTitles ?? [], at: Date()) { fields in
                self.actions.sendThemesRestore(fields: fields)
            }
            self.projectPaint.tick()
            // К3: первый тик с окнами и смена состава, до трёх отправок за поколение.
            self.autoAllowSwitch.tick(titles: self.tickTitles ?? [], at: Date()) { on in
                self.actions.sendAutoAllow(on)
            }
            self.autoContinueSwitch.tick(titles: self.tickTitles ?? [], at: Date()) { fields in
                self.commands.write(action: "auto-continue", fields: fields)
            }
            // Режим кружка-микрофона (К4) — тем же правилом поколений.
            self.micMonitor.tick(titles: self.tickTitles ?? [], at: Date())
            self.actions.noteNewWindowOutcome()
            // Счёт кнопки «▦ Галерея» (К-V7) — тоже; галерея молчит — попытка не тратится, канал проверяется.
            self.viewerCounts.tick(titles: self.tickTitles ?? [], pages: self.chatProbe.pages, at: Date()) { done in
                guard self.viewerClient.isUp else { self.viewerClient.ping(); done(false); return }
                self.sendViewerState(chat: false, counts: true, completion: done)
            }
            // Корень автодоверия (WF108): claude.json крошечный, читаем на тике; ключ сменился — новое поколение.
            let root = TrustRoot.current()
            if root != self.trustRoot {
                self.trustRoot = root
                self.trustRootSwitch.beginGeneration()
            }
            self.trustRootSwitch.tick(titles: self.tickTitles ?? [], at: Date()) { _ in
                self.commands.write(action: TrustRoot.action, fields: TrustRoot.fields(root: root))
            }
            // Притемнение и ракета отправки (WF113/WF114) — тем же правилом поколений; сменился набор окон
            // главного проекта (`keep`) — новое поколение `dim`.
            self.updateMainProjectKeep()
            self.pageLook.tick(titles: self.tickTitles ?? [], at: Date())
            // Спрятанное окно, чей чат ждёт Элвиса, — на экран (#8282); круг probe этого тика уже прочитан.
            self.showWaitingTick()
            // Страницы отвечают только старым лоадером (WF111) — плашкой один раз на каждое появление.
            let repatch = self.chatProbe.needsRepatch
            if repatch, !self.repatchNoticed {
                self.hud.show(MenuModel.oldLoaderNotice, seconds: MenuModel.newWindowNoticeSeconds)
            }
            self.repatchNoticed = repatch
            // Свой список проектов доливается из индекса (план WF36, WF30 ч. 2): файл пишется,
            // только когда состав или свежесть папок правда изменились.
            self.projects.absorb(self.index.projects(), at: Date())
            // «Окна как были» (#7065): снимок и автовозврат. До тика канала — начатый возврат
            // идёт его очередью; после круга probe — ответ главной страницы уже прочитан.
            self.windowSnapshots.tick()
            // Окна при смене мониторов (#7740): выборка раз в 10 с, возврат — после тишины.
            self.screenLayouts.tick()
            // Канал «Пимп» — на этом же тике: запросы из любого чата лежат файлами.
            self.pimp.tick()
            // «Обкэшить» из попапа ждёт ПОДТВЕРЖДЕНИЯ доезда текста, чтобы поставить новое
            // окно на место старого и закрыть старое (#5768, #5779). Работы нет — тик ничего
            // не делает. Стоит после круга probe: ответ страниц уже прочитан этим тиком.
            self.actions.cashoutTick()
            self.layoutGuardTick()
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
        restoreConfirmationUntil = nil
        stopLayoutInputMonitors()
        continueWatch.stop()
        micMonitor.stop()
        consentBeacon.stop()
        menu.stop()
        statusFeed.stop()
        htmlOpener.stop()
        hotkeys.removeAll()
        watchdog?.invalidate()
        watchdog = nil
        hud.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
    }

    /// Явная смена тумблера у часов отправляется сразу, повторное применение настроек — нет.
    public var autoAllowEnabled: Bool {
        get { autoAllowSwitch.on }
        set {
            let changed = newValue != autoAllowSwitch.on
            autoAllowSwitch.on = newValue
            guard changed, started else { return }
            actions.sendAutoAllow(newValue)
        }
    }

    public func configureAutoContinue(on: Bool, preservePageChoice: Bool) {
        let changed = on != autoContinueSwitch.on || preservePageChoice != autoContinueSwitch.migrate
        autoContinueSwitch.configure(on: on, migrate: preservePageChoice)
        if changed, started {
            commands.write(action: "auto-continue", fields: AutoContinueSwitch.fields(on: on, migrate: preservePageChoice))
            chatProbe.demand()
        }
    }

    public var autoContinueReported: Bool? { AutoContinueSwitch.reported(chatProbe.pages, at: Date()) }

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
    /// приложения и после «Пропатчить Claude»/«Снять патч…»: `Patcher.installLiveFiles` копирует claude.css
    /// из бандла ЦЕЛИКОМ и затирает его (решение 1 плана WF14).
    public func refreshLiveStyle() {
        LiveStyle.refresh()
    }

    // MARK: - статус (для меню-бара и живой проверки на гейте)

    /// `claude=<pid>/<сколько Claude запущено>` (#7096): `49762/2` — рядом живёт лишний.
    public var statusText: String {
        return """
        accessibility=\(isAccessibilityTrusted) claude=\(app.statusField) front=\(claudeFrontmost) \
        autoAllow=\(autoAllowSwitch.status) cont=\(continueWatch.fires) mic=\(micMonitor.status) \
        menu=\(minimizeMenuEnabled)/\(menu.isRunning) menus=\(menu.shows) \
        blockQuit=\(blockQuitEnabled) blocks=\(blockedQuits) hotkeys=\(hotkeys.count) \
        status=\(statusFeed.isRunning)/\(statusFeed.projectCount)/\(statusFeed.sentCount) \
        project=\(projectPaint.status) chats=\(chatProbe.status) themes=\(windowThemes.status) \
        pimp=\(pimp.status) snapshot=\(windowSnapshots.status) screens=\(screenLayouts.status) copy=\(htmlOpener.copyStatus) html=\(htmlOpener.status) view=\(fileView.shown)/\(fileView.closed)/\(htmlOpener.viewRejected) viewer=\(viewerClient.status) consent=\(consentBeacon.status) live=\(liveColorsStatus) lastCommand=\(actions.lastCommand)
        """
    }

    /// Живые цвета в строке диагностики: «off» или «solo/300/dark» (план WF18) — на гейте по
    /// ней видно, что приложение думает о крутёже, не открывая меню.
    private var liveColorsStatus: String {
        let state = actions.liveColors
        guard state.on else { return "off" }
        return "\(state.mode.rawValue)/\(state.period)/\(state.tone.rawValue)"
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
