import AppKit
import ClaudeAX
import SwiftUI

// MARK: виджеты (WF129, #9043)

/// Рамка заголовка блока в его карточке — над ней лежит нажатие «свернуть» (`WidgetCell`).
private struct WidgetTitleKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if value == .zero { value = next }
    }
}

private let widgetCellSpace = "pmpWidgetCell"

/// Шеврон у названия блока (файл 53, раздел 4): nil — блок не в сетке, шеврона нет; true — свёрнут (›), false —
/// развёрнут (⌄).
private struct WidgetFoldKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

/// Курсор над блоком — шеврон белеет (файл 53, 4.2: «понятно, что нажимается»).
private struct WidgetHotKey: EnvironmentKey {
    static let defaultValue = false
}

/// Заголовок блока: шеврон всегда на виду у названия (слово Элвиса 22.10.2026 — вместо исчезающих значков по наведению)
/// и рамка для нажатия «свернуть».
struct WidgetTitle: ViewModifier {
    @Environment(\.widgetFold) private var fold
    @Environment(\.widgetHot) private var hot

    func body(content: Content) -> some View {
        HStack(alignment: .center, spacing: 5) {
            content
            if let collapsed = fold {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(hot ? PanelColor.text : PanelColor.sub)
                    .frame(width: 9)
                    .accessibilityHidden(true)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: WidgetTitleKey.self, value: proxy.frame(in: .named(widgetCellSpace)))
        })
    }
}

/// Какие блоки сейчас есть в сетке (#10993): по ним кнопки сворачивания внутри блока (графики) находят соседа по ряду.
/// Вне сетки — пусто: блок сворачивается один, как раньше.
private struct WidgetVisibleKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var widgetVisible: Set<String> {
        get { self[WidgetVisibleKey.self] }
        set { self[WidgetVisibleKey.self] = newValue }
    }
}

/// #10993 (слово Элвиса 27.10.2026: «когда неделя разворачивается, тогда и сброс должен разворачиваться… они же в одной
/// строке»): блок сворачивается и разворачивается вместе с соседом по ряду (`PanelWidgetLayout.rowMates`). Каждый — через
/// `setCollapsed` модели: у «Оформления» и Workflow при сворачивании закрывается своё раскрытое.
extension PanelModel {
    func toggleRow(_ id: String, visible: Set<String>) {
        setRow(id, layout.item(id)?.collapsed != true, visible: visible)
    }

    func setRow(_ id: String, _ collapsed: Bool, visible: Set<String>) {
        for mate in layout.rowMates(id, visible: visible) { setCollapsed(mate, collapsed) }
    }

    /// Нажатие по свёрнутой строке: развернулся блок (не жест переноса) — разворачивается и сосед.
    func tapRow(_ id: String, visible: Set<String>) {
        tapCollapsed(id)
        guard layout.item(id)?.collapsed == false else { return }
        setRow(id, false, visible: visible)
    }

    /// Кнопка шапки «Свернуть» (#10993: «сворачиваются все к вот этому виду по умолчанию»): назад к виду по умолчанию.
    func foldToDefault(visible: Set<String>) {
        setAllCollapsed(true, visible: visible)
        changeLayout { $0.setDefaultFolds(visible: visible) }
    }
}

/// Блок поставлен в одну колонку — его вид ужимается (температура без линии, плитки лимитов столбиком…).
private struct NarrowKey: EnvironmentKey {
    static let defaultValue = false
}

/// Карточка стоит в ряду сетки виджетов: тянется по высоте ряда (WF181, #9217), фон и рамка — на всю высоту.
private struct FillKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var panelNarrow: Bool {
        get { self[NarrowKey.self] }
        set { self[NarrowKey.self] = newValue }
    }

    var panelFill: Bool {
        get { self[FillKey.self] }
        set { self[FillKey.self] = newValue }
    }

    /// Шеврон у названия: nil — нет, true — свёрнут, false — развёрнут.
    var widgetFold: Bool? {
        get { self[WidgetFoldKey.self] }
        set { self[WidgetFoldKey.self] = newValue }
    }

    var widgetHot: Bool {
        get { self[WidgetHotKey.self] }
        set { self[WidgetHotKey.self] = newValue }
    }
}

private struct WidgetFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Координаты рамок виджетов и указателя при перетаскивании.
private let widgetSpace = "pmpWidgets"

private struct WidgetIDKey: LayoutValueKey {
    static let defaultValue = ""
}

/// Сетка виджетов: ряды решает `PanelWidgetLayout.rows` (широкий — свой ряд, узкие — по двое), здесь только
/// место. Один `ForEach` с постоянными id — перестановка и смена ширины едут пружиной, состояние блоков живо.
struct WidgetGrid: Layout {
    let rows: [[PanelWidgetLayout.Item]]
    var spacing: CGFloat = 10
    var gap: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? PimpPanelController.width - 24
        return CGSize(width: width, height: place(width, subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = place(bounds.width, subviews)
        for (index, subview) in subviews.enumerated() {
            guard let frame = placed.frames[index] else {
                subview.place(at: bounds.origin, proposal: .zero)
                continue
            }
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func place(_ width: CGFloat, _ subviews: Subviews) -> (frames: [Int: CGRect], height: CGFloat) {
        let half = (width - gap) / 2
        let index: (String) -> Int? = { id in subviews.firstIndex { $0[WidgetIDKey.self] == id } }
        let measured = rows.map { row in row.compactMap { item -> (id: String, wide: Bool, height: CGFloat)? in
            guard let at = index(item.id) else { return nil }
            let wide = item.wide || row.count == 1
            let height = subviews[at].sizeThatFits(ProposedViewSize(width: wide ? width : half, height: nil)).height
            return (item.id, wide, height)
        } }
        let placed = Self.frames(measured, width: width, gap: gap, spacing: spacing)
        var frames: [Int: CGRect] = [:]
        for (id, frame) in placed.frames { if let at = index(id) { frames[at] = frame } }
        return (frames, placed.height)
    }

    /// Рамки блоков по рядам. Ряд — одной высоты (WF181, #9217: «по высоте все элементы одинаковые»): по самой
    /// высокой карточке ряда, остальные тянутся до неё. Раскрытый график соседа не растягивает: с WF242 он стоит
    /// своим рядом (`PanelWidgetLayout.rows(visible:expanded:)`). Одинокая половинка — во всю ширину (WF187):
    /// пустая вторая половина ряда выглядела дырой.
    static func frames(_ rows: [[(id: String, wide: Bool, height: CGFloat)]], width: CGFloat, gap: CGFloat,
                       spacing: CGFloat) -> (frames: [String: CGRect], height: CGFloat) {
        let half = (width - gap) / 2
        var frames: [String: CGRect] = [:]
        var y: CGFloat = 0
        for row in rows where !row.isEmpty {
            let tallest = row.map { $0.height }.max() ?? 0
            var x: CGFloat = 0
            for item in row {
                let w = item.wide || row.count == 1 ? width : half
                frames[item.id] = CGRect(x: x, y: y, width: w, height: tallest)
                x += w + gap
            }
            y += tallest + spacing
        }
        return (frames, max(0, y - spacing))
    }
}

/// Виджеты панели (файл 53, вариант 2): под блоками — «Скрытые: + Fable» (нажатие возвращает) и кнопка «Изменить
/// виджеты», как в Центре уведомлений macOS; в правке она — «Готово».
struct WidgetBoard<Cell: View>: View {
    @ObservedObject var model: PanelModel
    let visible: Set<String>
    @ViewBuilder let cell: (PanelWidget) -> Cell
    @State private var frames: [String: CGRect] = [:]
    /// Какой вид выбрала строка каждого блока (`FitLine`, WF253).
    @State private var fits: [String: PanelFit] = [:]
    /// Общий кегль подписей свёрнутых блоков (#10704): наименьшая доля, при которой входит каждый.
    @State private var labelScale: CGFloat = 1

    var body: some View {
        let items = model.layout.items.filter { visible.contains($0.id) && !$0.hidden }
        let hidden = model.layout.hidden(visible: visible)
        VStack(alignment: .leading, spacing: 8) {
            grid(items)
            // Скрытые — только в правке: на виду блока быть не должно (слово 03.11.2026 про Workflow).
            if !hidden.isEmpty, model.editingWidgets { HiddenWidgetsRow(model: model, items: hidden) }
            EditWidgetsButton(model: model)
        }
        // #11276: пара вразнобой (сохранена до #10993 или ряды съехали, когда блок появился или пропал) — по рядам,
        // которые сейчас на экране; ничего не поменялось — `changeLayout` не пишет.
        .onAppear { model.changeLayout { $0.alignRowFolds(visible: visible) } }
        .onChange(of: visible) { now in model.changeLayout { $0.alignRowFolds(visible: now) } }
    }

    private func grid(_ items: [PanelWidgetLayout.Item]) -> some View {
        // Раскрытый график (WF242) — своим рядом во всю ширину: два графика стоят друг под другом, края сходятся.
        let rows = model.layout.rows(visible: visible, expanded: model.expandedWidgets)
        // Половинка без пары (WF187) — во всю ширину; широкий блок своим рядом сюда не входит: его можно сузить.
        let lone = Set(rows.filter { $0.count == 1 }.flatMap { $0 }.filter { !$0.wide }.map { $0.id })
        // WF253: в ряду одному блоку строка не вошла (подпись над значением) — соседи встают так же, линии сходятся.
        let stacked = Set(rows.filter { row in row.count > 1 && row.contains { fits[$0.id]?.stacked == true } }
            .flatMap { $0 }.map { $0.id })
        return WidgetGrid(rows: rows) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let widget = item.widget {
                    WidgetCell(model: model, item: item, alone: lone.contains(item.id), frames: frames,
                               visible: visible) { cell(widget) }
                        .environment(\.panelStacked, stacked.contains(item.id))
                        .layoutValue(key: WidgetIDKey.self, value: item.id)
                        // Легенда счёта Workflow (#10239) ложится поверх соседних блоков.
                        .zIndex(model.widgetDrag?.id == item.id ? 1
                                : model.workflowLegend && item.widget == .workflow ? 0.5 : 0)
                        .appear(min(1 + index / 2, 3), model)
                }
            }
        }
        .environment(\.collapsedLabelScale, labelScale)
        .coordinateSpace(name: widgetSpace)
        .onPreferenceChange(WidgetFramesKey.self) { frames = $0 }
        .onPreferenceChange(PanelFitKey.self) { fits = $0 }
        .onPreferenceChange(CollapsedScaleKey.self) { labelScale = $0 }
    }
}

/// «Изменить виджеты» / «Готово» под блоками — капсулой контуром, как «Свернуть всё» в шапке. По центру, а рядом с
/// «Поддержать автора» (слово 03.11.2026) слева, кнопка справа. В правке кнопки нет.
private struct EditWidgetsButton: View {
    @ObservedObject var model: PanelModel
    @State private var hover = false
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let editing = model.editingWidgets
        let donate = !editing && PanelModel.donateButtonShown(available: model.donateAvailable,
                                                              hiddenAt: model.donateHiddenAt, now: model.now)
        HStack {
            if !donate { Spacer(minLength: 0) }
            Button { model.setEditingWidgets(!editing) } label: {
                Text(editing ? "Готово" : "Изменить виджеты").font(.system(size: 11, weight: editing ? .semibold : .regular))
                    .lineLimit(1).fixedSize()
                    .foregroundColor(editing ? PanelColor.ink : (hover ? PanelColor.text : PanelColor.sub))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(editing ? accent : Color.white.opacity(hover ? 0.06 : 0)))
                    .overlay(Capsule().strokeBorder(editing ? Color.clear : PanelColor.frame, lineWidth: 1))
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .handCursor()
            .help(editing ? "Закончить правку (Esc)"
                  : "Скрыть, переставить и сделать шире блоки панели — блоки покачиваются, «−» скрывает, кружок — ширина")
            Spacer(minLength: 0)
            if donate { DonateQuietButton(model: model) }
        }
        .padding(.top, 2)
    }
}

/// Неброская «Поддержать автора» и слабый крестик рядом: скрывает всё вместе на 100 часов (слово 03.11.2026).
private struct DonateQuietButton: View {
    @ObservedObject var model: PanelModel
    @State private var hover = false
    @State private var hoverClose = false

    var body: some View {
        HStack(spacing: 2) {
            Button { model.actions.donate() } label: {
                Text("Поддержать автора").font(.system(size: 11))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundColor(hover ? PanelColor.text : PanelColor.sub)
                    .frame(height: 22)
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .handCursor()
            .help("Окно «Поддержать автора»")
            Button { model.donateHiddenAt = Date() } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .medium))
                    .foregroundColor(hoverClose ? PanelColor.text : PanelColor.sub.opacity(0.6))
                    .frame(width: 16, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .onHover { hoverClose = $0 }
            .handCursor()
            .help("Скрыть, кнопка вернётся через 100 часов")
        }
    }
}

/// «Скрытые: + Fable + Память» — подписи-кнопки по левому краю под блоками; нажатие возвращает блок на его место.
private struct HiddenWidgetsRow: View {
    @ObservedObject var model: PanelModel
    let items: [PanelWidgetLayout.Item]
    @Environment(\.panelType) private var type

    var body: some View {
        // WF253: скрыто много — не вылезает за панель, а переносится рядами под подписью.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                caption
                ForEach(items) { item in button(item) }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                caption
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10, alignment: .leading)],
                          alignment: .leading, spacing: 4) {
                    ForEach(items) { item in button(item) }
                }
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    /// «Скрытые» — подпись набора шрифтов, как имена блоков (WF267).
    private var caption: some View { type.label.text("Скрытые").fixedSize() }

    private func button(_ item: PanelWidgetLayout.Item) -> some View {
        Button { model.changeLayout { $0.setHidden(item.id, false) } } label: {
            Text("+ " + (item.widget?.title ?? item.id)).font(.system(size: 11)).foregroundColor(PanelColor.text)
                .fixedSize()
        }
        .buttonStyle(PressStyle())
        .handCursor()
        .help("Вернуть блок «\(item.widget?.title ?? item.id)»")
    }
}

/// Блок сетки (файл 53, вариант 2 и меню правой кнопки из варианта 1; слово Элвиса 22.10.2026: «Изменить виджеты…
/// Вот это классно… правую кнопку тоже нужно сделать»). Обычно: шеврон у названия, нажатие по строке названия
/// сворачивает, по свёрнутой строке — разворачивает; зажал на 0,35 с — тащишь (Esc — отмена); правый клик — меню.
/// В правке: блок покачивается, «−» слева скрывает, кружок справа — ширина, тащится сразу, содержимое не нажимается.
private struct WidgetCell<Content: View>: View {
    @ObservedObject var model: PanelModel
    let item: PanelWidgetLayout.Item
    /// Один в ряду — стоит во всю ширину (WF187): «во всю ширину · половина» ему не нужны.
    let alone: Bool
    let frames: [String: CGRect]
    let visible: Set<String>
    @ViewBuilder let content: () -> Content
    @Environment(\.pmpAccent) private var accent
    @State private var title: CGRect = .zero
    @State private var hot = false
    @State private var wiggle = false
    @GestureState private var pressing = false

    private var dragging: Bool { model.widgetDrag?.id == item.id }
    private var lifted: Bool { dragging && model.widgetDrag?.cancelled == false }
    private var canToggle: Bool { !alone && (!item.wide || item.widget?.canNarrow == true) }
    private var editing: Bool { model.editingWidgets }
    private var spring: Animation { model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings }

    var body: some View {
        Group {
            if item.collapsed, let widget = item.widget {
                Button { model.tapRow(item.id, visible: visible) } label: { collapsedLine(widget) }
                .buttonStyle(PressStyle(scale: 0.99))
                .handCursor()
                .help("Нажми — развернуть")
            } else {
                content()
            }
        }
            .allowsHitTesting(!editing)
            .disabled(dragging)
            .environment(\.panelNarrow, !item.wide && !alone)
            .environment(\.panelFill, true)
            .environment(\.widgetFold, item.collapsed)
            .environment(\.widgetVisible, visible)
            .environment(\.widgetHot, hot && !editing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hot && !editing && item.collapsed ? 0.035 : 0)))
            // Строка названия развёрнутого блока — свернуть (файл 53, 4.3). Над заголовком, чтобы кнопки рядом с ним
            // (шестерёнка «Оформления») оставались своими.
            .overlay(alignment: .topLeading) {
                if !item.collapsed, !editing, title != .zero {
                    Color.clear
                        .frame(width: title.width + 12, height: title.height + 12)
                        .contentShape(Rectangle())
                        .onTapGesture { fold() }
                        .offset(x: title.minX - 6, y: title.minY - 6)
                        .handCursor()
                        .help("Свернуть в строку")
                        .accessibilityElement()
                        .accessibilityLabel("Свернуть «\(item.widget?.title ?? "")»")
                        .accessibilityAddTraits(.isButton)
                        // #11171 (WF297): без действия у элемента не было AXPress — свернуть клавиатурой и VoiceOver
                        // можно было только через контекстное меню.
                        .accessibilityAction(.default) { fold() }
                }
            }
            .simultaneousGesture(editing ? nil : LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(widgetSpace)))
                .updating($pressing) { value, state, _ in
                    if case .second(true, _) = value { state = true }
                }
                .onChanged { value in
                    guard case .second(true, let drag) = value, let drag = drag else { return }
                    over(drag.location)
                }
                .onEnded { _ in model.endWidgetDrag() })
            // В правке блок тащится сразу, без долгого нажатия (файл 53, 2.4).
            .gesture(editing ? DragGesture(minimumDistance: 2, coordinateSpace: .named(widgetSpace))
                .onChanged { over($0.location) }
                .onEnded { _ in model.endWidgetDrag() } : nil)
            .coordinateSpace(name: widgetCellSpace)
            .onPreferenceChange(WidgetTitleKey.self) { title = $0 }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: WidgetFramesKey.self,
                                       value: [item.id: proxy.frame(in: .named(widgetSpace))])
            })
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(lifted ? 0.7 : 0), lineWidth: 1.5))
            .overlay(alignment: .topLeading) { if editing { editBadges } }
            .rotationEffect(.degrees(editing && !lifted && !model.reduceMotion ? (wiggle ? 0.6 : -0.6) : 0))
            .scaleEffect(lifted && !model.reduceMotion ? 1.02 : 1)
            .shadow(color: Color.black.opacity(lifted ? 0.45 : 0), radius: 12, y: 6)
            .animation(PanelSpring.press, value: lifted)
            .onHover { inside in hot = inside }
            .onChange(of: editing) { on in startWiggle(on) }
            .onAppear { startWiggle(editing) }
            .contextMenu { menu }
            .onChange(of: pressing) { down in if !down { model.endWidgetDrag() } }
    }

    /// Свёрнутая строка блока. Своей функцией: в `body` выражение компилятор не успевал проверить.
    private func collapsedLine(_ widget: PanelWidget) -> CollapsedWidget {
        let spark: AnyView? = PanelModel.chartWidgets.contains(widget) && (item.wide || alone)
            ? AnyView(collapsedSpark(widget, model: model)) : nil
        var line = CollapsedWidget(title: widget.title, value: model.collapsedValue(widget),
                                   tone: model.collapsedTone(widget),
                                   swatch: widget == .colors ? model.colorsSwatch : nil, spark: spark)
        line.sharesScale = !CollapsedWidget.ownScale.contains(widget)
        return line
    }

    private func over(_ location: CGPoint) {
        let hit = frames.first { $0.key != item.id && $0.value.contains(location) }?.key
        model.dragWidget(item.id, over: hit)
    }

    private func fold() {
        guard model.widgetDrag == nil else { return }
        model.toggleRow(item.id, visible: visible)
    }

    /// Покачивание правки — как у значков на iPhone; «Уменьшить движение» — без него.
    private func startWiggle(_ on: Bool) {
        guard on, !model.reduceMotion else {
            withAnimation(.easeOut(duration: 0.1)) { wiggle = false }
            return
        }
        wiggle = false
        withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)
            .delay(Double(abs(item.id.hashValue % 7)) * 0.02)) { wiggle = true }
    }

    /// «−» на левом верхнем углу — скрыть; кружок на правом — во всю ширину / половина (файл 53, 2.3).
    private var editBadges: some View {
        HStack(spacing: 0) {
            EditBadge(symbol: "minus", help: "Скрыть блок «\(item.widget?.title ?? "")» — вернуть: «Скрытые» внизу") {
                model.changeLayout { $0.setHidden(item.id, true) }
            }
            Spacer(minLength: 0)
            if canToggle {
                EditBadge(symbol: item.wide ? "rectangle.split.2x1" : "rectangle",
                          help: item.wide ? "Половина — рядом с соседним блоком" : "Во всю ширину") {
                    model.changeLayout { $0.toggleWidth(item.id) }
                }
            }
        }
        // «−» — за левый угол, как у виджетов macOS; ширина — внутри правого угла: в ряду из двух она не наезжает на
        // «−» соседа.
        .offset(y: -7)
        .padding(.leading, -7)
        .padding(.trailing, 8)
    }

    /// Правый клик по блоку (файл 53, 1.2): то же, что видно в правке, и ещё порядок.
    @ViewBuilder private var menu: some View {
        Button(item.collapsed ? "Развернуть" : "Свернуть") { model.toggleRow(item.id, visible: visible) }
        Button(item.wide ? "Половина — рядом с соседним" : "Во всю ширину") {
            model.changeLayout { $0.toggleWidth(item.id) }
        }
        .disabled(!canToggle)
        Button("Сдвинуть выше") { model.changeLayout { $0.shift(item.id, by: -1, visible: visible) } }
            .disabled(model.layout.neighbor(item.id, by: -1, visible: visible) == nil)
        Button("Сдвинуть ниже") { model.changeLayout { $0.shift(item.id, by: 1, visible: visible) } }
            .disabled(model.layout.neighbor(item.id, by: 1, visible: visible) == nil)
        Divider()
        Button("Скрыть блок") { model.changeLayout { $0.setHidden(item.id, true) } }
        Button("Вернуть как было") { model.changeLayout { $0 = .standard } }
            .disabled(model.layout.isStandard)
        Divider()
        Button(editing ? "Готово" : "Изменить виджеты…") { model.setEditingWidgets(!editing) }
    }
}

/// Круглый значок правки на углу блока: «−» скрыть, ширина.
private struct EditBadge: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                .foregroundColor(PanelColor.text)
                .frame(width: 18, height: 18)
                .background(Circle().fill(PanelColor.hex(hover ? 0x4A4A4E : 0x3A3A3D)))
                .overlay(Circle().strokeBorder(PanelColor.panel, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .handCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

/// #10704 (снимок Элвиса 23.10.2026: «ПАМЯТЬ» крупнее «ПРОЦЕССОРА» и «ТОКЕНОВ» — их ужимал `minimumScaleFactor`): подписи
/// свёрнутых блоков сетки — одним кеглем. Каждый блок сообщает, во сколько надо ужать его подпись, чтобы строка вошла
/// целиком (1 — входит); сетка (`WidgetBoard`) берёт наименьшее и ставит его всем.
struct CollapsedScaleKey: PreferenceKey {
    static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

private struct CollapsedScaleEnvironment: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Общий кегль подписей свёрнутых блоков (доля от роли `label`), ставит `WidgetBoard`.
    var collapsedLabelScale: CGFloat {
        get { self[CollapsedScaleEnvironment.self] }
        set { self[CollapsedScaleEnvironment.self] = newValue }
    }
}

/// Свёрнутый блок (WF269, #10205): одна строка — имя блока с шевроном › и главное число справа; у «Оформления» —
/// кружок цвета окон и имя темы (слово Элвиса 22.10.2026: «должно показывать изначально… какой цвет установлен»).
struct CollapsedWidget: View {
    let title: String
    let value: String?
    /// Цвет числа: хорошо — акцент (`collapsedTone`); nil — цветом текста.
    var tone: Color? = nil
    var swatch: WindowColorChip? = nil
    /// Строка во всю ширину у блока с графиком — линия за 3 ч между названием и числом.
    var spark: AnyView? = nil
    /// Своя доля ужатия входит в общую (`CollapsedScaleKey`); false — подпись ужимается сама, остальных не трогает.
    var sharesScale = true
    @Environment(\.panelType) private var type
    @Environment(\.collapsedLabelScale) private var shared
    /// Ступени ужатия подписи (#10704): первая, при которой строка входит, — доля этого блока.
    static let scales: [CGFloat] = [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6]

    var body: some View {
        line(scale: shared, measure: false)
            // Своя доля — на той же ширине, скрыто; не зависит от общей — общая не залипает на малом. Долю дают строки
            // «имя · короткое число»: у линии графика, кружка темы и длинного счёта Workflow уступает не имя.
            .background(Group {
                if sharesScale, Self.measured(value: value, swatch: swatch != nil, spark: spark != nil) {
                    ViewThatFits(in: .horizontal) {
                        ForEach(Self.scales, id: \.self) { scale in
                            line(scale: scale, measure: true).preference(key: CollapsedScaleKey.self, value: scale)
                        }
                    }
                    .hidden()
                }
            })
            .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
            .card()
            .accessibilityElement(children: .combine)
            .accessibilityHint("Свёрнут")
    }

    /// Свою долю ужатия считают только строки «имя · короткое число». «Оформление» её не задаёт: в раскладке Элвиса
    /// (#10704) оно половинкой, и его длинная строка ужимала бы подписи всей панели (WF298).
    static func measured(value: String?, swatch: Bool, spark: Bool) -> Bool {
        !spark && !swatch && (value?.count ?? 0) <= 10
    }

    /// #10993 (слово Элвиса 27.10.2026: «не проц, там процессор»): «Процессор · 100 %» в половинку целиком входит не
    /// каждым набором — общую долю он не задаёт (иначе подписи всей панели мельчали до 0,7), ужимается сам.
    static let ownScale: Set<PanelWidget> = [.cpu]

    /// Кружок вместо длинного значения «Оформления», когда оно в строку не входит (#11180: в половинке резалось
    /// «ОФОРМЛЕ…», «Свой у каждо…»): у каждого проекта свой — разноцветный, как у Claude — цветами Claude.
    enum ColorMark { case byProject, plain }

    static func colorMark(_ value: String?) -> ColorMark? {
        switch value {
        case PanelColorTiles.byProjectName: return .byProject
        case PanelColorTiles.plainName: return .plain
        default: return nil
        }
    }

    /// Подпись роли `label` в доле `scale` (кегль и разрядка).
    private func label(_ scale: CGFloat) -> PanelTextStyle {
        var style = type.label
        style.size *= scale
        style.tracking *= scale
        return style
    }

    /// Строка блока. `measure` — для замера доли: подпись целиком, без ужатия.
    private func line(scale: CGFloat, measure: Bool) -> some View {
        // Без линии графика между подписью и числом — один зазор строки, не два вокруг распорки (#10704).
        // По центру, а не по базовой линии (слово 03.11.2026: «к нижней части как будто они прижаты»): подпись мельче
        // числа, по общей базовой линии она садилась низко.
        HStack(alignment: .center, spacing: spark == nil ? 0 : 8) {
            // #10461: половинкой в ряд «Температура · Память» имя целиком — ужимается, а не «ТЕМПЕРАТ…»; короткое число
            // («40°», «1 дн 21 ч») — всегда целиком. Длинный счёт Workflow сам уступает имени.
            let short = (value?.count ?? 0) <= 10
            let mark = swatch == nil ? Self.colorMark(value) : nil
            Group {
                if measure {
                    label(scale).text(title).lineLimit(1).fixedSize()
                } else {
                    label(scale).text(title).lineLimit(1).minimumScaleFactor(0.6).allowsTightening(true)
                }
            }
            .widgetTitle()
            .layoutPriority(short || swatch != nil || mark != nil ? 1 : 0)
            if let spark = spark {
                spark
            } else {
                Spacer(minLength: 8)
            }
            if let swatch = swatch {
                // Имя темы — когда входит; в половинке — только кружок цвета, имя в подсказке.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        dot(swatch)
                        type.note.text(value ?? "", color: PanelColor.text).lineLimit(1).fixedSize()
                    }
                    dot(swatch)
                }
                .help(value ?? "")
            } else if let value = value {
                if let mark = mark {
                    // Как у кружка темы: имя целиком, когда входит; нет — только кружок, имя в подсказке. Без «…».
                    ViewThatFits(in: .horizontal) {
                        type.note.text(value, color: PanelColor.text).lineLimit(1).fixedSize()
                        markDot(mark)
                    }
                    .help(value)
                } else if value.count > 10 {
                    // Счёт Workflow — целиком, ужимается, а не «…».
                    type.value.text(value, color: tone).lineLimit(1).minimumScaleFactor(0.6).allowsTightening(true)
                } else if short {
                    type.value.text(value, color: tone).lineLimit(1).fixedSize()
                }
            }
            if value == nil || swatch != nil || mark != nil {
                // Числа нет («Оформление», пустой Workflow) — строка той же высоты, имя на той же линии, что у соседа.
                type.value.text("0").lineLimit(1).fixedSize().hidden().frame(width: 0).accessibilityHidden(true)
            }
        }
    }

    /// Кружок «Оформления» без темы (#11180): разноцветный — у каждого проекта свой; фон и акцент Claude — как у Claude.
    @ViewBuilder private func markDot(_ mark: ColorMark) -> some View {
        switch mark {
        case .plain:
            dot(WindowColorChip(id: "plain", name: PanelColorTiles.plainName, background: "#262624", accent: "#D97757",
                                light: false))
        case .byProject:
            Circle().fill(AngularGradient(colors: [.purple, .blue, .teal, .green, .orange, .pink, .purple],
                                          center: .center))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .frame(width: 12, height: 12)
        }
    }

    /// Кружок цвета окон: фон темы, нижняя половина — её акцент.
    private func dot(_ swatch: WindowColorChip) -> some View {
        Circle().fill(PanelColor.css(swatch.background))
            .overlay(Circle().trim(from: 0.5, to: 1).fill(PanelColor.css(swatch.accent)).rotationEffect(.degrees(180)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .frame(width: 12, height: 12)
    }
}
