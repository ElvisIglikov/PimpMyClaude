import AppKit
import XCTest
@testable import ClaudeAX

/// #7749 (26.09 ~02:00, слово Элвиса): «окно открылось соседнее… должно было заменить…
/// старое окно не закрыла… растянулось на весь экран». Живые следы: в 01:51:12 нажат пункт
/// меню Пимпа, главное окно исполнило ОБЫЧНОЕ «Новое окно» (заглушка, имя проекта, без
/// `transfer`/`handoff`) — это ветка «💬 Новый чат» жёлтой кнопки из попапа (#5734): окно
/// рядом, Claude-размера, донор нетронут. Блока «ОТКРОЙ НОВЫЙ ЧАТ» в ответе донора не было,
/// так что кнопка и ссылка замены не появлялись вовсе, а пункт меню замены не умел.
///
/// Без живого Claude: выбор экземпляра пуст (`instances`), окна — AX-элементы несуществующих
/// процессов, отложенные шаги крутим сами.
final class Fix7749Tests: XCTestCase {
    private static let donorChat = "local_ffb6ef30-f45a-4af2-8088-cc567c85bb1b"
    private static let mainMatch = "/epitaxy/local_073e3cb7-8c7b-4ee7-96e6-0a156ad3bc2e"

    /// Часы прогона — общие для канала и действий.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_790_369_472)
    }

    private final class Rig {
        let actions: ClaudeActions
        let file: URL
        let clock: Clock
        var now: Date {
            get { clock.now }
            set { clock.now = newValue }
        }
        var queued: [(delay: TimeInterval, run: () -> Void)] = []
        var written: [[String: Any]] = []
        var used: [Project] = []
        let donor = AXUIElementCreateApplication(999_911)
        let project = Project(folder: URL(fileURLWithPath: "/tmp/VkusStatBot", isDirectory: true),
                              name: "VkusStatBot", lastFocusedAt: 0)

        init(dir: URL) {
            file = dir.appendingPathComponent("command.json")
            let app = IsolatedClaudeApp.make()
            // Ни одного Claude: фокус и ⌘N ничего не трогают на Маке, где идёт прогон.
            app.instances = { [] }
            // Зазор канала выдерживаем часами — каждая запись ложится сразу и попадает в журнал.
            let clock = Clock()
            self.clock = clock
            let channel = CommandChannel(path: file, now: { clock.now },
                                         schedule: { wait, block in
                                             clock.now = clock.now.addingTimeInterval(wait)
                                             block()
                                         })
            actions = ClaudeActions(app: app, commands: channel, themes: [], fonts: [],
                                    themeStore: ThemeStore(defaults: Fix7749Defaults()),
                                    myThemes: MyThemesStore(url: dir.appendingPathComponent("my.json")))
            actions.clock = { clock.now }
            actions.schedule = { [unowned self] delay, block in self.queued.append((delay, block)) }
            actions.isMainWindowTitle = { $0 == "Claude" }
            actions.chatForTitle = { _, _ in Fix7749Tests.donorChat }
            actions.projectForChat = { [unowned self] in $0 == Fix7749Tests.donorChat ? self.project : nil }
            actions.mainWindowMatch = { Fix7749Tests.mainMatch }
            actions.onProjectUsed = { [unowned self] in self.used.append($0) }
        }

        /// Отложенные шаги по одному, кроме ⌘N после записи (клавиши в тесте не жмём).
        func drain() {
            while let step = queued.first, step.delay != actions.newWindowKeyDelay {
                queued.removeFirst()
                now = now.addingTimeInterval(step.delay)
                step.run()
                record()
            }
        }

        private var lastBody = ""

        func record() {
            guard let body = try? String(contentsOf: file, encoding: .utf8), body != lastBody else { return }
            lastBody = body
            if let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] {
                written.append(json)
            }
        }
    }

    private func makeRig() -> Rig {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fix7749-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return Rig(dir: dir)
    }

    /// «💬 Новый чат» жёлтой кнопки в попапе — тот же путь, что кнопка «ОТКРОЙ НОВЫЙ ЧАТ»:
    /// сперва `cashout` с `handoff` донору, потом `new-window` с `transfer` и `sendTransfer`.
    /// До правки уходил голый `new-window` без переноса — главное окно открывало окно рядом,
    /// а донор оставался (живой статус главного окна 26.09: transfer/handoff null).
    func testNewChatFromPopoutReplacesDonorLikeContinueButton() throws {
        let rig = makeRig()
        rig.actions.newChatCommand(rig.donor, title: "Кассы по годам")
        rig.record()
        rig.drain()

        let actions = rig.written.compactMap { $0["action"] as? String }
        XCTAssertEqual(actions, [ClaudeCommand.cashout.rawValue, ClaudeCommand.newWindow.rawValue],
                       "из попапа — перенос с handoff, а не голое «Новое окно» рядом")
        let cashout = try XCTUnwrap(rig.written.first)
        XCTAssertEqual(cashout["handoff"] as? Bool, true)
        XCTAssertEqual(cashout["chat"] as? String, Fix7749Tests.donorChat, "адрес — чат донора")
        XCTAssertNil(cashout["match"], "попапу — chat, не match")

        let window = try XCTUnwrap(rig.written.last)
        XCTAssertEqual(window["transfer"] as? Bool, true, "новое окно штампует перенос донора")
        XCTAssertEqual(window["sendTransfer"] as? Bool, true)
        XCTAssertNil(window["stay"], "из попапа новый чат уходит в окно, а не в главное")
        XCTAssertEqual(window["folder"] as? String, "/tmp/VkusStatBot", "тот же проект")
        XCTAssertEqual(window["unpin"] as? String, Fix7749Tests.donorChat)
        XCTAssertEqual(rig.used, [rig.project])
    }

    /// Главное окно — как было: ⌘N, команд в канал нет (#5734).
    func testNewChatFromMainWindowStillPressesKey() {
        let rig = makeRig()
        rig.actions.newChatCommand(rig.donor, title: "Claude")
        rig.record()
        XCTAssertTrue(rig.written.isEmpty)
        XCTAssertEqual(rig.queued.map { $0.delay }, [rig.actions.focusDelay])
    }
}

/// Настройки в памяти — своя копия: у соседних файлов она `private`.
private final class Fix7749Defaults: ThemeDefaults {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
