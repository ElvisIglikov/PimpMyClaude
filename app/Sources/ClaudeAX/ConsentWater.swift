import CoreGraphics
import Foundation

// Окно доступа macOS — «окошко из воды» (WF98 Б5, #7766, макет `docs/12.html`, кадры 2.1 и 3.1).
// Слово Элвиса 26.09 ~07:05: как живой кадр 2.1, пузырёк у мыши тянется с физикой, цвет фиолетовый;
// перетекание между мониторами (3.1) — да; на одном мониторе маяк не нужен — окно запроса и так на виду.
//
// Здесь только расчёт — без окон и без Metal, чтобы гонять тестами: физика (порт `upRec`/`upOther`
// макета: пружины, «бульк», отрыв, капли через край монитора), раскладка окон-слоёв вокруг окна
// запроса (решение 12.5: над его прямоугольником и 3 pt запаса — ни одного нашего окна) и звук.
// Рисование и окна — `ConsentWaterView.swift`.
//
// Координаты — CG: pt, начало в левом верхнем углу главного монитора, y вниз (как в макете и как у
// `CGWindowListCopyWindowInfo`).

/// Размеры в pt — как `K` макета 12.
enum ConsentWaterK {
    /// Зазор до рамки, толщина рамки, скругление внутреннего края.
    static let gap: CGFloat = 8
    static let thick: CGFloat = 7
    static let rin: CGFloat = 16
    /// Запас вокруг окна запроса, куда не кладём ни одного своего окна.
    static let hole: CGFloat = 3
    /// Окошко у курсора, радиус его углов, отступ от курсора.
    static let plW: CGFloat = 230
    static let plH: CGFloat = 64
    static let plR: CGFloat = 22
    static let pad: CGFloat = 22
    /// Окошко целиком (стрелка, подписи, тело) тем крупнее, чем дальше курсор от окна запроса (#8111, #8122 —
    /// «надо, чтобы… весь объект этот увеличился со шрифтами и со всем остальным»; слово Элвиса 29.09: «чем он дальше…
    /// тем больше эта стрелочка… раза два больше… плавно нарастала»): ×1 ближе `reachNear`, ×`reachMax` дальше
    /// `reachFar`, между ними плавно. Потолок ×1,4, не ×2 (#8132, слово Элвиса 29.09: «слишком большая стала… конечный
    /// размер её пусть будет не таким большим, как сейчас»).
    static let reachNear: CGFloat = 120
    static let reachFar: CGFloat = 900
    static let reachMax: CGFloat = 1.4
    /// Запас окна-панели вокруг окошка: крупной стрелке есть куда вырасти.
    static let plMargin: CGFloat = 44
    /// «Бульк» ближе этого к рамке, отрыв — дальше этого.
    static let mIn: CGFloat = 36
    static let mOut: CGFloat = 230
    /// Потолки шейдера.
    static let maxCircles = 12
    static let maxRings = 4
    /// Запас рисования вокруг форм — свечение и тёмная кайма.
    static let glow: CGFloat = 40
}

// MARK: - пружины и геометрия

/// Пружина одного числа; шаг дробится до 240 Гц, как `sp1` макета.
struct WaterSpring1: Equatable {
    var x: CGFloat
    var v: CGFloat = 0

    mutating func step(to target: CGFloat, w: CGFloat, z: CGFloat, dt: CGFloat) {
        let n = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / CGFloat(n)
        for _ in 0..<n {
            v += (w * w * (target - x) - 2 * z * w * v) * h
            x += v * h
        }
        // Почти пришла — ставим точно: спокойный кадр повторяется, и его можно не перерисовывать.
        if abs(target - x) < 1e-5 && abs(v) < 1e-4 {
            x = target
            v = 0
        }
    }
}

/// Пружина точки, `sp2` макета.
struct WaterSpring2: Equatable {
    var x: CGFloat = 0, y: CGFloat = 0, vx: CGFloat = 0, vy: CGFloat = 0

    mutating func step(to tx: CGFloat, _ ty: CGFloat, w: CGFloat, z: CGFloat, dt: CGFloat) {
        let n = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / CGFloat(n)
        for _ in 0..<n {
            vx += (w * w * (tx - x) - 2 * z * w * vx) * h
            vy += (w * w * (ty - y) - 2 * z * w * vy) * h
            x += vx * h
            y += vy * h
        }
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
}

/// Точка на краю скруглённого прямоугольника и нормаль наружу.
struct WaterEdge: Equatable {
    var x: CGFloat, y: CGFloat, nx: CGFloat, ny: CGFloat
}

enum WaterGeo {
    static let tau = CGFloat.pi * 2

    /// `clamp` макета: сперва нижняя граница, потом верхняя (при a > b побеждает a).
    static func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { v < a ? a : (v > b ? b : v) }

    static func smooth(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = clamp((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Кратчайшая разница углов b − a в (−π, π].
    static func angleDelta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = (b - a).truncatingRemainder(dividingBy: tau)
        if d > .pi { d -= tau }
        if d < -.pi { d += tau }
        return d
    }

    static func grow(_ r: CGRect, _ m: CGFloat) -> CGRect { r.insetBy(dx: -m, dy: -m) }

    /// Расстояние от точки до прямоугольника (0 — внутри).
    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    /// Зазор между прямоугольниками (0 — касаются или пересекаются).
    static func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(max(b.minX - a.maxX, a.minX - b.maxX, 0), max(b.minY - a.maxY, a.minY - b.maxY, 0))
    }

    /// Пересечение с ненулевой площадью (касание краем — не пересечение), `hit` макета.
    static func hit(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    /// Точка внутри или на краю, `inR` макета.
    static func inside(_ p: CGPoint, _ r: CGRect) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    /// Ближайшая точка на границе скруглённого прямоугольника и нормаль наружу, `edgePtR`.
    static func edge(_ p: CGPoint, _ r: CGRect, _ rad: CGFloat) -> WaterEdge {
        let ix = r.minX + rad, iy = r.minY + rad
        let iw = max(r.width - 2 * rad, 0), ih = max(r.height - 2 * rad, 0)
        let qx = clamp(p.x, ix, ix + iw), qy = clamp(p.y, iy, iy + ih)
        let dx = p.x - qx, dy = p.y - qy, length = hypot(dx, dy)
        if length > 1e-4 {
            return WaterEdge(x: qx + dx / length * rad, y: qy + dy / length * rad, nx: dx / length, ny: dy / length)
        }
        let l = p.x - r.minX, rr = r.maxX - p.x, t = p.y - r.minY, b = r.maxY - p.y
        let m = min(l, rr, t, b)
        if m == l { return WaterEdge(x: r.minX, y: p.y, nx: -1, ny: 0) }
        if m == rr { return WaterEdge(x: r.maxX, y: p.y, nx: 1, ny: 0) }
        if m == t { return WaterEdge(x: p.x, y: r.minY, nx: 0, ny: -1) }
        return WaterEdge(x: p.x, y: r.maxY, nx: 0, ny: 1)
    }

    /// Выдавить прямоугольник (центр x, y, полуразмеры pw, ph) из зоны по кратчайшей оси.
    /// Ось: 0 — не задел, 1 — по x, 2 — по y.
    static func pushOut(_ x: CGFloat, _ y: CGFloat, _ pw: CGFloat, _ ph: CGFloat,
                        _ zone: CGRect) -> (x: CGFloat, y: CGFloat, axis: Int) {
        let l = (x + pw) - zone.minX, r = zone.maxX - (x - pw), t = (y + ph) - zone.minY, b = zone.maxY - (y - ph)
        if l <= 0 || r <= 0 || t <= 0 || b <= 0 { return (x, y, 0) }
        let m = min(l, r, t, b)
        if m == l { return (x - l, y, 1) }
        if m == r { return (x + r, y, 1) }
        if m == t { return (x, y - t, 2) }
        return (x, y + b, 2)
    }

    /// Место окошка: в пределах `bounds` и вне зоны; с ближней стороны не выходит — пробуем остальные.
    static func placeOut(_ x: CGFloat, _ y: CGFloat, _ pw: CGFloat, _ ph: CGFloat,
                         zone: CGRect, bounds b: CGRect) -> CGPoint {
        let cl = { (x: CGFloat, y: CGFloat) -> CGPoint in
            CGPoint(x: clamp(x, b.minX + pw, b.maxX - pw), y: clamp(y, b.minY + ph, b.maxY - ph))
        }
        let p = cl(x, y)
        let o = pushOut(p.x, p.y, pw, ph, zone)
        if o.axis == 0 { return p }
        let l = (p.x + pw) - zone.minX, r = zone.maxX - (p.x - pw)
        let t = (p.y + ph) - zone.minY, bt = zone.maxY - (p.y - ph)
        let tries: [(CGFloat, CGFloat, CGFloat)] = [(p.x - l, p.y, l), (p.x + r, p.y, r), (p.x, p.y - t, t), (p.x, p.y + bt, bt)]
        for k in tries.sorted(by: { $0.2 < $1.2 }) {
            let q = cl(k.0, k.1)
            if pushOut(q.x, q.y, pw, ph, zone).axis == 0 { return q }
        }
        return CGPoint(x: o.x, y: o.y)
    }

    /// Где луч c → T выходит из прямоугольника A (край монитора курсора).
    static func exitPoint(_ c: CGPoint, _ target: CGPoint, _ a: CGRect) -> CGPoint {
        var t: CGFloat = 1
        let dx = target.x - c.x, dy = target.y - c.y
        if dx > 0 { t = min(t, (a.maxX - c.x) / dx) } else if dx < 0 { t = min(t, (a.minX - c.x) / dx) }
        if dy > 0 { t = min(t, (a.maxY - c.y) / dy) } else if dy < 0 { t = min(t, (a.minY - c.y) / dy) }
        t = max(t, 0)
        return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    }

    /// Где отрезок E → T входит в прямоугольник B (край монитора запроса); не входит — nil.
    static func enterPoint(_ e: CGPoint, _ target: CGPoint, _ b: CGRect) -> CGPoint? {
        var t0: CGFloat = 0, t1: CGFloat = 1
        let d = [target.x - e.x, target.y - e.y], o = [e.x, e.y]
        let lo = [b.minX, b.minY], hi = [b.maxX, b.maxY]
        for i in 0..<2 {
            if abs(d[i]) < 1e-6 {
                if o[i] < lo[i] || o[i] > hi[i] { return nil }
                continue
            }
            var a = (lo[i] - o[i]) / d[i], c = (hi[i] - o[i]) / d[i]
            if a > c { swap(&a, &c) }
            t0 = max(t0, a)
            t1 = min(t1, c)
        }
        return t0 <= t1 ? CGPoint(x: e.x + d[0] * t0, y: e.y + d[1] * t0) : nil
    }

    /// Номер прямоугольника, где точка; нет такого — ближайший; список пуст — nil.
    static func index(of p: CGPoint, in rects: [CGRect]) -> Int? {
        if let i = rects.firstIndex(where: { inside(p, $0) }) { return i }
        return rects.indices.min { distance(p, rects[$0]) < distance(p, rects[$1]) }
    }

    static func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
}

/// Детерминированный генератор для брызг: тесты повторяемы, живьём — сид от времени.
struct WaterRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    /// Число в [0, 1).
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

// MARK: - кадр

/// Жидкая рамка вокруг одного окна запроса.
struct WaterRing: Equatable {
    var rect: CGRect
    var gap: CGFloat
    var thick: CGFloat
    var rin: CGFloat
    var amp: CGFloat
}

/// Капля поля: центр и радиус.
struct WaterCircle: Equatable {
    var x: CGFloat, y: CGFloat, r: CGFloat
}

/// Окошко у курсора: стрелка и две строки. Рисует его окно-панель, тело — вода шейдера.
struct WaterPlaque: Equatable {
    var center: CGPoint = .zero
    /// Масштаб «вырастания» (0…1).
    var zoom: CGFloat = 0
    var opacity: CGFloat = 0
    /// Угол стрелки, радианы, y вниз (0 — вправо, π/2 — вниз).
    var angle: CGFloat = 0
    /// «Дыхание» стрелки.
    var breathe: CGFloat = 1
    /// Размер окошка целиком от дали до окна запроса: 1…`ConsentWaterK.reachMax` (#8111, #8122).
    var reach: CGFloat = 1
    var line2 = ConsentWaterSim.lineClick
    /// Спокойный вид: своё тёмное стекло с фиолетовой каймой вместо воды.
    var solid = false

    /// Окно-панель окошка (полный размер, вырастание рисуется внутри).
    var panelRect: CGRect {
        CGRect(x: center.x - ConsentWaterK.plW * reach / 2, y: center.y - ConsentWaterK.plH * reach / 2,
               width: ConsentWaterK.plW * reach, height: ConsentWaterK.plH * reach)
    }

    /// Показывать ли панель и ловить ли ею клик.
    var shown: Bool { opacity > 0.01 }
    var clickable: Bool { opacity > 0.5 }
}

/// Всё, что нужно нарисовать в одном кадре.
struct ConsentWaterFrame: Equatable {
    /// Первая — у ближайшего окна запроса (с волнами «булька»).
    var rings: [WaterRing] = []
    /// Тело окошка из воды: прямоугольник (нет — пусто) и радиус углов.
    var box: CGRect?
    var boxR: CGFloat = 0
    var circles: [WaterCircle] = []
    /// Мягкость слияния (0,001 — без перемычек).
    var k: CGFloat = 0.001
    var hole: CGFloat = ConsentWaterK.hole
    /// Две волны «булька»: радиус и яркость каждой.
    var wave: [CGFloat] = [0, 0, 0, 0]
    var plaque = WaterPlaque()
    /// В этом кадре был «бульк» — позвать звук.
    var blub = false
    /// Окно запроса на другом мониторе, чем курсор.
    var otherScreen = false
    /// Спокойный вид («Уменьшить движение»).
    var calm = false
    /// Где что-то нарисовано (со свечением) — рисовать только тут; пусто — кадр пустой.
    var bounds: CGRect = .null
    /// Ответили, всё стекло — окна можно убирать.
    var finished = false

    /// Шейдерные параметры для окна-слоя с левым верхним углом `origin` (CG) и `scale` пикселей на pt.
    /// Раскладка — 25 × float4, её же читает `ConsentWaterShader.source`.
    func uniforms(origin: CGPoint, scale: CGFloat, light: Bool) -> [SIMD4<Float>] {
        var u = [SIMD4<Float>](repeating: .zero, count: ConsentWaterFrame.uniformCount)
        let f = { (v: CGFloat) in Float(v) }
        u[0] = SIMD4(f(origin.x), f(origin.y), f(scale), f(hole))
        u[1] = SIMD4(f(max(k, 0.001)), f(boxR), light ? 1 : 0, light ? 0.84 : 0.74)
        if let box = box { u[2] = SIMD4(f(box.midX), f(box.midY), f(box.width / 2), f(box.height / 2)) }
        u[3] = SIMD4(f(wave[0]), f(wave[1]), f(wave[2]), f(wave[3]))
        let rings = Array(self.rings.prefix(ConsentWaterK.maxRings))
        let circles = Array(self.circles.prefix(ConsentWaterK.maxCircles))
        u[4] = SIMD4(Float(rings.count), Float(circles.count), 0, 0)
        for (i, ring) in rings.enumerated() {
            u[5 + i] = SIMD4(f(ring.rect.midX), f(ring.rect.midY), f(ring.rect.width / 2), f(ring.rect.height / 2))
            u[9 + i] = SIMD4(f(ring.gap), f(ring.thick), f(ring.rin), f(ring.amp))
        }
        for (i, c) in circles.enumerated() { u[13 + i] = SIMD4(f(c.x), f(c.y), f(c.r), 0) }
        return u
    }

    static let uniformCount = 25
}

// MARK: - физика

/// Вход одного шага: где курсор, окна запроса, мониторы (всё в CG).
struct ConsentWaterInput {
    var cursor: CGPoint
    var targets: [CGRect]
    /// Мониторы целиком и их видимая часть (без строки меню и Dock), в одном порядке.
    var screens: [CGRect]
    var visible: [CGRect]
    /// Запрос ещё висит; false — всё стекает.
    var alive = true
}

/// Порт физики макета 12 (`upRec` — тот же монитор, `upOther` — запрос на соседнем).
struct ConsentWaterSim {
    static let lineClick = "клик — курсор к окну"
    static let lineOther = "на соседнем мониторе"

    /// Спокойный вид («Уменьшить движение», вид 4.2): без пружин, волн и брызг.
    var calm = false

    private(set) var t: CGFloat = 0
    private(set) var alive = true
    private(set) var merged = false
    private(set) var edgeMerged = false
    private var q: WaterEdge?
    private var qr: CGPoint?
    private var placed = false
    private var anchor: CGPoint?
    private var pl = WaterSpring2()
    private var th = WaterSpring1(x: 0)
    private var thReady = false
    private var rs = WaterSpring1(x: 1)
    private var pz = WaterSpring1(x: 0)
    private var amp = WaterSpring1(x: 0)
    private var wx = WaterSpring1(x: 1)
    private var wy = WaterSpring1(x: 1)
    private var bump = WaterSpring1(x: 0)
    private var tg = WaterSpring2()
    private var tr = WaterSpring1(x: 0)
    private var tgReady = false
    private var waves: [CGFloat] = []
    private struct Drip { var x, y, vx, vy, r, age, life: CGFloat }
    private struct StreamDrop { var d, r: CGFloat }
    private var drips: [Drip] = []
    private var stream: [StreamDrop] = []
    private var streamAcc: CGFloat = 0
    private var lastScreen: Int?
    private var entry: CGPoint?
    private var lastTarget: CGRect?
    private var circles: [WaterCircle] = []
    private var blub = false
    private var random: WaterRandom

    init(calm: Bool = false, seed: UInt64 = 1) {
        self.calm = calm
        random = WaterRandom(seed: seed)
    }

    mutating func step(dt rawDt: CGFloat, _ input: ConsentWaterInput) -> ConsentWaterFrame {
        let dt = min(max(rawDt, 0), 0.05)
        t += dt
        blub = false
        if input.alive && !alive { merged = false }
        alive = input.alive
        waves = waves.map { $0 + dt / 0.9 }.filter { $0 < 1 }
        let fade = exp(-4 * dt)
        drips = drips.map { d in
            Drip(x: d.x + d.vx * dt, y: d.y + d.vy * dt, vx: d.vx * fade, vy: d.vy * fade, r: d.r, age: d.age + dt, life: d.life)
        }.filter { $0.age < $0.life }

        let c = input.cursor
        let target = input.targets.min { WaterGeo.distance(c, $0) < WaterGeo.distance(c, $1) } ?? lastTarget
        guard let rect = target, !input.screens.isEmpty else { return ConsentWaterFrame(calm: calm, finished: true) }
        lastTarget = rect
        let far = WaterGeo.smooth(ConsentWaterK.reachNear, ConsentWaterK.reachFar, WaterGeo.distance(c, rect))
        let reach = 1 + (ConsentWaterK.reachMax - 1) * far
        if calm { rs = WaterSpring1(x: reach) } else { rs.step(to: reach, w: 4, z: 1, dt: dt) }
        let screens = input.screens
        let visible = input.visible.count == screens.count ? input.visible : screens
        let cs = WaterGeo.index(of: c, in: screens) ?? 0
        let ts = WaterGeo.index(of: WaterGeo.center(rect), in: screens) ?? 0
        if cs != lastScreen {
            if lastScreen != nil {
                let from = cs == ts ? (entry ?? c) : c
                pl = WaterSpring2(x: from.x, y: from.y)
                pz = WaterSpring1(x: 0.05)
                edgeMerged = false
                merged = false
            }
            lastScreen = cs
        }
        var frame: ConsentWaterFrame
        if cs == ts {
            edgeMerged = false
            stream = []
            frame = sameScreen(dt: dt, cursor: c, rect: rect, bounds: visible[cs])
        } else {
            frame = otherScreen(dt: dt, cursor: c, rect: rect, bounds: visible[cs], screen: screens[cs], targetScreen: screens[ts])
        }
        // Остальные окна запроса — своя рамка, без языка и волн.
        for other in input.targets where other != rect {
            var ring = frame.rings[0]
            ring.rect = other
            frame.rings.append(ring)
        }
        // Окно-панель окошка не ложится ни на одно окно запроса с запасом (решение 12.5).
        let holes = input.targets.map { WaterGeo.grow($0, ConsentWaterK.hole) } + [WaterGeo.grow(rect, ConsentWaterK.hole)]
        if holes.contains(where: { WaterGeo.hit($0, frame.plaque.panelRect) }) { frame.plaque.opacity = 0 }
        frame.blub = blub
        frame.calm = calm
        frame.bounds = contentBounds(frame)
        frame.finished = !alive && amp.x < 0.02 && pz.x < 0.02 && drips.isEmpty && waves.isEmpty && stream.isEmpty
        return frame
    }

    // MARK: общее

    private mutating func add(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        if circles.count < ConsentWaterK.maxCircles && r > 0.2 { circles.append(WaterCircle(x: x, y: y, r: r)) }
    }

    private var waveParams: [CGFloat] {
        var o: [CGFloat] = [0, 0, 0, 0]
        var j = 0
        for a in waves where a >= 0 && j <= 1 {
            o[j * 2] = (1 - pow(1 - a, 3)) * 80
            o[j * 2 + 1] = pow(1 - a, 1.5) * 0.9
            j += 1
        }
        return o
    }

    private mutating func splash(_ q: WaterEdge, count: Int = 5) {
        guard !calm else { return }
        for _ in 0..<count {
            let a = atan2(q.ny, q.nx) + (random.next() - 0.5) * 2.2
            let v = 90 + random.next() * 150
            drips.append(Drip(x: q.x + q.nx * 4, y: q.y + q.ny * 4, vx: cos(a) * v, vy: sin(a) * v,
                              r: 3 + random.next() * 3.5, age: 0, life: 0.45 + random.next() * 0.25))
        }
    }

    private mutating func addDrips() {
        for d in drips { add(d.x, d.y, d.r * (1 - d.age / d.life)) }
    }

    private mutating func merge(ring: CGRect, radius: CGFloat, cursor: CGPoint) {
        merged = true
        q = WaterGeo.edge(WaterGeo.inside(cursor, ring) && placed ? pl.point : cursor, ring, radius)
        if !calm, let q = q {
            bump.v += 14
            waves.append(contentsOf: [0, -0.16])
            splash(q)
        }
        blub = true
    }

    private mutating func split() {
        merged = false
        if !calm, let q = q { splash(q, count: 3) }
    }

    /// Стрелка к окну, место окошка на орбите вокруг курсора, привязь.
    private mutating func orbit(dt: CGFloat, cursor c: CGPoint, target: CGPoint, bounds: CGRect,
                                zone: CGRect) -> (x: CGFloat, y: CGFloat, pw: CGFloat, ph: CGFloat) {
        let phi = atan2(target.y - c.y, target.x - c.x)
        if calm || !thReady {
            th = WaterSpring1(x: phi)
            thReady = true
        } else {
            th.step(to: th.x + WaterGeo.angleDelta(th.x, phi), w: 8.5, z: 0.5, dt: dt)
        }
        // Окошко растёт с далью целиком (#8122) — и орбита вокруг курсора по его настоящему размеру.
        let pw = ConsentWaterK.plW * rs.x / 2, ph = ConsentWaterK.plH * rs.x / 2, ux = cos(th.x), uy = sin(th.x)
        let orb = min(pw / max(abs(ux), 1e-3), ph / max(abs(uy), 1e-3)) + ConsentWaterK.pad
        var a = CGPoint(x: c.x + ux * orb, y: c.y + uy * orb)
        let now = CGRect(x: pl.x - pw, y: pl.y - ph, width: 2 * pw, height: 2 * ph)
        // Пока окошко растёт или сжимается (#8122), старая точка не держит: выросшее наехало бы на курсор.
        let resizing = abs(rs.v) > 1e-3
        if placed, !resizing, let anchor = anchor, !merged, !edgeMerged, WaterGeo.distance(c, now) < ConsentWaterK.pad * 0.7 {
            a = anchor
        }
        a = WaterGeo.placeOut(a.x, a.y, pw, ph, zone: zone, bounds: bounds)
        anchor = a
        return (a.x, a.y, pw, ph)
    }

    private mutating func moveBody(dt: CGFloat, to tx: CGFloat, _ ty: CGFloat) {
        if !placed {
            pl = WaterSpring2(x: tx, y: ty)
            placed = true
        }
        if calm { pl = WaterSpring2(x: tx, y: ty) } else { pl.step(to: tx, ty, w: 9, z: 0.62, dt: dt) }
        let vx = abs(pl.vx) / 600, vy = abs(pl.vy) / 600
        wx.step(to: calm ? 1 : 1 + 0.1 * tanh(vx) - 0.05 * tanh(vy), w: 13, z: 0.3, dt: dt)
        wy.step(to: calm ? 1 : 1 + 0.1 * tanh(vy) - 0.05 * tanh(vx), w: 13, z: 0.3, dt: dt)
        amp.step(to: alive ? 1 : 0, w: calm ? 40 : 7, z: calm ? 1 : 0.45, dt: dt)
        bump.step(to: 0, w: 6, z: 0.3, dt: dt)
    }

    private func ringThickness() -> CGFloat {
        let bp = max(bump.x, 0)
        return ConsentWaterK.thick * (calm ? 1 : 1 + 0.1 * sin(t * WaterGeo.tau / 2.2)) * (1 + 0.25 * bp)
    }

    private func plaque(pw: CGFloat, ph: CGFloat, pz: CGFloat, rect: CGRect, line2: String) -> WaterPlaque {
        let box = CGRect(x: pl.x - pw * pz, y: pl.y - ph * pz, width: 2 * pw * pz, height: 2 * ph * pz)
        let over = WaterGeo.hit(box, WaterGeo.grow(rect, 2))
        let opacity: CGFloat = calm
            ? ((alive && !merged && !edgeMerged && !over) ? 1 : 0)
            : ((merged || edgeMerged || !alive || over) ? 0 : WaterGeo.smooth(0.45, 0.9, pz))
        return WaterPlaque(center: pl.point, zoom: calm ? 1 : min(max(pz, 0.01), 1), opacity: opacity, angle: th.x,
                           breathe: calm ? 1 : 1 + 0.05 * sin(t * WaterGeo.tau / 1.6), reach: rs.x, line2: line2,
                           solid: calm)
    }

    // MARK: 2.1 — запрос на мониторе курсора

    private mutating func sameScreen(dt: CGFloat, cursor c: CGPoint, rect r: CGRect, bounds b: CGRect) -> ConsentWaterFrame {
        let K = ConsentWaterK.self
        let ro = WaterGeo.grow(r, K.gap + K.thick), rro = K.rin + K.thick
        let center = WaterGeo.center(r), dc = WaterGeo.distance(c, ro)
        if alive {
            if !merged && dc < K.mIn { merge(ring: ro, radius: rro, cursor: c) } else if merged && dc > K.mOut { split() }
        }
        if merged {
            if !WaterGeo.inside(c, ro) || q == nil {
                q = WaterGeo.edge(c, ro, rro)
            } else if let rel = qr, let old = q {
                q = WaterEdge(x: r.minX + rel.x, y: r.minY + rel.y, nx: old.nx, ny: old.ny)
            }
            if let q = q { qr = CGPoint(x: q.x - r.minX, y: q.y - r.minY) }
        }
        var (tx, ty, pw, ph) = orbit(dt: dt, cursor: c, target: center, bounds: b, zone: WaterGeo.grow(ro, 6))
        if merged, let q = q {
            let p = max(pz.x, 0)
            let ext = min(pw * p / max(abs(q.nx), 1e-3), ph * p / max(abs(q.ny), 1e-3))
            tx = q.x + q.nx * ext * 0.8
            ty = q.y + q.ny * ext * 0.8
        }
        pz.step(to: (alive && !merged) ? 1 : 0, w: calm ? 40 : 10, z: calm ? 1 : 0.72, dt: dt)
        moveBody(dt: dt, to: tx, ty)
        let z = WaterGeo.clamp(pz.x, 0, 1.2), pwz = pw * wx.x * z, phz = ph * wy.x * z
        if !merged && alive {
            let o = WaterGeo.pushOut(pl.x, pl.y, pwz, phz, WaterGeo.grow(ro, 2))
            if o.axis != 0 {
                pl.x = o.x
                pl.y = o.y
                if o.axis == 1 { pl.vx = 0 } else { pl.vy = 0 }
            }
        }
        let plRect = CGRect(x: pl.x - pwz, y: pl.y - phz, width: 2 * pwz, height: 2 * phz)
        let gapPl = WaterGeo.gap(plRect, ro)
        let pull: CGFloat = (!calm && alive && !merged && z > 0.3) ? pow(WaterGeo.clamp(1 - gapPl / 300, 0, 1), 1.6) : 0
        if alive && !merged && gapPl < 8 && dc < 180 { merge(ring: ro, radius: rro, cursor: c) }
        let qT = merged ? (q ?? WaterGeo.edge(pl.point, ro, rro)) : WaterGeo.edge(pl.point, ro, rro)
        let bp = max(bump.x, 0)
        let ext = -3 + 24 * pull + 14 * bp, trad = 3 + 12 * pull + 9 * bp
        if !tgReady || calm {
            tg = WaterSpring2(x: qT.x, y: qT.y)
            tgReady = true
        }
        if !calm {
            tg.step(to: qT.x + qT.nx * ext, qT.y + qT.ny * ext, w: 7, z: 0.45, dt: dt)
            tr.step(to: trad, w: 9, z: 0.5, dt: dt)
        }
        circles = []
        if !calm && amp.x > 0.05 { add(tg.x, tg.y, tr.x * min(1, amp.x)) }
        if pull > 0.02 {
            let dx = qT.x - pl.x, dy = qT.y - pl.y, l = hypot(dx, dy) > 0 ? hypot(dx, dy) : 1
            let nx = dx / l, ny = dy / l
            let e = min(pwz / max(abs(nx), 1e-3), phz / max(abs(ny), 1e-3)) - 6 + 18 * pull
            add(pl.x + nx * e, pl.y + ny * e, (4 + 10 * pull) * z)
        }
        addDrips()
        var frame = ConsentWaterFrame()
        frame.rings = [WaterRing(rect: r, gap: K.gap, thick: ringThickness(), rin: K.rin, amp: max(amp.x, 0))]
        frame.box = (calm || z < 0.02) ? nil : plRect
        frame.boxR = K.plR * z
        frame.circles = circles
        frame.k = calm ? 0.001 : 8 + 24 * pull + 10 * bp
        frame.wave = waveParams
        frame.plaque = plaque(pw: pw, ph: ph, pz: z, rect: r, line2: ConsentWaterSim.lineClick)
        return frame
    }

    // MARK: 3.1 — запрос на соседнем мониторе

    private mutating func otherScreen(dt: CGFloat, cursor c: CGPoint, rect r: CGRect, bounds b: CGRect,
                                      screen a: CGRect, targetScreen bs: CGRect) -> ConsentWaterFrame {
        let K = ConsentWaterK.self
        merged = false
        let ro = WaterGeo.grow(r, K.gap + K.thick), rro = K.rin + K.thick, center = WaterGeo.center(r)
        let e = WaterGeo.exitPoint(c, center, a)
        let n = WaterGeo.enterPoint(e, center, bs) ?? CGPoint(x: bs.minX, y: WaterGeo.clamp(e.y, bs.minY, bs.maxY))
        entry = n
        let dE = hypot(e.x - c.x, e.y - c.y) > 0 ? hypot(e.x - c.x, e.y - c.y) : 1
        let inx = (c.x - e.x) / dE, iny = (c.y - e.y) / dE
        let pull: CGFloat = calm ? 0 : pow(WaterGeo.clamp(1 - dE / 1700, 0, 1), 1.2)
        let edgeM = alive && dE < 110
        if edgeM && !edgeMerged && !calm {
            bump.v += 10
            splash(WaterEdge(x: e.x, y: e.y, nx: inx, ny: iny), count: 4)
        }
        edgeMerged = edgeM
        var (tx, ty, pw, ph) = orbit(dt: dt, cursor: c, target: center, bounds: b,
                                     zone: CGRect(x: -1e6, y: -1e6, width: 0, height: 0))
        if edgeM {
            let p = max(pz.x, 0)
            tx = e.x + inx * ph * p * 0.8
            ty = e.y + iny * ph * p * 0.8
        }
        pz.step(to: (alive && !edgeM) ? 1 : 0, w: calm ? 40 : 10, z: calm ? 1 : 0.72, dt: dt)
        moveBody(dt: dt, to: tx, ty)
        let z = WaterGeo.clamp(pz.x, 0, 1.2), pwz = pw * wx.x * z, phz = ph * wy.x * z
        let bp = max(bump.x, 0), al: CGFloat = alive ? 1 : 0
        let qT = WaterGeo.edge(n, ro, rro), ext = -3 + 30 * pull
        if !tgReady || calm {
            tg = WaterSpring2(x: qT.x, y: qT.y)
            tgReady = true
        }
        if !calm {
            tg.step(to: qT.x + qT.nx * ext, qT.y + qT.ny * ext, w: 7, z: 0.45, dt: dt)
            tr.step(to: 3 + 14 * pull, w: 9, z: 0.5, dt: dt)
        }
        circles = []
        add(e.x, e.y, (12 + 20 * pull + (edgeM ? 12 : 0) + 8 * bp) * al)
        add(n.x, n.y, (10 + 12 * pull) * al)
        if !calm && amp.x > 0.05 { add(tg.x, tg.y, tr.x * min(1, amp.x)) }
        if pull > 0.03 && !edgeM {
            let dx = e.x - pl.x, dy = e.y - pl.y, l = hypot(dx, dy) > 0 ? hypot(dx, dy) : 1
            let nx = dx / l, ny = dy / l
            let ex = min(pwz / max(abs(nx), 1e-3), phz / max(abs(ny), 1e-3)) - 6 + 18 * pull
            add(pl.x + nx * ex, pl.y + ny * ex, (4 + 10 * pull) * z)
        }
        // Капли перетекают: край → тот монитор → язык рамки (в щели между мониторами их не видно).
        if !calm && alive {
            streamAcc += dt * (0.8 + 6 * pull + (edgeM ? 6 : 0))
            while streamAcc > 1 {
                streamAcc -= 1
                stream.append(StreamDrop(d: 0, r: 4.5 + 3 * pull + (edgeM ? 2 : 0)))
            }
        }
        let l1 = hypot(n.x - e.x, n.y - e.y), l2 = hypot(tg.x - n.x, tg.y - n.y), lt = l1 + l2
        stream = stream.map { StreamDrop(d: $0.d + dt * 1000, r: $0.r) }.filter { $0.d < lt }
        for s in stream {
            let x: CGFloat, y: CGFloat
            if s.d < l1 {
                let f = s.d / (l1 > 0 ? l1 : 1)
                x = e.x + (n.x - e.x) * f
                y = e.y + (n.y - e.y) * f
            } else {
                let f = (s.d - l1) / (l2 > 0 ? l2 : 1)
                x = n.x + (tg.x - n.x) * f
                y = n.y + (tg.y - n.y) * f
            }
            add(x, y, s.r * (1 - 0.5 * s.d / lt))
        }
        addDrips()
        var frame = ConsentWaterFrame()
        frame.rings = [WaterRing(rect: r, gap: K.gap, thick: ringThickness(), rin: K.rin, amp: max(amp.x, 0))]
        frame.box = (calm || z < 0.02) ? nil : CGRect(x: pl.x - pwz, y: pl.y - phz, width: 2 * pwz, height: 2 * phz)
        frame.boxR = K.plR * z
        frame.circles = circles
        frame.k = calm ? 0.001 : 10 + 22 * pull + 10 * bp
        frame.wave = waveParams
        frame.otherScreen = true
        frame.plaque = plaque(pw: pw, ph: ph, pz: z, rect: r, line2: ConsentWaterSim.lineOther)
        return frame
    }

    /// Где в кадре что-то есть, с запасом на свечение, кайму и волны.
    private func contentBounds(_ frame: ConsentWaterFrame) -> CGRect {
        var out = CGRect.null
        let glow = ConsentWaterK.glow
        for ring in frame.rings where ring.amp > 0.002 {
            let wave = max(frame.wave[0], frame.wave[2])
            out = out.union(WaterGeo.grow(ring.rect, ring.gap + ring.thick * 1.5 + wave + glow))
        }
        if let box = frame.box { out = out.union(WaterGeo.grow(box, glow)) }
        for c in frame.circles { out = out.union(CGRect(x: c.x - c.r, y: c.y - c.r, width: 2 * c.r, height: 2 * c.r).insetBy(dx: -glow, dy: -glow)) }
        return out
    }
}

// MARK: - раскладка окон-слоёв

/// Решение 12.5: не одно окно на экран, а куски экрана вокруг окон запроса. Над окном запроса и
/// 3 pt вокруг него нет ни одного нашего окна — macOS глушит клики по перекрытому окну запроса.
enum ConsentWaterLayout {
    /// Дырки — окна запроса с запасом, края наружу до целых pt.
    static func holes(_ targets: [CGRect]) -> [CGRect] {
        targets.map { r in
            let g = WaterGeo.grow(r, ConsentWaterK.hole)
            let x0 = g.minX.rounded(.down), y0 = g.minY.rounded(.down)
            return CGRect(x: x0, y: y0, width: g.maxX.rounded(.up) - x0, height: g.maxY.rounded(.up) - y0)
        }
    }

    /// Монитор минус дырки — прямоугольники полосами сверху вниз; одна дырка посреди — ровно четыре.
    static func pieces(of screen: CGRect, minus holes: [CGRect]) -> [CGRect] {
        let cut = holes.map { $0.intersection(screen) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        let ys = Array(Set([screen.minY, screen.maxY] + cut.flatMap { [$0.minY, $0.maxY] })).sorted()
        var out: [CGRect] = []
        for (y0, y1) in zip(ys, ys.dropFirst()) where y1 > y0 {
            let spans = cut.filter { $0.minY < y1 && $0.maxY > y0 }.map { ($0.minX, $0.maxX) }.sorted { $0.0 < $1.0 }
            var x = screen.minX
            for (a, b) in spans {
                if a > x { out.append(CGRect(x: x, y: y0, width: a - x, height: y1 - y0)) }
                x = max(x, b)
            }
            if x < screen.maxX { out.append(CGRect(x: x, y: y0, width: screen.maxX - x, height: y1 - y0)) }
        }
        // Полосы одной ширины встык — одним окном.
        var merged: [CGRect] = []
        for rect in out {
            if let i = merged.firstIndex(where: { $0.minX == rect.minX && $0.maxX == rect.maxX && $0.maxY == rect.minY }) {
                merged[i] = merged[i].union(rect)
            } else {
                merged.append(rect)
            }
        }
        return merged
    }

    /// Окна-слои: на мониторах с окнами запроса — куски вокруг дырок, на мониторе курсора — весь
    /// монитор (там окна запроса нет); прочие мониторы — без окон.
    static func windows(screens: [CGRect], targets: [CGRect], cursor: CGPoint) -> [CGRect] {
        let holes = self.holes(targets)
        let cursorScreen = WaterGeo.index(of: cursor, in: screens)
        var out: [CGRect] = []
        for (i, screen) in screens.enumerated() {
            let mine = holes.filter { WaterGeo.hit($0, screen) }
            if !mine.isEmpty {
                out += pieces(of: screen, minus: mine)
            } else if i == cursorScreen {
                out.append(screen)
            }
        }
        return out
    }
}

/// Решение, каким видом подсвечивать окна запроса.
enum ConsentBeaconStyle: String {
    /// Запроса нет.
    case idle
    /// Один монитор — окно запроса и так на виду, ничего не показываем (слово Элвиса 26.09 ~07:05).
    case single
    /// Окошко из воды (макет 12).
    case water
    /// Рамка и плашка WF91: выключатель `consentBeaconClassic` или Metal не завёлся.
    case classic

    static func choose(hasTargets: Bool, screenCount: Int, classic: Bool, waterAvailable: Bool) -> ConsentBeaconStyle {
        guard hasTargets else { return .idle }
        guard screenCount >= 2 else { return .single }
        return classic || !waterAvailable ? .classic : .water
    }
}

// MARK: - звук «бульк»

/// Синтез «блуп» макета: два синуса вверх, тихо. WAV в памяти, без файлов.
enum ConsentWaterSound {
    static let sampleRate = 44_100

    /// 16-бит моно WAV.
    static func wav() -> Data {
        let count = Int(0.2 * Double(sampleRate))
        var samples = [Double](repeating: 0, count: count)
        tone(&samples, start: 0, from: 240, to: 820, duration: 0.14, volume: 0.09)
        tone(&samples, start: 0.07, from: 420, to: 1150, duration: 0.1, volume: 0.045)
        var data = Data()
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        put32(UInt32(36 + count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        put32(16); put16(1); put16(1)
        put32(UInt32(sampleRate)); put32(UInt32(sampleRate * 2)); put16(2); put16(16)
        data.append(contentsOf: Array("data".utf8))
        put32(UInt32(count * 2))
        for s in samples { put16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767))) }
        return data
    }

    /// Синус с частотой вверх (экспонента за 70 % длины) и огибающей 12 мс вверх — экспонента вниз.
    private static func tone(_ out: inout [Double], start: Double, from f0: Double, to f1: Double,
                             duration: Double, volume: Double) {
        let rate = Double(sampleRate)
        var phase = 0.0
        let first = Int(start * rate), total = Int(duration * rate)
        for i in 0..<total where first + i < out.count {
            let t = Double(i) / rate
            let f = f0 * pow(f1 / f0, min(t / (duration * 0.7), 1))
            let gain = t < 0.012 ? 0.0001 * pow(volume / 0.0001, t / 0.012)
                                 : volume * pow(0.0001 / volume, (t - 0.012) / (duration - 0.012))
            phase += 2 * .pi * f / rate
            out[first + i] += sin(phase) * gain
        }
    }
}
