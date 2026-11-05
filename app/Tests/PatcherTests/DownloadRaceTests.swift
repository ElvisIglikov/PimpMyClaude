import CryptoKit
import XCTest
@testable import Patcher

/// Заглушка сети для гонки: каждый адрес отдаёт своё тело кусками с паузой, может соврать про
/// Content-Length, оборваться, зависнуть или ответить ошибкой. Клиенту отвечает на его же ранлупе.
/// #11258: умеет `Range` (206 с `Content-Range`) или нет (`ranges = false` — 200 целиком), считает
/// запросы и помнит их заголовок `Range`.
final class RaceStubProtocol: URLProtocol {
    struct Plan {
        var status = 200
        var body = Data()
        var chunk = 64 * 1024
        var interval: TimeInterval = 0.01
        /// Content-Length в ответе; nil — длина тела.
        var contentLength: Int?
        /// После стольких байт — обрыв соединения.
        var failAfter: Int?
        /// После стольких байт — тишина до отмены.
        var hangAfter: Int?
        /// После стольких байт — струйка: (байты, новый кусок, новая пауза).
        var slowAfter: (bytes: Int, chunk: Int, interval: TimeInterval)?
        /// Какой ошибкой рвать: временная (`networkConnectionLost`) — докачка, прочие — провал полосы.
        var failCode: URLError.Code = .networkConnectionLost
        /// `failAfter` и `hangAfter` — только на первых стольких запросах; дальше отдаёт честно.
        var breaksFor = Int.max
        /// Умеет `Range: bytes=N-`; нет — отвечает 200 и всем телом.
        var ranges = true
        /// После стольких байт — чистое закрытие без ошибки (раньше срока); как `failAfter`, по `breaksFor`.
        var closeAfter: Int?
        /// Ответ по номеру запроса (с 1): например `[2: 503]` — второй запрос получает 503 без тела.
        var statuses: [Int: Int] = [:]
    }

    private static let lock = NSLock()
    private static var plans: [String: Plan] = [:]
    private static var starts: [String: Int] = [:]
    private static var rangeHeaders: [String: [String?]] = [:]
    private static var breaking: Set<String> = []

    static func reset(_ newPlans: [String: Plan]) {
        lock.lock(); defer { lock.unlock() }
        plans = newPlans
        starts = [:]
        rangeHeaders = [:]
        breaking = []
    }

    /// Оборвать адрес ошибкой `failCode` на следующем шаге — по событию в тесте, не по счёту байтов (#11463).
    static func breakNow(_ url: String) {
        lock.lock(); defer { lock.unlock() }
        breaking.insert(url)
    }

    /// Заголовок `Range` каждого запроса по порядку (nil — без него).
    static func ranges(_ url: String) -> [String?] {
        lock.lock(); defer { lock.unlock() }
        return rangeHeaders[url] ?? []
    }

    static func started(_ url: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return starts[url] ?? 0
    }

    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RaceStubProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private let queue = DispatchQueue(label: "race-stub")
    private var timer: DispatchSourceTimer?
    private var runLoop: CFRunLoop?
    private var key = ""
    private var stopped = false
    private var sent = 0
    private var slowed = false

    override func startLoading() {
        key = request.url!.absoluteString
        RaceStubProtocol.lock.lock()
        var plan = RaceStubProtocol.plans[key] ?? Plan(status: 404)
        RaceStubProtocol.starts[key, default: 0] += 1
        let range = request.value(forHTTPHeaderField: "Range")
        RaceStubProtocol.rangeHeaders[key, default: []].append(range)
        let number = RaceStubProtocol.starts[key]!
        RaceStubProtocol.lock.unlock()
        if number > plan.breaksFor { plan.failAfter = nil; plan.hangAfter = nil; plan.closeAfter = nil }
        runLoop = CFRunLoopGetCurrent()
        var status = plan.statuses[number] ?? plan.status
        var headers = ["Content-Length": String(plan.contentLength ?? plan.body.count)]
        if plan.ranges, status == 200, let range = range, range.hasPrefix("bytes="), range.hasSuffix("-"),
           let from = Int(range.dropFirst(6).dropLast()) {
            if from < plan.body.count {
                status = 206
                sent = from
                headers = ["Content-Length": String(plan.body.count - from),
                           "Content-Range": "bytes \(from)-\(plan.body.count - 1)/\(plan.body.count)"]
            } else {
                status = 416
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard status == 200 || status == 206 else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // Строгий таймер (#11463): обычный система склеивает — шаг 5 мс шёл ≈11 мс, а под `taskpolicy -b` ≈70 мс,
        // и скорости полос, на которых стоит судья, зависели от приоритета прогона. Строгий держит шаг в любом режиме.
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now() + plan.interval, repeating: plan.interval)
        timer.setEventHandler { [weak self] in self?.step(plan) }
        self.timer = timer
        timer.resume()
    }

    override func stopLoading() {
        queue.sync {
            stopped = true
            timer?.cancel()
            timer = nil
        }
    }

    /// На очереди заглушки: следующий кусок или финал — клиенту на его ранлупе.
    private func step(_ plan: Plan) {
        guard !stopped else { return }
        RaceStubProtocol.lock.lock()
        let broken = RaceStubProtocol.breaking.contains(key)
        RaceStubProtocol.lock.unlock()
        if broken {
            finish { $0.client?.urlProtocol($0, didFailWithError: URLError(plan.failCode)) }
            return
        }
        if let hang = plan.hangAfter, sent >= hang { return }
        if let slow = plan.slowAfter, sent >= slow.bytes, !slowed {
            slowed = true
            timer?.schedule(deadline: .now() + slow.interval, repeating: slow.interval)
        }
        if let fail = plan.failAfter, sent >= fail {
            finish { $0.client?.urlProtocol($0, didFailWithError: URLError(plan.failCode)) }
            return
        }
        if let close = plan.closeAfter, sent >= close {
            finish { $0.client?.urlProtocolDidFinishLoading($0) }
            return
        }
        guard sent < plan.body.count else {
            finish { $0.client?.urlProtocolDidFinishLoading($0) }
            return
        }
        let chunk = slowed ? plan.slowAfter?.chunk ?? plan.chunk : plan.chunk
        var end = min(plan.body.count, sent + chunk)
        if let limit = plan.failAfter ?? plan.hangAfter ?? plan.closeAfter { end = min(end, max(limit, sent + 1)) }
        let piece = plan.body.subdata(in: sent..<end)
        sent = end
        perform { $0.client?.urlProtocol($0, didLoad: piece) }
    }

    private func finish(_ body: @escaping (RaceStubProtocol) -> Void) {
        timer?.cancel()
        timer = nil
        stopped = true
        perform(body)
    }

    private func perform(_ body: @escaping (RaceStubProtocol) -> Void) {
        guard let runLoop = runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { body(self) }
        CFRunLoopWakeUp(runLoop)
    }
}

/// Гонка загрузки (WF86, план WF87 батч A п. 2): лидер, отсев отстающего, завис, падение лидера →
/// перезапуск отключённых, все упали, отмена, чужой Content-Length. Время ужато правилами.
/// Докачка с места (#11258) — `DownloadResume11258Tests`.
final class DownloadRaceTests: XCTestCase {
    private var scratch: URL!
    private let snapshotQueue = DispatchQueue(label: "race-snapshots")
    private var snapshots: [RaceSnapshot] = []

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimpmyclaude-race-\(UUID().uuidString)", isDirectory: true)
        snapshots = []
    }

    override func tearDownWithError() throws {
        if let scratch = scratch { try? FileManager.default.removeItem(at: scratch) }
        RaceStubProtocol.reset([:])
    }

    private func body(_ size: Int, seed: UInt8) -> Data {
        Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func source(_ id: String, _ data: Data, sha known: String? = nil, size: Int64? = nil) -> DownloadSource {
        DownloadSource(id: id, title: id.uppercased(), url: URL(string: "https://\(id).test/Claude.dmg")!,
                       expectedSize: size ?? Int64(data.count), sha256: known ?? sha(data), format: .dmg)
    }

    private func rules(deadline: TimeInterval? = nil) -> ClaudeDownloadRace.Rules {
        var rules = ClaudeDownloadRace.Rules()
        rules.warmup = 0.3
        rules.stallSeconds = 0.6
        rules.tick = 0.05
        rules.speedWindow = 0.3
        rules.deadline = deadline
        rules.maxResumes = 3
        rules.resumePause = 0.01
        rules.resumePauseCap = 0.05
        return rules
    }

    private func race(_ sources: [DownloadSource], rules: ClaudeDownloadRace.Rules? = nil) -> ClaudeDownloadRace {
        let race = ClaudeDownloadRace(sources: sources, directory: scratch, rules: rules ?? self.rules(),
                                      configuration: RaceStubProtocol.configuration())
        race.callbackQueue = snapshotQueue
        race.onSnapshot = { [unowned self] in self.snapshots.append($0) }
        return race
    }

    private func states(of id: String) -> [RaceLane.State] {
        snapshotQueue.sync { snapshots.compactMap { $0.lanes.first { $0.id == id }?.state } }
    }

    private func lastSnapshot() -> RaceSnapshot? { snapshotQueue.sync { snapshots.last } }

    func testLeaderWinsAndFileIsVerified() throws {
        let data = body(1_500_000, seed: 1)
        RaceStubProtocol.reset([
            "https://fast.test/Claude.dmg": .init(body: data, chunk: 64 * 1024, interval: 0.01),
            "https://slow.test/Claude.dmg": .init(body: data, chunk: 8 * 1024, interval: 0.01),
        ])
        let winner = try race([source("fast", data), source("slow", data)]).run()
        XCTAssertEqual(winner.source.id, "fast")
        XCTAssertEqual(try Data(contentsOf: winner.file), data, "файл победителя — ровно тело")
        XCTAssertTrue(states(of: "fast").contains(.leading), "быстрый шёл лидером")
        let last = try XCTUnwrap(lastSnapshot())
        XCTAssertTrue(last.finished)
        XCTAssertEqual(last.lanes.first { $0.id == "fast" }?.state, .won)
        XCTAssertEqual(last.fraction, 1, accuracy: 0.0001)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
        XCTAssertEqual(leftovers, [winner.file.lastPathComponent], "файлы проигравших убраны")
    }

    func testLaggardIsDroppedAfterWarmup() throws {
        let data = body(3_000_000, seed: 2)
        RaceStubProtocol.reset([
            "https://fast.test/Claude.dmg": .init(body: data, chunk: 32 * 1024, interval: 0.02),
            "https://slow.test/Claude.dmg": .init(body: data, chunk: 2 * 1024, interval: 0.02),
        ])
        let winner = try race([source("fast", data), source("slow", data)]).run()
        XCTAssertEqual(winner.source.id, "fast")
        XCTAssertTrue(states(of: "slow").contains(.dropped("отстал — отключён")), "\(states(of: "slow"))")
        XCTAssertEqual(RaceStubProtocol.started("https://slow.test/Claude.dmg"), 1, "лидер не падал — не перезапускали")
    }

    /// До #11258 «завис» отключал полосу и перезапускал её с нуля один раз; теперь — докачка с места,
    /// `maxResumes` повторов подряд без новых байтов, потом провал.
    func testStalledSourceResumesUntilMaxResumesThenFails() {
        let data = body(500_000, seed: 3)
        RaceStubProtocol.reset(["https://hang.test/Claude.dmg": .init(body: data, hangAfter: 10_000)])
        XCTAssertThrowsError(try race([source("hang", data)]).run()) { error in
            let text = ClaudeUpdater.describe(error)
            XCTAssertTrue(text.contains("завис") && text.contains("3 повторов подряд"), text)
        }
        XCTAssertEqual(RaceStubProtocol.started("https://hang.test/Claude.dmg"), 4, "первый запрос и три повтора")
        XCTAssertEqual(RaceStubProtocol.ranges("https://hang.test/Claude.dmg"),
                       [nil, "bytes=10000-", "bytes=10000-", "bytes=10000-"], "повторы — с места, не с нуля")
    }

    /// Сетевой обрыв лидера с #11258 — докачка (`DownloadResume11258Tests`); здесь срыв окончательный.
    func testLeaderHardFailureRestartsDroppedLane() throws {
        let data = body(6_000_000, seed: 4)
        RaceStubProtocol.reset([
            "https://fast.test/Claude.dmg": .init(body: data, chunk: 64 * 1024, interval: 0.01, failAfter: 5_000_000,
                                                 failCode: .badServerResponse),
            "https://slow.test/Claude.dmg": .init(body: data, chunk: 16 * 1024, interval: 0.01),
        ])
        let winner = try race([source("fast", data), source("slow", data)]).run()
        XCTAssertEqual(winner.source.id, "slow", "лидер упал — выручил перезапущенный")
        XCTAssertTrue(states(of: "slow").contains(.dropped("отстал — отключён")), "\(states(of: "slow"))")
        XCTAssertEqual(RaceStubProtocol.started("https://slow.test/Claude.dmg"), 2)
        XCTAssertEqual(try Data(contentsOf: winner.file), data)
        if case .failed = lastSnapshot()?.lanes.first(where: { $0.id == "fast" })?.state {} else {
            XCTFail("упавший лидер — failed: \(String(describing: lastSnapshot()))")
        }
    }

    /// Живой случай 25.09: лидер рванул и сполз до струйки — отключённые оживают и забирают гонку.
    func testSaggingLeaderRevivesDroppedLanes() throws {
        let data = body(6_000_000, seed: 12)
        RaceStubProtocol.reset([
            "https://burst.test/Claude.dmg": .init(body: data, chunk: 64 * 1024, interval: 0.01,
                                                  slowAfter: (5_000_000, 1_024, 0.04)),
            "https://steady.test/Claude.dmg": .init(body: data, chunk: 16 * 1024, interval: 0.01),
        ])
        let winner = try race([source("burst", data), source("steady", data)]).run()
        XCTAssertEqual(winner.source.id, "steady")
        XCTAssertTrue(states(of: "steady").contains(.dropped("отстал — отключён")), "\(states(of: "steady"))")
        XCTAssertEqual(RaceStubProtocol.started("https://steady.test/Claude.dmg"), 2, "ожил один раз")
        XCTAssertEqual(RaceStubProtocol.started("https://burst.test/Claude.dmg"), 1, "сползший лидер с нуля не перезапускается")
    }

    func testWinnerWithWrongChecksumFailsAndDroppedLaneRestarts() throws {
        let data = body(4_000_000, seed: 5)
        RaceStubProtocol.reset([
            "https://fast.test/Claude.dmg": .init(body: data, chunk: 64 * 1024, interval: 0.01),
            "https://slow.test/Claude.dmg": .init(body: data, chunk: 12 * 1024, interval: 0.01),
        ])
        let liar = source("fast", data, sha: String(repeating: "0", count: 64))
        let winner = try race([liar, source("slow", data)]).run()
        XCTAssertEqual(winner.source.id, "slow")
        XCTAssertEqual(lastSnapshot()?.lanes.first { $0.id == "fast" }?.state, .failed("sha256 не сошлась"))
        XCTAssertEqual(RaceStubProtocol.started("https://slow.test/Claude.dmg"), 2)
    }

    /// Гейт 1 WF87, A2: сорвался НЕ лидер — попытку отключённого не тратим; она нужна, когда лидер
    /// не пройдёт проверку. Раньше B оживал на срыве C, снова отставал — и выручать было некому.
    /// #11463: порядок — по событиям, не по шуму замера скорости (под нагрузкой flaky на миг выходил в лидеры,
    /// и его срыв тратил попытку lag). lag первым запросом молчит — прогноз бесконечный, отключат при любом темпе;
    /// flaky в 8 раз медленнее лидера и рвётся, как только lag отключён.
    func testNonLeaderFailureKeepsDroppedLaneForLeaderCheck() throws {
        let data = body(3_000_000, seed: 14)
        let flaky = "https://flaky.test/Claude.dmg"
        RaceStubProtocol.reset([
            "https://lead.test/Claude.dmg": .init(body: data, chunk: 16 * 1024, interval: 0.01),
            "https://lag.test/Claude.dmg": .init(body: data, chunk: 32 * 1024, interval: 0.01, hangAfter: 0, breaksFor: 1),
            flaky: .init(body: data, chunk: 2 * 1024, interval: 0.01, failCode: .badServerResponse),
        ])
        var rules = self.rules()
        rules.warmup = 0.5        // первые байты лидера и flaky приходят до суда при любой нагрузке
        rules.stallSeconds = 5    // «завис» здесь не проверяем
        rules.dropFactor = 100    // отсев по скорости не нужен: lag отключает бесконечный прогноз
        let liar = source("lead", data, sha: String(repeating: "0", count: 64))
        let race = self.race([liar, source("lag", data), source("flaky", data)], rules: rules)
        race.onSnapshot = { [unowned self] snapshot in
            self.snapshots.append(snapshot)
            if snapshot.lanes.contains(where: { $0.id == "lag" && $0.state == .dropped("отстал — отключён") }) {
                RaceStubProtocol.breakNow(flaky)
            }
        }
        let winner = try race.run()
        XCTAssertEqual(winner.source.id, "lag", "лидер не прошёл sha — выручил отключённый")
        let order = snapshotQueue.sync {
            snapshots.map { snap in (lead: snap.lanes.first { $0.id == "lead" }?.state, lag: snap.lanes.first { $0.id == "lag" }?.state) }
        }
        let dropped = try XCTUnwrap(order.firstIndex { $0.lag == .dropped("отстал — отключён") }, "\(states(of: "lag"))")
        let revived = try XCTUnwrap(order[dropped...].firstIndex { $0.lag != .dropped("отстал — отключён") })
        XCTAssertEqual(order[revived].lead, .failed("sha256 не сошлась"), "lag ожил на срыве flaky, а не на провале лидера")
        XCTAssertEqual(RaceStubProtocol.started("https://lag.test/Claude.dmg"), 2, "перезапуск — только на провале лидера")
        XCTAssertEqual(RaceStubProtocol.started(flaky), 1)
        XCTAssertEqual(lastSnapshot()?.lanes.first { $0.id == "lead" }?.state, .failed("sha256 не сошлась"))
        XCTAssertEqual(try Data(contentsOf: winner.file), data)
    }

    /// Гейт 1 WF87, A3: у лидера к финишу прогноз стремится к нулю — почти догнавшую (остаток меньше
    /// `stallSeconds`) не отключаем: лидер не прошёл проверку — она докачивает, а не начинает с нуля.
    func testNearlyDoneLaneIsNotDroppedNearLeaderFinish() throws {
        let data = body(3_000_000, seed: 15)
        RaceStubProtocol.reset([
            "https://lead.test/Claude.dmg": .init(body: data, chunk: 64 * 1024, interval: 0.01),
            "https://close.test/Claude.dmg": .init(body: data, chunk: 32 * 1024, interval: 0.01),
        ])
        var rules = self.rules()
        rules.warmup = 0.05
        rules.stallSeconds = 2
        let liar = source("lead", data, sha: String(repeating: "0", count: 64))
        let winner = try race([liar, source("close", data)], rules: rules).run()
        XCTAssertEqual(winner.source.id, "close")
        XCTAssertEqual(RaceStubProtocol.started("https://close.test/Claude.dmg"), 1, "докачала, а не с нуля")
        XCTAssertFalse(states(of: "close").contains { if case .dropped = $0 { return true }; return false },
                       "\(states(of: "close"))")
    }

    func testAllSourcesFailWithReasonsInWords() {
        let data = body(200_000, seed: 6)
        RaceStubProtocol.reset([
            "https://gone.test/Claude.dmg": .init(status: 404, body: data),
            "https://broken.test/Claude.dmg": .init(body: data, chunk: 1_000, failAfter: 5_000),
        ])
        XCTAssertThrowsError(try race([source("gone", data), source("broken", data)]).run()) { error in
            let text = ClaudeUpdater.describe(error)
            XCTAssertTrue(text.contains("ни один источник не докачал"), text)
            XCTAssertTrue(text.contains("GONE — сервер ответил 404"), text)
            XCTAssertTrue(text.contains("BROKEN — обрыв, 3 повторов подряд без новых байтов"), text)
        }
        // #11258: оборвавшийся оставил недокачанное с меткой адреса — следующая гонка продолжит с места.
        XCTAssertEqual(((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []).sorted(),
                       ["broken.part", "broken.part.url"], "404 убран, оборванное оставлено")
    }

    func testCancelStopsWholeRace() {
        let data = body(5_000_000, seed: 7)
        RaceStubProtocol.reset([
            "https://a.test/Claude.dmg": .init(body: data, chunk: 4 * 1024, interval: 0.02),
            "https://b.test/Claude.dmg": .init(body: data, chunk: 4 * 1024, interval: 0.02),
        ])
        let control = DownloadControl()
        let race = self.race([source("a", data), source("b", data)])
        control.attach(race)
        // Отмена посреди загрузки — по событию «у обеих полос есть байты», не по часам (#11463).
        race.onSnapshot = { [unowned self] snapshot in
            self.snapshots.append(snapshot)
            if snapshot.lanes.allSatisfy({ $0.bytes > 0 }) { control.cancel() }
        }
        XCTAssertThrowsError(try race.run()) { error in
            guard case ClaudeUpdateError.cancelled = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(control.isCancelled)
        XCTAssertEqual(lastSnapshot()?.lanes.map { $0.state }, [.dropped("отменено"), .dropped("отменено")])
        // #11258: отменённое (сон Мака, «Отмена») не стирается — докачается в следующий раз.
        XCTAssertEqual(((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []).sorted(),
                       ["a.part", "a.part.url", "b.part", "b.part.url"])
    }

    func testCancelBeforeStartLaunchesNothing() {
        let data = body(100_000, seed: 13)
        RaceStubProtocol.reset(["https://a.test/Claude.dmg": .init(body: data)])
        let control = DownloadControl()
        control.cancel()
        let race = self.race([source("a", data)])
        control.attach(race)
        XCTAssertThrowsError(try race.run()) { error in
            guard case ClaudeUpdateError.cancelled = error else { return XCTFail("\(error)") }
        }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(RaceStubProtocol.started("https://a.test/Claude.dmg"), 0, "ни одного запроса")
    }

    func testWrongContentLengthIsRefusedAtFirstBytes() throws {
        let data = body(800_000, seed: 8)
        let other = body(900_000, seed: 9)
        RaceStubProtocol.reset([
            // R2 `latest/mac` уже сменился: отдаёт другой файл другого размера.
            "https://moved.test/Claude.dmg": .init(body: other, chunk: 256 * 1024, interval: 0.002),
            "https://pinned.test/Claude.dmg": .init(body: data, chunk: 32 * 1024, interval: 0.01),
        ])
        let winner = try race([source("moved", data), source("pinned", data)]).run()
        XCTAssertEqual(winner.source.id, "pinned")
        let moved = lastSnapshot()?.lanes.first { $0.id == "moved" }
        XCTAssertEqual(moved?.bytes, 0, "ни байта чужого файла")
        if case .failed(let why) = moved?.state { XCTAssertTrue(why.hasPrefix("отдаёт другой файл"), why) }
        else { XCTFail("\(String(describing: moved))") }
    }

    func testSourceWithoutKnownSizeUsesContentLength() throws {
        let data = body(300_000, seed: 10)
        RaceStubProtocol.reset([
            "https://short.test/Claude.dmg": .init(body: data, contentLength: data.count + 10),
        ])
        let unknown = DownloadSource(id: "short", title: "SHORT", url: URL(string: "https://short.test/Claude.dmg")!,
                                     expectedSize: nil, sha256: nil, format: .dmg)
        XCTAssertThrowsError(try race([unknown]).run(), "обещал больше, чем отдал")
    }

    func testDeadlineEndsRace() {
        let data = body(5_000_000, seed: 11)
        RaceStubProtocol.reset(["https://slow.test/Claude.dmg": .init(body: data, chunk: 1024, interval: 0.02)])
        XCTAssertThrowsError(try race([source("slow", data)], rules: rules(deadline: 0.3)).run()) { error in
            XCTAssertTrue(ClaudeUpdater.describe(error).contains("не успел"), ClaudeUpdater.describe(error))
        }
    }
}
