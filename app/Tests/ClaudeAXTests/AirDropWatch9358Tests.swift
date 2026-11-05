import XCTest
@testable import ClaudeAX

/// #9358: фото с AirDrop — сразу в поле Рика. Сторож «Загрузок» отбирает новые фото с карантином `sharingd`, ждёт, пока
/// они доедут и Элвис перестанет печатать, отдаёт одной порцией и после ⌘V двигает отметку CLI `voice-pasted.json`.
final class AirDropWatch9358Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("airdrop9358-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func stamp(_ date: Date, agent: String = "sharingd") -> String {
        String(format: "0081;%llx;%@;5A6AD6C9-D7E9-4ECF-BB63-FD6D0F5DC43F", UInt64(date.timeIntervalSince1970), agent)
    }

    private func entry(_ name: String, size: Int64 = 100, mtime: Double = 1, quarantine: String?) -> AirDropWatch.Entry {
        AirDropWatch.Entry(name: name, path: "/D/" + name, size: size, mtime: mtime, quarantine: quarantine)
    }

    // MARK: - чистая часть

    func testQuarantineOfAirDropIsSharingdWithArrivalTime() throws {
        let mark = try XCTUnwrap(AirDropWatch.quarantine("0081;6abbdd65;sharingd;25F4F8E4-280A-4F5B-8EFA-BA41C5557483"))
        XCTAssertEqual(mark.agent, "sharingd")
        XCTAssertEqual(mark.at, Date(timeIntervalSince1970: 0x6abbdd65))
        XCTAssertNil(AirDropWatch.quarantine(nil))
        XCTAssertNil(AirDropWatch.quarantine("мусор"))
        XCTAssertNil(AirDropWatch.quarantine("0081;zz;sharingd;x"))
    }

    func testVerdictWantsFreshSharingdAndSteadySize() {
        let fresh = stamp(now.addingTimeInterval(-5))
        XCTAssertEqual(AirDropWatch.verdict(entry("a.heic", quarantine: fresh), previousSize: 100, firstSeen: now, now: now), .ready)
        // Первый досмотр: размер ещё не с чем сравнить.
        XCTAssertEqual(AirDropWatch.verdict(entry("a.heic", quarantine: fresh), previousSize: nil, firstSeen: now, now: now), .settling)
        XCTAssertEqual(AirDropWatch.verdict(entry("a.heic", size: 200, quarantine: fresh), previousSize: 100, firstSeen: now, now: now), .settling)
        XCTAssertEqual(AirDropWatch.verdict(entry("a.heic", size: 0, quarantine: fresh), previousSize: 0, firstSeen: now, now: now), .settling)
        // Скачанное браузером и давний приезд — мимо навсегда.
        XCTAssertEqual(AirDropWatch.verdict(entry("a.jpg", quarantine: stamp(now, agent: "Safari")), previousSize: 100,
                                            firstSeen: now, now: now), .skip)
        XCTAssertEqual(AirDropWatch.verdict(entry("a.jpg", quarantine: stamp(now.addingTimeInterval(-601))), previousSize: 100,
                                            firstSeen: now, now: now), .skip)
        // Без карантина ждём его полминуты (атрибут ложится в конце приёма), потом — не AirDrop.
        XCTAssertEqual(AirDropWatch.verdict(entry("s.png", quarantine: nil), previousSize: 100,
                                            firstSeen: now.addingTimeInterval(-10), now: now), .settling)
        XCTAssertEqual(AirDropWatch.verdict(entry("s.png", quarantine: nil), previousSize: 100,
                                            firstSeen: now.addingTimeInterval(-31), now: now), .skip)
    }

    func testEnabledByDefaultOnlyWithMainChat() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: testSuiteName()))
        XCTAssertTrue(AirDropWatch.isEnabled(in: defaults, mainProject: "Rick"))
        XCTAssertTrue(AirDropWatch.isEnabled(in: defaults, mainProject: nil))
        defaults.set(false, forKey: AirDropWatch.enabledKey)
        XCTAssertFalse(AirDropWatch.isEnabled(in: defaults, mainProject: "Rick"))
        defaults.set(true, forKey: AirDropWatch.enabledKey)
        XCTAssertTrue(AirDropWatch.isEnabled(in: defaults, mainProject: nil))
    }

    func testPhotosAreTheCLIExtensions() {
        for name in ["IMG_1.HEIC", "a.jpg", "b.JPEG", "c.png", "d.heif", "e.gif", "f.webp"] {
            XCTAssertTrue(AirDropWatch.isPhoto(name), name)
        }
        for name in ["IMG_1.MOV", "a.pdf", ".hidden.jpg", "noext"] { XCTAssertFalse(AirDropWatch.isPhoto(name), name) }
    }

    func testMarkIsTheCLIFile() {
        XCTAssertEqual(AirDropWatch.mark(Data("{\"mtime\":1790000000.5}".utf8)), 1_790_000_000.5)
        XCTAssertEqual(AirDropWatch.mark(Data("{\"mtime\":true}".utf8)), 0)
        XCTAssertEqual(AirDropWatch.mark(nil), 0)
        XCTAssertEqual(AirDropWatch.markBody(12.5), "{\"mtime\":12.5}\n")
        XCTAssertEqual(AirDropWatch.guardAction, "airdrop-guard")
    }

    // MARK: - сторож

    private final class Rig {
        var files: [String: AirDropWatch.Entry] = [:]
        var queued: [() -> Void] = []
        var batches: [[String]] = []
        var notices: [String] = []
        var idle: TimeInterval = 100
        var clock: Date
        var answer = true
        let watch: AirDropWatch

        init(root: URL, now: Date, existing: [String]) {
            clock = now
            watch = AirDropWatch(directory: root, markURL: root.appendingPathComponent("voice-pasted.json"))
            watch.listNames = { [unowned self] _ in Array(self.files.keys) + existing }
            watch.inspect = { [unowned self] url in self.files[url.lastPathComponent] }
            watch.schedule = { [unowned self] _, block in self.queued.append(block) }
            watch.now = { [unowned self] in self.clock }
            watch.idleSeconds = { [unowned self] in self.idle }
            watch.onBatch = { [unowned self] paths, done in
                self.batches.append(paths)
                done(self.answer)
            }
            watch.onNotice = { [unowned self] in self.notices.append($0) }
            watch.begin(fd: -1, names: existing)
        }

        func add(_ name: String, arrived: Date, mtime: Double = 5, agent: String = "sharingd") {
            files[name] = AirDropWatch.Entry(name: name, path: "/D/" + name, size: 100, mtime: mtime,
                                             quarantine: String(format: "0081;%llx;%@;X",
                                                                UInt64(arrived.timeIntervalSince1970), agent))
        }

        /// Досмотр и всё, что он запланировал, пока очередь не опустеет (не больше `limit` шагов).
        func drain(limit: Int = 10, step: TimeInterval = 1) {
            watch.scan()
            var left = limit
            while !queued.isEmpty, left > 0 {
                left -= 1
                clock = clock.addingTimeInterval(step)
                queued.removeFirst()()
            }
        }
    }

    func testNewAirDropPhotosGoAsOneBatchAndMoveTheCLIMark() throws {
        let rig = Rig(root: root, now: now, existing: ["old.jpg"])
        rig.add("IMG_2.HEIC", arrived: now.addingTimeInterval(-1), mtime: 30)
        rig.add("IMG_1.HEIC", arrived: now.addingTimeInterval(-2), mtime: 20)
        rig.add("site.jpg", arrived: now, agent: "Safari")
        rig.files["notes.pdf"] = AirDropWatch.Entry(name: "notes.pdf", path: "/D/notes.pdf", size: 1, mtime: 1,
                                                    quarantine: stamp(now))
        rig.drain()
        // По времени приезда; старое, скачанное браузером и не фото — мимо.
        XCTAssertEqual(rig.batches, [["/D/IMG_1.HEIC", "/D/IMG_2.HEIC"]])
        XCTAssertEqual(AirDropWatch.mark(try Data(contentsOf: root.appendingPathComponent("voice-pasted.json"))), 30)
        // Вставленное второй раз не идёт.
        rig.drain()
        XCTAssertEqual(rig.batches.count, 1)
    }

    func testMarkNeverMovesBackAndStaysWhenPasteFailed() throws {
        let markURL = root.appendingPathComponent("voice-pasted.json")
        try Data("{\"mtime\":100}".utf8).write(to: markURL)
        let rig = Rig(root: root, now: now, existing: [])
        rig.add("a.heic", arrived: now, mtime: 50)
        rig.drain()
        XCTAssertEqual(AirDropWatch.mark(try Data(contentsOf: markURL)), 100, "фото со старым mtime отметку не отматывает")
        rig.answer = false
        rig.add("b.heic", arrived: rig.clock, mtime: 500)
        rig.drain()
        XCTAssertEqual(rig.batches.count, 2)
        XCTAssertEqual(AirDropWatch.mark(try Data(contentsOf: markURL)), 100, "⌘V не нажат — отметка CLI на месте")
    }

    func testWaitsWhileTypingThenGivesUpWithNotice() {
        let rig = Rig(root: root, now: now, existing: [])
        rig.idle = 0.5
        rig.add("a.heic", arrived: now)
        rig.drain(limit: 5)
        XCTAssertTrue(rig.batches.isEmpty, "Элвис печатает — окно не выдёргиваем")
        rig.idle = 10
        rig.drain()
        XCTAssertEqual(rig.batches, [["/D/a.heic"]], "перестал печатать — вставили")

        rig.idle = 0.5
        rig.add("b.heic", arrived: rig.clock)
        rig.drain(limit: 200)
        XCTAssertEqual(rig.batches.count, 1)
        XCTAssertEqual(rig.notices.count, 1)
        XCTAssertTrue(rig.notices[0].contains("ты печатал"), rig.notices[0])
    }

    func testDeletedNameComesBackAsNew() {
        let rig = Rig(root: root, now: now, existing: [])
        rig.add("a.heic", arrived: now)
        rig.drain()
        rig.files["a.heic"] = nil
        rig.drain()
        rig.add("a.heic", arrived: rig.clock)
        rig.drain()
        XCTAssertEqual(rig.batches, [["/D/a.heic"], ["/D/a.heic"]])
    }

    func testBigBatchGoesByLimit() {
        let rig = Rig(root: root, now: now, existing: [])
        for index in 0..<25 { rig.add(String(format: "IMG_%02d.HEIC", index), arrived: now.addingTimeInterval(Double(index) - 30)) }
        rig.drain()
        XCTAssertEqual(rig.batches.map { $0.count }, [AirDropWatch.limit, 5])
        XCTAssertEqual(rig.batches.first?.first, "/D/IMG_00.HEIC")
    }
}
