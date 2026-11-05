import AppKit
import XCTest
@testable import ClaudeAX

/// Прогрев «Нового окна» и «🪟 Новое окно ▸ проект» из меню через канал (WF88/WF94). Движок пустого
/// окна (File ▸ «New Session in New Window», черновик «Code», `draft-setup`, «↩︎» меню ⌘B) снят
/// в WF248 вместе со своими тестами.
final class NewWindowWF88Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_413_200)
    private let project = Project(folder: URL(fileURLWithPath: "/tmp/VkusnoffKz", isDirectory: true),
                                  name: "VkusnoffKz", lastFocusedAt: 0)
    private let main = PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 490, height: 859))
    private let placed = CGRect(x: 980, y: 34, width: 490, height: 859)

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf88-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Прогрев 40 с и перенос «Обкэшить» — чужая цепочка нового окна: канал «Новое окно» из меню не берёт.
    func testNewWindowWarmupIsBusyFor40Seconds() {
        XCTAssertTrue(ClaudeActions.newWindowBusy(cashout: true, since: nil, now: t0))
        XCTAssertFalse(ClaudeActions.newWindowBusy(cashout: false, since: nil, now: t0))
        XCTAssertTrue(ClaudeActions.newWindowBusy(cashout: false, since: t0, now: t0.addingTimeInterval(39)))
        XCTAssertFalse(ClaudeActions.newWindowBusy(cashout: false, since: t0, now: t0.addingTimeInterval(41)))
    }

    // MARK: - работа канала

    /// Стенд: канал на временном каталоге, часы и все сиденья — заглушки с журналом.
    private final class Rig {
        var now: Date
        var running = true
        var windows: [PimpWindow]
        var busy = false
        var log: [String] = []
        var arranged: [(ids: [CGWindowID], ordered: Bool)] = []
        var notices: [String] = []
        var opened: [String] = []
        var last: (chat: String, title: String)?
        init(now: Date, windows: [PimpWindow]) {
            self.now = now
            self.windows = windows
        }
    }

    private func channel(_ rig: Rig, placed: CGRect? = nil) throws -> (PimpChannel, URL) {
        let dir = try tempDir().appendingPathComponent("pimp", isDirectory: true)
        let channel = PimpChannel(directory: dir, now: { rig.now })
        let target = placed ?? self.placed
        channel.seats = PimpSeats(
            claudeRunning: { rig.running },
            windows: { rig.windows },
            projects: { [self.project] },
            arrangeSmart: { ids, ordered, _ in
                rig.arranged.append((ids, ordered))
                rig.log.append("arrange")
                return ids.map { id in
                    PimpWindow(id: id, title: id == 1 ? "Claude" : "Code",
                               frame: id == ids.last ? target : CGRect(x: 0, y: 34, width: 490, height: 859))
                }
            },
            isMainWindow: { $0 == "Claude" },
            openChat: { chat, _, _ in rig.opened.append(chat) },
            notice: { rig.notices.append($0) },
            raise: { rig.log.append("raise \($0)") },
            lastChat: { _ in rig.last },
            newWindowBusy: { rig.busy })
        return (channel, dir)
    }

    private func files(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private func code(_ id: CGWindowID, title: String = "Code",
                      frame: CGRect = CGRect(x: 300, y: 100, width: 900, height: 700)) -> PimpWindow {
        PimpWindow(id: id, title: title, frame: frame)
    }

}
