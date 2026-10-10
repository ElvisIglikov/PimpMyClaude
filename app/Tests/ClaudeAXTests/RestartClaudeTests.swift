import CoreGraphics
import XCTest
@testable import ClaudeAX

/// «Перезапусти Claude» (WF108, #8176): канал `restart-claude` по эталонам
/// `tests/fixtures/pimp/restart-claude*.json`. Перезапуск подменён сиденьем — настоящий Claude
/// тест не трогает; автовозврат снимка К5 изображает прямой вызов `startRestore(snapshot:)`.
final class RestartClaudeTests: XCTestCase {
    private static let rick = "local_5265171a-0ab8-4472-b4e5-40604a36ef6e"
    private static let trelvis = "local_7d0c9b52-2f3e-4f7e-9a51-0c6a1b2d3e4f"
    private static let chatA = "local_11111111-2222-4333-8444-555555555555"
    private static let chatB = "local_66666666-7777-4888-9999-aaaaaaaaaaaa"
    private static let lost = "local_bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: RestartClaudeTests.fixtures.appendingPathComponent(name))
    }

    private func fixtureText(_ name: String) throws -> String {
        try String(data: fixture(name), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Стенд: часы, окна, кто работает и перезапуск, ответ которого тест отдаёт сам.
    private final class Rig {
        var now: Date
        var running = true
        var windows: [PimpWindow] = [
            PimpWindow(id: 1, title: "Claude", chat: RestartClaudeTests.rick,
                       frame: CGRect(x: 0, y: 0, width: 800, height: 700)),
        ]
        var working: [(chat: String, name: String)]? = []
        var answered = false
        var demanded: [Date] = []
        var restarts = 0
        var restartDone: ((String?) -> Void)?
        var outcome: SnapshotOutcome = .pending
        var asked: [Date] = []
        var transcripts: URL?
        var sessions: [(chat: String, cli: String, name: String)]? = []
        var opened: [String] = []
        var notices: [String] = []
        private var nextID: CGWindowID = 10

        init(now: String) { self.now = PimpChannel.date(now)! }

        func at(_ text: String) { now = PimpChannel.date(text)! }

        /// Вынести чат окном: окно появляется сразу, кроме «потерянного» чата.
        func open(_ chat: String) {
            opened.append(chat)
            guard chat != RestartClaudeTests.lost else { return }
            nextID += 1
            windows.append(PimpWindow(id: nextID, title: chat, chat: chat,
                                      frame: CGRect(x: 800, y: 0, width: 400, height: 700)))
        }
    }

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("restart-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func channel(_ rig: Rig, in box: URL) -> PimpChannel {
        let channel = PimpChannel(directory: box, now: { rig.now })
        var seats = PimpSeats()
        seats.claudeRunning = { rig.running }
        seats.windows = { rig.windows }
        seats.isMainWindow = { $0 == "Claude" }
        seats.demandChats = { rig.demanded.append($0) }
        seats.chatsAnswered = { _ in rig.answered }
        seats.workingChats = { since in
            rig.asked.append(since)
            return rig.working
        }
        seats.transcriptsRoot = { rig.transcripts }
        seats.desktopSessions = { rig.sessions }
        seats.restartClaude = { done in
            rig.restarts += 1
            rig.restartDone = done
        }
        seats.snapshotOutcome = { rig.outcome }
        seats.openChat = { chat, _, _ in rig.open(chat) }
        seats.notice = { rig.notices.append($0) }
        channel.seats = seats
        channel.start()
        return channel
    }

    private func put(_ data: Data, id: String, in box: URL, at: Date) throws {
        let url = box.appendingPathComponent(id + ".json")
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: at], ofItemAtPath: url.path)
    }

    private func resultText(_ id: String, in box: URL) -> String? {
        (try? String(contentsOf: box.appendingPathComponent(id + ".result.json"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func result(_ id: String, in box: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: box.appendingPathComponent(id + ".result.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static let plain = "1790738400000-0801"
    private static let forced = "1790738410000-0802"

    /// Запрос без `force` из эталона, взятый каналом на 03:20:00.
    private func startPlain(_ rig: Rig, in box: URL) throws -> PimpChannel {
        let pimp = channel(rig, in: box)
        try put(fixture("restart-claude.request.json"), id: RestartClaudeTests.plain, in: box, at: rig.now)
        pimp.tick()
        return pimp
    }

    private func snapshot() -> WindowSnapshot {
        let frame = CGRect(x: 0, y: 0, width: 600, height: 700)
        return WindowSnapshot(at: PimpChannel.date("2026-09-30T03:20:01Z")!, claude: "1.0", windows: [
            SnapshotWindow(chat: LayoutsStore.mainChat, folder: "", title: "Claude", frame: frame, screen: ""),
            SnapshotWindow(chat: RestartClaudeTests.chatA, folder: "", title: "Чат А", frame: frame, screen: ""),
            SnapshotWindow(chat: RestartClaudeTests.chatB, folder: "", title: "Чат Б", frame: frame, screen: ""),
            SnapshotWindow(chat: RestartClaudeTests.lost, folder: "", title: "Дубли задач", frame: frame, screen: ""),
        ])
    }

    // MARK: - разбор

    func testParsesFixturesAndForceOnlyForRestart() throws {
        let plain = try XCTUnwrap(PimpRequest.parse(fixture("restart-claude.request.json")))
        XCTAssertEqual(plain.action, .restartClaude)
        XCTAssertEqual(plain.from, RestartClaudeTests.rick)
        XCTAssertFalse(plain.force)
        let forced = try XCTUnwrap(PimpRequest.parse(fixture("restart-claude-force.request.json")))
        XCTAssertTrue(forced.force)
        XCTAssertEqual(forced.from, "")
        let alien = try JSONSerialization.data(withJSONObject: [
            "id": "1-1", "at": "2026-09-30T03:20:00Z", "action": "windows", "from": "", "force": true])
        XCTAssertEqual(PimpRequest.parse(alien)?.force, false, "force — только у restart-claude")
    }

    // MARK: - занятость

    func testRefusesWhileAnotherChatIsAnswering() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.working = [(chat: RestartClaudeTests.rick, name: "Rick / Claude"),
                       (chat: RestartClaudeTests.trelvis, name: "TrelvisCom / Дубли задач")]
        let box = makeTemp()
        let pimp = try startPlain(rig, in: box)
        XCTAssertEqual(rig.demanded.count, 1, "сперва спрашиваем страницы")
        XCTAssertNil(resultText(RestartClaudeTests.plain, in: box), "ждём круг страниц")
        XCTAssertFalse(pimp.startRestore(snapshot: snapshot(), name: WindowSnapshotStore.restoreName),
                       "пока спрашиваем, возврат снимка не пускаем")
        rig.at("2026-09-30T03:20:02Z")
        rig.answered = true
        pimp.tick()
        XCTAssertEqual(resultText(RestartClaudeTests.plain, in: box),
                       try fixtureText("restart-claude-working.error.json"),
                       "позвавший чат (from) из списка выкинут, чужой назван")
        XCTAssertEqual(rig.restarts, 0, "Claude не трогали")
        XCTAssertFalse(pimp.isBusy)
    }

    func testCallerChatIsNotCountedAsWorking() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.working = [(chat: RestartClaudeTests.rick, name: "Rick / Claude")]
        rig.answered = true
        let box = makeTemp()
        _ = try startPlain(rig, in: box)
        XCTAssertEqual(rig.restarts, 1, "работает только сам позвавший — перезапускаем")
        XCTAssertNil(resultText(RestartClaudeTests.plain, in: box))
    }

    func testUnknownWorkRefusesAfterWait() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.working = nil
        let box = makeTemp()
        let pimp = try startPlain(rig, in: box)
        rig.at("2026-09-30T03:20:04Z")
        pimp.tick()
        XCTAssertNil(resultText(RestartClaudeTests.plain, in: box), "8 с ещё не вышли")
        rig.at("2026-09-30T03:20:08Z")
        pimp.tick()
        XCTAssertEqual(resultText(RestartClaudeTests.plain, in: box),
                       try fixtureText("restart-claude-unknown.error.json"))
        XCTAssertEqual(rig.restarts, 0)
    }

    func testNotRunningIsNoWindows() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.running = false
        let box = makeTemp()
        _ = try startPlain(rig, in: box)
        XCTAssertEqual(result(RestartClaudeTests.plain, in: box)?["error"] as? String, "no-windows")
        XCTAssertEqual(rig.restarts, 0)
    }

    // MARK: - force, отказ перезапуска и таймаут возврата

    func testForceSkipsQuestionAndReportsFailure() throws {
        let rig = Rig(now: "2026-09-30T03:20:10Z")
        rig.working = [(chat: RestartClaudeTests.trelvis, name: "TrelvisCom / Дубли задач")]
        let box = makeTemp()
        let pimp = channel(rig, in: box)
        try put(fixture("restart-claude-force.request.json"), id: RestartClaudeTests.forced, in: box, at: rig.now)
        pimp.tick()
        XCTAssertTrue(rig.demanded.isEmpty, "force страниц не спрашивает")
        XCTAssertEqual(rig.restarts, 1, "force обрывает работающие чаты — перезапуск сразу")
        rig.at("2026-09-30T03:20:42Z")
        rig.restartDone?("Claude не закрылся за 30 секунд. Закрой его сам (⌘Q) и повтори.")
        XCTAssertEqual(resultText(RestartClaudeTests.forced, in: box),
                       try fixtureText("restart-claude-failed.error.json"))
        XCTAssertFalse(pimp.isBusy)
    }

    func testRestoreTimeoutWhenSnapshotNeverSettles() throws {
        let rig = Rig(now: "2026-09-30T03:20:10Z")
        let box = makeTemp()
        let pimp = channel(rig, in: box)
        try put(fixture("restart-claude-force.request.json"), id: RestartClaudeTests.forced, in: box, at: rig.now)
        pimp.tick()
        rig.at("2026-09-30T03:20:42Z")
        rig.restartDone?(nil)
        rig.at("2026-09-30T03:22:50Z")
        pimp.tick()
        XCTAssertNil(resultText(RestartClaudeTests.forced, in: box), "130 с ещё не вышли")
        rig.at("2026-09-30T03:22:52Z")
        pimp.tick()
        XCTAssertEqual(resultText(RestartClaudeTests.forced, in: box),
                       try fixtureText("restart-claude-timeout.error.json"))
    }

    // MARK: - успех

    func testSuccessWaitsForRestoreAndNamesSkipped() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.answered = true
        let box = makeTemp()
        let pimp = try startPlain(rig, in: box)
        XCTAssertEqual(rig.restarts, 1)
        XCTAssertTrue(pimp.isBusy, "пока перезапуск, канал занят")
        // Чужой запрос в это время — `busy`.
        rig.at("2026-09-30T03:20:02Z")
        let other = try JSONSerialization.data(withJSONObject: [
            "id": "1790738402000-0901", "at": "2026-09-30T03:20:02Z", "action": "windows", "from": ""])
        try put(other, id: "1790738402000-0901", in: box, at: rig.now)
        pimp.tick()
        XCTAssertEqual(result("1790738402000-0901", in: box)?["error"] as? String, "busy")
        // Claude снова запущен — ждём возврат окон, ответа ещё нет.
        rig.at("2026-09-30T03:20:30Z")
        rig.restartDone?(nil)
        pimp.tick()
        XCTAssertNil(resultText(RestartClaudeTests.plain, in: box))
        // Снимок К5 увидел новый Claude и начал возврат: главное окно на месте, два чата
        // выносятся, «Дубли задач» не находится.
        rig.at("2026-09-30T03:20:40Z")
        XCTAssertTrue(pimp.startRestore(snapshot: snapshot(), name: WindowSnapshotStore.restoreName),
                      "возврат ради перезапуска канал пускает")
        rig.at("2026-09-30T03:20:42Z")
        pimp.tick()
        rig.at("2026-09-30T03:20:44Z")
        pimp.tick()
        XCTAssertNil(resultText(RestartClaudeTests.plain, in: box), "возврат ещё идёт")
        rig.at("2026-09-30T03:21:04Z")
        pimp.tick()
        XCTAssertEqual(rig.opened, [RestartClaudeTests.chatA, RestartClaudeTests.chatB, RestartClaudeTests.lost])
        XCTAssertEqual(resultText(RestartClaudeTests.plain, in: box),
                       try fixtureText("restart-claude.result.json"))
        XCTAssertEqual(rig.notices.count, 1, "плашка возврата осталась")
        XCTAssertFalse(pimp.isBusy)
    }

    func testNothingToRestoreAnswersZeros() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.answered = true
        let box = makeTemp()
        let pimp = try startPlain(rig, in: box)
        rig.at("2026-09-30T03:20:30Z")
        rig.restartDone?(nil)
        rig.outcome = .notNeeded
        pimp.tick()
        let answer = try XCTUnwrap(result(RestartClaudeTests.plain, in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["placed"] as? Int, 0)
        XCTAssertEqual(answer["opened"] as? Int, 0)
        XCTAssertEqual(answer["skipped"] as? [String], [])
    }

    // MARK: - гейт 2 WF108

    func testStaleMapIsUnknownWithoutAnswerAfterRequest() throws {
        // Карта страниц давностью до 180 с говорит «работает только сам» — а ответа ПОСЛЕ запроса нет.
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.working = [(chat: RestartClaudeTests.trelvis, name: "TrelvisCom / Дубли задач")]
        let box = makeTemp()
        let pimp = try startPlain(rig, in: box)
        rig.at("2026-09-30T03:20:08Z")
        pimp.tick()
        XCTAssertEqual(resultText(RestartClaudeTests.plain, in: box),
                       try fixtureText("restart-claude-unknown.error.json"),
                       "не дождались ответа после запроса — «не знаем», старую карту не берём")
        XCTAssertEqual(rig.restarts, 0)
        XCTAssertTrue(rig.asked.isEmpty, "старую карту даже не спрашивали")
    }

    func testWorkingIsAskedFromRequestTime() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.answered = true
        let box = makeTemp()
        _ = try startPlain(rig, in: box)
        XCTAssertEqual(rig.asked, [PimpChannel.date("2026-09-30T03:20:00Z")!],
                       "карта работы — только из ответа не раньше запроса")
        XCTAssertEqual(rig.restarts, 1)
    }

    /// Каталог транскриптов: `<папка>/<файл>` с временем правки `age` секунд до `now`.
    private func transcript(_ path: String, in root: URL, now: Date, age: TimeInterval) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    private static let rickCLI = "119e54ef-1250-465b-ab2b-50146dd26ece"
    private static let trelvisCLI = "293d3d00-1c4c-40b3-9203-a0be7ee1aeee"
    private static let terminalCLI = "7ce5a64d-f2b6-458e-af6a-ddfed881fdd2"

    private func transcriptRig() throws -> Rig {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.answered = true
        let root = makeTemp()
        rig.transcripts = root
        rig.sessions = [
            (chat: RestartClaudeTests.rick, cli: RestartClaudeTests.rickCLI, name: "Rick / Claude"),
            (chat: RestartClaudeTests.trelvis, cli: RestartClaudeTests.trelvisCLI, name: "TrelvisCom / Дубли задач"),
        ]
        // Свой чат пишет и сам, и субагентами — он не в счёт.
        try transcript("-Users-x-Rick/\(RestartClaudeTests.rickCLI).jsonl", in: root, now: rig.now, age: 1)
        try transcript("-Users-x-Rick/\(RestartClaudeTests.rickCLI)/subagents/workflows/wf_1/agent-a1.jsonl",
                       in: root, now: rig.now, age: 2)
        // Терминальный claude индексу Desktop неизвестен — перезапуск Claude его не трогает.
        try transcript("-Users-x-Vk/\(RestartClaudeTests.terminalCLI).jsonl", in: root, now: rig.now, age: 3)
        return rig
    }

    func testWindowlessChatWorkingByTranscriptRefuses() throws {
        let rig = try transcriptRig()
        // Оркестратор без окна молчит сам, пишут его субагенты (каталог <uuid>/…).
        try transcript("-Users-x-Trelvis/\(RestartClaudeTests.trelvisCLI)/subagents/agent-b2.jsonl",
                       in: rig.transcripts!, now: rig.now, age: 30)
        rig.answered = false
        let box = makeTemp()
        let pimp = try startPlain(rig, in: box)
        rig.at("2026-09-30T03:20:02Z")
        rig.answered = true
        pimp.tick()
        XCTAssertEqual(resultText(RestartClaudeTests.plain, in: box),
                       try fixtureText("restart-claude-working.error.json"),
                       "чат без окна, чей транскрипт свеж, — отказ с его именем")
        XCTAssertEqual(rig.restarts, 0)
    }

    func testOwnAndTerminalAndStaleTranscriptsDoNotBlock() throws {
        let rig = try transcriptRig()
        try transcript("-Users-x-Trelvis/\(RestartClaudeTests.trelvisCLI).jsonl",
                       in: rig.transcripts!, now: rig.now, age: 91)
        let box = makeTemp()
        _ = try startPlain(rig, in: box)
        XCTAssertNil(resultText(RestartClaudeTests.plain, in: box))
        XCTAssertEqual(rig.restarts, 1, "свой, терминальный и старый (91 с) транскрипты не мешают")
    }

    func testFreshTranscriptsWithoutIndexAreUnknown() throws {
        let rig = try transcriptRig()
        rig.sessions = nil
        let box = makeTemp()
        _ = try startPlain(rig, in: box)
        XCTAssertEqual(result(RestartClaudeTests.plain, in: box)?["error"] as? String, "working-unknown",
                       "свежие транскрипты есть, а сопоставить не с чем — не знаем")
        XCTAssertEqual(rig.restarts, 0)
    }

    func testFreshSessionsByPath() throws {
        let root = makeTemp()
        let now = PimpChannel.date("2026-09-30T03:20:00Z")!
        try transcript("a/AAAA-1.jsonl", in: root, now: now, age: 5)
        try transcript("a/bbbb-2/subagents/workflows/wf_x/journal.jsonl", in: root, now: now, age: 89)
        try transcript("a/cccc-3.jsonl", in: root, now: now, age: 120)
        try transcript("b/dddd-4/tool-results/x.txt", in: root, now: now, age: 1)
        XCTAssertEqual(PimpChannel.freshTranscriptSessions(root: root, at: now), ["aaaa-1", "bbbb-2"])
        XCTAssertEqual(PimpChannel.freshTranscriptSessions(root: root.appendingPathComponent("нет"), at: now), [])
    }

    func testSnapshotGaveUpIsNotSuccess() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.answered = true
        let box = makeTemp()
        let pimp = try startPlain(rig, in: box)
        rig.at("2026-09-30T03:20:30Z")
        rig.restartDone?(nil)
        pimp.tick()
        XCTAssertNil(resultText(RestartClaudeTests.plain, in: box))
        rig.at("2026-09-30T03:22:31Z")
        rig.outcome = .gaveUp(skipped: ["Чат А", "Чат Б", "Дубли задач"])
        pimp.tick()
        XCTAssertEqual(resultText(RestartClaudeTests.plain, in: box),
                       try fixtureText("restart-claude-gaveup.error.json"),
                       "снимок сдался — ответ не ok, чаты снимка названы")
        XCTAssertFalse(pimp.isBusy)
    }

    func testRestoreIsNotLetInWhileRelaunching() throws {
        let rig = Rig(now: "2026-09-30T03:20:00Z")
        rig.answered = true
        let box = makeTemp()
        let pimp = try startPlain(rig, in: box)
        XCTAssertEqual(rig.restarts, 1)
        XCTAssertFalse(pimp.startRestore(snapshot: snapshot(), name: WindowSnapshotStore.restoreName),
                       "Claude ещё закрывается и открывается — возврат снимка ждёт done(nil)")
        rig.at("2026-09-30T03:20:30Z")
        rig.restartDone?(nil)
        XCTAssertTrue(pimp.startRestore(snapshot: snapshot(), name: WindowSnapshotStore.restoreName))
    }
}
