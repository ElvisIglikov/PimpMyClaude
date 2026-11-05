import AppKit
import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// WF269 (#10220, слово Элвиса: «видеть температуру прямо в доке… расход и температура… значок Клауда»): вид
/// «Claude» у часов — искра, проценты недели, градусы цветом нагрева; без плашки, полоски и сводки проектов.
final class StatusIconWF269Tests: XCTestCase {
    private let now = Date()

    private func look(degrees: Int? = 53, heat: StatusIcon.Level = .normal, used: Int = 24) -> StatusIcon.Look {
        let limits = ClaudeLimits(at: now, plan: nil, fiveHour: .init(used: 5, resetsAt: nil),
                                  weekly: .init(used: used, resetsAt: nil), fable: nil, source: "api")
        var base = StatusIcon.look(mode: StatusIcon.Variant.claude.mode, limits: limits, patch: .unknown, phase: .idle, now: now)
        base.degrees = degrees
        base.heat = heat
        return StatusIcon.compose(base, variant: .claude, summary: "⏳1 · ✋4 · WF 51/51", toolTip: "")
    }

    func testClaudeVariantLook() {
        let claude = look()
        XCTAssertTrue(claude.spark)
        XCTAssertFalse(claude.badge)
        XCTAssertFalse(claude.underline)
        XCTAssertNil(claude.text, "без плашек ⏳ ✋ WF")
        XCTAssertTrue(claude.bars.isEmpty)
        XCTAssertEqual(claude.number, 24)
        XCTAssertEqual(claude.degrees, 53)
        XCTAssertGreaterThan(StatusIconArt.width(claude), StatusIconArt.width(look(degrees: nil)), "без градусов — уже")
    }

    func testDefaultAndMigration() throws {
        let suite = testSuiteName()
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        XCTAssertEqual(StatusIcon.variant(store), .claude)
        StatusIcon.saveVariant(.projects, store)
        XCTAssertTrue(StatusIcon.migrateToClaude(store))
        XCTAssertEqual(StatusIcon.variant(store), .claude, "прежний выбор переведён один раз")
        StatusIcon.saveVariant(.week, store)
        XCTAssertFalse(StatusIcon.migrateToClaude(store))
        XCTAssertEqual(StatusIcon.variant(store), .week, "дальше — выбор человека")
    }

    func testDegreesOnlyFromThreshold() {
        // #10289: ниже порога — только проценты; перегрев по словам macOS — градусы всегда.
        let warm = MacTemperatureSample(at: now.addingTimeInterval(-30), chipAverage: 45, chipMax: 50, battery: 30, state: .fair)
        XCTAssertNil(StatusIcon.degrees(warm, enabled: true, now: now, minimum: 70))
        let hot = MacTemperatureSample(at: now.addingTimeInterval(-30), chipAverage: 71.2, chipMax: 80, battery: 30, state: .nominal)
        XCTAssertEqual(StatusIcon.degrees(hot, enabled: true, now: now, minimum: 70)?.degrees, 80, "#10998: самый горячий датчик")
        let throttled = MacTemperatureSample(at: now.addingTimeInterval(-30), chipAverage: 58, chipMax: 66, battery: 30, state: .serious)
        XCTAssertEqual(StatusIcon.degrees(throttled, enabled: true, now: now, minimum: 70)?.degrees, 66)
        let store = UserDefaults(suiteName: testSuiteName())!
        XCTAssertEqual(StatusIcon.tempMin(store), 70, "умолчание — 70")
        store.set(55, forKey: StatusIcon.tempMinKey)
        XCTAssertEqual(StatusIcon.tempMin(store), 70, "мусор — умолчание")
        store.set(0, forKey: StatusIcon.tempMinKey)
        XCTAssertEqual(StatusIcon.tempMin(store), 0)
        XCTAssertEqual(StatusIcon.tempMinName(0), "всегда")
        XCTAssertEqual(StatusIcon.tempMinName(70), "от 70°")
    }

    func testDegreesFromHistory() {
        let fresh = MacTemperatureSample(at: now.addingTimeInterval(-30), chipAverage: 52.6, chipMax: 60, battery: 30, state: .fair)
        let hot = StatusIcon.degrees(fresh, enabled: true, now: now)
        XCTAssertEqual(hot?.degrees, 60)
        XCTAssertEqual(hot?.heat, .low)
        XCTAssertNil(StatusIcon.degrees(fresh, enabled: false, now: now), "монитор выключен — без градусов")
        XCTAssertNil(StatusIcon.degrees(nil, enabled: true, now: now), "нет данных — без градусов")
        let old = MacTemperatureSample(at: now.addingTimeInterval(-3600), chipAverage: 50, chipMax: 50, battery: nil, state: .nominal)
        XCTAssertNil(StatusIcon.degrees(old, enabled: true, now: now), "старая точка — без градусов")
        XCTAssertEqual(StatusIcon.heat(.nominal), .normal)
        XCTAssertEqual(StatusIcon.heat(.serious), .critical)
        XCTAssertEqual(StatusIcon.heat(.critical), .critical)
    }

    /// Картинка для глаз: тёмная и светлая строка меню, три нагрева и без градусов.
    func testSnapshot() throws {
        let looks = [look(), look(heat: .low), look(degrees: 88, heat: .critical, used: 100), look(degrees: nil)]
        let rowH: CGFloat = 30, w: CGFloat = 120
        let size = NSSize(width: w * 2, height: rowH * CGFloat(looks.count))
        let scale: CGFloat = 3
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                                 pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (half, dark) in [(0, true), (1, false)] {
            (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(x: CGFloat(half) * w, y: 0, width: w, height: size.height).fill()
            for (i, item) in looks.enumerated() {
                let image = StatusIconArt.image(item, dark: dark, accent: PMPAccent.violet.nsColor)
                XCTAssertGreaterThan(image.size.width, 30)
                image.draw(in: NSRect(x: CGFloat(half) * w + 12, y: size.height - CGFloat(i + 1) * rowH + 4,
                                      width: image.size.width, height: image.size.height))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon-claude.png"))
    }
}
