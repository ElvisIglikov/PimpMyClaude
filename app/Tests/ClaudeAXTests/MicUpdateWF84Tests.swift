import AppKit
import XCTest
@testable import ClaudeAX

/// Батч M2 WF84: кружок-микрофон (#7054, контракт К4) и пункт «⬆️ Обновить Claude» у часов
/// (#7078, #7079). Всё на подставных данных: ни мыши, ни Диктатора, ни фида, ни живого Claude.
final class MicUpdateWF84Tests: XCTestCase {
    private static let id = "1756900000123-0042"
    private static let at = Date(timeIntervalSince1970: 1_756_900_000)

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("tests/fixtures/cashout", isDirectory: true)

    private func click(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target as? NSObject else {
            return XCTFail("у пункта «\(item.title)» нет действия")
        }
        target.perform(action)
    }

    private func page(_ kind: ChatPage.Kind, _ title: String, frame: CGRect? = nil,
                      mic: CGRect? = nil) -> ChatPage {
        ChatPage(kind: kind, chat: nil, title: title, store: "ok", frame: frame, mic: mic,
                 at: MicUpdateWF84Tests.at)
    }

    // MARK: - К4: команда `mic`

    func testMicCommandBytes() {
        XCTAssertEqual(ClaudeCommand.mic.rawValue, "mic")
        XCTAssertEqual(CommandChannel.payload(action: ClaudeCommand.mic.rawValue, fields: MicMode.dictator.fields,
                                              id: MicUpdateWF84Tests.id, at: MicUpdateWF84Tests.at),
                       "{\"id\":\"1756900000123-0042\",\"action\":\"mic\","
                       + "\"at\":\"2025-09-03T11:46:40Z\",\"mode\":\"dictator\"}")
        XCTAssertEqual(CommandChannel.payload(action: ClaudeCommand.mic.rawValue, fields: MicMode.claude.fields,
                                              id: MicUpdateWF84Tests.id, at: MicUpdateWF84Tests.at),
                       "{\"id\":\"1756900000123-0042\",\"action\":\"mic\","
                       + "\"at\":\"2025-09-03T11:46:40Z\",\"mode\":\"claude\"}")
    }

    /// Режим `dictator` — только пока Диктатор запущен; повтор — в каждом поколении страниц.
    func testMicModeFollowsDictatorPerGeneration() {
        let monitor = MicMonitor()
        var sent: [MicMode] = []
        monitor.sendMode = { sent.append($0); return true }
        let t0 = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(monitor.mode, .claude)
        monitor.tick(titles: [], at: t0)
        XCTAssertEqual(sent, [], "окон нет — слать некому")
        monitor.tick(titles: ["Claude"], at: t0)
        XCTAssertEqual(sent, [.claude], "Диктатора нет — режим Claude, и сразу")
        monitor.tick(titles: ["Claude"], at: t0.addingTimeInterval(10))
        XCTAssertEqual(sent, [.claude], "состав окон тот же — не повторяем")

        monitor.noteDictator(true)
        XCTAssertEqual(monitor.mode, .dictator)
        XCTAssertTrue(monitor.wantsPages, "Диктатор запущен — карта страниц кружку нужна")
        monitor.tick(titles: ["Claude"], at: t0.addingTimeInterval(11))
        XCTAssertEqual(sent, [.claude, .dictator], "Диктатор запустился — новым поколением, сразу")

        monitor.beginGeneration()
        monitor.tick(titles: ["Claude"], at: t0.addingTimeInterval(12))
        XCTAssertEqual(sent, [.claude, .dictator, .dictator], "перезапуск Claude — режим заново")

        monitor.noteDictator(false)
        monitor.tick(titles: ["Claude"], at: t0.addingTimeInterval(13))
        XCTAssertEqual(sent.last, .claude, "Диктатор вышел — его клавиша ушла бы в поле текстом")
        XCTAssertTrue(monitor.status.hasPrefix("claude/"))
    }

    // MARK: - клавиша Диктатора

    func testDictatorHotkeyFromDefaults() {
        let f5 = DictatorHotkey.from(keyCode: NSNumber(value: 96), modifiers: NSNumber(value: 0))
        XCTAssertEqual(f5, DictatorHotkey(keyCode: 96, modifiers: 0), "у Элвиса F5 без модификаторов (S0)")
        XCTAssertEqual(f5.flags, [.maskSecondaryFn], "F-клавиша без fn Carbon-клавишу Диктатора не будит (26.09)")

        let optionCommand = DictatorHotkey.from(keyCode: NSNumber(value: 2), modifiers: NSNumber(value: 2 | 8))
        XCTAssertEqual(optionCommand.flags, [.maskAlternate, .maskCommand])
        let controlShift = DictatorHotkey.from(keyCode: NSNumber(value: 2), modifiers: NSNumber(value: 1 | 4 | 64))
        XCTAssertEqual(controlShift.flags, [.maskControl, .maskShift], "чужие биты отбрасываются")

        XCTAssertEqual(DictatorHotkey.from(keyCode: nil, modifiers: nil), DictatorHotkey.factory,
                       "ключей нет — заводская ⌥D Диктатора")
        XCTAssertEqual(DictatorHotkey.factory.flags, [.maskAlternate])
        XCTAssertEqual(DictatorHotkey.from(keyCode: NSNumber(value: 500), modifiers: NSNumber(value: 8)),
                       DictatorHotkey.factory, "код вне 0…127 — заводская целиком")
        XCTAssertEqual(DictatorHotkey.from(keyCode: "F5", modifiers: nil), DictatorHotkey.factory)
    }

    // MARK: - место кружка (поле `mic` в chats())

    func testParseMicSpot() throws {
        // Эталон батча P: у попапа в режиме письма кружка нет — `mic: null`.
        let raw = try Data(contentsOf: MicUpdateWF84Tests.fixtures.appendingPathComponent("probe-answer-popout.json"))
        var result = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let nonce = try XCTUnwrap(result["nonce"] as? String)
        func parse(_ result: [String: Any]) throws -> ChatPage? {
            let body: [String: Any] = ["at": "2026-09-23T18:00:00Z",
                                       "results": [["id": 1, "source": ProbeSourceFixture.metadata(url: "about:blank"), "url": "about:blank", "result": result]]]
            return ChatProbe.parseAnswer(try JSONSerialization.data(withJSONObject: body), nonce: nonce,
                                         at: MicUpdateWF84Tests.at).pages.first
        }
        XCTAssertNotNil(try parse(result))
        XCTAssertNil(try parse(result)?.mic)

        result["mic"] = [58, 41, 22, 22]
        XCTAssertEqual(try parse(result)?.mic, CGRect(x: 58, y: 41, width: 22, height: 22))

        XCTAssertNil(ChatProbe.micSpot([0, 41, 22, 22]), "значок у самого края — не внутри окна")
        XCTAssertNil(ChatProbe.micSpot([58, 41, 22]))
        XCTAssertNil(ChatProbe.micSpot(["58", 41, 22, 22]))
        XCTAssertNil(ChatProbe.micSpot(NSNull()))
        XCTAssertNil(ChatProbe.micSpot(nil))
    }

    func testMicRectFromRightBottomEdge() {
        let window = CGRect(x: 100, y: 50, width: 500, height: 800)
        let spot = CGRect(x: 58, y: 41, width: 22, height: 22)
        let rect = MicMonitor.micRect(spot: spot, window: window)
        XCTAssertEqual(rect, CGRect(x: 542, y: 809, width: 22, height: 22))
        XCTAssertTrue(MicMonitor.contains(rect, CGPoint(x: 553, y: 820)))
        XCTAssertTrue(MicMonitor.contains(rect, CGPoint(x: 541, y: 808)), "допуск в пару точек")
        XCTAssertFalse(MicMonitor.contains(rect, CGPoint(x: 530, y: 820)))
        // Окно подвинули и растянули — место живёт от правого нижнего угла.
        let moved = MicMonitor.micRect(spot: spot, window: CGRect(x: -800, y: 0, width: 700, height: 900))
        XCTAssertEqual(moved.origin, CGPoint(x: -158, y: 859))
    }

    func testPageForWindow() {
        let left = CGRect(x: 0, y: 25, width: 500, height: 800)
        let right = CGRect(x: 520, y: 25, width: 500, height: 800)
        let spot = CGRect(x: 58, y: 41, width: 22, height: 22)
        let pages = [page(.main, "Claude", frame: left, mic: spot),
                     page(.popout, "VkusnoffKz · заказы", frame: right, mic: nil),
                     page(.other, "VkusnoffKz · заказы", frame: right, mic: spot)]
        XCTAssertEqual(MicMonitor.page(window: left, title: "Claude", in: pages)?.kind, .main)
        XCTAssertEqual(MicMonitor.page(window: right, title: "VkusnoffKz · заказы", in: pages)?.kind, .popout,
                       "чужая страница (артефакт) не в счёт")
        XCTAssertNil(MicMonitor.page(window: right, title: "VkusnoffKz · заказы", in: pages)?.mic,
                     "у этого окна кружка нет — клик мимо")

        // Однофамильцы — решает рамка.
        let twins = [page(.popout, "Ожидание", frame: left, mic: spot),
                     page(.popout, "Ожидание", frame: right, mic: nil)]
        XCTAssertEqual(MicMonitor.page(window: right.offsetBy(dx: 5, dy: 0), title: "Ожидание", in: twins)?.frame,
                       right)

        // Заголовок не сошёлся (метка замка К6) — только по углу рамки и только один.
        XCTAssertEqual(MicMonitor.page(window: left, title: "Пимп жмёт Allow · чат", in: pages)?.kind, .main)
        XCTAssertNil(MicMonitor.page(window: CGRect(x: 300, y: 300, width: 500, height: 500),
                                     title: "Пимп жмёт Allow · чат", in: pages),
                     "угол далеко от всех — страницы нет, даже если она одна")
        XCTAssertNil(MicMonitor.page(window: left, title: "Нечто",
                                     in: [page(.main, "Claude", frame: nil, mic: spot)]))
    }

    func testFrontWindowAtPoint() {
        let point = CGPoint(x: 100, y: 100)
        let windows = [
            MicMonitor.ScreenWindow(pid: 7, frame: CGRect(x: 0, y: 0, width: 300, height: 300), alpha: 1),
            MicMonitor.ScreenWindow(pid: 9, frame: CGRect(x: 0, y: 0, width: 300, height: 300), alpha: 0),
            MicMonitor.ScreenWindow(pid: 5, frame: CGRect(x: 500, y: 0, width: 300, height: 300), alpha: 1),
            MicMonitor.ScreenWindow(pid: 42, frame: CGRect(x: 0, y: 0, width: 800, height: 800), alpha: 1),
            MicMonitor.ScreenWindow(pid: 11, frame: CGRect(x: 0, y: 0, width: 800, height: 800), alpha: 1),
        ]
        XCTAssertEqual(MicMonitor.frontWindow(at: point, in: windows, ownPID: 7)?.pid, 42,
                       "свои окна и прозрачные мимо — клик уходит сквозь них")
        XCTAssertEqual(MicMonitor.frontWindow(at: point, in: windows, ownPID: 1)?.pid, 7)
        XCTAssertNil(MicMonitor.frontWindow(at: CGPoint(x: 900, y: 900), in: windows, ownPID: 1))
    }

    // MARK: - меню «🎙 Рик»

    func testRickVoicesFromConfig() {
        let config = """
            {"current":"babka","voices":{
              "rick":{"voice_id":"a","name":"Рик Санчез"},
              "babka":{"voice_id":"b","name":"Бабка у подъезда"},
              "empty":{"voice_id":"c","name":" "},
              "junk":"строка"}}
            """
        let parsed = RickVoices.parse(Data(config.utf8))
        XCTAssertEqual(parsed.voices, [RickVoice(alias: "babka", name: "Бабка у подъезда"),
                                       RickVoice(alias: "rick", name: "Рик Санчез")])
        XCTAssertEqual(parsed.current, "babka")
        XCTAssertTrue(RickVoices.parse(Data("не json".utf8)).voices.isEmpty)
        XCTAssertTrue(RickVoices.parse(nil).voices.isEmpty)
    }

    func testRickMenuItems() throws {
        var used: [String] = []
        var repeats = 0
        let menu = MicMonitor.rickMenu(voices: [RickVoice(alias: "babka", name: "Бабка у подъезда"),
                                                RickVoice(alias: "rick", name: "Рик Санчез")],
                                       current: "babka",
                                       use: { used.append($0.alias) }, repeatLast: { repeats += 1 })
        XCTAssertEqual(menu.items.map { $0.title },
                       [MicMonitor.rickTitle, "● Бабка у подъезда", "○ Рик Санчез", "", MicMonitor.repeatTitle])
        XCTAssertFalse(menu.items[0].isEnabled, "заголовок — не пункт")
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        click(menu.items[2])
        click(menu.items[4])
        XCTAssertEqual(used, ["rick"])
        XCTAssertEqual(repeats, 1)
    }

    // MARK: - карта страниц, пока кружок нужен

    func testProbeRefreshesWhileMicWanted() throws {
        var now = Date(timeIntervalSince1970: 1_757_100_000)
        var script: String?
        var scriptVersion = 0
        var result: Data?
        var resultVersion = 0
        var writes = 0
        let files = ChatProbeFiles(
            scriptInfo: { script == nil ? nil : ("\(scriptVersion)", now) },
            readScript: { script },
            writeScript: { text in script = text; scriptVersion += 1; writes += 1; return true },
            resultInfo: { result == nil ? nil : "\(resultVersion)" },
            readResult: { result })
        let probe = ChatProbe(files: files, now: { now }, random: { 1 })
        var wanted = false
        probe.isEnabled = { false }
        probe.isMicWanted = { wanted }
        let windows: [(title: String, frame: CGRect?)] = [(title: "Claude", frame: nil)]
        func answer() throws {
            let nonce = try XCTUnwrap(script.flatMap { ChatProbe.markNonce($0) })
            let page: [String: Any] = ["v": 1, "nonce": nonce, "kind": "main", "title": "Claude", "store": "ok",
                                       "frame": [0, 25, 500, 800], "mic": [58, 41, 22, 22]]
            result = try JSONSerialization.data(withJSONObject: ["at": "x", "results": [["id": 1,
                "source": ProbeSourceFixture.metadata(url: "https://claude.ai/epitaxy"), "url": "https://claude.ai/epitaxy", "result": page]]])
            resultVersion += 1
        }

        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(writes, 0, "тумблер выключен и кружок не нужен — канала не касаемся")

        wanted = true
        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(writes, 1, "кружок нужен — канал открыт при любом тумблере")
        try answer()
        now = now.addingTimeInterval(2)
        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(probe.pages.first?.mic, CGRect(x: 58, y: 41, width: 22, height: 22))
        XCTAssertEqual(writes, 1, "пол частоты — 15 с")
        now = now.addingTimeInterval(ChatProbe.askInterval)
        probe.tick(windows: windows, indexRevision: 1)
        XCTAssertEqual(writes, 2, "без нового повода — всё равно раз в пол частоты: место значка меняется молча")
    }

    // MARK: - «⬆️ Обновить Claude» (#7078, #7079)

    func testUpdateMenuChecksFeedOnceInTenMinutes() {
        var menu = ClaudeUpdateMenu()
        let t0 = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(menu.phase, .idle, "ничего не знаем — блока нет (WF86: «Обновить» без обновления не висит, #7639)")
        XCTAssertTrue(menu.beginCheck(at: t0), "первое открытие меню — спросить источники")
        XCTAssertFalse(menu.beginCheck(at: t0), "вопрос уже идёт — второго нет")
        menu.finish(.latest(installed: "2.2553.13"), at: t0)
        XCTAssertEqual(menu.known, .latest(installed: "2.2553.13"))
        XCTAssertEqual(menu.phase, .idle, "последняя — предлагать нечего")
        XCTAssertFalse(menu.beginCheck(at: t0.addingTimeInterval(599)), "не чаще раза в 10 минут")
        XCTAssertTrue(menu.beginCheck(at: t0.addingTimeInterval(600)))
        menu.finish(.available(version: "2.2560.1"), at: t0.addingTimeInterval(601))
        XCTAssertEqual(menu.phase, .available(version: "2.2560.1"))

        menu.forget()
        XCTAssertEqual(menu.known, .unknown, "Claude обновился — прежний ответ не про него")
        XCTAssertTrue(menu.beginCheck(at: t0.addingTimeInterval(602)))
        menu.finish(.failed("нет сети"), at: t0.addingTimeInterval(603))
        XCTAssertFalse(menu.beginCheck(at: t0.addingTimeInterval(700)), "осечка тоже ответ — сеть не дёргаем")
        XCTAssertEqual(menu.phase, .failed("нет сети"), "не узнал — это не «последняя»")
    }
}
