import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF234: кадры карточки обновления Claude в панели у часов и сводки окна «Поддержать автора» — для проверки глазами
/// (правило №1 `INTERFACES.md`). Пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class UpdateCardWF234SnapshotTests: XCTestCase {
    private static let gb: UInt64 = 1_073_741_824
    private static let version = "2.31226.1"

    private var dir: URL? {
        ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("card-wf234-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// Сводка проекта: сколько Workflow готово и сколько идёт.
    private func project(_ name: String, done: Int, running: Int) throws {
        let folder = root.appendingPathComponent(name).appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var lines = ["# " + name]
        for index in 0..<(done + running) {
            let number = String(index + 1).map { "\($0)\u{FE0F}\u{20E3}" }.joined() // «1️⃣2️⃣» — цифры-клавиши
            lines.append(number + " Workflow " + (index < done ? "✅ готово" : "💭 идёт"))
            lines.append("- о чём: задача \(index + 1)")
            lines.append("- шаги \(index < done ? 3 : 1) из 3")
        }
        try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("status.md"), atomically: true,
                                                encoding: .utf8)
    }

    /// Семь Workflow в трёх проектах и четыре терминала — случай владельца 10.10.2026. Число в карточке и число блока
    /// «Идёт Workflow сейчас» считаются из одних и тех же сводок.
    private func busyDay(now: Date) throws -> (work: WorkNow, projects: PanelSnapshot) {
        try project("PimpMyClaude", done: 9, running: 3)
        try project("Rick", done: 4, running: 2)
        try project("VkusnoffKz", done: 2, running: 2)
        try project("Dictator", done: 5, running: 0)
        let terminals: Set<String> = ["PimpMyClaude", "Rick", "VkusnoffKz", "Dictator"]
        let store = ProjectSettingsStore(registryURL: root.appendingPathComponent("no-registry.json"))
        let digest = ProjectsDigest.projects(root: root, now: now, settings: { store.settings(in: $0) }, terminals: terminals)
        var watch = WorkWatch()
        watch.note(ProjectsDigest.work(ProjectsDigest.body(digest, now: now), rootExists: true, now: now,
                                        turning: 4)) // #10460: все 4 терминала дня — в ходе
        var snapshot = PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: now)
        snapshot.terminals = terminals
        return (watch.now(pages: PageSignals(workingChats: 0, lastWorkingAt: now.addingTimeInterval(-900)), at: now), snapshot)
    }

    private func model(_ update: PimpPanelText.UpdateBlock, projects: PanelSnapshot) -> PanelModel {
        let now = Date()
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.22"
        model.patch = .installed(version: "2.30115.4", loader: 8)
        model.loader = 8
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 24, resetsAt: now.addingTimeInterval(4 * 3600 + 300)),
                                    weekly: .init(used: 39, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    fable: .init(used: 0, resetsAt: now.addingTimeInterval(2 * 86400 + 21 * 3600)),
                                    source: "api")
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.memory = (0..<20).map {
            MacMemorySample(at: now.addingTimeInterval(Double($0 - 19) * 60), pressure: 47 + Double($0 % 4),
                            level: .normal, used: 6 * Self.gb + UInt64($0) * Self.gb / 60, total: 8 * Self.gb)
        }
        model.layout = .standard
        model.readySize = "374 МБ"
        model.projects = projects
        model.update = update
        return model
    }

    private func write(_ view: NSView, to url: URL?) throws {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let url = url else { return }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    private func render(_ update: PimpPanelText.UpdateBlock, projects: PanelSnapshot, height: CGFloat,
                        name: String, tune: (PanelModel) -> Void = { _ in }) throws {
        let model = model(update, projects: projects)
        tune(model)
        let view = NSHostingView(rootView: PanelRoot(model: model))
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: height)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.backgroundColor = .black
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        try write(view, to: dir?.appendingPathComponent(name))
    }

    func testSnapshotUpdateCardStates() throws {
        let now = Date()
        let empty = PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: now)
        let day = try busyDay(now: now)
        XCTAssertEqual(day.work.workflows, 7)
        XCTAssertEqual(day.work.projects, 3)
        XCTAssertEqual(day.work.terminals, 4)
        XCTAssertEqual(PanelTiles.runningCount(PanelTiles.groups(day.projects, now: now)), 7,
                       "карточка и блок «Идёт Workflow сейчас» называют одно число")
        XCTAssertNil(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: day.work))
        // #10307: карточка в три строки — «идёт работа: 7 Workflow · 4 терминала» коротко, как отдаёт `updateBlock`.
        let line = try XCTUnwrap(PimpPanelText.workShort(day.work))
        XCTAssertEqual(line, "7 Workflow · 4 терминала")
        try render(.busy(version: Self.version, work: line), projects: day.projects, height: 620, name: "1-idet-rabota.png")
        try render(.ready(version: Self.version, question: nil), projects: empty, height: 520, name: "0-gotovo.png")
        let quiet = WorkNow(chats: 0, workflows: 0, terminals: 0, idleSeconds: 15 * 60)
        let reason = try XCTUnwrap(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: quiet))
        try render(.timely(version: Self.version, reason: reason), projects: empty, height: 520, name: "2-samoe-vremya.png")
        try render(.ready(version: Self.version, question: PimpPanelText.confirmQuestion(work: day.work)),
                   projects: day.projects, height: 620, name: "3-vopros.png")
        try render(.installing(version: Self.version, step: 3), projects: empty, height: 700, name: "4-primer-svyazka.png")
        // Карточка патча: в покое — что прервёт закрытие Claude, пока патч идёт — тот же пример окна связки ключей.
        let lost = StatusIcon.Patch.lost(version: "2.30115.4", reason: PimpPanelText.claudeUpdatedReason)
        try render(.none, projects: day.projects, height: 700, name: "7-patch-rabota.png") { model in
            model.patch = lost
            model.patchWorkNote = PimpPanelText.patchWorkNote(day.work)
        }
        try render(.none, projects: empty, height: 760, name: "8-patch-idet.png") { model in
            model.patch = lost
            model.patchRun = .running("Открываю Claude…")
        }
    }

    /// WF238 (макет 41, кадр 1.1): до нажатия — одна тихая строка про пароль от Мака; пока ставится — пример окна
    /// macOS, нарисованный как настоящее. Кадры — в свою папку: имя теста с «WF238», гонять `--filter WF238`.
    func testSnapshotKeychainLineWF238() throws {
        let empty = PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: Date())
        try render(.ready(version: Self.version, question: nil), projects: empty, height: 520, name: "3-kartochka-stroka.png")
        try render(.installing(version: Self.version, step: 3), projects: empty, height: 800, name: "4-primer-v-paneli.png")
        let quiet = WorkNow(chats: 0, workflows: 0, terminals: 0, idleSeconds: 15 * 60)
        let reason = try XCTUnwrap(PimpPanelText.offerReason(claudeRunning: true, windowCount: 3, work: quiet))
        try render(.timely(version: Self.version, reason: reason), projects: empty, height: 540,
                   name: "5-kartochka-samoe-vremya.png")
        let lost = StatusIcon.Patch.lost(version: "2.30115.4", reason: PimpPanelText.claudeUpdatedReason)
        try render(.none, projects: empty, height: 560, name: "6-kartochka-patch.png") { $0.patch = lost }
    }

    /// #9823: запасной путь «Скачать с claude.ai» и «копировать» — после сбоя, когда писать в «Программы» нельзя, когда
    /// фон не скачал и под загрузкой дольше 3 мин. Гонять `--filter testSnapshotSiteDownload9823`.
    func testSnapshotSiteDownload9823() throws {
        let empty = PanelProjects.snapshot(root: root, recent: [], mainEntry: nil, now: Date())
        try render(.failed("подпись Anthropic не сошлась"), projects: empty, height: 560, name: "9823-1-ne-vyshlo.png")
        try render(.available(version: Self.version, canWrite: false, note: nil), projects: empty, height: 560,
                   name: "9823-2-net-prav.png")
        try render(.available(version: Self.version, canWrite: true, note: "Фоновая загрузка не вышла: нет сети"),
                   projects: empty, height: 560, name: "9823-3-fon-ne-vyshel.png")
        let lane = { (id: String, bytes: Int64, state: ClaudeUpdateMenu.LaneState) in
            ClaudeUpdateMenu.Lane(id: id, title: id, bytes: bytes, total: 380_000_000, bytesPerSec: 150_000, state: state)
        }
        let race = ClaudeUpdateMenu.Race(version: Self.version, lanes: [
            lane("anthropic", 61_000_000, .leading), lane("github", 12_000_000, .dropped("медленно")),
        ])
        try render(.downloading(race), projects: empty, height: 700, name: "9823-4-dolgo.png") { model in
            model.raceStartedAt = model.now.addingTimeInterval(-(PimpPanelText.siteDownloadAfter + 20))
        }
    }

    /// Окно разрешений: абзац про связку ключей кончается ссылкой «Код открыт». Окно только строится — не
    /// показывается и ничего у macOS не спрашивает.
    func testSnapshotSetupWindowKeychainParagraph() throws {
        _ = NSApplication.shared
        let setup = SetupWindow(stateText: { "" }, patchInstalled: { true }, onInstall: {}, onClose: {})
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Настройка PimpMyClaude" })
        window.appearance = NSAppearance(named: .darkAqua)
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        try write(try XCTUnwrap(window.contentView?.superview), to: dir?.appendingPathComponent("6-okno-razresheniy.png"))
        window.close()
        _ = setup
    }

    /// Сводка об авторе со ссылкой на код: окно как в приложении — та же рамка и заголовок.
    func testSnapshotDonateBioWithSource() throws {
        let json = #"{"amounts":[1000,5000,10000],"instagram":"_elvis.kz_","kaspi":"https://example.com/pay"}"#
        let model = DonateModel(config: try XCTUnwrap(DonateConfig.parse(Data(json.utf8))))
        model.reduceMotion = true
        // PMP_SNAPSHOT_DONATE=main — главный вид окна (текст просьбы), иначе сводка об авторе.
        let main = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DONATE"] == "main"
        model.bioOpen = !main
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/ElvisPhoto.jpg")
        let actions = DonateView.Actions(pay: { _ in }, reopen: {}, cancel: {}, copy: { _ in }, open: { _ in })
        let controller = NSHostingController(rootView: DonateView(model: model, actions: actions,
                                                                  photo: NSImage(contentsOf: resources)))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.title = "Поддержать автора"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = DonateColor.windowBackground
        window.setContentSize(controller.view.fittingSize)
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        window.layoutIfNeeded()
        let frame = try XCTUnwrap(window.contentView?.superview)
        try write(frame, to: dir?.appendingPathComponent(main ? "donat-glavnoe.png" : "5-donat-github.png"))
    }
}
