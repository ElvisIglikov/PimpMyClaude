import Foundation

// Строки журналов Claude Code `~/.claude/projects/**/*.jsonl` с расходом токенов — для «Цены Workflow» (#6282,
// `WorkflowCost`). Вынесено из статистики режимов работы (#10225), когда режимы сняли (слово Элвиса 22.10.2026:
// «Да вообще убирай, выпиливай эту фишку»).

/// Одна строка журнала Claude Code с расходом: `type == "assistant"`, `message.id`, `message.usage`, `timestamp`.
/// Отдельной чистой функцией — ею считает «Цена Workflow» (#6282).
public struct ClaudeUsageLine: Equatable {
    public let id: String
    public let at: Date
    public let model: String
    public let input: Int
    public let cacheCreate: Int
    public let cacheRead: Int
    public let output: Int
    /// Цена Workflow (#6282): из записи кэша — на 1 ч (`cache_creation.ephemeral_1h_input_tokens`), быстрый режим
    /// (`speed == "fast"`), данные в США (`inference_geo == "us"`).
    public var cacheWrite1h = 0
    public var fast = false
    public var usGeo = false

    /// Токены как у Рика: вход + запись кэша + чтение кэша + выход.
    public var total: Int { input + cacheCreate + cacheRead + output }

    public static func parse(_ line: Data) -> ClaudeUsageLine? {
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              record["type"] as? String == "assistant",
              let raw = record["timestamp"] as? String, let at = ClaudeUsage.date(raw),
              let message = record["message"] as? [String: Any],
              let id = message["id"] as? String, !id.isEmpty,
              let usage = message["usage"] as? [String: Any] else { return nil }
        func number(_ key: String) -> Int { max(0, (usage[key] as? NSNumber)?.intValue ?? 0) }
        var line = ClaudeUsageLine(id: id, at: at, model: message["model"] as? String ?? "",
                                   input: number("input_tokens"), cacheCreate: number("cache_creation_input_tokens"),
                                   cacheRead: number("cache_read_input_tokens"), output: number("output_tokens"))
        let hour = (usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"] as? NSNumber
        line.cacheWrite1h = max(0, hour?.intValue ?? 0)
        line.fast = usage["speed"] as? String == "fast"
        line.usGeo = usage["inference_geo"] as? String == "us"
        return line
    }
}

public enum ClaudeUsage {
    private static let isoMillis: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()
    private static let isoPlain = ISO8601DateFormatter()

    /// ISO 8601 с миллисекундами или без.
    public static func date(_ raw: String) -> Date? { isoMillis.date(from: raw) ?? isoPlain.date(from: raw) }

    private static let usageKey = Array("\"usage\"".utf8)
    private static let assistantKey = Array("\"assistant\"".utf8)

    /// Строки файла с `"usage"` и `"assistant"` → разбор; остальные даже не разбираем. Один `message.id` — строка с самым поздним `timestamp`.
    static func read(_ url: URL, since: Date, into byId: inout [String: ClaudeUsageLine]) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return }
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var start = 0
            let count = buffer.count
            while start < count {
                let rest = count - start
                let found = memchr(base + start, Int32(UInt8(ascii: "\n")), rest)
                let end = found.map { base.distance(to: UnsafeRawPointer($0)) } ?? count
                let length = end - start
                if length > 0, contains(base + start, length, usageKey), contains(base + start, length, assistantKey),
                   let line = ClaudeUsageLine.parse(Data(bytes: base + start, count: length)), line.at >= since {
                    if byId[line.id].map({ $0.at <= line.at }) ?? true { byId[line.id] = line }
                }
                start = end + 1
            }
        }
    }

    private static func contains(_ pointer: UnsafeRawPointer, _ length: Int, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { memmem(pointer, length, $0.baseAddress, needle.count) != nil }
    }
}
