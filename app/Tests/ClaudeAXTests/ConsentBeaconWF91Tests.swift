import XCTest
import CoreGraphics
@testable import ClaudeAX

/// Окна доступа macOS не пропустить (WF91, #7691): распознавание окна запроса по записи
/// CGWindowList и геометрия рамки и плашки.
final class ConsentBeaconWF91Tests: XCTestCase {
    private func record(pid: Int32 = 500, number: Int = 77, owner: String = "UserNotificationCenter",
                        layer: Int = 0, alpha: Double = 1, onscreen: Bool? = true,
                        bounds: CGRect = CGRect(x: 1600, y: 300, width: 260, height: 220)) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowNumber as String: NSNumber(value: number),
            kCGWindowOwnerName as String: owner,
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: bounds.dictionaryRepresentation as NSDictionary,
        ]
        if let onscreen = onscreen { info[kCGWindowIsOnscreen as String] = NSNumber(value: onscreen) }
        return info
    }

    private func parse(_ info: [String: Any], process: String? = nil, extra: String? = nil) -> ConsentWindow? {
        ConsentWindow.parse(info, ownPID: 1, extra: extra) { _ in process }
    }

    // MARK: - распознавание

    func testRecognizesSystemPromptsByExecutableNotLocalizedOwner() {
        // Имя владельца локализовано и обрезано — узнаём по исполняемому файлу.
        let window = parse(record(owner: "Универсальный до", layer: 8), process: "universalAccessAuthWarn")
        XCTAssertEqual(window?.process, "universalAccessAuthWarn")
        XCTAssertEqual(window?.layer, 8)
        XCTAssertEqual(window?.number, 77)
        XCTAssertEqual(window?.bounds, CGRect(x: 1600, y: 300, width: 260, height: 220))
        for name in ["UserNotificationCenter", "SecurityAgent", "coreautha", "tccd"] {
            XCTAssertNotNil(parse(record(owner: "что-то"), process: name), name)
        }
    }

    func testFallsBackToOwnerNameWhenPathUnknown() {
        XCTAssertEqual(parse(record(owner: "SecurityAgent"), process: nil)?.process, "SecurityAgent")
    }

    func testIgnoresOrdinaryAndOwnAndInvisibleWindows() {
        XCTAssertNil(parse(record(owner: "Claude"), process: "Claude"))
        XCTAssertNil(ConsentWindow.parse(record(pid: 1), ownPID: 1) { _ in "UserNotificationCenter" })
        XCTAssertNil(parse(record(alpha: 0), process: "UserNotificationCenter"))
        XCTAssertNil(parse(record(onscreen: false), process: "UserNotificationCenter"))
        XCTAssertNil(parse(record(layer: -2147483624), process: "UserNotificationCenter"))
        // Служебное окно 0×0 (так живёт AccessibilityUIServer) — не запрос.
        XCTAssertNil(parse(record(bounds: CGRect(x: 0, y: 382, width: 0, height: 0)), process: "SecurityAgent"))
        XCTAssertNil(parse(record(bounds: CGRect(x: 0, y: 0, width: 30, height: 300)), process: "SecurityAgent"))
        var broken = record()
        broken[kCGWindowBounds as String] = nil
        XCTAssertNil(parse(broken, process: "UserNotificationCenter"))
    }

    func testTestOwnerAddsLookalike() {
        XCTAssertNil(parse(record(owner: "osascript"), process: "osascript"))
        XCTAssertEqual(parse(record(owner: "osascript"), process: "osascript", extra: " OSAScript ")?.process, "osascript")
        XCTAssertNil(parse(record(owner: "osascript"), process: "osascript", extra: "  "))
    }

    // MARK: - геометрия

    func testCoordinatesAndRing() {
        // Главный монитор 900 pt в высоту: окно 100 pt от верха → низ окна 900 − 100 − 200 = 600.
        let cg = CGRect(x: 50, y: 100, width: 300, height: 200)
        let cocoa = ConsentBeaconGeometry.cocoaRect(fromCG: cg, primaryHeight: 900)
        XCTAssertEqual(cocoa, NSRect(x: 50, y: 600, width: 300, height: 200))
        // Монитор выше главного: y в CG отрицательный.
        XCTAssertEqual(ConsentBeaconGeometry.cocoaRect(fromCG: CGRect(x: 0, y: -500, width: 100, height: 100),
                                                       primaryHeight: 900).minY, 1300)
        // Рамка — четыре полосы, ни одна не заходит на окно запроса, вместе замыкают его кругом.
        let strips = ConsentBeaconGeometry.ringStrips(around: cocoa)
        let pad = ConsentBeaconGeometry.gap + ConsentBeaconGeometry.thickness
        XCTAssertEqual(strips.count, 4)
        for strip in strips { XCTAssertFalse(strip.intersects(cocoa), "\(strip)") }
        let union = strips.dropFirst().reduce(strips[0]) { $0.union($1) }
        XCTAssertEqual(union, cocoa.insetBy(dx: -pad, dy: -pad))
        for point in [NSPoint(x: cocoa.midX, y: cocoa.maxY + pad - 1), NSPoint(x: cocoa.midX, y: cocoa.minY - pad + 1),
                      NSPoint(x: cocoa.minX - pad + 1, y: cocoa.midY), NSPoint(x: cocoa.maxX + pad - 1, y: cocoa.midY),
                      NSPoint(x: cocoa.minX - pad + 1, y: cocoa.maxY + pad - 1)] {
            XCTAssertTrue(strips.contains { $0.contains(point) }, "\(point)")
        }
        // Курсор — в центр окна, а не на кнопку.
        XCTAssertEqual(ConsentBeaconGeometry.warpPoint(forCG: cg), CGPoint(x: 200, y: 200))
    }

    func testPlaqueSitsBelowRightAndFlipsAtEdges() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 300, height: 50)
        let offset = ConsentBeaconGeometry.offset
        let plain = ConsentBeaconGeometry.plaqueFrame(current: nil, cursor: NSPoint(x: 400, y: 400), size: size, visible: visible)!
        XCTAssertEqual(plain.origin, NSPoint(x: 400 + offset, y: 400 - offset - 50))
        let right = ConsentBeaconGeometry.plaqueFrame(current: nil, cursor: NSPoint(x: 900, y: 400), size: size, visible: visible)!
        XCTAssertEqual(right.maxX, 900 - offset)
        let bottom = ConsentBeaconGeometry.plaqueFrame(current: nil, cursor: NSPoint(x: 400, y: 30), size: size, visible: visible)!
        XCTAssertEqual(bottom.minY, 30 + offset)
        // Плашка никогда не под курсором и целиком на мониторе.
        for cursor in [NSPoint(x: 0, y: 0), NSPoint(x: 999, y: 799), NSPoint(x: 999, y: 0), NSPoint(x: 0, y: 799)] {
            let frame = ConsentBeaconGeometry.plaqueFrame(current: nil, cursor: cursor, size: size, visible: visible)!
            XCTAssertTrue(visible.contains(frame), "\(cursor)")
            XCTAssertFalse(frame.contains(cursor), "\(cursor)")
        }
    }

    func testPlaqueStaysOnLeashSoItCanBeClicked() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 300, height: 50)
        let placed = ConsentBeaconGeometry.plaqueFrame(current: nil, cursor: NSPoint(x: 400, y: 400), size: size, visible: visible)!
        // Идём к плашке — стоит на месте.
        let toward = NSPoint(x: placed.midX, y: placed.maxY + 10)
        XCTAssertEqual(ConsentBeaconGeometry.plaqueFrame(current: placed, cursor: toward, size: size, visible: visible), placed)
        // Ушли дальше привязи — поехала за курсором.
        let far = NSPoint(x: 100, y: 700)
        let moved = ConsentBeaconGeometry.plaqueFrame(current: placed, cursor: far, size: size, visible: visible)!
        XCTAssertNotEqual(moved, placed)
        let offset = ConsentBeaconGeometry.offset
        XCTAssertEqual(moved.origin, NSPoint(x: far.x + offset, y: far.y - offset - size.height))
        // Курсор на другом мониторе: старое место не в его видимой области — переезд.
        let other = NSRect(x: 1000, y: 0, width: 1000, height: 800)
        let jumped = ConsentBeaconGeometry.plaqueFrame(current: placed, cursor: NSPoint(x: 1400, y: 400), size: size, visible: other)!
        XCTAssertTrue(other.contains(jumped))
    }

    func testPlaqueNeverLiesOnPromptWindow() {
        let visible = NSRect(x: 0, y: 0, width: 1400, height: 900)
        let size = NSSize(width: 300, height: 50)
        let prompt = NSRect(x: 500, y: 300, width: 260, height: 220)
        let margin = ConsentBeaconGeometry.avoidMargin
        // Курсор в 30 pt слева от окна: справа-снизу плашка легла бы на окно — ушла влево.
        let cursor = NSPoint(x: prompt.minX - 30, y: prompt.midY)
        let left = ConsentBeaconGeometry.plaqueFrame(current: nil, cursor: cursor, size: size, visible: visible, avoid: [prompt])
        XCTAssertNotNil(left)
        XCTAssertFalse(left!.intersects(prompt.insetBy(dx: -margin, dy: -margin)))
        XCTAssertFalse(left!.contains(cursor))
        // Старое место на привязи задевает окно — не держим.
        let onPrompt = NSRect(x: prompt.minX - 10, y: prompt.midY - 60, width: size.width, height: size.height)
        let moved = ConsentBeaconGeometry.plaqueFrame(current: onPrompt, cursor: cursor, size: size, visible: visible, avoid: [prompt])
        XCTAssertNotEqual(moved, onPrompt)
        XCTAssertFalse(moved!.intersects(prompt.insetBy(dx: -margin, dy: -margin)))
        // Два окна запроса и курсор между ними — ни одного не задевает.
        let second = NSRect(x: 100, y: 300, width: 260, height: 220)
        let between = NSPoint(x: 430, y: 400)
        let both = ConsentBeaconGeometry.plaqueFrame(current: nil, cursor: between, size: size, visible: visible, avoid: [prompt, second])
        XCTAssertNotNil(both)
        for zone in [prompt, second] { XCTAssertFalse(both!.intersects(zone.insetBy(dx: -margin, dy: -margin))) }
        // Места нет нигде — плашку не показываем.
        let tight = NSRect(x: 0, y: 0, width: 400, height: 300)
        let wall = NSRect(x: 60, y: 40, width: 300, height: 220)
        XCTAssertNil(ConsentBeaconGeometry.plaqueFrame(current: nil, cursor: NSPoint(x: 20, y: 150), size: size,
                                                       visible: tight, avoid: [wall]))
    }

    func testNearestPromptToCursor() {
        let targets = [NSRect(x: 2000, y: 0, width: 200, height: 200), NSRect(x: 100, y: 100, width: 200, height: 200)]
        XCTAssertEqual(ConsentBeaconGeometry.nearest(to: NSPoint(x: 0, y: 0), among: targets), 1)
        XCTAssertEqual(ConsentBeaconGeometry.nearest(to: NSPoint(x: 1900, y: 100), among: targets), 0)
        XCTAssertNil(ConsentBeaconGeometry.nearest(to: .zero, among: []))
    }

    func testDistance() {
        let rect = NSRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(ConsentBeaconGeometry.distance(from: NSPoint(x: 5, y: 5), to: rect), 0)
        XCTAssertEqual(ConsentBeaconGeometry.distance(from: NSPoint(x: 13, y: 14), to: rect), 5)
    }

    func testPlaqueHiddenWhenCursorAlreadyOnPrompt() {
        let target = NSRect(x: 100, y: 100, width: 200, height: 150)
        XCTAssertFalse(ConsentBeaconGeometry.showsPlaque(cursor: NSPoint(x: 200, y: 170), targets: [target]))
        XCTAssertFalse(ConsentBeaconGeometry.showsPlaque(cursor: NSPoint(x: 90, y: 90), targets: [target]))
        XCTAssertTrue(ConsentBeaconGeometry.showsPlaque(cursor: NSPoint(x: 600, y: 600), targets: [target]))
        // У второго окна запроса — тоже прячется.
        let second = NSRect(x: 1000, y: 100, width: 200, height: 150)
        XCTAssertFalse(ConsentBeaconGeometry.showsPlaque(cursor: NSPoint(x: 1100, y: 170), targets: [target, second]))
        XCTAssertTrue(ConsentBeaconGeometry.showsPlaque(cursor: NSPoint(x: 600, y: 600), targets: [target, second]))
    }

    func testArrowPointsToPrompt() {
        let from = NSPoint(x: 0, y: 0)
        let cases: [(NSPoint, String)] = [
            (NSPoint(x: 100, y: 0), "→"), (NSPoint(x: 100, y: 100), "↗"), (NSPoint(x: 0, y: 100), "↑"),
            (NSPoint(x: -100, y: 100), "↖"), (NSPoint(x: -100, y: 0), "←"), (NSPoint(x: -100, y: -100), "↙"),
            (NSPoint(x: 0, y: -100), "↓"), (NSPoint(x: 100, y: -100), "↘"), (NSPoint(x: 100, y: 30), "→"),
            (NSPoint(x: 100, y: -30), "→"), (NSPoint(x: 0, y: 0), "↗"),
        ]
        for (to, arrow) in cases { XCTAssertEqual(ConsentBeaconGeometry.arrow(from: from, to: to), arrow, "\(to)") }
    }

    func testScreenIndexAndLines() {
        let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: 1440, y: 0, width: 1920, height: 1080)]
        XCTAssertEqual(ConsentBeaconGeometry.screenIndex(of: NSPoint(x: 100, y: 100), in: screens), 0)
        XCTAssertEqual(ConsentBeaconGeometry.screenIndex(of: NSPoint(x: 2000, y: 500), in: screens), 1)
        XCTAssertNil(ConsentBeaconGeometry.screenIndex(of: NSPoint(x: -50, y: 100), in: screens))
        XCTAssertEqual(ConsentBeaconGeometry.lines(arrow: "→", otherScreen: true).first,
                       "macOS ждёт твоего ответа → на соседнем мониторе")
        XCTAssertEqual(ConsentBeaconGeometry.lines(arrow: "↗", otherScreen: false).first, "macOS ждёт твоего ответа ↗")
    }

    func testSwitchDefaultsToOn() {
        let defaults = UserDefaults(suiteName: "ConsentBeaconWF91Tests")!
        defaults.removePersistentDomain(forName: "ConsentBeaconWF91Tests")
        let beacon = ConsentBeacon(defaults: defaults)
        XCTAssertTrue(beacon.isEnabled)
        XCTAssertEqual(beacon.status, "0/on/0")
        defaults.set(false, forKey: ConsentBeacon.enabledKey)
        XCTAssertFalse(beacon.isEnabled)
        defaults.removePersistentDomain(forName: "ConsentBeaconWF91Tests")
    }
}
