import Foundation

/// Обновление Claude глазами меню (#7078, #7079; WF86 — план WF87 батч A п. 3): чистая машина
/// состояний `idle → checking → available(v) → downloading(гонка) → ready(v) → installing → idle/failed`.
/// Проверка — раз в сутки в фоне (ошибка — повтор через час), раз в 10 минут при открытии меню;
/// все пути идут через один gate, ручной запрос обходит интервал. Качает и ставит `ClaudeUpdater`
/// (таргет `Patcher`); здесь только состояние и тексты — их и гоняют тесты. Входы провязывает
/// `AppDelegate`, показывает панель у часов (`PimpPanelText.updateBlock`).
public struct ClaudeUpdateMenu: Equatable {
    public static let checkInterval: TimeInterval = 600
    public static let dailyInterval: TimeInterval = 24 * 60 * 60
    /// Суточная проверка сорвалась (нет сети, сон) — повтор через час, а не через сутки.
    public static let retryInterval: TimeInterval = 60 * 60
    /// Когда следующая суточная проверка (UserDefaults, Date).
    public static let nextDailyKey = "claudeUpdateNextDaily"
    /// Выключатель фоновой загрузки (UserDefaults, Bool): чистая установка — выкл., существующий выбор сохраняется.
    public static let autoDownloadKey = "claudeAutoDownload"
    /// Про какую готовую версию уже было уведомление (UserDefaults, String) — одно на версию.
    public static let notifiedKey = "claudeUpdateNotifiedVersion"
    public enum Trigger { case menu, daily, manual }
    public static let confirmButton = "Обновить"
    public static let laterButton = "Позже"

    /// Ответ последней проверки.
    public enum Known: Equatable {
        case unknown
        /// Ответили все источники, новее нет.
        case latest(installed: String)
        case available(version: String)
        /// Не узнал (источник молчит) — это не «последняя».
        case failed(String)
    }

    /// Полоса гонки — зеркало `RaceLane` из `Patcher` (ClaudeAX от него не зависит).
    public enum LaneState: Equatable {
        case running, leading, dropped(String), failed(String), won
    }

    public struct Lane: Equatable {
        public let id: String
        public let title: String
        public let bytes: Int64
        public let total: Int64?
        public let bytesPerSec: Double
        public let state: LaneState

        public init(id: String, title: String, bytes: Int64, total: Int64?, bytesPerSec: Double, state: LaneState) {
            self.id = id
            self.title = title
            self.bytes = bytes
            self.total = total
            self.bytesPerSec = bytesPerSec
            self.state = state
        }
    }

    /// Снимок гонки для меню и панели.
    public struct Race: Equatable {
        public let version: String
        public let lanes: [Lane]

        public init(version: String, lanes: [Lane]) {
            self.version = version
            self.lanes = lanes
        }

        /// Доля лучшей живой полосы, 0…1.
        public var fraction: Double {
            lanes.compactMap { lane -> Double? in
                guard let total = lane.total, total > 0 else { return nil }
                switch lane.state {
                case .running, .leading, .won: return min(1, Double(lane.bytes) / Double(total))
                case .dropped, .failed: return nil
                }
            }.max() ?? 0
        }

        public var percent: Int { Int((fraction * 100).rounded(.down)) }
    }

    public enum Phase: Equatable {
        case idle
        case checking
        case available(version: String)
        case downloading(Race)
        case ready(version: String)
        case installing(version: String)
        case failed(String)
    }

    private enum Stage: Equatable {
        case none
        case downloading(Race)
        case ready(String)
        case installing(String)
    }

    public private(set) var known: Known = .unknown
    public private(set) var checkedAt: Date?
    public private(set) var checking = false
    /// Раньше этого суточная проверка не идёт. Пишется на старте проверки (+1 ч: оборвалась —
    /// повтор через час) и на ответе (+24 ч, ошибка — +1 ч).
    public private(set) var nextDailyAt: Date?
    /// Последняя ошибка фоновой загрузки или установки — подсказка к пункту.
    public private(set) var lastError: String?
    /// В папку Claude писать можно (`ClaudeUpdater.preflight`); нельзя — фон не качает.
    public var canWrite = true
    private var stage: Stage = .none
    private var downloadFailedAt: Date?

    public init(nextDailyAt: Date? = nil) { self.nextDailyAt = nextDailyAt }

    public var phase: Phase {
        switch stage {
        case .installing(let version): return .installing(version: version)
        case .downloading(let race): return .downloading(race)
        case .ready(let version): return .ready(version: version)
        case .none: break
        }
        if checking { return .checking }
        switch known {
        case .available(let version): return .available(version: version)
        case .failed(let why): return .failed(why)
        case .unknown, .latest: return .idle
        }
    }

    // MARK: - проверка

    /// Спросить ли источники сейчас. Да — `checking` взведён до `finish`. Пока качается или
    /// ставится — нет: одна работа за раз (ручная и фоновая друг друга не затирают).
    public mutating func beginCheck(at: Date, trigger: Trigger = .menu, busy: Bool = false) -> Bool {
        guard !busy, !checking else { return false }
        switch stage {
        case .downloading, .installing: return false
        case .none, .ready: break
        }
        switch trigger {
        case .daily:
            if let next = nextDailyAt, at < next { return false }
        case .menu:
            if let last = checkedAt {
                let elapsed = at.timeIntervalSince(last)
                if elapsed >= 0 && elapsed < Self.checkInterval { return false }
            }
        case .manual:
            break
        }
        checking = true
        nextDailyAt = at.addingTimeInterval(Self.retryInterval)
        return true
    }

    /// Ответ (или осечка — тоже ответ: без сети меню не должно дёргать источники на каждом открытии).
    public mutating func finish(_ known: Known, at: Date) {
        self.known = known
        checkedAt = at
        checking = false
        if case .failed = known {
            nextDailyAt = at.addingTimeInterval(Self.retryInterval)
        } else {
            nextDailyAt = at.addingTimeInterval(Self.dailyInterval)
        }
    }

    /// Claude обновился — прежний ответ больше не про него.
    public mutating func forget() {
        known = .unknown
        checkedAt = nil
        checking = false
    }

    // MARK: - загрузка и установка

    /// Какую версию качать в фоне сейчас: найдено новее готового, фон включён, писать можно,
    /// ничего не качается и не ставится, прошлая неудача — не раньше часа назад.
    public func wantsDownload(autoDownload: Bool, at: Date) -> String? {
        guard autoDownload, canWrite, case .available(let version) = known else { return nil }
        if let failed = downloadFailedAt, at.timeIntervalSince(failed) < Self.retryInterval { return nil }
        switch stage {
        case .downloading, .installing: return nil
        case .ready(let ready): return Self.isNewer(version, than: ready) ? version : nil
        case .none: return version
        }
    }

    public mutating func startDownload(version: String) {
        stage = .downloading(Race(version: version, lanes: []))
        lastError = nil
    }

    /// Снимок гонки; чужая версия (гонку уже сменили) не принимается.
    public mutating func progress(_ race: Race) {
        guard case .downloading(let current) = stage, current.version == race.version else { return }
        stage = .downloading(race)
    }

    /// Скачано и проверено — `ready.json` лёг.
    public mutating func downloaded(version: String) {
        stage = .ready(version)
        lastError = nil
        downloadFailedAt = nil
    }

    /// Загрузку отменили (дорогая сеть, сон) — не неудача: без часовой паузы и без ошибки в подсказке.
    public mutating func downloadCancelled() {
        if case .downloading = stage { stage = .none }
    }

    public mutating func downloadFailed(_ why: String, at: Date) {
        if case .downloading = stage { stage = .none }
        lastError = why
        downloadFailedAt = at
    }

    /// Готовое с прошлого запуска (`ClaudeUpdater.loadReady`). Во время загрузки/установки не трогаем.
    public mutating func restoreReady(version: String?) {
        switch stage {
        case .downloading, .installing: return
        case .none, .ready: stage = version.map { .ready($0) } ?? .none
        }
    }

    /// «Обновить» нажато на готовом — true, если было что ставить.
    public mutating func startInstall() -> Bool {
        guard case .ready(let version) = stage else { return false }
        stage = .installing(version)
        lastError = nil
        return true
    }

    public mutating func installFinished() {
        stage = .none
        lastError = nil
        forget()
    }

    public mutating func installFailed(_ why: String) {
        if case .installing = stage { stage = .none }
        lastError = why
    }

    // MARK: - «самое время» и одно нажатие

    /// Не работает ни одна страница хотя бы столько — можно предлагать.
    public static let offerIdleSeconds: TimeInterval = 120
    /// Не предлагать чаще (и «Позже» — на столько же).
    public static let offerRepeatSeconds: TimeInterval = 3 * 60 * 60

    /// Пора ли предложить обновиться (план WF87 п. 5): готово И (Claude не запущен ИЛИ окон 0 ИЛИ
    /// ни одна страница не работает ≥ 120 с) И не предлагали последние 3 ч И не «Позже».
    /// `anyPageWorking` nil — не знаем (это не «не работает»); `idleSeconds` — секунды с последнего
    /// «работает» на любой странице (или с первого тихого круга), nil — не наблюдали: не предлагаем. Сессии Claude Code без окна
    /// страницы не видят — их работа сюда не попадает.
    public static func shouldOffer(ready: Bool, claudeRunning: Bool, windowCount: Int, anyPageWorking: Bool?,
                                   idleSeconds: TimeInterval?, lastOfferAt: Date?, snoozeUntil: Date?,
                                   now: Date) -> Bool {
        guard ready else { return false }
        if let last = lastOfferAt, now.timeIntervalSince(last) < offerRepeatSeconds { return false }
        if let snooze = snoozeUntil, now < snooze { return false }
        if !claudeRunning || windowCount == 0 { return true }
        guard anyPageWorking == false else { return false }
        guard let idle = idleSeconds else { return false }
        return idle >= offerIdleSeconds
    }

    /// Спрашивать ли перед закрытием Claude: без вопроса — только когда Claude не запущен, окон нет
    /// или известно, что ни одна страница не работает. Не знаем — спрашиваем.
    public static func needsConfirm(claudeRunning: Bool, windowCount: Int, anyPageWorking: Bool?) -> Bool {
        claudeRunning && windowCount > 0 && anyPageWorking != false
    }

    /// Вопрос, когда известно, сколько чатов работает (панель батча C).
    public static func confirmWorkingTitle(chats: Int) -> String {
        "Идёт работа в \(chats) \(chats % 10 == 1 && chats % 100 != 11 ? "чате" : "чатах") — обновить всё равно?"
    }

    // MARK: - уведомление «Скачалось обновление»

    public static let readyCategory = "ClaudeUpdateReady"
    public static let updateAction = "UpdateClaude"
    /// Категория и кнопка «патч слетел» (`Notifier`) — чтобы разводить клики в одном месте.
    public static let patchLostCategory = "PatchLost"
    public static let patchAgainAction = "InstallAgain"
    /// `UNNotificationDefaultActionIdentifier` — клик по самому баннеру.
    public static let defaultAction = "com.apple.UNNotificationDefaultActionIdentifier"

    public static func readyNotificationTitle(version: String) -> String { "Скачалось обновление Claude \(version)" }
    public static let readyNotificationBody = "Одно нажатие — Claude обновится, патч и окна вернутся."

    public enum NotificationRoute: Equatable {
        /// «Вернуть патч» (патч слетел).
        case reinstallPatch
        /// «Обновить Claude» — тот же путь, что пункт меню, с вопросом, если есть окна.
        case updateClaude
        case nothing
    }

    /// Клик по уведомлению разводится по категории (критик WF87 п. 7): «Скачалось обновление» НЕ
    /// зовёт «Поставить»; закрыть баннер — ничего.
    public static func route(category: String, action: String) -> NotificationRoute {
        let pressed = action == defaultAction
        switch category {
        case readyCategory: return pressed || action == updateAction ? .updateClaude : .nothing
        case patchLostCategory: return pressed || action == patchAgainAction ? .reinstallPatch : .nothing
        default: return .nothing
        }
    }

    // MARK: - мелочи

    /// «5,1 МБ/с».
    public static func speedText(_ bytesPerSec: Double) -> String {
        let mb = max(0, bytesPerSec) / 1_000_000
        return String(format: "%.1f", mb).replacingOccurrences(of: ".", with: ",") + " МБ/с"
    }

    /// Версии числами по частям (как `ClaudeUpdater.compareVersions`); не сравнить — не новее.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ text: String) -> [Int]? {
            let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
            let numbers = pieces.compactMap { Int($0) }
            return numbers.count == pieces.count && !numbers.isEmpty ? numbers : nil
        }
        guard let left = parts(a), let right = parts(b) else { return false }
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : 0
            let r = i < right.count ? right[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
