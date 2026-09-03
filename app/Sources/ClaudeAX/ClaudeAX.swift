import Foundation

/// Контракт между AX-модулем (батч B) и приложением (батч A/C). Менять только по согласованию на гейте.
public enum ClaudeCommand: String, CaseIterable {
    /// `workflow` — первый пункт меню (решение 3 плана WF9): кладёт комплект воркфлоу
    /// в Application Support и вставляет текст кикоффа в поле ввода окна.
    case workflow, cashout, newChat, collapse, expand, arrange, show, scroll
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

// Реализация — ClaudeAXController.swift.
