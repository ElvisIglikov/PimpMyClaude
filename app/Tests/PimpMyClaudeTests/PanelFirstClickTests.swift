import AppKit
@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// Панель открывается с первого нажатия (#10527, П1; слово Элвиса 22.10.2026: «Нажимаю один раз… он не открывается…
/// со второго раза или с третьего»). Настоящий `PimpPanelController` с окном ЗА ЭКРАНОМ: значок — кнопка в окне на
/// −30000, область экрана подставлена туда же, на экран Элвиса ничего не выходит и приложение не активируется.
final class PanelFirstClickTests: XCTestCase {
    private static let away = NSRect(x: -30000, y: -31000, width: 1440, height: 875)

    private var bar: NSWindow?
    private var panel: PimpPanelController?

    override func tearDown() {
        panel?.close()
        spin(0.35)
        panel?.window?.orderOut(nil)
        bar?.orderOut(nil)
        panel = nil
        bar = nil
        super.tearDown()
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Ждёт события, не часов (#11463): под нагрузкой `asyncAfter` главной нитки опаздывает, и через
    /// `clickSettle + 0,1 с` нажатие ещё не судимо. Потолок — 5 с.
    private func spin(until done: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !done(), Date() < end { spin(0.02) }
    }

    /// Значок в окне за экраном и панель, чей холст считается от области за экраном.
    private func make() -> (PimpPanelController, NSStatusBarButton) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: Self.away.midX, y: Self.away.maxY - 24, width: 40, height: 24),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        window.contentView = button
        let panel = PimpPanelController()
        panel.model.reduceMotion = true
        panel.screenArea = { _ in Self.away }
        bar = window
        self.panel = panel
        return (panel, button)
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func assertAway(_ panel: PimpPanelController, file: StaticString = #filePath, line: UInt = #line) {
        let frame = panel.window?.frame ?? .zero
        XCTAssertTrue(NSScreen.screens.allSatisfy { !$0.frame.intersects(frame) }, "окно панели за экраном: \(frame)",
                      file: file, line: line)
    }

    func testClosedClickOpensAndShows() {
        let (panel, button) = make()
        panel.toggle(from: button, pressedAt: now)
        XCTAssertTrue(panel.isOpen)
        XCTAssertTrue(panel.isShown, "первое нажатие — панель видна")
        assertAway(panel)
        XCTAssertEqual(panel.window?.alphaValue, 1, "открытая панель не прозрачная (П3)")
        spin { panel.clicks.last?.shown != nil }
        XCTAssertEqual(panel.clicks.map { $0.action }, ["open"])
        XCTAssertEqual(panel.clicks.last?.shown, true, "журнал нажатий: открыл и видно")
    }

    func testOpenButHiddenWindowClickShows() {
        let (panel, button) = make()
        panel.toggle(from: button, pressedAt: now)
        spin(0.05)
        // Окно ушло с экрана, а флаг остался (⌥⌘H «Скрыть остальные» в другом приложении).
        panel.window?.orderOut(nil)
        XCTAssertTrue(panel.isOpen)
        XCTAssertFalse(panel.isShown)
        panel.toggle(from: button, pressedAt: now)
        XCTAssertTrue(panel.isShown, "считалась открытой, окна не было — первое же нажатие показывает")
        spin { panel.clicks.last?.shown != nil }
        XCTAssertEqual(panel.clicks.map { $0.action }, ["open", "open"])
        XCTAssertEqual(LiveCheck.appChecks(LiveCheck.AppFacts(clicks: panel.clicks))[3], .pass("clickLog"))
    }

    func testQueuedClickDoesNotClose() {
        let (panel, button) = make()
        let pressed = now
        panel.toggle(from: button, pressedAt: pressed)
        // Второе нажатие отпущено раньше, чем панель показалась (ждало в очереди главной нитки).
        panel.toggle(from: button, pressedAt: pressed - 0.05)
        XCTAssertTrue(panel.isShown, "нажатие из очереди не закрывает только что открытую")
        XCTAssertEqual(panel.clicks.map { $0.action }, ["open", "ignore"])
    }

    func testOpenClickCloses() {
        let (panel, button) = make()
        panel.toggle(from: button, pressedAt: now)
        spin(0.05)
        panel.toggle(from: button, pressedAt: now)
        XCTAssertFalse(panel.isOpen)
        spin { panel.clicks.last?.shown != nil && !(panel.window?.isVisible ?? false) }
        XCTAssertFalse(panel.window?.isVisible ?? false, "закрытая панель ушла с экрана")
        XCTAssertEqual(panel.clicks.map { $0.action }, ["open", "close"])
        XCTAssertEqual(panel.clicks.last?.shown, false)
        XCTAssertEqual(LiveCheck.appChecks(LiveCheck.AppFacts(clicks: panel.clicks))[3], .pass("clickLog"),
                       "закрыл и не видно — не «открыл, а не видно»")
    }
}
