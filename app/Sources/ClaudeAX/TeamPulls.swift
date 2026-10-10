import Combine
import Foundation
import Darwin
import CoreFoundation

/// Запросы на изменения команды (#8030, WF120, К-B4): открытые PR в репозиториях своего логина и его
/// организаций, кроме своих. Только чтение и проверенная ссылка на конкретный PR.
/// gh зовём сами, без pimp.py: вне главной очереди, со сроком на каждый вызов; список живёт 5 минут
/// «Обновить» — мимо кэша. Слова ошибок — общие с `pimp.py prs`.
/// Класс живёт на главной очереди; вид — `TeamPullsSection` в приложении.
public final class TeamPulls: ObservableObject {
    public struct Pull: Equatable, Identifiable {
        /// `owner/name`.
        public let repo: String
        public let number: Int
        public let title: String
        public let author: String
        public let created: Date
        public let draft: Bool
        /// Куда вольётся.
        public let base: String
        public let state: String
        public let headRefName: String
        public let url: String
        /// `MERGEABLE`, `CONFLICTING` или `UNKNOWN`.
        public let mergeable: String
        /// Голова ветки на момент чтения.
        public let head: String
        /// `statusCheckRollup.state` последнего коммита; nil — проверок нет.
        public let checks: String?
        public var id: String { "\(repo)#\(number)" }
    }

    /// Исход одного вызова gh.
    enum Run: Equatable {
        case missing
        case timedOut
        case done(status: Int32, out: String, err: String)
    }

    /// Запуск gh: аргументы и срок → исход. Тесты подставляют свой.
    typealias Runner = (_ arguments: [String], _ timeout: TimeInterval) -> Run

    // MARK: - слова (общие с `pimp.py prs` — К-B4 (в))

    public static let title = "🔀 Запросы команды"
    public static let noGh = "нет gh — поставь GitHub CLI"
    public static let notLoggedIn = "gh не вошёл — gh auth login"
    public static let offline = "сеть не отвечает"
    public static let emptyText = "Запросов нет"
    public static let loadingText = "Смотрю открытые запросы…"

    public static let cacheSeconds: TimeInterval = 300
    static let listTimeout: TimeInterval = 15
    static let loadTimeout: TimeInterval = 60
    static let malformed = "gh ответил непонятно — нажми «Обновить»"
    static let incomplete = "Список неполный — не удалось прочитать все запросы"
    static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    static let query = """
    query($q: String!, $cursor: String) {
      search(query: $q, type: ISSUE, first: 50, after: $cursor) {
        issueCount pageInfo { hasNextPage endCursor }
        nodes { ... on PullRequest {
          number title createdAt isDraft state baseRefName headRefName mergeable headRefOid url
          author { login } repository { nameWithOwner }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
        } }
      }
    }
    """

    // MARK: - состояние для вида

    /// Список; nil — ещё не загружали (или загрузка не удалась ни разу).
    @Published public private(set) var pulls: [Pull]?
    @Published public private(set) var loading = false
    /// Почему список не загрузился — словами; nil — загрузился.
    @Published public private(set) var error: String?
    private let runner: Runner
    private let now: () -> Date
    private let background: (@escaping () -> Void) -> Void
    private let main: (@escaping () -> Void) -> Void
    private var loadedAt: Date?

    public convenience init() {
        let queue = DispatchQueue(label: "pimp.team-pulls", qos: .userInitiated)
        self.init(runner: TeamPulls.run, now: Date.init,
                  background: { queue.async(execute: $0) },
                  main: { DispatchQueue.main.async(execute: $0) })
    }

    init(runner: @escaping Runner, now: @escaping () -> Date,
         background: @escaping (@escaping () -> Void) -> Void, main: @escaping (@escaping () -> Void) -> Void) {
        self.runner = runner
        self.now = now
        self.background = background
        self.main = main
    }

    // MARK: - нажатия

    /// Открыли «Запросы команды» — список из кэша, старше 5 минут — заново; `force` («Обновить») — мимо кэша.
    public func refresh(force: Bool = false) {
        guard !loading else { return }
        if !force, error == nil, pulls != nil, let at = loadedAt, now().timeIntervalSince(at) < Self.cacheSeconds { return }
        loading = true
        background { [weak self] in
            guard let self = self else { return }
            let result = self.load()
            self.main { [weak self] in self?.finishLoad(result) }
        }
    }

    private func finishLoad(_ result: (pulls: [Pull]?, error: String?)) {
        loading = false
        error = result.error
        guard let list = result.pulls else { return }
        pulls = list
        loadedAt = now()
    }

    // MARK: - gh

    /// Pagination errors never replace a previously complete list or its cache timestamp.
    func load() -> (pulls: [Pull]?, error: String?) {
        let deadline = ProcessInfo.processInfo.systemUptime + Self.loadTimeout
        func call(_ arguments: [String]) -> Run {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return .timedOut }
            let result = runner(arguments, min(Self.listTimeout, remaining))
            return ProcessInfo.processInfo.systemUptime < deadline ? result : .timedOut
        }
        let user = call(["api", "user", "--jq", ".login"])
        if let word = Self.word(user) { return (nil, word) }
        guard case .done(_, let out, _) = user else { return (nil, Self.offline) }
        let login = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validOwner(login) else { return (nil, Self.malformed) }
        var orgs: [String] = []
        var finishedOrgs = false
        for page in 1...100 {
            let result = call(["api", "user/orgs?per_page=100&page=\(page)"])
            if let word = Self.word(result) { return (nil, "\(Self.incomplete): \(word)") }
            guard case .done(_, let json, _) = result,
                  let rows = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]],
                  rows.count <= 100 else { return (nil, Self.malformed) }
            for row in rows {
                guard let name = row["login"] as? String, Self.validOwner(name), !orgs.contains(name) else {
                    return (nil, Self.malformed)
                }
                orgs.append(name)
            }
            if rows.count < 100 { finishedOrgs = true; break }
        }
        guard finishedOrgs else { return (nil, Self.incomplete) }
        var cursor: String?
        var seen = Set<String>()
        var list: [Pull] = []
        var count: Int?
        for _ in 0..<20 {
            var args = ["api", "graphql", "-f", "query=\(Self.query)", "-f", "q=\(Self.search(login: login, orgs: orgs))"]
            if let cursor = cursor { args += ["-f", "cursor=\(cursor)"] }
            let result = call(args)
            if let word = Self.word(result) { return (nil, word) }
            guard case .done(_, let json, _) = result else { return (nil, Self.offline) }
            if let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
               let errors = root["errors"] as? [Any], !errors.isEmpty {
                return (nil, "\(Self.incomplete): ошибка GitHub")
            }
            guard let page = Self.parsePage(Data(json.utf8)) else { return (nil, Self.malformed) }
            guard page.count <= 1000, count == nil || count == page.count else { return (nil, Self.incomplete) }
            count = page.count
            let owners = Set(([login] + orgs).map { $0.lowercased() })
            guard page.pulls.allSatisfy({ owners.contains(String($0.repo.split(separator: "/")[0]).lowercased())
                && $0.state == "OPEN" }) else {
                return (nil, Self.malformed)
            }
            list += page.pulls
            guard Set(list.map { $0.id }).count == list.count else { return (nil, Self.incomplete) }
            if !page.more {
                guard list.count == page.count else { return (nil, Self.incomplete) }
                return (list.filter { $0.author.lowercased() != login.lowercased() }
                    .sorted { $0.created > $1.created }, nil)
            }
            guard let next = page.cursor, !next.isEmpty, seen.insert(next).inserted, !page.pulls.isEmpty else {
                return (nil, Self.incomplete)
            }
            cursor = next
        }
        return (nil, Self.incomplete)
    }

    static func search(login: String, orgs: [String]) -> String {
        (["is:pr", "is:open", "-author:\(login)", "user:\(login)"] + orgs.map { "org:\($0)" }).joined(separator: " ")
    }

    static func validOwner(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9-]*$", options: .regularExpression) != nil
    }

    /// Same PR only: no credentials, ports, query, fragment, alternate host or URL scheme.
    public static func link(_ pull: Pull) -> URL? {
        validURL(pull.url, repo: pull.repo, number: pull.number)
    }

    static func validURL(_ value: String, repo: String, number: Int) -> URL? {
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, validOwner(String(parts[0])),
              String(parts[1]).range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
              parts[1] != ".", parts[1] != "..", number > 0,
              let url = URLComponents(string: value), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.percentEncodedPath == "/\(repo)/pull/\(number)" else { return nil }
        return url.url
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue.rounded() == n.doubleValue,
              n.doubleValue >= 0, n.doubleValue < Double(Int.max) else { return nil }
        return n.intValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    static func parsePage(_ data: Data) -> (pulls: [Pull], count: Int, more: Bool, cursor: String?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["errors"] == nil || (root["errors"] as? [Any])?.isEmpty == true,
              let search = (root["data"] as? [String: Any])?["search"] as? [String: Any],
              let count = integer(search["issueCount"]),
              let info = search["pageInfo"] as? [String: Any], let more = boolean(info["hasNextPage"]),
              let nodes = search["nodes"] as? [[String: Any]] else { return nil }
        let dates = ISO8601DateFormatter()
        var list: [Pull] = []
        for node in nodes {
            guard let number = integer(node["number"]), number > 0,
                  let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String,
                  let title = node["title"] as? String,
                  let author = node["author"] is NSNull ? "ghost" : (node["author"] as? [String: Any])?["login"] as? String,
                  !author.isEmpty,
                  let created = node["createdAt"] as? String, let date = dates.date(from: created),
                  let draft = boolean(node["isDraft"]), let state = node["state"] as? String,
                  let base = node["baseRefName"] as? String, let branch = node["headRefName"] as? String,
                  let head = node["headRefOid"] as? String, let mergeable = node["mergeable"] as? String,
                  let url = node["url"] as? String, validURL(url, repo: repo, number: number) != nil,
                  let commits = node["commits"] as? [String: Any], let commitNodes = commits["nodes"] as? [[String: Any]],
                  commitNodes.count == 1 else { return nil }
            var checks: String?
            if let last = commitNodes.last {
                guard let commit = last["commit"] as? [String: Any], let rollup = commit["statusCheckRollup"] else { return nil }
                if !(rollup is NSNull) {
                    guard let map = rollup as? [String: Any], let status = map["state"] as? String else { return nil }
                    checks = status
                }
            }
            list.append(Pull(repo: repo, number: number, title: title, author: author, created: date,
                             draft: draft, base: base, state: state, headRefName: branch, url: url,
                             mergeable: mergeable, head: head, checks: checks))
        }
        return (list, count, more, info["endCursor"] as? String)
    }

    /// Ошибка вызова словами (К-B4 (в)); удача — nil. Незнакомую ошибку — первой строкой самого gh.
    static func word(_ run: Run) -> String? {
        switch run {
        case .missing: return noGh
        case .timedOut: return offline
        case .done(0, _, _): return nil
        case .done(_, _, let err):
            let text = err.lowercased()
            func has(_ parts: String...) -> Bool { parts.contains { text.contains($0) } }
            if has("gh auth login", "not logged", "http 401", "bad credentials", "authentication required") { return notLoggedIn }
            if has("error connecting", "could not resolve", "no such host", "dial tcp", "network is unreachable",
                   "connection refused", "connection reset", "i/o timeout", "tls handshake") { return offline }
            if has("permission", "http 403", "not accessible", "not authorized") { return "нет доступа к запросам" }
            let line = err.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            return line.isEmpty ? "gh не смог — нажми «Обновить»" : String(line.prefix(120))
        }
    }

    // MARK: - слова вида

    /// «🔀 Запросы команды 2»; пока не знаем — без числа.
    public static func rowTitle(_ pulls: [Pull]?) -> String {
        guard let count = pulls?.count, count > 0 else { return title }
        return "\(title) \(count)"
    }

    /// Справа от строки: «проверяю…», ошибка, «нет».
    public static func rowDetail(pulls: [Pull]?, loading: Bool, error: String?) -> String {
        if let error = error { return error }
        guard let list = pulls else { return loading ? "проверяю…" : "" }
        return list.isEmpty ? "нет" : ""
    }

    /// Вторая строка запроса: `repo#N · автор · давность · проверки` (+ «черновик», «конфликт»).
    public static func detail(_ pull: Pull, now: Date) -> String {
        var parts = [pull.id, pull.author, age(pull.created, now: now), checksWord(pull.checks)]
        if pull.mergeable == "CONFLICTING" { parts.append("конфликт") }
        if pull.draft { parts.append("черновик") }
        return parts.joined(separator: " · ")
    }

    public static func checksWord(_ state: String?) -> String {
        switch state {
        case "SUCCESS": return "проверки ✓"
        case "FAILURE", "ERROR": return "проверки ✗"
        case "PENDING", "EXPECTED": return "проверки идут"
        case nil: return "без проверок"
        default: return "проверки неизвестны"
        }
    }

    public static func age(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "только что" }
        if minutes < 60 { return "\(minutes) мин" }
        if minutes < 24 * 60 { return "\(minutes / 60) ч" }
        return "\(minutes / (24 * 60)) дн"
    }

    // MARK: - по умолчанию

    /// gh вне терминала: без вопросов и цвета; PATH — с Homebrew (у приложения из Finder его нет).
    /// stdout и stderr читаем своими нитками (большой ответ забьёт трубу), срок вышел — гасим процесс.
    static func run(_ arguments: [String], _ timeout: TimeInterval) -> Run {
        guard let gh = ghPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return .missing }
        return run(executable: URL(fileURLWithPath: gh), arguments: arguments, timeout: timeout)
    }

    /// Nonblocking pipes and one monotonic deadline cover both EOF and process exit.
    /// Only this child is terminated; no terminal, shell interpolation or global kill.
    /// `launched` получает pid ребёнка сразу после запуска — тест сверяет, что погашен именно он (WF208).
    static func run(executable: URL, arguments: [String], timeout: TimeInterval,
                    launched: (pid_t) -> Void = { _ in }) -> Run {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        environment["NO_COLOR"] = "1"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return .missing }
        launched(process.processIdentifier)
        let handles = [out.fileHandleForReading, err.fileHandleForReading]
        defer { for handle in handles { try? handle.close() } }
        var descriptors = handles.map { pollfd(fd: $0.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0) }
        for fd in descriptors { _ = fcntl(fd.fd, F_SETFL, fcntl(fd.fd, F_GETFL) | O_NONBLOCK) }
        var buffers = [Data(), Data()]
        var eof = [false, false]
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var bytes = [UInt8](repeating: 0, count: 65536)
        while ProcessInfo.processInfo.systemUptime < deadline {
            for index in 0..<2 where !eof[index] {
                while ProcessInfo.processInfo.systemUptime < deadline {
                    let count = Darwin.read(descriptors[index].fd, &bytes, bytes.count)
                    if count > 0 { buffers[index].append(contentsOf: bytes.prefix(count)) }
                    else if count == 0 { eof[index] = true; descriptors[index].fd = -1; break }
                    else if errno == EINTR { continue }
                    else { break }
                    if buffers[index].count > 32 * 1024 * 1024 { break }
                }
            }
            if eof.allSatisfy({ $0 }), !process.isRunning {
                return .done(status: process.terminationStatus, out: String(decoding: buffers[0], as: UTF8.self),
                             err: String(decoding: buffers[1], as: UTF8.self))
            }
            if buffers.contains(where: { $0.count > 32 * 1024 * 1024 }) { break }
            _ = poll(&descriptors, nfds_t(descriptors.count), 20)
        }
        if process.isRunning {
            process.terminate()
            if exited.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                // SIGKILL не перехватить: ждём, пока Foundation заберёт ребёнка, — иначе под нагрузкой
                // `.timedOut` уходил раньше и процесс ещё висел зомби (нестабильный TeamPullsTests).
                _ = exited.wait(timeout: .now() + 5)
            }
        }
        return .timedOut
    }
}
