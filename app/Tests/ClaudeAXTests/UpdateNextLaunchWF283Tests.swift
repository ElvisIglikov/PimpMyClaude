import ClaudeAX
import XCTest

/// #10765, WF283: «Обновить сейчас» и «При запуске» у готового обновления Claude. Отложенная версия сворачивает
/// карточку в строку, вопрос и сбой её раскрывают, новая версия — снова полная карточка; ставится отложенное, только
/// когда Claude не запущен или PMP сам его перезапускает и ничем не занят.
final class UpdateNextLaunchWF283Tests: XCTestCase {
    private let version = "3.1623.1"
    private var menu: ClaudeUpdateMenu {
        var menu = ClaudeUpdateMenu()
        menu.restoreReady(version: version)
        return menu
    }

    // MARK: карточка

    func testReadyCardsOfferBothButtons() {
        let blocks: [PimpPanelText.UpdateBlock] = [
            .ready(version: version, question: nil),
            .busy(version: version, work: "4 терминала"),
            .timely(version: version, reason: "Claude не запущен"),
        ]
        for block in blocks {
            let card = PimpPanelText.updateCard(block, size: nil)
            XCTAssertEqual(card?.main.title, "Обновить сейчас", "\(block)")
            XCTAssertEqual(card?.second, .nextLaunch, "\(block)")
        }
        let asked = PimpPanelText.updateCard(.ready(version: version, question: "Обновить всё равно?"), size: nil)
        XCTAssertEqual(asked?.main, .updateAnyway, "вопрос — свои две кнопки")
        XCTAssertEqual(asked?.second, .wait)
    }

    func testPlannedCollapsesCardWhateverIsGoing() {
        let planned = PimpPanelText.UpdateExtras(plannedVersion: version)
        XCTAssertEqual(PimpPanelText.updateBlock(menu, planned), .planned(version: version))
        var busy = planned
        busy.workLine = "Работают 4 терминала"
        busy.workShort = "4 терминала"
        XCTAssertEqual(PimpPanelText.updateBlock(menu, busy), .planned(version: version), "работа не раскрывает строку")
        var timely = planned
        timely.offerReason = "Claude не запущен"
        XCTAssertEqual(PimpPanelText.updateBlock(menu, timely), .planned(version: version), "«самое время» молчит")
        XCTAssertNil(PimpPanelText.updateCard(.planned(version: version), size: nil), "строка — свой вид, не карточка")
        XCTAssertFalse(PimpPanelText.updateCardHidden(.planned(version: version), hidden: version))
    }

    func testQuestionAndFailureOpenThePlannedLine() {
        var asked = PimpPanelText.UpdateExtras(plannedVersion: version)
        asked.question = "Работают 2 терминала — Claude закроется, работа может сброситься. Обновить всё равно?"
        XCTAssertEqual(PimpPanelText.updateBlock(menu, asked), .ready(version: version, question: asked.question),
                       "«Сейчас» из строки при работе — вопрос виден целиком")
        let failed = PimpPanelText.UpdateExtras(installFailure: "нет места", plannedVersion: version)
        XCTAssertEqual(PimpPanelText.updateBlock(menu, failed), .failed("нет места"))
    }

    func testOtherVersionBringsFullCardBack() {
        let old = PimpPanelText.UpdateExtras(plannedVersion: "3.1600.0")
        XCTAssertEqual(PimpPanelText.updateBlock(menu, old), .ready(version: version, question: nil))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, PimpPanelText.UpdateExtras()), .ready(version: version, question: nil))
    }

    func testPlannedLine() {
        XCTAssertEqual(PimpPanelText.plannedLine, "Claude обновится при запуске")
        XCTAssertTrue(PimpPanelText.plannedHelp(version).hasPrefix("Claude 3.1623.1 скачан"), "номер версии — в подсказке")
    }

    // MARK: ставить ли сейчас

    func testInstallsOnlyWhenClaudeClosedOrRestartedAndPimpFree() {
        func now(planned: String? = "3.1623.1", ready: String? = "3.1623.1", running: Bool = false,
                 restarting: Bool = false, busy: Bool = false) -> Bool {
            PimpPanelText.installPlannedNow(planned: planned, ready: ready, claudeRunning: running,
                                            restarting: restarting, pimpBusy: busy)
        }
        XCTAssertTrue(now(), "Claude не запущен — прерывать нечего")
        XCTAssertFalse(now(running: true), "Claude открыт — ждём, пока закроют")
        XCTAssertTrue(now(running: true, restarting: true), "PMP сам перезапускает Claude — это и есть запуск")
        XCTAssertFalse(now(busy: true), "патч, установка или загрузка — не сейчас")
        XCTAssertFalse(now(running: true, restarting: true, busy: true))
        XCTAssertFalse(now(planned: nil), "ничего не откладывали")
        XCTAssertFalse(now(planned: "3.1600.0"), "отложили другую версию")
        XCTAssertFalse(now(ready: nil), "готового нет")
    }

    func testClosedInstallPromisesNoOpening() {
        let steps = PimpPanelText.installSteps(version: version, loader: 8, opensClaude: false)
        XCTAssertFalse(steps.contains("Открываю Claude"), "Claude закрыт человеком — PMP его не открывает")
        XCTAssertEqual(PimpPanelText.installSteps(version: version, loader: 8).count, 5)
    }

    // MARK: предупреждение

    func testWarningNamesWhatWorks() {
        let terminals = WorkNow(chats: 0, workflows: 0, terminals: 2)
        XCTAssertEqual(PimpPanelText.confirmQuestion(work: terminals),
                       "Работают 2 терминала — Claude закроется, работа может сброситься. Обновить всё равно?")
        XCTAssertEqual(PimpPanelText.confirmQuestion(work: WorkNow(chats: 1, workflows: 0, terminals: 1)),
                       "Работает 1 терминал · идёт работа в 1 чате — Claude закроется, работа может сброситься. Обновить всё равно?")
        XCTAssertEqual(PimpPanelText.confirmQuestion(work: WorkNow()), "Claude закроется вместе с окнами — обновить сейчас?",
                       "не знаем — общий вопрос, без выдуманных чисел")
    }
}
