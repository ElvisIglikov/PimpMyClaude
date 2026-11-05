import XCTest
@testable import ClaudeAX

/// #10464: открытые терминалы в панели — «<маркер> <Проект>», в ходе — сверху.
final class PanelTerminals10464Tests: XCTestCase {
    func testHeadingIsMarkerAndProject() {
        XCTAssertEqual(PanelTerminals.heading("# ⚪PimpMyClaude — памятка агенту (читать первой, до README)"), "⚪ PimpMyClaude")
        XCTAssertEqual(PanelTerminals.heading("# 🧼 VkusSES — подготовка точек Вкуснофф к проверке СЭС"), "🧼 VkusSES")
        XCTAssertEqual(PanelTerminals.heading("# 🎨Рисовалка"), "🎨 Рисовалка")
        XCTAssertEqual(PanelTerminals.heading("# 🖼️ PimpViewer · галерея"), "🖼️ PimpViewer")
        XCTAssertNil(PanelTerminals.heading("# Рисовалка — правила проекта"), "без маркера — ищем дальше")
        XCTAssertNil(PanelTerminals.heading(""))
    }

    func testTitleFromStatusThenPassportElseName() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("t10464-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let ses = root.appendingPathComponent("VkusSES")
        try FileManager.default.createDirectory(at: ses, withIntermediateDirectories: true)
        try "# 🧼 VkusSES — СЭС\n".write(to: ses.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        let kz = root.appendingPathComponent("VkusnoffKz/audit")
        try FileManager.default.createDirectory(at: kz, withIntermediateDirectories: true)
        try "# 🟠VkusnoffKz\n".write(to: kz.appendingPathComponent("status.md"), atomically: true, encoding: .utf8)
        try "# VkusnoffKz — сайт\n".write(to: kz.deletingLastPathComponent().appendingPathComponent("AGENTS.md"),
                                       atomically: true, encoding: .utf8)
        XCTAssertEqual(PanelTerminals.title(session: "VkusSES", root: root), "VkusSES", "статуса нет — паспорт; маркер в заголовок не идёт (#10564)")
        XCTAssertEqual(PanelTerminals.title(session: "vkusnoffkz", root: root), "VkusnoffKz", "регистр папки — любой")
        XCTAssertEqual(PanelTerminals.title(session: "Nope", root: root), "Nope")
    }

    func testRowsByNameAndCacheTimer() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let rows = PanelTerminals.rows(sessions: ["VkusSES", "PimpMyClaude", "Risovalka"], turning: ["Risovalka"],
                                       title: { "🧼 " + $0 }, coolsAt: { $0 == "VkusSES" ? now.addingTimeInterval(-60)
                                           : $0 == "PimpMyClaude" ? now.addingTimeInterval(41 * 60 + 5) : nil })
        XCTAssertEqual(rows.map { $0.session }, ["PimpMyClaude", "Risovalka", "VkusSES"], "по имени — строки не прыгают")
        XCTAssertEqual(rows.map { $0.name }, ["PimpMyClaude", "Risovalka", "VkusSES"], "без маркера-картинки")
        XCTAssertEqual(rows.map { $0.cacheMinutes(now: now) }, [42, 60, 0], "ход идёт — тёплый на весь час; остыл — 0")
        XCTAssertEqual(PanelTerminal(session: "x", title: "x y", turning: false).name, "x y", "без маркера — как есть")
    }

    func testLastWriteSkipsDesktopTranscripts() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("t10464c-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        setenv("CLAUDE_CONFIG_DIR", home.path, 1)
        defer { unsetenv("CLAUDE_CONFIG_DIR") }
        let folder = URL(fileURLWithPath: "/Users/x/_Elvis.Projects/Vkus SES")
        let dir = home.appendingPathComponent("projects/-Users-x--Elvis-Projects-Vkus-SES")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cli = dir.appendingPathComponent("a.jsonl"), desk = dir.appendingPathComponent("b.jsonl")
        try #"{"entrypoint":"cli"}"#.write(to: cli, atomically: true, encoding: .utf8)
        try #"{"entrypoint": "claude-desktop"}"#.write(to: desk, atomically: true, encoding: .utf8)
        let old = Date(timeIntervalSince1970: 2_000_000), new = Date(timeIntervalSince1970: 2_000_500)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: cli.path)
        try FileManager.default.setAttributes([.modificationDate: new], ofItemAtPath: desk.path)
        XCTAssertEqual(PanelTerminals.lastWrite(folder: folder), old, "свежий транскрипт окна Claude — не терминала")
    }
}
