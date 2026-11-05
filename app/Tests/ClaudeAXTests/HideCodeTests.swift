import AppKit
import XCTest
@testable import ClaudeAX

/// «Прятать код и планы» (#7976, контракт К-HC): выключатель «Оформления» панели под «Прятать инструменты». Память —
/// UserDefaults, ключа нет — выключено (команда копирует из ответов код); всем окнам команда `hide-code` строкой
/// `on:"true"|"false"` мимо enum, как `hide-tools`. Сворачивает сама страница; здесь только команда и умолчание.
final class HideCodeTests: XCTestCase {
    private func keepDefaults() {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: ClaudeActions.hideCodeKey)
        addTeardownBlock {
            if let before = before { defaults.set(before, forKey: ClaudeActions.hideCodeKey) }
            else { defaults.removeObject(forKey: ClaudeActions.hideCodeKey) }
        }
        defaults.removeObject(forKey: ClaudeActions.hideCodeKey)
    }

    private func actions(_ tag: String) throws -> (ClaudeActions, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hidecode-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("command.json")
        let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                    commands: CommandChannel(path: file, now: { Date() }, schedule: { _, _ in }))
        return (actions, file)
    }

    /// Ключа нет — выключено, и без нажатия команда не уходит (страница без команды тоже не прячет).
    func testDefaultIsOffAndSilent() throws {
        keepDefaults()
        let (actions, file) = try actions("default")
        XCTAssertFalse(actions.hideCodeEnabled, "ключа нет — выключено")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "без нажатия команды нет")
        XCTAssertNil(ClaudeCommand(rawValue: "hide-code"), "в enum команду не заводим — как hide-tools")
    }

    /// Нажатие пишет `{"id","action":"hide-code","at","on":"true"|"false"}` и запоминает выбор.
    func testSetWritesCommandAndRemembers() throws {
        keepDefaults()
        for on in [true, false] {
            let (actions, file) = try actions(on ? "on" : "off")
            actions.setHideCode(on)
            XCTAssertEqual(actions.hideCodeEnabled, on)
            XCTAssertEqual(UserDefaults.standard.object(forKey: ClaudeActions.hideCodeKey) as? Bool, on)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(json["action"] as? String, "hide-code")
            XCTAssertEqual(json["on"] as? String, on ? "true" : "false", "строкой, как у hide-tools")
            XCTAssertNotNil(json["id"] as? String)
        }
    }

    /// Выключатель не трогает соседний «Прятать инструменты» (у того умолчание — включено).
    func testIndependentFromHideTools() throws {
        keepDefaults()
        let defaults = UserDefaults.standard
        let tools = defaults.object(forKey: ClaudeActions.hideToolsKey)
        addTeardownBlock {
            if let tools = tools { defaults.set(tools, forKey: ClaudeActions.hideToolsKey) }
            else { defaults.removeObject(forKey: ClaudeActions.hideToolsKey) }
        }
        defaults.removeObject(forKey: ClaudeActions.hideToolsKey)
        let (actions, _) = try actions("tools")
        actions.setHideCode(true)
        XCTAssertTrue(actions.hideToolsEnabled, "«Прятать инструменты» осталось по умолчанию")
        XCTAssertNil(defaults.object(forKey: ClaudeActions.hideToolsKey))
    }
}
