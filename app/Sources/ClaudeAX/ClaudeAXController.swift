import AppKit
import ApplicationServices

/// Клавиши PMP в Claude и блокировка ⌘Q (`claude_noquit`); меню на кнопке «Свернуть» снято в WF237 (#9524).
///
/// Хоткеи и ⌘Q — Carbon `RegisterEventHotKey` (решение 1 плана): они регистрируются, когда
/// Claude выходит вперёд, и снимаются, когда уходит назад, поэтому в остальных приложениях
/// клавиши обычные. Без доверия Accessibility модуль работает вхолостую и держит флаг.
public final class ClaudeAXController {
    let app = ClaudeApp()
    let commands = CommandChannel()
    let hud = HUD()
    private let hotkeys = CarbonHotkeys()
    let actions: ClaudeActions
    private let statusFeed: StatusFeed
    /// Индекс чатов Claude Code — единственный источник правды «папка ↔ сессия» (критик Б2
    /// плана WF16): из него живёт и покраска по проекту, и список папок «🪟 Новое окно ▸»,
    /// и уникальное имя чата. Второго сканера тех же файлов в приложении нет.
    let index = ProjectIndex()
    private let chatLookupLock = NSLock()
    private var chatLookup: [String: (cwd: String, cli: String?)] = [:]

    /// Publish on main; HTTP readers copy one value under a short lock without waiting for AX.
    func refreshChatLookup() {
        var next: [String: (cwd: String, cli: String?)] = [:]
        for session in index.sessions { next[session.sessionId] = (session.cwd.path, session.cliSessionId) }
        chatLookupLock.lock()
        chatLookup = next
        chatLookupLock.unlock()
    }

    func knownChat(_ chat: String) -> (cwd: String, cli: String?)? {
        chatLookupLock.lock()
        defer { chatLookupLock.unlock() }
        return chatLookup[chat]
    }
    /// Вид проекта (`.pimpmyclaude.json`) — чтение для нового окна; файлов не пишет.
    private let projectSettings = ProjectSettingsStore()
    /// Цвет проекта (план WF15): своего таймера у покраски нет — она тикает вместе с
    /// watchdog'ом, раз в 2 с (критик М2).
    let projectPaint: ProjectPaint
    /// Канал probe (план WF29): страницы сами говорят, какой в них чат. Тикает на том же
    /// таймере и молчит, пока выключен тумблер «🗂 Цвет по проекту».
    let chatProbe = ChatProbe()
    /// Темы окон на диске (план WF35, задача #5473): переустановка Claude стирает localStorage
    /// страниц, и все окна становились серыми. Файл живёт рядом с `command.json`.
    private let windowThemes = WindowThemeStore()
    /// Разовое гашение снятых «Живых цветов» (WF237): ключи `liveColors.*` стираются после него.
    private let liveColorsRetire = LiveColorsRetire()
    /// Свой список недавних проектов (план WF36, WF30 ч. 2, задача #5451): индекс чатов Claude
    /// переустановку не переживает, а файл рядом с `command.json` — переживает.
    let projects = ProjectsStore()
    /// Раскладки проектов (план WF41, задача #5620): файл рядом с `projects.json` — «Утро»,
    /// «Разбор» и прочее, что Элвис запомнил.
    let layouts = LayoutsStore()
    /// Канал «Пимп» (план WF36, задача #5531): окна Claude из любого чата — файлами.
    /// Тикает на общем таймере, своего не заводит.
    let pimp = PimpChannel()
    /// «Окна как были» (#7065, контракт К5): снимок окон в `windows-snapshot.json` и возврат
    /// после запуска Claude. Тикает на общем таймере, окна возвращает очередью канала «Пимп».
    let windowSnapshots = WindowSnapshotKeeper()
    /// «📋 Копировать в буфер» (WF69, #6236): страница кладёт путь и метку, приложение подменяет
    /// буфер самим файлом. Свой таймер 0,25 с — общий тик в 2 с опоздал бы к «вставить» в Telegram.
    let htmlOpener = HtmlChromeOpener()
    /// Зеркало размера шрифта поля и возврат после переустановки Claude (WF107 К2).
    private let composerFont = ComposerFontMirror()
    /// Просмотр файла поверх монитора чата (WF103, маршрут `view` порта 47615).
    let fileView = FileView()
    /// Галерея — своё приложение PimpViewer.app (WF104, К-V8): клиент к нему, всё — на своей очереди.
    let viewerClient = ViewerClient()
    /// Панель материалов в окне Claude (WF277, К-DOCK): место от страницы → окно-док PimpViewer.
    let materialsDock = MaterialsDock()
    /// Gallery counts retry within a bounded page generation until probe confirms a counter increment.
    /// State and callbacks stay on the main queue.
    private let viewerCounts = ViewerCountsSync()
    /// К3: состояние тумблера и ограниченный повтор страницам; кнопки жмёт только страница.
    let autoAllowSwitch = AutoAllowSwitch()
    private let autoContinueSwitch = AutoContinueSwitch()
    /// «Повторять при ошибке сервера» (#6936, К-AR): выбор и повтор страницам по поколениям (`+AutoRetry`).
    let autoRetrySwitch = AutoRetrySwitch()
    /// Корень автодоверия страниц (WF108, `trust-root`): тем же правилом поколений; новое поколение —
    /// и когда `projectsRoot` в claude.json сменился. `trustRoot` — последний прочитанный корень.
    private let trustRootSwitch = AutoAllowSwitch()
    private var trustRoot: String?
    /// Притемнение окон (WF113, #8256) и ракета отправки (WF114, #8226): UserDefaults и рассылка поколениями.
    let pageLook = PageLookSettings(configURL: LiveConfig.url)
    /// Кнопка «💬 Новый чат» в самом чате (#7246): метка в заголовке окна.
    let continueWatch = ContinueWatch()
    /// Кружок-микрофон (#7054, К4): клик — клавиша Диктатора, правый — меню «🎙 Рик».
    let micMonitor = MicMonitor()
    /// Все, кто повторяет команды страницам по поколениям: новое поколение — на старте и при новом Claude.
    private lazy var generational: [Generational] = [windowThemes, liveColorsRetire, autoAllowSwitch,
                                                     autoContinueSwitch, micMonitor, viewerCounts, trustRootSwitch,
                                                     pageLook, autoRetrySwitch]
    /// Окна доступа macOS не пропустить (WF91, #7691): мигающая рамка и плашка у курсора.
    private let consentBeacon = ConsentBeacon()
    /// Вход на сайт (WF302, #11225): `pimp.py login` — Chrome вперёд, свечение и стрелка на поле входа.
    private lazy var loginBeacon = LoginBeacon(hud: { [weak self] text in self?.hud.show(text, seconds: 4) },
                                               paused: { [weak self] in self?.consentBeacon.isShowing ?? false })
    /// Окна при смене мониторов (#7740, WF94): расстановка на каждый набор экранов в
    /// `windows-by-screens.json` и возврат, когда набор сменился на знакомый.
    let screenLayouts = ScreenLayoutKeeper()
    /// Фото с AirDrop — в поле Рика (#9358): сторож «Загрузок», `AirDropWatch.swift`.
    let airDrop = AirDropWatch()
    /// Картинка из Telegram и прочих броском в окно Claude (#11310): `ForeignDrop.swift`.
    let foreignDrop = ForeignDrop()

    private var observers: [NSObjectProtocol] = []
    /// Заголовки окон, снятые в этом тике: их читает и канал probe, и покраска — второй
    /// обход AX за те же 2 с не нужен.
    private var tickTitles: [String]?
    /// Плашка «старый лоадер» уже сказана за это появление (WF111).
    private var repatchNoticed = false
    private var watchdog: Timer?
    var layoutGuard = OneShotLayoutGuard()
    var layoutGlobalMonitor: Any?
    var layoutLocalMonitor: Any?
    var layoutMonitorAttempted = false
    var restoreConfirmationUntil: Date?
    var started = false
    private var claudeFrontmost = false

    // Хранимые свойства разделов-расширений (`ClaudeAXController+<Раздел>.swift`): расширение их держать не может.
    // +WindowHide
    /// Окна, которые свернул Пимп (`hideOthers`); `showHidden` список чистит.
    let hiddenByPimp = HiddenWindows<AXUIElement> { AX.bool($0, kAXMinimizedAttribute) }

    /// Тик: чаты окон главного проекта — полю `keep` команды `dim` (вуаль и рамка их не трогают).
    /// Нет ключа — `keep` пуст. Ключ есть, а ни одного чата не опознали (карта probe молчит) — прежний
    /// набор держим: иначе на миг молчания вуаль легла бы на Рика.
    var dimMainProject: String?

    /// Окно, которое развернул разворот «ждёт Элвиса» (#8282); пока оно на экране и его чат всё ждёт,
    /// следующее не разворачиваем — по одному.
    var waitShown: AXUIElement?

    // +PageLook
    /// Поздний отказ показа (после повторов): строка для панели. Главная нить.
    public var onSendDelayPreviewFailed: ((String) -> Void)?

    // +ChatArchive
    lazy var chatArchive = ChatArchive.standard()

    /// Бэкап кончился (успех или отказ) — панели у часов вернуть подпись. Главная нить.
    public var onArchiveDone: (() -> Void)?
    /// Кнопка «PMP» в окне Claude (WF125 #8894): открыть панель у часов. Главная нить.
    public var onPanelRequest: (() -> Void)?

    // Проверка окна после обновления Claude (#10527, К-HEALTH).
    let liveCheck = LiveCheckRunner()
    /// Раздел приложения для проверки окна и ручки `live-check`: замеры значка и панели у часов. Главная нить.
    public var liveCheckApp: (() -> LiveCheck.AppSection?)?
    /// Проверка окна кончилась: отчёт и его датированный файл (nil — не записался). Главная нить.
    public var onLiveCheckDone: ((LiveCheck.Report, URL?) -> Void)?

    // +WindowSnapshots
    /// Перезапуск Claude для канала (WF108): копия Claude (nil — не знаем, какая запущена) и ответ
    /// `nil` — снова запущен, иначе причина. Вешает приложение — `Patcher` модулю не виден.
    public var restartClaude: ((URL?, @escaping (String?) -> Void) -> Void)?

    var claudeVersionCache: (pid: pid_t, version: String)?

    // +OneChat
    /// «Всё в одном чате» (#9552), а папки Rick нет: открыть панель у часов на строке «Поставить Рика». Главная нить.
    public var onRickSetupRequest: (() -> Void)?

    /// Есть ли доверие Accessibility. Промпт показывает приложение (батч C), модуль только читает.
    public private(set) var isAccessibilityTrusted = false

    public init() {
        projectPaint = ProjectPaint(index: index)
        actions = ClaudeActions(app: app, commands: commands)
        statusFeed = StatusFeed(commands: commands)
        // Окна переехали: протухли рамки в карте probe — по ним различаются окна-однофамильцы
        // (план WF77, критик блокер 6б).
        actions.onWindowsMoved = { [weak self] in
            self?.layoutGuard.disarm()
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
        // и живые цвета жили только там (решение 8 плана WF35).
        app.onRestart = { [weak self] in
            guard let self = self else { return }
            self.layoutGuard.disarm()
            self.restoreConfirmationUntil = nil
            // Новое поколение у всех повторов (`generational`): три попытки возврата тем и снова «первый пустой
            // ответ probe значит переустановку», гашение живых цветов, Авто-Allow, «Новый чат сам», кружок-микрофон,
            // счёт «▦ Галерея», корень автодоверия, притемнение с ракетой.
            self.generational.forEach { $0.beginGeneration() }
            // Отпечатки покраски стали враньём — окна голые, а мы считаем их покрашенными.
            self.projectPaint.forget()
        }
        // Рядом запущен второй Claude (#7096): работаем с настоящим, а про лишний говорим
        // плашкой — один раз на появление. Закрывать чужой процесс не наше дело (критик WF82 п. 4).
        // Ходом вперёд: зовут изнутри `running()`, посреди тика меню.
        app.onDuplicate = { [weak self] extra, count in
            DispatchQueue.main.async {
                self?.hud.show(Notices.duplicateClaudeNotice(path: extra.path, pid: extra.pid, count: count),
                               seconds: Notices.duplicateClaudeNoticeSeconds)
            }
        }

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
        projectPaint.isAllWindowsSet = { [weak self] in self?.actions.hasAllWindowsView ?? true }
        projectPaint.allLook = { [weak self] in self?.actions.themeStore.allLook ?? Look() }
        // Живые цвета сильнее цвета проекта (критик Б2 плана WF18): пока их гашение не кончилось (WF237), проект
        // не шлёт команд — иначе окно мигало бы между проектным цветом и живым. Себя нет — молчим.
        projectPaint.isLiveColorsOn = { [weak self] in self?.liveColorsRetire.pending ?? true }
        projectPaint.lastMenuCommand = { [weak self] in self?.actions.lastUserCommandAt }
        projectPaint.showNotice = { [weak self] text in self?.hud.show(text, seconds: 3) }
        // Ручной выбор в окне проекта молча становится видом проекта (решение 3.2 плана WF20):
        // крючок висит на `remember`, поэтому примерка мышью в файл проекта не пишет.
        actions.onWindowViewChanged = { [weak self] title, windowFrame, theme, font, size, frame, look in
            self?.projectPaint.noteManualChoice(title: title, windowFrame: windowFrame,
                                                theme: theme, font: font,
                                                size: size, frame: frame, look: look)
        }

        // Открыли папку (запрос канала) — она самая свежая.
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
        connectLiveCheck()
        connectWindowSnapshots()
        connectWF84Menus()
        connectMic()
        connectScreens()
        connectWindowHide()
        connectPageLook()
    }

    /// Проверка окна (#10527): круг probe с `health()`, раздел приложения, ручка `live-check` канала «Пимп».
    private func connectLiveCheck() {
        chatProbe.isHealthDue = { [weak self] in
            guard let self = self else { return false }
            return self.liveCheck.due(pages: self.chatProbe.pages)
        }
        liveCheck.appSection = { [weak self] in self?.liveCheckApp?() }
        liveCheck.onDone = { [weak self] report, file in self?.onLiveCheckDone?(report, file) }
        pimp.seats.liveCheck = { [weak self] in
            (app: self?.liveCheckApp?()?.value ?? .null, last: LiveCheck.lastSummary())
        }
    }

    /// Установлен Claude `version` (`AppDelegate.show(state:)`): ещё не проверяли — проверить окно, как только главная
    /// страница проживёт 20 с.
    public func armLiveCheck(claude version: String) { liveCheck.arm(claude: version) }

    // MARK: - жизненный цикл и выключатели (их зовёт AppDelegate)

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
        trustRoot = TrustRoot.current()
        // Выбор задержки и клавиш, которого в панели больше нет, — в ближайший из тех, что есть (#10334).
        pageLook.migrateLegacy()
        // Поколение с запуска у всех повторов: приложение только что поднялось, и Claude мог за это время
        // переустановиться (решение 5 плана WF35) — темы, гашение живых цветов (WF237), Авто-Allow и прочие.
        generational.forEach { $0.beginGeneration() }
        continueWatch.start()
        micMonitor.start()
        consentBeacon.start()
        loginBeacon.start()
        applyAirDrop()
        startForeignDrop()
        statusFeed.start()
        // Каталог канала «Пимп»: по нему CLI видит, что приложение вообще есть (план WF36).
        pimp.start()
        // «Закрытые чаты» (#5856) сняты по слову Элвиса 19.10 (#10332): их файл у людей — мусор, убираем на запуске.
        try? FileManager.default.removeItem(at: CommandChannel.directory.appendingPathComponent("closed-chats.json"))
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
        htmlOpener.onOneChat = { [weak self] in DispatchQueue.main.async { self?.openOneChat() } }
        // Размер шрифта поля (WF107 К2): страница сменила колесом — в зеркало; потеряла (`none`) — вернуть.
        htmlOpener.onComposerFont = { [weak self] ping in
            DispatchQueue.main.async {
                guard let self = self, let px = self.composerFont.receive(ping) else { return }
                self.actions.sendComposerFont(px)
            }
        }
        htmlOpener.onScriptFailed = { [weak self] in
            self?.hud.show("Разреши PMP управлять браузером — тогда вкладки не будут плодиться", seconds: 4)
        }
        htmlOpener.start()
        connectViewer()
        connectMaterialsDock()
        connectChatMedia()
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
            self.noteFlowPages()
            // Карта тем страницы приезжает тем же кругом probe (решение 3 плана WF35):
            // файл догоняет ею правду, а зеркало остаётся страховкой на время, пока канал
            // занят агентом на гейте.
            self.windowThemes.absorb(page: self.chatProbe.takeThemes(), at: Date())
            // Круг с `health()` (#10527) — проверке окна после обновления Claude.
            if let health = self.chatProbe.takeHealth() { self.liveCheck.absorb(health) }
            // Снятые в WF220 рамка и неон (#9440): у кого они ещё включены — гасим, выключателя в меню нет.
            self.windowThemes.retireTick(titles: self.tickTitles ?? [], at: Date(), send: { found in
                self.actions.retireEffects(frame: found.frame, look: found.neon ? found.all.layer : .keep)
            }, restore: { fields in
                self.actions.sendThemesRestore(fields: fields)
            })
            // «Живые цвета» сняты (WF237): у кого крутились — `live-colors {on:false}` всем окнам, как гашение неона.
            self.liveColorsRetire.tick(titles: self.tickTitles ?? [], at: Date(), send: {
                self.commands.write(action: LiveColorsRetire.action, fields: LiveColorsRetire.fields())
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
            self.autoRetrySwitch.tick(titles: self.tickTitles ?? [], at: Date()) { fields in
                self.commands.write(action: AutoRetry.action, fields: fields)
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
            self.applyAirDrop()
            self.pageLook.tick(titles: self.tickTitles ?? [], at: Date())
            // Спрятанное окно, чей чат ждёт Элвиса, — на экран (#8282); круг probe этого тика уже прочитан.
            self.showWaitingTick()
            // Страницы отвечают только старым лоадером (WF111) — плашкой один раз на каждое появление.
            let repatch = self.chatProbe.needsRepatch
            if repatch, !self.repatchNoticed {
                self.hud.show(Notices.oldLoaderNotice, seconds: Notices.newWindowNoticeSeconds)
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
        loginBeacon.stop()
        airDrop.stop()
        foreignDrop.stop()
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

    /// «Клавиши PMP в Claude» (WF237, бывший выключатель меню жёлтой кнопки): ⌥⌘N, ⌥⌘↑, ⌥⌘↓, ⇧⌘N, ⌥⌘A, ⌥⌘S, ⌥⌘D.
    /// Блок ⌘Q от него не зависит — у него свой выключатель.
    public var pmpKeysEnabled: Bool = true {
        didSet { refreshHotkeys() }
    }

    public var blockQuitEnabled: Bool = true {
        didSet { refreshHotkeys() }
    }

    /// Блок стилей в живом `claude.css` (радиус неоновой рамки и поля по бокам) — на запуске
    /// приложения и после «Пропатчить Claude»/«Снять патч…»: `Patcher.installLiveFiles` копирует claude.css
    /// из бандла ЦЕЛИКОМ и затирает его (решение 1 плана WF14).
    public func refreshLiveStyle() {
        LiveStyle.refresh()
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
        // (действия клавиш без AX не работают). «Клавиши PMP в Claude» выключены — тоже только ⌘Q.
        guard started, claudeFrontmost else {
            hotkeys.apply([])
            return
        }
        var bindings: [HotkeyBinding] = []
        if isAccessibilityTrusted, pmpKeysEnabled {
            for (index, entry) in Hotkeys.entries.enumerated() {
                guard entry.registersHotkey, let key = entry.key else { continue }
                bindings.append(HotkeyBinding(id: UInt32(index + 1), key: key) { [weak self] in
                    self?.actions.perform(entry.command, on: nil)
                })
            }
        }
        if blockQuitEnabled {
            bindings.append(HotkeyBinding(id: 100, key: Hotkeys.quitKey) { [weak self] in
                self?.onBlockedQuit()
            })
        }
        hotkeys.apply(bindings)
    }

    /// ⌘Q проглочен (Carbon перехватил его до Claude) — показываем, как выйти по-настоящему.
    private func onBlockedQuit() {
        hud.show(Hotkeys.quitMessage, seconds: 1.5)
    }
}
