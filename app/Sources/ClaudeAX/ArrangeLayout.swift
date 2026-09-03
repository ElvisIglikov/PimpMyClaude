import CoreGraphics
import Foundation

/// «Расставить»: ровная сетка по рабочей области главного экрана.
/// Чистая арифметика — сюда же смотрят тесты, живого AX не требует.
enum ArrangeLayout {
    /// Ширина ячейки, ниже которой столбец отбрасывается (M.minCellWidth = 340).
    static let minCellWidth: CGFloat = 340
    /// Разброс по вертикали, внутри которого окна считаются одним рядом.
    static let rowTolerance: CGFloat = 60

    /// Столбцы для n окон: сначала все в один ряд во всю высоту, ряды появляются
    /// только когда ячейка стала бы уже minCellWidth (слово Элвиса 03.09: «правильная
    /// четвёрка — четыре столбца во всю высоту, не 2×2»).
    static func columns(count: Int, width: CGFloat, minCellWidth: CGFloat = minCellWidth) -> Int {
        if count <= 1 { return 1 }
        var cols = count
        while cols > 1 && width / CGFloat(cols) < minCellWidth { cols -= 1 }
        return cols
    }

    /// Прямоугольники ячеек в порядке окон. Границы считаются от долей рамки
    /// (floor(x + 0.5), как в Lua), поэтому плитки стыкуются без щелей и наползаний.
    static func frames(count: Int, in area: CGRect,
                       minCellWidth: CGFloat = minCellWidth) -> [CGRect] {
        guard count > 0, area.width > 0, area.height > 0 else { return [] }
        let cols = columns(count: count, width: area.width, minCellWidth: minCellWidth)
        let rows = Int(ceil(Double(count) / Double(cols)))
        return (0..<count).map { i in
            let col = CGFloat(i % cols), row = CGFloat(i / cols)
            let x0 = area.minX + (col * area.width / CGFloat(cols) + 0.5).rounded(.down)
            let x1 = area.minX + ((col + 1) * area.width / CGFloat(cols) + 0.5).rounded(.down)
            let y0 = area.minY + (row * area.height / CGFloat(rows) + 0.5).rounded(.down)
            let y1 = area.minY + ((row + 1) * area.height / CGFloat(rows) + 0.5).rounded(.down)
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }

    /// Порядок окон: слева направо, потом сверху вниз — окно, стоящее нормально, остаётся
    /// на месте (слово Элвиса 03.09 13:50). Возвращает индексы исходного массива.
    ///
    /// В Lua это было сравнение «|Δy| > 60 → по y, иначе по x»; оно нетранзитивно (0, 50, 100),
    /// поэтому здесь тот же смысл выражен детерминированно: окна разбиваются на ряды по
    /// вертикали (шаг ряда — rowTolerance от якоря), внутри ряда — по x.
    ///
    /// Второй экран: порядок считается по глобальным координатам, экраны между собой не
    /// различаются — окна левого монитора идут раньше правого, а стоящие рядом по вертикали
    /// окна с разных экранов попадут в один ряд. «Расставить» и так работает по главному
    /// экрану; автопокраске (WF10) этого хватает — ей нужен устойчивый порядок, а не экраны.
    static func order(of frames: [CGRect], rowTolerance: CGFloat = rowTolerance) -> [Int] {
        let byTop = frames.indices.sorted { a, b in
            let (fa, fb) = (frames[a], frames[b])
            if fa.minY != fb.minY { return fa.minY < fb.minY }
            if fa.minX != fb.minX { return fa.minX < fb.minX }
            return a < b
        }
        var row = [Int: Int]()
        var currentRow = 0
        var anchor: CGFloat?
        for index in byTop {
            let top = frames[index].minY
            if let a = anchor, top - a > rowTolerance {
                currentRow += 1
                anchor = top
            } else if anchor == nil {
                anchor = top
            }
            row[index] = currentRow
        }
        return byTop.sorted { a, b in
            let (ra, rb) = (row[a] ?? 0, row[b] ?? 0)
            if ra != rb { return ra < rb }
            if frames[a].minX != frames[b].minX { return frames[a].minX < frames[b].minX }
            return a < b
        }
    }
}
