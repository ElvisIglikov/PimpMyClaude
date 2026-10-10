@testable import ClaudeAX
import XCTest

/// WF84, батч S-K (п. 6.3 ТЗ карточки): «Сейчас:» и «Ждёт Элвиса:» едут в шапке сводки.
final class StatusFeedWF84Tests: XCTestCase {
    private let sample = """
    # ⚪PimpMyClaude
    обновлено 19:40
    2 воркфлоу

    Сейчас: старое, его перекроет последнее.
    1️⃣ Workflow ✅ готово
    - о чём: первое
    - шаги 2 из 2
    - кодинг · Opus high

    2️⃣ Workflow ✋ ждёт
    - о чём: карточка
    - шаги 1 из 3
    - кодинг · Opus max ❓

    Сейчас: идёт кодинг.
    Ждёт Элвиса: буква по макету.
    """

    func testTailLinesMoveIntoHead() {
        XCTAssertEqual(StatusFeed.compact(sample).components(separatedBy: "\n"), [
            "# ⚪PimpMyClaude",
            "обновлено 19:40",
            "2 воркфлоу",
            "Сейчас: идёт кодинг.",
            "Ждёт Элвиса: буква по макету.",
            "1️⃣ Workflow ✅ готово",
            "- о чём: первое",
            "- шаги 2 из 2",
            "- кодинг · Opus high",
            "2️⃣ Workflow ✋ ждёт",
            "- о чём: карточка",
            "- шаги 1 из 3",
            "- кодинг · Opus max ❓",
        ])
    }

    func testOrderIsNowThenWaitWhateverTheFileOrder() {
        let text = "# P\nЖдёт Элвиса: ответ\n1️⃣ Workflow 💭 идёт\n- шаги 0 из 1\nСейчас: план"
        XCTAssertEqual(StatusFeed.compact(text),
                       "# P\nСейчас: план\nЖдёт Элвиса: ответ\n1️⃣ Workflow 💭 идёт\n- шаги 0 из 1")
    }

    func testOnlyOneKindOrNone() {
        XCTAssertEqual(StatusFeed.compact("# P\n1️⃣ Workflow 💭\n- шаги 1 из 2\nСейчас: кодинг"),
                       "# P\nСейчас: кодинг\n1️⃣ Workflow 💭\n- шаги 1 из 2")
        XCTAssertEqual(StatusFeed.compact("# P\n1️⃣ Workflow 💭\n- шаги 1 из 2"),
                       "# P\n1️⃣ Workflow 💭\n- шаги 1 из 2")
        // Блоков нет — хвост в конце шапки, она же весь файл.
        XCTAssertEqual(StatusFeed.compact("# P\nСейчас: тихо"), "# P\nСейчас: тихо")
    }

    func testIdempotent() {
        let once = StatusFeed.compact(sample)
        XCTAssertEqual(StatusFeed.compact(once), once)
        let long = "# P\n1️⃣ Workflow 💭\nСейчас: " + String(repeating: "я", count: 300)
        XCTAssertEqual(StatusFeed.compact(StatusFeed.compact(long)), StatusFeed.compact(long))
    }

    func testLongLineIsClippedTo200Characters() {
        let line = "Сейчас: " + String(repeating: "ж", count: 242)
        XCTAssertEqual(line.count, 250)
        let out = StatusFeed.compact("# P\n1️⃣ Workflow 💭\n- шаги 1 из 2\n" + line)
            .components(separatedBy: "\n")
        XCTAssertEqual(out[1].count, 200)
        XCTAssertEqual(out[1], String(line.prefix(200)))
        // Режется по границе символа: эмодзи из нескольких скаляров не рвётся.
        let emoji = "Ждёт Элвиса: " + String(repeating: "👨‍👩‍👧", count: 250)
        let clipped = StatusFeed.compact("# P\n" + emoji).components(separatedBy: "\n")[1]
        XCTAssertEqual(clipped.count, 200)
        XCTAssertTrue(clipped.hasSuffix("👨‍👩‍👧"))
    }

    func testSliceAt6KBKeepsBothTailLines() {
        var text = "# ⚪Проект\nобновлено 10:00\n"
        for index in 1...60 {
            text += "\(index % 9 + 1)️⃣ Workflow ✅ готово\n- о чём: "
                + String(repeating: "б", count: 60) + "\n- шаги 2 из 2\n"
        }
        text += "Сейчас: идёт проверка.\nЖдёт Элвиса: буква."
        let compacted = StatusFeed.compact(text)
        XCTAssertGreaterThan(compacted.utf8.count, StatusFeed.limit)
        let sliced = StatusFeed.slice(compacted)
        XCTAssertLessThanOrEqual(sliced.utf8.count, StatusFeed.limit)
        let lines = sliced.components(separatedBy: "\n")
        XCTAssertEqual(Array(lines.prefix(4)),
                       ["# ⚪Проект", "обновлено 10:00", "Сейчас: идёт проверка.", "Ждёт Элвиса: буква."])
        XCTAssertTrue(StatusFeed.isWorkflowHeading(lines[4]))
    }
}
