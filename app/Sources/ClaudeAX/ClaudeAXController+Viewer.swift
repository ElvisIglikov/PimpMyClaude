import AppKit
import ApplicationServices

extension ClaudeAXController {
    // MARK: - Pimp Viewer (WF97, #7719–#7724; с WF104 — PimpViewer.app, К-V8)

    /// Маршрут из чата в галерею и её ручки на порту 47615 (К-V1, К-V2, К-V7, К-V8). Зовут из `start()`.
    func connectViewer() {
        htmlOpener.toViewer = { [weak self] request, done in
            guard let self = self else { return done(false) }
            self.viewerClient.accept(path: request.path, mode: request.mode, chat: request.chat, done: done)
        }
        // Снимок HTML и PDF для карточки файла в чате — у галереи (#10603), без её запуска; нет — QuickLook.
        htmlOpener.viewerThumb = { [weak self] path, done in
            guard let self = self else { return done(nil) }
            self.viewerClient.thumb(path: path, done: done)
        }
        // «Галерея» отвечает странице словом исхода (#9631); нет контроллера — молчать нельзя, `silent`.
        htmlOpener.onViewer = { [weak self] request, reply in
            guard let self = self else { return reply(ViewerClient.GalleryOutcome.silent.rawValue) }
            self.viewerClient.gallery(chat: request.chat, on: request.on) { reply($0.rawValue) }
        }
        htmlOpener.onNudge = { [weak self] chat, counts in self?.sendViewerState(chat: chat, counts: counts) }
        htmlOpener.onDockOff = { [weak self] in DispatchQueue.main.async { self?.sendDockOff() } }
        // «в чат» из галереи: индекс и окна — на главной, ответ галерее — после работы.
        htmlOpener.onOpenChat = { [weak self] chat, reply in
            DispatchQueue.main.async {
                guard let self = self, let chat = chat else { return reply("chat-closed") }
                reply(self.viewerOpenChat(chat) ?? "ok")
            }
        }
        viewerClient.onMissing = { [weak self] in
            DispatchQueue.main.async { self?.hud.show("🖼 Галерея не установлена", seconds: 2.5) }
        }
        // Странице уже ответили «запускаю», а галерея так и не открылась (#9631) — HUD, а не тишина.
        viewerClient.onGalleryLate = { [weak self] outcome in
            DispatchQueue.main.async { self?.hud.show(Self.galleryLateText(outcome), seconds: 3) }
        }
        connectFileView()
        viewerClient.start()
    }

    /// Плашка HUD, когда после «запускаю» галерея не открылась (#9631). Чистая, её гоняют тесты.
    static func galleryLateText(_ outcome: ViewerClient.GalleryOutcome) -> String {
        switch outcome {
        case .noWindow: return "🖼 Галерея запустилась, но окна не показала"
        case .missing: return "🖼 Галерея не установлена"
        case .foreign: return "🖼 Галерея не открылась: порт 47616 занят другой программой"
        case .noToken: return "🖼 Галерея не открылась: нет ключа канала — перезапусти PimpViewer"
        case .refused: return "🖼 Галерея не открылась: PimpViewer отказал"
        case .silent, .opened, .off, .launching: return "🖼 Галерея не открылась: PimpViewer не отвечает"
        }
    }

    /// `/state` галереи → страницам `viewer-chat` (К-V2) и/или `viewer-counts` (К-V7). Запрос — на очереди
    /// клиента, запись команды — на главной: у `CommandChannel` нет замка.
    func sendViewerState(chat: Bool, counts: Bool, completion: ((Bool) -> Void)? = nil) {
        viewerClient.state { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self, let state = state else { completion?(false); return }
                if chat {
                    _ = self.commands.write(action: "viewer-chat", fields: [
                        (key: "scope", value: .string("all")),
                        (key: "chat", value: state.filterChat.map { .string($0) } ?? .null)])
                }
                if counts {
                    let value = CommandValue.object(state.counts.sorted { $0.key < $1.key }.map {
                        (key: $0.key, value: CommandValue.array($0.value.map { .number($0) }))
                    })
                    _ = self.commands.write(action: "viewer-counts", fields: [
                        (key: "scope", value: .string("all")), (key: "chats", value: value)], completion: completion)
                } else { completion?(true) }
            }
        }
    }

    /// ✕ в PimpViewer (#11224): команда страницы `dock {on:false, only:"owner"}` — во все страницы, закрывает только
    /// главное окно, где панель стоит (`dockLeave`), как нажатие «PMP». Запись — на главной.
    func sendDockOff() { Self.writeDockOff(commands) }

    @discardableResult
    static func writeDockOff(_ commands: CommandChannel) -> Bool {
        commands.write(action: "dock", fields: [
            (key: "scope", value: .string("all")), (key: "on", value: .bool(false)), (key: "only", value: .string("owner"))])
    }

    /// Число токенов остывшего чата (WF106 #8103) → страницам `chat-context`. Зовут на очереди порта: индекс —
    /// берётся из опубликованного снимка, расшифровка — на фоне, запись команды — на главной.
    func sendChatContext(_ chat: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self,
                  let cli = self.knownChat(chat)?.cli,
                  let tokens = ChatContext.tokens(cliSessionId: cli) else { return }
            DispatchQueue.main.async { ChatContext.send(chat: chat, tokens: tokens, via: self.commands) }
        }
    }

    /// HTTP readers use the latest index snapshot; UI work remains on main.
    private func connectFileView() {
        refreshChatLookup()
        htmlOpener.isKnownChat = { [weak self] chat in self?.knownChat(chat) != nil }
        htmlOpener.onView = { [weak self] request in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let cwd = request.chat.flatMap { self.index.session(for: $0) }?.cwd.path
                self.fileView.show(request, cwd: cwd)
            }
        }
        fileView.onReturn = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self = self, let pid = self.app.pid else { return }
                let windows = frame == nil ? [] : self.app.visibleWindows()
                guard let frame = frame, let best = FileView.nearest(frame, among: windows.map { AX.frame($0) }) else {
                    self.app.activate()
                    return
                }
                let window = windows[best]
                self.app.focus(window: window)
                // Activation may raise the previous key window. Retry once without blocking
                // the main queue, and only while this process and AX window still exist.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self = self, self.app.pid == pid,
                          AX.value(window, kAXRoleAttribute) != nil else { return }
                    self.app.forgetWindows()
                    guard self.app.windows().contains(where: { CFEqual($0, window) }) else { return }
                    self.app.focus(window: window)
                }
            }
        }
        // «в галерею»: `click` — галерея раскрывает карточку и выходит вперёд; не взяла — браузер.
        fileView.toGallery = { [weak self] path, chat in
            guard let self = self else { return }
            let request = HtmlChromeOpener.Request(path: path, mode: .click, chat: chat)
            guard let toViewer = self.htmlOpener.toViewer else { return self.htmlOpener.openInBrowser(path) }
            toViewer(request) { [weak self] taken in
                if !taken { self?.htmlOpener.openInBrowser(path) }
            }
        }
        fileView.toBrowser = { [weak self] path in self?.htmlOpener.openInBrowser(path) }
    }

    /// «🖼 Pimp Viewer» из панели у часов: окно галереи вперёд; приложения нет — плашка.
    public func showViewer() {
        viewerClient.show()
    }

    /// «в чат» из Viewer: окно чата открыто — вперёд; нет — вынести тем же путём, что
    /// `pimp.py open --last` (главное окно выносит чат отдельным окном).
    private func viewerOpenChat(_ chat: String) -> String? {
        guard app.running() != nil else { return "chat-closed" }
        let windows = pimp.seats.windows()
        if let open = PimpChannel.window(chat: chat, title: pimpTitle(forChat: chat), in: windows) {
            actions.raise(id: open.id)
            return nil
        }
        guard let session = index.session(for: chat), !session.isArchived,
              windows.contains(where: { $0.isMain(using: actions.isMainWindowTitle) }) else { return "chat-closed" }
        pimp.seats.openChat(chat, session.title, PimpChannel.popoutOrigin(.right, near: windows.first?.frame))
        return nil
    }
}
