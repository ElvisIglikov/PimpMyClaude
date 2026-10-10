import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Притемнение окон (WF113), отсчёт отправки и его показ (WF119), прежний CLI и разворот
/// спрятанного окна, где ждут Элвиса (#8282). AX и живого диска тут нет: UserDefaults — своя папка,
/// команды — в память.
final class PageLookWF113Tests: XCTestCase {
    private typealias Sent = (action: String, json: String, priority: CommandChannel.Priority)

    private func makeSettings(running: Bool = true) -> (PageLookSettings, UserDefaults, () -> [Sent]) {
        let suite = "wf113-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = PageLookSettings(defaults: defaults)
        var sent: [Sent] = []
        settings.write = { action, fields, priority in
            sent.append((action, CommandValue.object(fields).json, priority))
            return true
        }
        settings.mainMatch = { "/epitaxy/local_main" }
        settings.isRunning = { running }
        return (settings, defaults, { sent })
    }

    // MARK: - 1. память и команды

    func testDefaultsWhenNothingStored() {
        let (settings, _, _) = makeSettings()
        XCTAssertEqual(settings.current, PageLook(dimOn: false, dimPercent: 50, style: "1.8", size: 100))
    }

    func testDimSwitchWritesAndSendsAtOnce() {
        let (settings, defaults, sent) = makeSettings()
        let look = settings.setDim(on: true)
        XCTAssertTrue(look.dimOn)
        XCTAssertTrue(defaults.bool(forKey: DimSetting.onKey))
        XCTAssertEqual(sent().count, 1)
        XCTAssertEqual(sent()[0].action, "dim")
        XCTAssertEqual(sent()[0].json, "{\"on\":true,\"level\":0.5,\"keep\":[]}")
        XCTAssertEqual(sent()[0].priority, .normal)
    }

    func testDimLevelWritesImmediatelyFromCLI() {
        let (settings, defaults, sent) = makeSettings()
        settings.setDim(on: true, percent: 65)
        XCTAssertEqual(defaults.double(forKey: DimSetting.levelKey), 0.65)
        XCTAssertEqual(sent().last?.json, "{\"on\":true,\"level\":0.65,\"keep\":[]}")
        XCTAssertEqual(sent().last?.priority, .normal)
    }

    func testDimPercentClampedToSlider() {
        let (settings, _, _) = makeSettings()
        XCTAssertEqual(settings.setDim(on: true, percent: 95).dimPercent, 80)
        XCTAssertEqual(settings.setDim(percent: 3).dimPercent, 20)
        XCTAssertEqual(settings.setDim(percent: 52).dimPercent, 50)
    }

    /// Прежний CLI show — выбор и показ в главном окне: оба поля вместе, `match` главного.
    func testLegacyLookSendsChosenStyleAndPreviewsInMain() {
        let (settings, defaults, sent) = makeSettings()
        let done = settings.setLook(style: "1.4", show: true)
        XCTAssertTrue(done.shown)
        XCTAssertEqual(done.look.style, "1.4")
        XCTAssertEqual(defaults.string(forKey: SendLook.styleKey), "1.4")
        XCTAssertEqual(sent().count, 1)
        XCTAssertEqual(sent()[0].action, "send-look")
        XCTAssertEqual(sent()[0].json,
                       "{\"style\":\"1.4\",\"size\":100,\"preview\":true,\"match\":\"/epitaxy/local_main\"}")
        XCTAssertEqual(settings.setLook(style: "1.3").look.style, "1.4", "1.3 (К1 v3) не принимается")
    }

    func testClaudeClosedRemembersButDoesNotShow() {
        let (settings, defaults, sent) = makeSettings(running: false)
        let done = settings.setLook(style: "1.6", size: 140, show: true)
        XCTAssertFalse(done.shown)
        XCTAssertEqual(defaults.integer(forKey: SendLook.sizeKey), 140)
        XCTAssertEqual(sent()[0].json, "{\"style\":\"1.6\",\"size\":140,\"preview\":false}")
    }

    func testCLISizeAndGrowStayInRange() {
        let (settings, _, _) = makeSettings()
        XCTAssertEqual(settings.setLook(size: 130, show: true).look.size, 130)
        XCTAssertEqual(settings.setLook(grow: 100).look.size, 200)
        XCTAssertEqual(settings.setLook(grow: -500).look.size, 60)
        XCTAssertEqual(settings.setLook(size: 94).look.size, 90, "шаг размера — 10")
        XCTAssertEqual(settings.setLook(style: "1.7").look.style, "1.8", "чужой вид не записывается")
    }

    /// Поколение страниц (правило trust-root): первый тик с окнами — оба выбора, без показа.
    func testGenerationResendsBothWithoutPreview() {
        let (settings, _, sent) = makeSettings()
        settings.setLook(style: "1.2", size: 80)
        settings.setDim(on: true, percent: 40)
        let before = sent().count
        settings.beginGeneration()
        let t0 = Date(timeIntervalSince1970: 1_790_200_000)
        settings.tick(titles: [], at: t0)
        XCTAssertEqual(sent().count, before, "окон нет — слать некому")
        settings.tick(titles: ["Claude"], at: t0)
        let fresh = sent().dropFirst(before).map { "\($0.action) \($0.json)" }
        XCTAssertEqual(fresh, ["dim {\"on\":true,\"level\":0.4,\"keep\":[]}",
                               "send-look {\"style\":\"1.2\",\"size\":80,\"preview\":false}"])
        settings.tick(titles: ["Claude"], at: t0.addingTimeInterval(10))
        XCTAssertEqual(sent().count, before + 2, "состав окон тот же — повтора нет")
    }

    func testSendDelayWireMatchesContract() {
        for (id, on, stamp) in [("wf119-delay-on", true, "2026-10-03T00:00:00Z"),
                                ("wf119-delay-off", false, "2026-10-03T00:00:01Z")] {
            let setting = SendDelaySetting(on: on, seconds: 3)
            XCTAssertEqual(CommandChannel.payload(action: SendDelaySetting.action, fields: setting.fields,
                                                  id: id, at: PimpChannel.date(stamp)!),
                           "{\"id\":\"\(id)\",\"action\":\"send-delay\",\"at\":\"\(stamp)\",\"on\":\(on),\"seconds\":3}")
        }
    }

    func testSendDelayReadAndGenerationsNeverCreateChoice() {
        let (settings, defaults, sent) = makeSettings()
        var page = ChatPage(kind: .popout, chat: "local_a", title: "А", store: "ok", at: Self.at)
        page.sendDelaySetting = SendDelaySetting(on: false, seconds: 10)
        var other = page
        other.sendDelaySetting = SendDelaySetting(on: true, seconds: 3)
        XCTAssertEqual(settings.sendDelaySetting(pages: []), SendDelaySetting())
        XCTAssertEqual(settings.sendDelaySetting(pages: [page, other]), page.sendDelaySetting)
        settings.beginGeneration()
        for n in 0..<5 { settings.tick(titles: ["\(n)"], at: Self.at.addingTimeInterval(Double(n) * 6)) }
        XCTAssertFalse(sent().contains { $0.action == "send-delay" })
        XCTAssertNil(defaults.object(forKey: SendDelaySetting.key))
        defaults.set(["on": true, "seconds": 0], forKey: SendDelaySetting.key)
        settings.beginGeneration()
        settings.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(settings.sendDelaySetting(pages: [page]), page.sendDelaySetting)
        XCTAssertFalse(sent().contains { $0.action == "send-delay" }, "негодный ключ тоже не рассылается")
    }

    func testExplicitSendDelayRemembersImmediatelyAndRepeatsBoundedGeneration() {
        let (settings, defaults, sent) = makeSettings(running: false)
        settings.setSendDelay(on: false, seconds: 10)
        XCTAssertEqual(settings.savedSendDelay, SendDelaySetting(on: false, seconds: 10))
        XCTAssertEqual(settings.sendDelaySetting(pages: []), SendDelaySetting(on: false, seconds: 10))
        XCTAssertEqual(sent().last?.json, "{\"on\":false,\"seconds\":10}")
        XCTAssertEqual(sent().last?.priority, .normal)
        settings.beginGeneration()
        settings.tick(titles: [], at: Self.at)
        XCTAssertEqual(sent().filter { $0.action == "send-delay" }.count, 1)
        settings.tick(titles: ["А"], at: Self.at)
        settings.tick(titles: ["Б"], at: Self.at.addingTimeInterval(2))
        XCTAssertEqual(sent().filter { $0.action == "send-delay" }.count, 2)
        settings.tick(titles: ["А"], at: Self.at.addingTimeInterval(6))
        XCTAssertEqual(sent().filter { $0.action == "send-delay" }.count, 2, "тот же состав не повторяется")
        for n in 1...4 { settings.tick(titles: ["\(n)"], at: Self.at.addingTimeInterval(Double(n) * 6)) }
        XCTAssertEqual(sent().filter { $0.action == "send-delay" }.count, 4, "только три повтора")
        settings.setSendDelay(on: true, seconds: 10)
        settings.tick(titles: ["4"], at: Self.at.addingTimeInterval(25))
        XCTAssertEqual(sent().filter { $0.action == "send-delay" }.count, 6, "явный выбор начинает поколение")
        XCTAssertEqual(PageLookSettings(defaults: defaults).savedSendDelay, SendDelaySetting(on: true, seconds: 10))
        let before = sent().count
        settings.setSendDelay(on: true, seconds: 0)
        XCTAssertEqual(sent().count, before)
        XCTAssertEqual(settings.savedSendDelay?.seconds, 10)
    }

    /// «Закреплённые» (#8743): без выбора — показывать и молчать; выбор уходит сразу и повторяется поколением.
    func testPinnedLookDefaultsShowAndExplicitChoiceRepeats() {
        let (settings, defaults, sent) = makeSettings()
        XCTAssertEqual(settings.pinned, PinnedLook(folder: true, clock: true))
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertTrue(sent().filter { $0.action == "pinned-look" }.isEmpty, "выбора нет — страницам ничего не шлём")
        XCTAssertNil(defaults.object(forKey: PinnedLook.folderKey))
        settings.setPinned(PinnedLook(folder: false, clock: true))
        XCTAssertEqual(sent().last?.action, "pinned-look")
        XCTAssertEqual(sent().last?.json, "{\"folder\":false,\"clock\":true}")
        XCTAssertEqual(PageLookSettings(defaults: defaults).pinned, PinnedLook(folder: false, clock: true))
        settings.tick(titles: ["А"], at: Self.at)
        XCTAssertEqual(sent().filter { $0.action == "pinned-look" }.count, 2, "новое поколение страниц узнаёт выбор")
        settings.setPinned(PinnedLook(folder: false, clock: false))
        XCTAssertEqual(sent().last?.json, "{\"folder\":false,\"clock\":false}")
        XCTAssertEqual(settings.pinned, PinnedLook(folder: false, clock: false))
    }

    func testDimResetPreservesSnapshotLevelAndOtherChoices() {
        let (settings, defaults, sent) = makeSettings()
        defaults.set(true, forKey: DimSetting.onKey)
        defaults.set(0.7, forKey: DimSetting.levelKey)
        defaults.set(false, forKey: AutomationDefaults.allowKey)
        defaults.set(["on": false, "seconds": 3], forKey: SendDelaySetting.key)
        let snapshot = defaults.dictionaryRepresentation()
        XCTAssertTrue(settings.current.dimOn, "init не снимает флаг до снимка")
        DimSetting.resetOnLaunch(defaults)
        XCTAssertEqual(snapshot[DimSetting.onKey] as? Bool, true)
        XCTAssertNil(defaults.object(forKey: DimSetting.onKey))
        XCTAssertEqual(settings.current.dimPercent, 70)
        XCTAssertEqual(defaults.object(forKey: AutomationDefaults.allowKey) as? Bool, false)
        XCTAssertEqual(settings.savedSendDelay, SendDelaySetting(on: false, seconds: 3))
        settings.tick(titles: ["Claude"], at: Self.at)
        XCTAssertEqual(sent().first(where: { $0.action == "dim" })?.json, "{\"on\":false,\"level\":0.7,\"keep\":[]}")
    }

    func testPanelPreviewWireAndLegacyBroadcast() {
        let (settings, defaults, sent) = makeSettings()
        XCTAssertTrue(settings.previewSendDelay(seconds: 3, match: "/epitaxy/local_main", chat: nil))
        XCTAssertTrue(settings.previewSendDelay(seconds: 10, match: nil, chat: "local_aaaa-1111"))
        XCTAssertEqual(sent().map { $0.json }, [
            "{\"style\":\"1.8\",\"size\":100,\"preview\":true,\"seconds\":3,\"match\":\"/epitaxy/local_main\"}",
            "{\"style\":\"1.8\",\"size\":100,\"preview\":true,\"seconds\":10,\"chat\":\"local_aaaa-1111\"}"])
        for (id, stamp, seconds, match, chat) in [
            ("wf119-preview-main", "2026-10-03T00:00:02Z", 3, "/epitaxy/local_main" as String?, nil as String?),
            ("wf119-preview-popout", "2026-10-03T00:00:03Z", 10, nil, "local_aaaa-1111")
        ] {
            let fields = SendLook.fields(style: "1.5", size: 100, preview: true, match: match, seconds: seconds, chat: chat)
            let address = match.map { "\"match\":\"\($0)\"" } ?? "\"chat\":\"\(chat!)\""
            XCTAssertEqual(CommandChannel.payload(action: SendLook.action, fields: fields, id: id, at: PimpChannel.date(stamp)!),
                "{\"id\":\"\(id)\",\"action\":\"send-look\",\"at\":\"\(stamp)\",\"style\":\"1.5\",\"size\":100,\"preview\":true,\"seconds\":\(seconds),\(address)}")
        }
        XCTAssertTrue(sent().allSatisfy { $0.priority == .normal })
        XCTAssertNil(defaults.object(forKey: SendDelaySetting.key))
        XCTAssertNil(defaults.object(forKey: SendLook.styleKey))
        XCTAssertFalse(settings.previewSendDelay(seconds: 0, match: "/epitaxy", chat: nil))
        XCTAssertFalse(settings.previewSendDelay(seconds: 5, match: "blank", chat: nil))
        XCTAssertFalse(settings.previewSendDelay(seconds: 5, match: nil, chat: nil))
        XCTAssertFalse(settings.previewSendDelay(seconds: 5, match: "/epitaxy", chat: "local_a"))
        XCTAssertEqual(sent().count, 2)
        settings.mainMatch = { nil }
        settings.setLook(show: true)
        XCTAssertEqual(sent().last?.json, "{\"style\":\"1.8\",\"size\":100,\"preview\":true}")
        XCTAssertEqual(CommandChannel.payload(action: SendLook.action,
            fields: SendLook.fields(style: "1.3", size: 100, preview: false, match: "/epitaxy", seconds: 3, chat: "local_a"),
            id: "wf119-look-broadcast", at: PimpChannel.date("2026-10-03T00:00:04Z")!),
            "{\"id\":\"wf119-look-broadcast\",\"action\":\"send-look\",\"at\":\"2026-10-03T00:00:04Z\",\"style\":\"1.8\",\"size\":100,\"preview\":false}")
    }

    func testPreviewChoosesVisibleUniqueIdentity() {
        let main = ChatPage(kind: .main, chat: "local_main", title: "Claude", path: "/epitaxy/local_main", store: "ok", at: Self.at)
        let pop = ChatPage(kind: .popout, chat: "local_pop", title: "Чат", path: "blank", store: "ok", at: Self.at)
        let front = ChatPage(kind: .popout, chat: "local_front", title: "Впереди", path: "blank", store: "ok", at: Self.at)
        let pages = [main, pop, front]
        let visible: [(id: CGWindowID, page: ChatPage?)] = [(3, front), (1, main), (2, pop)]
        XCTAssertEqual(ClaudeActions.sendDelayPreviewTarget(visible: visible, focused: 2, pages: pages)?.chat, "local_pop")
        XCTAssertEqual(ClaudeActions.sendDelayPreviewTarget(visible: visible, focused: nil, pages: pages)?.match, main.path)
        XCTAssertEqual(ClaudeActions.sendDelayPreviewTarget(visible: [(3, front), (2, pop)], focused: nil, pages: pages)?.id, 3)
        XCTAssertEqual(ClaudeActions.sendDelayPreviewTarget(visible: [(2, pop)], focused: 1, pages: pages)?.id, 2,
                       "скрытое главное не выбирается")
        XCTAssertNil(ClaudeActions.sendDelayPreviewTarget(visible: [], focused: 1, pages: pages))
        XCTAssertNil(ClaudeActions.sendDelayPreviewTarget(visible: [(1, nil)], focused: 1, pages: pages))
        XCTAssertNil(ClaudeActions.sendDelayPreviewTarget(visible: [(2, pop)], focused: 2, pages: pages + [pop]),
                     "один chat у двух страниц — отказ")
        XCTAssertNil(ClaudeActions.sendDelayPreviewTarget(visible: [(1, main)], focused: nil, pages: pages + [main]))
        let changed = ChatPage(kind: .main, chat: "local_new", title: "Claude", path: "/epitaxy/local_new", store: "ok", at: Self.at)
        let before = ClaudeActions.sendDelayPreviewTarget(visible: [(1, main)], focused: nil, pages: pages)
        XCTAssertNotEqual(ClaudeActions.sendDelayPreviewTarget(visible: [(1, changed)], focused: nil, pages: [changed]), before,
                          "смена адреса отменяет отложенный показ")
        let blank = ChatPage(kind: .main, chat: nil, title: "Claude", path: "blank", store: "ok", at: Self.at)
        XCTAssertNil(ClaudeActions.sendDelayPreviewTarget(visible: [(1, blank)], focused: nil, pages: [blank]))
    }

    // MARK: - 1а. главный проект (гейт WF111, #8284): keep команды dim

    func testMainProjectSettingParsedLikeMainChat() {
        XCTAssertEqual(PimpChannel.mainProjectSetting(Data("{\"mainProject\":\" Dictator \"}".utf8)), "Dictator")
        XCTAssertNil(PimpChannel.mainProjectSetting(Data("{\"mainProject\":\"\"}".utf8)))
        XCTAssertNil(PimpChannel.mainProjectSetting(Data("{\"mainProject\":5}".utf8)))
        XCTAssertNil(PimpChannel.mainProjectSetting(Data("{\"mainChat\":\"Rick\"}".utf8)), "нет ключа — нет")
        XCTAssertNil(PimpChannel.mainProjectSetting(nil))
    }

    func testMainProjectChatsByFolder() {
        let windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: "/p/Other"),
            PimpWindow(id: 2, title: "Рик", chat: "local_rick", folder: "/p/Dictator"),
            PimpWindow(id: 3, title: "Рик 2", chat: "local_rick2", folder: "/p/Dictator"),
            PimpWindow(id: 4, title: "Рик 3", chat: "", folder: "/p/Dictator"),
            PimpWindow(id: 5, title: "Рик дубль", chat: "local_rick", folder: "/p/Dictator"),
        ]
        XCTAssertEqual(PimpChannel.mainProjectChats(windows, entry: "Dictator"), ["local_rick", "local_rick2"])
        XCTAssertEqual(PimpChannel.mainProjectChats(windows, entry: "/p/Dictator"), ["local_rick", "local_rick2"])
        XCTAssertEqual(PimpChannel.mainProjectChats(windows, entry: nil), [])
        XCTAssertEqual(PimpChannel.mainProjectChats(windows, entry: "dictator"), [], "как matches(folder:): регистр важен")
    }

    func testDimCarriesKeepOnlyWhenSet() {
        XCTAssertEqual(CommandValue.object(DimSetting.fields(on: true, percent: 50)).json, "{\"on\":true,\"level\":0.5,\"keep\":[]}")
        XCTAssertEqual(CommandValue.object(DimSetting.fields(on: false, percent: 50, keep: ["local_a", "Рик"])).json,
                       "{\"on\":false,\"level\":0.5,\"keep\":[\"local_a\"]}")
        let many = (0..<40).map { "local_\($0)" }
        let json = CommandValue.object(DimSetting.fields(on: true, percent: 50, keep: many)).json
        XCTAssertTrue(json.contains("\"local_31\"") && !json.contains("\"local_32\""), "не больше 32")
    }

    /// Набор окон главного проекта сменился — dim уходит заново (поколением), тот же — повтора нет.
    func testKeepChangeResendsDim() {
        let (settings, _, sent) = makeSettings()
        let t0 = Date(timeIntervalSince1970: 1_790_200_000)
        settings.tick(titles: ["Claude", "Рик"], at: t0)
        let before = sent().count
        settings.setKeep(["local_rick"])
        settings.tick(titles: ["Claude", "Рик"], at: t0.addingTimeInterval(2))
        XCTAssertEqual(sent().dropFirst(before).map { "\($0.action) \($0.json)" },
                       ["dim {\"on\":false,\"level\":0.5,\"keep\":[\"local_rick\"]}"])
        settings.setKeep(["local_rick"])
        settings.tick(titles: ["Claude", "Рик"], at: t0.addingTimeInterval(4))
        XCTAssertEqual(sent().count, before + 1, "тот же набор — тишина")
        settings.setDim(on: true)
        XCTAssertEqual(sent().last?.json, "{\"on\":true,\"level\":0.5,\"keep\":[\"local_rick\"]}", "выключатель несёт keep")
        settings.setKeep([])
        settings.tick(titles: ["Claude", "Рик"], at: t0.addingTimeInterval(6))
        XCTAssertEqual(sent().last?.json, "{\"on\":true,\"level\":0.5,\"keep\":[]}", "ключ сняли — явно очищаем исключения")
    }

    // MARK: - 2. канал по эталонам

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: PageLookWF113Tests.fixtures.appendingPathComponent(name), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf113-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testChannelAnswersDimAndLookByFixtures() throws {
        let box = makeTemp()
        let (settings, defaults, _) = makeSettings()
        var now = PimpChannel.date("2026-09-29T20:10:01Z")!
        let pimp = PimpChannel(directory: box, now: { now })
        pimp.seats.setDim = { on, percent in settings.setDim(on: on, percent: percent) }
        pimp.seats.setLook = { style, size, grow, show in
            settings.setLook(style: style, size: size, grow: grow, show: show)
        }
        pimp.start()

        /// `swap` — правка текста эталона на лету: `look.request.json` просит «1.3», а с К1 v3 (WF128) он
        /// не принимается — берём «1.2» «Удар»; `answerSwap` — те же правки ответа. Эталон не трогаем
        /// (владелец эталонов — не Swift-батч).
        func ask(_ request: String, id: String, at: String, answer: String, swap: (String, String)? = nil,
                 answerSwap: [(String, String)] = []) throws {
            now = PimpChannel.date(at)!
            var text = try fixture(request)
            if let swap = swap { text = text.replacingOccurrences(of: swap.0, with: swap.1) }
            try Data(text.utf8).write(to: box.appendingPathComponent(id + ".json"))
            pimp.tick()
            let got = try String(contentsOf: box.appendingPathComponent(id + ".result.json"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var want = try fixture(answer)
            for (old, new) in answerSwap { want = want.replacingOccurrences(of: old, with: new) }
            XCTAssertEqual(got, want, request)
        }
        try ask("dim.request.json", id: "1790200000000-2201", at: "2026-09-29T20:10:01Z", answer: "dim.result.json")
        XCTAssertTrue(defaults.bool(forKey: DimSetting.onKey), "канал меняет те же UserDefaults, что панель")
        try ask("dim-off.request.json", id: "1790200000000-2202", at: "2026-09-29T20:10:11Z",
                answer: "dim-off.result.json")
        XCTAssertEqual(defaults.double(forKey: DimSetting.levelKey), 0.6, "сила без поля — прежняя")
        let v3 = [("\"style\":\"1.5\",\"name\":\"Спокойная цифра\"", "\"style\":\"1.2\",\"name\":\"Удар\"")]
        try ask("look.request.json", id: "1790200000000-2211", at: "2026-09-29T20:11:01Z", answer: "look.result.json",
                swap: ("\"style\":\"1.3\"", "\"style\":\"1.2\""), answerSwap: v3)
        XCTAssertEqual(defaults.string(forKey: SendLook.styleKey), "1.2")
        try ask("look-grow.request.json", id: "1790200000000-2212", at: "2026-09-29T20:11:11Z",
                answer: "look-grow.result.json", answerSwap: v3)
        try ask("look-bad.request.json", id: "1790200000000-2213", at: "2026-09-29T20:11:21Z",
                answer: "look-bad.error.json")
        XCTAssertEqual(defaults.integer(forKey: SendLook.sizeKey), 140, "отказ ничего не меняет")
    }

    func testBadDimAndLookRequestsRefused() {
        func parse(_ tail: String, _ action: String) -> PimpRequest? {
            PimpRequest.parse(Data(("{\"id\":\"1-1\",\"at\":\"2026-09-29T20:10:00Z\",\"action\":\"\(action)\","
                + "\"from\":\"\"\(tail)}").utf8))
        }
        XCTAssertNil(parse("", "dim"), "без on")
        XCTAssertNil(parse(",\"on\":1", "dim"), "on — булево, не число")
        XCTAssertNil(parse(",\"on\":true,\"level\":0.9", "dim"))
        XCTAssertNil(parse(",\"on\":true,\"level\":true", "dim"))
        XCTAssertEqual(parse(",\"on\":true,\"level\":0.2", "dim")?.level, 20)
        XCTAssertNil(parse(",\"size\":250", "look"))
        XCTAssertNil(parse(",\"size\":120,\"grow\":10", "look"), "размер и прибавка вместе")
        XCTAssertNil(parse(",\"show\":\"yes\"", "look"))
        XCTAssertNil(parse(",\"size\":12.5", "look"))
        let bare = parse("", "look")
        XCTAssertEqual(bare?.style, "")
        XCTAssertNil(bare?.size)
        XCTAssertEqual(bare?.show, false, "голый look — только сказать, что выбрано")
        XCTAssertEqual(parse(",\"grow\":-20,\"show\":true", "look")?.grow, -20)
    }

    // MARK: - 3. #8282: спрятанное окно, где ждут Элвиса

    private static let at = Date(timeIntervalSince1970: 1_790_200_000)

    private func page(_ title: String, waiting: Bool?, frame: CGRect? = nil) -> ChatPage {
        var page = ChatPage(kind: .popout, chat: nil, title: title, store: "ok", frame: frame, at: Self.at)
        page.waiting = waiting
        return page
    }

    func testWaitingWindowPickedFirstOnly() {
        let pages = [page("Дубли задач", waiting: false), page("Бот: голос", waiting: true),
                     page("Кино", waiting: true)]
        let hidden: [(title: String, frame: CGRect?)] = [("Дубли задач", nil), ("Кино", nil), ("Бот: голос", nil)]
        XCTAssertEqual(WindowHide.waiting(hidden, pages: pages), 1, "первое по порядку, одно")
        XCTAssertNil(WindowHide.waiting([("Дубли задач", nil)], pages: pages))
        XCTAssertNil(WindowHide.waiting(hidden, pages: pages.map { page($0.title, waiting: nil) }),
                     "круг без status() — никто не ждёт")
    }

    func testWaitingTwinsResolvedByFrame() {
        let left = CGRect(x: 0, y: 30, width: 400, height: 600)
        let right = CGRect(x: 800, y: 30, width: 400, height: 600)
        let pages = [page("Claude", waiting: false, frame: left), page("Claude", waiting: true, frame: right)]
        XCTAssertEqual(WindowHide.waiting([("Claude", left), ("Claude", right)], pages: pages), 1)
        XCTAssertNil(WindowHide.waiting([("Claude", nil)], pages: pages), "однофамильцы без рамки — не гадаем")
    }

    func testHiddenWindowsCurrentAndRemove() {
        var minimized: [String: Bool] = ["А": true, "Б": true, "В": false]
        let hidden = HiddenWindows<String> { minimized[$0] }
        hidden.add(["А", "Б", "В"])
        XCTAssertEqual(hidden.current, ["А", "Б"])
        hidden.remove { $0 == "А" }
        XCTAssertEqual(hidden.count, 1)
        minimized["Б"] = nil
        XCTAssertEqual(hidden.current, [])
    }

    func testProbeAsksWaitAndReadsIt() throws {
        let script = ChatProbe.script(nonce: "chats-1-0001", scan: false, cash: true)
        XCTAssertTrue(script.contains("wait = !!(status.attention && status.attention.want)"),
                      "не wait.due: просто законченный ход окна не зовёт (#8112)")
        XCTAssertTrue(ChatProbe.isOwnScript(script))
        XCTAssertFalse(ChatProbe.script(nonce: "chats-1-0001", scan: false).contains("status.wait"),
                       "обычный круг побайтно прежний")
        let body: [String: Any] = ["at": "2026-09-30T20:00:00Z", "results": [
            ["id": 1, "source": ProbeSourceFixture.metadata(url: "about:blank"), "url": "about:blank", "result": ["v": 1, "nonce": "chats-1-0001", "kind": "popout",
                                                      "title": "Бот", "store": "ok", "wait": true]],
            ["id": 2, "source": ProbeSourceFixture.metadata(url: "https://x.test/"), "url": "https://x.test/", "result": ["v": 1, "nonce": "chats-1-0001", "kind": "other",
                                                          "title": "art", "store": "skip", "wait": true]],
            ["id": 3, "source": ProbeSourceFixture.metadata(url: "about:blank"), "url": "about:blank", "result": ["v": 1, "nonce": "chats-1-0001", "kind": "popout",
                                                      "title": "Кино", "store": "ok"]],
        ]]
        let pages = ChatProbe.parse(try JSONSerialization.data(withJSONObject: body), nonce: "chats-1-0001",
                                    at: Self.at)
        XCTAssertEqual(pages.map { $0.waiting }, [true, nil])
    }
}
