import XCTest
@testable import ClaudeAX

/// WF177 (слово Элвиса 09.10 02:35): «Цвет Claude» — один выбор на блок (живая заставка ИЛИ цвет) и последним в панели;
/// «Нагрузка на память» — ось в ГБ от всей памяти Мака; «Токены» — понятное пустое состояние вместо «0» и «—».
final class PanelWF177Tests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824

    private func defaults(_ name: String = #function) -> UserDefaults {
        let store = UserDefaults(suiteName: "PanelWF177Tests.\(name)")!
        store.removePersistentDomain(forName: "PanelWF177Tests.\(name)")
        return store
    }

    // Выбор «живая заставка или цвет» WF177 заменён WF180 (`PanelWF180Tests`): выделен всегда цвет, «Живой» его оживляет.

    // MARK: «Цвет Claude» — последним

    func testColorsWidgetIsLastAndSavedLayoutMovesOnce() {
        XCTAssertEqual(PanelWidget.allCases.last, .colors)
        XCTAssertEqual(PanelWidgetLayout.standard.items.last?.id, "colors")
        let store = defaults()
        // Раскладка Элвиса до WF177: цвета посередине.
        store.set(#"[{"id":"week","wide":true},{"id":"reset","wide":true},{"id":"limits","wide":true},"#
                  + #"{"id":"colors","wide":true},{"id":"temperature","wide":true},{"id":"memory","wide":true},"#
                  + #"{"id":"tokens","wide":true}]"#, forKey: PanelWidgetLayout.key)
        var layout = PanelWidgetLayout.load(store)
        XCTAssertEqual(layout.items.last?.id, "colors", "переехал вниз")
        XCTAssertEqual(layout.items.prefix(2).map { $0.id }, ["workflow", "week"],
                       "остальной порядок человека цел; новый блок WF214 — сверху")
        XCTAssertEqual(layout.item("limits")?.wide, false, "старый широкий «5 часов» — парой с Fable, как раньше")
        // Дальше порядок снова выбирает человек: поднял цвета наверх — так и остаётся.
        XCTAssertTrue(layout.move("colors", over: "workflow"))
        layout.save(store)
        XCTAssertEqual(PanelWidgetLayout.load(store).items.first?.id, "colors")
    }

    // MARK: память — ось в ГБ

    func testMemoryAxisInGigabytesOfThisMac() {
        let eight = MacMemory.axis(total: 8 * Self.gb)
        XCTAssertEqual(eight.map { $0.label }, ["0", "4", "8 ГБ"], "«0 · 4 · 8 ГБ» на 8 ГБ")
        XCTAssertEqual(eight.map { $0.fraction }, [0, 0.5, 1])
        XCTAssertEqual(MacMemory.axis(total: 24 * Self.gb).map { $0.label }, ["0", "12", "24 ГБ"])
        XCTAssertEqual(MacMemory.axis(total: 18 * Self.gb).map { $0.label }, ["0", "9", "18 ГБ"])
        XCTAssertEqual(MacMemory.axis(total: 0).map { $0.label }, ["0", "50", "100 %"], "памяти не знаем — проценты")
    }

    func testMemoryPointSitsOnItsGigabytes() {
        // «6,3 из 8, а график на середине — как будто 4»: нагрузка macOS 50 %, занято 6,3 ГБ.
        let used = UInt64(6.3 * Double(Self.gb))
        let sample = MacMemorySample(at: Date(), pressure: 50, level: .normal, used: used, total: 8 * Self.gb)
        XCTAssertEqual(MacMemory.fraction(sample)!, 6.3 / 8, accuracy: 0.001, "выше середины — на 6,3 из 8")
        XCTAssertEqual(MacMemory.nowText([sample]), "6,3 ГБ")
        XCTAssertEqual(MacMemory.amount(sample), "6,3 ГБ")
        let noUsed = MacMemorySample(at: Date(), pressure: 50, level: .normal, used: nil, total: 8 * Self.gb)
        XCTAssertEqual(MacMemory.fraction(noUsed)!, 0.5, accuracy: 0.001, "занятого нет — нагрузка")
        XCTAssertEqual(MacMemory.nowText([noUsed]), "50 %")
        XCTAssertEqual(MacMemory.nowText([]), "—")
        let over = MacMemorySample(at: Date(), pressure: 99, level: .critical, used: 9 * Self.gb, total: 8 * Self.gb)
        XCTAssertEqual(MacMemory.fraction(over), 1, "выше оси не рисуем")
    }

    // MARK: токены — пустое состояние

    func testTokensEmptyAndPendingAreWords() {
        XCTAssertEqual(TokenSpark(values: [0, 0, 0, 0, 0, 0, 0], scanned: nil).todayText, "нет данных")
        XCTAssertTrue(TokenSpark(values: [nil, nil, nil, nil, nil, nil, nil], scanned: nil).isEmpty)
        XCTAssertEqual(TokenSpark(values: [nil, nil, nil, nil, nil, nil, nil], scanned: nil).todayText, "нет данных")
        XCTAssertEqual(TokenSpark(values: [5, 0, 0, 0, 0, 0, nil], scanned: nil).todayText, "не собрано")
        XCTAssertFalse(TokenSpark(values: [5, 0, 0, 0, 0, 0, nil], scanned: nil).isEmpty)
        XCTAssertEqual(TokenSpark(values: [5, 0, 0, 0, 0, 0, 643_145_836], scanned: nil).todayText, "643 млн")
    }

    func testTokensLiveFileOfThisMacGivesSevenDays() throws {
        // Копилка этого Мака на 09.10 02:36 (Rick/data/tokens-daily.json, срез): два Мака, сбор свежий — линия есть,
        // сегодня число. До 02:05 копилку пополнял только ручной запуск Рика (последний — 08.10 23:19), поэтому
        // сегодня было «не собрано» (в 1.10.7 — «0»); с 02:05 её пополняет launchd `com.rick.tokenstats` раз в 30 мин.
        let json = #"{"hosts":{"m4":{"scanned":"2026-10-09T02:36:07+05:00","days":{"#
            + #""2026-10-07":{"Rick":{"in":759878248}},"2026-10-08":{"Rick":{"in":67926193}}}},"#
            + #""mac":{"scanned":"2026-10-09T02:36:06+05:00","days":{"2026-10-08":{"Rick":{"cr":378946981}},"#
            + #""2026-10-09":{"PimpMyClaude":{"cr":219292088,"out":1000}}}}}}"#
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 5 * 3600))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-09T02:40:00+05:00"))
        let spark = TokenStats.spark(TokensDaily.parse(Data(json.utf8)), now: now, calendar: calendar)
        XCTAssertEqual(spark.values.count, 7)
        XCTAssertEqual(spark.values.suffix(3), [759_878_248, 67_926_193 + 378_946_981, 219_293_088])
        XCTAssertFalse(spark.isEmpty)
        XCTAssertEqual(spark.todayText, "219 млн")
        // Тот же файл, собранный вчера в 23:19, — сегодня «не собрано», вчера и раньше — числа.
        let stale = json.replacingOccurrences(of: "2026-10-09T02:36:0", with: "2026-10-08T23:19:4")
        let old = TokenStats.spark(TokensDaily.parse(Data(stale.utf8)), now: now, calendar: calendar)
        XCTAssertNil(old.today)
        XCTAssertEqual(old.todayText, "не собрано")
    }
}
