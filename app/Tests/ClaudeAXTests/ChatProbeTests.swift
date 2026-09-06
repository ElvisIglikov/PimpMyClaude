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

    /// Ответ страницы на наш круг.
    func page(kind: String, chat: String?, title: String, store: String,
              nonce: String? = nil) -> [String: Any] {
        var payload: [String: Any] = ["v": 1, "nonce": nonce ?? self.nonce ?? "", "kind": kind,
                                      "title": title, "store": store]
        if let chat = chat { payload["self"] = chat }
        return ["id": 1, "url": kind == "main" ? "https://claude.ai/epitaxy/\(chat ?? "")"
                                               : "about:blank", "result": payload]
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
}
