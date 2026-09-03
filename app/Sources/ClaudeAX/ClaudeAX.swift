import Foundation

/// Контракт между AX-модулем (батч B) и приложением (батч A/C). Менять только по согласованию на гейте.
public enum ClaudeCommand: String, CaseIterable {
    case cashout, newChat, collapse, expand, arrange, show, scroll
}

public protocol ClaudeAXControlling: AnyObject {
    /// Запустить опрос окон Claude, авто-Allow, меню на кнопке «Свернуть», хоткеи, блок ⌘Q.
    func start()
    func stop()
    var autoAllowEnabled: Bool { get set }
    var minimizeMenuEnabled: Bool { get set }
    var blockQuitEnabled: Bool { get set }
    /// Отправить команду во все окна Claude (пишет command.json в Application Support/MyClaude).
    func send(_ command: ClaudeCommand)
}

/// Заглушка скелета. Батч B заменяет реализацию.
public final class ClaudeAXController: ClaudeAXControlling {
    public init() {}
    public func start() {}
    public func stop() {}
    public var autoAllowEnabled = true
    public var minimizeMenuEnabled = true
    public var blockQuitEnabled = true
    public func send(_ command: ClaudeCommand) {}
}
