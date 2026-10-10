import AppKit
import XCTest
@testable import ClaudeAX

/// Просмотр файла в окне чата (план WF103, батч S1): разбор `view`, маршрут, доступ на чтение,
/// цвет надписей, закрытие по resignActive. Окно не строится (`presents = false`).
final class FileViewWF103Tests: XCTestCase {
    typealias Request = HtmlChromeOpener.Request

    // MARK: - разбор

    func testParseView() {
        let request = HtmlChromeOpener.parse(
            "GET /open-html?mode=view&path=%2FUsers%2Fe%2Fa.html&chat=local_abc&frame=100,-900,800,700&bg=1A2B3C HTTP/1.1")
        XCTAssertEqual(request, Request(path: "/Users/e/a.html", mode: .view, chat: "local_abc",
                                        frame: CGRect(x: 100, y: -900, width: 800, height: 700), bg: "1a2b3c"))
        // Не страница — прежний click.
        XCTAssertEqual(HtmlChromeOpener.parse("GET /open-html?mode=view&path=%2Fa%2Fb.png HTTP/1.1")?.mode, .click)
        XCTAssertEqual(HtmlChromeOpener.parse("GET /open-html?mode=view&path=%2Fa%2Fb.pdf HTTP/1.1")?.mode, .click)
        XCTAssertEqual(HtmlChromeOpener.parse("GET /open-html?mode=view&path=%2Fa%2Fb.HTM HTTP/1.1")?.mode, .view)
    }

    func testParseFrameAndBgGarbage() {
        for bad in ["1,2,3", "1,2,0,4", "1,2,3,-4", "a,b,c,d", "1.5,2,3,4", "1,2,3,4,5", "", "+1,2,3,4", "1,,3,4"] {
            let head = "GET /open-html?mode=view&path=%2Fa.html&frame=\(bad) HTTP/1.1"
            XCTAssertNil(HtmlChromeOpener.parse(head)?.frame, bad)
        }
        XCTAssertEqual(HtmlChromeOpener.frame("-1512,-30,10,20"), CGRect(x: -1512, y: -30, width: 10, height: 20))
        for bad in ["12345", "1234567", "#12345", "gggggg", "", "ффффff"] {
            XCTAssertNil(HtmlChromeOpener.color(bad), bad)
        }
        XCTAssertEqual(HtmlChromeOpener.color("ABCDEF"), "abcdef")
    }

    func testOldAddressesUnchanged() {
        XCTAssertNil(HtmlChromeOpener.parse("GET /open-html?mode=auto&path=%2FUsers%2Fe%2Fa.html HTTP/1.1"))
        let click = HtmlChromeOpener.parse("GET /open-html?mode=click&path=%2Fa%2Fb.png&chat=local_x HTTP/1.1")
        XCTAssertEqual(click, Request(path: "/a/b.png", mode: .click, chat: "local_x"))
        XCTAssertNil(click?.frame)
        XCTAssertNil(click?.bg)
    }

    // MARK: - экран

    /// Окно просмотра — ровно рамка окна чата (#7964): перевод из координат страницы туда и обратно.
    func testWindowFrameIsChatFrame() {
        let chat = CGRect(x: 908, y: -720, width: 283, height: 720)
        XCTAssertEqual(Screens.flip(rect: FileView.windowFrame(for: chat)), chat)
        XCTAssertEqual(FileView.windowFrame(for: chat).size, chat.size)
    }

    // MARK: - маршрут

    private final class Route {
        let opener = HtmlChromeOpener()
        var viewer: [Request] = []
        var views: [Request] = []
        var browser: [Request] = []
        var clock = Date(timeIntervalSince1970: 1000)

        init(known: Set<String> = ["local_a"], viewerTakes: Bool = false, onView: Bool = true) {
            opener.toViewer = { [unowned self] request, done in self.viewer.append(request); done(viewerTakes) }
            if onView { opener.onView = { [unowned self] in self.views.append($0) } }
            opener.isKnownChat = { known.contains($0) }
            opener.browserSeam = { [unowned self] in self.browser.append($0) }
            opener.now = { [unowned self] in self.clock }
        }
    }

    private let view = Request(path: "/p/a.html", mode: .view, chat: "local_a",
                               frame: CGRect(x: 0, y: 0, width: 10, height: 10), bg: "ffffff")

    func testViewAcceptedGoesToGalleryQuietlyAndNeverBrowser() {
        for takes in [true, false] {
            let route = Route(viewerTakes: takes)
            route.opener.route(view)
            XCTAssertEqual(route.views, [view])
            XCTAssertEqual(route.viewer, [Request(path: "/p/a.html", mode: .view, chat: "local_a")])
            XCTAssertEqual(route.browser, [])
            XCTAssertEqual(route.opener.viewRejected, 0)
        }
    }

    /// Окно просмотра не ждёт галерею (WF104): ответа нет вовсе — `onView` уже был, браузера нет.
    func testViewDoesNotWaitForGallery() {
        let route = Route()
        var pending: [(Bool) -> Void] = []
        route.opener.toViewer = { request, done in route.viewer.append(request); pending.append(done) }
        route.opener.route(view)
        XCTAssertEqual(route.views, [view])
        XCTAssertEqual(route.viewer.map(\.mode), [.view])
        pending.forEach { $0(false) }
        XCTAssertEqual(route.browser, [])
    }

    func testViewWithoutKnownChatFallsBackToClick() {
        var noChat = view
        noChat.chat = nil
        var stranger = view
        stranger.chat = "local_zzz"
        for request in [noChat, stranger] {
            let route = Route()
            route.opener.route(request)
            XCTAssertEqual(route.views, [])
            XCTAssertEqual(route.viewer.map(\.mode), [.click])
            XCTAssertEqual(route.browser.map(\.mode), [.click])
            XCTAssertEqual(route.opener.viewRejected, 1)
        }
    }

    func testSecondViewWithinSecondIsDropped() {
        let route = Route(viewerTakes: true)
        route.opener.route(view)
        route.clock.addTimeInterval(0.5)
        route.opener.route(view)
        XCTAssertEqual(route.views.count, 1)
        XCTAssertEqual(route.viewer.map(\.mode), [.view])
        XCTAssertEqual(route.browser, [])
        XCTAssertEqual(route.opener.viewRejected, 1)
        route.clock.addTimeInterval(0.6)
        route.opener.route(view)
        XCTAssertEqual(route.views.count, 2)
    }

    func testViewWithoutFrameIsClick() {
        var noFrame = view
        noFrame.frame = nil
        let route = Route()
        route.opener.route(noFrame)
        XCTAssertEqual(route.views, [])
        XCTAssertEqual(route.viewer.map(\.mode), [.click])
        XCTAssertEqual(route.opener.viewRejected, 1)
    }

    func testNoOnViewIsClick() {
        let route = Route(onView: false)
        route.opener.route(view)
        XCTAssertEqual(route.viewer.map(\.mode), [.click])
        XCTAssertEqual(route.browser.map(\.mode), [.click])
        XCTAssertEqual(route.opener.viewRejected, 1)
    }

    // MARK: - доступ на чтение

    func testReadAccess() {
        let home = "/Users/e"
        XCTAssertEqual(FileView.readAccess(file: "/Users/e/P/docs/a.html", cwd: "/Users/e/P", home: home).path, "/Users/e/P")
        // Файл вне папки проекта — папка файла.
        XCTAssertEqual(FileView.readAccess(file: "/tmp/x/a.html", cwd: "/Users/e/P", home: home).path, "/tmp/x")
        // Проект закрытый (дом) — папка файла.
        XCTAssertEqual(FileView.readAccess(file: "/Users/e/Q/a.html", cwd: "/Users/e", home: home).path, "/Users/e/Q")
        // Папка файла закрытая — только сам файл.
        XCTAssertEqual(FileView.readAccess(file: "/Users/e/a.html", cwd: nil, home: home).path, "/Users/e/a.html")
        XCTAssertEqual(FileView.readAccess(file: "/Users/e/Library/x/a.html", cwd: "/Users/e/Library",
                                           home: home).path, "/Users/e/Library/x/a.html")
        // `..` не выводит за папку проекта.
        XCTAssertEqual(FileView.readAccess(file: "/Users/e/P/../R/a.html", cwd: "/Users/e/P", home: home).path, "/Users/e/R")
    }

    // MARK: - цвет надписей

    func testLabelContrast() {
        XCTAssertTrue(FileView.prefersDarkText(bg: "ffffff"))
        XCTAssertTrue(FileView.prefersDarkText(bg: "f5f0e6"))
        XCTAssertFalse(FileView.prefersDarkText(bg: "000000"))
        XCTAssertFalse(FileView.prefersDarkText(bg: "1b1b1d"))
        XCTAssertFalse(FileView.prefersDarkText(bg: nil))
        XCTAssertFalse(FileView.prefersDarkText(bg: "мусор"))
    }

    // MARK: - закрытие

    func testResignActiveClosesWithoutReturning() {
        let view = FileView()
        view.presents = false
        var returned: [CGRect?] = []
        view.onReturn = { returned.append($0) }
        view.show(self.view, cwd: "/p")
        XCTAssertEqual(view.current?.path, "/p/a.html")
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        XCTAssertNil(view.current)
        XCTAssertEqual(view.shown, 1)
        XCTAssertEqual(view.closed, 1)
        XCTAssertTrue(returned.isEmpty)
        // «Вернуть» — Claude вперёд по рамке чата.
        view.show(self.view, cwd: "/p")
        view.returnTapped(nil)
        XCTAssertEqual(returned, [CGRect(x: 0, y: 0, width: 10, height: 10)])
        XCTAssertEqual(view.closed, 2)
    }

    func testGalleryAndBrowserClose() {
        let view = FileView()
        view.presents = false
        var gallery: [String] = []
        var browser: [String] = []
        view.toGallery = { path, _ in gallery.append(path) }
        view.toBrowser = { browser.append($0) }
        view.show(self.view, cwd: nil)
        view.galleryTapped(nil)
        XCTAssertNil(view.current)
        view.show(self.view, cwd: nil)
        view.browserTapped(nil)
        XCTAssertEqual(gallery, ["/p/a.html"])
        XCTAssertEqual(browser, ["/p/a.html"])
        XCTAssertEqual(view.closed, 2)
    }

    func testNearestClaudeWindow() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(FileView.nearest(frame, among: [nil, CGRect(x: 500, y: 0, width: 10, height: 10),
                                                       CGRect(x: 50, y: 0, width: 100, height: 100),
                                                       CGRect(x: 0, y: 0, width: 100, height: 100)]), 3)
        XCTAssertNil(FileView.nearest(frame, among: [CGRect(x: 500, y: 0, width: 10, height: 10)]))
    }
}
