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
    var projects: [Project] = []
    var titles: [String: String] = [:]
    var layers = true

    var opened: [(project: Project, origin: (x: Int, y: Int)?)] = []
    var arranged: [[CGWindowID]] = []
    var moved: [PimpMove] = []

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
            arrange: { [unowned self] ids in self.arrange(ids) },
            place: { [unowned self] moves in self.place(moves) },
            titleForChat: { [unowned self] chat in self.titles[chat] },
            newWindowLayers: { [unowned self] in self.layers })
    }

    /// «Расставить»: та же арифметика, что в приложении, только окна двигаются в массиве.
    private func arrange(_ ids: [CGWindowID]) -> [PimpWindow] {
        arranged.append(ids)
        let ordered = ids.compactMap { id in windows.first { $0.id == id } }
        let cells = ArrangeLayout.frames(count: ordered.count, in: PimpRig.area)
        var out: [PimpWindow] = []
        for (index, window) in ordered.enumerated() {
            let placed = PimpWindow(id: window.id, title: window.title, chat: window.chat,
                                    folder: window.folder, frame: cells[index])
            out.append(placed)
            if let at = windows.firstIndex(where: { $0.id == window.id }) { windows[at] = placed }
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
        Project(folder: URL(fileURLWithPath: "/Users/elvis/_ElvisProjects/\(name)",
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
        }

        // Чужое действие — `bad-request` (эталон bad.request.json: "action":"fly").
        XCTAssertNil(PimpRequest.parse(try fixture("bad.request.json")))
        XCTAssertNil(PimpRequest.parse(Data("{".utf8)), "битый JSON — не запрос")
        XCTAssertNil(PimpRequest.parse(nil))
        // Без id ответ некому адресовать, без `at` не сказать, протух ли он.
        XCTAssertNil(PimpRequest.parse(Data("{\"id\":\"\",\"at\":\"2026-09-07T11:20:00Z\",\"action\":\"windows\"}".utf8)))
        XCTAssertNil(PimpRequest.parse(Data("{\"id\":\"1-1\",\"action\":\"windows\"}".utf8)))
        // «Новое окно» без папки бессмысленно.
        XCTAssertNil(PimpRequest.parse(Data("{\"id\":\"1-1\",\"at\":\"2026-09-07T11:20:00Z\",\"action\":\"new-window\",\"project\":\" \"}".utf8)))

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
                       folder: "/Users/elvis/_ElvisProjects/VkusnoffKz",
                       frame: CGRect(x: 0, y: 34, width: 490, height: 859)),
            PimpWindow(id: 2, title: "Claude", chat: "local_5265171a-0ab8-4472-b4e5-40604a36ef6e",
                       folder: "/Users/elvis/_ElvisProjects/PimpMyClaude",
                       frame: CGRect(x: 490, y: 34, width: 490, height: 859)),
            PimpWindow(id: 3, title: "Диктаторик",
                       frame: CGRect(x: 980, y: 34, width: 490, height: 859)),
        ]
        XCTAssertEqual(PimpAnswer(id: "1788780010000-0777",
                                  at: PimpChannel.date("2026-09-07T11:20:12Z")!, ok: true,
                                  fields: PimpChannel.windowsFields(windows, minimized: 0)).json,
                       try fixtureText("arrange.result.json"))

        let list = [Project(folder: URL(fileURLWithPath: "/Users/elvis/_ElvisProjects/PimpMyClaude"),
                            name: "PimpMyClaude",
                            lastFocusedAt: ProjectsStore.milliseconds(
                                PimpChannel.date("2026-09-07T11:19:00Z")!)),
                    Project(folder: URL(fileURLWithPath: "/Users/elvis/_ElvisProjects/VkusnoffKz"),
                            name: "VkusnoffKz",
                            lastFocusedAt: ProjectsStore.milliseconds(
                                PimpChannel.date("2026-09-07T10:02:00Z")!))]
        XCTAssertEqual(PimpAnswer(id: "1788780020000-0102",
                                  at: PimpChannel.date("2026-09-07T11:20:22Z")!, ok: true,
                                  fields: [(key: "projects",
                                            value: .array(list.map(PimpChannel.projectValue)))]).json,
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
        // Порог 360 pt: половина 719/2 = 359 — не делим.
        XCTAssertNil(PimpChannel.split(CGRect(x: 0, y: 0, width: 490, height: 719), above: false))
        XCTAssertNotNil(PimpChannel.split(CGRect(x: 0, y: 0, width: 490, height: 720), above: false))

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
        XCTAssertEqual(projects["screen"] as? String, "main")
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
        XCTAssertEqual(rig.arranged.first, [1, 3, 2], "новое окно встало между старыми")
        let window = try XCTUnwrap(answer["window"] as? [String: Any])
        XCTAssertEqual(window["title"] as? String, "Диктаторик")
        XCTAssertEqual(window["chat"] as? String, "local_new")
        XCTAssertEqual(window["frame"] as? [Int], [490, 34, 490, 859])
        XCTAssertEqual(answer["layers"] as? String, "ok")
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
        XCTAssertEqual(rig.arranged.first, [1, 2], "новое окно справа")
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
        XCTAssertEqual(rig.arranged.first, [1, 3])
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

        // Окно не появилось за 40 с — window-missing (чат при этом создан, так и скажет CLI).
        rig.advance(1)
        write(request("700-0002", action: "new-window", at: rig.now,
                      extra: ",\"project\":\"Dictator\",\"place\":\"right\""),
              id: "700-0002", in: box)
        channel.tick()
        XCTAssertNil(result("700-0002", in: box))
        rig.advance(41)
        channel.tick()
        XCTAssertEqual(result("700-0002", in: box)?["error"] as? String, "window-missing")
        // Канал снова свободен.
        write(request("700-0003", action: "windows", at: rig.now), id: "700-0003", in: box)
        channel.tick()
        XCTAssertEqual(result("700-0003", in: box)?["ok"] as? Bool, true)
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

    // MARK: - 10. окно по заголовку

    func testPimpWindowByTitleIgnoresDoubles() {
        let windows = [PimpWindow(id: 1, title: "Claude"), PimpWindow(id: 2, title: "Claude"),
                       PimpWindow(id: 3, title: " Пимп ")]
        XCTAssertEqual(PimpChannel.window(title: "Пимп", in: windows)?.id, 3)
        XCTAssertNil(PimpChannel.window(title: "Claude", in: windows), "заголовок носят двое")
        XCTAssertNil(PimpChannel.window(title: "  ", in: windows))
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
