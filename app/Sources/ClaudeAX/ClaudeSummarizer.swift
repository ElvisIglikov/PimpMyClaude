import Foundation

/// Провайдер `claude` сути длинного сообщения (#9806; слово Элвиса 17.10.2026 09:40 — «Claude на этом Маке»):
/// Claude CLI, что Claude Desktop держит в `~/Library/Application Support/Claude/claude-code/<версия>/<hash>/`,
/// Opus 5.5 low, без настроек, хуков и CLAUDE.md, без сессии на диске. Текст идёт только в stdin CLI — больше никуда.
/// `--bare` не годится: без ключа API он не входит (OAuth подписки там не читается).
/// Одна суть за раз (последовательная очередь), таймаут 60 с с убийством процесса; пусто или ошибка — `nil`,
/// и `UserSummary` пишет начало текста. Контракт — `docs/CONTRACTS.md`, «#9806 `POST /summary`».
final class ClaudeSummarizer {
    static let instruction = "Сожми сообщение автора в 1–3 короткие строки: что он просит или сообщает, его словами, "
        + "без вступлений, оценок и кавычек. Только суть."
    static let model = "claude-opus-5-5"
    static let maxSummary = 400

    /// Аргументы CLI ровно в этом порядке; пустые строки — значения флагов (ни настроек, ни инструментов).
    static let arguments = ["-p", instruction, "--setting-sources", "", "--tools", "", "--model", model,
                            "--effort", "low", "--no-session-persistence"]

    /// Путь к бинарнику на момент вызова (Claude Desktop обновляет CLI сам — ищем каждый раз). Тест подставляет свой.
    var binary: () -> String? = { ClaudeSummarizer.find() }
    var timeout: TimeInterval = 60
    private let queue = DispatchQueue(label: "pimp.summary.claude")

    /// Суть в `done` на очереди провайдера; `nil` — не далась.
    func summarize(_ text: String, done: @escaping (String?) -> Void) {
        queue.async { done(self.run(text)) }
    }

    /// Один вызов CLI синхронно: свежая пустая папка во временном каталоге — cwd (там нет CLAUDE.md),
    /// окружение наследуется как есть, stdin — текст и EOF.
    func run(_ text: String) -> String? {
        guard let path = binary() else { return nil }
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimp-summary-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: cwd, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? fm.removeItem(at: cwd) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = Self.arguments
        process.currentDirectoryURL = cwd
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        // Чтение и запись — в стороне: большой текст или болтливый ответ не встанут о буфер трубы.
        let io = DispatchGroup()
        let answer = Answer()
        DispatchQueue.global().async(group: io) { answer.set(output.fileHandleForReading.readDataToEndOfFile()) }
        let fd = input.fileHandleForWriting.fileDescriptor
        _ = fcntl(fd, F_SETNOSIGPIPE, 1) // процесс умер раньше — EPIPE, а не SIGPIPE всему Пимпу
        DispatchQueue.global().async(group: io) {
            Data(text.utf8).withUnsafeBytes { raw in
                guard var base = raw.baseAddress else { return }
                var left = raw.count
                while left > 0 {
                    let n = write(fd, base, left)
                    if n < 0 { if errno == EINTR { continue }; break }
                    left -= n
                    base += n
                }
            }
            try? input.fileHandleForWriting.close()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
            return nil // трубы дочитает сторона; ждать их незачем
        }
        // Внук CLI мог унести stdout с собой — EOF ждём недолго.
        guard io.wait(timeout: .now() + 2) == .success, process.terminationStatus == 0, let data = answer.get() else { return nil }
        let clean = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(Self.maxSummary))
    }

    private final class Answer {
        private let lock = NSLock()
        private var data: Data?
        func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
        func get() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    }

    // MARK: - где CLI

    /// Самая новая по номеру версия CLI Claude Desktop (`2.1.286` > `2.1.280`, `2.1.10` > `2.1.9`), потом
    /// `~/.local/bin/claude`, потом `claude` из `PATH`. Берётся только исполняемый файл.
    static func find(home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                     path: String? = ProcessInfo.processInfo.environment["PATH"]) -> String? {
        let fm = FileManager.default
        let root = (home as NSString).appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = ((try? fm.contentsOfDirectory(atPath: root)) ?? [])
            .compactMap { name -> (String, [Int])? in
                let parts = name.split(separator: ".").map { Int($0) }
                return parts.isEmpty || parts.contains(nil) ? nil : (name, parts.compactMap { $0 })
            }
            .sorted { $0.1.lexicographicallyPrecedes($1.1) }
        for (version, _) in versions.reversed() {
            let dir = (root as NSString).appendingPathComponent(version)
            for build in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() {
                let binary = (dir as NSString).appendingPathComponent("\(build)/claude.app/Contents/MacOS/claude")
                if fm.isExecutableFile(atPath: binary) { return binary }
            }
        }
        let local = (home as NSString).appendingPathComponent(".local/bin/claude")
        if fm.isExecutableFile(atPath: local) { return local }
        for dir in (path ?? "").split(separator: ":") where dir.hasPrefix("/") {
            let binary = (String(dir) as NSString).appendingPathComponent("claude")
            if fm.isExecutableFile(atPath: binary) { return binary }
        }
        return nil
    }
}
