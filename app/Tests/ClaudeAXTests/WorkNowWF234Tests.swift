import XCTest
@testable import ClaudeAX

/// WF234: «идёт ли работа» — один ответ для решений об обновлении. Карточка у часов звала обновиться словами
/// «15 мин никто не работает», пока шло семь Workflow: работу приложение знало только по страницам Claude.
/// Теперь источников три — страницы, идущие Workflow и терминальные чаты; «не знаем» — не «тихо».
final class WorkNowWF234Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// Страницы Claude давно тихо — как на снимке владельца.
    private var quietPages: PageSignals { PageSignals(workingChats: 0, lastWorkingAt: now.addingTimeInterval(-900)) }

    private func watch(_ work: ProjectsWork?, quietFor seconds: TimeInterval = 3600) -> WorkWatch {
        var watch = WorkWatch()
        watch.note(ProjectsWork(at: now.addingTimeInterval(-seconds)))
        watch.note(work)
        return watch
    }

    private func offer(_ work: WorkNow, running: Bool = true, windows: Int = 3) -> Bool {
        ClaudeUpdateMenu.shouldOffer(ready: true, claudeRunning: running, windowCount: windows, work: work,
                                     lastOfferAt: nil, snoozeUntil: nil, now: now)
    }

    // MARK: - сводка → работа

    private func flow(_ n: Int, _ state: String) -> DigestWorkflow {
        DigestWorkflow(n: n, state: state, about: "о чём", steps: "", phase: "")
    }

    private func project(_ name: String, group: String, _ flows: [DigestWorkflow], terminal: Bool? = false,
                         live: Bool? = nil) -> DigestProject {
        DigestProject(name: name, title: name, marker: "", color: "#9b9ba1", group: group, done: 0, total: flows.count,
                      workflows: flows, at: "", terminal: terminal, live: live)
    }

    func testDigestCountsRunningWorkflowsAndTerminalsLikeThePage() throws {
        let stamp = ISO8601DateFormatter().string(from: now)
        let body = DigestBody(v: 1, at: stamp, projects: [
            project("Pimp", group: "идут", [flow(1, "готово"), flow(2, "идёт"), flow(3, "идёт"), flow(4, "впереди")],
                    terminal: true),
            project("Rick", group: "идут", [flow(1, "идёт")], terminal: true),
            // Сводка старше суток: «идёт» в ней в счёт не идёт — как у строки «Идёт Workflow сейчас».
            project("Old", group: "тихо", [flow(1, "идёт")]),
            project("Waits", group: "ждут", [flow(1, "ждёт")], terminal: nil),
            project("OnlyTerminal", group: "тихо", [], terminal: true),
        ])
        let work = try XCTUnwrap(ProjectsDigest.work(body, rootExists: true, now: now, turning: 1))
        XCTAssertEqual(work, ProjectsWork(workflows: 3, projects: 2, terminals: 1, at: now))
        XCTAssertTrue(work.busy)
    }

    /// #10460 (Элвис 21.10: панель писала «идёт работа: 4 Workflow · 4 терминала», а Workflow не шло ни одного и
    /// все 4 терминала стояли): застывшее «идёт» без живого прогона и стоящие терминалы — не работа.
    func testOnlyLiveRunsAndTurningTerminalsAreWork() throws {
        let stamp = ISO8601DateFormatter().string(from: now)
        let body = DigestBody(v: 1, at: stamp, projects: [
            project("Pimp", group: "идут", [flow(1, "идёт"), flow(2, "идёт")], terminal: true, live: false),
            project("Rick", group: "идут", [flow(1, "идёт")], terminal: true, live: false),
            project("Kz", group: "идут", [flow(1, "идёт")], terminal: true, live: true),
        ])
        let idle = try XCTUnwrap(ProjectsDigest.work(body, rootExists: true, now: now))
        XCTAssertEqual(idle, ProjectsWork(workflows: 1, projects: 1, terminals: 0, at: now))
        var quiet = body.projects
        quiet[2].live = false
        let none = try XCTUnwrap(ProjectsDigest.work(DigestBody(v: 1, at: stamp, projects: quiet), rootExists: true,
                                                     now: now))
        XCTAssertFalse(none.busy, "4 стоящих терминала и сводки с «идёт» без прогона — обновлению не мешают")
        XCTAssertNil(PimpPanelText.workShort(WorkNow(chats: 1, workflows: none.workflows, terminals: none.terminals)
            .seen(claudeRunning: false, windowCount: 0)))
    }

    func testTurnIsTheInterruptHintUnderTheInput() {
        let rule = String(repeating: "─", count: 40)
        let working = "● Читаю файл\n\n✻ Thinking…\n\(rule)\n❯ \n\(rule)\n  ⏵⏵ bypass permissions on (shift+tab to cycle)"
            + " · esc to interrupt · ← for agents\n\n\n"
        let standing = "● Готово.\n\(rule)\n❯ Рик: дальше\n\(rule)\n  ⏵⏵ bypass permissions on (shift+tab to cycle)"
            + " · ← for agents\n\n"
        XCTAssertTrue(PanelTiles.inTurn(working))
        XCTAssertFalse(PanelTiles.inTurn(standing))
        XCTAssertFalse(PanelTiles.inTurn("● esc to interrupt — так пишут в ответе\n" + standing),
                       "в ленте выше поля — не ход")
        XCTAssertTrue(PanelTiles.turningTerminals([]).isEmpty)
    }

    func testUnreadDigestIsUnknownButMissingFolderIsQuiet() {
        let unread = DigestBody(v: 1, at: nil, projects: [])
        XCTAssertNil(ProjectsDigest.work(unread, rootExists: true, now: now), "папка есть, а не прочиталась — не знаем")
        XCTAssertEqual(ProjectsDigest.work(unread, rootExists: false, now: now), ProjectsWork(at: now),
                       "папки проектов нет вовсе — работы там и быть не может")
        XCTAssertNil(ProjectsDigest.work(DigestBody(v: 1, at: "вчера", projects: []), rootExists: true, now: now))
        let empty = DigestBody(v: 1, at: ISO8601DateFormatter().string(from: now), projects: [])
        XCTAssertEqual(ProjectsDigest.work(empty, rootExists: true, now: now)?.busy, false)
    }

    // MARK: - случай владельца

    func testRunningWorkflowsBlockTheOfferAndThePill() {
        // 10.10.2026: страницы 15 минут тихо, а идёт 7 Workflow в 3 проектах.
        let work = watch(ProjectsWork(workflows: 7, projects: 3, at: now)).now(pages: quietPages, at: now)
        XCTAssertEqual(work.working, true)
        XCTAssertFalse(offer(work), "Workflow идут — не «самое время»")
        XCTAssertNil(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: work),
                     "«никто не работает» сказать нельзя")
        XCTAssertEqual(PimpPanelText.workLine(work), "Идут 7 Workflow в 3 проектах")
        XCTAssertTrue(ClaudeUpdateMenu.needsConfirm(claudeRunning: true, windowCount: 3, work: work))
        XCTAssertEqual(PimpPanelText.confirmQuestion(work: work),
                       "Идут 7 Workflow в 3 проектах — Claude закроется, работа может сброситься. Обновить всё равно?")
    }

    func testWorkingTerminalsBlockTheOfferAndThePill() {
        let work = watch(ProjectsWork(terminals: 4, at: now)).now(pages: quietPages, at: now)
        XCTAssertEqual(work.working, true)
        XCTAssertFalse(offer(work))
        XCTAssertNil(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: work))
        XCTAssertEqual(PimpPanelText.workLine(work), "Работают 4 терминала")
        XCTAssertEqual(PimpPanelText.confirmQuestion(work: work),
                       "Работают 4 терминала — Claude закроется, работа может сброситься. Обновить всё равно?")
    }

    func testWorkOutsidePagesBlocksEvenWithoutClaudeWindows() {
        let work = watch(ProjectsWork(workflows: 1, projects: 1, terminals: 1, at: now)).now(pages: PageSignals(), at: now)
        XCTAssertFalse(offer(work, running: false, windows: 0), "Claude не запущен, но работа идёт — не предлагаем")
        XCTAssertNil(PimpPanelText.offerReason(claudeRunning: false, windowCount: 0, work: work))
        XCTAssertFalse(ClaudeUpdateMenu.needsConfirm(claudeRunning: false, windowCount: 0, work: work),
                       "закрывать нечего — обновление ничего не прервёт, вопроса нет")
    }

    // MARK: - не знаем — не «тихо»

    func testUnknownIsNotQuiet() {
        // Сводку ещё не читали.
        let never = WorkWatch().now(pages: quietPages, at: now)
        XCTAssertNil(never.working)
        XCTAssertNil(never.idleSeconds, "источник не наблюдали — минут тишины нет")
        XCTAssertFalse(offer(never))
        XCTAssertNil(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: never))
        XCTAssertFalse(offer(never, running: false, windows: 0), "и без окон: про Workflow не знаем — не предлагаем")
        XCTAssertNil(PimpPanelText.workLine(never), "выдумывать работу тоже нельзя")
        XCTAssertTrue(ClaudeUpdateMenu.needsConfirm(claudeRunning: true, windowCount: 3, work: never))
        XCTAssertEqual(PimpPanelText.confirmQuestion(work: never), "Claude закроется вместе с окнами — обновить сейчас?")

        // Сводка была тихой, но устарела: опрос встал — это уже не знание.
        let stale = watch(ProjectsWork(at: now.addingTimeInterval(-WorkWatch.freshSeconds)))
            .now(pages: quietPages, at: now)
        XCTAssertNil(stale.working)
        XCTAssertFalse(offer(stale))
        XCTAssertNil(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: stale))

        // Сводка не прочиталась — прежняя не переписывается «тишиной».
        var kept = watch(ProjectsWork(workflows: 2, projects: 1, at: now.addingTimeInterval(-10)))
        kept.note(nil)
        XCTAssertEqual(kept.now(pages: quietPages, at: now).workflows, 2)

        // Страницы молчат при открытых окнах.
        let silent = watch(ProjectsWork(at: now)).now(pages: PageSignals(), at: now)
        XCTAssertNil(silent.working)
        XCTAssertFalse(offer(silent))
        XCTAssertTrue(offer(silent, running: false, windows: 0), "окон нет — страницам работать негде, остальное тихо")
    }

    // MARK: - тишина — от последней работы любого источника

    func testIdleCountsFromTheLatestWorkOfAnySource() {
        // Страницы тихо 15 минут, Workflow кончился 40 секунд назад.
        var recent = WorkWatch()
        recent.note(ProjectsWork(workflows: 1, projects: 1, at: now.addingTimeInterval(-40)))
        recent.note(ProjectsWork(at: now))
        let work = recent.now(pages: quietPages, at: now)
        XCTAssertEqual(work.working, false)
        XCTAssertEqual(work.idleSeconds, 40)
        XCTAssertFalse(offer(work), "тихо меньше 120 с — рано")
        XCTAssertEqual(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: work), "никто не работает",
                       "и не «15 мин»: минуты — от последней работы любого источника")

        // Наоборот: Workflow давно тихо, страница работала 30 с назад.
        let pages = PageSignals(workingChats: 0, lastWorkingAt: now.addingTimeInterval(-30))
        XCTAssertEqual(watch(ProjectsWork(at: now)).now(pages: pages, at: now).idleSeconds, 30)

        // Все тихо давно — предлагаем, минуты честные.
        let quiet = watch(ProjectsWork(at: now), quietFor: 600).now(pages: quietPages, at: now)
        XCTAssertEqual(quiet.idleSeconds, 600)
        XCTAssertTrue(offer(quiet))
        XCTAssertEqual(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: quiet), "10 мин никто не работает")

        // Работу сводка видела — первая тихая сводка тишину не удлиняет.
        var seen = WorkWatch()
        seen.note(ProjectsWork(at: now.addingTimeInterval(-900)))
        seen.note(ProjectsWork(terminals: 1, at: now.addingTimeInterval(-60)))
        seen.note(ProjectsWork(at: now))
        XCTAssertEqual(seen.now(pages: quietPages, at: now).idleSeconds, 60)
    }

    // MARK: - тексты

    func testWorkLineAndQuestionNameEverythingThatGoes() {
        let all = WorkNow(chats: 2, workflows: 7, projects: 3, terminals: 4)
        XCTAssertEqual(PimpPanelText.workLine(all), "Идут 7 Workflow в 3 проектах · работают 4 терминала · идёт работа в 2 чатах")
        XCTAssertEqual(PimpPanelText.confirmQuestion(work: all),
                       "Идут 7 Workflow в 3 проектах · работают 4 терминала · идёт работа в 2 чатах — Claude закроется, работа может сброситься. Обновить всё равно?")
        let one = WorkNow(chats: 1, workflows: 1, projects: 1, terminals: 1)
        XCTAssertEqual(PimpPanelText.workLine(one), "Идёт 1 Workflow в 1 проекте · работает 1 терминал · идёт работа в 1 чате")
        XCTAssertEqual(PimpPanelText.workLine(WorkNow(chats: 0, workflows: 0, terminals: 5)), "Работают 5 терминалов")
        XCTAssertEqual(PimpPanelText.workLine(WorkNow(chats: 21, workflows: 0, terminals: 0)), "Идёт работа в 21 чате")
        XCTAssertNil(PimpPanelText.workLine(WorkNow(chats: 0, workflows: 0, terminals: 0)))
        // Окон нет — страницы в счёт не идут, даже если их старый ответ ещё жив.
        XCTAssertEqual(PimpPanelText.workLine(all.seen(claudeRunning: true, windowCount: 0)),
                       "Идут 7 Workflow в 3 проектах · работают 4 терминала")
        XCTAssertEqual(PimpPanelText.patchWorkNote(WorkNow(workflows: 2, projects: 1, terminals: 0)),
                       "Идут 2 Workflow в 1 проекте — Claude закроется и прервёт их.")
        XCTAssertNil(PimpPanelText.patchWorkNote(WorkNow()))
    }

    // MARK: - блок панели

    func testBlockTellsTheTruthWhileWorkGoes() {
        var menu = ClaudeUpdateMenu()
        menu.finish(.available(version: "2.31226.1"), at: now)
        menu.startDownload(version: "2.31226.1")
        menu.downloaded(version: "2.31226.1")
        let line = "Идут 7 Workflow в 3 проектах"
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(workLine: line)), .busy(version: "2.31226.1", work: line))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(offerReason: "15 мин никто не работает", workLine: line)),
                       .busy(version: "2.31226.1", work: line), "работа видна — «самое время» не показываем")
        let question = PimpPanelText.confirmQuestion(work: WorkNow(chats: 0, workflows: 7, projects: 3, terminals: 0))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(workLine: line, question: question)),
                       .ready(version: "2.31226.1", question: question), "нажали «Обновить сейчас» — вопрос")
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(offerReason: "10 мин никто не работает")),
                       .timely(version: "2.31226.1", reason: "10 мин никто не работает"))
        // Пример окна связки ключей живёт в состоянии «ставлю»: готово или сбой — блок другой.
        XCTAssertTrue(menu.startInstall())
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(workLine: line, installStep: 3)),
                       .installing(version: "2.31226.1", step: 3))
        menu.installFinished()
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(doneVersion: "2.31226.1")), .done(version: "2.31226.1"))
    }

    func testKeychainExampleWords() {
        // WF238: слова примера — как в настоящем окне macOS (`docs/ref/claude-svyazka-klyuchey.png`).
        XCTAssertEqual(PimpPanelText.keychainTitle, "«Claude» хочет использовать конфиденциальную информацию, "
            + "хранящуюся в «Claude Safe Storage» в Вашей связке ключей.")
        XCTAssertEqual(PimpPanelText.keychainBody, "Чтобы разрешить это, введите пароль для связки ключей «Вход».")
        XCTAssertEqual(PimpPanelText.keychainPassword, "Пароль:")
        XCTAssertEqual(PimpPanelText.keychainHint, "Нажми «Разрешать всегда» — пароль получает macOS, не PMP")
        XCTAssertEqual([PimpPanelText.keychainAlways, PimpPanelText.keychainDeny, PimpPanelText.keychainAllow],
                       ["Разрешать всегда", "Отказать", "Разрешить"])
        XCTAssertEqual(PimpPanelText.openSourceURL, "https://github.com/ElvisIglikov/PimpMyClaude")
    }
}
