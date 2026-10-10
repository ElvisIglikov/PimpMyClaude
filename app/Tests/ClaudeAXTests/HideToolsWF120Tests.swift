import AppKit
import XCTest
@testable import ClaudeAX

/// «🙈 Прятать инструменты» (WF120, #7976, контракт К-B1): тумблер под «📖 Автосвёртка» в «⋯ Ещё ▸»,
/// по её образцу — память в UserDefaults (по умолчанию выключено), всем окнам команда `hide-tools`
/// строкой `on:"true"|"false"` мимо enum. Прячет сама страница; здесь только меню и команда.
final class HideToolsWF120Tests: XCTestCase {
    private func more(_ config: MinimizeMenu.MenuConfig) throws -> NSMenu {
        let item = try XCTUnwrap(MinimizeMenu.build(config: config).items.last)
        XCTAssertEqual(item.title, MenuModel.moreTitle)
        return try XCTUnwrap(item.submenu)
    }

    private func click(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target as? NSObject else {
            return XCTFail("у пункта «\(item.title)» нет действия")
        }
        target.perform(action)
    }

    /// Пункт стоит сразу под «Автосвёртка», носит значок, подсказку и галку по состоянию;
    /// клик просит обратное состояние — и из выключенного, и из включённого.
    func testToggleSitsUnderAutoCollapse() throws {
        for on in [false, true] {
            var asked: [Bool] = []
            var config = MinimizeMenu.MenuConfig()
            config.hideTools = on
            config.setHideTools = { asked.append($0) }
            let items = try more(config).items
            let auto = try XCTUnwrap(items.firstIndex { $0.title == MenuModel.autoCollapseTitle })
            let item = items[auto + 1]
            XCTAssertEqual(item.title, "Прятать инструменты")
            XCTAssertNotNil(item.image, "значок 🙈")
            XCTAssertEqual(item.state, on ? .on : .off)
            XCTAssertEqual(item.toolTip, "Скрывать завершённые инструменты и список правок. Работа, ошибки, вопросы и "
                           + "запросы разрешения остаются видны.")
            XCTAssertTrue(item.keyEquivalent.isEmpty, "клавиши у тумблера нет")
            XCTAssertTrue(items[auto + 2].isSeparatorItem, "дальше — разделитель после «Свернуть»")
            click(item)
            XCTAssertEqual(asked, [!on])
        }
    }

    /// Команда — строкой мимо enum, как `auto-collapse`; флаг — в UserDefaults, по умолчанию выключен.
    func testSetWritesCommandAndRemembers() throws {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: MenuModel.hideToolsKey)
        addTeardownBlock {
            if let before = before { defaults.set(before, forKey: MenuModel.hideToolsKey) }
            else { defaults.removeObject(forKey: MenuModel.hideToolsKey) }
        }
        defaults.removeObject(forKey: MenuModel.hideToolsKey)
        XCTAssertNil(ClaudeCommand(rawValue: "hide-tools"), "в enum команду не заводим (критик WF120)")

        for on in [true, false] {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("wf120h-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("command.json")
            let actions = ClaudeActions(app: IsolatedClaudeApp.make(),
                                        commands: CommandChannel(path: file, now: { Date() }, schedule: { _, _ in }))
            if on { XCTAssertFalse(actions.hideToolsEnabled, "по умолчанию выключено") }
            actions.setHideTools(on)
            XCTAssertEqual(actions.hideToolsEnabled, on)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(json["action"] as? String, "hide-tools")
            XCTAssertEqual(json["on"] as? String, on ? "true" : "false")
            XCTAssertNotNil(json["id"] as? String)
        }
    }
}
