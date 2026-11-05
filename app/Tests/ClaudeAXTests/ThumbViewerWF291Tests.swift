import ImageIO
import Network
import XCTest
@testable import ClaudeAX

/// WF291 #10603 (слово Элвиса 22.10.2026: «превьюшки сделать HTML… прямо сразу превьюшка была… как в PimpViewer»):
/// `/thumb` для HTML/HTM/PDF сперва берёт снимок карточки у PimpViewer (`ViewerClient.thumb`, К-V8 `GET /thumb`);
/// 404, не JPEG, тишина — прежний QuickLook. Фото — только как было, галерею не спрашиваем. Живые порты не трогаем:
/// галерея — шов `viewerThumb` или свой слушатель `FakeViewer`, QuickLook — шов `pageShot`.
final class ThumbViewerWF291Tests: XCTestCase {
    private let chat = "local_thumb-291"
    private var dir: URL!
    private let viewerJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
    private let quickLookJPEG = Data([0xFF, 0xD8, 0xFF, 0xDB, 0x09])

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb291-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func file(_ name: String) throws -> String {
        let url = dir.appendingPathComponent(name)
        try Data("<html><body>ФАЙЛ 65</body></html>".utf8).write(to: url)
        return url.resolvingSymlinksInPath().path
    }

    /// Пимп с известным чатом; галерея отвечает `answer` (nil — молчит), QuickLook — `quickLookJPEG`.
    private func opener(asked: @escaping (String) -> Void = { _ in },
                        answer: @escaping (String) -> Data?? ) -> HtmlChromeOpener {
        let opener = HtmlChromeOpener()
        opener.home = dir.path
        opener.isKnownChat = { $0 == self.chat }
        opener.pageShot = { [quickLookJPEG] _ in quickLookJPEG }
        opener.viewerThumb = { path, done in
            asked(path)
            if let reply = answer(path) { done(reply) }
        }
        return opener
    }

    func testHtmlTakesViewerShot() throws {
        for name in ["65.html", "a.HTM", "b.pdf"] {
            let path = try file(name)
            var asked: [String] = []
            let opener = opener(asked: { asked.append($0) }, answer: { [viewerJPEG] _ in .some(viewerJPEG) })
            XCTAssertEqual(opener.thumb(.init(path: path, chat: chat)), viewerJPEG, name)
            XCTAssertEqual(asked, [path], "галерею спросили ровно раз, полным путём")
        }
    }

    func testViewerRefusedOrSilentFallsBackToQuickLook() throws {
        let path = try file("65.html")
        // 404 и ошибка клиента — nil; ответ не JPEG.
        for reply in [nil, Data("<html>".utf8), Data([0xFF])] as [Data?] {
            let opener = opener(answer: { _ in .some(reply) })
            XCTAssertEqual(opener.thumb(.init(path: path, chat: chat)), quickLookJPEG)
        }
        // Галерея молчит — ждём не дольше `viewerThumbWait`, потом QuickLook.
        let silent = opener(answer: { _ in .none })
        let started = Date()
        XCTAssertEqual(silent.thumb(.init(path: path, chat: chat)), quickLookJPEG)
        XCTAssertLessThan(Date().timeIntervalSince(started), HtmlChromeOpener.viewerThumbWait + 1)
    }

    func testPhotoGoesStraightToQuickLook() throws {
        let url = dir.appendingPathComponent("a.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let target = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(target, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(target))
        var asked = 0
        let opener = opener(asked: { _ in asked += 1 }, answer: { [viewerJPEG] _ in .some(viewerJPEG) })
        let jpeg = try XCTUnwrap(opener.thumb(.init(path: url.resolvingSymlinksInPath().path, chat: chat)))
        XCTAssertNotEqual(jpeg, viewerJPEG)
        XCTAssertEqual([UInt8](jpeg.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(asked, 0, "фото — без галереи")
    }

    // MARK: - ViewerClient.thumb против своего слушателя

    private func client(_ fake: ViewerChannelWF104Tests.FakeViewer) throws -> ViewerClient {
        let token = dir.appendingPathComponent("channel.token")
        try Data((String(repeating: "c3", count: 16) + "\n").utf8).write(to: token)
        let client = ViewerClient(port: fake.port, tokenURL: token, launches: true)
        client.owners = { _, _ in [.init(pid: getpid(), path: "/Applications/PimpViewer.app/Contents/MacOS/PimpViewer")] }
        client.installed = { true }
        client.running = { false }
        client.launch = { XCTFail("ради снимка галерею не запускаем") }
        client.raise = { XCTFail("окно галереи не выводим"); return true }
        return client
    }

    private func thumb(_ client: ViewerClient, _ path: String) -> Data? {
        let done = expectation(description: "thumb")
        var result: Data?
        client.thumb(path: path) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    /// Слушатель, что отвечает байтами (у `FakeViewer` ответ — строка, а FF D8 — не UTF-8).
    private final class RawViewer {
        let listener: NWListener
        private let queue = DispatchQueue(label: "test.raw-viewer")
        var reply = Data()
        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [unowned self] connection in
                connection.start(queue: self.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [unowned self] _, _, _, _ in
                    connection.send(content: self.reply, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 2)
        }
        var port: UInt16 { listener.port?.rawValue ?? 0 }
        deinit { listener.cancel() }
    }

    func testViewerClientThumbJPEG() throws {
        let raw = try RawViewer()
        let body: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
        raw.reply = Data("HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            + Data(body)
        let token = dir.appendingPathComponent("channel.token")
        try Data((String(repeating: "c3", count: 16) + "\n").utf8).write(to: token)
        let client = ViewerClient(port: raw.port, tokenURL: token, launches: false)
        client.owners = { _, _ in [.init(pid: getpid(), path: "/Applications/PimpViewer.app/Contents/MacOS/PimpViewer")] }
        client.installed = { true }
        client.running = { true }
        client.launch = { XCTFail("ради снимка галерею не запускаем") }
        XCTAssertEqual(thumb(client, "/p/65.html").map { [UInt8]($0) }, body)
    }

    func testViewerClientThumb() throws {
        typealias Fake = ViewerChannelWF104Tests.FakeViewer
        let fake = try Fake()
        let client = try client(fake)
        // Отказ и не JPEG — nil, без запуска галереи.
        for answer in [Fake.json(#"{"ok":false}"#, status: "404 Not Found"), Fake.json(#"{"ok":true}"#)] {
            fake.answer = { _, _ in answer }
            XCTAssertNil(thumb(client, "/p/65.html"), answer)
            // «Нет снимка» — не «галерея упала»: счёт кнопки «Галерея» не теряет тик до `/ping`.
            XCTAssertTrue(client.isUp, answer)
        }
        fake.answer = { _, _ in nil }
        XCTAssertNil(thumb(client, "/p/65.html"), "молчит — nil за таймаут")
        XCTAssertFalse(client.isUp, "молчит — не жива")
        let first = try XCTUnwrap(fake.requests.first)
        XCTAssertTrue(first.hasPrefix("GET /thumb?path=%2Fp%2F65.html HTTP/1.1\r\n"), first)
        XCTAssertTrue(first.lowercased().contains("x-pimp-viewer-token: \(String(repeating: "c3", count: 16))"))
    }
}
