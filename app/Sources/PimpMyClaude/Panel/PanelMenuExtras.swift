import AppKit
import ClaudeAX
import Combine
import SwiftUI

/// «Не влезли в строку меню» (WF270, #10264): значки программ, что macOS спрятала под вырез или убрала.
/// Клик — панель закрывается, через 0,15 с жмётся сам значок (меню программы открывается у выреза). Пусто — полосы нет.
/// #10280 (слово Элвиса 19.10: «чтобы те, которые не влезли в строку меню, чтобы я их драг-дропом мог переносить»):
/// значок тянется мышью — за курсором летит его копия, отпустил в строке меню правее выреза — Пимп ⌘-перетаскивает
/// туда настоящий значок; строка слева от значков говорит, что идёт и почему не вышло.
/// #10301–#10304 (слово Элвиса 19.10 14:30: «исправить цвет, сделать их крупнее, чтобы работала правая кнопка, чтобы
/// их можно было перетаскивать с ⌘»; решение — `docs/decisions/2026-10-19-ne-vlezli-10301.md`, заменяет #10286):
/// полоса цвета панели PMP по центру под значком PMP, без надписи; настоящие глифы строки меню белым (снимок окна
/// значка, без «Записи экрана» — иконка программы серым), 24 pt; правая кнопка и Ctrl+клик — меню программы; с ⌘
/// значок тянется сразу — в строку меню или между значками полосы (порядок в строке меню).
struct MenuExtrasStripView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var state: ExtrasStripState

    var body: some View {
        let items = model.menuExtras
        let noCapture = !MenuBarExtras.captureAllowed()
        return HStack(spacing: MenuExtrasStrip.gap) {
            if let note = model.extraNote {
                Text(note).font(.system(size: 11)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ExtraIcon(item: item, index: index, last: index == items.count - 1, image: model.extraImages[item.id],
                          noCapture: noCapture, model: model, state: state)
            }
        }
        .padding(.horizontal, MenuExtrasStrip.gap)
        .frame(maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
        .background(plate)
        .coordinateSpace(name: ExtrasStripState.space)
        .onPreferenceChange(ExtraFramesKey.self) { state.frames = $0 }
        .onHover(perform: hovered)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Значки, что не влезли в строку меню")
    }

    /// Подложка — как у панели PMP: графит, обводка 1 pt, скругление 12 у всех углов; тень — у окна.
    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            shape.fill(PanelColor.ink)
            shape.strokeBorder(PanelColor.frame, lineWidth: 1)
        }
    }

    private func hovered(_ inside: Bool) {
        state.hovering = inside
        state.command = NSEvent.modifierFlags.contains(.command)
        state.refreshCursor()
    }
}

/// Значок в полосе: глиф строки меню (или иконка программы серым), подсветка при наведении, черта вставки рядом.
private struct ExtraIcon: View {
    let item: MenuBarExtras.Item
    let index: Int
    let last: Bool
    let image: NSImage?
    let noCapture: Bool
    @ObservedObject var model: PanelModel
    @ObservedObject var state: ExtrasStripState
    @State private var hover = false

    var body: some View {
        Button(action: tap) { face }
            .buttonStyle(PressStyle())
            .simultaneousGesture(drag)
            .onHover(perform: hovered)
            .background(frameReader)
            .overlay(alignment: .leading) { line(state.insert == index, offset: -lineOffset) }
            .overlay(alignment: .trailing) { line(last && state.insert == index + 1, offset: lineOffset) }
            .help(help)
            .accessibilityLabel(item.hint)
            .accessibilityAction(named: "Меню программы") { model.pressExtraSecondary(item) }
    }

    /// Черта вставки — посреди промежутка между значками (2 pt шириной).
    private var lineOffset: CGFloat { MenuExtrasStrip.gap / 2 + 1 }

    private var face: some View {
        ExtraGlyphView(image: image, pid: item.pid)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(hover ? 0.1 : 0)))
            .opacity(state.dragging == item.id ? 0.35 : 1)
    }

    private func line(_ shown: Bool, offset: CGFloat) -> some View {
        Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: 18).offset(x: offset).opacity(shown ? 1 : 0)
    }

    private var frameReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: ExtraFramesKey.self,
                                   value: [item.id: geo.frame(in: .named(ExtrasStripState.space))])
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { _ in state.dragChanged(item) }
            .onEnded { _ in state.dragEnded() }
    }

    private var help: String {
        let base = "\(item.hint) — перетащи в строку меню (с ⌘ — сразу, и между значками), правая кнопка — меню"
        guard image == nil, noCapture, item.reason == .notch else { return base }
        return base + "\nДай PMP «Запись экрана» — значки будут как в строке меню"
    }

    private func tap() {
        if state.dragging == nil { model.pressExtra(item) }
    }

    private func hovered(_ inside: Bool) {
        hover = inside
        if inside { state.hoverID = item.id } else if state.hoverID == item.id { state.hoverID = nil }
        state.refreshCursor()
    }
}

/// Картинка значка — та же в полосе и в копии под курсором: снимок глифа (белый, без растяжки больше 1,25 — снимок
/// 2× не мылится) или иконка программы серым (на macOS 26 все иконки — скруглённые квадраты, шаблоном вышли бы
/// одинаковые белые плашки).
struct ExtraGlyphView: View {
    let image: NSImage?
    let pid: pid_t
    var height: CGFloat = MenuExtrasStrip.side

    var body: some View {
        if let image = image {
            glyph(image)
        } else {
            appIcon
        }
    }

    private func glyph(_ image: NSImage) -> some View {
        let size = MenuExtrasStrip.glyphSize(image.size, height: height)
        let slot = MenuExtrasStrip.slotWidth(size, height: height)
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .frame(width: slot, height: height)
    }

    private var appIcon: some View {
        Image(nsImage: NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage())
            .resizable()
            .interpolation(.high)
            .saturation(0)
            .opacity(0.9)
            .frame(width: height, height: height)
    }
}

/// Рамки значков полосы в её пространстве (сверху слева): по ним — черта вставки и правая кнопка.
private struct ExtraFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private enum ExtraCursor { case none, hand, grab }

/// Состояние полосы на время открытия: рамки значков, черта вставки, идущий перенос, курсор.
final class ExtrasStripState: ObservableObject {
    static let space = "extras-strip"
    /// Черта вставки: до значка с этим номером; `count` — после последнего.
    @Published var insert: Int?
    /// Какой значок тянут (в ряду полупрозрачный). Сбрасывается на такт позже конца: клик Button после отпускания
    /// не открывает меню значка.
    @Published var dragging: String?
    var frames: [String: CGRect] = [:]
    /// Перенос идёт — его конец что-то сделает. Панель закрыли посреди — сброшено, отпускание ничего не делает.
    var active: MenuBarExtras.Item?
    /// Перенос отменён закрытием, а жест SwiftUI ещё идёт: не начинать заново до его конца.
    var cancelled = false
    fileprivate var ghost: ExtraGhost?
    var command = false
    var hovering = false
    var hoverID: String?
    private var cursor: ExtraCursor = .none

    var begin: (MenuBarExtras.Item) -> Void = { _ in }
    var move: (NSPoint) -> Void = { _ in }
    var end: (NSPoint) -> Void = { _ in }

    /// Жест SwiftUI (без ⌘, порог 4 pt): начало, ход, конец — те же шаги, что у ⌘-переноса.
    func dragChanged(_ item: MenuBarExtras.Item) {
        guard !cancelled else { return }
        if active == nil { begin(item) }
        move(NSEvent.mouseLocation)
    }

    func dragEnded() {
        if cancelled { cancelled = false; return }
        end(NSEvent.mouseLocation)
    }

    /// Курсор одной парой push/pop: тянут или ⌘ над полосой — сжатая рука, над значком — палец.
    func refreshCursor() {
        let want: ExtraCursor = active != nil || (command && hovering) ? .grab : hoverID != nil ? .hand : .none
        guard want != cursor else { return }
        if cursor != .none { NSCursor.pop() }
        switch want {
        case .grab: NSCursor.closedHand.push()
        case .hand: NSCursor.pointingHand.push()
        case .none: break
        }
        cursor = want
    }

    /// Конец переноса: копия убрана, черта снята.
    func finish() {
        active = nil
        ghost?.close()
        ghost = nil
        if insert != nil { insert = nil }
        refreshCursor()
        DispatchQueue.main.async { [weak self] in self?.dragging = nil }
    }

    /// Полосу убрали: перенос посреди — отменён, курсор возвращён.
    func reset() {
        if active != nil { cancelled = true }
        active = nil
        ghost?.close()
        ghost = nil
        insert = nil
        dragging = nil
        hoverID = nil
        hovering = false
        command = false
        refreshCursor()
    }
}

/// Копия значка под курсором, пока его тянут: окно без рамки над всеми, мышь сквозь него; картинка — как в полосе.
private final class ExtraGhost {
    private let window: NSPanel
    private let size: CGSize
    static let side: CGFloat = 28

    init(image: NSImage?, pid: pid_t) {
        let side = Self.side
        let width = image.map {
            MenuExtrasStrip.slotWidth(MenuExtrasStrip.glyphSize($0.size, height: side), height: side)
        } ?? side
        size = CGSize(width: width, height: side)
        window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let host = NSHostingView(rootView: ExtraGlyphView(image: image, pid: pid, height: side))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
    }

    func follow(_ point: NSPoint) {
        window.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func close() { window.orderOut(nil) }
}

/// Куда встать перетащенному в полосе значку: рядом с соседом с этим номером, до него или после.
struct ExtraReorder: Equatable {
    var neighbor: Int
    var after: Bool
}

/// Окно полосы «Не влезли» (#10286, #10301–#10304): без рамки, цвета панели, по центру под значком PMP сразу под
/// строкой меню, на экране значка; ширина — по значкам. Открыта панель и есть спрятанные значки — видно; иначе убрано.
final class MenuExtrasStrip {
    /// Значок 24 pt, промежуток и поля 8, высота полосы — не меньше 34.
    static let side: CGFloat = 24
    static let gap: CGFloat = 8
    static let minHeight: CGFloat = 34
    /// Запас вокруг полосы для «отпустил между значками»: по бокам и снизу; сверху нет — там строка меню (#10280).
    static let slack: CGFloat = 4

    private var window: NSPanel?
    private var host: NSHostingView<MenuExtrasStripView>?
    private let model: PanelModel
    let state = ExtrasStripState()
    /// Окно значка PMP: плашка под строкой меню, если стоит, иначе сам значок (у PMP он один). Тест подставляет своё.
    var anchor: () -> NSWindow? = MenuExtrasStrip.statusItemWindow

    private var watch: AnyCancellable?
    private var monitor: Any?
    /// Нажатие полосы забрано себе (⌘ или Ctrl) — его отпускание тоже.
    private var swallowUp = false
    /// Идёт ⌘-перенос (события мыши — у монитора, не у SwiftUI).
    private var commandDrag = false

    /// Строка слева от значков меняется и из самой полосы (начали тянуть) — ширина подгоняется сама.
    init(model: PanelModel) {
        self.model = model
        watch = model.$extraNote.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { if let self = self, self.window?.isVisible == true { self.update(open: true) } }
        }
        state.begin = { [weak self] item in self?.beginDrag(item) }
        state.move = { [weak self] point in self?.moveDrag(point) }
        state.end = { [weak self] point in self?.endDrag(point) }
    }

    /// Высота полосы, когда она на экране; 0 — её нет.
    private(set) var height: CGFloat = 0

    func owns(_ other: NSWindow?) -> Bool { other != nil && other === window }

    /// Рамка окна полосы, пока оно на экране; nil — полосы нет.
    var shownFrame: CGRect? { window?.isVisible == true ? window?.frame : nil }

    /// Показать (или убрать, если значков нет) и вернуть высоту, на которую панель уходит ниже.
    @discardableResult
    func update(open: Bool) -> CGFloat {
        guard open, !model.menuExtras.isEmpty, let anchor = anchor(),
              let screen = anchor.screen ?? NSScreen.screens.first else { hide(); return 0 }
        if window?.isVisible != true { state.cancelled = false }
        let window = self.window ?? make()
        host?.rootView = MenuExtrasStripView(model: model, state: state)
        host?.layoutSubtreeIfNeeded()
        let icons = Self.iconsWidth(slots: slotWidths())
        // Замер SwiftUI бывает нулевым (живьём 21.10 у Элвиса: окно полосы 0×34 — значков не видно, а панель уже ниже
        // на её высоту): ширина не меньше самих значков с полями.
        let width = max(host?.fittingSize.width ?? 0, icons + Self.gap * 2)
        let frame = Self.stripFrame(width: width, lead: max(0, width - icons), anchor: anchor.frame,
                                    screen: screen.frame, visible: screen.visibleFrame)
        if window.frame != frame { window.setFrame(frame, display: true) }
        window.orderFrontRegardless()
        // Тень окна — по нарисованному: SwiftUI дорисует содержимое на следующем такте.
        window.invalidateShadow()
        DispatchQueue.main.async { [weak window] in window?.invalidateShadow() }
        watchMouse()
        height = frame.height
        // Панель висит на 5 pt ниже низа значка (`PimpPanelController.open`) — уходит ниже ровно до низа полосы.
        return max(0, anchor.frame.minY - frame.minY)
    }

    func hide() {
        window?.orderOut(nil)
        height = 0
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        swallowUp = false
        commandDrag = false
        state.reset()
    }

    // MARK: чистая часть

    /// Рамка полосы (Cocoa, снизу слева): верх — низ строки меню (или низ плашки PMP, если она ниже), высота
    /// `max(строка, 34)`; середина значков (`width − lead`, слева от них строка-подсказка шириной `lead`) — под
    /// серединой значка PMP; зажата в видимую часть экрана с полями 8.
    static func stripFrame(width: CGFloat, lead: CGFloat, anchor: CGRect, screen: CGRect, visible: CGRect) -> CGRect {
        let bar = max(22, screen.maxY - visible.maxY)
        let height = max(bar, minHeight)
        let top = min(screen.maxY - bar, anchor.minY)
        let w = min(width, visible.width - 16)
        let icons = max(0, w - lead)
        let x = min(max(anchor.midX - icons / 2 - lead, visible.minX + 8), visible.maxX - 8 - w)
        return CGRect(x: x.rounded(), y: top - height, width: w, height: height)
    }

    /// Размер глифа в слоте: высота до `height`, ширина до 64 (при 24), растяжка не больше 1,25.
    static func glyphSize(_ size: CGSize, height: CGFloat = side) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: height, height: height) }
        let scale = min(height / size.height, height * 8 / 3 / size.width, 1.25 * height / side)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Ширина слота: не уже квадрата, широкий текстовый значок — по глифу.
    static func slotWidth(_ glyph: CGSize, height: CGFloat = side) -> CGFloat { max(height, glyph.width) }

    /// Ширина ряда значков без строки-подсказки: поля 8, у значка поле 4 с каждой стороны, промежутки 8.
    static func iconsWidth(slots: [CGFloat]) -> CGFloat {
        guard !slots.isEmpty else { return gap * 2 }
        return gap * 2 + slots.reduce(0) { $0 + $1 + 8 } + gap * CGFloat(slots.count - 1)
    }

    /// Зона «отпустил в полосе»: окно полосы с запасом по бокам и снизу.
    static func zone(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - slack, y: frame.minY - slack, width: frame.width + slack * 2, height: frame.height + slack)
    }

    /// Куда встаёт черта: сколько значков левее точки (по их серединам).
    static func insertion(x: CGFloat, slots: [CGRect]) -> Int {
        slots.filter { $0.midX < x }.count
    }

    /// Что значит вставка `insert` для значка `from`: своё место (до или после себя) — nil; левее — до соседа,
    /// правее — после соседа.
    static func reorderTarget(count: Int, from: Int, insert: Int) -> ExtraReorder? {
        guard from >= 0, from < count, insert >= 0, insert <= count, insert != from, insert != from + 1 else { return nil }
        return insert < from ? ExtraReorder(neighbor: insert, after: false) : ExtraReorder(neighbor: insert - 1, after: true)
    }

    /// Глифы значков для полосы (снимки окон, `MenuBarExtras.glyph`) — не на главной нитке; размер — в точках экрана.
    static func glyphs(for items: [MenuBarExtras.Item], scale: CGFloat) -> [String: NSImage] {
        var out: [String: NSImage] = [:]
        for item in items {
            guard let image = MenuBarExtras.glyph(item) else { continue }
            out[item.id] = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale,
                                                               height: CGFloat(image.height) / scale))
        }
        return out
    }

    static func statusItemWindow() -> NSWindow? {
        NSApp.windows.first { $0 is StatusItemTabWindow && $0.isVisible }
            ?? NSApp.windows.first { PimpPanelController.isStatusItem($0) }
    }

    // MARK: перенос

    private func slotWidths() -> [CGFloat] {
        model.menuExtras.map { item in
            model.extraImages[item.id].map { Self.slotWidth(Self.glyphSize($0.size)) } ?? Self.side
        }
    }

    private func beginDrag(_ item: MenuBarExtras.Item) {
        guard state.active == nil else { return }
        state.active = item
        state.dragging = item.id
        state.ghost = ExtraGhost(image: model.extraImages[item.id], pid: item.pid)
        state.refreshCursor()
        model.extraNote = "Отпусти в строке меню правее выреза — или здесь, между значками"
    }

    private func moveDrag(_ point: NSPoint) {
        guard let item = state.active else { return }
        state.ghost?.follow(point)
        var slot: Int?
        if let target = target(for: item, at: point),
           MenuBarExtras.reorderable(item, neighbor: model.menuExtras[target.neighbor]) {
            slot = target.after ? target.neighbor + 1 : target.neighbor
        }
        if state.insert != slot { state.insert = slot }
    }

    /// Отпустил: над полосой — порядок рядом с соседом (своё место — ничего), иначе — в строку меню, как раньше.
    private func endDrag(_ point: NSPoint) {
        guard let item = state.active else { return }
        state.finish()
        guard let window = window, Self.zone(window.frame).contains(point) else {
            model.dropExtra(item, point)
            return
        }
        guard let target = target(for: item, at: point) else {
            model.extraNote = nil
            return
        }
        model.reorderExtra(item, model.menuExtras[target.neighbor], target.after)
    }

    /// Вставка по точке экрана: nil — не над полосой, рамок ещё нет или своё место.
    private func target(for item: MenuBarExtras.Item, at point: NSPoint) -> ExtraReorder? {
        guard let window = window, Self.zone(window.frame).contains(point) else { return nil }
        let items = model.menuExtras
        let slots = items.compactMap { state.frames[$0.id] }
        guard slots.count == items.count, let from = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        let insert = Self.insertion(x: point.x - window.frame.minX, slots: slots)
        return Self.reorderTarget(count: items.count, from: from, insert: insert)
    }

    // MARK: мышь: правая кнопка, Ctrl+клик, ⌘-перенос

    /// Монитор своих событий, пока полоса на экране: обычный клик и перенос без ⌘ идут к SwiftUI как раньше.
    private func watchMouse() {
        guard monitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .flagsChanged]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .flagsChanged:
            state.command = event.modifierFlags.contains(.command)
            state.refreshCursor()
            return event
        case .rightMouseDown:
            guard let item = item(at: event) else { return event }
            secondary(item)
            return nil
        case .leftMouseDown:
            return leftDown(event)
        case .leftMouseDragged:
            guard commandDrag else { return event }
            moveDrag(NSEvent.mouseLocation)
            return nil
        case .leftMouseUp:
            guard swallowUp else { return event }
            swallowUp = false
            if commandDrag {
                commandDrag = false
                endDrag(NSEvent.mouseLocation)
            }
            return nil
        default:
            return event
        }
    }

    /// Ctrl+клик — как правая кнопка; ⌘+нажатие — перенос сразу, без порога.
    private func leftDown(_ event: NSEvent) -> NSEvent? {
        guard let item = item(at: event) else { return event }
        let flags = event.modifierFlags
        if flags.contains(.control) {
            swallowUp = true
            secondary(item)
            return nil
        }
        guard flags.contains(.command) else { return event }
        swallowUp = true
        commandDrag = true
        beginDrag(item)
        moveDrag(NSEvent.mouseLocation)
        return nil
    }

    private func item(at event: NSEvent) -> MenuBarExtras.Item? {
        guard let window = window, event.window === window else { return nil }
        let height = window.contentView?.bounds.height ?? window.frame.height
        let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
        return model.menuExtras.first { state.frames[$0.id]?.contains(point) == true }
    }

    /// Меню программы — после монитора: закрытие панели снимает и его.
    private func secondary(_ item: MenuBarExtras.Item) {
        let model = self.model
        DispatchQueue.main.async { model.pressExtraSecondary(item) }
    }

    private func make() -> NSPanel {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: Self.minHeight),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.becomesKeyOnlyIfNeeded = true
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: MenuExtrasStripView(model: model, state: state))
        host.sizingOptions = []
        window.contentView = host
        self.window = window
        self.host = host
        return window
    }
}
