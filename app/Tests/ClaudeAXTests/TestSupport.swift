import Foundation
@testable import ClaudeAX

/// Настройки в памяти (`ThemeDefaults`): тесты не пишут в живые настройки приложения. Одна на весь набор —
/// вместо своей копии в каждом файле.
final class MemoryThemeDefaults: ThemeDefaults {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

/// Корень репозитория — от пути этого файла (`app/Tests/ClaudeAXTests/…`), чтобы тест не зависел от рабочего каталога.
enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Эталон или каталог эталонов `tests/fixtures/<path>`: `"pimp"`, `"cashout/probe-answer-popout.json"`.
    static func fixture(_ path: String) -> URL {
        root.appendingPathComponent("tests/fixtures/" + path)
    }
}
