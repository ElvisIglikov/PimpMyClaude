import AppKit
import XCTest
@testable import ClaudeAX

/// WF200 (#9182 п.4/9/10): «если он отключён — стандартные цвета без анимации; если включён — цвета анимируются».
/// Цвета окон «по проектам» (ProjectPaint) и переключатель «Живой» (`look` у `*`) не спорят: живой фон окна проекта —
/// всегда от переключателя, цвет — от проекта, неон и плотный текст — тоже от проекта.
final class LiveProjectsWF200Tests: XCTestCase {
    private final class Defaults: ThemeDefaults {
        var values: [String: Any] = [:]
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

    private var box: URL!
    private var now = Date(timeIntervalSince1970: 1_790_000_000)
    private var sent: [ProjectPaintCommand] = []
    private var all = Look()

    private var root: URL { box.appendingPathComponent("Projects", isDirectory: true) }
    private var project: URL { root.appendingPathComponent("PimpMyClaude", isDirectory: true) }
    private var sessions: URL { box.appendingPathComponent("sessions", isDirectory: true) }
    private var status: URL { box.appendingPathComponent("status.json") }
    private var store: ProjectSettingsStore {
        ProjectSettingsStore(registryURL: box.appendingPathComponent(ProjectSettingsStore.registryFileName))
    }

    override func setUp() {
        super.setUp()
        box = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf200-\(UUID().uuidString)", isDirectory: true)
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

    /// Главное окно — в чате проекта `name`.
    private func mainIn(_ name: String) {
        let dir = sessions.appendingPathComponent("a").appendingPathComponent("b")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cwd = root.appendingPathComponent(name).path
        let body: [String: Any] = ["sessionId": "local_\(name)", "title": "Чат \(name)", "titleSource": "user",
                                   "cwd": cwd, "originCwd": cwd, "lastFocusedAt": 3000, "lastActivityAt": 3000,
                                   "isArchived": false, "model": "claude-opus-5-5"]
        try? JSONSerialization.data(withJSONObject: body).write(to: dir.appendingPathComponent("local_\(name).json"))
        let state: [String: Any] = [
            "at": "2026-10-09T05:00:00Z", "loader": 7,
            "windows": [["id": 1, "min": [220, 400], "size": [422, 720]]],
            "webContents": [["id": 2, "url": "https://claude.ai/epitaxy/local_\(name)", "css": "inserted",
                             "inject": "wf93"]],
        ]
        try? JSONSerialization.data(withJSONObject: state).write(to: status)
    }

    private func makePaint(look: Layer<Look>?) -> ProjectPaint {
        if let look = look {
            store.write(ProjectSettings(name: "PimpMyClaude", theme: .set(Self.laser), look: look), to: project)
        }
        let index = ProjectIndex(sessionsDirectory: sessions, statusURL: status, projectsRoot: root,
                                 home: box, now: { [unowned self] in self.now })
        let paint = ProjectPaint(index: index, store: store, defaults: Defaults(),
                                 now: { [unowned self] in self.now })
        paint.send = { [unowned self] command in self.sent.append(command); return true }
        paint.allLook = { [unowned self] in self.all }
        return paint
    }

    private func step(_ paint: ProjectPaint) {
        now = now.addingTimeInterval(10)
        paint.tick()
    }

    private static let live = Look().withScheme("theme")

    // MARK: «Живой» включён — окна проекта оживают в своём цвете

    func testLiveOnAnimatesProjectWindowKeepingItsColorAndDense() throws {
        mainIn("PimpMyClaude")
        all = Self.live
        let paint = makePaint(look: .set(Look(dense: true)))
        step(paint)
        let command = try XCTUnwrap(sent.last)
        XCTAssertEqual(command.theme.value?.id, "laser", "цвет проекта на месте")
        XCTAssertEqual(command.look, .set(Look(aurora: true, dense: true, scheme: "theme")),
                       "«Плотный текст» проекта не гасит «Живой»: страница берёт `look` окна целиком")
    }

    func testProjectLookResetDoesNotWriteNoneOverLive() throws {
        // `"look":{"aurora":false}` в файле — сброс; окну ушёл бы `null` = «none», а он сильнее `*`.
        mainIn("PimpMyClaude")
        all = Self.live
        let paint = makePaint(look: .reset)
        step(paint)
        XCTAssertEqual(sent.last?.look, .set(Self.live), "сброс вида проекта не выключает «Живой» у окна")
    }

    func testAutoColorProjectLeavesLookToAllWindows() throws {
        // Проект без файла (авто-цвет): `look` ему не шлём вовсе — окно берёт «Живой» у `*`, цвет — свой.
        mainIn("Risovalka")
        all = Self.live
        let paint = makePaint(look: nil)
        step(paint)
        let command = try XCTUnwrap(sent.last)
        XCTAssertNotNil(command.theme.value, "авто-цвет проекта")
        XCTAssertEqual(command.look, .keep)
        // Переключили «Живой» — цвет проекта не перекрашивается, команд нет.
        all = Look()
        step(paint)
        XCTAssertEqual(sent.count, 1, "«Живой» не сбивает цвет проекта и не шлёт ему лишних команд")
    }

    // MARK: «Живой» выключен — без анимации везде, и после перезапуска

    func testLiveOffStopsAnimationFromOldProjectFile() throws {
        // В файле проекта остался живой фон из меню окна — выключенный «Живой» сильнее.
        mainIn("PimpMyClaude")
        let paint = makePaint(look: .set(Look(aurora: true, scheme: "sea")))
        step(paint)
        XCTAssertEqual(sent.last?.look, .reset, "«Живой» выключен — окно проекта без анимации")

        // Перезапуск Claude (`forget`) и приложения (новый ProjectPaint) — то же самое.
        paint.forget()
        step(paint)
        XCTAssertEqual(sent.last?.look, .reset)
        sent = []
        step(makePaint(look: nil))
        XCTAssertEqual(sent.last?.look, .reset, "после перезапуска приложения анимация не вернулась")
    }

    func testTogglingLiveRepaintsProjectWithOwnLook() throws {
        // Команда «всем» сняла на странице `look` окон — окна проекта со своим видом получают его заново.
        mainIn("PimpMyClaude")
        let paint = makePaint(look: .set(Look(dense: true)))
        step(paint)
        XCTAssertEqual(sent.last?.look, .set(Look(dense: true)))
        all = Self.live
        step(paint)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.last?.look, .set(Look(aurora: true, dense: true, scheme: "theme")))
        XCTAssertEqual(sent.last?.theme.value?.id, "laser")
        all = Look()
        step(paint)
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent.last?.look, .set(Look(dense: true)), "выключили — плотность проекта осталась, анимации нет")
        step(paint)
        XCTAssertEqual(sent.count, 3, "без перемен — молчим")
    }

    func testTurningProjectColorsOffKeepsLive() throws {
        // «Как у Claude» в панели снимает слои проекта — но `look:null` («none») погасил бы «Живой» у окна.
        mainIn("PimpMyClaude")
        all = Self.live
        let paint = makePaint(look: .set(Look(dense: true)))
        step(paint)
        sent = []
        paint.setEnabled(false)
        let command = try XCTUnwrap(sent.last)
        XCTAssertEqual(command.theme, .reset)
        XCTAssertEqual(command.look, .set(Self.live), "снятие вида проекта оставляет «Живой» всем окнам")
    }

    func testLiveLookRule() {
        XCTAssertEqual(ProjectPaint.liveLook(.keep, all: Self.live), .keep)
        XCTAssertEqual(ProjectPaint.liveLook(.reset, all: Look()), .reset)
        XCTAssertEqual(ProjectPaint.liveLook(.set(Look(aurora: true, scheme: "sea")), all: Look(dense: true)), .reset,
                       "плотность — от проекта, живой фон — только от «Живого»")
        XCTAssertEqual(ProjectPaint.liveLook(.set(Look(dense: true)), all: Look().withScheme("forest")),
                       .set(Look(aurora: true, dense: true, scheme: "forest")))
    }

    // MARK: меню окна — вид от того, что окно носит

    func testWindowMenuLookStartsFromAllWindowsLive() throws {
        let defaults = Defaults()
        let themes = ThemeStore(defaults: defaults)
        themes.setAllLook(Self.live)
        XCTAssertEqual(themes.effectiveWindowLook(title: "Vkusnoff"), Self.live, "своей записи нет — «всем окнам»")
        themes.setWindowLook(Look(dense: true), title: "Vkusnoff")
        XCTAssertEqual(themes.effectiveWindowLook(title: "Vkusnoff"), Look(dense: true))

        // «Плотный текст» в окне без своей записи шлёт вид С живым фоном — «Живой» на окне не гаснет.
        var applied: [Layer<Look>] = []
        var config = MinimizeMenu.MenuConfig()
        config.windowLook = themes.effectiveWindowLook(title: "Trelvis")
        config.allLook = themes.allLook
        config.apply = { _, _, _, _, _, look in applied.append(look) }
        let dense = try XCTUnwrap(MinimizeMenu.lookItems(config, scope: MenuModel.themeScopeWindow)
            .first { $0.title == MenuModel.lookDenseTitle })
        // WF202: «Живого фона» у окна нет (с WF220 нет и «Опытов»); в «Всем окнам ▸» его галка — правда.
        XCTAssertEqual(MinimizeMenu.lookItems(config, scope: MenuModel.themeScopeWindow).map { $0.title },
                       [MenuModel.lookDenseTitle])
        let allLab = try XCTUnwrap(MinimizeMenu.lookItems(config, scope: MenuModel.themeScopeAll)
            .first { $0.title == MenuModel.lookLabTitle }?.submenu)
        XCTAssertEqual(allLab.items.first { $0.title == MenuModel.lookAuroraTitle }?.state, .on,
                       "галка «Живой фон» во «Всем окнам» — правда")
        let target = try XCTUnwrap(dense.target as? NSObject)
        target.perform(try XCTUnwrap(dense.action))
        XCTAssertEqual(applied, [.set(Look(aurora: true, dense: true, scheme: "theme"))])
    }
}
