import Foundation
import Patcher

/// Мастер доступов в карточке панели (#10310, #10306; слова Элвиса 19.10: «Нужен мастер: открыть настройки и перетащить
/// туда иконки PMP и Claude, чик-чик… Какие доступы нужны — сразу все показать столбиком… Далее-далее-далее»; «Где PMP не
/// видит доступа Claude — там пусть появится удобный мастер… внутри этого прямоугольничка»).
///
/// Здесь только расчёт (тесты `AccessWizard10310Tests`): какие шаги, какой сделан, что писать. Окна, опрос раз в 2 с,
/// `tccutil` и плашку у Системных настроек ведёт `AccessWizardController` в таргете приложения.
///
/// Шаги по порядку: «0. Полный доступ к диску для PMP» (PMP не видит базу TCC), «Постоянная подпись Claude» (подпись
/// временная — иначе выданное слетит при следующем патче), потом «Универсальный доступ», «Запись экрана», «Полный доступ
/// к диску» — ровно те, что слетели у Claude, и «Универсальный доступ» самого PMP, если его нет.
public enum AccessWizard {
    public typealias Service = ClaudeAccess.Service
    public typealias Grant = ClaudeAccess.Grant

    /// Плитка для перетаскивания в список настроек.
    public enum App: Equatable { case pmp, claude }

    public enum Target: Equatable {
        case pmpFullDisk
        case sign
        case service(Service)
    }

    /// `skipped` — шаг не вышел и не держит мастер (постоянная подпись не встала).
    public enum Status: Equatable { case todo, done, skipped }

    public struct Step: Equatable {
        public let target: Target
        public let number: Int
        /// Чьи плитки тащить на этом шаге: только те, кому доступа ещё нет.
        public let apps: [App]
        public let status: Status
        public init(target: Target, number: Int, apps: [App], status: Status) {
            self.target = target
            self.number = number
            self.apps = apps
            self.status = status
        }
    }

    /// `done` — «Готово ✓» на 3 с, потом карточка уходит.
    public enum Phase: Equatable { case idle, steps, done }

    /// Что сейчас правда на диске.
    public struct Facts: Equatable {
        /// nil — базу TCC не прочитать (у PMP нет «Полного доступа к диску»).
        public var grants: [Service: Grant]?
        public var pmpTrusted: Bool
        /// Подпись Claude временная (ad-hoc); nil — не прочитать.
        public var adhoc: Bool?
        public var patched: Bool
        /// Записи, которые PMP снял `tccutil` и ждёт, что их выдадут заново (`accessWizardPending`).
        public var pending: Set<Service>
        public init(grants: [Service: Grant]?, pmpTrusted: Bool, adhoc: Bool?, patched: Bool, pending: Set<Service> = []) {
            self.grants = grants
            self.pmpTrusted = pmpTrusted
            self.adhoc = adhoc
            self.patched = patched
            self.pending = pending
        }
    }

    /// Что мастер покрывает за этот проход: растёт, пока мастер открыт, — сделанный шаг остаётся в столбике с ✓.
    public struct Need: Equatable {
        public var pmpFullDisk = false
        public var sign = false
        public var claude: Set<Service> = []
        public var pmpAccessibility = false
        public init(pmpFullDisk: Bool = false, sign: Bool = false, claude: Set<Service> = [], pmpAccessibility: Bool = false) {
            self.pmpFullDisk = pmpFullDisk
            self.sign = sign
            self.claude = claude
            self.pmpAccessibility = pmpAccessibility
        }

        public var isEmpty: Bool { !pmpFullDisk && !sign && claude.isEmpty && !pmpAccessibility }

        public func union(_ other: Need) -> Need {
            Need(pmpFullDisk: pmpFullDisk || other.pmpFullDisk, sign: sign || other.sign, claude: claude.union(other.claude),
                 pmpAccessibility: pmpAccessibility || other.pmpAccessibility)
        }
    }

    /// Что видит панель.
    public struct Snapshot: Equatable {
        public var phase = Phase.idle
        public var steps: [Step] = []
        public var index = 0
        /// `tccutil reset` не снял запись — шаг просит убрать Claude кнопкой «−».
        public var resetFailed: Set<Service> = []
        public var signFailed = false
        /// PMP получил «Полный доступ к диску», а базу всё не видит — macOS даёт его только после перезапуска.
        public var relaunchOffer = false
        public var adhoc: Bool?
        /// Доступы Claude из последней проверки — для текста шага (выключен или записан под старой подписью).
        public var grants: [Service: Grant] = [:]
        public var pmpApp: URL?
        public var claudeApp: URL?
        public init() {}

        public var current: Step? { steps.indices.contains(index) ? steps[index] : nil }
    }

    /// Порядок доступов Claude в столбике (ТЗ: «1. Универсальный доступ», «2. Запись экрана», «3. Полный доступ к диску»).
    public static let order: [Service] = [.accessibility, .screen, .fullDisk]

    /// Шаг 0 не закрылся за столько — предлагаем перезапустить PMP.
    public static let relaunchAfter: TimeInterval = 10
    /// «Готово ✓» видно столько.
    public static let doneSeconds: TimeInterval = 3

    // MARK: расчёт

    /// Состояние для значка и карточки. Запись, снятую `tccutil` (`pending`), база показывает как «нет записи», а
    /// `ClaudeAccess.evaluate` такое считает за «ок» — без этого точка на значке и карточка пропали бы посреди мастера.
    public static func effective(grants: [Service: Grant]?, pending: Set<Service>) -> ClaudeAccess.State {
        guard let grants = grants else { return .unknown }
        let missing = Service.allCases.filter { lost($0, grants: grants, pending: pending) }
        return missing.isEmpty ? .ok : .missing(missing)
    }

    static func lost(_ service: Service, grants: [Service: Grant], pending: Set<Service>) -> Bool {
        let grant = grants[service] ?? .absent
        return grant == .off || grant == .stale || (pending.contains(service) && grant != .granted)
    }

    /// Что нужно сейчас. PMP не видит базу — только шаг 0. У Claude всё есть — мастера нет: «Универсальный доступ»
    /// самого PMP без слетевшего у Claude — дело окна разрешений (`SetupWindow`), не карточки.
    public static func need(_ facts: Facts) -> Need {
        guard let grants = facts.grants else { return Need(pmpFullDisk: true) }
        let claude = Set(order.filter { lost($0, grants: grants, pending: facts.pending) })
        guard !claude.isEmpty else { return Need() }
        return Need(sign: facts.patched && facts.adhoc == true, claude: claude, pmpAccessibility: !facts.pmpTrusted)
    }

    /// Столбик шагов: одна программа — одна плитка; сделанный — ✓.
    public static func steps(_ need: Need, _ facts: Facts, signFailed: Bool) -> [Step] {
        var out: [Step] = []
        if need.pmpFullDisk {
            out.append(Step(target: .pmpFullDisk, number: 0, apps: [.pmp], status: facts.grants != nil ? .done : .todo))
        }
        var number = 1
        if need.sign {
            let status: Status = facts.adhoc == false ? .done : signFailed ? .skipped : .todo
            out.append(Step(target: .sign, number: number, apps: [], status: status))
            number += 1
        }
        for service in order where need.claude.contains(service) || (service == .accessibility && need.pmpAccessibility) {
            var apps: [App] = []
            if service == .accessibility && need.pmpAccessibility && !facts.pmpTrusted { apps.append(.pmp) }
            if need.claude.contains(service) && facts.grants?[service] != .granted { apps.append(.claude) }
            out.append(Step(target: .service(service), number: number, apps: apps, status: apps.isEmpty ? .done : .todo))
            number += 1
        }
        return out
    }

    public static func finished(_ steps: [Step]) -> Bool {
        !steps.isEmpty && steps.allSatisfy { $0.status != .todo }
    }

    /// Текущий шаг после пересчёта: стоял на шаге и тот только что сделан — к первому несделанному; листали «Назад» на
    /// сделанный — остаёмся там же; мастер только открылся — первый несделанный.
    public static func index(after previous: Snapshot, steps: [Step]) -> Int {
        let first = steps.firstIndex { $0.status == .todo } ?? 0
        guard let was = previous.current, let now = steps.firstIndex(where: { $0.target == was.target }) else { return first }
        return was.status == .todo && steps[now].status != .todo ? first : now
    }

    /// Снимать запись перед шагом — только когда она записана под старой подписью: выключенную включают выключателем.
    public static func needsReset(_ grant: Grant?) -> Bool { grant == .stale }

    /// Шаг 0 открыли, а база так и не читается — предложить перезапуск PMP.
    public static func offersRelaunch(askedAt: Date?, now: Date, known: Bool) -> Bool {
        guard let askedAt = askedAt, !known else { return false }
        return now.timeIntervalSince(askedAt) >= relaunchAfter
    }

    /// Ключ «Позже»: набор слетевшего (вместе с `pending` — иначе после сброса «Позже» → новый набор → карточка снова).
    public static func laterKey(_ state: ClaudeAccess.State) -> String {
        switch state {
        case .unknown: return "unknown"
        case .ok: return "ok"
        case .missing(let services): return "missing:" + services.map(\.tccName).sorted().joined(separator: ",")
        }
    }

    /// Карточка видна: идёт мастер (не спрятан «Позже» для этого же набора; шаг 0 — не «Не надо») или «Готово ✓».
    public static func cardVisible(state: ClaudeAccess.State, phase: Phase, dismissed: Bool, later: String?) -> Bool {
        switch phase {
        case .idle: return false
        case .done: return true
        case .steps: return state == .unknown ? !dismissed : later != laterKey(state)
        }
    }

    /// Лист Системных настроек шага; у подписи листа нет.
    public static func settingsURL(_ target: Target) -> URL? {
        switch target {
        case .pmpFullDisk: return Service.fullDisk.settingsURL
        case .sign: return nil
        case .service(let service): return service.settingsURL
        }
    }

    // MARK: тексты (слово «PMP», не «Пимп»)

    public static let fullDiskTitle = "Нужен полный доступ"
    public static let title = "Нужно дать доступы"
    public static let doneTitle = "Готово ✓"
    public static let doneText = "Все доступы на месте. Claude может попросить перезапуск — соглашайся."
    /// #10306 дословно: зачем PMP «Полный доступ к диску».
    public static let fullDiskWhy = "PMP только читает список доступов macOS, чтобы заметить, когда у Claude слетят "
        + "„Универсальный доступ“ и „Запись экрана“ после обновления. Файлы не читает и никуда не шлёт."
    public static let signWhy = "Подпись Claude сейчас временная: после каждого патча и обновления доступы слетают. "
        + "С постоянной их хватит одного раза. Claude закроется и откроется снова."
    public static let signFailedText = "Постоянная подпись не вышла — дальше по шагам, но после обновления Claude доступы "
        + "придётся дать снова."
    /// ТЗ: тихая строка, когда подпись осталась временной.
    public static let adhocLine = "Подпись временная — доступы слетят после обновления"
    public static let relaunchLink = "Включил, а PMP не видит — перезапустить PMP"
    /// Слово 03.11.2026: «название одинаковое… человек при обновлении опять разрешение просто даст, он затупит». После
    /// смены подписи старая строка остаётся с тем же именем: переключатель стоит, а прав нет.
    public static let staleRowHint = "Переключатель уже включён, а доступа всё равно нет? Это старая запись от прошлой "
        + "версии. Выдели строку, нажми «−», потом «+» и добавь программу заново."
    public static let later = "Позже"
    public static let dismiss = "Не надо"
    public static var passwordLine: String { SignIdentity.passwordLine }

    public static func cardTitle(_ snapshot: Snapshot) -> String {
        if snapshot.phase == .done { return doneTitle }
        return snapshot.steps.map(\.target) == [.pmpFullDisk] ? fullDiskTitle : title
    }

    public static func stepTitle(_ target: Target) -> String {
        switch target {
        case .pmpFullDisk: return "Полный доступ к диску для PMP"
        case .sign: return "Постоянная подпись Claude"
        case .service(let service): return service.title
        }
    }

    public static func openTitle(_ target: Target) -> String {
        switch target {
        case .pmpFullDisk: return "Дать полный доступ"
        case .sign: return "Сделать постоянной"
        case .service: return "Открыть"
        }
    }

    public static func appName(_ app: App) -> String { app == .pmp ? "PMP" : "Claude" }

    /// Что сделать на шаге — одной фразой под столбиком.
    public static func hint(_ step: Step, grant: Grant?, resetFailed: Bool) -> String {
        switch step.target {
        case .pmpFullDisk: return fullDiskWhy
        case .sign: return signWhy
        case .service(let service):
            if step.status != .todo { return "\(service.title) — готово." }
            if resetFailed { return "Убери Claude из списка кнопкой «−» и перетащи заново." }
            if grant == .off && step.apps == [.claude] { return "Включи переключатель у Claude в списке «\(service.title)»." }
            let who = step.apps.map(appName).joined(separator: " и ")
            return "Открой «\(service.title)» и перетащи \(who) в список."
        }
    }

    /// Заголовок плашки у окна настроек (как у Gemini: «Перетащите приложение…»).
    public static func plaqueTitle(_ step: Step, grant: Grant?) -> String {
        switch step.target {
        case .pmpFullDisk: return "Включи PimpMyClaude в списке (или перетащи его сюда)"
        case .sign: return stepTitle(.sign)
        case .service:
            if grant == .off && step.apps == [.claude] { return "Включи Claude в списке" }
            return "Перетащи " + step.apps.map(appName).joined(separator: " и ") + " в список"
        }
    }

    /// Строки плашки под заголовком.
    public static func plaqueLines(_ step: Step, resetFailed: Bool) -> [String] {
        guard case .service = step.target else { return [] }
        var lines: [String] = []
        if resetFailed { lines.append("Сначала убери старую запись Claude кнопкой «−».") }
        lines.append("Не берёт — нажми «+» под списком и выбери в «Программах».")
        return lines
    }
}
