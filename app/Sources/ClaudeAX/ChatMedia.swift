import AVFoundation
import Foundation
import Network

/// Ролики и картинки чата — с диска (#10699; слово Элвиса 23.10.2026: «Капец долго грузятся ролики… как будто бы они из
/// интернета откуда-то скачиваются… Они же на диске всё равно лежат»). Ролик, который Claude залил на свои серверы,
/// страница (раздел 12п⁵) прячет и ставит на его место свою кнопку с первым кадром; нажатие — ролик в панель материалов;
/// картинки-вложения берёт с диска.
///
/// Ручки порта 47615 (CORS как у `/thumb`, пути — в белом списке `PageHTTPAccess`):
/// - `GET /media-thumb?chat=<local_…>&name=<enc>[&path=<enc>]` → `200 image/jpeg` первый кадр ролика | `204` файл есть,
///   кадра нет (webm, битый) | `404` файла нет;
/// - `GET /media-file?chat&name[&path]` → `200 image/*` байты картинки | `404`;
/// - `GET /open-html?mode=click&name=<enc>&chat=…[&dock=1&x…&wh]` (без `path`) → `200 {found, taken, opened}`: файл нашёлся
///   — дальше как клик по файлу (док или галерея).
/// Какой файл: `path` страницы (из пропсов Claude) — с проверками `/thumb` (`acceptsCopyFile`: чат известен индексу, путь не
/// закрыт, обычный файл) и тем же именем файла, что `name`; нет `path` или не прошёл — путь по имени даёт PimpViewer
/// (`ViewerClient.resolve`, К-V8 `GET /resolve`), с теми же проверками. Иных путей нет — произвольного чтения диска нет.
public final class ChatMedia {
    public enum Kind: String { case thumb = "/media-thumb", file = "/media-file" }

    /// Запрос `/media-thumb` или `/media-file`.
    public struct Request: Equatable {
        public let kind: Kind
        public let chat: String
        public let name: String
        public let path: String?
    }

    /// `/open-html` по имени: всё, что у клика по файлу, кроме пути.
    public struct Open: Equatable {
        public let name: String
        public let chat: String
        public var frame: CGRect? = nil
        public var bg: String? = nil
        public var dock: MaterialsDock.Place? = nil

        func request(path: String) -> HtmlChromeOpener.Request {
            HtmlChromeOpener.Request(path: path, mode: .click, chat: chat, frame: frame, bg: bg, dock: dock)
        }
    }

    /// Ролики, у которых страница прячет плеер Claude; кадр умеет AVFoundation — у `frameExtensions`.
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]
    static let frameExtensions: Set<String> = ["mp4", "mov", "m4v"]
    /// Картинки, которые Chromium показывает сам, и их тип.
    static let imageTypes: [String: String] = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                               "gif": "image/gif", "webp": "image/webp", "bmp": "image/bmp"]
    /// Больше — не отдаём: страница оставит картинку Claude.
    static let maxFileBytes = 32 * 1024 * 1024
    /// Кадр — в рамку 320×240 CSS px на ретине.
    static let frameSize = CGSize(width: 640, height: 480)
    static let frameWait: TimeInterval = 5
    static let cacheLimit = 48
    /// Страница ждёт ответа на `name` не дольше, чем клик по файлу.
    static let openWait = HtmlChromeOpener.viewerReplyWait

    /// Путь по имени — у галереи (К-V8 `/resolve`); `done` — раз, с любой очереди. Боевой — `ViewerClient.resolve`.
    public var resolve: (_ chat: String, _ name: String, _ done: @escaping (String?) -> Void) -> Void = { $2(nil) }
    /// Первый кадр ролика JPEG (тест подменяет).
    var frame: (URL) -> Data? = ChatMedia.firstFrame(of:)

    /// Диск и AVFoundation — здесь, не на очереди порта.
    let queue = DispatchQueue(label: "pimpmyclaude.chat-media", qos: .userInitiated)
    /// Кадры по «путь|mtime|размер» — только на `queue`.
    private var frames: [String: Data] = [:]
    private var order: [String] = []

    public init() {}

    /// Дождаться очереди — тестам.
    func drain() { queue.sync {} }

    // MARK: - разбор

    /// Имя файла: не пустое, без `/` и `\0`, не `.`/`..`, до 255 байт, с расширением из `extensions`. Иначе nil.
    static func name(_ raw: String?, extensions: Set<String>) -> String? {
        guard let raw = raw, !raw.isEmpty, raw.utf8.count <= 255, !raw.contains("/"), !raw.contains("\0"),
              raw != ".", raw != "..", extensions.contains((raw as NSString).pathExtension.lowercased()) else { return nil }
        return raw
    }

    /// `GET /media-thumb|/media-file?chat&name[&path]` → запрос; мусорный чат или имя — nil; `path` не абсолютный или с
    /// `\0` — без него. Чистая.
    public static func parse(_ head: String) -> Request? {
        for kind in [Kind.thumb, .file] {
            guard let components = HtmlChromeOpener.query(head, path: kind.rawValue) else { continue }
            let value = { (key: String) in components.queryItems?.first(where: { $0.name == key })?.value }
            let allowed = kind == .thumb ? videoExtensions : Set(imageTypes.keys)
            guard let chat = HtmlChromeOpener.chatID(value("chat")), let name = name(value("name"), extensions: allowed)
            else { return nil }
            let path = value("path").flatMap { $0.hasPrefix("/") && !$0.contains("\0") ? $0 : nil }
            return Request(kind: kind, chat: chat, name: name, path: path)
        }
        return nil
    }

    /// `GET /open-html?mode=click&name&chat[&dock=1…][&frame][&bg]` без `path` → запрос по имени; иначе nil (с `path` — прежний
    /// разбор `HtmlChromeOpener.parse`). Имя — виды клика по файлу (`acceptsPath … dock`). Чистая.
    public static func parseOpen(_ head: String) -> Open? {
        guard let components = HtmlChromeOpener.query(head, path: "/open-html") else { return nil }
        let items = components.queryItems ?? []
        let value = { (key: String) in items.first(where: { $0.name == key })?.value }
        guard value("path") == nil, (value("mode") ?? "click") == "click",
              let chat = HtmlChromeOpener.chatID(value("chat")),
              let name = name(value("name"), extensions: HtmlChromeOpener.chromeExtensions
                .union(HtmlChromeOpener.imageExtensions).union(HtmlChromeOpener.dockExtensions)) else { return nil }
        return Open(name: name, chat: chat, frame: HtmlChromeOpener.frame(value("frame")), bg: HtmlChromeOpener.color(value("bg")),
                    dock: value("dock") == "1" ? MaterialsDock.place(value) : nil)
    }

    /// Имя файла пути — то же, что `name` (Unicode-равенство: NFC и NFD — одно имя).
    static func sameName(_ path: String, _ name: String) -> Bool {
        (path as NSString).lastPathComponent == name
    }

    // MARK: - кадр

    /// Первый кадр ролика JPEG в `frameSize` с поворотом дорожки; не вышло за `frameWait` — nil. Ждёт на очереди медиа.
    static func firstFrame(of url: URL) -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = frameSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var image: CGImage?
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, frame, _, result, _ in
            lock.lock()
            if result == .succeeded { image = frame }
            lock.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + frameWait) == .success else {
            generator.cancelAllCGImageGeneration()
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return image.flatMap(HtmlChromeOpener.jpegData)
    }

    /// Кадр из кэша по «путь|mtime|размер» или заново. На `queue`.
    func cachedFrame(_ path: String) -> Data? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let key = "\(path)|\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)|\(info.st_size)"
        if let data = frames[key] { return data }
        guard let data = frame(URL(fileURLWithPath: path)) else { return nil }
        frames[key] = data
        order.append(key)
        while order.count > Self.cacheLimit { frames[order.removeFirst()] = nil }
        return data
    }
}

extension HtmlChromeOpener {
    /// Файл ролика или картинки: путь страницы (те же имя и проверки, что у `/thumb`), иначе — галереи по имени.
    /// `done(путь)` — раз, с любой очереди; nil — не нашёлся или не прошёл проверки.
    func locateMedia(chat: String, name: String, path: String?, extensions: Set<String>, done: @escaping (String?) -> Void) {
        let check = { [weak self] (candidate: String?) -> String? in
            guard let self = self, let candidate = candidate, candidate.hasPrefix("/"), !candidate.contains("\0"),
                  ChatMedia.sameName(candidate, name),
                  extensions.contains((candidate as NSString).pathExtension.lowercased()),
                  let real = self.acceptsCopyFile(CopyFileRequest(path: candidate, chat: chat)) else { return nil }
            return real
        }
        if let found = check(path) { return done(found) }
        media.resolve(chat, name) { done(check($0)) }
    }

    /// `/media-thumb`, `/media-file`: ответ — после поиска и диска, не дольше `viewerReplyWait` (потом `404`).
    func serveMedia(_ request: ChatMedia.Request, access: PageAccess, _ connection: NWConnection) {
        let missing = Self.httpResponse(status: 404, contentType: nil, body: nil, access: access)
        let extensions = request.kind == .thumb ? ChatMedia.videoExtensions : Set(ChatMedia.imageTypes.keys)
        hold(connection, wait: Self.viewerReplyWait, late: missing) { [weak self] reply in
            guard let self = self else { return reply(missing) }
            self.locateMedia(chat: request.chat, name: request.name, path: request.path, extensions: extensions) { [weak self] path in
                guard let self = self, let path = path else { return reply(missing) }
                self.media.queue.async { reply(self.mediaResponse(request.kind, path: path, access: access)) }
            }
        }
    }

    /// Ответ по найденному файлу. На очереди медиа.
    func mediaResponse(_ kind: ChatMedia.Kind, path: String, access: PageAccess) -> Data {
        let ext = (path as NSString).pathExtension.lowercased()
        switch kind {
        case .thumb:
            if ChatMedia.frameExtensions.contains(ext), let jpeg = media.cachedFrame(path) {
                return Self.httpResponse(status: 200, contentType: "image/jpeg", body: jpeg, access: access)
            }
            // Кадра нет: файл есть — плашка с именем (204), нет — 404.
            return Self.httpResponse(status: FileManager.default.fileExists(atPath: path) ? 204 : 404,
                                     contentType: nil, body: nil, access: access)
        case .file:
            var info = stat()
            guard let type = ChatMedia.imageTypes[ext], stat(path, &info) == 0, info.st_size <= ChatMedia.maxFileBytes,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return Self.httpResponse(status: 404, contentType: nil, body: nil, access: access)
            }
            return Self.httpResponse(status: 200, contentType: type, body: data, access: access)
        }
    }

    /// `/open-html` по имени: путь — у галереи; нашёлся — как клик по файлу (док — ответ по доку, без дока — прежний
    /// `click`, ответ сразу). Не нашёлся — `found:false`, страница вернёт плеер Claude.
    func serveNamedOpen(_ open: ChatMedia.Open, access: PageAccess, _ connection: NWConnection) {
        let lost = Self.namedOpenResponse(found: false, taken: false, opened: false, access: access)
        let extensions = Self.chromeExtensions.union(Self.imageExtensions).union(Self.dockExtensions)
        hold(connection, wait: ChatMedia.openWait, late: lost) { [weak self] reply in
            guard let self = self else { return reply(lost) }
            self.locateMedia(chat: open.chat, name: open.name, path: nil, extensions: extensions) { [weak self] path in
                guard let self = self, let path = path else { return reply(lost) }
                let request = open.request(path: path)
                if request.dock != nil, self.toDock != nil {
                    return self.routeDock(request) {
                        reply(Self.namedOpenResponse(found: true, taken: $0, opened: $1, access: access))
                    }
                }
                reply(Self.namedOpenResponse(found: true, taken: false, opened: false, access: access))
                self.route(request)
            }
        }
    }

    /// `200 {found, taken, opened}` на `/open-html` по имени.
    static func namedOpenResponse(found: Bool, taken: Bool, opened: Bool, access: PageAccess) -> Data {
        httpResponse(status: 200, contentType: "application/json; charset=utf-8",
                     body: Data(#"{"found":\#(found),"taken":\#(taken),"opened":\#(opened)}"#.utf8), access: access)
    }
}

extension ClaudeAXController {
    /// Ролики и картинки с диска (#10699): путь по имени — у галереи. Зовут из `start()`.
    func connectChatMedia() {
        htmlOpener.media.resolve = { [weak self] chat, name, done in
            guard let self = self else { return done(nil) }
            self.viewerClient.resolve(chat: chat, name: name, done: done)
        }
    }
}
