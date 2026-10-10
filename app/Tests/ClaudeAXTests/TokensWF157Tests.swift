import XCTest
@testable import ClaudeAX

/// Токены (WF157, #9149; WF170, #9179): разбор копилки Рика, периоды и сравнение, один ряд по дням без накопления,
/// ранжир проектов, «ещё не собрано» вместо нуля, пустой файл.
final class TokensWF157Tests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// Чт 8 октября 2026, 12:00 UTC.
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!

    private func bucket(_ total: Int) -> [String: Any] {
        ["in": 1, "cw": 2, "cr": total - 4, "out": 1, "n": 999]
    }

    private func file(_ hosts: [String: [String: [String: [String: Any]]]]) -> Data {
        var json: [String: Any] = ["version": 1, "about": "…", "sessions": [:]]
        json["hosts"] = hosts.mapValues { ["days": $0, "scanned": "2026-10-08T23:00"] }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func sample() -> TokensDaily {
        TokensDaily.parse(file([
            "m4": ["2026-10-08": ["Rick": bucket(100), "PimpMyClaude": bucket(300)],
                   "2026-10-05": ["Rick": bucket(50)],
                   "2026-10-04": ["VkusnoffKz": bucket(70)]],
            "mac": ["2026-10-08": ["Rick": bucket(20), "Dictator": bucket(10)],
                    "2026-09-01": ["Rick": bucket(1000)]],
        ]))
    }

    func testParseSumsHostsAndFields() {
        let data = sample()
        XCTAssertEqual(data.days["2026-10-08"], ["Rick": 120, "PimpMyClaude": 300, "Dictator": 10],
                       "оба Мака складываются, n не токены")
        XCTAssertEqual(data.days["2026-10-05"], ["Rick": 50])
        XCTAssertEqual(data.total("2026-10-08"), 430)
        XCTAssertEqual(data.total("2026-10-07"), 0)
        XCTAssertFalse(data.isEmpty)
    }

    func testParseGarbageAndEmpty() {
        XCTAssertTrue(TokensDaily.parse(nil).isEmpty)
        XCTAssertTrue(TokensDaily.parse(Data("не json".utf8)).isEmpty)
        XCTAssertTrue(TokensDaily.parse(Data("{}".utf8)).isEmpty)
        XCTAssertTrue(TokensDaily.parse(Data(#"{"hosts":{}}"#.utf8)).isEmpty)
        let odd = TokensDaily.parse(Data(#"{"hosts":{"m4":{"days":{"вчера":{"Rick":{"in":5}},"2026-10-08":{"Rick":{"in":0},"X":"мусор"}}}}}"#.utf8))
        XCTAssertTrue(odd.isEmpty, "кривой день, нули и мусор пропущены")
    }

    func testRealFileShapeParses() throws {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects/Rick/data/tokens-daily.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("копилки Рика на этом Маке нет") }
        XCTAssertFalse(TokensDaily.parse(data).isEmpty)
    }

    func testPeriods() {
        XCTAssertEqual(TokenPeriod.today.days(now: now, calendar: calendar), ["2026-10-08"])
        XCTAssertEqual(TokenPeriod.yesterday.days(now: now, calendar: calendar), ["2026-10-07"])
        XCTAssertEqual(TokenPeriod.week.days(now: now, calendar: calendar),
                       ["2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08"])
        let month = TokenPeriod.month.days(now: now, calendar: calendar)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(month.first, "2026-09-09")
        XCTAssertEqual(month.last, "2026-10-08")
        XCTAssertEqual(TokenPeriod.allCases.map { $0.title }, ["Сегодня", "Вчера", "7 дней", "Месяц"])
        XCTAssertNil(TokenPeriod(rawValue: "dayBefore"), "старый «Позавчера» из настроек — к умолчанию")
        XCTAssertTrue(TokenPeriod.today.isSingleDay)
        XCTAssertFalse(TokenPeriod.week.isSingleDay)
    }

    func testPreviousPeriods() {
        XCTAssertEqual(TokenPeriod.today.previousDays(now: now, calendar: calendar), ["2026-10-07"])
        XCTAssertEqual(TokenPeriod.yesterday.previousDays(now: now, calendar: calendar), ["2026-10-06"])
        XCTAssertEqual(TokenPeriod.week.previousDays(now: now, calendar: calendar),
                       ["2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"])
        let month = TokenPeriod.month.previousDays(now: now, calendar: calendar)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(month.first, "2026-08-10")
        XCTAssertEqual(month.last, "2026-09-08")
    }

    func testDailyPointsOneSeriesNotCumulative() {
        let summary = TokenStats.summary(sample(), period: .week, grouping: .weeks, now: now, calendar: calendar)
        XCTAssertEqual(summary.points.count, 7, "у «7 дней» недель нет — всегда дни")
        XCTAssertEqual(summary.points.map { $0.value }, [0, 0, 70, 50, 0, 0, 430],
                       "каждый день — свой итог всех проектов, без нарастающей суммы")
        XCTAssertEqual(summary.points.last?.label, "8")
        XCTAssertEqual(summary.points.last?.weekday, "чт")
        XCTAssertEqual(summary.points.last?.title, "8 октября, чт")
        XCTAssertEqual(summary.total, 550)
        XCTAssertEqual(summary.peak, "2026-10-08")
        XCTAssertFalse(summary.pending, "сбор неизвестен — дни считаем собранными")
    }

    func testRankingSortedWithShares() {
        let summary = TokenStats.summary(sample(), period: .week, grouping: .days, now: now, calendar: calendar)
        XCTAssertEqual(summary.ranking.map { $0.project }, ["PimpMyClaude", "Rick", "VkusnoffKz", "Dictator"])
        XCTAssertEqual(summary.ranking.map { $0.value }, [300, 170, 70, 10])
        XCTAssertEqual(summary.ranking.map { $0.percent }, ["55%", "31%", "13%", "2%"])
        XCTAssertEqual(summary.ranking.reduce(0) { $0 + $1.value }, summary.total, "ранжир — те же токены, что итог")
        XCTAssertEqual(TokenStats.percent(0.0037), "<1%", "28,5 млн из 7,6 млрд — не «0%»")
        XCTAssertEqual(TokenStats.percent(0.006), "1%")
        XCTAssertEqual(TokenStats.percent(0), "0%")
        let tie = TokenStats.summary(TokensDaily(days: ["2026-10-08": ["B": 5, "A": 5]]), period: .today,
                                     grouping: .days, now: now, calendar: calendar)
        XCTAssertEqual(tie.ranking.map { $0.project }, ["A", "B"], "равные — по имени")
    }

    func testMonthWeeksMondayFirst() {
        let month = TokenStats.summary(sample(), period: .month, grouping: .weeks, now: now, calendar: calendar)
        XCTAssertEqual(month.points.count, 5, "9 сен (ср) … 8 окт (чт)")
        XCTAssertEqual(month.points.last?.id, "2026-10-05")
        XCTAssertEqual(month.points.last?.value, 480)
        XCTAssertEqual(month.points.last?.label, "5 окт – 8 окт")
        XCTAssertEqual(month.points.last?.title, "5 октября – 8 октября")
        XCTAssertEqual(month.points.last?.weekday, "")
        XCTAssertEqual(month.points.map { $0.value }.reduce(0, +), 550, "1 сентября в месяц не входит")
        let days = TokenStats.summary(sample(), period: .month, grouping: .days, now: now, calendar: calendar)
        XCTAssertEqual(days.points.count, 30)
    }

    func testSingleDayAndComparison() {
        let today = TokenStats.summary(sample(), period: .today, grouping: .days, now: now, calendar: calendar)
        XCTAssertEqual(today.total, 430)
        XCTAssertEqual(today.ranking.map { $0.project }, ["PimpMyClaude", "Rick", "Dictator"])
        XCTAssertEqual(today.previous, 0)
        XCTAssertEqual(TokenStats.comparison(today), "", "вчера пусто — сравнивать не с чем")

        var data = sample()
        data.days["2026-10-07"] = ["Rick": 200]
        data.days["2026-09-30"] = ["Rick": 1100]
        let withYesterday = TokenStats.summary(data, period: .today, grouping: .days, now: now, calendar: calendar)
        XCTAssertEqual(TokenStats.comparison(withYesterday), "вчера за весь день — 200",
                       "сегодня не кончилось — без процента")
        let yesterday = TokenStats.summary(data, period: .yesterday, grouping: .days, now: now, calendar: calendar)
        XCTAssertEqual(yesterday.total, 200)
        XCTAssertEqual(yesterday.previous, 0)
        let week = TokenStats.summary(data, period: .week, grouping: .days, now: now, calendar: calendar)
        XCTAssertEqual(week.total, 750)
        XCTAssertEqual(week.previous, 1100)
        XCTAssertEqual(TokenStats.comparison(week), "▼ 32% против прошлых 7 дней · было 1 тыс")
        data.days["2026-09-30"] = ["Rick": 500]
        let up = TokenStats.summary(data, period: .week, grouping: .days, now: now, calendar: calendar)
        XCTAssertEqual(TokenStats.comparison(up), "▲ 50% против прошлых 7 дней · было 500")
    }

    func testPendingTodayIsNotZero() {
        var data = sample()
        // Рик собрал вчера в 23:19 (UTC в тесте), сейчас 8 октября — сегодняшний день ещё не собран.
        data.scanned = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 23, minute: 19))!
        data.days["2026-10-08"] = nil
        XCTAssertTrue(data.isPending("2026-10-08", calendar: calendar))
        XCTAssertFalse(data.isPending("2026-10-07", calendar: calendar))
        let spark = TokenStats.spark(data, now: now, calendar: calendar)
        XCTAssertEqual(spark.values, [0, 0, 70, 50, 0, 0, nil])
        XCTAssertNil(spark.today)
        XCTAssertEqual(spark.todayText, "не собрано", "не собрано — словами, не «0» и не прочерк (WF177)")
        let today = TokenStats.summary(data, period: .today, grouping: .days, now: now, calendar: calendar)
        XCTAssertTrue(today.allPending)
        let week = TokenStats.summary(data, period: .week, grouping: .days, now: now, calendar: calendar)
        XCTAssertTrue(week.pending)
        XCTAssertFalse(week.allPending)
        XCTAssertEqual(week.points.map { $0.pending }, [false, false, false, false, false, false, true])
        XCTAssertEqual(TokenStats.scannedText(data.scanned, now: now, calendar: calendar), "собрано вчера в 23:19")
        XCTAssertEqual(TokenStats.scannedText(now, now: now, calendar: calendar), "собрано в 12:00")
        XCTAssertEqual(TokenStats.scannedText(nil, now: now, calendar: calendar), "")
    }

    func testScannedParsedFromHosts() {
        let json = #"{"hosts":{"m4":{"scanned":"2026-10-08T23:19:49+05:00","days":{"2026-10-08":{"Rick":{"in":5}}}},"mac":{"scanned":"2026-10-08T23:19:46+05:00","days":{}}}}"#
        let data = TokensDaily.parse(Data(json.utf8))
        XCTAssertEqual(data.scanned, ISO8601DateFormatter().date(from: "2026-10-08T18:19:49Z"), "самый свежий сбор")
        XCTAssertEqual(data.total("2026-10-08"), 5)
    }

    func testHumanNumbers() {
        XCTAssertEqual(TokenStats.human(0), "0")
        XCTAssertEqual(TokenStats.human(950), "950")
        XCTAssertEqual(TokenStats.human(12_400), "12 тыс")
        XCTAssertEqual(TokenStats.human(1_240_000), "1,2 млн")
        XCTAssertEqual(TokenStats.human(340_000_000), "340 млн")
        XCTAssertEqual(TokenStats.human(2_430_000_000), "2,4 млрд")
    }

    func testSpark() {
        let spark = TokenStats.spark(sample(), now: now, calendar: calendar)
        XCTAssertEqual(spark.values, [0, 0, 70, 50, 0, 0, 430])
        XCTAssertEqual(spark.todayText, "430")
        XCTAssertEqual(TokenStats.spark(.empty, now: now, calendar: calendar).values, [0, 0, 0, 0, 0, 0, 0])
    }

    func testStoreRereadsByMtimeAndMissingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tokens-wf157-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TokensDailyStore(url: url)
        XCTAssertTrue(store.load().isEmpty, "файла нет — пусто")
        try file(["m4": ["2026-10-08": ["Rick": bucket(100)]]]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: url.path)
        XCTAssertEqual(store.load().total("2026-10-08"), 100)
        try file(["m4": ["2026-10-08": ["Rick": bucket(200)]]]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: url.path)
        XCTAssertEqual(store.load().total("2026-10-08"), 100, "mtime тот же — не перечитывает")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: url.path)
        XCTAssertEqual(store.load().total("2026-10-08"), 200)
    }

    func testPathSetting() {
        let name = "tokens-wf157-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let root = URL(fileURLWithPath: "/tmp/projects", isDirectory: true)
        XCTAssertEqual(TokenStats.url(defaults: defaults, root: root).path, "/tmp/projects/Rick/data/tokens-daily.json")
        defaults.set("/tmp/x.json", forKey: TokenStats.pathKey)
        XCTAssertEqual(TokenStats.url(defaults: defaults, root: root).path, "/tmp/x.json")
    }
}
