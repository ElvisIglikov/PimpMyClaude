import AppKit
import Foundation
import Network

/// HTML-файлы из чата — в Chrome, а не в панель Browser у Claude (#6618; слово Элвиса 20.09.2026:
/// «одно нажатие на HTML-ку открывает его в Хроме… если файл уже открыт — вкладки новые не открывал,
/// ту же открытую показывал»).
///
/// Страница (`inject.js`, раздел 12д) просит об этом запросом на свой же Мак:
/// `GET http://127.0.0.1:47615/open-html?mode=<click|view|browser>&path=<путь в percent-encoding>`.
/// Другого быстрого пути от страницы к приложению нет: канал probe отвечает за 15 с, а буфер обмена
/// занят человеком. Слушаем ТОЛЬКО 127.0.0.1, берём только существующий `.html`/`.htm` с абсолютным
/// путём — худшее, что может чужая страница, это показать Элвису его же файл.
///
/// Chrome ведём AppleScript'ом через `/usr/bin/osascript`: вкладка с этим файлом есть — `click`
/// выводит её вперёд и перечитывает; вкладки нет — открываем новую и
/// выводим Chrome вперёд. macOS один раз спросит «PimpMyClaude хочет управлять Google Chrome».
/// Скрипт не прошёл (нет разрешения) — файл открывается в Chrome обычным путём, новой вкладкой.
public final class HtmlChromeOpener {
    public static let port: UInt16 = 47615
    public static let chromeBundleID = "com.google.Chrome"
    public static let vivaldiBundleID = "com.vivaldi.Vivaldi"
    /// Браузеры на Chromium: у них одинаковый AppleScript вкладок — ищем уже открытую (слово Элвиса
    /// 20.09.2026: «вкладки новые не открывал»). Bundle id → имя приложения для `tell application`.
    static let chromiumNames: [String: String] = [
        vivaldiBundleID: "Vivaldi",
        chromeBundleID: "Google Chrome",
        "com.brave.Browser": "Brave Browser",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge",
        "org.chromium.Chromium": "Chromium",
    ]

    /// Чем открыть страницу (WF108, #8146): браузер — системный по умолчанию для https (у Элвиса Vivaldi).
    enum BrowserRoute: Equatable {
        /// Chromium: AppleScript ищет открытую вкладку, иначе новая.
        case script(name: String, app: URL)
        /// Другой браузер (Safari, Firefox…): просто открыть файл в нём.
        case open(app: URL)
        /// Браузера по умолчанию нет — программе для типа файла.
        case system
    }

    /// Чистая, её гоняют тесты: `app` и `bundleID` — браузер по умолчанию для https.
    static func route(app: URL?, bundleID: String?) -> BrowserRoute {
        guard let app = app else { return .system }
        if let bundleID = bundleID, let name = chromiumNames[bundleID] { return .script(name: name, app: app) }
        return .open(app: app)
    }

    /// Браузер по умолчанию для https — не программа для `.html` (та бывает Safari или Xcode).
    static var browserRoute: BrowserRoute {
        let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        return route(app: app, bundleID: app.flatMap { Bundle(url: $0)?.bundleIdentifier })
    }
    public static let previewBundleID = "com.apple.Preview"
    /// Страницы и PDF — в Chrome, картинки — в «Просмотр» (#6621).
    public static let chromeExtensions: Set<String> = ["html", "htm", "pdf"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"]

    /// `view` (WF103) — файл в окне просмотра поверх монитора чата (`FileView`); только html/htm.
    /// `browser` (WF107): пункт «🌐 Открыть в браузере» — сразу браузер, мимо галереи.
    public enum Mode: String { case click, view, browser }
    public struct Request: Equatable {
        public let path: String
        public let mode: Mode
        /// Чат, откуда клик (`local_…`, WF97 К-V1); страница не знает — nil.
        public var chat: String? = nil
        /// Рамка окна чата (WF103, `view`): пункты, начало — левый верхний угол главного экрана,
        /// `x`,`y` со знаком. Мусор или нет ключа — nil.
        public var frame: CGRect? = nil
        /// Фон темы окна чата — 6 hex без `#`, строчными. Мусор или нет ключа — nil.
        public var bg: String? = nil
    }

    /// Кнопка «Галерея» в чате (WF97 К-V1): `/viewer?chat=<local_…>&on=1|0`.
    public struct ViewerRequest: Equatable {
        public let chat: String
        public let on: Bool
    }

    /// PimpViewer.app берёт html и фото себе (WF97, выбор 4; с WF104 — через `ViewerClient`, К-V8):
    /// `done(true)` — взял, браузер не нужен. Зовут на очереди порта, ответ — на очереди клиента: порт не ждёт.
    public var toViewer: ((Request, @escaping (Bool) -> Void) -> Void)?
    /// Кнопка «Галерея». Зовут на очереди порта.
    public var onViewer: ((ViewerRequest) -> Void)?
    /// Толчок галереи `/viewer-nudge` (К-V8): разослать страницам фильтр (`chat`) и/или счёт (`counts`).
    /// Зовут на очереди порта, ответ `204` уже ушёл.
    public var onNudge: ((_ chat: Bool, _ counts: Bool) -> Void)?
    /// «в чат» из галереи `/viewer-open-chat` (К-V8): `local_…` (nil — мусорный) → `reply("ok"|"chat-closed")`
    /// с любой очереди; соединение держится до ответа. Зовут на очереди порта.
    public var onOpenChat: ((String?, @escaping (String) -> Void) -> Void)?
    /// Токен канала галереи — перечитывается на каждом запросе `/viewer-*`: PimpViewer.app создаёт его
    /// уже после старта Пимпа. Тест подставляет свой.
    var channelToken: () -> String? = { ViewerClient.readToken(at: ViewerClient.tokenURL) }
    /// Заголовок `/viewer-*` дочитываем до конца, но не больше и не дольше этого.
    static let maxHead = 16 * 1024
    static let readTimeout: TimeInterval = 5
    /// Принятый `view` (WF103) — показать файл в окне просмотра. Зовут на очереди порта;
    /// nil — `view` не принимается, идёт прежним `click`.
    public var onView: ((Request) -> Void)?
    /// Знает ли индекс чатов этот `local_…` (контракт волны 1 WF103: чужая страница его не угадает).
    /// Зовут на очереди порта; nil — не знает никого.
    public var isKnownChat: ((String) -> Bool)?
    /// Часы ограничения `view` (1 в секунду) — тест подставляет свои.
    var now: () -> Date = Date.init
    /// Вместо браузера (тесты): куда ушёл бы запрос. nil — живой путь через `openQueue`.
    var browserSeam: ((Request) -> Void)?
    /// Не чаще одного `view` в секунду.
    static let viewInterval: TimeInterval = 1
    private var lastViewAt: Date?
    private var viewRejectedCount = 0
    /// Сколько `view` не принято: прежним `click` (нет чата, чужой чат, окно не подключено) или
    /// молча (чаще 1/с).
    public var viewRejected: Int { counters.lock(); defer { counters.unlock() }; return viewRejectedCount }

    /// «📋 Копировать в буфер» (WF106 #8102): `/copy-file?path=<enc>&chat=<local_…>` прошёл проверки
    /// (`acceptsCopyFile`) — путь к файлу (симлинки раскрыты). Зовут на очереди порта: буфер и плашка — на главной.
    public var onCopyFile: ((String) -> Void)?
    /// Кнопка «PMP» в окне Claude (WF125 #8894): `GET /panel` — открыть панель у часов. Зовут на очереди порта.
    public var onPanel: (() -> Void)?
    /// Сводка проектов для ячеек Workflow в поле Рика (WF133, К6): `GET /digest` → `200` JSON, не чаще раза в 10 с.
    let digest = ProjectsDigestCache()
    /// Холодный чат просит число токенов (WF106 #8103): `/context?chat=<local_…>` → `local_…`. Зовут на очереди порта.
    public var onContext: ((String) -> Void)?
    /// Размер шрифта поля (WF107 К2): `/composer-font?px=<N|none>&chat=<local_…>` от чата, известного индексу.
    /// Зовут на очереди порта: зеркало и меню — на главной.
    var onComposerFont: ((ComposerFont.Ping) -> Void)?
    /// Домашняя папка для `CopyFileRelay.isRefused` — тест подставляет свою.
    var home: String = FileManager.default.homeDirectoryForCurrentUser.path
    private var copiedCount = 0
    private var copyRefusedCount = 0
    /// `copy=<положил>/<отказ>` для строки диагностики.
    public var copyStatus: String {
        counters.lock(); defer { counters.unlock() }
        return "\(copiedCount)/\(copyRefusedCount)"
    }

    /// Скрипт не прошёл — повод для плашки.
    public var onScriptFailed: (() -> Void)?
    public var opened: Int { counters.lock(); defer { counters.unlock() }; return openedCount }
    public var failed: Int { counters.lock(); defer { counters.unlock() }; return failedCount }
    private var openedCount = 0
    private var failedCount = 0
    private let counters = NSLock()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pimpmyclaude.html-chrome")
    /// Браузер ведём на своей очереди (z5-r07): osascript ждёт окна согласия или зависшего браузера,
    /// а порт тем временем отвечает — «Галерея» и клики по файлам не молчат.
    private let openQueue = DispatchQueue(label: "pimpmyclaude.html-chrome.open", qos: .userInitiated)
    /// «📋 Копировать в буфер»: проверки пути и индекса — здесь, не на очереди порта.
    private let copyQueue = DispatchQueue(label: "pimpmyclaude.html-chrome.copy", qos: .userInitiated)
    /// Дождаться принятых `/copy-file` — тестам.
    func drainCopies() { copyQueue.sync {} }

    public init() {}

    /// `html=<открыл>/<скрипт не прошёл>` для строки диагностики.
    public var status: String { "\(opened)/\(failed)" }

    public func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Не приславшего заголовок за 5 с — прочь; дочитали — ждём сколько надо (`/viewer-open-chat`).
        let timeout = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + Self.readTimeout, execute: timeout)
        receive(connection, head: Data(), timeout: timeout)
    }

    private func receive(_ connection: NWConnection, head: Data, timeout: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxHead) { [weak self] data, _, done, error in
            guard let self = self else { return connection.cancel() }
            var bytes = head
            if let data = data { bytes.append(data) }
            let text = String(decoding: bytes, as: UTF8.self)
            // Ручки галереи — до `\r\n\r\n` (Host и токен могут прийти вторым пакетом); строку запроса — всегда.
            let channel = Self.isChannel(text)
            if !text.contains("\r\n\r\n"), bytes.count < Self.maxHead, !done, error == nil {
                return self.receive(connection, head: bytes, timeout: timeout)
            }
            timeout.cancel()
            if channel { return self.serveChannel(text, connection) }
            self.serveOld(text, connection)
        }
    }

    /// Полный заголовок проверяется до открытия файла, команды странице или изменения буфера.
    private func serveOld(_ head: String, _ connection: NWConnection) {
        let access = Self.checkPage(head, token: channelToken())
        if access.performsAction, Self.parseDigest(head) {
            return digest.get { [queue] body in
                queue.async {
                    connection.send(content: Self.digestResponse(body, access: access),
                                    completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        if access.performsAction, Self.parseKickoff(head) {
            return connection.send(content: Self.kickoffResponse(WorkflowKit.kickoff(), access: access),
                                   completion: .contentProcessed { _ in connection.cancel() })
        }
        connection.send(content: Self.pageResponse(access), completion: .contentProcessed { _ in
            connection.cancel()
        })
        if access.performsAction { performOld(head) }
    }

    /// Тот же вход без сетевого соединения — для поведенческих тестов границы доверия.
    func handleOld(_ head: String) {
        guard Self.checkPage(head, token: channelToken()).performsAction else { return }
        performOld(head)
    }

    private func performOld(_ head: String) {
        if let request = Self.parseCopyFile(head) {
            // Проверки трогают диск и индекс (main.sync) — не на очереди порта: она одна на все ручки
            // (гейт WF106: вопрос TCC на файле с рабочего стола держал порт, «Галерея» молчала).
            copyQueue.async { [weak self] in
                guard let self = self else { return }
                let path = self.acceptsCopyFile(request)
                self.counters.lock()
                if path == nil { self.copyRefusedCount += 1 } else { self.copiedCount += 1 }
                self.counters.unlock()
                if let path = path { self.onCopyFile?(path) }
            }
        } else if let chat = Self.parseContext(head) {
            onContext?(chat)
        } else if let ping = ComposerFont.parse(head) {
            if isKnownChat?(ping.chat) == true { onComposerFont?(ping) }
        } else if let viewer = Self.parseViewer(head) {
            onViewer?(viewer)
        } else if Self.parsePanel(head) {
            onPanel?()
        } else if let request = Self.parse(head), Self.isPage(request.path) {
            route(request)
        }
    }

    // MARK: - ручки галереи (К-V8, WF104)

    /// Галерея → Пимп: `/viewer-nudge`, `/viewer-open-chat`, `/viewer-open-browser`. Проверки — `checkChannel`,
    /// ответы без `Access-Control-*`; успех несёт `X-Pimp-Viewer: 1` (по нему галерея узнаёт Пимп фазы Б).
    private func serveChannel(_ head: String, _ connection: NWConnection) {
        let reply = { [queue] (status: Int, body: String?) in
            queue.async {
                connection.send(content: Self.channelResponse(status: status, body: body),
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        switch Self.checkChannel(head, token: channelToken()) {
        case .reject(let status):
            reply(status, nil)
        case .nudge(let chat, let counts):
            reply(204, nil)
            onNudge?(chat, counts)
        case .openChat(let chat):
            guard let open = onOpenChat else { return reply(200, "chat-closed") }
            open(chat) { reply(200, $0) }
        case .openBrowser(let path):
            guard Self.isPage(path) else { return reply(400, nil) }
            openInBrowser(path)
            reply(204, nil)
        }
    }

    /// Разбор запроса к ручкам галереи.
    enum ChannelVerdict: Equatable {
        case reject(Int)
        case nudge(chat: Bool, counts: Bool)
        /// nil — мусорный `chat`: ответ `chat-closed`.
        case openChat(String?)
        case openBrowser(String)
    }

    /// Путь строки запроса начинается с `/viewer-` (прежний `/viewer?chat=` — не он).
    static func isChannel(_ head: String) -> Bool {
        let line = head.prefix { $0 != "\r" && $0 != "\n" }
        let parts = line.split(separator: " ")
        return parts.count >= 2 && parts[1].hasPrefix("/viewer-")
    }

    /// Порядок К-V8, как на 47616: заголовок целиком → `Host` → токен (постоянное время) → OPTIONS 403,
    /// не GET — 405 → ручка (неизвестная — 404) и ключи (плохие — 400). Чистая, её и гоняют тесты.
    static func checkChannel(_ head: String, token: String?) -> ChannelVerdict {
        guard let end = head.range(of: "\r\n\r\n") else { return .reject(400) }
        let lines = head[..<end.lowerBound].components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), !parts[0].isEmpty, parts[1].hasPrefix("/")
        else { return .reject(400) }
        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .reject(400) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name, default: []].append(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        guard let host = headers["host"], host.count == 1,
              ["127.0.0.1:\(port)", "localhost:\(port)"].contains(host[0].lowercased()) else { return .reject(403) }
        guard let token = token, let given = headers["x-pimp-viewer-token"], given.count == 1,
              constantTimeEqual(given[0], token) else { return .reject(403) }
        guard parts[0] != "OPTIONS" else { return .reject(403) }
        guard parts[0] == "GET" else { return .reject(405) }
        guard let components = URLComponents(string: "http://127.0.0.1" + parts[1]) else { return .reject(400) }
        let value = { (name: String) in components.queryItems?.first(where: { $0.name == name })?.value }
        switch components.path {
        case "/viewer-nudge":
            let what = value("what")
            return .nudge(chat: what != "counts", counts: what != "chat")
        case "/viewer-open-chat":
            return .openChat(chatID(value("chat")))
        case "/viewer-open-browser":
            guard let path = value("path"), acceptsPath(path) else { return .reject(400) }
            return .openBrowser(path)
        default:
            return .reject(404)
        }
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<y.count { diff |= (i < x.count ? x[i] : 0) ^ y[i] }
        return diff == 0
    }

    /// Ответ ручки галереи: `Content-Length` (кроме 204 — RFC 9110 §8.6), `no-store`, `Connection: close`, ни одного
    /// `Access-Control-*`; `X-Pimp-Viewer: 1` — только на успехе (204 и 200), тело — `text/plain`.
    static func channelResponse(status: Int, body: String?) -> Data {
        let payload = Data((body ?? "").utf8)
        let text = [200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                    405: "Method Not Allowed"][status] ?? "Error"
        var head = "HTTP/1.1 \(status) \(text)\r\n"
        if status == 200 || status == 204 { head += "X-Pimp-Viewer: 1\r\n" }
        if body != nil { head += "Content-Type: text/plain; charset=utf-8\r\n" }
        if status != 204 { head += "Content-Length: \(payload.count)\r\n" }
        head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + payload
    }

    /// PDF — всегда в браузер; html и фото — в галерею, если она взяла (К-V1), иначе `fallBack` (WF107 К3) —
    /// из ответа галереи, порт его не ждёт. `view` (WF103): принят — сразу окно просмотра и галерее
    /// по-настоящему тихо (`view`, WF104; браузера нет при любом ответе); не принят — дальше как `click`.
    func route(_ request: Request) {
        var request = request
        if request.mode == .browser {
            return openBrowser(Request(path: request.path, mode: .click, chat: request.chat))
        }
        if request.mode == .view {
            let verdict = acceptsView(request)
            if verdict == .accept {
                onView?(request)
                toViewer?(Request(path: request.path, mode: .view, chat: request.chat)) { _ in }
                return
            }
            counters.lock()
            viewRejectedCount += 1
            counters.unlock()
            // Чаще 1/с — молча мимо (гейт 1 WF103): `click` поднял бы галерею на другом мониторе.
            if verdict == .tooSoon { return }
            request = Request(path: request.path, mode: .click, chat: request.chat)
        }
        let ext = (request.path as NSString).pathExtension.lowercased()
        // PDF — в галерею по клику (PimpViewer 1.7 берёт PDF; слово Элвиса 29.09: «надо, чтоб в Пимпе открывалось»).
        guard ext != "pdf" || request.mode == .click else { return openBrowser(request) }
        guard let toViewer = toViewer else { return fallBack(request) }
        toViewer(request) { [weak self] taken in
            if !taken { self?.fallBack(request) }
        }
    }

    /// Галерея не взяла `click` или её нет (WF107 К3): страница — в окно просмотра поверх окна чата (рамка есть,
    /// чат известен, не чаще 1/с — как у `view`), иначе браузер, как было. Фото — браузером («Просмотр»):
    /// окно просмотра — только для страниц.
    private func fallBack(_ request: Request) {
        let ext = (request.path as NSString).pathExtension.lowercased()
        guard request.mode == .click, ext == "html" || ext == "htm" else { return openBrowser(request) }
        switch acceptsView(request) {
        case .accept: onView?(Request(path: request.path, mode: .view, chat: request.chat,
                                      frame: request.frame, bg: request.bg))
        case .tooSoon: return
        case .refuse: openBrowser(request)
        }
    }

    private enum ViewVerdict { case accept, tooSoon, refuse }

    /// Контракт WF103: окно подключено, есть рамка окна чата, чат известен индексу, с прошлого `view`
    /// прошла секунда.
    private func acceptsView(_ request: Request) -> ViewVerdict {
        // Без рамки окна чата просмотру встать некуда (#7964: только в рамку своего окна).
        guard onView != nil, request.frame != nil, let chat = request.chat, isKnownChat?(chat) == true else { return .refuse }
        let at = now()
        counters.lock()
        defer { counters.unlock() }
        if let last = lastViewAt, at.timeIntervalSince(last) < Self.viewInterval, at >= last { return .tooSoon }
        lastViewAt = at
        return .accept
    }

    private func openBrowser(_ request: Request) {
        if let seam = browserSeam { return seam(request) }
        openQueue.async { [weak self] in self?.open(request) }
    }

    /// «в браузер» из Viewer: страницы — в Vivaldi/Chrome, картинки — в «Просмотр».
    public func openInBrowser(_ path: String) {
        openBrowser(Request(path: path, mode: .click))
    }

    /// `id` чата страницы: `local_` + буквы, цифры, дефис, подчёркивание.
    static func chatID(_ raw: String?) -> String? {
        guard let raw = raw, raw.hasPrefix("local_"), raw.count <= 128,
              raw.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        return raw
    }

    /// «📋 Копировать в буфер» (WF106 #8102).
    public struct CopyFileRequest: Equatable {
        public let path: String
        public let chat: String
    }

    /// `GET /copy-file?path=<enc>&chat=<local_…>` → запрос; нет чата, мусорный чат, путь не абсолютный
    /// или с `\0` — nil. Чистая.
    public static func parseCopyFile(_ head: String) -> CopyFileRequest? {
        guard let components = query(head, path: "/copy-file"),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/"), !path.contains("\0"),
              let chat = chatID(components.queryItems?.first(where: { $0.name == "chat" })?.value) else { return nil }
        return CopyFileRequest(path: path, chat: chat)
    }

    /// `GET /panel` — кнопка «PMP» страницы (WF125 #8894); параметров нет. Чистая.
    public static func parsePanel(_ head: String) -> Bool { query(head, path: "/panel") != nil }

    /// `GET /digest` — сводка проектов (WF133, К6); параметров нет. Чистая.
    static func parseDigest(_ head: String) -> Bool { query(head, path: "/digest") != nil }

    /// `GET /kickoff` — текст кикоффа Workflow для страницы (WF214, К-KO); параметров нет. Чистая.
    static func parseKickoff(_ head: String) -> Bool { query(head, path: "/kickoff") != nil }

    /// `GET /context?chat=<local_…>` → `local_…`; мусорный или пустой chat — nil. Чистая.
    public static func parseContext(_ head: String) -> String? {
        guard let components = query(head, path: "/context") else { return nil }
        return chatID(components.queryItems?.first(where: { $0.name == "chat" })?.value)
    }

    /// Строка запроса `GET <path>?…` → её разбор; другой метод или путь — nil.
    private static func query(_ head: String, path: String) -> URLComponents? {
        let line = head.prefix { $0 != "\r" && $0 != "\n" }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1" + parts[1]),
              components.path == path else { return nil }
        return components
    }

    /// Порт отвечает любой странице Chrome (критик WF106): чат известен индексу, путь — и сам, и после
    /// раскрытия симлинков — не закрыт `CopyFileRelay.isRefused` (скрытые, Keychains, Cookies), это обычный
    /// файл. Прошёл — путь для буфера (раскрытый), иначе nil.
    func acceptsCopyFile(_ request: CopyFileRequest) -> String? {
        guard isKnownChat?(request.chat) == true,
              !CopyFileRelay.isRefused(request.path, home: home) else { return nil }
        // Рабочий стол, «Загрузки», «Документы» под TCC (у Элвиса рабочий стол ещё и в iCloud): диск там Пимпу
        // не отвечает честно — живьём 29.09 файл с рабочего стола молча не копировался. Путь с расширением
        // берём как есть, диск не трогаем.
        if Self.underClosedFolder(request.path, home: home) { return request.path }
        let real = URL(fileURLWithPath: request.path).resolvingSymlinksInPath().path
        // Только stat(): `attributesOfItem` читает ещё и расширенные атрибуты (getxattr), а на файле с рабочего
        // стола это вопрос TCC — очередь порта висела, пока он открыт (гейт WF106, 29.09).
        // Остальное — только stat(): он не спрашивает TCC и не держит очередь. Ответил — только обычный файл;
        // не ответил правами (другая закрытая папка) — путь с расширением.
        var info = stat()
        let found = stat(real, &info) == 0
        let unseen = !found && (errno == EPERM || errno == EACCES)
        guard !CopyFileRelay.isRefused(real, home: home),
              (found && info.st_mode & S_IFMT == S_IFREG) || (unseen && !(real as NSString).pathExtension.isEmpty)
        else { return nil }
        return real
    }

    /// Папки под TCC, где Пимпу stat() может ответить «нет файла», хотя файл есть.
    static func underClosedFolder(_ path: String, home: String) -> Bool {
        guard !(path as NSString).pathExtension.isEmpty else { return false }
        return ["Desktop", "Downloads", "Documents"].contains { folder in
            path.hasPrefix((home as NSString).appendingPathComponent(folder) + "/")
        }
    }

    /// `GET /viewer?chat=<local_…>&on=1|0` → запрос «Галереи». Чистая, её и гоняют тесты.
    public static func parseViewer(_ head: String) -> ViewerRequest? {
        let line = head.prefix { $0 != "\r" && $0 != "\n" }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1" + parts[1]),
              components.path == "/viewer",
              let chat = chatID(components.queryItems?.first(where: { $0.name == "chat" })?.value) else { return nil }
        switch components.queryItems?.first(where: { $0.name == "on" })?.value {
        case "1": return ViewerRequest(chat: chat, on: true)
        case "0": return ViewerRequest(chat: chat, on: false)
        default: return nil
        }
    }

    /// Первая строка запроса → путь и режим. Чистая, её и гоняют тесты.
    public static func parse(_ head: String) -> Request? {
        let line = head.prefix { $0 != "\r" && $0 != "\n" }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1" + parts[1]),
              components.path == "/open-html",
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              acceptsPath(path) else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        let items = components.queryItems ?? []
        let value = { (name: String) in items.first(where: { $0.name == name })?.value }
        guard var mode = Mode(rawValue: value("mode") ?? "click") else { return nil }
        // `view` — только страницы (WF103); у прочих — прежний `click`.
        if mode == .view, ext != "html", ext != "htm" { mode = .click }
        let chat = chatID(value("chat"))
        return Request(path: path, mode: mode, chat: chat, frame: frame(value("frame")), bg: color(value("bg")))
    }

    /// Абсолютный путь без `\0` к странице, PDF или картинке — фильтр `/open-html` и `/viewer-open-browser`.
    static func acceptsPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0") else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return chromeExtensions.contains(ext) || imageExtensions.contains(ext)
    }

    /// `x,y,w,h` — целые, `x`,`y` со знаком, `w`,`h` > 0; иначе nil.
    static func frame(_ raw: String?) -> CGRect? {
        guard let raw = raw, raw.count <= 64 else { return nil }
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            let text = String(part)
            guard text.range(of: "^-?[0-9]{1,6}$", options: .regularExpression) != nil else { return nil }
            return Int(text)
        }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    /// Ровно 6 hex без `#` → строчными; иначе nil.
    static func color(_ raw: String?) -> String? {
        guard let raw = raw, raw.count == 6, raw.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return raw.lowercased()
    }

    static func isPage(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
    }

    /// AppleScript для Chrome. Чистая, её и гоняют тесты.
    public static func script(url: String, browser: String = "Google Chrome") -> String {
        let target = url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "\(browser)"
            set target to "\(target)"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    if URL of t is target then
                        reload t
                        set active tab index of w to i
                        set index of w to 1
                        activate
                        return "found"
                    end if
                end repeat
            end repeat
            if (count of windows) is 0 then
                make new window
                set URL of active tab of window 1 to target
            else
                tell window 1 to make new tab with properties {URL:target}
            end if
            activate
            return "opened"
        end tell
        """
    }

    private func count(failed: Bool) {
        counters.lock()
        if failed { failedCount += 1 } else { openedCount += 1 }
        counters.unlock()
    }

    private func open(_ request: Request) {
        let file = URL(fileURLWithPath: request.path)
        if Self.imageExtensions.contains(file.pathExtension.lowercased()) {
            count(failed: false)
            DispatchQueue.main.async { Self.launch(file, in: Self.previewBundleID) }
            return
        }
        // Браузер не на Chromium — открываем в нём без osascript и ложной плашки «Разреши Пимпу
        // управлять браузером» (z9-r10); браузера нет вовсе — программе по умолчанию.
        let browser: (name: String, app: URL)
        switch Self.browserRoute {
        case .script(let name, let app):
            browser = (name, app)
        case .open(let app):
            count(failed: false)
            DispatchQueue.main.async { Self.launch(file, at: app) }
            return
        case .system:
            count(failed: false)
            DispatchQueue.main.async { NSWorkspace.shared.open(file) }
            return
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", Self.script(url: file.absoluteString, browser: browser.name)]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}
        if process.isRunning == false, process.terminationStatus == 0 {
            count(failed: false)
            // Bring the browser forward for the explicit user action.
            DispatchQueue.main.async { Self.launch(nil, at: browser.app) }
            return
        }
        count(failed: true)
        DispatchQueue.main.async { [weak self] in
            // Без разрешения на Chrome — хотя бы обычным путём: новая вкладка лучше тишины.
            Self.launch(file, at: browser.app)
            self?.onScriptFailed?()
        }
    }

    /// Открыть файл программой (или просто вывести её вперёд, если файла нет); программы нет —
    /// файл уходит программе по умолчанию.
    private static func launch(_ file: URL?, in bundleID: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            if let file = file { NSWorkspace.shared.open(file) }
            return
        }
        launch(file, at: app)
    }

    /// Открыть файл именно этой программой (не `open(file)` — тот выбрал бы программу для типа файла).
    private static func launch(_ file: URL?, at app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let file = file {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        }
    }
}
