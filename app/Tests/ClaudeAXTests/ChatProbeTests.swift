import XCTest
@testable import ClaudeAX

/// Часы канала: тик общий, 2 с, а пол частоты — 15 с, поэтому время в тесте двигают руками.
private final class ProbeClock {
    var now = Date(timeIntervalSince1970: 1_757_100_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Два файла канала в памяти: диска в тестах нет, а правило владения и разбор ответа —
/// чистые части (решение 7 плана WF29). Заодно считает записи: лишний круг стоит лоадеру
/// обхода всех страниц Claude.
private final class ProbeBox {
    let clock: ProbeClock
    /// Что лежит в `probe.js` и когда его правили.
    var script: String?
    var scriptModified: Date?
    var scriptVersion = 0
    /// Что лежит в `probe-result.json`.
    var result: Data?
    var resultVersion = 0
    /// Все записи приложения в probe.js.
    var writes: [String] = []
    var writable = true

    init(clock: ProbeClock) { self.clock = clock }

    func files() -> ChatProbeFiles {
        ChatProbeFiles(
            scriptInfo: { [unowned self] in
                guard self.script != nil, let at = self.scriptModified else { return nil }
                return ("\(self.scriptVersion)", at)
            },
            readScript: { [unowned self] in self.script },
            writeScript: { [unowned self] text in
                guard self.writable else { return false }
                self.put(text)
                self.writes.append(text)
                return true
            },
            resultInfo: { [unowned self] in self.result == nil ? nil : "\(self.resultVersion)" },
            readResult: { [unowned self] in self.result })
    }

    /// Положить в probe.js текст — свой или чужой (агент на гейте).
    func put(_ text: String?, at: Date? = nil) {
        script = text
        scriptModified = text == nil ? nil : (at ?? clock.now)
        scriptVersion += 1
    }

    /// Метка круга из последнего записанного скрипта: первая строка `// myclaude-chats v1 <nonce>`.
    var nonce: String? {
        guard let head = writes.last?.split(separator: "\n").first else { return nil }
        let parts = head.split(separator: " ")
        return parts.count >= 4 ? String(parts[3]) : nil
    }

    /// Ответ лоадера: `{at, results:[{id,url,result|error}]}`.
    func answer(_ results: [[String: Any]]) {
        let body: [String: Any] = ["at": "2026-09-06T04:07:00Z", "results": results]
        result = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        resultVersion += 1
    }

    /// Ответ страницы на наш круг. `path` и `folder` (план WF37, часть C) страница шлёт
    /// всегда и только у главного окна соответственно — в тесте они необязательные.
    func page(kind: String, chat: String?, title: String, store: String,
              nonce: String? = nil, path: String? = nil, folder: Any? = nil) -> [String: Any] {
        var payload: [String: Any] = ["v": 1, "nonce": nonce ?? self.nonce ?? "", "kind": kind,
                                      "title": title, "store": store]
        if let chat = chat { payload["self"] = chat }
        if let path = path { payload["path"] = path }
        if let folder = folder { payload["folder"] = folder }
        return ["id": 1, "url": kind == "main" ? "https://claude.ai/epitaxy/\(chat ?? "")"
                                               : "about:blank", "result": payload]
    }

    /// Главное окно на домашнем экране: путь `/epitaxy`, чата нет, папка — из чипа.
    func home(folder: String = "/Users/elvis/_ElvisProjects/PimpMyClaude") -> [String: Any] {
        page(kind: "main", chat: nil, title: "Claude", store: "ok", path: ChatProbe.homePath,
             folder: folder)
    }
}

/// Канал probe (план WF29): приложение спрашивает страницы, какой в них чат, и уступает
/// канал агенту на гейте. Живого Claude тут нет — файлы в памяти, часы подставные.
final class ChatProbeTests: XCTestCase {
    private func makeProbe(_ box: ProbeBox, clock: ProbeClock) -> ChatProbe {
        var seed = 0
        return ChatProbe(files: box.files(), now: { clock.now }, random: {
            seed += 1
            return seed
        })
    }

    /// Тест 16 плана: разбор ответа — только свои записи, `error` мимо, `kind` по местам.
    func testChatProbeParsesAnswers() throws {
        let clock = ProbeClock()
        let box = ProbeBox(clock: clock)
        let probe = makeProbe(box, clock: clock)

        probe.tick(windowTitles: ["Bro Flow продолжение"], indexRevision: 1)
        let nonce = try XCTUnwrap(box.nonce, "первый тик обязан спросить страницы")
        // Первая строка — метка владения: по ней и приложение, и человек на гейте видят,
        // чей это скрипт (`head -1 probe.js`).
        XCTAssertTrue(try XCTUnwrap(box.writes.last).hasPrefix("\(ChatProbe.mark) \(nonce)\n"))
        XCTAssertTrue(try XCTUnwrap(box.writes.last).contains("api.chats({ scan: true"),
                      "неизвестное окно — просим страницу поискать стор")

        box.answer([
            box.page(kind: "main", chat: "local_a1", title: "PimpMyClaude", store: "ok"),
            box.page(kind: "popout", chat: "local_b2", title: "Bro Flow продолжение", store: "ok"),
            // Чужой круг (наш прошлый или скрипт агента) — не разбираем вовсе.
            box.page(kind: "popout", chat: "local_c3", title: "Чужой круг", store: "ok",
                     nonce: "chats-0-0000"),
            // Страница упала — записи с error пропускаем.
            ["id": 9, "url": "data:text/html,%3C", "error": "Script failed"],
            // Артефакты и панель браузера отвечают «не наша страница».
            box.page(kind: "other", chat: nil, title: "", store: "skip"),
            // id не из мира Claude в поле `chat` команды попасть не должен.
            box.page(kind: "popout", chat: "../../etc/passwd", title: "Кривой", store: "ok"),
        ])
        clock.advance(2)
        probe.tick(windowTitles: ["Bro Flow продолжение"], indexRevision: 1)

        // Чужие страницы в карте не нужны — их у живого Claude четыре пятых.
        XCTAssertEqual(probe.pages.map { $0.title }, ["PimpMyClaude", "Bro Flow продолжение", "Кривой"])
        XCTAssertEqual(probe.pages.map { $0.kind }, [.main, .popout, .popout])
        XCTAssertTrue(probe.isFresh)
        XCTAssertEqual(probe.mainChat, "local_a1")
        XCTAssertEqual(probe.chat(forTitle: "Bro Flow продолжение"), "local_b2")
        XCTAssertNil(probe.chat(forTitle: "Чужой круг"), "ответ на чужой nonce попал в карту")
        XCTAssertNil(probe.chat(forTitle: "Кривой"), "id не из мира Claude")
        XCTAssertEqual(probe.status, "own/3/2")

        // Ответ главного окна старше минуты не сильнее адреса из status.json (решение 8).
        clock.advance(ChatProbe.mainChatSeconds + 1)
        XCTAssertNil(probe.mainChat)
        XCTAssertEqual(probe.pages.count, 3, "карта осталась — протух только ответ главного окна")

        // Разбор чистой функцией: чужой nonce не берём, даже если записи больше не с кем сверить.
        XCTAssertTrue(ChatProbe.parse(box.result, nonce: "нет такого", at: clock.now).isEmpty)
        XCTAssertNil(ChatProbe.parse(nil, nonce: nonce, at: clock.now).first)
    }

    /// Тест 17 плана: правило владения каналом — чужой свежий скрипт не переписываем.
    func testChatProbeSkipsForeignProbe() throws {
        let clock = ProbeClock()
        let box = ProbeBox(clock: clock)
        let probe = makeProbe(box, clock: clock)

        probe.tick(windowTitles: ["Bro Flow продолжение"], indexRevision: 1)
        let mine = try XCTUnwrap(box.writes.last)
        box.answer([box.page(kind: "popout", chat: "local_b2", title: "Bro Flow продолжение",
                             store: "ok")])
        clock.advance(2)
        probe.tick(windowTitles: ["Bro Flow продолжение"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 1)
        XCTAssertTrue(probe.isFresh)

        // Агент на гейте положил свой скрипт: приложение молчит, а карта помечена несвежей —
        // покраска уходит на старый путь по заголовку.
        box.put("document.title")
        clock.advance(ChatProbe.askInterval + 1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Новое окно"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 1, "приложение переписало чужой probe.js")
        XCTAssertFalse(probe.isFresh)
        XCTAssertTrue(probe.pages.isEmpty)
        XCTAssertNil(probe.chat(forTitle: "Bro Flow продолжение"))
        XCTAssertEqual(probe.status, "busy/1/1", "карта прежняя, но канал не наш")

        // Скрипт на месте, минута молчания не вышла — файл даже не перечитываем.
        clock.advance(ChatProbe.askInterval + 1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Новое окно"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 1)

        // Тот же файл, но брошенный: старше 10 минут — канал забираем. Повод у всех
        // проверок ниже один и тот же и явный: изменился состав чатов.
        box.put("document.title", at: clock.now.addingTimeInterval(-ChatProbe.foreignStale - 1))
        clock.advance(ChatProbe.foreignQuiet + 1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Новое окно"], indexRevision: 2)
        XCTAssertEqual(box.writes.count, 2, "брошенный чужой скрипт держит канал вечно")

        // Наш побайтно (лоадер переписал файл, а мы не заметили) — тоже наш.
        box.put(mine)
        clock.advance(ChatProbe.askInterval + ChatProbe.answerTimeout + 1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Новое окно"], indexRevision: 3)
        XCTAssertEqual(box.writes.count, 3)

        // Скрипт от прошлого запуска приложения: узнаём по метке.
        box.put("\(ChatProbe.mark) chats-1-0001\n(function () { return 1 })()")
        clock.advance(ChatProbe.askInterval + ChatProbe.answerTimeout + 1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Новое окно"], indexRevision: 4)
        XCTAssertEqual(box.writes.count, 4)

        // Файла нет вовсе — канал свободен сразу, без минуты молчания (гейт, п. 4: `rm probe.js`).
        box.put(nil)
        clock.advance(ChatProbe.askInterval + ChatProbe.answerTimeout + 1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Новое окно"], indexRevision: 5)
        XCTAssertEqual(box.writes.count, 5)
    }

    /// Тест 18 плана: спрашиваем только по поводу и не чаще раза в 15 с.
    func testChatProbeAsksOnlyOnReason() throws {
        let clock = ProbeClock()
        let box = ProbeBox(clock: clock)
        var on = true
        let probe = makeProbe(box, clock: clock)
        probe.isEnabled = { on }

        // Тумблер «🗂 Цвет по проекту» выключен — канала не касаемся вовсе (риск 11 плана).
        on = false
        probe.tick(windowTitles: ["Bro Flow продолжение"], indexRevision: 1)
        XCTAssertTrue(box.writes.isEmpty)
        XCTAssertEqual(probe.status, "off/0/0")
        on = true

        // Первый тик после старта — спрашиваем.
        probe.tick(windowTitles: ["Bro Flow продолжение"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 1)

        // Прошлый круг не закрыт, а с записи прошло меньше 30 с — второго не начинаем:
        // поздно завершившийся старый круг затёр бы свежий ответ (критик В2 плана WF29).
        clock.advance(ChatProbe.askInterval + 1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Ещё окно"], indexRevision: 2)
        XCTAssertEqual(box.writes.count, 1)

        // Круг потерян (30 с) — спрашиваем заново.
        clock.advance(ChatProbe.answerTimeout + 1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Ещё окно"], indexRevision: 2)
        XCTAssertEqual(box.writes.count, 2)
        box.answer([box.page(kind: "popout", chat: "local_b2", title: "Bro Flow продолжение",
                             store: "ok"),
                    box.page(kind: "popout", chat: "local_c3", title: "Ещё окно", store: "ok")])
        clock.advance(1)
        probe.tick(windowTitles: ["Bro Flow продолжение", "Ещё окно"], indexRevision: 2)
        XCTAssertEqual(box.writes.count, 2)

        // Всё опознано и ничего не менялось — в покое вопросов ноль, сколько ни тикай.
        for _ in 0..<10 {
            clock.advance(ChatProbe.askInterval + 1)
            probe.tick(windowTitles: ["Bro Flow продолжение", "Ещё окно"], indexRevision: 2)
        }
        XCTAssertEqual(box.writes.count, 2)
        // И порядок окон на экране поводом не считается — набор тот же.
        clock.advance(ChatProbe.askInterval + 1)
        probe.tick(windowTitles: ["Ещё окно", "Bro Flow продолжение"], indexRevision: 2)
        XCTAssertEqual(box.writes.count, 2)

        // Состав чатов изменился (сменилась папка, чат переименовали) — спрашиваем.
        clock.advance(1)
        probe.tick(windowTitles: ["Ещё окно", "Bro Flow продолжение"], indexRevision: 3)
        XCTAssertEqual(box.writes.count, 3)
        XCTAssertTrue(try XCTUnwrap(box.writes.last).contains("api.chats({ scan: false"),
                      "неизвестных окон нет — стор искать незачем")

        // Чаще раза в 15 с не спрашиваем, даже когда поводов много.
        box.answer([box.page(kind: "popout", chat: "local_b2", title: "Bro Flow продолжение",
                             store: "ok"),
                    box.page(kind: "popout", chat: "local_c3", title: "Ещё окно", store: "ok")])
        clock.advance(2)
        probe.tick(windowTitles: ["Ещё окно"], indexRevision: 4)
        XCTAssertEqual(box.writes.count, 3)

        // Новое окно, чата которого мы не знаем: спрашиваем со `scan`, и не чаще раза в минуту.
        clock.advance(ChatProbe.askInterval)
        probe.tick(windowTitles: ["Ещё окно", "Незнакомое"], indexRevision: 4)
        XCTAssertEqual(box.writes.count, 4)
        XCTAssertTrue(try XCTUnwrap(box.writes.last).contains("api.chats({ scan: true"))
        box.answer([box.page(kind: "popout", chat: "local_c3", title: "Ещё окно", store: "ok"),
                    box.page(kind: "popout", chat: nil, title: "Незнакомое", store: "ok")])
        clock.advance(2)
        probe.tick(windowTitles: ["Ещё окно", "Незнакомое"], indexRevision: 4)
        XCTAssertEqual(box.writes.count, 4)
        // Окно не опознаётся в принципе (попап обычного чата claude.ai) — минуту молчим.
        clock.advance(ChatProbe.askInterval + 1)
        probe.tick(windowTitles: ["Ещё окно", "Незнакомое"], indexRevision: 4)
        XCTAssertEqual(box.writes.count, 4)
        clock.advance(ChatProbe.unknownInterval)
        probe.tick(windowTitles: ["Ещё окно", "Незнакомое"], indexRevision: 4)
        XCTAssertEqual(box.writes.count, 5)
        box.answer([box.page(kind: "popout", chat: "local_c3", title: "Ещё окно", store: "ok"),
                    box.page(kind: "popout", chat: nil, title: "Незнакомое", store: "ok")])
        clock.advance(2)
        probe.tick(windowTitles: ["Ещё окно", "Незнакомое"], indexRevision: 4)

        // Заглушки заголовка неизвестными окнами не считаются: их носит и главное окно,
        // и безымянный попап. Набор окон сменился — один вопрос, и дальше тишина.
        clock.advance(ChatProbe.askInterval + 1)
        probe.tick(windowTitles: ["Ещё окно", "Claude", "New chat"], indexRevision: 4)
        box.answer([box.page(kind: "popout", chat: "local_c3", title: "Ещё окно", store: "ok")])
        clock.advance(2)
        probe.tick(windowTitles: ["Ещё окно", "Claude", "New chat"], indexRevision: 4)
        let asked = box.writes.count
        clock.advance(ChatProbe.unknownInterval + ChatProbe.askInterval)
        probe.tick(windowTitles: ["Ещё окно", "Claude", "New chat"], indexRevision: 4)
        XCTAssertEqual(box.writes.count, asked)
    }

    /// Тест 19 плана: два окна с одним заголовком и заглушки id не дают.
    func testChatProbeTitleCollisionIsUnknown() {
        let clock = ProbeClock()
        let box = ProbeBox(clock: clock)
        let probe = makeProbe(box, clock: clock)

        probe.tick(windowTitles: ["Workflow продолжение"], indexRevision: 1)
        box.answer([
            box.page(kind: "popout", chat: "local_b2", title: "Workflow продолжение", store: "ok"),
            box.page(kind: "popout", chat: "local_c3", title: "Workflow продолжение", store: "ok"),
            box.page(kind: "popout", chat: "local_d4", title: "Claude", store: "ok"),
            box.page(kind: "popout", chat: "local_e5", title: "New chat", store: "ok"),
            box.page(kind: "popout", chat: "local_f6", title: "  ", store: "ok"),
        ])
        clock.advance(2)
        probe.tick(windowTitles: ["Workflow продолжение"], indexRevision: 1)

        XCTAssertNil(probe.chat(forTitle: "Workflow продолжение"),
                     "ничья по заголовку: лучше не покрасить, чем покрасить чужим цветом")
        XCTAssertNil(probe.chat(forTitle: "Claude"))
        XCTAssertNil(probe.chat(forTitle: "New chat"))
        XCTAssertNil(probe.chat(forTitle: "Новый чат"))
        XCTAssertNil(probe.chat(forTitle: " "))
        // Ничья именно ничья: то же имя у ОДНОГО чата помехой не считается.
        XCTAssertEqual(ChatProbe.chat(forTitle: "Один чат", in: [
            ChatPage(kind: .popout, chat: "local_z9", title: "Один чат", store: "ok", at: clock.now),
            ChatPage(kind: .popout, chat: "local_z9", title: "Один чат", store: "ok", at: clock.now),
        ]), "local_z9")
        // Заголовок носят два окна, а id назвало только одно — тоже ничья (находка 4
        // проверки WF29): иначе ручной выбор темы в неопознанном окне уехал бы в чужой проект.
        XCTAssertNil(ChatProbe.chat(forTitle: "Двойник", in: [
            ChatPage(kind: .popout, chat: "local_z9", title: "Двойник", store: "ok", at: clock.now),
            ChatPage(kind: .popout, chat: nil, title: "Двойник", store: "ok", at: clock.now),
        ]))
        XCTAssertNil(ChatProbe.chat(forTitle: "Двойник", in: [
            ChatPage(kind: .popout, chat: nil, title: "Двойник", store: "none", at: clock.now),
            ChatPage(kind: .popout, chat: "local_z9", title: "Двойник", store: "ok", at: clock.now),
        ]))
        // Главное окно по заголовку не адресуется вовсе — только `match` (критик Б1 плана WF15).
        XCTAssertNil(ChatProbe.chat(forTitle: "PimpMyClaude", in: [
            ChatPage(kind: .main, chat: "local_a1", title: "PimpMyClaude", store: "ok", at: clock.now),
        ]))
    }

    // MARK: - домашний экран (план WF37, части C2 и C3, задача #5576)

    /// Эталоны ответа страницы лежат в репозитории — те же файлы читает батч страницы.
    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/cashout", isDirectory: true)
    }

    /// Ответ лоадера с одной страницей: эталон кладётся внутрь как есть, побайтно.
    private func loaderAnswer(_ name: String, url: String) throws -> (data: Data, nonce: String) {
        let raw = try Data(contentsOf: ChatProbeTests.fixtures.appendingPathComponent(name))
        let page = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let nonce = try XCTUnwrap(page["nonce"] as? String)
        let body: [String: Any] = ["at": "2026-09-07T18:00:00Z",
                                   "results": [["id": 1, "url": url, "result": page]]]
        return (try JSONSerialization.data(withJSONObject: body), nonce)
    }

    /// Папку из ответа принимаем только у главного окна: у попапа её и не бывает, а верить
    /// чужой строке нельзя — на ней стоит цвет окна.
    func testParseAnswerFolderMainOnly() throws {
        let clock = ProbeClock()
        let box = ProbeBox(clock: clock)
        let probe = makeProbe(box, clock: clock)

        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        box.answer([
            box.home(),
            box.page(kind: "popout", chat: "local_b2", title: "VkusnoffKz 2", store: "cache",
                     path: "blank", folder: "/Users/elvis/_ElvisProjects/VkusnoffKz"),
        ])
        clock.advance(2)
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)

        XCTAssertEqual(probe.pages.map { $0.path }, [ChatProbe.homePath, "blank"])
        XCTAssertEqual(probe.pages.first?.folder, "/Users/elvis/_ElvisProjects/PimpMyClaude")
        XCTAssertNil(probe.pages.last?.folder, "папку берём только у главного окна")

        // Эталоны контракта побайтно: домашний экран, открытый чат и попап.
        let home = try loaderAnswer("probe-answer-home.json", url: "https://claude.ai/epitaxy")
        let atHome = ChatProbe.parseAnswer(home.data, nonce: home.nonce, at: clock.now)
        XCTAssertEqual(atHome.pages.first?.kind, .main)
        XCTAssertEqual(atHome.pages.first?.path, ChatProbe.homePath)
        XCTAssertEqual(atHome.pages.first?.folder, "/Users/elvis/_ElvisProjects/PimpMyClaude")
        XCTAssertNil(atHome.pages.first?.chat, "на домашнем экране чата нет вовсе")

        let chat = try loaderAnswer("probe-answer-chat.json",
                                    url: "https://claude.ai/epitaxy/local_facfb20c-4b3c-4aa9-838f-e084b0941b74")
        let inChat = ChatProbe.parseAnswer(chat.data, nonce: chat.nonce, at: clock.now)
        XCTAssertNil(inChat.pages.first?.folder, "в открытом чате папку даёт индекс, а не страница")
        XCTAssertEqual(inChat.pages.first?.path,
                       "/epitaxy/local_facfb20c-4b3c-4aa9-838f-e084b0941b74")

        let popout = try loaderAnswer("probe-answer-popout.json", url: "about:blank")
        let inPopout = ChatProbe.parseAnswer(popout.data, nonce: popout.nonce, at: clock.now)
        XCTAssertEqual(inPopout.pages.first?.kind, .popout)
        XCTAssertNil(inPopout.pages.first?.folder)
        XCTAssertEqual(inPopout.pages.first?.path, "blank")
    }

    /// Сито папки: только абсолютный путь и не длиннее потолка. Всё прочее — nil.
    func testParseAnswerFolderRejectsRelative() throws {
        XCTAssertNil(ChatProbe.folderPath("_ElvisProjects/PimpMyClaude"))
        XCTAssertNil(ChatProbe.folderPath("~/_ElvisProjects/PimpMyClaude"))
        XCTAssertNil(ChatProbe.folderPath(""))
        XCTAssertNil(ChatProbe.folderPath(nil))
        XCTAssertNil(ChatProbe.folderPath(42), "не строка — не папка")
        XCTAssertNil(ChatProbe.folderPath("/" + String(repeating: "a", count: ChatProbe.folderLimit)))
        XCTAssertEqual(ChatProbe.folderPath("/" + String(repeating: "a",
                                                         count: ChatProbe.folderLimit - 1))?.count,
                       ChatProbe.folderLimit)
        XCTAssertEqual(ChatProbe.folderPath("  /Users/elvis/_ElvisProjects/PimpMyClaude \n"),
                       "/Users/elvis/_ElvisProjects/PimpMyClaude")

        // То же через полный разбор ответа: кривую папку страница присылает — карта её не берёт.
        let clock = ProbeClock()
        let box = ProbeBox(clock: clock)
        let probe = makeProbe(box, clock: clock)
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        box.answer([box.page(kind: "main", chat: nil, title: "Claude", store: "ok",
                             path: ChatProbe.homePath, folder: "_ElvisProjects/PimpMyClaude")])
        clock.advance(2)
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        XCTAssertEqual(probe.pages.count, 1)
        XCTAssertNil(probe.pages.first?.folder)
        XCTAssertEqual(probe.pages.first?.path, ChatProbe.homePath)
    }

    /// Частота 4 с — только пока последний свежий ответ ГЛАВНОГО окна говорит «я на домашнем
    /// экране» (критик, важно 5): уехало окно в чат — снова 15 с.
    func testHomeIntervalOnlyWhileMainAtHome() throws {
        XCTAssertLessThan(ChatProbe.homeInterval, ChatProbe.askInterval)
        let clock = ProbeClock()
        let box = ProbeBox(clock: clock)
        let probe = makeProbe(box, clock: clock)

        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 1)
        box.answer([box.home()])
        clock.advance(2)
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 1, "пол частоты на домашнем экране — 4 с, прошло 2")

        // Домашний экран — повод сам по себе: заголовок окна там заглушка, состав чатов
        // при смене папки чипа не меняется, и спросить об этом больше некому.
        clock.advance(ChatProbe.homeInterval)
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 2)

        // Элвис открыл чат — путь другой, и частота возвращается к прежним 15 с.
        box.answer([box.page(kind: "main", chat: "local_a1", title: "Claude", store: "ok",
                             path: "/epitaxy/local_a1")])
        clock.advance(2)
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 2)
        clock.advance(ChatProbe.homeInterval + 1)
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 2, "в открытом чате 4 с не действуют")
        clock.advance(ChatProbe.askInterval)
        probe.tick(windowTitles: ["Claude"], indexRevision: 1)
        XCTAssertEqual(box.writes.count, 2, "и повода спрашивать в покое нет вовсе")
        // Канал при этом живой: настоящий повод (сменился состав чатов) слышен сразу.
        probe.tick(windowTitles: ["Claude"], indexRevision: 2)
        XCTAssertEqual(box.writes.count, 3)

        // Правило признака отдельно: протухший ответ и попап домашним экраном не считаются.
        let fresh = ChatPage(kind: .main, chat: nil, title: "Claude", path: ChatProbe.homePath,
                             store: "ok", folder: "/tmp/Проект", at: clock.now)
        XCTAssertTrue(ChatProbe.isMainAtHome([fresh], at: clock.now))
        XCTAssertFalse(ChatProbe.isMainAtHome([fresh],
                                              at: clock.now.addingTimeInterval(ChatProbe.mainChatSeconds + 1)),
                       "протухший ответ канал не разгоняет")
        XCTAssertFalse(ChatProbe.isMainAtHome([ChatPage(kind: .popout, chat: "local_b2",
                                                        title: "VkusnoffKz 2", path: ChatProbe.homePath,
                                                        store: "ok", at: clock.now)], at: clock.now),
                       "попап на частоту не влияет")
        XCTAssertFalse(ChatProbe.isMainAtHome([], at: clock.now))
    }
}
