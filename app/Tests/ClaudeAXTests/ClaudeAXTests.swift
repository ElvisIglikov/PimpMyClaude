import XCTest
@testable import ClaudeAX

/// Только чистая логика: раскладка «Расставить», клавиши меню и формат command.json.
/// Живой AX (окна Claude, авто-Allow, popUp) проверяется руками на гейте.
final class ClaudeAXTests: XCTestCase {
    func testSkeleton() { XCTAssertEqual(ClaudeCommand.allCases.count, 7) }

    // MARK: - «Расставить»

    func testColumnsKeepOneRowWhileCellsAreWideEnough() {
        // 1920/4 = 480 ≥ 340 — четыре столбца во всю высоту, а не 2×2.
        XCTAssertEqual(ArrangeLayout.columns(count: 4, width: 1920), 4)
        XCTAssertEqual(ArrangeLayout.columns(count: 1, width: 1920), 1)
        // 1920/6 = 320 < 340 — столбец отбрасывается, появляется второй ряд.
        XCTAssertEqual(ArrangeLayout.columns(count: 6, width: 1920), 5)
        XCTAssertEqual(ArrangeLayout.columns(count: 8, width: 1000), 2)
    }

    func testFramesTileAreaWithoutGaps() {
        let area = CGRect(x: 100, y: 25, width: 1710, height: 1055)
        let cells = ArrangeLayout.frames(count: 5, in: area)
        XCTAssertEqual(cells.count, 5)
        XCTAssertEqual(cells[0].minX, area.minX)
        XCTAssertEqual(cells[4].maxX, area.maxX)
        for i in 1..<cells.count {
            XCTAssertEqual(cells[i].minX, cells[i - 1].maxX, "щель между ячейками \(i - 1) и \(i)")
            XCTAssertEqual(cells[i].height, area.height)
        }
        XCTAssertTrue(ArrangeLayout.frames(count: 0, in: area).isEmpty)
    }

    func testFramesFillRowsTopDown() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let cells = ArrangeLayout.frames(count: 3, in: area) // 1000/3 = 333 < 340 → 2×2
        XCTAssertEqual(cells[0], CGRect(x: 0, y: 0, width: 500, height: 400))
        XCTAssertEqual(cells[1], CGRect(x: 500, y: 0, width: 500, height: 400))
        XCTAssertEqual(cells[2], CGRect(x: 0, y: 400, width: 500, height: 400))
    }

    func testOrderKeepsRowsLeftToRight() {
        let frames = [
            CGRect(x: 800, y: 0, width: 400, height: 400),   // 0 — правое верхнее
            CGRect(x: 0, y: 40, width: 400, height: 400),    // 1 — левое верхнее (тот же ряд, Δy < 60)
            CGRect(x: 0, y: 500, width: 400, height: 400),   // 2 — нижнее
        ]
        XCTAssertEqual(ArrangeLayout.order(of: frames), [1, 0, 2])
    }

    // MARK: - клавиши

    func testMenuKeysMatchReadme() {
        let expected: [(ClaudeCommand, String, UInt32, Bool)] = [
            (.cashout, "Обкэшить   ⌘⇧N", 0x2D, true),
            (.newChat, "Новый чат   ⌘N", 0x2D, false), // ⌘N — штатная клавиша Claude, не регистрируем
            (.collapse, "Свернуть   ⌘⌥↓", 0x7D, true),
            (.expand, "Развернуть   ⌘⌥↑", 0x7E, true),
            (.arrange, "Расставить   ⌘⌥A", 0x00, true),
            (.show, "Показать   ⌘⌥S", 0x01, true),
            (.scroll, "Прокрутить   ⌘⌥D", 0x02, true),
        ]
        XCTAssertEqual(MenuModel.entries.map { $0.command }, expected.map { $0.0 })
        for (command, title, code, registers) in expected {
            let entry = MenuModel.entry(for: command)
            XCTAssertEqual(entry?.menuTitle, title)
            XCTAssertEqual(entry?.key.keyCode, code)
            XCTAssertEqual(entry?.registersHotkey, registers)
        }
        XCTAssertEqual(MenuModel.entries.map { $0.icon }, ["💰", "💬", "⬇️", "⬆️", "▦", "👀", "⏬"])
    }

    func testCarbonModifiers() {
        XCTAssertEqual(KeyMods([.command, .shift]).carbon, 0x0100 | 0x0200)
        XCTAssertEqual(KeyMods([.command, .option]).carbon, 0x0100 | 0x0800)
        XCTAssertEqual(MenuModel.quitKey.keyCode, 0x0C)
        XCTAssertEqual(MenuModel.quitKey.hint, "⌘Q")
    }

    // MARK: - command.json

    func testPayloadMatchesLoaderContract() throws {
        let at = Date(timeIntervalSince1970: 1_756_900_000) // 2025-09-03T11:46:40Z
        let body = CommandChannel.payload(action: "cashout", extra: ["title": "Чат \"один\""],
                                          id: "1756900000123-0042", at: at)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "1756900000123-0042")
        XCTAssertEqual(json["action"] as? String, "cashout")
        XCTAssertEqual(json["at"] as? String, "2025-09-03T11:46:40Z")
        XCTAssertEqual(json["title"] as? String, "Чат \"один\"")
        XCTAssertTrue(body.hasPrefix("{\"id\":"), body)
    }

    func testJSONStringEscapesControls() {
        XCTAssertEqual(CommandChannel.jsonString("a\"b\\c"), "\"a\\\"b\\\\c\"")
        XCTAssertEqual(CommandChannel.jsonString("a\nb"), "\"a\\u000ab\"")
    }

    func testAtomicWriteReplacesFile() throws {
        // Живой ~/Library не трогаем: пишем во временную папку.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudeax-\(UUID().uuidString)", isDirectory: true)
        let file = dir.appendingPathComponent("command.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(CommandChannel.writeAtomic(file, "{\"id\":\"1\"}")) // папки ещё нет
        XCTAssertTrue(CommandChannel.writeAtomic(file, "{\"id\":\"2\"}")) // поверх существующего
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{\"id\":\"2\"}")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.appendingPathExtension("tmp").path))
    }

    func testIDsDifferWithinTheSameMillisecond() {
        // Лоадер отбрасывает команду с прежним id, поэтому две подряд обязаны отличаться.
        let ids = Set((0..<200).map { _ in CommandChannel.makeID() })
        XCTAssertGreaterThan(ids.count, 150)
    }
}
