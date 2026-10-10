import AppKit
import XCTest
@testable import ClaudeAX

/// Меню с кнопки боковой панели (⌘B) снято в WF220 (#9440); здесь остался сторож меню жёлтой кнопки.
final class SidebarMenuWF84Tests: XCTestCase {
    func testMinimizeMenuKeepsAppearance() throws {
        let plain = MinimizeMenu.build(config: MinimizeMenu.MenuConfig())
        let top = plain.items.map { $0.title }
        XCTAssertEqual(top.first, MenuModel.themeResetTitle)
        XCTAssertTrue(top.contains(MenuModel.resetAllTitle))
        XCTAssertEqual(top.last, MenuModel.moreTitle)
    }
}
