import AppKit
import CoreGraphics
import XCTest
@testable import ClaudeAX

/// Приложение под каналом «Пимп»: окна, проекты и расстановка живут в памяти теста —
/// ни AX, ни живого Claude каналу для проверки не нужно.
private final class PimpRig {
    /// Рабочая область «экрана»: ровно 1470×859 от 34 сверху — как у Элвиса на 15".
    static let area = CGRect(x: 0, y: 34, width: 1470, height: 859)

    var now = PimpChannel.date("2026-09-07T11:20:00Z")!
    var running = true
    var windows: [PimpWindow] = []
    var minimized = 0
    /// Зазор между окнами на «экране» стенда. По умолчанию 0 — эталоны канала и старые
    /// рамки остаются побайтно теми же; тесты зазора ставят свой.
    var gap: CGFloat = 0
    var projects: [Project] = []
    var titles: [String: String] = [:]
    var layers = true

    var opened: [(project: Project, origin: (x: Int, y: Int)?)] = []
    var arranged: [[CGWindowID]] = []
    /// Умные расстановки (план WF77): чьи окна и был ли порядок навязан. Плитку этот путь
    /// не трогает — по `layouts` видно, что она осталась прежней.
    var smart: [(ids: [CGWindowID], ordered: Bool)] = []
    /// Раскладки, с которыми звали «Расставить» (план WF21), и последняя выбранная.
    var layouts: [ArrangeLayout.Mode] = []
    var mode = ArrangeLayout.Mode.ribbon
    var fits = true
    var moved: [PimpMove] = []
    /// Расстановка не переставила ни одного окна: окна закрылись между снимком и вызовом
    /// (или экрана не нашлось) — приложение отдаёт пустой список (#5680).
    var arrangeMisses = false
    /// Плашки «Пимпа» для Элвиса: у работы из МЕНЮ ответа нет, итог уходит сюда (#5689).
    var notices: [String] = []

    /// Раскладки проектов (план WF41): файл-в-памяти, заголовок главного окна и просьбы
    /// «вынеси этот чат отдельным окном».
    var saved: [WindowLayout] = []
    var canSave = true
    var mainTitle = "Claude"
    var popouts: [(chat: String, name: String, origin: (x: Int, y: Int))] = []

    /// Голосовой Пимп (план WF75): поднятые и закрытые окна, окно в фокусе, вставки и
    /// последний чат каждой папки.
    var raised: [CGWindowID] = []
    var closed: [CGWindowID] = []
    var canClose = true
    /// Окно Claude в фокусе, когда Claude впереди; nil — Claude позади (тогда `front:true`
    /// вставлять не должен вовсе).
    var front: CGWindowID?
    var pastes: [(id: CGWindowID, paths: [String])] = []
    /// Нажали ли ⌘V: false — окно пропало между выбором и нажатием.
    var pasteWorks = true
    /// Последний чат папки: путь → чат и его заголовок (у приложения это `ProjectIndex`).
    var lastChats: [String: (chat: String, title: String)] = [:]

    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    func window(_ id: CGWindowID) -> PimpWindow? { windows.first { $0.id == id } }

    func seats() -> PimpSeats {
        PimpSeats(
            claudeRunning: { [unowned self] in self.running },
            windows: { [unowned self] in self.windows },
            minimized: { [unowned self] in self.minimized },
            projects: { [unowned self] in self.projects },
            openNewWindow: { [unowned self] project, origin in
                self.opened.append((project: project, origin: origin))
            },
            arrange: { [unowned self] ids, mode, _ in self.arrange(ids, mode) },
            arrangeSmart: { [unowned self] ids, ordered, _ in self.arrangeSmart(ids, ordered) },
            arrangeMode: { [unowned self] in self.mode },
            fitsLayout: { [unowned self] _ in self.fits },
            place: { [unowned self] moves in self.place(moves) },
            titleForChat: { [unowned self] chat in self.titles[chat] },
            newWindowLayers: { [unowned self] in self.layers },
            layouts: { [unowned self] in self.saved },
            saveLayout: { [unowned self] layout in
                guard self.canSave else { return false }
                self.saved = LayoutsStore.merge(layout, into: self.saved)
                return true
            },
            cells: { [unowned self] mode, count in
                ArrangeLayout.frames(count: count, in: PimpRig.area, mode: mode, gap: self.gap)
            },
            isMainWindow: { [unowned self] title in title == self.mainTitle },
            openChat: { [unowned self] chat, name, origin in
                self.popouts.append((chat: chat, name: name, origin: origin))
            },
            notice: { [unowned self] text in self.notices.append(text) },
            raise: { [unowned self] id in self.raised.append(id) },
            close: { [unowned self] id in
                guard self.canClose else { return false }
                self.closed.append(id)
                self.windows.removeAll { $0.id == id }
                return true
            },
            frontWindow: { [unowned self] in self.front },
            paste: { [unowned self] id, paths, done in
                self.pastes.append((id: id, paths: paths))
                done(self.pasteWorks)
            },
            lastChat: { [unowned self] folder in self.lastChats[folder.path] })
    }

    /// «Расставить»: та же арифметика, что в приложении, только окна двигаются в массиве.
    /// Ячеек меньше, чем окон, — хвост остаётся где стоял, как в `ClaudeActions`.
    private func arrange(_ ids: [CGWindowID],
                         _ mode: ArrangeLayout.Mode) -> (windows: [PimpWindow], skipped: Int) {
        arranged.append(ids)
        layouts.append(mode)
        self.mode = mode
        guard !arrangeMisses else { return (windows: [], skipped: 0) }
        let ordered = ids.compactMap { id in windows.first { $0.id == id } }
        let cells = ArrangeLayout.frames(count: ordered.count, in: PimpRig.area, mode: mode,
                                         gap: gap)
        var out: [PimpWindow] = []
        for (index, cell) in cells.enumerated() {
            let window = ordered[index]
            let placed = PimpWindow(id: window.id, title: window.title, chat: window.chat,
                                    folder: window.folder, frame: cell)
            out.append(placed)
            if let at = windows.firstIndex(where: { $0.id == window.id }) { windows[at] = placed }
        }
        return (windows: out, skipped: ordered.count - out.count)
    }

    /// Умная расстановка (план WF77): та же арифметика, что в приложении, на одном
    /// «экране» стенда. Плитку не трогаем вовсе, ячейка находится каждому окну.
    private func arrangeSmart(_ ids: [CGWindowID], _ ordered: Bool) -> [PimpWindow] {
        smart.append((ids: ids, ordered: ordered))
        guard !arrangeMisses else { return [] }
        let listed = ids.compactMap { id in windows.first { $0.id == id } }
        let placed = ArrangeLayout.smart(frames: listed.map { $0.frame }, in: PimpRig.area,
                                         minCellWidth: 280, gap: gap,
                                         order: ordered ? Array(listed.indices) : nil)
        var out: [PimpWindow] = []
        for (index, window) in listed.enumerated() {
            let moved = PimpWindow(id: window.id, title: window.title, chat: window.chat,
                                   folder: window.folder, frame: placed[index])
            out.append(moved)
            if let at = windows.firstIndex(where: { $0.id == window.id }) { windows[at] = moved }
        }
        return out
    }

    private func place(_ moves: [PimpMove]) {
        moved += moves
        for move in moves {
            guard let at = windows.firstIndex(where: { $0.id == move.id }) else { continue }
            let window = windows[at]
            windows[at] = PimpWindow(id: window.id, title: window.title, chat: window.chat,
                                     folder: window.folder, frame: move.frame)
        }
    }
}

/// Канал «Пимп» (план WF36, задача #5531): разбор запроса, сборка ответа, очередь на диске
/// и расстановка нового окна. Эталоны контракта — `tests/fixtures/pimp/*.json`, их читают
/// оба батча, поэтому тесты берут файлы прямо из репозитория.
final class PimpChannelTests: XCTestCase {
    // MARK: - песочница

    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pimp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Канал в песочнице с подставными сиденьями и часами.
    private func makeChannel(_ rig: PimpRig, in box: URL) -> PimpChannel {
        let channel = PimpChannel(directory: box, now: { rig.now })
        channel.seats = rig.seats()
        channel.start()
        return channel
    }

    /// Эталоны лежат в репозитории: `tests/fixtures/pimp/` от корня, путь считается от #filePath
    /// (app/Tests/ClaudeAXTests/…), чтобы тест не зависел от рабочего каталога.
    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp", isDirectory: true)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: PimpChannelTests.fixtures.appendingPathComponent(name))
    }

    private func fixtureText(_ name: String) throws -> String {
        try String(data: fixture(name), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func write(_ body: String, id: String, in box: URL) {
        try? Data(body.utf8).write(to: box.appendingPathComponent(id + ".json"))
    }

    /// Ответ канала как он лёг на диск — для побайтной сверки с эталоном.
    private func resultText(_ id: String, in box: URL) throws -> String {
        try String(contentsOf: box.appendingPathComponent(id + ".result.json"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func result(_ id: String, in box: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: box.appendingPathComponent(id + ".result.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private func request(_ id: String, action: String, at: Date, from: String = "",
                         extra: String = "") -> String {
        "{\"id\":\"\(id)\",\"at\":\"\(PimpChannel.stampText(at))\",\"action\":\"\(action)\","
            + "\"from\":\"\(from)\"\(extra)}"
    }

    private static func project(_ name: String, at: Double = 0) -> Project {
        Project(folder: URL(fileURLWithPath: "/Users/dev/Projects/\(name)",
                            isDirectory: true), name: name, lastFocusedAt: at)
    }

    // MARK: - 1. эталоны контракта: запрос

    func testPimpParsesFixtureRequests() throws {
        let open = try XCTUnwrap(PimpRequest.parse(fixture("new-window.request.json")))
        XCTAssertEqual(open.id, "1788780000000-0421")
        XCTAssertEqual(open.action, .newWindow)
        XCTAssertEqual(open.at, PimpChannel.date("2026-09-07T11:20:00Z"))
        XCTAssertEqual(open.from, "local_5265171a-0ab8-4472-b4e5-40604a36ef6e")
        XCTAssertEqual(open.project, "Dictator")
        XCTAssertEqual(open.place, .middle)

        for (name, action) in [("arrange.request.json", PimpRequest.Action.arrange),
                               ("projects.request.json", .projects),
                               ("windows.request.json", .windows)] {
            let parsed = try XCTUnwrap(PimpRequest.parse(fixture(name)), name)
            XCTAssertEqual(parsed.action, action, name)
            XCTAssertEqual(parsed.from, "", name)
            // Поля `place` у этих запросов нет — умолчание «справа», а не отказ.
            XCTAssertEqual(parsed.place, .right, name)
            // `layout` — лента: у arrange он «row», у остальных поля нет вовсе (план WF21).
            XCTAssertEqual(parsed.layout, .ribbon, name)
        }

        // Раскладки (план WF21): свои слова, «last» — раскладку подставит приложение,
        // чужое слово — не запрос (`bad-request`).
        func arrange(_ layout: String) -> Data {
            let body = "{\"id\":\"1-1\",\"at\":\"2026-09-07T11:20:00Z\",\"action\":\"arrange\","
                + "\"from\":\"\",\"layout\":\"\(layout)\"}"
            return Data(body.utf8)
        }
        XCTAssertEqual(PimpRequest.parse(arrange("4"))?.layout, .four)
        XCTAssertEqual(PimpRequest.parse(arrange("5"))?.layout, .five)
        XCTAssertEqual(PimpRequest.parse(arrange("5x2"))?.layout, .tenGrid)
        XCTAssertNil(try XCTUnwrap(PimpRequest.parse(arrange(" LAST "))).layout)
        XCTAssertNil(PimpRequest.parse(arrange("5x3")), "чужая раскладка — bad-request")

        // Чужое действие — `bad-request` (эталон bad.request.json: "action":"fly").
        XCTAssertNil(PimpRequest.parse(try fixture("bad.request.json")))
        XCTAssertNil(PimpRequest.parse(Data("{".utf8)), "битый JSON — не запрос")
        XCTAssertNil(PimpRequest.parse(nil))
        // Без id ответ некому адресовать, без `at` не сказать, протух ли он.
        XCTAssertNil(PimpRequest.parse(Data("{\"id\":\"\",\"at\":\"2026-09-07T11:20:00Z\",\"action\":\"windows\"}".utf8)))
        XCTAssertNil(PimpRequest.parse(Data("{\"id\":\"1-1\",\"action\":\"windows\"}".utf8)))
        // «Новое окно» без папки бессмысленно.
        XCTAssertNil(PimpRequest.parse(Data("{\"id\":\"1-1\",\"at\":\"2026-09-07T11:20:00Z\",\"action\":\"new-window\",\"project\":\" \"}".utf8)))

        // Раскладки проектов (план WF41): порядок папок, список, запомнить, вернуть, сводка.
        let ordered = try XCTUnwrap(PimpRequest.parse(fixture("arrange-order.request.json")))
        XCTAssertEqual(ordered.action, .arrange)
        XCTAssertEqual(ordered.layout, .five)
        XCTAssertEqual(ordered.order, ["/Users/dev/Projects/VkusnoffKz", "SkilZZZ",
                                       "/Users/dev/Projects/Dictator"])
        // Поля `order` нет — nil, и ответ остаётся прежним (arrange.result.json).
        XCTAssertNil(try XCTUnwrap(PimpRequest.parse(fixture("arrange.request.json"))).order)

        let list = try XCTUnwrap(PimpRequest.parse(fixture("layouts.request.json")))
        XCTAssertEqual(list.action, .layouts)
        let save = try XCTUnwrap(PimpRequest.parse(fixture("layout-save.request.json")))
        XCTAssertEqual(save.action, .layoutSave)
        XCTAssertEqual(save.name, "Утро")
        let back = try XCTUnwrap(PimpRequest.parse(fixture("layout-restore.request.json")))
        XCTAssertEqual(back.action, .layoutRestore)
        XCTAssertEqual(back.name, "Утро")
        XCTAssertFalse(back.fresh)
        let status = try XCTUnwrap(PimpRequest.parse(fixture("projects-status.request.json")))
        XCTAssertEqual(status.action, .projects)
        XCTAssertTrue(status.status)
        // Поля `status` нет — сводку не просили.
        XCTAssertFalse(try XCTUnwrap(PimpRequest.parse(fixture("projects.request.json"))).status)
        // Раскладку без имени ни записать, ни найти — это bad-request.
        XCTAssertNil(PimpRequest.parse(Data("{\"id\":\"1-1\",\"at\":\"2026-09-08T03:20:30Z\",\"action\":\"layout-save\",\"name\":\" \"}".utf8)))
        XCTAssertNil(PimpRequest.parse(Data("{\"id\":\"1-1\",\"at\":\"2026-09-08T03:20:40Z\",\"action\":\"layout-restore\"}".utf8)))

        // Места: слова, точка (в том числе с долями — CLI их пропускает) и чужое слово.
        XCTAssertEqual(PimpRequest.place("left"), .left)
        XCTAssertEqual(PimpRequest.place("Above"), .above)
        XCTAssertEqual(PimpRequest.place("120,80"), .point(x: 120, y: 80))
        XCTAssertEqual(PimpRequest.place("120.6,-80.2"), .point(x: 121, y: -80))
        XCTAssertNil(PimpRequest.place("под этим"))
        XCTAssertNil(PimpRequest.place("120,80,40"))
    }

    // MARK: - 2. эталоны контракта: ответ

    func testPimpAnswersMatchFixtures() throws {
        let at = PimpChannel.date("2026-09-07T11:20:52Z")!
        XCTAssertEqual(PimpAnswer(id: "1788780050000-0666", at: at, ok: false,
                                  error: PimpChannel.Failure.badRequest.rawValue).json,
                       try fixtureText("bad.result.json"))
        XCTAssertEqual(PimpAnswer(id: "1788780040000-0555",
                                  at: PimpChannel.date("2026-09-07T11:20:40Z")!, ok: false,
                                  error: PimpChannel.Failure.busy.rawValue).json,
                       try fixtureText("busy.result.json"))

        // Порядок полей ответа: id, at, ok, error, fromResolved, screen, затем поля действия.
        let windows = [
            PimpWindow(id: 1, title: "Вкуснофф Workflow 01 проверки",
                       chat: "local_c17b778b-6c3d-40dc-9717-4c7d30baad35",
                       folder: "/Users/dev/Projects/VkusnoffKz",
                       frame: CGRect(x: 0, y: 34, width: 490, height: 859)),
            PimpWindow(id: 2, title: "Claude", chat: "local_5265171a-0ab8-4472-b4e5-40604a36ef6e",
                       folder: "/Users/dev/Projects/PimpMyClaude",
                       frame: CGRect(x: 490, y: 34, width: 490, height: 859)),
            PimpWindow(id: 3, title: "Диктаторик",
                       frame: CGRect(x: 980, y: 34, width: 490, height: 859)),
        ]
        // У «Расставить» свои поля (план WF21): раскладка, окна, пропущенные, свёрнутые.
        XCTAssertEqual(PimpAnswer(id: "1788780010000-0777",
                                  at: PimpChannel.date("2026-09-07T11:20:12Z")!, ok: true,
                                  fields: PimpChannel.arrangeFields(windows, mode: .ribbon,
                                                                    skipped: 0, minimized: 0)).json,
                       try fixtureText("arrange.result.json"))

        let list = [Project(folder: URL(fileURLWithPath: "/Users/dev/Projects/PimpMyClaude"),
                            name: "PimpMyClaude",
                            lastFocusedAt: ProjectsStore.milliseconds(
                                PimpChannel.date("2026-09-07T11:19:00Z")!)),
                    Project(folder: URL(fileURLWithPath: "/Users/dev/Projects/VkusnoffKz"),
                            name: "VkusnoffKz",
                            lastFocusedAt: ProjectsStore.milliseconds(
                                PimpChannel.date("2026-09-07T10:02:00Z")!))]
        XCTAssertEqual(PimpAnswer(id: "1788780020000-0102",
                                  at: PimpChannel.date("2026-09-07T11:20:22Z")!, ok: true,
                                  fields: [(key: "projects",
                                            value: .array(list.map { PimpChannel.projectValue($0) }))]).json,
                       try fixtureText("projects.result.json"))

        let one = [PimpWindow(id: 9, title: "Claude",
                              frame: CGRect(x: 993, y: 34, width: 477, height: 859))]
        XCTAssertEqual(PimpAnswer(id: "1788780030000-0300",
                                  at: PimpChannel.date("2026-09-07T11:20:32Z")!, ok: true,
                                  fields: PimpChannel.windowsFields(one, minimized: 1)).json,
                       try fixtureText("windows.result.json"))

        XCTAssertEqual(PimpAnswer(id: "1788780000000-0421",
                                  at: PimpChannel.date("2026-09-07T11:20:07Z")!, ok: true,
                                  fromResolved: true, fields: [
                                    (key: "window", value: .object([
                                        (key: "title", value: .string("Диктаторик")),
                                        (key: "chat", value: .string("local_9f1c2d3e-0000-4000-8000-000000000001")),
                                        (key: "frame", value: PimpChannel.frameValue(
                                            CGRect(x: 490, y: 34, width: 490, height: 859))),
                                    ])),
                                    (key: "layers", value: .string("ok")),
                                  ]).json,
                       try fixtureText("new-window.result.json"))

        XCTAssertEqual(PimpAnswer(id: "1788780000000-0422",
                                  at: PimpChannel.date("2026-09-07T11:21:03Z")!, ok: false,
                                  error: PimpChannel.Failure.projectMissing.rawValue,
                                  fields: [(key: "projects", value: .array(
                                    ["PimpMyClaude", "VkusnoffKz", "Dictator", "SkilZZZ"]
                                        .map { .string($0) }))]).json,
                       try fixtureText("new-window.error.json"))
    }

    // MARK: - 2а. эталоны контракта WF41: порядок проектов, раскладки, сводка

    func testPimpLayoutAnswersMatchFixtures() throws {
        // `arrange` с `order`: окна названных папок первыми, `unknown` и `missing` — ПОСЛЕ
        // `skipped` и только когда порядок просили.
        let byOrder = [
            PimpWindow(id: 1, title: "VkusnoffKz 3",
                       chat: "local_df06e2d9-3957-48d7-832e-b21a91c483da",
                       folder: "/Users/dev/Projects/VkusnoffKz",
                       frame: CGRect(x: 0, y: 34, width: 294, height: 860)),
            PimpWindow(id: 2, title: "Claude", chat: "local_e12ecb16-bd3f-41c5-9fa7-047b866ea3d6",
                       folder: "/Users/dev/Projects/PimpMyClaude",
                       frame: CGRect(x: 294, y: 34, width: 294, height: 860)),
            PimpWindow(id: 3, title: "Без папки",
                       frame: CGRect(x: 588, y: 34, width: 294, height: 860)),
        ]
        XCTAssertEqual(PimpAnswer(id: "1788790010000-0811",
                                  at: PimpChannel.date("2026-09-08T03:20:12Z")!, ok: true,
                                  fields: PimpChannel.arrangeFields(
                                    byOrder, mode: .five, skipped: 0, unknown: 1,
                                    missing: ["SkilZZZ", "/Users/dev/Projects/Dictator"],
                                    minimized: 0)).json,
                       try fixtureText("arrange-order.result.json"))

        // Список раскладок: имя, время, сетка и сколько в ней мест — свежие первыми.
        let morning = PimpChannelTests.layout("Утро", at: "2026-09-08T03:00:00Z", mode: .five, cells: 2)
        let review = PimpChannelTests.layout("Разбор", at: "2026-09-07T20:00:00Z", mode: .ribbon,
                                          cells: 3)
        XCTAssertEqual(PimpAnswer(id: "1788790020000-0102",
                                  at: PimpChannel.date("2026-09-08T03:20:21Z")!, ok: true,
                                  fields: PimpChannel.layoutsFields([morning, review])).json,
                       try fixtureText("layouts.result.json"))

        XCTAssertEqual(PimpAnswer(id: "1788790030000-0303",
                                  at: PimpChannel.date("2026-09-08T03:20:31Z")!, ok: true,
                                  fields: PimpChannel.layoutSaveFields(name: "Утро", mode: .five,
                                                                       cells: 2)).json,
                       try fixtureText("layout-save.result.json"))
        XCTAssertEqual(PimpAnswer(id: "1788790030000-0304",
                                  at: PimpChannel.date("2026-09-08T03:20:33Z")!, ok: false,
                                  error: PimpChannel.Failure.chatUnknown.rawValue,
                                  fields: [(key: "windows",
                                            value: .array([.string("Диктаторик")]))]).json,
                       try fixtureText("layout-save.error.json"))

        XCTAssertEqual(PimpAnswer(id: "1788790040000-0404",
                                  at: PimpChannel.date("2026-09-08T03:21:30Z")!, ok: true,
                                  fields: PimpChannel.restoreFields(name: "Утро", placed: 1,
                                                                    opened: 1,
                                                                    missing: ["Диктаторик"])).json,
                       try fixtureText("layout-restore.result.json"))
        XCTAssertEqual(PimpAnswer(id: "1788790040000-0405",
                                  at: PimpChannel.date("2026-09-08T03:21:40Z")!, ok: false,
                                  error: PimpChannel.Failure.layoutMissing.rawValue,
                                  fields: [(key: "layouts", value: .array(
                                    ["Утро", "Разбор"].map { .string($0) }))]).json,
                       try fixtureText("layout-restore.error.json"))

        // `projects` со сводкой: `chats` и `state` — ПОСЛЕ `lastUsed`.
        let pimp = Project(folder: URL(fileURLWithPath: "/Users/dev/Projects/PimpMyClaude"),
                           name: "PimpMyClaude",
                           lastFocusedAt: ProjectsStore.milliseconds(
                            PimpChannel.date("2026-09-08T03:19:00Z")!))
        let vkus = Project(folder: URL(fileURLWithPath: "/Users/dev/Projects/VkusnoffKz"),
                           name: "VkusnoffKz",
                           lastFocusedAt: ProjectsStore.milliseconds(
                            PimpChannel.date("2026-09-07T10:02:00Z")!))
        XCTAssertEqual(PimpAnswer(id: "1788790050000-0505",
                                  at: PimpChannel.date("2026-09-08T03:20:51Z")!, ok: true,
                                  fields: [(key: "projects", value: .array([
                                    PimpChannel.projectValue(
                                        pimp, chats: ["Claude"],
                                        state: "41 воркфлоу · 27 готово · Сейчас: WF21 кодится"),
                                    PimpChannel.projectValue(vkus, chats: ["VkusnoffKz 3"],
                                                             state: ""),
                                  ]))]).json,
                       try fixtureText("projects-status.result.json"))
    }

    /// Раскладка для эталонов: столько-то пустых мест под именем.
    private static func layout(_ name: String, at: String, mode: ArrangeLayout.Mode,
                               cells: Int) -> WindowLayout {
        WindowLayout(name: name, at: PimpChannel.date(at)!, mode: mode,
                     cells: (0..<cells).map {
                         LayoutCell(folder: "/tmp/p\($0)", chat: "local_\($0)",
                                    title: "Окно \($0)", cell: $0)
                     })
    }

    // MARK: - 2б. эталоны контракта WF75: последний чат, закрытие, вставка, плашка

    func testPimpParsesWF75Requests() throws {
        // «Последний чат проекта»: ключ `chat` стоит ПОСЛЕ `place` и знает одно слово.
        let last = try XCTUnwrap(PimpRequest.parse(fixture("new-window-last.request.json")))
        XCTAssertEqual(last.action, .newWindow)
        XCTAssertEqual(last.project, "TrelvisCom")
        XCTAssertEqual(last.place, .right)
        XCTAssertEqual(last.chat, "last")
        // Поля `chat` нет — прежнее «новое окно» (эталон WF36 остаётся собой).
        XCTAssertEqual(try XCTUnwrap(PimpRequest.parse(fixture("new-window.request.json"))).chat, "")
        XCTAssertNil(PimpRequest.parse(Data(("{\"id\":\"1-1\",\"at\":\"2026-09-19T19:00:00Z\","
            + "\"action\":\"new-window\",\"project\":\"X\",\"chat\":\"local_1\"}").utf8)),
                     "чужое значение chat — bad-request")

        let close = try XCTUnwrap(PimpRequest.parse(fixture("close-window.request.json")))
        XCTAssertEqual(close.action, .closeWindow)
        XCTAssertEqual(close.project, "TrelvisCom")
        XCTAssertNil(PimpRequest.parse(Data(("{\"id\":\"1-1\",\"at\":\"2026-09-19T19:00:10Z\","
            + "\"action\":\"close-window\",\"from\":\"\"}").utf8)), "без папки закрывать нечего")

        let paste = try XCTUnwrap(PimpRequest.parse(fixture("paste.request.json")))
        XCTAssertEqual(paste.action, .paste)
        XCTAssertTrue(paste.front)
        XCTAssertEqual(paste.paths, ["/Users/dev/Downloads/IMG_0001.jpeg",
                                     "/Users/dev/Downloads/IMG_0002.jpeg"])
        let clipboard = try XCTUnwrap(PimpRequest.parse(fixture("paste-clipboard.request.json")))
        XCTAssertFalse(clipboard.front)
        XCTAssertTrue(clipboard.paths.isEmpty, "без paths вставляем то, что в буфере")
        XCTAssertEqual(clipboard.project, "VkusnoffKz")
        func pasteBody(_ list: [String]) -> Data {
            let body = list.map { "\"\($0)\"" }.joined(separator: ",")
            return Data(("{\"id\":\"1-1\",\"at\":\"2026-09-19T19:00:20Z\",\"action\":\"paste\","
                + "\"from\":\"\",\"paths\":[\(body)]}").utf8)
        }
        XCTAssertNil(PimpRequest.parse(pasteBody(["Downloads/IMG_0001.jpeg"])), "путь не от корня")
        XCTAssertNil(PimpRequest.parse(pasteBody((1...21).map { "/tmp/\($0).jpg" })),
                     "больше двадцати")
        XCTAssertEqual(PimpRequest.parse(pasteBody((1...20).map { "/tmp/\($0).jpg" }))?.paths.count,
                       20)

        let hud = try XCTUnwrap(PimpRequest.parse(fixture("hud.request.json")))
        XCTAssertEqual(hud.action, .hud)
        XCTAssertEqual(hud.text, "Открыл 3 чата: VkusnoffKz, TrelvisCom, Dictator")
        XCTAssertNil(PimpRequest.parse(Data(("{\"id\":\"1-1\",\"at\":\"2026-09-19T19:00:30Z\","
            + "\"action\":\"hud\",\"text\":\"  \"}").utf8)), "плашка без слов — bad-request")
        // Длинную плашку обрезаем, а не отказываем: на экране всё равно строка.
        let long = String(repeating: "я", count: 260)
        XCTAssertEqual(PimpRequest.parse(Data(("{\"id\":\"1-1\",\"at\":\"2026-09-19T19:00:30Z\","
            + "\"action\":\"hud\",\"text\":\"\(long)\"}").utf8))?.text.count,
                       PimpChannel.hudTextLimit)

        // Урок #5682: чужие поля новые действия не роняют — `place` и `layout` разбирает
        // только тот, кому они адресованы.
        let noise = "{\"id\":\"1-1\",\"at\":\"2026-09-19T19:00:10Z\",\"action\":\"close-window\","
            + "\"from\":\"\",\"project\":\"X\",\"place\":\"под этим\",\"layout\":\"5x3\"}"
        XCTAssertEqual(PimpRequest.parse(Data(noise.utf8))?.action, .closeWindow)
    }

    func testPimpWF75AnswersMatchFixtures() throws {
        // Плашка отвечает без полей действия.
        XCTAssertEqual(PimpAnswer(id: "1789850030000-0401",
                                  at: PimpChannel.date("2026-09-19T19:00:30Z")!, ok: true).json,
                       try fixtureText("hud.result.json"))
        XCTAssertEqual(PimpAnswer(id: "1789850000000-0102",
                                  at: PimpChannel.date("2026-09-19T19:00:11Z")!, ok: false,
                                  error: PimpChannel.Failure.chatMissing.rawValue).json,
                       try fixtureText("new-window-last.error.json"))
        XCTAssertEqual(PimpAnswer(id: "1789850010000-0203",
                                  at: PimpChannel.date("2026-09-19T19:00:13Z")!, ok: false,
                                  error: PimpChannel.Failure.mainWindow.rawValue).json,
                       try fixtureText("close-window-main.error.json"))
        XCTAssertEqual(PimpAnswer(id: "1789850020000-0303",
                                  at: PimpChannel.date("2026-09-19T19:00:24Z")!, ok: false,
                                  error: PimpChannel.Failure.badRequest.rawValue).json,
                       try fixtureText("paste.error.json"))

        XCTAssertEqual(PimpAnswer(id: "1789850010000-0201",
                                  at: PimpChannel.date("2026-09-19T19:00:11Z")!, ok: true,
                                  fields: PimpChannel.closeFields("Дубли задач")).json,
                       try fixtureText("close-window.result.json"))
        XCTAssertEqual(PimpAnswer(id: "1789850020000-0301",
                                  at: PimpChannel.date("2026-09-19T19:00:21Z")!, ok: true,
                                  fields: PimpChannel.pasteFields(pasted: 2,
                                                                  window: "Сайт: корзина")).json,
                       try fixtureText("paste.result.json"))
        XCTAssertEqual(PimpAnswer(id: "1789850020000-0302",
                                  at: PimpChannel.date("2026-09-19T19:00:23Z")!, ok: true,
                                  fields: PimpChannel.pasteFields(pasted: 0,
                                                                  window: "Сайт: корзина")).json,
                       try fixtureText("paste-clipboard.result.json"))
        // «Не знаю, какое окно»: в `windows` — заголовки тех, между которыми выбирать.
        let two = [PimpWindow(id: 1, title: "Дубли задач"), PimpWindow(id: 2, title: "Бот: голос")]
        XCTAssertEqual(PimpChannel.ambiguous(id: "1789850010000-0202",
                                             at: PimpChannel.date("2026-09-19T19:00:12Z")!,
                                             windows: two).json,
                       try fixtureText("close-window.error.json"))
    }

    // MARK: - 3. место нового окна

    func testPimpInsertPlacesNewWindowInOrder() {
        // Одно окно было — новое слева/справа, «посередине» из двух окон это правее середины.
        XCTAssertEqual(ArrangeLayout.insert(order: [0], count: 1, at: 0), [1, 0])
        XCTAssertEqual(ArrangeLayout.insert(order: [0], count: 1, at: 1), [0, 1])
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 1), 1)

        // Два окна: «посередине» — ровно между ними.
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 2), 1)
        XCTAssertEqual(ArrangeLayout.insert(order: [1, 0], count: 2, at: 1), [1, 2, 0])
        // Три: середина одна.
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 3), 2)
        XCTAssertEqual(ArrangeLayout.insert(order: [0, 1, 2], count: 3, at: 2), [0, 1, 3, 2])
        // Четыре (после вставки пять — чётного числа середины нет, берём правее).
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 4), 2)
        XCTAssertEqual(ArrangeLayout.insert(order: [0, 1, 2, 3], count: 4, at: 2),
                       [0, 1, 4, 2, 3])
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .middle, count: 5), 3)
        XCTAssertEqual(ArrangeLayout.insert(order: [4, 3, 2, 1, 0], count: 5, at: 3),
                       [4, 3, 2, 5, 1, 0])

        // Края: слева — первым, справа — последним, чужой индекс подрезается.
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .left, count: 4), 0)
        XCTAssertEqual(ArrangeLayout.insertIndex(of: .right, count: 4), 4)
        XCTAssertEqual(ArrangeLayout.insert(order: [0, 1], count: 2, at: 99), [0, 1, 2])
        XCTAssertEqual(ArrangeLayout.insert(order: [0, 1], count: 2, at: -5), [2, 0, 1])
        // Окон не было вовсе — новое единственное.
        XCTAssertEqual(ArrangeLayout.insert(order: [], count: 0, at: 0), [0])
        // Мусорные индексы в порядке (окно закрылось) не роняют расстановку.
        XCTAssertEqual(ArrangeLayout.insert(order: [7, 0], count: 1, at: 0), [1, 0])
    }

    // MARK: - 4. «под этим» и возврат в ряд

    func testPimpSplitColumnAndArrangeBack() {
        let column = CGRect(x: 490, y: 34, width: 490, height: 859)
        let below = PimpChannel.split(column, above: false)
        XCTAssertEqual(below?.old, CGRect(x: 490, y: 34, width: 490, height: 429))
        XCTAssertEqual(below?.new, CGRect(x: 490, y: 463, width: 490, height: 430))
        let above = PimpChannel.split(column, above: true)
        XCTAssertEqual(above?.new, CGRect(x: 490, y: 34, width: 490, height: 429))
        XCTAssertEqual(above?.old, CGRect(x: 490, y: 463, width: 490, height: 430))
        // Порог — настоящий минимум окна, 357 pt (WF94; было 360): половина 713/2 = 356 — не
        // делим, 714 — делим.
        XCTAssertNil(PimpChannel.split(CGRect(x: 0, y: 0, width: 490, height: 713), above: false))
        XCTAssertNotNil(PimpChannel.split(CGRect(x: 0, y: 0, width: 490, height: 714), above: false))

        // «Под этим» → потом «расставь в ряд» возвращает исходный порядок: A, B, C и новое
        // окно под B — ряд из четырёх идёт слева направо, новое последним.
        let frames = [CGRect(x: 0, y: 34, width: 490, height: 859),
                      below!.old,
                      CGRect(x: 980, y: 34, width: 490, height: 859),
                      below!.new]
        XCTAssertEqual(ArrangeLayout.order(of: frames), [0, 1, 2, 3])
    }

    // MARK: - 5. очередь на диске

    func testPimpChannelServesRequests() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("PimpMyClaude", at: 2),
                        PimpChannelTests.project("Dictator", at: 1)]
        rig.windows = [PimpWindow(id: 7, title: "Claude", chat: "local_1", folder: "/tmp/one",
                                  frame: CGRect(x: 993, y: 34, width: 477, height: 859))]
        rig.minimized = 1
        let channel = makeChannel(rig, in: box)

        write(request("100-0001", action: "projects", at: rig.now), id: "100-0001", in: box)
        write(request("100-0002", action: "windows", at: rig.now), id: "100-0002", in: box)
        rig.advance(1)
        channel.tick()

        let projects = try XCTUnwrap(result("100-0001", in: box))
        XCTAssertEqual(projects["ok"] as? Bool, true)
        // Экран в ответе — тот, где стоят окна, а не «главный» (#5732).
        XCTAssertEqual(projects["screen"] as? String, "windows")
        XCTAssertEqual((projects["projects"] as? [[String: Any]])?.compactMap { $0["name"] as? String },
                       ["PimpMyClaude", "Dictator"])
        let windows = try XCTUnwrap(result("100-0002", in: box))
        XCTAssertEqual(windows["minimized"] as? Int, 1)
        XCTAssertEqual((windows["windows"] as? [[String: Any]])?.first?["chat"] as? String, "local_1")
        XCTAssertEqual((windows["windows"] as? [[String: Any]])?.first?["frame"] as? [Int],
                       [993, 34, 477, 859])
        XCTAssertEqual(channel.status, "2/0")

        // Метка «взял в работу» и права 0600 — каталог общий (риск 4 плана).
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: box.appendingPathComponent("100-0001.taken").path))
        let mode = try FileManager.default.attributesOfItem(
            atPath: box.appendingPathComponent("100-0001.result.json").path)[.posixPermissions]
        XCTAssertEqual(mode as? NSNumber, 0o600)

        // Ответ уже лежит — второй раз запрос не исполняется.
        channel.tick()
        XCTAssertEqual(channel.status, "2/0")

        // Запрос с меткой, но без ответа — его исполняли, а приложение перезапустили посреди
        // работы: повторять нельзя (правда об исполнении лежит на диске, а не в памяти).
        write(request("100-0003", action: "windows", at: rig.now), id: "100-0003", in: box)
        try Data().write(to: box.appendingPathComponent("100-0003.taken"))
        channel.tick()
        XCTAssertNil(result("100-0003", in: box))
        XCTAssertEqual(channel.status, "2/0")
    }

    func testPimpChannelRefusesStaleBadAndBusy() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.windows = [PimpWindow(id: 1, title: "Claude")]
        rig.projects = [PimpChannelTests.project("Dictator")]
        let channel = makeChannel(rig, in: box)

        // Протухший запрос (старше 30 с) не исполняется вовсе.
        write(request("200-0001", action: "windows", at: rig.now.addingTimeInterval(-31)),
              id: "200-0001", in: box)
        // Битый JSON и чужое действие — bad-request.
        write("{\"id\":\"200-0002\",", id: "200-0002", in: box)
        write(request("200-0003", action: "fly", at: rig.now), id: "200-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("200-0001", in: box)?["error"] as? String, "stale")
        XCTAssertEqual(result("200-0002", in: box)?["error"] as? String, "bad-request")
        XCTAssertEqual(result("200-0003", in: box)?["error"] as? String, "bad-request")
        XCTAssertEqual(channel.status, "3/3")

        // Пока идёт «новое окно», остальным — busy, и своё место в очереди они не занимают.
        write(request("200-0004", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"right\""),
              id: "200-0004", in: box)
        write(request("200-0005", action: "windows", at: rig.now), id: "200-0005", in: box)
        channel.tick()
        XCTAssertEqual(rig.opened.count, 1)
        XCTAssertNil(result("200-0004", in: box), "«новое окно» ещё идёт — ответа нет")
        XCTAssertEqual(result("200-0005", in: box)?["error"] as? String, "busy")
    }

    /// WF101 (z4-r01): чужая цепочка «Нового окна» идёт — канал отвечает `busy` и окон не трогает;
    /// кончилась — следующий запрос проходит.
    func testPimpChannelWaitsForForeignNewWindowChain() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.windows = [PimpWindow(id: 1, title: "Claude")]
        rig.projects = [PimpChannelTests.project("Dictator")]
        let channel = makeChannel(rig, in: box)
        var starting = true
        var rooms = 0
        channel.seats.newWindowStarting = { starting }
        channel.seats.makeRoom = { _ in rooms += 1; return [] }

        write(request("210-0001", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"right\""),
              id: "210-0001", in: box)
        channel.tick()
        XCTAssertEqual(result("210-0001", in: box)?["error"] as? String, "busy")
        XCTAssertTrue(rig.opened.isEmpty)
        XCTAssertEqual(rooms, 0)

        starting = false
        write(request("210-0002", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"right\""),
              id: "210-0002", in: box)
        channel.tick()
        XCTAssertEqual(rig.opened.count, 1)
    }

    func testPimpChannelSaysNoWindowsAndMissingProject() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("PimpMyClaude"),
                        PimpChannelTests.project("VkusnoffKz")]
        let channel = makeChannel(rig, in: box)

        // Claude запущен, а окон на экране нет — открывать новое неоткуда (⌘N жать некому).
        write(request("300-0001", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"right\""),
              id: "300-0001", in: box)
        write(request("300-0002", action: "arrange", at: rig.now, extra: ",\"layout\":\"row\""),
              id: "300-0002", in: box)
        channel.tick()
        XCTAssertEqual(result("300-0001", in: box)?["error"] as? String, "no-windows")
        XCTAssertEqual(result("300-0002", in: box)?["error"] as? String, "no-windows")

        // Окна есть, а такой папки Пимп не знает — отказ со списком имён.
        rig.windows = [PimpWindow(id: 1, title: "Claude")]
        write(request("300-0003", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Диктаторик\",\"place\":\"right\""),
              id: "300-0003", in: box)
        channel.tick()
        let missing = try XCTUnwrap(result("300-0003", in: box))
        XCTAssertEqual(missing["error"] as? String, "project-missing")
        XCTAssertEqual(missing["projects"] as? [String], ["PimpMyClaude", "VkusnoffKz"])
        XCTAssertTrue(rig.opened.isEmpty)

        // Claude не запущен — no-windows и для «покажи окна».
        rig.running = false
        write(request("300-0004", action: "windows", at: rig.now), id: "300-0004", in: box)
        channel.tick()
        XCTAssertEqual(result("300-0004", in: box)?["error"] as? String, "no-windows")
    }

    // MARK: - 5а. раскладки «Расставить» (план WF21)

    func testPimpChannelArrangesByLayout() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.windows = (1...6).map { id in
            PimpWindow(id: CGWindowID(id), title: "Окно \(id)",
                       frame: CGRect(x: CGFloat(id - 1) * 240, y: 34, width: 240, height: 859))
        }
        let channel = makeChannel(rig, in: box)

        // «5 в ряд» на шести окнах: шестое остаётся где стояло, и об этом сказано числом.
        write(request("900-0001", action: "arrange", at: rig.now, extra: ",\"layout\":\"5\""),
              id: "900-0001", in: box)
        channel.tick()
        let five = try XCTUnwrap(result("900-0001", in: box))
        XCTAssertEqual(five["ok"] as? Bool, true)
        XCTAssertEqual(five["layout"] as? String, "5")
        XCTAssertEqual((five["windows"] as? [[String: Any]])?.count, 5)
        XCTAssertEqual(five["skipped"] as? Int, 1)
        XCTAssertEqual(rig.window(1)?.frame, CGRect(x: 0, y: 34, width: 294, height: 859))
        XCTAssertEqual(rig.window(6)?.frame, CGRect(x: 1200, y: 34, width: 240, height: 859))

        // Раскладка на этот экран не влезает — `too-small`, окна не трогаем вовсе.
        rig.advance(1)
        rig.fits = false
        write(request("900-0003", action: "arrange", at: rig.now, extra: ",\"layout\":\"5x2\""),
              id: "900-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("900-0003", in: box)?["error"] as? String, "too-small")
        XCTAssertEqual(rig.layouts.count, 1, "окна не двигали")

        // Чужое слово в `layout` — bad-request: наугад окна не ставим.
        rig.advance(1)
        rig.fits = true
        write(request("900-0004", action: "arrange", at: rig.now, extra: ",\"layout\":\"5x3\""),
              id: "900-0004", in: box)
        channel.tick()
        XCTAssertEqual(result("900-0004", in: box)?["error"] as? String, "bad-request")
    }

    /// Голая «расставь» (`layout:"last"`, оно же умолчание CLI) идёт УМНЫМ путём
    /// (план WF77): плитку Элвиса не читает и не пишет (критик блокер 2), `too-small`
    /// не отвечает никогда (блокер 3), в ответе `layout` — «row» и `skipped` 0
    /// (решение 8: эталоны канала не меняются). Главное окно на этом пути — рядовое.
    func testPimpChannelArrangesSmartOnBareRequest() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .four
        rig.gap = 5
        // Экран стенда 1470 при минимуме 280 и зазоре 5 держит пять столбцов.
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 40, y: 100, width: 900, height: 500)),
            PimpWindow(id: 2, title: "Окно 2", frame: CGRect(x: 700, y: 200, width: 600, height: 400)),
            PimpWindow(id: 3, title: "Окно 3", frame: CGRect(x: 120, y: 300, width: 500, height: 300)),
        ]
        // Плитка «5×2» на этот экран «не влезает» — умному пути это безразлично.
        rig.fits = false
        let channel = makeChannel(rig, in: box)

        write(request("905-0001", action: "arrange", at: rig.now, extra: ",\"layout\":\"last\""),
              id: "905-0001", in: box)
        channel.tick()
        let answer = try XCTUnwrap(result("905-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["layout"] as? String, "row")
        XCTAssertEqual(answer["skipped"] as? Int, 0)
        XCTAssertEqual((answer["windows"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual(rig.smart.map { $0.ordered }, [false], "порядок никто не навязывал")
        XCTAssertTrue(rig.layouts.isEmpty, "плитку умный путь не трогает")
        XCTAssertEqual(rig.mode, .four, "выбор Элвиса остался прежним")
        // Три окна делят экран поровну, и главное окно (заголовок `mainTitle`) — рядовое:
        // особых правил у него нет (решение 5 плана WF77).
        XCTAssertEqual(rig.mainTitle, "Claude")
        let thirds = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: PimpRig.area, gap: 5)
        XCTAssertEqual(rig.window(1)?.frame, thirds[0])
        XCTAssertEqual(rig.window(3)?.frame, thirds[2])

        // Поля `layout` нет вовсе — то же самое: умный путь, а не лента.
        rig.advance(1)
        write(request("905-0002", action: "arrange", at: rig.now), id: "905-0002", in: box)
        channel.tick()
        XCTAssertEqual(result("905-0002", in: box)?["layout"] as? String, "row")
        XCTAssertEqual(rig.smart.count, 2)
        XCTAssertTrue(rig.layouts.isEmpty)

        // Окна уже стоят по сетке — «расставь» их не двигает (слово Элвиса 20.09).
        rig.advance(1)
        write(request("905-0003", action: "arrange", at: rig.now, extra: ",\"layout\":\"last\""),
              id: "905-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("905-0003", in: box)?["ok"] as? Bool, true)
        XCTAssertEqual(rig.windows.map { $0.frame }, thirds)
    }

    /// Новое окно «справа» (и умолчание) идёт умным путём (план WF77) с НАВЯЗАННЫМ порядком
    /// (WF94, #7730): оно последним, самым правым; плитку никто не читает, а поля `skipped` в
    /// ответе нет — ячейка нашлась (критик зам. 15). Четыре окна ужимаются вместе с ним:
    /// сетка теперь на пятерых.
    func testPimpChannelSeatsNewWindowByItself() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.mode = .four
        rig.gap = 5
        rig.windows = (1...4).map { id in
            PimpWindow(id: CGWindowID(id), title: "Окно \(id)",
                       frame: CGRect(x: CGFloat(id - 1) * 367, y: 34, width: 367, height: 859))
        }
        let channel = makeChannel(rig, in: box)

        write(request("910-0001", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"right\""),
              id: "910-0001", in: box)
        channel.tick()
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 9, title: "Диктаторик",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()

        let answer = try XCTUnwrap(result("910-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertNil(answer["skipped"], "ячейка нашлась — говорить о пропуске нечего")
        XCTAssertEqual((answer["window"] as? [String: Any])?["frame"] as? [Int],
                       [1180, 34, 290, 859])
        XCTAssertEqual(rig.smart.map { $0.ordered }, [true], "справа — последним, порядок навязан")
        XCTAssertEqual(rig.smart.first?.ids, [1, 2, 3, 4, 9])
        XCTAssertTrue(rig.layouts.isEmpty, "плитку новое окно больше не трогает")
        XCTAssertEqual(rig.mode, .four)
        let fifths = ArrangeLayout.cells(cols: 5, rows: 1, count: 5, in: PimpRig.area, gap: 5)
        XCTAssertEqual(rig.window(9)?.frame, fifths[4])
        XCTAssertEqual(rig.window(1)?.frame, fifths[0])
    }

    /// Новое окно «слева» называет место — там порядок НАВЯЗАН: окно встаёт первым, а
    /// остальные сдвигаются, даже если стояли по сетке (план WF77).
    func testPimpChannelPutsNewWindowFirstWhenAskedLeft() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.gap = 5
        let thirds = ArrangeLayout.cells(cols: 3, rows: 1, count: 3, in: PimpRig.area, gap: 5)
        rig.windows = (1...2).map { id in
            PimpWindow(id: CGWindowID(id), title: "Окно \(id)", frame: thirds[id - 1])
        }
        let channel = makeChannel(rig, in: box)

        write(request("911-0001", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"left\""),
              id: "911-0001", in: box)
        channel.tick()
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 9, title: "Диктаторик",
                                      frame: CGRect(x: 160, y: 160, width: 900, height: 700)))
        channel.tick()

        XCTAssertEqual(result("911-0001", in: box)?["ok"] as? Bool, true)
        XCTAssertEqual(rig.smart.map { $0.ordered }, [true], "слева — порядок навязан")
        XCTAssertEqual(rig.smart.first?.ids, [9, 1, 2])
        XCTAssertEqual(rig.window(9)?.frame, thirds[0])
        XCTAssertEqual(rig.window(1)?.frame, thirds[1])
        XCTAssertEqual(rig.window(2)?.frame, thirds[2])
    }

    // MARK: - 5б. раскладки проектов (план WF41)

    /// `arrange` с `order`: окна названных папок встают первыми (папку узнаём и по пути,
    /// и по имени), проект без окна уходит в `missing`, окна без папки — в хвост.
    func testPimpChannelOrdersWindowsByProjects() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_p",
                       folder: "/Users/dev/Projects/PimpMyClaude",
                       frame: CGRect(x: 0, y: 34, width: 490, height: 859)),
            PimpWindow(id: 2, title: "Без папки",
                       frame: CGRect(x: 490, y: 34, width: 490, height: 859)),
            PimpWindow(id: 3, title: "VkusnoffKz 3", chat: "local_v",
                       folder: "/Users/dev/Projects/VkusnoffKz",
                       frame: CGRect(x: 980, y: 34, width: 490, height: 859)),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("920-0001", action: "arrange", at: rig.now,
                      extra: ",\"layout\":\"row\",\"order\":[\"VkusnoffKz\",\"SkilZZZ\"]"),
              id: "920-0001", in: box)
        channel.tick()

        let answer = try XCTUnwrap(result("920-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(rig.arranged.first, [3, 1, 2],
                       "Вкуснофф первым, потом опознанный Пимп, окно без папки — в хвост")
        XCTAssertEqual(answer["unknown"] as? Int, 1)
        XCTAssertEqual(answer["missing"] as? [String], ["SkilZZZ"])
        XCTAssertEqual((answer["windows"] as? [[String: Any]])?.first?["title"] as? String,
                       "VkusnoffKz 3")

        // Абсолютный путь работает так же, как имя папки.
        rig.advance(1)
        write(request("920-0002", action: "arrange", at: rig.now,
                      extra: ",\"layout\":\"row\",\"order\":"
                        + "[\"/Users/dev/Projects/VkusnoffKz\"]"),
              id: "920-0002", in: box)
        channel.tick()
        XCTAssertEqual(rig.arranged.last?.first, 3)

        // Порядка не просили — ответ прежний, без `unknown` и `missing` (эталон arrange).
        rig.advance(1)
        write(request("920-0003", action: "arrange", at: rig.now, extra: ",\"layout\":\"row\""),
              id: "920-0003", in: box)
        channel.tick()
        let plain = try XCTUnwrap(result("920-0003", in: box))
        XCTAssertNil(plain["unknown"])
        XCTAssertNil(plain["missing"])
    }

    /// «Запомни раскладку»: главное окно пишется как `main`, окно вне сетки — с пустой
    /// ячейкой, а окно с неопознанным чатом отменяет запись целиком (`chat-unknown`).
    func testPimpChannelSavesLayoutAndRefusesUnknownChat() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .five
        let cells = ArrangeLayout.frames(count: 5, in: PimpRig.area, mode: .five)
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: "/tmp/Pimp",
                       frame: cells[0]),
            PimpWindow(id: 2, title: "Вкуснофф", chat: "local_v", folder: "/tmp/Vkus",
                       frame: cells[1]),
            PimpWindow(id: 3, title: "Диктаторик",
                       frame: CGRect(x: 200, y: 200, width: 900, height: 700)),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("930-0001", action: "layout-save", at: rig.now, extra: ",\"name\":\"Утро\""),
              id: "930-0001", in: box)
        channel.tick()
        let refused = try XCTUnwrap(result("930-0001", in: box))
        XCTAssertEqual(refused["error"] as? String, "chat-unknown")
        XCTAssertEqual(refused["windows"] as? [String], ["Диктаторик"])
        XCTAssertTrue(rig.saved.isEmpty, "файл не тронут — вернулись бы не те чаты")

        // Чат опознан — записываем: главное окно как `main`, окно вне сетки без ячейки.
        rig.advance(1)
        rig.windows[2] = PimpWindow(id: 3, title: "Диктаторик", chat: "local_d",
                                    folder: "/tmp/Dict",
                                    frame: CGRect(x: 200, y: 200, width: 900, height: 700))
        write(request("930-0002", action: "layout-save", at: rig.now, extra: ",\"name\":\"Утро\""),
              id: "930-0002", in: box)
        channel.tick()
        let saved = try XCTUnwrap(result("930-0002", in: box))
        XCTAssertEqual(saved["ok"] as? Bool, true)
        XCTAssertEqual(saved["mode"] as? String, "5")
        // All three actual positions can now be restored, including the off-grid window.
        XCTAssertEqual(saved["cells"] as? Int, 3)
        let layout = try XCTUnwrap(rig.saved.first)
        XCTAssertEqual(layout.cells.map { $0.chat }, ["main", "local_v", "local_d"])
        XCTAssertEqual(layout.cells.map { $0.cell }, [0, 1, nil])
        XCTAssertEqual(layout.cells.map { $0.folder }, ["/tmp/Pimp", "/tmp/Vkus", "/tmp/Dict"])

        // Имя занято — перезапись, второй записи не заводим.
        rig.advance(1)
        write(request("930-0003", action: "layout-save", at: rig.now, extra: ",\"name\":\" утро \""),
              id: "930-0003", in: box)
        channel.tick()
        XCTAssertEqual(rig.saved.count, 1)
        XCTAssertEqual(rig.saved.first?.name, "утро")
    }

    /// «Запомни раскладку» на окнах, стоящих не по сетке: записывать нечего — такая раскладка
    /// вернула бы ноль окон, а Пимп рапортовал бы «N окон» (#5728). Расставили — запись идёт,
    /// и в ответе столько мест, сколько получили НОМЕР ячейки.
    func testPimpChannelSavesArbitraryLayoutFrames() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .five
        let cells = ArrangeLayout.frames(count: 5, in: PimpRig.area, mode: .five)
        rig.windows = [
            PimpWindow(id: 1, title: "Вкуснофф", chat: "local_v", folder: "/tmp/Vkus",
                       frame: CGRect(x: 200, y: 200, width: 900, height: 700)),
            PimpWindow(id: 2, title: "Диктаторик", chat: "local_d", folder: "/tmp/Dict",
                       frame: CGRect(x: 260, y: 260, width: 900, height: 700)),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("935-0001", action: "layout-save", at: rig.now, extra: ",\"name\":\"Проба\""),
              id: "935-0001", in: box)
        channel.tick()
        let savedFree = try XCTUnwrap(result("935-0001", in: box))
        XCTAssertEqual(savedFree["ok"] as? Bool, true)
        XCTAssertEqual(savedFree["cells"] as? Int, 2)
        XCTAssertEqual(rig.saved.first?.cells.map { $0.frame }, rig.windows.map { Optional($0.frame) })

        // Grid and arbitrary windows are both restorable.
        rig.advance(1)
        rig.windows[0] = PimpWindow(id: 1, title: "Вкуснофф", chat: "local_v",
                                    folder: "/tmp/Vkus", frame: cells[0])
        write(request("935-0002", action: "layout-save", at: rig.now, extra: ",\"name\":\"Проба\""),
              id: "935-0002", in: box)
        channel.tick()
        let saved = try XCTUnwrap(result("935-0002", in: box))
        XCTAssertEqual(saved["ok"] as? Bool, true)
        XCTAssertEqual(saved["cells"] as? Int, 2)
        XCTAssertEqual(rig.saved.last?.cells.map { $0.cell }, [0, nil],
                       "окно вне сетки в файле остаётся — просто без ячейки")
    }

    /// Безымянный попап носит тот же заголовок «Claude», что главное окно: записать оба как
    /// `main` нельзя — чат попапа пропал бы, а главное окно встало бы в две ячейки (#5729).
    /// Ведём себя как при неизвестном чате: запись отменяется целиком и второе окно названо.
    func testPimpChannelRefusesLayoutSaveWithTwoMainWindows() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .five
        let cells = ArrangeLayout.frames(count: 5, in: PimpRig.area, mode: .five)
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: "/tmp/Pimp",
                       frame: cells[0]),
            PimpWindow(id: 2, title: "Claude", chat: "local_popout", folder: "/tmp/Vkus",
                       frame: cells[1]),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("936-0001", action: "layout-save", at: rig.now, extra: ",\"name\":\"Утро\""),
              id: "936-0001", in: box)
        channel.tick()
        let refused = try XCTUnwrap(result("936-0001", in: box))
        XCTAssertEqual(refused["error"] as? String, "chat-unknown")
        XCTAssertEqual(refused["windows"] as? [String], ["Claude"], "назван второй «Claude»")
        XCTAssertTrue(rig.saved.isEmpty)
    }

    /// «Расставить», после которой ни одно окно не переехало (окна закрылись между снимком и
    /// расстановкой): говорить «Расставил N окон» нельзя — их никто не двигал (#5680).
    func testPimpChannelSaysNoWindowsWhenNothingMoved() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.windows = [PimpWindow(id: 1, title: "Окно 1",
                                  frame: CGRect(x: 0, y: 34, width: 490, height: 859)),
                       PimpWindow(id: 2, title: "Окно 2",
                                  frame: CGRect(x: 490, y: 34, width: 490, height: 859))]
        rig.arrangeMisses = true
        let channel = makeChannel(rig, in: box)

        write(request("905-0001", action: "arrange", at: rig.now, extra: ",\"layout\":\"row\""),
              id: "905-0001", in: box)
        channel.tick()
        let answer = try XCTUnwrap(result("905-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, false)
        XCTAssertEqual(answer["error"] as? String, "no-windows")
        XCTAssertNil(answer["windows"], "списка окон, которые не двигали, в ответе нет")
    }

    /// `place` разбирает только «новое окно», `layout` — только «расставить» (#5682): чужое
    /// слово в чужом поле роняло весь запрос в `bad-request`.
    func testPimpRequestReadsPlaceAndLayoutOnlyForTheirAction() {
        func body(_ action: String, _ tail: String) -> Data {
            Data(("{\"id\":\"1-1\",\"at\":\"2026-09-08T03:20:00Z\",\"action\":\"\(action)\","
                    + "\"from\":\"\"\(tail)}").utf8)
        }
        XCTAssertNotNil(PimpRequest.parse(body("windows", ",\"layout\":\"5x3\"")))
        XCTAssertNotNil(PimpRequest.parse(body("projects", ",\"place\":\"куда-нибудь\"")))
        XCTAssertNotNil(PimpRequest.parse(body("layout-restore",
                                               ",\"name\":\"Утро\",\"layout\":\"5x3\"")))
        // У своих действий чужое слово — по-прежнему `bad-request`: наугад окна не двигаем.
        XCTAssertNil(PimpRequest.parse(body("arrange", ",\"layout\":\"5x3\"")))
        XCTAssertNil(PimpRequest.parse(body("new-window",
                                            ",\"project\":\"Dictator\",\"place\":\"куда\"")))
    }

    /// Сирота прошлого запуска (`<id>.taken` без ответа) получает `stale` прямо на старте:
    /// повторять запрос нельзя, но и заставлять CLI ждать минуту незачем (#5556). Заодно
    /// уборка сносит `.tmp`-огрызки (#5558).
    func testPimpChannelAnswersOrphansAndCleansTemp() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.windows = [PimpWindow(id: 1, title: "Claude")]
        write(request("980-0001", action: "windows", at: rig.now), id: "980-0001", in: box)
        try Data().write(to: box.appendingPathComponent("980-0001.taken"))
        let tmp = box.appendingPathComponent(".980-0002.json.tmp")
        try Data("{".utf8).write(to: tmp)
        try FileManager.default.setAttributes(
            [.modificationDate: rig.now.addingTimeInterval(-7200)], ofItemAtPath: tmp.path)

        let channel = makeChannel(rig, in: box)
        let orphan = try XCTUnwrap(result("980-0001", in: box))
        XCTAssertEqual(orphan["ok"] as? Bool, false)
        XCTAssertEqual(orphan["error"] as? String, "stale")

        channel.tick()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "огрызок убран")
        // Ответ уже лежит — второй раз запрос никто не исполняет.
        XCTAssertEqual(channel.status, "1/1")
    }

    /// «Верни Утро»: открытое окно встаёт в ячейку, закрытый чат главное окно выносит
    /// попапом, а чат, окна для которого так и не появилось, уходит в `missing` — пустой
    /// ячейкой, без подмены новым чатом (#5455). Окна идут ПО ОДНОМУ, и после каждого
    /// переписывается метка `<id>.taken` (сердцебиение для CLI).
    func testPimpChannelRestoresSameChats() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .five
        let cells = ArrangeLayout.frames(count: 3, in: PimpRig.area, mode: .five)
        rig.saved = [WindowLayout(name: "Утро", at: rig.now, mode: .five, cells: [
            LayoutCell(folder: "/tmp/Pimp", chat: "main", title: "Claude", cell: 0),
            LayoutCell(folder: "/tmp/Vkus", chat: "local_v", title: "Вкуснофф", cell: 1),
            LayoutCell(folder: "/tmp/Dict", chat: "local_d", title: "Диктаторик", cell: 2),
        ])]
        rig.windows = [PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: "/tmp/Pimp",
                                  frame: CGRect(x: 300, y: 300, width: 900, height: 700))]
        let channel = makeChannel(rig, in: box)

        write(request("940-0001", action: "layout-restore", at: rig.now,
                      extra: ",\"name\":\"Утро\",\"fresh\":false"), id: "940-0001", in: box)
        channel.tick()
        // Главное окно уже на экране — оно просто встало в свою ячейку; следом попросили
        // вынести закрытый чат, и ответа пока нет.
        XCTAssertEqual(rig.window(1)?.frame, cells[0])
        XCTAssertEqual(rig.popouts.map { $0.chat }, ["local_v"])
        XCTAssertEqual(rig.popouts.first?.name, "Вкуснофф")
        XCTAssertEqual(rig.popouts.first?.origin.x, Int(cells[1].minX))
        XCTAssertNil(result("940-0001", in: box))

        // Пока идёт возврат, канал занят — остальным `busy`.
        write(request("940-0002", action: "windows", at: rig.now), id: "940-0002", in: box)
        channel.tick()
        XCTAssertEqual(result("940-0002", in: box)?["error"] as? String, "busy")

        // Метку убираем руками: после следующего окна она обязана появиться снова.
        let taken = box.appendingPathComponent("940-0001.taken")
        try FileManager.default.removeItem(at: taken)
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 2, title: "Вкуснофф", chat: "local_v",
                                      folder: "/tmp/Vkus",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()
        XCTAssertEqual(rig.window(2)?.frame, cells[1], "вынесенное окно встало в свою ячейку")
        XCTAssertTrue(FileManager.default.fileExists(atPath: taken.path), "сердцебиение")
        XCTAssertEqual(rig.popouts.map { $0.chat }, ["local_v", "local_d"])

        // Третье окно так и не появилось — ячейка остаётся пустой, чат назван в `missing`.
        rig.advance(PimpChannel.restoreWindowSeconds + 1)
        channel.tick()
        let answer = try XCTUnwrap(result("940-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["name"] as? String, "Утро")
        XCTAssertEqual(answer["placed"] as? Int, 1)
        XCTAssertEqual(answer["opened"] as? Int, 1)
        XCTAssertEqual(answer["missing"] as? [String], ["Диктаторик"])
        XCTAssertEqual(rig.windows.count, 2, "нового чата вместо старого не заводим")

        // Канал снова свободен.
        rig.advance(1)
        write(request("940-0003", action: "windows", at: rig.now), id: "940-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("940-0003", in: box)?["ok"] as? Bool, true)
    }

    /// Claude закрыли посреди возврата: очередь обрывается на том же тике, канал свободен, а
    /// оставшиеся чаты честно названы пропавшими — раньше он досматривал каждое место полным
    /// таймаутом и всем отвечал «занят» (#5730).
    func testPimpChannelStopsRestoreWhenClaudeGone() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .five
        rig.saved = [WindowLayout(name: "Утро", at: rig.now, mode: .five, cells: [
            LayoutCell(folder: "/tmp/Pimp", chat: "main", title: "Claude", cell: 0),
            LayoutCell(folder: "/tmp/Vkus", chat: "local_v", title: "Вкуснофф", cell: 1),
            LayoutCell(folder: "/tmp/Dict", chat: "local_d", title: "Диктаторик", cell: 2),
        ])]
        rig.windows = [PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: "/tmp/Pimp",
                                  frame: CGRect(x: 300, y: 300, width: 900, height: 700))]
        let channel = makeChannel(rig, in: box)

        write(request("945-0001", action: "layout-restore", at: rig.now,
                      extra: ",\"name\":\"Утро\",\"fresh\":false"), id: "945-0001", in: box)
        channel.tick()
        XCTAssertNil(result("945-0001", in: box), "ждём вынесенный чат")

        // Элвис вышел из Claude: ждать больше нечего и некому.
        rig.advance(2)
        rig.running = false
        channel.tick()
        let answer = try XCTUnwrap(result("945-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["placed"] as? Int, 1)
        XCTAssertEqual(answer["opened"] as? Int, 0)
        XCTAssertEqual(answer["missing"] as? [String], ["Вкуснофф", "Диктаторик"])

        // Канал свободен сразу же, а не через таймаут каждого места.
        rig.advance(1)
        rig.running = true
        write(request("945-0002", action: "windows", at: rig.now), id: "945-0002", in: box)
        channel.tick()
        XCTAssertEqual(result("945-0002", in: box)?["ok"] as? Bool, true)
    }

    /// «↩︎ Вернуть эти чаты» из МЕНЮ: запроса нет, ответить некому — итог уходит плашкой,
    /// теми же словами, что говорит CLI (#5689: раньше пункт молчал до конца дней).
    func testPimpChannelTellsMenuWhenRestoreIsDone() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .five
        let layout = WindowLayout(name: "Утро", at: rig.now, mode: .five, cells: [
            LayoutCell(folder: "/tmp/Pimp", chat: "main", title: "Claude", cell: 0),
            LayoutCell(folder: "/tmp/Vkus", chat: "local_v", title: "Вкуснофф", cell: 1),
        ])
        rig.saved = [layout]
        rig.windows = [PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: "/tmp/Pimp",
                                  frame: CGRect(x: 300, y: 300, width: 900, height: 700))]
        let channel = makeChannel(rig, in: box)

        XCTAssertTrue(channel.startRestore(layout, fresh: false))
        XCTAssertEqual(rig.popouts.map { $0.chat }, ["local_v"])
        XCTAssertTrue(rig.notices.isEmpty, "пока работа идёт, говорить нечего")

        // Окно так и не появилось: очередь кончилась — плашка называет итог.
        rig.advance(PimpChannel.restoreWindowSeconds + 1)
        channel.tick()
        XCTAssertEqual(rig.notices,
                       ["Вернул «Утро»: 1 стояло, 0 открыл; не нашёл чат: Вкуснофф"])
        // Канал снова свободен: запрос из чата больше не получает «занят».
        rig.advance(1)
        write(request("946-0001", action: "windows", at: rig.now), id: "946-0001", in: box)
        channel.tick()
        XCTAssertEqual(result("946-0001", in: box)?["ok"] as? Bool, true)
    }

    /// Возврат ЛЕНТЫ считает места по записи, а не по числу занятых ячеек: у ленты ширина
    /// ячейки зависит от их числа, и раскладка из трёх окон, где одно стояло вне сетки,
    /// возвращалась половинами вместо третей (#5688).
    func testPimpChannelRestoresRibbonByRecordedCount() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .ribbon
        let thirds = ArrangeLayout.frames(count: 3, in: PimpRig.area, mode: .ribbon)
        rig.saved = [WindowLayout(name: "Лента", at: rig.now, mode: .ribbon, cells: [
            LayoutCell(folder: "/tmp/A", chat: "local_a", title: "А", cell: 0),
            LayoutCell(folder: "/tmp/B", chat: "local_b", title: "Б", cell: 1),
            LayoutCell(folder: "/tmp/C", chat: "local_c", title: "В", cell: nil),
        ])]
        rig.windows = [
            PimpWindow(id: 1, title: "А", chat: "local_a", folder: "/tmp/A",
                       frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
            PimpWindow(id: 2, title: "Б", chat: "local_b", folder: "/tmp/B",
                       frame: CGRect(x: 200, y: 200, width: 800, height: 600)),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("947-0001", action: "layout-restore", at: rig.now,
                      extra: ",\"name\":\"Лента\",\"fresh\":false"), id: "947-0001", in: box)
        channel.tick()

        let answer = try XCTUnwrap(result("947-0001", in: box))
        XCTAssertEqual(answer["placed"] as? Int, 2)
        XCTAssertEqual(answer["missing"] as? [String], [], "место без ячейки пропавшим не зовём")
        XCTAssertEqual(rig.window(1)?.frame, thirds[0])
        XCTAssertEqual(rig.window(2)?.frame, thirds[1])
    }

    /// Опоздавшее окно прошлого места не должно занять чужую ячейку (#5691): пока ждём чат
    /// места, чужой опознанный чат за новое окно не считаем.
    func testPimpChannelKeepsLateWindowOutOfNextCell() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.mode = .five
        let cells = ArrangeLayout.frames(count: 2, in: PimpRig.area, mode: .five)
        rig.saved = [WindowLayout(name: "Утро", at: rig.now, mode: .five, cells: [
            LayoutCell(folder: "/tmp/Vkus", chat: "local_v", title: "Вкуснофф", cell: 0),
            LayoutCell(folder: "/tmp/Dict", chat: "local_d", title: "Диктаторик", cell: 1),
        ])]
        rig.windows = [PimpWindow(id: 1, title: "Claude", chat: "local_main",
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let channel = makeChannel(rig, in: box)

        write(request("948-0001", action: "layout-restore", at: rig.now,
                      extra: ",\"name\":\"Утро\",\"fresh\":false"), id: "948-0001", in: box)
        channel.tick()
        XCTAssertEqual(rig.popouts.map { $0.chat }, ["local_v"])

        // Появилось окно ЧУЖОГО чата (опоздавший вынос прошлой очереди) — оно не наше.
        rig.advance(2)
        rig.windows.append(PimpWindow(id: 2, title: "Опоздавший", chat: "local_late",
                                      frame: CGRect(x: 500, y: 500, width: 900, height: 700)))
        channel.tick()
        XCTAssertEqual(rig.window(2)?.frame, CGRect(x: 500, y: 500, width: 900, height: 700),
                       "чужое окно в ячейку не ставим")
        XCTAssertEqual(rig.popouts.count, 1, "ждём своё окно дальше")

        // Пришло своё — оно и встаёт в ячейку места.
        rig.advance(2)
        rig.windows.append(PimpWindow(id: 3, title: "Вкуснофф", chat: "local_v",
                                      folder: "/tmp/Vkus",
                                      frame: CGRect(x: 600, y: 600, width: 900, height: 700)))
        channel.tick()
        XCTAssertEqual(rig.window(3)?.frame, cells[0])
        XCTAssertEqual(rig.popouts.map { $0.chat }, ["local_v", "local_d"])
    }

    /// «Новые чаты по этим проектам»: те же папки через сегодняшний путь «нового окна»,
    /// по одному; открытые окна тех же чатов не переиспользуются, `missing` пуст.
    func testPimpChannelOpensFreshChatsByFolders() throws {
        let box = makeTemp()
        let rig = PimpRig()
        let vkus = box.appendingPathComponent("Vkus", isDirectory: true)
        try FileManager.default.createDirectory(at: vkus, withIntermediateDirectories: true)
        rig.mode = .five
        let cells = ArrangeLayout.frames(count: 2, in: PimpRig.area, mode: .five)
        rig.saved = [WindowLayout(name: "Утро", at: rig.now, mode: .five, cells: [
            LayoutCell(folder: vkus.path, chat: "local_v", title: "Вкуснофф", cell: 0),
            LayoutCell(folder: box.appendingPathComponent("Нет").path, chat: "local_x",
                       title: "Пропавший", cell: 1),
        ])]
        rig.windows = [PimpWindow(id: 1, title: "Claude", chat: "local_main",
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let channel = makeChannel(rig, in: box)

        write(request("950-0001", action: "layout-restore", at: rig.now,
                      extra: ",\"name\":\"Утро\",\"fresh\":true"), id: "950-0001", in: box)
        channel.tick()
        XCTAssertEqual(rig.opened.map { $0.project.folder.path }, [vkus.path])
        XCTAssertEqual(rig.opened.first?.origin?.x, Int(cells[0].minX))
        XCTAssertTrue(rig.popouts.isEmpty, "новые чаты попапом не выносят")

        rig.advance(3)
        rig.windows.append(PimpWindow(id: 2, title: "Vkus", chat: "local_new",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()
        // Второй папки нет на диске — открывать нечем, и ячейка просто пустует.
        let answer = try XCTUnwrap(result("950-0001", in: box))
        XCTAssertEqual(answer["opened"] as? Int, 1)
        XCTAssertEqual(answer["placed"] as? Int, 0)
        XCTAssertEqual(answer["missing"] as? [String], [], "у новых чатов пропавших нет")
        XCTAssertEqual(rig.window(2)?.frame, cells[0])
    }

    /// «Какие раскладки» и «верни то, чего нет»: список свежими вперёд, отказ со списком имён.
    func testPimpChannelListsLayoutsAndSaysMissing() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.windows = [PimpWindow(id: 1, title: "Claude", chat: "local_main")]
        rig.saved = [
            WindowLayout(name: "Утро", at: rig.now, mode: .five, cells: [
                LayoutCell(folder: "/tmp/Pimp", chat: "main", title: "Claude", cell: 0),
                // Место без ячейки в списке не считаем: вернётся оно ничем (#5728).
                LayoutCell(folder: "/tmp/Vkus", chat: "local_v", title: "Вкуснофф", cell: nil)]),
            WindowLayout(name: "Разбор", at: rig.now.addingTimeInterval(-3600), mode: .ribbon,
                         cells: []),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("960-0001", action: "layouts", at: rig.now), id: "960-0001", in: box)
        write(request("960-0002", action: "layout-restore", at: rig.now,
                      extra: ",\"name\":\"Вечер\",\"fresh\":false"), id: "960-0002", in: box)
        channel.tick()

        let list = try XCTUnwrap(result("960-0001", in: box))
        XCTAssertEqual((list["layouts"] as? [[String: Any]])?.compactMap { $0["name"] as? String },
                       ["Утро", "Разбор"])
        XCTAssertEqual((list["layouts"] as? [[String: Any]])?.compactMap { $0["cells"] as? Int },
                       [1, 0])
        let missing = try XCTUnwrap(result("960-0002", in: box))
        XCTAssertEqual(missing["error"] as? String, "layout-missing")
        XCTAssertEqual(missing["layouts"] as? [String], ["Утро", "Разбор"])
    }

    /// `projects --status`: у проекта появляются открытые окна и строка из его status.md;
    /// без `status` ответ прежний, побайтно.
    func testPimpProjectsCarryStatusAndChats() throws {
        let box = makeTemp()
        let rig = PimpRig()
        let folder = box.appendingPathComponent("Pimp", isDirectory: true)
        let docs = folder.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data("""
        # ⚪PimpMyClaude
        обновлено 03:25

        41 воркфлоу
        27 готово
        42 ч потрачено

        1️⃣ Workflow ✅ готово
        - шаги 2 из 2

        Сейчас: WF21 кодится
        """.utf8).write(to: docs.appendingPathComponent("status.md"))
        rig.projects = [Project(folder: folder, name: "Pimp", lastFocusedAt: 0)]
        rig.windows = [PimpWindow(id: 1, title: "Claude", chat: "local_p", folder: folder.path),
                       PimpWindow(id: 2, title: "Чужое", folder: "/tmp/other")]
        let channel = makeChannel(rig, in: box)

        write(request("970-0001", action: "projects", at: rig.now, extra: ",\"status\":true"),
              id: "970-0001", in: box)
        write(request("970-0002", action: "projects", at: rig.now), id: "970-0002", in: box)
        channel.tick()

        let one = try XCTUnwrap((result("970-0001", in: box)?["projects"] as? [[String: Any]])?.first)
        XCTAssertEqual(one["chats"] as? [String], ["Claude"])
        XCTAssertEqual(one["state"] as? String,
                       "41 воркфлоу · 27 готово · Сейчас: WF21 кодится")
        let plain = try XCTUnwrap((result("970-0002", in: box)?["projects"] as? [[String: Any]])?.first)
        XCTAssertNil(plain["chats"])
        XCTAssertNil(plain["state"])

        // Сводки нет вовсе — пустая строка, а не отказ.
        XCTAssertEqual(PimpChannel.state(of: box), "")
        XCTAssertEqual(PimpChannel.state(nil), "")
        // Строки блоков «✅ готово» в шапку не лезут: они начинаются с цифры-эмодзи.
        XCTAssertEqual(PimpChannel.state("3 воркфлоу\n1 готово\n2️⃣ Workflow ✅ готово"),
                       "3 воркфлоу · 1 готово")

        // «Сейчас:» пишут свободным текстом — строка обрезается по потолку, а счёт из шапки
        // стоит первым и переживает обрезку всегда (#5690).
        let long = PimpChannel.state("3 воркфлоу\n1 готово\nСейчас: "
                                        + String(repeating: "очень длинная строка ", count: 20))
        XCTAssertLessThanOrEqual(long.count, PimpChannel.stateLimit)
        XCTAssertTrue(long.hasPrefix("3 воркфлоу · 1 готово · Сейчас:"))
        XCTAssertTrue(long.hasSuffix("…"))
    }

    // MARK: - 6. новое окно посередине

    func testPimpChannelOpensWindowInTheMiddle() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.windows = [
            PimpWindow(id: 1, title: "Вкуснофф", frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 2, title: "Claude", frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("400-0001", action: "new-window", at: rig.now, from: "local_main",
                      extra: ",\"project\":\"dictator\",\"place\":\"middle\""),
              id: "400-0001", in: box)
        channel.tick()
        // Имя папки сверяется без учёта регистра, точка не задаётся — окно родится, как в меню.
        XCTAssertEqual(rig.opened.first?.project.name, "Dictator")
        XCTAssertNil(rig.opened.first?.origin ?? nil)
        XCTAssertNil(result("400-0001", in: box))

        // Окно ещё не появилось — ждём (до 40 с), ответа нет.
        rig.advance(2)
        channel.tick()
        XCTAssertNil(result("400-0001", in: box))

        // Появилось третье окно — оно и есть новое (по номеру, а не по имени: переименование
        // чата могло не удаться, риск 1 плана).
        rig.advance(2)
        rig.windows.append(PimpWindow(id: 3, title: "Диктаторик", chat: "local_new",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()

        let answer = try XCTUnwrap(result("400-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["fromResolved"] as? Bool, false, "чата from никто не назвал")
        // «Посередине» называет место — порядок навязан (план WF77), ячейки идут с зазором.
        XCTAssertEqual(rig.smart.first?.ids, [1, 3, 2], "новое окно встало между старыми")
        XCTAssertEqual(rig.smart.first?.ordered, true)
        let window = try XCTUnwrap(answer["window"] as? [String: Any])
        XCTAssertEqual(window["title"] as? String, "Диктаторик")
        XCTAssertEqual(window["chat"] as? String, "local_new")
        XCTAssertEqual(window["frame"] as? [Int], [490, 34, 490, 859])
        XCTAssertEqual(answer["layers"] as? String, "ok")
        // Ячейка нашлась — поля `skipped` в ответе нет вовсе (эталон new-window.result.json).
        XCTAssertNil(answer["skipped"])
        XCTAssertEqual(rig.window(3)?.frame, CGRect(x: 490, y: 34, width: 490, height: 859))
    }

    func testPimpChannelSplitsColumnBelowKnownChat() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.windows = [
            PimpWindow(id: 1, title: "Вкуснофф", frame: CGRect(x: 0, y: 34, width: 490, height: 859)),
            PimpWindow(id: 2, title: "Пимп", chat: "local_pimp",
                       frame: CGRect(x: 490, y: 34, width: 490, height: 859)),
            PimpWindow(id: 3, title: "Диктаторик", frame: CGRect(x: 980, y: 34, width: 490, height: 859)),
        ]
        rig.titles = ["local_pimp": "Пимп"]
        let channel = makeChannel(rig, in: box)

        write(request("500-0001", action: "new-window", at: rig.now, from: "local_pimp",
                      extra: ",\"project\":\"Dictator\",\"place\":\"below\""),
              id: "500-0001", in: box)
        channel.tick()
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 4, title: "Диктаторик 2",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()

        let answer = try XCTUnwrap(result("500-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["fromResolved"] as? Bool, true)
        XCTAssertTrue(rig.arranged.isEmpty, "остальные окна не трогаем")
        XCTAssertEqual(rig.window(2)?.frame, CGRect(x: 490, y: 34, width: 490, height: 429))
        XCTAssertEqual(rig.window(4)?.frame, CGRect(x: 490, y: 463, width: 490, height: 430))
        XCTAssertEqual((answer["window"] as? [String: Any])?["frame"] as? [Int],
                       [490, 463, 490, 430])
        XCTAssertEqual(rig.window(1)?.frame, CGRect(x: 0, y: 34, width: 490, height: 859))
    }

    /// Гейт WF36: главное окно носит заглушку «Claude», заголовок его чата из индекса
    /// («PimpMyClaude») с ней не совпадает — окно `from` находится по ЧАТУ.
    func testPimpChannelFindsMainWindowByChatNotTitle() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.windows = [
            PimpWindow(id: 1, title: "Вкуснофф", frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 2, title: "Claude", chat: "local_main",
                       frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        rig.titles = ["local_main": "PimpMyClaude"]
        let channel = makeChannel(rig, in: box)

        write(request("510-0001", action: "new-window", at: rig.now, from: "local_main",
                      extra: ",\"project\":\"Dictator\",\"place\":\"below\""),
              id: "510-0001", in: box)
        channel.tick()
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 4, title: "Dictator",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()

        let answer = try XCTUnwrap(result("510-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["fromResolved"] as? Bool, true)
        XCTAssertEqual(rig.window(2)?.frame, CGRect(x: 735, y: 34, width: 735, height: 429))
        XCTAssertEqual(rig.window(4)?.frame, CGRect(x: 735, y: 463, width: 735, height: 430))
    }

    func testPimpChannelFallsBackToRightWithoutChat() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.windows = [PimpWindow(id: 1, title: "Вкуснофф",
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let channel = makeChannel(rig, in: box)

        // Чат назвали, а окна с таким чатом нет (у субагента переменной вовсе не бывает) —
        // «под этим» честно вырождается в «справа», и это видно по fromResolved.
        write(request("600-0001", action: "new-window", at: rig.now, from: "local_ghost",
                      extra: ",\"project\":\"Dictator\",\"place\":\"below\""),
              id: "600-0001", in: box)
        channel.tick()
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 2, title: "Диктаторик",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()

        let answer = try XCTUnwrap(result("600-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["fromResolved"] as? Bool, false)
        XCTAssertEqual(rig.smart.first?.ids, [1, 2], "новое окно справа")
        XCTAssertEqual(rig.smart.first?.ordered, true, "справа — последним, порядок навязан (WF94)")
        XCTAssertTrue(rig.moved.isEmpty)
    }

    func testPimpChannelFallsBackToRightWhenFromWindowClosed() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.windows = [
            PimpWindow(id: 1, title: "Вкуснофф", frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 2, title: "Пимп", chat: "local_pimp",
                       frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        rig.titles = ["local_pimp": "Пимп"]
        let channel = makeChannel(rig, in: box)

        write(request("650-0001", action: "new-window", at: rig.now, from: "local_pimp",
                      extra: ",\"project\":\"Dictator\",\"place\":\"below\""),
              id: "650-0001", in: box)
        channel.tick()
        // Окно `from` закрыли, пока шли 40 с: делить нечего — новое окно встаёт справа.
        rig.windows.removeAll { $0.id == 2 }
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 3, title: "Диктаторик",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()

        let answer = try XCTUnwrap(result("650-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["fromResolved"] as? Bool, false)
        XCTAssertEqual(rig.smart.first?.ids, [1, 3])
        XCTAssertTrue(rig.moved.isEmpty)
    }

    func testPimpChannelSaysTooSmallAndWindowMissing() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.windows = [PimpWindow(id: 1, title: "Пимп", chat: "local_pimp",
                                  frame: CGRect(x: 0, y: 34, width: 490, height: 600))]
        rig.titles = ["local_pimp": "Пимп"]
        let channel = makeChannel(rig, in: box)

        // Столбец 600 pt пополам не делится — порог 360.
        write(request("700-0001", action: "new-window", at: rig.now, from: "local_pimp",
                      extra: ",\"project\":\"Dictator\",\"place\":\"above\""),
              id: "700-0001", in: box)
        channel.tick()
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 2, title: "Диктаторик",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()
        XCTAssertEqual(result("700-0001", in: box)?["error"] as? String, "too-small")
        XCTAssertTrue(rig.moved.isEmpty)

        // Окно не появилось за 65 с (WF102, C2; было 40) — window-missing (чат при этом создан,
        // так и скажет CLI). На 41-й секунде канал ещё ждёт: цепочка страницы с диалогом доверия
        // идёт дольше прежних 40 с.
        rig.advance(1)
        write(request("700-0002", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"right\""),
              id: "700-0002", in: box)
        channel.tick()
        XCTAssertNil(result("700-0002", in: box))
        rig.advance(41)
        channel.tick()
        XCTAssertNil(result("700-0002", in: box), "на 41-й секунде ещё ждём")
        rig.advance(PimpChannel.newWindowSeconds - 40)
        channel.tick()
        XCTAssertEqual(result("700-0002", in: box)?["error"] as? String, "window-missing")
        // Канал снова свободен.
        write(request("700-0003", action: "windows", at: rig.now), id: "700-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("700-0003", in: box)?["ok"] as? Bool, true)
    }

    // MARK: - 6а. голосовой Пимп (план WF75)

    /// Закрытый последний чат выносится отдельным окном, и ждём окно ИМЕННО ЕГО: чужое
    /// новое окно (вынос соседнего чата, «Обкэшить») нашим не считается — это #5691.
    func testPimpChannelOpensLastChatByIndex() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-19T19:00:00Z")!
        rig.projects = [PimpChannelTests.project("TrelvisCom")]
        rig.lastChats["/Users/dev/Projects/TrelvisCom"] =
            (chat: "local_9f1c2d3e-0000-4000-8000-000000000002", title: "Дубли задач")
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 2, title: "Вкуснофф",
                       frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        let channel = makeChannel(rig, in: box)

        write(try fixtureText("new-window-last.request.json"), id: "1789850000000-0101", in: box)
        channel.tick()
        // Нового чата не заводим вовсе — чат выносит главное окно, как «↩︎ Вернуть эти чаты».
        XCTAssertTrue(rig.opened.isEmpty)
        XCTAssertEqual(rig.popouts.first?.chat, "local_9f1c2d3e-0000-4000-8000-000000000002")
        XCTAssertEqual(rig.popouts.first?.name, "Дубли задач")
        XCTAssertNil(result("1789850000000-0101", in: box))

        rig.advance(2)
        rig.windows.append(PimpWindow(id: 3, title: "Бот: голос", chat: "local_other",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()
        XCTAssertNil(result("1789850000000-0101", in: box), "чужое новое окно — не наше")
        rig.windows.removeAll { $0.id == 3 }

        rig.advance(4)
        rig.windows.append(PimpWindow(id: 4, title: "Дубли задач",
                                      chat: "local_9f1c2d3e-0000-4000-8000-000000000002",
                                      frame: CGRect(x: 120, y: 120, width: 900, height: 700)))
        channel.tick()
        // Ответ побайтно: `opened` последним, и он есть только потому, что просили `chat`.
        XCTAssertEqual(try resultText("1789850000000-0101", in: box),
                       try fixtureText("new-window-last.result.json"))
        XCTAssertTrue(rig.raised.isEmpty, "окно родилось — поднимать было нечего")
    }

    func testPimpChannelRaisesWindowOfOpenLastChat() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("TrelvisCom")]
        rig.lastChats["/Users/dev/Projects/TrelvisCom"] =
            (chat: "local_last", title: "Дубли задач")
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 2, title: "Дубли задач", chat: "local_last",
                       frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("910-0001", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\",\"place\":\"left\",\"chat\":\"last\""),
              id: "910-0001", in: box)
        channel.tick()

        let answer = try XCTUnwrap(result("910-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["opened"] as? Bool, false, "окно было — мы его только подняли")
        XCTAssertEqual(rig.raised, [2])
        XCTAssertTrue(rig.popouts.isEmpty)
        XCTAssertTrue(rig.opened.isEmpty)
        XCTAssertEqual(rig.smart.first?.ids, [2, 1], "поднятое окно встало слева")
        XCTAssertEqual(rig.smart.first?.ordered, true, "место названо — порядок навязан")
        XCTAssertEqual(rig.window(2)?.frame, CGRect(x: 0, y: 34, width: 735, height: 859))
    }

    func testPimpChannelSaysChatMissingAndWaitsFifteenSeconds() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-19T19:00:11Z")!
        rig.projects = [PimpChannelTests.project("TrelvisCom")]
        rig.windows = [PimpWindow(id: 1, title: "Claude",
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let channel = makeChannel(rig, in: box)

        // Последнего чата у папки нет (Claude переустановлен, проект новый).
        write(request("1789850000000-0102", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\",\"place\":\"right\",\"chat\":\"last\""),
              id: "1789850000000-0102", in: box)
        channel.tick()
        XCTAssertEqual(try resultText("1789850000000-0102", in: box),
                       try fixtureText("new-window-last.error.json"))
        XCTAssertTrue(rig.popouts.isEmpty)

        // Чат есть, окно не приехало: ждём 15 с (вынос готового чата — секунды), не 40.
        rig.lastChats["/Users/dev/Projects/TrelvisCom"] =
            (chat: "local_last", title: "Дубли задач")
        rig.advance(1)
        write(request("920-0002", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\",\"place\":\"right\",\"chat\":\"last\""),
              id: "920-0002", in: box)
        channel.tick()
        XCTAssertEqual(rig.popouts.count, 1)
        rig.advance(14)
        channel.tick()
        XCTAssertNil(result("920-0002", in: box))
        rig.advance(2)
        channel.tick()
        XCTAssertEqual(result("920-0002", in: box)?["error"] as? String, "window-missing")

        // Главного окна на экране нет — выносить нечем.
        rig.windows = [PimpWindow(id: 2, title: "Вкуснофф",
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        rig.advance(1)
        write(request("920-0003", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\",\"place\":\"right\",\"chat\":\"last\""),
              id: "920-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("920-0003", in: box)?["error"] as? String, "window-missing")
        XCTAssertEqual(rig.popouts.count, 1, "второй раз выносить не пробовали")
    }

    func testPimpChannelClosesOneWindowOfProject() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-19T19:00:11Z")!
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_main",
                       folder: "/Users/dev/Projects/PimpMyClaude",
                       frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 2, title: "Дубли задач", chat: "local_2",
                       folder: "/Users/dev/Projects/TrelvisCom",
                       frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        let channel = makeChannel(rig, in: box)

        write(try fixtureText("close-window.request.json"), id: "1789850010000-0201", in: box)
        channel.tick()
        XCTAssertEqual(rig.closed, [2], "закрыли только окно проекта, и только красной кнопкой")
        XCTAssertEqual(try resultText("1789850010000-0201", in: box),
                       try fixtureText("close-window.result.json"))
    }

    func testPimpChannelRefusesToCloseAmbiguousOrMainWindow() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-19T19:00:12Z")!
        let trelvis = "/Users/dev/Projects/TrelvisCom"
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", folder: "/Users/dev/Projects/PimpMyClaude",
                       frame: CGRect(x: 0, y: 34, width: 490, height: 859)),
            PimpWindow(id: 2, title: "Дубли задач", chat: "local_2", folder: trelvis,
                       frame: CGRect(x: 490, y: 34, width: 490, height: 859)),
            PimpWindow(id: 3, title: "Бот: голос", chat: "local_3", folder: trelvis,
                       frame: CGRect(x: 980, y: 34, width: 490, height: 859)),
        ]
        let channel = makeChannel(rig, in: box)

        // Два окна проекта — не гадаем и не закрываем ни одного.
        write(request("1789850010000-0202", action: "close-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\""), id: "1789850010000-0202", in: box)
        channel.tick()
        XCTAssertEqual(try resultText("1789850010000-0202", in: box),
                       try fixtureText("close-window.error.json"))
        XCTAssertTrue(rig.closed.isEmpty)

        // Осталось главное окно проекта и попап с заглушкой: закрывать нечего, и это
        // не «окон нет», а «это главное окно» (#5729, #5534).
        rig.now = PimpChannel.date("2026-09-19T19:00:13Z")!
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: trelvis,
                       frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 4, title: "New chat", chat: "local_4", folder: trelvis,
                       frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        write(request("1789850010000-0203", action: "close-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\""), id: "1789850010000-0203", in: box)
        channel.tick()
        XCTAssertEqual(try resultText("1789850010000-0203", in: box),
                       try fixtureText("close-window-main.error.json"))
        XCTAssertTrue(rig.closed.isEmpty)

        // Карта чатов молчит — папки окон неизвестны, окон проекта не находится.
        rig.advance(1)
        rig.windows = [PimpWindow(id: 5, title: "Дубли задач",
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        write(request("930-0004", action: "close-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\""), id: "930-0004", in: box)
        channel.tick()
        XCTAssertEqual(result("930-0004", in: box)?["error"] as? String, "window-missing")

        // Кнопки закрытия у окна нет — «закрыл» без закрытия не пишем.
        rig.advance(1)
        rig.canClose = false
        rig.windows = [PimpWindow(id: 6, title: "Дубли задач", chat: "local_6", folder: trelvis,
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        write(request("930-0005", action: "close-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\""), id: "930-0005", in: box)
        channel.tick()
        XCTAssertEqual(result("930-0005", in: box)?["error"] as? String, "window-missing")
        XCTAssertTrue(rig.closed.isEmpty)
    }

    /// Два окна, которые приложение зовёт главными (безымянный попап носит ту же заглушку):
    /// не трогаем ничего, как `layout-save` (#5534).
    func testPimpChannelRefusesToCloseWithTwoMainWindows() throws {
        let box = makeTemp()
        let rig = PimpRig()
        let trelvis = "/Users/dev/Projects/TrelvisCom"
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: trelvis,
                       frame: CGRect(x: 0, y: 34, width: 490, height: 859)),
            PimpWindow(id: 2, title: "Claude", chat: "local_2", folder: trelvis,
                       frame: CGRect(x: 490, y: 34, width: 490, height: 859)),
            PimpWindow(id: 3, title: "Дубли задач", chat: "local_3", folder: trelvis,
                       frame: CGRect(x: 980, y: 34, width: 490, height: 859)),
        ]
        let channel = makeChannel(rig, in: box)

        write(request("940-0001", action: "close-window", at: rig.now,
                      extra: ",\"project\":\"TrelvisCom\""), id: "940-0001", in: box)
        channel.tick()
        let answer = try XCTUnwrap(result("940-0001", in: box))
        XCTAssertEqual(answer["error"] as? String, "ambiguous")
        XCTAssertEqual(answer["windows"] as? [String], ["Claude", "Claude"])
        XCTAssertTrue(rig.closed.isEmpty)
    }

    func testPimpChannelPastesFilesIntoFrontWindow() throws {
        let box = makeTemp()
        let files = makeTemp()
        let one = files.appendingPathComponent("IMG_0001.jpeg")
        let two = files.appendingPathComponent("IMG_0002.jpeg")
        try Data("1".utf8).write(to: one)
        try Data("2".utf8).write(to: two)
        let rig = PimpRig()
        rig.windows = [
            PimpWindow(id: 7, title: "Сайт: корзина", chat: "local_7",
                       folder: "/Users/dev/Projects/VkusnoffKz",
                       frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 8, title: "Диктаторик",
                       frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        rig.front = 7
        let channel = makeChannel(rig, in: box)

        write(request("950-0001", action: "paste", at: rig.now,
                      extra: ",\"front\":true,\"paths\":[\"\(one.path)\",\"\(two.path)\"]"),
              id: "950-0001", in: box)
        channel.tick()
        XCTAssertEqual(rig.pastes.first?.id, 7)
        XCTAssertEqual(rig.pastes.first?.paths, [one.path, two.path])
        let answer = try XCTUnwrap(result("950-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["pasted"] as? Int, 2)
        XCTAssertEqual(answer["window"] as? String, "Сайт: корзина")

        // Claude позади — ⌘V ушёл бы в чужую программу, поэтому не вставляем вовсе.
        rig.front = nil
        rig.advance(1)
        write(request("950-0002", action: "paste", at: rig.now,
                      extra: ",\"front\":true,\"paths\":[\"\(one.path)\"]"), id: "950-0002", in: box)
        channel.tick()
        XCTAssertEqual(result("950-0002", in: box)?["error"] as? String, "no-windows")
        XCTAssertEqual(rig.pastes.count, 1)

        // Путь абсолютный, а файла нет (или это папка) — bad-request, и ничего не нажимаем.
        rig.front = 7
        rig.advance(1)
        write(request("950-0003", action: "paste", at: rig.now,
                      extra: ",\"front\":true,\"paths\":[\"\(files.path)/нет-такого.jpg\"]"),
              id: "950-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("950-0003", in: box)?["error"] as? String, "bad-request")
        rig.advance(1)
        write(request("950-0004", action: "paste", at: rig.now,
                      extra: ",\"front\":true,\"paths\":[\"\(files.path)\"]"), id: "950-0004", in: box)
        channel.tick()
        XCTAssertEqual(result("950-0004", in: box)?["error"] as? String, "bad-request")
        XCTAssertEqual(rig.pastes.count, 1)
    }

    func testPimpChannelPastesByChatAndProject() throws {
        let box = makeTemp()
        let rig = PimpRig()
        let vkus = "/Users/dev/Projects/VkusnoffKz"
        rig.windows = [
            PimpWindow(id: 7, title: "Сайт: корзина", chat: "local_7", folder: vkus,
                       frame: CGRect(x: 0, y: 34, width: 735, height: 859)),
            PimpWindow(id: 8, title: "Диктаторик", chat: "local_8",
                       folder: "/Users/dev/Projects/Dictator",
                       frame: CGRect(x: 735, y: 34, width: 735, height: 859)),
        ]
        let channel = makeChannel(rig, in: box)

        // Чат назван — вставляем в его окно, и это видно по fromResolved.
        write(request("960-0001", action: "paste", at: rig.now, from: "local_7"),
              id: "960-0001", in: box)
        channel.tick()
        let byChat = try XCTUnwrap(result("960-0001", in: box))
        XCTAssertEqual(byChat["fromResolved"] as? Bool, true)
        XCTAssertEqual(byChat["pasted"] as? Int, 0, "буфер вставляем как есть")
        XCTAssertEqual(byChat["window"] as? String, "Сайт: корзина")
        XCTAssertEqual(rig.pastes.first?.id, 7)
        XCTAssertTrue(rig.pastes.first?.paths.isEmpty ?? false, "буфер не трогаем")

        // Чата нет — единственное окно проекта (эталон paste-clipboard.request.json).
        rig.advance(1)
        write(request("960-0002", action: "paste", at: rig.now,
                      extra: ",\"project\":\"VkusnoffKz\""), id: "960-0002", in: box)
        channel.tick()
        let byProject = try XCTUnwrap(result("960-0002", in: box))
        XCTAssertEqual(byProject["ok"] as? Bool, true)
        XCTAssertEqual(byProject["fromResolved"] as? Bool, false)
        XCTAssertEqual(rig.pastes.last?.id, 7)

        // Два окна проекта — не гадаем.
        rig.advance(1)
        rig.windows.append(PimpWindow(id: 9, title: "Сайт: доставка", chat: "local_9",
                                      folder: vkus,
                                      frame: CGRect(x: 0, y: 34, width: 200, height: 200)))
        write(request("960-0003", action: "paste", at: rig.now,
                      extra: ",\"project\":\"VkusnoffKz\""), id: "960-0003", in: box)
        channel.tick()
        let many = try XCTUnwrap(result("960-0003", in: box))
        XCTAssertEqual(many["error"] as? String, "ambiguous")
        XCTAssertEqual(many["windows"] as? [String], ["Сайт: корзина", "Сайт: доставка"])

        // Окон проекта нет вовсе.
        rig.advance(1)
        write(request("960-0004", action: "paste", at: rig.now,
                      extra: ",\"project\":\"SkilZZZ\""), id: "960-0004", in: box)
        channel.tick()
        XCTAssertEqual(result("960-0004", in: box)?["error"] as? String, "window-missing")

        // Окно пропало между выбором и нажатием — «вставил» не пишем.
        rig.advance(1)
        rig.pasteWorks = false
        write(request("960-0005", action: "paste", at: rig.now, from: "local_7"),
              id: "960-0005", in: box)
        channel.tick()
        XCTAssertEqual(result("960-0005", in: box)?["error"] as? String, "window-missing")
    }

    /// Плашка отвечает и когда канал занят долгой работой: её ветка стоит ВЫШЕ проверки
    /// занятости (критик Б12). Остальные действия в это время честно получают `busy`.
    func testPimpChannelShowsHudEvenWhenBusy() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-19T19:00:20Z")!
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.windows = [PimpWindow(id: 1, title: "Claude",
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let channel = makeChannel(rig, in: box)

        write(request("970-0001", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"right\""),
              id: "970-0001", in: box)
        channel.tick()
        XCTAssertNil(result("970-0001", in: box), "канал занят открытием окна")

        rig.advance(10)
        write(try fixtureText("hud.request.json"), id: "1789850030000-0401", in: box)
        write(request("970-0002", action: "arrange", at: rig.now), id: "970-0002", in: box)
        channel.tick()
        XCTAssertEqual(try resultText("1789850030000-0401", in: box),
                       try fixtureText("hud.result.json"))
        XCTAssertEqual(rig.notices.last, "Открыл 3 чата: VkusnoffKz, TrelvisCom, Dictator")
        XCTAssertEqual(result("970-0002", in: box)?["error"] as? String, "busy")
        XCTAssertTrue(rig.arranged.isEmpty, "плашка окон не трогает")
        XCTAssertNil(result("970-0001", in: box), "работа канала не сбилась")
    }

    // MARK: - 7. точка и уборка

    func testPimpChannelPassesPointToPageAndCleansOldFiles() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.projects = [PimpChannelTests.project("Dictator")]
        rig.windows = [PimpWindow(id: 1, title: "Claude",
                                  frame: CGRect(x: 0, y: 34, width: 1470, height: 859))]
        let channel = makeChannel(rig, in: box)

        write(request("800-0001", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"200,120\""),
              id: "800-0001", in: box)
        channel.tick()
        // Точку ставит сама страница — окно родится там же, и двигать его потом не надо.
        XCTAssertEqual(rig.opened.first?.origin?.x, 200)
        XCTAssertEqual(rig.opened.first?.origin?.y, 120)
        rig.advance(3)
        rig.windows.append(PimpWindow(id: 2, title: "Диктаторик",
                                      frame: CGRect(x: 200, y: 120, width: 900, height: 700)))
        channel.tick()
        XCTAssertTrue(rig.arranged.isEmpty)
        XCTAssertEqual((result("800-0001", in: box)?["window"] as? [String: Any])?["frame"] as? [Int],
                       [200, 120, 900, 700])

        // Файлы старше часа канал убирает сам (проверяет не чаще раза в минуту).
        let old = box.appendingPathComponent("1-0001.json")
        try Data("{}".utf8).write(to: old)
        try FileManager.default.setAttributes(
            [.modificationDate: rig.now.addingTimeInterval(-7200)], ofItemAtPath: old.path)
        rig.advance(61)
        channel.tick()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: box.appendingPathComponent("800-0001.result.json").path))
    }

    // MARK: - 8. поиск папки

    func testPimpFindsProjectByNameAndPath() throws {
        let box = makeTemp()
        let known = [PimpChannelTests.project("PimpMyClaude"), PimpChannelTests.project("Dictator")]
        XCTAssertEqual(PimpChannel.project(named: " Dictator ", in: known)?.name, "Dictator")
        XCTAssertEqual(PimpChannel.project(named: "pimpmyclaude", in: known)?.name, "PimpMyClaude")
        XCTAssertNil(PimpChannel.project(named: "Диктаторик", in: known))
        XCTAssertNil(PimpChannel.project(named: "  ", in: known))
        // Абсолютный путь берётся как есть, но только если папка правда есть на диске.
        XCTAssertEqual(PimpChannel.project(named: box.path, in: [])?.folder.path,
                       box.standardizedFileURL.path)
        XCTAssertNil(PimpChannel.project(named: box.path + "/нет-такой", in: []))
    }

    // MARK: - 9. ширина ячейки из живого claude.json

    func testPimpCellWidthComesFromLiveConfig() throws {
        let box = makeTemp()
        let config = box.appendingPathComponent("claude.json")
        // У Элвиса в живом файле 280 — уже этой ширины Electron окно всё равно не сделает.
        try Data("{\"minWindowWidth\":280,\"sidePadding\":5}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.minCellWidth(configURL: config), 280)
        // Пять столбцов на 15" вместо четырёх — ровно то, ради чего значение читается.
        XCTAssertEqual(ArrangeLayout.columns(count: 5, width: 1470, minCellWidth: 280), 5)
        XCTAssertEqual(ArrangeLayout.columns(count: 5, width: 1470), 4)

        // Ключа нет, файл битый, файла нет вовсе — 360, как в патче.
        try Data("{\"sidePadding\":5}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.minCellWidth(configURL: config), 360)
        try Data("{".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.minCellWidth(configURL: config), 360)
        XCTAssertEqual(ClaudeActions.minCellWidth(
            configURL: box.appendingPathComponent("нет.json")), 360)
        try Data("{\"minWindowWidth\":0}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.minCellWidth(configURL: config), 360)
    }

    /// Зазор между окнами читается из того же живого файла и тем же способом (план WF77,
    /// слово Элвиса 20.09: «должна быть настройка, сколько пикселей; по умолчанию — как у
    /// меня сейчас»). Пункта меню у ключа нет — файл правится руками, поэтому мусор и
    /// перебор зажимаются, а не разъезжают окна.
    func testPimpWindowGapComesFromLiveConfig() throws {
        let box = makeTemp()
        let config = box.appendingPathComponent("claude.json")
        try Data("{\"minWindowWidth\":280,\"sidePadding\":5,\"windowGap\":8}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.windowGap(configURL: config), 8)
        // Ключа нет, файл битый, файла нет вовсе — 5, как в `Patcher.configDefaults`.
        try Data("{\"minWindowWidth\":280}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.windowGap(configURL: config), 5)
        try Data("{".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.windowGap(configURL: config), 5)
        XCTAssertEqual(ClaudeActions.windowGap(
            configURL: box.appendingPathComponent("нет.json")), 5)
        // Зажим 0…40: ноль — окна встык (так было до WF77), сотня — 40.
        try Data("{\"windowGap\":0}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.windowGap(configURL: config), 0)
        try Data("{\"windowGap\":-7}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.windowGap(configURL: config), 0)
        try Data("{\"windowGap\":100}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.windowGap(configURL: config), 40)
        try Data("{\"windowGap\":\"пять\"}".utf8).write(to: config)
        XCTAssertEqual(ClaudeActions.windowGap(configURL: config), 5)
    }

    // MARK: - 10. окно по заголовку

    func testPimpWindowByTitleIgnoresDoubles() {
        let windows = [PimpWindow(id: 1, title: "Claude"), PimpWindow(id: 2, title: "Claude"),
                       PimpWindow(id: 3, title: " Пимп ")]
        XCTAssertEqual(PimpChannel.window(title: "Пимп", in: windows)?.id, 3)
        XCTAssertNil(PimpChannel.window(title: "Claude", in: windows), "заголовок носят двое")
        XCTAssertNil(PimpChannel.window(title: "  ", in: windows))
    }

    // MARK: - WF102: замена окна (#7917) и «главный по центру» (#7904)

    private static let rick = "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"
    private static let vkusChat = "local_82e41ae2-720f-4bf2-a0cd-68862ea6148e"
    private static let risoChat = "local_98141d87-8668-49b9-a735-013ed8822b27"
    private static let freshChat = "local_9f1c2d3e-0000-4000-8000-000000000102"
    private static let odyssey = CGRect(x: -800, y: -720, width: 2560, height: 720)
    private static let root = "/Users/dev/Projects/"

    /// Стенд замены: главное окно Рика по центру Одиссея, окна VkusnoffKz и Risovalka слева.
    private func renewRig() -> PimpRig {
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-26T18:30:00Z")!
        rig.projects = [PimpChannelTests.project("VkusnoffKz"), PimpChannelTests.project("Risovalka")]
        rig.windows = [
            PimpWindow(id: 1, title: "Claude", chat: PimpChannelTests.rick,
                       folder: PimpChannelTests.root + "Rick", frame: CGRect(x: 54, y: -720, width: 852, height: 720)),
            PimpWindow(id: 2, title: "Страница скачивания приложения", chat: PimpChannelTests.vkusChat,
                       folder: PimpChannelTests.root + "VkusnoffKz",
                       frame: CGRect(x: -800, y: -720, width: 283, height: 720)),
            PimpWindow(id: 4, title: "Мультяшные персонажи", chat: PimpChannelTests.risoChat,
                       folder: PimpChannelTests.root + "Risovalka",
                       frame: CGRect(x: -515, y: -720, width: 282, height: 720)),
        ]
        return rig
    }

    /// Что канал попросил открыть для замены.
    private final class RenewLog {
        var calls: [(project: Project, origin: (x: Int, y: Int), text: String?, handoff: NewChatHandoff)] = []
    }

    private func watchRenew(_ channel: PimpChannel) -> RenewLog {
        let log = RenewLog()
        channel.seats.openRenewWindow = { project, origin, text, handoff in
            log.calls.append((project: project, origin: origin, text: text, handoff: handoff))
        }
        return log
    }

    private func renewBody(_ id: String, at: String, chat: String? = nil, project: String? = nil,
                           extra: String = "") -> String {
        var body = "{\"id\":\"\(id)\",\"at\":\"\(at)\",\"action\":\"renew-window\","
            + "\"from\":\"\(PimpChannelTests.rick)\""
        if let chat = chat { body += ",\"chat\":\"\(chat)\"" }
        if let project = project { body += ",\"project\":\"\(project)\"" }
        return body + extra + "}"
    }

    func testPimpParsesWF102Requests() throws {
        let renew = try XCTUnwrap(PimpRequest.parse(fixture("renew-window.request.json")))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("renew-window.request.json"))
                                as? [String: Any])
        XCTAssertEqual(renew.action, .renewWindow)
        XCTAssertEqual(renew.chat, PimpChannelTests.vkusChat)
        XCTAssertEqual(renew.project, "")
        XCTAssertEqual(renew.text, raw["text"] as? String)
        XCTAssertEqual(renew.model, "Opus 5.5")
        XCTAssertEqual(renew.effort, "extra")

        let byProject = try XCTUnwrap(PimpRequest.parse(fixture("renew-window-project.request.json")))
        XCTAssertEqual(byProject.project, "Risovalka")
        XCTAssertEqual(byProject.chat, "")
        XCTAssertEqual(byProject.text, "", "нет текста — штатный")
        XCTAssertEqual(byProject.model, "")

        func parse(_ extra: String, chat: String? = PimpChannelTests.vkusChat,
                   project: String? = nil) -> PimpRequest? {
            PimpRequest.parse(Data(renewBody("1-1", at: "2026-09-26T18:30:00Z", chat: chat,
                                             project: project, extra: extra).utf8))
        }
        XCTAssertNil(parse("", project: "Risovalka"), "ровно одно из chat и project")
        XCTAssertNil(parse("", chat: nil), "ни окна, ни проекта")
        XCTAssertNil(parse("", chat: "last"), "chat — только local_<uuid>")
        XCTAssertNil(parse("", chat: PimpChannelTests.vkusChat.uppercased()))
        // Текст не режется до 200, как у плашки, — только потолок 20 000.
        let long = String(repeating: "я", count: PimpChannel.renewTextLimit)
        XCTAssertEqual(parse(",\"text\":\"\(long)\"")?.text.count, PimpChannel.renewTextLimit)
        XCTAssertNil(parse(",\"text\":\"\(long)я\""))
        XCTAssertEqual(parse(",\"effort\":\" High \"")?.effort, "high")
        XCTAssertNil(parse(",\"effort\":\"ultracode\""), "эффорт — слова контракта")
        XCTAssertNil(parse(",\"model\":5"))

        let center = try XCTUnwrap(PimpRequest.parse(fixture("arrange-center.request.json")))
        XCTAssertEqual(center.action, .arrange)
        XCTAssertEqual(center.layout, .center)
        XCTAssertEqual(center.center, "Rick")
        XCTAssertEqual(center.order?.count, 6)
        // `center` у чужого действия не читается.
        let windows = Data("{\"id\":\"1-1\",\"at\":\"2026-09-26T18:40:00Z\",\"action\":\"windows\",\"center\":\"Rick\"}".utf8)
        XCTAssertEqual(PimpRequest.parse(windows)?.center, "")
    }

    /// Замена по эталону: новое окно рождается в углу донора, встаёт в его рамку, донор
    /// закрывается, только когда известен id нового чата; модель сверяется по файлу сессии.
    func testPimpRenewReplacesWindowAndMatchesFixture() throws {
        let box = makeTemp()
        let rig = renewRig()
        let channel = makeChannel(rig, in: box)
        let log = watchRenew(channel)
        channel.seats.chatModel = { chat in
            chat == PimpChannelTests.freshChat
                ? SessionModel(model: "claude-opus-5-5", effort: "xhigh", auto: false) : nil
        }
        let id = "1790450000000-0102"
        try fixture("renew-window.request.json").write(to: box.appendingPathComponent(id + ".json"))
        channel.tick()

        let call = try XCTUnwrap(log.calls.first)
        XCTAssertEqual(log.calls.count, 1)
        XCTAssertEqual(call.project.name, "VkusnoffKz", "проект — папка донора")
        XCTAssertTrue(call.origin == (x: -776, y: -696), "окно рождается со сдвигом от угла донора")
        XCTAssertEqual(call.text, try PimpRequest.parse(fixture("renew-window.request.json"))?.text)
        // Без закрепки (WF181, #9225): ни `pin`, ни `unpin` донора.
        XCTAssertEqual(call.handoff, NewChatHandoff(model: "Opus 5.5", effort: "extra", stay: false,
                                                    transfer: false, pin: false))
        XCTAssertNil(result(id, in: box))
        XCTAssertTrue(channel.isBusy)

        // Сердцебиение (C2): пока ждём окно, метка `<id>.taken` переписывается на каждом тике.
        let taken = box.appendingPathComponent(id + ".taken")
        try FileManager.default.removeItem(at: taken)
        rig.advance(2)
        channel.tick()
        XCTAssertTrue(FileManager.default.fileExists(atPath: taken.path))

        rig.now = PimpChannel.date("2026-09-26T18:30:21Z")!
        rig.windows.append(PimpWindow(id: 3, title: "Ожидание задачи", chat: PimpChannelTests.freshChat,
                                      folder: PimpChannelTests.root + "VkusnoffKz",
                                      frame: CGRect(x: -800, y: -720, width: 900, height: 700)))
        channel.tick()
        XCTAssertEqual(try resultText(id, in: box), try fixtureText("renew-window.result.json"))
        XCTAssertEqual(rig.closed, [2], "донор закрыт")
        XCTAssertEqual(rig.window(3)?.frame, CGRect(x: -800, y: -720, width: 283, height: 720),
                       "новое окно — ровно в рамке донора")
        XCTAssertFalse(channel.isBusy)
    }

    /// По проекту: окно проекта ищется как у `close-window`; id нового чата сказала страница
    /// (карта чатов ещё молчит); модель не встала — `missed`, донор всё равно закрыт.
    func testPimpRenewByProjectTakesChatFromPageAndSaysModelMissed() throws {
        let box = makeTemp()
        let rig = renewRig()
        let channel = makeChannel(rig, in: box)
        let log = watchRenew(channel)
        let start = rig.now
        channel.seats.newWindowRun = {
            NewWindowRun(at: start.addingTimeInterval(4), step: "back", handoff: "",
                         chat: PimpChannelTests.freshChat, state: "ok")
        }
        channel.seats.chatModel = { _ in SessionModel(model: "claude-sonnet-4-5", effort: "", auto: false) }
        write(renewBody("300-0001", at: "2026-09-26T18:30:00Z", project: "Risovalka",
                        extra: ",\"model\":\"Opus 5.5\""), id: "300-0001", in: box)
        channel.tick()
        XCTAssertEqual(log.calls.first?.project.name, "Risovalka")
        XCTAssertNil(log.calls.first?.text, "нет текста — штатный")
        XCTAssertNil(log.calls.first?.handoff.unpin, "донора не открепляем (WF181)")
        XCTAssertEqual(log.calls.first?.handoff.pin, false)

        rig.advance(5)
        rig.windows.append(PimpWindow(id: 5, title: "Ожидание задачи",
                                      frame: CGRect(x: -515, y: -720, width: 900, height: 700)))
        channel.tick()
        let answer = try XCTUnwrap(result("300-0001", in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["replaced"] as? String, PimpChannelTests.risoChat)
        XCTAssertEqual((answer["window"] as? [String: Any])?["chat"] as? String, PimpChannelTests.freshChat)
        XCTAssertEqual((answer["window"] as? [String: Any])?["frame"] as? [Int], [-515, -720, 282, 720])
        XCTAssertEqual(answer["model"] as? String, "missed")
        XCTAssertEqual(rig.closed, [4])
    }

    /// Id нового чата не опознан за 10 с после рождения окна — `chat-unknown` по эталону,
    /// донор НЕ закрыт, новое окно стоит в его рамке.
    func testPimpRenewKeepsDonorWhenChatUnknown() throws {
        let box = makeTemp()
        let rig = renewRig()
        rig.now = PimpChannel.date("2026-09-26T18:33:00Z")!
        let channel = makeChannel(rig, in: box)
        _ = watchRenew(channel)
        let id = "1790450000000-0106"
        write(renewBody(id, at: "2026-09-26T18:33:00Z", chat: PimpChannelTests.risoChat), id: id, in: box)
        channel.tick()
        rig.now = PimpChannel.date("2026-09-26T18:33:05Z")!
        rig.windows.append(PimpWindow(id: 6, title: "Ожидание задачи",
                                      frame: CGRect(x: -515, y: -720, width: 900, height: 700)))
        channel.tick()
        rig.advance(9)
        channel.tick()
        XCTAssertNil(result(id, in: box), "ждём id чата 10 с")
        rig.advance(1)
        channel.tick()
        XCTAssertEqual(try resultText(id, in: box), try fixtureText("renew-window-unknown.error.json"))
        XCTAssertTrue(rig.closed.isEmpty, "донор остаётся")
        XCTAssertFalse(channel.isBusy)
    }

    /// Отказы: отказ страницы (эталон), окна нет, два окна проекта. С WF131 чат главного окна —
    /// не отказ `main-window`, а замена (тесты `testPimpRenewMainWindow…`).
    func testPimpRenewRefusals() throws {
        let box = makeTemp()
        let rig = renewRig()
        rig.now = PimpChannel.date("2026-09-26T18:30:02Z")!
        let channel = makeChannel(rig, in: box)
        let log = watchRenew(channel)

        write(renewBody("300-0002", at: "2026-09-26T18:30:02Z",
                        chat: "local_00000000-0000-4000-8000-000000000000"), id: "300-0002", in: box)
        channel.tick()
        XCTAssertEqual(result("300-0002", in: box)?["error"] as? String, "window-missing")
        XCTAssertTrue(log.calls.isEmpty)

        // Два окна проекта — не гадаем.
        rig.windows.append(PimpWindow(id: 7, title: "Второй Рисовалки", chat: "local_2",
                                      folder: PimpChannelTests.root + "Risovalka",
                                      frame: CGRect(x: 1193, y: -720, width: 282, height: 720)))
        write(renewBody("300-0003", at: "2026-09-26T18:30:02Z", project: "Risovalka"), id: "300-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("300-0003", in: box)?["error"] as? String, "ambiguous")
        XCTAssertEqual(result("300-0003", in: box)?["windows"] as? [String],
                       ["Мультяшные персонажи", "Второй Рисовалки"])

        // Страница сказала «сообщение не ушло» — `chat-not-created` сразу, донор цел.
        rig.now = PimpChannel.date("2026-09-26T18:31:00Z")!
        let id = "1790450000000-0104"
        write(renewBody(id, at: "2026-09-26T18:31:00Z", chat: PimpChannelTests.vkusChat), id: id, in: box)
        channel.tick()
        XCTAssertEqual(log.calls.count, 1)
        let start = rig.now
        channel.seats.newWindowRun = {
            NewWindowRun(at: start.addingTimeInterval(3), step: "session", handoff: "", chat: "", state: "no-send")
        }
        rig.now = PimpChannel.date("2026-09-26T18:31:04Z")!
        channel.tick()
        XCTAssertEqual(try resultText(id, in: box), try fixtureText("renew-window-not-created.error.json"))
        XCTAssertTrue(rig.closed.isEmpty)
    }

    /// Стенд замены главного окна: Рик в главном, исход цепочки страницы и команды `main-chat`
    /// (их быть не должно — с WF181 новый чат открывается в самом главном окне).
    private final class MainRenewLog {
        var sent: [(chat: String, origin: (x: Int, y: Int))] = []
        var run: NewWindowRun?
    }

    private func mainRenewRig() -> (PimpRig, PimpChannel, URL, RenewLog, MainRenewLog) {
        let box = makeTemp()
        let rig = renewRig()
        rig.projects.append(PimpChannelTests.project("Rick"))
        let channel = makeChannel(rig, in: box)
        let log = watchRenew(channel)
        let main = MainRenewLog()
        channel.seats.sendMainChat = { chat, origin in main.sent.append((chat: chat, origin: origin)) }
        channel.seats.newWindowRun = { main.run }
        return (rig, channel, box, log, main)
    }

    /// Ошибка #9225 (слово Элвиса 09.10 03:20: «Зачем ты открываешь новое окно? Мы работаем сейчас
    /// в одном окне, всегда. Не закрепляй»): замена чата главного окна — новый чат в САМОМ главном
    /// окне (`stay`), без закрепки, без второго окна и без `main-chat`; ничего не закрывается и не
    /// двигается, прежний чат остаётся в списке слева.
    func testPimpRenewMainWindowOpensNewChatInSameWindowWithoutPin() throws {
        let (rig, channel, box, log, main) = mainRenewRig()
        let id = "1790450000000-0131"
        write(renewBody(id, at: "2026-09-26T18:30:00Z", project: "Rick",
                        extra: ",\"text\":\"Передача Рика\""), id: id, in: box)
        channel.tick()
        let call = try XCTUnwrap(log.calls.first)
        XCTAssertEqual(call.project.name, "Rick")
        XCTAssertEqual(call.text, "Передача Рика")
        XCTAssertEqual(call.handoff, NewChatHandoff(model: nil, effort: nil, stay: true, transfer: false, pin: false),
                       "в том же окне и без закрепки")
        XCTAssertTrue(channel.isBusy)

        // Страница ещё идёт — ответа нет.
        rig.advance(3)
        main.run = NewWindowRun(at: rig.now, step: "send", handoff: "", chat: "", state: "run", busy: true)
        channel.tick()
        XCTAssertNil(result(id, in: box))

        // Главное окно встало на новый чат.
        rig.advance(3)
        rig.windows[0] = PimpWindow(id: 1, title: "Новый Рик", chat: PimpChannelTests.freshChat,
                                    folder: PimpChannelTests.root + "Rick", frame: rig.windows[0].frame)
        channel.tick()
        let answer = try XCTUnwrap(result(id, in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["main"] as? Bool, true)
        XCTAssertEqual(answer["replaced"] as? String, PimpChannelTests.rick)
        XCTAssertNil(answer["model"])
        let window = try XCTUnwrap(answer["window"] as? [String: Any])
        XCTAssertEqual(window["chat"] as? String, PimpChannelTests.freshChat)
        XCTAssertEqual(window["title"] as? String, "Новый Рик")
        XCTAssertEqual(window["frame"] as? [Int], [54, -720, 852, 720])
        XCTAssertTrue(rig.closed.isEmpty, "закрывать нечего — второго окна нет")
        XCTAssertTrue(rig.moved.isEmpty, "главное окно не двигаем")
        XCTAssertTrue(main.sent.isEmpty, "`main-chat` не нужен")
        XCTAssertTrue(rig.popouts.isEmpty, "чатов окнами не выносим")
        XCTAssertFalse(channel.isBusy)
    }

    /// Чат назвала цепочка страницы раньше карты чатов; модель ждём по файлу сессии.
    func testPimpRenewMainWindowTakesChatFromPageAndChecksModel() throws {
        let (rig, channel, box, _, main) = mainRenewRig()
        let id = "1790450000000-0132"
        write(renewBody(id, at: "2026-09-26T18:30:00Z", chat: PimpChannelTests.rick,
                        extra: ",\"model\":\"Opus 5.5\""), id: id, in: box)
        var model: SessionModel?
        channel.seats.chatModel = { _ in model }
        channel.tick()
        rig.advance(4)
        main.run = NewWindowRun(at: rig.now, step: "stay", handoff: "", chat: PimpChannelTests.freshChat, state: "ok")
        channel.tick()
        XCTAssertNil(result(id, in: box), "файла сессии ещё нет — ждём модель")
        model = SessionModel(model: "claude-opus-5-5", effort: "", auto: false)
        rig.advance(1)
        channel.tick()
        let answer = try XCTUnwrap(result(id, in: box))
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["model"] as? String, "ok")
        XCTAssertEqual((answer["window"] as? [String: Any])?["chat"] as? String, PimpChannelTests.freshChat)
        XCTAssertTrue(rig.closed.isEmpty)
    }

    /// Страница закончила «на месте», а чата нет (текст не ушёл) — `chat-not-created`/`no-send`
    /// сразу: CLI не повторяет и второй чат не заводит; отказ страницы — её исход.
    func testPimpRenewMainWindowRefusesWhenPageSentNothing() throws {
        let (rig, channel, box, _, main) = mainRenewRig()
        write(renewBody("300-0131", at: "2026-09-26T18:30:00Z", chat: PimpChannelTests.rick), id: "300-0131", in: box)
        channel.tick()
        rig.advance(2)
        main.run = NewWindowRun(at: rig.now, step: "stay", handoff: "", chat: "", state: "ok")
        channel.tick()
        XCTAssertEqual(result("300-0131", in: box)?["error"] as? String, "chat-not-created")
        XCTAssertEqual(result("300-0131", in: box)?["state"] as? String, "no-send")

        rig.advance(60)
        write(renewBody("300-0132", at: "2026-09-26T18:31:02Z", chat: PimpChannelTests.rick), id: "300-0132", in: box)
        channel.tick()
        rig.advance(2)
        main.run = NewWindowRun(at: rig.now, step: "folder", handoff: "", chat: "", state: "no-folder")
        channel.tick()
        XCTAssertEqual(result("300-0132", in: box)?["state"] as? String, "no-folder")
        XCTAssertTrue(rig.closed.isEmpty)
        XCTAssertFalse(channel.isBusy)
    }

    /// Стенд «главного по центру»: семь окон эталона на Одиссее вразнобой и одно на MacBook.
    private func centerRig(_ channel: PimpChannel, rig: PimpRig, arranged: @escaping ([CGWindowID]) -> Void) {
        rig.gap = 2
        channel.seats.screens = {
            [(full: CGRect(x: 0, y: 0, width: 1280, height: 832), usable: CGRect(x: 0, y: 38, width: 1280, height: 740)),
             (full: PimpChannelTests.odyssey, usable: PimpChannelTests.odyssey)]
        }
        channel.seats.cellWidth = { 220 }
        channel.seats.arrange = { [unowned rig] ids, mode, _ in
            arranged(ids)
            let cells = ArrangeLayout.frames(count: ids.count, in: PimpChannelTests.odyssey, mode: mode,
                                             minCellWidth: 220, gap: 2)
            var out: [PimpWindow] = []
            for (index, id) in ids.enumerated() {
                guard let window = rig.window(id), index < cells.count else { continue }
                let placed = PimpWindow(id: id, title: window.title, chat: window.chat,
                                        folder: window.folder, frame: cells[index])
                out.append(placed)
                if let at = rig.windows.firstIndex(where: { $0.id == id }) { rig.windows[at] = placed }
            }
            return (windows: out, skipped: ids.count - out.count)
        }
    }

    private func centerWindows() throws -> [PimpWindow] {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("arrange-center.result.json"))
                                 as? [String: Any])
        let list = try XCTUnwrap(json["windows"] as? [[String: Any]])
        // Стоят вразнобой: порядок по рамкам не совпадает ни с `order`, ни с итогом.
        let scattered: [CGFloat] = [900, -800, 1400, -300, 300, 1150, -550]
        return list.enumerated().map { index, item in
            PimpWindow(id: CGWindowID(10 + index), title: item["title"] as? String ?? "",
                       chat: item["chat"] as? String ?? "", folder: item["folder"] as? String ?? "",
                       frame: CGRect(x: scattered[index], y: -700, width: 400, height: 600))
        }
    }

    /// «Главный по центру» по эталону: Рик — четвёртым шириной в треть, остальные по `order`,
    /// окно на MacBook не трогается вовсе.
    func testPimpArrangesCenterLikeFixture() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-26T18:40:02Z")!
        rig.mainTitle = "Claude"
        let macbook = PimpWindow(id: 99, title: "SkilZZZ", chat: "local_mac", folder: PimpChannelTests.root + "SkilZZZ",
                                 frame: CGRect(x: 100, y: 100, width: 600, height: 600))
        rig.windows = try centerWindows() + [macbook]
        let channel = makeChannel(rig, in: box)
        var arranged: [[CGWindowID]] = []
        centerRig(channel, rig: rig) { arranged.append($0) }
        let id = "1790450010000-0701"
        try fixture("arrange-center.request.json").write(to: box.appendingPathComponent(id + ".json"))
        channel.tick()
        XCTAssertEqual(try resultText(id, in: box), try fixtureText("arrange-center.result.json"))
        XCTAssertEqual(arranged, [[10, 11, 12, 13, 14, 15, 16]])
        XCTAssertEqual(rig.window(99)?.frame, macbook.frame, "окно другого экрана не тронуто")
    }

    /// WF103 (#7954): окно проекта из `order`, съехавшее на MacBook, возвращается на экран
    /// главного; окно вне `order` на MacBook остаётся где стояло.
    func testPimpCenterBringsOrderWindowFromOtherScreen() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-26T18:40:02Z")!
        var windows = try centerWindows()
        // Marketolog (id 12) после блокировки экрана — на MacBook.
        let away = windows[2]
        windows[2] = PimpWindow(id: away.id, title: away.title, chat: away.chat, folder: away.folder,
                                frame: CGRect(x: 200, y: 100, width: 600, height: 600))
        let stranger = PimpWindow(id: 99, title: "SkilZZZ", chat: "local_mac", folder: PimpChannelTests.root + "SkilZZZ",
                                  frame: CGRect(x: 100, y: 100, width: 600, height: 600))
        rig.windows = windows + [stranger]
        let channel = makeChannel(rig, in: box)
        var arranged: [[CGWindowID]] = []
        centerRig(channel, rig: rig) { arranged.append($0) }
        let id = "1790450010000-0702"
        try fixture("arrange-center.request.json").write(to: box.appendingPathComponent(id + ".json"))
        channel.tick()
        XCTAssertEqual(result(id, in: box)?["ok"] as? Bool, true)
        XCTAssertEqual(arranged, [[10, 11, 12, 13, 14, 15, 16]], "окно Marketolog взято с MacBook")
        XCTAssertTrue(PimpChannelTests.odyssey.contains(try XCTUnwrap(rig.window(12)).frame),
                      "и стоит на экране главного")
        XCTAssertEqual(rig.window(99)?.frame, stranger.frame, "окно вне order на MacBook не тронуто")
    }

    /// Кто главный: без ключа — окно чата `from`, без него — главное окно; чужое имя —
    /// `window-missing`, два окна проекта — `ambiguous`; тесно — `too-small`, окон не двигаем.
    func testPimpCenterPicksMainAndRefuses() throws {
        let box = makeTemp()
        let rig = PimpRig()
        rig.now = PimpChannel.date("2026-09-26T18:40:00Z")!
        rig.windows = try centerWindows()
        let channel = makeChannel(rig, in: box)
        var arranged: [[CGWindowID]] = []
        centerRig(channel, rig: rig) { arranged.append($0) }
        func ask(_ id: String, from: String = "", _ extra: String = "") -> [String: Any]? {
            write(request(id, action: "arrange", at: rig.now, from: from,
                          extra: ",\"layout\":\"center\"" + extra), id: id, in: box)
            channel.tick()
            return result(id, in: box)
        }
        // Окно чата `from` (PimpMyClaude, id 14) встаёт в середину.
        let byFrom = ask("400-0001", from: "local_0181959d-85cc-42ee-a2b0-bf24342be20f")
        XCTAssertEqual(byFrom?["fromResolved"] as? Bool, true)
        XCTAssertEqual(arranged.last?[3], 14)
        // Ни `center`, ни `from` — главное окно Claude («Claude» у Рика, id 13).
        _ = ask("400-0002")
        XCTAssertEqual(arranged.last?[3], 13)
        XCTAssertEqual(ask("400-0003", ",\"center\":\"Nope\"")?["error"] as? String, "window-missing")
        rig.windows.append(PimpWindow(id: 20, title: "Второй Диктатора", chat: "local_d2",
                                      folder: PimpChannelTests.root + "Dictator",
                                      frame: CGRect(x: 0, y: -700, width: 300, height: 600)))
        let twice = ask("400-0004", ",\"center\":\"Dictator\"")
        XCTAssertEqual(twice?["error"] as? String, "ambiguous")
        XCTAssertEqual(twice?["windows"] as? [String], ["Марафон после паузы", "Второй Диктатора"])
        // Девять окон при ширине 280: с боков по четыре окна по 211 pt — тесно.
        channel.seats.cellWidth = { 280 }
        let count = arranged.count
        rig.windows.append(PimpWindow(id: 21, title: "Девятый", chat: "local_9", folder: PimpChannelTests.root + "Nine",
                                      frame: CGRect(x: 200, y: -700, width: 300, height: 600)))
        XCTAssertEqual(ask("400-0005", ",\"center\":\"Rick\"")?["error"] as? String, "too-small")
        XCTAssertEqual(arranged.count, count, "тесно — окна не двигаем")
    }

    /// `renew-window` у приложения: своё первое сообщение, модель, эффорт и закрепка — без
    /// записи «Обкэшить» (`sendTransfer` и `transfer` не уходят), окно рождается в точке донора.
    func testRenewNewWindowCommandCarriesTextWithoutTransfer() throws {
        let dir = makeTemp()
        let file = dir.appendingPathComponent("command.json")
        let app = IsolatedClaudeApp.make()
        app.instances = { [] }
        var now = Date(timeIntervalSince1970: 1_790_450_000)
        let commands = CommandChannel(path: file, now: { now }, schedule: { wait, block in
            now = now.addingTimeInterval(wait)
            block()
        })
        let actions = ClaudeActions(app: app, commands: commands, themes: [], fonts: [],
                                    themeStore: ThemeStore(defaults: WF102Defaults()),
                                    myThemes: MyThemesStore(url: dir.appendingPathComponent("my.json")))
        actions.clock = { now }
        actions.schedule = { _, _ in }
        actions.mainWindowMatch = { "/epitaxy/" + PimpChannelTests.rick }
        let project = Project(folder: URL(fileURLWithPath: "/tmp/VkusnoffKz", isDirectory: true),
                              name: "VkusnoffKz", lastFocusedAt: 0)
        actions.newWindow(in: project, on: nil, origin: (x: -800, y: -720), text: "Передача Рика",
                          handoff: NewChatHandoff(model: "Opus 5.5", effort: "extra", stay: false,
                                                  unpin: PimpChannelTests.vkusChat, transfer: false, pin: false))
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(sent["action"] as? String, ClaudeCommand.newWindow.rawValue)
        XCTAssertEqual(sent["text"] as? String, "Передача Рика")
        XCTAssertEqual(sent["model"] as? String, "Opus 5.5")
        XCTAssertEqual(sent["effort"] as? String, "extra")
        XCTAssertNil(sent["pin"], "замена не закрепляет (WF181, #9225)")
        XCTAssertNil(sent["unpin"])
        XCTAssertEqual(sent["folder"] as? String, "/tmp/VkusnoffKz")
        XCTAssertEqual(sent["x"] as? Int, -800)
        XCTAssertEqual(sent["y"] as? Int, -720)
        XCTAssertNil(sent["sendTransfer"], "записи «Обкэшить» нет — текст из команды")
        XCTAssertNil(sent["transfer"])
        XCTAssertNil(sent["stay"])

        // Без текста — штатное первое сообщение нового окна.
        now = now.addingTimeInterval(60)
        actions.newWindow(in: project, on: nil, origin: (x: -800, y: -720), text: nil,
                          handoff: NewChatHandoff(model: nil, effort: nil, stay: false, transfer: false))
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(plain["text"] as? String, MenuModel.newWindowText)
        XCTAssertNil(plain["model"])
        XCTAssertNil(plain["sendTransfer"])

        // Главное окно (WF181): `stay` с текстом замены, без закрепки и без записи «Обкэшить».
        now = now.addingTimeInterval(60)
        actions.newWindow(in: project, on: nil, origin: (x: 0, y: 0), text: "Передача Рика",
                          handoff: NewChatHandoff(model: nil, effort: nil, stay: true, transfer: false, pin: false))
        let here = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(here["stay"] as? Bool, true)
        XCTAssertEqual(here["text"] as? String, "Передача Рика")
        XCTAssertNil(here["pin"])
        XCTAssertNil(here["unpin"])
        XCTAssertNil(here["sendTransfer"])
    }
}

/// Раскладки проектов (`layouts.json`, план WF41, задача #5620): файл побайтно по эталону,
/// перезапись по имени, лимит и снимок окон по ячейкам.
final class LayoutsStoreTests: XCTestCase {
    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("layouts-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Эталон контракта лежит в репозитории: его читают оба конца канала.
    private func fixtureText() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/pimp/layouts.json")
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func morning() -> WindowLayout {
        WindowLayout(name: "Утро", at: PimpChannel.date("2026-09-08T03:00:00Z")!, mode: .five,
                     cells: [
                        LayoutCell(folder: "/Users/dev/Projects/PimpMyClaude",
                                   chat: "main", title: "Claude", cell: 0),
                        LayoutCell(folder: "/Users/dev/Projects/VkusnoffKz",
                                   chat: "local_df06e2d9-3957-48d7-832e-b21a91c483da",
                                   title: "VkusnoffKz 3", cell: 1),
                        LayoutCell(folder: "/Users/dev/Projects/Dictator",
                                   chat: "local_34211288-3534-44ed-aebe-ee9e4ca22226",
                                   title: "Диктаторик", cell: nil),
                     ])
    }

    private func review() -> WindowLayout {
        WindowLayout(name: "Разбор", at: PimpChannel.date("2026-09-07T20:00:00Z")!, mode: .ribbon,
                     cells: [LayoutCell(folder: "/Users/dev/Projects/PimpMyClaude",
                                        chat: "main", title: "Claude", cell: 0)])
    }

    func testLayoutsStoreWritesContractBytes() throws {
        let box = makeTemp()
        let url = box.appendingPathComponent(LayoutsStore.fileName)
        let store = LayoutsStore(url: url)
        XCTAssertTrue(store.save(review()))
        XCTAssertTrue(store.save(morning()))

        // Порядок ключей побайтно: version, layouts; в записи — name, at, mode, cells;
        // в месте — folder, chat, title, cell (окно вне сетки — null).
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), try fixtureText())
        // Своё же и читаем: запись переживает перезапуск приложения.
        XCTAssertEqual(store.load(), [morning(), review()])
        XCTAssertEqual(store.layout(named: " утро ")?.cells.count, 3)
        XCTAssertNil(store.layout(named: "Вечер"))
        XCTAssertEqual(LayoutsStore.parse(try Data(contentsOf: url)).first?.mode, .five)
    }

    func testLayoutsStoreOverwritesByNameAndKeepsLimit() throws {
        let box = makeTemp()
        let store = LayoutsStore(url: box.appendingPathComponent(LayoutsStore.fileName))
        store.save(morning())
        // Имя занято (регистр и пробелы не в счёт) — перезапись, второй записи нет.
        let later = WindowLayout(name: " утро ", at: PimpChannel.date("2026-09-08T04:00:00Z")!,
                                 mode: .ribbon, cells: [])
        XCTAssertTrue(store.save(later))
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.load().first?.mode, .ribbon)
        XCTAssertEqual(store.load().first?.name, "утро")
        // Пустое имя не записывается вовсе.
        XCTAssertFalse(store.save(WindowLayout(name: "  ", at: Date(), mode: .five, cells: [])))

        // Удаление: только своя запись, чужого имени файл не касается.
        XCTAssertFalse(store.delete(name: "Вечер"))
        XCTAssertTrue(store.delete(name: "УТРО"))
        XCTAssertTrue(store.load().isEmpty)

        // Больше тридцати раскладок не держим: уходит самая старая по `at`.
        var list: [WindowLayout] = []
        for index in 0..<(LayoutsStore.limit + 3) {
            list = LayoutsStore.merge(WindowLayout(name: "р\(index)",
                                                   at: Date(timeIntervalSince1970: Double(index)),
                                                   mode: .five, cells: []), into: list)
        }
        XCTAssertEqual(list.count, LayoutsStore.limit)
        XCTAssertEqual(list.first?.name, "р\(LayoutsStore.limit + 2)")
        XCTAssertEqual(list.last?.name, "р3")
    }

    func testLayoutsStoreParseSkipsJunk() {
        let json = """
        {"version":1,"layouts":[{"name":"  "},\
        {"name":"Утро","at":"2026-09-08T03:00:00Z","mode":"5x3","cells":[\
        {"folder":"/tmp/a","chat":"main","title":"Claude","cell":0},\
        {"folder":"/tmp/b","title":"Без чата","cell":1},\
        {"chat":"local_c","title":"Без папки","cell":-2}]},\
        {"name":"утро","at":"2026-09-08T02:00:00Z","mode":"row","cells":[]}]}
        """
        let list = LayoutsStore.parse(Data(json.utf8))
        XCTAssertEqual(list.map { $0.name }, ["Утро"], "запись без имени и дубль имени мимо")
        let layout = try? XCTUnwrap(list.first)
        XCTAssertEqual(layout?.mode, .ribbon, "незнакомая сетка читается как лента")
        XCTAssertEqual(layout?.cells.map { $0.chat }, ["main", "local_c"], "место без чата мимо")
        XCTAssertEqual(layout?.cells.last?.cell, nil, "отрицательный номер ячейки — не номер")
        XCTAssertTrue(LayoutsStore.parse(Data("{".utf8)).isEmpty)
        XCTAssertTrue(LayoutsStore.parse(nil).isEmpty)
    }

    /// Снимок окон: номер ячейки — совпавшая рамка (допуск 2 pt), главное окно пишется как
    /// `main`, окно с неопознанным чатом отменяет запись (его заголовок — в `unknown`).
    func testLayoutsStoreSnapshotCountsCells() {
        let cells = ArrangeLayout.frames(count: 3, in: CGRect(x: 0, y: 34, width: 1470, height: 859),
                                         mode: .five)
        let windows = [
            PimpWindow(id: 1, title: "Claude", chat: "local_main", folder: "/tmp/Pimp",
                       frame: cells[0]),
            // Окно доехало не идеально: 2 pt внутри допуска — ячейка та же.
            PimpWindow(id: 2, title: "Вкуснофф", chat: "local_v", folder: "/tmp/Vkus",
                       frame: cells[1].offsetBy(dx: 2, dy: 0)),
            PimpWindow(id: 3, title: "Гость",
                       frame: CGRect(x: 500, y: 500, width: 900, height: 700)),
        ]
        let snapshot = LayoutsStore.snapshot(name: " Утро ", at: Date(), mode: .five,
                                             windows: windows, cells: cells,
                                             isMain: { $0 == "Claude" })
        XCTAssertEqual(snapshot.unknown, ["Гость"])
        XCTAssertEqual(snapshot.layout.name, "Утро")
        XCTAssertEqual(snapshot.layout.cells.map { $0.chat }, ["main", "local_v"])
        XCTAssertEqual(snapshot.layout.cells.map { $0.cell }, [0, 1])
        // 3 pt — уже другое место, ячейки нет.
        XCTAssertNil(LayoutsStore.cell(of: cells[2].offsetBy(dx: 3, dy: 0), in: cells))
        XCTAssertEqual(LayoutsStore.cell(of: cells[2], in: cells), 2)
    }
}

/// Полоса раскладок (`LayoutPicker.swift`, план WF21): подсказки серых плиток после того,
/// как AppKit растянул вьюху пункта по ширине меню (#5681).
final class LayoutPickerHintsTests: XCTestCase {
    private func picker(fits: @escaping (ArrangeLayout.Mode) -> Bool) -> LayoutPickerView {
        var config = MinimizeMenu.MenuConfig()
        config.arrangeMode = .ribbon
        config.arrangeFits = fits
        // Десять окон: полоса собирается по их числу (#5800), и без них в ней осталась бы
        // одна плитка «как сейчас» — серой, про которую подсказка, не было бы вовсе.
        config.windowArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        config.windowFrames = (0..<10).map {
            CGRect(x: CGFloat($0) * 100, y: 0, width: 100, height: 500)
        }
        return LayoutPickerView(config: config)
    }

    func testLayoutPickerMovesHintsWithWidth() {
        let view = picker { $0 != .tenGrid }
        // Подсказка одна — у серой плитки «5 × 2» (третья по порядку макета).
        XCTAssertEqual(view.hintRects, [view.cell(of: 2)])

        // Меню шире полосы: клетки уезжают вправо — вместе с ними обязана уехать подсказка,
        // иначе она висит над соседней плиткой.
        let wide = NSSize(width: LayoutPickerView.width + 120, height: LayoutPickerView.height)
        view.setFrameSize(wide)
        XCTAssertEqual(view.hintRects, [view.cell(of: 2)])
        XCTAssertEqual(view.hintRects.first?.minX, view.cell(of: 2).minX)
        XCTAssertGreaterThan(view.cell(of: 2).minX, LayoutPickerView.tileSize.width)

        // Все плитки влезают — подсказывать нечего.
        let all = picker { _ in true }
        XCTAssertTrue(all.hintRects.isEmpty)
        all.setFrameSize(wide)
        XCTAssertTrue(all.hintRects.isEmpty)
    }
}

/// Свой список недавних проектов (`projects.json`, план WF36 и WF30 ч. 2, задача #5451).
final class ProjectsStoreTests: XCTestCase {
    private func makeTemp() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("projects-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func project(_ folder: URL, at: String) -> Project {
        Project(folder: folder, name: folder.lastPathComponent,
                lastFocusedAt: ProjectsStore.milliseconds(PimpChannel.date(at)!))
    }

    func testProjectsStoreWritesContractBytes() throws {
        let box = makeTemp()
        let url = box.appendingPathComponent(ProjectsStore.fileName)
        let store = ProjectsStore(url: url)
        let pimp = box.appendingPathComponent("PimpMyClaude", isDirectory: true)
        let vkus = box.appendingPathComponent("VkusnoffKz", isDirectory: true)
        for folder in [pimp, vkus] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        XCTAssertTrue(store.absorb([project(vkus, at: "2026-09-07T10:02:00Z"),
                                    project(pimp, at: "2026-09-07T11:19:00Z")],
                                   at: PimpChannel.date("2026-09-07T11:20:00Z")!))

        // Порядок ключей побайтно: version, projects; в записи — name, folder, lastUsed.
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       "{\"version\":1,\"projects\":["
                       + "{\"name\":\"PimpMyClaude\",\"folder\":\"\(pimp.path)\","
                       + "\"lastUsed\":\"2026-09-07T11:19:00Z\"},"
                       + "{\"name\":\"VkusnoffKz\",\"folder\":\"\(vkus.path)\","
                       + "\"lastUsed\":\"2026-09-07T10:02:00Z\"}]}")
        XCTAssertEqual(store.load().map { $0.name }, ["PimpMyClaude", "VkusnoffKz"])
        // Своё же и читаем: запись переживает перезапуск приложения.
        XCTAssertEqual(ProjectsStore.parse(try Data(contentsOf: url)).first?.lastFocusedAt,
                       ProjectsStore.milliseconds(PimpChannel.date("2026-09-07T11:19:00Z")!))
    }

    func testProjectsStoreKeepsMissingFoldersInFileButHidesThem() throws {
        let box = makeTemp()
        let url = box.appendingPathComponent(ProjectsStore.fileName)
        let store = ProjectsStore(url: url)
        let alive = box.appendingPathComponent("Alive", isDirectory: true)
        let gone = box.appendingPathComponent("Gone", isDirectory: true)
        try FileManager.default.createDirectory(at: alive, withIntermediateDirectories: true)
        store.absorb([project(gone, at: "2026-09-07T11:00:00Z"),
                      project(alive, at: "2026-09-07T10:00:00Z")],
                     at: PimpChannel.date("2026-09-07T11:20:00Z")!)

        // Папки нет на диске — в меню её не показываем, но из файла не выбрасываем.
        XCTAssertEqual(store.recent(limit: 8).map { $0.name }, ["Alive"])
        XCTAssertEqual(store.load().map { $0.name }, ["Gone", "Alive"])
        XCTAssertTrue(store.recent(limit: 0).isEmpty)
    }

    func testProjectsStoreAbsorbWritesOnlyOnChange() throws {
        let box = makeTemp()
        let url = box.appendingPathComponent(ProjectsStore.fileName)
        let store = ProjectsStore(url: url)
        let folder = box.appendingPathComponent("Pimp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let at = PimpChannel.date("2026-09-07T11:20:00Z")!
        XCTAssertTrue(store.absorb([project(folder, at: "2026-09-07T11:00:00Z")], at: at))
        // Та же отметка — файл не переписываем (иначе он менялся бы раз в 2 с).
        XCTAssertFalse(store.absorb([project(folder, at: "2026-09-07T11:00:00Z")], at: at))
        // Сдвиг меньше минуты — тоже не повод.
        XCTAssertFalse(store.absorb([project(folder, at: "2026-09-07T11:00:30Z")], at: at))
        XCTAssertTrue(store.absorb([project(folder, at: "2026-09-07T11:10:00Z")], at: at))

        // Клик по пункту меню (или запрос «Пимпа») делает папку самой свежей всегда.
        let other = box.appendingPathComponent("Vkus", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        store.absorb([project(other, at: "2026-09-07T11:19:00Z")], at: at)
        XCTAssertEqual(store.load().first?.name, "Vkus")
        XCTAssertTrue(store.note(Project(folder: folder, name: "Pimp", lastFocusedAt: 0),
                                 at: PimpChannel.date("2026-09-07T11:30:00Z")!))
        XCTAssertEqual(store.load().map { $0.name }, ["Pimp", "Vkus"])
    }

    func testProjectsStoreParseSkipsJunkAndKeepsLimit() {
        // Битая запись пропускается, весь список из-за неё не теряется.
        let json = """
        {"version":1,"projects":[{"name":"Без папки"},\
        {"name":"Pimp","folder":"/tmp/Pimp","lastUsed":"2026-09-07T11:19:00Z"},\
        {"folder":"/tmp/Pimp","lastUsed":"2026-09-07T09:00:00Z"},\
        {"folder":"/tmp/Vkus","lastUsed":"не дата"}]}
        """
        let list = ProjectsStore.parse(Data(json.utf8))
        XCTAssertEqual(list.map { $0.name }, ["Pimp", "Vkus"], "дубль папки и запись без пути мимо")
        XCTAssertEqual(list.last?.lastFocusedAt, 0, "нечитаемая дата — «давно», запись цела")
        XCTAssertTrue(ProjectsStore.parse(Data("{".utf8)).isEmpty)
        XCTAssertTrue(ProjectsStore.parse(nil).isEmpty)

        // Больше сотни папок не держим: уходит самая старая.
        let many = (0..<(ProjectsStore.limit + 5)).map {
            Project(folder: URL(fileURLWithPath: "/tmp/p\($0)"), name: "p\($0)",
                    lastFocusedAt: Double($0))
        }
        let merged = ProjectsStore.merge(many, into: [], refresh: 0)
        XCTAssertEqual(merged.count, ProjectsStore.limit)
        XCTAssertEqual(merged.first?.name, "p\(ProjectsStore.limit + 4)")
        XCTAssertEqual(merged.last?.name, "p5")
    }
}

/// Настройки в памяти для `ClaudeActions` в тесте замены окна (WF102).
private final class WF102Defaults: ThemeDefaults {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
