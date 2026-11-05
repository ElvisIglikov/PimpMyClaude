import AppKit
import CoreServices
import Foundation

// Открытые терминалы в панели (#10464, слово Элвиса 21.10.2026: «Открытые терминалы, может быть, выведем в ПимП.
// Сверху вот там вот… чтоб они видимыми стали, те терминалы, с которыми работа идёт. И заголовки терминалов, чтоб
// были с названиями проектов»). Терминал — живая сессия tmux `rick-<проект>` (как у `pimp.py term`); строка —
// «<маркер> <Проект>» и идёт ли в нём ход (`PanelTiles.inTurn`, #10460); нажатие — окно Terminal этой сессии
// (как `pimp.py term <проект> --show`). Заголовки окон всех терминалов — «<Проект>», без маркера (`retitle`, #10564).

/// Один открытый терминал.
public struct PanelTerminal: Equatable, Identifiable {
    /// Имя после `rick-`: «VkusSES».
    public let session: String
    /// «🧼 VkusSES»; маркера нет — имя.
    public let title: String
    /// Сейчас идёт ход.
    public let turning: Bool
    /// Когда кеш промпта остынет (#10464, слово Элвиса 21.10 12:10: «сколько до протухания таймеров на терминалах…
    /// кэш тёплый, не тёплый»): кеш живёт `cacheSeconds` с последней записи CLI-транскрипта папки проекта (правило
    /// грелки Рика, `Rick/tools/kesh_grelka.py`); nil — транскрипта нет.
    public let coolsAt: Date?

    public init(session: String, title: String, turning: Bool, coolsAt: Date? = nil) {
        self.session = session
        self.title = title
        self.turning = turning
        self.coolsAt = coolsAt
    }

    /// Имя без маркера — строка панели (слово Элвиса: «даже картинки не нужны вот эти вот, кругляшки»).
    public var name: String {
        let parts = title.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let first = parts[0].unicodeScalars.first,
              PanelTerminals.isMarker(first) else { return title }
        return String(parts[1])
    }

    /// Минут до остывания кеша (0 — остыл); nil — не знаем. Ход идёт — кеш тёплый на полный срок.
    public func cacheMinutes(now: Date) -> Int? {
        if turning { return Int(PanelTerminals.cacheSeconds / 60) }
        guard let cools = coolsAt else { return nil }
        return max(0, Int(ceil(cools.timeIntervalSince(now) / 60)))
    }

    /// Секунд с последней активности (слово Элвиса 22.10.2026: «отсчёт шёл одна секунда, две секунды… тик-тик-тик»):
    /// с последней записи транскрипта (`coolsAt` − `cacheSeconds`); ход идёт — активность сейчас, 0; nil — не знаем.
    public func idleSeconds(now: Date) -> TimeInterval? {
        if turning { return 0 }
        guard let cools = coolsAt else { return nil }
        return max(0, now.timeIntervalSince(cools.addingTimeInterval(-PanelTerminals.cacheSeconds)))
    }

    public var id: String { session }
}

public enum PanelTerminals {
    /// Откуда берётся маркер проекта — первая строка этих файлов папки, по порядку (как `term_title` в `pimp.py`).
    public static let headingFiles = ["docs/status.md", "audit/status.md", "AGENTS.md", "CLAUDE.md"]

    /// «# ⚪PimpMyClaude — памятка агенту» → «⚪ PimpMyClaude»; маркера в начале нет — nil.
    public static func heading(_ line: String) -> String? {
        let text = line.trimmingCharacters(in: .whitespaces).drop { $0 == "#" || $0 == " " }
        var marker = ""
        var rest = Substring(text)
        while let first = rest.unicodeScalars.first, isMarker(first) {
            let character = rest.first!
            marker.append(character)
            rest = rest.dropFirst()
        }
        guard !marker.isEmpty else { return nil }
        let body = rest.trimmingCharacters(in: .whitespaces)
        let label = body.components(separatedBy: CharacterSet(charactersIn: "—–|·")).first?
            .replacingOccurrences(of: " - ", with: "\u{0}").components(separatedBy: "\u{0}").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return label.isEmpty ? nil : marker + " " + label
    }

    static func isMarker(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x2300...0x27FF).contains(value) || (0x1F000...0x1FAFF).contains(value) || value == 0xFE0F
            || value == 0x200D
    }

    /// Заголовок терминала проекта: «<Проект>» из первой строки `headingFiles`, если она начинается с маркера; сам маркер
    /// в заголовок не идёт (#10564, слово Элвиса 22.10.2026: «Убери все иконки с терминалов — это правило»); нигде
    /// маркера нет — имя.
    public static func title(session: String, root: URL, fileManager: FileManager = .default) -> String {
        guard let folder = folder(session: session, root: root, fileManager: fileManager) else { return session }
        for relative in headingFiles {
            guard let handle = FileHandle(forReadingAtPath: folder.appendingPathComponent(relative).path) else { continue }
            let data = handle.readData(ofLength: 4096)
            try? handle.close()
            let first = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").first ?? ""
            if let found = heading(first) { return found.split(separator: " ", maxSplits: 1).last.map(String.init) ?? found }
        }
        return session
    }

    /// Папка проекта сессии: то же имя в корне проектов, без учёта регистра.
    static func folder(session: String, root: URL, fileManager: FileManager) -> URL? {
        let exact = root.appendingPathComponent(session, isDirectory: true)
        if fileManager.fileExists(atPath: exact.path) { return exact }
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        return names.first { $0.lowercased() == session.lowercased() }.map { root.appendingPathComponent($0) }
    }

    /// Сколько живёт кеш промпта с последней записи транскрипта (как у грелки Рика).
    public static let cacheSeconds: TimeInterval = 60 * 60

    /// Свежий CLI-транскрипт папки проекта: `~/.claude/projects/<путь, где всё кроме [A-Za-z0-9-] — «-»>/*.jsonl`,
    /// самый новый с `"entrypoint":"cli"` (или без поля) в первых 64 КБ — как `latest` у `kesh_grelka.py`.
    public static func lastWrite(folder: URL, fileManager: FileManager = .default) -> Date? {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let encoded = String(folder.standardizedFileURL.path.unicodeScalars.map { scalar -> Character in
            let ok = (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122) || scalar == "-"
            return ok ? Character(scalar) : "-"
        })
        let dir = base.appendingPathComponent("projects").appendingPathComponent(encoded)
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return nil }
        let files = names.filter { $0.hasSuffix(".jsonl") }.compactMap { name -> (URL, Date)? in
            let url = dir.appendingPathComponent(name)
            guard let date = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            else { return nil }
            return (url, date)
        }.sorted { $0.1 > $1.1 }
        for (url, date) in files {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = String(decoding: handle.readData(ofLength: 65_536), as: UTF8.self)
            try? handle.close()
            if let range = head.range(of: #""entrypoint": ?"([^"]*)""#, options: .regularExpression) {
                guard head[range].hasSuffix("\"cli\"") else { continue }
            }
            return date
        }
        return nil
    }

    /// Строки панели — по имени (ход меняется каждые секунды, строки не прыгают).
    public static func rows(sessions: Set<String>, turning: Set<String>, title: (String) -> String,
                            coolsAt: (String) -> Date? = { _ in nil }) -> [PanelTerminal] {
        sessions.map { PanelTerminal(session: $0, title: title($0), turning: turning.contains($0), coolsAt: coolsAt($0)) }
            .sorted { $0.session.lowercased() < $1.session.lowercased() }
    }

    /// Живой список: сессии tmux, ход по низу экрана, заголовки по папкам. В фоне — tmux и чтение файлов.
    public static func live() -> [PanelTerminal] {
        let root = StatusFeed.projectsRoot()
        let sessions = Set(PanelTiles.terminalActivity().keys)
        let turning = PanelTiles.turningTerminals(sessions)
        return rows(sessions: sessions, turning: turning, title: { title(session: $0, root: root) }, coolsAt: { session in
            folder(session: session, root: root, fileManager: .default)
                .flatMap { lastWrite(folder: $0) }?.addingTimeInterval(cacheSeconds)
        })
    }

    // MARK: право управлять Терминалом (#10464)

    /// Право Пимпа управлять Терминалом (Конфиденциальность › Автоматизация): без него вкладки не переименовать и окно
    /// по нажатию не показать (слово Элвиса 21.10 12:10: «надо в настройки PIMPA это добавить, чтоб у него всегда было
    /// право управлять терминалом»).
    public enum Access: Equatable {
        case allowed, denied, notAsked
    }

    /// Состояние права; `ask` — спросить человека системным окном, если ещё не спрашивали (ждёт ответа — только не на
    /// главной нити). Терминал не запущен — `notAsked` (macOS отвечает только про запущенное приложение).
    public static func access(ask: Bool) -> Access {
        let target = NSAppleEventDescriptor(bundleIdentifier: terminalBundle)
        guard let desc = target.aeDesc else { return .notAsked }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notAsked
        }
    }

    public static let terminalBundle = "com.apple.Terminal"
    /// Раздел «Автоматизация» Системных настроек.
    public static let automationSettings = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// Кнопка в настройках: запрещено — открыть «Автоматизацию»; иначе запустить Терминал (если не запущен) и спросить.
    /// Ответ — новое состояние. Только не на главной нити.
    public static func requestAccess() -> Access {
        if access(ask: false) == .denied {
            DispatchQueue.main.async { NSWorkspace.shared.open(automationSettings) }
            return .denied
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: terminalBundle).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundle) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in done.signal() }
            _ = done.wait(timeout: .now() + 5)
        }
        return access(ask: true)
    }

    // MARK: окна Terminal

    /// Показать окно сессии: вкладка Terminal, где она подключена, — вперёд; нет такой — новое окно `tmux attach`.
    /// Заголовок вкладки — `title`, без пути, процесса и размера. Ответ — «shown», «opened» или nil (не вышло).
    public static func show(_ terminal: PanelTerminal) -> String? {
        guard let tmux = PanelTiles.tmuxPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }
        // Сводное окно iTerm2 (#10564): чат — вкладкой окна iTerm сессии `pimp-hub`, не Terminal.
        if ITermHub.exists(tmux: tmux) {
            return ITermHub.show(tmux: tmux, session: terminal.session, title: terminal.title)
        }
        let clients = FlowShell.run(tmux, ["list-clients", "-t", "=rick-\(terminal.session)", "-F", "#{client_tty}"])
        let ttys = clients?.status == 0 ? clients?.text ?? "" : ""
        // «=имя» в кавычках: zsh раскрыл бы голое =слово в путь команды (как в `pimp.py`).
        let attach = "exec \(tmux) attach -t '=rick-\(terminal.session)'"
        return osascript(showScript, [terminal.title, attach, ttys], timeout: 10)
    }

    /// Заголовки всех вкладок Terminal, где подключены терминалы: «<Проект>»; строка состояния tmux внизу снята — в ней
    /// тоже слово tmux (#10564). Terminal не запущен — ничего.
    public static func retitle(_ terminals: [PanelTerminal]) {
        guard !terminals.isEmpty,
              let tmux = PanelTiles.tmuxPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return }
        var pairs: [String] = []
        for terminal in terminals {
            let target = "=rick-\(terminal.session)"
            retitleTmux(tmux, session: terminal.session, title: terminal.title)
            guard let clients = FlowShell.run(tmux, ["list-clients", "-t", target, "-F", "#{client_tty}"]),
                  clients.status == 0 else { continue }
            for tty in clients.text.components(separatedBy: "\n") where !tty.isEmpty {
                pairs.append(tty + "\t" + terminal.title)
            }
        }
        guard !pairs.isEmpty else { return }
        _ = osascript(retitleScript, [pairs.joined(separator: "\n")], timeout: 10)
    }

    /// Заголовок сессии `rick-<session>` в tmux (опции сессии, без -g): «<Проект>», строка состояния снята.
    static func retitleTmux(_ tmux: String, session: String, title: String) {
        let target = "=rick-\(session):"
        _ = FlowShell.run(tmux, ["set-option", "-t", target, "set-titles", "on"])
        _ = FlowShell.run(tmux, ["set-option", "-t", target, "set-titles-string",
                                 title.replacingOccurrences(of: "#", with: "##")])
        _ = FlowShell.run(tmux, ["set-option", "-t", target, "status", "off"])
    }

    static func osascript(_ script: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        guard let out = FlowShell.run("/usr/bin/osascript", ["-e", script] + arguments, timeout: timeout),
              out.status == 0 else { return nil }
        return out.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// argv: заголовок, команда подключения, tty подключённых клиентов строками.
    static let showScript = """
    on run argv
      set ttl to item 1 of argv
      set ttys to paragraphs of (item 3 of argv)
      tell application "Terminal"
        repeat with w in windows
          repeat with t in tabs of w
            if ttys contains (tty of t) then
              my titled(t, ttl)
              set selected of t to true
              try
                set miniaturized of w to false
              end try
              set index of w to 1
              activate
              return "shown"
            end if
          end repeat
        end repeat
        set t to do script (item 2 of argv)
        try
          set current settings of t to settings set "Пимп"
        end try
        my titled(t, ttl)
        activate
      end tell
      return "opened"
    end run
    on titled(t, ttl)
      tell application "Terminal"
        set custom title of t to ttl
        set title displays custom title of t to true
        try
          set title displays device name of t to false
          set title displays shell path of t to false
          set title displays window size of t to false
          set title displays file name of t to false
        end try
      end tell
    end titled
    """

    /// argv: строки «tty⇥заголовок».
    static let retitleScript = """
    on run argv
      if application "Terminal" is not running then return "0"
      set sep to character id 9
      set wanted to paragraphs of (item 1 of argv)
      set done to 0
      tell application "Terminal"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with pair in wanted
              set AppleScript's text item delimiters to sep
              set parts to text items of pair
              set AppleScript's text item delimiters to ""
              if (count of parts) is 2 and (tty of t) is (item 1 of parts) then
                if custom title of t is not (item 2 of parts) then set custom title of t to (item 2 of parts)
                set title displays custom title of t to true
                try
                  set title displays device name of t to false
                  set title displays shell path of t to false
                  set title displays window size of t to false
                  set title displays file name of t to false
                end try
                set done to done + 1
              end if
            end repeat
          end repeat
        end repeat
      end tell
      return done as text
    end run
    """
}
