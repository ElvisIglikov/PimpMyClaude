import XCTest
@testable import ClaudeAX

/// #10310 (+ #10306): мастер доступов в карточке панели — состав шагов, ✓, снятые записи, «Позже», тексты.
final class AccessWizard10310Tests: XCTestCase {
    private typealias Grant = ClaudeAccess.Grant
    private let current = Data([1]), old = Data([2])

    private func facts(_ grants: [ClaudeAccess.Service: Grant]?, trusted: Bool = true, adhoc: Bool? = false,
                       pending: Set<ClaudeAccess.Service> = []) -> AccessWizard.Facts {
        AccessWizard.Facts(grants: grants, pmpTrusted: trusted, adhoc: adhoc, patched: true, pending: pending)
    }

    // MARK: доступы

    func testGrantsFourCases() {
        let records = [ClaudeAccess.Record(service: .accessibility, allowed: true, csreq: current),
                       ClaudeAccess.Record(service: .screen, allowed: false, csreq: current),
                       ClaudeAccess.Record(service: .fullDisk, allowed: true, csreq: old)]
        let grants = ClaudeAccess.grants(records) { $0 == self.current }
        XCTAssertEqual(grants[.accessibility], .granted)
        XCTAssertEqual(grants[.screen], .off, "подпись та же, выключатель выключен")
        XCTAssertEqual(grants[.fullDisk], .stale, "выключатель горит, а требование к подписи старое")
        XCTAssertEqual(ClaudeAccess.grants([]) { _ in true }[.screen], .absent)
        let staleOff = [ClaudeAccess.Record(service: .screen, allowed: false, csreq: old)]
        XCTAssertEqual(ClaudeAccess.grants(staleOff) { $0 == self.current }[.screen], .stale, "старая подпись важнее выключателя")
        XCTAssertEqual(ClaudeAccess.state(of: grants), .missing([.fullDisk, .screen]))
    }

    func testTccNames() {
        XCTAssertEqual(ClaudeAccess.Service.accessibility.tccName, "Accessibility")
        XCTAssertEqual(ClaudeAccess.Service.screen.tccName, "ScreenCapture")
        XCTAssertEqual(ClaudeAccess.Service.fullDisk.tccName, "SystemPolicyAllFiles")
    }

    // MARK: шаги

    func testUnknownIsStepZeroOnly() {
        let unknown = facts(nil, trusted: false)
        let need = AccessWizard.need(unknown)
        XCTAssertEqual(need, AccessWizard.Need(pmpFullDisk: true), "«Универсальный доступ» PMP — дело окна разрешений")
        let steps = AccessWizard.steps(need, unknown, signFailed: false)
        XCTAssertEqual(steps, [AccessWizard.Step(target: .pmpFullDisk, number: 0, apps: [.pmp], status: .todo)])
        var snapshot = AccessWizard.Snapshot()
        snapshot.steps = steps
        XCTAssertEqual(AccessWizard.cardTitle(snapshot), "Нужен полный доступ")
        XCTAssertEqual(AccessWizard.openTitle(.pmpFullDisk), "Дать полный доступ")
        XCTAssertEqual(AccessWizard.effective(grants: nil, pending: []), .unknown)
    }

    func testOrderSignFirstAndTiles() {
        let now = facts([.accessibility: .stale, .screen: .off, .fullDisk: .granted], trusted: false, adhoc: true)
        let need = AccessWizard.need(now)
        XCTAssertTrue(need.sign, "подпись временная — сперва сделать постоянной, иначе выданное слетит")
        let steps = AccessWizard.steps(need, now, signFailed: false)
        XCTAssertEqual(steps.map(\.target), [.sign, .service(.accessibility), .service(.screen)])
        XCTAssertEqual(steps.map(\.number), [1, 2, 3])
        XCTAssertEqual(steps[1].apps, [.pmp, .claude], "Универсальный доступ нужен обоим — две плитки")
        XCTAssertEqual(steps[2].apps, [.claude], "одна программа — одна плитка")
        let trusted = facts([.accessibility: .stale, .screen: .off, .fullDisk: .granted], trusted: true, adhoc: false)
        let plain = AccessWizard.steps(AccessWizard.need(trusted), trusted, signFailed: false)
        XCTAssertEqual(plain.map(\.target), [.service(.accessibility), .service(.screen)], "подпись постоянная — шага нет")
        XCTAssertEqual(plain.map(\.number), [1, 2])
        XCTAssertEqual(plain[0].apps, [.claude])
    }

    func testFullDiskIsLastOfClaudeSteps() {
        let now = facts([.accessibility: .stale, .screen: .stale, .fullDisk: .stale])
        XCTAssertEqual(AccessWizard.steps(AccessWizard.need(now), now, signFailed: false).map(\.target),
                       [.service(.accessibility), .service(.screen), .service(.fullDisk)])
    }

    func testNoCardWhenClaudeIsFine() {
        let now = facts([.accessibility: .granted, .screen: .absent, .fullDisk: .granted], trusted: false, adhoc: true)
        XCTAssertTrue(AccessWizard.need(now).isEmpty, "доступы у Claude есть — мастера нет, даже без доступа у PMP")
        XCTAssertFalse(AccessWizard.cardVisible(state: .ok, phase: .idle, dismissed: false, later: nil))
    }

    func testPendingIsNotDoneUntilGranted() {
        // После `tccutil reset` строки нет — evaluate считал бы это за «ок».
        let reset = facts([.accessibility: .absent, .screen: .granted, .fullDisk: .granted], pending: [.accessibility])
        XCTAssertEqual(ClaudeAccess.state(of: reset.grants ?? [:]), .ok)
        XCTAssertEqual(AccessWizard.effective(grants: reset.grants, pending: reset.pending), .missing([.accessibility]))
        let need = AccessWizard.need(reset)
        let steps = AccessWizard.steps(need, reset, signFailed: false)
        XCTAssertEqual(steps.map(\.status), [.todo])
        XCTAssertFalse(AccessWizard.finished(steps))

        let granted = facts([.accessibility: .granted, .screen: .granted, .fullDisk: .granted], pending: [.accessibility])
        let after = AccessWizard.steps(need, granted, signFailed: false)
        XCTAssertEqual(after.map(\.status), [.done], "выдали — ✓")
        XCTAssertTrue(AccessWizard.finished(after))
        XCTAssertEqual(AccessWizard.effective(grants: granted.grants, pending: granted.pending), .ok)
    }

    func testNeedGrowsAndDoneStepsStay() {
        let first = facts([.accessibility: .stale, .screen: .granted, .fullDisk: .absent])
        var need = AccessWizard.need(first)
        // Шаг сделан, а другой слетел: столбик растёт, сделанный остаётся с ✓.
        let second = facts([.accessibility: .granted, .screen: .stale, .fullDisk: .absent])
        need = need.union(AccessWizard.need(second))
        let steps = AccessWizard.steps(need, second, signFailed: false)
        XCTAssertEqual(steps.map(\.target), [.service(.accessibility), .service(.screen)])
        XCTAssertEqual(steps.map(\.status), [.done, .todo])
    }

    func testSignStepStatus() {
        let need = AccessWizard.Need(sign: true, claude: [.screen])
        let adhoc = facts([.screen: .stale], adhoc: true)
        XCTAssertEqual(AccessWizard.steps(need, adhoc, signFailed: false).first?.status, .todo)
        XCTAssertEqual(AccessWizard.steps(need, adhoc, signFailed: true).first?.status, .skipped)
        XCTAssertEqual(AccessWizard.steps(need, facts([.screen: .stale], adhoc: false), signFailed: false).first?.status, .done)
        let done = facts([.screen: .granted], adhoc: true)
        XCTAssertTrue(AccessWizard.finished(AccessWizard.steps(need, done, signFailed: true)),
                      "подпись не вышла — мастер её не ждёт")
    }

    func testNeedsResetOnlyForStale() {
        XCTAssertTrue(AccessWizard.needsReset(.stale))
        for grant in [Grant.granted, .off, .absent] { XCTAssertFalse(AccessWizard.needsReset(grant)) }
        XCTAssertFalse(AccessWizard.needsReset(nil))
    }

    func testIndexFollowsDoneStep() {
        let todo = AccessWizard.Step(target: .service(.accessibility), number: 1, apps: [.claude], status: .todo)
        let done = AccessWizard.Step(target: .service(.accessibility), number: 1, apps: [], status: .done)
        let screen = AccessWizard.Step(target: .service(.screen), number: 2, apps: [.claude], status: .todo)
        var previous = AccessWizard.Snapshot()
        XCTAssertEqual(AccessWizard.index(after: previous, steps: [done, screen]), 1, "открылся — первый несделанный")
        previous.steps = [todo, screen]
        previous.index = 0
        XCTAssertEqual(AccessWizard.index(after: previous, steps: [done, screen]), 1, "шаг сделан — дальше сам")
        previous.steps = [done, screen]
        XCTAssertEqual(AccessWizard.index(after: previous, steps: [done, screen]), 0, "листали «Назад» — стоим")
    }

    // MARK: карточка

    func testCardVisibility() {
        let missing = ClaudeAccess.State.missing([.accessibility, .screen])
        XCTAssertTrue(AccessWizard.cardVisible(state: missing, phase: .steps, dismissed: true, later: nil))
        XCTAssertFalse(AccessWizard.cardVisible(state: missing, phase: .steps, dismissed: false,
                                                later: AccessWizard.laterKey(missing)), "«Позже» для этого набора")
        XCTAssertTrue(AccessWizard.cardVisible(state: .missing([.accessibility]), phase: .steps, dismissed: false,
                                               later: AccessWizard.laterKey(missing)), "слетело другое — снова видна")
        XCTAssertFalse(AccessWizard.cardVisible(state: .unknown, phase: .steps, dismissed: true, later: nil), "«Не надо»")
        XCTAssertTrue(AccessWizard.cardVisible(state: .unknown, phase: .steps, dismissed: false, later: nil))
        XCTAssertTrue(AccessWizard.cardVisible(state: .ok, phase: .done, dismissed: false, later: nil),
                      "«Готово ✓» видно, хотя всё уже «ок»")
        XCTAssertEqual(AccessWizard.laterKey(missing), AccessWizard.laterKey(.missing([.screen, .accessibility])))
    }

    func testRelaunchOfferAfterTenSeconds() {
        let asked = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(AccessWizard.offersRelaunch(askedAt: asked, now: asked.addingTimeInterval(5), known: false))
        XCTAssertTrue(AccessWizard.offersRelaunch(askedAt: asked, now: asked.addingTimeInterval(10), known: false))
        XCTAssertFalse(AccessWizard.offersRelaunch(askedAt: asked, now: asked.addingTimeInterval(30), known: true))
        XCTAssertFalse(AccessWizard.offersRelaunch(askedAt: nil, now: asked, known: false))
    }

    // MARK: тексты

    func testTextsSayPMP() {
        XCTAssertTrue(AccessWizard.fullDiskWhy.hasPrefix("PMP только читает список доступов macOS"), "текст #10306")
        var texts = [AccessWizard.title, AccessWizard.fullDiskTitle, AccessWizard.doneTitle, AccessWizard.doneText,
                     AccessWizard.fullDiskWhy, AccessWizard.signWhy, AccessWizard.signFailedText, AccessWizard.adhocLine,
                     AccessWizard.relaunchLink, AccessWizard.later, AccessWizard.dismiss, AccessWizard.passwordLine]
        let targets: [AccessWizard.Target] = [.pmpFullDisk, .sign, .service(.accessibility), .service(.screen),
                                              .service(.fullDisk)]
        for target in targets {
            texts += [AccessWizard.stepTitle(target), AccessWizard.openTitle(target)]
            for apps in [[AccessWizard.App.pmp, .claude], [.claude], [.pmp]] {
                let step = AccessWizard.Step(target: target, number: 1, apps: apps, status: .todo)
                for grant in [Grant.off, .stale, nil] {
                    texts.append(AccessWizard.hint(step, grant: grant, resetFailed: false))
                    texts.append(AccessWizard.plaqueTitle(step, grant: grant))
                }
                texts.append(AccessWizard.hint(step, grant: .stale, resetFailed: true))
                texts += AccessWizard.plaqueLines(step, resetFailed: true)
            }
        }
        for text in texts { XCTAssertFalse(text.contains("Пимп"), text) }
        let both = AccessWizard.Step(target: .service(.accessibility), number: 1, apps: [.pmp, .claude], status: .todo)
        XCTAssertEqual(AccessWizard.plaqueTitle(both, grant: .stale), "Перетащи PMP и Claude в список")
        XCTAssertTrue(AccessWizard.hint(both, grant: .stale, resetFailed: true).contains("кнопкой «−»"))
    }
}
