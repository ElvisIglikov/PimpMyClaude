import AppKit
import Patcher

/// Автообновление Пимпа и PimpViewer (WF217, #9410, контракт К-SU): КОГДА проверять и КОГДА ставить.
/// Что и чем проверяется перед установкой и сама подмена — `Patcher/SelfUpdater`.
/// Проверка: на запуске Пимпа и Claude (не чаще раза в 15 мин) и фоном не чаще раза в 6 часов.
/// Установка: Пимп — на своём запуске (до интерфейса) и после запуска Claude, как только момент тихий (канал
/// «Пимп» свободен, окна вернулись), но не позже 5 минут; Viewer — в любой тихий момент, пока он не запущен.
/// Выключатель выключен — ни сети, ни установки; выключили посреди круга — он кончается перед следующим шагом.
/// Живёт на главной очереди; сеть, распаковка и подмена — на своей.
final class SelfUpdateDriver {
    /// Переключатель «Обновлять Пимп и Viewer самим» (UserDefaults, Bool); нет ключа — включено.
    static let enabledKey = "selfUpdateEnabled"
    /// Claude запустился, а очередь была занята загрузкой дольше этого — момент ушёл, Пимп не перезапускаем.
    static let momentSeconds: TimeInterval = 30
    /// Claude запустился, а момент занят (возврат окон, канал «Пимп», панель — находка R2 проверки 10.10.2026):
    /// подмену Пимпа не теряем, а переспрашиваем момент раз в `retryEvery`, пока от запуска не прошло `retrySeconds`.
    var retrySeconds: TimeInterval = 5 * 60
    var retryEvery: TimeInterval = 3
    /// Запуск Пимпа — главная нитка, значка у часов ещё нет (находка R3 проверки 10.10.2026): каждый шаг проверки
    /// скачанного ждём не дольше этого; не уложился — запуск идёт как обычно, скачанное ждёт следующего момента.
    var launchPatience: TimeInterval = 10

    /// Что показывает группа «Обновления» и строка панели.
    struct Look: Equatable {
        var on = true
        var line = ""
        var note: String?
    }

    private let updater: SelfUpdater
    private let defaults: UserDefaults
    private let pimpApp: URL
    private let viewerApp: () -> URL?
    private let queue = DispatchQueue(label: "pimp.self-update", qos: .utility)
    private var checking = false
    /// Когда продукт последний раз спрашивали — в памяти: папка `self-update/` не пишется (диск полон) — в файле
    /// попытки нет, и без этого запрос уходил бы каждую минуту (находка R4 проверки 10.10.2026).
    private var attempted: [String: Date] = [:]
    /// Пимп подменил себя и выходит (читается и пишется только на своей очереди): что стояло в очереди следом —
    /// не начинается, чтобы выход не застал подмену Viewer на полпути.
    private var leaving = false
    /// С какого запуска Claude скачанный Пимп ждёт тихого момента; nil — не ждёт.
    private var pimpWaitsSince: Date?
    /// Что сейчас на Маке: панель, запись, патч, Viewer, канал и окна — спрашиваем у приложения в момент подмены
    /// (`enabled` водитель подставляет сам).
    var moment: () -> SelfUpdateMoment = { SelfUpdateMoment() }
    /// Сеть есть и не дорогая.
    var networkOK: () -> Bool = { true }
    /// Состояние поменялось — панели пора перечитать `look()`.
    var onChange: () -> Void = {}
    /// Пимп подменил себя: помощник ждёт выхода и откроет новую версию.
    var relaunch: (URL) -> Void = { app in
        if !SelfUpdater.relaunch(app) { _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-n", app.path]) }
    }
    var quit: () -> Void = { NSApp.terminate(nil) }
    /// Других запущенных копий Пимпа нет: при второй копии подменять бандл нельзя — первая осталась бы жить
    /// из папки отката, а помощник открыл бы её же.
    var alone: () -> Bool = {
        NSRunningApplication.runningApplications(withBundleIdentifier: SelfUpdateProduct.pimp.bundleID)
            .allSatisfy { $0.processIdentifier == getpid() }
    }

    init(updater: SelfUpdater = SelfUpdater(), defaults: UserDefaults = .standard,
         pimpApp: URL = Bundle.main.bundleURL, viewerApp: @escaping () -> URL? = SelfUpdateDriver.installedViewer) {
        self.updater = updater
        self.defaults = defaults
        self.pimpApp = pimpApp
        self.viewerApp = viewerApp
    }

    /// PimpViewer в «Программах» (общих или своих); в других местах его не обновляем.
    static func installedViewer() -> URL? {
        SelfUpdater.standardParents.map { $0.appendingPathComponent(SelfUpdateProduct.viewer.appName, isDirectory: true) }
            .first { SelfUpdater.installedVersion($0, bundleID: SelfUpdateProduct.viewer.bundleID) != nil }
    }

    var enabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    func setEnabled(_ on: Bool) {
        defaults.set(on, forKey: Self.enabledKey)
        onChange()
        if on { check(interval: SelfUpdater.launchInterval) }
    }

    private func app(_ product: SelfUpdateProduct) -> URL? { product == .viewer ? viewerApp() : pimpApp }

    // MARK: - когда ставить

    /// Запуск Пимпа, интерфейс ещё не поднят: скачанное и проверенное лежит — подменить себя.
    /// true — подменили и запустили помощника: вызывающий сразу выходит.
    func installAtLaunch() -> Bool {
        var quick = updater
        quick.patience = launchPatience
        guard enabled, alone(), (try? quick.install(.pimp, app: pimpApp)) != nil else { return false }
        relaunch(pimpApp)
        return true
    }

    /// Пимп поднялся: Viewer — если не запущен, и вопрос про новое.
    func started() {
        installIfQuiet(.viewer)
        check(interval: SelfUpdater.launchInterval)
    }

    /// Claude только что запустился — человек не посреди работы: ставим скачанное и спрашиваем про новое.
    func claudeLaunched() {
        installIfQuiet(.viewer)
        // Скачанное есть — ждём тихого момента; нечего ставить или выключено — и ждать нечего.
        let ready = enabled && updater.loadState().products[SelfUpdateProduct.pimp.key]?.ready != nil
        pimpWaitsSince = ready ? Date() : nil
        installWaitingPimp()
        check(interval: SelfUpdater.launchInterval)
    }

    /// Скачанный Пимп после запуска Claude: момент тихий — ставим, занят — переспросим через `retryEvery`.
    private func installWaitingPimp() {
        guard let since = pimpWaitsSince else { return }
        guard Date().timeIntervalSince(since) <= retrySeconds else { pimpWaitsSince = nil; return }
        guard quiet(.pimp) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + retryEvery) { [weak self] in
                if self?.pimpWaitsSince == since { self?.installWaitingPimp() } // новый запуск Claude ведёт свой отсчёт
            }
            return
        }
        pimpWaitsSince = nil
        installIfQuiet(.pimp, within: Self.momentSeconds)
    }

    /// Viewer закрыли — отложенное обновление можно ставить.
    func viewerQuit() { installIfQuiet(.viewer) }

    /// Тихий ли момент для подмены; выключатель сильнее всего, что скажет приложение.
    private func quiet(_ product: SelfUpdateProduct) -> Bool {
        var now = moment()
        now.enabled = enabled
        return SelfUpdater.mayInstall(product, now)
    }

    private func installIfQuiet(_ product: SelfUpdateProduct, within seconds: TimeInterval? = nil) {
        guard let app = app(product), updater.loadState().products[product.key]?.ready != nil,
              quiet(product), product == .viewer || alone() else { return }
        let asked = Date()
        queue.async { [updater] in
            if self.leaving { return }
            if let seconds = seconds, Date().timeIntervalSince(asked) > seconds { return }
            // Прямо перед подменой — ещё раз: за время распаковки и проверки панель могли открыть.
            let note = try? updater.install(product, app: app, confirm: {
                DispatchQueue.main.sync { self.quiet(product) }
            })
            guard note != nil else { return }
            if product == .pimp { self.leaving = true }
            DispatchQueue.main.async {
                guard product == .pimp else { return self.onChange() }
                self.relaunch(app)
                self.quit()
            }
        }
    }

    // MARK: - когда проверять

    /// Раз в минуту из общего таймера приложения: фоновая проверка — не чаще раза в 6 часов.
    func tick() { check(interval: SelfUpdater.checkInterval) }

    func check(interval: TimeInterval) {
        guard enabled, !checking, networkOK() else { return }
        let state = updater.loadState()
        let now = Date()
        let due = [SelfUpdateProduct.pimp, .viewer].compactMap { product -> (product: SelfUpdateProduct, app: URL)? in
            // Пауза — от более поздней из двух попыток: записанной в файл и своей, в памяти (R4).
            var mine = SelfUpdateState.Product()
            mine.attemptedAt = attempted[product.key]
            guard let app = app(product),
                  SelfUpdater.shouldCheck(state.products[product.key], now: now, interval: interval),
                  SelfUpdater.shouldCheck(mine, now: now, interval: interval) else { return nil }
            return (product, app)
        }
        guard !due.isEmpty else { return }
        checking = true
        for target in due { attempted[target.product.key] = now }
        queue.async { [updater] in
            // Выключатель читается перед каждым продуктом и перед каждым шагом круга (находка R8 проверки
            // 10.10.2026): выключили посреди проверки — дальше в сеть ничего не уходит.
            for target in due where !self.leaving && self.enabled {
                updater.check(target.product, app: target.app, proceed: { self.enabled })
            }
            DispatchQueue.main.async {
                self.checking = false
                self.onChange()
                self.installIfQuiet(.viewer) // не запущен — встаёт сразу, никому не мешает
            }
        }
    }

    // MARK: - панель

    func look(now: Date = Date()) -> Look {
        let state = updater.loadState()
        let on = enabled
        let pimp = SelfUpdateProduct.pimp, viewer = SelfUpdateProduct.viewer
        var line = SelfUpdater.statusLine(installed: SelfUpdater.installedVersion(pimpApp, bundleID: pimp.bundleID) ?? "—",
                                          state: state.products[pimp.key], enabled: on,
                                          place: updater.placeProblem(pimpApp, product: pimp), now: now)
        if on, let app = viewerApp(),
           let tail = SelfUpdater.viewerLine(installed: SelfUpdater.installedVersion(app, bundleID: viewer.bundleID),
                                             state: state.products[viewer.key]) {
            line += " · " + tail
        }
        return Look(on: on, line: line, note: SelfUpdater.noteLine(state.notes))
    }

    /// Строку «обновился» панель показала — больше не показываем.
    func clearNotes() { queue.async { [updater] in updater.clearNotes() } }
}
