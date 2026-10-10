import AppKit
import XCTest
@testable import ClaudeAX

/// WF106: «📋 Копировать в буфер» через порт (`/copy-file`, #8102) и число токенов остывшего чата
/// (`/context` → `chat-context`, #8103). Буфер — именованный, не общий; расшифровки — во временной папке.
final class CopyContextWF106Tests: XCTestCase {
    private var dir: URL!
    private var file: URL!
    private let chat = "local_abc-123"

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf106-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("отчёт 1.html")
        try? Data("<p>ok</p>".utf8).write(to: file)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func head(_ target: String) -> String { "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:47615\r\nOrigin: https://claude.ai\r\n\r\n" }
    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }

    private func opener(known: Set<String>) -> (HtmlChromeOpener, () -> [String]) {
        let opener = HtmlChromeOpener()
        opener.isKnownChat = { known.contains($0) }
        opener.home = dir.path
        var copied: [String] = []
        opener.onCopyFile = { copied.append($0) }
        opener.browserSeam = { _ in XCTFail("браузер не должен открываться") }
        return (opener, { copied })
    }

    // MARK: - разбор

    func testParseCopyFileAndContext() {
        let path = "/Users/dev/Не удалять/файл.png"
        XCTAssertEqual(HtmlChromeOpener.parseCopyFile(head("/copy-file?path=\(enc(path))&chat=\(chat)")),
                       HtmlChromeOpener.CopyFileRequest(path: path, chat: chat))
        XCTAssertNil(HtmlChromeOpener.parseCopyFile(head("/copy-file?path=\(enc(path))")), "без чата")
        XCTAssertNil(HtmlChromeOpener.parseCopyFile(head("/copy-file?path=\(enc(path))&chat=evil")), "мусорный чат")
        XCTAssertNil(HtmlChromeOpener.parseCopyFile(head("/copy-file?path=relative.txt&chat=\(chat)")), "путь не абсолютный")
        XCTAssertNil(HtmlChromeOpener.parseCopyFile(head("/copy-file?path=%2Fa%00b&chat=\(chat)")), "\\0 в пути")
        XCTAssertNil(HtmlChromeOpener.parseCopyFile("POST /copy-file?path=\(enc(path))&chat=\(chat) HTTP/1.1\r\n"))
        XCTAssertNil(HtmlChromeOpener.parseCopyFile(head("/open-html?path=\(enc(path))&chat=\(chat)")))

        XCTAssertEqual(HtmlChromeOpener.parseContext(head("/context?chat=\(chat)")), chat)
        XCTAssertNil(HtmlChromeOpener.parseContext(head("/context")))
        XCTAssertNil(HtmlChromeOpener.parseContext(head("/context?chat=../../x")))
        XCTAssertNil(HtmlChromeOpener.parseContext(head("/contexts?chat=\(chat)")))
        // Новые ручки не путаются со старыми.
        XCTAssertNil(HtmlChromeOpener.parse(head("/copy-file?path=\(enc(path))&chat=\(chat)")))
        XCTAssertNil(HtmlChromeOpener.parseViewer(head("/context?chat=\(chat)")))
    }

    // MARK: - /copy-file

    func testCopyFileAcceptsKnownChatAndRegularFile() {
        let (opener, copied) = opener(known: [chat])
        opener.handleOld(head("/copy-file?path=\(enc(file.path))&chat=\(chat)"))
        opener.drainCopies()
        XCTAssertEqual(copied(), [file.resolvingSymlinksInPath().path])
        XCTAssertEqual(opener.copyStatus, "1/0")
    }

    func testCopyFileRefusesUnknownChatHiddenFolderDirectoryAndMissing() throws {
        let (opener, copied) = opener(known: [chat])
        // Чужой чат (индекс его не знает).
        opener.handleOld(head("/copy-file?path=\(enc(file.path))&chat=local_other"))
        opener.drainCopies()
        // Скрытая папка.
        let hidden = dir.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        let key = hidden.appendingPathComponent("id_rsa")
        try Data("secret".utf8).write(to: key)
        opener.handleOld(head("/copy-file?path=\(enc(key.path))&chat=\(chat)"))
        opener.drainCopies()
        // Симлинк на скрытый файл снаружи.
        let link = dir.appendingPathComponent("key.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: key)
        opener.handleOld(head("/copy-file?path=\(enc(link.path))&chat=\(chat)"))
        opener.drainCopies()
        // Связка ключей в домашней папке.
        let keychains = dir.appendingPathComponent("Library/Keychains")
        try FileManager.default.createDirectory(at: keychains, withIntermediateDirectories: true)
        let db = keychains.appendingPathComponent("login.keychain-db")
        try Data("k".utf8).write(to: db)
        opener.handleOld(head("/copy-file?path=\(enc(db.path))&chat=\(chat)"))
        opener.drainCopies()
        // Папка и несуществующий файл.
        opener.handleOld(head("/copy-file?path=\(enc(dir.path))&chat=\(chat)"))
        opener.drainCopies()
        opener.handleOld(head("/copy-file?path=\(enc(dir.appendingPathComponent("нет.png").path))&chat=\(chat)"))
        opener.drainCopies()
        // Нет чата вовсе.
        opener.handleOld(head("/copy-file?path=\(enc(file.path))"))
        opener.drainCopies()
        XCTAssertEqual(copied(), [])
        XCTAssertEqual(opener.copyStatus, "0/6", "без чата запрос не разобран — не отказ, а мимо")
    }

    /// Папка, закрытая для Пимпа (как рабочий стол под TCC): stat() — EACCES, файл всё равно идёт в буфер
    /// (живой случай гейта WF106: файл с рабочего стола молча не копировался).
    func testCopyFileFromClosedFolderStillAccepted() throws {
        let (opener, copied) = opener(known: [chat])
        let closed = dir.appendingPathComponent("Закрытая")
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        let inside = closed.appendingPathComponent("Анна.html")
        try Data("<p>".utf8).write(to: inside)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: closed.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: closed.path) }
        opener.handleOld(head("/copy-file?path=\(enc(inside.path))&chat=\(chat)"))
        opener.drainCopies()
        XCTAssertEqual(copied().count, 1, "файл из закрытой папки не принят")
    }

    /// Рабочий стол под TCC: Пимпу stat() может сказать «нет файла» — такой путь с расширением принимаем,
    /// без расширения и вне рабочего стола/загрузок/документов — нет.
    func testClosedFoldersAcceptPathWithExtension() {
        let home = "/Users/тест"
        XCTAssertTrue(HtmlChromeOpener.underClosedFolder("/Users/тест/Desktop/Разослать/Анна.html", home: home))
        XCTAssertTrue(HtmlChromeOpener.underClosedFolder("/Users/тест/Downloads/фото.png", home: home))
        XCTAssertFalse(HtmlChromeOpener.underClosedFolder("/Users/тест/Desktop/папка", home: home))
        XCTAssertFalse(HtmlChromeOpener.underClosedFolder("/Users/тест/Projects/а.html", home: home))
        XCTAssertFalse(HtmlChromeOpener.underClosedFolder("/Users/тестер/Desktop/а.html", home: home))
    }

    func testCopyFileWithoutIndexRefuses() {
        let opener = HtmlChromeOpener()
        var copied = 0
        opener.onCopyFile = { _ in copied += 1 }
        opener.handleOld(head("/copy-file?path=\(enc(file.path))&chat=\(chat)"))
        opener.drainCopies()
        XCTAssertEqual(copied, 0)
    }

    /// То, что приложение делает с принятым путём: файл тремя слоями, как «Скопировать» в Finder.
    func testAcceptedPathGoesToPasteboardAsFile() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("pimpmyclaude-wf106-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let (opener, _) = opener(known: [chat])
        opener.onCopyFile = { XCTAssertTrue(CopyFileRelay.write(path: $0, to: pasteboard)) }
        opener.handleOld(head("/copy-file?path=\(enc(file.path))&chat=\(chat)"))
        opener.drainCopies()
        let real = file.resolvingSymlinksInPath()
        XCTAssertEqual(pasteboard.string(forType: .fileURL), real.absoluteString)
        XCTAssertEqual(pasteboard.propertyList(forType: CopyFileRelay.filenamesType) as? [String], [real.path])
        XCTAssertEqual(pasteboard.string(forType: .string), real.path)
    }

    // MARK: - /context

    func testContextRequestReachesHandler() {
        let opener = HtmlChromeOpener()
        var asked: [String] = []
        opener.onContext = { asked.append($0) }
        opener.onCopyFile = { _ in XCTFail() }
        opener.handleOld(head("/context?chat=\(chat)"))
        opener.handleOld(head("/context?chat=junk"))
        XCTAssertEqual(asked, [chat])
    }

    private func line(_ record: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
    }

    private func assistant(_ usage: [String: Int], model: String = "claude-opus-5-5", sidechain: Bool = false) -> String {
        line(["type": "assistant", "isSidechain": sidechain, "message": ["model": model, "usage": usage]])
    }

    func testTokensTakeLastMainAssistantWithUsage() {
        let lines = [
            assistant(["input_tokens": 1, "cache_creation_input_tokens": 2, "cache_read_input_tokens": 3]),
            assistant(["input_tokens": 2, "cache_creation_input_tokens": 422, "cache_read_input_tokens": 214376,
                       "output_tokens": 1660]),
            line(["type": "user", "message": ["content": "привет"]]),
            assistant(["input_tokens": 9, "cache_read_input_tokens": 999], sidechain: true),
            assistant(["input_tokens": 5, "cache_read_input_tokens": 5], model: "<synthetic>"),
            assistant(["input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 3]),
            "{рваная",
            "",
        ]
        XCTAssertEqual(ChatContext.tokens(inTail: Data(lines.joined(separator: "\n").utf8), truncated: false), 214800)
        XCTAssertNil(ChatContext.tokens(inTail: Data(line(["type": "user"]).utf8), truncated: false))
        // Хвост с середины файла: первая строка рваная — её вон, даже если она целая с виду.
        let tail = [assistant(["input_tokens": 7]), line(["type": "user"])].joined(separator: "\n")
        XCTAssertNil(ChatContext.tokens(inTail: Data(tail.utf8), truncated: true))
        XCTAssertEqual(ChatContext.tokens(inTail: Data(tail.utf8), truncated: false), 7)
    }

    func testTokensFromNewestTranscriptAndTail() throws {
        let root = dir.appendingPathComponent("projects")
        let id = "0f1e2d3c-aaaa-bbbb-cccc-1234567890ab"
        let old = root.appendingPathComponent("-Users-a")
        let new = root.appendingPathComponent("-Users-b")
        for folder in [old, new] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try Data(assistant(["input_tokens": 100]).utf8).write(to: old.appendingPathComponent(id + ".jsonl"))
        // Свежий файл длиннее хвоста: в начале — мусор, в конце — ответ.
        let filler = String(repeating: line(["type": "user", "message": ["content": String(repeating: "я", count: 900)]]) + "\n",
                            count: 400)
        let body = assistant(["input_tokens": 1]) + "\n" + filler
            + assistant(["input_tokens": 3, "cache_creation_input_tokens": 40, "cache_read_input_tokens": 400000]) + "\n"
        XCTAssertGreaterThan(body.utf8.count, ChatContext.tailBytes)
        let fresh = new.appendingPathComponent(id + ".jsonl")
        try Data(body.utf8).write(to: fresh)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                              ofItemAtPath: old.appendingPathComponent(id + ".jsonl").path)
        XCTAssertEqual(ChatContext.transcript(cliSessionId: id, root: root)?.resolvingSymlinksInPath(), fresh.resolvingSymlinksInPath())
        XCTAssertEqual(ChatContext.tokens(cliSessionId: id, root: root), 400043)
        // Мусорный id и нет файла — nil.
        XCTAssertNil(ChatContext.tokens(cliSessionId: "../x", root: root))
        XCTAssertNil(ChatContext.tokens(cliSessionId: "*", root: root))
        XCTAssertNil(ChatContext.tokens(cliSessionId: "missing", root: root))
        XCTAssertNil(ChatContext.tokens(cliSessionId: id, root: dir.appendingPathComponent("нет")))
    }

    func testChatContextCommandGoesToQueue() throws {
        let path = dir.appendingPathComponent("command.json")
        let channel = CommandChannel(path: path, schedule: { _, _ in })
        XCTAssertTrue(ChatContext.send(chat: chat, tokens: 400043, via: channel))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "chat-context")
        XCTAssertEqual(json["chat"] as? String, chat)
        XCTAssertEqual(json["tokens"] as? Int, 400043)
        XCTAssertNotNil(json["id"] as? String)
        XCTAssertNotNil(json["at"] as? String)
    }
}
