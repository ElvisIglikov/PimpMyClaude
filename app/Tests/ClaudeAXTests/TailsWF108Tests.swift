import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Хвосты проверки WF107 (WF108, Б9): `skipped` нового пути центра, экран «главного по центру» по месту
/// главного в тесноте, «воскрешение» размера поля после «Как у Claude».
/// Миграция Авто-Allow после WF121 проверяется в AutomationDefaultsTests одним общим мигратором.
final class TailsWF108Tests: XCTestCase {
    private static let odyssey = CGRect(x: -800, y: -720, width: 2560, height: 720)
    private static let macbook = CGRect(x: 0, y: 0, width: 1280, height: 832)
    private static let root = "/Users/dev/Projects/"

    // MARK: - 1. skipped нового пути центра

    /// Вход: стопка «A+B», Рик назван посередине, окно C ушло с экрана, пока считали (его номера нет в
    /// `windowIDs`). Ожидание: C не ставим и не отдаём, `skipped` 1, `hub` — номер Рика среди оставшихся.
    func testCenterStackCountsVanishedWindowAsSkipped() throws {
        let rig = Rig()
        let (channel, box) = makeChannel(rig)
        channel.seats.windowIDs = { Set(rig.windows.map { $0.id }).subtracting([4]) }
        let answer = try XCTUnwrap(ask(channel, rig, box, id: "600-0001", order: ["A+B", "Rick", "C", "D"]))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["skipped"] as? Int, 1)
        let titles = (answer["windows"] as? [[String: Any]])?.compactMap { $0["title"] as? String }
        XCTAssertEqual(titles, ["A", "B", "Rick", "D"])
        XCTAssertEqual(answer["hub"] as? Int, 2)
        XCTAssertEqual(rig.moves.last?.map { $0.id }, [2, 3, 1, 5], "ушедшее окно не двигаем")
    }

    /// Без опроса номеров (стенд, старые сиденья) — как было: `skipped` 0, все окна на месте.
    func testCenterStackWithoutWindowIDsSkipsNothing() throws {
        let rig = Rig()
        let (channel, box) = makeChannel(rig)
        let answer = try XCTUnwrap(ask(channel, rig, box, id: "600-0002", order: ["A+B", "Rick", "C", "D"]))
        XCTAssertEqual(answer["skipped"] as? Int, 0)
        XCTAssertEqual(rig.moves.last?.map { $0.id }, [2, 3, 1, 4, 5])
    }

    // MARK: - 2. экран «главного по центру»

    /// Нечётное n: место одно — `(n − 1) / 2`.
    func testCenterSlotOdd() {
        let slot = ClaudeActions.centerSlot(count: 7, minCellWidth: 220, gap: 2) { _ in TailsWF108Tests.odyssey }
        XCTAssertEqual(slot, 3)
    }

    /// Чётное n в тесноте (8 окон на Одиссее при 220): главный на `n / 2` = 4 — экран берётся по нему,
    /// даже когда окно на `(n − 1) / 2` стоит на MacBook (там 8 окон не влезают вовсе).
    func testCenterSlotEvenTight() {
        XCTAssertEqual(ClaudeActions.centerSlot(count: 8, minCellWidth: 220, gap: 2) { _ in TailsWF108Tests.odyssey }, 4)
        let mixed = ClaudeActions.centerSlot(count: 8, minCellWidth: 220, gap: 2) {
            $0 == 4 ? TailsWF108Tests.odyssey : TailsWF108Tests.macbook
        }
        XCTAssertEqual(mixed, 4)
    }

    /// Чётное n без тесноты (6 окон на Одиссее): главный на `(n − 1) / 2` = 2; сосед на `n / 2` с MacBook
    /// место не перехватывает.
    func testCenterSlotEvenLoose() {
        XCTAssertEqual(ClaudeActions.centerSlot(count: 4, minCellWidth: 220, gap: 2) { _ in TailsWF108Tests.odyssey }, 1)
        let mixed = ClaudeActions.centerSlot(count: 6, minCellWidth: 220, gap: 2) {
            $0 == 2 ? TailsWF108Tests.odyssey : TailsWF108Tests.macbook
        }
        XCTAssertEqual(mixed, 2)
        // Экранов не знаем — прежнее место.
        XCTAssertEqual(ClaudeActions.centerSlot(count: 8, minCellWidth: 220, gap: 2) { _ in nil }, 3)
    }

    // MARK: - 3. «Как у Claude» не воскресает

    /// Вход: «Как у Claude» в меню, через секунду страница присылает прежние 18 (пинг загрузки ушёл до
    /// команды), потом `none`. Ожидание: зеркало пустое, возвращать нечего; через 5 с число снова пишется.
    func testResetIsNotResurrectedByStalePing() {
        let suite = "TailsWF108Tests.font"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 1_000)
        let mirror = ComposerFontMirror(defaults: defaults, now: { now })
        ComposerFont.setMirror(18, in: defaults)
        ComposerFont.choose(nil, in: defaults, at: now)
        now = now.addingTimeInterval(1)
        XCTAssertNil(mirror.receive(ComposerFont.Ping(px: 18, chat: "local_a")))
        XCTAssertNil(ComposerFont.mirror(in: defaults), "старое значение не воскресло")
        XCTAssertNil(mirror.receive(ComposerFont.Ping(px: nil, chat: "local_a")), "возвращать нечего")
        now = now.addingTimeInterval(ComposerFont.settleInterval)
        XCTAssertNil(mirror.receive(ComposerFont.Ping(px: 17, chat: "local_a")))
        XCTAssertEqual(ComposerFont.mirror(in: defaults), 17, "колесо после выбора — снова в зеркало")
    }

    /// Выбор 20: эхо 14 в первые секунды отбрасывается, те же 20 — приняты.
    func testChoiceKeepsItsValue() {
        let suite = "TailsWF108Tests.choice"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let at = Date(timeIntervalSince1970: 2_000)
        let mirror = ComposerFontMirror(defaults: defaults, now: { at.addingTimeInterval(2) })
        ComposerFont.choose(20, in: defaults, at: at)
        _ = mirror.receive(ComposerFont.Ping(px: 14, chat: "local_a"))
        XCTAssertEqual(ComposerFont.mirror(in: defaults), 20)
        XCTAssertTrue(ComposerFont.isStale(14, in: defaults, at: at.addingTimeInterval(2)))
        XCTAssertFalse(ComposerFont.isStale(20, in: defaults, at: at.addingTimeInterval(2)))
        // Выбора в меню не было вовсе — любое число принимается, как в WF107.
        let clean = UserDefaults(suiteName: suite + ".clean")!
        clean.removePersistentDomain(forName: suite + ".clean")
        addTeardownBlock { clean.removePersistentDomain(forName: suite + ".clean") }
        XCTAssertFalse(ComposerFont.isStale(14, in: clean, at: at))
    }

    // MARK: - стенд канала

    private final class Rig {
        let now = PimpChannel.date("2026-09-30T05:00:00Z")!
        var windows: [PimpWindow]
        var moves: [[PimpMove]] = []

        init() {
            let names = ["Rick", "A", "B", "C", "D"]
            windows = names.enumerated().map { index, name in
                PimpWindow(id: CGWindowID(index + 1), title: name, chat: "local_\(index + 1)",
                           folder: TailsWF108Tests.root + name,
                           frame: CGRect(x: -700 + CGFloat(index) * 300, y: -700, width: 280, height: 600))
            }
        }
    }

    private func makeChannel(_ rig: Rig) -> (PimpChannel, URL) {
        let box = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tails-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: box) }
        let channel = PimpChannel(directory: box, now: { rig.now })
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { rig.windows }
        seats.screens = { [(full: TailsWF108Tests.odyssey, usable: TailsWF108Tests.odyssey)] }
        seats.cellWidth = { 220 }
        seats.gap = { 2 }
        seats.place = { rig.moves.append($0) }
        channel.seats = seats
        channel.start()
        return (channel, box)
    }

    private func ask(_ channel: PimpChannel, _ rig: Rig, _ box: URL, id: String, order: [String]) -> [String: Any]? {
        let list = order.map { "\"\($0)\"" }.joined(separator: ",")
        let body = "{\"id\":\"\(id)\",\"at\":\"\(PimpChannel.stampText(rig.now))\",\"action\":\"arrange\","
            + "\"from\":\"\",\"layout\":\"center\",\"order\":[\(list)],\"center\":\"Rick\"}"
        let url = box.appendingPathComponent(id + ".json")
        try? Data(body.utf8).write(to: url)
        // Время файла — по часам стенда, иначе уборка канала сочла бы запрос старым.
        try? FileManager.default.setAttributes([.modificationDate: rig.now], ofItemAtPath: url.path)
        channel.tick()
        guard let data = try? Data(contentsOf: box.appendingPathComponent(id + ".result.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
