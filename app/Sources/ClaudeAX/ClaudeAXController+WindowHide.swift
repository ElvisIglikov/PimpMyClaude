import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - «🙈 Спрятать окна» (WF112, #8255)

    /// Канал `hide`/`show` и заморозка снимков: пока есть окна, спрятанные Пимпом, снимок К5 и
    /// раскладка мониторов не пишутся — свёрнутых нет в списке окон, и оба затёрлись бы главным.
    func connectWindowHide() {
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
                            fullScreen: AX.bool($0.window, MenuKit.fullScreenAttribute) == true,
                            keep: entry != nil && PimpChannel.isMainProject(folder: folder, entry: entry),
                            projectKnown: entry == nil || !folder.isEmpty)
        })
    }

    /// `mainProject` живого claude.json (гейт WF111, #8284); файл крошечный — читаем, когда нужен.
    func mainProjectSetting() -> String? {
        PimpChannel.mainProjectSetting(LiveConfig.data())
    }

    func updateMainProjectKeep() {
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

    /// Тик 2 с (#8282, слово Рика 30.09: «окно, где ждут Элвиса, должно быть видно»): спрятанное Пимпом
    /// окно, чей чат ждёт слова Элвиса (`status().attention.want` страницы), разворачивается само, одно; остальные
    /// спрятаны. Claude впереди — клавиатура возвращается главному окну (там Рик).
    func showWaitingTick() {
        let resolve: (String, CGRect?) -> WindowIdentity = { [weak self] title, frame in
            self?.windowIdentity(title: title, frame: frame) ?? .unknown
        }
        if let shown = waitShown {
            // Снова свёрнуто или закрыто — забыли; на экране и чат всё ждёт (или круг без ответа) — ждём и мы.
            if AX.bool(shown, kAXMinimizedAttribute) == false,
               let page = WindowHide.page(for: (AX.string(shown, kAXTitleAttribute) ?? "", AX.frame(shown)),
                                          resolve: resolve),
               page.waiting != false { return }
            waitShown = nil
        }
        guard hiddenByPimp.count > 0, !windowsBusy else { return }
        let hidden = hiddenByPimp.current
        let seen = hidden.map { (title: AX.string($0, kAXTitleAttribute) ?? "", frame: AX.frame($0)) }
        guard let index = WindowHide.waiting(seen, resolve: resolve),
              AX.set(hidden[index], kAXMinimizedAttribute, bool: false) else { return }
        let window = hidden[index]
        hiddenByPimp.remove { CFEqual($0, window) }
        waitShown = window
        if app.isFrontmost { focusMainSoon() }
    }
}
