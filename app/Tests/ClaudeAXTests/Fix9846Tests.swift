import XCTest
@testable import ClaudeAX

/// #9846: карточка «Работают N терминалов» показала «Сейчас:» сводки от 11.10 как живое, а сайт — двумя строками.
/// Класс: всё, что панель и `/digest` берут из сводки проектов, — со свежестью, и одна сессия терминала — одна строка.
final class Fix9846Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fix9846-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func project(_ name: String, _ status: String?, age: TimeInterval = 60) throws {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("docs"), withIntermediateDirectories: true)
        guard let status = status else { return }
        let file = folder.appendingPathComponent("docs/status.md")
        try status.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
    }

    private func digest(_ terminals: Set<String>) -> [DigestProject] {
        let store = ProjectSettingsStore(registryURL: root.appendingPathComponent("no-registry.json"))
        return ProjectsDigest.projects(root: root, now: now, settings: { store.settings(in: $0) },
                                       terminals: terminals) ?? []
    }

    private static let site = """
    # 🟠VkusnoffKz
    1️⃣ Workflow 💭 идёт
    - о чём: корзина
    Сейчас: Курочка 3.0 продаётся, первый заказ гостью сверен в кассе.
    Ждёт Элвиса: «да» баннеру.
    """

    // MARK: свежесть

    func testStaleNowIsNotShownAsNow() throws {
        try project("Fresh", Self.site.replacingOccurrences(of: "VkusnoffKz", with: "Fresh"), age: 3600)
        try project("Day", Self.site.replacingOccurrences(of: "VkusnoffKz", with: "Day"), age: 2 * 86_400)
        try project("Week", Self.site.replacingOccurrences(of: "VkusnoffKz", with: "Week"), age: 8 * 86_400)
        let items = Dictionary(uniqueKeysWithValues: digest(["Fresh", "Day", "Week"]).map { ($0.name, $0) })

        XCTAssertEqual(items["Fresh"]?.now, "Курочка 3.0 продаётся, первый заказ гостью сверен в кассе.")
        XCTAssertEqual(items["Fresh"]?.wait, "«да» баннеру.")
        // Двое суток: «Сейчас:» уже не сейчас; «Ждёт Элвиса:» ещё держится, как в разделе «Ждут тебя».
        XCTAssertNil(items["Day"]?.now)
        XCTAssertEqual(items["Day"]?.wait, "«да» баннеру.")
        XCTAssertEqual(items["Day"]?.group, "ждут")
        // Старше недели — ни «сейчас», ни «ждёт»; терминал жив — строка остаётся, без старого текста.
        XCTAssertNil(items["Week"]?.now)
        XCTAssertNil(items["Week"]?.wait)
        XCTAssertEqual(items["Week"]?.group, "тихо")
        XCTAssertEqual(items["Week"]?.terminal, true)
    }

    func testPanelSnapshotUsesTheSameFreshness() throws {
        try project("Old", Self.site.replacingOccurrences(of: "VkusnoffKz", with: "Old"), age: 13 * 3600)
        try project("New", Self.site.replacingOccurrences(of: "VkusnoffKz", with: "New"), age: 600)
        let snapshot = PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: now)
        let all = snapshot.working + snapshot.waiting + snapshot.others
        XCTAssertEqual(all.first { $0.name == "Old" }?.now, "", "сводка старше 12 ч — «Сейчас:» не показываем")
        XCTAssertEqual(all.first { $0.name == "New" }?.now, "Курочка 3.0 продаётся, первый заказ гостью сверен в кассе.")
    }

    func testFreshHelpers() {
        var status = PanelStatus()
        status.now = "идёт"
        status.waitFor = "ничего"
        XCTAssertEqual(PanelProjects.freshNow(status, age: PanelProjects.runFreshSeconds), "идёт")
        XCTAssertEqual(PanelProjects.freshNow(status, age: PanelProjects.runFreshSeconds + 1), "")
        XCTAssertEqual(PanelProjects.freshWait(status, age: 0), "", "«ничего» — не ждёт")
        status.waitFor = "«да»"
        XCTAssertEqual(PanelProjects.freshWait(status, age: PanelProjects.waitFreshSeconds), "«да»")
        XCTAssertEqual(PanelProjects.freshWait(status, age: .infinity), "")
    }

    // MARK: одна сессия — одна строка

    func testSessionGoesToFolderOfTheSameNameOnly() throws {
        // Папка проекта без сводки и вторая папка со сводкой того же имени — сессия одна, строка одна.
        try project("VkusnoffKz", nil)
        try project("VkusnoffSite", Self.site)
        let items = digest(["VkusnoffKz"])
        XCTAssertEqual(items.filter { $0.terminal == true }.map { $0.name }, ["VkusnoffKz"])
        XCTAssertEqual(items.first { $0.name == "VkusnoffSite" }?.terminal, false)
        XCTAssertEqual(items.filter { $0.terminal == true }.count, 1, "«Работает 1 терминал», не два")
    }

    func testWithoutSuchFolderTheFreshestSummaryOfThatNameOwnsTheSession() throws {
        try project("SiteOld", Self.site, age: 5 * 3600)
        try project("SiteNew", Self.site, age: 600)
        let items = digest(["vkusnoffkz"])
        XCTAssertEqual(items.filter { $0.terminal == true }.map { $0.name }, ["SiteNew"])
    }

    func testOwnersHelper() {
        let early = now.addingTimeInterval(-600), late = now
        let candidates: [(key: String, folder: String, name: String, updated: Date?)] = [
            ("/a", "Copy", "Site", late), ("/b", "Site", "Site", early), ("/c", "Other", "Shop", early),
            ("/d", "Shop2", "Shop", late), ("/e", "Blank", "", nil),
        ]
        XCTAssertEqual(PanelTiles.terminalOwners(candidates, sessions: ["site", "SHOP", "nobody"]), ["/b", "/d"])
        XCTAssertEqual(PanelTiles.terminalOwners(candidates, sessions: []), [])
    }

    func testPanelTilesGiveTheSessionToOneTile() {
        func make(_ folder: String, _ name: String, updated: Date) -> PanelProject {
            PanelProject(folder: folder, name: name, marker: "", isMain: false, updated: updated, now: "",
                         words: [], note: "", waits: false, running: [])
        }
        var snapshot = PanelSnapshot(waiting: [], working: [],
                                     others: [make("/p/VkusnoffKz", "VkusnoffKz", updated: now.addingTimeInterval(-60)),
                                              make("/p/VkusnoffSite", "VkusnoffKz", updated: now)])
        snapshot.terminals = ["VkusnoffKz"]
        let tiles = PanelTiles.groups(snapshot, now: now).flatMap { $0.tiles }
        XCTAssertEqual(tiles.map { $0.folder }, ["/p/VkusnoffKz"])
        XCTAssertEqual(tiles.first?.phase, "чат в терминале")
    }
}
