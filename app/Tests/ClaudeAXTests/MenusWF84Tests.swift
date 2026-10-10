import AppKit
import XCTest
@testable import ClaudeAX

private final class WF84Defaults: ThemeDefaults {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

/// Меню WF84 (батч M1): «💬 Новый чат» на ⌘B (#7072, контракты К1 и К2), повтор команды по поколениям
/// страниц (К3, Авто-Allow возвращён в WF121), серый замок (#7199, К6) и «↩️ Вернуть окна» (#7065). Всё на
/// подставных данных — ни AX, ни живого Claude, ни перехвата ввода.
final class MenusWF84Tests: XCTestCase {
    private static let id = "1756900000123-0042"
    private static let at = Date(timeIntervalSince1970: 1_756_900_000)
    private static let mainMatch = "/epitaxy/local_facfb20c-4b3c-4aa9-838f-e084b0941b74"

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: MenusWF84Tests.repositoryRoot
            .appendingPathComponent("tests/fixtures/cashout/\(name)"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func payload(_ action: String, _ fields: [(key: String, value: CommandValue)]) -> String {
        CommandChannel.payload(action: action, fields: fields, id: MenusWF84Tests.id, at: MenusWF84Tests.at)
    }

    // MARK: - К1: «Обкэшить» с handoff — побайтно по эталонам батча P

    func testCashoutHandoffMatchesFixtures() throws {
        XCTAssertEqual(payload("cashout", ClaudeActions.cashoutFields(
            title: "VkusnoffKz 2", chat: "local_4dae798d-aed9-42d7-bd1b-3631eb360c07", handoff: true)),
            try fixture("cashout-handoff.json"))
        XCTAssertEqual(payload("cashout", ClaudeActions.cashoutFields(
            title: "PimpMyClaude", match: MenusWF84Tests.mainMatch, handoff: true)),
            try fixture("cashout-handoff-main.json"))
        // Без handoff поле не пишется вовсе — «Обкэшить» WF37 как был.
        XCTAssertEqual(payload("cashout", ClaudeActions.cashoutFields(
            title: "VkusnoffKz 2", chat: "local_4dae798d-aed9-42d7-bd1b-3631eb360c07")),
            try fixture("cashout-popout.json"))
    }

    // MARK: - К2: new-window с моделью, эффортом, sendTransfer и stay

    func testNewWindowHandoffMatchesFixtures() throws {
        XCTAssertEqual(payload(ClaudeCommand.newWindow.rawValue, ClaudeActions.newWindowFields(
            title: "VkusnoffKz 2", match: MenusWF84Tests.mainMatch, x: 586, y: 303, text: "Привет",
            folder: "/Users/dev/Projects/VkusnoffKz", name: "VkusnoffKz 3", transfer: true,
            model: "Opus 5.5", effort: "High", sendTransfer: true, frame: .set(true))),
            try fixture("new-window-handoff.json"))
        XCTAssertEqual(payload(ClaudeCommand.newWindow.rawValue, ClaudeActions.newWindowFields(
            title: "PimpMyClaude", match: MenusWF84Tests.mainMatch, x: 586, y: 303, text: "Привет",
            folder: "/Users/dev/Projects/PimpMyClaude", name: "",
            model: "Fable 5.1", effort: "Extra", sendTransfer: true, stay: true)),
            try fixture("new-window-handoff-stay.json"))
        // Прежние пути полей К2 не несут.
        let plain = payload(ClaudeCommand.newWindow.rawValue, ClaudeActions.newWindowFields(
            title: "VkusnoffKz 2", x: 1, y: 2, text: "Привет"))
        for key in ["model", "effort", "sendTransfer", "stay", "transfer"] {
            XCTAssertFalse(plain.contains("\"\(key)\""), "поле \(key) в обычном «Новом окне»")
        }
    }

    // MARK: - модель донора: имя из id сессии общим правилом

    func testSessionModelNamesByGeneralRule() {
        XCTAssertEqual(SessionModel.menuModel("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(SessionModel.menuModel("claude-opus-5"), "Opus 5", "«Opus 5» ≠ «Opus 5.5»")
        XCTAssertEqual(SessionModel.menuModel("claude-fable-5-1"), "Fable 5.1")
        XCTAssertEqual(SessionModel.menuModel("claude-sonnet-4-5-20250929"), "Sonnet 4.5")
        XCTAssertEqual(SessionModel.menuModel("claude-opus-5-5[1m]"), "Opus 5.5")
        XCTAssertEqual(SessionModel.menuModel("claude-3-5-sonnet-20241022"), "Sonnet 3.5")
        XCTAssertEqual(SessionModel.menuModel("claude-haiku-6-2"), "Haiku 6.2", "новая модель — без таблицы")
        XCTAssertNil(SessionModel.menuModel(""))
        XCTAssertNil(SessionModel.menuModel("claude-opus"), "без цифр подписи не угадать")
        XCTAssertNil(SessionModel.menuModel("gpt-4-turbo"), "два слова — не наша форма")

        XCTAssertEqual(SessionModel.menuEffort("xhigh"), "Extra", "в файле xhigh, на экране Extra")
        XCTAssertEqual(SessionModel.menuEffort("high"), "High")
        XCTAssertEqual(SessionModel.menuEffort("max"), "Max")
        XCTAssertEqual(SessionModel.menuEffort("low"), "Low")
        XCTAssertNil(SessionModel.menuEffort(""))
    }

    func testHandoffTakesDonorModelUnlessAuto() {
        let fixed = SessionModel(model: "claude-opus-5-5", effort: "xhigh", auto: false)
        XCTAssertEqual(NewChatHandoff.from(fixed, stay: false),
                       NewChatHandoff(model: "Opus 5.5", effort: "Extra", stay: false))
        // Донор на Auto: модель не шлём — остаётся Auto; эффорт как у донора.
        let auto = SessionModel(model: "claude-opus-5-5", effort: "high", auto: true)
        XCTAssertEqual(NewChatHandoff.from(auto, stay: true),
                       NewChatHandoff(model: nil, effort: "High", stay: true))
        // Чат неизвестен — ничего не трогаем.
        XCTAssertEqual(NewChatHandoff.from(nil, stay: true), NewChatHandoff(model: nil, effort: nil, stay: true))
    }

    func testSessionFileCarriesModel() throws {
        let body = """
        {"sessionId":"local_1","cwd":"/tmp/x","title":"T","model":"claude-fable-5-1","effort":"medium",\
        "autoChosenInApp":true}
        """
        let session = try XCTUnwrap(ProjectIndex.parseSession(Data(body.utf8)))
        XCTAssertEqual(session.model, SessionModel(model: "claude-fable-5-1", effort: "medium", auto: true))
        let bare = try XCTUnwrap(ProjectIndex.parseSession(Data(#"{"sessionId":"local_2","cwd":"/tmp/y"}"#.utf8)))
        XCTAssertNil(bare.model)
    }

    func testNewChatNoticeNamesModel() {
        XCTAssertEqual(MenuModel.newChatNotice(model: "Opus 5.5", effort: "High"),
                       "💬 Открываю новый чат — Opus 5.5 · High, несколько секунд…")
        XCTAssertEqual(MenuModel.newChatNotice(model: nil, effort: nil),
                       "💬 Открываю новый чат, несколько секунд…")
    }

    // MARK: - «↩️ Вернуть окна» под «Расставить»

    private func click(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target as? NSObject else {
            return XCTFail("у пункта «\(item.title)» нет действия")
        }
        target.perform(action)
    }

    func testRestoreWindowsSitsUnderArrange() throws {
        var config = MinimizeMenu.MenuConfig()
        var asked = 0
        config.restoreWindows = { asked += 1 }
        let menu = MinimizeMenu.build(config: config)
        let more = try XCTUnwrap(menu.items.first { $0.title == MenuModel.moreTitle }?.submenu)
        let titles = more.items.map { $0.title }
        let arrange = try XCTUnwrap(titles.firstIndex(of: "Расставить"))
        XCTAssertEqual(titles[arrange + 1], MenuModel.restoreWindowsTitle)
        click(more.items[arrange + 1])
        XCTAssertEqual(asked, 1)
    }

    // MARK: - К3: повтор по поколениям страниц (общий `AutoAllowSwitch`)

    func testAutoAllowCommandBytes() {
        XCTAssertEqual(payload(ClaudeCommand.autoAllow.rawValue, AutoAllowSwitch.fields(on: false)),
                       "{\"id\":\"1756900000123-0042\",\"action\":\"auto-allow-once\","
                       + "\"at\":\"2025-09-03T11:46:40Z\",\"on\":\"false\"}")
        XCTAssertEqual(payload(ClaudeCommand.autoAllow.rawValue, AutoAllowSwitch.fields(on: true)),
                       "{\"id\":\"1756900000123-0042\",\"action\":\"auto-allow-once\","
                       + "\"at\":\"2025-09-03T11:46:40Z\",\"on\":\"true\"}")
    }

    func testPerformAutoAllowWritesBothStatesWithoutClaudeOrAccessibility() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("command.json")
        var now = Self.at
        let channel = CommandChannel(path: file, now: { now }, schedule: { _, _ in
            XCTFail("разнесённые по времени команды не должны ждать очереди")
        })
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(), commands: channel, themes: [], fonts: [],
                                    themeStore: ThemeStore(defaults: WF84Defaults()),
                                    myThemes: MyThemesStore(url: dir.appendingPathComponent("my.json")),
                                    autoPaintStore: AutoPaintStore(defaults: WF84Defaults()),
                                    liveColorsStore: LiveColorsStore(defaults: WF84Defaults()))
        for on in [true, false] {
            actions.autoAllowOn = { on }
            actions.perform(.autoAllow, on: nil)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["id", "action", "at", "on"], "без адресации окна")
            XCTAssertEqual(json["action"] as? String, "auto-allow-once")
            XCTAssertEqual(json["on"] as? String, on ? "true" : "false")
            now = now.addingTimeInterval(2)
        }
    }

    func testAutoAllowRepeatsPerGeneration() {
        let sw = AutoAllowSwitch()
        XCTAssertFalse(sw.on, "без настроек выключен")
        var sent: [Bool] = []
        let send: (Bool) -> Bool = { sent.append($0); return true }
        let t0 = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(sw.tick(titles: [], at: t0, send: send), "окон нет — слать некому")
        XCTAssertTrue(sw.tick(titles: ["Claude"], at: t0, send: send), "первый тик с окнами — сразу")
        XCTAssertEqual(sent, [false], "шлём флаг тумблера, а не «вкл»")
        XCTAssertFalse(sw.tick(titles: ["Claude"], at: t0.addingTimeInterval(10), send: send),
                       "состав тот же — не повторяем")
        XCTAssertFalse(sw.tick(titles: ["PimpMyClaude"], at: t0.addingTimeInterval(3), send: send),
                       "не чаще раза в 5 с")
        XCTAssertTrue(sw.tick(titles: ["PimpMyClaude"], at: t0.addingTimeInterval(6), send: send))
        XCTAssertTrue(sw.tick(titles: ["PimpMyClaude", "Dictatorik"], at: t0.addingTimeInterval(12), send: send))
        XCTAssertFalse(sw.tick(titles: ["A", "B", "C"], at: t0.addingTimeInterval(30), send: send),
                       "не больше трёх за поколение")
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sw.status, "off/3")

        // Перезапуск Claude — новое поколение, флаг снова уезжает.
        sw.on = true
        sw.beginGeneration()
        XCTAssertEqual(sw.status, "on/0", "поколение сбрасывает счёт, но сохраняет выбор")
        XCTAssertTrue(sw.tick(titles: ["Claude"], at: t0.addingTimeInterval(31), send: send))
        XCTAssertEqual(sent.count, 4)
        XCTAssertEqual(sent.last, true)
        // Запись не удалась (очередь канала сказала «нет») — повтор не потрачен.
        let failing = AutoAllowSwitch()
        XCTAssertFalse(failing.tick(titles: ["Claude"], at: t0, send: { _ in false }))
        XCTAssertTrue(failing.tick(titles: ["Claude"], at: t0.addingTimeInterval(1), send: { _ in true }))
    }

    func testAutoAllowRetriesDoNotSpendBudgetOrAdvanceWindowCompositionOnFailure() {
        let sw = AutoAllowSwitch()
        let t0 = Date(timeIntervalSince1970: 1_000)
        var accepted: [Bool] = []
        let send: (Bool) -> Bool = { accepted.append($0); return true }
        for second in 0..<5 {
            XCTAssertFalse(sw.tick(titles: ["A"], at: t0.addingTimeInterval(Double(second)), send: { _ in false }))
        }
        XCTAssertEqual(sw.status, "off/0")
        XCTAssertTrue(sw.tick(titles: ["A"], at: t0.addingTimeInterval(5), send: send))
        XCTAssertFalse(sw.tick(titles: ["B", "A"], at: t0.addingTimeInterval(10), send: { _ in false }))
        sw.on = true
        XCTAssertTrue(sw.tick(titles: ["B", "A"], at: t0.addingTimeInterval(11), send: send), "ошибка не ставит паузу")
        XCTAssertFalse(sw.tick(titles: ["A", "B"], at: t0.addingTimeInterval(20), send: send), "порядок окон не важен")
        XCTAssertTrue(sw.tick(titles: ["C"], at: t0.addingTimeInterval(21), send: send))
        XCTAssertFalse(sw.tick(titles: ["D"], at: t0.addingTimeInterval(30), send: send))
        XCTAssertEqual(accepted, [false, true, true])
        XCTAssertEqual(sw.status, "on/3")
    }
}
