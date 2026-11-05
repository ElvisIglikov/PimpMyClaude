import AppKit
import ApplicationServices
import Patcher

// Вход на сайт (WF302, #11225). Слово Элвиса 30.10.2026 ~17:45: «я постоянно теряюсь, ну, забываю, что куда-то войти
// нужно, если такие стрелочки будут, то будет удобно… а что будет, если несколько входов нужно сделать?» Правило —
// SkilZZZ `RARE.md`, «Вход на сайт — Элвису окном со свечением и стрелкой».
//
// Чат зовёт `pimp.py login <адрес> [--name …]` — CLI кладёт `logins/<id>.json`. Здесь раз в секунду берём самый старый
// вход, выводим Chrome с этой страницей вперёд — один раз на вход (AppleScript: право «Автоматизация» на Chrome у Пимпа
// уже есть с #6618, `HtmlChromeOpener`; не дали — `open` новой вкладкой), и «вода» маяка окон доступа
// (`ConsentWaterOverlay`) рисует свечение вокруг окна Chrome и стрелку у курсора на поле входа. Поле — из AX-дерева
// Chrome (веб-дерево включаем `AXManualAccessibility`, когда вход висит, и выключаем, когда очередь пуста, если включали
// мы). Клик по окошку — курсор в поле и фокус в нём; печатает и жмёт «Войти» человек, мы не печатаем ничего.
// Поле пропало (вошёл) — `done`, вода стекает, следующий вход. Входы — строго по одному, в порядке прихода; тот же сайт
// второй раз — тот же вход. Висит 30 мин — маяк гаснет, плашка HUD, вход ждёт повторного `pimp.py login`.
// Ответ CLI — `logins/<id>.state.json`: его пишет только приложение, запрос — только CLI (снять вход — CLI удаляет
// свой запрос). Висит окно запроса macOS (`ConsentBeacon`) — вход уступает ему воду. Контракт —
// docs/contracts/630-wf302-login.md.

/// Запрос входа — `logins/<id>.json`, пишет `pimp.py login`.
struct LoginRequest: Equatable {
    let id: String
    let url: String
    let name: String
    let at: String
    let from: String
    /// Тот же вход позвали снова (CLI перезаписал файл): будит погасший по 30 мин маяк.
    let again: String?

    /// Разбор файла: `v` = 1, `id` совпадает с именем файла, адрес — http(s) с хостом; иначе nil.
    static func parse(_ data: Data, fileID: String) -> LoginRequest? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (json["v"] as? NSNumber)?.intValue == 1, let id = json["id"] as? String, id == fileID,
              let url = json["url"] as? String, LoginQueue.host(of: url) != nil else { return nil }
        let name = (json["name"] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return LoginRequest(id: id, url: url, name: name.isEmpty ? (LoginQueue.host(of: url) ?? url) : name,
                            at: json["at"] as? String ?? "", from: json["from"] as? String ?? "",
                            again: json["again"] as? String)
    }

    var host: String { LoginQueue.host(of: url) ?? "" }
}

/// Состояние входа в `<id>.state.json`.
enum LoginState: String {
    /// В очереди (или погас по 30 мин — `reason` скажет).
    case waiting
    /// Chrome впереди, маяк горит.
    case shown
    /// Вошёл: поле входа пропало.
    case done
    /// Вкладку входа закрыли или Chrome закрыли.
    case gone
    /// Не вышло открыть (нет Chrome).
    case failed

    var finished: Bool { self == .done || self == .gone || self == .failed }
}

/// Запись `<id>.state.json`.
struct LoginStateRecord: Equatable {
    var id: String
    var state: LoginState
    var reason: String
    var url: String
    var name: String
    var index: Int
    var total: Int

    func json(at date: Date) -> Data {
        let body: [String: Any] = ["v": 1, "id": id, "state": state.rawValue, "reason": reason,
                                   "at": LoginQueue.iso(date), "url": url, "name": name, "index": index, "total": total]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    /// Состояние, время и `total` из файла (0 — дубль, в счёт «k из n» не идёт); не разобрали — nil.
    static func parse(_ data: Data) -> (state: LoginState, at: Date?, total: Int)? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = json["state"] as? String, let state = LoginState(rawValue: raw) else { return nil }
        return (state, (json["at"] as? String).flatMap { LoginQueue.date($0) }, (json["total"] as? NSNumber)?.intValue ?? 1)
    }
}

/// Очередь входов — чистые правила.
enum LoginQueue {
    static let requestSuffix = ".json"
    static let stateSuffix = ".state.json"
    /// Законченный вход считается в «1 из 3» ещё столько.
    static let recentWindow: TimeInterval = 30 * 60
    /// Законченный вход (запрос и состояние) убираем через столько.
    static let keepFinished: TimeInterval = 60 * 60

    /// Хост адреса строчными, без `www.`; не http(s) или без хоста — nil.
    static func host(of url: String) -> String? {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme),
              var host = parsed.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Порядок прихода: по `at`, при равенстве — по id (id CLI начинается с миллисекунд).
    static func ordered(_ requests: [LoginRequest]) -> [LoginRequest] {
        requests.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    }

    /// Тот же сайт дважды — один вход: остаётся первый по порядку, остальные — дубли (id → id первого).
    static func split(_ ordered: [LoginRequest]) -> (queue: [LoginRequest], duplicates: [String: String]) {
        var first: [String: String] = [:]
        var queue: [LoginRequest] = []
        var duplicates: [String: String] = [:]
        for request in ordered {
            if let owner = first[request.host] {
                duplicates[request.id] = owner
            } else {
                first[request.host] = request.id
                queue.append(request)
            }
        }
        return (queue, duplicates)
    }

    /// «Вход k из n»: законченные недавно идут в счёт, чтобы третий вход не стал «1 из 1».
    static func counter(position: Int, finishedRecent: Int, queued: Int) -> (index: Int, total: Int) {
        (finishedRecent + position + 1, finishedRecent + queued)
    }

    /// Заголовок окошка: «Вход: App Store Connect» — в ширину окошка влезает шрифтом от 12 (с «Войди:» — нет).
    static func title(_ name: String) -> String { "Вход: \(name)" }

    /// Куда ведёт клик по окошку.
    enum Click {
        case field, tab, window

        var long: String {
            switch self {
            case .field: return "клик — курсор в поле"
            case .tab: return "клик — к вкладке входа"
            case .window: return "клик — к окну входа"
            }
        }

        var short: String {
            switch self {
            case .field: return "клик — в поле"
            case .tab: return "клик — к вкладке"
            case .window: return "клик — к окну"
            }
        }
    }

    /// Вторая строка окошка: входов несколько — сперва «2 из 3», клик — коротко.
    static func line2(index: Int, total: Int, click: Click) -> String {
        total > 1 ? "\(index) из \(total) · \(click.short)" : click.long
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

/// Поле ввода страницы из AX-дерева Chrome.
struct LoginField: Equatable {
    var role: String
    var subrole: String?
    /// CG (y вниз).
    var frame: CGRect
    var enabled: Bool
    /// Поле пустое (значение не храним — там бывает пароль).
    var empty: Bool
    /// Подписи строчными: заголовок, описание, подсказка, id элемента страницы.
    var label: String

    var secure: Bool { role == "AXSecureTextField" || subrole == "AXSecureTextField" }
}

/// Какое поле — поле входа.
enum LoginFieldPick {
    static let roles: Set<String> = ["AXTextField", "AXSecureTextField", "AXComboBox"]
    /// Подписи поля входа: почта, телефон, Apple ID, логин; коды подтверждения (второй шаг входа).
    static let labelHints = ["mail", "phone", "apple id", "appleid", "account", "login", "log in", "user", "почт",
                             "логин", "телефон", "пользовател", "учётн", "учетн", "code", "verification", "digit", "otp",
                             "код", "цифр"]
    /// Адрес страницы или рамки входа (у App Store Connect форма в рамке idmsa.apple.com).
    static let urlHints = ["login", "log-in", "signin", "sign-in", "sign_in", "logon", "/auth", "auth.", "idmsa.",
                           "accounts.", "/sso", "sso.", "oauth", "/session"]

    static func isLoginURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return urlHints.contains { lower.contains($0) }
    }

    static func hinted(_ field: LoginField) -> Bool {
        labelHints.contains { field.label.contains($0) }
    }

    /// Номер поля входа в `fields` (порядок документа) или nil — входа на странице нет. Сильные поля — пароль и
    /// поле с подписью входа; простые текстовые — только на странице входа (`loginURL`: коды второго шага). Среди
    /// группы — первое пустое на виду, иначе первое на виду, иначе первое.
    static func choose(_ fields: [LoginField], visible: CGRect, loginURL: Bool) -> Int? {
        let usable = fields.indices.filter { fields[$0].enabled && fields[$0].frame.width > 2 && fields[$0].frame.height > 2 }
        let strong = usable.filter { fields[$0].secure || hinted(fields[$0]) }
        let group = strong.isEmpty ? (loginURL ? usable : []) : strong
        guard !group.isEmpty else { return nil }
        let onScreen = { (i: Int) in visible.intersects(fields[i].frame) }
        return group.first { fields[$0].empty && onScreen($0) } ?? group.first(where: onScreen) ?? group.first
    }
}

/// Когда вход кончился — чистое правило по опросам.
struct LoginTracker {
    static let missingPolls = 3
    static let missingSeconds: TimeInterval = 4
    /// Поля входа так и не было (страница без входа — уже вошёл) — через столько.
    static let neverSeenSeconds: TimeInterval = 12
    /// Висит без входа — маяк гаснет.
    static let timeout: TimeInterval = 30 * 60

    enum Verdict: Equatable {
        case wait
        case done(String)
        case timeout
    }

    let shownAt: Date
    private(set) var seenAt: Date?
    private var missingSince: Date?
    private var missing = 0

    init(shownAt: Date) { self.shownAt = shownAt }

    /// `found` — поле входа нашлось (nil — дерево не прочли, не считаем); `active` — вкладка входа сейчас видна.
    mutating func observe(found: Bool?, active: Bool, now: Date) -> Verdict {
        if now.timeIntervalSince(shownAt) >= Self.timeout { return .timeout }
        guard active, let found = found else {
            missing = 0
            missingSince = nil
            return .wait
        }
        if found {
            if seenAt == nil { seenAt = now }
            missing = 0
            missingSince = nil
            return .wait
        }
        missing += 1
        if missingSince == nil { missingSince = now }
        let long = missing >= Self.missingPolls && now.timeIntervalSince(missingSince ?? now) >= Self.missingSeconds
        if seenAt != nil, long { return .done("поле входа пропало — вошёл") }
        if seenAt == nil, missing >= Self.missingPolls, now.timeIntervalSince(shownAt) >= Self.neverSeenSeconds {
            return .done("поля входа на странице нет — похоже, уже вошёл")
        }
        return .wait
    }
}

/// Chrome: AppleScript (вкладки по адресу) и разбор ответов — чистые.
enum LoginChrome {
    static let bundleID = "com.google.Chrome"
    static let appName = "Google Chrome"

    struct Tab: Equatable {
        var window: Int
        var tab: Int
        var url: String
    }

    /// Где вкладка входа сейчас: окно, активна ли, рамка окна (CG), адрес.
    struct Check: Equatable {
        var window: Int
        var active: Bool
        var bounds: CGRect?
        var url: String
    }

    private static let head = "set sep to character id 9\n"

    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Все вкладки: строка «окно⇥вкладка⇥адрес». Два запроса на окно, а не по одному на вкладку.
    static func listScript() -> String {
        head + """
        set out to ""
        tell application "\(appName)"
            repeat with w in windows
                set wid to id of w
                set ids to id of tabs of w
                set urls to URL of tabs of w
                repeat with i from 1 to count of ids
                    set out to out & wid & sep & (item i of ids) & sep & (item i of urls) & linefeed
                end repeat
            end repeat
        end tell
        return out
        """
    }

    static func parseList(_ output: String) -> [Tab] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let window = Int(parts[0]), let tab = Int(parts[1]) else { return nil }
            return Tab(window: window, tab: tab, url: String(parts[2]))
        }
    }

    /// Вкладка этого входа: тот же хост; адрес начинается с адреса входа — лучше.
    static func pick(_ tabs: [Tab], for url: String) -> Tab? {
        guard let host = LoginQueue.host(of: url) else { return nil }
        let same = tabs.filter { LoginQueue.host(of: $0.url) == host }
        let prefix = url.hasSuffix("/") ? String(url.dropLast()) : url
        return same.first { $0.url.hasPrefix(prefix) } ?? same.first
    }

    private static let bounds = "(item 1 of b) & \",\" & (item 2 of b) & \",\" & (item 3 of b) & \",\" & (item 4 of b)"

    /// Вкладку — активной, окно — первым, Chrome — вперёд; ответ «ok⇥окно⇥вкладка⇥рамка».
    /// `id` окна и вкладки в словаре Chrome — текст (`scripting.sdef`, type="text"): сравниваем строками через `as text`,
    /// иначе «"123" is 123» — ложь, и вкладка не находится никогда (живая проба 30.10 18:45 — «вкладку закрыли» через 2 с).
    static func activateScript(window: Int, tab: Int) -> String {
        head + """
        tell application "\(appName)"
            repeat with w in windows
                if ((id of w) as text) is "\(window)" then
                    set ids to id of tabs of w
                    repeat with i from 1 to count of ids
                        if ((item i of ids) as text) is "\(tab)" then set active tab index of w to i
                    end repeat
                    set index of w to 1
                    activate
                    set b to bounds of w
                    return "ok" & sep & \(window) & sep & \(tab) & sep & \(bounds)
                end if
            end repeat
        end tell
        error "нет окна"
        """
    }

    /// Вкладки нет — новая с адресом в первом окне (окон нет — новое окно); ответ как у `activateScript`.
    static func openScript(url: String) -> String {
        head + """
        tell application "\(appName)"
            if (count of windows) is 0 then
                make new window
                set URL of active tab of window 1 to \(quoted(url))
            else
                tell window 1 to make new tab with properties {URL:\(quoted(url))}
            end if
            set w to window 1
            activate
            set wid to id of w
            set tid to id of active tab of w
            set b to bounds of w
        end tell
        return "ok" & sep & wid & sep & tid & sep & \(bounds)
        """
    }

    /// Где вкладка `tab` (её могли перетащить в другое окно); нет — «gone».
    static func checkScript(tab: Int) -> String {
        head + """
        tell application "\(appName)"
            repeat with w in windows
                set ids to id of tabs of w
                repeat with i from 1 to count of ids
                    if ((item i of ids) as text) is "\(tab)" then
                        set b to bounds of w
                        set act to (((id of active tab of w) as text) is "\(tab)")
                        set u to URL of tab i of w
                        return "ok" & sep & (id of w) & sep & act & sep & \(bounds) & sep & u
                    end if
                end repeat
            end repeat
        end tell
        return "gone"
        """
    }

    /// «l,t,r,b» → рамка CG.
    static func parseBounds(_ text: Substring) -> CGRect? {
        let numbers = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, numbers[2] > numbers[0], numbers[3] > numbers[1] else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
    }

    /// Ответ `activateScript`/`openScript`: окно, вкладка, рамка.
    static func parseOpened(_ output: String) -> (window: Int, tab: Int, bounds: CGRect?)? {
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "ok", let window = Int(parts[1]), let tab = Int(parts[2]) else { return nil }
        return (window, tab, parseBounds(parts[3]))
    }

    enum CheckResult: Equatable {
        case found(Check)
        case gone
    }

    /// Ответ `checkScript`; не разобрали — nil (не повод что-то решать).
    static func parseCheck(_ output: String) -> CheckResult? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "gone" { return .gone }
        let parts = text.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == "ok", let window = Int(parts[1]) else { return nil }
        return .found(Check(window: window, active: parts[2] == "true", bounds: parseBounds(parts[3]), url: String(parts[4])))
    }
}

/// Что нашли в окне Chrome за один проход AX.
struct LoginScan {
    var windowFrame: CGRect?
    /// Веб-областей (страница и рамки); 0 — веб-дерева нет, о поле судить нельзя.
    var webAreas = 0
    var urls: [String] = []
    var fields: [LoginField] = []
    var elements: [AXUIElement] = []
    var window: AXUIElement?

    /// Поле входа: номер в `fields` или nil; `nil` у `found` — судить нельзя.
    func pick() -> (index: Int?, found: Bool?) {
        guard webAreas > 0, let frame = windowFrame else { return (nil, nil) }
        let index = LoginFieldPick.choose(fields, visible: frame, loginURL: urls.contains(where: LoginFieldPick.isLoginURL))
        return (index, index != nil)
    }
}

/// Маяк входа: очередь файлов, Chrome вперёд, «вода» со стрелкой на поле.
public final class LoginBeacon {
    public static let directoryName = "logins"
    /// Опрос каталога и, пока вход висит, AX Chrome — раз в секунду, не чаще.
    static let poll: TimeInterval = 1
    /// Вкладку входа сверяем AppleScript'ом не чаще этого.
    static let checkEvery: TimeInterval = 3
    /// Своё окно AX сверяем с рамкой окна из AppleScript с этим допуском.
    static let boundsSlack: CGFloat = 6
    static let manualAccessibility = "AXManualAccessibility"

    private let directory: URL
    private let hud: (String) -> Void
    private let paused: () -> Bool
    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private let scanQueue = DispatchQueue(label: "pimp.login.scan", qos: .userInitiated)
    private let scriptQueue = DispatchQueue(label: "pimp.login.script", qos: .userInitiated)
    private var timer: Timer?
    private var water: ConsentWaterOverlay?
    private var waterFailed = false
    private var written: [String: LoginStateRecord] = [:]

    private final class Session {
        let request: LoginRequest
        var tracker: LoginTracker
        var window: Int?
        var tab: Int?
        var bounds: CGRect?
        var active = true
        var url: String?
        var checkedAt: Date?
        var checking = false
        var scanning = false
        var scan: LoginScan?
        var field: AXUIElement?
        var fieldRect: CGRect?
        var index = 1
        var total = 1

        init(request: LoginRequest, now: Date) {
            self.request = request
            tracker = LoginTracker(shownAt: now)
        }
    }

    private enum Phase {
        case idle
        case opening(LoginRequest)
        case active(Session)
    }

    private var phase = Phase.idle
    /// Погасшие по 30 мин: id → метка повтора `again` на тот момент ("" — не было). Очередь идёт мимо них, будит
    /// повторный `pimp.py login` (CLI ставит новое `again`).
    private var dormant: [String: String] = [:]
    /// Веб-дерево Chrome включили мы — нам и выключать, когда входов нет.
    private var manualSetBy: pid_t?

    /// Сколько входов показали и закончили — для диагностики.
    public private(set) var shownCount = 0
    public private(set) var doneCount = 0
    /// `<фаза>[:хост]/<показано>/<закончено>` — для диагностики.
    public var status: String {
        switch phase {
        case .idle: return "idle/\(shownCount)/\(doneCount)"
        case .opening(let request): return "opening:\(request.host)/\(shownCount)/\(doneCount)"
        case .active(let session): return "shown:\(session.request.host)/\(shownCount)/\(doneCount)"
        }
    }

    public init(directory: URL = SupportFiles.directory.appendingPathComponent(LoginBeacon.directoryName, isDirectory: true),
                defaults: UserDefaults = .standard,
                hud: @escaping (String) -> Void = { _ in }, paused: @escaping () -> Bool = { false }) {
        self.directory = directory
        self.defaults = defaults
        self.hud = hud
        self.paused = paused
    }

    public func start() {
        stop()
        schedule(LoginBeacon.poll)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        water?.stop()
        if case .active = phase { phase = .idle }
        if case .opening = phase { phase = .idle }
        releaseManualAccessibility()
    }

    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    // MARK: - очередь

    private func poll() {
        let now = Date()
        let (requests, states) = readDirectory(now: now)
        let pending = requests.filter { !(states[$0.id]?.state.finished ?? false) }
        let (queue, duplicates) = LoginQueue.split(LoginQueue.ordered(pending))
        // Дубли (total 0) — не отдельный вход: иначе единственный вход стал бы «2 из 2».
        let recent = states.values.filter {
            $0.state.finished && $0.total > 0 && now.timeIntervalSince($0.at ?? now) < LoginQueue.recentWindow
        }.count
        for (id, owner) in duplicates {
            guard let request = requests.first(where: { $0.id == id }) else { continue }
            write(LoginStateRecord(id: id, state: .done, reason: "тот же вход, что \(owner)", url: request.url,
                                   name: request.name, index: 0, total: 0))
        }
        // Снятые (CLI удалил запрос) и законченные — гасим своё.
        if case .active(let session) = phase, !queue.contains(where: { $0.id == session.request.id }) { end(session) }
        for (id, again) in dormant where queue.first(where: { $0.id == id }).map({ ($0.again ?? "") != again }) ?? true {
            dormant[id] = nil
        }
        for (position, request) in queue.enumerated() {
            let (index, total) = LoginQueue.counter(position: position, finishedRecent: recent, queued: queue.count)
            if case .active(let session) = phase, session.request.id == request.id {
                session.index = index
                session.total = total
                continue
            }
            if case .opening(let opening) = phase, opening.id == request.id { continue }
            if dormant[request.id] != nil {
                write(LoginStateRecord(id: request.id, state: .waiting,
                                       reason: "30 мин без входа — маяк погашен; повтори pimp.py login", url: request.url,
                                       name: request.name, index: index, total: total))
                continue
            }
            write(LoginStateRecord(id: request.id, state: .waiting, reason: position == 0 ? "сейчас покажу" :
                                    "в очереди: \(index) из \(total)", url: request.url, name: request.name,
                                   index: index, total: total))
        }
        switch phase {
        case .idle:
            if let position = queue.firstIndex(where: { dormant[$0.id] == nil }) {
                open(queue[position], index: LoginQueue.counter(position: position, finishedRecent: recent,
                                                                queued: queue.count))
            } else {
                water?.fade()
                releaseManualAccessibility()
            }
        case .active(let session):
            tick(session, now: now)
        case .opening:
            break
        }
    }

    /// Запросы и состояния каталога; старые законченные пары и состояния без запроса — убираем.
    private func readDirectory(now: Date) -> ([LoginRequest], [String: (state: LoginState, at: Date?, total: Int)]) {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        var requests: [LoginRequest] = []
        var states: [String: (state: LoginState, at: Date?, total: Int)] = [:]
        for name in names where name.hasSuffix(LoginQueue.stateSuffix) {
            let id = String(name.dropLast(LoginQueue.stateSuffix.count))
            if let data = fileManager.contents(atPath: directory.appendingPathComponent(name).path),
               let parsed = LoginStateRecord.parse(data) { states[id] = parsed }
        }
        for name in names where name.hasSuffix(LoginQueue.requestSuffix) && !name.hasSuffix(LoginQueue.stateSuffix)
            && !name.hasPrefix(".") {
            let id = String(name.dropLast(LoginQueue.requestSuffix.count))
            let url = directory.appendingPathComponent(name)
            if let state = states[id], state.state.finished, now.timeIntervalSince(state.at ?? now) > LoginQueue.keepFinished {
                try? fileManager.removeItem(at: url)
                try? fileManager.removeItem(at: stateURL(id))
                states[id] = nil
                written[id] = nil
                continue
            }
            if let data = fileManager.contents(atPath: url.path), let request = LoginRequest.parse(data, fileID: id) {
                requests.append(request)
            }
        }
        for id in states.keys where !requests.contains(where: { $0.id == id }) {
            // Запрос сняли (CLI удалил свой файл) или он битый — своё состояние убираем тоже.
            try? fileManager.removeItem(at: stateURL(id))
            states[id] = nil
            written[id] = nil
        }
        return (requests, states)
    }

    private func stateURL(_ id: String) -> URL { directory.appendingPathComponent(id + LoginQueue.stateSuffix) }

    /// Пишем, только когда что-то сменилось: CLI смотрит на файл, а не на его mtime.
    private func write(_ record: LoginStateRecord) {
        guard written[record.id] != record else { return }
        if SupportFiles.writeAtomic(stateURL(record.id), record.json(at: Date())) { written[record.id] = record }
    }

    // MARK: - Chrome вперёд

    private func open(_ request: LoginRequest, index: (index: Int, total: Int)) {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: LoginChrome.bundleID) else {
            write(LoginStateRecord(id: request.id, state: .failed, reason: "Google Chrome не установлен", url: request.url,
                                   name: request.name, index: index.index, total: index.total))
            return
        }
        phase = .opening(request)
        scriptQueue.async { [weak self] in
            var opened: (window: Int, tab: Int, bounds: CGRect?)?
            if let list = LoginBeacon.runScript(LoginChrome.listScript()) {
                if let tab = LoginChrome.pick(LoginChrome.parseList(list), for: request.url) {
                    opened = LoginBeacon.runScript(LoginChrome.activateScript(window: tab.window, tab: tab.tab))
                        .flatMap(LoginChrome.parseOpened)
                }
                if opened == nil {
                    opened = LoginBeacon.runScript(LoginChrome.openScript(url: request.url)).flatMap(LoginChrome.parseOpened)
                }
            }
            DispatchQueue.main.async {
                guard let self = self, case .opening(let current) = self.phase, current.id == request.id else { return }
                if opened == nil, let url = URL(string: request.url) {
                    // Нет права «Автоматизация» на Chrome — хотя бы обычным путём: новая вкладка лучше тишины.
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: configuration)
                }
                let session = Session(request: request, now: Date())
                session.window = opened?.window
                session.tab = opened?.tab
                session.bounds = opened?.bounds
                session.index = index.index
                session.total = index.total
                self.phase = .active(session)
                self.shownCount += 1
                self.write(LoginStateRecord(id: request.id, state: .shown,
                                            reason: opened == nil ? "открыл новой вкладкой (без права на Chrome)" : "",
                                            url: request.url, name: request.name, index: index.index, total: index.total))
            }
        }
    }

    /// osascript с потолком 6 с; не вышло — nil.
    static func runScript(_ source: String, timeout: TimeInterval = 6) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = output
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - вход на экране

    private func tick(_ session: Session, now: Date) {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: LoginChrome.bundleID).first else {
            return finish(session, .gone, "Chrome закрыли")
        }
        if let tab = session.tab, !session.checking, now.timeIntervalSince(session.checkedAt ?? .distantPast) >= LoginBeacon.checkEvery {
            session.checking = true
            scriptQueue.async { [weak self] in
                let result = LoginBeacon.runScript(LoginChrome.checkScript(tab: tab)).flatMap(LoginChrome.parseCheck)
                DispatchQueue.main.async { self?.apply(result, to: session) }
            }
        }
        if !session.scanning {
            session.scanning = true
            let pid = chrome.processIdentifier, bounds = session.bounds, trusted = AXIsProcessTrusted()
            let enable = manualSetBy != pid
            scanQueue.async { [weak self] in
                var setByUs = false
                if enable { setByUs = LoginBeacon.enableWebTree(pid) }
                let scan = trusted ? LoginBeacon.scan(pid: pid, bounds: bounds) : nil
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if setByUs { self.manualSetBy = pid }
                    self.apply(scan, to: session, now: Date())
                }
            }
        }
        draw(session)
    }

    private func isCurrent(_ session: Session) -> Bool {
        if case .active(let current) = phase { return current === session }
        return false
    }

    private func apply(_ result: LoginChrome.CheckResult?, to session: Session) {
        session.checking = false
        session.checkedAt = Date()
        guard isCurrent(session), let result = result else { return }
        switch result {
        case .gone:
            finish(session, .gone, "вкладку входа закрыли")
        case .found(let check):
            session.window = check.window
            session.active = check.active
            session.url = check.url
            if let bounds = check.bounds { session.bounds = bounds }
        }
    }

    private func apply(_ scan: LoginScan?, to session: Session, now: Date) {
        session.scanning = false
        guard isCurrent(session) else { return }
        session.scan = scan
        let picked: (index: Int?, found: Bool?) = scan?.pick() ?? (nil, nil)
        if let scan = scan, let index = picked.index {
            session.field = scan.elements[index]
            session.fieldRect = scan.fields[index].frame
        } else {
            session.field = nil
            session.fieldRect = nil
        }
        if let frame = scan?.windowFrame { session.bounds = frame }
        // Окно не наше (рамка AppleScript и AX не сошлись) — о поле не судим.
        let ours = scan?.window != nil
        switch session.tracker.observe(found: ours ? picked.found : nil, active: session.active, now: now) {
        case .wait:
            draw(session)
        case .done(let reason):
            doneCount += 1
            finish(session, .done, reason)
        case .timeout:
            water?.fade()
            dormant[session.request.id] = session.request.again ?? ""
            phase = .idle
            write(LoginStateRecord(id: session.request.id, state: .waiting,
                                   reason: "30 мин без входа — маяк погашен; повтори pimp.py login",
                                   url: session.request.url, name: session.request.name,
                                   index: session.index, total: session.total))
            hud("Вход в «\(session.request.name)» ждёт — маяк погашен через 30 мин")
        }
    }

    private func finish(_ session: Session, _ state: LoginState, _ reason: String) {
        write(LoginStateRecord(id: session.request.id, state: state, reason: reason, url: session.request.url,
                               name: session.request.name, index: session.index, total: session.total))
        end(session)
    }

    private func end(_ session: Session) {
        water?.fade()
        if isCurrent(session) { phase = .idle }
    }

    /// Вода: свечение вокруг окна Chrome, стрелка — на поле входа (его нет или вкладка не видна — на окно).
    private func draw(_ session: Session) {
        guard isCurrent(session) else { return }
        guard !paused(), let window = session.bounds else {
            water?.fade()
            return
        }
        guard let overlay = waterOverlay() else { return }
        let field = session.active ? session.fieldRect.flatMap { window.intersects($0) ? $0 : nil } : nil
        let click: LoginQueue.Click = !session.active ? .tab : field != nil ? .field : .window
        overlay.title = LoginQueue.title(session.request.name)
        overlay.line2 = LoginQueue.line2(index: session.index, total: session.total, click: click)
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: LoginChrome.bundleID).first?.processIdentifier ?? 0
        let ring = ConsentWindow(number: 0, pid: pid, process: LoginChrome.appName, layer: 0, bounds: window)
        overlay.show([ring], calm: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, aim: field ?? window)
    }

    private func waterOverlay() -> ConsentWaterOverlay? {
        if let water = water { return water }
        guard !waterFailed, let overlay = ConsentWaterOverlay() else {
            waterFailed = true
            return nil
        }
        overlay.onClick = { [weak self] in self?.clicked() }
        overlay.soundEnabled = { [weak self] in
            self?.defaults.object(forKey: ConsentBeacon.soundKey) as? Bool ?? true
        }
        water = overlay
        return overlay
    }

    /// Клик по окошку: вкладку входа — активной, Chrome — вперёд, курсор — в поле и фокус в нём. Печатает человек.
    private func clicked() {
        guard case .active(let session) = phase else { return }
        let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: LoginChrome.bundleID).first
        if !session.active, let window = session.window, let tab = session.tab {
            scriptQueue.async { _ = LoginBeacon.runScript(LoginChrome.activateScript(window: window, tab: tab)) }
            session.active = true
            session.checkedAt = nil
            return
        }
        chrome?.activate(options: [])
        if let window = session.scan?.window { AX.perform(window, kAXRaiseAction) }
        if let field = session.field, let rect = session.fieldRect {
            AX.set(field, kAXFocusedAttribute, bool: true)
            CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: rect.midY))
        } else if let window = session.bounds {
            CGWarpMouseCursorPosition(CGPoint(x: window.midX, y: window.midY))
        }
        // Warp глушит мышь на четверть секунды — возвращаем сразу.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - AX Chrome (не на главном потоке)

    /// Веб-дерево Chrome: без `AXManualAccessibility` Chrome отдаёт только свои кнопки. true — включили мы.
    static func enableWebTree(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard AX.bool(app, manualAccessibility) != true else { return false }
        return AX.set(app, manualAccessibility, bool: true)
    }

    private func releaseManualAccessibility() {
        guard let pid = manualSetBy else { return }
        manualSetBy = nil
        scanQueue.async {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 1)
            AX.set(app, LoginBeacon.manualAccessibility, bool: false)
        }
    }

    /// Роли, внутрь которых не ходим: поля там нет (браузерные вкладки и строка адреса — тоже не наше).
    static let skipRoles: Set<String> = ["AXStaticText", "AXImage", "AXButton", "AXRadioButton", "AXCheckBox",
                                         "AXPopUpButton", "AXMenuButton", "AXTabGroup", "AXToolbar", "AXMenuBar",
                                         "AXMenu", "AXScrollBar", "AXTextField", "AXSecureTextField", "AXComboBox"]
    static let maxNodes = 4000
    static let maxDepth = 80
    static let budget: TimeInterval = 0.6

    /// Окно Chrome (по рамке из AppleScript, иначе главное) и поля его веб-областей.
    static func scan(pid: pid_t, bounds: CGRect?) -> LoginScan {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var result = LoginScan()
        let windows = AX.elements(app, kAXWindowsAttribute as String)
        let near = { (frame: CGRect?, target: CGRect) -> Bool in
            guard let frame = frame else { return false }
            return abs(frame.minX - target.minX) <= boundsSlack && abs(frame.minY - target.minY) <= boundsSlack
                && abs(frame.width - target.width) <= boundsSlack && abs(frame.height - target.height) <= boundsSlack
        }
        let window: AXUIElement?
        if let bounds = bounds {
            window = windows.first { near(AX.frame($0), bounds) }
        } else {
            window = AX.element(app, kAXMainWindowAttribute as String) ?? AX.element(app, kAXFocusedWindowAttribute as String)
        }
        guard let window = window else { return result }
        result.window = window
        result.windowFrame = AX.frame(window)
        let started = Date()
        var stack: [(AXUIElement, Int, Bool)] = [(window, 0, false)]
        var seen = 0
        while let item = stack.popLast(), seen < maxNodes, Date().timeIntervalSince(started) < budget {
            let (element, depth, inWeb) = item
            seen += 1
            let role = AX.string(element, kAXRoleAttribute as String) ?? ""
            var web = inWeb
            if role == "AXWebArea" {
                web = true
                result.webAreas += 1
                if let url = AX.value(element, "AXURL") {
                    if let url = url as? URL { result.urls.append(url.absoluteString) } else if let text = url as? String {
                        result.urls.append(text)
                    }
                }
            }
            if web, LoginFieldPick.roles.contains(role), let frame = AX.frame(element) {
                let labels = [kAXTitleAttribute as String, kAXDescriptionAttribute as String, "AXPlaceholderValue",
                              kAXHelpAttribute as String, "AXDOMIdentifier"].compactMap { AX.string(element, $0) }
                let value = AX.string(element, kAXValueAttribute as String) ?? ""
                result.fields.append(LoginField(role: role, subrole: AX.string(element, kAXSubroleAttribute as String),
                                                frame: frame, enabled: AX.bool(element, kAXEnabledAttribute as String) ?? true,
                                                empty: value.isEmpty, label: labels.joined(separator: " ").lowercased()))
                result.elements.append(element)
            }
            guard !skipRoles.contains(role), depth < maxDepth else { continue }
            // В стек — в обратном порядке: обход идёт в порядке документа.
            for child in AX.elements(element, kAXChildrenAttribute as String).reversed() {
                stack.append((child, depth + 1, web))
            }
        }
        return result
    }
}
