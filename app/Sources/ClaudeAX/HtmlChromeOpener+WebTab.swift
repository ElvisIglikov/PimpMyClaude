import AppKit
import Foundation
import Network

/// Внешняя ссылка из чата — на уже открытую вкладку браузера (#11323, продолжение #11118; К-LINK,
/// `docs/contracts/600-wf288-our-links.md`). Слово Элвиса 31.10.2026: «Я чик нажал и перешёл сразу в Хром на нужную
/// вкладку». Страница (раздел 12д³) отдаёт адрес сюда: `GET /open-link?kind=web&url=<адрес в percent-encoding>`.
///
/// Тот же путь и тот же белый список `PageHTTPAccess`, что у задач Trelvis, — новый вид запроса (`kind=web`), а не новая
/// ручка: старый Пимп без вида отвечает на такой адрес `400` (адрес не из списка задач), и страница уходит в прежний
/// `window.open`. Берём любой http(s), кроме адресов самого Claude. Браузер по умолчанию на Chromium — AppleScript ищет
/// вкладку с этим адресом (без `#фрагмента`, конечного «/» и схемы http/https) и выводит её вперёд БЕЗ перечитывания
/// (это веб-страница, не файл); нет — новая вкладка в переднем окне. Браузер не Chromium или скрипт не прошёл (нет
/// разрешения Automation) — `NSWorkspace.open(url)`. Ответ — `200 {"opened":true,"via":"web"}` сразу, открытие — после.
extension HtmlChromeOpener {
    static let webMaxLength = 4096
    static let webClaudeHosts = ["claude.ai", "claude.com", "anthropic.com"]

    /// `kind=web` в запросе `/open-link` — развилка `serveLink`. Чистая.
    static func isWebLink(_ head: String) -> Bool {
        query(head, path: "/open-link")?.queryItems?.contains(where: { $0.name == "kind" && $0.value == "web" }) == true
    }

    /// Адрес → URL для открытия: только http(s) с хостом, не Claude, не длиннее `webMaxLength`; иначе nil. Чистая.
    static func webURL(_ raw: String) -> URL? {
        guard raw.count <= webMaxLength, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        if webClaudeHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) { return nil }
        return url
    }

    /// `GET /open-link?kind=web&url=<enc>` → адрес; нет вида, нет `url` или отказ — nil. Чистая.
    static func parseWeb(_ head: String) -> URL? {
        guard isWebLink(head), let components = query(head, path: "/open-link"),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value else { return nil }
        return webURL(raw)
    }

    /// Ключ сравнения вкладок: без `#фрагмента`, без схемы `http://`/`https://` (хост остаётся — чужой сайт не совпадёт),
    /// без одного конечного «/». Тот же разбор — в AppleScript (`pimpWebKey`). Чистая.
    static func webKey(_ url: String) -> String {
        var key = url
        if let hash = key.firstIndex(of: "#") { key = String(key[..<hash]) }
        for prefix in ["https://", "http://"] where key.lowercased().hasPrefix(prefix) {
            key = String(key.dropFirst(prefix.count))
            break
        }
        if key.count > 1, key.hasSuffix("/") { key.removeLast() }
        return key
    }

    static func appleScriptString(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// AppleScript веб-вкладки для Chromium-браузера: та же страница открыта — вперёд без `reload`, нет — новая вкладка.
    /// Чистая, её гоняют тесты.
    static func webTabScript(url: String, browser: String = "Google Chrome") -> String {
        """
        on pimpWebKey(u)
            try
                set k to u as text
            on error
                return ""
            end try
            set o to offset of "#" in k
            if o is 1 then return ""
            if o > 1 then set k to text 1 thru (o - 1) of k
            if k starts with "https://" and (length of k) > 8 then
                set k to text 9 thru -1 of k
            else if k starts with "http://" and (length of k) > 7 then
                set k to text 8 thru -1 of k
            end if
            if (length of k) > 1 and k ends with "/" then set k to text 1 thru -2 of k
            return k
        end pimpWebKey

        set target to "\(appleScriptString(url))"
        set targetKey to "\(appleScriptString(webKey(url)))"
        tell application "\(appleScriptString(browser))"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    considering case
                        set isSame to (my pimpWebKey(URL of t)) is targetKey
                    end considering
                    if isSame then
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

    /// Каким путём пошло открытие (для тестов и счёта).
    enum WebOutcome: Equatable {
        /// Chromium, скрипт прошёл — вкладка вперёд или новая.
        case script
        /// Chromium, скрипт не прошёл — `open(url)`.
        case scriptFailed
        /// Браузер не Chromium или его нет — `open(url)`.
        case open
    }

    /// Выбор пути. Зовут не на главной нити: `runScript` ждёт osascript. Подставки — у тестов.
    @discardableResult
    static func openWeb(_ url: URL, route: BrowserRoute, runScript: (String) -> Bool,
                        open: (URL) -> Void, activate: (URL) -> Void) -> WebOutcome {
        guard case .script(let name, let app) = route else {
            open(url)
            return .open
        }
        if runScript(webTabScript(url: url.absoluteString, browser: name)) {
            activate(app)
            return .script
        }
        open(url)
        return .scriptFailed
    }

    /// osascript ведём здесь, не на главной нити и не на очереди порта (как `openQueue` у файлов).
    static let webQueue = DispatchQueue(label: "pimpmyclaude.html-chrome.web", qos: .userInitiated)

    /// Живое открытие: на `webQueue` выбор пути, `NSWorkspace` — на главной.
    static func openWebLive(_ url: URL) {
        webQueue.async {
            openWeb(url, route: browserRoute, runScript: runOsascript, open: { target in
                DispatchQueue.main.async { NSWorkspace.shared.open(target) }
            }, activate: { app in
                DispatchQueue.main.async {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                }
            })
        }
    }

    /// osascript с текстом скрипта; вышел с 0 — true.
    static func runOsascript(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return false }
        return process.terminationStatus == 0
    }

    /// `/open-link?kind=web`: ответ сразу (`200 {"opened":true,"via":"web"}` или `400 {"opened":false}`), открытие —
    /// после него (`webOpen`).
    func serveWeb(_ head: String, access: PageAccess, _ connection: NWConnection) {
        let url = Self.parseWeb(head)
        let plan = url.map { LinkPlan(url: $0, via: "web") }
        connection.send(content: Self.linkResponse(plan, access: access), completion: .contentProcessed { _ in
            connection.cancel()
        })
        if let url = url { webOpen(url) }
    }
}
