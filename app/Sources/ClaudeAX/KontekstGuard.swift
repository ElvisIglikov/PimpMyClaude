import Foundation
import Patcher

/// Сторож контекста Claude Code (пожелания 03.11.2026, раздел 0): хуки в `~/.claude/settings.json`.
///
/// Скрипт ставит сам себя (`python3 kontekst_storozh.py install`) и пишет в хук свой путь, поэтому он не может
/// лежать внутри .app: обновление Пимпа заменяет бандл. Есть `<projectsRoot>/SkilZZZ` — берём источник оттуда,
/// иначе копия из ресурсов ложится в `Application Support/MyClaude/kontekst/`.
public enum KontekstGuard {
    static let folderName = "kontekst"
    static let scriptName = "kontekst_storozh.py"
    static let helperName = "rules_size_guard.py"
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse"]

    public enum Outcome: Equatable {
        case installed
        /// Текст простыми словами, для строки в панели.
        case failed(String)
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static var isInstalled: Bool { isInstalled(settings: try? Data(contentsOf: settingsURL)) }

    /// «Стоит»: скрипт есть на диске и в хуке каждого из трёх событий, задано `autoCompactWindow`.
    static func isInstalled(settings: Data?,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        guard let settings = settings,
              let json = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any],
              json["autoCompactWindow"] != nil,
              let hooks = json["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            scriptPaths(event: hooks[event]).contains(where: exists)
        }
    }

    /// Пути к скрипту в командах одного события.
    private static func scriptPaths(event: Any?) -> [String] {
        // Чужой мусор рядом с нашей группой скрипт оставляет на месте, здесь он не должен гасить ответ.
        let groups = (event as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let hooks = groups.flatMap { ($0["hooks"] as? [Any]) ?? [] }.compactMap { $0 as? [String: Any] }
        let commands = hooks.compactMap { $0["command"] as? String }
        return commands.flatMap(shellWords).filter { ($0 as NSString).lastPathComponent == scriptName }.map {
            ($0.replacingOccurrences(of: "$HOME", with: NSHomeDirectory()) as NSString).expandingTildeInPath
        }
    }

    /// Разбор команды как в shell: `shlex.quote` оборачивает путь с пробелом в кавычки («Application Support»).
    static func shellWords(_ text: String) -> [String] {
        var words: [String] = []
        var word = ""
        var started = false
        var quote: Character?
        var escaped = false
        for char in text {
            if escaped {
                word.append(char)
                escaped = false
            } else if let open = quote {
                if char == open { quote = nil } else if char == "\\", open == "\"" { escaped = true } else { word.append(char) }
            } else if char == "'" || char == "\"" {
                quote = char
                started = true
            } else if char == "\\" {
                escaped = true
                started = true
            } else if char == " " || char == "\t" {
                if started { words.append(word) }
                word = ""
                started = false
            } else {
                word.append(char)
                started = true
            }
        }
        if started { words.append(word) }
        return words
    }

    /// Поставить сторож. Долго (запуск python3) — звать не с главной нитки.
    public static func install() -> Outcome {
        let fm = FileManager.default
        let scripts = StatusFeed.projectsRoot().appendingPathComponent("SkilZZZ/scripts", isDirectory: true)
        let source: URL
        if fm.fileExists(atPath: scripts.appendingPathComponent(scriptName).path),
           fm.fileExists(atPath: scripts.appendingPathComponent(helperName).path) {
            source = scripts
        } else {
            let target = CommandChannel.directory.appendingPathComponent(folderName, isDirectory: true)
            guard let bundled = ThemeCatalog.resourcesDirectory?.appendingPathComponent(folderName, isDirectory: true),
                  place(from: bundled, to: target) else {
                return .failed("не вышло положить файлы сторожа, переустанови Пимп")
            }
            source = target
        }
        if let why = run(source.appendingPathComponent(scriptName)) { return .failed(why) }
        return isInstalled ? .installed : .failed("установка прошла, но сторож в настройках Claude Code не появился")
    }

    /// Новая сборка на старте обновляет уже лежащую копию: карточки у стоящего сторожа нет, а пороги живут в самом скрипте.
    /// Только файлы: `install` здесь нельзя, его merge увёл бы хук на копию с источника правды в SkilZZZ.
    public static func refreshCopy() {
        guard let bundled = ThemeCatalog.resourcesDirectory?.appendingPathComponent(folderName, isDirectory: true) else { return }
        refreshCopy(from: bundled, to: CommandChannel.directory.appendingPathComponent(folderName, isDirectory: true))
    }

    static func refreshCopy(from bundled: URL, to target: URL) {
        guard FileManager.default.fileExists(atPath: target.appendingPathComponent(scriptName).path) else { return }
        _ = place(from: bundled, to: target)
    }

    /// Скрипт и его соседа — на постоянное место; соседа первым, скрипт без него не запустится.
    static func place(from source: URL, to target: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for name in [helperName, scriptName] {
                let body = try Data(contentsOf: source.appendingPathComponent(name))
                try body.write(to: target.appendingPathComponent(name), options: .atomic)
            }
            return true
        } catch {
            return false
        }
    }

    /// `python3 <скрипт> install`: nil — вышло, иначе причина. У приложения короткий PATH и нет своей локали.
    private static func run(_ script: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["PYTHONUTF8"] = "1"
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "install"]
        process.environment = environment
        process.currentDirectoryURL = script.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return "не запустился python3"
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return failure(status: process.terminationStatus, output: output)
    }

    /// Хвост вывода вместо голого кода: `⛔` скрипта уже написан по-человечески.
    static func failure(status: Int32, output: String) -> String? {
        guard status != 0 else { return nil }
        if status == 127 || output.contains("xcode-select") {
            return "Маку нужны инструменты разработчика (python3). Согласись в окне macOS, дождись конца и нажми ещё раз. "
                + "Окна нет — в Терминале: xcode-select --install"
        }
        // Порядок важен: в сообщении об отказе записи тоже есть путь к settings.json.
        if output.contains("Не смог записать") { return "Мак не дал записать настройки Claude Code" }
        if output.contains("не поставлен") {
            return "файл настроек Claude Code испорчен. Покажи этот текст чату в терминале"
        }
        let lines = output.split(separator: "\n").map(String.init)
        let tail = lines.last.map { String($0.prefix(200)) } ?? ""
        return tail.isEmpty ? "установка сорвалась, нажми ещё раз" : tail
    }
}
