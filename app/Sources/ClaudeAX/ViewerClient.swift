import AppKit
import ApplicationServices
import Foundation

/// Клиент Пимп → PimpViewer.app (WF104, контракт К-V8 в `PimpViewer/docs/CONTRACTS.md`): галерея живёт своим
/// приложением на `127.0.0.1:47616`, Пимп только подаёт ей файлы из чата (`/accept`), держит «▦ Галерея»
/// (`/gallery`, `/state`) и меню «🖼 Pimp Viewer» (`/show`).
///
/// Всё межпроцессное — на своей очереди: ни порт 47615, ни главная ответа не ждут, колбэки приходят на очередь
/// клиента. Токен — `channel.token` склада (создаёт Viewer, Пимп только читает): лениво, 403 — перечитать и
/// повторить один раз. Токен не пишется ни в журнал, ни в диагностику.
///
/// Не достучались (нет токена, отказ соединения, тишина) — Пимп сам запускает PimpViewer.app в фоне
/// (`--background`, без фокуса) и до 3 с ждёт `/ping` с `ready:true`, потом повторяет запрос один раз; не вышло —
/// у сиденья прежний путь (браузер, «Просмотр»). С `PIMP_VIEWER_STORE` (гейт на копии склада) — без автозапуска.
public final class ViewerClient {
    public static let port: UInt16 = 47616
    public static let bundleID = "com.elvis.pimpviewer"
    static let tokenFile = "channel.token"
    /// Таймаут запроса (ТЗ: ≈300 мс) — клик из чата не должен заметно ждать галерею.
    static let timeout: TimeInterval = 0.3
    /// Сколько ждём `ready:true` после запуска и как часто спрашиваем.
    static let readyWait: TimeInterval = 3
    static let readyPoll: TimeInterval = 0.15
    /// Сколько после молчания запущенной галереи не ждём её `ready` снова.
    static let deadPause: TimeInterval = 30
    /// Окно галереи появляется позже ответа `/accept` — столько раз по стольку ждём его для вывода вперёд.
    static let frontTries = 5
    static let frontPause: TimeInterval = 0.15

    struct Reply {
        let status: Int
        let json: [String: Any]
    }

    let port: UInt16
    let tokenURL: URL
    /// Запускать ли PimpViewer.app самим (нет `PIMP_VIEWER_STORE`).
    let launches: Bool
    private let queue = DispatchQueue(label: "pimpmyclaude.viewer-client", qos: .userInitiated)
    private let session: URLSession
    /// Токен — только на очереди клиента.
    private var token: String?

    /// Установлен ли PimpViewer.app (тест подменяет).
    var installed: () -> Bool = { ViewerClient.appURL() != nil }
    /// Запущен ли (тест подменяет).
    var running: () -> Bool = { !NSRunningApplication.runningApplications(withBundleIdentifier: ViewerClient.bundleID).isEmpty }
    /// Запуск в фоне без окна и фокуса (тест подменяет).
    var launch: () -> Void = ViewerClient.launchInBackground
    /// Вывод окна галереи вперёд; true — окно есть и поднято (тест подменяет).
    var raise: () -> Bool = { false }
    /// «▦ Галерея» или «🖼 Pimp Viewer», а приложения нет — повод для плашки. Зовут на очереди клиента.
    public var onMissing: (() -> Void)?

    private let lock = NSLock()
    private var up = false
    private var known = true
    private var takenCount = 0
    private var refusedCount = 0
    /// pid галереи из `/ping` — вывод вперёд именно её, а не безглавого экземпляра гейта (П1 WF104).
    private var viewerPID: pid_t?
    /// Запущено, а канал молчит — до этой поры не ждём `ready` на каждом клике (П1 WF104).
    private var deadUntil: Date?
    /// Последний запуск: второй запрос в эти 3 с не зовёт `openApplication` снова — иначе reopen покажет окно.
    private var launchedAt: Date?

    /// Боевой клиент: склад — `PIMP_VIEWER_STORE` (гейт), иначе `MyClaude/viewer`.
    public convenience init() {
        let custom = ViewerClient.customStore
        self.init(port: ViewerClient.port,
                  tokenURL: (custom ?? ViewerClient.defaultStore).appendingPathComponent(ViewerClient.tokenFile),
                  launches: custom == nil)
        raise = { [weak self] in ViewerClient.raiseWindow(pid: self?.currentPID) }
    }

    init(port: UInt16, tokenURL: URL, launches: Bool) {
        self.port = port
        self.tokenURL = tokenURL
        self.launches = launches
        // Как `PimpClient` на той стороне: без кэша, прокси и редиректов, колбэки — на очереди клиента.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldUsePipelining = false
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: delegateQueue)
    }

    static var defaultStore: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyClaude/viewer", isDirectory: true)
    }

    /// `PIMP_VIEWER_STORE` — склад не боевой (гейт); так же его читает PimpViewer.app.
    static var customStore: URL? {
        guard let raw = ProcessInfo.processInfo.environment["PIMP_VIEWER_STORE"], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath, isDirectory: true)
    }

    /// Файл токена канала — его же читают входящие ручки порта 47615.
    public static var tokenURL: URL {
        (customStore ?? defaultStore).appendingPathComponent(tokenFile)
    }

    // MARK: - диагностика

    private var currentPID: pid_t? { lock.lock(); defer { lock.unlock() }; return viewerPID }

    /// Последний `/ping` или `/state` удался — счёт кнопке «Галерея» есть кому отдать.
    public var isUp: Bool { lock.lock(); defer { lock.unlock() }; return up }

    /// `viewer=<up|down|none>/<принято>/<отказов>`: `none` — PimpViewer.app не установлен.
    public var status: String {
        lock.lock(); defer { lock.unlock() }
        return "\(up ? "up" : known ? "down" : "none")/\(takenCount)/\(refusedCount)"
    }

    // MARK: - запросы

    /// На старте Пимпа: установлен и не запущен — запустить в фоне; дождаться `ready`, чтобы знать, что канал жив.
    public func start() {
        queue.async { [self] in waitReady { _ in } }
    }

    /// Файл из чата (`click`/`auto`/`view`). `done(true)` — галерея взяла, браузер не нужен; на очереди клиента.
    /// `focus:true` (только `click` + известный чат) — окно галереи вперёд.
    public func accept(path: String, mode: HtmlChromeOpener.Mode, chat: String?, done: @escaping (Bool) -> Void) {
        var target = "/accept?mode=\(mode.rawValue)&path=\(ViewerClient.encode(path))"
        if let chat = chat { target += "&chat=\(ViewerClient.encode(chat))" }
        call(target, starting: true) { [self] reply in
            let taken = reply?.status == 200 && reply?.json["taken"] as? Bool == true
            lock.lock()
            if taken { takenCount += 1 } else { refusedCount += 1 }
            lock.unlock()
            if taken, reply?.json["focus"] as? Bool == true { bringFront() }
            done(taken)
        }
    }

    /// Кнопка «Галерея» в чате (К-V1 `/viewer`).
    public func gallery(chat: String, on: Bool) {
        call("/gallery?chat=\(ViewerClient.encode(chat))&on=\(on ? 1 : 0)", starting: true, missing: true) { _ in }
    }

    /// «🖼 Pimp Viewer» из меню и панели у часов: окно галереи вперёд.
    public func show() {
        call("/show", starting: true, missing: true) { [self] reply in
            if reply?.status == 200 { bringFront() }
        }
    }

    /// Фильтр и счёт галереи (К-V2, К-V7); nil — не ответила. Без запуска: толкает галерея сама.
    public func state(done: @escaping ((filterChat: String?, counts: [String: [Int]])?) -> Void) {
        call("/state", starting: false) { reply in
            guard let reply = reply, reply.status == 200 else { return done(nil) }
            done(ViewerClient.parseState(reply.json))
        }
    }

    /// Жив ли канал — для счёта кнопки «Галерея», пока галерея молчит. Без запуска.
    public func ping() {
        call("/ping", starting: false) { _ in }
    }

    /// `/state` → фильтр и счёт: числа — только целые, мусор — прочь.
    static func parseState(_ json: [String: Any]) -> (filterChat: String?, counts: [String: [Int]]) {
        var counts: [String: [Int]] = [:]
        for (chat, value) in json["counts"] as? [String: Any] ?? [:] {
            guard HtmlChromeOpener.chatID(chat) != nil, let numbers = value as? [NSNumber] else { continue }
            counts[chat] = numbers.map { $0.intValue }
        }
        return (HtmlChromeOpener.chatID(json["filterChat"] as? String), counts)
    }

    /// Запрос; не достучались и `starting` — запуск, `ready`, один повтор. `missing` — приложения нет — плашка.
    private func call(_ target: String, starting: Bool, missing: Bool = false, done: @escaping (Reply?) -> Void) {
        queue.async { [self] in
            get(target) { [self] reply in
                guard reply == nil, starting else { return done(reply) }
                waitReady { [self] ready in
                    guard ready else {
                        if missing, !known { onMissing?() }
                        return done(nil)
                    }
                    get(target, done: done)
                }
            }
        }
    }

    /// Запустить (если можно и нужно) и до 3 с ждать `/ping` с `ready:true`. На очереди клиента, без сна.
    private func waitReady(done: @escaping (Bool) -> Void) {
        let installed = installed()
        lock.lock()
        known = installed
        lock.unlock()
        let now = Date()
        if let dead = deadUntil, now < dead { return done(false) }
        let isRunning = running()
        if !isRunning {
            guard launches, installed else { return done(false) }
            if launchedAt.map({ now.timeIntervalSince($0) >= ViewerClient.readyWait }) ?? true {
                launchedAt = now
                launch()
            }
        }
        let deadline = now.addingTimeInterval(ViewerClient.readyWait)
        func poll() {
            get("/ping") { [self] reply in
                if reply?.status == 200, reply?.json["ready"] as? Bool == true {
                    deadUntil = nil
                    return done(true)
                }
                guard Date() < deadline else {
                    // Было запущено, а канал так и не ответил — полминуты клики сразу идут прежним путём.
                    if isRunning { deadUntil = Date().addingTimeInterval(ViewerClient.deadPause) }
                    return done(false)
                }
                queue.asyncAfter(deadline: .now() + ViewerClient.readyPoll) { poll() }
            }
        }
        poll()
    }

    /// GET на галерею: нет токена — перечитать перед запросом, 403 — перечитать и повторить один раз.
    /// nil — не достучались. На очереди клиента.
    private func get(_ target: String, done: @escaping (Reply?) -> Void) {
        if token == nil { token = ViewerClient.readToken(at: tokenURL) }
        send(target) { [self] reply in
            guard reply?.status == 403 else { return finish(reply, done) }
            token = ViewerClient.readToken(at: tokenURL)
            send(target) { [self] in finish($0, done) }
        }
    }

    private func finish(_ reply: Reply?, _ done: (Reply?) -> Void) {
        lock.lock()
        up = reply?.status == 200
        if up { known = true }
        if up, let pid = reply?.json["pid"] as? NSNumber { viewerPID = pid_t(pid.int32Value) }
        lock.unlock()
        done(reply)
    }

    private func send(_ target: String, done: @escaping (Reply?) -> Void) {
        guard let token = token, let url = URL(string: "http://127.0.0.1:\(port)" + target) else { return done(nil) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ViewerClient.timeout)
        request.setValue(token, forHTTPHeaderField: "X-Pimp-Viewer-Token")
        session.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse else { return done(nil) }
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            done(Reply(status: http.statusCode, json: json))
        }.resume()
    }

    /// Окно галереи вперёд: оно появляется позже ответа — до 5 попыток по 150 мс, на очереди клиента.
    private func bringFront(attempt: Int = 1) {
        guard !raise(), attempt < ViewerClient.frontTries else { return }
        queue.asyncAfter(deadline: .now() + ViewerClient.frontPause) { [self] in bringFront(attempt: attempt + 1) }
    }

    // MARK: - приложение

    /// Ключ запроса — как `encodeURIComponent`.
    static func encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// 32 строчных hex и перевод строки — иначе nil.
    static func readToken(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count <= 64 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 32, text.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return text
    }

    /// Какую копию PimpViewer.app запускать: `/Applications`, иначе любая, кроме сборок и корзины (П1 WF104:
    /// LaunchServices знает и dev-сборку `PimpViewer/app/.build` — на боевом складе ей не место).
    static func appURL() -> URL? {
        let main = URL(fileURLWithPath: "/Applications/PimpViewer.app")
        if Bundle(url: main)?.bundleIdentifier == bundleID { return main }
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first { url in
            !["/.build/", "/DerivedData/", "/.Trash/"].contains { url.path.contains($0) }
        }
    }

    static func launchInBackground() {
        guard let app = appURL() else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["--background"]
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    /// Вывод вперёд — как окна Claude (`ClaudeApp.focus`): `activate`, raise, main, и `kAXFrontmost` вдогонку (гейт фазы
    /// В: одного `kAXFrontmost` не хватило). Окно — обычное, не служебное (у галереи есть и служебное за экраном).
    /// `pid` — из `/ping` (не `.first`: рядом может жить безглавый экземпляр гейта); AX с коротким сроком — окно
    /// галереи не держит очередь клиента по 6 с, если её главный поток занят.
    static func raiseWindow(pid: pid_t?) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let app = apps.first(where: { $0.processIdentifier == pid }) ?? (apps.count == 1 ? apps.first : nil)
        else { return true }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AX.timeout(element, 0.3)
        guard let window = AX.elements(element, kAXWindowsAttribute)
            .first(where: { AX.string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }) else { return false }
        AX.timeout(window, 0.3)
        app.activate(options: [])
        _ = AX.set(element, kAXFrontmostAttribute, bool: true)
        _ = AX.perform(window, kAXRaiseAction)
        _ = AX.set(window, kAXMainAttribute, bool: true)
        return true
    }
}

/// Редиректы клиент не выполняет: 30x — неуспех (чужой на 47616 не уведёт путь и токен наружу).
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
