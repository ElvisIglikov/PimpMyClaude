import AppKit
import XCTest
@testable import ClaudeAX

/// «📋 Копировать в буфер» (WF69, задача #6236): страница кладёт путь текстом и метку в HTML-слое,
/// приложение подменяет содержимое буфера самим файлом. Буфер — именованный, не общий: тесты не
/// затирают то, что лежит в буфере у человека, и не спрашивают разрешений macOS 26.
final class CopyFileRelayTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var file: URL!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("pimpmyclaude-copy-test-\(UUID().uuidString)"))
        file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("копия \(UUID().uuidString).html")
        try? Data("<p>ok</p>".utf8).write(to: file)
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: file)
        super.tearDown()
    }

    /// То, что кладёт страница: как Chromium — с <meta charset> впереди HTML-слоя.
    private func putMark(for path: String, text: String? = nil) {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
        let html = "<meta charset='utf-8'><!--pimpmyclaude:copy-file:\(encoded)--><a href=\"file://\(path)\">x</a>"
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(text ?? path, forType: .string)
    }

    // MARK: - метка

    func testPathInHTMLDecodesPercentEncodingAndRefusesJunk() {
        let path = "/Users/elvis/Не удалять/после установки.command"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertEqual(CopyFileRelay.path(inHTML: "<meta charset='utf-8'><!--pimpmyclaude:copy-file:\(encoded)--><a>x</a>"), path)
        XCTAssertNil(CopyFileRelay.path(inHTML: "<meta charset='utf-8'><b>обычная копия</b>"), "метки нет — путь из ниоткуда")
        XCTAssertNil(CopyFileRelay.path(inHTML: "<!--pimpmyclaude:copy-file:--><a>x</a>"), "пустая метка")
        XCTAssertNil(CopyFileRelay.path(inHTML: "<!--pimpmyclaude:copy-file:relative%2Fx.html-->"), "относительный путь")
        XCTAssertNil(CopyFileRelay.path(inHTML: "<!--pimpmyclaude:copy-file:%2FUsers%2Fx"), "метка без конца")
    }

    // MARK: - тик

    func testTickReplacesMarkWithFileURLFilenamesAndPath() {
        let relay = CopyFileRelay(pasteboard: pasteboard)
        var copied: [String] = []
        relay.onCopied = { copied.append($0) }
        putMark(for: file.path)

        XCTAssertEqual(relay.tick(), file.path, "метка не опознана")
        XCTAssertEqual(pasteboard.string(forType: .fileURL), file.absoluteString, "public.file-url не тот")
        XCTAssertEqual(pasteboard.propertyList(forType: CopyFileRelay.filenamesType) as? [String], [file.path],
                       "NSFilenamesPboardType не тот")
        XCTAssertEqual(pasteboard.string(forType: .string), file.path, "путь текстом пропал — вставка в терминал дала бы пустоту")
        XCTAssertNil(pasteboard.string(forType: .html), "HTML-слой с меткой остался")
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.map(\.path), [file.path], "как файл (NSURL) буфер не читается — так его читают Telegram и Finder")
        XCTAssertEqual(copied, [file.lastPathComponent])
        XCTAssertEqual(relay.copies, 1)
        XCTAssertEqual(relay.status, "1/0")

        // Своя запись подняла changeCount — следующий тик её не трогает и не считает.
        XCTAssertNil(relay.tick())
        XCTAssertEqual(relay.copies, 1, "своя запись посчитана второй копией")
        XCTAssertEqual(pasteboard.string(forType: .fileURL), file.absoluteString, "буфер перезаписан второй раз")
    }

    func testOrdinaryCopyIsLeftAlone() {
        let relay = CopyFileRelay(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("<b>жирное</b>", forType: .html)
        pasteboard.setString("жирное", forType: .string)
        XCTAssertNil(relay.tick())
        XCTAssertEqual(pasteboard.string(forType: .html), "<b>жирное</b>", "чужая копия тронута")
        XCTAssertEqual(pasteboard.string(forType: .string), "жирное")
        XCTAssertEqual(relay.copies, 0)

        pasteboard.clearContents()
        pasteboard.setString(file.path, forType: .string)
        XCTAssertNil(relay.tick(), "голый путь текстом — не метка")
        XCTAssertNil(pasteboard.string(forType: .fileURL), "путь текстом превратили в файл без метки")
    }

    func testUnchangedPasteboardIsNotRead() {
        var reads = 0
        let relay = CopyFileRelay(pasteboard: pasteboard, exists: { _ in reads += 1; return true })
        putMark(for: file.path)
        XCTAssertEqual(relay.tick(), file.path)
        XCTAssertEqual(reads, 1)
        XCTAssertNil(relay.tick())
        XCTAssertNil(relay.tick())
        XCTAssertEqual(reads, 1, "буфер без изменений перечитан")
    }

    func testMissingFileKeepsPasteboardAndTellsPath() {
        let relay = CopyFileRelay(pasteboard: pasteboard, exists: { _ in false })
        var missing: [String] = []
        relay.onMissing = { missing.append($0) }
        var copied = 0
        relay.onCopied = { _ in copied += 1 }
        putMark(for: "/nowhere/x.html")

        XCTAssertNil(relay.tick())
        XCTAssertEqual(missing, ["/nowhere/x.html"])
        XCTAssertEqual(copied, 0)
        XCTAssertEqual(relay.misses, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "/nowhere/x.html", "путь текстом должен остаться — хоть что-то вставится")
        XCTAssertNil(pasteboard.string(forType: .fileURL), "несуществующий файл положен в буфер")
        XCTAssertEqual(relay.status, "0/1")
    }
}
