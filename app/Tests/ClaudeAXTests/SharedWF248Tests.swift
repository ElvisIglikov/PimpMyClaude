import XCTest
@testable import ClaudeAX

/// Общие куски ревизии WF247 (С5а): эталон заголовков status.md, ответы ручек страницы, цвет, числительные, id чата,
/// живой claude.json.
final class SharedWF248Tests: XCTestCase {
    private struct StatusTable: Decodable {
        let states: [String: [String: String]]
        let headings: [[String]]
        let notHeadings: [String]
        let tails: [[String]]
        let documents: [Document]

        struct Document: Decodable {
            let name: String
            let text: String
            let workflows: [String]
            let now: String
            let wait: String
        }
    }

    private static func swiftName(_ state: PanelWorkflow.State) -> String {
        switch state {
        case .running: return "running"
        case .waiting: return "waiting"
        case .failed: return "failed"
        case .done: return "done"
        case .planned: return "planned"
        }
    }

    /// Один эталон на всех разборщиков (`tests/fixtures/status-states.json`, пишет его CLI-полоса): заголовок блока,
    /// его состояние, «Сейчас:»/«Ждёт Элвиса:» и целые сводки — у Swift то же, что у `pimp.py digest` и страницы.
    func testStatusStatesFixtureMatchesSwiftParsers() throws {
        let table = try JSONDecoder().decode(StatusTable.self,
                                             from: Data(contentsOf: Repo.fixture("status-states.json")))
        let swift = { (key: String) in table.states[key]?["swift"] ?? "?" }
        for pair in table.headings {
            XCTAssertTrue(StatusFeed.isWorkflowHeading(pair[0]), pair[0])
            XCTAssertEqual(Self.swiftName(PanelProjects.blockState(pair[0])), swift(pair[1]), pair[0])
        }
        for line in table.notHeadings {
            XCTAssertFalse(StatusFeed.isWorkflowHeading(line), line)
        }
        for tail in table.tails {
            let found = PanelProjects.tailLine(tail[0])
            XCTAssertEqual(found?.now, tail[1] == "now", tail[0])
            XCTAssertEqual(found?.value, tail[2], tail[0])
        }
        for document in table.documents {
            let status = PanelProjects.parse(document.text)
            XCTAssertEqual(status.workflows.map { Self.swiftName($0.state) }, document.workflows.map(swift), document.name)
            XCTAssertEqual(status.now, document.now, document.name)
            XCTAssertEqual(status.waitFor, document.wait, document.name)
        }
    }

    /// Все четыре ответа ручек страницы — одним `httpResponse`: CORS только для браузера и ровно `https://claude.ai`,
    /// у нативного и отказа — ни строки `Access-Control`; длина тела и `no-store` у всех.
    func testPageResponsesShareExactCORS() {
        let cors = "Access-Control-Allow-Origin: https://claude.ai\r\nVary: Origin\r\n"
            + "Access-Control-Allow-Methods: GET\r\nAccess-Control-Allow-Private-Network: true\r\n"
        let tail = "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        let browser = HtmlChromeOpener.PageAccess.browser(preflight: false)
        let text = { (data: Data) in String(decoding: data, as: UTF8.self) }
        XCTAssertEqual(text(HtmlChromeOpener.pageResponse(.browser(preflight: true))),
                       "HTTP/1.1 204 No Content\r\n" + cors + tail)
        XCTAssertEqual(text(HtmlChromeOpener.pageResponse(.reject(403))),
                       "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n" + tail)
        XCTAssertEqual(text(HtmlChromeOpener.digestResponse(Data("{}".utf8), access: browser)),
                       "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n" + cors
                       + "Content-Length: 2\r\n" + tail + "{}")
        XCTAssertEqual(text(HtmlChromeOpener.thumbResponse(nil, access: browser)),
                       "HTTP/1.1 404 Not Found\r\n" + cors + "Content-Length: 0\r\n" + tail)
        XCTAssertEqual(text(HtmlChromeOpener.kickoffResponse("ok", access: browser)),
                       "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n" + cors
                       + "Content-Length: 2\r\n" + tail + "ok")
        let natives = [HtmlChromeOpener.pageResponse(.native),
                       HtmlChromeOpener.digestResponse(Data("{}".utf8), access: .native),
                       HtmlChromeOpener.thumbResponse(Data([1]), access: .native),
                       HtmlChromeOpener.kickoffResponse("ok", access: .native)]
        for answer in natives { XCTAssertFalse(text(answer).contains("Access-Control"), text(answer)) }
    }

    func testColorMath() {
        XCTAssertEqual(ColorMath.rgb(hex: " #FF8000 "), 0xFF8000)
        XCTAssertEqual(ColorMath.rgb(hex: "ff8000"), 0xFF8000)
        XCTAssertNil(ColorMath.rgb(hex: "#fff"))
        XCTAssertNil(ColorMath.rgb(hex: "мусор!"))
        XCTAssertEqual(ColorMath.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(ColorMath.hsl(0x00FF00).hue ?? -1, 120, accuracy: 0.01)
        XCTAssertNil(ColorMath.hsl(0x808080).hue)
        XCTAssertEqual(ColorMath.hsl(0xFF0000).saturation, 1, accuracy: 0.001)
        XCTAssertEqual(ColorMath.hsl(0xFFFFFF).lightness, 1, accuracy: 0.001)
        XCTAssertEqual(ColorMath.mix(0xFFFFFF, 0x000000, 0.5), 0x808080)
        // Прежние разборщики стоят на нём же.
        XCTAssertEqual(ThemeKnobs.hue(hex: "#0000ff"), 240)
        XCTAssertEqual(AutoPaint.saturation(hex: "#808080"), 0)
    }

    func testPluralRu() {
        let forms = [0, 1, 2, 5, 11, 12, 14, 21, 22, 25, 101, 111, 112].map { Plural.ru($0, "чат", "чата", "чатов") }
        XCTAssertEqual(forms, ["чатов", "чат", "чата", "чатов", "чатов", "чатов", "чатов", "чат", "чата", "чатов",
                               "чат", "чатов", "чатов"])
        XCTAssertEqual(ChatArchive.plural(3, "бэкап", "бэкапа", "бэкапов"), "3 бэкапа")
    }

    func testChatIDOneRule() {
        let uuid = "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"
        XCTAssertEqual(ChatID.parse(" \(uuid) "), uuid)
        XCTAssertEqual(ChatID.parse("local_abc_DEF-1"), "local_abc_DEF-1")
        XCTAssertNil(ChatID.parse("local_"))
        XCTAssertNil(ChatID.parse("local_a/b"))
        XCTAssertNil(ChatID.parse("chat_abc"))
        XCTAssertNil(ChatID.parse("local_" + String(repeating: "a", count: ChatID.limit)))
        // Страница, порт и адрес страницы пускают одно и то же.
        for raw in [uuid, "local_x y", "local_"] {
            XCTAssertEqual(ChatProbe.chatId(raw), ChatID.parse(raw), raw)
            XCTAssertEqual(HtmlChromeOpener.chatID(raw), ChatID.parse(raw), raw)
        }
        XCTAssertTrue(ChatID.isUUID(uuid))
        XCTAssertFalse(ChatID.isUUID("local_abc"))
        // Канал: ровно одно из chat (uuid) или project.
        XCTAssertEqual(PimpRequest.exclusiveChat(["chat": uuid], project: ""), uuid)
        XCTAssertEqual(PimpRequest.exclusiveChat([:], project: "Rick"), "")
        XCTAssertNil(PimpRequest.exclusiveChat(["chat": uuid], project: "Rick"))
        XCTAssertNil(PimpRequest.exclusiveChat([:], project: ""))
        XCTAssertNil(PimpRequest.exclusiveChat(["chat": "local_abc"], project: ""))
    }

    /// Живой claude.json читается заново только после смены файла — и смену видит сразу.
    func testLiveConfigRereadsOnChange() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liveconfig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("claude.json")
        XCTAssertNil(LiveConfig.json(at: url))
        try Data(#"{"windowGap": 7, "projectsRoot": "~/P"}"#.utf8).write(to: url, options: .atomic)
        XCTAssertEqual(LiveConfig.number("windowGap", at: url), 7)
        XCTAssertEqual(LiveConfig.string("projectsRoot", at: url), "~/P")
        XCTAssertEqual(ClaudeActions.windowGap(configURL: url), 7)
        try Data(#"{"windowGap": 12}"#.utf8).write(to: url, options: .atomic)
        XCTAssertEqual(ClaudeActions.windowGap(configURL: url), 12)
        XCTAssertNil(LiveConfig.string("projectsRoot", at: url))
        try Data("битый".utf8).write(to: url, options: .atomic)
        XCTAssertNil(LiveConfig.json(at: url))
        XCTAssertEqual(LiveConfig.text(at: url), "битый")
        XCTAssertEqual(ClaudeActions.windowGap(configURL: url), ClaudeActions.defaultWindowGap)
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(LiveConfig.data(at: url))
    }
}
