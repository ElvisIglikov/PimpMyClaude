import Foundation

/// Сроки, оставшиеся от пустого окна проекта (план WF88, К17). Сам движок — пункт Claude
/// File ▸ «New Session in New Window», приём черновика «Code» и команда `draft-setup` — снят
/// в WF248 (меню ⌘B ушло в WF220, вызовов не осталось). Живы только общие сроки: опрос
/// «Обкэшить», прогрев «Нового окна» и поиск пункта в меню Claude (`pressClaudeSettings`).
enum BlankWindow {
    /// Шаг опроса цепочек ожидания (`ClaudeActions.whenCashoutIdle`).
    static let pollSeconds: TimeInterval = 0.25
    /// Потолок поиска пункта по часам и срок AX на каждый элемент (правка критика V-N п. 11).
    static let searchSeconds: TimeInterval = 1
    static let axTimeout: Float = 0.25
    /// Прогрев «Нового окна» моложе этого — чужая цепочка ещё может родить окно «Code»
    /// (правка критика V-N п. 3): канал новое окно из меню не начинает (`newWindowBusy`).
    static let newWindowQuietSeconds: TimeInterval = 40
}
