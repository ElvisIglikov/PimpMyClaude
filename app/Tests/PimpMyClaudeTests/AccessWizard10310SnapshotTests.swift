import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #10310 (+ #10306): место плашки мастера у окна Системных настроек и кадры карточки-мастера в панели — шаг 1 из 3,
/// шаг 0 «Нужен полный доступ», «Готово ✓», плашка с плитками как у Gemini. Кадры пишутся, только когда задан
/// `PMP_SNAPSHOT_DIR`; живых окон тест не открывает и у macOS ничего не спрашивает.
final class AccessWizard10310SnapshotTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let plaque = NSSize(width: 330, height: 180)

    // MARK: место плашки

    func testInsidePlacementIsBottomRightOfSettings() {
        let settings = NSRect(x: 300, y: 120, width: 840, height: 680)
        let (frame, target) = PermissionHintController.frame(.inside, settings: settings, size: plaque, visible: visible)
        XCTAssertEqual(frame.maxX, settings.maxX - 16, "справа, как у Gemini")
        XCTAssertEqual(frame.minY, settings.minY + 16, "снизу (Cocoa: y вверх)")
        XCTAssertTrue(settings.contains(frame))
        XCTAssertNil(target, "внутри окна — без стрелки и без «дыхания»: плитку ловят мышью")
    }

    func testInsideFallsBackBesideWhenTooSmall() {
        let small = NSRect(x: 300, y: 300, width: 300, height: 150)
        let (frame, target) = PermissionHintController.frame(.inside, settings: small, size: plaque, visible: visible)
        XCTAssertEqual(frame.minX, small.maxX + 12, "не влезает — сбоку, как плашка «Управления приложениями»")
        XCTAssertEqual(target, small)
        let (corner, none) = PermissionHintController.frame(.inside, settings: nil, size: plaque, visible: visible)
        XCTAssertEqual(corner.maxX, visible.maxX - 16, "окна нет — правый верхний угол")
        XCTAssertEqual(corner.maxY, visible.maxY - 16)
        XCTAssertNil(none)
    }

    func testBesidePlacementUnchanged() {
        let settings = NSRect(x: 200, y: 200, width: 700, height: 600)
        let (frame, target) = PermissionHintController.frame(.beside, settings: settings, size: plaque, visible: visible)
        XCTAssertEqual(frame.minX, settings.maxX + 12)
        XCTAssertEqual(frame.maxY, settings.maxY)
        XCTAssertEqual(target, settings)
    }

    func testAppManagementTextWordForWord() {
        let content = PermissionHintContent.appManagement
        XCTAssertEqual(content.title, "Включи PimpMyClaude")
        XCTAssertEqual(content.steps.count, 3)
        XCTAssertEqual(content.steps.first, "В настройках «Управление приложениями» щёлкни переключатель у PimpMyClaude.")
        XCTAssertEqual(content.note, "Патч продолжится сам — нажимать «Пропатчить» ещё раз не надо.")
        XCTAssertEqual(content.link, "Включил, а патч стоит — перезапустить PMP")
        XCTAssertFalse(content.gemini)
        XCTAssertTrue(content.tiles.isEmpty)
    }

    // MARK: кадры

    private func model(_ access: ClaudeAccess.State, wizard: AccessWizard.Snapshot) -> PanelModel {
        let now = Date()
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.30"
        model.maxCardHeight = 1400
        model.patch = .installed(version: "2.31226.0", loader: 8)
        model.loader = 8
        model.layout = .standard
        model.access = access
        model.wizard = wizard
        return model
    }

    private func snapshot(_ facts: AccessWizard.Facts, phase: AccessWizard.Phase = .steps) -> AccessWizard.Snapshot {
        var snapshot = AccessWizard.Snapshot()
        snapshot.steps = AccessWizard.steps(AccessWizard.need(facts), facts, signFailed: false)
        snapshot.index = AccessWizard.index(after: AccessWizard.Snapshot(), steps: snapshot.steps)
        snapshot.phase = phase
        snapshot.grants = facts.grants ?? [:]
        snapshot.adhoc = facts.adhoc
        snapshot.pmpApp = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        snapshot.claudeApp = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        return snapshot
    }

    private func render(_ model: PanelModel, height: CGFloat, name: String) throws {
        let view = NSHostingView(rootView: PanelRoot(model: model))
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: height)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.backgroundColor = .black
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        try write(view, name)
    }

    private func write(_ view: NSView, _ name: String) throws {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let dir = dir else { return }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    func testSnapshotWizardStepOneOfThree() throws {
        UserDefaults.standard.removeObject(forKey: AccessWizardController.laterKey)
        let facts = AccessWizard.Facts(grants: [.accessibility: .stale, .screen: .stale, .fullDisk: .granted],
                                       pmpTrusted: false, adhoc: true, patched: true)
        let wizard = snapshot(facts)
        XCTAssertEqual(wizard.steps.count, 3, "подпись, Универсальный доступ, Запись экрана")
        try render(model(AccessWizard.effective(grants: facts.grants, pending: []), wizard: wizard), height: 760,
                   name: "10310-1-shag-1-iz-3.png")
        var second = wizard
        second.index = 1
        try render(model(.missing([.accessibility, .screen]), wizard: second), height: 760, name: "10310-2-plitki.png")
    }

    func testSnapshotStepZeroFullDisk() throws {
        UserDefaults.standard.removeObject(forKey: AccessWizardController.dismissedKey)
        let facts = AccessWizard.Facts(grants: nil, pmpTrusted: true, adhoc: true, patched: true)
        let wizard = snapshot(facts)
        XCTAssertEqual(AccessWizard.cardTitle(wizard), "Нужен полный доступ")
        try render(model(.unknown, wizard: wizard), height: 640, name: "10310-3-shag-0.png")
    }

    func testSnapshotDone() throws {
        let facts = AccessWizard.Facts(grants: [.accessibility: .granted, .screen: .granted, .fullDisk: .granted],
                                       pmpTrusted: true, adhoc: false, patched: true)
        var wizard = AccessWizard.Snapshot()
        wizard.steps = AccessWizard.steps(AccessWizard.Need(claude: [.accessibility, .screen]), facts, signFailed: false)
        wizard.phase = .done
        XCTAssertTrue(AccessWizard.finished(wizard.steps))
        try render(model(.ok, wizard: wizard), height: 560, name: "10310-4-gotovo.png")
    }

    func testSnapshotPlaqueWithTiles() throws {
        let tiles = [PermissionHintContent.Tile(url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                                title: "PMP"),
                     PermissionHintContent.Tile(url: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                                title: "Claude")]
        let content = PermissionHintContent(title: "Перетащи PMP и Claude в список", gemini: true,
                                            note: "Не берёт — нажми «+» под списком и выбери в «Программах».", tiles: tiles)
        let view = NSHostingView(rootView: PermissionHintView(content: content, openSettings: {}, relaunch: {}, cancel: {}))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(view.fittingSize.width, PermissionHintView.width + 2 * HintPointer.inset)
        try write(view, "10310-5-plashka.png")
    }
}
