@testable import ClaudeAX
import XCTest

/// #6282: таблица цен по API. Каждая цена положительная, модель находится по id (с датой, `[1m]`, обёртками облаков),
/// чужие и будущие версии — без цены; быстрый режим, ступень Haiku 5.5 и данные в США.
final class ModelPricesTests: XCTestCase {
    func testAllPricesPositive() {
        XCTAssertFalse(ModelPrices.rows.isEmpty)
        for row in ModelPrices.rows {
            XCTAssertTrue(row.standard.all.allSatisfy { $0 > 0 }, row.id)
            XCTAssertTrue(row.fast?.all.allSatisfy { $0 > 0 } ?? true, row.id)
            XCTAssertTrue(row.long?.all.allSatisfy { $0 > 0 } ?? true, row.id)
            XCTAssertEqual(row.standard.write5m, row.standard.input * 1.25, accuracy: 1e-9, "запись на 5 мин — 1,25× входа: \(row.id)")
            XCTAssertEqual(row.standard.write1h, row.standard.input * 2, accuracy: 1e-9, "на 1 ч — 2×: \(row.id)")
        }
        XCTAssertEqual(Set(ModelPrices.rows.map(\.id)).count, ModelPrices.rows.count, "id без повторов")
    }

    func testFamilyById() {
        XCTAssertEqual(ModelPrices.row("claude-opus-5-5")?.name, "Opus 5.5")
        XCTAssertEqual(ModelPrices.family("claude-opus-5-5"), "Opus")
        XCTAssertEqual(ModelPrices.row("claude-opus-5")?.name, "Opus 5")
        XCTAssertEqual(ModelPrices.row("claude-sonnet-4-6-20260217")?.name, "Sonnet 4.6", "дата в хвосте")
        XCTAssertEqual(ModelPrices.row("claude-opus-5-5[1m]")?.name, "Opus 5.5")
        XCTAssertEqual(ModelPrices.row("claude-fable-5-1")?.family, "Fable")
        XCTAssertEqual(ModelPrices.row("claude-haiku-4-5-20251001")?.name, "Haiku 4.5")
        XCTAssertEqual(ModelPrices.row("claude-opus-4-20250514")?.name, "Opus 4")
        XCTAssertEqual(ModelPrices.row("claude-opus-4-5")?.name, "Opus 4.5", "не Opus 4")
        XCTAssertEqual(ModelPrices.row("us.anthropic.claude-opus-4-6-v1:0")?.name, "Opus 4.6")
        XCTAssertEqual(ModelPrices.row("claude-opus-4-5@20251101")?.name, "Opus 4.5")
        XCTAssertEqual(ModelPrices.row("claude-3-5-haiku-20241022")?.name, "Haiku 3.5")
        XCTAssertNil(ModelPrices.row("claude-opus-5-7"), "будущая версия — не цена соседней")
        XCTAssertNil(ModelPrices.row("gpt-5"))
        XCTAssertNil(ModelPrices.row("<synthetic>"))
        XCTAssertNil(ModelPrices.row(""))
    }

    func testCostRules() throws {
        let million = 1_000_000
        XCTAssertEqual(try XCTUnwrap(ModelPrices.cost(model: "claude-opus-5-5", input: million, output: million,
                                                      write5m: million, write1h: million, read: million)),
                       4 + 20 + 5 + 8 + 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ModelPrices.cost(model: "claude-opus-5-5", input: million, output: million, write5m: 0,
                                                      write1h: 0, read: 0, fast: true)), 48, accuracy: 1e-9, "быстрый ×2")
        XCTAssertNil(ModelPrices.cost(model: "claude-sonnet-5-5", input: 1, output: 1, write5m: 0, write1h: 0, read: 0, fast: true),
                     "быстрого режима нет — цены нет")
        XCTAssertEqual(try XCTUnwrap(ModelPrices.cost(model: "claude-haiku-5-5", input: 50_000, output: million, write5m: 0,
                                                      write1h: 0, read: 50_000)), 0.005 + 0.5 + 0.0005, accuracy: 1e-9,
                       "100 000 ровно — нижняя ступень")
        XCTAssertEqual(try XCTUnwrap(ModelPrices.cost(model: "claude-haiku-5-5", input: 50_000, output: million, write5m: 0,
                                                      write1h: 0, read: 50_001)), 0.025 + 2.5 + 0.00250005, accuracy: 1e-9,
                       "больше 100 000 — верхняя")
        XCTAssertEqual(try XCTUnwrap(ModelPrices.cost(model: "claude-opus-5-5", input: million, output: 0, write5m: 0,
                                                      write1h: 0, read: 0, usGeo: true)), 4.4, accuracy: 1e-9)
        XCTAssertNil(ModelPrices.cost(model: "gpt-5", input: 1, output: 1, write5m: 0, write1h: 0, read: 0))
    }
}
