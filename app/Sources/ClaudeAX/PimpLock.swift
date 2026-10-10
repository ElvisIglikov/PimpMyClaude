import Foundation

/// Shared bounded timeout for reading Electron AX titles (ContinueWatch).
enum PimpLock {
    /// Срок ответа окну Claude на чтение заголовка: опрос идёт в главном потоке, зависший
    /// Electron не должен его вешать.
    static let titleTimeout: Float = 0.25
}
