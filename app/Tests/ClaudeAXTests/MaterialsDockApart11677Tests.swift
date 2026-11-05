import XCTest
@testable import ClaudeAX

/// #11677 (Элвис 05.11: «PimpViewer был отдельным приложением наверху… документы было удобно смотреть»): ответ `/dock`
/// несёт `apart` — PimpViewer жив, дока нет ни у одного окна Claude и отдельное окно галереи на экране. Тогда страница
/// отдаёт файл из чата в то окно и док сама не ставит. Окно галереи спрашиваем только без дока: окно-док — тоже её окно.
final class MaterialsDockApart11677Tests: XCTestCase {
    private let frame = CGRect(x: 383, y: 29, width: 896, height: 742)

    private final class Box {
        let lock = NSLock()
        var answers: [MaterialsDock.Answer] = []
        var asks = 0
        var shown = true
    }

    private func make(_ box: Box, viewer: MaterialsDock.Viewer = .up) -> MaterialsDock {
        let dock = MaterialsDock()
        dock.heartTimer = false
        dock.findWindow = { [frame] in $0 == frame ? 7 : nil }
        dock.probe = { $0(viewer) }
        dock.send = { command, done in done(MaterialsDock.Reply(viewer: viewer, docked: command.spot != nil)) }
        dock.windowShown = { box.lock.lock(); defer { box.lock.unlock() }; box.asks += 1; return box.shown }
        return dock
    }

    private func ask(_ dock: MaterialsDock, _ box: Box, _ target: String) -> MaterialsDock.Answer {
        let request = MaterialsDock.parse("GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n")!
        dock.handle(request) { answer in box.lock.lock(); box.answers.append(answer); box.lock.unlock() }
        dock.drain()
        dock.drain()
        box.lock.lock(); defer { box.lock.unlock() }
        return box.answers.last!
    }

    private var on: String {
        "/dock?on=1&vis=1&x=0&y=40&w=420&h=700&wx=383&wy=29&ww=896&wh=742&chat=local_a&seq=7"
    }

    private func json(_ answer: MaterialsDock.Answer) -> String { String(decoding: answer.json, as: UTF8.self) }

    func testProbeApartWhenViewerWindowOnScreenAndNoDock() {
        let box = Box()
        let dock = make(box)
        XCTAssertEqual(json(ask(dock, box, "/dock?probe=1")), #"{"ok":true,"viewer":"up","apart":true}"#)
        box.shown = false
        XCTAssertEqual(json(ask(dock, box, "/dock?probe=1")), #"{"ok":true,"viewer":"up","apart":false}"#, "окна не видно")
    }

    func testViewerDownOrMissingIsNotApartAndWindowNotAsked() {
        for viewer in [MaterialsDock.Viewer.down, .none] {
            let box = Box()
            let dock = make(box, viewer: viewer)
            XCTAssertFalse(ask(dock, box, "/dock?probe=1").apart, viewer.rawValue)
            XCTAssertEqual(box.asks, 0, "галерея не жива — окна не ищем")
        }
    }

    func testDockStandingIsNotApartAndWindowNotAsked() {
        let box = Box()
        let dock = make(box)
        let taken = ask(dock, box, on)
        XCTAssertEqual(json(taken), #"{"ok":true,"viewer":"up","docked":true,"owner":"this","apart":false}"#)
        XCTAssertFalse(ask(dock, box, "/dock?probe=1").apart, "док у окна Claude — файл в док, как раньше")
        XCTAssertEqual(box.asks, 0, "окно-док за отдельное окно не считаем")
        // Закрыли док кнопкой — отдельное окно на экране снова «apart».
        let closed = ask(dock, box, "/dock?on=0&chat=local_a&wx=383&wy=29&ww=896&wh=742&seq=9")
        XCTAssertEqual(json(closed), #"{"ok":true,"viewer":"up","docked":false,"owner":"this","apart":true}"#)
        XCTAssertTrue(ask(dock, box, "/dock?probe=1").apart)
    }

    func testOldAnswerDefaultsToNotApart() {
        XCTAssertFalse(MaterialsDock.Answer(ok: true, viewer: .up, docked: false, mine: true).apart)
    }
}
