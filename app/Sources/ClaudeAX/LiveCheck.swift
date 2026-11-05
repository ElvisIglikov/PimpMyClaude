import CoreFoundation
import CoreGraphics
import Foundation
import Patcher

/// Проверка окна Claude после его обновления и самопроверка Пимпа (#10527, контракт К-HEALTH —
/// `docs/contracts/550-10527-health-live-check.md`; эталоны `tests/fixtures/live-check.json`,
/// `tests/fixtures/pimp/live-check*.json`). Здесь чистая часть: нужна ли проверка, проверки приложения по замерам,
/// отчёт, текст уведомления и файлы `live-check/`. Замеры снимает приложение, `health()` страниц приносит канал probe
/// (`ChatProbe`), ход проверки ведёт `LiveCheckRunner`.
public enum LiveCheck {
    /// Версия Claude, которую уже проверили (String в UserDefaults приложения).
    public static let checkedKey = "liveCheckedClaudeVersion"
    /// Главная страница должна прожить столько после первого ответа, прежде чем её спрашивать.
    public static let settleSeconds: TimeInterval = 20
    /// Красное перепроверяется через столько: случайная загрузка страницы не должна давать тревогу.
    public static let retrySeconds: TimeInterval = 120
    /// Видна ли панель — смотрим через столько после нажатия на значок.
    public static let clickSettle: TimeInterval = 0.15
    /// Кольцо нажатий на значок.
    public static let ringSize = 20
    /// Датированных отчётов в каталоге не больше.
    public static let keepFiles = 50
    public static let directoryName = "live-check"
    public static let lastFileName = "live-check.json"
    /// Кольцо `clickLog`: решение «открыть» — только это решение и проверяется на «видно».
    public static let openAction = "open"

    // MARK: - запись проверки

    /// `{id, ok, skip?, why?, at?}` — одна форма у страницы и приложения.
    public struct Check: Equatable {
        public let id: String
        public let ok: Bool
        public var skip: String?
        public var why: String?
        public var at: Date?

        public static func pass(_ id: String) -> Check { Check(id: id, ok: true) }
        public static func skipped(_ id: String, _ code: String) -> Check { Check(id: id, ok: true, skip: code) }
        public static func red(_ id: String, _ why: String, at: Date? = nil) -> Check {
            Check(id: id, ok: false, why: why, at: at)
        }

        var value: CommandValue {
            var fields: [(key: String, value: CommandValue)] = [(key: "id", value: .string(id)), (key: "ok", value: .bool(ok))]
            if let skip = skip { fields.append((key: "skip", value: .string(skip))) }
            if let why = why { fields.append((key: "why", value: .string(why))) }
            if let at = at { fields.append((key: "at", value: .string(Stamp.utc.string(from: at)))) }
            return .object(fields)
        }
    }

    /// Нажатие на значок: время, решение `PanelClick` (`open`, `close`, `ignore`), видна ли панель через 150 мс
    /// (nil — ещё не смотрели).
    public struct Click: Equatable {
        public let at: Date
        public let action: String
        public var shown: Bool?

        public init(at: Date, action: String, shown: Bool? = nil) {
            self.at = at
            self.action = action
            self.shown = shown
        }
    }

    /// Последние `ringSize` нажатий.
    public static func ring(_ clicks: [Click]) -> [Click] { Array(clicks.suffix(ringSize)) }

    // MARK: - нужна ли проверка

    /// Новая версия Claude, которую ещё не проверяли. Версии нет — проверять нечего.
    public static func needsCheck(installed: String?, checked: String?) -> Bool {
        guard let installed = installed, !installed.isEmpty else { return false }
        return installed != checked
    }

    // MARK: - самопроверка приложения

    /// Экран глазами проверки: кадр и области строки меню слева и справа от выреза.
    public struct Screen: Equatable {
        public var frame: CGRect
        public var left: CGRect?
        public var right: CGRect?

        public init(frame: CGRect, left: CGRect? = nil, right: CGRect? = nil) {
            self.frame = frame
            self.left = left
            self.right = right
        }

        /// Вырез: между левой и правой областью.
        var notch: (minX: CGFloat, maxX: CGFloat)? {
            guard let left = left, let right = right, right.minX > left.maxX else { return nil }
            return (left.maxX, right.minX)
        }
    }

    /// Замеры своего процесса — только чтение.
    public struct AppFacts: Equatable {
        /// Рамка окна кнопки значка; nil — значка или окна нет.
        public var item: CGRect?
        public var screens: [Screen] = []
        public var statsOn = false
        public var limitsKnown = false
        public var iconNumber = false
        /// Рамка окна полосы «Не влезли», пока она на экране; nil — полосы нет.
        public var strip: CGRect?
        public var clicks: [Click] = []
        public var panelOpen = false
        public var panelAlpha: CGFloat = 1
        public var backgroundAlpha: CGFloat = 1

        public init(item: CGRect? = nil, screens: [Screen] = [], statsOn: Bool = false, limitsKnown: Bool = false,
                    iconNumber: Bool = false, strip: CGRect? = nil, clicks: [Click] = [], panelOpen: Bool = false,
                    panelAlpha: CGFloat = 1, backgroundAlpha: CGFloat = 1) {
            self.item = item
            self.screens = screens
            self.statsOn = statsOn
            self.limitsKnown = limitsKnown
            self.iconNumber = iconNumber
            self.strip = strip
            self.clicks = clicks
            self.panelOpen = panelOpen
            self.panelAlpha = panelAlpha
            self.backgroundAlpha = backgroundAlpha
        }
    }

    /// Допуск на дробные края кадра значка.
    static let slack: CGFloat = 2

    /// Пять проверок приложения в порядке контракта.
    public static func appChecks(_ facts: AppFacts) -> [Check] {
        [statusItem(facts), iconNumber(facts), stripWindow(facts), clickLog(facts), panelOpaque(facts)]
    }

    static func statusItem(_ facts: AppFacts) -> Check {
        let id = "statusItem"
        guard let frame = facts.item else { return .red(id, "no-item") }
        guard frame.width > 0, frame.height > 0 else { return .red(id, "zero: \(int(frame.width))×\(int(frame.height))") }
        var host: Screen?
        var best: CGFloat = 0
        for screen in facts.screens {
            let common = screen.frame.intersection(frame)
            guard !common.isNull, common.width * common.height > best else { continue }
            best = common.width * common.height
            host = screen
        }
        let inside = { (area: CGRect) in
            frame.minX >= area.minX - slack && frame.maxX <= area.maxX + slack
                && frame.minY >= area.minY - slack && frame.maxY <= area.maxY + slack
        }
        guard let screen = host, inside(screen.frame) else {
            return .red(id, "off-screen: \(int(frame.minX)),\(int(frame.minY))")
        }
        if let notch = screen.notch {
            let areas = [screen.left, screen.right].compactMap { $0 }
            guard areas.contains(where: { frame.minX >= $0.minX - slack && frame.maxX <= $0.maxX + slack }) else {
                return .red(id, "notch: \(int(notch.minX))–\(int(notch.maxX))")
            }
        }
        return .pass(id)
    }

    static func iconNumber(_ facts: AppFacts) -> Check {
        let id = "iconNumber"
        guard facts.statsOn else { return .skipped(id, "stats-off") }
        guard facts.limitsKnown else { return .skipped(id, "no-limits") }
        return facts.iconNumber ? .pass(id) : .red(id, "no-number")
    }

    static func stripWindow(_ facts: AppFacts) -> Check {
        let id = "stripWindow"
        guard let strip = facts.strip else { return .skipped(id, "hidden") }
        guard strip.width >= 40, strip.height >= 20 else {
            return .red(id, "zero: \(int(strip.width))×\(int(strip.height))")
        }
        return .pass(id)
    }

    static func clickLog(_ facts: AppFacts) -> Check {
        let id = "clickLog"
        let clicks = ring(facts.clicks)
        guard !clicks.isEmpty else { return .skipped(id, "no-clicks") }
        let lost = clicks.filter { $0.action == openAction && $0.shown == false }
        guard let last = lost.last else { return .pass(id) }
        return .red(id, "open-invisible: \(lost.count) из \(clicks.count)", at: last.at)
    }

    static func panelOpaque(_ facts: AppFacts) -> Check {
        let id = "panelOpaque"
        guard facts.panelOpen else { return .skipped(id, "closed") }
        guard facts.panelAlpha >= 1 else { return .red(id, "alpha: \(number(facts.panelAlpha))") }
        guard facts.backgroundAlpha >= 1 else { return .red(id, "background: альфа \(number(facts.backgroundAlpha))") }
        return .pass(id)
    }

    private static func int(_ value: CGFloat) -> Int { Int(value.rounded()) }

    private static func number(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    /// Раздел приложения: `{v:1, version, at, claude, checked, checks, red}`.
    public struct AppSection: Equatable {
        public let version: String
        public let at: Date
        public let claude: String
        public let checked: String?
        public let checks: [Check]

        public init(version: String, at: Date, claude: String, checked: String?, checks: [Check]) {
            self.version = version
            self.at = at
            self.claude = claude
            self.checked = checked
            self.checks = checks
        }

        public var red: [String] { checks.filter { !$0.ok }.map { $0.id } }

        var value: CommandValue {
            .object([
                (key: "v", value: .number(1)),
                (key: "version", value: .string(version)),
                (key: "at", value: .string(LiveCheck.isoText(at))),
                (key: "claude", value: .string(claude)),
                (key: "checked", value: checked.map { .string($0) } ?? .null),
                (key: "checks", value: .array(checks.map { $0.value })),
                (key: "red", value: .array(red.map { .string($0) })),
            ])
        }
    }

    // MARK: - отчёт

    /// Ответ одной страницы на круг с `health`: id webContents, адрес и сам ответ (`{v:1…}`, `{v:0}` или null).
    public struct PageAnswer {
        public let id: Int
        public let url: String
        public let health: Any?

        public init(id: Int, url: String, health: Any?) {
            self.id = id
            self.url = url
            self.health = health
        }

        var version: Int? { ((health as? [String: Any])?["v"] as? NSNumber)?.intValue }
        var map: [String: Any]? { health as? [String: Any] }
    }

    public struct Red: Equatable {
        public let window: String
        public let chat: String
        public let check: String

        var value: CommandValue {
            .object([(key: "window", value: .string(window)), (key: "chat", value: .string(chat)),
                     (key: "check", value: .string(check))])
        }
    }

    /// `{v:1, at, by, claude, pimp, ok, red, pages, unchecked, app}`.
    public struct Report {
        public let at: Date
        public let by: String
        public let claude: String
        public let pages: [PageAnswer]
        public let unchecked: Int
        public let app: AppSection?
        public let red: [Red]

        public var ok: Bool { red.isEmpty }

        var value: CommandValue {
            .object([
                (key: "v", value: .number(1)),
                (key: "at", value: .string(LiveCheck.isoText(at))),
                (key: "by", value: .string(by)),
                (key: "claude", value: .string(claude)),
                (key: "pimp", value: app.map { .string($0.version) } ?? .null),
                (key: "ok", value: .bool(ok)),
                (key: "red", value: .array(red.map { $0.value })),
                (key: "pages", value: .array(pages.map { page in
                    .object([(key: "id", value: .number(page.id)),
                             (key: "health", value: page.map.map(LiveCheck.healthValue) ?? .null)])
                })),
                (key: "unchecked", value: .number(unchecked)),
                (key: "app", value: app?.value ?? .null),
            ])
        }

        public var json: String { value.json }
    }

    /// Отчёт по ответам страниц: в `pages` — ответы `v:1`, `unchecked` — страницы claude.ai и попапы с `{v:0}`.
    public static func report(answers: [PageAnswer], app: AppSection?, claude: String, by: String, at: Date) -> Report {
        let pages = answers.filter { $0.version == 1 }
        let unchecked = answers.filter { answer in
            answer.version == 0 && (answer.url.hasPrefix(ChatProbe.claudeOrigin) || answer.url == "about:blank")
        }.count
        var red: [Red] = []
        for page in pages {
            let map = page.map ?? [:]
            let window = map["kind"] as? String ?? ""
            let chat = map["chat"] as? String ?? ""
            for id in (map["red"] as? [Any] ?? []).compactMap({ $0 as? String }) {
                red.append(Red(window: window, chat: chat, check: id))
            }
        }
        if let app = app {
            red += app.red.map { Red(window: "app", chat: "", check: $0) }
        } else {
            red.append(Red(window: "app", chat: "", check: "answer"))
        }
        return Report(at: at, by: by, claude: claude, pages: pages, unchecked: unchecked, app: app, red: red)
    }

    // MARK: - слова

    /// Что сломалось — словами для уведомления и панели.
    static let names: [String: String] = [
        "anchors": "опоры окна не найдены", "wide": "поле не справа", "fold": "свёртка поля",
        "title": "заголовок", "sidebarButton": "кнопка боковой панели", "look": "живой фон",
        "ownButtons": "кнопки PMP", "claudeButtons": "кнопки Claude перекрыты", "install": "страница не встала",
        "statusItem": "значок у часов", "iconNumber": "число в значке", "stripWindow": "полоса «Не влезли»",
        "clickLog": "панель не открылась с клика", "panelOpaque": "панель просвечивает", "answer": "PMP не ответил",
    ]

    /// «поле не справа, заголовок» — без повторов, в порядке отчёта.
    public static func brokenText(_ red: [Red]) -> String {
        var seen = Set<String>()
        var words: [String] = []
        for entry in red where seen.insert(entry.check).inserted { words.append(names[entry.check] ?? entry.check) }
        return words.joined(separator: ", ")
    }

    /// «3.1623.0» → «3.1623»: хвост «.0» в словах не нужен.
    public static func shortVersion(_ version: String) -> String {
        version.hasSuffix(".0") ? String(version.dropLast(2)) : version
    }

    /// Уведомление при красном: «Claude 3.1623: PMP нашёл поломки — поле не справа, заголовок».
    public static func notificationText(_ report: Report) -> String {
        "Claude \(shortVersion(report.claude)): PMP нашёл поломки — \(brokenText(report.red))"
    }

    /// Строка в блоке обновления панели: «Проверка окна Claude 3.1623: 2 красных — поле не справа, заголовок».
    public static func panelLine(_ report: Report) -> String? {
        guard !report.ok else { return nil }
        let count = report.red.count
        return "Проверка окна Claude \(shortVersion(report.claude)): \(count) "
            + Plural.ru(count, "красная", "красных", "красных") + " — " + brokenText(report.red)
    }

    // MARK: - файлы

    public static var directory: URL { SupportFiles.directory.appendingPathComponent(directoryName, isDirectory: true) }

    /// `<YYYY-MM-DD>-claude-<версия>.json`, дата местная.
    public static func fileName(at: Date, claude: String, timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd"
        return "\(format.string(from: at))-claude-\(claude).json"
    }

    /// Отчёт — в датированный файл и копией в `live-check.json` (временный файл и `rename`); датированных больше
    /// `keepFiles` — самые старые долой. Возвращает датированный файл; не записалось — nil.
    @discardableResult
    public static func write(_ report: Report, to directory: URL = LiveCheck.directory) -> URL? {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        let data = Data((report.json + "\n").utf8)
        let dated = directory.appendingPathComponent(fileName(at: report.at, claude: report.claude))
        guard save(data, to: dated), save(data, to: directory.appendingPathComponent(lastFileName)) else { return nil }
        let names = ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.contains("-claude-") && $0.hasSuffix(".json") }.sorted()
        for name in names.dropLast(keepFiles) { try? manager.removeItem(at: directory.appendingPathComponent(name)) }
        return dated
    }

    private static func save(_ data: Data, to url: URL) -> Bool {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { return false }
        guard rename(temp.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
        return true
    }

    /// Сводка последнего отчёта для ручки канала: `{file, at, by, claude, ok, red}`; нет файла или не читается — null.
    static func lastSummary(directory: URL = LiveCheck.directory, timeZone: TimeZone = .current) -> CommandValue {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(lastFileName)),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = map["at"] as? String, let claude = map["claude"] as? String,
              let ok = map["ok"] as? Bool, let date = parseISO(at) else { return .null }
        let red = (map["red"] as? [[String: Any]] ?? []).map { entry in
            Red(window: entry["window"] as? String ?? "", chat: entry["chat"] as? String ?? "",
                check: entry["check"] as? String ?? "").value
        }
        return .object([
            (key: "file", value: .string(fileName(at: date, claude: claude, timeZone: timeZone))),
            (key: "at", value: .string(at)),
            (key: "by", value: .string(map["by"] as? String ?? "")),
            (key: "claude", value: .string(claude)),
            (key: "ok", value: .bool(ok)),
            (key: "red", value: .array(red)),
        ])
    }

    // MARK: - время и JSON

    /// ISO с миллисекундами и `Z`: «2026-10-22T09:14:06.104Z».
    public static func isoText(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: date)
    }

    static func parseISO(_ text: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: text) { return date }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: text)
    }

    /// Порядок ключей ответа `health()` и его проверок — как в контракте; чужие ключи — следом, по алфавиту.
    static let healthOrder = ["v", "version", "page", "kind", "mode", "wide", "chat", "title", "at", "checks", "red"]
    static let checkOrder = ["id", "ok", "skip", "why", "at"]

    static func healthValue(_ map: [String: Any]) -> CommandValue {
        ordered(map, healthOrder) { key, value in
            guard key == "checks", let list = value as? [Any] else { return nil }
            return .array(list.map { item in
                (item as? [String: Any]).map { ordered($0, checkOrder) { _, _ in nil } } ?? anyValue(item)
            })
        }
    }

    private static func ordered(_ map: [String: Any], _ order: [String],
                                special: (String, Any) -> CommandValue?) -> CommandValue {
        let keys = order.filter { map[$0] != nil } + map.keys.filter { !order.contains($0) }.sorted()
        return .object(keys.map { key in
            let value = map[key] ?? NSNull()
            return (key: key, value: special(key, value) ?? anyValue(value))
        })
    }

    /// Значение из `JSONSerialization` — обратно в JSON: числа целые — целыми, булевы — булевыми.
    static func anyValue(_ value: Any) -> CommandValue {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let double = number.doubleValue
            if double.isFinite, double.rounded() == double, abs(double) < 9_007_199_254_740_992 { return .number(Int(double)) }
            return .decimal(double)
        case let text as String: return .string(text)
        case let list as [Any]: return .array(list.map(anyValue))
        case let map as [String: Any]:
            return .object(map.keys.sorted().map { (key: $0, value: anyValue(map[$0] ?? NSNull())) })
        default: return .null
        }
    }
}

/// Ход проверки окна после обновления Claude (#10527): взвели на новой версии — ждём главную страницу, через 20 с
/// просим `health()` кругом probe; красное — ещё раз через 2 мин; итог — отчёт `by:"app"`, ключ
/// `liveCheckedClaudeVersion` и `onDone`. Страницы без `health()` (старая страница) — «не проверено»: повтор через
/// 2 мин, на второй раз бросаем до следующего запуска. Живёт на главной очереди.
final class LiveCheckRunner {
    private let now: () -> Date
    private let defaults: UserDefaults
    /// Раздел приложения — его собирает `AppDelegate` (замеры значка и панели); nil — приложение не ответило.
    var appSection: () -> LiveCheck.AppSection? = { nil }
    var write: (LiveCheck.Report) -> URL? = { LiveCheck.write($0) }
    var onDone: (LiveCheck.Report, URL?) -> Void = { _, _ in }

    private(set) var pending: String?
    private var mainSince: Date?
    private var retryAt: Date?
    private var redSeen = false
    private var uncheckedRounds = 0

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// Установлен Claude `version`: не проверяли — взвести.
    func arm(claude version: String) {
        guard pending != version,
              LiveCheck.needsCheck(installed: version, checked: defaults.string(forKey: LiveCheck.checkedKey)) else { return }
        pending = version
        mainSince = nil
        retryAt = nil
        redSeen = false
        uncheckedRounds = 0
    }

    /// Пора ли в этом круге просить `health()`: главная страница отвечает уже 20 с и повтор не ждёт.
    func due(pages: [ChatPage]) -> Bool {
        guard pending != nil else { return false }
        let at = now()
        if mainSince == nil, pages.contains(where: { $0.kind == .main }) { mainSince = at }
        guard let since = mainSince, at.timeIntervalSince(since) >= LiveCheck.settleSeconds else { return false }
        if let retry = retryAt, at < retry { return false }
        return true
    }

    /// Ответы круга с `health()`.
    func absorb(_ answers: [LiveCheck.PageAnswer]) {
        guard let claude = pending else { return }
        let at = now()
        let report = LiveCheck.report(answers: answers, app: appSection(), claude: claude, by: "app", at: at)
        if report.pages.isEmpty {
            uncheckedRounds += 1
            if uncheckedRounds >= 2 { pending = nil } else { retryAt = at.addingTimeInterval(LiveCheck.retrySeconds) }
            return
        }
        if !report.ok && !redSeen {
            redSeen = true
            retryAt = at.addingTimeInterval(LiveCheck.retrySeconds)
            return
        }
        let file = write(report)
        defaults.set(claude, forKey: LiveCheck.checkedKey)
        pending = nil
        onDone(report, file)
    }
}
