import CoreGraphics
import XCTest
@testable import ClaudeAX

/// «Спрятать окна Claude, кроме главного, и показать по слову» (WF112, #8255): кого сворачивать,
/// вид кнопки панели, ответы канала `hide`/`show` по эталонам и заморозка снимков, пока окна
/// спрятаны. AX тут нет — сворачивает контроллер.
final class HideWF112Tests: XCTestCase {
    private typealias Seen = WindowHide.Seen

    private static func seen(_ title: String, main: Bool = false, full: Bool = false) -> Seen {
        Seen(title: title, isMain: main, fullScreen: full)
    }

    // MARK: - 1. кого сворачивать

    func testHidesEveryoneButMainAndSkipsFullScreen() {
        let windows = [Self.seen("Claude", main: true), Self.seen("Дубли задач"),
                       Self.seen("Кино", full: true), Self.seen("Бот: голос")]
        XCTAssertEqual(WindowHide.plan(windows, minimized: 0), .hide([1, 3], skipped: 1))
    }

    /// Главного нет (резолвер промолчал и рамка не его) — не прячем никого: свернули бы Рика.
    func testNoMainRefusesAndTouchesNothing() {
        let windows = [Self.seen("Дубли задач"), Self.seen("Бот: голос")]
        XCTAssertEqual(WindowHide.plan(windows, minimized: 0), .refuse(.windowMissing))
    }

    /// Два «главных» (безымянный попап носит ту же заглушку) — оба остаются видимыми.
    func testTwoMainsStayVisible() {
        let windows = [Self.seen("Claude", main: true), Self.seen("Claude", main: true), Self.seen("Пимп")]
        XCTAssertEqual(WindowHide.plan(windows, minimized: 0), .hide([2], skipped: 0))
    }

    /// Главный проект (`mainProject`, гейт WF111): Рик — попап, его окна не сворачиваются никогда; главное
    /// окно Claude — тоже. Окно главного проекта главным для отказа не считается.
    func testMainProjectWindowsNeverHidden() {
        var rick = Self.seen("Рик")
        rick.keep = true
        var rick2 = Self.seen("Рик 2")
        rick2.keep = true
        let windows = [Self.seen("Claude", main: true), rick, Self.seen("Дубли задач"), rick2]
        XCTAssertEqual(WindowHide.plan(windows, minimized: 0), .hide([2], skipped: 0))
        XCTAssertEqual(WindowHide.plan([rick, Self.seen("Кино")], minimized: 0), .refuse(.windowMissing),
                       "главного окна нет — не прячем никого, как прежде")
    }

    func testNothingToHide() {
        XCTAssertEqual(WindowHide.plan([Self.seen("Claude", main: true)], minimized: 0), .hide([], skipped: 0))
        XCTAssertEqual(WindowHide.plan([], minimized: 3), .hide([], skipped: 0), "всё уже свёрнуто — не отказ")
        XCTAssertEqual(WindowHide.plan([], minimized: 0), .refuse(.noWindows))
    }

    // MARK: - 3. канал по эталонам

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf112-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: HideWF112Tests.fixtures.appendingPathComponent(name), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func answer(_ id: String, in box: URL) throws -> String {
        try String(contentsOf: box.appendingPathComponent(id + ".result.json"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ask(_ id: String, _ action: String, at: Date, in box: URL) {
        let body = "{\"id\":\"\(id)\",\"at\":\"\(PimpChannel.stampText(at))\",\"action\":\"\(action)\",\"from\":\"\"}"
        try? Data(body.utf8).write(to: box.appendingPathComponent(id + ".json"))
    }

    func testChannelAnswersHideAndShowByFixtures() throws {
        let box = makeTemp()
        var now = PimpChannel.date("2026-09-29T19:30:01Z")!
        var hideResult = WindowHideResult(titles: ["Дубли задач", "Бот: голос"], skipped: 1)
        var showResult = WindowHideResult(titles: ["Дубли задач", "Бот: голос"])
        var hides = 0
        let pimp = PimpChannel(directory: box, now: { now })
        pimp.seats.claudeRunning = { true }
        pimp.seats.hideWindows = {
            hides += 1
            return hideResult
        }
        pimp.seats.showWindows = { showResult }
        pimp.start()

        XCTAssertEqual(PimpRequest.parse(Data(try fixture("hide.request.json").utf8))?.action, .hide)
        XCTAssertEqual(PimpRequest.parse(Data(try fixture("show.request.json").utf8))?.action, .show)
        try Data(try fixture("hide.request.json").utf8).write(to: box.appendingPathComponent("1790100000000-1121.json"))
        pimp.tick()
        XCTAssertEqual(try answer("1790100000000-1121", in: box), try fixture("hide.result.json"))
        XCTAssertEqual(hides, 1)

        hideResult = WindowHideResult()
        now = PimpChannel.date("2026-09-29T19:30:11Z")!
        ask("1790100000000-1122", "hide", at: now, in: box)
        pimp.tick()
        XCTAssertEqual(try answer("1790100000000-1122", in: box), try fixture("hide-already.result.json"))

        hideResult = WindowHideResult(failure: .windowMissing)
        now = PimpChannel.date("2026-09-29T19:30:21Z")!
        ask("1790100000000-1123", "hide", at: now, in: box)
        pimp.tick()
        XCTAssertEqual(try answer("1790100000000-1123", in: box), try fixture("hide-no-main.error.json"))

        now = PimpChannel.date("2026-09-29T19:31:01Z")!
        try Data(try fixture("show.request.json").utf8).write(to: box.appendingPathComponent("1790100000000-1124.json"))
        pimp.tick()
        XCTAssertEqual(try answer("1790100000000-1124", in: box), try fixture("show.result.json"))

        showResult = WindowHideResult()
        now = PimpChannel.date("2026-09-29T19:31:11Z")!
        ask("1790100000000-1125", "show", at: now, in: box)
        pimp.tick()
        XCTAssertEqual(try answer("1790100000000-1125", in: box), try fixture("show-already.result.json"))

        // Занято (цепочка «Нового окна», возврат К5) — отказ `busy`, как у прочих действий.
        showResult = WindowHideResult(failure: .busy)
        ask("1790100000000-1126", "show", at: now, in: box)
        pimp.tick()
        XCTAssertTrue(try answer("1790100000000-1126", in: box).contains("\"ok\":false,\"error\":\"busy\""))
    }

    // MARK: - 4. снимки не пишутся, пока окна спрятаны

    /// Свёрнутых окон нет в списке окон: пиши снимок К5 дальше — он затёрся бы одним главным,
    /// и restart-claude вернул бы только Рика (блокер критика WF111).
    func testSnapshotFreezesWhileWindowsHidden() {
        let box = makeTemp()
        let store = WindowSnapshotStore(url: box.appendingPathComponent(WindowSnapshotStore.fileName))
        let keeper = WindowSnapshotKeeper(store: store)
        let frame = CGRect(x: 0, y: 34, width: 700, height: 859)
        keeper.claude = { (pid: 1, launch: Date(timeIntervalSince1970: 0), version: "1") }
        keeper.windows = { [SnapshotWindow(chat: LayoutsStore.mainChat, folder: "", title: "Claude", frame: frame, screen: "")] }
        var minimized = 2
        keeper.minimized = { minimized }
        var at = Date(timeIntervalSince1970: 1_790_000_000)
        for _ in 0..<6 {
            keeper.tick(at: at)
            at = at.addingTimeInterval(4)
        }
        XCTAssertEqual(keeper.writes, 0, "спрятаны — снимок не пишется")
        XCTAssertNil(store.load())
        XCTAssertFalse(keeper.saveNow(at: at), "и перед перезапуском тоже")
        minimized = 0
        for _ in 0..<2 {
            keeper.tick(at: at)
            at = at.addingTimeInterval(4)
        }
        XCTAssertEqual(keeper.writes, 1, "показали — снимок снова ведётся")
    }

    func testScreenLayoutFreezesWhileWindowsHidden() {
        let box = makeTemp()
        let keeper = ScreenLayoutKeeper(store: ScreenLayoutStore(url: box.appendingPathComponent(ScreenLayoutStore.fileName)))
        let screen = ScreenSpec(name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        let frame = CGRect(x: 0, y: 34, width: 700, height: 859)
        keeper.screens = { [screen] }
        keeper.windows = { [SnapshotWindow(chat: LayoutsStore.mainChat, folder: "", title: "Claude", frame: frame, screen: "")] }
        var minimized = 1
        keeper.minimized = { minimized }
        var at = Date(timeIntervalSince1970: 1_790_000_000)
        for _ in 0..<30 {
            keeper.tick(at: at)
            at = at.addingTimeInterval(2)
        }
        XCTAssertEqual(keeper.status, "0/0/0", "спрятаны — набор мониторов не пишется")
        minimized = 0
        for _ in 0..<15 {
            keeper.tick(at: at)
            at = at.addingTimeInterval(2)
        }
        XCTAssertEqual(keeper.status, "1/1/0")
    }

    // MARK: - 5. только спрятанное Пимпом (гейт 1 WF111)

    /// Свёрнутое руками окно в список Пимпа не попадает: пустой список — 0 без вызовов AX.
    func testHiddenWindowsCountsOnlyPimpsAndPrunes() {
        var state: [String: Bool?] = ["А": true, "Б": true, "Руками": true]
        var asked = 0
        let hidden = HiddenWindows<String> { name in
            asked += 1
            return state[name] ?? nil
        }
        XCTAssertEqual(hidden.count, 0)
        XCTAssertEqual(asked, 0, "пустой список — AX не зовём")
        hidden.add(["А", "Б"])
        XCTAssertEqual(hidden.count, 2)
        state["А"] = false
        state["Б"] = .some(nil)
        XCTAssertEqual(hidden.count, 0, "развёрнутые и закрытые выкидываются")
        hidden.add(["А"])
        hidden.clear()
        XCTAssertEqual(hidden.count, 0)
    }

    /// Окно свёрнуто руками (Пимп ничего не прятал) — снимок К5 пишется, как прежде.
    func testSnapshotKeepsWritingWhenMinimizedByHand() {
        let box = makeTemp()
        let store = WindowSnapshotStore(url: box.appendingPathComponent(WindowSnapshotStore.fileName))
        let keeper = WindowSnapshotKeeper(store: store)
        let frame = CGRect(x: 0, y: 34, width: 700, height: 859)
        keeper.claude = { (pid: 1, launch: Date(timeIntervalSince1970: 0), version: "1") }
        keeper.windows = { [SnapshotWindow(chat: LayoutsStore.mainChat, folder: "", title: "Claude", frame: frame, screen: "")] }
        let hidden = HiddenWindows<String> { _ in true }
        keeper.minimized = { hidden.count }
        var at = Date(timeIntervalSince1970: 1_790_000_000)
        for _ in 0..<3 {
            keeper.tick(at: at)
            at = at.addingTimeInterval(4)
        }
        XCTAssertEqual(keeper.writes, 1, "свёрнутое руками снимок не морозит")
        XCTAssertTrue(keeper.saveNow(at: at))
    }

    /// Возврат снимка при спрятанных окнах: сперва «покажи», окна двигаются только после анимации.
    func testRestoreShowsHiddenFirstThenWaitsForAnimation() {
        let box = makeTemp()
        var now = PimpChannel.date("2026-09-30T20:00:00Z")!
        var log: [String] = []
        var scheduled: [(TimeInterval, () -> Void)] = []
        var hiddenLeft = 2
        let pimp = PimpChannel(directory: box, now: { now })
        pimp.seats.claudeRunning = { true }
        pimp.seats.windows = {
            [PimpWindow(id: 1, title: "Claude", chat: "", frame: CGRect(x: 0, y: 0, width: 800, height: 700))]
        }
        pimp.seats.isMainWindow = { $0 == "Claude" }
        pimp.seats.place = { _ in log.append("place") }
        pimp.seats.openChat = { chat, _, _ in log.append("open " + chat) }
        pimp.seats.schedule = { delay, block in scheduled.append((delay, block)) }
        pimp.seats.showHiddenForRestore = {
            guard hiddenLeft > 0 else { return false }
            hiddenLeft = 0
            log.append("show")
            return true
        }
        pimp.start()
        let frame = CGRect(x: 0, y: 0, width: 600, height: 700)
        let snapshot = WindowSnapshot(at: now, claude: "1.0", windows: [
            SnapshotWindow(chat: LayoutsStore.mainChat, folder: "", title: "Claude", frame: frame, screen: ""),
            SnapshotWindow(chat: "local_11111111-2222-4333-8444-555555555555", folder: "", title: "Чат А",
                           frame: frame, screen: ""),
        ])
        XCTAssertTrue(pimp.startRestore(snapshot: snapshot, name: WindowSnapshotStore.restoreName))
        XCTAssertEqual(log, ["show"], "сперва показали спрятанные, окна ещё не трогали")
        XCTAssertTrue(pimp.isRestoring, "канал занят возвратом, пока ждём анимацию")
        XCTAssertEqual(scheduled.map { $0.0 }, [WindowHide.focusDelay])
        now = now.addingTimeInterval(0.3)
        pimp.tick()
        XCTAssertEqual(log, ["show"], "анимация не кончилась — ждём")
        now = now.addingTimeInterval(0.3)
        scheduled.removeFirst().1()
        XCTAssertEqual(log.first, "show")
        XCTAssertEqual(log.dropFirst().first, "place", "после анимации — возврат: главное на место")
        XCTAssertTrue(log.contains("open local_11111111-2222-4333-8444-555555555555"))
    }
}
