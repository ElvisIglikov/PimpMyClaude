import Foundation
import Network

/// Кадр панели материалов для скриншотилок (#10760, WF279, К-DOCK-4; слово Элвиса 23.10.2026: «Сделай, чтобы на скриншоте
/// тоже было видно. Это важно. И в Диктаторе, и в других программах скриншотилках»). Панель — отдельное окно PimpViewer
/// поверх окна Claude, а снимок окна берёт одно окно Claude: на месте панели выходила пустая подложка. PimpViewer снимает
/// страницу дока в `viewer/dock-shot.jpg`; страница Claude (раздел 12п⁴¹) забирает кадр здесь и кладёт в подложку под
/// панелью.
///
/// `GET /dock-shot?since=<версия>` (CORS как у `/media-file`, путь — в белом списке `PageHTTPAccess`) →
/// `200 image/jpeg` с `X-Pimp-Shot: <версия>` | `204` — версия та же | `404` — кадра нет | `400` — битая версия.
/// Версия — `<mtime, мс>.<размер>` файла. Читается только этот файл.
extension HtmlChromeOpener {
    static let dockShotPath = "/dock-shot"
    static let dockShotMaxBytes = 16 * 1024 * 1024
    static let dockShotHeader = "X-Pimp-Shot"

    /// Запрос `/dock-shot`: nil — не он; `.some(nil)` — битая версия (400); иначе версия страницы ("" — первый запрос).
    static func parseDockShot(_ head: String) -> String?? {
        guard let components = query(head, path: dockShotPath) else { return nil }
        let since = components.queryItems?.first(where: { $0.name == "since" })?.value ?? ""
        guard since.count <= 40, since.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return .some(nil) }
        return .some(since)
    }

    /// Версия файла кадра; нет файла или не обычный файл — nil.
    static func dockShotVersion(_ url: URL) -> (version: String, size: Int)? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 0 else { return nil }
        let millis = Int64(info.st_mtimespec.tv_sec) * 1000 + Int64(info.st_mtimespec.tv_nsec) / 1_000_000
        return ("\(millis).\(info.st_size)", Int(info.st_size))
    }

    /// Ответ на `/dock-shot` по файлу `url`. С любой очереди.
    static func dockShotResponse(since: String, file url: URL, access: PageAccess) -> Data {
        guard let found = dockShotVersion(url), found.size <= dockShotMaxBytes else {
            return httpResponse(status: 404, contentType: nil, body: nil, access: access)
        }
        if found.version == since { return httpResponse(status: 204, contentType: nil, body: nil, access: access) }
        guard let jpeg = try? Data(contentsOf: url), jpeg.count >= 3, jpeg.prefix(3) == Data([0xFF, 0xD8, 0xFF]),
              let version = dockShotVersion(url)?.version else {
            return httpResponse(status: 404, contentType: nil, body: nil, access: access)
        }
        let response = httpResponse(status: 200, contentType: "image/jpeg", body: jpeg, access: access)
        guard let end = response.range(of: Data("\r\n".utf8)) else { return response }
        var extra = "\(dockShotHeader): \(version)\r\n"
        if case .browser = access { extra += "Access-Control-Expose-Headers: \(dockShotHeader)\r\n" }
        var out = response
        out.insert(contentsOf: Data(extra.utf8), at: end.upperBound)
        return out
    }

    func serveDockShot(since: String?, access: PageAccess, _ connection: NWConnection) {
        guard let since = since else {
            return connection.send(content: Self.httpResponse(status: 400, contentType: nil, body: nil, access: access),
                                   completion: .contentProcessed { _ in connection.cancel() })
        }
        let file = dockShotFile
        let missing = Self.httpResponse(status: 404, contentType: nil, body: nil, access: access)
        hold(connection, wait: Self.viewerReplyWait, late: missing) { [media] reply in
            media.queue.async { reply(Self.dockShotResponse(since: since, file: file, access: access)) }
        }
    }
}
