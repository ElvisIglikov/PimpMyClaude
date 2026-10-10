import CoreGraphics
import XCTest
@testable import ClaudeAX

/// «Чат в главное окно» (WF108, #8148): разбор запроса, кого с кем менять, работа канала по эталонам
/// `tests/fixtures/pimp/main*` и настройка `mainChat` после «главного по центру».
final class MainChatTests: XCTestCase {
    private static let rick = "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"
    private static let popped = "local_d6d88c02-7455-425f-811b-f899694c2156"
    private static let mainFrame = CGRect(x: 0, y: 38, width: 900, height: 700)
    private static let rickFrame = CGRect(x: 1000, y: 38, width: 600, height: 700)

    // MARK: - разбор

    func testParseFixtures() throws {
        let byChat = try XCTUnwrap(PimpRequest.parse(fixture("main.request.json")))
        XCTAssertEqual(byChat.action, .main)
        XCTAssertEqual(byChat.chat, MainChatTests.rick)
        XCTAssertEqual(byChat.project, "")
        let byProject = try XCTUnwrap(PimpRequest.parse(fixture("main-project.request.json")))
        XCTAssertEqual(byProject.project, "Rick")
        XCTAssertEqual(byProject.chat, "")
        for body in ["{\"id\":\"1\",\"at\":\"2026-09-30T05:20:00Z\",\"action\":\"main\",\"from\":\"\"}",
                     "{\"id\":\"1\",\"at\":\"2026-09-30T05:20:00Z\",\"action\":\"main\",\"from\":\"\",\"chat\":\"Rick\"}",
                     "{\"id\":\"1\",\"at\":\"2026-09-30T05:20:00Z\",\"action\":\"main\",\"from\":\"\","
                        + "\"chat\":\"\(MainChatTests.rick)\",\"project\":\"Rick\"}"] {
            XCTAssertNil(PimpRequest.parse(Data(body.utf8)), body)
        }
    }

    func testSettingParse() {
        XCTAssertEqual(PimpChannel.mainChatSetting(Data("{\"mainChat\":\" Rick \"}".utf8)), "Rick")
        XCTAssertNil(PimpChannel.mainChatSetting(Data("{\"mainChat\":\"\"}".utf8)))
        XCTAssertNil(PimpChannel.mainChatSetting(Data("{\"mainChat\":5}".utf8)))
        XCTAssertNil(PimpChannel.mainChatSetting(Data("{}".utf8)))
        XCTAssertNil(PimpChannel.mainChatSetting(nil))
    }

    // MARK: - кого с кем менять

    private let isMain: (String) -> Bool = { $0 == "Claude" }

    private func windows(mainChat: String = MainChatTests.popped) -> [PimpWindow] {
        [PimpWindow(id: 10, title: "Claude", chat: mainChat, folder: "/p/VkusUchet", frame: MainChatTests.mainFrame),
         PimpWindow(id: 11, title: "Рик", chat: MainChatTests.rick, folder: "/p/Rick", frame: MainChatTests.rickFrame),
         PimpWindow(id: 12, title: "Словарь", chat: "local_x", folder: "/p/Dictator", frame: .zero)]
    }

    private func plan(chat: String = "", project: String = "", _ list: [PimpWindow],
                      last: (chat: String, title: String)? = nil) -> PimpChannel.MainPlan {
        PimpChannel.mainPlan(chat: chat, project: project, windows: list, isMain: isMain,
                             projects: [Project(folder: URL(fileURLWithPath: "/p/Napominator"), name: "Napominator",
                                                lastFocusedAt: 0)],
                             lastChat: { _ in last })
    }

    func testPlanByChatAndProject() {
        let list = windows()
        XCTAssertEqual(plan(chat: MainChatTests.rick, list), .swap(main: list[0], chat: MainChatTests.rick, target: list[1]))
        XCTAssertEqual(plan(project: "Rick", list), .swap(main: list[0], chat: MainChatTests.rick, target: list[1]))
        XCTAssertEqual(plan(project: "🟢 rick", list), .swap(main: list[0], chat: MainChatTests.rick, target: list[1]),
                       "имя проекта — как у order: без маркера и регистра")
        // Чата нет окном — главное окно откроет его из списка слева.
        XCTAssertEqual(plan(chat: "local_closed", list), .swap(main: list[0], chat: "local_closed", target: nil))
        XCTAssertEqual(plan(project: "Napominator", list, last: (chat: "local_n", title: "Напоминалка")),
                       .swap(main: list[0], chat: "local_n", target: nil))
    }

    func testPlanAlreadyAndRefusals() {
        let list = windows(mainChat: MainChatTests.rick)
        XCTAssertEqual(plan(chat: MainChatTests.rick, list), .already(chat: MainChatTests.rick))
        XCTAssertEqual(plan(project: "VkusUchet", windows()), .already(chat: MainChatTests.popped),
                       "проект — в главном окне, других окон у него нет")
        let rickInMain = [PimpWindow(id: 10, title: "Claude", chat: "local_r1", folder: "/p/Rick"),
                          PimpWindow(id: 16, title: "Рик 2", chat: "local_r2", folder: "/p/Rick")]
        XCTAssertEqual(plan(project: "Rick", rickInMain), .already(chat: "local_r1"),
                       "проект уже в главном — второй его чат окном не меняем")
        XCTAssertEqual(plan(chat: MainChatTests.rick, Array(windows().dropFirst())), .refuse(.windowMissing, list: []))
        let twoMains = windows() + [PimpWindow(id: 13, title: "Claude")]
        XCTAssertEqual(plan(chat: MainChatTests.rick, twoMains), .refuse(.ambiguous, list: ["Claude", "Claude"]))
        let twoRicks = windows() + [PimpWindow(id: 14, title: "Рик 2", chat: "local_r2", folder: "/p/Rick")]
        XCTAssertEqual(plan(project: "Rick", twoRicks), .refuse(.ambiguous, list: ["Рик", "Рик 2"]))
        XCTAssertEqual(plan(project: "Nope", windows()), .refuse(.projectMissing, list: ["Napominator"]))
        XCTAssertEqual(plan(project: "Napominator", windows()), .refuse(.chatMissing, list: []))
        let unknown = [windows()[0], PimpWindow(id: 15, title: "Рик", folder: "/p/Rick")]
        XCTAssertEqual(plan(project: "Rick", unknown), .refuse(.chatUnknown, list: ["Рик"]))
    }

    func testMovesSwapFrames() {
        let list = windows()
        XCTAssertEqual(PimpChannel.mainMoves(main: list[0], target: list[1], popped: 50),
                       [PimpMove(id: 50, frame: MainChatTests.mainFrame), PimpMove(id: 10, frame: MainChatTests.rickFrame)])
        XCTAssertEqual(PimpChannel.mainMoves(main: list[0], target: list[1], popped: nil),
                       [PimpMove(id: 10, frame: MainChatTests.rickFrame)])
        XCTAssertEqual(PimpChannel.mainMoves(main: list[0], target: nil, popped: 50), [])
    }

    // MARK: - канал по эталонам

    /// Вход: `main` чатом Рика. Ожидание: окно Рика закрыто, на следующем тике — `main-chat` главной
    /// странице в угол окна Рика, страница сказала `ok` с вынесенным чатом, окно родилось — рамки
    /// поменялись, ответ побайтно `main.result.json`.
    func testChannelSwapMatchesFixture() throws {
        let rig = Rig(windows: windows(), at: "2026-09-30T05:20:00Z")
        let (channel, box) = makeChannel(rig)
        try put(fixture("main.request.json"), id: "1790745600000-0901", in: box)
        channel.tick()
        XCTAssertEqual(rig.closed, [11])
        XCTAssertTrue(rig.sent.isEmpty, "окно цели ещё закрывается")
        XCTAssertTrue(channel.isBusy)
        rig.clock("2026-09-30T05:20:02Z")
        channel.tick()
        XCTAssertEqual(rig.sent.count, 1)
        XCTAssertEqual(rig.sent.first?.chat, MainChatTests.rick)
        XCTAssertEqual(rig.sent.first?.x, 1000)
        XCTAssertEqual(rig.sent.first?.y, 38)
        rig.run = NewWindowRun(at: PimpChannel.date("2026-09-30T05:20:03Z")!, step: "main", handoff: "",
                               chat: MainChatTests.popped, state: "ok")
        rig.windows.append(PimpWindow(id: 50, title: "ВкусУчёт", chat: MainChatTests.popped, frame: .zero))
        rig.clock("2026-09-30T05:20:06Z")
        channel.tick()
        XCTAssertEqual(resultText("1790745600000-0901", in: box), try fixtureText("main.result.json"))
        XCTAssertEqual(rig.moves.last, [PimpMove(id: 50, frame: MainChatTests.mainFrame),
                                        PimpMove(id: 10, frame: MainChatTests.rickFrame)])
        XCTAssertFalse(channel.isBusy)
    }

    /// Страница не открыла чат: окно цели выносится обратно в свой угол, ответ `main-chat-missing.error.json`.
    func testChannelChatMissingReopensTarget() throws {
        let rig = Rig(windows: windows(), at: "2026-09-30T05:20:18Z")
        let (channel, box) = makeChannel(rig)
        try put(request(id: "1790745600000-0903", at: "2026-09-30T05:20:18Z", chat: MainChatTests.rick),
                id: "1790745600000-0903", in: box)
        channel.tick()
        rig.clock("2026-09-30T05:20:20Z")
        channel.tick()
        rig.run = NewWindowRun(at: PimpChannel.date("2026-09-30T05:20:21Z")!, step: "row", handoff: "", chat: "",
                               state: "chat-missing")
        rig.clock("2026-09-30T05:20:22Z")
        channel.tick()
        channel.tick() // Read back the one reopened donor and restore its full frame.
        XCTAssertEqual(resultText("1790745600000-0903", in: box), try fixtureText("main-chat-missing.error.json"))
        XCTAssertEqual(rig.reopened.first?.chat, MainChatTests.rick)
        XCTAssertEqual(rig.reopened.first?.x, 1000)
        XCTAssertEqual(rig.moves.last, [PimpMove(id: 99, frame: MainChatTests.rickFrame)])
    }

    /// Главного окна нет — сразу `main-no-main.error.json`, ничего не закрыто.
    func testChannelNoMainWindow() throws {
        let rig = Rig(windows: Array(windows().dropFirst()), at: "2026-09-30T05:20:30Z")
        let (channel, box) = makeChannel(rig)
        try put(request(id: "1790745600000-0904", at: "2026-09-30T05:20:30Z", chat: MainChatTests.rick),
                id: "1790745600000-0904", in: box)
        channel.tick()
        XCTAssertEqual(resultText("1790745600000-0904", in: box), try fixtureText("main-no-main.error.json"))
        XCTAssertTrue(rig.closed.isEmpty)
    }

    /// Чат открыт, прежний не вынесся: главное окно встаёт на место цели, ответ `main-not-created.error.json`.
    func testChannelPopoutFailed() throws {
        let rig = Rig(windows: windows(), at: "2026-09-30T05:20:40Z")
        let (channel, box) = makeChannel(rig)
        try put(request(id: "1790745600000-0905", at: "2026-09-30T05:20:40Z", chat: MainChatTests.rick),
                id: "1790745600000-0905", in: box)
        channel.tick()
        rig.clock("2026-09-30T05:20:42Z")
        channel.tick()
        rig.run = NewWindowRun(at: PimpChannel.date("2026-09-30T05:20:43Z")!, step: "store", handoff: "",
                               chat: MainChatTests.popped, state: "popout-failed")
        rig.windows[0] = PimpWindow(id: 10, title: "Claude", chat: MainChatTests.rick,
                                    frame: MainChatTests.mainFrame)
        rig.clock("2026-09-30T05:20:44Z")
        channel.tick()
        XCTAssertEqual(resultText("1790745600000-0905", in: box), try fixtureText("main-not-created.error.json"))
        XCTAssertTrue(rig.moves.isEmpty, "Failure must not move main using an unconfirmed page outcome")
    }

    /// Чат уже в главном окне — ответ сразу, ничего не закрыто и не послано.
    func testChannelAlready() throws {
        let rig = Rig(windows: windows(mainChat: MainChatTests.rick).filter { $0.id != 11 }, at: "2026-09-30T05:21:00Z")
        let (channel, box) = makeChannel(rig)
        try put(request(id: "700-0001", at: "2026-09-30T05:21:00Z", chat: MainChatTests.rick), id: "700-0001", in: box)
        channel.tick()
        let answer = try XCTUnwrap(result("700-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["already"] as? Bool, true)
        XCTAssertTrue(rig.closed.isEmpty)
        XCTAssertTrue(rig.sent.isEmpty)
    }

    /// Page timeout restores the donor only when the current complete census proves absence.
    func testChannelPageSilent() throws {
        let rig = Rig(windows: windows(), at: "2026-09-30T05:22:00Z")
        let (channel, box) = makeChannel(rig)
        try put(request(id: "700-0002", at: "2026-09-30T05:22:00Z", chat: MainChatTests.rick), id: "700-0002", in: box)
        channel.tick()
        rig.clock("2026-09-30T05:22:02Z")
        channel.tick()
        rig.clock("2026-09-30T05:22:17Z")
        channel.tick()
        channel.tick()
        XCTAssertEqual(result("700-0002", in: box)?["error"] as? String, "no-answer")
        XCTAssertEqual(rig.reopened.map { $0.chat }, [MainChatTests.rick])
    }

    /// Настройка `mainChat`: после «главного по центру» на следующем свободном тике главный чат уходит в
    /// главное окно — ответа никому, окно Рика закрыто и страница позвана.
    func testSettingAfterCenterArrange() throws {
        let rig = Rig(windows: windows(), at: "2026-09-30T05:23:00Z")
        let (channel, box) = makeChannel(rig)
        channel.seats.mainChatSetting = { "Rick" }
        channel.seats.arrange = { ids, _, _ in
            (windows: ids.compactMap { id in rig.windows.first { $0.id == id } }, skipped: 0)
        }
        let body = "{\"id\":\"700-0003\",\"at\":\"2026-09-30T05:23:00Z\",\"action\":\"arrange\",\"from\":\"\","
            + "\"layout\":\"center\",\"center\":\"Rick\"}"
        try put(Data(body.utf8), id: "700-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("700-0003", in: box)?["ok"] as? Bool, true)
        XCTAssertTrue(rig.closed.isEmpty, "замена — не в том же тике: рамки ещё едут")
        rig.clock("2026-09-30T05:23:02Z")
        channel.tick()
        XCTAssertEqual(rig.closed, [11])
        rig.clock("2026-09-30T05:23:04Z")
        channel.tick()
        XCTAssertEqual(rig.sent.first?.chat, MainChatTests.rick)
        // Настройки нет — центр ничего не меняет.
        let quiet = Rig(windows: windows(), at: "2026-09-30T05:23:00Z")
        let (other, otherBox) = makeChannel(quiet)
        other.seats.arrange = channel.seats.arrange
        try put(Data(body.utf8), id: "700-0003", in: otherBox)
        other.tick()
        quiet.clock("2026-09-30T05:23:02Z")
        other.tick()
        XCTAssertTrue(quiet.closed.isEmpty)
    }

    // MARK: - стенд

    private final class Rig {
        var now: Date
        var windows: [PimpWindow]
        var run: NewWindowRun?
        var closed: [CGWindowID] = []
        var sent: [(chat: String, x: Int, y: Int)] = []
        var reopened: [(chat: String, x: Int, y: Int)] = []
        var moves: [[PimpMove]] = []

        init(windows: [PimpWindow], at: String) {
            self.windows = windows
            now = PimpChannel.date(at)!
        }

        func clock(_ at: String) { now = PimpChannel.date(at)! }
    }

    private func makeChannel(_ rig: Rig) -> (PimpChannel, URL) {
        let box = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("main-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: box) }
        let channel = PimpChannel(directory: box, now: { rig.now })
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { rig.windows }
        seats.isMainWindow = { $0 == "Claude" }
        seats.close = { id in
            rig.closed.append(id)
            rig.windows.removeAll { $0.id == id }
            return true
        }
        seats.sendMainChat = { chat, origin in rig.sent.append((chat: chat, x: origin.x, y: origin.y)) }
        seats.openChat = { chat, title, origin in
            rig.reopened.append((chat: chat, x: origin.x, y: origin.y))
            rig.windows.append(PimpWindow(id: 99, title: title, chat: chat,
                frame: CGRect(x: origin.x, y: origin.y, width: 900, height: 700), main: false))
        }
        seats.newWindowRun = { rig.run }
        seats.place = { rig.moves.append($0) }
        channel.seats = seats
        channel.start()
        return (channel, box)
    }

    private func request(id: String, at: String, chat: String) -> Data {
        Data(("{\"id\":\"\(id)\",\"at\":\"\(at)\",\"action\":\"main\",\"from\":\"\",\"chat\":\"\(chat)\"}").utf8)
    }

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: MainChatTests.fixtures.appendingPathComponent(name))
    }

    private func fixtureText(_ name: String) throws -> String {
        try String(data: fixture(name), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Файл запроса со временем стенда: иначе уборка канала (файлы старше часа по часам стенда) снесла бы его.
    private func put(_ data: Data, id: String, in box: URL) throws {
        let url = box.appendingPathComponent(id + ".json")
        try data.write(to: url)
        let at = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["at"] as? String
        if let date = at.flatMap(PimpChannel.date) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    private func resultText(_ id: String, in box: URL) -> String? {
        (try? String(contentsOf: box.appendingPathComponent(id + ".result.json"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func result(_ id: String, in box: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: box.appendingPathComponent(id + ".result.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
