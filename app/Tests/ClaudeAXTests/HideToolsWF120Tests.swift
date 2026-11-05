import AppKit
import XCTest
@testable import ClaudeAX

/// «Прятать инструменты» (WF120, #7976, контракт К-B1; с WF237 — выключатель «Оформления» панели): память в UserDefaults
/// (с WF242 по умолчанию включено — как у страницы page-63), всем окнам команда `hide-tools` строкой `on:"true"|"false"`
/// мимо enum. Прячет сама страница; здесь только команда.
final class HideToolsWF120Tests: XCTestCase {
    /// Команда — строкой мимо enum; флаг — в UserDefaults, ключа нет — включён (WF242:
    /// страница прячет инструменты, пока ей не сказали «нет», — галочка в меню говорит то же).
    func testSetWritesCommandAndRemembers() throws {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: ClaudeActions.hideToolsKey)
        addTeardownBlock {
            if let before = before { defaults.set(before, forKey: ClaudeActions.hideToolsKey) }
            else { defaults.removeObject(forKey: ClaudeActions.hideToolsKey) }
        }
        defaults.removeObject(forKey: ClaudeActions.hideToolsKey)
        XCTAssertNil(ClaudeCommand(rawValue: "hide-tools"), "в enum команду не заводим (критик WF120)")

        for on in [true, false] {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("wf120h-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("command.json")
            let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                        commands: CommandChannel(path: file, now: { Date() }, schedule: { _, _ in }))
            if on { XCTAssertTrue(actions.hideToolsEnabled, "ключа нет — включено") }
            actions.setHideTools(on)
            XCTAssertEqual(actions.hideToolsEnabled, on)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(json["action"] as? String, "hide-tools")
            XCTAssertEqual(json["on"] as? String, on ? "true" : "false")
            XCTAssertNotNil(json["id"] as? String)
        }
    }
}
