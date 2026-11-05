import AppKit
import ApplicationServices
import ClaudeAX
import Network
import Patcher
import ServiceManagement
import UserNotifications

extension AppDelegate {
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
    func refreshUpdateBlock(now: Date = Date()) {
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
        extras.plannedVersion = UserDefaults.standard.string(forKey: PimpPanelText.updatePlannedKey)
        // Готовое: что сейчас идёт (страницы, Workflow, терминалы) — правдой в блоке; «самое время» — только когда
        // общий ответ «тихо» (WF234).
        if extras.question == nil, case .ready(let version) = claudeUpdate.phase, let target = claudeUpdateTarget() {
            let presence = claudePresence(ClaudeUpdater(appURL: target))
            let work = workNow(at: now).seen(claudeRunning: presence.running, windowCount: presence.windows)
            extras.workLine = PimpPanelText.workLine(work)
            extras.workShort = PimpPanelText.workShort(work)
            if offering == version {
                extras.offerReason = PimpPanelText.offerReason(claudeRunning: presence.running,
                                                               windowCount: presence.windows, work: work)
            }
        }
        shownWorkLine = extras.workLine
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

    /// «Самое время» (10-choice §3.3, провязка `shouldOffer`): готово, работа не идёт нигде (страницы, Workflow,
    /// терминальные чаты — `workNow`, WF234), Claude не запущен, окон нет или тихо ≥ 2 мин, не предлагали 3 ч и не
    /// «Позже». Предложение держится, пока условия верны (иначе «Обновить сейчас» без вопроса закрыло бы работающий
    /// чат); уведомление «Скачалось» — одно на версию, в первый такой момент или через сутки после готовности.
    func evaluateOffer(now: Date = Date(), refresh: Bool = true) {
        guard case .ready(let version) = claudeUpdate.phase, !busy, let target = claudeUpdateTarget() else { return }
        let defaults = UserDefaults.standard
        // Отложено «При запуске» (WF283) — не маячим: ни «самого времени», ни уведомления «Скачалось».
        if defaults.string(forKey: PimpPanelText.updatePlannedKey) == version {
            if offering != nil {
                offering = nil
                if refresh { refreshUpdateBlock(now: now) }
            }
            return
        }
        let presence = claudePresence(ClaudeUpdater(appURL: target))
        let work = workNow(at: now)
        func offer(lastOfferAt: Date?, snoozeUntil: Date?) -> Bool {
            ClaudeUpdateMenu.shouldOffer(ready: true, claudeRunning: presence.running, windowCount: presence.windows,
                                         work: work, lastOfferAt: lastOfferAt, snoozeUntil: snoozeUntil, now: now)
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
        let line = PimpPanelText.workLine(work.seen(claudeRunning: presence.running, windowCount: presence.windows))
        if refresh, before != offering || line != shownWorkLine { refreshUpdateBlock(now: now) }
    }

    // ---------------------------------------------------------------- идёт ли работа (WF234)

    /// Идёт ли работа — один ответ для всех решений об обновлении и перезапуске: страницы Claude, идущие Workflow
    /// и терминальные чаты. Заодно переспрашивает сводку — не чаще раза в `WorkWatch.askSeconds` и только когда
    /// ответ кому-то нужен (готовое обновление, подмена Пимпа, открытая панель); своего таймера нет.
    private func workNow(at now: Date = Date()) -> WorkNow {
        refreshWork(now: now)
        return workWatch.now(pages: ax.pageSignals, at: now)
    }

    private func refreshWork(now: Date = Date(), force: Bool = false) {
        guard force || now.timeIntervalSince(workAskedAt) >= WorkWatch.askSeconds else { return }
        workAskedAt = now
        ax.projectsWork { [weak self] work in
            guard let self = self else { return }
            let before = self.workWatch
            self.workWatch.note(work)
            guard before != self.workWatch else { return }
            self.refreshPatchWorkNote()
            if case .ready = self.claudeUpdate.phase { self.evaluateOffer() }
        }
    }

    /// То же про копию Claude, которую обновляем и патчим: без окон страницы в счёт не идут. `closes` — у копии
    /// есть окна, то есть её закрытие что-то прервёт.
    func workNowForClaude() -> (work: WorkNow, closes: Bool) {
        let presence = claudeUpdateTarget().map { claudePresence(ClaudeUpdater(appURL: $0)) } ?? (running: false, windows: 0)
        return (workNow().seen(claudeRunning: presence.running, windowCount: presence.windows),
                presence.running && presence.windows > 0)
    }

    /// Что прервёт закрытие Claude патчем — строка под кнопкой патча и в вопросах «Пропатчить / Снять патч».
    /// Окон нет или работы не видно — nil.
    func patchWorkNote() -> String? {
        let claude = workNowForClaude()
        return claude.closes ? PimpPanelText.patchWorkNote(claude.work) : nil
    }

    func refreshPatchWorkNote() {
        guard panel.isOpen else { return }
        let note = patchWorkNote()
        if panel.model.patchWorkNote != note { panel.model.patchWorkNote = note }
    }

    /// Какую копию обновлять: пропатченную (`installed.json`), иначе выбранную, иначе в /Applications.
    /// Копию в «_Не удалять» и прочие фон не трогает (критик WF87 п. 1).
    func claudeUpdateTarget() -> URL? {
        ClaudeUpdater.targetClaude(installedAppPath: ClaudeUpdater.installedAppPath(),
                                   savedPath: UserDefaults.standard.string(forKey: Key.claudePath),
                                   copies: Patcher.locateClaude())
    }

    private func saveNextDaily() {
        UserDefaults.standard.set(claudeUpdate.nextDailyAt, forKey: ClaudeUpdateMenu.nextDailyKey)
    }

    @objc func checkClaudeUpdateAfterWake() { checkClaudeUpdate(trigger: .daily) }

    /// Мак засыпает — гонку отменяем сами: после сна судья счёл бы все полосы «завис», перезапустил
    /// их без сети и ушёл бы на часовую паузу. Отмена паузы не даёт; продолжит таймер или сеть.
    @objc func claudeDownloadBeforeSleep() { claudeDownload?.cancel() }

    func resumeClaudeDownload() {
        guard foundRelease != nil, claudeDownload == nil, let url = claudeUpdateTarget() else { return }
        startClaudeDownloadIfWanted(url: url)
    }

    /// Готовое с прошлого запуска (`ready.json`, подпись и Gatekeeper заново). Потом — `next`.
    func restoreReadyClaude(then next: @escaping () -> Void = {}) {
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
    func checkClaudeUpdate(trigger: ClaudeUpdateMenu.Trigger = .menu) {
        defer { showClaudeUpdate() }
        guard !busy, let url = claudeUpdateTarget(),
              claudeUpdate.beginCheck(at: Date(), trigger: trigger, busy: busy) else { return }
        saveNextDaily()
        let updater = ClaudeUpdater(appURL: url)
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try updater.check() }
            DispatchQueue.main.async {
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
            claudeUpdate.finish(.failed(error.humanText), at: Date())
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
        var updater = ClaudeUpdater(appURL: url)
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
        showClaudeUpdate()
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try updater.prepare(release, control: control) }
            DispatchQueue.main.async {
                self.claudeDownload = nil
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
                    self.claudeUpdate.downloadFailed(error.humanText, at: Date())
                    self.restoreReadyClaude() // прежнее готовое могло уцелеть
                }
            }
        }
    }

    /// Дорогая или ограниченная сеть — фоновая загрузка не идёт, начатая отменяется; сеть снова
    /// обычная — продолжаем сразу, не ждём проверки (гейт 1 WF87, A1).
    func networkChanged(costly: Bool, up: Bool) {
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

    /// Кнопка уведомления «Обновить»: панель у значка и то же, что кнопка блока (вопрос — в панели).
    @objc func updateClaude() {
        openPanel()
        pressUpdate()
    }

    /// «Обновить Claude» / «Обновить сейчас» в блоке: готово — одно нажатие; спрашиваем прямо в блоке, только если у
    /// этой копии есть окна и общий ответ (страницы, Workflow, терминальные чаты — WF234) не «тихо»: работа видна —
    /// вопрос называет, что прервётся. Найдено, но не скачано — «Скачать».
    func pressUpdate() {
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
        // страницы сейчас и решаем только по ответу, пришедшему после нажатия; сводку — заодно.
        askingPages = true
        let since = Date()
        ax.refreshPageSignals()
        refreshWork(now: since, force: true)
        waitForPages(since: since, url: url)
    }

    /// Последний шаг нажатия: работа видна или «тихо» сказать нельзя — вопрос в блоке, иначе ставим.
    private func confirmOrInstall(_ prepared: PreparedClaudeUpdate, url: URL, work: WorkNow) {
        let presence = claudePresence(ClaudeUpdater(appURL: url))
        guard ClaudeUpdateMenu.needsConfirm(claudeRunning: presence.running, windowCount: presence.windows,
                                            work: work) else {
            installClaude(prepared, url: url)
            return
        }
        openPanel() // панель закрыли, пока ждали, — вопрос должен быть виден
        updateExtras.question = PimpPanelText.confirmQuestion(
            work: work.seen(claudeRunning: presence.running, windowCount: presence.windows))
        refreshUpdateBlock()
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
        confirmOrInstall(ready.prepared, url: url, work: workWatch.now(pages: signals, at: Date()))
    }

    /// «Обновить всё равно» — ответ на вопрос, без повторного вопроса.
    func updateWithoutAsking() {
        updateExtras.question = nil
        guard !busy, claudeDownload == nil, readyRechecks == 0, let url = claudeUpdateTarget(),
              let ready = readyClaude, ready.url == url, case .ready = claudeUpdate.phase else {
            refreshUpdateBlock()
            return
        }
        installClaude(ready.prepared, url: url)
    }

    /// «Позже»: не предлагать 3 ч, блок на 2,5 с говорит «напомню через 3 часа».
    func updateLater() {
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
    /// `relaunch: false` — Claude после установки не открывается (отложенное при закрытом Claude, WF283); `finished` —
    /// итог (nil — встало, иначе причина). false — установка не началась, `finished` не зовётся.
    @discardableResult
    func installClaude(_ prepared: PreparedClaudeUpdate, url: URL, relaunch: Bool = true,
                       finished: ((String?) -> Void)? = nil) -> Bool {
        let updater = ClaudeUpdater(appURL: url)
        guard claudeUpdate.startInstall() else { return false }
        busy = true
        offering = nil
        updateExtras = PimpPanelText.UpdateExtras()
        extrasGeneration += 1
        panel.model.installOpensClaude = relaunch
        showClaudeUpdate()
        // Снимок окон — до закрытия Claude (К5), и заморозка: без неё окна другой копии перепишут его.
        _ = ax.saveWindowSnapshot()
        ax.freezeWindowSnapshot(true)
        let pidsBefore = updater.runningPIDs()
        let post: (String) -> Void = { line in
            self.keychainHintIfClaudeOpens(line, .update)
            self.watchPermission(line, resume: "update")
            DispatchQueue.main.async {
                let step = PimpPanelText.installStep(line, current: self.updateExtras.installStep)
                guard step != self.updateExtras.installStep else { return }
                self.updateExtras.installStep = step
                self.refreshUpdateBlock()
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Ставим при закрытом Claude (`relaunch: false`) — открытый человеком за это время не закрываем.
                let outcome = try updater.install(prepared, relaunch: relaunch, closeRunning: relaunch, progress: post)
                DispatchQueue.main.async {
                    self.permissionEnded(nil)
                    self.readyClaude = nil
                    UserDefaults.standard.removeObject(forKey: PimpPanelText.updatePlannedKey)
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
                    finished?(nil)
                }
            } catch {
                let untouched = !pidsBefore.isEmpty && updater.runningPIDs() == pidsBefore
                DispatchQueue.main.async {
                    // Claude не закрывался — снимок ведётся дальше; закрывался — заморозка растает с запуском.
                    if untouched { self.ax.freezeWindowSnapshot(false) }
                    // Claude открыли до подмены (WF283) — не сбой: бандл цел, план стоит до следующего закрытия.
                    if case ClaudeUpdateError.claudeOpened = error {
                        self.ax.freezeWindowSnapshot(false)
                        self.permissionEnded(nil)
                        self.claudeUpdate.installFailed(error.humanText)
                        self.claudeUpdateFinished()
                        self.restoreReadyClaude()
                        finished?(error.humanText)
                        return
                    }
                    // Отложенное не повторяется само по кругу: сбой — полная карточка и «Ещё раз» (WF283).
                    UserDefaults.standard.removeObject(forKey: PimpPanelText.updatePlannedKey)
                    finished?(error.humanText)
                    if self.permissionEnded(error) { return }
                    self.claudeUpdate.installFailed(error.humanText)
                    self.updateExtras = PimpPanelText.UpdateExtras(installFailure: error.humanText)
                    self.claudeUpdateFinished()
                    self.restoreReadyClaude()
                    self.openPanel()
                }
            }
        }
        return true
    }

    /// Отказы `restart-claude` — их читает человек в ответе CLI; в интерфейсе только «PMP» (#9604).
    static let restartClosingText = "PMP закрывается"
    static let restartBusyText = "PMP занят: обновляет или патчит Claude"

    /// `pimp.py restart-claude` (WF108, #8176): путь «Обновить Claude» без подмены бандла — снимок
    /// окон (К5) и заморозка, как в `installClaude`, потом `ClaudeUpdater.restartClaude` (те же выход
    /// и запуск) той же копии. Окна вернёт автовозврат снимка. Claude не закрывался — снимок оттаивает.
    func wireRestartClaude() {
        ax.restartClaude = { [weak self] running, done in
            guard let self = self else { return done(AppDelegate.restartClosingText) }
            guard !self.busy else { return done(AppDelegate.restartBusyText) }
            guard let url = running ?? self.claudeUpdateTarget() else { return done("Не нашёл Claude.app") }
            // Обновление отложено «При запуске» (WF283) — перезапуск и есть запуск: ставим его, Claude откроется.
            if let prepared = self.plannedPrepared(for: url, restarting: true),
               self.installClaude(prepared, url: url, finished: { done($0) }) { return }
            let updater = ClaudeUpdater(appURL: url)
            // Пока Claude закрывается и открывается, «Обновить/Пропатчить Claude» панели ждут (гейт 2 WF108).
            self.busy = true
            self.refreshUpdateBlock()
            _ = self.ax.saveWindowSnapshot()
            self.ax.freezeWindowSnapshot(true)
            let pidsBefore = updater.runningPIDs()
            DispatchQueue.global(qos: .userInitiated).async {
                var failure: String?
                do { try updater.restartClaude() } catch { failure = error.humanText }
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
        let windows = WindowInfo.list([.optionAll, .excludeDesktopElements]).filter {
            pids.contains($0.pid) && $0.layer == 0 && $0.frame.width >= 200 && $0.frame.height >= 200
        }.count
        return (true, windows)
    }

    private func claudeUpdateFinished() {
        operationFinished()
        showClaudeUpdate()
    }
}
