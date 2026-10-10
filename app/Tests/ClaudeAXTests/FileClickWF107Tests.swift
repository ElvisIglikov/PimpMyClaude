import AppKit
import XCTest
@testable import ClaudeAX

/// Клик по файлу — сразу в PimpViewer (WF107 #8127, контракт К3, сторона приложения): `click` от чата → галерея;
/// галерея не взяла или её нет — окно просмотра поверх окна чата (рамка есть, чат известен), иначе браузер.
final class FileClickWF107Tests: XCTestCase {
    typealias Request = HtmlChromeOpener.Request

    private final class Route {
        let opener = HtmlChromeOpener()
        var viewer: [Request] = []
        var views: [Request] = []
        var browser: [Request] = []
        var clock = Date(timeIntervalSince1970: 1000)

        init(viewerTakes: Bool? = false, onView: Bool = true) {
            if let takes = viewerTakes {
                opener.toViewer = { [unowned self] request, done in self.viewer.append(request); done(takes) }
            }
            if onView { opener.onView = { [unowned self] in self.views.append($0) } }
            opener.isKnownChat = { $0 == "local_a" }
            opener.browserSeam = { [unowned self] in self.browser.append($0) }
            opener.now = { [unowned self] in self.clock }
        }
    }

    private let frame = CGRect(x: -800, y: -720, width: 568, height: 720)
    private var click: Request {
        Request(path: "/p/a.html", mode: .click, chat: "local_a", frame: frame, bg: "1a2b3c")
    }

    /// Разбор: `click` со страницы несёт рамку и фон окна чата (для запасного пути).
    func testParseClickKeepsFrameAndBg() {
        let request = HtmlChromeOpener.parse(
            "GET /open-html?mode=click&path=%2Fp%2Fa.html&chat=local_a&frame=-800,-720,568,720&bg=1A2B3C HTTP/1.1")
        XCTAssertEqual(request, click)
    }

    /// «🌐 Открыть в браузере» (`browser`) — сразу браузер: галерея и окно просмотра его не видят.
    func testBrowserModeSkipsGallery() {
        let request = HtmlChromeOpener.parse("GET /open-html?mode=browser&path=%2Fp%2Fa.html&chat=local_a HTTP/1.1")
        XCTAssertEqual(request?.mode, .browser)
        let route = Route(viewerTakes: true)
        route.opener.route(request!)
        XCTAssertEqual(route.viewer, [])
        XCTAssertEqual(route.views, [])
        XCTAssertEqual(route.browser.map(\.path), ["/p/a.html"])
        XCTAssertEqual(route.browser.map(\.mode), [.click])
    }

    func testGalleryTakesClick() {
        let route = Route(viewerTakes: true)
        route.opener.route(click)
        XCTAssertEqual(route.viewer, [click])
        XCTAssertEqual(route.views, [])
        XCTAssertEqual(route.browser, [])
    }

    func testGalleryRefusedFallsBackToChatWindow() {
        let route = Route(viewerTakes: false)
        route.opener.route(click)
        XCTAssertEqual(route.viewer.map(\.mode), [.click])
        XCTAssertEqual(route.views, [Request(path: "/p/a.html", mode: .view, chat: "local_a", frame: frame, bg: "1a2b3c")])
        XCTAssertEqual(route.browser, [])
    }

    func testNoGalleryFallsBackToChatWindow() {
        let route = Route(viewerTakes: nil)
        route.opener.route(click)
        XCTAssertEqual(route.views.map(\.path), ["/p/a.html"])
        XCTAssertEqual(route.browser, [])
    }

    func testFallbackWithoutFrameOrKnownChatIsBrowser() {
        var noFrame = click
        noFrame.frame = nil
        var stranger = click
        stranger.chat = "local_zzz"
        var noChat = click
        noChat.chat = nil
        for request in [noFrame, stranger, noChat] {
            let route = Route()
            route.opener.route(request)
            XCTAssertEqual(route.views, [])
            XCTAssertEqual(route.browser, [request])
        }
        let route = Route(onView: false)
        route.opener.route(click)
        XCTAssertEqual(route.browser, [click])
    }

    /// Окно просмотра — только для страниц; фото, PDF и `auto` — как было.
    func testPhotoPdfAndAutoKeepOldPath() {
        let photo = Request(path: "/p/a.png", mode: .click, chat: "local_a", frame: frame, bg: nil)
        let route = Route()
        route.opener.route(photo)
        XCTAssertEqual(route.viewer, [photo])
        XCTAssertEqual(route.browser, [photo])
        XCTAssertEqual(route.views, [])

        // PDF по клику — в галерею (PimpViewer 1.7), не взяла — браузер.
        let pdf = Request(path: "/p/a.pdf", mode: .click, chat: "local_a", frame: frame, bg: nil)
        let pdfRoute = Route(viewerTakes: true)
        pdfRoute.opener.route(pdf)
        XCTAssertEqual(pdfRoute.viewer, [pdf])
        XCTAssertEqual(pdfRoute.browser, [])
        let pdfRefused = Route(viewerTakes: false)
        pdfRefused.opener.route(pdf)
        XCTAssertEqual(pdfRefused.browser, [pdf])
        XCTAssertEqual(pdfRefused.views, [])


    }

    /// Запасное окно просмотра — не чаще 1/с, как у `view`: лишний клик молча мимо (не браузер).
    func testFallbackRateLimited() {
        let route = Route()
        route.opener.route(click)
        route.clock.addTimeInterval(0.5)
        route.opener.route(click)
        XCTAssertEqual(route.views.count, 1)
        XCTAssertEqual(route.browser, [])
        route.clock.addTimeInterval(0.6)
        route.opener.route(click)
        XCTAssertEqual(route.views.count, 2)
    }

    /// `view` (правый клик «👁 Посмотреть в окне чата») — как было: окно просмотра и тихая галерея.
    func testViewUnchanged() {
        let view = Request(path: "/p/a.html", mode: .view, chat: "local_a", frame: frame, bg: "1a2b3c")
        let route = Route(viewerTakes: false)
        route.opener.route(view)
        XCTAssertEqual(route.views, [view])
        XCTAssertEqual(route.viewer, [Request(path: "/p/a.html", mode: .view, chat: "local_a")])
        XCTAssertEqual(route.browser, [])
    }
}
