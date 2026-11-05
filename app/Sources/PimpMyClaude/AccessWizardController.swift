import AppKit
import ApplicationServices
import ClaudeAX
import Patcher

/// Нажатия карточки-мастера доступов.
enum AccessWizardAction: Equatable { case open, back, next, later, dismiss, relaunch }

/// Мастер доступов (#10310, #10306): шаги из `AccessWizard`, снятие записи под старой подписью (`tccutil reset` —
/// «удалить и перенести заново» без кнопки «−»), плашка у окна Системных настроек с плитками PMP и Claude (как у
/// Gemini), опрос раз в 2 с, пока открыта панель или видна плашка: шаг сам ставит ✓ и мастер идёт дальше. Всё выдано —
/// «Готово ✓» на 3 с, карточка уходит.
///
/// «Позже» (`accessWizardLater`) прячет карточку до другого набора слетевшего — точка на значке остаётся: доступа у
/// Claude правда нет. Снятые записи (`accessWizardPending`) помнятся и после перезапуска PMP, пока доступ не выдан.
final class AccessWizardController {
    static let pendingKey = "accessWizardPending"
    static let laterKey = "accessWizardLater"
    static let dismissedKey = "accessHintDismissed"
    static let pollSeconds: TimeInterval = 2

    var isPanelOpen: () -> Bool = { false }
    /// Идёт патч или другая операция: плашка мастера не ложится поверх плашки «Управления приложениями».
    var isBusy: () -> Bool = { false }
    /// Последний патч упал — шаг подписи остаётся с «Ещё раз», а не пропускается.
    var patchFailed: () -> Bool = { false }
    /// «Сделать постоянной» — тот же путь, что «Пропатчить» в панели (`patchFromPanel`): Claude перезапустится.
    var sign: () -> Void = {}
    var relaunch: () -> Void = {}
    var publish: (AccessWizard.Snapshot) -> Void = { _ in }
    /// Новое состояние для значка и карточки — после опроса мастера (проверку раз в минуту ведёт `refreshState`).
    var onAccess: (ClaudeAccess.State) -> Void = { _ in }

    private let hint = PermissionHintController()
    private let defaults: UserDefaults
    private var need = AccessWizard.Need()
    private var facts: AccessWizard.Facts?
    /// Claude из последней проверки `refreshState` — его опрашиваем и его плитку тащим.
    private var appURL: URL?
    private(set) var snapshot = AccessWizard.Snapshot()
    private(set) var state = ClaudeAccess.State.ok
    private var timer: Timer?
    private var reading = false
    private var signing = false
    private var fullDiskAskedAt: Date?
    private var doneGeneration = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hint.onRelaunch = { [weak self] in self?.relaunch() }
    }

    /// Факты с диска: база TCC, «Универсальный доступ» PMP, подпись Claude. Не на главной нитке.
    static func read(appURL: URL, patched: Bool) -> AccessWizard.Facts {
        AccessWizard.Facts(grants: ClaudeAccess.grants(appURL: appURL, bundleID: Patcher.claudeBundleID),
                           pmpTrusted: AXIsProcessTrusted(), adhoc: SignIdentity.isAdhoc(appURL), patched: patched)
    }

    /// Новые факты о Claude `appURL` (главная нитка): мастер, плашка, карточка. Возвращает состояние для значка — с
    /// учётом снятых записей, иначе после `tccutil reset` значок и карточка решили бы, что всё хорошо.
    @discardableResult
    func update(_ fresh: AccessWizard.Facts, appURL: URL) -> ClaudeAccess.State {
        self.appURL = appURL
        var facts = fresh
        facts.pending = keepPending(granted: fresh.grants)
        self.facts = facts
        state = AccessWizard.effective(grants: facts.grants, pending: facts.pending)
        if signing && !isBusy() {
            signing = false
            if facts.adhoc == true && !patchFailed() { snapshot.signFailed = true }
        }
        if snapshot.phase != .done { recompute(facts) }
        publish(snapshot)
        return state
    }

    func perform(_ action: AccessWizardAction) {
        switch action {
        case .open:
            if let step = snapshot.current { open(step, auto: false) }
        case .back:
            move(by: -1)
        case .next:
            move(by: 1)
        case .later:
            defaults.set(AccessWizard.laterKey(state), forKey: Self.laterKey)
            hint.hide()
        case .dismiss:
            defaults.set(true, forKey: Self.dismissedKey)
            hint.hide()
        case .relaunch:
            relaunch()
        }
    }

    // MARK: расчёт

    private func recompute(_ facts: AccessWizard.Facts) {
        let previous = snapshot
        need = need.union(AccessWizard.need(facts))
        guard !need.isEmpty else { return finish() }
        var next = previous
        next.steps = AccessWizard.steps(need, facts, signFailed: previous.signFailed)
        next.adhoc = facts.adhoc
        next.grants = facts.grants ?? [:]
        next.pmpApp = Bundle.main.bundleURL
        next.claudeApp = appURL
        if facts.grants != nil { fullDiskAskedAt = nil }
        next.relaunchOffer = AccessWizard.offersRelaunch(askedAt: fullDiskAskedAt, now: Date(), known: facts.grants != nil)
        if AccessWizard.finished(next.steps) {
            next.phase = .done
            snapshot = next
            hint.hide()
            scheduleIdle()
            return
        }
        next.phase = .steps
        next.index = AccessWizard.index(after: previous, steps: next.steps)
        snapshot = next
        startTimer()
        followPlaque(previous: previous)
    }

    /// Плашка идёт за шагом: шаг сделан — сразу следующий лист (подпись сама не запускается); идёт патч — прячется.
    private func followPlaque(previous: AccessWizard.Snapshot) {
        guard hint.isShown, let current = snapshot.current else { return }
        if isBusy() || current.target == .sign { return hint.hide() }
        if current.target != previous.current?.target { open(current, auto: true) } else { hint.refresh(content(current)) }
    }

    private func finish() {
        need = AccessWizard.Need()
        snapshot = AccessWizard.Snapshot()
        fullDiskAskedAt = nil
        hint.hide()
        stopTimer()
        defaults.removeObject(forKey: Self.laterKey)
    }

    /// «Готово ✓» — 3 с, потом карточка уходит.
    private func scheduleIdle() {
        doneGeneration += 1
        let generation = doneGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + AccessWizard.doneSeconds) { [weak self] in
            guard let self = self, generation == self.doneGeneration, self.snapshot.phase == .done else { return }
            self.finish()
            self.defaults.removeObject(forKey: Self.pendingKey)
            self.publish(self.snapshot)
        }
    }

    private func move(by delta: Int) {
        let index = snapshot.index + delta
        guard snapshot.steps.indices.contains(index) else { return }
        snapshot.index = index
        publish(snapshot)
        if hint.isShown, let step = snapshot.current, step.target != .sign, step.status == .todo {
            open(step, auto: true)
        } else if hint.isShown {
            hint.hide()
        }
    }

    // MARK: шаг

    private func open(_ step: AccessWizard.Step, auto: Bool) {
        guard !isBusy() else { return }
        switch step.target {
        case .sign:
            guard !auto else { return }
            hint.hide()
            signing = true
            sign()
        case .pmpFullDisk:
            if fullDiskAskedAt == nil { fullDiskAskedAt = Date() }
            showPlaque(step)
        case .service(let service):
            guard AccessWizard.needsReset(facts?.grants?[service]), !snapshot.resetFailed.contains(service),
                  let url = appURL else { return showPlaque(step) }
            resetThenShow(service, step: step, appURL: url)
        }
    }

    /// Запись под старой подписью снимается до показа листа: список настроек читается при открытии. Снялась ли —
    /// по базе; осталась — шаг просит кнопку «−».
    private func resetThenShow(_ service: ClaudeAccess.Service, step: AccessWizard.Step, appURL: URL) {
        addPending(service)
        let patched = facts?.patched ?? true
        DispatchQueue.global(qos: .userInitiated).async {
            ClaudeAccess.reset(service, bundleID: Patcher.claudeBundleID)
            let after = Self.read(appURL: appURL, patched: patched)
            DispatchQueue.main.async {
                if let grant = after.grants?[service], grant != .absent { self.snapshot.resetFailed.insert(service) }
                self.onAccess(self.update(after, appURL: appURL))
                self.showPlaque(self.snapshot.current ?? step)
            }
        }
    }

    private func showPlaque(_ step: AccessWizard.Step) {
        guard let target = AccessWizard.settingsURL(step.target) else { return }
        hint.show(content(step), link: target.absoluteString, placement: .inside) {}
    }

    private func content(_ step: AccessWizard.Step) -> PermissionHintContent {
        var grant: ClaudeAccess.Grant?
        var resetFailed = false
        if case .service(let service) = step.target {
            grant = facts?.grants?[service]
            resetFailed = snapshot.resetFailed.contains(service)
        }
        let tiles = step.apps.compactMap { app -> PermissionHintContent.Tile? in
            let url = app == .pmp ? Bundle.main.bundleURL : appURL
            return url.map { PermissionHintContent.Tile(url: $0, title: AccessWizard.appName(app)) }
        }
        let relaunchLink = step.target == .pmpFullDisk && snapshot.relaunchOffer ? AccessWizard.relaunchLink : nil
        let lines = AccessWizard.plaqueLines(step, resetFailed: resetFailed)
        return PermissionHintContent(title: AccessWizard.plaqueTitle(step, grant: grant), gemini: true,
                                     note: lines.isEmpty ? nil : lines.joined(separator: "\n"), tiles: tiles,
                                     link: relaunchLink)
    }

    // MARK: опрос

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Раз в 2 с — только пока на мастер смотрят (панель открыта или плашка видна). Один опрос за раз.
    private func tick() {
        guard !reading, isPanelOpen() || hint.isShown, let url = appURL else { return }
        if isBusy() && hint.isShown { hint.hide() }
        reading = true
        let patched = facts?.patched ?? true
        DispatchQueue.global(qos: .utility).async {
            let fresh = Self.read(appURL: url, patched: patched)
            DispatchQueue.main.async {
                self.reading = false
                self.onAccess(self.update(fresh, appURL: url))
            }
        }
    }

    // MARK: снятые записи

    private func addPending(_ service: ClaudeAccess.Service) {
        var names = Set(defaults.stringArray(forKey: Self.pendingKey) ?? [])
        names.insert(service.rawValue)
        defaults.set(names.sorted(), forKey: Self.pendingKey)
    }

    /// Снятые записи, ещё не выданные заново; выданные забываются.
    private func keepPending(granted grants: [ClaudeAccess.Service: ClaudeAccess.Grant]?) -> Set<ClaudeAccess.Service> {
        let saved = Set((defaults.stringArray(forKey: Self.pendingKey) ?? []).compactMap(ClaudeAccess.Service.init(rawValue:)))
        guard let grants = grants else { return saved }
        let left = saved.filter { grants[$0] != .granted }
        if left != saved { defaults.set(left.map(\.rawValue).sorted(), forKey: Self.pendingKey) }
        return left
    }
}
