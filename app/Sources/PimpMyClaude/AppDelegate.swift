import AppKit
import ApplicationServices
import ClaudeAX
import Network
import Patcher
import ServiceManagement
import UserNotifications

/// Меню-бар без окна (LSUIElement). С WF87 у часов значок PMP с лимитом, левый клик — вылетающая
/// панель (`PimpPanel`), правый — короткое меню; «Поставить / Снять / Статус» на виду больше нет.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    enum Key {
        static let autoAllow = AutomationDefaults.allowOnceKey
        /// «Клавиши PMP в Claude» (WF237): свой ключ — выключенное меню жёлтой кнопки (`minimizeMenuEnabled`)
        /// клавиши не гасило, и унаследовать его значит молча снять клавиши тем, кто меню выключал.
        static let pmpKeys = "pmpKeysEnabled"
        static let blockQuit = "blockQuitEnabled"
        static let loginItemConfigured = "loginItemConfigured"
        static let claudePath = "claudeAppPath"
        static let setupDone = "setupWindowSeen"
        /// «Самое время» обновить Claude (WF87): когда предлагали и до какого момента «Позже» (Date).
        static let lastOfferAt = "claudeUpdateLastOfferAt"
        static let snoozeUntil = "claudeUpdateSnoozeUntil"
        /// Патч ждал «Управление приложениями» и Пимп перезапустился (#9842): что продолжить и когда начали ждать.
        static let resumeKind = "permissionResumeKind"
        static let resumeAt = "permissionResumeAt"
    }
    /// «Позже» — на столько же, сколько пауза между предложениями.
    static let snoozeSeconds = ClaudeUpdateMenu.offerRepeatSeconds

    let ax = ClaudeAXController()
    var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    var busy = false
    private var setup: SetupWindow?
    /// Рик встал сам на этом запуске (новая установка, WF216) — окно первой настройки говорит, где он.
    private var rickFolder: URL?
    private(set) var lastState: ClaudeState?
    /// Доступы Claude (#10252) — с той же проверкой раз в минуту, что и патч.
    private var lastAccess: ClaudeAccess.State = .ok
    private var lostNotified = false
    /// Обновление Claude (WF86): срок суточной проверки переживает перезапуск; ошибка — повтор через час.
    var claudeUpdate = ClaudeUpdateMenu(nextDailyAt:
        UserDefaults.standard.object(forKey: ClaudeUpdateMenu.nextDailyKey) as? Date)
    /// Готовое обновление (`ready.json`) и для какой копии Claude.
    var readyClaude: (url: URL, prepared: PreparedClaudeUpdate)?
    /// Что нашла последняя проверка — его качает фон и ручное «Обновить».
    var foundRelease: ClaudeRelease?
    /// Идущая фоновая гонка — для отмены.
    var claudeDownload: DownloadControl?
    private let networkMonitor = NWPathMonitor()
    var costlyNetwork = false
    /// Сеть есть (`NWPath.status == .satisfied`) — без неё фон не начинает гонку: сорвётся и уйдёт на час.
    var networkUp = true
    /// Сколько фоновых перепроверок готового (`loadReady`) идёт — «Обновить» и загрузка ждут (A5).
    var readyRechecks = 0
    /// «Обновить» ждёт свежего ответа страниц о работе (гейт 2 WF87) — второе нажатие не нужно.
    var askingPages = false
    /// Сколько ждём круг страниц после нажатия: тик 2 с пишет вопрос, лоадер читает раз в 500 мс,
    /// ответ забирает следующий тик. Не дождались — «не знаем», вопрос в панели.
    static let pagesWaitSeconds: TimeInterval = 4

    /// Строка статуса патча — окну разрешений и подсказкам.
    private var stateText = "Проверяю…"
    private var iconPainter: StatusIconPainter?
    /// Сторож значка (#10016): значок за вырезом — узкий вид, потом плашка PMP под строкой меню.
    var statusGuard: StatusItemGuard?
    let panel = PimpPanelController()
    /// Проекты, «Отправить», цвета панели (WF126).
    lazy var feed = PanelFeed(ax: ax, panel: panel)
    /// «💛 Поддержать автора» (WF108, #8179): окно и строка в настройках панели.
    let donate = DonateWindowController()
    /// Температура Мака в панели (#8898): опрос раз в минуту на своей очереди, пока выключатель включён.
    private let temperature = MacTemperatureMonitor(
        file: Patcher.defaultSupportDirectory.appendingPathComponent("temperature-history.json"))
    /// Нагрузка на память (#9082, WF164): копит 3 ч молча, в панель отдаёт, только пока она открыта.
    let memory = MacMemoryMonitor(file: Patcher.defaultSupportDirectory.appendingPathComponent("memory-history.json"))
    /// Процессор и видеокарта (#10308): опрос раз в минуту на своей очереди, пока выключатель включён.
    private let macLoad = MacLoadMonitor(file: Patcher.defaultSupportDirectory.appendingPathComponent("load-history.json"))
    /// «Мак перегрелся» (#10998): по точкам температуры, не чаще раза в 30 мин.
    private let heatWarner = MacHeatWarner()
    private var iconTimer: Timer?
    /// Терминалы всегда на экране (#10564): окно каждой сессии `rick-<проект>` — раз за её жизнь.
    private let terminalKeeper = TerminalKeeper()
    private var terminalTimer: Timer?
    /// Вид значка «Проекты» (WF129): когда сводку проектов перечитывали для значка.
    private var iconProjectsAt = Date.distantPast
    /// «Самое время» (WF87): какую готовую версию сейчас предлагаем и с какого момента она готова.
    var offering: String?
    var readySince: (version: String, at: Date)?
    /// Что добавляет к машине обновления панель: вопрос, «Позже», шаг установки, «готово», сбой.
    var updateExtras = PimpPanelText.UpdateExtras()
    var extrasGeneration = 0
    /// Идёт установка, отложенная «При запуске» (WF283), при закрытом Claude, и открыли ли его за это время.
    var plannedInstallRunning = false
    var claudeOpenedDuringPlanned = false
    /// Журнал патча из панели — для «Подробнее…».
    var patchLog: [String] = []
    var patchSettings: (() -> Void)?
    /// Автообновление самого Пимпа и PimpViewer (WF217, К-SU).
    let selfUpdate = SelfUpdateDriver()
    /// Последние известные лимиты (#9824): с прошлого запуска или из страницы — вместо «—», бледным и с давностью.
    lazy var knownLimits: ClaudeLimits? = LimitsMemory.load()
    private var seenLimits: ClaudeLimits?
    /// Работа вне страниц Claude (WF234): последняя сводка Workflow и терминальных чатов и когда её спрашивали.
    var workWatch = WorkWatch()
    var workAskedAt = Date.distantPast
    /// Строка «что идёт», которую сейчас показывает блок обновления, — сменилась, блок перерисовывается.
    var shownWorkLine: String?
    /// Подсказка под окном macOS «Claude Safe Storage» (WF238): встаёт, когда Claude открывается переподписанным.
    let keychainHint = KeychainHintController()
    /// Плашка «Включи PimpMyClaude в «Управление приложениями»» у окна настроек (#9842).
    private let permissionHint = PermissionHintController()
    /// Мастер доступов Claude в карточке панели и его плашка у окна настроек (#10310).
    private let accessWizard = AccessWizardController()
    /// Отметка перезапуска живёт столько: дольше — человек ушёл, продолжать молча нельзя.
    private static let resumeSeconds: TimeInterval = 15 * 60

    // ---------------------------------------------------------------- запуск

    func applicationDidFinishLaunching(_ notification: Notification) {
        let previous = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        let installed = try? Data(contentsOf: SupportFiles.directory.appendingPathComponent(SupportFiles.installedFileName))
        // All migrations, including Auto-Allow, use this one pre-write snapshot.
        AutomationDefaults.migrate(values: previous, legacyPatched: AutomationDefaults.legacyMarker(installed))
        KeepOldDefaults.apply(values: previous, installed: installed) // #11655: умолчания 03.11 — только новым
        DimSetting.resetOnLaunch()
        UserDefaults.standard.register(defaults: [Key.autoAllow: false, Key.pmpKeys: true, Key.blockQuit: true,
                                                  MacTemperature.enabledKey: true, MacMemory.enabledKey: true,
                                                  MacLoad.enabledKey: true])
        // Новая версия Пимпа скачана и проверена заранее (WF217, К-SU) — встаёт сейчас, пока интерфейса ещё нет:
        // помощник дождётся выхода и откроет её.
        if selfUpdate.installAtLaunch() { exit(0) }
        // Значок «Claude» (WF269, #10220): сохранённый выбор один раз переводится на него.
        if StatusIcon.migrateToClaude() { panel.model.iconVariant = .claude }
        buildStatusItem()
        wirePanel()
        wireLiveCheck()
        wireRestartClaude()
        applySettingsToAX()
        temperature.onUpdate = { [weak self] history in
            self?.panel.model.temperature = history
            self?.refreshIcon() // градусы на значке «Claude» (WF269)
            self?.heatWarner.check(history, gpu: self?.panel.model.macLoad.last?.gpu) { Notifier.postHeatWarn(title: $0, body: $1) }
        }
        applyTemperatureSetting()
        memory.onUpdate = { [weak self] history in self?.panel.model.memory = history }
        memory.onEaters = { [weak self] eaters in self?.panel.model.memoryEaters = eaters }
        applyMemorySetting()
        macLoad.onUpdate = { [weak self] history in self?.panel.model.macLoad = history }
        applyLoadSetting()
        Patcher.refreshLiveFilesIfBundledNewer() // z9-r01: страница из сборки строго новее живой — до ax.start()
        KontekstGuard.refreshCopy()
        ax.start()
        // Новая установка (WF210, #9378): «Живой» включён, тема — «Фиолетовая»; кто уже ставил или выбирал — мимо.
        if PanelColorTiles.isNewInstall(values: previous, installed: installed) { ax.applyNewInstallLook() }
        // Рик приходит вместе с Пимпом (WF216, #9381): на новой установке — сам; папка Rick уже есть — не трогаем.
        if case .installed(let folder) = RickKit.firstRun(values: previous, installed: installed) {
            rickFolder = folder
        }
        // Радиус рамки и поля по бокам живут блоком в claude.css — восстанавливаем его на
        // запуске (план WF14, решение 1: три точки записи, это первая).
        ax.refreshLiveStyle()
        Notifier.registerCategory(delegate: self)
        configureLoginItemOnFirstRun()
        refreshState()
        permissionHint.onRelaunch = { [weak self] in self?.relaunchForPermission() }
        wireAccessWizard()
        resumeAfterPermissionRelaunch()
        // `open -a PimpMyClaude.app --args --status` — окно статуса без похода в меню (нужно на гейте).
        if CommandLine.arguments.contains("--status") { showStatus() }
        // `open -a PimpMyClaude --args --panel` — панель у часов без клика (нужно на гейте, WF101).
        if CommandLine.arguments.contains("--panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openPanel() }
        }
        // `open -a PimpMyClaude --args --permission-hint` — плашка «Управление приложениями» без патча (гейт #9842).
        if CommandLine.arguments.contains("--permission-hint") { permissionHint.show() }
        // Первый запуск: пошаговое окно разрешений. Закрыли — больше не всплываем,
        // вернуться можно пунктом «Настроить разрешения…».
        if !UserDefaults.standard.bool(forKey: Key.setupDone) { showSetup() }

        // Решение 4: проверка при активации Claude и раз в 60 с.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(checkClaudeUpdateAfterWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(claudeDownloadBeforeSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appLaunchedOrQuit(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appLaunchedOrQuit(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        wireSelfUpdate()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let costly = path.isExpensive || path.isConstrained
            let up = path.status == .satisfied
            DispatchQueue.main.async { self?.networkChanged(costly: costly, up: up) }
        }
        networkMonitor.start(queue: .global(qos: .utility))
        // Сперва готовое с прошлого запуска, потом суточная проверка — иначе проверка с загрузкой
        // и перепроверка готового поделили бы одну папку распаковки.
        // Отложенное «При запуске» (WF283): Claude не запущен — ставим сразу, проверка тогда подождёт таймера.
        restoreReadyClaude { [weak self] in
            self?.installPlannedIfClaudeClosed()
            self?.checkClaudeUpdate(trigger: .daily)
        }
        let poll = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshState()
            // Отложенное (WF283) не застряло: при выходе Claude PMP был занят или процессы Claude ещё уходили.
            self?.installPlannedIfClaudeClosed()
            self?.checkClaudeUpdate(trigger: .daily)
            // Загрузка не только из ответа проверки: сорвалась (повтор через час), отменили (сон,
            // дорогая сеть) — продолжаем здесь, а не через сутки (гейт 1 WF87, A1).
            self?.resumeClaudeDownload()
            self?.selfUpdate.tick()
        }
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
        // Лимиты на значке и «самое время» (WF87): канал probe отвечает раз в минуту, значок
        // перерисовывается только при смене вида.
        let icon = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshIconProjects()
            self?.refreshIcon()
            self?.evaluateOffer()
        }
        RunLoop.main.add(icon, forMode: .common)
        iconTimer = icon
        let keeper = Timer(timeInterval: TerminalKeeper.interval, repeats: true) { [weak self] _ in
            self?.terminalKeeper.tick()
        }
        RunLoop.main.add(keeper, forMode: .common)
        terminalTimer = keeper
        ITermQuiet.shared.activated = { [weak self] in self?.terminalKeeper.tick() }
        ITermQuiet.shared.start()
        PhoneMirrorFit.shared.start()
    }

    /// Повторный запуск из Finder/Launchpad: окна в доке нет, покажем окно настройки — иначе
    /// человеку кажется, что приложение не запускается.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showSetup() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        iconTimer?.invalidate()
        terminalTimer?.invalidate()
        claudeDownload?.cancel()
        networkMonitor.cancel()
        ax.stop()
        // #10394: подсветку клавиатуры — обратно macOS, как «Выход» NightWolf.
        NightLight.shared.quit()
    }

    /// Значок PMP у часов: левый клик — панель, правый (или ⌃-клик) — короткое меню (10-choice §2).
    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        iconPainter = StatusIconPainter(button: button)
        let watcher = StatusItemGuard(item: item)
        watcher.onCompactChange = { [weak self] in self?.refreshIcon() }
        watcher.onTabClick = { [weak self] tab in self?.tabClicked(tab) }
        watcher.onTabMenu = { [weak self] event, view in self?.showShortMenu(event: event, in: view) }
        statusGuard = watcher
        refreshIcon()
        watcher.start()
    }

    /// Плашка PMP (значок за вырезом): то же, что левый клик по значку. Нажатие мимо открытой панели её уже закрыло —
    /// не открываем снова.
    private func tabClicked(_ tab: NSStatusBarButton) {
        if panel.isShown {
            panel.toggle(from: tab)
        } else if !panel.closedJustNow {
            panel.open(from: tab)
        }
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showShortMenu()
        } else {
            panel.toggle(from: sender)
        }
    }

    /// Правый клик (WF126 §6): «Настройки…», разрешения, о программе, выйти. С плашки (#10016) — у неё.
    private func showShortMenu(event: NSEvent? = nil, in view: NSView? = nil) {
        panel.close()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Разрешения macOS…", action: #selector(showSetup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "О программе", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        if let event = event, let view = view {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            return
        }
        guard let item = statusItem, let button = item.button else { return }
        // Меню на время одного клика: иначе левый клик тоже открывал бы его, а не панель.
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    /// Панель сразу на листе «Настройки».
    @objc private func showSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.openPanel()
            self.panel.showSheet(.settings)
        }
    }

    /// Состояние патча глазами значка и панели. Страницы отвечают только старым лоадером (WF111) —
    /// «Вернуть патч», даже если на диске патч новый.
    var patchLook: StatusIcon.Patch {
        let disk: StatusIcon.Patch
        switch lastState {
        case .none: disk = .unknown
        case .claudeNotFound?: disk = .claudeNotFound
        case .notInstalled(let version)?: disk = .notInstalled(version: version)
        case .lost(let version, let reason)?: disk = .lost(version: version, reason: reason)
        case .installed(let version, let loader)?: disk = .installed(version: version, loader: loader)
        }
        return PimpPanelText.patch(disk, needsRepatch: ax.pageSignals.needsRepatch)
    }

    /// Лимиты для значка и панели: пришли новые от страницы — запомнить на диск, иначе последние известные.
    func currentLimits() -> ClaudeLimits? {
        let live = ax.pageSignals.limits
        if live != seenLimits {
            seenLimits = live
            knownLimits = LimitsMemory.remember(live)
        }
        return knownLimits
    }

    func refreshIcon() {
        let limits = currentLimits()
        if panel.isOpen, panel.model.sendDelay != ax.sendDelaySetting { panel.model.sendDelay = ax.sendDelaySetting }
        if panel.isOpen, panel.model.claudeZoom != ax.claudeZoom, let zoom = ax.claudeZoom { panel.model.claudeZoom = zoom }
        let patch = patchLook
        // Значок — вариант под «Цвет PMP» (WF189: картинки на выбор, по умолчанию «PMP и неделя» с процентами).
        let variant = panel.model.iconVariant
        var missing: [String] = []
        if case .missing(let services) = lastAccess { missing = services.map(\.title) }
        var look = StatusIcon.look(mode: variant.mode, limits: limits, patch: patch,
                                   phase: claudeUpdate.phase, now: Date(), access: missing,
                                   guardMissing: panel.model.kontekst != .ok)
        if variant == .claude, let temp = StatusIcon.degrees(panel.model.temperature.last,
                                                             enabled: UserDefaults.standard.bool(forKey: MacTemperature.enabledKey),
                                                             now: Date(), minimum: StatusIcon.tempMin()) {
            look.degrees = temp.degrees
            look.heat = temp.heat
        }
        if variant.showsProjects, let snapshot = panel.model.projects {
            let groups = PanelTiles.groups(snapshot, now: Date())
            look = StatusIcon.compose(look, variant: variant, summary: PanelTiles.summary(groups),
                                      toolTip: PanelTiles.summaryHelp(groups))
        } else {
            look = StatusIcon.compose(look, variant: variant, summary: nil, toolTip: "PMP — читаю проекты")
        }
        let accent = PMPAccent.current.nsColor
        iconPainter?.apply(statusGuard?.shown(look, accent: accent) ?? look, accent: accent)
        // Тот же значок — в шапке панели (#9020 п. 3).
        if panel.model.iconLook != look { panel.model.iconLook = look }
        // Ответы страниц меняют карточку патча между проверками диска (раз в минуту).
        if panel.model.access != lastAccess { panel.change { panel.model.access = lastAccess } }
        if panel.model.patch != patch {
            panel.change {
                panel.model.patch = patch
                if case .installed(_, let loader) = patch { panel.model.loader = loader }
            }
        }
        guard panel.isOpen else { return }
        let model = panel.model
        if model.limits != limits { model.limits = limits }
    }

    /// Сводка проектов для значка (вид «Проекты»): раз в 30 с, пока панель закрыта (открытую ведёт `PanelFeed`).
    func refreshIconProjects(force: Bool = false) {
        guard panel.model.iconVariant.showsProjects, force || !panel.isOpen,
              force || Date().timeIntervalSince(iconProjectsAt) >= 30 else { return }
        iconProjectsAt = Date()
        ax.panelProjects { [weak self] snapshot in
            guard let self = self else { return }
            if self.panel.model.projects != snapshot { self.panel.model.projects = snapshot }
            self.refreshIcon()
        }
    }

    // ---------------------------------------------------------------- статус

    @objc private func appActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == Patcher.claudeBundleID else { return }
        refreshState()
    }

    func refreshState() {
        guard !busy else { return }
        guard let url = chosenClaude(askIfSeveral: false) else { show(state: .claudeNotFound); return }
        DispatchQueue.global(qos: .utility).async {
            let state = ClaudePatcher(appURL: url).state()
            // #10568: встроенный обновлятор Claude не качает зря, пока патч стоит.
            ShipItCache.hold(patched: state.isInstalled)
            let facts = AccessWizardController.read(appURL: url, patched: state.isInstalled)
            DispatchQueue.main.async {
                // #10310: состояние — через мастер: снятые им записи (`tccutil`) остаются «слетевшими», пока их не выдали.
                self.lastAccess = self.accessWizard.update(facts, appURL: url)
                self.show(state: state)
            }
        }
    }

    /// Мастер доступов (#10310): «Сделать постоянной» — тот же патч, что в панели; опрос — пока панель открыта.
    func wireAccessWizard() {
        let wizard = accessWizard
        wizard.isPanelOpen = { [weak self] in self?.panel.isOpen == true }
        wizard.isBusy = { [weak self] in self?.busy == true }
        wizard.patchFailed = { [weak self] in
            if case .failed? = self?.panel.model.patchRun { return true }
            return false
        }
        wizard.sign = { [weak self] in self?.patchFromPanel() }
        wizard.relaunch = { [weak self] in self?.relaunchForPermission() }
        wizard.publish = { [weak self] snapshot in
            guard let self = self, self.panel.model.wizard != snapshot else { return }
            self.panel.change { self.panel.model.wizard = snapshot }
        }
        wizard.onAccess = { [weak self] state in
            self?.lastAccess = state
            self?.refreshIcon()
        }
        panel.model.actions.accessWizard = { [weak wizard] action in wizard?.perform(action) }
    }

    private func show(state: ClaudeState) {
        stateText = state.menuTitle
        lastState = state
        // Claude обновился (#10527): версию, которую ещё не проверяли, проверить на живом окне.
        if case .installed(let version, _) = state { ax.armLiveCheck(claude: version) }
        refreshKontekst() // сторож виден значком и тем, кто панель не открывает
        refreshIcon() // карточку патча обновляет он же
        notifyIfPatchLost(state)
    }

    /// Решение 4: одно уведомление «патч слетел» с кнопкой «Вернуть патч» (WF87),
    /// повторов нет, пока патч не вернулся на место.
    private func notifyIfPatchLost(_ state: ClaudeState) {
        if case .lost(let version, let reason) = state {
            guard !lostNotified else { return }
            // Флаг взводится только когда баннер реально отправлен: без разрешения на уведомления
            // попробуем снова на следующей проверке (человек мог разрешить их в окне настройки).
            Notifier.postPatchLost(PimpPanelText.patchLostNotice(version: version, reason: reason)) { [weak self] sent in
                if sent { self?.lostNotified = true }
            }
            return
        }
        if lostNotified {
            lostNotified = false
            Notifier.clearPatchLost()
        }
    }

    // ---------------------------------------------------------------- поиск Claude

    /// Решение 3: ищем по bundle id (Launch Services видит и ~/Applications). Копий несколько — спрашиваем.
    private func chosenClaude(askIfSeveral: Bool) -> URL? {
        let copies = Patcher.locateClaude()
        if copies.isEmpty { return nil }
        // Сохранённая скрытая копия (#7096: `.Claude-before-Matrix-1.20186.1.app`) забывается.
        let saved = Patcher.savedClaude(UserDefaults.standard.string(forKey: Key.claudePath), among: copies)
        if saved.forget { UserDefaults.standard.removeObject(forKey: Key.claudePath) }
        if let match = saved.url { return match }
        if copies.count == 1 { return copies[0] }
        guard askIfSeveral else { return copies[0] }

        let alert = NSAlert()
        alert.messageText = "Какой Claude патчить?"
        alert.informativeText = "На Маке несколько копий Claude.app. Выбери ту, которой пользуешься."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
        copies.forEach { popup.addItem(withTitle: $0.path) }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Продолжить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let chosen = copies[max(0, popup.indexOfSelectedItem)]
        UserDefaults.standard.set(chosen.path, forKey: Key.claudePath)
        return chosen
    }

    // ---------------------------------------------------------------- патч: окно разрешений, «Снять патч», --status

    /// Кнопка «Пропатчить Claude» окна разрешений (панель патчит без вопроса — `patchFromPanel`).
    @objc private func install() {
        guard !busy, let url = askForClaude() else { return }
        let alert = NSAlert()
        alert.messageText = "Пропатчить Claude?"
        alert.informativeText = (patchWorkNote().map { $0 + "\n\n" } ?? "") + """
            Claude закроется и через несколько секунд откроется снова.
            Файлы Claude сохранятся. «Снять патч…» (панель у часов › Настройки › Обновления) вернёт их.
            После первой установки macOS один раз заново спросит разрешения (микрофон, экран).

            \(url.path)
            """
        alert.addButton(withTitle: "Пропатчить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        runOperation(title: "Пропатчить Claude", appURL: url) { patcher, progress in
            switch try patcher.install(progress: { line in
                progress(line)
                self.keychainHintIfClaudeOpens(line, .patch)
            }) {
            case .alreadyInstalled(let version): return "Патч уже стоял — Claude \(version) не трогали."
            case .repaired(let version): return "Починил: хэш и подпись Claude \(version) снова сходятся."
            case .installed(let version): return "Готово. Патч стоит в Claude \(version)."
            }
        }
    }

    @objc func uninstall() {
        panel.close()
        guard !busy, let url = askForClaude() else { return }
        let alert = NSAlert()
        alert.messageText = "Снять патч?"
        alert.informativeText = (patchWorkNote().map { $0 + "\n\n" } ?? "") + """
            Вернём оригинальные app.asar и Info.plist из бэкапа и переподпишем Claude локальной подписью.
            Подпись Apple при этом не возвращается — настоящий откат это переустановка Claude с claude.ai/download.
            Claude закроется и откроется снова.

            \(url.path)
            """
        alert.addButton(withTitle: "Снять")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        runOperation(title: "Снять патч", appURL: url) { patcher, progress in
            try patcher.restore(progress: progress)
            return "Готово. Оригинальные файлы Claude на месте."
        }
    }

    @objc private func showStatus() {
        guard !busy else { return }
        guard let url = chosenClaude(askIfSeveral: true) else { report(PatchError.claudeNotFound); return }
        let window = OperationWindow(title: "Статус")
        window.show()
        let patcher = ClaudePatcher(appURL: url)
        DispatchQueue.global(qos: .userInitiated).async {
            let state = patcher.state()
            let report = (try? patcher.fullStatus())?.report
            DispatchQueue.main.async {
                window.append(state.menuTitle)
                window.append("")
                window.append(report ?? "Подробности недоступны: app.asar не читается.")
                window.finish("")
                self.show(state: state)
            }
        }
    }

    // ---------------------------------------------------------------- «Управление приложениями» (#9842)

    /// Строка журнала патча (любая нитка): шаг записи ждёт права — настройки на нужной странице и плашка рядом,
    /// отметка «что продолжить после перезапуска»; любая следующая строка — право есть, плашка уходит.
    func watchPermission(_ line: String, resume kind: String?) {
        DispatchQueue.main.async {
            if line == Patcher.appManagementWaitLine {
                UserDefaults.standard.set(kind ?? "panel", forKey: Key.resumeKind)
                UserDefaults.standard.set(Date(), forKey: Key.resumeAt)
                self.panel.close() // настройки и плашка встают поверх; панель всё равно закрылась бы от клика
                self.permissionHint.show()
            } else if self.permissionHint.isShown {
                self.permissionHint.hide()
            }
        }
    }

    /// Операция кончилась (главная нитка): плашка уходит. `needsRelaunch` — Пимп перезапускается и продолжит сам
    /// (true — вызывающему больше ничего не делать); иначе отметка снимается.
    @discardableResult
    func permissionEnded(_ error: Error?) -> Bool {
        permissionHint.hide()
        if case PatchError.needsRelaunch? = error {
            relaunchForPermission()
            return true
        }
        UserDefaults.standard.removeObject(forKey: Key.resumeKind)
        UserDefaults.standard.removeObject(forKey: Key.resumeAt)
        return false
    }

    /// Право дали, но этот процесс macOS не пускает до перезапуска: помощник откроет Пимп заново, отметка
    /// скажет ему продолжить. Ссылка плашки «перезапустить PMP» — сюда же.
    private func relaunchForPermission() {
        if UserDefaults.standard.string(forKey: Key.resumeKind) == nil {
            UserDefaults.standard.set("panel", forKey: Key.resumeKind)
        }
        UserDefaults.standard.set(Date(), forKey: Key.resumeAt)
        Patcher.cancelPermissionWait()
        SelfUpdater.relaunchOrOpen(Bundle.main.bundleURL)
        NSApp.terminate(nil)
    }

    /// Запуск после такого перезапуска (наш или «Закрыть и открыть снова» в настройках): патч из панели — заново
    /// сам, обновление Claude и прочее — панель открыта, кнопка ждёт. Отметка одноразовая.
    private func resumeAfterPermissionRelaunch() {
        let defaults = UserDefaults.standard
        guard let kind = defaults.string(forKey: Key.resumeKind) else { return }
        let at = defaults.object(forKey: Key.resumeAt) as? Date ?? .distantPast
        defaults.removeObject(forKey: Key.resumeKind)
        defaults.removeObject(forKey: Key.resumeAt)
        guard Date().timeIntervalSince(at) < Self.resumeSeconds else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.openPanel()
            if kind == "patch" { self.patchFromPanel() }
        }
    }

    /// Claude открывается уже переподписанным — macOS сейчас спросит пароль к «Claude Safe Storage»: под её окном
    /// встаёт подсказка (WF238). Зовётся из фоновой нитки патча.
    func keychainHintIfClaudeOpens(_ line: String, _ kind: KeychainHint.Kind) {
        guard KeychainHint.opensClaude(line) else { return }
        DispatchQueue.main.async { self.keychainHint.begin(kind) }
    }

    /// «Подробнее…» под ошибкой патча — прежнее окно журнала.
    func showPatchLog() {
        panel.close()
        let window = OperationWindow(title: "Пропатчить Claude")
        window.show()
        patchLog.dropLast().forEach { window.append($0) }
        window.finish(patchLog.last ?? "", settings: patchSettings)
    }

    /// «Найти Claude…»: Claude лежит не там, где его видит Launch Services, — покажи сам.
    func findClaude() {
        panel.close()
        let open = NSOpenPanel()
        open.allowedContentTypes = [.applicationBundle]
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.message = "Где лежит Claude.app?"
        NSApp.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK, let url = open.url else { return }
        guard Bundle(url: url)?.bundleIdentifier == Patcher.claudeBundleID else {
            report(NSError(domain: "PimpMyClaude", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Это не Claude: \(url.lastPathComponent)."]))
            return
        }
        LSRegisterURL(url as CFURL, true)
        UserDefaults.standard.set(url.path, forKey: Key.claudePath)
        refreshState()
    }

    // ---------------------------------------------------------------- первый запуск, о программе

    /// «Поставить Рика» в настройках панели (WF216): то же копирование, что на новой установке, не на главной нитке.
    func installRick() {
        guard panel.model.rick != .running else { return }
        panel.change { panel.model.rick = .running }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = RickKit.install()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.panel.change { self.panel.model.rick = RickInstall(outcome) }
            }
        }
    }

    /// Пошаговое окно разрешений: первый запуск и пункт меню. Второй раз не плодим — поднимаем открытое.
    @objc func showSetup() {
        panel.close()
        if let setup = setup {
            setup.show()
            return
        }
        let window = SetupWindow(
            rickFolder: rickFolder,
            kontekst: { [weak self] in
                self?.refreshKontekst()
                return self?.panel.model.kontekst ?? .ok
            },
            onKontekst: { [weak self] in self?.installKontekst() },
            stateText: { [weak self] in self?.stateText ?? "" },
            patchInstalled: { [weak self] in self?.lastState?.isInstalled ?? false },
            onInstall: { [weak self] in self?.install() },
            onClose: { [weak self] in
                UserDefaults.standard.set(true, forKey: Key.setupDone)
                self?.setup = nil
            })
        setup = window
        window.show()
    }

    @objc func showAbout() {
        panel.close()
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let alert = NSAlert()
        alert.messageText = "PimpMyClaude \(version) (\(build))"
        alert.informativeText = """
            Прокачка Claude Desktop: узкие окна и поля, ручка над полем ввода, цвета и шрифт окон, \
            горячие клавиши, обратный отсчёт, Авто-Allow и блокировка ⌘Q. Без Hammerspoon и Node.

            \(Bundle.main.bundleURL.path)
            Elvis Iglikov
            """
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // ---------------------------------------------------------------- уведомления

    /// Баннер показываем, даже когда наше приложение впереди.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Клик разводится по категории (критик WF87 п. 7): «Патч слетел» → «Вернуть патч», «Скачалось
    /// обновление Claude» → «Обновить» (то же, что кнопка блока панели) или «Позже»; клик по самому
    /// баннеру — только панель у значка; закрыть баннер — ничего.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        let route = ClaudeUpdateMenu.route(category: category, action: action)
        let liveCheckFile = response.notification.request.content.userInfo[Notifier.liveCheckFileKey] as? String
        DispatchQueue.main.async { [weak self] in
            // Проверка окна (#10527): «Отчёт» и нажатие по баннеру — файл отчёта; файла нет — панель с его строкой.
            if category == Notifier.liveCheckCategory {
                guard action != UNNotificationDismissActionIdentifier else { return }
                if let path = liveCheckFile, FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } else {
                    self?.openPanel()
                }
                return
            }
            guard let self = self else { return }
            if category == StatusItemNotice.category, action == UNNotificationDefaultActionIdentifier {
                self.openPanel()
                return
            }
            if category == ClaudeUpdateMenu.readyCategory, action == Notifier.laterAction {
                self.updateLater()
                return
            }
            switch route {
            case .reinstallPatch:
                self.openPanel()
                if action == ClaudeUpdateMenu.patchAgainAction { self.patchFromPanel() }
            case .updateClaude:
                if action == ClaudeUpdateMenu.updateAction { self.updateClaude() } else { self.openPanel() }
            case .nothing:
                break
            }
        }
        completionHandler()
    }

    func askForClaude() -> URL? {
        if let url = chosenClaude(askIfSeveral: true) { return url }
        report(PatchError.claudeNotFound)
        return nil
    }

    /// Патч крутится в фоне, окно только пишет строки — меню-бар остаётся живым.
    private func runOperation(title: String, appURL: URL,
                              body: @escaping (ClaudePatcher, (String) -> Void) throws -> String) {
        busy = true
        refreshUpdateBlock()
        let window = OperationWindow(title: title)
        window.show()
        let patcher = ClaudePatcher(appURL: appURL)
        DispatchQueue.global(qos: .userInitiated).async {
            let post: (String) -> Void = { line in
                self.watchPermission(line, resume: nil)
                DispatchQueue.main.async { window.append(line) }
            }
            do {
                let done = try body(patcher, post)
                DispatchQueue.main.async {
                    self.permissionEnded(nil)
                    window.finish(done)
                    self.operationFinished()
                }
            } catch {
                let message = error.humanText
                let settings = Self.settingsAction(for: error)
                DispatchQueue.main.async {
                    if self.permissionEnded(error) { return }
                    window.finish("Не вышло. " + message, settings: settings)
                    self.operationFinished()
                }
            }
        }
    }

    func operationFinished() {
        busy = false
        refreshUpdateBlock()
        // «Пропатчить Claude» кладёт в claude.css авто-блок из бандла (Patcher.installLiveCSS, WF45 —
        // свои правила человека при этом сохраняются), а блок надо пересчитать под живой
        // sidePadding и версию macOS (план WF14, решение 1).
        ax.refreshLiveStyle()
        refreshState()
    }

    static func settingsAction(for error: Error) -> (() -> Void)? {
        if case PatchError.needsAppManagement = error { return { SystemSettings.open(SystemSettings.appManagement) } }
        return nil
    }

    func report(_ error: Error) {
        panel.close()
        Alerts.failure(error)
    }

    // ---------------------------------------------------------------- тумблеры

    private func applySettingsToAX() {
        let defaults = UserDefaults.standard
        // «Сам нажимать „Allow once“» вернулся (#9998, слово Элвиса 16.10.2026 20:38) — для чатов без Bypass;
        // в чатах с Bypass permissions страница жмёт сама и при выключенном.
        ax.autoAllowEnabled = defaults.bool(forKey: Key.autoAllow)
        ax.configureAutoContinue(on: defaults.bool(forKey: AutomationDefaults.continueKey),
                                 preservePageChoice: defaults.bool(forKey: AutomationDefaults.continueMigrationKey))
        applyAutoRetry()
        ax.pmpKeysEnabled = defaults.bool(forKey: Key.pmpKeys)
        ax.blockQuitEnabled = defaults.bool(forKey: Key.blockQuit)
    }

    /// Выключатели панели (сетка по два в ряд): состояние и подсказки — прежние пункты меню.
    func updateToggleMarks() {
        let defaults = UserDefaults.standard
        // Без Универсального доступа живым остаётся блок ⌘Q (Carbon-хоткеи доверия не просят).
        let trusted = ax.isAccessibilityTrusted || AXIsProcessTrusted()
        let needsAX = "Включи PimpMyClaude в Универсальном доступе: «Разрешения macOS…»"
        let toggles = [
            PanelToggle(id: Key.autoAllow, title: SettingsText.autoAllowTitle, on: defaults.bool(forKey: Key.autoAllow),
                        needsAccess: false, toolTip: SettingsText.autoAllowHelp),
            PanelToggle(id: AutomationDefaults.continueKey, title: SettingsText.continueTitle,
                        on: defaults.bool(forKey: AutomationDefaults.continueMigrationKey)
                            ? ax.autoContinueReported ?? false : defaults.bool(forKey: AutomationDefaults.continueKey), needsAccess: false,
                        toolTip: "Чат написал блок «🆕 ОТКРОЙ НОВЫЙ ЧАТ» — PMP сам открывает новый чат с его текстом и моделью, когда ты не печатаешь. Сохранённые настройки страниц сохраняются до явного выбора здесь.",
                        mixed: defaults.bool(forKey: AutomationDefaults.continueMigrationKey) && ax.autoContinueReported == nil),
            // WF237: бывший «Меню на жёлтой кнопке окна» (лист 48, ответ 2.1) — меню снято, выключатель держит клавиши.
            PanelToggle(id: Key.pmpKeys, title: SettingsText.pmpKeysTitle, on: defaults.bool(forKey: Key.pmpKeys),
                        needsAccess: !trusted, toolTip: trusted ? SettingsText.pmpKeysHelp : needsAX),
            PanelToggle(id: Key.blockQuit, title: "⌘Q не закрывает Claude", on: defaults.bool(forKey: Key.blockQuit),
                        needsAccess: false,
                        toolTip: "⌘Q не закрывает Claude, пока его окно впереди. Работает и без Accessibility."),
            // Маяк окон доступа (WF91): читает ключ сам раз в секунду — перезапуск не нужен.
            PanelToggle(id: ConsentBeacon.enabledKey, title: "Подсвечивать окна разрешений macOS",
                        on: ConsentBeacon.isEnabled(in: defaults), needsAccess: false,
                        toolTip: PimpPanelText.consentToolTip),
            // #9358: умолчание — включено, когда есть главный чат (`mainProject`); вставка — AX (фокус окна и ⌘V).
            PanelToggle(id: AirDropWatch.enabledKey, title: "Фото с AirDrop — в поле Рика", on: ax.airDropEnabled,
                        needsAccess: !trusted,
                        toolTip: trusted ? "Фото, присланные по AirDrop, PMP сам вставляет в поле ввода главного чата. Enter не жмёт; в поле текст — не вставляет, фото остаются в «Загрузках»." : needsAX),
            PanelToggle(id: MacTemperature.enabledKey, title: "Температура в панели",
                        on: defaults.bool(forKey: MacTemperature.enabledKey), needsAccess: false,
                        toolTip: "Градусы чипа раз в минуту и график за 3 часа внизу панели. Выключено — Мак не опрашивается."),
            PanelToggle(id: MacMemory.enabledKey, title: "Память в панели",
                        on: defaults.bool(forKey: MacMemory.enabledKey), needsAccess: false,
                        toolTip: "Нагрузка на память раз в минуту и график за 3 часа, как в «Мониторинге системы». Выключено — Мак не опрашивается."),
            PanelToggle(id: MacLoad.enabledKey, title: "Процессор и видеокарта в панели",
                        on: defaults.bool(forKey: MacLoad.enabledKey), needsAccess: false,
                        toolTip: "Занятость процессора и видеокарты раз в минуту и графики за 3 часа. Выключено — Мак не опрашивается."),
            PanelToggle(id: "login", title: "Запускать вместе с Mac", on: SMAppService.mainApp.status == .enabled,
                        needsAccess: false,
                        toolTip: "Автозапуск при входе в систему; включается сам, когда приложение лежит в «Программах»."),
        ]
        if panel.model.toggles != toggles { panel.model.toggles = toggles }
    }

    func pressToggle(_ id: String) {
        switch id {
        case Key.autoAllow: toggleAutoAllow()
        case AutomationDefaults.continueKey:
            let defaults = UserDefaults.standard
            let on = !(defaults.bool(forKey: AutomationDefaults.continueMigrationKey)
                ? ax.autoContinueReported ?? false : defaults.bool(forKey: AutomationDefaults.continueKey))
            UserDefaults.standard.set(on, forKey: AutomationDefaults.continueKey)
            UserDefaults.standard.set(false, forKey: AutomationDefaults.continueMigrationKey)
            applySettingsToAX()
            updateToggleMarks()
        case Key.pmpKeys:
            if panel.model.toggles.first(where: { $0.id == id })?.needsAccess == true { showSetup() } else { togglePMPKeys() }
        case Key.blockQuit: toggleBlockQuit()
        case "login": toggleLoginItem()
        case MacTemperature.enabledKey:
            _ = flip(MacTemperature.enabledKey)
            applyTemperatureSetting()
        case MacMemory.enabledKey:
            _ = flip(MacMemory.enabledKey)
            applyMemorySetting()
        case MacLoad.enabledKey:
            _ = flip(MacLoad.enabledKey)
            applyLoadSetting()
        case ConsentBeacon.enabledKey:
            UserDefaults.standard.set(!ConsentBeacon.isEnabled(in: .standard), forKey: ConsentBeacon.enabledKey)
            updateToggleMarks()
        case AirDropWatch.enabledKey:
            if panel.model.toggles.first(where: { $0.id == id })?.needsAccess == true { showSetup() } else {
                ax.setAirDrop(!ax.airDropEnabled)
                updateToggleMarks()
            }
        default: break
        }
    }

    private func flip(_ key: String) -> Bool {
        let value = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        applySettingsToAX()
        updateToggleMarks()
        return value
    }

    private func toggleAutoAllow() { _ = flip(Key.autoAllow) }

    private func applyTemperatureSetting() {
        if UserDefaults.standard.bool(forKey: MacTemperature.enabledKey) { temperature.start() } else { temperature.stop() }
    }

    private func applyMemorySetting() {
        if UserDefaults.standard.bool(forKey: MacMemory.enabledKey) { memory.start() } else { memory.stop() }
    }

    private func applyLoadSetting() {
        if UserDefaults.standard.bool(forKey: MacLoad.enabledKey) { macLoad.start() } else { macLoad.stop() }
    }

    private func togglePMPKeys() {
        if flip(Key.pmpKeys) { warnIfNoAccessibility() }
    }

    private func toggleBlockQuit() { _ = flip(Key.blockQuit) }

    private func warnIfNoAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        panel.close()
        let alert = NSAlert()
        alert.messageText = "Нужен Универсальный доступ"
        alert.informativeText = "Клавиши PMP в Claude работают через Универсальный доступ (Accessibility). "
            + "Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → включи PimpMyClaude.\n\n"
            + AccessWizard.staleRowHint
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Потом")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { SystemSettings.open(SystemSettings.accessibility) }
    }

    // ---------------------------------------------------------------- автозапуск (решение 5)

    private func configureLoginItemOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.loginItemConfigured) else { updateToggleMarks(); return }
        // Dev-сборка из .build автозапуск не заводит — иначе в «Объектах входа» останется путь в .build.
        guard SetupWindow.isInApplicationsFolder else { updateToggleMarks(); return }
        defaults.set(true, forKey: Key.loginItemConfigured)
        try? SMAppService.mainApp.register()
        updateToggleMarks()
    }

    private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            report(error)
        }
        updateToggleMarks()
        if service.status == .requiresApproval {
            panel.close()
            let alert = NSAlert()
            alert.messageText = "Осталось разрешить автозапуск"
            alert.informativeText = "Системные настройки → Основные → Объекты входа: включи PimpMyClaude."
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Потом")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { SystemSettings.open(SystemSettings.loginItems) }
        }
    }
}
