import AVFoundation
import ImageIO
import Network
import XCTest
@testable import ClaudeAX

/// #10699 (слово Элвиса 23.10.2026: «Капец долго грузятся ролики… Они же на диске всё равно лежат»): ролики и картинки
/// чата — с диска. Разбор `/media-thumb`, `/media-file` и `/open-html` по имени, белый список страницы, клиент
/// `ViewerClient.resolve` (К-V8 `/resolve`) против своего слушателя, проверки пути (только путь страницы с проверками
/// `/thumb` или путь галереи), первый кадр настоящего mp4, кэш кадров и ответы по настоящему сокету. Живые порты
/// 47615/47616, окна и склад галереи не трогаем.
final class ChatMedia10699Tests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func head(_ target: String, origin: String? = nil) -> String {
        "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n\r\n" } ?? "")
    }

    private func enc(_ text: String) -> String { ViewerClient.encode(text) }

    /// Пимп с известным чатом `local_a`, домом во временной папке и галереей-подменой.
    private func makeOpener(resolve: @escaping (String, String) -> String? = { _, _ in nil }) -> HtmlChromeOpener {
        let opener = HtmlChromeOpener()
        opener.channelToken = { nil }
        opener.home = tmp.path
        opener.isKnownChat = { $0 == "local_a" }
        opener.media.resolve = { chat, name, done in done(resolve(chat, name)) }
        return opener
    }

    private func file(_ name: String, _ data: Data = Data("x".utf8)) throws -> String {
        let url = tmp.appendingPathComponent(name)
        try data.write(to: url)
        return url.resolvingSymlinksInPath().path
    }

    private func locate(_ opener: HtmlChromeOpener, chat: String = "local_a", name: String, path: String?,
                        extensions: Set<String> = ChatMedia.videoExtensions) -> String? {
        let done = expectation(description: "locate")
        var result: String?
        opener.locateMedia(chat: chat, name: name, path: path, extensions: extensions) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    // MARK: - разбор

    func testParseMediaRequests() throws {
        let thumb = try XCTUnwrap(ChatMedia.parse(head("/media-thumb?chat=local_a&name=\(enc("пицца 2.mp4"))&path=\(enc("/p/пицца 2.mp4"))")))
        XCTAssertEqual(thumb, ChatMedia.Request(kind: .thumb, chat: "local_a", name: "пицца 2.mp4", path: "/p/пицца 2.mp4"))
        XCTAssertEqual(ChatMedia.parse(head("/media-thumb?chat=local_a&name=a.MOV"))?.path, nil)
        XCTAssertEqual(ChatMedia.parse(head("/media-file?chat=local_a&name=a.png&path=rel%2Fa.png")),
                       ChatMedia.Request(kind: .file, chat: "local_a", name: "a.png", path: nil), "путь не абсолютный — без него")
        let bad = ["/media-thumb?chat=evil&name=a.mp4", "/media-thumb?chat=local_a", "/media-thumb?chat=local_a&name=a.png",
                   "/media-file?chat=local_a&name=a.mp4", "/media-thumb?chat=local_a&name=..%2Fa.mp4",
                   "/media-thumb?chat=local_a&name=a%00.mp4", "/media-file?chat=local_a&name=a.heic", "/media-thumbs?chat=local_a&name=a.mp4"]
        for target in bad { XCTAssertNil(ChatMedia.parse(head(target)), target) }
        XCTAssertNil(ChatMedia.parse("POST /media-thumb?chat=local_a&name=a.mp4 HTTP/1.1\r\n"))
    }

    func testParseNamedOpen() throws {
        let target = "/open-html?mode=click&dock=1&name=\(enc("a b.mp4"))&chat=local_a&x=0&y=50&w=358&h=692&wx=0&wy=29&ww=1280&wh=742"
        let open = try XCTUnwrap(ChatMedia.parseOpen(head(target)))
        XCTAssertEqual(open.name, "a b.mp4")
        XCTAssertEqual(open.chat, "local_a")
        XCTAssertEqual(open.dock, MaterialsDock.Place(place: CGRect(x: 0, y: 50, width: 358, height: 692),
                                                     window: CGRect(x: 0, y: 29, width: 1280, height: 742)))
        XCTAssertEqual(open.request(path: "/p/a b.mp4"),
                       HtmlChromeOpener.Request(path: "/p/a b.mp4", mode: .click, chat: "local_a", dock: open.dock))
        XCTAssertNil(ChatMedia.parseOpen(head("/open-html?mode=click&name=a.mp4&chat=local_a&path=%2Fp%2Fa.mp4")),
                     "с путём — прежний разбор")
        XCTAssertNotNil(HtmlChromeOpener.parse(head("/open-html?mode=click&name=a.mp4&chat=local_a&path=%2Fp%2Fa.mp4")))
        XCTAssertNil(HtmlChromeOpener.parse(head("/open-html?mode=click&name=a.mp4&chat=local_a")), "без пути прежний разбор молчит")
        for target in ["/open-html?mode=view&name=a.html&chat=local_a", "/open-html?mode=click&name=a.exe&chat=local_a",
                       "/open-html?mode=click&name=a.mp4", "/open-html?mode=click&name=a.mp4&chat=evil"] {
            XCTAssertNil(ChatMedia.parseOpen(head(target)), target)
        }
        XCTAssertNil(ChatMedia.parseOpen(head(target.replacingOccurrences(of: "w=358", with: "w=0")))?.dock, "негодное место — без дока")
    }

    func testPageWhitelist() {
        for path in ["/media-thumb?chat=local_a&name=a.mp4", "/media-file?chat=local_a&name=a.png"] {
            XCTAssertEqual(HtmlChromeOpener.checkPage(head(path, origin: "https://claude.ai"), token: nil), .browser(preflight: false), path)
            XCTAssertEqual(HtmlChromeOpener.checkPage("OPTIONS \(path) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\nOrigin: https://claude.ai\r\n"
                + "Access-Control-Request-Method: GET\r\n\r\n", token: nil), .browser(preflight: true))
            XCTAssertEqual(HtmlChromeOpener.checkPage(head(path) + "\r\n", token: nil), .reject(403), "без Origin — картинка чужой страницы")
            XCTAssertEqual(HtmlChromeOpener.checkPage(head(path, origin: "https://evil.test"), token: nil), .reject(403))
        }
    }

    // MARK: - путь: страницы с проверками `/thumb` или галереи

    func testLocateTakesPagePathOrGalleryPathWithSameChecks() throws {
        let movie = try file("пицца.mp4")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("папка.mp4"), withIntermediateDirectories: true)
        let hidden = tmp.appendingPathComponent(".tajna", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        let secret = hidden.appendingPathComponent("пицца.mp4").path
        try Data("x".utf8).write(to: URL(fileURLWithPath: secret))
        var asked: [String] = []
        var gallery: String?
        let opener = makeOpener { chat, name in asked.append("\(chat)/\(name)"); return gallery }
        // Путь страницы с тем же именем — без галереи.
        XCTAssertEqual(locate(opener, name: "пицца.mp4", path: movie), movie)
        XCTAssertEqual(asked, [])
        // NFD-имя из пропсов и NFC-имя подписи — одно имя.
        let tea = try file("чай.mp4".precomposedStringWithCanonicalMapping)
        XCTAssertEqual(locate(opener, name: "чай.mp4".decomposedStringWithCanonicalMapping, path: tea), tea)
        // Путь страницы не того имени, закрытый, каталог — к галерее; галерея молчит — nil.
        XCTAssertNil(locate(opener, name: "drugoy.mp4", path: movie))
        XCTAssertNil(locate(opener, name: "пицца.mp4", path: secret))
        XCTAssertNil(locate(opener, name: "папка.mp4", path: tmp.appendingPathComponent("папка.mp4").path))
        XCTAssertEqual(asked, ["local_a/drugoy.mp4", "local_a/пицца.mp4", "local_a/папка.mp4"])
        // Галерея: её путь — с теми же проверками.
        gallery = movie
        XCTAssertEqual(locate(opener, name: "пицца.mp4", path: nil), movie)
        XCTAssertNil(locate(opener, name: "другое.mp4", path: nil), "галерея дала файл с другим именем")
        gallery = secret
        XCTAssertNil(locate(opener, name: "пицца.mp4", path: nil), "закрытый путь галереи")
        gallery = movie
        XCTAssertNil(locate(opener, name: "пицца.mp4", path: nil, extensions: Set(ChatMedia.imageTypes.keys)), "не тот вид")
        XCTAssertNil(locate(opener, chat: "local_b", name: "пицца.mp4", path: movie), "чат неизвестен индексу")
    }

    // MARK: - кадр и кэш

    /// Настоящий mp4 64×48, три кадра серого — AVAssetWriter.
    private func movie(_ name: String) throws -> String {
        let url = tmp.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                           AVVideoWidthKey: 64, AVVideoHeightKey: 48])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        for index in 0..<3 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let frame = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(frame, [])
            memset(CVPixelBufferGetBaseAddress(frame), 0x80, CVPixelBufferGetDataSize(frame))
            CVPixelBufferUnlockBaseAddress(frame, [])
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 10)))
        }
        input.markAsFinished()
        let done = expectation(description: "movie")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed, String(describing: writer.error))
        return url.resolvingSymlinksInPath().path
    }

    func testFirstFrameOfRealMovieIsJPEG() throws {
        let path = try movie("ролик.mp4")
        let jpeg = try XCTUnwrap(ChatMedia.firstFrame(of: URL(fileURLWithPath: path)))
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
        let image = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        XCTAssertEqual([image.width, image.height], [64, 48])
        XCTAssertNil(ChatMedia.firstFrame(of: URL(fileURLWithPath: try file("битый.mp4"))))
    }

    private func response(_ data: Data) -> (head: String, body: Data) {
        let end = data.range(of: Data("\r\n\r\n".utf8))!
        return (String(decoding: data[..<end.lowerBound], as: UTF8.self), data[end.upperBound...])
    }

    func testThumbCacheByPathMtimeAndSize() throws {
        let opener = makeOpener()
        var made = 0
        opener.media.frame = { _ in made += 1; return Data([0xFF, 0xD8, 0xFF, UInt8(made)]) }
        let path = try file("a.mp4")
        let access = HtmlChromeOpener.PageAccess.browser(preflight: false)
        let first = response(opener.media.queue.sync { opener.mediaResponse(.thumb, path: path, access: access) })
        XCTAssertTrue(first.head.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\n"), first.head)
        XCTAssertTrue(first.head.contains("Access-Control-Allow-Origin: https://claude.ai"))
        XCTAssertEqual(Array(first.body), [0xFF, 0xD8, 0xFF, 1])
        _ = opener.media.queue.sync { opener.mediaResponse(.thumb, path: path, access: access) }
        XCTAssertEqual(made, 1, "тот же файл — из кэша")
        try Data("xy".utf8).write(to: URL(fileURLWithPath: path))
        let again = response(opener.media.queue.sync { opener.mediaResponse(.thumb, path: path, access: access) })
        XCTAssertEqual(made, 2, "файл сменился — кадр заново")
        XCTAssertEqual(Array(again.body), [0xFF, 0xD8, 0xFF, 2])
        // webm: кадра AVFoundation не даёт — файл есть, плашка (204); файла нет — 404.
        let webm = try file("b.webm")
        XCTAssertTrue(response(opener.media.queue.sync { opener.mediaResponse(.thumb, path: webm, access: access) }).head
            .hasPrefix("HTTP/1.1 204 "))
        opener.media.frame = { _ in nil }
        XCTAssertTrue(response(opener.media.queue.sync { opener.mediaResponse(.thumb, path: try! file("c.mp4"), access: access) }).head
            .hasPrefix("HTTP/1.1 204 "), "кадр не вышел — плашка")
        XCTAssertTrue(response(opener.media.queue.sync { opener.mediaResponse(.thumb, path: tmp.path + "/нет.mp4", access: access) }).head
            .hasPrefix("HTTP/1.1 404 "))
        // Картинка — байты и тип по расширению.
        let png = try file("a.png", Data([0x89, 0x50, 0x4E, 0x47]))
        let picture = response(opener.media.queue.sync { opener.mediaResponse(.file, path: png, access: access) })
        XCTAssertTrue(picture.head.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n"), picture.head)
        XCTAssertEqual(Array(picture.body), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertTrue(response(opener.media.queue.sync { opener.mediaResponse(.file, path: try! file("a.heic"), access: access) }).head
            .hasPrefix("HTTP/1.1 404 "))
    }

    // MARK: - ViewerClient.resolve против своего слушателя

    private func client(_ fake: ViewerChannelWF104Tests.FakeViewer) throws -> ViewerClient {
        let token = tmp.appendingPathComponent("channel.token")
        try Data((String(repeating: "b2", count: 16) + "\n").utf8).write(to: token)
        let client = ViewerClient(port: fake.port, tokenURL: token, launches: false)
        client.owners = { _, _ in [.init(pid: getpid(), path: "/Applications/PimpViewer.app/Contents/MacOS/PimpViewer")] }
        client.installed = { true }
        client.running = { true }
        client.launch = { XCTFail("ради пути галерею не запускаем") }
        client.raise = { XCTFail("вывод вперёд не ждали"); return true }
        return client
    }

    private func resolve(_ client: ViewerClient, name: String) -> String? {
        let done = expectation(description: "resolve")
        var result: String?
        client.resolve(chat: "local_a", name: name) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    func testViewerClientResolve() throws {
        typealias Fake = ViewerChannelWF104Tests.FakeViewer
        let fake = try Fake()
        fake.answer = { _, _ in Fake.json(#"{"ok":true,"path":"/Users/dev/Rick/work/пицца 2.mp4","kind":"video"}"#) }
        let client = try client(fake)
        XCTAssertEqual(resolve(client, name: "пицца 2.mp4"), "/Users/dev/Rick/work/пицца 2.mp4")
        XCTAssertTrue(fake.requests[0].hasPrefix("GET /resolve?chat=local_a&name=%D0%BF%D0%B8%D1%86%D1%86%D0%B0%202.mp4 HTTP/1.1\r\n"),
                      fake.requests[0])
        XCTAssertTrue(fake.requests[0].lowercased().contains("x-pimp-viewer-token: \(String(repeating: "b2", count: 16))"))
        // Не нашла, старая (404), путь не абсолютный, молчит — nil.
        for answer in [Fake.json(#"{"ok":false}"#), Fake.json(#"{"ok":false,"error":"not-found"}"#, status: "404 Not Found"),
                       Fake.json(#"{"ok":true,"path":"work/a.mp4"}"#), Fake.json(#"{"ok":true}"#)] {
            fake.answer = { _, _ in answer }
            XCTAssertNil(resolve(client, name: "a.mp4"), answer)
        }
        fake.answer = { _, _ in nil }
        XCTAssertNil(resolve(client, name: "a.mp4"))
    }

    // MARK: - ответ странице по настоящему сокету

    private final class Server {
        let listener: NWListener
        init(_ opener: HtmlChromeOpener) throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { opener.serve($0) }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: DispatchQueue(label: "test.media-server"))
            _ = ready.wait(timeout: .now() + 3)
        }
        deinit { listener.cancel() }

        func exchange(_ target: String, origin: String? = "https://claude.ai") throws -> (head: String, body: Data) {
            let port = try XCTUnwrap(listener.port)
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            let ended = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var data = Data()
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { bytes, _, done, error in
                    lock.lock()
                    if let bytes = bytes { data.append(bytes) }
                    lock.unlock()
                    if done || error != nil { ended.signal() } else { receive() }
                }
            }
            let head = "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n" } ?? "") + "\r\n"
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
                receive()
            }
            connection.start(queue: DispatchQueue(label: "test.media-client"))
            defer { connection.cancel() }
            XCTAssertEqual(ended.wait(timeout: .now() + 8), .success, target)
            lock.lock()
            defer { lock.unlock() }
            let end = data.range(of: Data("\r\n\r\n".utf8)) ?? data.endIndex..<data.endIndex
            return (String(decoding: data[..<end.lowerBound], as: UTF8.self), Data(data[end.upperBound...]))
        }
    }

    func testPageGetsFramePictureAndNamedOpenOverSocket() throws {
        let video = try movie("пицца.mp4")
        let png = try file("фото.png", Data([0x89, 0x50, 0x4E, 0x47, 1, 2]))
        var gallery: [String: String] = ["пицца.mp4": video]
        let opener = makeOpener { _, name in gallery[name] }
        var docked: [HtmlChromeOpener.Request] = []
        opener.toDock = { request, done in docked.append(request); done(true, true) }
        var routed: [HtmlChromeOpener.Request] = []
        opener.toViewer = { request, done in routed.append(request); done(true) }
        let server = try Server(opener)

        // Кадр: по пути страницы и по имени (путь галереи).
        for target in ["/media-thumb?chat=local_a&name=\(enc("пицца.mp4"))&path=\(enc(video))", "/media-thumb?chat=local_a&name=\(enc("пицца.mp4"))"] {
            let frame = try server.exchange(target)
            XCTAssertTrue(frame.head.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\n"), frame.head)
            XCTAssertTrue(frame.head.contains("Access-Control-Allow-Origin: https://claude.ai"))
            XCTAssertEqual(Array(frame.body.prefix(2)), [0xFF, 0xD8])
        }
        let picture = try server.exchange("/media-file?chat=local_a&name=\(enc("фото.png"))&path=\(enc(png))")
        XCTAssertTrue(picture.head.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n"), picture.head)
        XCTAssertEqual(Array(picture.body), [0x89, 0x50, 0x4E, 0x47, 1, 2])
        // Не нашлось — 404 с CORS (страница видит отказ); чужой Origin — 403; без Origin — 403.
        let lost = try server.exchange("/media-thumb?chat=local_a&name=net.mp4")
        XCTAssertTrue(lost.head.hasPrefix("HTTP/1.1 404 "), lost.head)
        XCTAssertTrue(lost.head.contains("Access-Control-Allow-Origin: https://claude.ai"))
        XCTAssertTrue(try server.exchange("/media-file?chat=local_a&name=a.png", origin: "https://evil.test").head.hasPrefix("HTTP/1.1 403 "))
        XCTAssertTrue(try server.exchange("/media-file?chat=local_a&name=\(enc("фото.png"))&path=\(enc(png))", origin: nil).head
            .hasPrefix("HTTP/1.1 403 "))

        // Нажатие по имени: с местом — в док, ответ по доку.
        let place = "&x=0&y=50&w=358&h=692&wx=0&wy=29&ww=1280&wh=742"
        let open = try server.exchange("/open-html?mode=click&dock=1&name=\(enc("пицца.mp4"))&chat=local_a" + place)
        XCTAssertTrue(open.head.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n"), open.head)
        XCTAssertEqual(String(decoding: open.body, as: UTF8.self), #"{"found":true,"taken":true,"opened":true}"#)
        XCTAssertEqual(docked.map { $0.path }, [video])
        XCTAssertNotNil(docked.first?.dock)
        // Без места — прежний клик в галерею, ответ сразу после поиска.
        let plain = try server.exchange("/open-html?mode=click&name=\(enc("пицца.mp4"))&chat=local_a")
        XCTAssertEqual(String(decoding: plain.body, as: UTF8.self), #"{"found":true,"taken":false,"opened":false}"#)
        let deadline = Date().addingTimeInterval(2)
        while routed.isEmpty, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(routed.map { $0.path }, [video])
        // Не нашлось — found:false, никуда не отдаём.
        gallery = [:]
        let gone = try server.exchange("/open-html?mode=click&dock=1&name=\(enc("пицца.mp4"))&chat=local_a" + place)
        XCTAssertEqual(String(decoding: gone.body, as: UTF8.self), #"{"found":false,"taken":false,"opened":false}"#)
        XCTAssertEqual(docked.count, 1)
    }
}
