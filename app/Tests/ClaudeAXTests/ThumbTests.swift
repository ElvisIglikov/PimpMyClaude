import ImageIO
import XCTest
@testable import ClaudeAX

/// К-TH `GET /thumb` (слово Элвиса 11.10.2026 06:36): миниатюра JPEG для плитки `.HEIC` во вложениях чата —
/// только фото HEIC/HEIF, только известному чату, по тем же отказам пути, что у `/copy-file`.
final class ThumbTests: XCTestCase {
    private let chat = "local_thumb-1011"
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func head(_ target: String, origin: String = "https://claude.ai") -> String {
        "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\nOrigin: \(origin)\r\n\r\n"
    }
    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }

    /// Фото 400×200 в файле нужного типа; этот Мак HEIC не пишет — nil.
    private func photo(_ name: String, type: String) -> URL? {
        let url = dir.appendingPathComponent(name)
        guard let context = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        guard let image = context.makeImage(),
              let target = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(target, image, nil)
        return CGImageDestinationFinalize(target) ? url : nil
    }

    func testParseThumbTakesOnlyHeicOfAChat() {
        let path = "/Users/dev/Downloads/IMG_0506.HEIC"
        XCTAssertEqual(HtmlChromeOpener.parseThumb(head("/thumb?path=\(enc(path))&chat=\(chat)")),
                       HtmlChromeOpener.CopyFileRequest(path: path, chat: chat))
        XCTAssertNotNil(HtmlChromeOpener.parseThumb(head("/thumb?path=%2Fa%2Fb.heif&chat=\(chat)")))
        XCTAssertNil(HtmlChromeOpener.parseThumb(head("/thumb?path=\(enc(path))")), "без чата")
        XCTAssertNil(HtmlChromeOpener.parseThumb(head("/thumb?path=\(enc(path))&chat=evil")), "мусорный чат")
        XCTAssertNil(HtmlChromeOpener.parseThumb(head("/thumb?path=IMG.HEIC&chat=\(chat)")), "путь не абсолютный")
        XCTAssertNil(HtmlChromeOpener.parseThumb(head("/thumb?path=%2Fa%00b.heic&chat=\(chat)")), "\\0 в пути")
        XCTAssertNil(HtmlChromeOpener.parseThumb(head("/thumb?path=%2Fa%2Fkey.pem&chat=\(chat)")), "не фото HEIC")
        // #10254, #10229: любое фото плиткой файла, HTML и PDF — тоже.
        for name in ["b.png", "b.JPG", "b.webp", "a.html", "a.pdf"] {
            XCTAssertNotNil(HtmlChromeOpener.parseThumb(head("/thumb?path=%2Fa%2F\(name)&chat=\(chat)")), name)
        }
        XCTAssertNil(HtmlChromeOpener.parseThumb(head("/copy-file?path=\(enc(path))&chat=\(chat)")))
        // Ручку видит только страница Claude; чужой странице — отказ.
        XCTAssertTrue(HtmlChromeOpener.checkPage(head("/thumb?path=\(enc(path))&chat=\(chat)"), token: nil).performsAction)
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/thumb?path=\(enc(path))&chat=\(chat)", origin: "https://evil.example"),
                                                  token: nil), .reject(403))
    }

    func testThumbOfHtmlIsQuickLookSnapshot() throws {
        let page = dir.appendingPathComponent("81-plan.html")
        try Data("<!doctype html><html><body style=\"background:#123\"><h1 style=\"color:#fff\">ФАЙЛ 81</h1></body></html>".utf8).write(to: page)
        let opener = HtmlChromeOpener()
        opener.home = dir.path
        opener.isKnownChat = { $0 == self.chat }
        guard let jpeg = opener.thumb(.init(path: page.path, chat: chat)) else { throw XCTSkip("QuickLook здесь не отвечает") }
        XCTAssertEqual([UInt8](jpeg.prefix(3)), [0xFF, 0xD8, 0xFF], "JPEG")
        XCTAssertNil(opener.thumb(.init(path: page.path, chat: "local_other")), "чужой чат")
    }

    func testThumbIsSmallJpegOnlyForKnownChatAndOpenPath() throws {
        guard let file = photo("IMG_0506.HEIC", type: "public.heic") else { throw XCTSkip("этот Мак не пишет HEIC") }
        let opener = HtmlChromeOpener()
        opener.home = dir.path
        opener.isKnownChat = { $0 == self.chat }
        let jpeg = try XCTUnwrap(opener.thumb(.init(path: file.path, chat: chat)))
        XCTAssertEqual([UInt8](jpeg.prefix(3)), [0xFF, 0xD8, 0xFF], "JPEG")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 400, "меньше потолка — не растягиваем")
        XCTAssertEqual(image.height, 200)
        XCTAssertEqual(HtmlChromeOpener.jpegThumb(of: file, side: 100).flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width, 100, "длинная сторона — по потолку")

        XCTAssertNil(opener.thumb(.init(path: file.path, chat: "local_other")), "чужой чат")
        XCTAssertNil(opener.thumb(.init(path: dir.appendingPathComponent("net.heic").path, chat: chat)), "файла нет")
        // Не фото под именем .heic — миниатюры нет, содержимое наружу не уходит.
        let fake = dir.appendingPathComponent("secret.heic")
        try Data("это не фото, а текст под чужим расширением".utf8).write(to: fake)
        XCTAssertNil(opener.thumb(.init(path: fake.path, chat: chat)))
        // Скрытая папка закрыта, как у `/copy-file`.
        let hidden = dir.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: hidden.appendingPathComponent("a.heic"))
        XCTAssertNil(opener.thumb(.init(path: hidden.appendingPathComponent("a.heic").path, chat: chat)))
    }

    func testThumbResponseCarriesBodyOnlyToClaudePage() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let ok = String(decoding: HtmlChromeOpener.thumbResponse(jpeg, access: .browser(preflight: false)), as: UTF8.self)
        XCTAssertTrue(ok.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\n"))
        XCTAssertTrue(ok.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"))
        XCTAssertTrue(ok.contains("Content-Length: 4\r\n"))
        let none = String(decoding: HtmlChromeOpener.thumbResponse(nil, access: .browser(preflight: false)), as: UTF8.self)
        XCTAssertTrue(none.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(none.contains("Content-Length: 0\r\n"))
        let native = String(decoding: HtmlChromeOpener.thumbResponse(jpeg, access: .native), as: UTF8.self)
        XCTAssertFalse(native.contains("Access-Control-"))
    }
}
