import CoreGraphics
import Foundation

// Плавная линия графиков панели — температура и память (WF242; слово Элвиса 11.10.2026: «График рваный, от этого
// какой-то неприятный… плавный… более точный, но поплавнее… рваные в интерфейсе вещи раздражают»).
// Два шага, оба без вранья:
//   1. `smoothed` — рябь между соседними минутами гасится окном 1-2-1 в несколько проходов (`passes`); это
//      усреднение, поэтому линия никогда не выходит за самое большое и самое малое чтение. Последняя точка
//      остаётся как есть: «сейчас» на линии — то же число, что в строке. Пик на одну минуту рисуется ниже
//      своего числа — настоящее чтение каждой минуты говорит подпись под курсором, размах — подпись под графиком;
//   2. `controls` — кривая через точки монотонным кубическим сплайном (Фрич — Карлсон): между двумя соседними
//      точками линия не выходит за их значения — зубцов и вылетов нет.
// Чистая часть; рисует `Panel/PanelCharts.swift`, тесты — `ChartCurveWF242Tests`.

public enum ChartCurve {
    /// Проходов окна 1-2-1: четыре — усреднение примерно по пяти минутам вокруг точки (чтения раз в минуту). На
    /// графике за 3 ч минута — полтора пикселя: мельче этого глаз видит не данные, а пилу.
    public static let passes = 4

    /// Сглаженные значения: окно 1-2-1, `passes` проходов; последняя точка («сейчас») не трогается, первая
    /// усредняется с соседом — без крючка на левом краю. Результат всегда внутри «минимум…максимум» исходных.
    public static func smoothed(_ values: [Double], passes: Int = ChartCurve.passes) -> [Double] {
        guard values.count > 2 else { return values }
        var out = values
        for _ in 0..<max(0, passes) {
            let before = out
            out[0] = (3 * before[0] + before[1]) / 4
            for index in 1..<(before.count - 1) {
                out[index] = (before[index - 1] + 2 * before[index] + before[index + 1]) / 4
            }
        }
        return out
    }

    /// Опорные точки кривых Безье между соседними точками (их на одну меньше, чем точек): отрезок `i` идёт от
    /// `points[i]` к `points[i + 1]` через `c1`, `c2`. Точки — слева направо; совпавшие по X — прямой.
    public static func controls(_ points: [CGPoint]) -> [(c1: CGPoint, c2: CGPoint)] {
        guard points.count > 1 else { return [] }
        let count = points.count
        let steps = (0..<(count - 1)).map { points[$0 + 1].x - points[$0].x }
        let slopes = (0..<(count - 1)).map { steps[$0] > 0 ? (points[$0 + 1].y - points[$0].y) / steps[$0] : 0 }
        var tangents = [CGFloat](repeating: 0, count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]
        if count > 2 {
            for index in 1..<(count - 1) {
                // Вершина или впадина — касательная горизонтальна: кривая не перелетает точку.
                tangents[index] = slopes[index - 1] * slopes[index] <= 0 ? 0 : (slopes[index - 1] + slopes[index]) / 2
            }
        }
        for index in 0..<(count - 1) {
            guard slopes[index] != 0 else {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }
            let a = tangents[index] / slopes[index], b = tangents[index + 1] / slopes[index]
            let length = a * a + b * b
            if length > 9 {
                let scale = 3 / length.squareRoot()
                tangents[index] = scale * a * slopes[index]
                tangents[index + 1] = scale * b * slopes[index]
            }
        }
        return (0..<(count - 1)).map { index in
            let from = points[index], to = points[index + 1], third = steps[index] / 3
            return (CGPoint(x: from.x + third, y: from.y + tangents[index] * third),
                    CGPoint(x: to.x - third, y: to.y - tangents[index + 1] * third))
        }
    }

    /// Доли 0…1 оси X линии в свёрнутой строке (слово Элвиса 22.10.2026: температура «рвётся» — точка, разрыв, линия;
    /// нужна сплошная): по времени, но промежуток дольше `gap` (Мак спал, Пимп не работал) идёт за один обычный шаг
    /// `step` — линия одним куском, сон её не рвёт. В раскрытом графике с осью часов сон остаётся разрывом.
    /// Одна точка или все в одну секунду — справа (1).
    public static func awakeFractions(_ dates: [Date], gap: TimeInterval, step: TimeInterval) -> [Double] {
        guard !dates.isEmpty else { return [] }
        var offsets: [Double] = [0]
        for index in dates.indices.dropFirst() {
            let delta = max(0, dates[index].timeIntervalSince(dates[index - 1]))
            offsets.append(offsets[index - 1] + (delta > gap ? step : delta))
        }
        guard let span = offsets.last, span > 0 else { return dates.map { _ in 1 } }
        return offsets.map { $0 / span }
    }

    /// Значение Y кривой Безье отрезка на доле `t` (0…1) — для проверки, что линия не вылетает.
    static func bezierY(_ from: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ to: CGPoint, at t: CGFloat) -> CGFloat {
        let u = 1 - t
        return u * u * u * from.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * to.y
    }
}
