import XCTest
@testable import ClaudeAX

/// #10760 (слово Элвиса 23.10.2026: «Сделай, чтобы на скриншоте тоже было видно. Это важно»): кадр панели материалов
/// от PimpViewer — странице Claude под панель (К-DOCK-4 `GET /dock-shot`). Разбор, белый список, ответы по версии файла.
/// Живой склад галереи не трогаем — файл во временной папке.
final class DockShotWF279Tests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dock-shot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func head(_ target: String, origin: String? = "https://claude.ai") -> String {
        "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\n" + (origin.map { "Origin: \($0)\r\n" } ?? "") + "\r\n"
    }

    private func text(_ data: Data) -> String { String(decoding: data.prefix(400), as: UTF8.self) }

    func testParseAndWhitelist() {
        XCTAssertEqual(HtmlChromeOpener.parseDockShot(head("/dock-shot")), .some(""))
        XCTAssertEqual(HtmlChromeOpener.parseDockShot(head("/dock-shot?since=1729688000123.20480")), .some("1729688000123.20480"))
        XCTAssertEqual(HtmlChromeOpener.parseDockShot(head("/dock-shot?since=../x")), .some(nil), "битая версия — 400")
        XCTAssertNil(HtmlChromeOpener.parseDockShot(head("/dock?probe=1")))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/dock-shot?since="), token: nil), .browser(preflight: false))
        XCTAssertEqual(HtmlChromeOpener.checkPage(head("/dock-shot", origin: "https://evil.example"), token: nil), .reject(403))
    }

    func testResponsesByVersion() throws {
        let file = tmp.appendingPathComponent("dock-shot.jpg")
        let access = HtmlChromeOpener.PageAccess.browser(preflight: false)
        XCTAssertTrue(text(HtmlChromeOpener.dockShotResponse(since: "", file: file, access: access)).hasPrefix("HTTP/1.1 404"),
                      "кадра нет — 404")
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        try jpeg.write(to: file)
        let first = HtmlChromeOpener.dockShotResponse(since: "", file: file, access: access)
        let head = text(first)
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 200 OK\r\nX-Pimp-Shot: "), head)
        XCTAssertTrue(head.contains("Access-Control-Expose-Headers: X-Pimp-Shot\r\n"))
        XCTAssertTrue(head.contains("Access-Control-Allow-Origin: https://claude.ai\r\n"))
        XCTAssertTrue(head.contains("Content-Type: image/jpeg\r\n"))
        XCTAssertEqual(first.suffix(jpeg.count), jpeg)
        let version = try XCTUnwrap(HtmlChromeOpener.dockShotVersion(file)?.version)
        XCTAssertTrue(head.contains("X-Pimp-Shot: \(version)\r\n"))
        XCTAssertTrue(text(HtmlChromeOpener.dockShotResponse(since: version, file: file, access: access)).hasPrefix("HTTP/1.1 204"),
                      "та же версия — 204")
        try Data("not a jpeg".utf8).write(to: file)
        XCTAssertTrue(text(HtmlChromeOpener.dockShotResponse(since: "", file: file, access: access)).hasPrefix("HTTP/1.1 404"),
                      "не JPEG — не отдаём")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("dir.jpg"), withIntermediateDirectories: true)
        XCTAssertNil(HtmlChromeOpener.dockShotVersion(tmp.appendingPathComponent("dir.jpg")), "папка — не кадр")
    }
}
