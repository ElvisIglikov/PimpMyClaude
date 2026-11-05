import XCTest
@testable import ClaudeAX

/// Цвет боковой панели Claude под доком (#10759, WF282, К-DOCK-5 — `docs/contracts/590-wf282-dock-size.md`): страница
/// шлёт `bg` (6 hex) в `/dock on=1`, Пимп передаёт его PimpViewer в `/dock` и в сердце. Мусор — без цвета, запрос годен.
final class DockLookWF282Tests: XCTestCase {
    private func head(_ target: String) -> String { "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" }
    private let base = "/dock?on=1&vis=1&x=0&y=40&w=420&h=700&wx=383&wy=29&ww=896&wh=742"

    func testParseBg() {
        XCTAssertEqual(MaterialsDock.parse(head(base + "&bg=0E1013&chat=local_a&seq=7"))?.bg, "0e1013")
        XCTAssertNil(MaterialsDock.parse(head(base + "&chat=local_a&seq=7"))?.bg, "нет bg — нет цвета")
        for junk in ["%230e1013", "0e101", "0e10133", "zzzzzz", "red"] {
            let request = MaterialsDock.parse(head(base + "&bg=\(junk)&seq=7"))
            XCTAssertNotNil(request, junk)
            XCTAssertNil(request?.bg, junk)
        }
    }

    func testTargetCarriesBg() {
        let spot = MaterialsDock.Spot(window: 77, place: CGRect(x: 0, y: 40, width: 1067, height: 563), bg: "0e1013")
        XCTAssertEqual(ViewerClient.dockTarget(MaterialsDock.Command(vis: true, spot: spot)),
                       "/dock?on=1&vis=1&win=77&x=0&y=40&w=1067&h=563&bg=0e1013")
        let plain = MaterialsDock.Spot(window: 77, place: CGRect(x: 0, y: 40, width: 420, height: 563))
        XCTAssertEqual(ViewerClient.dockTarget(MaterialsDock.Command(vis: false, spot: plain)),
                       "/dock?on=1&vis=0&win=77&x=0&y=40&w=420&h=563")
    }

    func testHandleForwardsBg() {
        let dock = MaterialsDock()
        dock.heartTimer = false
        dock.findWindow = { _ in 77 }
        var sent: [MaterialsDock.Command] = []
        let lock = NSLock()
        dock.send = { command, done in
            lock.lock(); sent.append(command); lock.unlock()
            done(MaterialsDock.Reply(viewer: .up, docked: true))
        }
        let request = MaterialsDock.parse(head(base + "&bg=0e1013&chat=local_a&seq=7"))!
        dock.handle(request) { _ in }
        dock.drain()
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(sent.last?.spot?.bg, "0e1013")
    }
}
