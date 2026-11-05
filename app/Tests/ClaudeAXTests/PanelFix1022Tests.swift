@testable import ClaudeAX
import XCTest

/// Панель у часов, слова Элвиса 22.10.2026: линия температуры (и памяти, нагрузки) в строке — сплошная; счёт терминала —
/// прямой, с последней активности; расход журналов Claude Code для «Цены Workflow» живёт без режимов работы.
final class PanelFix1022Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: сплошная линия

    /// Как у Элвиса в 01:18: одна точка до сна (крышка закрыта 22:24–22:54), дальше чтения раз в минуту. По времени
    /// X точки до сна — на левом краю, дальше пустота в шестую часть строки; без сна — шаг как у соседей.
    func testSparkCompressesSleepIntoOneStep() {
        let dates = [t0] + (0..<150).map { t0.addingTimeInterval(1820 + Double($0) * 60) }
        let x = ChartCurve.awakeFractions(dates, gap: MacTemperature.gap, step: MacTemperature.interval)
        XCTAssertEqual(x.count, dates.count)
        XCTAssertEqual(x.first, 0)
        XCTAssertEqual(x.last, 1)
        XCTAssertEqual(x[1] - x[0], x[2] - x[1], accuracy: 1e-9, "сон — за один обычный шаг, разрыва нет")
        XCTAssertEqual(zip(x, x.dropFirst()).allSatisfy { $0 < $1 }, true, "слева направо")
        // Сегменты с разрывом остаются для раскрытого графика с часами.
        let samples = dates.map { MacTemperatureSample(at: $0, chipAverage: 40, chipMax: 45, battery: nil, state: .nominal) }
        XCTAssertEqual(MacTemperature.segments(samples).count, 2)
    }

    /// Обычная работа: шаг минута, перезапуск Пимпа (10–50 с) — без сжатия; пусто и одна точка — не падает.
    func testSparkKeepsTimeWhileAwake() {
        let dates = [0, 60, 120, 130, 172, 232].map { t0.addingTimeInterval($0) }
        let x = ChartCurve.awakeFractions(dates, gap: MacMemory.gap, step: MacMemory.interval)
        XCTAssertEqual(x.map { ($0 * 232).rounded() }, [0, 60, 120, 130, 172, 232])
        XCTAssertEqual(ChartCurve.awakeFractions([], gap: 150, step: 60), [])
        XCTAssertEqual(ChartCurve.awakeFractions([t0], gap: 150, step: 60), [1], "одна точка — справа")
        XCTAssertEqual(ChartCurve.awakeFractions([t0, t0], gap: 150, step: 60), [1, 1])
    }

    // MARK: терминалы

    func testIdleSecondsCountUpFromLastWrite() {
        let now = t0
        let quiet = PanelTerminal(session: "a", title: "a", turning: false,
                                  coolsAt: now.addingTimeInterval(PanelTerminals.cacheSeconds - 236))
        XCTAssertEqual(quiet.idleSeconds(now: now), 236)
        XCTAssertEqual(quiet.idleSeconds(now: now.addingTimeInterval(1)), 237, "тикает вперёд")
        XCTAssertEqual(PanelTerminal(session: "b", title: "b", turning: true, coolsAt: nil).idleSeconds(now: now), 0,
                       "ход идёт — активность сейчас")
        XCTAssertNil(PanelTerminal(session: "c", title: "c", turning: false).idleSeconds(now: now), "транскрипта нет")
        let cold = PanelTerminal(session: "d", title: "d", turning: false, coolsAt: now.addingTimeInterval(-120))
        XCTAssertEqual(cold.idleSeconds(now: now), PanelTerminals.cacheSeconds + 120)
        XCTAssertEqual(cold.cacheMinutes(now: now), 0, "остыл")
    }

    // MARK: расход без режимов

    private func answer(_ id: String, _ at: String, input: Int = 0, create: Int = 0, read: Int = 0, output: Int) -> String {
        #"{"parentUuid":"p","message":{"model":"claude-opus-5-5","id":"\#(id)","type":"message","#
            + #""role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":\#(input),"#
            + #""cache_creation_input_tokens":\#(create),"cache_read_input_tokens":\#(read),"output_tokens":\#(output)}},"#
            + #""type":"assistant","uuid":"u","timestamp":"\#(at)"}"#
    }

    func testUsageLineParse() {
        let line = ClaudeUsageLine.parse(Data(answer("msg_1", "2026-10-19T10:00:00.500Z", input: 2, create: 30, read: 400,
                                                     output: 5).utf8))
        XCTAssertEqual(line?.id, "msg_1")
        XCTAssertEqual(line?.total, 437)
        XCTAssertEqual(line?.at, ClaudeUsage.date("2026-10-19T10:00:00.500Z"))
        XCTAssertNil(ClaudeUsageLine.parse(Data(#"{"type":"user","message":{"id":"x","usage":{"input_tokens":1}},"timestamp":"2026-10-19T10:00:00Z"}"#.utf8)))
        XCTAssertNil(ClaudeUsageLine.parse(Data(#"{"type":"assistant","message":{"id":"x"},"timestamp":"2026-10-19T10:00:00Z"}"#.utf8)))
        XCTAssertNil(ClaudeUsageLine.parse(Data("{\"type\":\"assistant\"".utf8)), "рваная строка")
        XCTAssertNotNil(ClaudeUsage.date("2026-10-19T10:00:00Z"), "и без миллисекунд")
    }

    /// Один ответ несколькими строками — один раз, строка с самым поздним временем.
    func testReadKeepsLatestLinePerAnswer() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-1022-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = [answer("m1", "2026-10-19T10:00:00Z", output: 1), answer("m1", "2026-10-19T10:00:05Z", output: 9),
                     #"{"type":"user","message":{"content":"привет"}}"#, answer("m2", "2026-10-19T10:01:00Z", output: 3)]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        var byId: [String: ClaudeUsageLine] = [:]
        ClaudeUsage.read(url, since: .distantPast, into: &byId)
        XCTAssertEqual(byId.count, 2)
        XCTAssertEqual(byId["m1"]?.output, 9)
        XCTAssertEqual(byId["m2"]?.output, 3)
    }
}
