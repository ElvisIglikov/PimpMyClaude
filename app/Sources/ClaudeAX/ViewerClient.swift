import AppKit
import ApplicationServices
import Foundation
import Patcher

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
///
/// Токен — только галерее (#8302, WF259): перед каждым запросом — кто слушает порт (`viewerListens`); не PimpViewer —
/// запроса нет, прежний путь; чужой своего пользователя — ещё и без запуска и ожидания `/ping`.
public final class ViewerClient {
    public static let port: UInt16 = 47616
    public static let bundleID = "com.elvis.pimpviewer"
    static let tokenFile = "channel.token"
    /// Таймаут запроса (ТЗ: ≈300 мс) — клик из чата не должен заметно ждать галерею.
    static let timeout: TimeInterval = 0.3
    /// Таймаут `/dock` (WF277, К-DOCK-1: Пимп ждёт PimpViewer до 1,5 с): за 0,3 с занятая главная галереи давала
    /// `down`, и страница снимала кнопку.
    static let dockTimeout: TimeInterval = 1.5
    /// Таймаут `/thumb` (#10603): снимок карточки галереи берём, только если она ответила быстро, иначе — QuickLook.
    static let thumbTimeout: TimeInterval = 1.5
    /// С этой версии PimpViewer знает док (К-DOCK-2): у старой кнопки «PMP» нет.
    static let dockSince = "1.10.35"
    /// Сколько ждём `ready:true` после запуска и как часто спрашиваем.
    static let readyWait: TimeInterval = 3
    static let readyPoll: TimeInterval = 0.15
    /// Сколько после молчания запущенной галереи не ждём её `ready` снова.
    static let deadPause: TimeInterval = 30
    /// Окно галереи появляется позже ответа `/accept` — столько раз по стольку ждём его для вывода вперёд.
    static let frontTries = 5
    static let frontPause: TimeInterval = 0.15
    /// След нажатия (#10831): как часто спрашиваем `/opened` и сколько ждём ответа на каждый вопрос — страница галереи
    /// отвечает с главной, за 0,3 с занятая не успевает.
    static let openedPoll: TimeInterval = 0.2
    static let openedTimeout: TimeInterval = 1
    /// Файл следа нажатий и его хвост в строках (#10831).
    static let traceFile = "viewer-clicks.jsonl"
    static let traceLines = 300

    struct Reply {
        let status: Int
        let json: [String: Any]
        /// Тело как есть — миниатюре `/thumb` (#10603); у JSON-ручек не нужно.
        var data = Data()
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
    /// Версия запущенной галереи с диска, без запроса к ней; nil — не прочлась (тест подменяет).
    var runningVersion: () -> String? = ViewerClient.runningAppVersion
    /// Запуск в фоне без окна и фокуса (тест подменяет).
    var launch: () -> Void = ViewerClient.launchInBackground
    /// Вывод окна галереи вперёд; true — окно есть и поднято (тест подменяет).
    var raise: () -> Bool = { false }
    /// Окно галереи видно на экране (#9631; тест подменяет, умолчание тестового клиента — видно). Боевой — по списку
    /// окон Quartz без AX. Зовут с любой очереди.
    var windowShown: () -> Bool = { true }
    /// Сколько ждём окна галереи после её `{ok:true}` на «Галерею» и как часто смотрим (#9631).
    var windowWait: TimeInterval = 1.5
    static let windowPoll: TimeInterval = 0.15
    /// Сколько после окна галереи ждём, что в нём раскрыт именно этот файл (`/opened`, #10831).
    var openedWait: TimeInterval = 2
    /// Строка следа нажатия (#10831; боевой — в `viewer-clicks.jsonl`, тест подменяет). Зовут на очереди клиента.
    var trace: ([String: Any]) -> Void = { _ in }
    /// «Галерея» уже ответила странице «запускаю», а запуск не удался — повод для плашки HUD (#9631).
    /// Зовут на очереди клиента.
    public var onGalleryLate: ((GalleryOutcome) -> Void)?
    /// «▦ Галерея» или «🖼 Pimp Viewer», а приложения нет — повод для плашки. Зовут на очереди клиента.
    public var onMissing: (() -> Void)?
    /// Кто слушает порт галереи (#8302): (порт, только этот pid) → свои слушатели (`PortOwner.listeners`). Подменяют
    /// тесты и гейт против отладочной галереи; зовут на очереди клиента.
    var owners: (UInt16, pid_t?) -> [PortOwner.Holder]? = { PortOwner.listeners(port: $0, pid: $1) }
    /// Сколько верить проверенному pid галереи без обхода всех процессов, пока он слушает порт.
    var ownerTTL: TimeInterval = 5
    /// Строка в журнал (тест подменяет).
    var note: (String) -> Void = { NSLog("PimpMyClaude: %@", $0) }

    private let lock = NSLock()
    private var up = false
    private var known = true
    private var takenCount = 0
    private var refusedCount = 0
    /// Клик взят, а окно галереи так и не вышло — показали просмотром в окне чата.
    private var unshownCount = 0
    /// pid галереи из `/ping` — вывод вперёд именно её, а не безглавого экземпляра гейта (П1 WF104).
    private var viewerPID: pid_t?
    /// Запущено, а канал молчит — до этой поры не ждём `ready` на каждом клике (П1 WF104).
    private var deadUntil: Date?
    /// Последний запуск: второй запрос в эти 3 с не зовёт `openApplication` снова — иначе reopen покажет окно.
    private var launchedAt: Date?
    /// #8302, только на очереди клиента: проверенный pid галереи, последний отказ чужаку (журнал — раз на состав),
    /// последний полный обход нашёл на порту чужого своего пользователя.
    private var knownViewer: (pid: pid_t, at: Date)?
    private var refusedNote: String?
    private var foreignHolds = false

    /// Боевой клиент: склад — `PIMP_VIEWER_STORE` (гейт), иначе `MyClaude/viewer`.
    public convenience init() {
        let custom = ViewerClient.customStore
        self.init(port: ViewerClient.port,
                  tokenURL: (custom ?? ViewerClient.defaultStore).appendingPathComponent(ViewerClient.tokenFile),
                  launches: custom == nil)
        raise = { [weak self] in ViewerClient.raiseWindow(pid: self?.currentPID) }
        windowShown = { [weak self] in ViewerClient.windowOnScreen(pid: self?.currentPID) }
        let traceURL = (custom ?? SupportFiles.directory).appendingPathComponent(ViewerClient.traceFile)
        trace = { ViewerClient.appendTrace($0, to: traceURL) }
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

    /// `viewer=<up|down|none>/<принято>/<отказов>`: `none` — PimpViewer.app не установлен; `+N` — клики, взятые без
    /// окна галереи (показаны просмотром в окне чата).
    public var status: String {
        lock.lock(); defer { lock.unlock() }
        return "\(up ? "up" : known ? "down" : "none")/\(takenCount)/\(refusedCount)" + (unshownCount > 0 ? "+\(unshownCount)" : "")
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
        let started = Date()
        call(target, starting: true) { [self] reply in
            let taken = reply?.status == 200 && reply?.json["taken"] as? Bool == true
            let opened = reply?.json["opened"] as? Bool
            lock.lock()
            if taken { takenCount += 1 } else { refusedCount += 1 }
            lock.unlock()
            if taken, reply?.json["focus"] as? Bool == true { bringFront() }
            // Исход — сиденью, след — только у нажатия человека (#10831).
            let finish = { [self] (window: Bool?, file: FileVerdict, result: Bool) in
                done(result)
                guard mode == .click else { return }
                traceClick(via: "gallery", path: path, chat: chat, taken: taken, opened: opened, window: window,
                           file: file, fallback: !result, since: started)
            }
            // Клик человека из чата (слово Элвиса 22.10.2026: файл «открывается только со второго нажатия»): галерея
            // ответила «взяла», но окно показывает сама и не всегда — чат ей ещё не известен (тогда файл только в
            // ленту), окно выгружено и грузится, галерея проснулась позже. Окна за `windowWait` так и нет — не молчим:
            // `false`, и сиденье покажет страницу просмотром в окне чата (`HtmlChromeOpener.fallBack`).
            guard taken, mode == .click, chat != nil else { return finish(nil, .unknown, taken) }
            // PimpViewer с #10531 сам говорит, выйдет ли окно (`opened`): `false` — сразу просмотр в окне чата, без 1,5 с.
            if opened == false {
                lock.lock()
                unshownCount += 1
                lock.unlock()
                note("галерея взяла клик без окна (opened:false) — файл открываю просмотром в окне чата")
                return finish(nil, .unknown, false)
            }
            waitWindow(until: Date().addingTimeInterval(windowWait)) { [self] shown in
                guard shown else {
                    lock.lock()
                    unshownCount += 1
                    lock.unlock()
                    note("галерея взяла клик, а окна не показала — файл открываю просмотром в окне чата")
                    return finish(false, .unknown, false)
                }
                // Окно есть — ещё не файл (#10831): загруженная страница галереи к сроку так его и не раскрыла —
                // тоже просмотр в окне чата. Грузится, выгружена, старая галерея без `/opened` — как было, взяла.
                checkOpened(path: path, until: Date().addingTimeInterval(openedWait)) { [self] file in
                    guard file == .missed else { return finish(true, file, true) }
                    lock.lock()
                    unshownCount += 1
                    lock.unlock()
                    note("галерея показала окно, а файл в нём не раскрыла — файл открываю просмотром в окне чата")
                    finish(true, .missed, false)
                }
            }
        }
    }

    /// Файл в док (WF277, К-DOCK-2 `/accept … dock=1&win&x&y&w&h`): галерея встаёт в док над местом окна Claude, если
    /// ещё не стоит, и открывает файл в слое — без смены стола и фокуса. Окна галереи не ждём: док — не оно.
    /// `done(taken, opened)` — на очереди клиента; не достучались — `(false, false)`, у сиденья прежний путь.
    /// Взят без файла (`opened:false`) — тоже прежний путь у сиденья (#10831) и счёт `+N`.
    public func accept(path: String, chat: String?, dock: MaterialsDock.Spot,
                       done: @escaping (_ taken: Bool, _ opened: Bool) -> Void) {
        var target = "/accept?mode=click&path=\(ViewerClient.encode(path))"
        if let chat = chat { target += "&chat=\(ViewerClient.encode(chat))" }
        let started = Date()
        call(target + "&dock=1" + dock.query, starting: true) { [self] reply in
            let taken = reply?.status == 200 && reply?.json["taken"] as? Bool == true
            let said = reply?.json["opened"] as? Bool
            let opened = taken && said != false
            lock.lock()
            if taken { takenCount += 1 } else { refusedCount += 1 }
            if taken, !opened { unshownCount += 1 }
            lock.unlock()
            // Старая галерея дока не знает и берёт клик как раньше — её окно вперёд, как у `accept(mode:)`.
            if taken, reply?.json["focus"] as? Bool == true { bringFront() }
            if taken, !opened { note("галерея взяла клик в док без файла (opened:false) — файл открываю как раньше") }
            done(taken, opened)
            // След (#10831): исход уже ушёл, `/opened` здесь — только для журнала.
            guard opened else {
                return traceClick(via: "dock", path: path, chat: chat, taken: taken, opened: said, window: nil,
                                  file: .unknown, fallback: true, since: started)
            }
            checkOpened(path: path, until: Date().addingTimeInterval(openedWait)) { [self] file in
                traceClick(via: "dock", path: path, chat: chat, taken: taken, opened: said, window: nil,
                           file: file, fallback: false, since: started)
            }
        }
    }

    /// Что галерея сказала о файле нажатия (`/opened`, #10831): раскрыт; к сроку так и не раскрыт загруженной
    /// страницей; страница грузится или выгружена; не знаем (старая галерея, ответ без `open`, молчит).
    enum FileVerdict: String { case open, missed, loading, unknown }

    /// Раскрыт ли этот файл в странице галереи (К-V8 `/opened`): раз в `openedPoll` до срока; `unknown` — сразу.
    /// Без запуска галереи и без сна, на очереди клиента.
    private func checkOpened(path: String, until deadline: Date, done: @escaping (FileVerdict) -> Void) {
        get("/opened?path=\(ViewerClient.encode(path))", timeout: ViewerClient.openedTimeout) { [self] reply in
            guard let reply = reply, reply.status == 200, reply.json["known"] as? Bool != false,
                  let open = reply.json["open"] as? Bool else { return done(.unknown) }
            if open { return done(.open) }
            let ready = reply.json["loaded"] as? Bool == true && reply.json["parked"] as? Bool != true
            guard Date() < deadline else { return done(ready ? .missed : .loading) }
            queue.asyncAfter(deadline: .now() + ViewerClient.openedPoll) { [self] in
                checkOpened(path: path, until: deadline, done: done)
            }
        }
    }

    /// След нажатия по файлу (#10831) — строкой в `viewer-clicks.jsonl`: когда, куда (`gallery|dock`), что ответила
    /// галерея, вышло ли окно, раскрыт ли файл, ушло ли сиденью «показать самим», сколько мс заняло.
    private func traceClick(via: String, path: String, chat: String?, taken: Bool, opened: Bool?, window: Bool?,
                            file: FileVerdict, fallback: Bool, since started: Date) {
        let stamp = ISO8601DateFormatter()
        stamp.timeZone = .current
        trace(["at": stamp.string(from: started), "via": via, "path": path, "chat": chat ?? NSNull(), "taken": taken,
               "opened": opened ?? NSNull(), "window": window ?? NSNull(), "file": file.rawValue, "fallback": fallback,
               "ms": Int(Date().timeIntervalSince(started) * 1000)])
    }

    /// Строка в конец файла следа; файл держим коротким — хвост в `traceLines` строк, права 0600.
    static func appendTrace(_ line: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return }
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        lines.append(String(decoding: data, as: UTF8.self))
        SupportFiles.writeAtomic(url, Data((lines.suffix(traceLines).joined(separator: "\n") + "\n").utf8))
    }

    /// Путь файла чата по имени (#10699, К-V8 `GET /resolve?chat=<local_…>&name=<enc>` → `{ok, path, kind}`): ролик или
    /// картинка-вложение Claude в ленте — с диска. Без запуска галереи; `done(path)` — раз, на очереди клиента; не нашла,
    /// молчит, старая (404) или ответ без абсолютного пути — nil. Проверки пути — у сиденья (`HtmlChromeOpener.locateMedia`).
    public func resolve(chat: String, name: String, done: @escaping (String?) -> Void) {
        call("/resolve?chat=\(ViewerClient.encode(chat))&name=\(ViewerClient.encode(name))", starting: false) { reply in
            guard let reply = reply, reply.status == 200, reply.json["ok"] as? Bool == true,
                  let path = reply.json["path"] as? String, path.hasPrefix("/") else { return done(nil) }
            done(path)
        }
    }

    /// Снимок страницы как у карточки галереи (#10603, К-V8 `GET /thumb?path=<enc>` → `200 image/jpeg` 480×360, верх
    /// карточки 4:3, или `404`). Слово Элвиса 22.10.2026: «превьюшки сделать HTML… как в PimpViewer». Без запуска
    /// галереи и без её окна, таймаут `thumbTimeout`; `done` — раз, на очереди клиента: не 200, не JPEG (нет FF D8),
    /// молчит — nil, и у сиденья прежний путь (QuickLook).
    public func thumb(path: String, done: @escaping (Data?) -> Void) {
        call("/thumb?path=\(ViewerClient.encode(path))", starting: false, timeout: ViewerClient.thumbTimeout) { reply in
            guard let reply = reply, reply.status == 200, reply.data.count > 3,
                  reply.data[reply.data.startIndex] == 0xFF, reply.data[reply.data.startIndex + 1] == 0xD8 else { return done(nil) }
            done(reply.data)
        }
    }

    /// Место дока (WF277, К-DOCK-2 `/dock`) — без запуска галереи, таймаут `dockTimeout`. `done` — ровно раз, на очереди
    /// клиента.
    public func dock(_ command: MaterialsDock.Command, done: @escaping (MaterialsDock.Reply) -> Void) {
        call(ViewerClient.dockTarget(command), starting: false, timeout: ViewerClient.dockTimeout) { [self] reply in
            let viewer: MaterialsDock.Viewer = reply?.status == 200 ? .up : reply == nil && !installed() ? .none : .down
            done(MaterialsDock.Reply(viewer: viewer, docked: viewer == .up && reply?.json["docked"] as? Bool == true))
        }
    }

    /// Жив ли PimpViewer для кнопки «PMP» (WF277, `/dock?probe=1`) — без запроса к галерее: проверка не трогает её док
    /// (`on=0` снимал док другого окна). Не установлена — `none`; запущена и знает док (`dockSince`, версия не прочлась
    /// или не числами — знает) — `up`; иначе `down`. `done` — на очереди клиента.
    public func dockProbe(done: @escaping (MaterialsDock.Viewer) -> Void) {
        queue.async { [self] in
            guard installed() else { return done(.none) }
            guard running() else { return done(.down) }
            let old = runningVersion().flatMap { ClaudeUpdater.compareVersions($0, ViewerClient.dockSince) } == .orderedAscending
            done(old ? .down : .up)
        }
    }

    /// Версия запущенной PimpViewer.app — из её Info.plist на диске (кэш `Bundle` не держит старую после обновления).
    static func runningAppVersion() -> String? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    /// `/dock?on=1&vis=<0|1>&win&x&y&w&h` | `/dock?on=0`. Чистая.
    static func dockTarget(_ command: MaterialsDock.Command) -> String {
        guard let spot = command.spot else { return "/dock?on=0" }
        return "/dock?on=1&vis=\(command.vis ? 1 : 0)" + spot.query
    }

    /// Исход нажатия «Галерея» (#9631, жалоба коллеги 10.10: «нажимаю и ничего не открывается»): его слово уходит
    /// странице ответом на `/viewer`, и она говорит человеку, что вышло. Молчать нельзя.
    public enum GalleryOutcome: String {
        /// Галерея взяла фильтр «этот чат», и её окно на экране.
        case opened
        /// Фильтр снят: кнопка горела, окно галереи видно.
        case off
        /// PimpViewer не был запущен — запускаем; окно выйдет само.
        case launching
        /// Галерея ответила, а её окна на экране нет (чат ей неизвестен или окно на другом столе).
        case noWindow = "no-window"
        /// PimpViewer.app не установлен.
        case missing
        /// Порт галереи 47616 держит чужая программа (#8302).
        case foreign
        /// Нет ключа канала `channel.token`.
        case noToken = "no-token"
        /// Установлен, а не ответил.
        case silent
        /// Ответил отказом.
        case refused

        /// Галерея открылась, закрылась или открывается — остальное отказ.
        public var ok: Bool { self == .opened || self == .off || self == .launching }
    }

    /// Кнопка «Галерея» в чате (К-V1 `/viewer`). `done` — исход, ровно один раз, на очереди клиента. Горит кнопка
    /// (`on=0`), а окна галереи не видно (закрыли красной кнопкой, фильтр остался) — нажатие открывает, а не гасит.
    /// `windowShown` здесь зовётся на очереди того, кто нажал (порт 47615), — только список окон Quartz.
    public func gallery(chat: String, on: Bool, done: @escaping (GalleryOutcome) -> Void = { _ in }) {
        // Без лишнего прыжка на очередь: запрос встаёт в неё тем же порядком, что и раньше (`call`).
        let on = on || !windowShown()
        var answered = false
        let answer = { (outcome: GalleryOutcome) in
            guard !answered else { return }
            answered = true
            done(outcome)
        }
        call("/gallery?chat=\(ViewerClient.encode(chat))&on=\(on ? 1 : 0)", starting: true,
             launched: { answer(.launching) }) { [self] reply in
            let finish = { (outcome: GalleryOutcome) in
                if answered { if !outcome.ok { self.onGalleryLate?(outcome) } } else { answer(outcome) }
            }
            guard let reply = reply else { return finish(downReason()) }
            guard reply.status == 200 else { return finish(.refused) }
            guard on else { return finish(.off) }
            // `{ok:true}` ещё не окно: неизвестный галерее чат она молча пропускает (К-V8 `/gallery`).
            waitWindow(until: Date().addingTimeInterval(windowWait)) { finish($0 ? .opened : .noWindow) }
        }
    }

    /// Почему галерея не ответила. На очереди клиента.
    private func downReason() -> GalleryOutcome {
        if !installed() { return .missing }
        if foreignHolds { return .foreign }
        if ViewerClient.readToken(at: tokenURL) == nil { return .noToken }
        return .silent
    }

    /// Окно галереи на экране — сразу или в пределах срока, без сна на очереди.
    private func waitWindow(until deadline: Date, done: @escaping (Bool) -> Void) {
        if windowShown() { return done(true) }
        guard Date() < deadline else { return done(false) }
        queue.asyncAfter(deadline: .now() + ViewerClient.windowPoll) { [self] in waitWindow(until: deadline, done: done) }
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
    /// `launched` — PimpViewer.app запущен этим запросом (#9631: страница слышит «запускаю» сразу).
    private func call(_ target: String, starting: Bool, missing: Bool = false, launched: (() -> Void)? = nil,
                      timeout: TimeInterval = ViewerClient.timeout, done: @escaping (Reply?) -> Void) {
        queue.async { [self] in
            get(target, timeout: timeout) { [self] reply in
                guard reply == nil, starting else { return done(reply) }
                waitReady(launched: launched) { [self] ready in
                    guard ready else {
                        if missing, !known { onMissing?() }
                        return done(nil)
                    }
                    get(target, timeout: timeout, done: done)
                }
            }
        }
    }

    /// Запустить (если можно и нужно) и до 3 с ждать `/ping` с `ready:true`. На очереди клиента, без сна.
    private func waitReady(launched: (() -> Void)? = nil, done: @escaping (Bool) -> Void) {
        let installed = installed()
        lock.lock()
        known = installed
        lock.unlock()
        let now = Date()
        if let dead = deadUntil, now < dead { return done(false) }
        // Порт держит чужой (#8302): галерея на занятый порт не встанет — не запускать и `/ping` не ждать.
        if !viewerListens(), foreignHolds { return done(false) }
        let isRunning = running()
        if !isRunning {
            guard launches, installed else { return done(false) }
            if launchedAt.map({ now.timeIntervalSince($0) >= ViewerClient.readyWait }) ?? true {
                launchedAt = now
                launch()
                launched?()
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
    private func get(_ target: String, timeout: TimeInterval = ViewerClient.timeout, done: @escaping (Reply?) -> Void) {
        if token == nil { token = ViewerClient.readToken(at: tokenURL) }
        send(target, timeout: timeout) { [self] reply in
            guard reply?.status == 403 else { return finish(reply, done) }
            token = ViewerClient.readToken(at: tokenURL)
            send(target, timeout: timeout) { [self] in finish($0, done) }
        }
    }

    private func finish(_ reply: Reply?, _ done: (Reply?) -> Void) {
        lock.lock()
        // Ответила — жива: 404 у `/thumb` и `/resolve` значит «нет снимка, нет файла», не «галерея упала» (#10603) —
        // иначе счёт «Галереи» теряет тик до `/ping`. Не жива для счёта — молчит, чужой токен (403), не готова (503).
        up = reply.map { $0.status != 403 && $0.status != 503 } ?? false
        if up { known = true }
        if up, let pid = reply?.json["pid"] as? NSNumber { viewerPID = pid_t(pid.int32Value) }
        lock.unlock()
        done(reply)
    }

    /// Где живёт галерея: только её программе из `/Applications` или `~/Applications` уходит токен (#8302).
    static func viewerPaths(home: String = NSHomeDirectory()) -> Set<String> {
        Set(["/Applications", home + "/Applications"].map { $0 + "/PimpViewer.app/Contents/MacOS/PimpViewer" })
    }

    /// Порт слушает галерея: свой слушатель есть, и все свои слушатели порта — программа PimpViewer.
    static func isViewer(_ holders: [PortOwner.Holder]?, paths: Set<String> = viewerPaths()) -> Bool {
        guard let holders = holders, !holders.isEmpty else { return false }
        return holders.allSatisfy { paths.contains($0.path) }
    }

    /// Перед каждым запросом с токеном (#8302, как `PimpClient.pimpListens` у PimpViewer): порт слушает галерея?
    /// Проверенный не дольше `ownerTTL` назад pid галереи, всё ещё слушающий порт, — без обхода (доли мс); иначе обход
    /// своих процессов (3–6 мс на ~470) — таймауту 300 мс не помеха. Чужой или никого своего — запрос не идёт; чужой —
    /// строка в журнал, раз на состав слушателей. На очереди клиента.
    func viewerListens() -> Bool {
        if let known = knownViewer, Date().timeIntervalSince(known.at) < ownerTTL,
           ViewerClient.isViewer(owners(port, known.pid)) { return true }
        knownViewer = nil
        let holders = owners(port, nil)
        foreignHolds = false
        if ViewerClient.isViewer(holders), let pid = holders?.first?.pid {
            knownViewer = (pid, Date())
            refusedNote = nil
            return true
        }
        if let holders = holders, !holders.isEmpty {
            foreignHolds = true
            let list = holders.map { "pid \($0.pid) \($0.path.isEmpty ? "?" : $0.path)" }.joined(separator: ", ")
            if list != refusedNote { note("порт галереи \(port) слушает не PimpViewer (\(list)) — токен не шлю") }
            refusedNote = list
        }
        return false
    }

    private func send(_ target: String, timeout: TimeInterval, done: @escaping (Reply?) -> Void) {
        guard let token = token, let url = URL(string: "http://127.0.0.1:\(port)" + target),
              viewerListens() else { return done(nil) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue(token, forHTTPHeaderField: "X-Pimp-Viewer-Token")
        session.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse else { return done(nil) }
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            done(Reply(status: http.statusCode, json: json, data: data ?? Data()))
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

    /// Окно галереи видно (#9631): обычный слой, не крошка, и хоть краем на экране — служебное окно за краем экранов
    /// не в счёт. Только Quartz (pid, слой, рамка) — без AX и без права записи экрана. `pid` — из `/ping`; нет его —
    /// любой запущенный PimpViewer.
    static func windowOnScreen(pid: pid_t?) -> Bool {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map { $0.processIdentifier })
        let wanted = pid.map { pids.contains($0) ? [$0] : pids } ?? pids
        guard !wanted.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &count) == .success else { return false }
        let screens = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
        return list.contains { info in
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, wanted.contains(owner),
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 100, rect.height >= 100 else { return false }
            return screens.contains { $0.intersects(rect) }
        }
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
