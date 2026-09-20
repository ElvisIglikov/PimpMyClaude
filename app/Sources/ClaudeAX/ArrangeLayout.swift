import CoreGraphics
import Foundation

/// «Расставить»: ровная сетка по рабочей области главного экрана.
/// Чистая арифметика — сюда же смотрят тесты, живого AX не требует.
enum ArrangeLayout {
    /// Ширина ячейки, ниже которой столбец отбрасывается (M.minCellWidth = 340).
    static let minCellWidth: CGFloat = 340
    /// Разброс по вертикали, внутри которого окна считаются одним рядом.
    static let rowTolerance: CGFloat = 60

    /// Раскладка «Расставить» (план WF21, слова Элвиса 08.09): лента считает столбцы сама,
    /// у остальных сетка задана и лишние окна не трогаются вовсе. Строки — те же, что в
    /// поле `layout` канала «Пимп» (`tools/pimp.py`).
    enum Mode: String, CaseIterable {
        case ribbon = "row"
        case four = "4"
        case five = "5"
        case tenGrid = "5x2"
    }

    /// Сетка фиксированной раскладки: столбцы × ряды. У ленты их нет (nil) — она считает
    /// столбцы по числу окон (`columns(count:width:)`).
    static func grid(of mode: Mode) -> (cols: Int, rows: Int)? {
        switch mode {
        case .ribbon: return nil
        case .four: return (cols: 4, rows: 1)
        case .five: return (cols: 5, rows: 1)
        case .tenGrid: return (cols: 5, rows: 2)
        }
    }

    /// Сколько окон помещается в раскладку; лента берёт все (nil).
    static func capacity(of mode: Mode) -> Int? { grid(of: mode).map { $0.cols * $0.rows } }

    /// Ниже этой высоты ячейку не даём: лоадер подменяет только ширину минимума окна,
    /// высоту Electron держит сам (тот же порог, что у деления столбца «под этим»).
    static let minCellHeight: CGFloat = 360

    /// Влезает ли раскладка на экран: ячейка не уже `minCellWidth` и не ниже
    /// `minCellHeight`. Лента влезает всегда — узкие ячейки она разводит по рядам сама.
    ///
    /// Зазор вычитается здесь же (критик WF77 п. 11): без него «влезает» у плитки и живая
    /// ячейка расходились ровно на `gap`, и плитка на грани начинала врать.
    static func fits(_ mode: Mode, in area: CGRect, minCellWidth: CGFloat,
                     gap: CGFloat = 0) -> Bool {
        guard let grid = grid(of: mode) else { return true }
        return (area.width - gap * CGFloat(grid.cols - 1)) / CGFloat(grid.cols) >= minCellWidth
            && (area.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows) >= minCellHeight
    }

    /// Годится ли раскладка при таком числе окон (#5800, слово Элвиса 08.09: «нажимаешь — и
    /// там должно быть: от количества окон меняются режимы доступные»). У сетки ячеек ровно
    /// столько, сколько задано: окон меньше — часть ячеек осталась бы пустой, экран дырявым,
    /// а окна узкими без нужды («здесь же вообще нету четырёх окон»). Лента считает ячейки
    /// по числу окон и годится всегда.
    static func suits(_ mode: Mode, windows: Int) -> Bool {
        guard let capacity = capacity(of: mode) else { return true }
        return windows >= capacity
    }

    /// Как окна стоят СЕЙЧАС — долями рабочей области (0…1; начало отсчёта — левый верхний
    /// угол области, y вниз, как в перевёрнутых координатах AX). По ним плитка «как сейчас»
    /// рисует настоящее положение окон (#5798, слово Элвиса 08.09: «"как сейчас" всегда же
    /// по-разному — там нужно отображать, как сейчас окна реально отображаются»).
    /// Что вылезло за край области — обрезается; окно на другом экране обрезается в ничто
    /// и в ответ не попадает вовсе.
    static func shapes(of frames: [CGRect], in area: CGRect) -> [CGRect] {
        guard area.width > 0, area.height > 0 else { return [] }
        return frames.compactMap { frame in
            let x0 = share(frame.minX - area.minX, of: area.width)
            let x1 = share(frame.maxX - area.minX, of: area.width)
            let y0 = share(frame.minY - area.minY, of: area.height)
            let y1 = share(frame.maxY - area.minY, of: area.height)
            guard x1 > x0, y1 > y0 else { return nil }
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }

    /// Доля отрезка в области, обрезанная её краями.
    private static func share(_ value: CGFloat, of size: CGFloat) -> CGFloat {
        min(max(value / size, 0), 1)
    }

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
    ///
    /// Рамок ровно `min(count, ёмкость)`: у «4», «5» и «5×2» сетка задана, окон меньше —
    /// лишние ячейки остаются пустыми (окна не растягиваем), окон больше — хвост рамок
    /// не получает и остаётся где стоял (слово Элвиса 08.09: «лишние не трогаем»).
    static func frames(count: Int, in area: CGRect, mode: Mode = .ribbon,
                       minCellWidth: CGFloat = minCellWidth, gap: CGFloat = 0) -> [CGRect] {
        guard count > 0, area.width > 0, area.height > 0 else { return [] }
        let taken = min(count, capacity(of: mode) ?? count)
        let cols: Int, rows: Int
        if let grid = grid(of: mode) {
            (cols, rows) = grid
        } else {
            cols = columns(count: taken, width: area.width, minCellWidth: minCellWidth)
            rows = Int(ceil(Double(taken) / Double(cols)))
        }
        return cells(cols: cols, rows: rows, count: taken, in: area, gap: gap)
    }

    /// Ячейки сетки `cols × rows` слева направо, сверху вниз — общая арифметика плиток,
    /// ленты и умной расстановки.
    ///
    /// Зазор (план WF77, слово Элвиса 20.09: «между окнами небольшие отступы — это
    /// специально») живёт ТОЛЬКО между окнами: у краёв рабочей области, сверху и снизу
    /// окна прижаты к ней встык. Отсюда ширина ячейки `(W − g·(k−1)) / k`, а столбец `i`
    /// начинается на `i·(ячейка + g)`. Умолчание 0 — прежние рамки остаются побайтно
    /// теми же (`area.width − 0` и `+ 0` рамку не двигают).
    static func cells(cols: Int, rows: Int, count: Int, in area: CGRect,
                      gap: CGFloat = 0) -> [CGRect] {
        guard count > 0, cols > 0, rows > 0 else { return [] }
        let room = CGSize(width: area.width - gap * CGFloat(cols - 1),
                          height: area.height - gap * CGFloat(rows - 1))
        return (0..<count).map { i in
            let col = CGFloat(i % cols), row = CGFloat(i / cols)
            let x0 = area.minX + (col * room.width / CGFloat(cols) + col * gap + 0.5).rounded(.down)
            let x1 = area.minX
                + ((col + 1) * room.width / CGFloat(cols) + col * gap + 0.5).rounded(.down)
            let y0 = area.minY + (row * room.height / CGFloat(rows) + row * gap + 0.5).rounded(.down)
            let y1 = area.minY
                + ((row + 1) * room.height / CGFloat(rows) + row * gap + 0.5).rounded(.down)
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }

    /// Порядок с НОВЫМ окном (план WF36): `order` — порядок существующих окон (индексы
    /// в массиве из `count` окон, как их отдал `order(of:)`), новое окно — индекс `count`
    /// (его дописывают в конец массива), `at` — его место в порядке.
    ///
    /// Зачем отдельная функция: новое окно рождается уступом от окна-источника
    /// (`popoutOrigin`, 40/40), и `order(of:)` по рамкам поставил бы его куда попало —
    /// «посередине» из этого не выходит. Здесь порядок ЗАДАЁТСЯ, а не вычисляется.
    static func insert(order: [Int], count: Int, at: Int) -> [Int] {
        var out = order.filter { $0 >= 0 && $0 < count }
        let place = min(max(at, 0), out.count)
        out.insert(count, at: place)
        return out
    }

    /// Место нового окна в порядке: слева — первым, справа — последним, посередине —
    /// ровно в середину, а при чётном числе окон ПРАВЕЕ середины (контракт плана WF36).
    /// Прочие места (деление столбца, точка) порядка не задают — для них середина.
    ///
    /// `columns` — сколько ячеек в ПЕРВОМ ряду раскладки: у сетки с рядами «посередине»
    /// значит середину первого ряда, а не всего порядка (#5560) — иначе окно, которое
    /// просили поставить посередине, уезжало во второй ряд («5×2» с девятью окнами давало
    /// место 5, то есть начало нижнего ряда). Раскладка без заданных рядов (лента) `columns`
    /// не задаёт, и середина считается по всему порядку, как раньше.
    static func insertIndex(of place: PimpPlace, count: Int, columns: Int? = nil) -> Int {
        switch place {
        case .left: return 0
        case .right: return count
        default:
            var slots = count + 1
            if let columns = columns, columns > 0 { slots = min(slots, columns) }
            return slots / 2
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

    // MARK: - умная расстановка (план WF77)

    /// Больше шести столбцов не делаем никогда (слово Элвиса 20.09: «Odyssey делим
    /// максимум на шесть частей»).
    static let maxColumns = 6

    /// Допуск «окно уже сидит в этой ячейке»: 8 pt, а не `frameTolerance` 2 — Electron
    /// зажимает ширину окна по своему минимуму, и окно, стоящее на месте, сходится с
    /// ячейкой не точка в точку (риск 1 плана WF77).
    static let sitTolerance: CGFloat = 8

    /// Потолок столбцов на этом экране: не больше `maxColumns` и не уже `minCellWidth`
    /// С УЧЁТОМ зазора (критик WF77 блокер 7: при gap 40 четвёртый столбец макбука дал бы
    /// 261 pt — Electron зажал бы окна друг на друга). Один столбец есть всегда.
    /// Числа Элвиса: Odyssey 3008 → 6, макбук 1205 при минимуме 280 → 4.
    static func cap(width: CGFloat, minCellWidth: CGFloat = minCellWidth,
                    gap: CGFloat = 0) -> Int {
        guard width > 0, minCellWidth > 0 else { return 1 }
        return max(1, min(maxColumns, Int(((width + gap) / (minCellWidth + gap)).rounded(.down))))
    }

    /// Сколько рядов держит экран: ячейка не ниже `minCellHeight` (критик WF77 зам. 8 —
    /// девять окон на макбуке в три ряда дали бы 267 pt, и повтор рамки этого не чинит).
    static func capRows(height: CGFloat, gap: CGFloat = 0) -> Int {
        guard height > 0 else { return 1 }
        return max(1, Int(((height + gap) / (minCellHeight + gap)).rounded(.down)))
    }

    /// Окно уже стоит в этой ячейке: все четыре стороны сошлись в пределах допуска.
    static func sits(_ frame: CGRect, in cell: CGRect,
                     tolerance: CGFloat = sitTolerance) -> Bool {
        abs(frame.minX - cell.minX) <= tolerance && abs(frame.minY - cell.minY) <= tolerance
            && abs(frame.maxX - cell.maxX) <= tolerance && abs(frame.maxY - cell.maxY) <= tolerance
    }

    /// Кто из окон уже сидит в ячейках этой сетки: окно → номер ячейки. Одну ячейку
    /// занимает одно окно — два окна друг на друге сеткой не считаются, второе пойдёт
    /// в свободную ячейку.
    static func seated(frames: [CGRect], in cells: [CGRect],
                       tolerance: CGFloat = sitTolerance) -> [Int: Int] {
        var out: [Int: Int] = [:]
        var busy = Set<Int>()
        for index in frames.indices {
            guard let cell = cells.indices.first(where: {
                !busy.contains($0) && sits(frames[index], in: cells[$0], tolerance: tolerance)
            }) else { continue }
            out[index] = cell
            busy.insert(cell)
        }
        return out
    }

    /// Куда селить неприкаянных: занятые ячейки обязаны остаться подряд, без дыры
    /// посередине (критик WF77 зам. 6; слово Элвиса «по ширине идут по очереди слева
    /// направо»). Берём самый левый непрерывный отрезок из `count` ячеек, в который
    /// попадают все занятые, и отдаём его свободные ячейки; такого отрезка нет (занятые
    /// разошлись шире) — просто все свободные слева направо.
    static func freeCells(count: Int, cells: Int, taken: Set<Int>) -> [Int] {
        guard cells > 0 else { return [] }
        let free = (0..<cells).filter { !taken.contains($0) }
        let length = min(max(count, 0), cells)
        guard length > 0, let lo = taken.min(), let hi = taken.max() else { return free }
        let start = max(0, hi - length + 1)
        guard start <= lo else { return free }
        return free.filter { $0 >= start && $0 < start + length }
    }

    /// Умная расстановка на ОДНОМ экране (план WF77, слова Элвиса 20.09: «окна, которые
    /// уже стояли на месте, никуда не переводить; есть свободное место и одно-два окна
    /// болтаются неприкаянно — заполни ими свободное место»).
    ///
    /// Отдаёт итоговую рамку КАЖДОМУ окну в порядке входного массива: сидящему — его
    /// собственную (его не трогают вовсе), неприкаянному — свободную ячейку, лишнему
    /// сверх ёмкости сетки — тоже собственную («лишние не трогаем», слово Элвиса 08.09).
    ///
    /// Сетка выбирается так: рядов столько, сколько нужно и сколько держит высота;
    /// столбцов — от «меньше уже не влезет» до потолка экрана, и побеждает тот вариант,
    /// где больше окон УЖЕ сидит. Сетку шире минимальной берём, только когда сидит не
    /// меньше половины окон: одно случайно совпавшее окно сетку не диктует. Ничья и
    /// «никто не сидит» — наименьшее число столбцов, окна делят экран поровну.
    ///
    /// `order` — НАВЯЗАННЫЙ порядок (индексы входного массива): новое окно «слева» и
    /// «посередине» просит конкретное место, и тогда окна кладутся подряд, а «сидит»
    /// уже никого не держит. nil — обычный путь.
    static func smart(frames: [CGRect], in area: CGRect,
                      minCellWidth: CGFloat = minCellWidth, gap: CGFloat = 0,
                      order: [Int]? = nil, tolerance: CGFloat = sitTolerance) -> [CGRect] {
        guard !frames.isEmpty, area.width > 0, area.height > 0 else { return frames }
        let top = cap(width: area.width, minCellWidth: minCellWidth, gap: gap)
        let rows = min(capRows(height: area.height, gap: gap),
                       Int(ceil(Double(frames.count) / Double(top))))
        let least = min(top, max(1, Int(ceil(Double(frames.count) / Double(rows)))))
        var best = (columns: least, sitting: [Int: Int]())
        for columns in least...top {
            let grid = cells(cols: columns, rows: rows, count: columns * rows, in: area, gap: gap)
            let sitting = seated(frames: frames, in: grid, tolerance: tolerance)
            // Порог половины: сетку шире минимальной оправдывают только сидящие окна.
            if columns > least && sitting.count * 2 < frames.count { continue }
            if sitting.count > best.sitting.count { best = (columns, sitting) }
        }
        let grid = cells(cols: best.columns, rows: rows, count: best.columns * rows,
                         in: area, gap: gap)
        var out = frames
        if let order = order {
            var queue: [Int] = []
            var named = Set<Int>()
            for index in order where frames.indices.contains(index) {
                guard named.insert(index).inserted else { continue }
                queue.append(index)
            }
            // Окно, которого в порядке не назвали, встаёт за названными — по своему месту.
            queue += ArrangeLayout.order(of: frames).filter { !named.contains($0) }
            for (cell, index) in zip(grid.indices, queue) { out[index] = grid[cell] }
            return out
        }
        let restless = frames.indices.filter { best.sitting[$0] == nil }
        let free = freeCells(count: frames.count, cells: grid.count,
                             taken: Set(best.sitting.values))
        // Неприкаянные упорядочены ПО СЕБЕ (замечание критика WF77): сидящие в их счёте
        // не участвуют, иначе порядок зависел бы от окон, которых мы не двигаем.
        let queue = ArrangeLayout.order(of: restless.map { frames[$0] }).map { restless[$0] }
        for (index, cell) in zip(queue, free) { out[index] = grid[cell] }
        return out
    }

    /// То же на НЕСКОЛЬКИХ экранах: окно считается на том экране, где лежит центр его
    /// рамки, и на другой не переезжает (решение 2 плана WF77). `screens` — пары «полная
    /// рамка экрана (по ней ловится центр) — рабочая область (по ней считается сетка)».
    static func smart(frames: [CGRect], screens: [(full: CGRect, usable: CGRect)],
                      minCellWidth: CGFloat = minCellWidth, gap: CGFloat = 0,
                      order: [Int]? = nil, anchor: Int? = nil) -> [CGRect] {
        guard !frames.isEmpty, !screens.isEmpty else { return frames }
        let home = Screens.assign(screens: screens.map { $0.full }, frames: frames)
        var out = frames
        for screen in screens.indices {
            let mine = frames.indices.filter { home[$0] == screen }
            guard !mine.isEmpty else { continue }
            // Порядок навязан ради НОВОГО окна (`anchor`) — только его экрану: на другом
            // мониторе стоящие окна не перекладываем (проверка WF77, блокер 2). Якоря нет
            // (`arrange --order`) — порядок просили для всех экранов.
            let imposed = anchor.map { frames.indices.contains($0) && home[$0] == screen } ?? true
            let inner = imposed ? order.map { named in named.compactMap { mine.firstIndex(of: $0) } } : nil
            let placed = smart(frames: mine.map { frames[$0] }, in: screens[screen].usable,
                               minCellWidth: minCellWidth, gap: gap, order: inner)
            for (slot, index) in mine.enumerated() { out[index] = placed[slot] }
        }
        return out
    }
}
