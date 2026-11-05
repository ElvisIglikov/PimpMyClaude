import AppKit
import Foundation
import ImageIO
import Network
import QuickLookThumbnailing

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
    /// Текст и ролики (WF277, К-DOCK «Виды файлов»), архив zip (#11347) — в док или галерею PimpViewer по клику; не
    /// взяли — программой macOS по умолчанию; ни браузеру, ни «Просмотру», ни `view`.
    public static let dockExtensions: Set<String> = ["md", "markdown", "txt", "mp4", "mov", "m4v", "webm", "mp3", "m4a",
                                                     "aac", "wav", "zip"]

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
        /// `dock=1` (WF277, К-DOCK-1): файл в панель материалов — место и рамка окна из того же запроса; только `click`.
        public var dock: MaterialsDock.Place? = nil
    }

    /// Кнопка «Галерея» в чате (WF97 К-V1): `/viewer?chat=<local_…>&on=1|0`.
    public struct ViewerRequest: Equatable {
        public let chat: String
        public let on: Bool
    }

    /// PimpViewer.app берёт html и фото себе (WF97, выбор 4; с WF104 — через `ViewerClient`, К-V8):
    /// `done(true)` — взял, браузер не нужен. Зовут на очереди порта, ответ — на очереди клиента: порт не ждёт.
    public var toViewer: ((Request, @escaping (Bool) -> Void) -> Void)?
    /// Кнопка «Галерея». Зовут на очереди порта; второй аргумент — слово исхода (`ViewerClient.GalleryOutcome`) для
    /// ответа странице, с любой очереди, один раз (#9631: нажатие не молчит).
    public var onViewer: ((ViewerRequest, @escaping (String) -> Void) -> Void)?
    /// Столько страница ждёт исхода «Галереи»; не пришёл — ответ `silent`.
    static let viewerReplyWait: TimeInterval = 6
    /// Панель материалов (WF277, К-DOCK-1 `/dock`): ответ странице — с любой очереди, один раз. Зовут на очереди порта.
    public var onDock: ((MaterialsDock.Request, @escaping (MaterialsDock.Answer) -> Void) -> Void)?
    /// `/open-html … dock=1`: файл в док PimpViewer → `(taken, opened)` с любой очереди, один раз; nil — прежний `click`.
    public var toDock: ((Request, @escaping (_ taken: Bool, _ opened: Bool) -> Void) -> Void)?
    /// Столько страница ждёт ответа `/dock`; не пришёл — `MaterialsDock.Answer.late`.
    static let dockReplyWait: TimeInterval = 2
    /// Толчок галереи `/viewer-nudge` (К-V8): разослать страницам фильтр (`chat`) и/или счёт (`counts`).
    /// Зовут на очереди порта, ответ `204` уже ушёл.
    public var onNudge: ((_ chat: Bool, _ counts: Bool) -> Void)?
    /// «в чат» из галереи `/viewer-open-chat` (К-V8): `local_…` (nil — мусорный) → `reply("ok"|"chat-closed")`
    /// с любой очереди; соединение держится до ответа. Зовут на очереди порта.
    public var onOpenChat: ((String?, @escaping (String) -> Void) -> Void)?
    /// ✕ в PimpViewer `/viewer-dock-off` (К-V8, #11224): закрыть панель у окна-владельца, как «PMP». Зовут на очереди
    /// порта, ответ `204` уже ушёл (дока нет — тоже 204).
    public var onDockOff: (() -> Void)?
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
    /// Вместо программы по умолчанию (тесты): текст и ролики, которые PimpViewer не взяла. nil — `NSWorkspace.open`.
    var defaultSeam: ((Request) -> Void)?
    /// `/open-link` (WF288, К-LINK): есть ли в системе программа для адреса и чем открыть план — тест подставляет свои,
    /// приложений не открывая.
    var linkHasApp: (URL) -> Bool = { NSWorkspace.shared.urlForApplication(toOpen: $0) != nil }
    var linkOpen: (LinkPlan) -> Void = HtmlChromeOpener.openLinkLive
    /// `/open-link?kind=web` (#11323, К-LINK): открыть внешний адрес на уже открытой вкладке — тест подставляет свою.
    var webOpen: (URL) -> Void = HtmlChromeOpener.openWebLive
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
    /// «Всё в одном чате» панели PMP страницы (#9552, К-OC): `GET /one-chat` — окно в папке Рика или к его установке.
    /// Зовут на очереди порта.
    public var onOneChat: (() -> Void)?
    /// Сводка проектов для ячеек Workflow в поле Рика (WF133, К6): `GET /digest` → `200` JSON, не чаще раза в 10 с.
    let digest = ProjectsDigestCache()
    /// Суть длинного сообщения Элвиса (#9806, `POST /summary`) — пишет Claude CLI этого Мака. Тест подставляет свою
    /// с временным файлом.
    var summaries = UserSummary.onThisMac()
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
    /// Миниатюры HEIC (К-TH): чтение фото и сжатие — здесь.
    private let thumbQueue = DispatchQueue(label: "pimpmyclaude.html-chrome.thumb", qos: .userInitiated)
    /// Ролики и картинки чата с диска (#10699, `ChatMedia.swift`): кадры, байты картинок, путь по имени.
    public let media = ChatMedia()
    /// Снимок HTML и PDF от PimpViewer (#10603, `ViewerClient.thumb`); `done` — раз, с любой очереди, nil — нет снимка.
    /// Тест подменяет; без проводки — сразу nil, и снимок делает QuickLook.
    public var viewerThumb: (_ path: String, _ done: @escaping (Data?) -> Void) -> Void = { $1(nil) }
    /// Снимок QuickLook для HTML и PDF — прежний путь (тест подменяет).
    var pageShot: (URL) -> Data? = { HtmlChromeOpener.pageThumb(of: $0, side: HtmlChromeOpener.pageThumbSide) }
    /// Кадр панели материалов от PimpViewer (#10760, `DockShot.swift`); тест подменяет.
    var dockShotFile = CommandChannel.directory.appendingPathComponent("viewer/dock-shot.jpg")
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
        // Порт занят (#8302): галерея такому слушателю токен уже не шлёт, но клики из чата и «▦ Галерея» без Пимпа
        // не работают — громко в журнал, кто его держит.
        listener.stateUpdateHandler = { state in
            if case .failed(.posix(.EADDRINUSE)) = state {
                NSLog("PimpMyClaude: %@", Self.busyNote(holders: PortOwner.listeners(port: Self.port)))
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Кто держит занятый порт 47615: свои слушатели (pid, путь) или «своего нет» — порт у другого пользователя Мака.
    static func busyNote(holders: [PortOwner.Holder]?) -> String {
        let list = (holders ?? []).map { "pid \($0.pid) \($0.path.isEmpty ? "?" : $0.path)" }.joined(separator: ", ")
        let who = list.isEmpty ? "своего слушателя нет — другой пользователь" : list
        return "ВНИМАНИЕ: порт \(port) занят чужим процессом (\(who))"
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
            if Self.isSummary(text) { return self.serveSummary(bytes, connection, timeout: timeout) }
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
        if access.performsAction, let request = Self.parseThumb(head) {
            // Диск и индекс — не на очереди порта (как у `/copy-file`); своя очередь: вопрос TCC на папке
            // фото не держит ни порт, ни буфер.
            return thumbQueue.async { [weak self, queue] in
                let jpeg = self?.thumb(request)
                queue.async {
                    connection.send(content: Self.thumbResponse(jpeg, access: access),
                                    completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        // Ролики и картинки с диска (#10699): ответ — после поиска файла и диска.
        if access.performsAction, let request = ChatMedia.parse(head) { return serveMedia(request, access: access, connection) }
        if access.performsAction, let open = ChatMedia.parseOpen(head) { return serveNamedOpen(open, access: access, connection) }
        if access.performsAction, let since = Self.parseDockShot(head) { return serveDockShot(since: since, access: access, connection) }
        if access.performsAction, let viewer = Self.parseViewer(head), let onViewer = onViewer {
            return serveViewer(viewer, onViewer, access: access, connection)
        }
        // Док (WF277): ответ — когда PimpViewer ответил, не сразу 204.
        if access.performsAction, let onDock = onDock, Self.query(head, path: "/dock") != nil {
            guard let request = MaterialsDock.parse(head) else {
                return connection.send(content: Self.httpResponse(status: 400, contentType: nil, body: nil, access: access),
                                       completion: .contentProcessed { _ in connection.cancel() })
            }
            return hold(connection, wait: Self.dockReplyWait, late: Self.dockResponse(.late, access: access)) { reply in
                onDock(request) { reply(Self.dockResponse($0, access: access)) }
            }
        }
        if access.performsAction, toDock != nil, let request = Self.parse(head), request.dock != nil {
            let refused = Self.dockOpenResponse(taken: false, opened: false, access: access)
            // Файла нет (WF288, К-LINK): 404 — страница отличает «нет файла» от «док не взял, Пимп открыл сам».
            guard Self.isPage(request.path) else {
                let missing = Self.dockOpenResponse(taken: false, opened: false, access: access, status: 404)
                return connection.send(content: missing, completion: .contentProcessed { _ in connection.cancel() })
            }
            return hold(connection, wait: Self.viewerReplyWait, late: refused) { reply in
                routeDock(request) { reply(Self.dockOpenResponse(taken: $0, opened: $1, access: access)) }
            }
        }
        if access.performsAction, Self.parseKickoff(head) {
            return connection.send(content: Self.kickoffResponse(WorkflowKit.kickoff(), access: access),
                                   completion: .contentProcessed { _ in connection.cancel() })
        }
        // Наши ссылки из чата (WF288, К-LINK): только белый список адресов.
        if access.performsAction, Self.query(head, path: "/open-link") != nil {
            return serveLink(head, access: access, connection)
        }
        // Клик по файлу, которого нет (WF288, К-LINK): 404 вместо 204 — делать всё равно нечего (`performOld`).
        if access.performsAction, let request = Self.parse(head), !Self.isPage(request.path) {
            return connection.send(content: Self.httpResponse(status: 404, contentType: nil, body: nil, access: access),
                                   completion: .contentProcessed { _ in connection.cancel() })
        }
        connection.send(content: Self.pageResponse(access), completion: .contentProcessed { _ in
            connection.cancel()
        })
        if access.performsAction { performOld(head) }
    }

    /// «Галерея» (#9631): соединение держится до исхода, ответ — `viewerResponse`; исхода нет за
    /// `viewerReplyWait` — `silent`. Отвечаем ровно раз.
    private func serveViewer(_ viewer: ViewerRequest, _ onViewer: (ViewerRequest, @escaping (String) -> Void) -> Void,
                             access: PageAccess, _ connection: NWConnection) {
        let silent = Self.viewerResponse(ViewerClient.GalleryOutcome.silent.rawValue, access: access)
        hold(connection, wait: Self.viewerReplyWait, late: silent) { reply in
            onViewer(viewer) { reply(Self.viewerResponse($0, access: access)) }
        }
    }

    /// Ответ после работы (`/viewer`, `/dock`, `/open-html … dock=1`, `/media-*`): соединение держится до `reply` (с любой
    /// очереди), нет его за `wait` — `late`. Отвечаем ровно раз.
    func hold(_ connection: NWConnection, wait: TimeInterval, late: Data,
              _ work: (@escaping (Data) -> Void) -> Void) {
        let lock = NSLock()
        var sent = false
        let reply = { [queue] (data: Data) in
            lock.lock()
            let first = !sent
            sent = true
            lock.unlock()
            guard first else { return }
            queue.async { connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() }) }
        }
        queue.asyncAfter(deadline: .now() + wait) { reply(late) }
        work(reply)
    }

    /// Ответ «Галерее»: `200` — открылась, снят фильтр или запускается; иначе `503`; тело — слово исхода
    /// (`text/plain`), CORS — как у остальных ручек страницы: слово читает только страница Claude.
    static func viewerResponse(_ word: String, access: PageAccess) -> Data {
        let ok = ViewerClient.GalleryOutcome(rawValue: word)?.ok ?? false
        return httpResponse(status: ok ? 200 : 503, contentType: "text/plain; charset=utf-8", body: Data(word.utf8),
                            access: access)
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
            onViewer?(viewer) { _ in }
        } else if Self.parsePanel(head) {
            onPanel?()
        } else if Self.parseOneChat(head) {
            onOneChat?()
        } else if let request = Self.parse(head), Self.isPage(request.path) {
            route(request)
        }
    }

    // MARK: - ручки галереи (К-V8, WF104)

    /// Галерея → Пимп: `/viewer-nudge`, `/viewer-open-chat`, `/viewer-open-browser`, `/viewer-dock-off`. Проверки — `checkChannel`,
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
        case .dockOff:
            reply(204, nil)
            onDockOff?()
        }
    }

    /// Разбор запроса к ручкам галереи.
    enum ChannelVerdict: Equatable {
        case reject(Int)
        case nudge(chat: Bool, counts: Bool)
        /// nil — мусорный `chat`: ответ `chat-closed`.
        case openChat(String?)
        case openBrowser(String)
        case dockOff
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
        case "/viewer-dock-off":
            return .dockOff
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

    /// Файл в панель материалов (WF277, `dock=1`): `toDock` — PimpViewer встаёт в док и открывает файл; не взял или
    /// его нет — прежний путь (`fallBack`); взял без файла (`opened:false`) — тоже (#10831: молча терялось).
    /// `answer(taken, opened)` — ровно раз, с любой очереди.
    func routeDock(_ request: Request, answer: @escaping (_ taken: Bool, _ opened: Bool) -> Void) {
        guard let toDock = toDock else {
            answer(false, false)
            return route(request)
        }
        toDock(request) { [weak self] taken, opened in
            answer(taken, opened)
            if !taken || !opened { self?.fallBack(request) }
        }
    }

    /// Галерея не взяла `click` или её нет (WF107 К3): страница — в окно просмотра поверх окна чата (рамка есть,
    /// чат известен, не чаще 1/с — как у `view`), иначе браузер, как было. Фото — браузером («Просмотр»):
    /// окно просмотра — только для страниц. Текст и ролики дока (WF277) — программой macOS по умолчанию: клик забран
    /// у Claude, молчать нельзя.
    private func fallBack(_ request: Request) {
        let ext = (request.path as NSString).pathExtension.lowercased()
        guard !Self.dockExtensions.contains(ext) else { return openDefault(request) }
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

    private func openDefault(_ request: Request) {
        if let seam = defaultSeam { return seam(request) }
        count(failed: false)
        DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: request.path)) }
    }

    /// «в браузер» из Viewer: страницы — в Vivaldi/Chrome, картинки — в «Просмотр».
    public func openInBrowser(_ path: String) {
        openBrowser(Request(path: path, mode: .click))
    }

    /// `id` чата страницы — `ChatID.parse`.
    static func chatID(_ raw: String?) -> String? { ChatID.parse(raw) }

    /// «📋 Копировать в буфер» (WF106 #8102).
    public struct CopyFileRequest: Equatable {
        public let path: String
        public let chat: String
    }

    /// `GET /copy-file?path=<enc>&chat=<local_…>` → запрос; нет чата, мусорный чат, путь не абсолютный
    /// или с `\0` — nil. Чистая.
    public static func parseCopyFile(_ head: String) -> CopyFileRequest? { fileRequest(head, path: "/copy-file") }

    /// Фото, которые Chromium не показывает сам, — им страница просит миниатюру (К-TH); с #10254 — и любое фото,
    /// которое Claude кладёт плиткой файла (JPG от Рика), а с #10229 — HTML и PDF: снимок верха страницы.
    public static let thumbExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "gif", "webp", "tif", "tiff", "bmp",
                                                      "html", "htm", "pdf"]
    /// Страницы и PDF — снимком QuickLook (как карточка галереи: шапка, заголовок, подзаголовок), не ImageIO.
    static let pageThumbExtensions: Set<String> = ["html", "htm", "pdf"]
    /// Сторона снимка страницы, точек: карточка в чате 260×170, на ретине с запасом.
    static let pageThumbSide = 1080
    /// Сколько ждать QuickLook: дольше — плашка остаётся плашкой.
    static let pageThumbWait: TimeInterval = 10
    /// Длинная сторона миниатюры, точек: её же открывает просмотр фото в окне чата — на весь монитор.
    static let thumbSide = 1600

    /// `GET /thumb?path=<enc>&chat=<local_…>` (слово Элвиса 11.10.2026 06:36: «Хэйки эти превьюшки отображаются.
    /// Можно сделать как-нибудь?») → запрос; те же отказы, что у `/copy-file`, и не из `thumbExtensions` — nil. Чистая.
    public static func parseThumb(_ head: String) -> CopyFileRequest? {
        fileRequest(head, path: "/thumb", extensions: thumbExtensions)
    }

    /// `GET <path>?path=<enc>&chat=<local_…>` у `/copy-file` и `/thumb`: путь абсолютный без `\0` (и с одним из
    /// `extensions`, если они заданы), чат годный; иначе nil.
    private static func fileRequest(_ head: String, path wanted: String, extensions: Set<String>? = nil) -> CopyFileRequest? {
        guard let components = query(head, path: wanted),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/"), !path.contains("\0"),
              extensions.map({ $0.contains((path as NSString).pathExtension.lowercased()) }) ?? true,
              let chat = chatID(components.queryItems?.first(where: { $0.name == "chat" })?.value) else { return nil }
        return CopyFileRequest(path: path, chat: chat)
    }

    /// Миниатюра JPEG для плитки вложения: проверки пути и чата — `acceptsCopyFile`; файл не фото или не
    /// читается — nil. Поворот из EXIF применён. HTML и PDF — снимок верха QuickLook.
    func thumb(_ request: CopyFileRequest) -> Data? {
        guard let path = acceptsCopyFile(request) else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        guard Self.thumbExtensions.contains(ext) else { return nil }
        let url = URL(fileURLWithPath: path)
        // HTML и PDF (#10603, слово Элвиса 22.10.2026: «превьюшки сделать HTML… как в PimpViewer»): сперва верх карточки
        // галереи — её снимок шириной телефона, текст читается; QuickLook рисует страницу шириной компьютера, и в 240 px
        // буквы мелкие. Галерея молчит, отказала или ответила не JPEG — QuickLook, как было.
        if Self.pageThumbExtensions.contains(ext) {
            return viewerThumbNow(path) ?? pageShot(url)
        }
        return Self.jpegThumb(of: url, side: Self.thumbSide)
    }

    /// Ответ `viewerThumb` с ожиданием не дольше `viewerThumbWait` (на очереди миниатюр); только JPEG (FF D8).
    func viewerThumbNow(_ path: String) -> Data? {
        let done = DispatchSemaphore(value: 0)
        let box = NSLock()
        var jpeg: Data?
        viewerThumb(path) { data in
            box.lock(); jpeg = data; box.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + Self.viewerThumbWait) == .success else { return nil }
        box.lock(); defer { box.unlock() }
        guard let jpeg, jpeg.count > 3, jpeg[jpeg.startIndex] == 0xFF, jpeg[jpeg.startIndex + 1] == 0xD8 else { return nil }
        return jpeg
    }

    /// Сколько ждать снимка галереи: таймаут клиента (`ViewerClient.thumbTimeout`) и запас на проверку порта.
    static let viewerThumbWait: TimeInterval = 1.8

    /// Снимок верха HTML или первого листа PDF — QuickLook (тот же, что у Finder), квадрат `side` точек; не успел
    /// за `pageThumbWait` или не вышло — nil. Ждёт на очереди миниатюр, не на очереди порта.
    static func pageThumb(of url: URL, side: Int) -> Data? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side / 2, height: side / 2), scale: 2,
                                                   representationTypes: .thumbnail)
        let done = DispatchSemaphore(value: 0)
        var image: CGImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            image = representation?.cgImage
            done.signal()
        }
        guard done.wait(timeout: .now() + pageThumbWait) == .success, let image else {
            QLThumbnailGenerator.shared.cancel(request)
            return nil
        }
        return jpegData(image)
    }

    static func jpegThumb(of url: URL, side: Int) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: side]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpegData(image)
    }

    static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(target) ? data as Data : nil
    }

    /// `GET /panel` — кнопка «PMP» страницы (WF125 #8894); параметров нет. Чистая.
    public static func parsePanel(_ head: String) -> Bool { query(head, path: "/panel") != nil }

    /// `GET /one-chat` — «Всё в одном чате» панели PMP страницы (#9552, К-OC); параметров нет. Чистая.
    static func parseOneChat(_ head: String) -> Bool { query(head, path: "/one-chat") != nil }

    /// `GET /digest` — сводка проектов (WF133, К6); параметров нет. Чистая.
    static func parseDigest(_ head: String) -> Bool { query(head, path: "/digest") != nil }

    /// `GET /kickoff` — текст кикоффа Workflow для страницы (WF214, К-KO); параметров нет. Чистая.
    static func parseKickoff(_ head: String) -> Bool { query(head, path: "/kickoff") != nil }

    /// `GET /context?chat=<local_…>` → `local_…`; мусорный или пустой chat — nil. Чистая.
    public static func parseContext(_ head: String) -> String? {
        guard let components = query(head, path: "/context") else { return nil }
        return chatID(components.queryItems?.first(where: { $0.name == "chat" })?.value)
    }

    /// Строка запроса `GET <path>?…` → её разбор; другой метод или путь — nil. Одна на все ручки порта.
    static func query(_ head: String, path: String) -> URLComponents? {
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
        guard let components = query(head, path: "/viewer"),
              let chat = chatID(components.queryItems?.first(where: { $0.name == "chat" })?.value) else { return nil }
        switch components.queryItems?.first(where: { $0.name == "on" })?.value {
        case "1": return ViewerRequest(chat: chat, on: true)
        case "0": return ViewerRequest(chat: chat, on: false)
        default: return nil
        }
    }

    /// Первая строка запроса → путь и режим. Чистая, её и гоняют тесты.
    public static func parse(_ head: String) -> Request? {
        guard let components = query(head, path: "/open-html"),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        let items = components.queryItems ?? []
        let value = { (name: String) in items.first(where: { $0.name == name })?.value }
        guard var mode = Mode(rawValue: value("mode") ?? "click") else { return nil }
        // Док (WF277) — только у клика и только с годными местом и рамкой окна. Текст и ролики — у любого клика: без
        // места их возьмёт галерея или программа по умолчанию (страница забирает их только при годной панели).
        let dock = mode == .click && value("dock") == "1" ? MaterialsDock.place(value) : nil
        guard acceptsPath(path, dock: mode == .click) else { return nil }
        // `view` — только страницы (WF103); у прочих — прежний `click`.
        if mode == .view, ext != "html", ext != "htm" { mode = .click }
        let chat = chatID(value("chat"))
        return Request(path: path, mode: mode, chat: chat, frame: frame(value("frame")), bg: color(value("bg")), dock: dock)
    }

    /// Абсолютный путь без `\0` к странице, PDF или картинке — фильтр `/open-html` и `/viewer-open-browser`;
    /// `dock` (WF277, клик `/open-html`) — ещё текст и ролики дока.
    static func acceptsPath(_ path: String, dock: Bool = false) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0") else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return chromeExtensions.contains(ext) || imageExtensions.contains(ext) || (dock && dockExtensions.contains(ext))
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
