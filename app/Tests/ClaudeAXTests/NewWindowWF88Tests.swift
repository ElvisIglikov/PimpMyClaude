import AppKit
import XCTest
@testable import ClaudeAX

/// Пустое окно Claude Code проекта (план WF88, вариант V-N): штатный пункт File ▸ «New Session
/// in New Window» у выбранного Claude, приём черновика «Code», место, `draft-setup`; меню ⌘B
/// «🪟 Новое окно ▸» с «↩︎» и правым кликом.
final class NewWindowWF88Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_413_200)
    private let project = Project(folder: URL(fileURLWithPath: "/tmp/VkusnoffKz", isDirectory: true),
                                  name: "VkusnoffKz", lastFocusedAt: 0)
    private let main = PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 490, height: 859))
    private let placed = CGRect(x: 980, y: 34, width: 490, height: 859)

    // MARK: - подписи пункта

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf88-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func table(_ dir: URL, _ name: String, _ body: String) throws {
        try Data(body.utf8).write(to: dir.appendingPathComponent(name))
    }

    func testLabelsJoinBundleTablesWithFallback() throws {
        let dir = try tempDir()
        try table(dir, "en-US.json", #"{"U//bQDu9Yk":" New Session in New Window ","x":"y"}"#)
        try table(dir, "de-DE.json", #"{"U//bQDu9Yk":"Neue Sitzung in neuem Fenster"}"#)
        try table(dir, "xx-XX.json", #"{"U//bQDu9Yk":"Brand New Window Label"}"#)
        try table(dir, "broken.json", "{not json")
        try table(dir, "nokey.json", #"{"other":"New"}"#)
        try table(dir, "array.json", #"["U//bQDu9Yk"]"#)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("en.lproj"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dir.json"),
                                                withIntermediateDirectories: true)
        let labels = BlankWindow.labels(resources: dir)
        XCTAssertEqual(labels, BlankWindow.fallbackLabels + ["Brand New Window Label"])
        XCTAssertEqual(Set(labels).count, labels.count, "без повторов")
    }

    func testLabelsEmptyFolderIsFallbackOnly() throws {
        XCTAssertEqual(BlankWindow.labels(resources: try tempDir()), BlankWindow.fallbackLabels)
        XCTAssertEqual(BlankWindow.labels(resources: nil), BlankWindow.fallbackLabels)
        XCTAssertEqual(BlankWindow.fallbackLabels.count, 10)
        XCTAssertEqual(BlankWindow.fallbackLabels.first, "New Session in New Window")
    }

    // MARK: - поиск пункта (чистая часть на дереве заголовков)

    private func tree(file: [BlankWindow.MenuTitle], other: [BlankWindow.MenuTitle] = []) -> [[BlankWindow.MenuTitle]] {
        [[(title: "About This Mac", enabled: true)], [(title: "Quit Claude", enabled: true)], file,
         [(title: "Undo", enabled: true)], other]
    }

    func testFindsItemInFile() throws {
        let file: [BlankWindow.MenuTitle] = [(title: "New Session", enabled: true),
                                             (title: "New Session in New Window", enabled: true),
                                             (title: "Open File…", enabled: true)]
        let hit = try XCTUnwrap(BlankWindow.find(in: tree(file: file), labels: BlankWindow.fallbackLabels))
        XCTAssertEqual(hit.menu, 2)
        XCTAssertEqual(hit.item, 1)
    }

    func testFindsGermanItem() throws {
        let file: [BlankWindow.MenuTitle] = [(title: "Neue Sitzung", enabled: true),
                                             (title: "Neue Sitzung in neuem Fenster", enabled: nil)]
        let hit = try XCTUnwrap(BlankWindow.find(in: tree(file: file), labels: BlankWindow.fallbackLabels))
        XCTAssertEqual(hit.item, 1)
    }

    func testDisabledOrMissingItemIsNotFound() {
        let disabled: [BlankWindow.MenuTitle] = [(title: "New Session in New Window", enabled: false)]
        XCTAssertNil(BlankWindow.find(in: tree(file: disabled), labels: BlankWindow.fallbackLabels))
        XCTAssertNil(BlankWindow.find(in: tree(file: [(title: "Open File…", enabled: true)]),
                                      labels: BlankWindow.fallbackLabels))
        XCTAssertNil(BlankWindow.find(in: tree(file: [(title: "New Session", enabled: true)]),
                                      labels: BlankWindow.fallbackLabels),
                     "«New Session» без хвоста — другой пункт Claude")
    }

    func testFileIsSearchedFirstThenTheRest() throws {
        XCTAssertEqual(BlankWindow.searchOrder(count: 8), [2, 0, 1, 3, 4, 5, 6, 7])
        XCTAssertEqual(BlankWindow.searchOrder(count: 2), [0, 1])
        let hit = try XCTUnwrap(BlankWindow.find(
            in: tree(file: [(title: "Open File…", enabled: true)],
                     other: [(title: "New Session in New Window", enabled: true)]),
            labels: BlankWindow.fallbackLabels))
        XCTAssertEqual(hit.menu, 4)
    }

    func testDraftTitleIsStub() {
        XCTAssertTrue(BlankWindow.isDraftTitle(" Code "))
        XCTAssertTrue(ProjectIndex.isStub("Code"))
        XCTAssertFalse(BlankWindow.isDraftTitle("Claude"))
    }

    // MARK: - команда черновику (К18)

    func testDraftSetupJSONBytes() {
        let full = BlankWindow.draftSetupFields(folder: "/Users/dev/Projects/VkusnoffKz",
                                                model: "Opus 5.5", effort: "High", text: "проверь")
        XCTAssertEqual(CommandValue.object(full).json,
                       #"{"scope":"window","title":"","draft":true,"folder":"/Users/dev/Projects/VkusnoffKz","model":"Opus 5.5","effort":"High","text":"проверь"}"#)
        let bare = BlankWindow.draftSetupFields(folder: nil, model: nil, effort: nil)
        XCTAssertEqual(CommandValue.object(bare).json, #"{"scope":"window","title":"","draft":true}"#)
    }

    func testModelOfLastChat() {
        let opus = SessionModel(model: "claude-opus-5-5", effort: "high", auto: false)
        XCTAssertEqual(BlankWindow.model(of: opus).model, "Opus 5.5")
        XCTAssertEqual(BlankWindow.model(of: opus).effort, "High")
        let auto = BlankWindow.model(of: SessionModel(model: "claude-opus-5-5", effort: "high", auto: true))
        XCTAssertNil(auto.model)
        XCTAssertNil(auto.effort, "Auto — полей нет")
        XCTAssertNil(BlankWindow.model(of: nil).model)
    }

    func testNewWindowWarmupBlocksBlankFor40Seconds() {
        XCTAssertTrue(ClaudeActions.newWindowBusy(cashout: true, since: nil, now: t0))
        XCTAssertFalse(ClaudeActions.newWindowBusy(cashout: false, since: nil, now: t0))
        XCTAssertTrue(ClaudeActions.newWindowBusy(cashout: false, since: t0, now: t0.addingTimeInterval(39)))
        XCTAssertFalse(ClaudeActions.newWindowBusy(cashout: false, since: t0, now: t0.addingTimeInterval(41)))
    }

    // MARK: - работа канала

    /// Стенд: канал на временном каталоге, часы и все сиденья — заглушки с журналом.
    private final class Rig {
        var now: Date
        var running = true
        var windows: [PimpWindow]
        var ax: [PimpWindow]
        var busy = false
        var press = true
        var pressed = 0
        var polls = 0
        var log: [String] = []
        var arranged: [(ids: [CGWindowID], ordered: Bool)] = []
        var setups: [String] = []
        var notices: [String] = []
        var opened: [String] = []
        var last: (chat: String, title: String)?
        init(now: Date, windows: [PimpWindow]) {
            self.now = now
            self.windows = windows
            self.ax = windows
        }
    }

    private func channel(_ rig: Rig, placed: CGRect? = nil) throws -> (PimpChannel, URL) {
        let dir = try tempDir().appendingPathComponent("pimp", isDirectory: true)
        let channel = PimpChannel(directory: dir, now: { rig.now })
        let target = placed ?? self.placed
        channel.seats = PimpSeats(
            claudeRunning: { rig.running },
            windows: { rig.windows },
            projects: { [self.project] },
            arrangeSmart: { ids, ordered, _ in
                rig.arranged.append((ids, ordered))
                rig.log.append("arrange")
                return ids.map { id in
                    PimpWindow(id: id, title: id == 1 ? "Claude" : "Code",
                               frame: id == ids.last ? target : CGRect(x: 0, y: 34, width: 490, height: 859))
                }
            },
            isMainWindow: { $0 == "Claude" },
            openChat: { chat, _, _ in rig.opened.append(chat) },
            notice: { rig.notices.append($0) },
            raise: { rig.log.append("raise \($0)") },
            lastChat: { _ in rig.last },
            newWindowBusy: { rig.busy },
            blankWindows: { rig.ax },
            pressDraftItem: { _ in
                rig.pressed += 1
                return rig.press
            },
            draftSetup: { fields in
                rig.log.append("draft-setup")
                rig.setups.append(CommandValue.object(fields).json)
            },
            chatModel: { _ in SessionModel(model: "claude-opus-5-5", effort: "high", auto: false) },
            schedule: { _, _ in rig.polls += 1 })
        return (channel, dir)
    }

    private func files(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private func code(_ id: CGWindowID, title: String = "Code",
                      frame: CGRect = CGRect(x: 300, y: 100, width: 900, height: 700)) -> PimpWindow {
        PimpWindow(id: id, title: title, frame: frame)
    }

    func testNewCodeWindowIsPlacedRaisedAndSetUp() throws {
        let rig = Rig(now: t0, windows: [main])
        rig.last = (chat: "local_1", title: "Чат")
        let (channel, dir) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(rig.pressed, 1)
        XCTAssertEqual(rig.polls, 1, "опрос 0,25 с своим сиденьем, не тиком")
        rig.ax = [main, code(50)]
        rig.windows = [main, code(50)]
        channel.pollBlank(at: t0.addingTimeInterval(0.25))
        XCTAssertEqual(rig.arranged.count, 1)
        XCTAssertEqual(rig.arranged[0].ids, [1, 50])
        XCTAssertTrue(rig.arranged[0].ordered, "справа — умный путь, черновик последним (WF94)")
        XCTAssertEqual(rig.log, ["arrange", "raise 50", "draft-setup"])
        XCTAssertEqual(rig.setups, [#"{"scope":"window","title":"","draft":true,"folder":"/tmp/VkusnoffKz","model":"Opus 5.5","effort":"High"}"#])
        XCTAssertEqual(files(dir), [], "у работы из меню файла ответа нет")
        XCTAssertEqual(rig.notices, [])
        // Канал свободен: следующее пустое окно начинается.
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: nil))
    }

    func testCodeFromBeforeIsNotTaken() throws {
        let rig = Rig(now: t0, windows: [main])
        rig.ax = [main, code(40)]
        let (channel, _) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: nil))
        channel.pollBlank(at: t0.addingTimeInterval(1))
        XCTAssertTrue(rig.arranged.isEmpty)
        XCTAssertEqual(rig.polls, 2)
        channel.pollBlank(at: t0.addingTimeInterval(6))
        XCTAssertTrue(rig.arranged.isEmpty)
        XCTAssertEqual(rig.notices, [MenuModel.blankNoWindowNotice])
    }

    func testWindowTitledLaterAsCodeIsTaken() throws {
        let rig = Rig(now: t0, windows: [main])
        let (channel, _) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: nil))
        rig.ax = [main, code(51, title: "Claude")]
        channel.pollBlank(at: t0.addingTimeInterval(0.25))
        XCTAssertTrue(rig.arranged.isEmpty, "«Claude» — ещё не черновик, но и не чужое навсегда")
        rig.ax = [main, code(51)]
        channel.pollBlank(at: t0.addingTimeInterval(0.75))
        XCTAssertEqual(rig.arranged.first?.ids, [1, 51])
    }

    func testUntitledWindowWaitsOneSecondAndIsNotTaken() throws {
        let rig = Rig(now: t0, windows: [main])
        let (channel, _) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: nil))
        rig.ax = [main, code(52, title: "")]
        channel.pollBlank(at: t0.addingTimeInterval(6))
        XCTAssertEqual(rig.notices, [], "без заголовка — ждём ещё до 1 с")
        channel.pollBlank(at: t0.addingTimeInterval(7))
        XCTAssertTrue(rig.arranged.isEmpty)
        XCTAssertEqual(rig.notices, [MenuModel.blankNoWindowNotice])
    }

    func testTwoCodeCandidatesTakeNone() throws {
        let rig = Rig(now: t0, windows: [main])
        let (channel, _) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: nil))
        rig.ax = [main, code(53), code(54)]
        channel.pollBlank(at: t0.addingTimeInterval(0.5))
        channel.pollBlank(at: t0.addingTimeInterval(6))
        XCTAssertTrue(rig.arranged.isEmpty)
        XCTAssertEqual(rig.notices, [MenuModel.blankNoWindowNotice])
    }

    func testDraftOnServiceFrameIsTaken() throws {
        // Черновик встал ровно на рамку служебного окна: `windows` его не видит, AX — видит.
        let rig = Rig(now: t0, windows: [main])
        let (channel, _) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: nil))
        let token: CGWindowID = 0xF000_0001
        rig.ax = [main, code(token, frame: ClaudeApp.serviceWindowFrame)]
        channel.pollBlank(at: t0.addingTimeInterval(0.25))
        XCTAssertEqual(rig.arranged.first?.ids, [1, token])
        XCTAssertEqual(rig.log.dropFirst().first, "raise \(token)")
    }

    func testRequestAnswerIsBlankLast() throws {
        let rig = Rig(now: t0, windows: [main])
        let (channel, dir) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: "", id: "1790334000000-0101"))
        rig.ax = [main, code(50)]
        rig.now = t0.addingTimeInterval(2)
        channel.pollBlank(at: rig.now)
        let body = try String(contentsOf: dir.appendingPathComponent("1790334000000-0101.result.json"),
                              encoding: .utf8)
        XCTAssertEqual(body, #"{"id":"1790334000000-0101","at":"2026-09-26T09:00:02Z","ok":true,"error":"","fromResolved":false,"screen":"windows","window":{"title":"Code","chat":"","frame":[980,34,490,859]},"blank":true}"# + "\n")
    }

    func testRequestWindowMissingAfterSixSeconds() throws {
        let rig = Rig(now: t0, windows: [main])
        let (channel, dir) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: "r1"))
        channel.pollBlank(at: t0.addingTimeInterval(5.9))
        XCTAssertEqual(files(dir), [])
        channel.pollBlank(at: t0.addingTimeInterval(6))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appendingPathComponent("r1.result.json"))) as? [String: Any])
        XCTAssertEqual(json["error"] as? String, "window-missing")
        XCTAssertEqual(rig.notices, [], "запросу — код, не плашка")
    }

    func testBusyChannelAndForeignChainRefuse() throws {
        let rig = Rig(now: t0, windows: [main])
        let (channel, dir) = try channel(rig)
        XCTAssertTrue(channel.startBlank(project: project, place: .right, from: nil, id: nil))
        XCTAssertFalse(channel.startBlank(project: project, place: .right, from: nil, id: nil))
        XCTAssertFalse(channel.startLast(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(rig.notices, [MenuModel.blankBusyNotice, MenuModel.blankBusyNotice])
        XCTAssertEqual(rig.pressed, 1)
        // Запрос «новое окно» во время работы пустого окна — `busy`.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"id":"q1","at":"2026-09-26T09:00:00Z","action":"new-window","from":"","project":"VkusnoffKz"}"#.utf8)
            .write(to: dir.appendingPathComponent("q1.json"))
        // Файл «свежий» по часам стенда: иначе уборка канала сочла бы его часовой давности.
        try FileManager.default.setAttributes([.modificationDate: t0],
                                              ofItemAtPath: dir.appendingPathComponent("q1.json").path)
        channel.tick()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appendingPathComponent("q1.result.json"))) as? [String: Any])
        XCTAssertEqual(json["error"] as? String, "busy")
        XCTAssertTrue(rig.arranged.isEmpty, "тик пустое окно не двигает")

        let other = Rig(now: t0, windows: [main])
        other.busy = true
        let (second, _) = try self.channel(other)
        XCTAssertFalse(second.startBlank(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(other.pressed, 0, "чужая цепочка нового окна — пункт не жмём")
        XCTAssertEqual(other.notices, [MenuModel.blankBusyNotice])
    }

    func testRefusalsHaveTheirNotices() throws {
        let noMain = Rig(now: t0, windows: [code(9, title: "Чат")])
        let (a, _) = try channel(noMain)
        XCTAssertFalse(a.startBlank(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(noMain.pressed, 0, "без главного окна пункт не жмём")
        XCTAssertEqual(noMain.notices, [MenuModel.blankNoItemNotice])

        let noItem = Rig(now: t0, windows: [main])
        noItem.press = false
        let (b, dir) = try channel(noItem)
        XCTAssertFalse(b.startBlank(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(noItem.notices, [MenuModel.blankNoItemNotice])
        XCTAssertFalse(b.startBlank(project: project, place: .right, from: nil, id: "r2"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appendingPathComponent("r2.result.json"))) as? [String: Any])
        XCTAssertEqual(json["error"] as? String, "no-draft-item")

        let off = Rig(now: t0, windows: [main])
        off.running = false
        let (c, _) = try channel(off)
        XCTAssertFalse(c.startBlank(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(off.notices, [MenuModel.blankNoClaudeNotice])
    }

    // MARK: - «🪟 Новое окно ▸ проект» из меню жёлтой кнопки (проверка гейта WF94, #7749)

    func testMenuNewWindowGoesThroughChannelAndLandsRight() throws {
        let rig = Rig(now: t0, windows: [main])
        let (channel, dir) = try channel(rig)
        channel.seats.openNewWindow = { project, origin in
            rig.log.append("open \(project.name) \(origin == nil ? "без точки" : "в точке")")
        }
        XCTAssertTrue(channel.startNewWindow(project: project))
        XCTAssertEqual(rig.log, ["open VkusnoffKz без точки"])
        XCTAssertFalse(channel.startNewWindow(project: project), "канал занят — меню идёт прежним путём")
        rig.windows = [main, code(60)]
        channel.tick()
        XCTAssertEqual(rig.arranged.first?.ids, [1, 60], "новое окно встало самым правым")
        XCTAssertEqual(rig.arranged.first?.ordered, true)
        XCTAssertEqual(files(dir), [], "у работы из меню файла ответа нет")
    }

    // MARK: - «↩︎» последнее окно проекта

    func testLastChatOpenIsRaisedAndPlaced() throws {
        let rig = Rig(now: t0, windows: [main, PimpWindow(id: 7, title: "Чат", chat: "local_7",
                                                          frame: CGRect(x: 500, y: 34, width: 400, height: 800))])
        rig.last = (chat: "local_7", title: "Чат")
        let (channel, dir) = try channel(rig)
        XCTAssertTrue(channel.startLast(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(rig.log, ["raise 7", "arrange"])
        XCTAssertEqual(rig.opened, [])
        XCTAssertEqual(files(dir), [], "«↩︎» из меню через `finish` файла ответа не пишет")
    }

    func testLastChatClosedIsOpenedAndPlacedOnTick() throws {
        let rig = Rig(now: t0, windows: [main])
        rig.last = (chat: "local_8", title: "Чат")
        let (channel, dir) = try channel(rig)
        XCTAssertTrue(channel.startLast(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(rig.opened, ["local_8"])
        rig.windows = [main, PimpWindow(id: 8, title: "Чат", chat: "local_8")]
        channel.tick()
        XCTAssertEqual(rig.arranged.first?.ids, [1, 8])
        XCTAssertEqual(files(dir), [])
    }

    func testLastChatMissingAndWindowMissingNotices() throws {
        let rig = Rig(now: t0, windows: [main])
        let (channel, dir) = try channel(rig)
        XCTAssertFalse(channel.startLast(project: project, place: .right, from: nil, id: nil))
        XCTAssertEqual(rig.notices, [MenuModel.lastChatMissingNotice("VkusnoffKz")])
        rig.last = (chat: "local_9", title: "Долгий чат")
        XCTAssertTrue(channel.startLast(project: project, place: .right, from: nil, id: nil))
        rig.now = t0.addingTimeInterval(PimpChannel.restoreWindowSeconds + 1)
        channel.tick()
        XCTAssertEqual(rig.notices.last, MenuModel.lastChatNoWindowNotice("Долгий чат"))
        XCTAssertEqual(MenuModel.lastChatNoWindowNotice("Долгий чат"), "Окно чата Долгий чат не открылось — нажми ещё раз")
        XCTAssertEqual(files(dir), [])
    }
}
