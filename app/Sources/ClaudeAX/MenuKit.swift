import AppKit

/// Общие куски меню, оставшиеся от меню жёлтой кнопки (снято в WF237, #9524, лист 48 — ответ 2.1): ожидание
/// активности перед `popUp` (меню голосов Диктатора, меню файла) и признак полноэкранного окна.
enum MenuKit {
    /// AX-атрибут полноэкранного окна.
    static let fullScreenAttribute = "AXFullScreen"

    // MARK: - активность перед popUp (#5797)

    /// Сколько ждём активность после `activate`. Живьём она приезжает за десятки миллисекунд;
    /// не приехала за это время — не приедет вовсе, и лишняя пауза перед меню хуже попытки.
    static let activateWait: TimeInterval = 0.3
    /// Шаг ожидания: столько ждём одно событие за заход.
    static let activateStep: TimeInterval = 0.02

    /// Дождаться, пока приложение ПРАВДА станет активным. Чистая — её и гоняют тесты:
    /// `isActive` спрашивает состояние, `pump` даёт AppKit ход (живьём — разбор одного
    /// события главной очереди), `now` — часы. Отвечает, дождались ли.
    @discardableResult
    static func awaitActive(isActive: () -> Bool, pump: () -> Void, now: () -> TimeInterval,
                            timeout: TimeInterval = activateWait) -> Bool {
        let deadline = now() + timeout
        while !isActive() {
            guard now() < deadline else { return false }
            pump()
        }
        return true
    }

    /// Один шаг ожидания живьём: берём событие из очереди и отдаём его AppKit — тем же путём,
    /// каким его разобрал бы главный цикл. Без этого активация так и лежала бы в очереди,
    /// пока мы стоим на `popUp`. Событий нет — ждём до `activateStep` и выходим.
    static func pumpEvent() {
        let until = Date().addingTimeInterval(activateStep)
        guard let event = NSApp.nextEvent(matching: .any, until: until, inMode: .default,
                                          dequeue: true) else { return }
        NSApp.sendEvent(event)
    }
}

/// Прежнее имя для файлов вне батча WF237 (`FileView`, `MicMonitor`, `ChatGPTWindows`): их правку
/// на `MenuKit` делает гейт, тогда строка уходит.
typealias MinimizeMenu = MenuKit

/// NSMenuItem с замыканием: цели-селекторы здесь только мешают.
class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) не используется") }

    @objc private func fire() { handler() }
}
