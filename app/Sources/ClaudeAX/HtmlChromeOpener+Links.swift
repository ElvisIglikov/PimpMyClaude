import AppKit
import Foundation
import Network

/// Наши ссылки из чата (WF288, #10892; контракт `docs/contracts/600-wf288-our-links.md`, К-LINK). Слово Элвиса 24.10.2026
/// о ссылке задачи Trelvis в сообщении Рика: «Нажимаю, ничего не происходит». Свою схему `trelvis://` Claude молча
/// выбрасывает, https — в браузер справа; страница (раздел 12д²) отдаёт адрес сюда:
/// `GET /open-link?url=<адрес в percent-encoding>`.
///
/// Берём ТОЛЬКО адреса белого списка — задача Trelvis (`https://vlusnoff-production.up.railway.app/#t/N` или `#task/N`,
/// `trelvis://task/N`, `kaban://task/N`); худшее, что может чужая страница, — показать Элвису его задачу. Есть программа
/// для `trelvis://` (Trelvis.app) — `trelvis://task/N`, иначе веб-Трелвис в Google Chrome (правило Элвиса 27.09.2026
/// «Ссылки — в Google Chrome»). Ответ — `200 {"opened":true,"via":"trelvis"|"chrome"}`, чужой адрес — `400 {"opened":false}`.
extension HtmlChromeOpener {
    /// Что открыть по ссылке белого списка.
    public enum LinkTarget: Equatable {
        case trelvisTask(Int)
    }

    /// Чем открыть: адрес и слово `via` ответа странице.
    public struct LinkPlan: Equatable {
        public let url: URL
        public let via: String
    }

    static let trelvisWeb = "https://vlusnoff-production.up.railway.app/"
    static let linkPatterns = [
        #"^https://vlusnoff-production\.up\.railway\.app/#(?:t|task)/[1-9][0-9]{0,8}$"#,
        #"^(?:trelvis|kaban)://task/[1-9][0-9]{0,8}$"#,
    ]

    /// Адрес ссылки → цель; не из белого списка — nil. Чистая.
    static func linkTarget(_ raw: String) -> LinkTarget? {
        guard raw.count <= 128, linkPatterns.contains(where: { raw.range(of: $0, options: .regularExpression) != nil }),
              let tail = raw.split(separator: "/").last, let number = Int(tail), number > 0 else { return nil }
        return .trelvisTask(number)
    }

    /// `GET /open-link?url=<enc>` → цель; другой путь, нет `url` или чужой адрес — nil. Чистая.
    static func parseLink(_ head: String) -> LinkTarget? {
        guard let components = query(head, path: "/open-link"),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value else { return nil }
        return linkTarget(raw)
    }

    static func trelvisURL(task: Int) -> URL { URL(string: "trelvis://task/\(task)")! }

    /// Есть Trelvis.app — его схема, нет — веб-Трелвис в Chrome. Чистая.
    static func linkPlan(_ target: LinkTarget, hasTrelvis: Bool) -> LinkPlan {
        switch target {
        case .trelvisTask(let task):
            return hasTrelvis ? LinkPlan(url: trelvisURL(task: task), via: "trelvis")
                : LinkPlan(url: URL(string: "\(trelvisWeb)#task/\(task)")!, via: "chrome")
        }
    }

    /// `200 {"opened":true,"via":…}` или `400 {"opened":false}`; CORS — как у остальных ручек страницы.
    static func linkResponse(_ plan: LinkPlan?, access: PageAccess) -> Data {
        let body = plan.map { #"{"opened":true,"via":"\#($0.via)"}"# } ?? #"{"opened":false}"#
        return httpResponse(status: plan == nil ? 400 : 200, contentType: "application/json; charset=utf-8",
                            body: Data(body.utf8), access: access)
    }

    /// Ответ сразу, открытие — после него (`linkOpen`, живьём — главная очередь).
    func serveLink(_ head: String, access: PageAccess, _ connection: NWConnection) {
        if Self.isWebLink(head) { return serveWeb(head, access: access, connection) }  // #11323, +WebTab
        let plan = Self.parseLink(head).map { target -> LinkPlan in
            switch target {
            case .trelvisTask(let task): return Self.linkPlan(target, hasTrelvis: linkHasApp(Self.trelvisURL(task: task)))
            }
        }
        connection.send(content: Self.linkResponse(plan, access: access), completion: .contentProcessed { _ in
            connection.cancel()
        })
        if let plan = plan { linkOpen(plan) }
    }

    /// Живое открытие: `trelvis://` — системе (Trelvis.app), https — в Google Chrome, его нет — браузеру по умолчанию.
    static func openLinkLive(_ plan: LinkPlan) {
        DispatchQueue.main.async {
            guard plan.via == "chrome",
                  let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeBundleID) else {
                NSWorkspace.shared.open(plan.url)
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([plan.url], withApplicationAt: chrome, configuration: configuration)
        }
    }
}
