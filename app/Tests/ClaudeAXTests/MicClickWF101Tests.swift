import AppKit
import XCTest
@testable import ClaudeAX

/// WF101 (#7873): второй клик двойного по кружку не жмёт клавишу Диктатора — иначе запись
/// останавливается сразу после старта. Одиночный клик — как был.
final class MicClickWF101Tests: XCTestCase {
    private let spot = CGPoint(x: 100, y: 100)
    private let hit = MicMonitor.Hit(rect: CGRect(x: 90, y: 90, width: 22, height: 22), key: "a",
                                     chat: "c1", match: "Chat")

    private func rig() -> (MicMonitor, () -> Int) {
        let monitor = MicMonitor()
        var keys = 0
        var state: DictatorState = .idle
        var now = Date(timeIntervalSince1970: 1_000_000)
        monitor.dictatorState = { state }
        monitor.postKey = { keys += 1; state = state == .recording ? .idle : .recording }
        monitor.sendRefused = { _, _ in true }
        monitor.notice = { _ in }
        monitor.now = { now = now.addingTimeInterval(2); return now }
        monitor.noteDictator(true)
        return (monitor, { keys })
    }

    private func click(_ monitor: MicMonitor, count: Int) {
        monitor.mouse(.leftMouseDown, clickCount: count, at: spot) { hit }
        monitor.mouse(.leftMouseUp, clickCount: count, at: spot) { hit }
    }

    func testDoubleClickPressesOnce() {
        let (monitor, keys) = rig()
        click(monitor, count: 1)
        XCTAssertEqual(keys(), 1)
        click(monitor, count: 2)
        XCTAssertEqual(keys(), 1, "второй клик двойного клавишу не жмёт")
    }

    func testSingleClicksStillPress() {
        let (monitor, keys) = rig()
        click(monitor, count: 1)
        click(monitor, count: 1)
        XCTAssertEqual(keys(), 2, "одиночный повтор — остановка, как раньше")
    }
}
