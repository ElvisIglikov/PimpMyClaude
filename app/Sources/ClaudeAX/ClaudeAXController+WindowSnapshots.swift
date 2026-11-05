import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - окна как были (#7065, контракт К5)

    /// Сиденья снимка окон. Окна — те же, что у канала «Пимп»; возврат — его очередью, так
    /// что пункт меню, запрос из чата и автовозврат друг с другом не спорят.
    func connectWindowSnapshots() {
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

    /// Снять окна прямо сейчас — перед тем как закрыть Claude (обновление, батч M2 WF84).
    /// Возврат после нового запуска сработает сам.
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

    /// Имя экрана, где лежит центр рамки (перевёрнутые координаты), — справка в снимке.
    static func screenName(_ frame: CGRect) -> String {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { Screens.flip(rect: $0.frame).contains(center) }?
            .localizedName ?? ""
    }
}
