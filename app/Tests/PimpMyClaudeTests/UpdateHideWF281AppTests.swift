import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// #10765: крестик карточки обновления в панели — версия запоминается в UserDefaults, переживает новую панель
/// (перезапуск), новая версия показывает карточку снова, «Обновить» в «Настройках» карточку возвращает.
final class UpdateHideWF281AppTests: XCTestCase {
    private let key = PimpPanelText.updateHiddenKey
    private var saved: Any?

    override func setUp() {
        saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() { UserDefaults.standard.set(saved, forKey: key) }

    func testHideRemembersVersionUntilNext() {
        let model = PanelModel()
        model.reduceMotion = true
        model.update = .busy(version: "1.4758.0", work: "4 терминала")
        XCTAssertFalse(model.updateCardHidden)
        model.hideUpdateCard()
        XCTAssertTrue(model.updateCardHidden)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "1.4758.0")

        let reopened = PanelModel()
        reopened.update = .ready(version: "1.4758.0", question: nil)
        XCTAssertTrue(reopened.updateCardHidden)
        reopened.update = .ready(version: "1.4759.0", question: nil)
        XCTAssertFalse(reopened.updateCardHidden)
    }

    func testHideDoesNothingWithoutCard() {
        let model = PanelModel()
        model.update = .installing(version: "1.4758.0", step: 2)
        model.hideUpdateCard()
        XCTAssertNil(model.hiddenUpdateVersion)
        XCTAssertNil(UserDefaults.standard.string(forKey: key))
    }

    func testUpdateFromSettingsUnhides() {
        let model = PanelModel()
        model.reduceMotion = true
        model.update = .busy(version: "1.4758.0", work: "4 терминала")
        model.hideUpdateCard()
        model.sheet = .settings
        var pressed = 0
        model.actions.update = { pressed += 1 }
        SettingsSheet.pressUpdate(model)
        XCTAssertEqual(pressed, 1)
        XCTAssertFalse(model.updateCardHidden)
        XCTAssertNil(UserDefaults.standard.string(forKey: key))
    }
}
