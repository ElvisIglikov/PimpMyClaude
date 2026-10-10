import XCTest
@testable import ClaudeAX

/// WF108 (#8179), WF227 (#9406): «Поддержать автора» — разбор donate.json, живой сильнее бандла, входы,
/// способы оплаты только по ссылкам, `{amount}`, «≈ $», Instagram, счёт людей, мусор в файле, возвратные ссылки.
final class DonateTests: XCTestCase {
    private let full = #"""
    {"version":1,"updated":"2026-10-10","people":187,"usdRate":510,"amounts":[1000,5000,10000],
     "applePay":"https://pay.example/ap?amount={amount}","card":"https://pay.example/card?amount={amount}",
     "kaspi":"https://pay.kaspi.example/pimp",
     "crypto":[{"coin":"USDT","network":"TRC-20","address":"TAddr"},{"coin":"BTC","network":"Bitcoin","address":"bc1addr"}],
     "instagram":"_elvis.kz_"}
    """#

    /// Файл прежней формы (до WF227): цель-ноутбук, собранные тенге, нет Kaspi и Instagram.
    private let old = #"""
    {"version":1,"updated":"2026-09-30",
     "goal":{"title":"MacBook Pro 14″","color":"космический чёрный","hex":"#3b3b40",
             "specs":["M5 Pro","64 ГБ","1 ТБ","14,2″"],"target":2150000},
     "raised":1376000,"people":187,"usdRate":510,"amounts":[1000,5000,10000],
     "applePay":"https://pay.example/ap?amount={amount}","card":"https://pay.example/card?amount={amount}",
     "crypto":[{"coin":"USDT","network":"TRC-20","address":"TAddr"}]}
    """#

    private func parse(_ json: String) -> DonateConfig? { DonateConfig.parse(Data(json.utf8)) }

    func testFullFileParses() throws {
        let config = try XCTUnwrap(parse(full))
        XCTAssertEqual(config.people, 187)
        XCTAssertEqual(config.usdRate, 510)
        XCTAssertEqual(config.amounts, [1000, 5000, 10000])
        XCTAssertEqual(config.kaspi, "https://pay.kaspi.example/pimp")
        XCTAssertEqual(config.crypto.map(\.coin), ["USDT", "BTC"])
        XCTAssertEqual(config.crypto.first?.network, "TRC-20")
        XCTAssertEqual(config.instagram, "_elvis.kz_")
        XCTAssertEqual(Donate.methods(config), [.applePay, .card, .kaspi, .crypto])
    }

    /// Старый файл без новых полей живёт: цель и «собрано» молча пропускаются, способы — те, что были.
    func testOldFileWithoutNewFieldsLives() throws {
        let config = try XCTUnwrap(parse(old))
        XCTAssertEqual(config.people, 187)
        XCTAssertNil(config.kaspi)
        XCTAssertNil(config.instagram)
        XCTAssertEqual(Donate.methods(config), [.applePay, .card, .crypto])
        XCTAssertTrue(Donate.entriesVisible(config, hidden: false))
        XCTAssertTrue(Donate.showsAmounts(config))
    }

    /// В бандле способов оплаты нет — в окне нет ни одной кнопки оплаты; окно открывается ради автора и Instagram.
    func testBundledDefaultHasNoPayButtons() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/donate.json").standardizedFileURL
        let config = try XCTUnwrap(DonateConfig.parse(try Data(contentsOf: url)))
        XCTAssertEqual(config.people, 0)
        XCTAssertEqual(Donate.methods(config), [])
        XCTAssertFalse(Donate.hasAddress(config))
        XCTAssertFalse(Donate.showsAmounts(config))
        XCTAssertEqual(config.instagram, "_elvis.kz_")
        // Способов оплаты в бандле нет — окна и входов нет ни у кого, хотя Instagram вписан (решение файла 37).
        XCTAssertFalse(Donate.windowAvailable(config))
        XCTAssertFalse(Donate.entriesVisible(config, hidden: false))
        XCTAssertFalse(Donate.entriesVisible(config, hidden: true))
    }

    func testLiveBeatsBundledAndBrokenLiveFallsBack() {
        let live = Data(#"{"people":5,"crypto":[{"coin":"USDT","network":"TRC-20","address":"T1"}]}"#.utf8)
        let bundled = Data(#"{"people":0}"#.utf8)
        XCTAssertEqual(DonateStore.resolve(live: live, bundled: bundled)?.people, 5)
        XCTAssertEqual(DonateStore.resolve(live: Data("{не json".utf8), bundled: bundled)?.people, 0)
        XCTAssertEqual(DonateStore.resolve(live: Data("[1,2]".utf8), bundled: bundled)?.people, 0)
        XCTAssertEqual(DonateStore.resolve(live: nil, bundled: bundled)?.people, 0)
        XCTAssertNil(DonateStore.resolve(live: nil, bundled: nil))
    }

    func testStoreRereadsByMtime() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("donate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let live = dir.appendingPathComponent("donate.json")
        let bundled = dir.appendingPathComponent("bundled.json")
        try Data(#"{"people":1}"#.utf8).write(to: bundled)
        let store = DonateStore(live: live, bundled: bundled)
        XCTAssertEqual(store.current()?.people, 1)
        try Data(#"{"people":7}"#.utf8).write(to: live)
        XCTAssertEqual(store.current()?.people, 7)
        try Data(#"{"people":9}"#.utf8).write(to: live)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: live.path)
        XCTAssertEqual(store.current()?.people, 9)
        try FileManager.default.removeItem(at: live)
        XCTAssertEqual(store.current()?.people, 1)
    }

    func testEntriesVisibility() throws {
        let config = try XCTUnwrap(parse(full))
        XCTAssertTrue(Donate.entriesVisible(config, hidden: false))
        XCTAssertFalse(Donate.entriesVisible(config, hidden: true))
        XCTAssertFalse(Donate.entriesVisible(nil, hidden: false))
        let cryptoOnly = try XCTUnwrap(parse(#"{"crypto":[{"coin":"BTC","network":"Bitcoin","address":"bc1"}]}"#))
        XCTAssertTrue(Donate.entriesVisible(cryptoOnly, hidden: false))
        let cardOnly = try XCTUnwrap(parse(#"{"card":"https://pay.example/c"}"#))
        XCTAssertTrue(Donate.entriesVisible(cardOnly, hidden: false))
        let none = try XCTUnwrap(parse(#"{"applePay":"","card":"  ","kaspi":"","crypto":[{"coin":"BTC"}]}"#))
        XCTAssertFalse(Donate.hasAddress(none))
        // Нет способа оплаты — окну нечего показать, входов нет.
        XCTAssertFalse(Donate.windowAvailable(none))
        XCTAssertFalse(Donate.entriesVisible(none, hidden: false))
        XCTAssertFalse(Donate.entriesVisible(try XCTUnwrap(parse("{}")), hidden: false))
    }

    /// Кнопка есть только у способа, чья ссылка есть в файле; порядок — Apple Pay, карта, Kaspi, крипта.
    func testMethodsOnlyByLinks() throws {
        XCTAssertEqual(Donate.methods(try XCTUnwrap(parse("{}"))), [])
        XCTAssertEqual(Donate.methods(try XCTUnwrap(parse(#"{"instagram":"_elvis.kz_"}"#))), [])
        let kaspiOnly = try XCTUnwrap(parse(#"{"kaspi":"https://pay.kaspi.example/pimp"}"#))
        XCTAssertEqual(Donate.methods(kaspiOnly), [.kaspi])
        let cryptoOnly = try XCTUnwrap(parse(#"{"crypto":[{"coin":"BTC","network":"Bitcoin","address":"bc1"}]}"#))
        XCTAssertEqual(Donate.methods(cryptoOnly), [.crypto])
        let apOnly = try XCTUnwrap(parse(#"{"applePay":"https://pay.example/ap"}"#))
        XCTAssertEqual(Donate.methods(apOnly), [.applePay])
        let mixed = try XCTUnwrap(parse(#"{"kaspi":"https://k.example/p","card":"https://c.example/p","applePay":"ftp://x"}"#))
        XCTAssertEqual(Donate.methods(mixed), [.card, .kaspi])
        XCTAssertTrue(Donate.showsAmounts(try XCTUnwrap(parse(#"{"kaspi":"https://k.example/p?sum={amount}"}"#))))
    }

    /// Instagram «_elvis.kz_» (#9394): подчёркивания по краям — часть имени, ссылка с ними не ломается.
    func testInstagramHandleKeepsUnderscores() throws {
        XCTAssertEqual(Donate.instagramHandle("_elvis.kz_"), "_elvis.kz_")
        XCTAssertEqual(Donate.instagramHandle("  @_elvis.kz_ "), "_elvis.kz_")
        XCTAssertEqual(Donate.instagramHandle("https://www.instagram.com/_elvis.kz_/?hl=ru"), "_elvis.kz_")
        XCTAssertEqual(Donate.instagramHandle("instagram.com/_elvis.kz_"), "_elvis.kz_")
        let url = try XCTUnwrap(Donate.instagramURL("_elvis.kz_"))
        XCTAssertEqual(url.absoluteString, "https://instagram.com/_elvis.kz_")
        XCTAssertEqual(url.host, "instagram.com")
        XCTAssertEqual(url.path, "/_elvis.kz_")
        XCTAssertEqual(url.lastPathComponent, "_elvis.kz_")
        // Чужая ссылка, пробелы, кириллица, слишком длинно, не строка — имени нет, ссылки в окне нет.
        XCTAssertNil(Donate.instagramHandle("https://evil.example/_elvis.kz_"))
        XCTAssertNil(Donate.instagramHandle("elvis kz"))
        XCTAssertNil(Donate.instagramHandle("элвис"))
        XCTAssertNil(Donate.instagramHandle(String(repeating: "a", count: 31)))
        XCTAssertNil(Donate.instagramHandle(""))
        XCTAssertNil(Donate.instagramHandle(nil))
        XCTAssertNil(parse(#"{"instagram":42}"#)?.instagram)
        XCTAssertEqual(parse(#"{"instagram":"@_elvis.kz_"}"#)?.instagram, "_elvis.kz_")
    }

    /// Счёт людей вместо шкалы денег (кадр 37.5): ячейки до ближайшей ступени 10, 25, 50, 100.
    func testFriendsSteps() {
        XCTAssertEqual(Donate.friends(0), Donate.Friends(cells: 10, filled: 0, note: "Пока никто — стань первым."))
        XCTAssertEqual(Donate.friends(7), Donate.Friends(cells: 10, filled: 7, note: "До ступени «10» — ещё 3."))
        XCTAssertEqual(Donate.friends(10), Donate.Friends(cells: 25, filled: 10, note: "Ступень «10» пройдена. До «25» — ещё 15."))
        XCTAssertEqual(Donate.friends(12), Donate.Friends(cells: 25, filled: 12, note: "Ступень «10» пройдена. До «25» — ещё 13."))
        XCTAssertEqual(Donate.friends(99), Donate.Friends(cells: 100, filled: 99, note: "Ступень «50» пройдена. До «100» — ещё 1."))
        XCTAssertEqual(Donate.friends(100), Donate.Friends(cells: 0, filled: 0, note: "Ступень «100» пройдена."))
        XCTAssertEqual(Donate.friends(187).cells, 0)
    }

    func testAmountTokenDecidesAmountsRowAndLink() throws {
        let config = try XCTUnwrap(parse(full))
        XCTAssertTrue(Donate.showsAmounts(config))
        XCTAssertEqual(Donate.payURL(config.applePay, amount: 5000)?.absoluteString, "https://pay.example/ap?amount=5000")
        XCTAssertNil(Donate.payURL(config.applePay, amount: 0))
        XCTAssertNil(Donate.payURL(config.applePay, amount: nil))
        let plain = try XCTUnwrap(parse(#"{"applePay":"https://pay.example/ap","card":"https://pay.example/c"}"#))
        XCTAssertFalse(Donate.showsAmounts(plain))
        XCTAssertEqual(Donate.payURL(plain.card, amount: nil)?.absoluteString, "https://pay.example/c")
        XCTAssertFalse(Donate.showsAmounts(try XCTUnwrap(parse(#"{"crypto":[{"address":"x"}]}"#))))
    }

    func testUsdByRate() {
        XCTAssertEqual(Donate.usd(1000, rate: 510), "≈ $2")
        XCTAssertEqual(Donate.usd(5000, rate: 510), "≈ $10")
        XCTAssertEqual(Donate.usd(10000, rate: 510), "≈ $20")
        XCTAssertEqual(Donate.usd(100, rate: 510), "≈ $1")
        XCTAssertEqual(Donate.usd(9_999_999, rate: 510), "≈ $19\u{00A0}608")
        XCTAssertNil(Donate.usd(1000, rate: nil))
        XCTAssertNil(Donate.usd(0, rate: 510))
        XCTAssertNil(parse(#"{"usdRate":0}"#)?.usdRate)
        XCTAssertNil(parse(#"{"usdRate":"510"}"#)?.usdRate)
    }

    func testGarbageFieldsFallBackQuietly() throws {
        XCTAssertNil(parse("не json"))
        XCTAssertNil(parse("42"))
        let config = try XCTUnwrap(parse(#"""
            {"goal":{"title":5,"hex":"красный","target":-3,"specs":"M5"},"raised":"много","people":-4,
             "amounts":[0,-5,"1000",2000,3000,4000,5000,99999999],"applePay":"javascript:alert(1)",
             "card":"file:///etc/passwd","kaspi":"kaspi://pay","crypto":"адрес","instagram":"<script>"}
            """#))
        XCTAssertEqual(config.people, 0)
        XCTAssertEqual(config.amounts, [2000, 3000, 4000])
        XCTAssertNil(config.applePay)
        XCTAssertNil(config.card)
        XCTAssertNil(config.kaspi)
        XCTAssertNil(config.instagram)
        XCTAssertTrue(config.crypto.isEmpty)
        XCTAssertFalse(Donate.hasAddress(config))
        XCTAssertEqual(parse(#"{"people":true}"#)?.people, 0)
        XCTAssertEqual(parse("{}")?.amounts, [1000, 5000, 10000])
    }

    func testTenge() {
        XCTAssertEqual(Donate.tenge(1_376_000), "1\u{00A0}376\u{00A0}000\u{00A0}₸")
        XCTAssertEqual(Donate.tenge(500), "500\u{00A0}₸")
        XCTAssertEqual(Donate.group(15000), "15\u{00A0}000")
    }

    func testReturnLinks() {
        XCTAssertEqual(Donate.parseReturn(URL(string: "pimpmyclaude://donate/thanks")!), .thanks)
        XCTAssertEqual(Donate.parseReturn(URL(string: "pimpmyclaude://donate/cancel")!), .cancel)
        XCTAssertEqual(Donate.parseReturn(URL(string: "PimpMyClaude://donate/thanks/")!), .thanks)
        XCTAssertNil(Donate.parseReturn(URL(string: "pimpmyclaude://donate/other")!))
        XCTAssertNil(Donate.parseReturn(URL(string: "https://donate/thanks")!))
        XCTAssertNil(Donate.parseReturn(URL(string: "pimpmyclaude://panel/thanks")!))
    }

    func testMenuHasDonateLastOnlyWhenGiven() {
        var config = MinimizeMenu.MenuConfig()
        XCTAssertFalse(MinimizeMenu.build(config: config).items.contains { $0.title == MenuModel.donateTitle })
        config.donate = {}
        let items = MinimizeMenu.build(config: config).items
        XCTAssertEqual(items.last?.title, MenuModel.donateTitle)
    }
}
