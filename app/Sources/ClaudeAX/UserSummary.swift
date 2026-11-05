import Foundation
import Network

/// Суть длинного сообщения Элвиса в ленте чата (#9806, слово Элвиса 11.10.2026): страница сворачивает его текст
/// в короткую суть, нажал — раскрылся весь. Суть пишет `provider`: `lead` — первые 1–2 предложения (страница метит
/// её тихим «начало»); `claude` — Claude CLI на этом Маке (`ClaudeSummarizer`, слово Элвиса 17.10.2026 09:40),
/// в Пимпе он по умолчанию (`onThisMac`).
/// Кэш по sha1 текста — `~/Library/Application Support/MyClaude/summaries.json`, 0600, до 500 записей.
/// Контракт — `docs/CONTRACTS.md`, «#9806 `POST /summary`».
public final class UserSummary {
    enum Provider: String { case lead, claude }

    struct Entry: Codable, Equatable {
        var summary: String
        /// `lead` — начало текста, `ai` — пересказ нейронки.
        var kind: String
        /// Кем сделана (или кому не далась) запись: сменили `provider` — суть пересчитывается один раз.
        var by: String
        var at: String
    }

    enum Answer: Equatable {
        case ready(Entry)
        case pending
    }

    static let maxEntries = 500
    static let maxText = 20_000
    static let leadLimit = 180

    /// Единственная настройка выбора. Не `lead` без `ai` — работает `lead`.
    var provider: Provider = .lead
    /// Ветка нейронки: (provider, текст, ответ: суть или nil). Сети и ключа здесь нет; nil — ветки нет.
    var ai: ((Provider, String, @escaping (String?) -> Void) -> Void)?
    var now: () -> Date = Date.init

    let url: URL
    private var entries: [String: Entry]?
    private var pending: Set<String> = []
    private let lock = NSLock()

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyClaude/summaries.json")) {
        self.url = url
    }

    /// Суть Пимпа: Claude CLI этого Мака (`ClaudeSummarizer`, одна суть за раз). Нет CLI или не ответил — начало текста.
    static func onThisMac(claude: ClaudeSummarizer = ClaudeSummarizer()) -> UserSummary {
        let summary = UserSummary()
        summary.provider = .claude
        summary.ai = { _, text, done in claude.summarize(text, done: done) }
        return summary
    }

    /// Готовая суть сразу или «ждите» (нейронка думает; страница переспросит через 3 с).
    func answer(hash: String, text: String) -> Answer {
        lock.lock()
        let by = (provider == .lead || ai == nil) ? Provider.lead : provider
        if let entry = load()[hash], entry.by == by.rawValue { lock.unlock(); return .ready(entry) }
        guard by != .lead, let ai = ai else {
            defer { lock.unlock() }
            return .ready(store(hash, Self.lead(text), kind: "lead", by: by))
        }
        let start = pending.insert(hash).inserted
        lock.unlock()
        // Нейронку зовём вне замка: ответ может прийти и сразу.
        if start {
            ai(by, text) { [weak self] summary in
                guard let self = self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                self.pending.remove(hash)
                let clean = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // Не далась — начало текста с той же `by`: нейронку не зовём на каждом опросе.
                if clean.isEmpty { self.store(hash, Self.lead(text), kind: "lead", by: by) }
                else { self.store(hash, clean, kind: "ai", by: by) }
            }
        }
        return .pending
    }

    @discardableResult
    private func store(_ hash: String, _ summary: String, kind: String, by: Provider) -> Entry {
        let entry = Entry(summary: summary, kind: kind, by: by.rawValue, at: Self.stamp.string(from: now()))
        var all = load()
        all[hash] = entry
        if all.count > Self.maxEntries {
            let old = all.sorted { ($0.value.at, $0.key) < ($1.value.at, $1.key) }.prefix(all.count - Self.maxEntries)
            old.forEach { all[$0.key] = nil }
        }
        entries = all
        save(all)
        return entry
    }

    private struct File: Codable { var version = 1; var items: [String: Entry] }

    private func load() -> [String: Entry] {
        if let entries = entries { return entries }
        let loaded = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) }?.items ?? [:]
        entries = loaded
        return loaded
    }

    /// Временный рядом с 0600 → `rename`: файла с чужими правами нет ни миллисекунды (как `PimpChannel.writeSecure`).
    private func save(_ all: [String: Entry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(File(items: all)) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".tmp")
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        if rename(tmp.path, url.path) != 0 { try? fm.removeItem(at: tmp) }
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    // MARK: - начало текста (`lead`)

    /// Первые 1–2 предложения, не длиннее `limit` знаков, по границе предложения. Первое длиннее — режется по слову
    /// с «…». Граница — `.!?…` (с закрывающими кавычками и скобками) перед пробелом и НЕ строчной буквой
    /// («т.е. в» — не граница), и конец строки (пункты списка, абзацы). Маркеры `#`, `>`, `-`, `*`, `•` в начале строки
    /// снимаются; предложения без точки склеиваются через « · ».
    static func lead(_ text: String, limit: Int = leadLimit) -> String {
        var sentences: [String] = []
        for raw in text.prefix(maxText).split(whereSeparator: \.isNewline) {
            var line = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            while let first = line.first, "#>-*•".contains(first),
                  line.dropFirst().first.map({ $0 == " " || "#>".contains($0) }) ?? false {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            sentences += split(line)
            if sentences.count >= 2 { break }
        }
        guard let first = sentences.first else { return "" }
        if first.count > limit {
            var cut = String(first.prefix(limit - 1))
            if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
                cut = String(cut[..<space])
            }
            return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—–-")) + "…"
        }
        // Без точки в конце (заголовок, пункт списка) — разделитель « · ».
        let glue = first.last.map { ".!?…»\")”".contains($0) } == true ? " " : " · "
        if sentences.count > 1, first.count + glue.count + sentences[1].count <= limit { return first + glue + sentences[1] }
        return first
    }

    /// Строка без переводов → предложения.
    private static func split(_ line: String) -> [String] {
        let chars = Array(line)
        var out: [String] = []
        var start = 0, i = 0
        while i < chars.count {
            if ".!?…".contains(chars[i]) {
                var end = i + 1
                while end < chars.count, ".!?…»\")”".contains(chars[end]) { end += 1 }
                if end == chars.count || (chars[end] == " " && !(end + 1 < chars.count && chars[end + 1].isLowercase)) {
                    out.append(String(chars[start..<end]).trimmingCharacters(in: .whitespaces))
                    start = end
                }
                i = end
            } else {
                i += 1
            }
        }
        let tail = String(chars[min(start, chars.count)...]).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out.filter { !$0.isEmpty }
    }
}

// MARK: - ручка `POST /summary` порта 47615

extension HtmlChromeOpener {
    static let maxSummaryBody = 64 * 1024

    enum SummaryHead: Equatable {
        case reject(Int)
        case preflight
        case post(length: Int)
    }

    /// Строка запроса — `POST /summary` или `OPTIONS /summary` (тело дочитывает `serveSummary`).
    static func isSummary(_ head: String) -> Bool {
        let line = head.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
        return line.count >= 2 && ["POST", "OPTIONS"].contains(line[0])
            && URLComponents(string: "http://127.0.0.1" + line[1])?.path == "/summary"
    }

    /// Только страница Claude: Host этого порта, ровно Origin `https://claude.ai` (токена у ручки нет), без
    /// `Transfer-Encoding`, `Content-Length` 1…64 КБ. OPTIONS — предполёт POST с `Content-Type`.
    static func checkSummary(_ head: String) -> SummaryHead {
        guard let (parts, headers) = parseHead(head) else { return .reject(400) }
        guard loopbackHost(headers), headers["origin"] == ["https://claude.ai"] else { return .reject(403) }
        guard URLComponents(string: "http://127.0.0.1" + parts[1])?.path == "/summary" else { return .reject(404) }
        if parts[0] == "OPTIONS" {
            let asked = headers["access-control-request-headers"]?.joined(separator: ",").lowercased() ?? ""
            guard headers["access-control-request-method"] == ["POST"],
                  asked.split(separator: ",").allSatisfy({ $0.trimmingCharacters(in: .whitespaces) == "content-type" })
            else { return .reject(403) }
            return .preflight
        }
        guard parts[0] == "POST" else { return .reject(405) }
        guard headers["transfer-encoding"] == nil, let sizes = headers["content-length"], sizes.count == 1,
              let length = Int(sizes[0]), length > 0 else { return .reject(400) }
        return length > maxSummaryBody ? .reject(413) : .post(length: length)
    }

    /// Ответ ручки; CORS — только допущенной странице (`cors`), отказ заголовка — без него, как у `pageResponse`.
    static func summaryResponse(_ status: Int, _ body: [String: Any]? = nil, cors: Bool) -> Data {
        let json = body.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) } ?? Data()
        let reason = [200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"][status] ?? "Error"
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        if !json.isEmpty { response += "Content-Type: application/json; charset=utf-8\r\n" }
        if cors {
            response += "Access-Control-Allow-Origin: https://claude.ai\r\nVary: Origin\r\nAccess-Control-Allow-Methods: POST\r\n"
            response += "Access-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\n"
        }
        if status != 204 { response += "Content-Length: \(json.count)\r\n" }
        return Data((response + "Cache-Control: no-store\r\nConnection: close\r\n\r\n").utf8) + json
    }

    /// Тело `{"hash":"<sha1 hex>","text":"…"}` → `200 {hash,summary,kind,at}` или `202 {hash,pending:true}`;
    /// мусор — `400`. Текст длиннее 20 000 знаков берётся началом.
    func summaryReply(_ body: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let hash = (object["hash"] as? String)?.lowercased(), hash.count == 40,
              hash.allSatisfy({ $0.isHexDigit && $0.isASCII }),
              let text = object["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return Self.summaryResponse(400, cors: true) }
        switch summaries.answer(hash: hash, text: String(text.prefix(UserSummary.maxText))) {
        case .ready(let entry):
            return Self.summaryResponse(200, ["hash": hash, "summary": entry.summary, "kind": entry.kind, "at": entry.at],
                                        cors: true)
        case .pending:
            return Self.summaryResponse(202, ["hash": hash, "pending": true], cors: true)
        }
    }

    /// Сетевая обвязка: заголовок уже дочитан `receive`, тело дочитываем до `Content-Length` в те же 5 с.
    func serveSummary(_ bytes: Data, _ connection: NWConnection, timeout: DispatchWorkItem) {
        let send = { (data: Data) in
            timeout.cancel()
            connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
        }
        guard let end = bytes.range(of: Data("\r\n\r\n".utf8)) else { return send(Self.summaryResponse(400, cors: false)) }
        let head = String(decoding: bytes[..<end.upperBound], as: UTF8.self)
        switch Self.checkSummary(head) {
        case .reject(let status): send(Self.summaryResponse(status, cors: false))
        case .preflight: send(Self.summaryResponse(204, cors: true))
        case .post(let length):
            func read(_ body: Data) {
                if body.count >= length { return send(summaryReply(body.prefix(length))) }
                connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxSummaryBody) { data, _, done, error in
                    guard let data = data, !data.isEmpty, error == nil else {
                        return done || error != nil ? send(Self.summaryResponse(400, cors: true)) : read(body)
                    }
                    read(body + data)
                }
            }
            read(Data(bytes[end.upperBound...]))
        }
    }
}
