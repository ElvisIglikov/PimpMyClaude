import XCTest
import AppKit
@testable import ClaudeAX

/// Подсказка у окна macOS «Claude Safe Storage» (WF238, #9580, макет `docs/41.html`): слова, когда показывается и
/// уходит, где встаёт и какое окно считает окном macOS (своей рамки у подсказки нет с WF246). Живых окон тест не
/// открывает.
final class KeychainHintWF238Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)
    private let dialog = CGRect(x: 481, y: 250, width: 477, height: 224)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    // MARK: слова

    func testPlaqueWords() {
        XCTAssertEqual(KeychainHint.title, "Это окно — от macOS. Так и должно быть")
        XCTAssertEqual(KeychainHint.steps.map { $0.text },
                       ["Впиши пароль от Мака — тот, которым входишь в компьютер",
                        "Нажми «Разрешать всегда» — и оно больше не спросит"])
        XCTAssertEqual(KeychainHint.passwordStays, "Пароль остаётся в macOS — ни Claude, ни PMP его не видят")
        XCTAssertEqual(KeychainHint.reason(.update), "Спрашивает, потому что PMP заново прокачал обновлённый Claude, "
            + "чтобы темы, кнопка PMP и остальное работали")
        XCTAssertEqual(KeychainHint.reason(.patch), "Спрашивает, потому что PMP заново прокачал Claude, "
            + "чтобы темы, кнопка PMP и остальное работали", "после патча без обновления Claude не «обновлённый»")
        XCTAssertEqual(KeychainHint.sourceLink, "Код PMP открыт")
        XCTAssertEqual(PimpPanelText.openSourceURL, "https://github.com/ElvisIglikov/PimpMyClaude")
        XCTAssertEqual(KeychainHint.doneTitle(.update), "Готово — Claude обновлён")
        XCTAssertEqual(KeychainHint.doneTitle(.patch), "Готово — патч на месте")
        XCTAssertEqual(KeychainHint.doneText, "Про пароль спросит снова только после следующего обновления Claude")
    }

    /// Тихая строка до нажатия: полужирное в ней — её же кусок, иначе вид собрал бы строку с дырой.
    func testQuietLineBeforePress() {
        // Пробелы в «пароль от Мака —» неразрывные; человек читает обычные.
        XCTAssertEqual(PimpPanelText.keychainSoon.replacingOccurrences(of: "\u{00A0}", with: " "),
                       "Потом macOS один раз спросит пароль от Мака — покажу, что нажать")
        XCTAssertEqual(PimpPanelText.keychainSoon.components(separatedBy: PimpPanelText.keychainSoonBold),
                       ["Потом macOS один раз спросит ", "\u{00A0}— покажу, что нажать"])
    }

    // MARK: запуск

    func testDemoArgumentTurnsOrdinaryLaunchOff() {
        XCTAssertTrue(KeychainHint.isDemoLaunch(["/Applications/PimpMyClaude.app/Contents/MacOS/PimpMyClaude",
                                                 "--keychain-hint-demo"]))
        XCTAssertFalse(KeychainHint.isDemoLaunch(["PimpMyClaude"]))
        XCTAssertFalse(KeychainHint.isDemoLaunch(["PimpMyClaude", "--panel"]))
        XCTAssertFalse(KeychainHint.isDemoLaunch(["--keychain-hint-demo"]), "нулевой аргумент — путь программы")
        XCTAssertFalse(KeychainHint.isDemoLaunch([]))
    }

    /// Ждать окно macOS начинаем со строки журнала патча, после которой Claude открывается переподписанным.
    func testWatchStartsWhenPatchedClaudeOpens() {
        XCTAssertTrue(KeychainHint.opensClaude("Готово. Открываю Claude…"))
        XCTAssertFalse(KeychainHint.opensClaude("Ставлю лоадер в app.asar…"))
        XCTAssertFalse(KeychainHint.opensClaude("Закрываю Claude…"))
        XCTAssertFalse(KeychainHint.opensClaude("Патч уже стоит. Обновляю только живые файлы в Application Support."))
    }

    // MARK: когда показывается и уходит

    private func step(_ state: KeychainHint.State, _ visible: Bool, at seconds: TimeInterval) -> KeychainHint.State {
        KeychainHint.step(state, windowVisible: visible, now: t0.addingTimeInterval(seconds))
    }

    func testShowsOnlyWhileMacWindowIsOnScreen() {
        var state = KeychainHint.State()
        XCTAssertEqual(step(state, true, at: 0).phase, .idle, "никто не ждал — чужое окно пароля не трогаем")
        state = KeychainHint.begin(now: t0)
        XCTAssertEqual(state.phase, .watching)
        state = step(state, false, at: 3)
        XCTAssertEqual(state.phase, .watching, "окна ещё нет — на экране ничего")
        state = step(state, true, at: 4)
        XCTAssertEqual(state.phase, .shown)
        state = step(state, true, at: 30)
        XCTAssertEqual(state.phase, .shown)
        // Пропало на миг (между двумя запросами подряд) — плашка стоит.
        state = step(state, false, at: 30.25)
        XCTAssertEqual(state.phase, .shown)
        state = step(state, true, at: 30.5)
        XCTAssertEqual(state.phase, .shown)
        XCTAssertNil(state.missingSince)
        // Закрыли — «Готово…» на 4,5 с и уход.
        state = step(state, false, at: 40)
        state = step(state, false, at: 40 + KeychainHint.goneGrace)
        XCTAssertEqual(state.phase, .done)
        state = step(state, false, at: 44)
        XCTAssertEqual(state.phase, .done)
        state = step(state, false, at: 40 + KeychainHint.goneGrace + KeychainHint.doneSeconds)
        XCTAssertEqual(state.phase, .idle)
    }

    func testSecondQuestionBringsHintBack() {
        var state = step(KeychainHint.begin(now: t0), true, at: 1)
        state = step(state, false, at: 5)
        state = step(state, false, at: 6)
        XCTAssertEqual(state.phase, .done)
        state = step(state, true, at: 7)
        XCTAssertEqual(state.phase, .shown, "macOS спросила ещё раз — снова подсказка, а не «Готово»")
    }

    func testTimeouts() {
        let waiting = KeychainHint.begin(now: t0)
        XCTAssertEqual(step(waiting, false, at: KeychainHint.watchSeconds - 1).phase, .watching)
        XCTAssertEqual(step(waiting, false, at: KeychainHint.watchSeconds).phase, .idle, "окно не появилось — молча уходим")
        let shown = step(waiting, true, at: 2)
        XCTAssertEqual(step(shown, true, at: 2 + KeychainHint.shownSeconds - 1).phase, .shown)
        XCTAssertEqual(step(shown, true, at: 2 + KeychainHint.shownSeconds).phase, .idle, "вечно не висит")
        XCTAssertEqual(KeychainHint.doneSeconds, 4.5)
    }

    // MARK: место плашки

    func testPlaqueStandsRightUnderMacWindow() {
        let size = CGSize(width: KeychainHint.plaqueWidth(window: dialog), height: 230)
        XCTAssertEqual(size.width, dialog.width, "шириной с окно macOS — общие края")
        let frame = KeychainHint.plaqueFrame(window: dialog, size: size, visible: screen)
        XCTAssertEqual(frame.midX, dialog.midX)
        XCTAssertEqual(frame.minX, dialog.minX)
        XCTAssertEqual(frame.minY, dialog.maxY + KeychainHint.spacing)
        // Рамка маяка вокруг окна macOS (зазор и толщина) плашку не задевает; своей рамки у плашки нет (WF246).
        XCTAssertGreaterThan(frame.minY - dialog.maxY, ConsentWaterK.gap + ConsentWaterK.thick)
        XCTAssertFalse(frame.intersects(dialog))
    }

    func testPlaqueNeverCoversMacWindow() {
        let size = CGSize(width: 477, height: 230)
        // Окно macOS у нижнего края — плашка над ним.
        let low = CGRect(x: 481, y: 560, width: 477, height: 224)
        let above = KeychainHint.plaqueFrame(window: low, size: size, visible: screen)
        XCTAssertEqual(above.maxY, low.minY - KeychainHint.spacing)
        // Низкий экран: ни под окном, ни над ним места нет — сбоку.
        let short = CGRect(x: 0, y: 0, width: 1700, height: 560)
        let middle = CGRect(x: 500, y: 170, width: 477, height: 224)
        let side = KeychainHint.plaqueFrame(window: middle, size: size, visible: short)
        XCTAssertEqual(side.minX, middle.maxX + KeychainHint.spacing)
        // Совсем тесно — под окном, пусть и за краем: окно пароля не накрываем никогда.
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 560)
        let window = CGRect(x: 160, y: 170, width: 477, height: 224)
        for visible in [screen, short, tiny] {
            for target in [dialog, low, middle, window] {
                let frame = KeychainHint.plaqueFrame(window: target, size: size, visible: visible)
                XCTAssertFalse(frame.intersects(target.insetBy(dx: -ConsentWaterK.hole, dy: -ConsentWaterK.hole)))
            }
        }
        XCTAssertEqual(KeychainHint.plaqueFrame(window: window, size: size, visible: tiny).minY,
                       window.maxY + KeychainHint.spacing)
        // Узкое и очень широкое окно — ширина плашки в пределах.
        XCTAssertEqual(KeychainHint.plaqueWidth(window: CGRect(x: 0, y: 0, width: 260, height: 300)), KeychainHint.minWidth)
        XCTAssertEqual(KeychainHint.plaqueWidth(window: CGRect(x: 0, y: 0, width: 900, height: 300)), KeychainHint.maxWidth)
    }

    func testFlipIsItsOwnInverse() {
        let cocoa = KeychainHint.flipped(dialog, primaryHeight: 900)
        XCTAssertEqual(cocoa, CGRect(x: 481, y: 900 - 474, width: 477, height: 224))
        XCTAssertEqual(KeychainHint.flipped(cocoa, primaryHeight: 900), dialog)
    }

    // MARK: окно macOS

    func testPicksSecurityAgentWindowOnly() {
        let consent = { (number: Int, process: String, bounds: CGRect) in
            ConsentWindow(number: number, pid: 77, process: process, layer: 8, bounds: bounds)
        }
        XCTAssertNil(KeychainHint.pick([]))
        XCTAssertNil(KeychainHint.pick([consent(1, "UserNotificationCenter", dialog)]),
                     "запрос доступа к файлам — не окно связки ключей")
        let small = CGRect(x: 0, y: 0, width: 60, height: 60)
        let found = KeychainHint.pick([consent(1, "tccd", dialog), consent(2, "SecurityAgent", small),
                                       consent(3, "SecurityAgent", dialog)])
        XCTAssertEqual(found, KeychainHint.Target(number: 3, bounds: dialog))
        XCTAssertTrue(ConsentWindow.processes.contains(KeychainHint.process), "тот же признак, что у маяка окон доступа")
    }
}
