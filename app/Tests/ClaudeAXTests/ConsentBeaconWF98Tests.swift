import XCTest
import AppKit
import Metal
@testable import ClaudeAX

/// Окно доступа macOS «из воды» (WF98 Б5, #7766, макет 12, кадры 2.1 и 3.1): выбор вида, окна-слои
/// вокруг окна запроса, физика окошка, шейдер. Живых окон тест не открывает.
/// `CONSENT_WATER_SNAPSHOT_DIR=<папка>` — ещё и снимки кадров на тестовых данных (PNG).
final class ConsentBeaconWF98Tests: XCTestCase {
    // Два монитора: широкий слева, вертикальный справа вплотную (CG, y вниз).
    private let wide = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let tall = CGRect(x: 1440, y: -180, width: 800, height: 1280)
    private let prompt = CGRect(x: 1000, y: 300, width: 260, height: 290)
    private let dt: CGFloat = 1.0 / 60

    private var visibleWide: CGRect { CGRect(x: 0, y: 25, width: 1440, height: 875) }
    private var visibleTall: CGRect { CGRect(x: 1440, y: -155, width: 800, height: 1255) }

    private func input(_ cursor: CGPoint, targets: [CGRect]? = nil, alive: Bool = true) -> ConsentWaterInput {
        ConsentWaterInput(cursor: cursor, targets: targets ?? [prompt], screens: [wide, tall],
                          visible: [visibleWide, visibleTall], alive: alive)
    }

    @discardableResult
    private func run(_ sim: inout ConsentWaterSim, _ cursor: CGPoint, seconds: CGFloat,
                     targets: [CGRect]? = nil, alive: Bool = true) -> [ConsentWaterFrame] {
        (0..<Int(seconds / dt)).map { _ in sim.step(dt: dt, input(cursor, targets: targets, alive: alive)) }
    }

    private func holes(_ targets: [CGRect]) -> [CGRect] { targets.map { $0.insetBy(dx: -ConsentWaterK.hole, dy: -ConsentWaterK.hole) } }

    // MARK: - стрелка растёт с далью (#8111)

    /// «Чем он дальше… тем больше эта стрелочка… раза два больше… плавно нарастала» (слово Элвиса 29.09).
    func testArrowGrowsWithDistanceSmoothlyUpToTwice() {
        var sim = ConsentWaterSim(seed: 3)
        // Рядом с окном запроса — обычная стрелка.
        let near = run(&sim, CGPoint(x: 950, y: 440), seconds: 2).last!.plaque.reach
        XCTAssertEqual(near, 1, accuracy: 0.02)
        // Курсор ушёл далеко: стрелка растёт не скачком, а к ×2.
        let steps = run(&sim, CGPoint(x: 60, y: 60), seconds: 2).map(\.plaque.reach)
        XCTAssertLessThan(steps[1], 1.2, "выросла скачком")
        XCTAssertEqual(steps.last!, ConsentWaterK.reachMax, accuracy: 0.03)
        XCTAssertLessThanOrEqual(steps.max()!, ConsentWaterK.reachMax + 0.05, "перелетела ×2")
        // Вернулся — снова уменьшается.
        let back = run(&sim, CGPoint(x: 950, y: 440), seconds: 2).last!.plaque.reach
        XCTAssertEqual(back, 1, accuracy: 0.03)
    }

    /// Растёт окошко целиком (#8122): и его рамка, и орбита вокруг курсора; курсор не накрывает.
    func testWholePlaqueGrowsWithDistance() {
        var sim = ConsentWaterSim(seed: 5)
        let near = run(&sim, CGPoint(x: 950, y: 440), seconds: 2).last!.plaque
        let far = run(&sim, CGPoint(x: 90, y: 450), seconds: 3).last!.plaque
        XCTAssertEqual(far.panelRect.width / near.panelRect.width, ConsentWaterK.reachMax, accuracy: 0.05)
        XCTAssertEqual(WaterGeo.distance(CGPoint(x: 90, y: 450), far.panelRect), ConsentWaterK.pad, accuracy: 4,
                       "крупное окошко наехало на курсор или ушло далеко")
    }

    /// Окно окошка шире на запас: стрелка ×2 помещается, клик — только по самому окошку.
    func testPlaquePanelLeavesRoomForBigArrow() {
        let view = ConsentWaterPlaqueView(frame: ConsentWaterPlaqueView.panelBounds)
        XCTAssertEqual(view.frame.width, ConsentWaterK.plW * ConsentWaterK.reachMax + 2 * ConsentWaterK.plMargin)
        XCTAssertGreaterThanOrEqual(ConsentWaterK.plMargin, 20 * ConsentWaterK.reachMax, "стрелка окошка ×2 не влезает слева")
        XCTAssertNil(view.hitTest(NSPoint(x: 5, y: 5)), "запас ловит клик")
        XCTAssertNotNil(view.hitTest(NSPoint(x: view.frame.midX, y: view.frame.midY)))
    }

    // MARK: - вид

    func testStyleSingleMonitorShowsNothing() {
        XCTAssertEqual(ConsentBeaconStyle.choose(hasTargets: false, screenCount: 3, classic: false, waterAvailable: true), .idle)
        XCTAssertEqual(ConsentBeaconStyle.choose(hasTargets: true, screenCount: 1, classic: false, waterAvailable: true), .single)
        XCTAssertEqual(ConsentBeaconStyle.choose(hasTargets: true, screenCount: 1, classic: true, waterAvailable: false), .single)
        XCTAssertEqual(ConsentBeaconStyle.choose(hasTargets: true, screenCount: 2, classic: false, waterAvailable: true), .water)
        XCTAssertEqual(ConsentBeaconStyle.choose(hasTargets: true, screenCount: 3, classic: true, waterAvailable: true), .classic)
        XCTAssertEqual(ConsentBeaconStyle.choose(hasTargets: true, screenCount: 2, classic: false, waterAvailable: false), .classic)
        XCTAssertEqual(ConsentBeacon.soundKey, "consentBeaconSound")
        XCTAssertEqual(ConsentBeacon.classicKey, "consentBeaconClassic")
    }

    // MARK: - окна-слои (решение 12.5)

    private func area(_ rects: [CGRect]) -> CGFloat { rects.reduce(0) { $0 + $1.width * $1.height } }

    func testOneHoleGivesFourWindowsAroundPrompt() {
        let hole = ConsentWaterLayout.holes([prompt])[0]
        XCTAssertEqual(hole, CGRect(x: 997, y: 297, width: 266, height: 296))
        let pieces = ConsentWaterLayout.pieces(of: wide, minus: [hole])
        XCTAssertEqual(pieces.count, 4)
        for piece in pieces {
            XCTAssertFalse(WaterGeo.hit(piece, hole), "\(piece)")
            XCTAssertTrue(wide.contains(piece))
        }
        XCTAssertEqual(area(pieces), wide.width * wide.height - hole.width * hole.height, accuracy: 0.001)
    }

    func testHoleAtScreenEdgeAndFractionalPrompt() {
        let edge = CGRect(x: 0, y: 200.4, width: 300.2, height: 250)
        let hole = ConsentWaterLayout.holes([edge])[0]
        // Края дырки — наружу до целых pt: окно запроса с запасом накрыто целиком.
        XCTAssertTrue(hole.contains(edge.insetBy(dx: -ConsentWaterK.hole, dy: -ConsentWaterK.hole)))
        let pieces = ConsentWaterLayout.pieces(of: wide, minus: [hole])
        XCTAssertEqual(pieces.count, 3)
        XCTAssertFalse(pieces.contains { WaterGeo.hit($0, hole) })
    }

    func testTwoPromptsOnOneScreenNoWindowOverEither() {
        let second = CGRect(x: 200, y: 450, width: 260, height: 220)
        let hs = ConsentWaterLayout.holes([prompt, second])
        let pieces = ConsentWaterLayout.pieces(of: wide, minus: hs)
        for piece in pieces { for hole in hs { XCTAssertFalse(WaterGeo.hit(piece, hole), "\(piece) над \(hole)") } }
        XCTAssertEqual(area(pieces), wide.width * wide.height - area(hs), accuracy: 0.001)
    }

    func testWindowsOnlyOnPromptAndCursorScreens() {
        let third = CGRect(x: -1470, y: 0, width: 1470, height: 956)
        let screens = [wide, tall, third]
        let onTall = CGRect(x: 1700, y: 200, width: 260, height: 290)
        // Курсор на широком, запрос на вертикальном: широкий целиком, вертикальный — четыре куска, третий пуст.
        let windows = ConsentWaterLayout.windows(screens: screens, targets: [onTall], cursor: CGPoint(x: 300, y: 400))
        XCTAssertEqual(windows.count, 5)
        XCTAssertTrue(windows.contains(wide))
        XCTAssertFalse(windows.contains { WaterGeo.hit($0, third) })
        XCTAssertFalse(windows.contains { WaterGeo.hit($0, ConsentWaterLayout.holes([onTall])[0]) })
        // Курсор там же, где запрос: только четыре куска.
        let same = ConsentWaterLayout.windows(screens: screens, targets: [onTall], cursor: CGPoint(x: 1600, y: 100))
        XCTAssertEqual(same.count, 4)
    }

    // MARK: - физика

    func testPlaqueNeverOverPromptOnRandomWalk() {
        var sim = ConsentWaterSim(seed: 7)
        var random = WaterRandom(seed: 42)
        var cursor = CGPoint(x: 200, y: 700)
        let hs = holes([prompt])
        var shown = 0
        for i in 0..<3000 {
            // Блуждание с рывками, в том числе сквозь окно запроса и на соседний монитор.
            if i % 90 == 0 {
                cursor = CGPoint(x: random.next() * 2240, y: random.next() * 900)
            } else {
                cursor.x = min(max(cursor.x + (random.next() - 0.5) * 40, 0), 2239)
                cursor.y = min(max(cursor.y + (random.next() - 0.5) * 40, 0), 899)
            }
            let frame = sim.step(dt: dt, input(cursor))
            guard frame.plaque.shown else { continue }
            shown += 1
            XCTAssertFalse(hs.contains { WaterGeo.hit($0, frame.plaque.panelRect) }, "шаг \(i): окошко над окном запроса")
        }
        XCTAssertGreaterThan(shown, 500)
    }

    func testPlaqueGrowsNextToCursorOnItsScreen() {
        var sim = ConsentWaterSim()
        let cursor = CGPoint(x: 300, y: 450)
        // 2 с: окошко ещё и растёт с далью (#8122) — ждём, пока встанет.
        let frames = run(&sim, cursor, seconds: 2)
        XCTAssertLessThan(frames[0].plaque.zoom, 0.2, "окошко вырастает, а не появляется рывком")
        let last = frames.last!
        XCTAssertEqual(last.plaque.zoom, 1, accuracy: 0.02)
        XCTAssertEqual(last.plaque.opacity, 1, accuracy: 0.02)
        XCTAssertTrue(last.plaque.clickable)
        XCTAssertTrue(visibleWide.contains(last.plaque.panelRect))
        // Окошко со стороны окна запроса (справа от курсора), в 22 pt от него.
        XCTAssertGreaterThan(last.plaque.center.x, cursor.x)
        XCTAssertEqual(WaterGeo.distance(cursor, last.plaque.panelRect), ConsentWaterK.pad, accuracy: 3)
        XCTAssertFalse(last.otherScreen)
        XCTAssertEqual(last.plaque.line2, ConsentWaterSim.lineClick)
        // Рамка выросла и дышит.
        XCTAssertEqual(last.rings.count, 1)
        XCTAssertEqual(last.rings[0].amp, 1, accuracy: 0.05)
        XCTAssertNotNil(last.box)
    }

    func testArrowTurnsWithSpringNotJump() {
        var sim = ConsentWaterSim()
        // Курсор слева от окна: стрелка вправо (0).
        run(&sim, CGPoint(x: 300, y: 445), seconds: 1)
        XCTAssertEqual(sim.step(dt: dt, input(CGPoint(x: 300, y: 445))).plaque.angle, 0, accuracy: 0.02)
        // Курсор под окном: стрелка вверх (−π/2 в CG), поворот плавный.
        let below = CGPoint(x: 1130, y: 880)
        let first = sim.step(dt: dt, input(below))
        XCTAssertGreaterThan(first.plaque.angle, -0.3, "за один кадр стрелка не прыгает")
        let settled = run(&sim, below, seconds: 1.2).last!
        XCTAssertEqual(settled.plaque.angle, -.pi / 2, accuracy: 0.03)
        // Спокойный вид — сразу.
        var calm = ConsentWaterSim(calm: true)
        run(&calm, CGPoint(x: 300, y: 445), seconds: 0.2)
        XCTAssertEqual(calm.step(dt: dt, input(below)).plaque.angle, -.pi / 2, accuracy: 0.001)
    }

    func testBlubWhenCursorReachesRingAndDetachesFarAway() {
        var sim = ConsentWaterSim()
        run(&sim, CGPoint(x: 300, y: 445), seconds: 1)
        XCTAssertFalse(sim.merged)
        // Курсор у рамки (ближе 36 pt к её внешнему краю) — «бульк», один раз.
        let near = CGPoint(x: prompt.minX - 30, y: 445)
        let frames = run(&sim, near, seconds: 0.6)
        XCTAssertTrue(sim.merged)
        XCTAssertEqual(frames.filter { $0.blub }.count, 1)
        XCTAssertTrue(frames.contains { $0.wave[1] > 0.1 }, "волна по контуру")
        XCTAssertFalse(frames.last!.plaque.shown, "окошко втекло в рамку")
        // Ближе 230 pt — ещё держится; дальше — отрыв, окошко снова у курсора.
        run(&sim, CGPoint(x: prompt.minX - 150, y: 445), seconds: 0.3)
        XCTAssertTrue(sim.merged)
        let away = run(&sim, CGPoint(x: prompt.minX - 400, y: 445), seconds: 1).last!
        XCTAssertFalse(sim.merged)
        XCTAssertTrue(away.plaque.shown)
    }

    func testTongueStretchesTowardPlaqueWhenClose() {
        var far = ConsentWaterSim()
        let farFrame = run(&far, CGPoint(x: 100, y: 445), seconds: 1).last!
        var near = ConsentWaterSim()
        let nearFrame = run(&near, CGPoint(x: prompt.minX - 330, y: 445), seconds: 1).last!
        XCTAssertFalse(near.merged)
        // Ближе — язык рамки толще и перемычки мягче: тянутся друг к другу.
        XCTAssertGreaterThan(nearFrame.k, farFrame.k + 5)
        XCTAssertGreaterThan(nearFrame.circles.count, farFrame.circles.count)
        XCTAssertGreaterThan(nearFrame.circles.map { $0.r }.max() ?? 0, farFrame.circles.map { $0.r }.max() ?? 0)
    }

    func testOtherScreenDropsFlowOverEdge() {
        var sim = ConsentWaterSim()
        let onTall = CGRect(x: 1700, y: 200, width: 260, height: 290)
        let cursor = CGPoint(x: 700, y: 400)
        let frame = run(&sim, cursor, seconds: 1.5, targets: [onTall]).last!
        XCTAssertTrue(frame.otherScreen)
        XCTAssertEqual(frame.plaque.line2, ConsentWaterSim.lineOther)
        XCTAssertTrue(frame.plaque.shown)
        XCTAssertTrue(visibleWide.contains(frame.plaque.panelRect))
        // Лужица на краю своего монитора и капля на краю соседнего.
        XCTAssertTrue(frame.circles.contains { abs($0.x - wide.maxX) < 0.5 && $0.r > 10 })
        XCTAssertTrue(frame.circles.contains { $0.x > wide.maxX && $0.x < onTall.minX - 10 }, "капли бегут к рамке")
        // Курсор у края (ближе 110 pt) — окошко втекает в лужицу.
        let edge = run(&sim, CGPoint(x: wide.maxX - 60, y: 380), seconds: 0.6, targets: [onTall]).last!
        XCTAssertTrue(sim.edgeMerged)
        XCTAssertFalse(edge.plaque.shown)
        // Перевёл мышь на тот монитор — обычный вид 2.1.
        let there = run(&sim, CGPoint(x: 1500, y: 900), seconds: 1, targets: [onTall]).last!
        XCTAssertFalse(there.otherScreen)
        XCTAssertEqual(there.plaque.line2, ConsentWaterSim.lineClick)
    }

    func testAnsweredEverythingDrainsAndFinishes() {
        var sim = ConsentWaterSim()
        let before = run(&sim, CGPoint(x: 300, y: 445), seconds: 1).last!
        XCTAssertFalse(before.finished)
        let after = run(&sim, CGPoint(x: 300, y: 445), seconds: 1, targets: [], alive: false)
        XCTAssertFalse(after[0].finished, "стекает, а не пропадает")
        XCTAssertFalse(after[0].plaque.shown)
        let doneAt = after.firstIndex { $0.finished }
        XCTAssertNotNil(doneAt)
        XCTAssertLessThan(CGFloat(doneAt ?? 999) * dt, 0.9)
        // Нет окон запроса совсем — кадр пустой.
        var fresh = ConsentWaterSim()
        XCTAssertTrue(fresh.step(dt: dt, input(.zero, targets: [])).finished)
    }

    func testCalmModeIsStill() {
        var sim = ConsentWaterSim(calm: true)
        let frames = run(&sim, CGPoint(x: prompt.minX - 30, y: 445), seconds: 0.5)
            + run(&sim, CGPoint(x: 300, y: 445), seconds: 0.5)
        for frame in frames {
            XCTAssertEqual(frame.k, 0.001)
            XCTAssertNil(frame.box)
            XCTAssertEqual(frame.wave, [0, 0, 0, 0])
            XCTAssertTrue(frame.circles.isEmpty, "без брызг и языка")
            XCTAssertEqual(frame.rings[0].thick, ConsentWaterK.thick)
        }
        let last = frames.last!
        XCTAssertTrue(last.plaque.solid)
        XCTAssertEqual(last.plaque.opacity, 1)
        // Кадры спокойного вида повторяются — перерисовывать нечего.
        XCTAssertEqual(sim.step(dt: dt, input(CGPoint(x: 300, y: 445))), sim.step(dt: dt, input(CGPoint(x: 300, y: 445))))
    }

    func testSecondPromptGetsItsOwnRing() {
        var sim = ConsentWaterSim()
        let second = CGRect(x: 200, y: 450, width: 260, height: 220)
        let frame = run(&sim, CGPoint(x: 700, y: 200), seconds: 0.8, targets: [prompt, second]).last!
        XCTAssertEqual(frame.rings.count, 2)
        XCTAssertEqual(Set(frame.rings.map { $0.rect.origin.x }), [prompt.minX, second.minX])
    }

    func testBoundsCoverRingPlaqueAndGlow() {
        var sim = ConsentWaterSim()
        let frame = run(&sim, CGPoint(x: 300, y: 445), seconds: 1).last!
        XCTAssertTrue(frame.bounds.contains(prompt.insetBy(dx: -ConsentWaterK.gap - ConsentWaterK.thick,
                                                           dy: -ConsentWaterK.gap - ConsentWaterK.thick)))
        XCTAssertTrue(frame.bounds.contains(frame.box!.insetBy(dx: -30, dy: -30)))
    }

    func testUniformsLayout() {
        var frame = ConsentWaterFrame()
        frame.rings = [WaterRing(rect: prompt, gap: 8, thick: 7, rin: 16, amp: 1)]
        frame.box = CGRect(x: 100, y: 200, width: 230, height: 64)
        frame.boxR = 22
        frame.circles = [WaterCircle(x: 5, y: 6, r: 7)]
        frame.k = 12
        let u = frame.uniforms(origin: CGPoint(x: 1440, y: -180), scale: 2, light: true)
        XCTAssertEqual(u.count, ConsentWaterFrame.uniformCount)
        XCTAssertEqual(u[0], SIMD4<Float>(1440, -180, 2, 3))
        XCTAssertEqual(u[1], SIMD4<Float>(12, 22, 1, 0.84))
        XCTAssertEqual(u[2], SIMD4<Float>(215, 232, 115, 32))
        XCTAssertEqual(u[4], SIMD4<Float>(1, 1, 0, 0))
        XCTAssertEqual(u[5], SIMD4<Float>(1130, 445, 130, 145))
        XCTAssertEqual(u[9], SIMD4<Float>(8, 7, 16, 1))
        XCTAssertEqual(u[13], SIMD4<Float>(5, 6, 7, 0))
    }

    func testScissorClipsToContentInsideWindow() {
        let window = CGRect(x: 1440, y: -180, width: 800, height: 1280)
        let sc = ConsentWaterRenderer.scissor(content: CGRect(x: 1400, y: 0, width: 200, height: 100), window: window,
                                              scale: 2, width: 1600, height: 2560)
        XCTAssertEqual(sc?.x, 0)
        XCTAssertEqual(sc?.y, 360)
        XCTAssertEqual(sc?.width, 320)
        XCTAssertEqual(sc?.height, 200)
        XCTAssertNil(ConsentWaterRenderer.scissor(content: CGRect(x: 0, y: 0, width: 100, height: 100), window: window,
                                                  scale: 2, width: 1600, height: 2560))
        XCTAssertNil(ConsentWaterRenderer.scissor(content: .null, window: window, scale: 2, width: 1600, height: 2560))
    }

    // #7766: слой Metal — на рамку содержимого с запасом, а не во весь монитор; мелкий сдвиг его не дёргает.
    func testMetalLayerFollowsContentNotWholeScreen() {
        let window = wide
        let content = CGRect(x: 600, y: 400, width: 300, height: 120)
        let rect = ConsentWaterLayerWindow.layerRect(content: content, window: window, current: .zero)
        XCTAssertTrue(rect.contains(content))
        XCTAssertTrue(window.contains(rect))
        XCTAssertLessThan(rect.width * rect.height, window.width * window.height / 4)
        XCTAssertEqual(rect.minX.truncatingRemainder(dividingBy: ConsentWaterLayerWindow.layerGrid), 0)
        let nudged = content.offsetBy(dx: 30, dy: -20)
        XCTAssertEqual(ConsentWaterLayerWindow.layerRect(content: nudged, window: window, current: rect), rect)
        let far = content.offsetBy(dx: 400, dy: 0)
        let next = ConsentWaterLayerWindow.layerRect(content: far, window: window, current: rect)
        XCTAssertNotEqual(next, rect)
        XCTAssertTrue(next.contains(far))
        // Содержимого в окне нет — слой где был; не было — пусто.
        XCTAssertEqual(ConsentWaterLayerWindow.layerRect(content: .null, window: window, current: rect), rect)
        XCTAssertEqual(ConsentWaterLayerWindow.layerRect(content: tall, window: window, current: .zero), .zero)
        // У края монитора — не вылезает за окно.
        let edge = ConsentWaterLayerWindow.layerRect(content: CGRect(x: 0, y: 0, width: 50, height: 50), window: window, current: .zero)
        XCTAssertEqual(edge.origin, .zero)
    }

    // #7766: stop() не прячет окна-слои, а закрывает и выбрасывает их вместе с drawable.
    func testStopDropsLayerWindows() throws {
        guard let overlay = ConsentWaterOverlay() else { throw XCTSkip("нет Metal") }
        overlay.makeLayers(3)
        XCTAssertEqual(overlay.layerCount, 3)
        overlay.stop()
        XCTAssertEqual(overlay.layerCount, 0)
    }

    func testBlubSoundIsQuietShortWav() {
        let data = ConsentWaterSound.wav()
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
        let count = Int(0.2 * Double(ConsentWaterSound.sampleRate))
        XCTAssertEqual(data.count, 44 + count * 2)
        let samples = stride(from: 44, to: data.count, by: 2).map { Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8) }
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1000)
        XCTAssertLessThan(peak, Int(0.15 * 32_767), "тихо")
    }

    // MARK: - шейдер

    func testShaderCompilesAndLeavesPromptClean() throws {
        guard let renderer = ConsentWaterRenderer() else { throw XCTSkip("нет Metal") }
        var sim = ConsentWaterSim()
        var frame = ConsentWaterFrame()
        for _ in 0..<60 { frame = sim.step(dt: dt, input(CGPoint(x: prompt.minX - 330, y: 445))) }
        // Весь монитор одним окном — даже так шейдер не рисует над окном запроса и его запасом.
        let px = try XCTUnwrap(renderer.pixels(frame, window: wide, scale: 1, light: false))
        XCTAssertEqual(px.width, 1440)
        let alpha = { (x: Int, y: Int) in px.bytes[(y * px.width + x) * 4 + 3] }
        let hole = holes([prompt])[0]
        var maxInHole: UInt8 = 0
        for y in Int(hole.minY)..<Int(hole.maxY) { for x in Int(hole.minX)..<Int(hole.maxX) { maxInHole = max(maxInHole, alpha(x, y)) } }
        XCTAssertEqual(maxInHole, 0, "ни пикселя над окном запроса")
        // Рамка видна: середина её толщины над окном запроса.
        let ringY = Int(prompt.minY - ConsentWaterK.gap - ConsentWaterK.thick / 2)
        XCTAssertGreaterThan(alpha(Int(prompt.midX), ringY), 150)
        // Тело окошка видно.
        let box = try XCTUnwrap(frame.box)
        XCTAssertGreaterThan(alpha(Int(box.midX), Int(box.midY)), 150)
        // Далеко от всего — пусто.
        XCTAssertEqual(alpha(20, 880), 0)
    }

    // MARK: - снимки на тестовых данных (по желанию)

    func testSnapshotsWhenAsked() throws {
        // Без папки — молча ничего: пропуск тестов tools/test.sh считает неполным прогоном.
        guard let dir = ProcessInfo.processInfo.environment["CONSENT_WATER_SNAPSHOT_DIR"],
              let renderer = ConsentWaterRenderer() else { return }
        let url = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let canvas = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // 2.1: издалека, язык тянется, «бульк»; 4.2 спокойный; 5.1 окна-слои.
        let shots: [(String, CGPoint, Bool, CGFloat)] = [
            ("2.1-far", CGPoint(x: 260, y: 640), false, 1.2),
            ("2.1-pull", CGPoint(x: prompt.minX - 330, y: 520), false, 1.2),
            ("2.1-blub", CGPoint(x: prompt.minX - 26, y: 520), false, 0.18),
            ("4.2-calm", CGPoint(x: 420, y: 560), true, 0.5),
        ]
        for (name, cursor, calm, seconds) in shots {
            var sim = ConsentWaterSim(calm: calm, seed: 3)
            if name == "2.1-blub" { run(&sim, CGPoint(x: prompt.minX - 330, y: 520), seconds: 1) }
            let frame = run(&sim, cursor, seconds: seconds).last!
            let image = try compose(renderer: renderer, canvas: canvas, screens: [canvas], frame: frame, cursor: cursor,
                                    targets: [prompt], layers: name == "2.1-pull")
            try write(image, to: url.appendingPathComponent("\(name).png"))
            if name == "2.1-pull" {
                let layers = try compose(renderer: renderer, canvas: canvas, screens: [canvas], frame: frame, cursor: cursor,
                                         targets: [prompt], layers: true, outline: true)
                try write(layers, to: url.appendingPathComponent("5.1-layers.png"))
            }
        }
        // 3.1: курсор на широком, запрос на вертикальном.
        let onTall = CGRect(x: 1700, y: 260, width: 260, height: 290)
        var sim = ConsentWaterSim(seed: 5)
        let cursor = CGPoint(x: 820, y: 430)
        let frame = run(&sim, cursor, seconds: 1.6, targets: [onTall]).last!
        let both = CGRect(x: 0, y: -180, width: 2240, height: 1280)
        let image = try compose(renderer: renderer, canvas: both, screens: [wide, tall], frame: frame, cursor: cursor,
                                targets: [onTall], layers: false)
        try write(image, to: url.appendingPathComponent("3.1-two-screens.png"))
    }

    // Стол, окно запроса, вода, окошко и курсор — одной картинкой, как на экране.
    private func compose(renderer: ConsentWaterRenderer, canvas: CGRect, screens: [CGRect], frame: ConsentWaterFrame,
                         cursor: CGPoint, targets: [CGRect], layers: Bool, outline: Bool = false) throws -> CGImage {
        let scale: CGFloat = 1
        let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: scale, y: scale)
        // CG (y вниз) → контекст (y вверх).
        let flip = { (r: CGRect) in CGRect(x: r.minX - canvas.minX, y: canvas.maxY - r.maxY, width: r.width, height: r.height) }
        ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.03, blue: 0.08, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: canvas.size))
        for screen in screens {
            let r = flip(screen)
            ctx.saveGState()
            ctx.clip(to: r)
            let colors = [NSColor(srgbRed: 0.20, green: 0.12, blue: 0.32, alpha: 1).cgColor,
                          NSColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.maxX, y: r.minY), options: [])
            // Пара окон приложений — чтобы было видно, что вода прозрачна вокруг.
            ctx.setFillColor(NSColor(srgbRed: 0.13, green: 0.12, blue: 0.16, alpha: 1).cgColor)
            ctx.fill(CGRect(x: r.minX + 60, y: r.minY + 120, width: 420, height: r.height - 220))
            ctx.restoreGState()
        }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        for target in targets {
            let r = flip(target)
            NSColor(srgbRed: 0.17, green: 0.17, blue: 0.19, alpha: 1).setFill()
            NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
            let text = "«PimpMyClaude» хочет управлять «Google Chrome»." as NSString
            text.draw(in: CGRect(x: r.minX + 20, y: r.maxY - 130, width: r.width - 40, height: 60), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.white])
            NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: r.midX + 8, y: r.minY + 16, width: r.width / 2 - 24, height: 28),
                         xRadius: 6, yRadius: 6).fill()
            NSColor(white: 0.35, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: r.minX + 16, y: r.minY + 16, width: r.width / 2 - 24, height: 28),
                         xRadius: 6, yRadius: 6).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        // Вода: рисуем окнами-слоями, как живьём (куски вокруг дырки + монитор курсора).
        let windows = ConsentWaterLayout.windows(screens: screens, targets: targets, cursor: cursor)
        for window in windows {
            let px = try XCTUnwrap(renderer.pixels(frame, window: window, scale: scale, light: false))
            let provider = CGDataProvider(data: Data(px.bytes) as CFData)!
            let image = CGImage(width: px.width, height: px.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: px.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                    | CGImageAlphaInfo.premultipliedFirst.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            ctx.draw(image, in: flip(window))
            if outline {
                ctx.setStrokeColor(NSColor(srgbRed: 0.94, green: 0.78, blue: 0.36, alpha: 0.95).cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [8, 6])
                ctx.stroke(flip(window).insetBy(dx: 3, dy: 3))
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }
        if outline {
            ctx.setStrokeColor(NSColor(srgbRed: 0.9, green: 0.39, blue: 0.36, alpha: 1).cgColor)
            ctx.setLineWidth(2)
            for hole in ConsentWaterLayout.holes(targets) { ctx.stroke(flip(hole)) }
        }
        // Окошко: его панель рисует стрелку и подписи.
        if frame.plaque.shown {
            let view = ConsentWaterPlaqueView(frame: ConsentWaterPlaqueView.panelBounds)
            view.apply(frame.plaque, scale: scale)
            let r = flip(frame.plaque.panelRect)
            ctx.saveGState()
            let bounds = ConsentWaterPlaqueView.panelBounds
            ctx.translateBy(x: r.midX - bounds.width / 2, y: r.midY - bounds.height / 2)
            ctx.setAlpha(frame.plaque.opacity)
            view.layer?.render(in: ctx)
            ctx.restoreGState()
            if outline {
                ctx.setStrokeColor(NSColor(srgbRed: 0.31, green: 0.81, blue: 0.54, alpha: 1).cgColor)
                ctx.stroke(r)
            }
        }
        // Курсор.
        let c = CGPoint(x: cursor.x - canvas.minX, y: canvas.maxY - cursor.y)
        let arrow = CGMutablePath()
        arrow.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: -18), CGPoint(x: 4.6, y: -13.6),
                                 CGPoint(x: 7.7, y: -20.6), CGPoint(x: 10.9, y: -19.2), CGPoint(x: 7.8, y: -12.4),
                                 CGPoint(x: 13, y: -12.4)])
        arrow.closeSubpath()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.addPath(arrow)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.4)
        ctx.drawPath(using: .fillStroke)
        return try XCTUnwrap(ctx.makeImage())
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
