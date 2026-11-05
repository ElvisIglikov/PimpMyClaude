import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - канал «Пимп» (план WF36)

    /// Недавние проекты для меню и канала: свой файл, долитый из индекса Claude. Файл не
    /// записался (папки нет, прав нет) — отдаём индекс: список обязан остаться живым, как
    /// до WF36.
    func knownProjects(limit: Int) -> [Project] {
        projects.absorb(index.projects(), at: Date())
        let stored = projects.recent(limit: limit)
        return stored.isEmpty ? index.recentProjects(limit: limit) : stored
    }

    /// Сиденья канала: всё, что он спрашивает у приложения. AX наружу не отдаём — канал
    /// говорит номерами окон Quartz, а окна двигает `ClaudeActions`.
    func connectPimp() {
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
                self?.hud.show(text, seconds: Notices.newWindowNoticeSeconds)
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
            newWindowBusy: { [weak self] in self?.actions.newWindowBusy ?? false },
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

    /// Окна Claude для раскладок: то же, что отдаёт канал «Пимп».
    func pimpWindowList() -> [PimpWindow] {
        actions.beginWindowBatch()
        defer { actions.endWindowBatch() }
        return actions.pimpWindows().map { pimpWindow(id: $0.id, title: $0.title, frame: $0.frame) }
    }

    func allWindowObservation() -> (windows: [PimpWindow], complete: Bool) {
        actions.beginWindowBatch()
        defer { actions.endWindowBatch() }
        let census = actions.windowCensus()
        let windows = census.windows.map { pimpWindow(id: $0.id, title: $0.title, frame: $0.frame) }
        let checked = WindowSnapshotStore.observe(from: windows, complete: census.complete,
                                                   isMain: { _ in false }, screen: { _ in "" })
        return (windows, checked.complete)
    }

    func snapshotObservation() -> SnapshotObservation {
        let census = allWindowObservation()
        return WindowSnapshotStore.observe(from: census.windows, complete: census.complete,
                                            isMain: actions.isMainWindowTitle, screen: Self.screenName)
    }

    func restoreFrame(_ frame: CGRect) -> CGRect {
        RestoreFrame.adapt(frame, screens: Screens.all().map { $0.usable }, minWidth: ClaudeActions.minFrameWidth())
    }

    /// Окно канала: к заголовку и рамке добавляются чат и папка — их знает индекс Claude
    /// и карта probe. Карта молчит (тумблер выключен, канал занят агентом) — обе строки пусты.
    func pimpWindow(id: CGWindowID, title: String, frame: CGRect) -> PimpWindow {
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
    func windowIdentity(id: CGWindowID? = nil, title: String, frame: CGRect?) -> WindowIdentity {
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
    func pimpTitle(forChat chat: String) -> String? {
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
    func startLayoutInputMonitors() {
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

    func stopLayoutInputMonitors() {
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
                && AX.bool($0.window, MenuKit.fullScreenAttribute) == false
        }
        let safe = started && AX.isTrusted && layoutGlobalMonitor != nil && layoutLocalMonitor != nil
            && NSEvent.pressedMouseButtons == 0 && safeWindows && !pimp.isBusy
            && !actions.cashoutPending && !actions.newWindowStarting
        let screens = NSScreen.screens.map { ScreenSpec(name: $0.localizedName, frame: Screens.flip(rect: $0.frame)) }
        return OneShotLayoutGuard.Observation(pid: app.pid, screens: ScreenLayoutKeeper.key(screens),
            windows: census.windows, complete: census.complete, safe: safe,
            restorePending: windowSnapshots.hasPendingRestore || screenLayouts.hasPendingRestore,
            nativeComplete: actions.windowCensus().complete)
    }

    func armLayoutGuard(_ moves: [PimpMove], waitForRestore: Bool = false) {
        let desired = moves.map { PimpMove(id: $0.id, frame: restoreFrame($0.frame)) }
        layoutGuard.arm(desired, observation: layoutGuardObservation(), at: Date(), waitForRestore: waitForRestore)
    }

    func layoutGuardTick() {
        if !windowSnapshots.hasPendingRestore && !screenLayouts.hasPendingRestore { restoreConfirmationUntil = nil }
        guard layoutGuard.active else { return }
        let correction = layoutGuard.tick(layoutGuardObservation(), at: Date())
        // The guard has already consumed itself. place/onWindowsMoved cannot rearm it.
        if !correction.isEmpty { actions.place(correction) }
    }
}
