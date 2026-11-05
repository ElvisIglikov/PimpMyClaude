@testable import ClaudeAX
import XCTest

/// #9820: «Не напоминать» у «Ждёт тебя». Ключ (папка + SHA1 текста), разбор файла, сроки и их истечение, фильтр снимка
/// панели (значок у часов), `/digest` и сводки для полоски; файл 0600 и снятие записи.
final class MutedWaits9820Tests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    private let limit = "Постоянный лимит 99 %, доплата или ждём пятницы"

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("muted-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    @discardableResult
    private func status(_ name: String, _ text: String) throws -> URL {
        let docs = root.appendingPathComponent(name, isDirectory: true).appendingPathComponent("docs", isDirectory: true)
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        let file = docs.appendingPathComponent("status.md")
        try Data(text.utf8).write(to: file)
        return file
    }

    private func folder(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    /// Rick: только «Ждёт Элвиса:», ничего не идёт. Shop: блок ✋ и своя строка «Ждёт Элвиса:».
    private func twoProjects(rickWait: String? = nil) throws {
        try status("Rick", "# 🧠Rick\n\nЖдёт Элвиса: \(rickWait ?? limit)\n")
        try status("Shop", "# Shop\n\n1️⃣ Workflow ✋ ждёт\n- о чём: оплата\n- 10:00 → 10:40\n\nЖдёт Элвиса: «да» на выкладку\n")
    }

    private func snapshot(_ muted: MutedWaits? = nil, now: Date = Date()) -> PanelSnapshot {
        PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: now, muted: muted)
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: ключ

    func testKeyIsFolderAndTextHash() {
        let a = MutedWaits.key(folder: "/p/Rick", text: limit)
        XCTAssertTrue(a.hasPrefix("/p/Rick|"))
        XCTAssertEqual(a.split(separator: "|").last?.count, 40, "SHA1 — 40 знаков hex")
        XCTAssertEqual(a, MutedWaits.key(folder: "/p/Rick/", text: "  " + limit + " "), "края и вид пути не важны")
        XCTAssertEqual(a, MutedWaits.key(folder: URL(fileURLWithPath: "/p/x/../Rick"), text: limit))
        XCTAssertNotEqual(a, MutedWaits.key(folder: "/p/Rick", text: limit + "!"), "новый текст — новый ключ")
        XCTAssertNotEqual(a, MutedWaits.key(folder: "/p/Shop", text: limit))
    }

    /// Один проект через три пути (снимок панели, `/digest`, сводка для полоски) — один ключ.
    func testOneKeyForPanelDigestAndFeed() throws {
        try twoProjects()
        let rick = try XCTUnwrap(snapshot().waiting.first { $0.name == "Rick" })
        let muted = MutedWaits().muting(MutedWaits.key(folder: rick.folder, text: rick.waitFor), until: nil, now: Date())
        XCTAssertNil(snapshot(muted).waiting.first { $0.name == "Rick" }, "панель")
        let digest = try XCTUnwrap(ProjectsDigest.projects(root: root, now: Date(), settings: { _ in nil }, muted: muted))
        XCTAssertNil(digest.first { $0.name == "Rick" }?.wait, "/digest")
        let feed = StatusFeed.scan(root: root, muted: muted)
        XCTAssertFalse(try XCTUnwrap(feed.first { $0.name == "Rick" }).text.contains("Ждёт Элвиса"), "полоска")
    }

    // MARK: файл

    func testParseBrokenFileIsEmpty() {
        XCTAssertEqual(MutedWaits.parse(nil), .empty)
        XCTAssertEqual(MutedWaits.parse(Data("не json".utf8)), .empty)
        XCTAssertEqual(MutedWaits.parse(Data(#"{"version":2,"muted":[{"key":"/a|b","until":null}]}"#.utf8)), .empty,
                       "чужая версия")
        XCTAssertEqual(MutedWaits.parse(Data(#"{"version":1}"#.utf8)), .empty)
    }

    func testParseSkipsJunkAndRoundTrips() throws {
        let raw = #"""
        {"version":1,"muted":[
          {"key":"/p/Rick|aa","until":null,"at":"2026-10-19T10:00:00.000Z"},
          {"key":"/p/Shop|bb","until":"2026-10-20T06:00:00Z","at":"2026-10-19T10:00:00Z"},
          {"key":"без черты","until":null},
          {"key":"/p/X|cc","until":"вчера"},
          {"key":"/p/Y|dd","until":42},
          "мусор"
        ]}
        """#
        let parsed = MutedWaits.parse(Data(raw.utf8))
        XCTAssertEqual(parsed.items.map(\.key), ["/p/Rick|aa", "/p/Shop|bb"])
        XCTAssertNil(parsed.items[0].until)
        XCTAssertEqual(parsed.items[1].until, ISO8601DateFormatter().date(from: "2026-10-20T06:00:00Z"))
        XCTAssertEqual(MutedWaits.parse(parsed.encode()), parsed)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: parsed.encode()) as? [String: Any])
        XCTAssertEqual(body["version"] as? Int, 1)
        let first = try XCTUnwrap((body["muted"] as? [[String: Any]])?.first)
        XCTAssertTrue(first["until"] is NSNull, "бессрочная — null")
    }

    // MARK: сроки

    func testUntilChoices() {
        let cal = calendar()
        let now = at(20, 23, 30)
        XCTAssertEqual(MutedWaits.until(.hour, now: now, calendar: cal), at(21, 0, 30))
        XCTAssertEqual(MutedWaits.until(.tomorrow, now: now, calendar: cal), at(21, 6, 0))
        XCTAssertEqual(MutedWaits.until(.tomorrow, now: at(20, 1, 0), calendar: cal), at(21, 6, 0),
                       "в 01:00 «до завтра» — тоже до 06:00 следующего календарного дня")
        XCTAssertEqual(MutedWaits.until(.week, now: now, calendar: cal), at(27, 23, 30))
        XCTAssertNil(MutedWaits.until(.textChange, now: now, calendar: cal))
    }

    func testExpiry() {
        let now = at(20, 12, 0)
        let muted = MutedWaits().muting("/p|a", until: at(20, 13, 0), now: now).muting("/p|b", until: nil, now: now)
        XCTAssertTrue(muted.isMuted("/p|a", now: at(20, 12, 59)))
        XCTAssertFalse(muted.isMuted("/p|a", now: at(20, 13, 0)), "срок вышел — пункт снова виден")
        XCTAssertTrue(muted.isMuted("/p|b", now: at(30, 12, 0)), "пока текст тот же")
        XCTAssertFalse(muted.isMuted("/p|c", now: now))
        XCTAssertEqual(muted.unmuting("/p|a").items.map(\.key), ["/p|b"])
        XCTAssertEqual(muted.muting("/p|a", until: nil, now: now).items.filter { $0.key == "/p|a" }.count, 1,
                       "та же строка — одна запись")
    }

    func testPrunedDropsExpiredOldAndOverLimit() {
        let now = at(20, 12, 0)
        let old = now.addingTimeInterval(-91 * 86_400)
        let muted = MutedWaits(items: [
            .init(key: "/p|expired", until: at(20, 11, 0), at: at(20, 10, 0)),
            .init(key: "/p|old", until: nil, at: old),
            .init(key: "/p|keep", until: nil, at: at(19, 10, 0)),
        ]).pruned(now: now)
        XCTAssertEqual(muted.items.map(\.key), ["/p|keep"])
        let many = MutedWaits(items: (0..<520).map { .init(key: "/p|\($0)", until: nil, at: now.addingTimeInterval(Double($0))) })
        let kept = many.pruned(now: now.addingTimeInterval(600))
        XCTAssertEqual(kept.items.count, MutedWaits.limit)
        XCTAssertTrue(kept.isMuted("/p|519", now: now), "свежие остаются")
        XCTAssertFalse(kept.isMuted("/p|0", now: now))
    }

    // MARK: снимок, значок, /digest, полоска

    func testSnapshotHidesMutedLineButKeepsWaitingBlock() throws {
        try twoProjects()
        let before = snapshot()
        XCTAssertEqual(Set(before.waiting.map(\.name)), ["Rick", "Shop"])
        XCTAssertTrue(PanelTiles.summary(PanelTiles.groups(before, now: Date())).contains("✋ 2"))

        let rick = MutedWaits.key(folder: folder("Rick"), text: limit)
        let shop = MutedWaits.key(folder: folder("Shop"), text: "«да» на выкладку")
        let muted = MutedWaits().muting(rick, until: nil, now: Date()).muting(shop, until: nil, now: Date())
        let after = snapshot(muted)
        XCTAssertEqual(after.waiting.map(\.name), ["Shop"], "Shop ждёт блоком ✋ — это состояние Workflow")
        let shopProject = try XCTUnwrap(after.waiting.first)
        XCTAssertEqual(shopProject.waitFor, "")
        XCTAssertEqual(shopProject.words, [])
        XCTAssertEqual(shopProject.note, "Workflow «оплата» ждёт тебя")
        let rickProject = try XCTUnwrap(after.others.first { $0.name == "Rick" })
        XCTAssertEqual(rickProject.waitFor, "")
        XCTAssertFalse(rickProject.waits)
        let summary = PanelTiles.summary(PanelTiles.groups(after, now: Date()))
        XCTAssertTrue(summary.contains("✋ 1"), summary)
        XCTAssertEqual(PanelProjects.loneWaits(after).map(\.name), [], "заглушённого нет и в строках «Ждёт тебя»")
    }

    func testChangedTextComesBack() throws {
        try twoProjects()
        let muted = MutedWaits().muting(MutedWaits.key(folder: folder("Rick"), text: limit), until: nil, now: Date())
        XCTAssertNil(snapshot(muted).waiting.first { $0.name == "Rick" })
        try twoProjects(rickWait: "лимит 99 %, ждём пятницы")
        let rick = try XCTUnwrap(snapshot(muted).waiting.first { $0.name == "Rick" }, "сменился текст — снова видно")
        XCTAssertEqual(rick.waitFor, "лимит 99 %, ждём пятницы")
    }

    func testExpiredMuteComesBack() throws {
        try twoProjects()
        let now = Date()
        let muted = MutedWaits().muting(MutedWaits.key(folder: folder("Rick"), text: limit),
                                        until: now.addingTimeInterval(3600), now: now)
        XCTAssertNil(snapshot(muted, now: now).waiting.first { $0.name == "Rick" })
        XCTAssertNotNil(snapshot(muted, now: now.addingTimeInterval(3601)).waiting.first { $0.name == "Rick" })
    }

    func testDigestWaitIsEmpty() throws {
        try twoProjects()
        let muted = MutedWaits()
            .muting(MutedWaits.key(folder: folder("Rick"), text: limit), until: nil, now: Date())
            .muting(MutedWaits.key(folder: folder("Shop"), text: "«да» на выкладку"), until: nil, now: Date())
        let plain = try XCTUnwrap(ProjectsDigest.projects(root: root, now: Date(), settings: { _ in nil }))
        XCTAssertEqual(plain.first { $0.name == "Rick" }?.wait, limit)
        XCTAssertEqual(plain.first { $0.name == "Rick" }?.group, "ждут")
        let quiet = try XCTUnwrap(ProjectsDigest.projects(root: root, now: Date(), settings: { _ in nil }, muted: muted))
        let rick = try XCTUnwrap(quiet.first { $0.name == "Rick" })
        XCTAssertNil(rick.wait)
        XCTAssertEqual(rick.group, "тихо")
        let shop = try XCTUnwrap(quiet.first { $0.name == "Shop" })
        XCTAssertNil(shop.wait)
        XCTAssertEqual(shop.group, "ждут", "блок ✋ — всё ещё ждёт")
        let json = String(decoding: ProjectsDigest.json(ProjectsDigest.body(quiet, now: Date())), as: UTF8.self)
        XCTAssertFalse(json.contains(limit))
    }

    func testStatusFeedDropsMutedLine() throws {
        try twoProjects()
        let plain = StatusFeed.scan(root: root)
        XCTAssertTrue(try XCTUnwrap(plain.first { $0.name == "Rick" }).text.contains("Ждёт Элвиса: " + limit))
        let muted = MutedWaits().muting(MutedWaits.key(folder: folder("Rick"), text: limit), until: nil, now: Date())
        let quiet = StatusFeed.scan(root: root, muted: muted)
        XCTAssertFalse(try XCTUnwrap(quiet.first { $0.name == "Rick" }).text.contains("Ждёт Элвиса"))
        XCTAssertTrue(try XCTUnwrap(quiet.first { $0.name == "Shop" }).text.contains("Ждёт Элвиса"), "чужое не трогаем")
        XCTAssertNotEqual(StatusFeed.digest(plain), StatusFeed.digest(quiet), "сводка уйдёт заново")
        XCTAssertEqual(StatusFeed.compact("# A\nЖдёт Элвиса: x\n1️⃣ Workflow ✅\n- о чём: y", dropWait: true),
                       "# A\n1️⃣ Workflow ✅\n- о чём: y")
    }

    func testLoneWaits() throws {
        try twoProjects()
        let lone = PanelProjects.loneWaits(snapshot())
        XCTAssertEqual(Set(lone.map(\.name)), ["Rick", "Shop"], "ничего не идёт — у обоих своя строка")
        let rick = try XCTUnwrap(lone.first { $0.name == "Rick" })
        let hidden = PanelProjects.loneWaits(snapshot(), hidden: [MutedWaits.key(folder: rick.folder, text: rick.waitFor)])
        XCTAssertEqual(hidden.map(\.name), ["Shop"])
    }

    // MARK: файл на диске

    func testStoreWritesPrivateFileAndUnmutes() throws {
        let file = root.appendingPathComponent("MyClaude", isDirectory: true).appendingPathComponent(MutedWaits.fileName)
        let store = MutedWaitsStore(file: file)
        XCTAssertEqual(store.current(), .empty, "нет файла — всё напоминается")
        XCTAssertTrue(store.mute("/p/Rick|aa", until: nil))
        let mode = try XCTUnwrap(fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue & 0o777, 0o600)
        XCTAssertTrue(MutedWaits.parse(try Data(contentsOf: file)).isMuted("/p/Rick|aa", now: Date()))
        XCTAssertTrue(MutedWaitsStore(file: file).current().isMuted("/p/Rick|aa", now: Date()), "второй читатель видит")
        XCTAssertTrue(store.unmute("/p/Rick|aa"))
        XCTAssertFalse(store.current().isMuted("/p/Rick|aa", now: Date()))
        XCTAssertFalse(MutedWaits.parse(try Data(contentsOf: file)).isMuted("/p/Rick|aa", now: Date()))
    }

    func testStoreRereadsChangedFileAndReportsWriteFailure() throws {
        let file = root.appendingPathComponent(MutedWaits.fileName)
        let store = MutedWaitsStore(file: file)
        XCTAssertTrue(store.mute("/p|a", until: nil))
        try MutedWaits().muting("/p|bbbb", until: nil, now: Date()).encode().write(to: file)
        XCTAssertEqual(store.current().items.map(\.key), ["/p|bbbb"], "файл сменили снаружи — перечитан")
        // Папка — обычный файл: записать нельзя, в памяти всё как было.
        let blocker = root.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let broken = MutedWaitsStore(file: blocker.appendingPathComponent(MutedWaits.fileName))
        XCTAssertFalse(broken.mute("/p|a", until: nil))
        XCTAssertEqual(broken.current(), .empty)
    }

    func testUndoPlateWords() {
        let at = Date()
        let undo = WaitUndo(key: "/p|a", folder: "/p", choice: .tomorrow, at: at, failed: false, inCard: true)
        XCTAssertEqual(undo.left(now: at), 5)
        XCTAssertEqual(undo.left(now: at.addingTimeInterval(4.2)), 1)
        XCTAssertEqual(undo.left(now: at.addingTimeInterval(5)), 0)
        XCTAssertEqual(undo.text, "Не буду напоминать до завтра")
        XCTAssertEqual(WaitUndo(key: "", folder: "", choice: .hour, at: at, failed: true, inCard: false).text,
                       "Не вышло записать — напоминание осталось")
    }
}
