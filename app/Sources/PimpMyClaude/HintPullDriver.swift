import AppKit
import ClaudeAX
import SwiftUI

// Пузырьки-подсказки «тянутся друг к другу» (#9841, #9840): окно плашки подлетает к своей цели по пружине `HintPull`,
// потом чуть «дышит» к ней; уходит растворением. «Уменьшить движение» — только спокойное проявление. Один драйвер на
// окно: плашка связки ключей (`KeychainHintWindow.swift`) и плашка разрешения (`PermissionHintWindow.swift`); у окошка
// маяка окон доступа своя физика, спокойный вид — тот же `HintPull` (`ConsentWaterSim`). Стрелка к цели — `hintPointer`.

/// Двигает окно плашки по `HintPull`. Координаты — Cocoa.
final class HintPullDriver {
    /// «Уменьшить движение» в macOS; читается при каждом появлении.
    var calm: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private weak var window: NSWindow?
    private var rest = NSRect.zero
    private var toward = CGVector.zero
    private var calmNow = false
    private var shownAt: CFTimeInterval?
    private var hideAt: CFTimeInterval?
    private var done: (() -> Void)?
    private var timer: Timer?
    private var interval: TimeInterval = 0

    init(window: NSWindow) { self.window = window }

    /// Встать в `frame`, тянуться к точке `target` (nil — плашка ни на что не показывает: только проявляется).
    /// Первое появление — подлёт; уже стоит — только новое место покоя.
    func show(at frame: NSRect, toward target: NSPoint?) {
        guard let window = window else { return }
        rest = frame
        toward = target.map { CGVector(dx: $0.x - frame.midX, dy: $0.y - frame.midY) } ?? .zero
        hideAt = nil
        done = nil
        if shownAt == nil {
            shownAt = CACurrentMediaTime()
            calmNow = calm()
            window.alphaValue = 0
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
        } else if window.frame.size != frame.size {
            window.setFrame(NSRect(origin: window.frame.origin, size: frame.size), display: true)
        }
        tick()
    }

    /// Уйти растворением; потом окно убирается и зовётся `completion`. Не показано — сразу.
    func hide(completion: (() -> Void)? = nil) {
        guard shownAt != nil, let window = window, window.isVisible else {
            reset()
            completion?()
            return
        }
        if hideAt == nil { hideAt = CACurrentMediaTime() }
        done = completion
        tick()
    }

    var isShown: Bool { shownAt != nil && hideAt == nil }

    private func tick() {
        guard let window = window, let shownAt = shownAt else { return stopTimer() }
        let now = CACurrentMediaTime()
        if let hideAt = hideAt {
            let alpha = HintPull.fadeOut(at: now - hideAt)
            window.alphaValue = alpha * CGFloat(min(1, HintPull.frame(at: now - shownAt, toward: toward, calm: calmNow).opacity))
            guard alpha > 0 else {
                window.orderOut(nil)
                let finish = done
                reset()
                finish?()
                return
            }
            return schedule(1.0 / 60)
        }
        let t = now - shownAt
        let frame = HintPull.frame(at: t, toward: toward, calm: calmNow)
        window.alphaValue = frame.opacity
        let origin = NSPoint(x: (rest.minX + frame.offset.dx).rounded(), y: (rest.minY + frame.offset.dy).rounded())
        if window.frame.origin != origin { window.setFrameOrigin(origin) }
        // Подлёт — 60 кадров; дальше дыхание — 30; спокойный вид после проявления не двигается вовсе.
        if calmNow || toward == .zero { return t < HintPull.fade ? schedule(1.0 / 60) : stopTimer() }
        schedule(t < HintPull.settle ? 1.0 / 60 : 1.0 / 30)
    }

    private func schedule(_ every: TimeInterval) {
        guard timer == nil || interval != every else { return }
        timer?.invalidate()
        interval = every
        let timer = Timer(timeInterval: every, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func reset() {
        stopTimer()
        shownAt = nil
        hideAt = nil
        done = nil
    }
}

// MARK: - стрелка к цели

/// Стрелка плашки к её цели: треугольник в прозрачном поле вокруг плашки (окно плашки на `inset` больше её со всех
/// сторон — стрелка с любой стороны помещается, размер окна от стороны не зависит).
struct HintPointer: Shape {
    static let inset: CGFloat = 9
    static let width: CGFloat = 18
    let side: HintPull.Side
    /// Только две косые стороны — обводка; закрытый треугольник — заливка.
    var open = false

    func path(in rect: CGRect) -> Path {
        let (tip, a, b): (CGPoint, CGPoint, CGPoint)
        switch side {
        case .top: (tip, a, b) = (CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY),
                                  CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottom: (tip, a, b) = (CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY),
                                     CGPoint(x: rect.maxX, y: rect.minY))
        case .left: (tip, a, b) = (CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.minY),
                                      CGPoint(x: rect.maxX, y: rect.maxY))
        case .right: (tip, a, b) = (CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.minX, y: rect.minY),
                                       CGPoint(x: rect.minX, y: rect.maxY))
        }
        var path = Path()
        path.move(to: a)
        path.addLine(to: tip)
        path.addLine(to: b)
        if !open { path.closeSubpath() }
        return path
    }
}

extension View {
    /// Плашка со стрелкой к цели: поле `HintPointer.inset` со всех сторон, стрелка — с `side` (nil — без стрелки),
    /// заливка и обводка — как у самой плашки; основание стрелки заходит на кайму, шва нет.
    func hintPointer(_ side: HintPull.Side?, fill: Color, stroke: Color, lineWidth: CGFloat) -> some View {
        let inset = HintPointer.inset
        let reach = inset + lineWidth
        let along = HintPointer.width
        return padding(inset).overlay(alignment: Self.alignment(side)) {
            if let side = side {
                let size = side == .top || side == .bottom ? CGSize(width: along, height: reach)
                    : CGSize(width: reach, height: along)
                ZStack {
                    HintPointer(side: side).fill(fill)
                    HintPointer(side: side, open: true).stroke(stroke, style: StrokeStyle(lineWidth: lineWidth,
                                                                                          lineJoin: .round))
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
            }
        }
    }

    private static func alignment(_ side: HintPull.Side?) -> Alignment {
        switch side {
        case .top?: return .top
        case .bottom?: return .bottom
        case .left?: return .leading
        case .right?: return .trailing
        case nil: return .center
        }
    }
}
