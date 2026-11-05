import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF238: плашка под окном macOS не забирает фокус у окна пароля, а её крестик нажимается и так. Окно плашки
/// только строится — на экран не выходит.
final class KeychainHintWF238AppTests: XCTestCase {
    func testPlaqueNeverTakesFocusButCloseButtonWorks() throws {
        _ = NSApplication.shared
        let panel = KeychainHintPanel()
        XCTAssertFalse(panel.canBecomeKey, "ключевым остаётся окно пароля macOS")
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces), "на всех рабочих столах")
        XCTAssertTrue(panel.host.acceptsFirstMouse(for: nil), "первое нажатие — уже действие")

        var closed = 0
        panel.host.rootView = KeychainHintPlaque(content: .hint(.update), width: 477, close: { closed += 1 },
                                                 spots: panel.host.spots)
        let size = panel.host.fittingSize
        // Вокруг плашки — поле под стрелку к окну macOS (#9841, `hintPointer`): нажимаемые места сдвинуты на него.
        let edge = HintPointer.inset
        XCTAssertEqual(size.width, 477 + 2 * edge)
        panel.setFrame(NSRect(origin: NSPoint(x: 200, y: 200), size: size), display: true)
        panel.host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        // Крестик — в правом верхнем углу, под мышь не меньше 24 pt; ссылка — внизу слева.
        let close = try XCTUnwrap(panel.host.spots.frames[.close])
        XCTAssertGreaterThanOrEqual(min(close.width, close.height), 24)
        XCTAssertEqual(close.maxX, size.width - edge - 16, accuracy: 0.5)
        XCTAssertLessThan(close.midY, size.height / 3)
        let source = try XCTUnwrap(panel.host.spots.frames[.source])
        XCTAssertEqual(source.minX, edge + 16, accuracy: 0.5)
        XCTAssertGreaterThan(source.midY, size.height * 2 / 3)
        XCTAssertEqual(panel.host.spots.spot(at: CGPoint(x: close.midX, y: close.midY)), .close)
        XCTAssertNil(panel.host.spots.spot(at: CGPoint(x: size.width / 2, y: size.height / 2)), "мимо — ничего")
        // Нажатие в окне без фокуса: координаты окна — y вверх.
        let press = { (point: CGPoint) throws in
            panel.host.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: point.x, y: size.height - point.y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)))
        }
        try press(CGPoint(x: size.width / 2, y: size.height / 2))
        XCTAssertEqual(closed, 0)
        try press(CGPoint(x: close.midX, y: close.midY))
        XCTAssertEqual(closed, 1, "крестик нажался в окне, которое не бывает ключевым")
        // Та же плашка поставлена заново (окно macOS сдвинули) — крестик на месте.
        panel.host.rootView = KeychainHintPlaque(content: .hint(.update), width: 477, close: { closed += 1 },
                                                 spots: panel.host.spots)
        panel.host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try press(CGPoint(x: close.midX, y: close.midY))
        XCTAssertEqual(closed, 2)
        // «Готово…» — без крестика: само уходит через несколько секунд.
        panel.host.rootView = KeychainHintPlaque(content: .done(.update), width: 477, spots: panel.host.spots)
        panel.host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(panel.host.spots.frames.isEmpty)
        XCTAssertLessThan(panel.host.fittingSize.height, size.height)
    }
}
