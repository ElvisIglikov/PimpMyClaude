import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Новый чат при свёрнутом или закрытом главном окне Claude (01.10.2026): выносит чаты только главное
/// окно, поэтому канал сперва возвращает его и отвечает `busy` — CLI повторит через 2 с; окно так и не
/// пришло — прежний отказ.
final class MainWindowReturnTests: XCTestCase {
    // Часы стенда — в прошлом: уборка канала сносит файлы, чей mtime «старше часа» от этих часов.
    private let t0 = PimpChannel.date("2026-09-07T11:20:00Z")!
    private let main = PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 490, height: 859))
    private let other = PimpWindow(id: 2, title: "Сайт", frame: CGRect(x: 500, y: 34, width: 490, height: 859))

    private final class Rig {
        var now: Date
        var windows: [PimpWindow]
        var canShow = true
        var shows = 0
        var popouts: [String] = []
        init(now: Date, windows: [PimpWindow]) {
            self.now = now
            self.windows = windows
        }
    }

    private func channel(_ rig: Rig) throws -> (PimpChannel, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("main-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let channel = PimpChannel(directory: dir, now: { rig.now })
        var seats = PimpSeats()
        seats.claudeRunning = { true }
        seats.windows = { rig.windows }
        seats.projects = {
            [Project(folder: URL(fileURLWithPath: "/tmp/TrelvisCom", isDirectory: true), name: "TrelvisCom",
                     lastFocusedAt: 0)]
        }
        seats.isMainWindow = { $0 == "Claude" }
        seats.openChat = { chat, _, _ in rig.popouts.append(chat) }
        seats.lastChat = { _ in (chat: "local_8", title: "Чат") }
        seats.showMain = {
            rig.shows += 1
            return rig.canShow
        }
        channel.seats = seats
        channel.start()
        return (channel, dir)
    }

    /// `open TrelvisCom --last` файлом канала; ответ — "ok", код ошибки или nil (ответа ещё нет).
    private func ask(_ channel: PimpChannel, _ dir: URL, _ rig: Rig, id: String) -> String? {
        let body = "{\"id\":\"\(id)\",\"at\":\"\(PimpChannel.stampText(rig.now))\",\"action\":\"new-window\","
            + "\"from\":\"\",\"project\":\"TrelvisCom\",\"place\":\"right\",\"chat\":\"last\"}"
        try? Data(body.utf8).write(to: dir.appendingPathComponent(id + ".json"))
        channel.tick()
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(id + ".result.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["ok"] as? Bool) == true ? "ok" : json["error"] as? String
    }

    func testClosedMainIsShownThenLastChatOpens() throws {
        let rig = Rig(now: t0, windows: [other])
        let (channel, dir) = try channel(rig)
        XCTAssertEqual(ask(channel, dir, rig, id: "1-1"), "busy")
        XCTAssertEqual(rig.shows, 1)
        XCTAssertEqual(rig.popouts, [])
        rig.now = t0.addingTimeInterval(2)
        rig.windows = [main, other]
        XCTAssertNil(ask(channel, dir, rig, id: "1-2"), "главное вернулось — чат выносится, ответ после рождения окна")
        XCTAssertEqual(rig.popouts, ["local_8"])
        XCTAssertEqual(rig.shows, 1)
    }

    func testMainThatNeverReturnsFallsBackToOldRefusal() throws {
        let rig = Rig(now: t0, windows: [other])
        let (channel, dir) = try channel(rig)
        XCTAssertEqual(ask(channel, dir, rig, id: "2-1"), "busy")
        rig.now = t0.addingTimeInterval(2)
        XCTAssertEqual(ask(channel, dir, rig, id: "2-2"), "busy", "ждём окно, второй раз не зовём")
        rig.now = t0.addingTimeInterval(PimpChannel.mainWaitSeconds + 1)
        XCTAssertEqual(ask(channel, dir, rig, id: "2-3"), "window-missing")
        XCTAssertEqual(rig.shows, 1)
        XCTAssertEqual(rig.popouts, [])
    }

    func testNothingToShowKeepsNoWindows() throws {
        let rig = Rig(now: t0, windows: [])
        rig.canShow = false
        let (channel, dir) = try channel(rig)
        XCTAssertEqual(ask(channel, dir, rig, id: "3-1"), "no-windows")
        XCTAssertEqual(rig.shows, 1)
    }
}
