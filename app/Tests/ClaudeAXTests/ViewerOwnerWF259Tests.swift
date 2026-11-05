import Darwin
import XCTest
@testable import ClaudeAX

/// #8302 (WF259, зеркало `ChannelOwnerTests` PimpViewer): токен канала уходит только галерее. Перед запросом к 47616
/// `ViewerClient` узнаёт, кто слушает порт (`PortOwner`, libproc): свой пользователь и программа PimpViewer — запрос
/// идёт; чужой процесс, другой пользователь или никого — не идёт, у сиденья прежний путь. Слушатели — настоящие, на
/// порту 0, в процессе теста; живые порты 47615/47616 и склад не трогаем.
final class ViewerOwnerWF259Tests: XCTestCase {
    typealias FakeViewer = ViewerChannelWF104Tests.FakeViewer
    private let token = String(repeating: "a1", count: 16)
    private let galleryPath = "/Applications/PimpViewer.app/Contents/MacOS/PimpViewer"
    private var tmp: URL!
    private var tokenURL: URL { tmp.appendingPathComponent("channel.token") }

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("viewer-owner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try Data((token + "\n").utf8).write(to: tokenURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Клиент без приложения; определитель — настоящий, пока тест его не подменит.
    private func client(_ fake: FakeViewer, launches: Bool = false) -> ViewerClient {
        let client = ViewerClient(port: fake.port, tokenURL: tokenURL, launches: launches)
        client.installed = { true }
        client.running = { false }
        client.launch = { XCTFail("запуск не ждали") }
        client.raise = { XCTFail("вывод вперёд не ждали"); return true }
        return client
    }

    private func accept(_ client: ViewerClient) -> Bool {
        let done = expectation(description: "accept")
        var result = true
        client.accept(path: "/p/a.html", mode: .click, chat: "local_a") { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    private func state(_ client: ViewerClient) -> Bool {
        let done = expectation(description: "state")
        var result = false
        client.state { result = $0 != nil; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    /// libproc находит свой слушатель: этот процесс, его путь; быстрый путь по pid — то же; чужой uid (launchd) — пусто;
    /// обход своих процессов — в доли таймаута запроса.
    func testListenersFindOwnSocket() throws {
        let fake = try FakeViewer()
        let port = fake.port
        XCTAssertNotEqual(port, 0)
        let me = PortOwner.Holder(pid: getpid(), path: try XCTUnwrap(PortOwner.path(of: getpid())))
        let started = Date()
        let all = try XCTUnwrap(PortOwner.listeners(port: port))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "обход своих процессов съел бы таймаут запроса")
        XCTAssertEqual(all, [me])
        XCTAssertEqual(PortOwner.listeners(port: port, pid: getpid()), [me])
        XCTAssertEqual(PortOwner.listeners(port: port, pid: 1), [], "launchd — чужой uid")
        XCTAssertEqual(PortOwner.owner(of: getpid()), getuid())
        XCTAssertFalse(ViewerClient.isViewer(all), "процесс теста — не PimpViewer")
        fake.listener.cancel()
        // NWListener закрывает сокет не сразу.
        let deadline = Date().addingTimeInterval(3)
        while PortOwner.listeners(port: port, pid: getpid()) != [], Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(PortOwner.listeners(port: port, pid: getpid()), [], "слушатель закрыт")
    }

    /// Галерея — только программа PimpViewer из /Applications или ~/Applications, и все свои слушатели порта — она.
    func testOnlyViewerProgramIsViewer() {
        let paths = ViewerClient.viewerPaths(home: "/Users/e")
        let home = "/Users/e/Applications/PimpViewer.app/Contents/MacOS/PimpViewer"
        let fake = "/Users/e/Library/Containers/x/Data/PimpViewer.app/Contents/MacOS/PimpViewer"
        XCTAssertEqual(paths, [galleryPath, home])
        XCTAssertTrue(ViewerClient.isViewer([.init(pid: 10, path: galleryPath)], paths: paths))
        XCTAssertTrue(ViewerClient.isViewer([.init(pid: 10, path: home)], paths: paths))
        XCTAssertFalse(ViewerClient.isViewer([.init(pid: 10, path: fake)], paths: paths), "песочница с тем же именем")
        XCTAssertFalse(ViewerClient.isViewer([.init(pid: 10, path: galleryPath), .init(pid: 11, path: fake)], paths: paths),
                       "второй слушатель того же порта")
        XCTAssertFalse(ViewerClient.isViewer([.init(pid: 10, path: "")], paths: paths), "путь не прочитан")
        XCTAssertFalse(ViewerClient.isViewer([], paths: paths), "своего слушателя нет — порт у другого пользователя")
        XCTAssertFalse(ViewerClient.isViewer(nil, paths: paths))
    }

    /// Поддельная галерея на порту 0 и настоящий определитель (процесс теста — не PimpViewer): ни одного запроса,
    /// токен не ушёл, приложение не запускается, `/ping` не ждём; другой пользователь и сбой libproc — тоже без запроса.
    func testNoTokenToForeignListener() throws {
        let fake = try FakeViewer()
        fake.answer = { _, _ in FakeViewer.json(#"{"focus":false,"taken":true,"ready":true}"#) }
        let client = client(fake, launches: true)
        let started = Date()
        XCTAssertFalse(accept(client))
        XCTAssertFalse(state(client))
        client.ping()
        client.show()
        client.gallery(chat: "local_a", on: true)
        XCTAssertFalse(accept(client))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "чужой на порту — `ready` не ждём")
        XCTAssertEqual(fake.requests.count, 0, "чужому слушателю ушёл запрос с токеном")

        for owners in [{ (_: UInt16, _: pid_t?) -> [PortOwner.Holder]? in [] }, { _, _ in nil }] {
            client.owners = owners
            XCTAssertFalse(state(client))
        }
        XCTAssertEqual(fake.requests.count, 0)
        XCTAssertEqual(client.status, "down/0/2")
    }

    /// Подменённый определитель с путём галереи — запрос идёт, с токеном.
    func testGalleryPathSendsRequest() throws {
        let fake = try FakeViewer()
        fake.answer = { _, _ in FakeViewer.json(#"{"focus":false,"taken":true}"#) }
        let client = client(fake)
        let gallery = galleryPath
        client.owners = { _, _ in [.init(pid: 42, path: gallery)] }
        XCTAssertTrue(accept(client))
        let first = try XCTUnwrap(fake.requests.first)
        XCTAssertTrue(first.hasPrefix("GET /accept?mode=click&"), first)
        XCTAssertTrue(first.lowercased().contains("x-pimp-viewer-token: \(token)\r\n"))
    }

    /// Кэш по pid: проверенная галерея, пока слушает, — только быстрый путь; ушла с порта — полный обход, и чужому
    /// запроса нет; срок кэша вышел — снова полный обход.
    func testViewerPidCachedWhileItListens() throws {
        let fake = try FakeViewer()
        fake.answer = { _, _ in FakeViewer.json(#"{"counts":{},"filterChat":null}"#) }
        let client = client(fake)
        let lock = NSLock()
        var calls: [pid_t?] = []
        var alive = true
        let gallery = galleryPath
        client.owners = { _, pid in
            lock.lock(); defer { lock.unlock() }
            calls.append(pid)
            if let pid = pid { return alive && pid == 42 ? [.init(pid: 42, path: gallery)] : [] }
            return alive ? [.init(pid: 42, path: gallery)] : [.init(pid: 77, path: "/tmp/evil")]
        }
        func seen() -> [pid_t?] { lock.lock(); defer { lock.unlock() }; return calls }
        XCTAssertTrue(state(client))
        XCTAssertTrue(state(client))
        XCTAssertEqual(seen(), [nil, 42], "второй запрос — без обхода всех процессов")

        lock.lock(); alive = false; lock.unlock()
        XCTAssertFalse(state(client))
        XCTAssertEqual(seen(), [nil, 42, 42, nil])
        XCTAssertEqual(fake.requests.count, 2, "галерея ушла, порт у чужого — запроса нет")

        lock.lock(); alive = true; calls = []; lock.unlock()
        client.ownerTTL = 0
        XCTAssertTrue(state(client))
        XCTAssertTrue(state(client))
        XCTAssertEqual(seen(), [nil, nil], "срок кэша вышел — полный обход")
    }

    /// Чужой своего пользователя на порту галереи: PimpViewer не запускается (ни кликом, ни на старте), строка в журнал —
    /// одна на состав слушателей.
    func testForeignListenerNoLaunchOneNotePerHolders() throws {
        let fake = try FakeViewer()
        let client = client(fake, launches: true)
        let lock = NSLock()
        var notes: [String] = []
        client.note = { line in lock.lock(); notes.append(line); lock.unlock() }
        func logged() -> [String] { lock.lock(); defer { lock.unlock() }; return notes }
        var holders: [PortOwner.Holder] = [.init(pid: 77, path: "/tmp/evil")]
        client.owners = { _, _ in holders }

        XCTAssertFalse(accept(client))
        XCTAssertFalse(accept(client))
        client.start()
        XCTAssertFalse(state(client))
        XCTAssertEqual(logged(), ["порт галереи \(fake.port) слушает не PimpViewer (pid 77 /tmp/evil) — токен не шлю"])

        holders.append(.init(pid: 78, path: galleryPath))
        XCTAssertFalse(accept(client), "второй слушатель рядом с галереей — тоже чужой")
        XCTAssertFalse(accept(client))
        XCTAssertEqual(logged().count, 2)
        XCTAssertTrue(logged()[1].contains("(pid 77 /tmp/evil, pid 78 \(galleryPath))"), logged()[1])
        XCTAssertTrue(fake.requests.isEmpty)
    }

    /// 47615 не встал из-за `EADDRINUSE` — кто его держит: свой чужак (pid, путь) или «своего нет».
    func testBusyPimpPortNote() {
        XCTAssertEqual(HtmlChromeOpener.busyNote(holders: [.init(pid: 9, path: "/tmp/listener")]),
                       "ВНИМАНИЕ: порт 47615 занят чужим процессом (pid 9 /tmp/listener)")
        XCTAssertEqual(HtmlChromeOpener.busyNote(holders: [.init(pid: 9, path: "")]),
                       "ВНИМАНИЕ: порт 47615 занят чужим процессом (pid 9 ?)")
        for holders in [[], nil] as [[PortOwner.Holder]?] {
            XCTAssertEqual(HtmlChromeOpener.busyNote(holders: holders),
                           "ВНИМАНИЕ: порт 47615 занят чужим процессом (своего слушателя нет — другой пользователь)")
        }
    }
}
