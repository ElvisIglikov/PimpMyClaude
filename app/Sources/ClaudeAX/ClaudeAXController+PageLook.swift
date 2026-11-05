import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - вид страницы и отсчёт отправки

    func connectPageLook() {
        pageLook.write = { [weak self] action, fields, priority in
            self?.commands.write(action: action, fields: fields, priority: priority) ?? false
        }
        // Прежний CLI show адресует главное окно; кнопка панели выбирает видимое ниже.
        pageLook.mainMatch = { [weak self] in self?.actions.mainWindowMatch() }
        pageLook.isRunning = { [weak self] in self?.app.running() != nil }
        // Файл настроек Claude читается не чаще раза в 30 с: тик идёт каждые несколько секунд.
        var bypassCache: (at: Date, allowed: Bool)?
        pageLook.bypassAllowed = {
            if let cache = bypassCache, Date().timeIntervalSince(cache.at) < 30 { return cache.allowed }
            let allowed = BypassNew.permission() == .allowed
            bypassCache = (Date(), allowed)
            return allowed
        }
        pimp.seats.setDim = { [weak self] on, percent in
            self?.pageLook.setDim(on: on, percent: percent) ?? PageLook()
        }
        pimp.seats.setLook = { [weak self] style, size, grow, show in
            self?.pageLook.setLook(style: style, size: size, grow: grow, show: show) ?? (PageLook(), false)
        }
    }

    public var sendDelaySetting: SendDelaySetting { pageLook.sendDelaySetting(pages: chatProbe.pages) }

    /// Масштаб окон Claude в процентах; круг `ChatProbe` ещё не прошёл — nil.
    public var claudeZoom: Int? { chatProbe.pages.first { $0.kind == .main && $0.zoom != nil }?.zoom }

    /// Шаг масштаба пунктом меню Claude; пункта нет или он погашен — false.
    @discardableResult public func stepClaudeZoom(_ step: ClaudeZoom) -> Bool { actions.pressClaudeZoom(step) }

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

    /// Размер отсчёта, проценты 60…200 (WF242: «размер ракеты… чтобы она побольше была»); ключа нет — 100.
    public var sendLookSize: Int { pageLook.current.size }

    /// Ползунок размера в панели: память и рассылка `send-look` всем страницам без показа.
    public func setSendLookSize(_ size: Int) { pageLook.setLook(size: size) }

    /// Стартер чата (WF242, «Анализ памяти»): текст ложится в поле ввода окна Claude и НЕ отправляется — человек
    /// сам жмёт Enter. Окно — то же, что у показа отсчёта: опознанное видимое в фокусе, иначе главное; не опознали —
    /// главное окно на экране, команда без адреса (страница в фокусе). nil — команда ушла; строка — почему нет.
    public func insertStarter(_ text: String) -> String? {
        guard app.pid != nil, !actions.pimpWindows().isEmpty else { return "Открой окно Claude — вставить некуда" }
        let match: String?, chat: String?
        if let target = sendDelayPreviewTarget() {
            actions.raise(id: target.id)
            (match, chat) = (target.match, target.chat)
        } else {
            guard let id = fallbackMainWindowID(actions.pimpWindows()) else {
                return "Открой главное окно Claude — вставить некуда"
            }
            actions.raise(id: id)
            (match, chat) = (nil, nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + actions.focusDelay) { [weak self] in
            self?.actions.insertStarter(text: text, match: match, chat: chat)
        }
        return nil
    }

    /// Разрешён ли Bypass в самом Claude — только чтение его файла настроек.
    public var bypassPermission: BypassNew.Permission { BypassNew.permission() }

    /// Окно настроек Claude (пункт «Settings…» его меню); false — пункта не нашли.
    @discardableResult
    public func openClaudeSettings() -> Bool { actions.pressClaudeSettings() }

    /// `only` — адрес именно этого окна (сверка после подъёма, #9812), остальные видимые не смотрим.
    private func sendDelayPreviewTarget(only: CGWindowID? = nil) -> ClaudeActions.SendDelayPreviewTarget? {
        guard let pid = app.pid else { return nil }
        // Один свежий AX-снимок на подбор; через focusDelay он не переносится.
        actions.beginWindowBatch()
        defer { actions.endWindowBatch() }
        let windows = actions.pimpWindows()
        let focused = app.isFrontmost ? app.focusedWindow() : nil
        let focusedID = windows.first { entry in focused.map { CFEqual(entry.window, $0) } ?? false }?.id
        let visible = ClaudeApp.onScreenFrames(pid: pid).compactMap { frame -> (id: CGWindowID, page: ChatPage?)? in
            guard only == nil || frame.id == only, let window = windows.first(where: { $0.id == frame.id }) else { return nil }
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

    public func previewSendDelay(seconds: Int) -> String? {
        guard SendDelaySetting.validSeconds(seconds) else { return "Выбери 2, 3, 5 или 10 секунд" }
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
            guard let id = self.fallbackMainWindowID(windows) else {
                self.onSendDelayPreviewFailed?(windows.isEmpty ? "Открой окно Claude, чтобы показать отсчёт"
                                                               : "Открой главное окно Claude, чтобы показать отсчёт")
                return
            }
            self.actions.raise(id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + self.actions.focusDelay) { [weak self] in
                guard let self = self, self.app.pid == pid else { return }
                if !self.pageLook.previewSendDelayMain(seconds: seconds) {
                    self.onSendDelayPreviewFailed?(Self.sendDelayPreviewNotWritten)
                }
            }
        }
    }

    /// Запасное окно отсчёта и стартера (`ClaudeActions.sendDelayFallbackWindow`): главное на экране, в фокусе.
    private func fallbackMainWindowID(_ windows: [ClaudeActions.WindowRecord]) -> CGWindowID? {
        let focused = app.isFrontmost ? app.focusedWindow() : nil
        return ClaudeActions.sendDelayFallbackWindow(windows.map { entry in
            (id: entry.id, main: windowIdentity(id: entry.id, title: entry.title, frame: entry.frame).isMain
                || actions.isMainWindowTitle(entry.title),
             focused: focused.map { CFEqual(entry.window, $0) } ?? false)
        })
    }

    /// «Показать» молчал (#9812, слово Элвиса 11.10: «ракету показать в окне клауда не работает»): после подъёма
    /// окна показ шёл, только если ВЕСЬ подбор окна сходился с первым — а он плывёт сам: ответ главного окна
    /// живёт 10 с при круге карты 15 с (`ChatProbe.mainChatSeconds`), подъём меняет фокус, карта обновляется
    /// между двумя взглядами. Не сошлось — показ молча не шёл, панель уже закрыта. Теперь сверка — только «окно
    /// то же и живо»: адрес — его свежий, не опознано сейчас — прежний (страница сверит его с собой). Окно
    /// закрылось или команда не записалась — причина в панели, а не тишина.
    static let sendDelayPreviewGone = "Окно Claude закрылось раньше показа — открой его и нажми «Показать» ещё раз"
    static let sendDelayPreviewNotWritten = "Показ не дошёл до окна Claude: не записался command.json в папке MyClaude"

    /// Адрес показа после подъёма: свежий адрес ТОГО ЖЕ окна, иначе прежний. Чистая, её гоняют тесты.
    static func sendDelayPreviewAddress(sent: ClaudeActions.SendDelayPreviewTarget,
                                        now: ClaudeActions.SendDelayPreviewTarget?) -> ClaudeActions.SendDelayPreviewTarget {
        guard let now = now, now.id == sent.id else { return sent }
        return now
    }

    private func playSendDelayPreview(seconds: Int, target: ClaudeActions.SendDelayPreviewTarget, pid: pid_t) {
        // Панель успевает закрыться; после подъёма сверяем только, что окно то же и живо (#9812).
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.app.pid == pid else { return }
            guard self.actions.pimpWindows().contains(where: { $0.id == target.id }) else {
                self.onSendDelayPreviewFailed?(Self.sendDelayPreviewGone); return
            }
            self.actions.raise(id: target.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + self.actions.focusDelay) { [weak self] in
                guard let self = self, self.app.pid == pid else { return }
                guard self.actions.pimpWindows().contains(where: { $0.id == target.id }) else {
                    self.onSendDelayPreviewFailed?(Self.sendDelayPreviewGone); return
                }
                let address = Self.sendDelayPreviewAddress(sent: target, now: self.sendDelayPreviewTarget(only: target.id))
                if !self.pageLook.previewSendDelay(seconds: seconds, match: address.match, chat: address.chat) {
                    self.onSendDelayPreviewFailed?(Self.sendDelayPreviewNotWritten)
                }
            }
        }
    }
}
