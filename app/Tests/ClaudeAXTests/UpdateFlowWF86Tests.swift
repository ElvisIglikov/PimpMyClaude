import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Обновление Claude «гонкой» (WF86, план WF87 батч A): машина состояний меню, суточная проверка
/// с повтором через час, «самое время», одно нажатие, разводка уведомлений, заморозка снимка окон.
final class UpdateFlowWF86Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func race(_ version: String, _ lanes: [ClaudeUpdateMenu.Lane]) -> ClaudeUpdateMenu.Race {
        ClaudeUpdateMenu.Race(version: version, lanes: lanes)
    }

    private func lane(_ title: String, _ bytes: Int64, _ speed: Double, _ state: ClaudeUpdateMenu.LaneState,
                      total: Int64? = 1_000) -> ClaudeUpdateMenu.Lane {
        ClaudeUpdateMenu.Lane(id: title.lowercased(), title: title, bytes: bytes, total: total,
                              bytesPerSec: speed, state: state)
    }

    // MARK: - машина состояний

    func testFullPathIdleToInstalled() {
        var menu = ClaudeUpdateMenu()
        XCTAssertEqual(menu.phase, .idle)
        XCTAssertTrue(menu.beginCheck(at: t0, trigger: .daily))
        XCTAssertEqual(menu.phase, .checking, "пока проверяем — предлагать нечего")
        menu.finish(.available(version: "2.9939.2"), at: t0)
        XCTAssertEqual(menu.phase, .available(version: "2.9939.2"))
        XCTAssertEqual(menu.wantsDownload(autoDownload: true, at: t0), "2.9939.2")

        menu.startDownload(version: "2.9939.2")
        XCTAssertNil(menu.wantsDownload(autoDownload: true, at: t0), "вторую гонку не начинаем")
        XCTAssertFalse(menu.beginCheck(at: t0.addingTimeInterval(700), trigger: .manual), "пока качается — не проверяем")
        let live = race("2.9939.2", [
            lane("R2", 420, 5_100_000, .leading),
            lane("GitHub", 30, 8_000, .dropped("отстал — отключён")),
            lane("Anthropic", 200, 1_260_000, .running),
        ])
        menu.progress(live)
        menu.progress(race("2.0.0", [lane("R2", 999, 1, .leading)]))
        XCTAssertEqual(menu.phase, .downloading(live), "снимок чужой версии не принимается")
        XCTAssertEqual(live.percent, 42, "доля лучшей живой полосы")

        menu.downloaded(version: "2.9939.2")
        XCTAssertEqual(menu.phase, .ready(version: "2.9939.2"))
        XCTAssertNil(menu.wantsDownload(autoDownload: true, at: t0), "та же версия уже готова")

        XCTAssertTrue(menu.startInstall())
        XCTAssertEqual(menu.phase, .installing(version: "2.9939.2"))
        XCTAssertFalse(menu.startInstall(), "второе нажатие ничего не ставит")
        menu.installFinished()
        XCTAssertEqual(menu.phase, .idle)
        XCTAssertEqual(menu.known, .unknown, "прежний ответ — про старый Claude")
    }

    func testReadyFromPreviousLaunchAndFailures() {
        var menu = ClaudeUpdateMenu()
        menu.restoreReady(version: "2.9939.2") // ready.json с прошлого запуска
        XCTAssertEqual(menu.phase, .ready(version: "2.9939.2"))
        XCTAssertTrue(menu.beginCheck(at: t0, trigger: .daily), "готово — проверять дальше можно")
        menu.finish(.available(version: "2.9940.0"), at: t0)
        XCTAssertEqual(menu.wantsDownload(autoDownload: true, at: t0), "2.9940.0", "вышло ещё новее — качаем его")
        XCTAssertNil(menu.wantsDownload(autoDownload: false, at: t0), "выключатель claudeAutoDownload")
        menu.startDownload(version: "2.9940.0")
        menu.downloadFailed("ни один источник не докачал", at: t0)
        menu.restoreReady(version: "2.9939.2") // прежнее готовое уцелело
        XCTAssertEqual(menu.phase, .ready(version: "2.9939.2"))
        XCTAssertNil(menu.wantsDownload(autoDownload: true, at: t0.addingTimeInterval(3_599)), "после неудачи — не раньше часа")
        XCTAssertEqual(menu.wantsDownload(autoDownload: true, at: t0.addingTimeInterval(3_600)), "2.9940.0")

        XCTAssertTrue(menu.startInstall())
        menu.installFailed("Claude не закрылся")
        XCTAssertEqual(menu.lastError, "Claude не закрылся")
        menu.restoreReady(version: nil) // готового больше нет
        XCTAssertEqual(menu.phase, .available(version: "2.9940.0"))
        if case .available(_, _, let note) = PimpPanelText.updateBlock(menu, .init()) {
            XCTAssertEqual(note, "Фоновая загрузка не вышла: Claude не закрылся")
        } else {
            XCTFail("готового нет — блок «Вышел Claude»")
        }
    }

    func testNoWriteAccessMeansManualOnly() {
        var menu = ClaudeUpdateMenu()
        XCTAssertTrue(menu.beginCheck(at: t0))
        menu.finish(.available(version: "3.0.0"), at: t0)
        menu.canWrite = false
        XCTAssertNil(menu.wantsDownload(autoDownload: true, at: t0), "фон молча не качает")
        // Гейт 1 WF87, A4: кнопки нет, «поставь сам» — пароль FileManager не спросит.
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init()), .available(version: "3.0.0", canWrite: false, note: nil))
        menu.canWrite = true // права вернулись — пересчёт на следующей проверке
        XCTAssertEqual(menu.wantsDownload(autoDownload: true, at: t0), "3.0.0")
    }

    /// Гейт 1 WF87, A1: отмена (сон, дорогая сеть) — не неудача: качаем снова сразу, без часовой паузы;
    /// настоящая неудача — повтор через час (его подбирает таймер раз в 60 с, а не суточная проверка).
    func testCancelledDownloadResumesWithoutPause() {
        var menu = ClaudeUpdateMenu()
        XCTAssertTrue(menu.beginCheck(at: t0))
        menu.finish(.available(version: "3.0.0"), at: t0)
        menu.startDownload(version: "3.0.0")
        menu.downloadCancelled()
        XCTAssertEqual(menu.phase, .available(version: "3.0.0"))
        XCTAssertNil(menu.lastError, "отмена — не ошибка в подсказке")
        XCTAssertEqual(menu.wantsDownload(autoDownload: true, at: t0.addingTimeInterval(1)), "3.0.0")
        menu.startDownload(version: "3.0.0")
        menu.downloadFailed("ни один источник не докачал", at: t0)
        XCTAssertNil(menu.wantsDownload(autoDownload: true, at: t0.addingTimeInterval(60)))
        XCTAssertEqual(menu.wantsDownload(autoDownload: true, at: t0.addingTimeInterval(3_600)), "3.0.0",
                       "через час — снова, а не через сутки")
        menu.downloaded(version: "3.0.0")
        menu.downloadCancelled()
        XCTAssertEqual(menu.phase, .ready(version: "3.0.0"), "отмена вне загрузки готовое не трогает")
    }

    /// Ручная проверка не затирается фоновой: gate один, пока идёт одна — вторая не начинается.
    func testOneGateForManualAndBackground() {
        var menu = ClaudeUpdateMenu()
        XCTAssertTrue(menu.beginCheck(at: t0, trigger: .manual))
        XCTAssertFalse(menu.beginCheck(at: t0, trigger: .daily))
        XCTAssertFalse(menu.beginCheck(at: t0, trigger: .menu))
        XCTAssertFalse(menu.beginCheck(at: t0, trigger: .manual))
        menu.finish(.latest(installed: "2.0"), at: t0)
        XCTAssertFalse(menu.beginCheck(at: t0.addingTimeInterval(5), trigger: .menu))
        XCTAssertTrue(menu.beginCheck(at: t0.addingTimeInterval(5), trigger: .manual), "ручная — мимо интервала")
        var busy = ClaudeUpdateMenu()
        XCTAssertFalse(busy.beginCheck(at: t0, busy: true), "идёт «Поставить» — не проверяем")
    }

    // MARK: - суточная проверка

    func testDailyCheckRetriesInAnHourAfterError() {
        var menu = ClaudeUpdateMenu()
        XCTAssertTrue(menu.beginCheck(at: t0, trigger: .daily), "первый запуск — сразу")
        XCTAssertEqual(menu.nextDailyAt, t0.addingTimeInterval(3_600), "оборвётся на полпути — повтор через час")
        menu.finish(.failed("нет сети"), at: t0.addingTimeInterval(10))
        XCTAssertEqual(menu.nextDailyAt, t0.addingTimeInterval(3_610))
        XCTAssertFalse(menu.beginCheck(at: t0.addingTimeInterval(3_609), trigger: .daily))
        XCTAssertTrue(menu.beginCheck(at: t0.addingTimeInterval(3_610), trigger: .daily), "ошибка — через час, не через сутки")
        menu.finish(.latest(installed: "2.0"), at: t0.addingTimeInterval(3_611))
        XCTAssertEqual(menu.nextDailyAt, t0.addingTimeInterval(3_611 + 86_400))

        // Перезапуск Пимпа: срок пришёл из UserDefaults.
        var restarted = ClaudeUpdateMenu(nextDailyAt: menu.nextDailyAt)
        XCTAssertFalse(restarted.beginCheck(at: t0.addingTimeInterval(80_000), trigger: .daily))
        XCTAssertTrue(restarted.beginCheck(at: t0.addingTimeInterval(3_611 + 86_400), trigger: .daily))

        // Успешная проверка из меню тоже отодвигает суточную.
        var viaMenu = ClaudeUpdateMenu()
        XCTAssertTrue(viaMenu.beginCheck(at: t0, trigger: .menu))
        viaMenu.finish(.available(version: "3.0"), at: t0)
        XCTAssertFalse(viaMenu.beginCheck(at: t0.addingTimeInterval(3_600), trigger: .daily))
    }

    // MARK: - «самое время» и одно нажатие

    func testShouldOffer() {
        func offer(ready: Bool = true, running: Bool = true, windows: Int = 3, working: Bool? = false,
                   idle: TimeInterval? = 300, last: Date? = nil, snooze: Date? = nil) -> Bool {
            ClaudeUpdateMenu.shouldOffer(ready: ready, claudeRunning: running, windowCount: windows,
                                         anyPageWorking: working, idleSeconds: idle, lastOfferAt: last,
                                         snoozeUntil: snooze, now: t0)
        }
        XCTAssertTrue(offer())
        XCTAssertFalse(offer(ready: false), "не готово — не предлагаем")
        XCTAssertTrue(offer(running: false, working: true), "Claude не запущен")
        XCTAssertTrue(offer(windows: 0, working: true), "окон нет")
        XCTAssertFalse(offer(working: true), "страница работает")
        XCTAssertFalse(offer(working: nil), "не знаем — это не «не работает»")
        XCTAssertFalse(offer(idle: 119), "тишина меньше 120 с")
        XCTAssertTrue(offer(idle: 120))
        XCTAssertFalse(offer(idle: nil), "гейт 2 WF87: тишину не наблюдали — это не «2 мин никто не работает»")
        XCTAssertTrue(offer(running: false, idle: nil), "Claude не запущен — тишина не нужна")
        XCTAssertFalse(offer(last: t0.addingTimeInterval(-3 * 3_600 + 1)), "предлагали меньше 3 ч назад")
        XCTAssertTrue(offer(last: t0.addingTimeInterval(-3 * 3_600)))
        XCTAssertFalse(offer(snooze: t0.addingTimeInterval(1)), "«Позже»")
        XCTAssertTrue(offer(snooze: t0))
    }

    func testOneClickAsksOnlyWhenChatsMayBeWorking() {
        XCTAssertFalse(ClaudeUpdateMenu.needsConfirm(claudeRunning: false, windowCount: 0, anyPageWorking: nil))
        XCTAssertFalse(ClaudeUpdateMenu.needsConfirm(claudeRunning: true, windowCount: 0, anyPageWorking: nil),
                       "окон нет — без вопроса")
        XCTAssertTrue(ClaudeUpdateMenu.needsConfirm(claudeRunning: true, windowCount: 2, anyPageWorking: nil),
                      "1.5.9: признака работы нет — окна есть, значит спрашиваем")
        XCTAssertFalse(ClaudeUpdateMenu.needsConfirm(claudeRunning: true, windowCount: 2, anyPageWorking: false))
        XCTAssertTrue(ClaudeUpdateMenu.needsConfirm(claudeRunning: true, windowCount: 2, anyPageWorking: true))
        XCTAssertEqual(ClaudeUpdateMenu.confirmWorkingTitle(chats: 1), "Идёт работа в 1 чате — обновить всё равно?")
        XCTAssertEqual(ClaudeUpdateMenu.confirmWorkingTitle(chats: 3), "Идёт работа в 3 чатах — обновить всё равно?")
        XCTAssertEqual(ClaudeUpdateMenu.confirmWorkingTitle(chats: 11), "Идёт работа в 11 чатах — обновить всё равно?")
    }

    // MARK: - уведомления

    func testNotificationClicksAreRoutedByCategory() {
        let body = ClaudeUpdateMenu.defaultAction
        XCTAssertEqual(ClaudeUpdateMenu.route(category: ClaudeUpdateMenu.readyCategory, action: body), .updateClaude,
                       "клик по «Скачалось обновление» — обновить Claude, НЕ «Поставить»")
        XCTAssertEqual(ClaudeUpdateMenu.route(category: ClaudeUpdateMenu.readyCategory,
                                              action: ClaudeUpdateMenu.updateAction), .updateClaude)
        XCTAssertEqual(ClaudeUpdateMenu.route(category: ClaudeUpdateMenu.readyCategory,
                                              action: "com.apple.UNNotificationDismissActionIdentifier"), .nothing)
        XCTAssertEqual(ClaudeUpdateMenu.route(category: "PatchLost", action: "InstallAgain"), .reinstallPatch)
        XCTAssertEqual(ClaudeUpdateMenu.route(category: "PatchLost", action: body), .reinstallPatch)
        XCTAssertEqual(ClaudeUpdateMenu.route(category: "", action: body), .nothing, "без категории — ничего")
        XCTAssertEqual(ClaudeUpdateMenu.readyNotificationTitle(version: "2.9939.2"), "Скачалось обновление Claude 2.9939.2")
    }

    func testVersionOrder() {
        XCTAssertTrue(ClaudeUpdateMenu.isNewer("2.9940.0", than: "2.9939.2"))
        XCTAssertTrue(ClaudeUpdateMenu.isNewer("2.10", than: "2.9.9"))
        XCTAssertFalse(ClaudeUpdateMenu.isNewer("2.9939.2", than: "2.9939.2"))
        XCTAssertFalse(ClaudeUpdateMenu.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(ClaudeUpdateMenu.isNewer("2.x", than: "1.0"))
    }

    // MARK: - заморозка снимка окон (критик WF87 п. 2)

    private final class Rig {
        var claude: (pid: pid_t, launch: Date?, version: String)?
        var windows: [SnapshotWindow] = []
        var started: [WindowSnapshot] = []
        let store: WindowSnapshotStore
        let keeper: WindowSnapshotKeeper

        init(url: URL) {
            store = WindowSnapshotStore(url: url)
            keeper = WindowSnapshotKeeper(store: store)
            keeper.claude = { [unowned self] in self.claude }
            keeper.windows = { [unowned self] in self.windows }
            keeper.pageReady = { _ in true }
            keeper.startRestore = { [unowned self] snapshot in
                self.started.append(snapshot)
                return true
            }
        }
    }

    private func window(_ chat: String, x: CGFloat) -> SnapshotWindow {
        SnapshotWindow(chat: chat, folder: "", title: chat, frame: CGRect(x: x, y: 40, width: 500, height: 800), screen: "")
    }

    private func rig() -> Rig {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf86-snapshot-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return Rig(url: url)
    }

    /// Обновление закрывает Claude из /Applications; выбор переезжает на старую копию — её окна
    /// снимок не переписывают. Новый Claude (запущен после заморозки) получает прежние окна.
    func testFrozenSnapshotSurvivesOtherCopyAndReturnsToNewClaude() {
        let rig = rig()
        let mine = [window("main", x: 0), window("local_a", x: 520), window("local_b", x: 1040)]
        rig.claude = (pid: 100, launch: t0.addingTimeInterval(-86_400), version: "2.9000.0")
        rig.windows = mine
        var at = t0
        rig.keeper.tick(at: at)
        XCTAssertTrue(rig.keeper.saveNow(at: at), "снимок перед закрытием")
        let saved = rig.store.load()
        rig.keeper.freeze(at: at)
        XCTAssertTrue(rig.keeper.status.hasSuffix("/frozen"))

        // Claude из /Applications закрылся — выбрана старая копия с её окнами (запущена давно).
        rig.claude = (pid: 97_061, launch: t0.addingTimeInterval(-7 * 86_400), version: "1.34493.1")
        rig.windows = [window("main", x: 2_000)]
        for _ in 0..<10 {
            at.addTimeInterval(4)
            rig.keeper.tick(at: at)
        }
        XCTAssertEqual(rig.store.load(), saved, "окна другой копии снимок не переписали")
        XCTAssertEqual(rig.keeper.writes, 1)

        // Новый Claude запущен после заморозки — заморозка тает, окна возвращаются.
        let launch = at.addingTimeInterval(1)
        rig.claude = (pid: 200, launch: launch, version: "2.9939.2")
        rig.windows = [window("main", x: 0)]
        at = launch.addingTimeInterval(2)
        rig.keeper.tick(at: at)
        XCTAssertFalse(rig.keeper.status.hasSuffix("/frozen"))
        XCTAssertEqual(rig.keeper.phase, .restoring, "окно и страница есть — возврат сразу")
        XCTAssertEqual(rig.started.map { $0.windows }, [mine], "вернулись окна до обновления")
    }

    func testThawAndFreezeLimit() {
        let rig = rig()
        rig.claude = (pid: 100, launch: t0.addingTimeInterval(-100), version: "2.0")
        rig.windows = [window("main", x: 0)]
        rig.keeper.freeze(at: t0)
        rig.keeper.tick(at: t0.addingTimeInterval(4))
        rig.keeper.tick(at: t0.addingTimeInterval(8))
        XCTAssertEqual(rig.keeper.writes, 0, "заморожено — не пишем")
        rig.keeper.thaw() // обновление сорвалось до закрытия Claude
        rig.keeper.tick(at: t0.addingTimeInterval(12))
        rig.keeper.tick(at: t0.addingTimeInterval(16))
        XCTAssertEqual(rig.keeper.writes, 1, "дальше снимок ведётся как был")

        rig.keeper.freeze(at: t0.addingTimeInterval(20))
        rig.windows = [window("main", x: 300)]
        rig.keeper.tick(at: t0.addingTimeInterval(24))
        rig.keeper.tick(at: t0.addingTimeInterval(28))
        XCTAssertEqual(rig.keeper.writes, 1)
        rig.keeper.tick(at: t0.addingTimeInterval(20 + WindowSnapshotKeeper.freezeLimitSeconds))
        rig.keeper.tick(at: t0.addingTimeInterval(24 + WindowSnapshotKeeper.freezeLimitSeconds))
        XCTAssertEqual(rig.keeper.writes, 2, "через 10 мин заморозка тает сама")
    }
}
