import AppKit
import Foundation
import Network

/// HTML-файлы из чата — в Chrome, а не в панель Browser у Claude (#6618; слово Элвиса 20.09.2026:
/// «одно нажатие на HTML-ку открывает его в Хроме… если файл уже открыт — вкладки новые не открывал,
/// ту же открытую показывал»).
///
/// Страница (`inject.js`, раздел 12д) просит об этом запросом на свой же Мак:
/// `GET http://127.0.0.1:47615/open-html?mode=<click|auto>&path=<путь в percent-encoding>`.
/// Другого быстрого пути от страницы к приложению нет: канал probe отвечает за 15 с, а буфер обмена
/// занят человеком. Слушаем ТОЛЬКО 127.0.0.1, берём только существующий `.html`/`.htm` с абсолютным
/// путём — худшее, что может чужая страница, это показать Элвису его же файл.
///
/// Chrome ведём AppleScript'ом через `/usr/bin/osascript`: вкладка с этим файлом есть — `click`
/// выводит её вперёд и перечитывает, `auto` перечитывает молча; вкладки нет — открываем новую и
/// выводим Chrome вперёд. macOS один раз спросит «PimpMyClaude хочет управлять Google Chrome».
/// Скрипт не прошёл (нет разрешения) — файл открывается в Chrome обычным путём, новой вкладкой.
public final class HtmlChromeOpener {
    public static let port: UInt16 = 47615
    public static let chromeBundleID = "com.google.Chrome"
    /// Vivaldi стоит — страницы идут в него (слово Элвиса 20.09.2026, #6652: «в Вивальди по
    /// высоте больше, чем в Хроме»); он на Chromium и понимает тот же AppleScript. Нет его
    /// (команда) — Chrome, как раньше.
    public static let vivaldiBundleID = "com.vivaldi.Vivaldi"
    static var browser: (name: String, bundleID: String) {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: vivaldiBundleID) != nil
            ? ("Vivaldi", vivaldiBundleID) : ("Google Chrome", chromeBundleID)
    }
    public static let previewBundleID = "com.apple.Preview"
    /// Страницы и PDF — в Chrome, картинки — в «Просмотр» (#6621).
    public static let chromeExtensions: Set<String> = ["html", "htm", "pdf"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"]

    public enum Mode: String { case click, auto }
    public struct Request: Equatable {
        public let path: String
        public let mode: Mode
    }

    /// Скрипт не прошёл — повод для плашки.
    public var onScriptFailed: (() -> Void)?
    public private(set) var opened = 0
    public private(set) var failed = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pimpmyclaude.html-chrome")

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

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            let head = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let request = Self.parse(head)
            let reply = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\n"
                + "Access-Control-Allow-Private-Network: true\r\nConnection: close\r\n\r\n"
            connection.send(content: reply.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            if let request = request, Self.isPage(request.path) { self?.open(request) }
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
              path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        guard chromeExtensions.contains(ext) || imageExtensions.contains(ext) else { return nil }
        let mode = components.queryItems?.first(where: { $0.name == "mode" })?.value
        return Request(path: path, mode: Mode(rawValue: mode ?? "") ?? .click)
    }

    static func isPage(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
    }

    /// AppleScript для Chrome. Чистая, её и гоняют тесты.
    public static func script(url: String, mode: Mode, browser: String = "Google Chrome") -> String {
        let target = url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let bring = mode == .click ? """
                        set active tab index of w to i
                        set index of w to 1
                        activate

        """ : ""
        return """
        tell application "\(browser)"
            set target to "\(target)"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    if URL of t is target then
                        reload t
        \(bring)                return "found"
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

    private func open(_ request: Request) {
        let file = URL(fileURLWithPath: request.path)
        if Self.imageExtensions.contains(file.pathExtension.lowercased()) {
            opened += 1
            DispatchQueue.main.async { Self.launch(file, in: Self.previewBundleID) }
            return
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let browser = Self.browser
        process.arguments = ["-e", Self.script(url: file.absoluteString, mode: request.mode, browser: browser.name)]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}
        if process.isRunning == false, process.terminationStatus == 0 {
            opened += 1
            let answer = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // `activate` из скрипта фонового приложения macOS вперёд не выводит (#6622) — выводим
            // Chrome через LaunchServices. Авто-открытие при уже открытой вкладке Chrome не трогает.
            if request.mode == .click || !answer.contains("found") {
                DispatchQueue.main.async { Self.launch(nil, in: browser.bundleID) }
            }
            return
        }
        failed += 1
        DispatchQueue.main.async { [weak self] in
            // Без разрешения на Chrome — хотя бы обычным путём: новая вкладка лучше тишины.
            Self.launch(file, in: browser.bundleID)
            self?.onScriptFailed?()
        }
    }

    /// Открыть файл программой (или просто вывести её вперёд, если файла нет); программы нет —
    /// файл уходит программе по умолчанию.
    private static func launch(_ file: URL?, in bundleID: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            if let file = file { NSWorkspace.shared.open(file) }
            return
        }
        if let file = file {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        }
    }
}
