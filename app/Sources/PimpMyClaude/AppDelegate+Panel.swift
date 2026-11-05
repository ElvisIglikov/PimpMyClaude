import AppKit
import ApplicationServices
import ClaudeAX
import Network
import Patcher
import ServiceManagement
import UserNotifications

extension AppDelegate {
    // ---------------------------------------------------------------- обновление самого Пимпа и Viewer (WF217, К-SU)

    /// Когда нельзя подменять: открыта панель, идёт патч, обновление Claude или его загрузка, пишет Диктатор;
    /// Viewer — пока запущен; Пимп — пока занят канал «Пимп», окна Claude не вернулись или идёт работа (WF234). Сеть — та же мерка, что у фоновой загрузки Claude: есть и не дорогая.
    func wireSelfUpdate() {
        selfUpdate.moment = { [weak self] in
            guard let self = self else { return SelfUpdateMoment(busy: true) }
            return SelfUpdateMoment(
                panelOpen: self.panel.isOpen,
                busy: self.busy || self.claudeDownload != nil || self.readyRechecks > 0,
                recording: self.ax.isDictating,
                viewerRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: SelfUpdateProduct.viewer.bundleID).isEmpty,
                windows: self.ax.isSettlingWindows,
                // Общий ответ «идёт ли работа» (WF234): идёт или не знаем — Пимп себя не подменяет.
                working: self.workNowForClaude().work.working != false)
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

    /// Claude только что запустился — тихий момент для установки; Viewer закрыли — его обновление встаёт. Claude
    /// запустился или вышел — отложенное «При запуске» обновление Claude (WF283).
    @objc func appLaunchedOrQuit(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let launched = notification.name == NSWorkspace.didLaunchApplicationNotification
        if app?.bundleIdentifier == Patcher.claudeBundleID { claudeLaunchedOrQuit(launched: launched) }
        if launched {
            if app?.bundleIdentifier == Patcher.claudeBundleID { selfUpdate.claudeLaunched() }
        } else if app?.bundleIdentifier == SelfUpdateProduct.viewer.bundleID {
            selfUpdate.viewerQuit()
        }
    }

    // ---------------------------------------------------------------- значок — в строку меню (#10280)

    /// Значок из ряда «Не влезли» отпустили в точке экрана: в строке меню правее выреза — Пимп ⌘-перетаскивает туда
    /// настоящий значок (панель не закрывается, ряд обновляется); мимо строки — подсказка, ничего не трогаем.
    func dropExtra(_ item: MenuBarExtras.Item, at cocoa: CGPoint) {
        let model = panel.model
        let screen = NSScreen.screens.first
        let bar = MenuBarExtras.bar(screen: screen)
        let drop = CGPoint(x: cocoa.x - (screen?.frame.minX ?? 0), y: (screen?.frame.maxY ?? 0) - cocoa.y)
        guard MenuBarExtras.movable(item) else {
            // Убранный совсем (не под вырезом) значок macOS не держит в строке — тащить нечего (#10285).
            showExtraNote("«\(item.appName)» macOS убрал из строки меню совсем — его не перенести. Нажми на него, чтобы открыть")
            return
        }
        model.extraNote = "Переношу «\(item.appName)»…"
        panel.refreshExtras()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let point = MenuBarExtras.dropPoint(drop, bar: bar, shown: MenuBarExtras.shownFrames())
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let point = point else {
                    self.showExtraNote("Отпусти значок в строке меню, правее выреза — рядом с другими значками")
                    return
                }
                self.panel.holdOpen = true
                MenuBarExtras.move(item, to: point) { [weak self] ok in
                    guard let self = self else { return }
                    self.panel.holdOpen = false
                    self.showExtraNote(ok ? nil : "«\(item.appName)» не перенёсся — macOS не пустил. Зажми ⌘ и перетащи значок в строке меню сам")
                    self.reloadExtras(force: true)
                }
            }
        }
    }

    private func showExtraNote(_ text: String?) {
        panel.model.extraNote = text
        panel.refreshExtras()
        guard let text = text else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self, self.panel.model.extraNote == text else { return }
            self.panel.model.extraNote = nil
            self.panel.refreshExtras()
        }
    }

    /// Значок отпустили между значками полосы (#10304): Пимп ⌘-переносом ставит его в строке меню рядом с соседом
    /// (панель не закрывается, полоса перечитывается); убранный совсем значок — подсказка, ни одного события.
    func reorderExtra(_ item: MenuBarExtras.Item, beside neighbor: MenuBarExtras.Item, after: Bool) {
        guard MenuBarExtras.reorderable(item, neighbor: neighbor) else {
            let off = MenuBarExtras.movable(item) ? neighbor : item
            showExtraNote("«\(off.appName)» macOS убрал из строки меню совсем — рядом с ним не переставить")
            return
        }
        panel.model.extraNote = "Переставляю «\(item.appName)»…"
        panel.refreshExtras()
        panel.holdOpen = true
        MenuBarExtras.reorder(item, beside: neighbor, after: after) { [weak self] ok in
            guard let self = self else { return }
            self.panel.holdOpen = false
            self.showExtraNote(ok ? nil : "«\(item.appName)» не переставился — macOS не пустил. Зажми ⌘ и перетащи значок в строке меню сам")
            self.reloadExtras(force: true)
        }
    }

    /// Значки «Не влезли» и их глифы (снимки окон, #10301) — вне главной нитки, вместе: полоса встаёт сразу с
    /// готовыми глифами и не меняет ширину после открытия. Панель закрылась — не трогаем.
    func reloadExtras(force: Bool = false) {
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = MenuBarExtras.hidden(force: force)
            let images = MenuExtrasStrip.glyphs(for: items, scale: scale)
            DispatchQueue.main.async {
                guard let self = self, self.panel.isOpen else { return }
                self.panel.model.extraImages = images
                self.panel.model.menuExtras = items
                self.panel.refreshExtras()
            }
        }
    }

    // ---------------------------------------------------------------- панель у часов (WF87)

    func wirePanel() {
        let model = panel.model
        let info = Bundle.main.infoDictionary ?? [:]
        model.appVersion = info["CFBundleShortVersionString"] as? String ?? "—"
        feed.onAccent = { [weak self] in self?.refreshIcon() }
        model.pressExtra = { [weak self] item in
            self?.panel.close()
            MenuBarExtras.press(item)
        }
        model.dropExtra = { [weak self] item, cocoa in self?.dropExtra(item, at: cocoa) }
        model.pressExtraSecondary = { [weak self] item in
            self?.panel.close()
            MenuBarExtras.pressSecondary(item)
        }
        model.reorderExtra = { [weak self] item, neighbor, after in self?.reorderExtra(item, beside: neighbor, after: after) }
        model.pickTempMin = { [weak self] value in
            UserDefaults.standard.set(value, forKey: StatusIcon.tempMinKey)
            self?.panel.model.tempMin = value
            self?.refreshIcon()
        }
        wireAutoRetry()
        panel.onOpen = { [weak self] in
            guard let self = self else { return }
            self.panel.model.limits = self.currentLimits()
            self.panel.model.patch = self.patchLook
            self.panel.model.archiving = self.ax.archiveBusy
            // «Поставить Рика» (WF216): строка видна, только пока папки Rick нет; идущее и готовое не сбрасываем.
            switch self.panel.model.rick {
            case .running, .done: break
            case .hidden, .idle, .failed: self.panel.model.rick = RickKit.isPresent ? .hidden : .idle
            }
            self.refreshKontekst()
            self.panel.model.sendDelay = self.ax.sendDelaySetting
            self.panel.model.sendDelayLine = nil
            self.panel.model.pinnedLook = self.ax.pinnedLook
            self.panel.model.enterKeys = self.ax.enterKeys
            self.panel.model.countdownSound = self.ax.countdownSound
            self.panel.model.sendLookStyle = self.ax.sendLookStyle
            self.panel.model.sendLookSize = self.ax.sendLookSize
            self.panel.model.bypassNew = self.ax.bypassNewChats
            self.panel.model.textJustify = self.ax.textJustify
            self.panel.model.cleanAnswers = self.ax.cleanAnswers
            self.panel.model.sidePadding = TextLook.sidePadding
            self.refreshWindowText()
            self.panel.model.bypassPermission = self.ax.bypassPermission
            self.panel.model.claudeSettingsFailed = false
            self.panel.model.memory = self.memory.watch(true)
            self.feed.opened()
            self.updateExtras.question = nil // вопрос про прошлое нажатие — к этому открытию не относится
            // «Не влезли в строку меню» (WF270): сбор AX — вне главной нитки, не чаще раза в 2 с.
            self.reloadExtras()
            self.updateToggleMarks()
            self.refreshDonateRow()
            self.refreshUpdateBlock()
            self.refreshPatchWorkNote()
            self.refreshState()
            self.checkClaudeUpdate()
            self.panel.model.selfUpdate = self.selfUpdate.look()
        }
        panel.onClose = { [weak self] in
            guard let self = self else { return }
            self.memory.watch(false)
            self.panel.model.extraNote = nil
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
            nextLaunch: { [weak self] in self?.planNextLaunch() },
            cancelNextLaunch: { [weak self] in self?.cancelNextLaunch() },
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
                // Прошлая причина отказа не висит после удачного нажатия (#9812).
                self.panel.model.sendDelayLine = self.ax.previewSendDelay(seconds: seconds)
                if self.panel.model.sendDelayLine == nil { self.panel.close() }
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
            installKontekst: { [weak self] in self?.installKontekst() },
            setup: { [weak self] in self?.showSetup() },
            donate: { [weak self] in
                self?.panel.close()
                self?.donate.show()
            },
            about: { [weak self] in self?.showAbout() },
            uninstall: { [weak self] in self?.uninstall() },
            quit: { NSApp.terminate(nil) },
            windowColor: { [weak self] choice in self?.feed.chooseWindowColor(choice) },
            previewWindowColor: { [weak self] choice in self?.feed.previewWindowColor(choice) },
            live: { [weak self] motion in self?.feed.setLiveMotion(motion) },
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
        // Размер отсчёта (WF242): ползунок в настройках выбранной плитки — `send-look` всем страницам.
        model.actions.sendLookSize = { [weak self] size in
            guard let self = self else { return }
            self.ax.setSendLookSize(size)
            self.panel.model.sendLookSize = self.ax.sendLookSize
        }
        // «Анализ памяти» (WF242): поручение из файла — в поле ввода окна Claude, без отправки. Ушло — панель
        // закрывается, чтобы поле было видно; не ушло — причина строкой под кнопкой.
        model.actions.memoryAnalysis = { [weak self] in
            guard let self = self else { return }
            let reason: String?
            do { reason = self.ax.insertStarter(try ChatStarter.memoryPrompt()) }
            catch { reason = "Не смог создать файл поручения: \(error.localizedDescription)" }
            if let reason = reason { self.panel.change { self.panel.model.memoryStarterNote = reason } }
            else { self.panel.close() }
        }
        model.actions.editMemoryPrompt = { [weak self] in
            guard let self = self else { return }
            do {
                _ = try ChatStarter.memoryPrompt()
                NSWorkspace.shared.open(ChatStarter.defaultDirectory.appendingPathComponent(ChatStarter.memoryFileName))
                self.panel.close()
            } catch {
                self.panel.change {
                    self.panel.model.memoryStarterNote = "Не смог создать файл поручения: \(error.localizedDescription)"
                }
            }
        }
        model.actions.sidePadding = { [weak self] value in
            self?.panel.model.sidePadding = TextLook.setSidePadding(value)
        }
        model.actions.selfUpdate = { [weak self] on in self?.selfUpdate.setEnabled(on) }
        wireWindowText()
        wireOneChat()
        wireMutedWaits()
    }

    /// Дополнительное оформление (WF237, бывшее меню жёлтой кнопки — лист 48, ответ 2.1): схема живого фона и текст
    /// окон — всем окнам; строка панели меняется сразу, запись берётся из `ax` на следующем открытии.
    private func wireWindowText() {
        let model = panel.model
        model.actions.scheme = { [weak self] id in
            guard let self = self else { return }
            self.ax.setLiveScheme(id)
            self.panel.model.liveScheme = id
            self.panel.model.liveBackground = true
        }
        model.actions.zoom = { [weak self] step in
            guard let self = self, self.ax.stepClaudeZoom(step) else { return }
            if let now = self.panel.model.claudeZoom { self.panel.model.claudeZoom = step.percent(after: now) }
        }
        model.actions.dense = { [weak self] on in
            self?.ax.setDenseText(on)
            self?.panel.model.denseText = on
        }
        model.actions.windowFont = { [weak self] id in
            self?.ax.setWindowFont(id)
            self?.panel.model.windowFontID = id
        }
        model.actions.textSize = { [weak self] px in
            self?.ax.setWindowTextSize(px)
            self?.panel.model.windowTextSize = px
        }
        model.actions.hideTools = { [weak self] on in
            self?.ax.setHideTools(on)
            self?.panel.model.hideTools = on
        }
        model.actions.hideCode = { [weak self] on in
            self?.ax.setHideCode(on)
            self?.panel.model.hideCode = on
        }
    }

    private func refreshWindowText() {
        let model = panel.model
        model.denseText = ax.denseText
        let fonts = ax.panelFonts
        if model.windowFonts != fonts { model.windowFonts = fonts }
        model.windowFontID = ax.windowFontID
        model.windowTextSize = ax.windowTextSize
        model.hideTools = ax.hideTools
        model.hideCode = ax.hideCode
    }

    /// Строка «Поддержать автора»: donate.json перечитан по mtime при каждом открытии панели.
    private func refreshDonateRow() {
        let model = panel.model
        model.donateAvailable = Donate.windowAvailable(donate.config())
    }

    /// Возврат платёжки `pimpmyclaude://donate/thanks|cancel` (WF108): «Спасибо!» или «Отменено» в окне.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let answer = Donate.parseReturn(url) { donate.handleReturn(answer) }
        }
    }

    /// Панель у значка (кнопка уведомления, сбой установки, кнопка PMP в окне Claude); значок за вырезом — у плашки
    /// (#10016). Уже открыта — ничего.
    func openPanel() {
        guard !panel.isShown, let button = statusGuard?.anchor ?? statusItem?.button else { return }
        panel.open(from: button)
    }

    /// «Пропатчить Claude» / «Вернуть патч» — без вопроса (кнопка и есть согласие): шаг — в
    /// кнопке, ошибка — под ней, «Подробнее…» — прежнее окно журнала. Встал — панель пружиной
    /// распрямляется в «всё хорошо» (`show(state:)`).
    func patchFromPanel() {
        guard !busy, let url = askForClaude() else { return }
        busy = true
        refreshUpdateBlock()
        patchLog = []
        patchSettings = nil
        panel.model.patchFix = nil
        let loader = panel.model.loader
        panel.change { panel.model.patchRun = .running("Закрываю Claude…") }
        let patcher = ClaudePatcher(appURL: url)
        let post: (String) -> Void = { line in
            self.keychainHintIfClaudeOpens(line, .patch)
            self.watchPermission(line, resume: "patch")
            DispatchQueue.main.async {
                self.patchLog.append(line)
                if let step = PimpPanelText.patchStep(line, loader: loader) {
                    self.panel.model.patchRun = .running(step)
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outcome = try patcher.install(progress: post)
                DispatchQueue.main.async {
                    self.permissionEnded(nil)
                    // Починка хэша и подписи открывает Claude без строки в журнале — подсказка нужна и тут.
                    if case .repaired = outcome { self.keychainHint.begin(.patch) }
                    self.panel.model.patchRun = .idle
                    self.operationFinished()
                }
            } catch {
                let message = error.humanText
                let settings = Self.settingsAction(for: error)
                DispatchQueue.main.async {
                    if self.permissionEnded(error) { return }
                    if case PatchError.cancelled = error {
                        self.panel.model.patchRun = .idle
                        self.operationFinished()
                        return
                    }
                    self.patchLog.append("Не вышло. " + message)
                    self.patchSettings = settings
                    // Права так и не дали — кнопка панели снова открывает настройки и сама ждёт (#9842).
                    let fix = settings == nil ? nil : "Открыть настройки"
                    self.panel.change {
                        self.panel.model.patchFix = fix
                        self.panel.model.patchRun = .failed(message)
                    }
                    self.operationFinished()
                    self.openPanel() // панель закрылась, пока шёл патч, — ошибка иначе не видна
                }
            }
        }
    }
}
