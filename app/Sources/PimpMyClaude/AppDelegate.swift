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
    private enum Key {
        static let autoAllow = AutomationDefaults.allowKey
        static let minimizeMenu = "minimizeMenuEnabled"
        static let blockQuit = "blockQuitEnabled"
        static let loginItemConfigured = "loginItemConfigured"
        static let claudePath = "claudeAppPath"
        static let setupDone = "setupWindowSeen"
        /// «Самое время» обновить Claude (WF87): когда предлагали и до какого момента «Позже» (Date).
        static let lastOfferAt = "claudeUpdateLastOfferAt"
        static let snoozeUntil = "claudeUpdateSnoozeUntil"
    }
    /// «Позже» — на столько же, сколько пауза между предложениями.
    private static let snoozeSeconds = ClaudeUpdateMenu.offerRepeatSeconds

    private let ax = ClaudeAXController()
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var busy = false
    private var setup: SetupWindow?
    /// Рик встал сам на этом запуске (новая установка, WF216) — окно первой настройки говорит, где он.
    private var rickFolder: URL?
    private var lastState: ClaudeState?
    private var lostNotified = false
    /// Обновление Claude (WF86): срок суточной проверки переживает перезапуск; ошибка — повтор через час.
    private var claudeUpdate = ClaudeUpdateMenu(nextDailyAt:
        UserDefaults.standard.object(forKey: ClaudeUpdateMenu.nextDailyKey) as? Date)
    /// Готовое обновление (`ready.json`) и для какой копии Claude.
    private var readyClaude: (url: URL, prepared: PreparedClaudeUpdate)?
    /// Что нашла последняя проверка — его качает фон и ручное «Обновить».
    private var foundRelease: ClaudeRelease?
    /// Идущая фоновая гонка — для отмены.
    private var claudeDownload: DownloadControl?
    private let networkMonitor = NWPathMonitor()
    private var costlyNetwork = false
    /// Сеть есть (`NWPath.status == .satisfied`) — без неё фон не начинает гонку: сорвётся и уйдёт на час.
    private var networkUp = true
    /// Сколько фоновых перепроверок готового (`loadReady`) идёт — «Обновить» и загрузка ждут (A5).
    private var readyRechecks = 0
    /// «Обновить» ждёт свежего ответа страниц о работе (гейт 2 WF87) — второе нажатие не нужно.
    private var askingPages = false
    /// Сколько ждём круг страниц после нажатия: тик 2 с пишет вопрос, лоадер читает раз в 500 мс,
    /// ответ забирает следующий тик. Не дождались — «не знаем», вопрос в панели.
    private static let pagesWaitSeconds: TimeInterval = 4

    /// Строка статуса патча — окну разрешений и подсказкам.
    private var stateText = "Проверяю…"
    private var iconPainter: StatusIconPainter?
    private let panel = PimpPanelController()
    /// Проекты, «Отправить», цвета панели (WF126).
    private lazy var feed = PanelFeed(ax: ax, panel: panel)
    /// «💛 Поддержать автора» (WF108, #8179): окно, строка панели и пункт меню жёлтой кнопки.
    private let donate = DonateWindowController()
    /// Температура Мака в панели (#8898): опрос раз в минуту на своей очереди, пока выключатель включён.
    private let temperature = MacTemperatureMonitor()
    /// Нагрузка на память (#9082, WF164): копит 3 ч молча, в панель отдаёт, только пока она открыта.
    private let memory = MacMemoryMonitor()
    private var iconTimer: Timer?
    /// Вид значка «Проекты» (WF129): когда сводку проектов перечитывали для значка.
    private var iconProjectsAt = Date.distantPast
    /// «Самое время» (WF87): какую готовую версию сейчас предлагаем и с какого момента она готова.
    private var offering: String?
    private var readySince: (version: String, at: Date)?
    /// Что добавляет к машине обновления панель: вопрос, «Позже», шаг установки, «готово», сбой.
    private var updateExtras = PimpPanelText.UpdateExtras()
    private var extrasGeneration = 0
    private var updateSourceGeneration = 0
    /// Журнал патча из панели — для «Подробнее…».
    private var patchLog: [String] = []
    private var patchSettings: (() -> Void)?
    /// Автообновление самого Пимпа и PimpViewer (WF217, К-SU).
    private let selfUpdate = SelfUpdateDriver()

    // ---------------------------------------------------------------- запуск

    func applicationDidFinishLaunching(_ notification: Notification) {
        let previous = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        let installed = try? Data(contentsOf: Patcher.defaultSupportDirectory.appendingPathComponent("installed.json"))
        // All migrations, including Auto-Allow, use this one pre-write snapshot.
        AutomationDefaults.migrate(values: previous, legacyPatched: AutomationDefaults.legacyMarker(installed))
        DimSetting.resetOnLaunch()
        UserDefaults.standard.register(defaults: [Key.autoAllow: false, Key.minimizeMenu: true, Key.blockQuit: true,
                                                  MacTemperature.enabledKey: true, MacMemory.enabledKey: true])
        // Новая версия Пимпа скачана и проверена заранее (WF217, К-SU) — встаёт сейчас, пока интерфейса ещё нет:
        // помощник дождётся выхода и откроет её.
        if selfUpdate.installAtLaunch() { exit(0) }
        buildStatusItem()
        wirePanel()
        wireRestartClaude()
        ax.setDonate(visible: { [weak self] in self?.donate.entriesVisible ?? false },
                     open: { [weak self] in self?.donate.show() })
        applySettingsToAX()
        temperature.onUpdate = { [weak self] history in self?.panel.model.temperature = history }
        applyTemperatureSetting()
        memory.onUpdate = { [weak self] history in self?.panel.model.memory = history }
        applyMemorySetting()
        Patcher.refreshLiveFilesIfBundledNewer() // z9-r01: страница из сборки строго новее живой — до ax.start()
        ax.start()
        // Новая установка (WF210, #9378): «Живой» включён, тема — «Фиолетовая»; кто уже ставил или выбирал — мимо.
        if PanelColorTiles.isNewInstall(values: previous, installed: installed) { ax.applyNewInstallLook() }
        // Рик приходит вместе с Пимпом (WF216, #9381): на новой установке — сам; папка Rick уже есть — не трогаем.
        if case .installed(let folder) = RickKit.firstRun(values: previous, installed: installed,
                                                          configDefaults: Patcher.configDefaults) {
            rickFolder = folder
        }
        // Радиус рамки и поля по бокам живут блоком в claude.css — восстанавливаем его на
        // запуске (план WF14, решение 1: три точки записи, это первая).
        ax.refreshLiveStyle()
        Notifier.registerCategory(delegate: self)
        configureLoginItemOnFirstRun()
        refreshState()
        // `open -a PimpMyClaude.app --args --status` — окно статуса без похода в меню (нужно на гейте).
        if CommandLine.arguments.contains("--status") { showStatus() }
        // `open -a PimpMyClaude --args --panel` — панель у часов без клика (нужно на гейте, WF101).
        if CommandLine.arguments.contains("--panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openPanel() }
        }
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
        restoreReadyClaude { [weak self] in self?.checkClaudeUpdate(trigger: .daily) }
        let poll = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshState()
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
        claudeDownload?.cancel()
        networkMonitor.cancel()
        ax.stop()
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
        refreshIcon()
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showShortMenu()
        } else {
            panel.toggle(from: sender)
        }
    }

    /// Правый клик (WF126 §6): «Настройки…», разрешения, о программе, выйти.
    private func showShortMenu() {
        panel.close()
        guard let item = statusItem, let button = item.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Разрешения macOS…", action: #selector(showSetup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "О программе", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
    private var patchLook: StatusIcon.Patch {
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

    private func refreshIcon() {
        let signals = ax.pageSignals
        if panel.isOpen, panel.model.sendDelay != ax.sendDelaySetting { panel.model.sendDelay = ax.sendDelaySetting }
        let patch = patchLook
        // Значок — вариант под «Цвет PMP» (WF189: картинки на выбор, по умолчанию «PMP и неделя» с процентами).
        let variant = panel.model.iconVariant
        var look = StatusIcon.look(mode: variant.mode, limits: signals.limits, patch: patch,
                                   phase: claudeUpdate.phase, now: Date())
        if variant.showsProjects, let snapshot = panel.model.projects {
            let groups = PanelTiles.groups(snapshot, now: Date())
            look = StatusIcon.compose(look, variant: variant, summary: PanelTiles.summary(groups),
                                      toolTip: PanelTiles.summaryHelp(groups))
        } else {
            look = StatusIcon.compose(look, variant: variant, summary: nil, toolTip: "PMP — читаю проекты")
        }
        iconPainter?.apply(look, accent: PMPAccent.current.nsColor)
        // Тот же значок — в шапке панели (#9020 п. 3).
        if panel.model.iconLook != look { panel.model.iconLook = look }
        // Ответы страниц меняют карточку патча между проверками диска (раз в минуту).
        if panel.model.patch != patch {
            panel.change {
                panel.model.patch = patch
                if case .installed(_, let loader) = patch { panel.model.loader = loader }
            }
        }
        guard panel.isOpen else { return }
        let model = panel.model
        if model.limits != signals.limits { model.limits = signals.limits }
    }

    /// Сводка проектов для значка (вид «Проекты»): раз в 30 с, пока панель закрыта (открытую ведёт `PanelFeed`).
    private func refreshIconProjects(force: Bool = false) {
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

    private func refreshState() {
        guard !busy else { return }
        guard let url = chosenClaude(askIfSeveral: false) else { show(state: .claudeNotFound); return }
        DispatchQueue.global(qos: .utility).async {
            let state = ClaudePatcher(appURL: url).state()
            DispatchQueue.main.async { self.show(state: state) }
        }
    }

    private func show(state: ClaudeState) {
        stateText = state.menuTitle
        lastState = state
        refreshIcon()
        let patch = patchLook
        if panel.model.patch != patch {
            panel.change {
                panel.model.patch = patch
                if case .installed(_, let loader) = patch { panel.model.loader = loader }
            }
        }
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
        alert.informativeText = """
            Claude закроется и через несколько секунд откроется снова.
            Оригинальные app.asar и Info.plist уйдут в бэкап — «Снять патч» (панель у часов → «Ещё») вернёт их.
            После первой установки macOS один раз заново спросит разрешения (микрофон, экран).

            \(url.path)
            """
        alert.addButton(withTitle: "Пропатчить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        runOperation(title: "Пропатчить Claude", appURL: url) { patcher, progress in
            switch try patcher.install(progress: progress) {
            case .alreadyInstalled(let version): return "Патч уже стоял — Claude \(version) не трогали."
            case .repaired(let version): return "Починил: хэш и подпись Claude \(version) снова сходятся."
            case .installed(let version): return "Готово. Патч стоит в Claude \(version)."
            }
        }
    }

    @objc private func uninstall() {
        panel.close()
        guard !busy, let url = askForClaude() else { return }
        let alert = NSAlert()
        alert.messageText = "Снять патч?"
        alert.informativeText = """
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

    // ---------------------------------------------------------------- обновление Claude (#7078, #7079, WF86)

    /// Единая точка после КАЖДОГО изменения `claudeUpdate` (контракт A): значок, блок панели,
    /// «самое время». Снимки гонки идут 4 раза в секунду — тяжёлое (окна Claude) только на готовом.
    private func showClaudeUpdate() {
        let now = Date()
        if case .ready(let version) = claudeUpdate.phase {
            if readySince?.version != version { readySince = (version, now) }
        } else {
            readySince = nil
            offering = nil
        }
        if case .ready = claudeUpdate.phase { evaluateOffer(now: now, refresh: false) }
        refreshIcon()
        refreshUpdateBlock(now: now)
    }

    /// Блок обновления в панели.
    private func refreshUpdateBlock(now: Date = Date()) {
        let model = panel.model
        if case .downloading(let race) = claudeUpdate.phase {
            if model.raceStartedAt == nil { model.raceStartedAt = now }
            model.lanes.note(race, at: now)
        } else if model.raceStartedAt != nil {
            model.raceStartedAt = nil
            model.lanes.reset()
        }
        model.readySize = readyClaude.flatMap { ready in
            ready.prepared.release.size > 0 ? "\(ready.prepared.release.size / 1_000_000) МБ" : nil
        }
        var extras = updateExtras
        if extras.question == nil, let version = offering, case .ready(version) = claudeUpdate.phase,
           let target = claudeUpdateTarget() {
            let presence = claudePresence(ClaudeUpdater(appURL: target))
            extras.offerReason = PimpPanelText.offerReason(claudeRunning: presence.running,
                                                           windowCount: presence.windows,
                                                           idleSeconds: ax.pageSignals.idleSeconds(at: now))
        }
        let block = PimpPanelText.updateBlock(claudeUpdate, extras)
        // Отказанную версию (второй замок, G2 WF101) не предлагаем «Скачать» каждый день.
        var refused: String?
        if case .available(let version, _, _) = block, let release = foundRelease, release.version == version,
           let target = claudeUpdateTarget(), ClaudeUpdater(appURL: target).refusedReason(for: release) != nil {
            refused = version
        }
        if model.refusedVersion != refused { model.refusedVersion = refused }
        if model.update != block {
            // Появился или ушёл блок, сменилась стадия — пружиной settings; снимки гонки — без неё.
            let sameKind: Bool
            switch (model.update, block) {
            case (.downloading, .downloading), (.installing, .installing): sameKind = true
            default: sameKind = false
            }
            if sameKind || !panel.isOpen { model.update = block } else { panel.change { model.update = block } }
        }
    }

    /// «Самое время» (10-choice §3.3, провязка `shouldOffer`): готово, Claude не запущен, окон нет
    /// или ≥ 2 мин никто не работает, не предлагали 3 ч и не «Позже». Предложение держится, пока
    /// условия верны (иначе «Обновить сейчас» без вопроса закрыло бы работающий чат); уведомление
    /// «Скачалось» — одно на версию, в первый такой момент или через сутки после готовности.
    private func evaluateOffer(now: Date = Date(), refresh: Bool = true) {
        guard case .ready(let version) = claudeUpdate.phase, !busy, let target = claudeUpdateTarget() else { return }
        let defaults = UserDefaults.standard
        let presence = claudePresence(ClaudeUpdater(appURL: target))
        let signals = ax.pageSignals
        func offer(lastOfferAt: Date?, snoozeUntil: Date?) -> Bool {
            ClaudeUpdateMenu.shouldOffer(ready: true, claudeRunning: presence.running, windowCount: presence.windows,
                                         anyPageWorking: signals.anyPageWorking,
                                         idleSeconds: signals.idleSeconds(at: now),
                                         lastOfferAt: lastOfferAt, snoozeUntil: snoozeUntil, now: now)
        }
        let before = offering
        if offering == version {
            if !offer(lastOfferAt: nil, snoozeUntil: nil) { offering = nil }
        } else if offer(lastOfferAt: defaults.object(forKey: Key.lastOfferAt) as? Date,
                        snoozeUntil: defaults.object(forKey: Key.snoozeUntil) as? Date) {
            offering = version
            defaults.set(now, forKey: Key.lastOfferAt)
        }
        let notified = defaults.string(forKey: ClaudeUpdateMenu.notifiedKey)
        if PimpPanelText.shouldNotifyReady(version: version, notified: notified, offer: offering == version,
                                           readySince: readySince?.version == version ? readySince?.at : nil,
                                           now: now) {
            Notifier.postClaudeReady(version: version) { sent in
                if sent { defaults.set(version, forKey: ClaudeUpdateMenu.notifiedKey) }
            }
        }
        if refresh, before != offering { refreshUpdateBlock(now: now) }
    }

    /// Какую копию обновлять: пропатченную (`installed.json`), иначе выбранную, иначе в /Applications.
    /// Копию в «_Не удалять» и прочие фон не трогает (критик WF87 п. 1).
    private func claudeUpdateTarget() -> URL? {
        ClaudeUpdater.targetClaude(installedAppPath: ClaudeUpdater.installedAppPath(),
                                   savedPath: UserDefaults.standard.string(forKey: Key.claudePath),
                                   copies: Patcher.locateClaude())
    }

    private func saveNextDaily() {
        UserDefaults.standard.set(claudeUpdate.nextDailyAt, forKey: ClaudeUpdateMenu.nextDailyKey)
    }

    @objc private func checkClaudeUpdateAfterWake() { checkClaudeUpdate(trigger: .daily) }

    /// Мак засыпает — гонку отменяем сами: после сна судья счёл бы все полосы «завис», перезапустил
    /// их без сети и ушёл бы на часовую паузу. Отмена паузы не даёт; продолжит таймер или сеть.
    @objc private func claudeDownloadBeforeSleep() { claudeDownload?.cancel() }

    private func resumeClaudeDownload() {
        guard foundRelease != nil, claudeDownload == nil, let url = claudeUpdateTarget() else { return }
        startClaudeDownloadIfWanted(url: url)
    }

    /// Готовое с прошлого запуска (`ready.json`, подпись и Gatekeeper заново). Потом — `next`.
    private func restoreReadyClaude(then next: @escaping () -> Void = {}) {
        guard let url = claudeUpdateTarget() else { next(); return }
        readyRechecks += 1
        DispatchQueue.global(qos: .utility).async {
            let ready = ClaudeUpdater(appURL: url).loadReady()
            DispatchQueue.main.async {
                self.readyRechecks -= 1
                self.setReadyClaude(ready, url: url)
                next()
            }
        }
    }

    private func setReadyClaude(_ ready: PreparedClaudeUpdate?, url: URL) {
        readyClaude = ready.map { (url, $0) }
        claudeUpdate.restoreReady(version: ready?.release.version)
        showClaudeUpdate()
    }

    /// Только метаданные; ручная и фоновая проверки идут через один gate (`beginCheck`).
    private func checkClaudeUpdate(trigger: ClaudeUpdateMenu.Trigger = .menu) {
        defer { showClaudeUpdate() }
        guard !busy, let url = claudeUpdateTarget(),
              claudeUpdate.beginCheck(at: Date(), trigger: trigger, busy: busy) else { return }
        saveNextDaily()
        let generation = updateSourceGeneration
        let updater = ClaudeUpdater(appURL: url, allowMirrors: true)
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try updater.check() }
            DispatchQueue.main.async {
                guard generation == self.updateSourceGeneration else { return }
                self.claudeCheckFinished(result, url: url)
            }
        }
    }

    private func claudeCheckFinished(_ result: Result<ClaudeFeedAnswer, Error>, url: URL) {
        // Другой пункт меню мог заменить/выбрать Claude, пока сеть отвечала.
        guard !busy, claudeUpdateTarget() == url else {
            claudeUpdate.forget()
            showClaudeUpdate()
            return
        }
        switch result {
        case .success(.latest(let installed, _)):
            claudeUpdate.finish(.latest(installed: installed), at: Date())
        case .success(.available(_, let release)):
            foundRelease = release
            claudeUpdate.finish(.available(version: release.version), at: Date())
        case .failure(let error):
            claudeUpdate.finish(.failed(Self.describe(error)), at: Date())
        }
        saveNextDaily()
        // Права на папку Claude — на каждой проверке: иначе «нет прав» держалось бы до перезапуска Пимпа.
        if let release = foundRelease, case .available = claudeUpdate.known {
            if case .notWritable = ClaudeUpdater(appURL: url).preflight(release) {
                claudeUpdate.canWrite = false
            } else {
                claudeUpdate.canWrite = true
            }
        }
        showClaudeUpdate()
        recheckReadyClaude(url: url)
    }

    /// Стоящая версия могла смениться (Claude поставили руками) — готовое перепроверяем быстро, но
    /// только когда ничего не качается и не ставится: `loadReady` при несовпадении сносит распаковку,
    /// а `install` в это время двигает бандлы (гейт 1 WF87, A5). Пока идёт — «Обновить» ждёт.
    private func recheckReadyClaude(url: URL) {
        switch claudeUpdate.phase {
        case .downloading, .installing: return
        default: break
        }
        guard !busy, readyRechecks == 0, claudeDownload == nil else { return }
        readyRechecks += 1
        DispatchQueue.global(qos: .utility).async {
            let ready = ClaudeUpdater(appURL: url).loadReady(verifySignature: false)
            DispatchQueue.main.async {
                self.readyRechecks -= 1
                guard !self.busy, self.claudeUpdateTarget() == url else { return }
                self.readyClaude = ready.map { (url, $0) }
                self.claudeUpdate.restoreReady(version: ready?.release.version)
                self.showClaudeUpdate()
                self.startClaudeDownloadIfWanted(url: url)
            }
        }
    }

    /// Найдено новее — скачать и подготовить в фоне (с WF126 всегда, выключателя нет): сеть не дорогая,
    /// в папку Claude писать можно, места хватает (критик WF87 п. 9).
    /// `force` — кнопка «Скачать» в панели: мимо часовой паузы и дорогой сети.
    private func startClaudeDownloadIfWanted(url: URL, force: Bool = false) {
        guard !busy, readyRechecks == 0, claudeDownload == nil, force || !costlyNetwork, networkUp,
              let release = foundRelease else { return }
        if force {
            guard case .available(release.version) = claudeUpdate.phase else { return }
        } else {
            guard claudeUpdate.wantsDownload(autoDownload: true, at: Date()) == release.version else { return }
        }
        var updater = ClaudeUpdater(appURL: url, allowMirrors: true)
        updater.raceRules.deadline = ClaudeUpdater.backgroundDeadline
        switch updater.preflight(release) {
        case .ok:
            claudeUpdate.canWrite = true
        case .notWritable:
            claudeUpdate.canWrite = false
            showClaudeUpdate()
            return
        case .noSpace(let needed, let free):
            claudeUpdate.downloadFailed(PimpPanelText.noSpaceText(needed: needed, free: free), at: Date())
            showClaudeUpdate()
            return
        }
        let version = release.version
        claudeUpdate.startDownload(version: version)
        let control = DownloadControl { [weak self] snapshot in
            guard let self = self else { return }
            self.claudeUpdate.progress(Self.race(version, snapshot))
            self.showClaudeUpdate()
        }
        claudeDownload = control
        let generation = updateSourceGeneration
        showClaudeUpdate()
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try updater.prepare(release, control: control) }
            DispatchQueue.main.async {
                self.claudeDownload = nil
                guard generation == self.updateSourceGeneration else {
                    self.claudeUpdate.downloadCancelled()
                    self.showClaudeUpdate()
                    self.checkClaudeUpdate(trigger: .manual)
                    return
                }
                switch result {
                case .success(let prepared):
                    self.readyClaude = (url, prepared)
                    self.claudeUpdate.downloaded(version: prepared.release.version)
                    self.showClaudeUpdate()
                case .failure(ClaudeUpdateError.cancelled):
                    // Сон или дорогая сеть — не неудача: без часовой паузы, продолжит таймер или сеть.
                    self.claudeUpdate.downloadCancelled()
                    self.restoreReadyClaude()
                case .failure(let error):
                    self.claudeUpdate.downloadFailed(Self.describe(error), at: Date())
                    self.restoreReadyClaude() // прежнее готовое могло уцелеть
                }
            }
        }
    }

    /// Дорогая или ограниченная сеть — фоновая загрузка не идёт, начатая отменяется; сеть снова
    /// обычная — продолжаем сразу, не ждём проверки (гейт 1 WF87, A1).
    private func networkChanged(costly: Bool, up: Bool) {
        costlyNetwork = costly
        networkUp = up
        if costly, let download = claudeDownload { download.cancel() }
        if !costly, up { resumeClaudeDownload() }
    }

    private static func race(_ version: String, _ snapshot: RaceSnapshot) -> ClaudeUpdateMenu.Race {
        ClaudeUpdateMenu.Race(version: version, lanes: snapshot.lanes.map { lane in
            let state: ClaudeUpdateMenu.LaneState
            switch lane.state {
            case .running: state = .running
            case .leading: state = .leading
            case .dropped(let why): state = .dropped(why)
            case .failed(let why): state = .failed(why)
            case .won: state = .won
            }
            return ClaudeUpdateMenu.Lane(id: lane.id, title: lane.title, bytes: lane.bytes, total: lane.total,
                                         bytesPerSec: lane.bytesPerSec, state: state)
        })
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Кнопка уведомления «Обновить»: панель у значка и то же, что кнопка блока (вопрос — в панели).
    @objc private func updateClaude() {
        openPanel()
        pressUpdate()
    }

    /// «Обновить Claude» / «Обновить сейчас» в блоке: готово — одно нажатие; спрашиваем прямо в блоке,
    /// только если у этой копии есть окна и свежий ответ страниц не сказал, что никто не работает.
    /// Найдено, но не скачано — «Скачать».
    private func pressUpdate() {
        guard !busy, claudeDownload == nil, readyRechecks == 0, !askingPages else { return }
        guard let url = claudeUpdateTarget() else { report(PatchError.claudeNotFound); return }
        if case .available = claudeUpdate.phase {
            startClaudeDownloadIfWanted(url: url, force: true)
            return
        }
        guard let ready = readyClaude, ready.url == url, case .ready = claudeUpdate.phase else { return }
        let presence = claudePresence(ClaudeUpdater(appURL: url))
        guard presence.running, presence.windows > 0 else {
            installClaude(ready.prepared, url: url)
            return
        }
        // Признак «работает» из минутного круга бывает трёхминутной давности (гейт 2 WF87): спрашиваем
        // страницы сейчас и решаем только по ответу, пришедшему после нажатия.
        askingPages = true
        let since = Date()
        ax.refreshPageSignals()
        waitForPages(since: since, url: url)
    }

    /// Ждём круг страниц после нажатия (до `pagesWaitSeconds`); не дождались — «не знаем» и вопрос.
    private func waitForPages(since: Date, url: URL) {
        let signals = ax.pageSignals.answered(after: since)
        if signals.workingChats == nil, Date().timeIntervalSince(since) < Self.pagesWaitSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.waitForPages(since: since, url: url)
            }
            return
        }
        askingPages = false
        guard !busy, claudeDownload == nil, readyRechecks == 0, claudeUpdateTarget() == url,
              let ready = readyClaude, ready.url == url, case .ready = claudeUpdate.phase else {
            refreshUpdateBlock()
            return
        }
        let presence = claudePresence(ClaudeUpdater(appURL: url))
        if ClaudeUpdateMenu.needsConfirm(claudeRunning: presence.running, windowCount: presence.windows,
                                         anyPageWorking: signals.anyPageWorking) {
            openPanel() // панель закрыли, пока ждали, — вопрос должен быть виден
            updateExtras.question = PimpPanelText.confirmQuestion(workingChats: signals.workingChats)
            refreshUpdateBlock()
            return
        }
        installClaude(ready.prepared, url: url)
    }

    /// «Обновить всё равно» — ответ на вопрос, без повторного вопроса.
    private func updateWithoutAsking() {
        updateExtras.question = nil
        guard !busy, claudeDownload == nil, readyRechecks == 0, let url = claudeUpdateTarget(),
              let ready = readyClaude, ready.url == url, case .ready = claudeUpdate.phase else {
            refreshUpdateBlock()
            return
        }
        installClaude(ready.prepared, url: url)
    }

    /// «Позже»: не предлагать 3 ч, блок на 2,5 с говорит «напомню через 3 часа».
    private func updateLater() {
        let now = Date()
        UserDefaults.standard.set(now.addingTimeInterval(Self.snoozeSeconds), forKey: Key.snoozeUntil)
        offering = nil
        showTransient(\.snoozedShown, seconds: 2.5)
    }

    /// Временное состояние блока («Позже», «готово») — снимается само, если его не перебили.
    private func showTransient(_ flag: WritableKeyPath<PimpPanelText.UpdateExtras, Bool>, seconds: TimeInterval) {
        extrasGeneration += 1
        let generation = extrasGeneration
        updateExtras[keyPath: flag] = true
        refreshUpdateBlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self, generation == self.extrasGeneration else { return }
            self.updateExtras[keyPath: flag] = false
            self.refreshUpdateBlock()
        }
    }

    /// Порядок (критик WF84 Б5, WF87 п. 2, 10): вопрос уже задан в панели → снимок окон (К5) →
    /// заморозка снимка → подмена и патч → запуск. Шаги — в блоке панели по строкам журнала.
    /// Окна вернёт автовозврат: заморозка тает, когда появится Claude, запущенный после неё.
    /// Сорвалось — `ClaudeUpdater` возвращает прежний, причина — в блоке.
    private func installClaude(_ prepared: PreparedClaudeUpdate, url: URL) {
        let updater = ClaudeUpdater(appURL: url)
        guard claudeUpdate.startInstall() else { return }
        busy = true
        offering = nil
        updateExtras = PimpPanelText.UpdateExtras()
        extrasGeneration += 1
        showClaudeUpdate()
        // Снимок окон — до закрытия Claude (К5), и заморозка: без неё окна другой копии перепишут его.
        _ = ax.saveWindowSnapshot()
        ax.freezeWindowSnapshot(true)
        let pidsBefore = updater.runningPIDs()
        let post: (String) -> Void = { line in
            DispatchQueue.main.async {
                let step = PimpPanelText.installStep(line, current: self.updateExtras.installStep)
                guard step != self.updateExtras.installStep else { return }
                self.updateExtras.installStep = step
                self.refreshUpdateBlock()
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outcome = try updater.install(prepared, relaunch: true, progress: post)
                DispatchQueue.main.async {
                    self.readyClaude = nil
                    self.claudeUpdate.installFinished()
                    self.updateExtras = PimpPanelText.UpdateExtras(doneVersion: outcome.to)
                    self.claudeUpdateFinished()
                    // «✓ стоит, патч на месте» — 10 с, потом блок сворачивается.
                    self.extrasGeneration += 1
                    let generation = self.extrasGeneration
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        guard generation == self.extrasGeneration else { return }
                        self.updateExtras.doneVersion = nil
                        self.refreshUpdateBlock()
                    }
                }
            } catch {
                let untouched = !pidsBefore.isEmpty && updater.runningPIDs() == pidsBefore
                DispatchQueue.main.async {
                    // Claude не закрывался — снимок ведётся дальше; закрывался — заморозка растает с запуском.
                    if untouched { self.ax.freezeWindowSnapshot(false) }
                    self.claudeUpdate.installFailed(Self.describe(error))
                    self.updateExtras = PimpPanelText.UpdateExtras(installFailure: Self.describe(error))
                    self.claudeUpdateFinished()
                    self.restoreReadyClaude()
                    self.openPanel()
                }
            }
        }
    }

    /// `pimp.py restart-claude` (WF108, #8176): путь «Обновить Claude» без подмены бандла — снимок
    /// окон (К5) и заморозка, как в `installClaude`, потом `ClaudeUpdater.restartClaude` (те же выход
    /// и запуск) той же копии. Окна вернёт автовозврат снимка. Claude не закрывался — снимок оттаивает.
    private func wireRestartClaude() {
        ax.restartClaude = { [weak self] running, done in
            guard let self = self else { return done("Пимп закрывается") }
            guard !self.busy else { return done("Пимп занят: обновляет или патчит Claude") }
            guard let url = running ?? self.claudeUpdateTarget() else { return done("Не нашёл Claude.app") }
            let updater = ClaudeUpdater(appURL: url)
            // Пока Claude закрывается и открывается, «Обновить/Пропатчить Claude» панели ждут (гейт 2 WF108).
            self.busy = true
            self.refreshUpdateBlock()
            _ = self.ax.saveWindowSnapshot()
            self.ax.freezeWindowSnapshot(true)
            let pidsBefore = updater.runningPIDs()
            DispatchQueue.global(qos: .userInitiated).async {
                var failure: String?
                do { try updater.restartClaude() } catch { failure = Self.describe(error) }
                let untouched = failure != nil && !pidsBefore.isEmpty && updater.runningPIDs() == pidsBefore
                DispatchQueue.main.async {
                    if untouched { self.ax.freezeWindowSnapshot(false) }
                    self.busy = false
                    self.refreshUpdateBlock()
                    done(failure)
                }
            }
        }
    }

    /// Запущена ли ИМЕННО эта копия (по bundleURL) и сколько у неё обычных окон, включая свёрнутые.
    private func claudePresence(_ updater: ClaudeUpdater) -> (running: Bool, windows: Int) {
        let pids = Set(updater.runningPIDs())
        guard !pids.isEmpty else { return (false, 0) }
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows = list.filter { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (bounds["Width"] ?? 0) >= 200 && (bounds["Height"] ?? 0) >= 200
        }.count
        return (true, windows)
    }

    private func claudeUpdateFinished() {
        operationFinished()
        showClaudeUpdate()
    }

    // ---------------------------------------------------------------- обновление самого Пимпа и Viewer (WF217, К-SU)

    /// Когда нельзя подменять: открыта панель, идёт патч, обновление Claude или его загрузка, пишет Диктатор;
    /// Viewer — пока запущен; Пимп — пока занят канал «Пимп» или окна Claude не вернулись. Сеть — та же мерка, что у фоновой загрузки Claude: есть и не дорогая.
    private func wireSelfUpdate() {
        selfUpdate.moment = { [weak self] in
            guard let self = self else { return SelfUpdateMoment(busy: true) }
            return SelfUpdateMoment(
                panelOpen: self.panel.isOpen,
                busy: self.busy || self.claudeDownload != nil || self.readyRechecks > 0,
                recording: self.ax.isDictating,
                viewerRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: SelfUpdateProduct.viewer.bundleID).isEmpty,
                windows: self.ax.isSettlingWindows)
        }
        selfUpdate.networkOK = { [weak self] in self.map { $0.networkUp && !$0.costlyNetwork } ?? false }
        selfUpdate.onChange = { [weak self] in
            guard let self = self, self.panel.isOpen else { return }
            // Строку «обновился» панель берёт только на открытии — посреди открытой панели она не появляется.
            var look = self.selfUpdate.look()
            look.note = self.panel.model.selfUpdate.note
            if self.panel.model.selfUpdate != look { self.panel.model.selfUpdate = look }
        }
        selfUpdate.started()
    }

    /// Claude только что запустился — тихий момент для установки; Viewer закрыли — его обновление встаёт.
    @objc private func appLaunchedOrQuit(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if notification.name == NSWorkspace.didLaunchApplicationNotification {
            if app?.bundleIdentifier == Patcher.claudeBundleID { selfUpdate.claudeLaunched() }
        } else if app?.bundleIdentifier == SelfUpdateProduct.viewer.bundleID {
            selfUpdate.viewerQuit()
        }
    }

    // ---------------------------------------------------------------- панель у часов (WF87)

    private func wirePanel() {
        let model = panel.model
        let info = Bundle.main.infoDictionary ?? [:]
        model.appVersion = info["CFBundleShortVersionString"] as? String ?? "—"
        feed.onAccent = { [weak self] in self?.refreshIcon() }
        panel.onOpen = { [weak self] in
            guard let self = self else { return }
            self.panel.model.limits = self.ax.pageSignals.limits
            self.panel.model.patch = self.patchLook
            self.panel.model.archiving = self.ax.archiveBusy
            // «Поставить Рика» (WF216): строка видна, только пока папки Rick нет; идущее и готовое не сбрасываем.
            switch self.panel.model.rick {
            case .running, .done: break
            case .hidden, .idle, .failed: self.panel.model.rick = RickKit.isPresent ? .hidden : .idle
            }
            self.panel.model.sendDelay = self.ax.sendDelaySetting
            self.panel.model.sendDelayLine = nil
            self.panel.model.pinnedLook = self.ax.pinnedLook
            self.panel.model.enterKeys = self.ax.enterKeys
            self.panel.model.countdownSound = self.ax.countdownSound
            self.panel.model.sendLookStyle = self.ax.sendLookStyle
            self.panel.model.bypassNew = self.ax.bypassNewChats
            self.panel.model.textJustify = self.ax.textJustify
            self.panel.model.cleanAnswers = self.ax.cleanAnswers
            self.panel.model.sidePadding = TextLook.sidePadding
            self.panel.model.bypassPermission = self.ax.bypassPermission
            self.panel.model.claudeSettingsFailed = false
            self.panel.model.memory = self.memory.watch(true)
            self.feed.opened()
            self.updateExtras.question = nil // вопрос про прошлое нажатие — к этому открытию не относится
            self.updateToggleMarks()
            self.refreshDonateRow()
            self.refreshUpdateBlock()
            self.refreshState()
            self.checkClaudeUpdate()
            self.panel.model.selfUpdate = self.selfUpdate.look()
        }
        panel.onClose = { [weak self] in
            guard let self = self else { return }
            self.memory.watch(false)
            self.feed.closed()
            // «Пимп обновился до …» показана один раз — на этом открытии.
            if self.panel.model.selfUpdate.note != nil {
                self.panel.model.selfUpdate.note = nil
                self.selfUpdate.clearNotes()
            }
            guard self.updateExtras.question != nil else { return }
            self.updateExtras.question = nil
            self.refreshUpdateBlock()
        }
        ax.onArchiveDone = { [weak self] in self?.panel.model.archiving = false }
        // «Показать» не нашёл окна и после повторов (WF180): панель уже закрылась — открыть её на «Задержке» с причиной.
        ax.onSendDelayPreviewFailed = { [weak self] reason in
            guard let self = self else { return }
            if !self.panel.isOpen {
                self.openPanel()
                self.panel.showSheet(.settings)
            }
            self.panel.change { self.panel.model.settingsGroup = .enter }
            self.panel.model.sendDelayLine = reason
        }
        // Кнопка «PMP» в окне Claude (#8894). Панель открыта — её уже закрывает сам клик мимо неё (нажатие
        // кнопки и есть такой клик), а запрос приходит следом: только что закрытую не открываем — не моргает.
        ax.onPanelRequest = { [weak self] in
            guard let self = self, !self.panel.closedJustNow else { return }
            self.openPanel()
        }
        model.actions = PanelActions(
            patch: { [weak self] in self?.patchFromPanel() },
            findClaude: { [weak self] in self?.findClaude() },
            patchLog: { [weak self] in self?.showPatchLog() },
            download: { [weak self] in self?.pressUpdate() },
            update: { [weak self] in self?.pressUpdate() },
            updateAnyway: { [weak self] in self?.updateWithoutAsking() },
            wait: { [weak self] in
                self?.updateExtras.question = nil
                self?.refreshUpdateBlock()
            },
            updateNow: { [weak self] in self?.pressUpdate() },
            later: { [weak self] in self?.updateLater() },
            cancelRace: { [weak self] in self?.claudeDownload?.cancel() },
            retryUpdate: { [weak self] in
                self?.updateExtras.installFailure = nil
                self?.refreshUpdateBlock()
                self?.pressUpdate()
            },
            toggle: { [weak self] id in self?.pressToggle(id) },
            sendDelay: { [weak self] on, seconds in
                guard let self = self else { return }
                self.ax.setSendDelay(on: on, seconds: seconds)
                self.panel.model.sendDelay = self.ax.sendDelaySetting
                self.panel.model.sendDelayLine = nil
            },
            previewSendDelay: { [weak self] seconds in
                guard let self = self else { return }
                if let reason = self.ax.previewSendDelay(seconds: seconds) { self.panel.model.sendDelayLine = reason }
                else { self.panel.close() }
            },
            pinnedLook: { [weak self] look in
                guard let self = self else { return }
                self.ax.pinnedLook = look
                self.panel.model.pinnedLook = self.ax.pinnedLook
            },
            archiveChats: { [weak self] in
                guard let self = self else { return }
                self.ax.archiveChats()
                self.panel.model.archiving = self.ax.archiveBusy
            },
            showViewer: { [weak self] in self?.ax.showViewer() },
            installRick: { [weak self] in self?.installRick() },
            revealRick: { NSWorkspace.shared.activateFileViewerSelecting([RickKit.folder]) },
            setup: { [weak self] in self?.showSetup() },
            donate: { [weak self] in
                self?.panel.close()
                self?.donate.show()
            },
            toggleDonate: { [weak self] in
                let defaults = UserDefaults.standard
                defaults.set(!defaults.bool(forKey: Donate.hiddenKey), forKey: Donate.hiddenKey)
                self?.panel.change { self?.refreshDonateRow() }
            },
            about: { [weak self] in self?.showAbout() },
            uninstall: { [weak self] in self?.uninstall() },
            quit: { NSApp.terminate(nil) },
            windowColor: { [weak self] choice in self?.feed.chooseWindowColor(choice) },
            previewWindowColor: { [weak self] choice in self?.feed.previewWindowColor(choice) },
            live: { [weak self] on in self?.feed.setLive(on) },
            setAccent: { [weak self] accent in self?.feed.setAccent(accent) },
            escape: { [weak self] in self?.feed.escape() ?? false },
            enterKeys: { [weak self] keys in
                guard let self = self else { return }
                let was = self.panel.model.enterKeys
                self.ax.setEnterKeys(second: keys.second != was.second ? keys.second : nil,
                                     shift: keys.shift != was.shift ? keys.shift : nil)
                self.panel.model.enterKeys = keys
            },
            countdownSound: { [weak self] sound in
                guard let self = self else { return }
                self.ax.setCountdownSound(sound)
                self.panel.model.countdownSound = sound
            },
            sendLookStyle: { [weak self] style in
                guard let self = self else { return }
                self.ax.setSendLookStyle(style)
                self.panel.model.sendLookStyle = self.ax.sendLookStyle
            },
            bypassNew: { [weak self] on in
                guard let self = self else { return }
                self.ax.bypassNewChats = on
                self.panel.model.bypassNew = on
                self.panel.model.bypassPermission = self.ax.bypassPermission
            },
            openClaudeSettings: { [weak self] in
                guard let self = self else { return }
                if self.ax.openClaudeSettings() { self.panel.close() } else { self.panel.model.claudeSettingsFailed = true }
            },
            iconVariant: { [weak self] variant in
                guard let self = self else { return }
                StatusIcon.saveVariant(variant)
                self.panel.change { self.panel.model.iconVariant = variant }
                self.refreshIcon()
                if variant.showsProjects { self.refreshIconProjects(force: true) }
            })
        // Блок «Текст» (WF167, #9168): по ширине/влево — команда страницам; поля — claude.json, как «↔️ Поля» на «−».
        model.actions.textJustify = { [weak self] on in
            guard let self = self else { return }
            self.ax.textJustify = on
            self.panel.model.textJustify = on
        }
        // «Чистые ответы» (WF210, #9398, К-CA): команда `clean-answers` всем страницам.
        model.actions.cleanAnswers = { [weak self] on in
            guard let self = self else { return }
            self.ax.cleanAnswers = on
            self.panel.model.cleanAnswers = on
        }
        model.actions.sidePadding = { [weak self] value in
            self?.panel.model.sidePadding = TextLook.setSidePadding(value)
        }
        model.actions.selfUpdate = { [weak self] on in self?.selfUpdate.setEnabled(on) }
    }

    /// Строка «Поддержать автора»: donate.json перечитан по mtime при каждом открытии панели.
    private func refreshDonateRow() {
        let model = panel.model
        model.donateAvailable = Donate.windowAvailable(donate.config())
        model.donateShown = !UserDefaults.standard.bool(forKey: Donate.hiddenKey)
    }

    /// Возврат платёжки `pimpmyclaude://donate/thanks|cancel` (WF108): «Спасибо!» или «Отменено» в окне.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let answer = Donate.parseReturn(url) { donate.handleReturn(answer) }
        }
    }

    /// Панель у значка (кнопка уведомления, сбой установки, кнопка PMP в окне Claude). Уже открыта — ничего.
    private func openPanel() {
        guard !panel.isOpen, let button = statusItem?.button else { return }
        panel.open(from: button)
    }

    /// «Пропатчить Claude» / «Вернуть патч» — без вопроса (кнопка и есть согласие): шаг — в
    /// кнопке, ошибка — под ней, «Подробнее…» — прежнее окно журнала. Встал — панель пружиной
    /// распрямляется в «всё хорошо» (`show(state:)`).
    private func patchFromPanel() {
        guard !busy, let url = askForClaude() else { return }
        busy = true
        refreshUpdateBlock()
        patchLog = []
        patchSettings = nil
        let loader = panel.model.loader
        panel.change { panel.model.patchRun = .running("Закрываю Claude…") }
        let patcher = ClaudePatcher(appURL: url)
        let post: (String) -> Void = { line in
            DispatchQueue.main.async {
                self.patchLog.append(line)
                if let step = PimpPanelText.patchStep(line, loader: loader) {
                    self.panel.model.patchRun = .running(step)
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try patcher.install(progress: post)
                DispatchQueue.main.async {
                    self.panel.model.patchRun = .idle
                    self.operationFinished()
                }
            } catch {
                let message = Self.describe(error)
                let settings = Self.settingsAction(for: error)
                DispatchQueue.main.async {
                    self.patchLog.append("Не вышло. " + message)
                    self.patchSettings = settings
                    self.panel.change { self.panel.model.patchRun = .failed(message) }
                    self.operationFinished()
                    self.openPanel() // панель закрылась, пока шёл патч, — ошибка иначе не видна
                }
            }
        }
    }

    /// «Подробнее…» под ошибкой патча — прежнее окно журнала.
    private func showPatchLog() {
        panel.close()
        let window = OperationWindow(title: "Пропатчить Claude")
        window.show()
        patchLog.dropLast().forEach { window.append($0) }
        window.finish(patchLog.last ?? "", settings: patchSettings)
    }

    /// «Найти Claude…»: Claude лежит не там, где его видит Launch Services, — покажи сам.
    private func findClaude() {
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
    private func installRick() {
        guard panel.model.rick != .running else { return }
        panel.change { panel.model.rick = .running }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = RickKit.install(configDefaults: Patcher.configDefaults)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.panel.change { self.panel.model.rick = RickInstall(outcome) }
            }
        }
    }

    /// Пошаговое окно разрешений: первый запуск и пункт меню. Второй раз не плодим — поднимаем открытое.
    @objc private func showSetup() {
        panel.close()
        if let setup = setup {
            setup.show()
            return
        }
        let window = SetupWindow(
            rickFolder: rickFolder,
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

    @objc private func showAbout() {
        panel.close()
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let alert = NSAlert()
        alert.messageText = "PimpMyClaude \(version) (\(build))"
        alert.informativeText = """
            Прокачка Claude Desktop: узкие окна и поля, ручка над полем ввода, меню на кнопке «Свернуть» \
            с горячими клавишами, обратный отсчёт, Авто-Allow и блокировка ⌘Q. Без Hammerspoon и Node.

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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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

    private func askForClaude() -> URL? {
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
            let post: (String) -> Void = { line in DispatchQueue.main.async { window.append(line) } }
            do {
                let done = try body(patcher, post)
                DispatchQueue.main.async {
                    window.finish(done)
                    self.operationFinished()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let settings = Self.settingsAction(for: error)
                DispatchQueue.main.async {
                    window.finish("Не вышло. " + message, settings: settings)
                    self.operationFinished()
                }
            }
        }
    }

    private func operationFinished() {
        busy = false
        refreshUpdateBlock()
        // «Пропатчить Claude» кладёт в claude.css авто-блок из бандла (Patcher.installLiveCSS, WF45 —
        // свои правила человека при этом сохраняются), а блок надо пересчитать под живой
        // sidePadding и версию macOS (план WF14, решение 1).
        ax.refreshLiveStyle()
        refreshState()
    }

    private static func settingsAction(for error: Error) -> (() -> Void)? {
        if case PatchError.needsAppManagement = error { return { SystemSettings.open(SystemSettings.appManagement) } }
        return nil
    }

    private func report(_ error: Error) {
        panel.close()
        let alert = NSAlert()
        alert.messageText = "Не вышло"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // ---------------------------------------------------------------- тумблеры

    private func applySettingsToAX() {
        let defaults = UserDefaults.standard
        ax.autoAllowEnabled = defaults.bool(forKey: Key.autoAllow)
        ax.configureAutoContinue(on: defaults.bool(forKey: AutomationDefaults.continueKey),
                                 preservePageChoice: defaults.bool(forKey: AutomationDefaults.continueMigrationKey))
        ax.minimizeMenuEnabled = defaults.bool(forKey: Key.minimizeMenu)
        ax.blockQuitEnabled = defaults.bool(forKey: Key.blockQuit)
    }

    /// Выключатели панели (сетка по два в ряд): состояние и подсказки — прежние пункты меню.
    private func updateToggleMarks() {
        let defaults = UserDefaults.standard
        // Без Универсального доступа живым остаётся блок ⌘Q (Carbon-хоткеи доверия не просят).
        let trusted = ax.isAccessibilityTrusted || AXIsProcessTrusted()
        let needsAX = "Включи PimpMyClaude в Универсальном доступе: «Разрешения macOS…»"
        let toggles = [
            PanelToggle(id: AutomationDefaults.allowKey, title: "Сам нажимать «Allow once»",
                        on: defaults.bool(forKey: AutomationDefaults.allowKey), needsAccess: false,
                        toolTip: "Сам нажимает «Allow once», кроме удаления, выкладки, денег и паролей. Вопросы человеку и постоянные разрешения — вручную. Режим Claude не меняет."),
            PanelToggle(id: AutomationDefaults.continueKey, title: "Новый чат по блоку передачи",
                        on: defaults.bool(forKey: AutomationDefaults.continueMigrationKey)
                            ? ax.autoContinueReported ?? false : defaults.bool(forKey: AutomationDefaults.continueKey), needsAccess: false,
                        toolTip: "Сам открывает новый чат по блоку передачи, когда ты не печатаешь. Сохранённые настройки страниц сохраняются до явного выбора здесь.",
                        mixed: defaults.bool(forKey: AutomationDefaults.continueMigrationKey) && ax.autoContinueReported == nil),
            // Хоткеи меню живут отдельно от тумблера: он гасит само меню на жёлтой кнопке, клавиши остаются.
            PanelToggle(id: Key.minimizeMenu, title: "Меню на жёлтой кнопке окна", on: defaults.bool(forKey: Key.minimizeMenu),
                        needsAccess: !trusted, toolTip: trusted
                            ? "Меню на жёлтой кнопке окна. Горячие клавиши (⌘⌥↑ ↓ A S D) от него не зависят."
                            : needsAX),
            PanelToggle(id: Key.blockQuit, title: "⌘Q не закрывает Claude", on: defaults.bool(forKey: Key.blockQuit),
                        needsAccess: false,
                        toolTip: "⌘Q не закрывает Claude, пока его окно впереди. Работает и без Accessibility."),
            // Маяк окон доступа (WF91): читает ключ сам раз в секунду — перезапуск не нужен.
            PanelToggle(id: ConsentBeacon.enabledKey, title: "Подсвечивать окна разрешений macOS",
                        on: ConsentBeacon.isEnabled(in: defaults), needsAccess: false,
                        toolTip: PimpPanelText.consentToolTip),
            PanelToggle(id: MacTemperature.enabledKey, title: "Температура в панели",
                        on: defaults.bool(forKey: MacTemperature.enabledKey), needsAccess: false,
                        toolTip: "Градусы чипа раз в минуту и график за 3 часа внизу панели. Выключено — Мак не опрашивается."),
            PanelToggle(id: MacMemory.enabledKey, title: "Память в панели",
                        on: defaults.bool(forKey: MacMemory.enabledKey), needsAccess: false,
                        toolTip: "Нагрузка на память раз в минуту и график за 3 часа, как в «Мониторинге системы». Выключено — Мак не опрашивается."),
            PanelToggle(id: "login", title: "Запускать вместе с Mac", on: SMAppService.mainApp.status == .enabled,
                        needsAccess: false,
                        toolTip: "Автозапуск при входе в систему; включается сам, когда приложение лежит в «Программах»."),
        ]
        if panel.model.toggles != toggles { panel.model.toggles = toggles }
    }

    private func pressToggle(_ id: String) {
        switch id {
        case AutomationDefaults.allowKey: toggleAutoAllow()
        case AutomationDefaults.continueKey:
            let defaults = UserDefaults.standard
            let on = !(defaults.bool(forKey: AutomationDefaults.continueMigrationKey)
                ? ax.autoContinueReported ?? false : defaults.bool(forKey: AutomationDefaults.continueKey))
            UserDefaults.standard.set(on, forKey: AutomationDefaults.continueKey)
            UserDefaults.standard.set(false, forKey: AutomationDefaults.continueMigrationKey)
            applySettingsToAX()
            updateToggleMarks()
        case Key.minimizeMenu:
            if panel.model.toggles.first(where: { $0.id == id })?.needsAccess == true { showSetup() } else { toggleMinimizeMenu() }
        case Key.blockQuit: toggleBlockQuit()
        case "login": toggleLoginItem()
        case MacTemperature.enabledKey:
            _ = flip(MacTemperature.enabledKey)
            applyTemperatureSetting()
        case MacMemory.enabledKey:
            _ = flip(MacMemory.enabledKey)
            applyMemorySetting()
        case ConsentBeacon.enabledKey:
            UserDefaults.standard.set(!ConsentBeacon.isEnabled(in: .standard), forKey: ConsentBeacon.enabledKey)
            updateToggleMarks()
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

    private func toggleMinimizeMenu() {
        if flip(Key.minimizeMenu) { warnIfNoAccessibility("Меню на кнопке «Свернуть»") }
    }

    private func toggleBlockQuit() { _ = flip(Key.blockQuit) }

    private func warnIfNoAccessibility(_ feature: String) {
        guard !AXIsProcessTrusted() else { return }
        panel.close()
        let alert = NSAlert()
        alert.messageText = "Нужен Универсальный доступ"
        alert.informativeText = "\(feature) работает через Универсальный доступ (Accessibility). "
            + "Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → включи PimpMyClaude."
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
