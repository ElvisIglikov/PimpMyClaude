import AppKit
import Foundation

/// «📦 Архив чатов» (#7729, батч Б2 WF94): один zip со всеми чатами вкладки Code — переписки
/// `~/.claude/projects/**` (субагенты лежат внутри папки родительского чата и в счёт чатов не
/// идут) и метаданные Claude Desktop — плюс `ОГЛАВЛЕНИЕ.html` внутри. Склад —
/// `<projectsRoot>/_Не удалять/Склад чатов Claude/`, нет папки проектов — запасной в
/// Application Support. Склад в iCloud — отказ: в переписках бывают ключи, в облако без слова
/// человека не отдаём. Пишем во временный `.partial` и переименовываем в конце; старые архивы
/// не удаляем. Корни источников и склада — параметрами: тесты гоняют всё во временных каталогах.
public final class ChatArchive {
    /// Источник: что и под каким именем лежит в архиве. `chats` — источник переписок, по нему
    /// считаются чаты и оглавление; пустой или его нет — отказ.
    public struct Source {
        public let url: URL
        public let name: String
        public let chats: Bool
        public init(url: URL, name: String, chats: Bool = false) {
            self.url = url
            self.name = name
            self.chats = chats
        }
    }

    public struct Summary: Equatable {
        public let archive: URL
        public let chats: Int
        public let bytes: Int64
        public let storeCount: Int
        public let storeBytes: Int64

        public var notice: String {
            "💾 Бэкап готов: \(ChatArchive.chatsWord(chats)), \(ChatArchive.megabytes(bytes)) МБ · "
                + "на складе \(ChatArchive.archivesWord(storeCount)), \(ChatArchive.megabytes(storeBytes)) МБ"
        }
    }

    public enum Failure: Error, Equatable {
        case emptySource
        case inCloud(String)
        case noSpace(needed: Int64, free: Int64)
        case failed(String)

        public var notice: String {
            switch self {
            case .emptySource:
                return "💾 Бэкапить нечего: чатов Claude Code на этом Маке нет"
            case .inCloud(let path):
                return "💾 Склад чатов лежит в iCloud (\(path)) — бэкап не пишу: в переписках бывают ключи"
            case .noSpace(let needed, let free):
                return "💾 Мало места для бэкапа: нужно \(ChatArchive.megabytes(needed)) МБ, свободно \(ChatArchive.megabytes(free)) МБ"
            case .failed(let why):
                return "💾 Бэкап не собрался: \(why)"
            }
        }
    }

    /// Одна строка оглавления.
    struct Entry: Equatable {
        var title: String
        var project: String
        var file: String
        var first: Date?
        var last: Date?
        var messages: Int
    }

    public static let storeFolderName = "Склад чатов Claude"
    public static let keepFolderName = "_Не удалять"
    static let tocName = "ОГЛАВЛЕНИЕ.html"
    static let partialSuffix = ".partial"

    let sources: [Source]
    let store: URL
    let now: () -> Date
    let freeSpace: (URL) -> Int64?
    let isCloud: (URL) -> Bool
    private let queue = DispatchQueue(label: "pimpmyclaude.chat-archive", qos: .utility)
    /// Идёт сборка: второй клик ничего не делает. Трогается только на главной нитке.
    public private(set) var isBusy = false

    public init(sources: [Source], store: URL, now: @escaping () -> Date = Date.init,
                freeSpace: @escaping (URL) -> Int64? = ChatArchive.availableSpace,
                isCloud: @escaping (URL) -> Bool = ChatArchive.isInCloud) {
        self.sources = sources
        self.store = store
        self.now = now
        self.freeSpace = freeSpace
        self.isCloud = isCloud
    }

    /// Настоящие источники и склад этого Мака.
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ChatArchive {
        let desktop = home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        let sources = [
            Source(url: home.appendingPathComponent(".claude/projects", isDirectory: true),
                   name: "Claude Code/projects", chats: true),
            Source(url: desktop.appendingPathComponent("claude-code-sessions", isDirectory: true),
                   name: "Claude Desktop/claude-code-sessions"),
            Source(url: desktop.appendingPathComponent("local-agent-mode-sessions", isDirectory: true),
                   name: "Claude Desktop/local-agent-mode-sessions"),
        ]
        // Корень — только заданный явно в claude.json (как `TrustRoot`, гейт 2 WF108): умолчание
        // `~/Projects` молча увезло бы склад команды из Application Support.
        return ChatArchive(sources: sources,
                           store: storeFolder(projectsRoot: TrustRoot.current()
                                                .map { URL(fileURLWithPath: $0, isDirectory: true) },
                                              fallback: CommandChannel.directory))
    }

    // MARK: - склад и имя

    /// `<projectsRoot>/_Не удалять/Склад чатов Claude/`; корня нет (ключ `projectsRoot` не задан) или
    /// папки нет — `<fallback>/Склад чатов Claude/`.
    static func storeFolder(projectsRoot: URL?, fallback: URL, fileManager: FileManager = .default) -> URL {
        var isDir: ObjCBool = false
        if let projectsRoot = projectsRoot,
           fileManager.fileExists(atPath: projectsRoot.path, isDirectory: &isDir), isDir.boolValue {
            return projectsRoot.appendingPathComponent(keepFolderName, isDirectory: true)
                .appendingPathComponent(storeFolderName, isDirectory: true)
        }
        return fallback.appendingPathComponent(storeFolderName, isDirectory: true)
    }

    /// `Claude-чаты-ГГГГ-ММ-ДД-ЧЧММ.zip` по местному времени.
    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Claude-чаты-\(formatter.string(from: date)).zip"
    }

    /// iCloud Drive («Рабочий стол и Документы» тоже) или папка file-provider: путь или
    /// ближайший существующий предок помечен облачным.
    public static func isInCloud(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.contains("/Library/Mobile Documents/") || path.contains("/Library/CloudStorage/") { return true }
        var probe = url.standardizedFileURL
        while probe.path != "/" {
            if FileManager.default.fileExists(atPath: probe.path) {
                let values = try? probe.resourceValues(forKeys: [.isUbiquitousItemKey])
                return values?.isUbiquitousItem == true
            }
            probe.deleteLastPathComponent()
        }
        return false
    }

    public static func availableSpace(_ url: URL) -> Int64? {
        var probe = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" { probe.deleteLastPathComponent() }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                         .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    // MARK: - сборка

    /// Собрать в фоне. false — уже собирается (второй клик — ничего). Ответ — на главной нитке.
    @discardableResult
    public func start(_ done: @escaping (Result<Summary, Failure>) -> Void) -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        queue.async { [self] in
            let outcome: Result<Summary, Failure>
            do { outcome = .success(try make()) } catch let failure as Failure {
                outcome = .failure(failure)
            } catch {
                outcome = .failure(.failed(error.localizedDescription))
            }
            DispatchQueue.main.async {
                self.isBusy = false
                done(outcome)
            }
        }
        return true
    }

    /// Собрать сейчас, на этой нитке (тесты зовут напрямую).
    func make() throws -> Summary {
        let fm = FileManager.default
        let present = sources.filter { fm.fileExists(atPath: $0.url.path) }
        let chatFiles = present.filter(\.chats).flatMap { Self.chatFiles(in: $0.url) }
        guard !chatFiles.isEmpty else { throw Failure.emptySource }
        if isCloud(store) { throw Failure.inCloud(store.path) }

        let sourceBytes = present.reduce(Int64(0)) { $0 + Self.size(of: $1.url) }
        // Копия источников во временную папку клонируется (APFS, тот же том) и места не ест; на
        // другом томе — честная копия, её тоже в счёт.
        let sameVolume = present.allSatisfy { Self.volume(of: $0.url) != nil && Self.volume(of: $0.url) == Self.volume(of: store) }
        let margin = max(Int64(50 << 20), sourceBytes / 10)
        let needed = sourceBytes * (sameVolume ? 1 : 2) + margin
        if let free = freeSpace(store), free < needed { throw Failure.noSpace(needed: needed, free: free) }

        do {
            try fm.createDirectory(at: store, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: store.path)
        } catch { throw Failure.failed("не создать склад \(store.path)") }

        let target = uniqueTarget(Self.fileName(for: now()))
        let partial = target.deletingLastPathComponent()
            .appendingPathComponent(target.lastPathComponent + Self.partialSuffix)
        let staging = store.appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent).staging",
                                                   isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for source in present {
                let into = staging.appendingPathComponent(source.name, isDirectory: true)
                try fm.createDirectory(at: into.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source.url, to: into)
            }
            let entries = chatFiles.map(Self.entry(for:)).map { entry -> Entry in
                var entry = entry
                entry.file = relative(entry.file, present)
                return entry
            }
            try Data(Self.tocHTML(entries, made: now()).utf8)
                .write(to: staging.appendingPathComponent(Self.tocName))
            try zip(staging, into: partial)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: partial.path)
            try fm.moveItem(at: partial, to: target)
        } catch {
            try? fm.removeItem(at: partial)
            if let failure = error as? Failure { throw failure }
            throw Failure.failed(error.localizedDescription)
        }
        let bytes = Self.size(of: target)
        let archives = ((try? fm.contentsOfDirectory(at: store, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "zip" }
        return Summary(archive: target, chats: chatFiles.count, bytes: bytes, storeCount: archives.count,
                       storeBytes: archives.reduce(Int64(0)) { $0 + Self.size(of: $1) })
    }

    /// Два архива в одну минуту — второму суффикс, старый не затираем.
    private func uniqueTarget(_ name: String) -> URL {
        var url = store.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = store.appendingPathComponent(name.replacingOccurrences(of: ".zip", with: "-\(n).zip"))
            n += 1
        }
        return url
    }

    /// Путь файла чата внутри архива — для колонки «Файл» оглавления.
    private func relative(_ path: String, _ present: [Source]) -> String {
        for source in present where path.hasPrefix(source.url.standardizedFileURL.path + "/") {
            return source.name + String(path.dropFirst(source.url.standardizedFileURL.path.count))
        }
        return path
    }

    private func zip(_ folder: URL, into archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", folder.path, archive.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.failed("ditto не запустился") }
        let tail = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.failed("ditto: \(text.isEmpty ? "код \(process.terminationStatus)" : text)")
        }
    }

    // MARK: - чаты и оглавление

    /// Чат — `<проект>/<id>.jsonl` прямо в папке проекта; всё глубже (субагенты, результаты
    /// инструментов) — часть родительского чата.
    static func chatFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return projects.flatMap { project -> [URL] in
            guard (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: nil) else { return [] }
            return files.filter { $0.pathExtension == "jsonl" }
        }.sorted { $0.path < $1.path }
    }

    private static let markers = ["\"user\"", "\"assistant\"", "custom-title", "\"summary\""].map { Data($0.utf8) }

    /// Строка оглавления из файла переписки: название (своё имя чата, итог, первая реплика
    /// человека), проект (папка `cwd`), первое и последнее сообщение, их число.
    static func entry(for file: URL) -> Entry {
        let folder = file.deletingLastPathComponent().lastPathComponent
        var entry = Entry(title: "", project: folder, file: file.standardizedFileURL.path, first: nil, last: nil, messages: 0)
        var custom: String?
        var summary: String?
        var firstPrompt: String?
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            entry.title = file.deletingPathExtension().lastPathComponent
            return entry
        }
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard markers.contains(where: { line.range(of: $0) != nil }),
                  let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            switch type {
            case "custom-title":
                if let title = object["customTitle"] as? String, !title.isEmpty { custom = title }
            case "summary":
                if let text = object["summary"] as? String, !text.isEmpty { summary = text }
            case "user", "assistant":
                if let cwd = object["cwd"] as? String, !cwd.isEmpty {
                    entry.project = URL(fileURLWithPath: cwd).lastPathComponent
                }
                if object["isMeta"] as? Bool == true || object["toolUseResult"] != nil { continue }
                entry.messages += 1
                if let stamp = (object["timestamp"] as? String).flatMap(date(from:)) {
                    entry.first = min(entry.first ?? stamp, stamp)
                    entry.last = max(entry.last ?? stamp, stamp)
                }
                if type == "user", firstPrompt == nil, let text = promptText(object["message"]) { firstPrompt = text }
            default:
                continue
            }
        }
        entry.title = custom ?? summary ?? firstPrompt ?? file.deletingPathExtension().lastPathComponent
        return entry
    }

    private static func promptText(_ message: Any?) -> String? {
        guard let message = message as? [String: Any] else { return nil }
        var text: String?
        if let plain = message["content"] as? String {
            text = plain
        } else if let blocks = message["content"] as? [[String: Any]] {
            text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        }
        guard let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clean.isEmpty, !clean.hasPrefix("<") else { return nil }
        let line = clean.replacingOccurrences(of: "\n", with: " ")
        return line.count > 90 ? String(line.prefix(90)) + "…" : line
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let whole = ISO8601DateFormatter()

    private static func date(from text: String) -> Date? {
        fractional.date(from: text) ?? whole.date(from: text)
    }

    /// Автономная тёмная страница без внешних ресурсов (SkilZZZ/HTML.md): свежие чаты сверху.
    static func tocHTML(_ entries: [Entry], made: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        let show = { (date: Date?) in date.map(formatter.string(from:)) ?? "—" }
        let sorted = entries.sorted { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }
        let rows = sorted.enumerated().map { index, entry in
            "<tr><td class=n>\(index + 1)</td><td><b>\(escape(entry.title))</b><div class=f>\(escape(entry.file))</div></td>"
                + "<td>\(escape(entry.project))</td><td class=d>\(show(entry.first))</td>"
                + "<td class=d>\(show(entry.last))</td><td class=n>\(entry.messages)</td></tr>"
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="ru"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Бэкап чатов Claude · \(show(made))</title>
        <style>
        :root { color-scheme: dark; }
        body { margin: 0; padding: 24px 16px; background: #15171c; color: #e6e6e6;
               font: 20px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
        h1 { font-size: 3rem; line-height: 1.1; margin: 0 0 8px; }
        p { color: #9aa0a6; margin: 0 0 20px; }
        .wrap { overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; min-width: 760px; }
        th, td { text-align: left; vertical-align: top; padding: 10px 12px; border-bottom: 1px solid #2a2e36; }
        th { color: #9aa0a6; font-weight: 500; font-size: 16px; }
        td.n { text-align: right; color: #9aa0a6; }
        td.d { white-space: nowrap; }
        .f { color: #6f7680; font-size: 14px; word-break: break-all; margin-top: 4px; }
        @media (max-width: 500px) { body { font-size: 18px; } h1 { font-size: 2.2rem; } }
        </style></head><body>
        <h1>Бэкап чатов Claude</h1>
        <p>Собран \(show(made)) · \(chatsWord(entries.count)) · переписки — в папке «Claude Code/projects», субагенты — внутри папки своего чата</p>
        <div class="wrap"><table>
        <tr><th>№</th><th>Чат</th><th>Проект</th><th>Первое</th><th>Последнее</th><th>Сообщений</th></tr>
        \(rows)
        </table></div>
        </body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - мелочи

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private static func volume(of url: URL) -> String? {
        var probe = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" { probe.deleteLastPathComponent() }
        return ((try? probe.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier).map { "\($0)" }
    }

    static func megabytes(_ bytes: Int64) -> String {
        let value = Double(bytes) / 1_048_576
        return value < 10 ? String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
                          : String(Int(value.rounded()))
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tail = n % 100
        if (11...14).contains(tail) { return "\(n) \(many)" }
        switch n % 10 {
        case 1: return "\(n) \(one)"
        case 2...4: return "\(n) \(few)"
        default: return "\(n) \(many)"
        }
    }

    static func chatsWord(_ n: Int) -> String { plural(n, "чат", "чата", "чатов") }
    static func archivesWord(_ n: Int) -> String { plural(n, "бэкап", "бэкапа", "бэкапов") }

    // MARK: - плашка «готово»

    /// Итог с кнопкой «Показать в Finder». HUD мышь не ловит — поэтому алерт, как у остальных
    /// вопросов приложения (LSUIElement: без activate окно ушло бы за Claude).
    static func presentDone(_ summary: Summary) {
        let alert = NSAlert()
        alert.messageText = summary.notice
        alert.informativeText = summary.archive.path
        // OK — первой, кнопкой по умолчанию: алерт отнимает фокус у Claude, и Enter, набранный
        // в поле ввода, не должен открывать Finder (проверка гейта WF94).
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Показать в Finder")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([summary.archive])
        }
    }
}
