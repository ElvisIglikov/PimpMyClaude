import CoreGraphics
import Foundation

// Пузырьки-подсказки «тянутся друг к другу» (#9841, #9840; слово Элвиса 12.10.2026 00:54: «Он анимирован со стрелкой.
// Они тянуться должны друг к другу… и везде пусть они будут анимированы и тянутся друг к другу»). Одна анимация на все
// пузырьки: плашка под окном связки ключей (`KeychainHint`), плашка разрешения у Системных настроек
// (`PermissionHintWindow`) и спокойный вид окошка маяка окон доступа (`ConsentWaterSim`). Образец — само окошко маяка:
// пружина к окну запроса (`pl.step(w: 9, z: 0.62)`) и «дыхание» стрелки. «Уменьшить движение» — без сдвига и дыхания,
// только спокойное проявление.
// Здесь только расчёт кадра (тесты `HintPullTests`); окна двигает `HintPullDriver` в таргете приложения.

public enum HintPull {
    /// Откуда пузырёк подлетает к цели: на столько pt дальше от неё.
    public static let distance: CGFloat = 28
    /// Пружина подлёта — как у окошка маяка.
    static let w = 9.0
    static let z = 0.62
    /// «Дыхание» навстречу цели после подлёта: на столько pt, период — в секундах.
    public static let lean: CGFloat = 3
    public static let period = 2.4
    /// Появление и уход растворением, с: в спокойном виде — всё движение.
    public static let fade = 0.25
    /// К этому времени подлёт закончен — дальше только дыхание (драйвер может обновлять кадр реже).
    public static let settle = 0.9

    public struct Frame: Equatable {
        /// Сдвиг от места покоя, pt, в координатах вектора `toward`.
        public var offset: CGVector
        public var opacity: CGFloat
        /// Насколько пузырёк сейчас тянется к цели, 0…1.
        public var pull: CGFloat
    }

    /// Кадр через `t` с после появления. `toward` — направление от пузырька к цели (нормируется; нулевое — пузырёк
    /// никуда не показывает: только проявляется). `calm` — «Уменьшить движение».
    public static func frame(at t: Double, toward: CGVector, calm: Bool) -> Frame {
        let t = max(0, t)
        let dir = unit(toward)
        guard !calm, dir != .zero else { return Frame(offset: .zero, opacity: CGFloat(eased(t / fade)), pull: 0) }
        // Недодемпфированная пружина: стартует на `distance` позади (дальше от цели), без скорости.
        let wd = w * (1 - z * z).squareRoot()
        let back = Double(distance) * exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t))
        // Дыхание включается плавно, пока подлёт гаснет.
        let on = eased((t - settle / 2) / (settle / 2))
        let breath = Double(lean) * on * (1 - cos(2 * .pi * t / period)) / 2
        let ahead = CGFloat(breath - back)
        let pull = min(1, max(0, CGFloat(max(back / Double(distance), breath / Double(lean)))))
        return Frame(offset: CGVector(dx: dir.dx * ahead, dy: dir.dy * ahead), opacity: CGFloat(eased(t / 0.18)),
                     pull: pull)
    }

    /// Прозрачность через `t` с после «уйди»: растворение за `fade` — в обоих видах, без рывка.
    public static func fadeOut(at t: Double) -> CGFloat { CGFloat(1 - eased(max(0, t) / fade)) }

    /// Шаг проявления 0…1 к `target` за `dt` с — линейно, полный путь за `fade` (спокойный вид маяка).
    public static func approach(_ value: CGFloat, to target: CGFloat, dt: CGFloat) -> CGFloat {
        let step = dt / CGFloat(fade)
        return value < target ? min(target, value + step) : max(target, value - step)
    }

    /// С какой стороны плашки её цель — там у плашки стрелка.
    public enum Side: Equatable, Sendable { case top, bottom, left, right }

    /// Сторона цели `target` от плашки `plaque`, обе в CG (y вниз): цель целиком выше, ниже, левее или правее;
    /// перекрываются — nil (стрелке некуда показывать).
    public static func side(of target: CGRect, from plaque: CGRect) -> Side? {
        if target.maxY <= plaque.minY { return .top }
        if target.minY >= plaque.maxY { return .bottom }
        if target.maxX <= plaque.minX { return .left }
        if target.minX >= plaque.maxX { return .right }
        return nil
    }

    /// Плавный край 0…1 (smoothstep), вне — зажат.
    public static func eased(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }

    static func unit(_ vector: CGVector) -> CGVector {
        let length = (vector.dx * vector.dx + vector.dy * vector.dy).squareRoot()
        guard length > 1e-6 else { return .zero }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }
}
