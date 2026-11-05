import XCTest
@testable import ClaudeAX

/// #11654 (+ #11634, контракт `docs/contracts/660-11654-dock-bar.md`): строка «Файлы» над местом — `bx,by,bh` в `/dock`
/// и в `/open-html … dock=1` (К-DOCK-6a), проверка К-DOCK-6b (негодно — строки нет, запрос годен), передача PimpViewer
/// после `&bg=…` (К-DOCK-6c). Порты, окна и склад галереи не трогаем.
final class MaterialsDockBar11654Tests: XCTestCase {
    private let window = CGRect(x: 0, y: 29, width: 1067, height: 618)
    private let room = CGRect(x: 0, y: 55, width: 534, height: 563)
    private let place = "&x=0&y=55&w=534&h=563&wx=0&wy=29&ww=1067&wh=618"

    private func head(_ target: String) -> String { "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" }
    private func dock(_ bar: String) -> MaterialsDock.Request? {
        MaterialsDock.parse(head("/dock?on=1&vis=1" + place + bar + "&bg=1c1917&chat=local_a&seq=3"))
    }

    func testDockParsesBar() throws {
        let request = try XCTUnwrap(dock("&bx=350&by=11&bh=37"))
        XCTAssertEqual(request.place, MaterialsDock.Place(place: room, window: window, bar: MaterialsDock.Bar(x: 350, y: 11, h: 37)))
        XCTAssertEqual(request.bg, "1c1917")
        XCTAssertEqual(dock("&bx=-40&by=11&bh=37")?.place?.bar, MaterialsDock.Bar(x: 0, y: 11, h: 37), "bx < x → bx = x")
        XCTAssertEqual(dock("&bx=454&by=18&bh=37")?.place?.bar, MaterialsDock.Bar(x: 454, y: 18, h: 37), "ровно 80 pt, by + bh = y")
        XCTAssertEqual(dock("&bx=350&by=0&bh=16")?.place?.bar?.h, 16)
        XCTAssertEqual(dock("&bx=350&by=0&bh=55")?.place?.bar?.h, 55, "bh ≤ 64 и by + bh = y")
    }

    func testBadBarDropsOnlyBar() throws {
        for bar in ["", "&bx=455&by=11&bh=37", "&bx=350&by=-1&bh=37", "&bx=350&by=11&bh=15", "&bx=350&by=0&bh=65",
                    "&bx=350&by=19&bh=37", "&bx=35.5&by=11&bh=37", "&bx=350&by=11", "&bx=350&by=11&bh=abc",
                    "&bx=1234567&by=11&bh=37"] {
            let request = try XCTUnwrap(dock(bar), bar)
            XCTAssertEqual(request.place, MaterialsDock.Place(place: room, window: window), bar)
            XCTAssertNil(request.place?.bar, bar)
        }
    }

    func testOpenHtmlDockParsesBar() throws {
        let base = "/open-html?mode=click&dock=1&path=%2Fa%2Fb.html&chat=local_a" + place
        let good = try XCTUnwrap(HtmlChromeOpener.parse(head(base + "&bx=350&by=11&bh=37&frame=0,29,1067,618&bg=1c1917")))
        XCTAssertEqual(good.dock?.bar, MaterialsDock.Bar(x: 350, y: 11, h: 37))
        let bad = try XCTUnwrap(HtmlChromeOpener.parse(head(base + "&bx=350&by=11&bh=99")))
        XCTAssertEqual(bad.dock, MaterialsDock.Place(place: room, window: window), "негодная строка — место как было")
    }

    func testSpotQueryCarriesBarAfterBg() {
        let bar = MaterialsDock.Bar(x: 350, y: 11, h: 37)
        let spot = MaterialsDock.Spot(window: 77, place: room, bg: "1c1917", bar: bar)
        XCTAssertEqual(ViewerClient.dockTarget(MaterialsDock.Command(vis: true, spot: spot)),
                       "/dock?on=1&vis=1&win=77&x=0&y=55&w=534&h=563&bg=1c1917&bx=350&by=11&bh=37")
        XCTAssertEqual(MaterialsDock.Spot(window: 77, place: room, bar: bar).query, "&win=77&x=0&y=55&w=534&h=563&bx=350&by=11&bh=37")
        XCTAssertEqual(MaterialsDock.Spot(window: 77, place: room, bg: "1c1917").query, "&win=77&x=0&y=55&w=534&h=563&bg=1c1917",
                       "строки нет — как было")
    }

    func testHandleAndOpenPassBarToViewer() throws {
        let materials = MaterialsDock()
        materials.heartTimer = false
        materials.findWindow = { [window] frame in frame == window ? 9 : nil }
        let lock = NSLock()
        var sent: [MaterialsDock.Command] = []
        materials.send = { command, done in
            lock.lock(); sent.append(command); lock.unlock()
            done(MaterialsDock.Reply(viewer: .up, docked: true))
        }
        let request = try XCTUnwrap(self.dock("&bx=350&by=11&bh=37"))
        let answered = expectation(description: "ответ /dock")
        materials.handle(request) { _ in answered.fulfill() }
        wait(for: [answered], timeout: 2)
        materials.drain()
        lock.lock(); let first = sent.first; lock.unlock()
        XCTAssertEqual(first?.spot?.bar, MaterialsDock.Bar(x: 350, y: 11, h: 37))
        XCTAssertEqual(first?.spot?.bg, "1c1917")
        let opened = expectation(description: "место для /accept")
        var spot: MaterialsDock.Spot?
        materials.open(MaterialsDock.Place(place: room, window: window, bar: MaterialsDock.Bar(x: 300, y: 11, h: 37))) {
            spot = $0
            opened.fulfill()
        }
        wait(for: [opened], timeout: 2)
        XCTAssertEqual(spot?.query, "&win=9&x=0&y=55&w=534&h=563&bx=300&by=11&bh=37")
    }
}
