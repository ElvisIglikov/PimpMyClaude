import Foundation
import Patcher

/// Живой `claude.json` одним местом (ревизия WF247, С5а): путь — одна константа, файл читается и разбирается заново
/// только когда сменился (mtime, размер, номер файла), в остальное время — из памяти. Его зовут тик контроллера
/// (`mainProject`, корень доверия — раз в 2 с), повторы setFrame (`minWindowWidth`), канал и панель. Пишут файл
/// по-прежнему merge-записью свои хозяева (`LiveStyle`, `RickKit`, `PageLookSettings`) — следующее чтение увидит новое.
enum LiveConfig {
    static var url: URL { CommandChannel.directory.appendingPathComponent(SupportFiles.configFileName) }

    /// Тело файла; нет или не читается — nil.
    static func data(at url: URL = LiveConfig.url) -> Data? { entry(url)?.data }

    /// Тело текстом (для merge-записи и разборщиков по строке).
    static func text(at url: URL = LiveConfig.url) -> String? {
        data(at: url).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Корневой объект; файл битый или не объект — nil.
    static func json(at url: URL = LiveConfig.url) -> [String: Any]? { entry(url)?.json }

    /// Числовой ключ; нет, не число или не конечное — nil (границы — у того, кто спрашивает).
    static func number(_ key: String, at url: URL = LiveConfig.url) -> Double? {
        guard let value = (json(at: url)?[key] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
        return value
    }

    /// Строковый ключ как есть; нет или не строка — nil.
    static func string(_ key: String, at url: URL = LiveConfig.url) -> String? {
        json(at: url)?[key] as? String
    }

    private struct FileStamp: Equatable {
        let modified: Date?
        let size: Int?
        let number: Int?
    }

    private struct Entry {
        let stamp: FileStamp
        let data: Data
        let json: [String: Any]?
    }

    private static var cache: [String: Entry] = [:]
    private static let lock = NSLock()

    private static func entry(_ url: URL) -> Entry? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        lock.lock()
        defer { lock.unlock() }
        guard let attributes = attributes else {
            cache[url.path] = nil
            return nil
        }
        let stamp = FileStamp(modified: attributes[.modificationDate] as? Date,
                              size: (attributes[.size] as? NSNumber)?.intValue,
                              number: (attributes[.systemFileNumber] as? NSNumber)?.intValue)
        if let hit = cache[url.path], hit.stamp == stamp { return hit }
        guard let data = try? Data(contentsOf: url) else {
            cache[url.path] = nil
            return nil
        }
        let fresh = Entry(stamp: stamp, data: data,
                          json: (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
        cache[url.path] = fresh
        return fresh
    }
}
