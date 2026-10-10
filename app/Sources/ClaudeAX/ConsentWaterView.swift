import AppKit
import Metal
import QuartzCore

// «Окошко из воды» на экране (WF98 Б5, макет 12): окна-слои с Metal-шейдером поля расстояний и
// окошко-панель у курсора. Расчёт — `ConsentWater.swift`; здесь только окна, рисование и звук.
//
// Слой — не одно окно на экран, а куски мониторов вокруг окон запроса (`ConsentWaterLayout`): над
// окном запроса и 3 pt вокруг него нашего нет ничего (решение 12.5). Все окна-слои рисуют одну
// картинку в общих координатах CG, поэтому шва между ними не видно. Клики сквозь слои проходят,
// ловит их только окошко-панель. 60 кадров в секунду — только пока висит запрос. Слой Metal в окне —
// не во весь кусок монитора, а на рамку содержимого с запасом (`ConsentWaterLayerWindow.layerRect`,
// #7766): drawable и очистка — на эту рамку, перестановка слоя — в одной транзакции с кадром.

/// Шейдер — порт WebGL-шейдера макета 12. Параметры — 25 × float4 (`ConsentWaterFrame.uniforms`):
/// [0] угол окна-слоя (CG), пикселей на pt, запас дырки; [1] мягкость слияния, радиус углов окошка,
/// светлый стол, плотность заливки; [2] окошко (центр, полуразмеры); [3] две волны «булька»;
/// [4] число рамок и капель; [5…8] окна запроса (центр, полуразмеры); [9…12] их рамки (зазор,
/// толщина, радиус, сила); [13…24] капли (x, y, r).
enum ConsentWaterShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    static float sdRB(float2 p, float2 b, float r) {
        r = min(r, min(b.x, b.y));
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    static float smin(float a, float b, float k) {
        float h = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - h * h * k * 0.25;
    }

    static float field(float2 p, constant float4 *u) {
        float d = 1e4;
        int nr = int(u[4].x), nc = int(u[4].y);
        float k = u[1].x;
        for (int i = 0; i < nr; i++) {
            float4 w = u[5 + i], r = u[9 + i];
            if (r.w > 0.002) {
                float t = r.y * r.w;
                d = min(d, abs(sdRB(p - w.xy, w.zw + r.x + t * 0.5, r.z + t * 0.5)) - t * 0.5);
            }
        }
        float4 b = u[2];
        if (b.z > 0.3 && b.w > 0.3) { d = smin(d, sdRB(p - b.xy, b.zw, u[1].y), k); }
        for (int i = 0; i < nc; i++) {
            float4 c = u[13 + i];
            if (c.z > 0.15) { d = smin(d, length(p - c.xy) - c.z, k); }
        }
        return d;
    }

    static float4 over(float4 b, float3 c, float a) { return float4(c * a, a) + b * (1.0 - a); }

    vertex float4 waterVertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        return float4(p * 2.0 - 1.0, 0.0, 1.0);
    }

    fragment float4 waterFragment(float4 pos [[position]], constant float4 *u [[buffer(0)]]) {
        float scale = u[0].z;
        float2 p = u[0].xy + pos.xy / scale;
        int nr = int(u[4].x);
        float m = 1.0;
        for (int i = 0; i < nr; i++) {
            float4 w = u[5 + i];
            // Дырка прямоугольная, как окна-слои вокруг неё: углы тоже пустые.
            float2 hq = abs(p - w.xy) - w.zw;
            m = min(m, clamp(max(hq.x, hq.y) - u[0].w, 0.0, 1.0));
        }
        if (m <= 0.0) { return float4(0.0); }
        float px = 1.0 / scale;
        float d = field(p, u);
        float e = d / px;
        // Свечение, кайма и блик — в «пикселях ретины» (0,5 pt), чтобы на мониторах 1x и 2x вода была одна.
        float es = d / 0.5;
        float2 n = normalize(float2(field(p + float2(px, 0.0), u) - d, field(p + float2(0.0, px), u) - d) + 1e-6);
        float3 A = float3(0.706, 0.549, 1.0), RIM = float3(0.87, 0.81, 1.0);
        float3 F = float3(0.114, 0.059, 0.2), DK = float3(0.06, 0.02, 0.12);
        float cov = clamp(0.5 - e, 0.0, 1.0), inn = max(-es, 0.0), ou = max(es, 0.0);
        float light = u[1].z, fill = u[1].w;
        float4 c = float4(0.0);
        c = over(c, A, (1.0 - cov) * exp(-ou / 9.0) * 0.32);
        c = over(c, DK, (1.0 - cov) * (1.0 - smoothstep(0.3, 1.8, ou)) * (0.22 + 0.5 * light));
        c = over(c, F, cov * fill);
        c = over(c, A, cov * exp(-inn / 7.0) * 0.6);
        c = over(c, RIM, cov * (1.0 - smoothstep(1.0, 2.8, inn)) * 0.95);
        float sp = pow(max(dot(n, normalize(float2(-0.5, -0.87))), 0.0), 4.0);
        c = over(c, float3(1.0), cov * sp * (1.0 - smoothstep(1.5, 6.0, inn)) * 0.8);
        float4 wv = u[3];
        if (nr > 0 && (wv.y > 0.003 || wv.w > 0.003)) {
            float4 w = u[5], r = u[9];
            float rb = sdRB(p - w.xy, w.zw + r.x + r.y, r.z + r.y);
            c = over(c, RIM, (1.0 - smoothstep(1.0, 3.0, abs(rb - wv.x) / 0.5)) * wv.y);
            c = over(c, RIM, (1.0 - smoothstep(1.0, 3.0, abs(rb - wv.z) / 0.5)) * wv.w);
        }
        return c * m;
    }
    """
}

/// Metal: один конвейер на все окна-слои.
final class ConsentWaterRenderer {
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    /// nil — Metal нет или шейдер не собрался: тогда рамка WF91.
    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device = device, let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: ConsentWaterShader.source, options: nil),
              let vertex = library.makeFunction(name: "waterVertex"),
              let fragment = library.makeFunction(name: "waterFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = ConsentWaterRenderer.pixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    /// Прямоугольник рисования в пикселях текстуры окна-слоя: где кадр что-то рисует; нет — nil.
    static func scissor(content: CGRect, window: CGRect, scale: CGFloat, width: Int, height: Int) -> MTLScissorRect? {
        let r = content.intersection(window)
        guard !r.isNull, r.width > 0, r.height > 0 else { return nil }
        let x0 = max(0, Int(((r.minX - window.minX) * scale).rounded(.down)))
        let y0 = max(0, Int(((r.minY - window.minY) * scale).rounded(.down)))
        let x1 = min(width, Int(((r.maxX - window.minX) * scale).rounded(.up)))
        let y1 = min(height, Int(((r.maxY - window.minY) * scale).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        return MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Кадр в текстуру окна-слоя `window` (CG). Вне `scissor` — прозрачно; `scissor` nil — только очистка.
    func encode(_ frame: ConsentWaterFrame, window: CGRect, scale: CGFloat, light: Bool, texture: MTLTexture,
                scissor: MTLScissorRect?, into buffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let scissor = scissor {
            var uniforms = frame.uniforms(origin: window.origin, scale: scale, light: light)
            encoder.setRenderPipelineState(pipeline)
            encoder.setScissorRect(scissor)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride * uniforms.count, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    /// Кадр в память — для тестов и снимков: BGRA, альфа умножена, строки сверху вниз.
    func pixels(_ frame: ConsentWaterFrame, window: CGRect, scale: CGFloat, light: Bool) -> (width: Int, height: Int, bytes: [UInt8])? {
        let width = Int((window.width * scale).rounded()), height = Int((window.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ConsentWaterRenderer.pixelFormat,
                                                                  width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { return nil }
        let scissor = ConsentWaterRenderer.scissor(content: frame.bounds, window: window, scale: scale, width: width, height: height)
        encode(frame, window: window, scale: scale, light: light, texture: texture, scissor: scissor, into: buffer)
        if texture.storageMode == .managed, let blit = buffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return (width, height, bytes)
    }
}

/// Окно-слой: прозрачное, клики насквозь, рисует Metal.
final class ConsentWaterLayerWindow: NSWindow {
    /// Запас слоя Metal вокруг содержимого и сетка его краёв, pt: слой не переставляется каждый кадр.
    static let layerMargin: CGFloat = 96
    static let layerGrid: CGFloat = 32

    let metal = CAMetalLayer()
    private(set) var cgRect: CGRect = .zero
    private(set) var scale: CGFloat = 2
    /// Где стоит слой Metal (CG): рамка содержимого с запасом; пусто — слой спрятан.
    private(set) var drawRect: CGRect = .zero
    /// Окно переставили — слой Metal надо поставить заново.
    private var moved = true
    /// В прошлый раз что-то нарисовали — пустой кадр надо один раз очистить.
    var drewLast = false

    init(device: MTLDevice) {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        sharingType = .none
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        metal.device = device
        metal.pixelFormat = ConsentWaterRenderer.pixelFormat
        metal.framebufferOnly = true
        metal.isOpaque = false
        metal.maximumDrawableCount = 2
        metal.allowsNextDrawableTimeout = true
        metal.backgroundColor = NSColor.clear.cgColor
        metal.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metal.isHidden = true
        let root = CALayer()
        root.addSublayer(metal)
        let view = NSView(frame: .zero)
        view.layer = root
        view.wantsLayer = true
        contentView = view
    }

    /// Поставить на прямоугольник `rect` (CG) монитора с масштабом `scale`.
    func place(_ rect: CGRect, scale: CGFloat, primaryHeight: CGFloat) {
        guard rect != cgRect || scale != self.scale else { return }
        cgRect = rect
        self.scale = scale
        setFrame(ConsentBeaconGeometry.cocoaRect(fromCG: rect, primaryHeight: primaryHeight), display: false)
        moved = true
    }

    /// Куда поставить слой Metal в окне `window` (CG): рамка содержимого `content` с запасом
    /// `layerMargin`, края по сетке `layerGrid`. Содержимое внутри `current`, и тот не больше вчетверо
    /// нужного — `current` (слой не дёргаем). Содержимого в окне нет — `current` в пределах окна.
    static func layerRect(content: CGRect, window: CGRect, current: CGRect) -> CGRect {
        let kept = current.intersection(window)
        let keep = kept.isNull || kept.width <= 0 || kept.height <= 0 ? CGRect.zero : kept
        let want = content.intersection(window)
        guard !want.isNull, want.width > 0, want.height > 0 else { return keep }
        let need = WaterGeo.grow(want, layerMargin).intersection(window)
        if keep.contains(want), keep.width * keep.height <= 4 * need.width * need.height { return keep }
        let g = layerGrid
        let x0 = (need.minX / g).rounded(.down) * g, y0 = (need.minY / g).rounded(.down) * g
        let x1 = (need.maxX / g).rounded(.up) * g, y1 = (need.maxY / g).rounded(.up) * g
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).intersection(window)
    }

    /// Слой Metal — на рамку содержимого `content` (CG); true — слой переставлен, кадр показать
    /// в той же транзакции. Зовётся внутри открытой `CATransaction`.
    func fit(_ content: CGRect) -> Bool {
        let rect = ConsentWaterLayerWindow.layerRect(content: content, window: cgRect, current: moved ? .zero : drawRect)
        guard rect != drawRect || moved else { return false }
        moved = false
        drawRect = rect
        guard rect.width > 0, rect.height > 0 else {
            metal.isHidden = true
            drewLast = false
            return false
        }
        // Корневой слой окна — y вверх, CG — y вниз.
        metal.frame = CGRect(x: rect.minX - cgRect.minX, y: cgRect.maxY - rect.maxY, width: rect.width, height: rect.height)
        metal.contentsScale = scale
        metal.drawableSize = CGSize(width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
        metal.isHidden = false
        return true
    }
}

/// Окошко у курсора: стрелка и две строки поверх воды; ловит только клик.
final class ConsentWaterPlaquePanel: NSPanel {
    var onClick: () -> Void = {}
    private let box = ConsentWaterPlaqueView(frame: ConsentWaterPlaqueView.panelBounds)

    init() {
        super.init(contentRect: ConsentWaterPlaqueView.panelBounds,
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        sharingType = .none
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        box.onClick = { [weak self] in self?.onClick() }
        contentView = box
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ plaque: WaterPlaque, primaryHeight: CGFloat, scale: CGFloat) {
        guard plaque.shown else {
            if isVisible { orderOut(nil) }
            return
        }
        // Окно одного размера — под окошко ×`reachMax` и запас `plMargin`; ставим его центром на окошко (#8122).
        let rect = ConsentBeaconGeometry.cocoaRect(fromCG: plaque.panelRect, primaryHeight: primaryHeight)
        let size = ConsentWaterPlaqueView.panelBounds.size
        let frame = NSRect(x: (rect.midX - size.width / 2).rounded(), y: (rect.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        if self.frame != frame { setFrame(frame, display: false) }
        alphaValue = plaque.opacity
        ignoresMouseEvents = !plaque.clickable
        box.apply(plaque, scale: scale)
        if !isVisible { orderFrontRegardless() }
    }
}

/// Рисунок окошка: стрелка на пружине и подписи; в спокойном виде — своё тёмное стекло.
final class ConsentWaterPlaqueView: NSView {
    /// Окошко ×`reachMax` и запас `plMargin` со всех сторон — под окошко на всю дальность (#8111, #8122).
    static let panelBounds = NSRect(x: 0, y: 0,
                                    width: ConsentWaterK.plW * ConsentWaterK.reachMax + 2 * ConsentWaterK.plMargin,
                                    height: ConsentWaterK.plH * ConsentWaterK.reachMax + 2 * ConsentWaterK.plMargin)
    var onClick: () -> Void = {}
    private let body = CALayer()
    private let arrow = CALayer()
    private let arrowStroke = CAShapeLayer()
    private let arrowFill = CAShapeLayer()
    private let title = CATextLayer()
    private let subtitle = CATextLayer()
    private var line2 = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Своё дерево слоёв (layer-hosting): рисуется и без окна — так его снимают тесты.
        let root = CALayer()
        root.backgroundColor = NSColor.clear.cgColor
        layer = root
        wantsLayer = true
        let w = ConsentWaterK.plW, h = ConsentWaterK.plH
        body.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        body.position = CGPoint(x: Self.panelBounds.midX, y: Self.panelBounds.midY)
        body.cornerRadius = 20
        root.addSublayer(body)
        // Стрелка из макета (viewBox −32…32 в квадрате 56 pt), обводка под заливкой.
        let path = CGMutablePath()
        let s: CGFloat = 56 / 64
        let points: [(CGFloat, CGFloat)] = [(-24, -7.5), (4, -7.5), (4, -18), (27, 0), (4, 18), (4, 7.5), (-24, 7.5)]
        path.addLines(between: points.map { CGPoint(x: $0.0 * s, y: $0.1 * s) })
        path.closeSubpath()
        arrow.bounds = CGRect(x: -28, y: -28, width: 56, height: 56)
        arrow.position = CGPoint(x: 8 + 28, y: h / 2)
        arrowStroke.path = path
        arrowStroke.fillColor = nil
        arrowStroke.strokeColor = NSColor(srgbRed: 0x1d / 255, green: 0x0f / 255, blue: 0x33 / 255, alpha: 1).cgColor
        arrowStroke.lineWidth = 2.4 * s
        arrowStroke.lineJoin = .round
        arrowFill.path = path
        arrowFill.fillColor = NSColor(srgbRed: 0xf7 / 255, green: 0xf2 / 255, blue: 1, alpha: 1).cgColor
        arrow.addSublayer(arrowStroke)
        arrow.addSublayer(arrowFill)
        arrow.shadowColor = NSColor(srgbRed: 180 / 255, green: 140 / 255, blue: 1, alpha: 1).cgColor
        arrow.shadowRadius = 5
        arrow.shadowOffset = .zero
        body.addSublayer(arrow)
        for (layer, size, weight, alpha, y) in [(title, CGFloat(15), NSFont.Weight.bold, CGFloat(1), CGFloat(31)),
                                                 (subtitle, CGFloat(11.5), NSFont.Weight.medium, CGFloat(0.8), CGFloat(14))] {
            layer.frame = CGRect(x: 68, y: y, width: w - 68 - 8, height: size + 5)
            layer.font = NSFont.systemFont(ofSize: size, weight: weight)
            layer.fontSize = size
            layer.foregroundColor = NSColor(srgbRed: 0xf3 / 255, green: 0xee / 255, blue: 0xfb / 255, alpha: alpha).cgColor
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.55
            layer.shadowRadius = 1.5
            layer.shadowOffset = CGSize(width: 0, height: -1)
            layer.truncationMode = .end
            body.addSublayer(layer)
        }
        title.string = "macOS ждёт ответа"
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ plaque: WaterPlaque, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Подписи растут вместе с окошком — растр под крупный размер, чтобы шрифт не мылился (#8122).
        let sharp = scale * max(1, (plaque.reach * 4).rounded(.up) / 4)
        for layer in [title, subtitle] where layer.contentsScale != sharp { layer.contentsScale = sharp }
        if plaque.line2 != line2 {
            line2 = plaque.line2
            subtitle.string = line2
        }
        body.setAffineTransform(CGAffineTransform(scaleX: plaque.zoom * plaque.reach, y: plaque.zoom * plaque.reach))
        // Угол в CG (y вниз), слой — y вверх: поворот обратный.
        // Растёт окошко целиком (body), стрелка в нём — только дышит.
        arrow.setAffineTransform(CGAffineTransform(rotationAngle: -plaque.angle).scaledBy(x: plaque.breathe, y: plaque.breathe))
        body.backgroundColor = plaque.solid ? NSColor(srgbRed: 29 / 255, green: 15 / 255, blue: 51 / 255, alpha: 0.92).cgColor : nil
        body.borderColor = NSColor(srgbRed: 180 / 255, green: 140 / 255, blue: 1, alpha: 1).cgColor
        body.borderWidth = plaque.solid ? 2 : 0
        arrow.shadowOpacity = plaque.solid ? 0 : 0.95
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Ловит клик только само окошко, не запас вокруг.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return body.frame.contains(local) ? self : nil
    }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// Живой маяк «из воды»: 60 кадров, пока висит запрос; ответили — стекает за полсекунды и гаснет.
final class ConsentWaterOverlay {
    static let frameInterval: TimeInterval = 1.0 / 60
    /// «Бульк» не чаще этого.
    static let soundGap: CFTimeInterval = 2

    var onClick: () -> Void = {}
    var soundEnabled: () -> Bool = { true }

    private let renderer: ConsentWaterRenderer
    private var sim = ConsentWaterSim(seed: UInt64(Date().timeIntervalSince1970))
    private var layers: [ConsentWaterLayerWindow] = []
    private var layout: [CGRect] = []
    private let plaque = ConsentWaterPlaquePanel()
    private var timer: Timer?
    private var targets: [ConsentWindow] = []
    private var alive = false
    private var lastTick: CFTimeInterval = 0
    private var ticks = 0
    private var lastSound: CFTimeInterval = -1e9
    private var sound: NSSound?
    private var lastFrame: ConsentWaterFrame?
    /// Прошлый кадр ещё на GPU: новый не начинаем, чтобы `nextDrawable` не ждал на главном потоке.
    private var inFlight = false

    /// Кадров нарисовано — для диагностики.
    private(set) var frames = 0
    var isRunning: Bool { timer != nil }
    /// Окон-слоёв живо (после `stop()` — 0).
    var layerCount: Int { layers.count }

    init?() {
        guard let renderer = ConsentWaterRenderer() else { return nil }
        self.renderer = renderer
        plaque.onClick = { [weak self] in self?.onClick() }
    }

    /// Запрос висит: окна `windows`, спокойный вид — `calm`.
    func show(_ windows: [ConsentWindow], calm: Bool) {
        if !alive || timer == nil { sim = ConsentWaterSim(calm: calm, seed: UInt64(Date().timeIntervalSince1970)) }
        sim.calm = calm
        targets = windows
        alive = true
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: ConsentWaterOverlay.frameInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Ответили: всё стекает и само гаснет — не дольше `fadeMax` (#8122: «после успешного ввода… закрывать. Она ещё
    /// долго висит»).
    func fade() {
        if alive { fadeAt = CACurrentMediaTime() }
        alive = false
    }
    /// Сколько после ответа ещё стекает вода — дальше убираем сразу.
    static let fadeMax: CFTimeInterval = 0.45
    private var fadeAt: CFTimeInterval?

    /// Убрать сразу.
    func stop() {
        timer?.invalidate()
        timer = nil
        alive = false
        // Окна-слои с их drawable — закрыть и выбросить, а не только спрятать (#7766).
        layers.forEach { $0.close() }
        layers = []
        layout = []
        plaque.orderOut(nil)
        lastFrame = nil
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(now - lastTick)
        lastTick = now
        ticks += 1
        if ticks % 6 == 0 { refreshBounds() }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return stop() }
        let primary = primaryHeight
        let cg = { (r: NSRect) in ConsentBeaconGeometry.cocoaRect(fromCG: r, primaryHeight: primary) }
        let frames = screens.map { cg($0.frame) }
        let visible = screens.map { cg($0.visibleFrame) }
        let mouse = NSEvent.mouseLocation
        let cursor = CGPoint(x: mouse.x, y: primary - mouse.y)
        let rects = targets.map { $0.bounds }
        let frame = sim.step(dt: dt, ConsentWaterInput(cursor: cursor, targets: alive ? rects : [], screens: frames,
                                                       visible: visible, alive: alive))
        if frame.finished { return stop() }
        if !alive, let fadeAt = fadeAt, now - fadeAt > Self.fadeMax { return stop() }
        let wanted = ConsentWaterLayout.windows(screens: frames, targets: rects, cursor: cursor)
        let relaid = wanted != layout
        if relaid { place(wanted, screens: screens, screenRects: frames) }
        let drawn = relaid || frame != lastFrame ? render(frame) : true
        lastFrame = drawn ? frame : nil
        let cursorScreen = WaterGeo.index(of: cursor, in: frames).map { screens[$0].backingScaleFactor } ?? 2
        plaque.apply(frame.plaque, primaryHeight: primary, scale: cursorScreen)
        if frame.blub && soundEnabled() && now - lastSound > ConsentWaterOverlay.soundGap {
            lastSound = now
            if sound == nil { sound = NSSound(data: ConsentWaterSound.wav()) }
            sound?.stop()
            sound?.play()
        }
    }

    private func place(_ rects: [CGRect], screens: [NSScreen], screenRects: [CGRect]) {
        layout = rects
        makeLayers(rects.count)
        let primary = primaryHeight
        for (i, window) in layers.enumerated() {
            guard i < rects.count else {
                window.orderOut(nil)
                continue
            }
            let screen = WaterGeo.index(of: WaterGeo.center(rects[i]), in: screenRects).map { screens[$0] }
            window.place(rects[i], scale: screen?.backingScaleFactor ?? 2, primaryHeight: primary)
            window.orderFrontRegardless()
        }
    }

    /// Окон-слоёв не меньше `count` (новые — невидимые).
    func makeLayers(_ count: Int) {
        while layers.count < count { layers.append(ConsentWaterLayerWindow(device: renderer.device)) }
    }

    /// Кадр во все окна-слои. false — нарисован не везде (окно скрыто, нет drawable, GPU занят
    /// прошлым кадром): следующий тик нарисует снова.
    private func render(_ frame: ConsentWaterFrame) -> Bool {
        guard !inFlight, let buffer = renderer.queue.makeCommandBuffer() else { return false }
        let light = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        var any = false, complete = true
        var synced: [CAMetalDrawable] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for window in layers.prefix(layout.count) {
            // В скрытое окно не рисуем (экран спит, заставка).
            guard window.occlusionState.contains(.visible) else {
                complete = false
                continue
            }
            let moved = window.fit(frame.bounds)
            let rect = window.drawRect
            guard rect.width > 0, rect.height > 0 else { continue }
            let size = window.metal.drawableSize
            let scissor = ConsentWaterRenderer.scissor(content: frame.bounds, window: rect, scale: window.scale,
                                                       width: Int(size.width), height: Int(size.height))
            if scissor == nil && !window.drewLast && !moved { continue }
            // Слой переставлен — кадр покажем в одной транзакции с ним, без мигания.
            window.metal.presentsWithTransaction = moved
            guard let drawable = window.metal.nextDrawable() else {
                complete = false
                continue
            }
            renderer.encode(frame, window: rect, scale: window.scale, light: light, texture: drawable.texture,
                            scissor: scissor, into: buffer)
            if moved { synced.append(drawable) } else { buffer.present(drawable) }
            window.drewLast = scissor != nil
            any = true
        }
        if any {
            inFlight = true
            buffer.addCompletedHandler { [weak self] _ in DispatchQueue.main.async { self?.inFlight = false } }
        }
        buffer.commit()
        if !synced.isEmpty {
            buffer.waitUntilScheduled()
            synced.forEach { $0.present() }
        }
        CATransaction.commit()
        if any { frames += 1 }
        return complete
    }

    /// Окно запроса могли сдвинуть: его рамка — 10 раз в секунду, только по известным номерам окон.
    private func refreshBounds() {
        guard alive, !targets.isEmpty else { return }
        var ids: [UnsafeRawPointer?] = targets.map { UnsafeRawPointer(bitPattern: UInt($0.number)) }
        guard let array = CFArrayCreate(kCFAllocatorDefault, &ids, ids.count, nil),
              let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return }
        var bounds: [Int: CGRect] = [:]
        for info in list {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            bounds[number] = rect
        }
        targets = targets.map { window in
            guard let rect = bounds[window.number], rect != window.bounds else { return window }
            return ConsentWindow(number: window.number, pid: window.pid, process: window.process, layer: window.layer, bounds: rect)
        }
    }
}
