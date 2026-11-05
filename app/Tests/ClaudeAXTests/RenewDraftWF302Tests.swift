import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Черновик при смене чата главного окна (#11201, WF302; слово Элвиса 30.10 ~17:45: «Я там скриншоты ещё
/// закреплял, скриншоты не закрепились… диктовки ещё куски большие не вставились»): канал ждёт паузы в наборе
/// перед заменой и исход переноса черновика страницей, а в ответ кладёт поле `draft`.
final class RenewDraftWF302Tests: XCTestCase {
    private static let rick = "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"
    private static let fresh = "local_9f1c2d3e-0000-4000-8000-000000000102"
    private static let root = "/Users/dev/Projects/"

    private final class Rig {
        var now = PimpChannel.date("2026-10-30T14:00:00Z")!
        var windows = [PimpWindow(id: 1, title: "Claude", chat: RenewDraftWF302Tests.rick,
                                  folder: RenewDraftWF302Tests.root + "Rick",
                                  frame: CGRect(x: 54, y: -720, width: 852, height: 720))]
        var run: NewWindowRun?
        var idle: TimeInterval? = 30
        var opened = 0
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("renew-draft-\(UUID().uuidString)", isDirectory: true)
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
        seats.projects = {
            [Project(folder: URL(fileURLWithPath: RenewDraftWF302Tests.root + "Rick", isDirectory: true),
                     name: "Rick", lastFocusedAt: 0)]
        }
        seats.openRenewWindow = { _, _, _, _ in rig.opened += 1 }
        seats.newWindowRun = { rig.run }
        seats.keyIdle = { rig.idle }
        channel.seats = seats
        channel.start()
        return channel
    }

    private func put(_ id: String, rig: Rig, in box: URL) throws {
        let body = "{\"id\":\"\(id)\",\"at\":\"\(PimpChannel.stampText(rig.now))\",\"action\":\"renew-window\","
            + "\"from\":\"\(RenewDraftWF302Tests.rick)\",\"chat\":\"\(RenewDraftWF302Tests.rick)\",\"text\":\"Ты — Рик.\"}"
        let url = box.appendingPathComponent(id + ".json")
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: rig.now], ofItemAtPath: url.path)
    }

    private func result(_ id: String, in box: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: box.appendingPathComponent(id + ".result.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func carry(_ state: String, landed: Int = 0) -> DraftCarry {
        DraftCarry.parse(["state": state, "chars": 42, "files": 3, "want": 3, "landed": landed])!
    }

    func testDraftCarryParse() {
        XCTAssertNil(DraftCarry.parse(nil))
        XCTAssertNil(DraftCarry.parse(["state": "куда-то"]), "состояние не из списка")
        let parsed = DraftCarry.parse(["state": "part", "chars": 12, "want": 3, "landed": 1, "why": "x\ny"])
        XCTAssertEqual(parsed?.landed, 1)
        XCTAssertEqual(parsed?.why, "", "управляющие знаки — без причины")
        XCTAssertEqual(DraftCarry.parse(["state": "fail", "why": "текст не лёг в поле"])?.field.json,
                       "{\"state\":\"fail\",\"chars\":0,\"want\":0,\"landed\":0,\"why\":\"текст не лёг в поле\"}")
        let run = NewWindowRun.parse(["at": 1_790_000_000_000.0, "step": "stay", "id": RenewDraftWF302Tests.fresh,
                                      "state": "ok", "carry": ["state": "ok", "chars": 5, "want": 1, "landed": 1]])
        XCTAssertEqual(run?.carry?.state, "ok")
        XCTAssertNil(NewWindowRun.parse(["at": 1_790_000_000_000.0, "carry": NSNull()])?.carry)
    }

    func testTypingHold() {
        let at = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(RenewTyping.hold(idle: nil, since: nil, at: at), "не знаем — не ждём")
        XCTAssertNil(RenewTyping.hold(idle: 5, since: nil, at: at), "пауза есть")
        XCTAssertEqual(RenewTyping.hold(idle: 1, since: nil, at: at), at)
        XCTAssertEqual(RenewTyping.hold(idle: 1, since: at, at: at.addingTimeInterval(59)), at)
        XCTAssertNil(RenewTyping.hold(idle: 1, since: at, at: at.addingTimeInterval(60)), "дольше минуты не ждём")
        XCTAssertEqual(RenewTyping.hold(idle: 1, since: at, at: at.addingTimeInterval(200)), at.addingTimeInterval(200),
                       "старое ожидание забыто — новое с нуля")
    }

    /// Элвис печатает — `busy` с `typing`, окно не трогаем; пауза — замена пошла.
    func testRenewWaitsForTypingPause() throws {
        let rig = Rig()
        let box = makeTemp()
        let channel = channel(rig, in: box)
        rig.idle = 0.5
        try put("1790000000000-0001", rig: rig, in: box)
        channel.tick()
        let busy = try XCTUnwrap(result("1790000000000-0001", in: box))
        XCTAssertEqual(busy["error"] as? String, "busy")
        XCTAssertEqual(busy["typing"] as? Bool, true)
        XCTAssertEqual(rig.opened, 0, "новый чат не открывали")
        XCTAssertFalse(channel.isBusy)

        rig.advance(2)
        rig.idle = 4
        try put("1790000000000-0002", rig: rig, in: box)
        channel.tick()
        XCTAssertNil(result("1790000000000-0002", in: box), "замена идёт — ответа ещё нет")
        XCTAssertEqual(rig.opened, 1)
    }

    /// Печатает без конца — через 60 с меняем всё равно.
    func testRenewTypingCapsAtMinute() throws {
        let rig = Rig()
        let box = makeTemp()
        let channel = channel(rig, in: box)
        rig.idle = 0.2
        for (index, step) in [0.0, 30, 31].enumerated() {
            rig.advance(step)
            try put("1790000000000-01\(index)", rig: rig, in: box)
            channel.tick()
        }
        XCTAssertEqual(result("1790000000000-011", in: box)?["typing"] as? Bool, true)
        XCTAssertNil(result("1790000000000-012", in: box), "61 с ожидания — замена пошла")
        XCTAssertEqual(rig.opened, 1)
    }

    /// Чат назван, а страница ещё кладёт черновик — ответ ждёт исход и несёт его полем `draft`.
    func testRenewMainWaitsForDraftAndReportsIt() throws {
        let rig = Rig()
        let box = makeTemp()
        let channel = channel(rig, in: box)
        let id = "1790000000000-0201"
        try put(id, rig: rig, in: box)
        channel.tick()
        rig.advance(3)
        rig.run = NewWindowRun(at: rig.now, step: "stay", handoff: "", chat: RenewDraftWF302Tests.fresh,
                               state: "run", busy: true, carry: carry("wait"))
        channel.tick()
        XCTAssertNil(result(id, in: box), "черновик ещё едет")
        rig.advance(2)
        rig.run = NewWindowRun(at: rig.now, step: "stay", handoff: "", chat: RenewDraftWF302Tests.fresh,
                               state: "ok", carry: carry("part", landed: 2))
        channel.tick()
        let answer = try XCTUnwrap(result(id, in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        let draft = try XCTUnwrap(answer["draft"] as? [String: Any])
        XCTAssertEqual(draft["state"] as? String, "part")
        XCTAssertEqual(draft["want"] as? Int, 3)
        XCTAssertEqual(draft["landed"] as? Int, 2)
    }

    /// Страница так и не сказала исход за срок — отвечаем с `wait`, канал не висит.
    func testRenewMainDraftWaitHasCeiling() throws {
        let rig = Rig()
        let box = makeTemp()
        let channel = channel(rig, in: box)
        let id = "1790000000000-0301"
        try put(id, rig: rig, in: box)
        channel.tick()
        rig.advance(3)
        rig.run = NewWindowRun(at: rig.now, step: "stay", handoff: "", chat: RenewDraftWF302Tests.fresh,
                               state: "run", busy: true, carry: carry("wait"))
        channel.tick()
        rig.advance(PimpChannel.renewDraftSeconds + 1)
        channel.tick()
        XCTAssertEqual((result(id, in: box)?["draft"] as? [String: Any])?["state"] as? String, "wait")
        XCTAssertFalse(channel.isBusy)
    }

    /// Пустой черновик — поля `draft` нет, ответ как раньше.
    func testRenewMainWithoutDraftHasNoField() throws {
        let rig = Rig()
        let box = makeTemp()
        let channel = channel(rig, in: box)
        let id = "1790000000000-0401"
        try put(id, rig: rig, in: box)
        channel.tick()
        rig.advance(3)
        rig.run = NewWindowRun(at: rig.now, step: "stay", handoff: "", chat: RenewDraftWF302Tests.fresh, state: "ok")
        channel.tick()
        let answer = try XCTUnwrap(result(id, in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertNil(answer["draft"])
    }
}
