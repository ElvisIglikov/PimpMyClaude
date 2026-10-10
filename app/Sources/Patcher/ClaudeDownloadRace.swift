import CryptoKit
import Foundation

// Гонка загрузки Claude (WF86, план WF87 батч A п. 2): все источники одной версии качаются разом,
// отстающий отключается, победитель сверяется с размером и sha256. Общего лимита на ресурс нет
// (критик WF87 п. 5): медленный канал не обрывается по часам, его отключает только правило
// отсева или «20 с без байтов»; потолок всей гонки задаёт вызывающий (`Rules.deadline`, фон — 2 ч).

/// Один источник архива: куда идти и чем проверить (размер и sha256 — если известны).
public struct DownloadSource: Equatable {
    public let id: String
    public let title: String
    public let url: URL
    /// Ожидаемый размер; `nil` — сверим с Content-Length, дальше опора на подпись и версию бандла.
    public let expectedSize: Int64?
    /// Ожидаемый sha256 строчными; `nil` — не известен.
    public let sha256: String?
    public let format: ClaudeRelease.Format

    public init(id: String, title: String, url: URL, expectedSize: Int64?, sha256: String?,
                format: ClaudeRelease.Format) {
        self.id = id
        self.title = title
        self.url = url
        self.expectedSize = expectedSize.flatMap { $0 > 0 ? $0 : nil }
        self.sha256 = sha256.flatMap { $0.isEmpty ? nil : $0.lowercased() }
        self.format = format
    }
}

/// Полоса гонки глазами UI: снимок раз в `Rules.tick` на очереди `callbackQueue` (по умолчанию главная).
public struct RaceLane: Equatable {
    public enum State: Equatable {
        case running
        /// Прогноз финиша лучший.
        case leading
        /// Отключена правилом: «отстал — отключён», «завис». Может перезапуститься.
        case dropped(String)
        /// Сорвалась: ошибка сети, не тот ответ, не сошлись размер или sha256.
        case failed(String)
        case won
    }

    public let id: String
    public let title: String
    public let bytes: Int64
    /// Размер файла, если известен (ожидаемый или Content-Length).
    public let total: Int64?
    public let bytesPerSec: Double
    public let state: State

    public init(id: String, title: String, bytes: Int64, total: Int64?, bytesPerSec: Double, state: State) {
        self.id = id
        self.title = title
        self.bytes = bytes
        self.total = total
        self.bytesPerSec = bytesPerSec
        self.state = state
    }
}

public struct RaceSnapshot: Equatable {
    public let lanes: [RaceLane]
    /// Гонка кончилась (победой, провалом или отменой) — снимок последний.
    public let finished: Bool

    /// Доля лучшей живой полосы (лидер или победитель), 0…1.
    public var fraction: Double {
        lanes.compactMap { lane -> Double? in
            guard let total = lane.total, total > 0 else { return nil }
            switch lane.state {
            case .running, .leading, .won: return min(1, Double(lane.bytes) / Double(total))
            case .dropped, .failed: return nil
            }
        }.max() ?? 0
    }
}

/// Победитель: какой источник и где лежит его файл (проверенный по размеру и sha256, если были).
public struct RaceWinner {
    public let source: DownloadSource
    public let file: URL
}

/// Отмена и подписка снаружи: `prepare` отдаёт его гонке, UI держит у себя и зовёт `cancel()`.
public final class DownloadControl {
    private let lock = NSLock()
    private var cancelled = false
    private weak var race: ClaudeDownloadRace?
    /// Снимки гонки на `callbackQueue` гонки (по умолчанию главная).
    public let onSnapshot: ((RaceSnapshot) -> Void)?

    public init(onSnapshot: ((RaceSnapshot) -> Void)? = nil) { self.onSnapshot = onSnapshot }

    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    public func cancel() {
        lock.lock()
        cancelled = true
        let race = self.race
        lock.unlock()
        race?.cancel()
    }

    func attach(_ race: ClaudeDownloadRace) {
        lock.lock()
        self.race = race
        let cancelled = self.cancelled
        lock.unlock()
        if cancelled { race.cancel() }
    }
}

public final class ClaudeDownloadRace: NSObject, URLSessionDataDelegate {
    /// Updater policy is checked again before following a server redirect.
    public var allowsRedirect: (URL) -> Bool = { _ in true }
    public struct Rules {
        /// Разгон: раньше отстающего не судим.
        public var warmup: TimeInterval = 4
        /// Прогноз финиша хуже лидера во столько раз — «отстал — отключён».
        public var dropFactor: Double = 3
        /// Столько без единого байта — «завис».
        public var stallSeconds: TimeInterval = 20
        /// Шаг судьи и снимков для UI.
        public var tick: TimeInterval = 0.25
        /// Окно, по которому считается скорость.
        public var speedWindow: TimeInterval = 2
        /// Сколько раз отключённую полосу можно перезапустить (падение лидера, провал проверки,
        /// лидер скис).
        public var maxRestarts = 1
        /// Потолок всей гонки; nil — без потолка.
        public var deadline: TimeInterval?

        public init() {}
    }

    public let sources: [DownloadSource]
    public let directory: URL
    public let rules: Rules
    public var callbackQueue: DispatchQueue = .main
    /// Снимок для UI (async на `callbackQueue`).
    public var onSnapshot: ((RaceSnapshot) -> Void)?
    /// Строки журнала — синхронно на внутренней очереди, только пока идёт `run()`.
    public var log: ((String) -> Void)?

    private let queue = DispatchQueue(label: "pimpmyclaude.download-race")
    private let configuration: URLSessionConfiguration
    private var session: URLSession?
    private var lanes: [LaneRun] = []
    private var timer: DispatchSourceTimer?
    private var startedAt = Date()
    private var outcome: Result<RaceWinner, Error>?
    private let done = DispatchSemaphore(value: 0)
    private var cancelled = false
    private var loggedTenth = 0
    /// С какой минуты отключённая полоса с нуля доехала бы раньше лидера.
    private var saggingSince: Date?

    public init(sources: [DownloadSource], directory: URL, rules: Rules = Rules(),
                configuration: URLSessionConfiguration = .ephemeral) {
        self.sources = sources
        self.directory = directory
        self.rules = rules
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Судья сам отключает зависшее; системные таймауты — только страховка сверху.
        configuration.timeoutIntervalForRequest = max(rules.stallSeconds * 2, 30)
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        self.configuration = configuration
        super.init()
    }

    /// Блокирует до победы, провала всех или отмены. Звать не с главной нити.
    public func run() throws -> RaceWinner {
        guard !sources.isEmpty else { throw ClaudeUpdateError.download("нет источников") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        queue.sync { start() }
        done.wait()
        // Последний снимок уже отправлен; дальше гонка ничего не шлёт.
        return try queue.sync { try outcome!.get() }
    }

    public func cancel() {
        queue.async {
            guard self.outcome == nil else { return }
            self.cancelled = true
            self.finish(.failure(ClaudeUpdateError.cancelled))
        }
    }

    // MARK: - полосы

    private final class LaneRun {
        let source: DownloadSource
        let file: URL
        var task: URLSessionDataTask?
        var handle: FileHandle?
        var hasher = SHA256()
        var bytes: Int64 = 0
        var contentLength: Int64?
        var startedAt = Date()
        var lastByteAt = Date()
        var samples: [(at: Date, bytes: Int64)] = []
        var state: RaceLane.State = .running
        var restarts = 0
        var error: Error?
        /// Скорость в миг отключения — по ней судим, стоит ли перезапускать.
        var speedAtDrop: Double = 0

        init(source: DownloadSource, file: URL) {
            self.source = source
            self.file = file
        }

        var total: Int64? { source.expectedSize ?? contentLength }
        var alive: Bool {
            switch state { case .running, .leading: return true; default: return false }
        }
        var isDropped: Bool { if case .dropped = state { return true }; return false }
    }

    private func start() {
        // Отменили раньше, чем гонка началась, — ничего не запускаем.
        guard outcome == nil else { return }
        startedAt = Date()
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = queue
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        var used = Set<String>()
        lanes = sources.map { source in
            var name = source.id
            while !used.insert(name).inserted { name += "-" }
            return LaneRun(source: source, file: directory.appendingPathComponent(name + ".part"))
        }
        log?("Качаю разом: " + lanes.map { $0.source.title }.joined(separator: ", ") + ".")
        lanes.forEach(launch)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + rules.tick, repeating: rules.tick)
        timer.setEventHandler { [weak self] in self?.judge() }
        timer.resume()
        self.timer = timer
    }

    private func launch(_ lane: LaneRun) {
        try? FileManager.default.removeItem(at: lane.file)
        FileManager.default.createFile(atPath: lane.file.path, contents: nil)
        lane.handle = try? FileHandle(forWritingTo: lane.file)
        lane.hasher = SHA256()
        lane.bytes = 0
        lane.contentLength = nil
        lane.startedAt = Date()
        lane.lastByteAt = lane.startedAt
        lane.samples = [(lane.startedAt, 0)]
        lane.state = .running
        lane.error = nil
        guard lane.handle != nil, let session = session else {
            fail(lane, ClaudeUpdateError.download("не создать файл \(lane.file.lastPathComponent)"), reason: "не создать файл")
            return
        }
        var request = URLRequest(url: lane.source.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request)
        lane.task = task
        task.resume()
    }

    private func lane(of task: URLSessionTask) -> LaneRun? {
        lanes.first { $0.task === task }
    }

    private func stop(_ lane: LaneRun) {
        let task = lane.task
        lane.task = nil
        task?.cancel()
        try? lane.handle?.close()
        lane.handle = nil
        try? FileManager.default.removeItem(at: lane.file)
    }

    private func drop(_ lane: LaneRun, _ reason: String, speed: Double = 0) {
        guard lane.alive else { return }
        lane.speedAtDrop = speed
        stop(lane)
        lane.state = .dropped(reason)
        log?("\(lane.source.title): \(reason).")
    }

    /// `atCheck` — полоса докачала, но не прошла проверку размера или sha256 (победитель на проверке).
    private func fail(_ lane: LaneRun, _ error: Error, reason: String, atCheck: Bool = false) {
        let wasLeading = lane.state == .leading
        stop(lane)
        lane.state = .failed(reason)
        lane.error = error
        log?("\(lane.source.title) не подошёл: \(reason).")
        // Попытка отключённых одна (`maxRestarts`) — тратим её, только когда сорвался лидер или
        // победитель на проверке; прочие срывы — `settleIfOver` (живых не осталось — перезапустит).
        if wasLeading || atCheck { restartDropped() }
        settleIfOver()
    }

    private func restartDropped(only chosen: [LaneRun]? = nil) {
        for lane in chosen ?? lanes where lane.isDropped && lane.restarts < rules.maxRestarts {
            lane.restarts += 1
            log?("Перезапускаю \(lane.source.title).")
            launch(lane)
        }
    }

    /// Живых нет: перезапустить отключённых; и их нет — провал.
    private func settleIfOver() {
        guard outcome == nil, !lanes.contains(where: { $0.alive }) else { return }
        restartDropped()
        guard !lanes.contains(where: { $0.alive }) else { return }
        if lanes.count == 1, let error = lanes[0].error {
            finish(.failure(error))
            return
        }
        let reasons = lanes.map { lane -> String in
            switch lane.state {
            case .failed(let why), .dropped(let why): return "\(lane.source.title) — \(why)"
            default: return lane.source.title
            }
        }
        finish(.failure(ClaudeUpdateError.download("ни один источник не докачал: " + reasons.joined(separator: "; "))))
    }

    private func finish(_ result: Result<RaceWinner, Error>) {
        guard outcome == nil else { return }
        outcome = result
        timer?.cancel()
        timer = nil
        for lane in lanes where lane.alive {
            stop(lane)
            lane.state = cancelled ? .dropped("отменено") : .dropped("не понадобился")
        }
        session?.invalidateAndCancel()
        session = nil
        emit(finished: true)
        log = nil
        done.signal()
    }

    // MARK: - судья

    private func speed(_ lane: LaneRun, now: Date) -> Double {
        let horizon = now.addingTimeInterval(-rules.speedWindow)
        guard let base = lane.samples.last(where: { $0.at <= horizon }) ?? lane.samples.first else { return 0 }
        let span = now.timeIntervalSince(base.at)
        guard span > 0.05 else { return 0 }
        return Double(lane.bytes - base.bytes) / span
    }

    /// Секунды до финиша; неизвестно — бесконечность.
    private func eta(_ lane: LaneRun, speed: Double, fallbackTotal: Int64?) -> Double {
        guard speed > 0 else { return .infinity }
        guard let total = lane.total ?? fallbackTotal else { return 1 / speed }
        return Double(max(0, total - lane.bytes)) / speed
    }

    private func judge() {
        guard outcome == nil else { return }
        let now = Date()
        if let deadline = rules.deadline, now.timeIntervalSince(startedAt) >= deadline {
            finish(.failure(ClaudeUpdateError.download("не успел за \(Int(deadline / 60)) мин")))
            return
        }
        for lane in lanes where lane.alive {
            lane.samples.append((now, lane.bytes))
            let keep = now.addingTimeInterval(-(rules.speedWindow + 1))
            while lane.samples.count > 2, lane.samples[1].at < keep { lane.samples.removeFirst() }
            if now.timeIntervalSince(lane.lastByteAt) >= rules.stallSeconds { drop(lane, "завис") }
        }
        let fallbackTotal = lanes.compactMap { $0.total }.max()
        let alive = lanes.filter { $0.alive }
        let etas = alive.map { ($0, eta($0, speed: speed($0, now: now), fallbackTotal: fallbackTotal)) }
        let leader = etas.filter { $0.0.bytes > 0 && $0.1.isFinite }.min { $0.1 < $1.1 }
        reviveIfLeaderSagged(leaderETA: etas.map { $0.1 }.min() ?? .infinity, fallbackTotal: fallbackTotal, now: now)
        if let (lane, _) = leader, let total = lane.total, total > 0 {
            let tenth = Int(Double(lane.bytes) / Double(total) * 10)
            if tenth > loggedTenth, tenth < 10 {
                loggedTenth = tenth
                log?("Скачано \(tenth * 10)% · впереди \(lane.source.title), \(Self.speedText(speed(lane, now: now))).")
            }
        }
        for (lane, laneEta) in etas {
            if lane === leader?.0 { lane.state = .leading; continue }
            lane.state = .running
            // Почти догнавшую (остаток меньше `stallSeconds`) не отключаем: у лидера к финишу прогноз
            // стремится к нулю, а её файл — запас на случай, если лидер не пройдёт проверку.
            guard let leader = leader, now.timeIntervalSince(lane.startedAt) >= rules.warmup,
                  laneEta >= rules.stallSeconds, laneEta > leader.1 * rules.dropFactor else { continue }
            drop(lane, "отстал — отключён", speed: speed(lane, now: now))
        }
        settleIfOver()
        if outcome == nil { emit(finished: false) }
    }

    /// Лидер скис (живьём 25.09: Anthropic рванул на старте, R2 и GitHub отключились, потом Anthropic
    /// сполз до 0,1 МБ/с — байты идут, «завис» не срабатывает): отключённая полоса, которая С НУЛЯ на
    /// своей скорости в миг отключения доехала бы раньше лучшего живого, `stallSeconds` подряд —
    /// перезапускается; дальше рассудит обычный отсев.
    private func reviveIfLeaderSagged(leaderETA: Double, fallbackTotal: Int64?, now: Date) {
        let better = lanes.filter { lane in
            guard lane.isDropped, lane.restarts < rules.maxRestarts, lane.speedAtDrop > 0,
                  let total = lane.total ?? fallbackTotal else { return false }
            return Double(total) / lane.speedAtDrop < leaderETA
        }
        guard !better.isEmpty, lanes.contains(where: { $0.alive }) else {
            saggingSince = nil
            return
        }
        let since = saggingSince ?? now
        saggingSince = since
        guard now.timeIntervalSince(since) >= rules.stallSeconds else { return }
        saggingSince = nil
        log?("Лидер сполз — с нуля быстрее: " + better.map { $0.source.title }.joined(separator: ", ") + ".")
        restartDropped(only: better)
    }

    private func emit(finished: Bool) {
        guard let onSnapshot = onSnapshot else { return }
        let now = Date()
        let snapshot = RaceSnapshot(lanes: lanes.map { lane in
            RaceLane(id: lane.source.id, title: lane.source.title, bytes: lane.bytes, total: lane.total,
                     bytesPerSec: lane.alive ? speed(lane, now: now) : 0, state: lane.state)
        }, finished: finished)
        callbackQueue.async { onSnapshot(snapshot) }
    }

    /// «5,1 МБ/с» — мегабайты по-русски, одна цифра после запятой.
    public static func speedText(_ bytesPerSec: Double) -> String {
        let mb = max(0, bytesPerSec) / 1_000_000
        return String(format: "%.1f", mb).replacingOccurrences(of: ".", with: ",") + " МБ/с"
    }

    // MARK: - URLSession

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, allowsRedirect(url) else { completionHandler(nil); return }
        completionHandler(request)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let lane = lane(of: dataTask), outcome == nil else { completionHandler(.cancel); return }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            completionHandler(.cancel)
            fail(lane, ClaudeUpdateError.download("\(lane.source.title) ответил \(http.statusCode)"),
                 reason: "сервер ответил \(http.statusCode)")
            return
        }
        let length = response.expectedContentLength
        if length > 0 { lane.contentLength = length }
        // Первые байты: R2 `latest/mac` мог уже смениться — чужой файл не качаем до конца.
        if let expected = lane.source.expectedSize, length > 0, length != expected {
            completionHandler(.cancel)
            fail(lane, ClaudeUpdateError.sizeMismatch(expected: expected, got: length),
                 reason: "отдаёт другой файл (\(length) байт, ждали \(expected))")
            return
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let lane = lane(of: dataTask), lane.alive, let handle = lane.handle else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            fail(lane, ClaudeUpdateError.download(error.localizedDescription), reason: "не записать на диск")
            return
        }
        lane.hasher.update(data: data)
        lane.bytes += Int64(data.count)
        lane.lastByteAt = Date()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let lane = lane(of: task), lane.alive, outcome == nil else { return }
        if let error = error {
            fail(lane, ClaudeUpdateError.download(error.localizedDescription), reason: error.localizedDescription)
            return
        }
        lane.task = nil
        try? lane.handle?.close()
        lane.handle = nil
        let expected = lane.source.expectedSize ?? lane.contentLength
        if let expected = expected, lane.bytes != expected {
            fail(lane, ClaudeUpdateError.sizeMismatch(expected: expected, got: lane.bytes),
                 reason: "размер не тот (\(lane.bytes) байт, ждали \(expected))", atCheck: true)
            return
        }
        if let sha = lane.source.sha256 {
            let got = lane.hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard got == sha else {
                fail(lane, ClaudeUpdateError.checksumMismatch, reason: "sha256 не сошлась", atCheck: true)
                return
            }
        }
        lane.state = .won
        log?("\(lane.source.title) докачал первым — \(lane.bytes / 1_000_000) МБ.")
        finish(.success(RaceWinner(source: lane.source, file: lane.file)))
    }
}
