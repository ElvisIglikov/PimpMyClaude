import AppKit
import XCTest
@testable import ClaudeAX

// WF145: одно правило состояний status.md, замок «меню открыто», схемы живого фона в Swift.

final class StatusStatesWF145Tests: XCTestCase {
    /// Заголовки эталонных status.md (PimpMyClaude, Dictator, VkusnoffKz 08.10 ~23:00) и чужие формы правила.
    func testHeadingStatesOneRule() {
        let cases: [(String, PanelWorkflow.State)] = [
            ("1️⃣ Workflow ⏳ идёт", .running),
            ("2️⃣ Workflow 💭 идёт", .running),
            ("3️⃣ Workflow ✅ готово", .done),
            ("4️⃣ Workflow ✅ готово, выложено", .done),
            ("5️⃣ Workflow ⬜ запланирован", .planned),
            ("6️⃣ Workflow ❓ ждёт Элвиса", .waiting),
            ("7️⃣ Workflow ✋ ждёт", .waiting),
            ("8️⃣ Workflow ⚠️ глянь", .waiting),
            ("9️⃣ Workflow 🙋 ответь", .waiting),
            ("🔟 Workflow ⏸️ пауза", .waiting),
            ("1️⃣ Workflow 🛑 упал", .failed),
            ("2️⃣ Workflow ❌ стоп", .failed),
            ("3️⃣ Workflow 🟢 готов", .done),
            ("4️⃣ Workflow кодинг", .running),
            ("5️⃣ Workflow критика", .running),
            ("6️⃣ Workflow запланирован", .planned),
            ("7️⃣ Workflow впереди", .planned),
            ("8️⃣ Workflow ждёт Элвиса", .waiting),
            ("9️⃣ Workflow упал на гейте", .failed),
            ("1️⃣ Workflow", .planned),
        ]
        for (heading, state) in cases {
            XCTAssertEqual(PanelProjects.blockState(heading), state, heading)
        }
    }

    func testLiveHeadingCountsHourglassAsRunning() {
        XCTAssertTrue(StatusFeed.isLiveHeading("1️⃣ Workflow ⏳ идёт"), "⏳ — живой блок, его срез не режет")
        XCTAssertFalse(StatusFeed.isLiveHeading("2️⃣ Workflow ⬜ запланирован"))
        XCTAssertFalse(StatusFeed.isLiveHeading("3️⃣ Workflow ✅ готово"))
    }

    private func digest(_ text: String) -> DigestProject {
        let now = Date()
        return ProjectsDigest.project(folderName: "PimpMyClaude", status: PanelProjects.parse(text),
                                      updated: now.addingTimeInterval(-60), now: now, settings: nil)
    }

    /// Находка WF136: PimpMyClaude с одними ⏳ сводка звала «ждут».
    func testHourglassProjectGroupsAsRunning() {
        let item = digest("""
        # ⚪PimpMyClaude
        1️⃣ Workflow ✅ готово
        - о чём: раз
        2️⃣ Workflow ⏳ идёт
        - о чём: два
        - шаги 2 из 4
        3️⃣ Workflow ⬜ запланирован
        - о чём: три
        Ждёт Элвиса: глянуть полосу
        """)
        XCTAssertEqual(item.group, "идут")
        XCTAssertEqual(item.workflows.map { $0.state }, ["готово", "идёт", "впереди"])
    }

    /// «⬜ запланирован» — «впереди», не «ждёт Элвиса»: проект без строки «Ждёт Элвиса» — тихо.
    func testPlannedIsNotWaiting() {
        let item = digest("# Calm\n1️⃣ Workflow ✅ готово\n2️⃣ Workflow ⬜ запланирован\nЖдёт Элвиса: ничего\n")
        XCTAssertEqual(item.workflows.map { $0.state }, ["готово", "впереди"])
        XCTAssertEqual(item.group, "тихо")
        let waits = digest("# Hand\n1️⃣ Workflow ❓ ждёт Элвиса\n2️⃣ Workflow ⬜ запланирован\n")
        XCTAssertEqual(waits.workflows.map { $0.state }, ["ждёт", "впереди"])
        XCTAssertEqual(waits.group, "ждут")
    }

    /// Эталонные сводки 08.10: сколько каких Workflow (сверено с `pimp.py digest` на тех же файлах).
    func testReferenceProjectsCounts() {
        func text(_ heads: [(String, Int)]) -> String {
            var lines = ["# X"]
            var n = 0
            for (head, count) in heads {
                for _ in 0..<count { n += 1; lines.append("\(n % 10)️⃣ Workflow \(head)"); lines.append("- о чём: x") }
            }
            return lines.joined(separator: "\n")
        }
        func counts(_ text: String) -> [String: Int] {
            Dictionary(digest(text).workflows.map { ($0.state, 1) }, uniquingKeysWith: +)
        }
        XCTAssertEqual(counts(text([("✅ готово", 6), ("⏳ идёт", 5), ("⬜ запланирован", 1)])),
                       ["готово": 6, "идёт": 5, "впереди": 1])     // PimpMyClaude
        XCTAssertEqual(counts(text([("✅ готово", 17), ("💭 идёт", 4)])), ["готово": 17, "идёт": 4])  // Dictator
        XCTAssertEqual(counts(text([("✅ готово", 5), ("💭 идёт", 9), ("⬜ запланирован", 2)])),
                       ["готово": 5, "идёт": 9, "впереди": 2])     // VkusnoffKz
    }
}

final class MenuHoldWF145Tests: XCTestCase {
    private func hold() -> (MenuHold, () -> Void) {
        let hold = MenuHold()
        var timers: [() -> Void] = []
        hold.schedule = { _, work in timers.append(work) }
        return (hold, { let ready = timers; timers = []; ready.forEach { $0() } })
    }

    func testFocusWaitsForMenuToClose() {
        let (hold, tick) = hold()
        let menu = NSMenu(title: "жёлтая")
        var done: [Int] = []
        hold.run { done.append(0) }
        XCTAssertEqual(done, [0], "меню нет — сразу")
        hold.begin(menu)
        hold.run { done.append(1) }
        hold.run { done.append(2) }
        XCTAssertEqual(done, [0], "меню открыто — фокус ждёт")
        XCTAssertEqual(hold.pending, 2)
        hold.endMenu(menu, root: true)
        tick()
        XCTAssertEqual(done, [0, 1, 2], "после закрытия — по порядку")
        XCTAssertEqual(hold.pending, 0)
    }

    func testRootEndReleasesForgottenSubmenu() {
        let (hold, tick) = hold()
        let root = NSMenu(title: "у часов"), sub = NSMenu(title: "Схема")
        var done = false
        let center = NotificationCenter()           // свой центр: живые меню тестов не мешают
        hold.start(center: center)
        center.post(name: NSMenu.didBeginTrackingNotification, object: root)
        center.post(name: NSMenu.didBeginTrackingNotification, object: sub)
        hold.run { done = true }
        XCTAssertFalse(done)
        center.post(name: NSMenu.didEndTrackingNotification, object: root)
        tick()
        XCTAssertTrue(done, "конец корневого снимает и подменю, чей конец не пришёл")
    }

    func testPanelHoldsUntilClosed() {
        let (hold, tick) = hold()
        let panel = NSObject()
        var done = false
        hold.begin(panel)
        hold.run { done = true }
        tick()
        XCTAssertFalse(done, "панель ⌘B открыта — ждём")
        hold.end(panel)
        tick()
        XCTAssertTrue(done)
    }

    func testForgottenHolderExpires() {
        let (hold, tick) = hold()
        var clock: TimeInterval = 0
        hold.now = { clock }
        var done = false
        hold.begin(NSObject())
        hold.run { done = true }
        XCTAssertFalse(done)
        clock = MenuHold.maxHold + 1
        tick()
        XCTAssertTrue(done, "потерянный конец не запирает фокус навсегда")
    }

    func testDeferredQueueIsCapped() {
        let (hold, _) = hold()
        let menu = NSMenu(title: "m")
        hold.begin(menu)
        for _ in 0..<(MenuHold.maxDeferred + 5) { hold.run {} }
        XCTAssertEqual(hold.pending, MenuHold.maxDeferred)
    }
}

final class LookSchemeWF145Tests: XCTestCase {
    func testSchemeGoesLastAndOnlyWhenSet() {
        XCTAssertEqual(Look(aurora: true).commandValue.json, "{\"aurora\":true,\"neon\":false,\"dense\":false}")
        XCTAssertEqual(Look(aurora: true, scheme: "sea").commandValue.json,
                       "{\"aurora\":true,\"neon\":false,\"dense\":false,\"scheme\":\"sea\"}")
    }

    func testWithSchemeTurnsLiveBackgroundOnAndDropsDefault() {
        let look = Look(dense: true).withScheme("forest")
        XCTAssertEqual(look, Look(aurora: true, dense: true, scheme: "forest"))
        XCTAssertNil(look.withScheme(LookScheme.defaultID).scheme, "умолчание ключом не пишется")
        XCTAssertNil(look.withScheme("кислота").scheme, "чужой id — умолчание")
        XCTAssertEqual(look.withScheme("violet").schemeID, "violet")
    }

    func testSchemeSurvivesDefaultsProjectFileAndThemeMap() throws {
        let suite = "wf145-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ThemeStore(defaults: defaults)
        store.setAllLook(Look(aurora: true, scheme: "lavender"))
        XCTAssertEqual(store.allLook.scheme, "lavender")
        store.setWindowLook(Look(aurora: true, scheme: "sunset"), title: "c:chat")
        XCTAssertEqual(store.windowLook(title: "c:chat").scheme, "sunset")

        let settings = ProjectSettings.parse(object: ["look": ["aurora": true, "scheme": "graphite"]])
        guard case .set(let look) = settings.look else { return XCTFail("слой look потерян") }
        XCTAssertEqual(look.scheme, "graphite")
        XCTAssertEqual(Look.from(["aurora": true, "scheme": "мусор"])?.scheme, nil)

        // window-themes.json хранит запись страницы как есть, порядок ключей — контракта.
        let raw: [String: Any] = ["scheme": "sea", "dense": false, "aurora": true, "neon": false]
        XCTAssertEqual(WindowThemeStore.value(from: raw, field: "look")?.json,
                       "{\"aurora\":true,\"neon\":false,\"dense\":false,\"scheme\":\"sea\"}")
    }

    func testMenuSchemeItemsCheckCurrentAndApplyLiveBackground() throws {
        var config = MinimizeMenu.MenuConfig()
        config.windowLook = Look(aurora: true, scheme: "sea")
        var applied: [Look] = []
        config.apply = { _, _, _, _, _, look in if case .set(let value) = look { applied.append(value) } }
        let item = MinimizeMenu.schemeItem(config, scope: "window")
        let items = try XCTUnwrap(item.submenu?.items)
        XCTAssertEqual(items.map { $0.title }, LookScheme.all.map { $0.name })
        XCTAssertEqual(items.filter { $0.state == .on }.map { $0.title }, ["Глубокое море"])
        let forest = try XCTUnwrap(items.first { $0.title == "Лес" })
        _ = (forest.target as? NSObject)?.perform(forest.action, with: forest)
        XCTAssertEqual(applied, [Look(aurora: true, scheme: "forest")])

        var off = MinimizeMenu.MenuConfig()
        off.windowLook = Look(dense: true)
        let none = try XCTUnwrap(MinimizeMenu.schemeItem(off, scope: "window").submenu?.items)
        XCTAssertTrue(none.allSatisfy { $0.state == .off }, "живой фон выключен — галки нет")
    }

    func testLookItemsCarrySchemeSubmenuUnderLiveBackground() throws {
        let items = MinimizeMenu.lookItems(MinimizeMenu.MenuConfig(), scope: MenuModel.themeScopeAll)
        let lab = try XCTUnwrap(items.last?.submenu?.items.map { $0.title })
        let live = try XCTUnwrap(lab.firstIndex(of: MenuModel.lookAuroraTitle))
        XCTAssertEqual(lab[live + 1], MenuModel.lookSchemeTitle)
    }

    /// Сверка с `LOOK_SCHEMES` страницы (по образцу `testCommandContractMatchesInjectJS`): ids, имена, тона, порядок.
    func testSchemesMatchInjectJS() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let inject = try String(contentsOf: root.appendingPathComponent("claude-patch/inject.js"), encoding: .utf8)
        guard let start = inject.range(of: "const LOOK_SCHEMES = [") else {
            throw XCTSkip("в этой ветке страница ещё без схем (WF146) — сверка оживёт после слияния")
        }
        let tail = inject[start.upperBound...]
        let body = String(tail[..<(tail.range(of: "];")?.lowerBound ?? tail.endIndex)])
        let pattern = try NSRegularExpression(
            pattern: #"\{\s*id:\s*"([^"]+)",\s*name:\s*"([^"]+)",\s*tones:\s*(null|\[[^\]]*\])\s*\}"#)
        let page: [LookScheme] = pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)).map { match in
            let part = { (i: Int) in String(body[Range(match.range(at: i), in: body)!]) }
            let tones = part(3) == "null" ? nil : part(3).components(separatedBy: "\"")
                .filter { $0.hasPrefix("#") }
            return LookScheme(id: part(1), name: part(2), tones: tones)
        }
        XCTAssertEqual(page, LookScheme.all)
        XCTAssertTrue(inject.contains("LOOK_SCHEME_DEFAULT = \"\(LookScheme.defaultID)\""))
    }
}
