import AppKit
import XCTest
@testable import ClaudeAX

private final class BugsDefaults: ThemeDefaults {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

/// WF137 «Ошибки Swift»: #9060 (К5, `new-window` + `mode:"bypass"`) и #7829 (меню ⌘B гасит
/// вылетающую панель Claude и своё подменю при спуске вниз).
final class BugsWF137Tests: XCTestCase {

    // MARK: - #9060, К5: new-window при «Bypass в новых чатах»

    func testNewWindowFieldsAppendBypassModeLast() {
        let plain = CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "", x: 120, y: 120, text: "Привет"),
            id: "1-0001", at: Date(timeIntervalSince1970: 0))
        // Без настройки — побайтно как до К5 (эталон testNewWindowPayloadMatchesContract).
        XCTAssertEqual(plain, "{\"id\":\"1-0001\",\"action\":\"new-window\",\"at\":\"1970-01-01T00:00:00Z\","
                       + "\"scope\":\"window\",\"title\":\"\",\"x\":120,\"y\":120,\"text\":\"Привет\","
                       + "\"folder\":\"\",\"name\":\"\"}")
        XCTAssertEqual(CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "", x: 120, y: 120, text: "Привет", bypass: false),
            id: "1-0001", at: Date(timeIntervalSince1970: 0)), plain)
        // С настройкой — `mode` ПОСЛЕДНИМ, после слоёв и полей «💬 Новый чат».
        let bypass = CommandChannel.payload(
            action: ClaudeCommand.newWindow.rawValue,
            fields: ClaudeActions.newWindowFields(title: "", x: 120, y: 120, text: "Привет",
                                                  folder: "/tmp/P", name: "P", model: "Opus 5.5", effort: "high",
                                                  pin: true, frame: .set(true), bypass: true),
            id: "1-0001", at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(bypass.hasSuffix(",\"model\":\"Opus 5.5\",\"effort\":\"high\",\"pin\":true,"
                                       + "\"frame\":true,\"mode\":\"bypass\"}"), bypass)
        XCTAssertEqual(BypassNew.draftMode, "bypass")
    }

    private func rig(bypass: Bool) throws -> (actions: ClaudeActions, command: URL, project: Project) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf137-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let command = directory.appendingPathComponent("command.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
            commands: CommandChannel(path: command, now: { now }, schedule: { _, _ in }),
            themes: [], fonts: [], themeStore: ThemeStore(defaults: BugsDefaults()),
            myThemes: MyThemesStore(url: directory.appendingPathComponent("themes.json")),
            autoPaintStore: AutoPaintStore(defaults: BugsDefaults()),
            liveColorsStore: LiveColorsStore(defaults: BugsDefaults()))
        actions.clock = { now }
        actions.schedule = { _, _ in } // без синтетического ⌘N
        actions.bypassNew = { bypass }
        return (actions, command, Project(folder: directory, name: "P137", lastFocusedAt: 0))
    }

    /// Все пути «нового окна» сходятся в одну точку записи: «▸ проект» / канал «Пимп» (`pimp.py open`,
    /// `renew-window`) — `newWindow(in:)`, «💬 Новый чат» — то же с `handoff`.
    func testEveryNewWindowPathCarriesBypassOnlyWhenEnabled() throws {
        for bypass in [false, true] {
            for handoff in [nil, NewChatHandoff(model: "Opus 5.5", effort: "high", stay: false, transfer: false)] {
                let (actions, command, project) = try rig(bypass: bypass)
                actions.newWindow(in: project, on: nil, handoff: handoff)
                let body = try String(contentsOf: command, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
                XCTAssertEqual(json["action"] as? String, "new-window")
                if bypass {
                    XCTAssertTrue(body.hasSuffix(",\"mode\":\"bypass\"}"), body)
                } else {
                    XCTAssertNil(json["mode"], body)
                }
            }
        }
    }
}
