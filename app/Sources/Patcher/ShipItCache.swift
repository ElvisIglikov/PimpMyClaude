import Foundation

// Закачки встроенного обновлятора Claude (#10568). Squirrel Claude раз в час находит новую версию, качает её
// (~0,4 ГБ) в `~/Library/Caches/com.anthropic.claudefordesktop.ShipIt/update.XXXXXXX` и отказывает: подпись
// пропатченного Claude — не Anthropic (DECISIONS, «Патч блокирует автообновление»). Пока патч стоит, папка закачки —
// только для чтения: Squirrel не может завести в ней временную папку и отказывает сразу, ничего не скачав (проверено
// 22.10.2026 14:06: «Could not create temporary directory», в ту же секунду). Claude обновляет сам Пимп; патч снят —
// права обратно, и встроенный обновлятор снова работает.
public enum ShipItCache {
    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.anthropic.claudefordesktop.ShipIt", isDirectory: true)
    }
    static let locked: Int = 0o555
    static let open: Int = 0o755

    /// Патч стоит — папка только для чтения (нет её — заводим); снят — права обратно, если стоят наши. Ответ —
    /// поменялись ли права.
    @discardableResult
    public static func hold(patched: Bool, folder: URL = folder, fileManager: FileManager = .default) -> Bool {
        let path = folder.path
        var mode = ((try? fileManager.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber)?.intValue
        if patched {
            if mode == nil {
                guard (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return false }
                mode = open
            }
            guard let now = mode, now & 0o777 != locked else { return false }
            return (try? fileManager.setAttributes([.posixPermissions: locked], ofItemAtPath: path)) != nil
        }
        guard let now = mode, now & 0o777 == locked else { return false }
        return (try? fileManager.setAttributes([.posixPermissions: open], ofItemAtPath: path)) != nil
    }
}
