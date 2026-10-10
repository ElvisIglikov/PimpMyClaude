import Foundation

/// Сколько токенов перечитается, если отправить в остывший чат (WF106 #8103; слово Элвиса 29.09.2026:
/// «предупреждать… что там 400 000 контекста будет перечитано заново»).
///
/// Как `tools/pimp.py` (`transcript_tail`): расшифровка чата — `~/.claude/projects/*/<cliSessionId>.jsonl`
/// (несколько — самая свежая по mtime), читаем хвост 512 КБ, первую рваную строку отбрасываем. Берём
/// последний ответ ассистента основной ветки (не `isSidechain`, модель не `<synthetic>`, usage не нулевой):
/// `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. Читать — не на главной.
enum ChatContext {
    /// Команда страницам: `{"id":…, "action":"chat-context", "at":…, "chat":"local_…", "tokens":N}`.
    static let action = "chat-context"
    static let tailBytes = 512 * 1024
    static var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// Команда `chat-context` в очередь канала (обычная, FIFO). Звать на главной.
    @discardableResult
    static func send(chat: String, tokens: Int, via commands: CommandChannel) -> Bool {
        commands.write(action: action, fields: [(key: "chat", value: .string(chat)), (key: "tokens", value: .number(tokens))])
    }

    /// Число токенов контекста чата; нет расшифровки или ответа ассистента в хвосте — nil.
    static func tokens(cliSessionId: String, root: URL = projectsRoot) -> Int? {
        guard let file = transcript(cliSessionId: cliSessionId, root: root),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return nil }
        return tokens(inTail: data, truncated: start > 0)
    }

    /// Файл расшифровки: id — только буквы, цифры, дефис, подчёркивание (в glob чужого не подставить).
    static func transcript(cliSessionId id: String, root: URL) -> URL? {
        guard !id.isEmpty, id.count <= 128,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        let found = folders.compactMap { folder -> (URL, Date)? in
            let file = folder.appendingPathComponent(id + ".jsonl")
            guard let attributes = try? manager.attributesOfItem(atPath: file.path),
                  attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
            return (file, attributes[.modificationDate] as? Date ?? .distantPast)
        }
        return found.max { $0.1 < $1.1 }?.0
    }

    /// Хвост расшифровки → токены последнего ответа ассистента. `truncated` — хвост начат не с начала
    /// файла: первая строка рваная.
    static func tokens(inTail data: Data, truncated: Bool) -> Int? {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        if truncated, !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() {
            guard let record = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  record["type"] as? String == "assistant", record["isSidechain"] as? Bool != true,
                  let message = record["message"] as? [String: Any],
                  message["model"] as? String != "<synthetic>",
                  let usage = message["usage"] as? [String: Any] else { continue }
            let sum = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                .reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
            if sum > 0 { return sum }
        }
        return nil
    }
}
