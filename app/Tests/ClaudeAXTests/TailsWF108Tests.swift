import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Хвосты проверки WF107 (WF108, Б9): `skipped` нового пути центра, экран «главного по центру» по месту
/// главного в тесноте.
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
