import XCTest
@testable import ClaudeAX

/// #7727 (слово Элвиса 25.09 23:30): «два чата по Пимпу, оба в папке PimpMyClaude, почему у тебя
/// синяя тема, а у того фиолетовая?». Главное окно перешло в другой чат ТОЙ ЖЕ папки — покраска
/// по проекту молчала (отпечаток `main` сверял только папку и вид), и чат брал на странице запись
/// окна `main`, переписанную домашним экраном чужого проекта. Теперь смена чата в главном окне —
/// повод послать вид проекта заново: страница кладёт его в запись ЭТОГО чата.
final class Fix7727Tests: XCTestCase {
    private final class Defaults: ThemeDefaults {
        private var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    }

    private static let laser = Theme(id: "laser", name: "Лазер", type: "dark",
                                     palette: ["accent": "#ff2d55", "background": "#0c0e1c",
                                               "foreground": "#fcdee4", "sidebar": "#080a13",
                                               "panel": "#131527", "muted": "#c86f80"])
    private static let risovalka = Theme(id: "risovalka", name: "Risovalka", type: "dark",
                                         palette: ["accent": "#8a7dff", "background": "#1a1830",
                                                   "foreground": "#ecebff", "sidebar": "#141226",
                                                   "panel": "#221f3d", "muted": "#a39fd0"])

    private var box: URL!
    private var now = Date(timeIntervalSince1970: 1_790_000_000)
    private var sent: [ProjectPaintCommand] = []
    private var pages: [ChatPage] = []

    private var root: URL { box.appendingPathComponent("Projects", isDirectory: true) }
    private var sessions: URL { box.appendingPathComponent("sessions", isDirectory: true) }
    private var status: URL { box.appendingPathComponent("status.json") }

    override func setUp() {
        super.setUp()
        box = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fix7727-\(UUID().uuidString)", isDirectory: true)
        for name in ["PimpMyClaude", "Risovalka"] {
            try? FileManager.default.createDirectory(
                at: root.appendingPathComponent(name).appendingPathComponent(".git"),
                withIntermediateDirectories: true)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: box)
        super.tearDown()
    }

    private func putSession(_ id: String, title: String, project: String, at: Double) {
        let dir = sessions.appendingPathComponent("a").appendingPathComponent("b")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cwd = root.appendingPathComponent(project).path
        let body: [String: Any] = ["sessionId": id, "title": title, "titleSource": "user", "cwd": cwd,
                                   "originCwd": cwd, "lastFocusedAt": at, "lastActivityAt": at,
                                   "isArchived": false, "model": "claude-opus-5-5"]
        try? JSONSerialization.data(withJSONObject: body).write(to: dir.appendingPathComponent("\(id).json"))
    }

    private func putStatus(_ path: String) {
        let body: [String: Any] = [
            "at": "2026-09-25T18:30:00Z", "loader": 7,
            "windows": [["id": 1, "min": [220, 400], "size": [422, 720]]],
            "webContents": [["id": 2, "url": "https://claude.ai\(path)", "css": "inserted", "inject": "wf93"]],
        ]
        try? JSONSerialization.data(withJSONObject: body).write(to: status)
    }

    private func makePaint() -> ProjectPaint {
        let store = ProjectSettingsStore(
            registryURL: box.appendingPathComponent(ProjectSettingsStore.registryFileName))
        store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(Fix7727Tests.laser)),
                    to: root.appendingPathComponent("PimpMyClaude"))
        store.write(ProjectSettings(name: "Risovalka", theme: .set(Fix7727Tests.risovalka)),
                    to: root.appendingPathComponent("Risovalka"))
        let index = ProjectIndex(sessionsDirectory: sessions, statusURL: status, projectsRoot: root,
                                 home: box, now: { [unowned self] in self.now })
        let paint = ProjectPaint(index: index, store: store, defaults: Defaults(),
                                 now: { [unowned self] in self.now })
        paint.send = { [unowned self] command in self.sent.append(command); return true }
        paint.chatPages = { [unowned self] in self.pages }
        return paint
    }

    private func step(_ paint: ProjectPaint) {
        now = now.addingTimeInterval(10)
        paint.tick()
    }

    func testMainWindowChatSwitchInSameFolderRepaintsThatChat() throws {
        putSession("local_4976", title: "Обновления и иконка Pimpa", project: "PimpMyClaude", at: 3000)
        putSession("local_e247", title: "Pimp Viewer макет", project: "PimpMyClaude", at: 3100)
        putStatus("/epitaxy/local_4976")
        let paint = makePaint()

        step(paint)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?.match, "/epitaxy/local_4976")
        XCTAssertEqual(sent.last?.theme.value?.id, "laser")

        // Тот же чат — молчим, как и раньше.
        step(paint)
        XCTAssertEqual(sent.count, 1, "без смены чата команды не шлём")

        // Главное окно ушло в другой чат той же папки — вид проекта уходит ЭТОМУ чату.
        putStatus("/epitaxy/local_e247")
        step(paint)
        XCTAssertEqual(sent.count, 2, "смена чата в той же папке прошла молча — чат брал запись `main`")
        let command = try XCTUnwrap(sent.last)
        XCTAssertEqual(command.key, ProjectPaint.mainKey)
        XCTAssertEqual(command.match, "/epitaxy/local_e247", "адресовано новому чату главного окна")
        XCTAssertEqual(command.theme.value?.id, "laser", "цвет проекта этого чата, а не окна")
    }

    func testHomeScreenOfOtherProjectDoesNotStickToChatAfterReturn() throws {
        putSession("local_4976", title: "Обновления и иконка Pimpa", project: "PimpMyClaude", at: 3000)
        putSession("local_e247", title: "Pimp Viewer макет", project: "PimpMyClaude", at: 3100)
        putStatus("/epitaxy/local_4976")
        let paint = makePaint()
        step(paint)
        XCTAssertEqual(sent.last?.theme.value?.id, "laser")

        // Цепочка «Нового окна» проходит домашний экран с чипом Рисовалки: окно `main` — её цвета.
        putStatus("/epitaxy")
        pages = [ChatPage(kind: .main, chat: nil, title: ProjectPaint.mainWindowTitle,
                          path: ChatProbe.homePath, store: ChatProbe.storeOK,
                          folder: root.appendingPathComponent("Risovalka").path, at: now.addingTimeInterval(10))]
        step(paint)
        XCTAssertEqual(sent.last?.theme.value?.id, "risovalka")
        XCTAssertEqual(sent.last?.match, ChatProbe.homePath)

        // Главное окно вернулось в чат PimpMyClaude, страница уже назвала его, а `status.json`
        // лоадера ещё держит прежний путь: команда ушла путём прошлого чата — мимо страницы.
        putStatus("/epitaxy/local_4976")
        pages = [ChatPage(kind: .main, chat: "local_e247", title: ProjectPaint.mainWindowTitle,
                          path: "/epitaxy/local_e247", store: ChatProbe.storeOK, at: now.addingTimeInterval(10))]
        step(paint)
        XCTAssertEqual(sent.last?.match, "/epitaxy/local_4976")
        XCTAssertEqual(sent.last?.theme.value?.id, "laser")
        // Лоадер догнал — путь сменился, и вид проекта уходит заново, теперь этому чату.
        pages = []
        putStatus("/epitaxy/local_e247")
        let before = sent.count
        step(paint)
        XCTAssertEqual(sent.count, before + 1, "потерянная команда не повторилась — чат остался в цвете Рисовалки")
        XCTAssertEqual(sent.last?.match, "/epitaxy/local_e247")
        XCTAssertEqual(sent.last?.theme.value?.id, "laser")
    }

    func testStalePageAnswerDoesNotPaintNewChatWithOldFolder() throws {
        putSession("local_4976", title: "Обновления и иконка Pimpa", project: "PimpMyClaude", at: 3000)
        putSession("local_r111", title: "Мультяшные персонажи", project: "Risovalka", at: 3100)
        putStatus("/epitaxy/local_4976")
        let paint = makePaint()
        step(paint)
        XCTAssertEqual(sent.last?.theme.value?.id, "laser")

        // Окно ушло в чат Рисовалки: status.json уже на новом пути, а ответ страницы (свежий,
        // до 10 с) ещё называет прежний чат PimpMyClaude — вид старой папки новому чату не шлём.
        putStatus("/epitaxy/local_r111")
        pages = [ChatPage(kind: .main, chat: "local_4976", title: ProjectPaint.mainWindowTitle,
                          path: "/epitaxy/local_4976", store: ChatProbe.storeOK, at: now.addingTimeInterval(10))]
        step(paint)
        let command = try XCTUnwrap(sent.last)
        XCTAssertEqual(command.match, "/epitaxy/local_r111")
        XCTAssertEqual(command.theme.value?.id, "risovalka", "вид папки ЭТОГО чата, а не прошлого")
    }

    func testMainChatMovedRule() {
        let folder = URL(fileURLWithPath: "/Users/dev/Projects/PimpMyClaude")
        let main = ProjectTarget(key: ProjectPaint.mainKey, match: "/epitaxy/local_b", chat: nil,
                                 title: ProjectPaint.mainWindowTitle, folder: folder)
        XCTAssertTrue(ProjectPaint.mainChatMoved(main, previous: "/epitaxy/local_a"))
        XCTAssertFalse(ProjectPaint.mainChatMoved(main, previous: "/epitaxy/local_b"), "тот же чат")
        let unknown = ProjectTarget(key: ProjectPaint.mainKey, match: "/epitaxy/local_b", chat: nil,
                                    title: ProjectPaint.mainWindowTitle, folder: nil)
        XCTAssertFalse(ProjectPaint.mainChatMoved(unknown, previous: "/epitaxy/local_a"),
                       "папки не знаем — молчим, как и раньше")
        let popout = ProjectTarget(key: "c:local_b", match: nil, chat: "local_b", title: "Чат",
                                   folder: folder)
        XCTAssertFalse(ProjectPaint.mainChatMoved(popout, previous: "/epitaxy/local_a"), "только главное окно")
    }
}
