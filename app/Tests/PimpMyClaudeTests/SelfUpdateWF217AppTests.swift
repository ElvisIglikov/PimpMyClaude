import Patcher
import XCTest
@testable import PimpMyClaude

/// WF217 (#9410, К-SU): когда автообновление проверяет и когда ставит. Временные папки, подставной источник
/// и подставные проверки подписи; настоящие приложения, сеть и настройки Пимпа не трогаются.
final class SelfUpdateWF217AppTests: XCTestCase {
    private var scratch: URL!
    private var apps: URL!
    private var defaults: UserDefaults!
    private var suite = ""
    private var asked = 0
    private var moment = SelfUpdateMoment()
    private var relaunched: [URL] = []
    private var quits = 0
    private var alone = true
    private let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pimp-self-update-app-\(UUID().uuidString)", isDirectory: true)
        apps = scratch.appendingPathComponent("Applications", isDirectory: true)
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        suite = "pimp-self-update-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        if let scratch = scratch { try? fm.removeItem(at: scratch) }
    }

    @discardableResult
    private func makeApp(in folder: URL, _ product: SelfUpdateProduct, version: String) throws -> URL {
        let app = folder.appendingPathComponent(product.appName, isDirectory: true)
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": product.bundleID, "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    private func zip(_ product: SelfUpdateProduct, version: String) throws -> URL {
        let source = scratch.appendingPathComponent("src-\(UUID().uuidString)", isDirectory: true)
        try makeApp(in: source, product, version: version)
        let archive = scratch.appendingPathComponent("\(product.name)-\(UUID().uuidString).zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", source.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)
        return archive
    }

    /// Источник отдаёт выпуски `versions` (продукт → версия); проверки подписи проходят.
    private func makeUpdater(_ versions: [String: String]) throws -> SelfUpdater {
        var archives: [String: URL] = [:]
        for product in [SelfUpdateProduct.pimp, .viewer] {
            if let version = versions[product.key] { archives[product.key] = try zip(product, version: version) }
        }
        var updater = SelfUpdater(directory: scratch.appendingPathComponent("Support/self-update", isDirectory: true))
        updater.allowedParents = [apps]
        updater.transport = SelfUpdateTransport(
            latest: { product in
                self.asked += 1
                guard let version = versions[product.key], let archive = archives[product.key] else { return .failure(.missing("нет выпуска")) }
                let size = (try? self.fm.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.int64Value ?? 0
                let asset: [String: Any] = ["name": product.assetName(version), "state": "uploaded", "size": size,
                                            "browser_download_url": product.assetURL(tag: "v" + version, version: version).absoluteString]
                let release: [String: Any] = ["tag_name": "v" + version, "draft": false, "prerelease": false, "assets": [asset]]
                return .success(try! JSONSerialization.data(withJSONObject: release))
            },
            download: { _, product, file in
                guard let archive = archives[product.key], (try? self.fm.copyItem(at: archive, to: file)) != nil else {
                    return .failure(.offline("нет архива"))
                }
                return .success(())
            })
        updater.checks = SelfUpdateChecks(signature: { _, _ in nil }, gatekeeper: { _ in nil })
        return updater
    }

    private var pimpApp: URL { apps.appendingPathComponent("PimpMyClaude.app", isDirectory: true) }
    private var viewerApp: URL { apps.appendingPathComponent("PimpViewer.app", isDirectory: true) }
    private func version(_ product: SelfUpdateProduct) -> String? {
        SelfUpdater.installedVersion(product == .viewer ? viewerApp : pimpApp, bundleID: product.bundleID)
    }

    private func makeDriver(_ updater: SelfUpdater, viewer: Bool = false) -> SelfUpdateDriver {
        let viewerApp = self.viewerApp
        let driver = SelfUpdateDriver(updater: updater, defaults: defaults, pimpApp: pimpApp, viewerApp: { viewer ? viewerApp : nil })
        driver.moment = { self.moment }
        driver.relaunch = { self.relaunched.append($0) }
        driver.quit = { self.quits += 1 }
        driver.alone = { self.alone } // на Маке разработчика настоящий Пимп запущен — тест о нём не знает
        return driver
    }

    /// Крутить главную очередь, пока условие не сбудется или не выйдет срок (своя очередь водителя отвечает на главную).
    private func settle(until done: () -> Bool, seconds: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    // MARK: - выключатель

    func testSwitchIsOnByDefaultAndOffMeansNoNetworkAndNoInstall() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        let driver = makeDriver(try makeUpdater(["pimp": "1.10.20"]))
        XCTAssertTrue(driver.enabled, "по умолчанию включено")
        XCTAssertTrue(driver.look().on)

        driver.setEnabled(false)
        XCTAssertFalse(driver.enabled)
        XCTAssertEqual(defaults.object(forKey: SelfUpdateDriver.enabledKey) as? Bool, false)
        XCTAssertFalse(driver.look().on)
        driver.started()
        driver.tick()
        driver.claudeLaunched()
        driver.viewerQuit()
        driver.check(interval: 0)
        settle(until: { false }, seconds: 0.5)
        XCTAssertEqual(asked, 0, "выключено — ничего не проверяется и не скачивается")

        // Включили — проверка идёт сразу, новая версия скачана и ждёт.
        var changes = 0
        driver.onChange = { changes += 1 }
        driver.setEnabled(true)
        settle(until: { changes > 1 })
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(driver.look().line, "Скачано 1.10.20 — встанет при следующем запуске")

        // Выключили со скачанным — оно не ставится ни на запуске Пимпа, ни на запуске Claude.
        driver.setEnabled(false)
        XCTAssertFalse(driver.installAtLaunch())
        driver.claudeLaunched()
        settle(until: { false }, seconds: 0.5)
        XCTAssertEqual(version(.pimp), "1.10.19")
        XCTAssertEqual(relaunched, [])
        XCTAssertEqual(quits, 0)
        XCTAssertEqual(driver.look().line, "Стоит 1.10.19")

        driver.setEnabled(true)
        XCTAssertTrue(driver.installAtLaunch())
        XCTAssertEqual(version(.pimp), "1.10.20")
        XCTAssertEqual(relaunched, [pimpApp])
    }

    // MARK: - запуск Пимпа

    func testReadyUpdateIsInstalledAtPimpLaunchBeforeInterface() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        let updater = try makeUpdater(["pimp": "1.10.20"])
        let driver = makeDriver(updater)
        XCTAssertFalse(driver.installAtLaunch(), "ничего не скачано — запуск как обычно")
        XCTAssertEqual(relaunched, [])
        updater.check(.pimp, app: pimpApp)
        XCTAssertTrue(driver.installAtLaunch(), "подменили себя — вызывающий выходит")
        XCTAssertEqual(version(.pimp), "1.10.20")
        XCTAssertEqual(relaunched, [pimpApp], "помощник откроет новую версию")
        XCTAssertEqual(driver.look().note, "Пимп обновился до 1.10.20")
        XCTAssertFalse(driver.installAtLaunch(), "новая версия на своём запуске второй раз не ставится")
        // Панель показала строку — больше её нет.
        driver.clearNotes()
        settle(until: { driver.look().note == nil })
        XCTAssertNil(driver.look().note)
    }

    func testSecondRunningCopyNeverSwapsTheBundle() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        let updater = try makeUpdater(["pimp": "1.10.20"])
        updater.check(.pimp, app: pimpApp)
        let driver = makeDriver(updater)
        alone = false
        XCTAssertFalse(driver.installAtLaunch(), "запущена ещё одна копия Пимпа — бандл не трогаем")
        driver.claudeLaunched()
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(version(.pimp), "1.10.19")
        XCTAssertEqual(quits, 0)
        alone = true
        XCTAssertTrue(driver.installAtLaunch())
    }

    // MARK: - запуск Claude

    func testClaudeLaunchInstallsOnlyInAQuietMoment() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        let updater = try makeUpdater(["pimp": "1.10.20"])
        updater.check(.pimp, app: pimpApp)
        let driver = makeDriver(updater)
        for busy in [SelfUpdateMoment(panelOpen: true), SelfUpdateMoment(busy: true), SelfUpdateMoment(recording: true)] {
            moment = busy
            driver.claudeLaunched()
            settle(until: { false }, seconds: 0.4)
            XCTAssertEqual(version(.pimp), "1.10.19", "\(busy)")
        }
        XCTAssertEqual(relaunched, [])
        XCTAssertEqual(quits, 0)
        XCTAssertEqual(updater.loadState().products["pimp"]?.ready, "1.10.20", "скачанное ждёт следующего момента")

        moment = SelfUpdateMoment()
        driver.claudeLaunched()
        settle(until: { self.quits > 0 })
        XCTAssertEqual(version(.pimp), "1.10.20")
        XCTAssertEqual(relaunched, [pimpApp])
        XCTAssertEqual(quits, 1, "Пимп выходит, помощник открывает новую версию")
    }

    /// Находка R2 проверки 10.10.2026: Claude запустился, а канал «Пимп» занят или окна ещё возвращаются —
    /// Пимп не выходит посреди этого, но и момент не теряет: встаёт, как только стало тихо.
    func testPimpWaitsForWindowsAfterClaudeLaunchAndThenInstalls() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        let updater = try makeUpdater(["pimp": "1.10.20"])
        updater.check(.pimp, app: pimpApp)
        let driver = makeDriver(updater)
        driver.retryEvery = 0.05
        moment = SelfUpdateMoment(windows: true)
        driver.claudeLaunched()
        settle(until: { false }, seconds: 0.5)
        XCTAssertEqual(version(.pimp), "1.10.19", "окна возвращаются — Пимп на месте")
        XCTAssertEqual(quits, 0)
        XCTAssertEqual(updater.loadState().products["pimp"]?.ready, "1.10.20")

        moment = SelfUpdateMoment() // возврат кончился — второго запуска Claude не ждём
        settle(until: { self.quits > 0 })
        XCTAssertEqual(version(.pimp), "1.10.20")
        XCTAssertEqual(relaunched, [pimpApp])
        XCTAssertEqual(quits, 1)
    }

    func testWaitingForWindowsHasADeadline() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        let updater = try makeUpdater(["pimp": "1.10.20"])
        updater.check(.pimp, app: pimpApp)
        let driver = makeDriver(updater)
        driver.retryEvery = 0.05
        driver.retrySeconds = 0.3
        moment = SelfUpdateMoment(windows: true)
        driver.claudeLaunched()
        settle(until: { false }, seconds: 0.6)
        // Срок вышел: человек уже работает — Пимп себя не перезапускает, скачанное ждёт следующего запуска.
        moment = SelfUpdateMoment()
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(version(.pimp), "1.10.19")
        XCTAssertEqual(quits, 0)
        XCTAssertEqual(updater.loadState().products["pimp"]?.ready, "1.10.20")
    }

    func testViewerIsNotHeldByBusyWindows() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        try makeApp(in: apps, .viewer, version: "1.10.7")
        let updater = try makeUpdater(["viewer": "1.10.8"])
        updater.check(.viewer, app: viewerApp)
        let driver = makeDriver(updater, viewer: true)
        moment = SelfUpdateMoment(windows: true) // Claude закрыт или возвращает окна — Viewer это не касается
        driver.viewerQuit()
        settle(until: { self.version(.viewer) == "1.10.8" })
        XCTAssertEqual(version(.viewer), "1.10.8")
        XCTAssertEqual(quits, 0)
    }

    func testClaudeLaunchUpdatesViewerFirstThenPimpLeaves() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        try makeApp(in: apps, .viewer, version: "1.10.7")
        let updater = try makeUpdater(["pimp": "1.10.20", "viewer": "1.10.8"])
        updater.check(.pimp, app: pimpApp)
        updater.check(.viewer, app: viewerApp)
        let driver = makeDriver(updater, viewer: true)
        driver.claudeLaunched()
        settle(until: { self.quits > 0 })
        XCTAssertEqual(version(.viewer), "1.10.8", "Viewer встал до того, как Пимп пошёл на выход")
        XCTAssertEqual(version(.pimp), "1.10.20")
        XCTAssertEqual(relaunched, [pimpApp])
        XCTAssertEqual(quits, 1)
        // Пимп уже выходит: что придёт следом, подмен не начинает.
        let before = asked
        driver.viewerQuit()
        driver.check(interval: 0)
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(asked, before)
    }

    func testPanelOpenedWhileUnpackingCancelsSwap() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        var updater = try makeUpdater(["pimp": "1.10.20"])
        updater.check(.pimp, app: pimpApp)
        // Момент был тихим, но пока шла проверка подписи перед подменой, человек открыл панель.
        var checked = 0
        updater.checks.signature = { _, _ in
            checked += 1
            self.moment = SelfUpdateMoment(panelOpen: true)
            return nil
        }
        let driver = makeDriver(updater)
        driver.claudeLaunched()
        settle(until: { checked > 0 }, seconds: 5)
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(checked, 1, "проверили — и на этом остановились")
        XCTAssertEqual(version(.pimp), "1.10.19")
        XCTAssertEqual(quits, 0)
        XCTAssertEqual(updater.loadState().products["pimp"]?.ready, "1.10.20")
    }

    // MARK: - мелкие находки R3, R4, R8 проверки 10.10.2026

    /// R3: на запуске Пимпа — главная нитка: зависшую проверку ждём недолго и запускаемся как обычно, а
    /// скачанное остаётся до следующего момента (на сутки не откладывается).
    func testPimpLaunchDoesNotWaitForAStuckCheck() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        var updater = try makeUpdater(["pimp": "1.10.20"])
        updater.check(.pimp, app: pimpApp)
        var stuck = true
        updater.checks.gatekeeper = { _ in
            if stuck { Thread.sleep(forTimeInterval: 3) }
            return nil
        }
        let driver = makeDriver(updater)
        driver.launchPatience = 0.5
        let started = Date()
        XCTAssertFalse(driver.installAtLaunch(), "Gatekeeper завис — запуск идёт как обычно")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
        XCTAssertEqual(version(.pimp), "1.10.19")
        XCTAssertEqual(relaunched, [])
        XCTAssertEqual(updater.loadState().products["pimp"]?.ready, "1.10.20")
        XCTAssertEqual(driver.look().line, "Скачано 1.10.20 — встанет при следующем запуске")
        stuck = false
        driver.launchPatience = 10
        XCTAssertTrue(driver.installAtLaunch(), "следующий запуск: проверка отвечает — встаёт")
        XCTAssertEqual(version(.pimp), "1.10.20")
    }

    /// R4: папка `self-update/` не пишется — попытка в файл не попадает, но пауза держится в памяти водителя.
    func testCheckPauseHoldsInMemoryWhenTheFolderCannotBeWritten() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        var updater = try makeUpdater(["pimp": "1.10.20"])
        let blocked = scratch.appendingPathComponent("blocked") // на месте папки — файл: создать её нельзя
        try Data().write(to: blocked)
        updater.directory = blocked.appendingPathComponent("self-update", isDirectory: true)
        let driver = makeDriver(updater)
        var changes = 0
        driver.onChange = { changes += 1 }
        driver.tick()
        settle(until: { changes > 0 })
        XCTAssertEqual(asked, 1)
        XCTAssertNil(updater.loadState().products["pimp"], "попытка в файл не записалась")
        driver.tick()
        driver.claudeLaunched()
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(asked, 1, "запрос не уходит каждую минуту")
    }

    /// R8: выключили переключатель посреди круга — второй продукт не спрашиваем и архив первого не качаем.
    func testSwitchedOffInTheMiddleStopsTheRound() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        try makeApp(in: apps, .viewer, version: "1.10.7")
        var updater = try makeUpdater(["pimp": "1.10.20", "viewer": "1.10.8"])
        let source = updater.transport
        var downloads = 0
        updater.transport.latest = { product in
            let answer = source.latest(product)
            self.defaults.set(false, forKey: SelfUpdateDriver.enabledKey) // человек выключил, пока шёл запрос
            return answer
        }
        updater.transport.download = { release, product, file in
            downloads += 1
            return source.download(release, product, file)
        }
        let driver = makeDriver(updater, viewer: true)
        var changes = 0
        driver.onChange = { changes += 1 }
        driver.tick()
        settle(until: { changes > 0 })
        XCTAssertEqual(asked, 1, "второй продукт уже не спрашиваем")
        XCTAssertEqual(downloads, 0, "и архив первого не качаем")
        XCTAssertNil(updater.loadState().products["pimp"]?.ready)
        XCTAssertEqual(version(.viewer), "1.10.7")
    }

    // MARK: - Viewer

    func testViewerWaitsUntilItIsClosedAndIsNeverOpened() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        try makeApp(in: apps, .viewer, version: "1.10.7")
        let updater = try makeUpdater(["viewer": "1.10.8"])
        let driver = makeDriver(updater, viewer: true)
        var changes = 0
        driver.onChange = { changes += 1 }
        moment = SelfUpdateMoment(viewerRunning: true)
        driver.started() // проверка на запуске: Viewer скачан, но запущен — ждёт
        settle(until: { changes > 0 })
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(asked, 2, "спросили оба репозитория")
        XCTAssertEqual(version(.viewer), "1.10.7", "запущенный Viewer не подменяем")
        XCTAssertEqual(driver.look().line, "Стоит 1.10.19 · выпусков на GitHub не видно · Viewer 1.10.8 скачан — встанет, когда его закроешь")
        driver.claudeLaunched()
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(version(.viewer), "1.10.7", "и на запуске Claude — тоже, пока открыт")

        moment = SelfUpdateMoment()
        driver.viewerQuit()
        settle(until: { self.version(.viewer) == "1.10.8" })
        XCTAssertEqual(version(.viewer), "1.10.8")
        XCTAssertEqual(relaunched, [], "Viewer не был открыт — и не открываем")
        XCTAssertEqual(quits, 0, "Пимп из-за Viewer не перезапускается")
        XCTAssertEqual(version(.pimp), "1.10.19")
        settle(until: { driver.look().note != nil })
        XCTAssertEqual(driver.look().note, "Viewer обновился до 1.10.8")
    }

    func testClosedViewerIsUpdatedRightAfterDownload() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        try makeApp(in: apps, .viewer, version: "1.10.7")
        let driver = makeDriver(try makeUpdater(["pimp": "1.10.20", "viewer": "1.10.8"]), viewer: true)
        driver.tick()
        settle(until: { self.version(.viewer) == "1.10.8" })
        XCTAssertEqual(version(.viewer), "1.10.8", "Viewer закрыт — встаёт сразу")
        XCTAssertEqual(version(.pimp), "1.10.19", "Пимп ждёт запуска Claude или своего")
        XCTAssertEqual(quits, 0)
        // Фоновая проверка — не чаще раза в 6 часов.
        let before = asked
        driver.tick()
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(asked, before)
    }

    func testNoNetworkMeansNoCheck() throws {
        try makeApp(in: apps, .pimp, version: "1.10.19")
        let driver = makeDriver(try makeUpdater(["pimp": "1.10.20"]))
        driver.networkOK = { false }
        driver.tick()
        driver.claudeLaunched()
        settle(until: { false }, seconds: 0.4)
        XCTAssertEqual(asked, 0, "сети нет или она дорогая — не спрашиваем и не качаем")
        XCTAssertEqual(driver.look().line, "Стоит 1.10.19")
    }
}
