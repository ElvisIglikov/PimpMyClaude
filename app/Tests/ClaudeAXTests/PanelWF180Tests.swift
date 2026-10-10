import CoreGraphics
import XCTest
@testable import ClaudeAX

/// WF180 (слово Элвиса 09.10 02:50): «Оформление» — выделен всегда цвет, «Живой» оживляет его, не меняя; «Показать»
/// не сдаётся при пустой карте чатов; «Ракета»; значок — выбор вариантов картинками, без числа недели.
final class PanelWF180Tests: XCTestCase {
    private func defaults(_ name: String = #function) -> UserDefaults {
        let store = UserDefaults(suiteName: "PanelWF180Tests.\(name)")!
        store.removePersistentDomain(forName: "PanelWF180Tests.\(name)")
        return store
    }

    // MARK: «Оформление» — одна плитка, «Живой» цвет не меняет

    func testExactlyOneTileSelectedWithLiveOnOrOff() {
        let tiles: [PanelColorTiles.Tile] = [.plain, .theme("mint"), .theme("lemonade"), .theme("ultra")]
        for choice in [WindowColorChoice.plain, .theme("mint"), .theme("ultra")] {
            XCTAssertEqual(tiles.filter { PanelColorTiles.isSelected($0, choice) }.count, 1, "\(choice)")
        }
        XCTAssertEqual(PanelColorTiles.picked(.theme("mint")), .theme("mint"))
        XCTAssertEqual(PanelColorTiles.picked(.plain), .plain)
        XCTAssertNil(PanelColorTiles.picked(.byProject), "свой цвет каждому проекту — из меню окна, в полосах не выделен")
    }

    func testLiveSwitchKeepsColorAndFollowsIt() {
        // Включил «Живой» — живой фон в тонах цвета окон («Как у темы»), прочие эффекты вида целы.
        let start = Look().with(.dense, true)
        let on = PanelColorTiles.liveLook(start, on: true)
        XCTAssertTrue(on.aurora)
        XCTAssertEqual(on.schemeID, "theme")
        XCTAssertTrue(on.dense, "другие эффекты вида не трогаем")
        // Выключил — тот же цвет без движения: только `aurora` снят, цвета окон в виде нет вовсе.
        let off = PanelColorTiles.liveLook(on, on: false)
        XCTAssertFalse(off.aurora)
        XCTAssertTrue(off.dense)
        // Выделение — только от цвета окон: у `picked` нет входа «живой», переключатель его не сдвинет.
        XCTAssertEqual(PanelColorTiles.picked(.theme("mint")), .theme("mint"))
    }

    func testColorClickMovesForeignLiveSchemeToColorTones() {
        XCTAssertTrue(PanelColorTiles.colorNeedsLiveScheme(live: true, scheme: "sea"), "схема до WF180 — на тона цвета")
        XCTAssertFalse(PanelColorTiles.colorNeedsLiveScheme(live: true, scheme: PanelColorTiles.liveScheme))
        XCTAssertFalse(PanelColorTiles.colorNeedsLiveScheme(live: false, scheme: "sea"), "живой выключен — не включаем")
        XCTAssertEqual(PanelColorTiles.title, "Оформление")
        XCTAssertEqual(PanelWidget.colors.title, "Оформление")
    }

    // MARK: «Показать» с пустой картой чатов

    func testPreviewFallsBackToMainWindowOnScreen() {
        // Карта чатов пуста (страница не ответила, probe держит агент) — адреса нет.
        XCTAssertNil(ClaudeActions.sendDelayPreviewTarget(visible: [(id: 7, page: nil), (id: 9, page: nil)],
                                                          focused: 9, pages: []))
        // …и показ берёт главное окно Claude на экране, в фокусе — если главных несколько.
        XCTAssertEqual(ClaudeActions.sendDelayFallbackWindow([(id: 7, main: false, focused: true),
                                                              (id: 9, main: true, focused: false)]), 9)
        XCTAssertEqual(ClaudeActions.sendDelayFallbackWindow([(id: 3, main: true, focused: false),
                                                              (id: 4, main: true, focused: true)]), 4)
        XCTAssertNil(ClaudeActions.sendDelayFallbackWindow([(id: 7, main: false, focused: true)]),
                     "одни попапы — без адреса не сыграет, отказ")
        XCTAssertNil(ClaudeActions.sendDelayFallbackWindow([]))
        XCTAssertGreaterThanOrEqual(ClaudeAXController.sendDelayPreviewRetries, 2, "не сдаёмся с первого раза")
    }

    func testUnaddressedPreviewPlaysInMainWindow() {
        let suite = "wf180-preview-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        addTeardownBlock { store.removePersistentDomain(forName: suite) }
        let settings = PageLookSettings(defaults: store)
        var sent: [String] = []
        settings.write = { _, fields, _ in sent.append(CommandValue.object(fields).json); return true }
        XCTAssertTrue(settings.previewSendDelayMain(seconds: 3))
        XCTAssertFalse(settings.previewSendDelayMain(seconds: 4), "только 3, 5, 10")
        XCTAssertEqual(sent, ["{\"style\":\"1.8\",\"size\":100,\"preview\":true,\"seconds\":3}"],
                         "без match/chat — страница играет в главном окне")
    }

    // MARK: «Ракета», без эмодзи

    func testRocketNameAndPlainSoundNames() {
        XCTAssertEqual(SendLook.name("1.8"), "Ракета")
        XCTAssertFalse(SendLook.styles.contains { $0.name == "Взлёт" })
        XCTAssertEqual(CountdownSound.allCases.map { $0.name },
                       ["Мягкий колокольчик", "Тик", "Капля", "Ретро-бип", "Без звука"])
        for sound in CountdownSound.allCases {
            XCTAssertTrue(sound.name.unicodeScalars.allSatisfy { !$0.properties.isEmojiPresentation }, sound.name)
        }
    }
    // Значок — варианты: с WF189 в `PanelWF189Tests` (числа вернулись, по умолчанию «PMP и неделя»).
}
