import AppKit
import ApplicationServices

/// Семь действий меню и хоткеев — порт `claude_minimize_menu.lua`.
/// Страничные (`collapse`, `expand`, `scroll`, `cashout`) уходят в command.json,
/// оконные (`newChat`, `arrange`, `show`) делаются нативно.
final class ClaudeActions {
    /// Фокус → команда: страница отвечает только когда `document.hasFocus()`.
    let focusDelay: TimeInterval = 0.1
    /// «Обкэшить» → ⌘N: лоадер опрашивает command.json раз в 500 мс (fs.watchFile interval),
    /// плюс IPC до страницы — ⌘N раньше 1,2 с открыл бы новый чат до того, как старый отложил ответ.
    let cashoutNewChatDelay: TimeInterval = 1.2

    private let app: ClaudeApp
    private let commands: CommandChannel

    init(app: ClaudeApp, commands: CommandChannel) {
        self.app = app
        self.commands = commands
    }

    var lastCommand: String { commands.lastCommand }

    /// Окно, на которое действует хоткей: окно Claude в фокусе (хоткеи живут, только пока
    /// Claude впереди).
    func focusedWindow() -> AXUIElement? { app.focusedWindow() }

    func perform(_ command: ClaudeCommand, on window: AXUIElement?) {
        let target = window ?? focusedWindow()
        switch command {
        case .cashout: cashout(target)
        case .newChat: newChat(target)
        case .collapse: stage("collapse", target)
        case .expand: stage("expand", target)
        case .arrange: arrange()
        case .show: showAll(target)
        // «Прокрутить» адресована всем окнам сразу — фокус не нужен.
        case .scroll: commands.write(action: "scroll")
        }
    }

    // MARK: - страничные команды

    private func stage(_ action: String, _ window: AXUIElement?) {
        guard let window = window else { return }
        app.focus(window: window)
        after(focusDelay) { [weak self] in self?.commands.write(action: action) }
    }

    private func cashout(_ window: AXUIElement?) {
        guard let window = window else { return }
        app.focus(window: window)
        after(focusDelay) { [weak self] in
            guard let self = self else { return }
            // Заголовок нужен, чтобы страница поняла «это я»: окно «Open in new window»
            // (about:blank) может не считать себя в фокусе (грабли 03.09).
            let title = AX.string(window, kAXTitleAttribute) ?? ""
            self.commands.write(action: "cashout", extra: ["title": title])
            self.after(self.cashoutNewChatDelay) { self.newChat(window) }
        }
    }

    // MARK: - оконные команды

    /// ⌘N — штатная клавиша самого Claude, посылаем её в окно (focus асинхронный, отсюда задержка).
    private func newChat(_ window: AXUIElement?) {
        if let window = window { app.focus(window: window) }
        after(focusDelay) { [weak self] in
            guard let key = KeySpec(mods: [.command], name: "n").keyCode else { return }
            self?.app.postKey(CGKeyCode(key), flags: .maskCommand)
        }
    }

    /// Ровная сетка по главному экрану. Порядок окон сохраняется (см. ArrangeLayout.order).
    /// Свёрнутые и спрятанные не трогаем; чужие приложения — тоже (в отличие от ElvisOS).
    func arrange() {
        let windows = app.visibleWindows()
        guard !windows.isEmpty, let area = Screens.mainUsableFrame else { return }
        let frames = windows.map { AX.frame($0) ?? .zero }
        let order = ArrangeLayout.order(of: frames)
        let cells = ArrangeLayout.frames(count: order.count, in: area)
        for (index, windowIndex) in order.enumerated() {
            let cell = cells[index]
            let window = windows[windowIndex]
            AX.set(window, kAXPositionAttribute, point: cell.origin)
            AX.set(window, kAXSizeAttribute, size: cell.size)
        }
        onWindowsMoved?()
    }

    /// Все окна Claude вперёд, потом фокус обратно тому, из которого пришли.
    func showAll(_ window: AXUIElement?) {
        guard let running = app.running() else { return }
        running.activate(options: [.activateAllWindows])
        for candidate in app.visibleWindows() { AX.perform(candidate, kAXRaiseAction) }
        guard let window = window else { return }
        // activate/raise асинхронные — даём им тик, прежде чем забрать фокус назад.
        after(focusDelay) { [weak self] in self?.app.focus(window: window) }
    }

    /// Окна переехали: кэш прямоугольников кнопки «Свернуть» протух.
    var onWindowsMoved: (() -> Void)?

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}
