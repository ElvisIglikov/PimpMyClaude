import Network
import XCTest
@testable import ClaudeAX

/// #9806 (WF262): суть длинного сообщения Элвиса — `POST /summary` порта 47615, начало текста (`lead`), кэш на диске,
/// ветка нейронки (провод без сети).
final class UserSummaryWF262Tests: XCTestCase {
    private var dir: URL!
    private let sha = String(repeating: "ab", count: 20)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("summary-wf262-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func store() -> UserSummary { UserSummary(url: dir.appendingPathComponent("summaries.json")) }

    private func head(_ method: String = "POST", path: String = "/summary", origin: String? = "https://claude.ai",
                      length: Int? = 10, extra: String = "") -> String {
        var text = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n"
        if let origin = origin { text += "Origin: \(origin)\r\n" }
        if let length = length { text += "Content-Length: \(length)\r\n" }
        return text + extra + "\r\n"
    }

    private func json(_ data: Data) throws -> (status: Int, head: String, body: [String: Any]) {
        let raw = String(decoding: data, as: UTF8.self)
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let status = Int(parts[0].split(separator: " ")[1]) ?? 0
        let body = parts[1].isEmpty ? [:] : try XCTUnwrap(JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any])
        return (status, parts[0], body)
    }

    // MARK: - начало текста

    func testLeadTakesOneOrTwoSentencesByBoundary() {
        XCTAssertEqual(UserSummary.lead("Сделай свёртку. Потом проверь тесты. И ещё третье."),
                       "Сделай свёртку. Потом проверь тесты.")
        let long = "Первое предложение довольно длинное, чтобы второе уже не влезало в сто восемьдесят знаков никак, "
            + "ну совсем никак, честно-честно говорю. Второе тоже длинное и вместе они точно больше лимита в сто восемьдесят."
        XCTAssertEqual(UserSummary.lead(long), String(long.prefix { $0 != "." }) + ".")
        XCTAssertEqual(UserSummary.lead("Версия 1.10.31 вышла, т.е. всё готово! Дальше?"),
                       "Версия 1.10.31 вышла, т.е. всё готово! Дальше?", "1.10.31 и «т.е. в» — не границы")
        XCTAssertEqual(UserSummary.lead("## Заголовок\n- пункт первый\n- пункт второй"), "Заголовок · пункт первый",
                       "строка — граница, маркеры сняты")
        XCTAssertEqual(UserSummary.lead("   \n\n"), "")
    }

    func testLeadCutsLongFirstSentenceByWordWithEllipsis() {
        let words = Array(repeating: "слово", count: 80).joined(separator: " ")
        let lead = UserSummary.lead(words)
        XCTAssertLessThanOrEqual(lead.count, UserSummary.leadLimit)
        XCTAssertTrue(lead.hasSuffix("слово…"), lead)
    }

    // MARK: - кэш

    func testLeadIsCachedOnDiskWith0600AndReused() throws {
        let first = store()
        first.now = { Date(timeIntervalSince1970: 1_790_000_000) }
        guard case .ready(let entry) = first.answer(hash: sha, text: "Раз. Два. Три.") else { return XCTFail() }
        XCTAssertEqual(entry.summary, "Раз. Два.")
        XCTAssertEqual(entry.kind, "lead")
        XCTAssertEqual(entry.at, "2026-09-21T14:13:20Z")
        let file = dir.appendingPathComponent("summaries.json")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        // Новый процесс читает с диска: другой текст под тем же hash — прежняя суть.
        XCTAssertEqual(store().answer(hash: sha, text: "Совсем другое."), .ready(entry))
    }

    func testCacheKeepsNewest500() throws {
        let summary = store()
        var clock = 1_790_000_000.0
        summary.now = { Date(timeIntervalSince1970: clock) }
        for n in 0..<501 {
            clock += 1
            _ = summary.answer(hash: String(format: "%040x", n), text: "Текст \(n).")
        }
        let file = dir.appendingPathComponent("summaries.json")
        let items = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])["items"]
        let keys = try XCTUnwrap(items as? [String: Any]).keys
        XCTAssertEqual(keys.count, UserSummary.maxEntries)
        XCTAssertFalse(keys.contains(String(format: "%040x", 0)), "самая старая выброшена")
        XCTAssertTrue(keys.contains(String(format: "%040x", 500)))
    }

    func testBrokenCacheFileIsIgnored() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "мусор".write(to: dir.appendingPathComponent("summaries.json"), atomically: true, encoding: .utf8)
        guard case .ready(let entry) = store().answer(hash: sha, text: "Живой текст.") else { return XCTFail() }
        XCTAssertEqual(entry.summary, "Живой текст.")
    }

    // MARK: - ветка нейронки

    func testAIProviderAnswersPendingThenAIAndFallsBackToLead() {
        let summary = store()
        XCTAssertEqual(summary.provider, .lead, "по умолчанию — начало текста")
        summary.provider = .claude
        guard case .ready(let plain) = summary.answer(hash: sha, text: "Без провода. Второе.") else { return XCTFail() }
        XCTAssertEqual(plain.kind, "lead", "ветки нет — работает lead")

        var calls = 0
        var reply: ((String?) -> Void)?
        summary.ai = { provider, _, done in
            XCTAssertEqual(provider, .claude)
            calls += 1
            reply = done
        }
        XCTAssertEqual(summary.answer(hash: sha, text: "Без провода. Второе."), .pending, "lead-запись другой ветки не годится")
        XCTAssertEqual(summary.answer(hash: sha, text: "Без провода. Второе."), .pending)
        XCTAssertEqual(calls, 1, "переспрос не зовёт нейронку второй раз")
        reply?("  Суть: попросил свёртку.  ")
        guard case .ready(let ai) = summary.answer(hash: sha, text: "x") else { return XCTFail() }
        XCTAssertEqual(ai.summary, "Суть: попросил свёртку.")
        XCTAssertEqual(ai.kind, "ai")

        let other = String(repeating: "cd", count: 20)
        summary.ai = { _, _, done in calls += 1; done(nil) }
        XCTAssertEqual(summary.answer(hash: other, text: "Не далась. Совсем."), .pending)
        guard case .ready(let fallback) = summary.answer(hash: other, text: "Не далась. Совсем.") else { return XCTFail() }
        XCTAssertEqual(fallback.kind, "lead", "не далась — начало текста")
        XCTAssertEqual(fallback.summary, "Не далась. Совсем.")
        XCTAssertEqual(calls, 2, "после неудачи нейронку не зовут на каждом опросе")
    }

    // MARK: - провайдер `claude` (CLI этого Мака; настоящий claude тест не зовёт)

    /// Подменный «claude»: аргументы — через \0 в `args`, stdin — в `stdin`, cwd и его содержимое — в `cwd`,
    /// дальше — `body` (ответ, сон, пустота).
    private func fakeClaude(_ body: String) throws -> String {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude")
        let out = dir.path
        try """
        #!/bin/sh
        printf '%s\\0' "$@" > '\(out)/args'
        cat > '\(out)/stdin'
        { pwd -P; ls -A | wc -l | tr -d ' '; } > '\(out)/cwd'
        \(body)
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    private func claude(_ path: String, timeout: TimeInterval = 10) -> ClaudeSummarizer {
        let claude = ClaudeSummarizer()
        claude.binary = { path }
        claude.timeout = timeout
        return claude
    }

    func testClaudeGetsExactArgumentsStdinAndEmptyTempCwd() throws {
        let path = try fakeClaude("echo '  Просит свернуть длинные сообщения в суть.  '")
        let text = "Длинная диктовка Элвиса.\nВторая строка — «кавычки», ёлки и \\ обратная черта."
        XCTAssertEqual(claude(path).run(text), "Просит свернуть длинные сообщения в суть.")
        let args = try String(contentsOf: dir.appendingPathComponent("args"), encoding: .utf8)
            .components(separatedBy: "\0").dropLast()
        XCTAssertEqual(Array(args), ["-p", "Сожми сообщение автора в 1–3 короткие строки: что он просит или сообщает, "
            + "его словами, без вступлений, оценок и кавычек. Только суть.", "--setting-sources", "", "--tools", "",
            "--model", "claude-opus-5-5", "--effort", "low", "--no-session-persistence"])
        XCTAssertFalse(args.contains("--bare"), "--bare без ключа API не входит")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("stdin"), encoding: .utf8), text, "текст — только stdin")
        let cwd = try String(contentsOf: dir.appendingPathComponent("cwd"), encoding: .utf8).split(separator: "\n")
        let temp = try XCTUnwrap(realpath(NSTemporaryDirectory(), nil).map { path in defer { free(path) }; return String(cString: path) })
        XCTAssertTrue(cwd[0].hasPrefix(temp + "/pimp-summary-"), "\(cwd[0]) не в \(temp)")
        XCTAssertEqual(cwd[1], "0", "папка пустая — CLAUDE.md неоткуда взять")
        XCTAssertFalse(FileManager.default.fileExists(atPath: String(cwd[0])), "папка убрана после вызова")
    }

    func testClaudeAnswerIsCutTo400AndEmptyOrFailureIsNil() throws {
        XCTAssertEqual(claude(try fakeClaude("printf 'я%.0s' $(seq 1 600)")).run("x")?.count, ClaudeSummarizer.maxSummary)
        XCTAssertNil(claude(try fakeClaude("printf '  \\n\\n'")).run("x"), "пусто — nil")
        XCTAssertNil(claude(try fakeClaude("echo 'Not logged in'; exit 1")).run("x"), "код не 0 — nil")
        XCTAssertNil(claude(dir.appendingPathComponent("нет-такого").path).run("x"))
        let none = ClaudeSummarizer()
        none.binary = { nil }
        XCTAssertNil(none.run("x"))
    }

    func testClaudeTimeoutKillsProcess() throws {
        let pidFile = dir.appendingPathComponent("pid").path
        let path = try fakeClaude("echo $$ > '\(pidFile)'; exec sleep 30")
        let started = Date()
        XCTAssertNil(claude(path, timeout: 3).run("x"), "первый запуск свежего скрипта macOS проверяет ~1 с — таймаут с запасом")
        XCTAssertLessThan(Date().timeIntervalSince(started), 8)
        let pid = try XCTUnwrap(Int32(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1, "процесс убит")
    }

    func testClaudeRunsOneAtATimeAndEmptyFallsBackToLead() throws {
        let log = dir.appendingPathComponent("log").path
        let path = try fakeClaude("echo start >> '\(log)'; sleep 0.3; echo end >> '\(log)'; cat '\(dir.path)/stdin'")
        let claude = claude(path)
        let both = expectation(description: "две сути")
        both.expectedFulfillmentCount = 2
        claude.summarize("Первая.") { _ in both.fulfill() }
        claude.summarize("Вторая.") { _ in both.fulfill() }
        wait(for: [both], timeout: 10)
        XCTAssertEqual(try String(contentsOfFile: log, encoding: .utf8), "start\nend\nstart\nend\n", "одна суть за раз")

        // Провод `onThisMac`: суть CLI — `ai`; CLI промолчал — начало текста.
        let summary = UserSummary.onThisMac(claude: claude)
        XCTAssertEqual(summary.provider, .claude)
        let file = dir.appendingPathComponent("summaries.json")
        let live = UserSummary(url: file)
        live.provider = summary.provider
        live.ai = summary.ai
        XCTAssertEqual(live.answer(hash: sha, text: "Сверни это. Длинно."), .pending)
        let ai = try waitReady(live, sha, "Сверни это. Длинно.")
        XCTAssertEqual(ai.kind, "ai")
        XCTAssertEqual(ai.summary, "Сверни это. Длинно.")
        claude.binary = { try? self.fakeClaude("true") }
        let other = String(repeating: "cd", count: 20)
        XCTAssertEqual(live.answer(hash: other, text: "Молчит. Совсем."), .pending)
        let lead = try waitReady(live, other, "Молчит. Совсем.")
        XCTAssertEqual(lead.kind, "lead")
        XCTAssertEqual(lead.summary, "Молчит. Совсем.")
    }

    private func waitReady(_ summary: UserSummary, _ hash: String, _ text: String) throws -> UserSummary.Entry {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if case .ready(let entry) = summary.answer(hash: hash, text: text) { return entry }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("суть не пришла за 10 с")
        throw CocoaError(.userCancelled)
    }

    func testFindTakesNewestDesktopVersionThenLocalThenPath() throws {
        let fm = FileManager.default
        let home = dir.appendingPathComponent("home").path
        func make(_ relative: String) throws -> String {
            let path = (home as NSString).appendingPathComponent(relative)
            try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
            return path
        }
        let bin = dir.appendingPathComponent("bin").path
        XCTAssertNil(ClaudeSummarizer.find(home: home, path: bin))
        try fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
        fm.createFile(atPath: bin + "/claude", contents: Data(), attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(ClaudeSummarizer.find(home: home, path: "relative:" + bin), bin + "/claude")
        let local = try make(".local/bin/claude")
        XCTAssertEqual(ClaudeSummarizer.find(home: home, path: bin), local)
        let app = "Library/Application Support/Claude/claude-code/"
        let tail = "/claude.app/Contents/MacOS/claude"
        _ = try make(app + "2.1.9/aaa" + tail)
        let newest = try make(app + "2.1.10/bbb" + tail)
        _ = try make(app + "2.1.286-beta/ccc" + tail)
        try fm.createDirectory(atPath: (home as NSString).appendingPathComponent(app + "2.1.300/ddd"), withIntermediateDirectories: true)
        XCTAssertEqual(ClaudeSummarizer.find(home: home, path: bin), newest, "2.1.10 > 2.1.9; не число и пустая папка — мимо")
    }

    // MARK: - заголовок и ответ ручки

    func testCheckSummaryAdmitsOnlyClaudePage() {
        XCTAssertTrue(HtmlChromeOpener.isSummary(head()))
        XCTAssertTrue(HtmlChromeOpener.isSummary(head("OPTIONS", length: nil)))
        XCTAssertFalse(HtmlChromeOpener.isSummary(head("GET", length: nil)))
        XCTAssertFalse(HtmlChromeOpener.isSummary(head(path: "/summaryx")))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head()), .post(length: 10))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head(origin: nil)), .reject(403), "без Origin — нет (токена у ручки нет)")
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head(origin: "https://evil.example")), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head(extra: "Origin: https://claude.ai\r\n")), .reject(403), "два Origin")
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head().replacingOccurrences(of: "127.0.0.1:47615", with: "evil:47615")),
                       .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head(length: nil)), .reject(400))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head(length: 0)), .reject(400))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head(extra: "Transfer-Encoding: chunked\r\n")), .reject(400))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head(length: 64 * 1024 + 1)), .reject(413))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head(length: 64 * 1024)), .post(length: 64 * 1024))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head("PUT")), .reject(405))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head("OPTIONS", length: nil,
            extra: "Access-Control-Request-Method: POST\r\nAccess-Control-Request-Headers: content-type\r\n")), .preflight)
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head("OPTIONS", length: nil,
            extra: "Access-Control-Request-Method: POST\r\n")), .preflight)
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head("OPTIONS", length: nil,
            extra: "Access-Control-Request-Method: POST\r\nAccess-Control-Request-Headers: content-type, x-evil\r\n")), .reject(403))
        XCTAssertEqual(HtmlChromeOpener.checkSummary(head("OPTIONS", length: nil,
            extra: "Access-Control-Request-Method: GET\r\n")), .reject(403))
        // Прежние ручки страницы тело по-прежнему не берут.
        XCTAssertEqual(HtmlChromeOpener.checkPage(head(path: "/summary"), token: nil), .reject(400))
    }

    func testReplyIsJSONWithCORSAndRejectsGarbage() throws {
        let opener = HtmlChromeOpener()
        opener.summaries = store()
        let body = try JSONSerialization.data(withJSONObject: ["hash": sha.uppercased(), "text": "Сверни. Длинно. Очень."])
        let ok = try json(opener.summaryReply(body))
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(ok.body["hash"] as? String, sha)
        XCTAssertEqual(ok.body["summary"] as? String, "Сверни. Длинно.")
        XCTAssertEqual(ok.body["kind"] as? String, "lead")
        XCTAssertNotNil(ok.body["at"] as? String)
        XCTAssertNil(ok.body["by"], "служебное поле кэша наружу не идёт")
        XCTAssertTrue(ok.head.contains("Access-Control-Allow-Origin: https://claude.ai"))
        XCTAssertTrue(ok.head.contains("Content-Type: application/json"))

        opener.summaries.provider = .claude
        opener.summaries.ai = { _, _, _ in }
        let other = String(repeating: "0", count: 40)
        let wait = try json(opener.summaryReply(JSONSerialization.data(withJSONObject: ["hash": other, "text": "Жди."])))
        XCTAssertEqual(wait.status, 202)
        XCTAssertEqual(wait.body["pending"] as? Bool, true)
        XCTAssertEqual(wait.body["hash"] as? String, other)

        for bad: [String: Any] in [["hash": "zz", "text": "x"], ["hash": sha], ["hash": sha, "text": "  "],
                                   ["hash": String(repeating: "g", count: 40), "text": "x"]] {
            XCTAssertEqual(try json(opener.summaryReply(JSONSerialization.data(withJSONObject: bad))).status, 400, "\(bad)")
        }
        XCTAssertEqual(try json(opener.summaryReply(Data("не json".utf8))).status, 400)

        let preflight = String(decoding: HtmlChromeOpener.summaryResponse(204, cors: true), as: UTF8.self)
        XCTAssertTrue(preflight.contains("Access-Control-Allow-Methods: POST"))
        XCTAssertTrue(preflight.contains("Access-Control-Allow-Headers: Content-Type"))
        XCTAssertTrue(preflight.contains("Access-Control-Allow-Private-Network: true"))
        XCTAssertFalse(String(decoding: HtmlChromeOpener.summaryResponse(403, cors: false), as: UTF8.self).contains("Access-Control"))
    }

    /// Живой сокет на свободном порту: заголовок и тело приходят кусками, тело дочитывается до `Content-Length`.
    func testSocketReadsBodyInPiecesAndAnswers() throws {
        let opener = HtmlChromeOpener()
        opener.summaries = store()
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { opener.serve($0) }
        let ready = expectation(description: "listener")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .global())
        wait(for: [ready], timeout: 5)
        defer { listener.cancel() }

        let body = Data(#"{"hash":"\#(sha)","text":"Первое. Второе. Третье."}"#.utf8)
        let client = NWConnection(host: "127.0.0.1", port: try XCTUnwrap(listener.port), using: .tcp)
        client.start(queue: .global())
        let head = "POST /summary HTTP/1.1\r\nHost: 127.0.0.1:47615\r\nOrigin: https://claude.ai\r\n"
            + "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n"
        client.send(content: Data(head.utf8) + body.prefix(7), completion: .idempotent)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            client.send(content: body.dropFirst(7), completion: .idempotent)
        }
        let answered = expectation(description: "answer")
        var reply = Data()
        func read() {
            client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, done, _ in
                if let data = data { reply += data }
                if done || data == nil { answered.fulfill() } else { read() }
            }
        }
        read()
        wait(for: [answered], timeout: 5)
        client.cancel()
        let answer = try json(reply)
        XCTAssertEqual(answer.status, 200)
        XCTAssertEqual(answer.body["summary"] as? String, "Первое. Второе.")
    }
}
