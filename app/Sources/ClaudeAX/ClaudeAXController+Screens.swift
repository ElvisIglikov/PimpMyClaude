import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - окна WF94: мониторы, ChatGPT, исход «Нового окна»

    /// Сиденья окон WF94. Расстановка по мониторам (#7740) — окна те же, что у снимка К5;
    /// не начинается, пока занят канал «Пимп» или идёт возврат К5. Каналу — окно ChatGPT
    /// для ответа `windows` (#7732), исход цепочки главной страницы (K-N) и ручной возврат
    /// `screens-restore`.
    func connectScreens() {
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
                        && AX.bool($0.window, MenuKit.fullScreenAttribute) == false
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
            PimpChannel.mainChatSetting(LiveConfig.data())
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
        // #11201 (WF302): замена чата ждёт паузы в наборе — клавиши Элвиса и синтетические Диктатора.
        pimp.seats.keyIdle = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) }
        pimp.seats.screens = { Screens.all() }
        pimp.seats.cellWidth = { [weak self] in self?.actions.cellWidth() ?? 0 }
        // WF103 (#7953): «отправь текст в чат» — команда окну и исход страницы из круга `cash`.
        pimp.seats.sendText = { [weak self] chat, text, id in self?.actions.sendText(chat: chat, text: text, id: id) }
        pimp.seats.sendState = { [weak self] id in
            self?.chatProbe.pages.lazy.compactMap { $0.send }.first { $0.id == id }?.state
        }
        // WF105 (#8071): `arrange --order` не нашёл окно с неопознанным чатом — переспросить
        // карту чатов один раз, без сна: ответ ждёт канал на тиках.
        pimp.seats.demandChats = { [weak self] at in self?.chatProbe.demand(at: at) }
        pimp.seats.chatsAnswered = { [weak self] since in self?.chatProbe.answered(after: since) ?? true }
        // WF98 (#7841): новое окно сразу на месте — ячейка до команды, опрос рождения 0,1 с.
        actions.connectNewWindowPlace(&pimp.seats)
        pimp.seats.isRestoring = { [weak self] in self?.windowSnapshots.phase == .restoring }
        actions.isRestoringWindows = { [weak self] in self?.windowSnapshots.phase == .restoring || self?.pimp.isRestoring == true }
    }
}
