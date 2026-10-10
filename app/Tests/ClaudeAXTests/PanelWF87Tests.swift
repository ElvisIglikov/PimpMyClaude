import XCTest
@testable import ClaudeAX

/// Пимп у часов (WF87, батч C, `docs/10-choice.md`): значок (режимы, остаток, прочерк, метки),
/// состояния панели по стадиям обновления, провязка «самое время», разбор working/limits.
final class PanelWF87Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func limits(week: Int? = 77, five: Int? = 65, fable: Int? = 40, source: String? = "api",
                        age: TimeInterval = 30, plan: String? = "Max 20x",
                        weekReset: Date? = nil) -> ClaudeLimits {
        ClaudeLimits(at: now.addingTimeInterval(-age), plan: plan,
                     fiveHour: five.map { .init(used: $0, resetsAt: now.addingTimeInterval(58 * 60)) },
                     weekly: week.map { .init(used: $0, resetsAt: weekReset ?? now.addingTimeInterval(3 * 86_400)) },
                     fable: fable.map { .init(used: $0, resetsAt: nil) }, source: source)
    }

    private let installed = StatusIcon.Patch.installed(version: "2.9939.2", loader: 7)

    func testCompactPercentAndWarnings() {
        XCTAssertEqual(StatusIcon.mode("percent"), .percent)
        XCTAssertEqual(StatusIcon.mainKind(.percent, limits()), .week)
        XCTAssertEqual(StatusIcon.menuTitle(.percent, limits: limits(), now: now), "Только % · неделя")
        for used in [0, 62, 100] {
            let plain = StatusIcon.look(mode: .percent, limits: limits(week: used), patch: installed, phase: .idle, now: now)
            XCTAssertEqual(plain.number, used)
            XCTAssertTrue(plain.showsNumber)
            XCTAssertTrue(plain.bars.isEmpty)
            let lost = StatusIcon.look(mode: .percent, limits: limits(week: used), patch: .lost(version: "1"), phase: .ready(version: "2"), now: now)
            XCTAssertEqual(lost.mark, .patchLost)
            XCTAssertEqual(lost.width, plain.width + 10, "метка отдельно от числа, в том числе 100%")
        }
        let stale = StatusIcon.look(mode: .percent, limits: limits(age: 601), patch: installed, phase: .idle, now: now)
        XCTAssertNil(stale.number)
        XCTAssertTrue(stale.showsNumber)
        XCTAssertEqual(StatusIcon.look(mode: .percent, limits: nil, patch: installed, phase: .idle, now: now).number, nil)
        XCTAssertEqual(StatusIcon.look(mode: .percent, limits: limits(), patch: installed, phase: .ready(version: "2"), now: now).mark, .updateReady)
        let spin = StatusIcon.look(mode: .percent, limits: limits(), patch: installed, phase: .installing(version: "2"), now: now)
        XCTAssertTrue(spin.spinner)
        XCTAssertFalse(spin.showsNumber)
        XCTAssertEqual(spin.width, 22)
        for patch in [StatusIcon.Patch.claudeNotFound, .notInstalled(version: "1")] {
            let outline = StatusIcon.look(mode: .percent, limits: limits(), patch: patch, phase: .idle, now: now)
            XCTAssertTrue(outline.outlined)
            XCTAssertNil(outline.number)
            XCTAssertEqual(outline.width, 22)
        }
    }

    // MARK: - значок

    func testDefaultModeIsWeekAndNumberIsUsed() {
        XCTAssertEqual(StatusIcon.mode(nil), .week)
        XCTAssertEqual(StatusIcon.mode("мусор"), .week)
        XCTAssertEqual(StatusIcon.mode("fable"), .fable)
        let look = StatusIcon.look(mode: .week, limits: limits(), patch: installed, phase: .idle, now: now)
        XCTAssertEqual(look.number, 77, "израсходовано, как у Claude (#7863)")
        XCTAssertTrue(look.showsNumber)
        XCTAssertEqual(look.width, 45)
        XCTAssertEqual(look.level, .normal)
        XCTAssertEqual(look.mark, .none)
        XCTAssertEqual(StatusIcon.look(mode: .fiveHour, limits: limits(), patch: installed, phase: .idle, now: now).number, 65)
        XCTAssertEqual(StatusIcon.look(mode: .fable, limits: limits(), patch: installed, phase: .idle, now: now).number, 40)
    }

    func testRemainingClampsAndResetInPastIsFull() {
        XCTAssertEqual(StatusIcon.remaining(.init(used: 130, resetsAt: nil), now: now), 0)
        XCTAssertEqual(StatusIcon.remaining(.init(used: -5, resetsAt: nil), now: now), 100)
        XCTAssertEqual(StatusIcon.remaining(.init(used: 95, resetsAt: now.addingTimeInterval(-1)), now: now), 100,
                       "сброс уже прошёл — цифра вчерашняя, показываем 100")
        XCTAssertNil(StatusIcon.remaining(nil, now: now))
        XCTAssertEqual(StatusIcon.used(.init(used: 130, resetsAt: nil), now: now), 100)
        XCTAssertEqual(StatusIcon.used(.init(used: 95, resetsAt: now.addingTimeInterval(-1)), now: now), 0, "сброс прошёл — 0")
        let full = StatusIcon.look(mode: .week, limits: limits(week: 100), patch: installed, phase: .idle, now: now)
        XCTAssertEqual(full.number, 100)
        XCTAssertEqual(full.level, .critical)
        XCTAssertEqual(full.width, 52, "«100» шире двух цифр")
    }

    func testDashWhenNoNumbers() {
        for broken in [nil, limits(source: nil), limits(week: nil), limits(age: 601)] as [ClaudeLimits?] {
            let look = StatusIcon.look(mode: .week, limits: broken, patch: installed, phase: .idle, now: now)
            XCTAssertTrue(look.showsNumber)
            XCTAssertNil(look.number, "нет цифр — прочерк")
            XCTAssertEqual(look.width, 45)
            XCTAssertEqual(look.toolTip, "PMP — лимиты придут, когда откроется окно Claude")
        }
        XCTAssertEqual(StatusIcon.look(mode: .week, limits: limits(age: 600), patch: installed, phase: .idle,
                                       now: now).number, 77, "ровно 10 минут — ещё свежие")
    }

    func testFableModeFallsBackToWeekWithoutFableOnPlan() {
        let noFable = StatusIcon.look(mode: .fable, limits: limits(fable: nil), patch: installed, phase: .idle, now: now)
        XCTAssertEqual(noFable.number, 77, "тариф без Fable (api) — неделя")
        let label = StatusIcon.look(mode: .fable, limits: limits(fable: nil, source: "label"), patch: installed,
                                    phase: .idle, now: now)
        XCTAssertNil(label.number, "подпись кружка — один лимит, остальных просто нет: прочерк")
    }

    func testThreeBarsAndPlain() {
        let three = StatusIcon.look(mode: .three, limits: limits(fable: nil), patch: installed, phase: .idle, now: now)
        XCTAssertEqual(three.bars, [65, 77, nil], "сверху вниз 5 часов, неделя, Fable — израсходовано, как число")
        XCTAssertFalse(three.showsNumber)
        XCTAssertEqual(three.width, 47)
        let plain = StatusIcon.look(mode: .plain, limits: limits(), patch: installed, phase: .idle, now: now)
        XCTAssertFalse(plain.showsNumber)
        XCTAssertTrue(plain.bars.isEmpty)
        XCTAssertEqual(plain.width, 25, "WF180: плашка 23 pt и по пикселю с краёв")
    }

    func testLevels() {
        XCTAssertEqual(StatusIcon.level(21), .normal)
        XCTAssertEqual(StatusIcon.level(20), .low)
        XCTAssertEqual(StatusIcon.level(11), .low)
        XCTAssertEqual(StatusIcon.level(10), .critical)
        XCTAssertEqual(StatusIcon.level(nil), .normal)
        XCTAssertEqual(StatusIcon.look(mode: .week, limits: limits(week: 92), patch: installed, phase: .idle,
                                       now: now).level, .critical)
    }

    func testMarksAndStates() {
        let lost = StatusIcon.look(mode: .week, limits: limits(), patch: .lost(version: "2.9939.2"),
                                   phase: .ready(version: "2.9941.0"), now: now)
        XCTAssertEqual(lost.mark, .patchLost, "точка сильнее треугольника")
        XCTAssertEqual(lost.number, 77, "число при слетевшем патче остаётся")
        let ready = StatusIcon.look(mode: .week, limits: limits(), patch: installed,
                                    phase: .ready(version: "2.9941.0"), now: now)
        XCTAssertEqual(ready.mark, .updateReady)
        let spinning = StatusIcon.look(mode: .week, limits: limits(), patch: installed,
                                       phase: .installing(version: "2.9941.0"), now: now)
        XCTAssertTrue(spinning.spinner)
        XCTAssertFalse(spinning.showsNumber)
        XCTAssertEqual(spinning.width, 41)
        let race = ClaudeUpdateMenu.Race(version: "2.9941.0", lanes: [])
        XCTAssertEqual(StatusIcon.look(mode: .week, limits: limits(), patch: installed, phase: .downloading(race),
                                       now: now), StatusIcon.look(mode: .week, limits: limits(), patch: installed,
                                                                  phase: .idle, now: now),
                       "во время гонки значок не меняется")
        for patch in [StatusIcon.Patch.notInstalled(version: "2.9939.2"), .claudeNotFound] {
            let bare = StatusIcon.look(mode: .week, limits: limits(), patch: patch, phase: .idle, now: now)
            XCTAssertTrue(bare.outlined)
            XCTAssertFalse(bare.showsNumber)
            XCTAssertEqual(bare.width, 26)
        }
    }

    func testToolTipAndMenuTitles() {
        let week = limits(weekReset: Date(timeIntervalSince1970: 1_800_000_000 + 4 * 86_400 + 3600))
        XCTAssertEqual(StatusIcon.toolTip(mode: .week, limits: week, now: now, calendar: utc),
                       "PMP — неделя: израсходовано 77 % · сброс вт 09:00")
        XCTAssertEqual(StatusIcon.menuTitle(.week, limits: limits(), now: now), "Неделя — 77 %")
        XCTAssertEqual(StatusIcon.menuTitle(.fiveHour, limits: limits(), now: now), "5 часов — 65 %")
        XCTAssertEqual(StatusIcon.menuTitle(.fable, limits: limits(), now: now), "Fable — 40 %")
        XCTAssertEqual(StatusIcon.menuTitle(.three, limits: limits(), now: now), "Три полоски")
        XCTAssertEqual(StatusIcon.menuTitle(.plain, limits: limits(), now: now), "Только PMP")
        XCTAssertEqual(StatusIcon.menuTitle(.week, limits: nil, now: now), "Неделя", "нет цифр — без « — N %»")
    }

    func testResetText() {
        XCTAssertEqual(StatusIcon.resetText(now.addingTimeInterval(58 * 60), now: now), "сброс через 58 мин")
        XCTAssertEqual(StatusIcon.resetText(now.addingTimeInterval(3 * 3600 + 12 * 60), now: now),
                       "сброс через 3 ч 12 мин")
        XCTAssertEqual(StatusIcon.resetText(now.addingTimeInterval(2 * 3600), now: now), "сброс через 2 ч")
        // 1_800_000_000 — пт 15 янв 2027 08:00 UTC.
        XCTAssertEqual(StatusIcon.resetText(now.addingTimeInterval(7 * 86_400), now: now, calendar: utc), "сброс пт 08:00")
        // #8896: неделя и Fable сбрасываются в один момент, а приходят с разницей в секунду — подпись одна.
        XCTAssertEqual(StatusIcon.resetText(now.addingTimeInterval(7 * 86_400 - 1), now: now, calendar: utc), "сброс пт 08:00")
        XCTAssertEqual(StatusIcon.resetText(now.addingTimeInterval(7 * 86_400 + 29), now: now, calendar: utc), "сброс пт 08:00")
        XCTAssertEqual(StatusIcon.resetText(now.addingTimeInterval(7 * 86_400 - 31), now: now, calendar: utc), "сброс пт 07:59")
        XCTAssertNil(StatusIcon.resetText(now.addingTimeInterval(-60), now: now))
        XCTAssertNil(StatusIcon.resetText(nil, now: now))
    }

    func testWeekStrip() {
        // now — пт 15 янв 2027 08:00 UTC; сброс через 2 дня 7 часов — вс 15:00, неделя началась в вс 15:00.
        let strip = StatusIcon.weekStrip(now.addingTimeInterval(2 * 86_400 + 7 * 3600), now: now, calendar: utc)
        XCTAssertEqual(strip?.left, "2 дня 7 часов")
        XCTAssertEqual(strip?.days, ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"])
        XCTAssertEqual(strip?.today, 4)
        XCTAssertEqual(strip?.fills.prefix(4), [1, 1, 1, 1])
        XCTAssertEqual(strip?.fills[4] ?? 0, 17.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(strip?.fills.suffix(2), [0, 0])
        XCTAssertEqual(StatusIcon.weekStrip(now.addingTimeInterval(5 * 3600), now: now, calendar: utc)?.left, "5 часов")
        XCTAssertEqual(StatusIcon.weekStrip(now.addingTimeInterval(21 * 60), now: now, calendar: utc)?.left, "21 минута")
        XCTAssertNil(StatusIcon.weekStrip(now.addingTimeInterval(-60), now: now))
        XCTAssertNil(StatusIcon.weekStrip(nil, now: now))
    }

    // MARK: - панель: патч

    func testPatchCards() {
        XCTAssertNil(PimpPanelText.patchCard(installed), "всё хорошо — тихо")
        XCTAssertEqual(PimpPanelText.patchCard(.notInstalled(version: "2.9939.2"))?.button, "Пропатчить Claude")
        XCTAssertEqual(PimpPanelText.patchCard(.lost(version: "2.9939.2"))?.button, "Вернуть патч")
        XCTAssertEqual(PimpPanelText.patchCard(.claudeNotFound)?.button, "Найти Claude…")
        // #8894: план первым, номера лоадера нет, версия приложения — последней. WF126: о беде говорит карточка
        // патча — в шапке тогда только версии, без плана.
        XCTAssertEqual(PimpPanelText.headerLine(installed, plan: "Max 20x", app: "1.10.0"),
                       "Max 20x · Claude 2.9939.2 · PMP 1.10.0")
        XCTAssertEqual(PimpPanelText.headerLine(installed, plan: nil, app: "1.10.0"), "Claude 2.9939.2 · PMP 1.10.0")
        XCTAssertEqual(PimpPanelText.headerLine(installed, plan: "Max 20x"), "Max 20x · Claude 2.9939.2")
        XCTAssertEqual(PimpPanelText.headerLine(.lost(version: "2.9939.2"), plan: nil), "Claude 2.9939.2")
        XCTAssertEqual(PimpPanelText.headerLine(.lost(version: "2.9939.2"), plan: "Max 20x", app: "1.10.0"),
                       "Claude 2.9939.2 · PMP 1.10.0")
        XCTAssertEqual(PimpPanelText.headerLine(.notInstalled(version: "2.9939.2"), plan: nil, app: "1.10.0"),
                       "Claude 2.9939.2 · PMP 1.10.0")
        XCTAssertEqual(PimpPanelText.headerLine(.claudeNotFound, plan: "Max 20x", app: "1.10.0"), "PMP 1.10.0")
        // Без «…» в строке (WF181): «Проверяю Claude» — подсказкой.
        XCTAssertEqual(PimpPanelText.headerLine(.unknown, plan: "Max 20x", app: "1.10.0"), "PMP 1.10.0")
        XCTAssertEqual(PimpPanelText.headerHelp(.unknown), "Проверяю Claude")
        XCTAssertEqual(PimpPanelText.headerHelp(installed), "")
        // Слова «Пимп» в видимом нет (слово Элвиса 06.10): карточки — «PMP».
        XCTAssertEqual(PimpPanelText.patchCard(.notInstalled(version: "2.9939.2"))?.title, "Claude пока без патча PMP")
        XCTAssertEqual(PimpPanelText.patchCard(.lost(version: "2.9939.2"))?.text,
                       "Темы, узкие окна и полоска работы сейчас молчат. Настройки целы.")
        XCTAssertEqual(PimpPanelText.patchStep("Закрываю Claude…", loader: 7), "Закрываю Claude…")
        XCTAssertEqual(PimpPanelText.patchStep("Ставлю лоадер в app.asar…", loader: 7), "Ставлю патч 7.0…")
        XCTAssertEqual(PimpPanelText.patchStep("Готово. Открываю Claude…", loader: 7), "Открываю Claude…")
        XCTAssertNil(PimpPanelText.patchStep("Настройки /x/claude.json", loader: 7))
        XCTAssertEqual(PimpPanelText.patchStep(
            "macOS спрашивает разрешение «Управление приложениями» — нажми «Разрешить», дальше сам.", loader: 7),
                       "Нажми «Разрешить» в окне macOS…")
    }

    // MARK: - панель: блок обновления по стадиям

    private func lane(_ id: String, _ state: ClaudeUpdateMenu.LaneState, bytes: Int64 = 200_000_000,
                      speed: Double = 2_000_000) -> ClaudeUpdateMenu.Lane {
        ClaudeUpdateMenu.Lane(id: id, title: id, bytes: bytes, total: 374_000_000, bytesPerSec: speed, state: state)
    }

    func testUpdateBlockFollowsPhases() {
        var menu = ClaudeUpdateMenu()
        let quiet = PimpPanelText.UpdateExtras()
        XCTAssertEqual(PimpPanelText.updateBlock(menu, quiet), .none)
        XCTAssertTrue(menu.beginCheck(at: now, trigger: .manual))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, quiet), .none, "проверка — блока нет")
        menu.finish(.available(version: "2.9941.0"), at: now)
        XCTAssertEqual(PimpPanelText.updateBlock(menu, quiet), .available(version: "2.9941.0", canWrite: true, note: nil))
        menu.canWrite = false
        XCTAssertEqual(PimpPanelText.updateBlock(menu, quiet), .available(version: "2.9941.0", canWrite: false, note: nil))
        menu.canWrite = true

        menu.startDownload(version: "2.9941.0")
        let live = ClaudeUpdateMenu.Race(version: "2.9941.0", lanes: [lane("r2", .leading), lane("github", .running)])
        menu.progress(live)
        XCTAssertEqual(PimpPanelText.updateBlock(menu, quiet), .downloading(live))
        menu.progress(ClaudeUpdateMenu.Race(version: "2.9941.0", lanes: [lane("r2", .won), lane("github", .dropped("не понадобился"))]))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, quiet), .verifying(version: "2.9941.0", from: "Cloudflare"),
                       "гонка кончилась — проверяю подпись")

        menu.downloaded(version: "2.9941.0")
        XCTAssertEqual(PimpPanelText.updateBlock(menu, quiet), .ready(version: "2.9941.0", question: nil))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(offerReason: "окна Claude закрыты")),
                       .timely(version: "2.9941.0", reason: "окна Claude закрыты"))
        let asked = PimpPanelText.UpdateExtras(offerReason: "x", question: "Идёт работа в 2 чатах — обновить всё равно?")
        XCTAssertEqual(PimpPanelText.updateBlock(menu, asked),
                       .ready(version: "2.9941.0", question: "Идёт работа в 2 чатах — обновить всё равно?"),
                       "вопрос сильнее «самое время»")
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(snoozedShown: true)), .snoozed)

        XCTAssertTrue(menu.startInstall())
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(installStep: 2)), .installing(version: "2.9941.0", step: 2))
        menu.installFailed("Claude не закрылся")
        menu.restoreReady(version: "2.9941.0")
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(installFailure: "Claude не закрылся")),
                       .failed("Claude не закрылся"), "сбой виден и поверх вернувшегося готового")
        XCTAssertTrue(menu.startInstall())
        menu.installFinished()
        XCTAssertEqual(PimpPanelText.updateBlock(menu, .init(doneVersion: "2.9941.0")), .done(version: "2.9941.0"))
        XCTAssertEqual(PimpPanelText.updateBlock(menu, quiet), .none)
    }

    func testInstallStepsFromProgressLines() {
        var step = 0
        for (line, want) in [("Проверяю подпись Anthropic…", 0), ("Закрываю Claude…", 0),
                             ("Меняю Claude 2.9939.2 на 2.9941.0…", 1), ("Ставлю патч на новый Claude…", 2),
                             ("Ставлю лоадер в app.asar…", 2), ("Готово. Открываю Claude…", 3),
                             ("Закрываю Claude…", 3)] {
            step = PimpPanelText.installStep(line, current: step)
            XCTAssertEqual(step, want, line)
        }
        XCTAssertEqual(PimpPanelText.installSteps(version: "2.9941.0", loader: 7),
                       ["Закрываю Claude", "Ставлю Claude 2.9941.0", "Ставлю патч 7.0", "Открываю Claude",
                        "Окна встают на места"])
    }

    func testRaceTexts() {
        let race = ClaudeUpdateMenu.Race(version: "2.9941.0", lanes: [
            lane("github", .dropped("отстал — отключён"), bytes: 2_700_000, speed: 0),
            lane("r2", .leading, bytes: 212_000_000, speed: 1_000_000),
            lane("anthropic", .running, bytes: 100_000_000, speed: 500_000),
        ])
        XCTAssertEqual(PimpPanelText.orderedLanes(race.lanes).map { $0.id }, ["r2", "anthropic", "github"])
        XCTAssertEqual(PimpPanelText.orderedLanes(race.lanes).map(PimpPanelText.laneName),
                       ["Cloudflare", "Anthropic", "GitHub"])
        XCTAssertEqual(PimpPanelText.raceSubtitle(race, elapsed: 2), "наперегонки из трёх мест")
        XCTAssertEqual(PimpPanelText.raceSubtitle(race, elapsed: 36), "наперегонки · осталось ~3 мин")
        let close = ClaudeUpdateMenu.Race(version: "2.9941.0", lanes: [lane("r2", .leading, bytes: 334_000_000,
                                                                            speed: 1_000_000)])
        XCTAssertEqual(PimpPanelText.raceSubtitle(close, elapsed: 36), "наперегонки · осталось ~40 с")
        XCTAssertEqual(PimpPanelText.elapsedText(36), "0:36")
        XCTAssertEqual(PimpPanelText.elapsedText(125), "2:05")
        XCTAssertEqual(PimpPanelText.bytesText(212_000_000, total: 374_000_000), "212 из 374 МБ")
        XCTAssertEqual(PimpPanelText.bytesText(2_700_000, total: 374_000_000), "2,7 из 374 МБ")
        XCTAssertEqual(PimpPanelText.laneBadge(race.lanes[0], revived: false), "отстал — отключён")
        XCTAssertEqual(PimpPanelText.laneBadge(race.lanes[1], revived: false), "лидер")
        XCTAssertNil(PimpPanelText.laneBadge(race.lanes[2], revived: false))
        XCTAssertEqual(PimpPanelText.laneBadge(race.lanes[2], revived: true), "ожил — лидер сполз")
    }

    func testLaneMemoryRevives() {
        var memory = LaneMemory()
        memory.note(.init(version: "v", lanes: [lane("github", .dropped("отстал — отключён"))]), at: now)
        XCTAssertFalse(memory.isRevived("github", at: now))
        memory.note(.init(version: "v", lanes: [lane("github", .running)]), at: now)
        XCTAssertTrue(memory.isRevived("github", at: now.addingTimeInterval(5.9)))
        XCTAssertFalse(memory.isRevived("github", at: now.addingTimeInterval(6)), "метка «ожил» — 6 с")
        memory.note(.init(version: "v", lanes: [lane("r2", .running)]), at: now)
        XCTAssertFalse(memory.isRevived("r2", at: now), "не отключалась — не «ожила»")
    }

    // MARK: - «самое время»: провязка shouldOffer

    func testOfferWiring() {
        let signals = PageSignals(workingChats: 0, lastWorkingAt: now.addingTimeInterval(-150))
        XCTAssertEqual(signals.anyPageWorking, false)
        XCTAssertEqual(signals.idleSeconds(at: now), 150)
        XCTAssertTrue(ClaudeUpdateMenu.shouldOffer(ready: true, claudeRunning: true, windowCount: 3,
                                                   anyPageWorking: signals.anyPageWorking,
                                                   idleSeconds: signals.idleSeconds(at: now),
                                                   lastOfferAt: nil, snoozeUntil: nil, now: now))
        let busy = PageSignals(workingChats: 2, lastWorkingAt: now)
        XCTAssertFalse(ClaudeUpdateMenu.shouldOffer(ready: true, claudeRunning: true, windowCount: 3,
                                                    anyPageWorking: busy.anyPageWorking,
                                                    idleSeconds: busy.idleSeconds(at: now),
                                                    lastOfferAt: nil, snoozeUntil: nil, now: now))
        XCTAssertNil(PageSignals().anyPageWorking, "ответа нет — не знаем")
        XCTAssertNil(PageSignals().idleSeconds(at: now))
        // Гейт 2 WF87: работы не видели — тишина с первого тихого круга; меньше 2 мин — не предлагаем.
        let started = PageSignals(workingChats: 0, quietSince: now.addingTimeInterval(-30))
        XCTAssertEqual(started.idleSeconds(at: now), 30)
        XCTAssertFalse(ClaudeUpdateMenu.shouldOffer(ready: true, claudeRunning: true, windowCount: 3,
                                                    anyPageWorking: started.anyPageWorking,
                                                    idleSeconds: started.idleSeconds(at: now),
                                                    lastOfferAt: nil, snoozeUntil: nil, now: now))
        XCTAssertEqual(PageSignals(lastWorkingAt: now.addingTimeInterval(-10), quietSince: now.addingTimeInterval(-900))
                        .idleSeconds(at: now), 10, "работа была — считаем от неё")
        // «Обновить»: ответ до нажатия не годится.
        let answered = PageSignals(workingChats: 0, workingAt: now)
        XCTAssertEqual(answered.answered(after: now).workingChats, 0)
        XCTAssertNil(answered.answered(after: now.addingTimeInterval(0.1)).workingChats)
        XCTAssertNil(PageSignals(workingChats: 0).answered(after: now).anyPageWorking)

        XCTAssertEqual(PimpPanelText.offerReason(claudeRunning: false, windowCount: 0, idleSeconds: nil), "Claude не запущен")
        XCTAssertEqual(PimpPanelText.offerReason(claudeRunning: true, windowCount: 0, idleSeconds: nil), "окна Claude закрыты")
        XCTAssertEqual(PimpPanelText.offerReason(claudeRunning: true, windowCount: 2, idleSeconds: 150),
                       "2 мин никто не работает")
        XCTAssertEqual(PimpPanelText.offerReason(claudeRunning: true, windowCount: 2, idleSeconds: 60),
                       "никто не работает", "меньше 2 мин наблюдения — минут не называем")
        XCTAssertEqual(PimpPanelText.offerReason(claudeRunning: true, windowCount: 2, idleSeconds: nil),
                       "никто не работает")
        XCTAssertEqual(PimpPanelText.offerReason(claudeRunning: true, windowCount: 2, idleSeconds: 600),
                       "10 мин никто не работает")

        XCTAssertEqual(PimpPanelText.confirmQuestion(workingChats: 2), "Идёт работа в 2 чатах — обновить всё равно?")
        XCTAssertEqual(PimpPanelText.confirmQuestion(workingChats: nil),
                       "Claude закроется вместе с окнами — обновить сейчас?")
    }

    func testReadyNotificationOncePerVersion() {
        let since = now.addingTimeInterval(-3600)
        XCTAssertTrue(PimpPanelText.shouldNotifyReady(version: "2.9941.0", notified: nil, offer: true,
                                                      readySince: since, now: now), "первый момент «самое время»")
        XCTAssertFalse(PimpPanelText.shouldNotifyReady(version: "2.9941.0", notified: nil, offer: false,
                                                       readySince: since, now: now), "ещё не время и не сутки")
        XCTAssertTrue(PimpPanelText.shouldNotifyReady(version: "2.9941.0", notified: "2.9939.2", offer: false,
                                                      readySince: now.addingTimeInterval(-24 * 3600), now: now),
                      "сутки без удобного момента — всё равно одно")
        XCTAssertFalse(PimpPanelText.shouldNotifyReady(version: "2.9941.0", notified: "2.9941.0", offer: true,
                                                       readySince: since, now: now), "одно на версию")
    }

    // MARK: - разбор limits

    func testLimitsParse() {
        let parsed = ClaudeLimits.parse([
            "v": 1, "at": 1_756_900_000_123, "plan": "Max 20x", "source": "api",
            "fiveHour": ["used": 65, "resetsAt": 1_756_903_600_000],
            "weekly": ["used": 177, "resetsAt": NSNull()],
            "fable": NSNull(),
        ] as [String: Any])
        XCTAssertEqual(parsed?.plan, "Max 20x")
        XCTAssertEqual(parsed?.source, "api")
        XCTAssertEqual(parsed?.fiveHour, .init(used: 65, resetsAt: Date(timeIntervalSince1970: 1_756_903_600)))
        XCTAssertEqual(parsed?.weekly, .init(used: 100, resetsAt: nil), "used зажат в 0…100")
        XCTAssertNil(parsed?.fable)
        XCTAssertEqual(parsed?.at, Date(timeIntervalSince1970: 1_756_900_000.123))
        XCTAssertNil(ClaudeLimits.parse(nil))
        XCTAssertNil(ClaudeLimits.parse("api"))
        let empty = ClaudeLimits.parse(["v": 1, "at": NSNull(), "plan": NSNull(), "fiveHour": NSNull(),
                                        "weekly": ["used": "77"], "fable": NSNull(), "source": NSNull()] as [String: Any])
        XCTAssertNotNil(empty)
        XCTAssertNil(empty?.weekly, "used строкой — лимита нет")
        XCTAssertFalse(StatusIcon.isFresh(empty, now: now))
    }
}
