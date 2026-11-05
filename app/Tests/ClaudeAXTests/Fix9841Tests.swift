import XCTest
@testable import ClaudeAX

/// #9841, #9840 (слово Элвиса 12.10.2026 00:54: «Он анимирован со стрелкой. Они тянуться должны друг к другу… и везде
/// пусть они будут анимированы»): одна анимация пузырьков-подсказок `HintPull` — подлёт к цели и дыхание к ней,
/// «Уменьшить движение» — спокойное проявление без рывка; спокойный вид окошка маяка проявляется ею же.
final class Fix9841Tests: XCTestCase {
    private let up = CGVector(dx: 0, dy: 1)

    // MARK: подлёт и дыхание

    func testBubbleFliesInTowardTargetAndSettles() {
        let start = HintPull.frame(at: 0, toward: CGVector(dx: 0, dy: 10), calm: false)
        XCTAssertEqual(start.offset.dx, 0, accuracy: 1e-6)
        XCTAssertEqual(start.offset.dy, -HintPull.distance, accuracy: 1e-6, "стартует позади — дальше от цели")
        XCTAssertEqual(start.opacity, 0)
        XCTAssertEqual(start.pull, 1, accuracy: 1e-6)

        // Подлетает: расстояние до места покоя быстро убывает, проскакивает чуть вперёд (пружина), но не дальше дыхания.
        let quarter = HintPull.frame(at: 0.2, toward: up, calm: false)
        XCTAssertGreaterThan(quarter.offset.dy, start.offset.dy)
        XCTAssertEqual(quarter.opacity, 1, accuracy: 0.05)
        var worst: CGFloat = 0
        for step in 0...600 {
            let frame = HintPull.frame(at: Double(step) / 60, toward: up, calm: false)
            XCTAssertEqual(frame.offset.dx, 0, accuracy: 1e-9, "движется только по оси к цели")
            if Double(step) / 60 > HintPull.settle {
                worst = max(worst, abs(frame.offset.dy))
                XCTAssertGreaterThanOrEqual(frame.offset.dy, -0.5, "после подлёта не отступает от цели")
            }
        }
        XCTAssertLessThanOrEqual(worst, HintPull.lean + 0.5, "после подлёта — только дыхание в пределах `lean`")
        // Дыхание: через полпериода тянется к цели почти на всю глубину, через период — снова на месте.
        let base = 3 * HintPull.period
        XCTAssertEqual(HintPull.frame(at: base + HintPull.period / 2, toward: up, calm: false).offset.dy,
                       HintPull.lean, accuracy: 0.05)
        XCTAssertEqual(HintPull.frame(at: base, toward: up, calm: false).offset.dy, 0, accuracy: 0.05)
    }

    func testDirectionIsNormalizedAndAnyWay() {
        let left = HintPull.frame(at: 0, toward: CGVector(dx: -300, dy: 0), calm: false)
        XCTAssertEqual(left.offset.dx, HintPull.distance, accuracy: 1e-6, "цель слева — стартует правее")
        XCTAssertEqual(left.offset.dy, 0, accuracy: 1e-6)
    }

    func testReduceMotionOrNoTargetOnlyFadesIn() {
        for (toward, calm) in [(up, true), (CGVector.zero, false)] {
            var last: CGFloat = -1
            for step in 0...30 {
                let frame = HintPull.frame(at: Double(step) / 60, toward: toward, calm: calm)
                XCTAssertEqual(frame.offset, .zero, "без сдвига")
                XCTAssertEqual(frame.pull, 0)
                XCTAssertGreaterThanOrEqual(frame.opacity, last, "проявляется, не мигает")
                last = frame.opacity
            }
            XCTAssertEqual(HintPull.frame(at: 0, toward: toward, calm: calm).opacity, 0)
            XCTAssertEqual(HintPull.frame(at: HintPull.fade, toward: toward, calm: calm).opacity, 1)
            XCTAssertGreaterThan(HintPull.frame(at: HintPull.fade / 2, toward: toward, calm: calm).opacity, 0.3,
                                 "не рывком в конце, а плавно")
        }
    }

    func testFadeOutAndApproach() {
        XCTAssertEqual(HintPull.fadeOut(at: 0), 1)
        XCTAssertEqual(HintPull.fadeOut(at: HintPull.fade), 0)
        XCTAssertEqual(HintPull.fadeOut(at: HintPull.fade / 2), 0.5, accuracy: 0.01)
        XCTAssertEqual(HintPull.approach(0, to: 1, dt: CGFloat(HintPull.fade / 2)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(HintPull.approach(0.9, to: 1, dt: 1), 1)
        XCTAssertEqual(HintPull.approach(0.2, to: 0, dt: 1), 0)
    }

    func testSideOfTarget() {
        let plaque = CGRect(x: 100, y: 400, width: 400, height: 200)
        XCTAssertEqual(HintPull.side(of: CGRect(x: 100, y: 100, width: 477, height: 270), from: plaque), .top,
                       "окно связки ключей над плашкой (CG, y вниз) — стрелка вверх")
        XCTAssertEqual(HintPull.side(of: CGRect(x: 100, y: 650, width: 400, height: 100), from: plaque), .bottom)
        XCTAssertEqual(HintPull.side(of: CGRect(x: 0, y: 300, width: 80, height: 600), from: plaque), .left)
        XCTAssertEqual(HintPull.side(of: CGRect(x: 520, y: 300, width: 600, height: 600), from: plaque), .right)
        XCTAssertNil(HintPull.side(of: plaque.insetBy(dx: 20, dy: 20), from: plaque), "перекрываются — стрелки нет")
    }

    func testKeychainPlaqueUnderWindowPointsUp() {
        let window = CGRect(x: 500, y: 200, width: 477, height: 270)
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = KeychainHint.plaqueFrame(window: window, size: CGSize(width: 477, height: 220), visible: visible)
        XCTAssertEqual(HintPull.side(of: window, from: frame), .top)
        // Внизу места нет — плашка над окном, стрелка вниз.
        let low = CGRect(x: 500, y: 600, width: 477, height: 270)
        let above = KeychainHint.plaqueFrame(window: low, size: CGSize(width: 477, height: 220), visible: visible)
        XCTAssertEqual(HintPull.side(of: low, from: above), .bottom)
    }

    // MARK: спокойный вид маяка — тем же проявлением

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let prompt = CGRect(x: 1000, y: 300, width: 260, height: 290)
    private let dt: CGFloat = 1.0 / 60

    private func input(alive: Bool = true) -> ConsentWaterInput {
        ConsentWaterInput(cursor: CGPoint(x: 300, y: 445), targets: [prompt], screens: [screen],
                          visible: [CGRect(x: 0, y: 25, width: 1440, height: 875)], alive: alive)
    }

    func testCalmBeaconBubbleFadesInsteadOfJumping() {
        var sim = ConsentWaterSim(calm: true)
        let shown = (0..<30).map { _ in sim.step(dt: dt, input()).plaque.opacity }
        XCTAssertLessThan(shown[0], 0.2, "первый кадр — не сразу целиком")
        XCTAssertTrue(zip(shown, shown.dropFirst()).allSatisfy { $0 <= $1 }, "проявляется без скачков назад")
        XCTAssertTrue(zip(shown, shown.dropFirst()).allSatisfy { $1 - $0 < 0.3 }, "без рывка")
        XCTAssertEqual(shown.last, 1)
        // Ответили — растворяется, и кадр «всё» — только когда растворилось.
        var gone: [ConsentWaterFrame] = []
        for _ in 0..<60 {
            let frame = sim.step(dt: dt, input(alive: false))
            gone.append(frame)
            if frame.finished { break }
        }
        let fading = gone.map { $0.plaque.opacity }
        XCTAssertTrue(zip(fading, fading.dropFirst()).allSatisfy { $0 >= $1 })
        XCTAssertGreaterThan(fading[1], 0, "не пропадает рывком")
        XCTAssertTrue(gone.last?.finished == true)
        XCTAssertLessThan(gone.last?.plaque.opacity ?? 1, 0.05)
    }
}
