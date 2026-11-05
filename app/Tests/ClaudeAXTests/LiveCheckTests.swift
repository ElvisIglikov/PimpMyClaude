import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Проверка окна после обновления Claude и самопроверка Пимпа (#10527, контракт К-HEALTH,
/// `docs/contracts/550-10527-health-live-check.md`). Эталоны — `tests/fixtures/live-check.json` и
/// `tests/fixtures/pimp/live-check*.json`: на них стоят и страница, и CLI.
final class LiveCheckTests: XCTestCase {
    // MARK: - песочница

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("live-check-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixtureText(_ name: String) throws -> String {
        try String(contentsOf: Repo.fixture(name), encoding: .utf8)
    }

    private func fixtureJSON(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Repo.fixture(name))) as? [String: Any])
    }

    /// Эталон без пробелов вне строк — порядок ключей сохраняется (сверка побайтно).
    private func minified(_ text: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        for char in text {
            if inString {
                out.append(char)
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == "\"" { inString = false }
            } else if char == "\"" {
                inString = true
                out.append(char)
            } else if !char.isWhitespace {
                out.append(char)
            }
        }
        return out
    }

    private func date(_ text: String) throws -> Date { try XCTUnwrap(LiveCheck.parseISO(text)) }

    /// Кольцо из 20 нажатий: два «открыл, а не видно», последнее такое — в 09:02:11Z.
    private func clicks() throws -> [LiveCheck.Click] {
        let lost = try date("2026-10-22T09:02:11Z")
        var list: [LiveCheck.Click] = []
        for index in 0..<18 {
            let even = index % 2 == 0
            list.append(LiveCheck.Click(at: lost.addingTimeInterval(TimeInterval(index - 100)),
                                        action: even ? "open" : "close", shown: even))
        }
        list.insert(LiveCheck.Click(at: lost.addingTimeInterval(-200), action: "open", shown: false), at: 3)
        list.append(LiveCheck.Click(at: lost, action: "open", shown: false))
        // Двадцать первое (старое) из кольца выпадает.
        return [LiveCheck.Click(at: lost.addingTimeInterval(-900), action: "open", shown: false)] + list
    }

    private let screen = LiveCheck.Screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                          left: CGRect(x: 0, y: 950, width: 662, height: 32),
                                          right: CGRect(x: 850, y: 950, width: 662, height: 32))

    // MARK: - нужна ли проверка

    func testNeedsCheckOnlyForNewVersion() {
        XCTAssertTrue(LiveCheck.needsCheck(installed: "3.1623.0", checked: nil), "ключа нет — проверить")
        XCTAssertTrue(LiveCheck.needsCheck(installed: "3.1623.0", checked: "2.42304.0"), "Claude обновился")
        XCTAssertFalse(LiveCheck.needsCheck(installed: "3.1623.0", checked: "3.1623.0"), "эту уже проверили")
        XCTAssertFalse(LiveCheck.needsCheck(installed: nil, checked: nil))
        XCTAssertFalse(LiveCheck.needsCheck(installed: "", checked: "3.1623.0"))
    }

    // MARK: - ручка канала на эталонах

    func testChannelAnswerMatchesFixture() throws {
        let box = makeTemp()
        let last = #"{"v":1,"at":"2026-10-22T08:52:31Z","by":"app","claude":"3.1623.0","pimp":"1.10.65","ok":true,"red":[],"pages":[],"unchecked":0,"app":null}"#
        try Data(last.utf8).write(to: box.appendingPathComponent(LiveCheck.lastFileName))
        let facts = LiveCheck.AppFacts(item: CGRect(x: 1200, y: 950, width: 40, height: 32), screens: [screen],
                                       statsOn: true, limitsKnown: true, iconNumber: true, clicks: try clicks())
        let app = LiveCheck.AppSection(version: "1.10.65", at: try date("2026-10-22T09:14:06.104Z"), claude: "3.1623.0",
                                       checked: "3.1623.0", checks: LiveCheck.appChecks(facts))
        let answer = PimpAnswer(id: "1792660445000-0527", at: try date("2026-10-22T09:14:06Z"), ok: true, fields: [
            (key: "app", value: app.value),
            (key: "last", value: LiveCheck.lastSummary(directory: box, timeZone: TimeZone(identifier: "UTC")!)),
        ])
        XCTAssertEqual(answer.json, try fixtureText("pimp/live-check.result.json").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testFirstChannelAnswerMatchesFixture() throws {
        let facts = LiveCheck.AppFacts(item: CGRect(x: 1200, y: 950, width: 40, height: 32), screens: [screen],
                                       statsOn: true, limitsKnown: false)
        let app = LiveCheck.AppSection(version: "1.10.65", at: try date("2026-10-22T09:14:06.104Z"), claude: "3.1623.0",
                                       checked: nil, checks: LiveCheck.appChecks(facts))
        let answer = PimpAnswer(id: "1792660445000-0528", at: try date("2026-10-22T09:14:06Z"), ok: true, fields: [
            (key: "app", value: app.value), (key: "last", value: LiveCheck.lastSummary(directory: makeTemp())),
        ])
        XCTAssertEqual(answer.json,
                       try fixtureText("pimp/live-check-first.result.json").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Канал отвечает на `live-check` и когда занят (как `hud`): это чтение своего процесса.
    func testChannelServesLiveCheck() throws {
        let box = makeTemp()
        // Часы канала — настоящие: файлы старше часа по времени правки канал убирает сам.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let stamp = PimpChannel.stampText(now)
        let channel = PimpChannel(directory: box, now: { now })
        var seats = PimpSeats()
        seats.liveCheck = { (app: .object([(key: "v", value: .number(1))]), last: .null) }
        channel.seats = seats
        channel.start()
        let request = try String(contentsOf: Repo.fixture("pimp/live-check.request.json"), encoding: .utf8)
        let fresh = request.replacingOccurrences(of: "2026-10-22T09:14:05Z", with: stamp)
        try Data(fresh.utf8).write(to: box.appendingPathComponent("1792660445000-0527.json"))
        channel.tick()
        let data = try Data(contentsOf: box.appendingPathComponent("1792660445000-0527.result.json"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                       #"{"id":"1792660445000-0527","at":""# + stamp
                        + #"","ok":true,"error":"","fromResolved":false,"screen":"windows","app":{"v":1},"last":null}"#)
        XCTAssertEqual(PimpRequest.parse(Data(request.utf8))?.action, .liveCheck)
    }

    // MARK: - проверки приложения

    func testStatusItemCheck() {
        let check = { (frame: CGRect?, screens: [LiveCheck.Screen]) in
            LiveCheck.appChecks(LiveCheck.AppFacts(item: frame, screens: screens))[0]
        }
        XCTAssertEqual(check(nil, [screen]), .red("statusItem", "no-item"))
        XCTAssertEqual(check(CGRect(x: 1200, y: 950, width: 0, height: 34), [screen]), .red("statusItem", "zero: 0×34"))
        XCTAssertEqual(check(CGRect(x: -900, y: 950, width: 40, height: 32), [screen]), .red("statusItem", "off-screen: -900,950"))
        XCTAssertEqual(check(CGRect(x: 700, y: 950, width: 40, height: 32), [screen]), .red("statusItem", "notch: 662–850"),
                       "значок за «бровью»")
        XCTAssertEqual(check(CGRect(x: 1200, y: 950, width: 40, height: 32), [screen]), .pass("statusItem"))
        XCTAssertEqual(check(CGRect(x: 500, y: 950, width: 40, height: 32), [LiveCheck.Screen(frame: screen.frame)]),
                       .pass("statusItem"), "экран без выреза — достаточно лежать на нём")
    }

    func testOtherAppChecks() throws {
        func checks(_ facts: LiveCheck.AppFacts) -> [LiveCheck.Check] { LiveCheck.appChecks(facts) }
        XCTAssertEqual(checks(.init()).map { $0.id }, ["statusItem", "iconNumber", "stripWindow", "clickLog", "panelOpaque"])
        XCTAssertEqual(checks(.init(statsOn: false))[1], .skipped("iconNumber", "stats-off"))
        XCTAssertEqual(checks(.init(statsOn: true, limitsKnown: true, iconNumber: false))[1], .red("iconNumber", "no-number"))
        XCTAssertEqual(checks(.init(strip: CGRect(x: 0, y: 0, width: 0, height: 34)))[2], .red("stripWindow", "zero: 0×34"),
                       "окно полосы 0×34 (#10471)")
        XCTAssertEqual(checks(.init(strip: CGRect(x: 0, y: 0, width: 180, height: 34)))[2], .pass("stripWindow"))
        XCTAssertEqual(checks(.init(clicks: [LiveCheck.Click(at: Date(), action: "open", shown: true),
                                             LiveCheck.Click(at: Date(), action: "close", shown: false),
                                             LiveCheck.Click(at: Date(), action: "open")]))[3], .pass("clickLog"),
                       "закрыл и не видно — правильно; ещё не смотрели — не красное")
        let lost = try clicks()
        XCTAssertEqual(checks(.init(clicks: lost))[3],
                       .red("clickLog", "open-invisible: 2 из 20", at: try date("2026-10-22T09:02:11Z")))
        XCTAssertEqual(checks(.init(panelOpen: true, panelAlpha: 0.94))[4], .red("panelOpaque", "alpha: 0.94"))
        XCTAssertEqual(checks(.init(panelOpen: true, backgroundAlpha: 0.94))[4], .red("panelOpaque", "background: альфа 0.94"),
                       "панель просвечивает (#9192)")
        XCTAssertEqual(checks(.init(panelOpen: true))[4], .pass("panelOpaque"))
        XCTAssertEqual(LiveCheck.ring(lost).count, LiveCheck.ringSize)
    }

    // MARK: - отчёт

    /// Отчёт по ответам страниц эталона — побайтно эталон `live-check.json` (порядок ключей контракта).
    func testReportMatchesFixture() throws {
        let fixture = try fixtureJSON("live-check.json")
        let pages = try XCTUnwrap(fixture["pages"] as? [[String: Any]])
        var answers = pages.map { LiveCheck.PageAnswer(id: ($0["id"] as? Int) ?? 0, url: "https://claude.ai/epitaxy", health: $0["health"]) }
        // Старая страница без `health()` и чужой артефакт: первая — в `unchecked`, вторая — мимо.
        answers.append(LiveCheck.PageAnswer(id: 9, url: "https://claude.ai/epitaxy/local_x", health: ["v": 0]))
        answers.append(LiveCheck.PageAnswer(id: 11, url: "https://example.com/", health: ["v": 0]))
        let app = LiveCheck.AppSection(version: "1.10.65", at: try date("2026-10-22T09:14:06.104Z"), claude: "3.1623.0",
                                       checked: "3.1623.0", checks: [
                                        .pass("statusItem"), .pass("iconNumber"), .skipped("stripWindow", "hidden"),
                                        .pass("clickLog"), .skipped("panelOpaque", "closed")])
        let report = LiveCheck.report(answers: answers, app: app, claude: "3.1623.0", by: "cli",
                                      at: try date("2026-10-22T09:14:07.880Z"))
        var expected = minified(try fixtureText("live-check.json"))
        expected = expected.replacingOccurrences(of: #""unchecked":0"#, with: #""unchecked":1"#)
        XCTAssertEqual(report.json, expected)
        XCTAssertFalse(report.ok)
        XCTAssertEqual(report.red.map { $0.check }, ["wide", "fold"])
    }

    func testReportRedWhenAppSilentAndAllGreen() throws {
        let health = try fixtureJSON("health.json")
        let green = LiveCheck.report(answers: [LiveCheck.PageAnswer(id: 3, url: "https://claude.ai/epitaxy", health: health)],
                                     app: LiveCheck.AppSection(version: "1", at: Date(), claude: "3", checked: nil, checks: []),
                                     claude: "3", by: "app", at: Date())
        XCTAssertTrue(green.ok)
        let silent = LiveCheck.report(answers: [LiveCheck.PageAnswer(id: 3, url: "https://claude.ai/epitaxy", health: health)],
                                      app: nil, claude: "3", by: "app", at: Date())
        XCTAssertEqual(silent.red, [LiveCheck.Red(window: "app", chat: "", check: "answer")], "Пимп не ответил — красное")
    }

    func testWordsForNotificationAndPanel() throws {
        let fixture = try fixtureJSON("live-check.json")
        let pages = try XCTUnwrap(fixture["pages"] as? [[String: Any]])
        let report = LiveCheck.report(answers: pages.map { LiveCheck.PageAnswer(id: 0, url: "about:blank", health: $0["health"]) },
                                      app: LiveCheck.AppSection(version: "1", at: Date(), claude: "3.1623.0", checked: nil,
                                                                checks: [.red("panelOpaque", "alpha: 0.5")]),
                                      claude: "3.1623.0", by: "app", at: Date())
        XCTAssertEqual(LiveCheck.notificationText(report),
                       "Claude 3.1623: PMP нашёл поломки — поле не справа, свёртка поля, панель просвечивает")
        XCTAssertEqual(LiveCheck.panelLine(report),
                       "Проверка окна Claude 3.1623: 3 красных — поле не справа, свёртка поля, панель просвечивает")
    }

    func testWriteDatedAndLastAndPrune() throws {
        let box = makeTemp().appendingPathComponent("live-check")
        let at = try date("2026-10-22T09:14:07.880Z")
        let report = LiveCheck.report(answers: [], app: nil, claude: "3.1623.0", by: "app", at: at)
        let dated = try XCTUnwrap(LiveCheck.write(report, to: box))
        XCTAssertEqual(dated.lastPathComponent, LiveCheck.fileName(at: at, claude: "3.1623.0"))
        XCTAssertEqual(try String(contentsOf: dated, encoding: .utf8), report.json + "\n")
        XCTAssertEqual(try String(contentsOf: box.appendingPathComponent(LiveCheck.lastFileName), encoding: .utf8),
                       report.json + "\n")
        let mode = { (url: URL) in (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? -1 }
        XCTAssertEqual(mode(box), 0o700)
        XCTAssertEqual(mode(dated), 0o600)
        XCTAssertEqual(LiveCheck.fileName(at: at, claude: "3.1623.0", timeZone: TimeZone(identifier: "UTC")!),
                       "2026-10-22-claude-3.1623.0.json")
        for day in 1...55 {
            let old = LiveCheck.report(answers: [], app: nil, claude: "1.\(1000 + day)", by: "app",
                                       at: at.addingTimeInterval(Double(-day) * 86_400 * 3))
            XCTAssertNotNil(LiveCheck.write(old, to: box))
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: box.path).filter { $0.contains("-claude-") }
        XCTAssertEqual(left.count, LiveCheck.keepFiles)
        XCTAssertTrue(left.contains(dated.lastPathComponent), "свежий отчёт на месте, ушли самые старые")
    }

    // MARK: - ход проверки

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_792_660_000)
    }

    private func runner(_ clock: Clock, defaults: UserDefaults, written: @escaping (LiveCheck.Report) -> Void,
                        done: @escaping (LiveCheck.Report) -> Void) -> LiveCheckRunner {
        let runner = LiveCheckRunner(defaults: defaults, now: { clock.now })
        runner.appSection = { LiveCheck.AppSection(version: "1.10.65", at: clock.now, claude: "3.1623.0", checked: nil, checks: []) }
        runner.write = { written($0); return nil }
        runner.onDone = { report, _ in done(report) }
        return runner
    }

    private func defaults() -> UserDefaults {
        let name = testSuiteName()
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func main() -> ChatPage { ChatPage(kind: .main, chat: nil, title: "Claude", store: "ok", at: Date()) }

    private func answer(_ name: String) throws -> LiveCheck.PageAnswer {
        LiveCheck.PageAnswer(id: 3, url: "https://claude.ai/epitaxy", health: try fixtureJSON(name))
    }

    func testRunnerWaitsForMainPageThenRetriesRed() throws {
        let clock = Clock()
        let store = defaults()
        var written: [LiveCheck.Report] = []
        var done: [LiveCheck.Report] = []
        let check = runner(clock, defaults: store, written: { written.append($0) }, done: { done.append($0) })
        XCTAssertFalse(check.due(pages: [main()]), "не взведена — не спрашиваем")
        check.arm(claude: "3.1623.0")
        XCTAssertFalse(check.due(pages: []), "главной страницы ещё нет")
        XCTAssertFalse(check.due(pages: [main()]), "главная только что ответила")
        clock.now += 19
        XCTAssertFalse(check.due(pages: []))
        clock.now += 1
        XCTAssertTrue(check.due(pages: []), "20 с с первого ответа главной страницы")
        check.absorb([try answer("health-red.json")])
        XCTAssertTrue(written.isEmpty, "первое красное — только повтор, без отчёта")
        XCTAssertFalse(check.due(pages: [main()]))
        clock.now += LiveCheck.retrySeconds - 1
        XCTAssertFalse(check.due(pages: [main()]))
        clock.now += 1
        XCTAssertTrue(check.due(pages: [main()]), "повтор через 2 минуты")
        check.absorb([try answer("health-red.json")])
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(done.first?.red.map { $0.check }, ["wide", "fold"])
        XCTAssertEqual(done.first?.by, "app")
        XCTAssertEqual(store.string(forKey: LiveCheck.checkedKey), "3.1623.0")
        XCTAssertNil(check.pending)
        check.arm(claude: "3.1623.0")
        XCTAssertNil(check.pending, "проверенную версию второй раз не проверяем — и уведомления второго нет")
    }

    func testRunnerGreenWritesAtOnceAndOldPageGivesUp() throws {
        let clock = Clock()
        let store = defaults()
        var done: [LiveCheck.Report] = []
        let check = runner(clock, defaults: store, written: { _ in }, done: { done.append($0) })
        check.arm(claude: "3.1623.0")
        _ = check.due(pages: [main()])
        clock.now += 20
        XCTAssertTrue(check.due(pages: []))
        check.absorb([try answer("health.json")])
        XCTAssertEqual(done.count, 1)
        XCTAssertTrue(done[0].ok)
        XCTAssertEqual(store.string(forKey: LiveCheck.checkedKey), "3.1623.0")

        // Старая страница без `health()`: не проверено — повтор через 2 мин, на второй раз бросаем, ключ не пишем.
        check.arm(claude: "3.2000.0")
        _ = check.due(pages: [main()])
        clock.now += 20
        let old = LiveCheck.PageAnswer(id: 3, url: "https://claude.ai/epitaxy", health: ["v": 0])
        check.absorb([old])
        XCTAssertNotNil(check.pending)
        clock.now += LiveCheck.retrySeconds
        XCTAssertTrue(check.due(pages: []))
        check.absorb([old])
        XCTAssertNil(check.pending)
        XCTAssertEqual(store.string(forKey: LiveCheck.checkedKey), "3.1623.0")
        XCTAssertEqual(done.count, 1)
    }

    // MARK: - круг probe с health()

    func testProbeScriptWithHealthIsOwnAndOrdinaryUnchanged() {
        let plain = ChatProbe.script(nonce: "chats-1-0001", scan: false)
        XCTAssertEqual(ChatProbe.script(nonce: "chats-1-0001", scan: false, cash: false, health: false), plain)
        XCTAssertFalse(plain.contains("health"), "обычный круг побайтно прежний")
        for scan in [false, true] {
            for cash in [false, true] {
                let script = ChatProbe.script(nonce: "chats-1-0002", scan: scan, cash: cash, health: true)
                XCTAssertTrue(ChatProbe.isOwnScript(script), "свой скрипт с health — не чужой после перезапуска")
                XCTAssertTrue(script.contains("api.health()"))
                XCTAssertTrue(script.contains("{ v: 0 }"), "страница без health() — {v:0}")
                XCTAssertEqual(script.contains("api.status()"), cash)
            }
        }
    }

    func testProbeAsksHealthWhenDueAndHandsAnswers() throws {
        var now = Date(timeIntervalSince1970: 1_792_660_000)
        var script: String?
        var stamp = 0
        var result: Data?
        let files = ChatProbeFiles(
            scriptInfo: { script == nil ? nil : ("\(stamp)", now) }, readScript: { script },
            writeScript: { script = $0; stamp += 1; return true },
            resultInfo: { result == nil ? nil : "r\(stamp)" }, readResult: { result })
        let probe = ChatProbe(files: files, now: { now }, random: { 7 })
        probe.isEnabled = { false }
        var due = false
        probe.isHealthDue = { due }
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        XCTAssertNil(script, "тумблер выключен и проверки нет — канал молчит")
        due = true
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        let text = try XCTUnwrap(script)
        XCTAssertTrue(text.contains("api.health()"), "пора — круг с health()")
        let nonce = try XCTUnwrap(ChatProbe.markNonce(text))
        let health = try fixtureJSON("health.json")
        let body: [String: Any] = ["at": "2026-10-22T09:14:05Z", "results": [
            ProbeSourceFixture.entry(["id": 3, "url": "https://claude.ai/epitaxy/local_x", "result": [
                "v": 1, "nonce": nonce, "kind": "main", "title": "Claude", "store": "ok", "health": health]]),
            ProbeSourceFixture.entry(["id": 7, "url": "about:blank", "result": [
                "v": 1, "nonce": nonce, "kind": "popout", "title": "x", "store": "ok", "health": ["v": 0]]]),
            ProbeSourceFixture.entry(["id": 8, "url": "about:blank", "result": [
                "v": 1, "nonce": "chats-old", "kind": "popout", "title": "x", "store": "ok", "health": ["v": 1]]]),
        ]]
        result = try JSONSerialization.data(withJSONObject: body)
        now += 2
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        let answers = try XCTUnwrap(probe.takeHealth())
        XCTAssertEqual(answers.map { $0.id }, [3, 7], "только свой круг")
        XCTAssertEqual((answers[0].health as? [String: Any])?["kind"] as? String, "main")
        XCTAssertNil(probe.takeHealth(), "ответы отдаются один раз")
    }
}
