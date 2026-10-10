import CoreGraphics
import XCTest
@testable import ClaudeAX

/// «Отправь текст в чат» (WF103, #7953, #7927): разбор запроса `send`, команда `send-text`
/// окну, исход страницы из круга `cash` и ответы — по эталонам `tests/fixtures/pimp/send*.json`.
final class SendWF103Tests: XCTestCase {
    private static let rick = "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"
    private static let target = "local_d6d88c02-7455-425f-811b-f899694c2156"
    private static let root = "/Users/dev/Projects/"
    private static let title = "WF103 оркестровка просмотра файлов"

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: SendWF103Tests.fixtures.appendingPathComponent(name))
    }

    private func fixtureText(_ name: String) throws -> String {
        try String(data: fixture(name), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Стенд: канал в песочнице, окна Рика (главное), чата-адресата и два окна VkusnoffKz.
    private final class Rig {
        var now: Date
        var windows: [PimpWindow]
        var sent: [(chat: String, text: String, id: String)] = []
        var states: [String: String] = [:]

        init(now: String) {
            self.now = PimpChannel.date(now)!
            windows = [
                PimpWindow(id: 1, title: "Claude", chat: SendWF103Tests.rick,
                           folder: SendWF103Tests.root + "Rick", frame: CGRect(x: 0, y: 0, width: 800, height: 700)),
                PimpWindow(id: 2, title: SendWF103Tests.title, chat: SendWF103Tests.target,
                           folder: SendWF103Tests.root + "PimpMyClaude", frame: CGRect(x: 800, y: 0, width: 400, height: 700)),
            ]
        }
    }

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("send-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func channel(_ rig: Rig, in box: URL) -> PimpChannel {
        let channel = PimpChannel(directory: box, now: { rig.now })
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { rig.windows }
        seats.isMainWindow = { $0 == "Claude" }
        seats.sendText = { chat, text, id in rig.sent.append((chat: chat, text: text, id: id)) }
        seats.sendState = { rig.states[$0] }
        channel.seats = seats
        channel.start()
        return channel
    }

    /// Файл запроса со временем стенда: иначе уборка канала (файлы старше часа) сочла бы его
    /// старым — часы стенда стоят на эталонном 27.09 02:10Z, а файл пишется сейчас.
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

    private func body(_ id: String, at: String, chat: String? = nil, project: String? = nil,
                      text: String? = "привет") -> Data {
        var map: [String: Any] = ["id": id, "at": at, "action": "send", "from": SendWF103Tests.rick]
        if let chat = chat { map["chat"] = chat }
        if let project = project { map["project"] = project }
        if let text = text { map["text"] = text }
        return try! JSONSerialization.data(withJSONObject: map)
    }

    // MARK: - разбор

    func testSendParsesFixturesAndRefusesBadRequests() throws {
        let byChat = try XCTUnwrap(PimpRequest.parse(fixture("send.request.json")))
        XCTAssertEqual(byChat.action, .send)
        XCTAssertEqual(byChat.chat, SendWF103Tests.target)
        XCTAssertEqual(byChat.project, "")
        XCTAssertEqual(byChat.text, "Проверка send: это текст от голоса Элвиса.")
        let byProject = try XCTUnwrap(PimpRequest.parse(fixture("send-project.request.json")))
        XCTAssertEqual(byProject.project, "VkusnoffKz")
        XCTAssertEqual(byProject.chat, "")
        XCTAssertEqual(byProject.text, "Сделай баннер на завтра.")

        let at = "2026-09-27T02:10:00Z"
        XCTAssertNil(PimpRequest.parse(body("1-1", at: at, chat: SendWF103Tests.target, project: "Rick")),
                     "ровно одно из chat и project")
        XCTAssertNil(PimpRequest.parse(body("1-1", at: at)), "ни окна, ни проекта")
        XCTAssertNil(PimpRequest.parse(body("1-1", at: at, chat: "last")))
        XCTAssertNil(PimpRequest.parse(body("1-1", at: at, chat: SendWF103Tests.target, text: nil)))
        XCTAssertNil(PimpRequest.parse(body("1-1", at: at, chat: SendWF103Tests.target, text: "")))
        XCTAssertNil(PimpRequest.parse(body("1-1", at: at, chat: SendWF103Tests.target, text: "a\u{0}b")))
        let full = String(repeating: "я", count: PimpChannel.sendTextLimit)
        XCTAssertEqual(PimpRequest.parse(body("1-1", at: at, chat: SendWF103Tests.target, text: full))?.text, full,
                       "8000 знаков — можно, текст не режется")
        XCTAssertNil(PimpRequest.parse(body("1-1", at: at, chat: SendWF103Tests.target, text: full + "я")))
    }

    // MARK: - канал

    /// По эталону: команда окну с его чатом и id запроса, канал занят, сердцебиение, исход
    /// `sent` — ответ побайтно как `send.result.json`.
    func testSendByChatAnswersLikeFixture() throws {
        let box = makeTemp()
        let rig = Rig(now: "2026-09-27T02:10:00Z")
        let channel = channel(rig, in: box)
        let id = "1790460000000-0201"
        try put(fixture("send.request.json"), id: id, in: box, at: rig.now)
        channel.tick()
        XCTAssertEqual(rig.sent.count, 1)
        XCTAssertEqual(rig.sent.first?.chat, SendWF103Tests.target)
        XCTAssertEqual(rig.sent.first?.text, "Проверка send: это текст от голоса Элвиса.")
        XCTAssertEqual(rig.sent.first?.id, id)
        XCTAssertTrue(channel.isBusy)
        XCTAssertTrue(channel.isWaitingPage, "пока ждём — круг probe несёт status().send")
        XCTAssertNil(resultText(id, in: box))

        // Сердцебиение: метка `<id>.taken` переписывается на каждом тике.
        let taken = box.appendingPathComponent(id + ".taken")
        try FileManager.default.removeItem(at: taken)
        rig.now = rig.now.addingTimeInterval(1)
        rig.states["другой-id"] = "sent"
        channel.tick()
        XCTAssertTrue(FileManager.default.fileExists(atPath: taken.path))
        XCTAssertNil(resultText(id, in: box), "чужой id — не наш исход")

        rig.now = PimpChannel.date("2026-09-27T02:10:02Z")!
        rig.states[id] = "sent"
        channel.tick()
        XCTAssertEqual(resultText(id, in: box), try fixtureText("send.result.json"))
        XCTAssertFalse(channel.isBusy)
        XCTAssertEqual(rig.sent.count, 1, "повтора нет")
    }

    /// Исходы страницы — ошибки с полем `window`; 20 с тишины — `no-answer` (эталоны).
    func testSendPageOutcomesAndNoAnswer() throws {
        let box = makeTemp()
        let rig = Rig(now: "2026-09-27T02:10:11Z")
        let channel = channel(rig, in: box)
        let busyID = "1790460000000-0203"
        try put(body(busyID, at: "2026-09-27T02:10:11Z", chat: SendWF103Tests.target), id: busyID, in: box, at: rig.now)
        channel.tick()
        rig.now = PimpChannel.date("2026-09-27T02:10:12Z")!
        rig.states[busyID] = "field-busy"
        channel.tick()
        XCTAssertEqual(resultText(busyID, in: box), try fixtureText("send-field-busy.error.json"))

        // WF111: свой текст Элвиса в поле — фраза в очереди окна, для канала успех с `queued: true`.
        let queuedID = "1790460000000-0205"
        rig.now = PimpChannel.date("2026-09-27T02:10:31Z")!
        try put(body(queuedID, at: "2026-09-27T02:10:31Z", chat: SendWF103Tests.target), id: queuedID, in: box, at: rig.now)
        channel.tick()
        rig.now = PimpChannel.date("2026-09-27T02:10:32Z")!
        rig.states[queuedID] = "queued"
        channel.tick()
        XCTAssertEqual(resultText(queuedID, in: box), try fixtureText("send-queued.result.json"))
        rig.now = PimpChannel.date("2026-09-27T02:10:21Z")!

        // Незнакомое слово страницы — не исход, ждём дальше.
        let quietID = "1790460000000-0204"
        rig.now = PimpChannel.date("2026-09-27T02:10:21Z")!
        try put(body(quietID, at: "2026-09-27T02:10:21Z", chat: SendWF103Tests.target), id: quietID, in: box, at: rig.now)
        channel.tick()
        rig.states[quietID] = "typing"
        rig.now = PimpChannel.date("2026-09-27T02:10:40Z")!
        channel.tick()
        XCTAssertNil(resultText(quietID, in: box), "19 с — ещё ждём")
        rig.now = PimpChannel.date("2026-09-27T02:10:41Z")!
        channel.tick()
        XCTAssertEqual(resultText(quietID, in: box), try fixtureText("send-no-answer.error.json"))

        for state in ["no-field", "no-send"] {
            let id = "1790460000001-\(state)"
            try put(body(id, at: PimpChannel.stampText(rig.now), chat: SendWF103Tests.target), id: id, in: box, at: rig.now)
            channel.tick()
            rig.states[id] = state
            channel.tick()
            XCTAssertEqual(result(id, in: box)?["error"] as? String, state)
            XCTAssertEqual(result(id, in: box)?["window"] as? String, SendWF103Tests.title)
        }
    }

    /// Окно — как у `renew-window`: главное можно, два окна проекта — `ambiguous` + `windows`,
    /// нет — `window-missing`; пока идёт `send`, прочим — `busy`. У отказов поля `window` нет.
    func testSendPicksWindowAndRefuses() throws {
        let box = makeTemp()
        let rig = Rig(now: "2026-09-27T02:10:05Z")
        let channel = channel(rig, in: box)
        let at = "2026-09-27T02:10:05Z"

        try put(body("2-1", at: at, project: "Rick"), id: "2-1", in: box, at: rig.now)
        channel.tick()
        XCTAssertEqual(rig.sent.last?.chat, SendWF103Tests.rick, "главное окно можно")
        try put(body("2-2", at: at, chat: SendWF103Tests.target), id: "2-2", in: box, at: rig.now)
        channel.tick()
        XCTAssertEqual(result("2-2", in: box)?["error"] as? String, "busy")
        XCTAssertNil(result("2-2", in: box)?["window"])
        rig.states["2-1"] = "sent"
        channel.tick()
        XCTAssertEqual(result("2-1", in: box)?["ok"] as? Bool, true)
        XCTAssertEqual(result("2-1", in: box)?["window"] as? String, "Claude")

        rig.windows += [
            PimpWindow(id: 3, title: "Баннер", chat: "local_a", folder: SendWF103Tests.root + "VkusnoffKz"),
            PimpWindow(id: 4, title: "Сайт", chat: "local_b", folder: SendWF103Tests.root + "VkusnoffKz"),
        ]
        try put(fixture("send-project.request.json"), id: "2-3", in: box, at: rig.now)
        channel.tick()
        XCTAssertEqual(result("2-3", in: box)?["error"] as? String, "ambiguous")
        XCTAssertEqual(result("2-3", in: box)?["windows"] as? [String], ["Баннер", "Сайт"])
        XCTAssertNil(result("2-3", in: box)?["window"])

        try put(body("2-4", at: at, project: "Nope"), id: "2-4", in: box, at: rig.now)
        try put(body("2-5", at: at, chat: "local_00000000-0000-0000-0000-000000000000"), id: "2-5", in: box, at: rig.now)
        channel.tick()
        XCTAssertEqual(result("2-4", in: box)?["error"] as? String, "window-missing")
        XCTAssertEqual(result("2-5", in: box)?["error"] as? String, "window-missing")
        XCTAssertEqual(rig.sent.count, 1, "отказы команду окну не шлют")
    }

    // MARK: - круг probe

    /// Круг `cash` несёт `status().send` у ЛЮБОГО нашего окна; у чужой страницы — нет.
    func testChatProbeCarriesSendOfAnyWindow() throws {
        let cash = ChatProbe.script(nonce: "chats-1-0001", scan: false, cash: true)
        XCTAssertTrue(cash.contains("status.send"))
        XCTAssertFalse(ChatProbe.script(nonce: "chats-1-0001", scan: false).contains("send"))
        XCTAssertTrue(ChatProbe.isOwnScript(cash))

        let answer: [String: Any] = ["at": 1, "results": [
            ["id": 1, "source": ProbeSourceFixture.metadata(url: "about:blank"), "url": "about:blank", "result": ["v": 1, "nonce": "n", "kind": "popout", "self": SendWF103Tests.target,
                                                      "title": SendWF103Tests.title, "store": "ok",
                                                      "send": ["id": "1790460000000-0201", "state": "sent", "at": 1, "sends": 1]]],
            ["id": 2, "source": ProbeSourceFixture.metadata(url: "https://claude.ai/epitaxy"), "url": "https://claude.ai/epitaxy", "result": ["v": 1, "nonce": "n", "kind": "main", "self": SendWF103Tests.rick,
                                                                    "title": "Claude", "store": "ok", "send": NSNull()]],
            ["id": 3, "source": ProbeSourceFixture.metadata(url: "https://example.com/"), "url": "https://example.com/", "result": ["v": 1, "nonce": "n", "kind": "other", "store": "skip",
                                                               "send": ["id": "x", "state": "sent"]]],
        ]]
        let pages = ChatProbe.parse(try JSONSerialization.data(withJSONObject: answer), nonce: "n", at: Date())
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].send, SendRun(id: "1790460000000-0201", state: "sent"))
        XCTAssertNil(pages[1].send)
        XCTAssertNil(SendRun.parse(["id": 5, "state": "sent"]))
    }
}
