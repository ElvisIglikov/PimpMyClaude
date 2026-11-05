import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF297 (батч B): окно «Токены» — пустой день подписан, у срезанного списка признак «ниже ещё» (#11168); образец
/// нового чата в настройках словами (#11169); образцы значка с настоящими числами и читаемый ряд проектов (#11170).
/// #11171 (AXPress у заголовка раскрытого блока) деревом доступности под XCTest не проверить (см. `PanelButtonsTests`).
/// Снимки пишутся, только когда задан `PMP_SNAPSHOT_DIR`; имя снимка — с приставкой `PMP_SNAPSHOT_TAG` (before/after).
final class PanelWF297bTests: XCTestCase {
    private var tag: String { ProcessInfo.processInfo.environment["PMP_SNAPSHOT_TAG"] ?? "after" }

    private func write<V: View>(_ root: V, size: NSSize, name: String) throws {
        let view = NSHostingView(rootView: root)
        view.frame = NSRect(origin: .zero, size: size)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.backgroundColor = .black
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("B-\(name)-\(tag).png"))
    }

    private func panel(now: Date) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.appVersion = "1.10.90"
        model.patch = .installed(version: "2.26454.2", loader: 9)
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 10, resetsAt: now.addingTimeInterval(4 * 3600)),
                                    weekly: .init(used: 95, resetsAt: now.addingTimeInterval(9 * 3600)),
                                    fable: .init(used: 0, resetsAt: now.addingTimeInterval(9 * 3600)),
                                    source: "api")
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.layout = .standard
        return model
    }

    private func render(_ model: PanelModel, height: CGFloat, name: String) throws {
        try write(PanelRoot(model: model),
                  size: NSSize(width: PimpPanelController.width + 2 * PimpPanelController.margin, height: height), name: name)
    }

    // MARK: #11168 — окно «Токены»

    /// Неделя как на S1-15: понедельника 26 в копилке нет совсем, проектов восемь.
    private func tokens(now: Date) -> TokensModel {
        let model = TokensModel()
        var days: [String: [String: Int]] = [:]
        let calendar = Calendar.current
        let projects = ["VkusnoffKz", "Rick", "PimpMyClaude", "Risovalka", "TrelvisCom", "Marketolog", "SkilZZZ", "Dictator"]
        let values = [2600, 963, 862, 542, 330, 307, 210, 120]
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        for back in 0..<7 where back != 3 {
            let day = format.string(from: calendar.date(byAdding: .day, value: -back, to: now)!)
            var row: [String: Int] = [:]
            for (index, project) in projects.enumerated() { row[project] = values[index] * 1_000_000 / (back + 1) }
            days[day] = row
        }
        model.data = TokensDaily(days: days, scanned: now)
        model.now = now
        model.loaded = true
        model.period = .week
        return model
    }

    func testZeroDayHasLabel() {
        XCTAssertEqual(TokensView.zeroLabel, "0")
    }

    func testTokensMoreBelow() {
        XCTAssertTrue(TokensMoreBelow.shown(content: 900, visible: 600, scrolled: 0))
        XCTAssertFalse(TokensMoreBelow.shown(content: 900, visible: 600, scrolled: 300), "долистали до конца")
        XCTAssertFalse(TokensMoreBelow.shown(content: 500, visible: 600, scrolled: 0), "всё влезло")
    }

    func testSnapshotTokensWeek() throws {
        let saved = UserDefaults.standard.string(forKey: TokensModel.periodKey)
        defer { UserDefaults.standard.set(saved, forKey: TokensModel.periodKey) }
        try write(TokensView(model: tokens(now: Date())), size: TokensWindowController.defaultSize, name: "11168")
    }

    // MARK: #11169 — образец нового чата

    func testChatSampleInWords() {
        XCTAssertEqual(ChatSample.chips(bypass: true), ["Bypass", "Opus 5.5", "high"])
        XCTAssertEqual(ChatSample.chips(bypass: false), ["Ask permissions", "Opus 5.5", "high"])
    }

    func testSnapshotSettingsChats() throws {
        let model = panel(now: Date())
        model.sheet = .settings
        model.settingsGroup = .chats
        model.bypassNew = true
        try render(model, height: 720, name: "11169")
    }

    // MARK: #11170 — образцы значка

    func testIconSampleUsesRealLimits() {
        let now = Date()
        let model = panel(now: now)
        let look = IconSample.look(.week, limits: model.limits, now: now)
        XCTAssertEqual(look.number, 95)
        XCTAssertEqual(IconSample.look(.fiveHour, limits: model.limits, now: now).number, 10)
        // Лимитов ещё нет — прежний образец.
        XCTAssertEqual(IconSample.look(.week, limits: nil, now: now).number, 37)
    }

    /// Сетка в блоке 296 pt: широкие со сводкой проектов не уже своей картинки (плитка — минус 8 pt полей).
    func testProjectTilesNotShrunk() {
        let column = (296 - CGFloat(IconGroup.columns - 1) * IconGroup.spacing) / CGFloat(IconGroup.columns)
        let cells = IconGroup.rows.flatMap { $0 }
        XCTAssertEqual(cells.map { $0.variant }.sorted { $0.rawValue < $1.rawValue },
                       StatusIcon.Variant.allCases.sorted { $0.rawValue < $1.rawValue }, "каждый вариант ровно раз")
        for row in IconGroup.rows { XCTAssertLessThanOrEqual(row.reduce(0) { $0 + $1.span }, IconGroup.columns) }
        for cell in cells where cell.variant.showsProjects {
            let image = IconSample.image(cell.variant, accent: .white, projects: "⏳ 3 · ✋ 5 · WF 127/133")
            let width = column * CGFloat(cell.span) + IconGroup.spacing * CGFloat(cell.span - 1) - 8
            XCTAssertLessThanOrEqual(image.size.width, width, "\(cell.variant): картинка шире плитки — ужмётся")
        }
    }

    func testSnapshotAccentIcons() throws {
        let model = panel(now: Date())
        model.accentOpen = true
        model.projects = nil
        try render(model, height: 420, name: "11170")
    }
}
