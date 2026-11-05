import AppKit
import ClaudeAX
import SwiftUI

// MARK: блок «Workflow» (#10239)

/// Блок Workflow — порт блока PMP Tray для Windows (`pimp-tray/PimpTray.cs`, WorkflowBody; слово Элвиса 19.10.2026
/// 04:55: «вернуть таким, как он на Windows был. Там грамотно всё»). Шапка: «Workflow» и счёт «2 готово · 2 идут ·
/// 2 впереди» — числа нажимаются (фильтр), над счётом — легенда знаков; нажатие шапки — раскрыть или свернуть.
/// Раскрыт: полоса по отрезку на Workflow, строки выбранной группы порциями по 5 под заголовками проектов
/// («‹ 1–5 из 13 ›»), у «идут» — «Впереди · N» (раскрытое помнится). Нажатие строки — карточка на месте блока:
/// ‹ точки › и ✕, этапы с кружками, кто и на чём, когда; листают стрелки, точки, ← →, свайп. Знаки — единой схемой
/// (`WorkflowBlock.Mark`), идущее мерцает (≈1,6 с; «Уменьшить движение» — без мерцания). Данные и слова —
/// `WorkflowBlock` (ClaudeAX).
struct WorkflowBlockView: View {
    @ObservedObject var model: PanelModel
    @Environment(\.panelType) private var type
    @State private var headHover = false
    /// Над каким числом курсор — подпись легенды.
    @State private var under: WorkflowBlock.Filter?

    var body: some View {
        let groups = model.workflowGroups
        // Ничего не идёт (#10315, только живое) — одна строка, без чисел и раскрытия.
        let idle: String? = groups.flatMap { WorkflowBlock.idleLine($0) }
        let open = model.workflowOpen && idle == nil
        Group {
            if let idle = idle {
                // #10461 (слово Элвиса 21.10.2026: «Там только рабочие worblow должны быть и всё»): строк
                // «Ждёт тебя» проектов без идущего Workflow в блоке нет — только строка.
                idleRow(idle)
            } else if open, let groups = groups, let group = model.flow.cardGroup(groups) {
                FlowCardView(model: model, group: group)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    head(groups, open: open).zIndex(1)
                    if open { list(groups) }
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: open ? 7 : 9, trailing: 12))
        .card()
    }

    /// «Workflow» и «Сейчас ничего не идёт · готово N» (период — в шапке «Workflow · 24 ч») (#10315): нажимать нечего — шеврона нет. Не влезает
    /// в ширину — «Ничего не идёт · …», число готовых не обрезается.
    private func idleRow(_ text: String) -> some View {
        let short: String = text.replacingOccurrences(of: "Сейчас ничего", with: "Ничего")
        return HStack(spacing: 0) {
            type.label.text(PanelTiles.dayTitle).fixedSize().widgetTitle()
            ViewThatFits(in: .horizontal) {
                type.note.text(text).lineLimit(1).fixedSize()
                type.note.text(short).lineLimit(1).fixedSize()
                type.note.text(short).lineLimit(1).truncationMode(.tail)
            }
            .padding(.leading, 10)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 18)
        // Открытая карточка не видна — не держит Esc и стрелки.
        .onAppear { if model.flow.card != nil { model.flow.card = nil } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workflow")
        .accessibilityValue(text)
    }

    private func filter(_ groups: WorkflowBlock.Groups?) -> WorkflowBlock.Filter {
        guard let groups = groups else { return .run }
        return (groups[model.flow.filter] ?? []).isEmpty ? .run : model.flow.filter
    }

    /// Шапка: «Workflow», счёт и шеврон; нажатие мимо чисел — раскрыть или свернуть.
    private func head(_ groups: WorkflowBlock.Groups?, open: Bool) -> some View {
        HStack(spacing: 0) {
            type.label.text(PanelTiles.dayTitle).fixedSize().widgetTitle()
            if let groups = groups {
                FlowCounts(model: model, counts: WorkflowBlock.counts(groups), filter: filter(groups), open: open,
                           under: $under)
                    .padding(.leading, 10)
                    .layoutPriority(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                .foregroundColor(headHover ? PanelColor.text : PanelColor.sub)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .frame(minHeight: 18)
        // Легенда — под счётом, по правой грани блока: не вылезает за панель; поверх строк и соседних блоков.
        .overlay(alignment: .topTrailing) {
            if model.workflowLegend, let groups = groups {
                let counts = WorkflowBlock.counts(groups)
                FlowLegend(lines: WorkflowBlock.legend(counts, motion: !model.reduceMotion),
                           hint: WorkflowBlock.legendHint(counts, under: under, filter: filter(groups), open: open),
                           motion: !model.reduceMotion)
                    .offset(x: 4, y: 26)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggleWorkflow() }
        .onHover { headHover = $0 }
        .handCursor()
        .help(open ? "Свернуть" : "Раскрыть Workflow")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workflow")
        .accessibilityValue(groups.map(WorkflowBlock.countsLine) ?? "Читаю проекты…")
        .accessibilityAddTraits(.isButton)
        // #11181 (WF298): без действия AXPress не сворачивал блок — как #11171.
        .accessibilityAction(.default) { model.toggleWorkflow() }
    }

    @ViewBuilder private func list(_ groups: WorkflowBlock.Groups?) -> some View {
        let filter = filter(groups)
        let shown = groups?[filter] ?? []
        let planned = groups?[.plan] ?? []
        VStack(alignment: .leading, spacing: 0) {
            if let groups = groups {
                let strip = WorkflowBlock.strip(groups)
                if !strip.isEmpty {
                    FlowStrip(marks: strip, filter: filter, motion: !model.reduceMotion)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }
            }
            if shown.isEmpty {
                type.note.text(groups == nil ? "Читаю проекты…" : "Сейчас ничего не идёт")
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .padding(.top, 4)
            } else {
                FlowRows(model: model, rows: shown, ahead: false)
            }
            if filter == .run, !planned.isEmpty {
                AheadRow(model: model, count: planned.count)
                if model.aheadOpen { FlowRows(model: model, rows: planned, ahead: true) }
            }
        }
        .transition(.opacity)
    }
}

// MARK: знаки единой схемы

/// Мерцание идущего: 0…1, вдох-выдох ≈1,6 с по общим часам — все знаки мерцают вместе; без движения — 1.
private struct Pulse<Content: View>: View {
    let motion: Bool
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.flowStill) private var still

    var body: some View {
        if motion && !still {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                content(0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.6))
            }
        } else {
            content(1)
        }
    }
}

/// Невидимая копия (порции и страницы карточки держат высоту) — без мерцания: часы зря не крутятся.
private struct FlowStillKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var flowStill: Bool {
        get { self[FlowStillKey.self] }
        set { self[FlowStillKey.self] = newValue }
    }
}

enum FlowColor {
    static func of(_ mark: WorkflowBlock.Mark, accent: Color) -> Color {
        switch mark {
        case .done: return PanelColor.good(accent)
        case .run: return accent
        case .wait: return PanelColor.warn
        case .fail: return PanelColor.bad
        case .plan: return PanelColor.sub.opacity(0x55 / 255.0)
        }
    }

    static let alpha = { (value: Int) in Double(value) / 255 }
}

/// Полоска-знак: готово, ждёт, упал — залитая; идёт — рамочка с мерцанием; впереди — серая тусклая. `strong` —
/// из выбранной группы (иначе бледнее); `lit` — серая выбрана фильтром «впереди».
private struct FlowMark: View {
    let mark: WorkflowBlock.Mark
    var strong = true
    var lit = false
    let motion: Bool
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        if mark == .run {
            Pulse(motion: motion && strong) { p in
                ZStack {
                    Capsule().fill(accent.opacity(strong ? FlowColor.alpha(0x10) + FlowColor.alpha(0x30) * p : 0))
                    Capsule().strokeBorder(accent.opacity(strong ? FlowColor.alpha(0x70) + FlowColor.alpha(0x8F) * p
                                                           : FlowColor.alpha(0x60)), lineWidth: 1.4)
                }
            }
        } else {
            let base = lit ? PanelColor.sub.opacity(FlowColor.alpha(0xB0)) : FlowColor.of(mark, accent: accent)
            Capsule().fill(!strong && mark != .plan ? base.opacity(FlowColor.alpha(0x48)) : base)
        }
    }
}

/// Ячейка номера по состоянию Workflow: идёт — рамочка с мерцанием, остальное — залито; двузначный — шире.
private struct FlowCell: View {
    let number: Int
    let mark: WorkflowBlock.Mark
    let motion: Bool
    @Environment(\.pmpAccent) private var accent

    static func width(_ number: Int) -> CGFloat { number >= 10 ? 21 : 16 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            if mark == .run {
                Pulse(motion: motion) { p in
                    ZStack {
                        shape.fill(accent.opacity(FlowColor.alpha(0x0C) + FlowColor.alpha(0x28) * p))
                        shape.strokeBorder(accent.opacity(FlowColor.alpha(0x80) + FlowColor.alpha(0x7F) * p), lineWidth: 1.4)
                    }
                }
            } else {
                shape.fill(FlowColor.of(mark, accent: accent))
            }
            Text(verbatim: "\(number)").font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundColor(mark == .run ? PanelColor.text : mark == .plan ? PanelColor.sub : PanelColor.ink)
        }
        .frame(width: Self.width(number), height: 16)
    }
}

/// Полоса над списком — по отрезку на Workflow; выбранная фильтром группа — в полный цвет, остальные бледно.
private struct FlowStrip: View {
    let marks: [WorkflowBlock.Mark]
    let filter: WorkflowBlock.Filter
    let motion: Bool

    var body: some View {
        HStack(spacing: marks.count > 30 ? 1.5 : 3) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                FlowMark(mark: mark, strong: WorkflowBlock.picked(mark, filter: filter),
                         lit: filter == .plan && mark == .plan, motion: motion)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: счёт и легенда

/// Счёт в шапке: число жирным, подпись обычным; серым (выбранный — цветом текста), ждёт — жёлтым, упал — красным,
/// ноль — бледнее и не нажимается. Не влезает — часть долой (`variants`). Курсор на счёте 0,45 с — легенда.
private struct FlowCounts: View {
    @ObservedObject var model: PanelModel
    let counts: [WorkflowBlock.Count]
    let filter: WorkflowBlock.Filter
    let open: Bool
    @Binding var under: WorkflowBlock.Filter?
    @State private var pending: DispatchWorkItem?
    @Environment(\.panelType) private var type

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(variants.enumerated()), id: \.offset) { _, items in row(items).fixedSize() }
        }
        .onHover(perform: hover)
        .onDisappear {
            pending?.cancel()
            if model.workflowLegend { model.workflowLegend = false }
        }
    }

    /// Все числа; не влезли — долой «впереди», потом «готово», потом «идут» (выбранное остаётся). «Ждёт» и «упал» —
    /// зов, их не прячем (на Windows уходили с конца — первым терялся «упал»).
    private var variants: [[WorkflowBlock.Count]] {
        var out = [counts]
        var items = counts
        for key in [WorkflowBlock.Filter.plan, .done, .run] where key != filter {
            guard let at = items.firstIndex(where: { $0.filter == key }) else { continue }
            items.remove(at: at)
            out.append(items)
        }
        return out
    }

    private func row(_ items: [WorkflowBlock.Count]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, count in
                if index > 0 { type.note.text("·").padding(.horizontal, 1) }
                FlowCountButton(count: count, picked: open && count.filter == filter && count.on) {
                    model.pickWorkflowFilter(count.filter)
                } hover: { inside in
                    if inside { under = count.filter } else if under == count.filter { under = nil }
                }
            }
        }
    }

    private func hover(_ inside: Bool) {
        pending?.cancel()
        pending = nil
        if inside {
            let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.15)) { model.workflowLegend = true } }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        } else if model.workflowLegend {
            withAnimation(.easeOut(duration: 0.1)) { model.workflowLegend = false }
        }
    }
}

private struct FlowCountButton: View {
    let count: WorkflowBlock.Count
    let picked: Bool
    let action: () -> Void
    let hover: (Bool) -> Void
    @State private var over = false
    @Environment(\.panelType) private var type

    var body: some View {
        let call = count.filter == .wait || count.filter == .fail
        let tint = count.filter == .wait ? PanelColor.warn : count.filter == .fail ? PanelColor.bad : PanelColor.sub
        let color = !count.on ? PanelColor.sub.opacity(FlowColor.alpha(0x90)) : picked && !call ? PanelColor.text : tint
        let fill = call && count.on ? tint : Color.white
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "\(count.number)").font(.system(size: 12.5, weight: .bold).monospacedDigit())
                    .foregroundColor(color)
                type.note.text(count.word, color: color)
            }
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: 22)
            .background(Capsule().fill(fill.opacity(picked ? (over ? 0.2 : 0.15) : over && count.on ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .disabled(!count.on)
        .onHover { inside in
            over = inside
            hover(inside)
        }
        .accessibilityLabel("\(count.number) \(count.word)")
        .accessibilityHint(count.on ? "Показать только эти" : (count.zeroTip ?? ""))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// Легенда счёта: те же знаки, что в полосе, строках и карточке, и что делает нажатие на число.
private struct FlowLegend: View {
    let lines: [(mark: WorkflowBlock.Mark, text: String)]
    let hint: String
    let motion: Bool
    @Environment(\.panelType) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 10) {
                    FlowMark(mark: line.mark, motion: motion).frame(width: 22, height: 6)
                    type.note.text(line.text, color: PanelColor.text).fixedSize()
                }
                .frame(height: 20)
            }
            type.note.text(hint).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
        .frame(width: 210, alignment: .leading)
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelColor.panel))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.19), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.4), radius: 8, y: 3)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: строки

/// Строки группы порциями по 5: над строками проекта — его имя заголовком; больше порции — «‹ 1–5 из 13 ›».
/// Высота — по самой высокой порции: листаешь — «‹ ›» и всё ниже стоят на месте.
private struct FlowRows: View {
    @ObservedObject var model: PanelModel
    let rows: [WorkflowBlock.Row]
    let ahead: Bool

    var body: some View {
        let pages = WorkflowBlock.pages(rows.count)
        let page = min(max(0, ahead ? model.flow.aheadPage : model.flow.page), pages - 1)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ForEach(0..<pages, id: \.self) { index in
                    let current = index == page
                    portion(index)
                        .environment(\.flowStill, !current)
                        .opacity(current ? 1 : 0)
                        .allowsHitTesting(current)
                        .accessibilityHidden(!current)
                }
            }
            if pages > 1 {
                PageRow(page: page, pages: pages, count: rows.count) { step in
                    model.turnWorkflowPage(step, ahead: ahead)
                }
            }
        }
    }

    private func portion(_ page: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(WorkflowBlock.portion(rows, page: page)) { item in
                switch item {
                case .head(let name, let count, _):
                    ProjectHead(name: name, count: count)
                case .row(let row):
                    FlowRowView(model: model, row: row, inCard: false) { model.openWorkflowCard(row.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Заголовок проекта над его строками: имя жирным бледно, счёт — обычным; по левой грани ячеек номера.
private struct ProjectHead: View {
    let name: String
    let count: Int
    @Environment(\.panelType) private var type

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            type.note.weight(.semibold).text(name).lineLimit(1)
            if count > 1 { type.note.text("· \(count)").fixedSize() }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Листание порций: ‹ и › по краям подписи «6–10 из 13», посередине; на крайней порции стрелка бледная.
private struct PageRow: View {
    let page: Int
    let pages: Int
    let count: Int
    let turn: (Int) -> Void
    @Environment(\.panelType) private var type

    var body: some View {
        HStack(spacing: 6) {
            arrow(-1)
            type.note.text(WorkflowBlock.pageLabel(page: page, count: count)).fixedSize()
            arrow(1)
        }
        .frame(maxWidth: .infinity, minHeight: 24)
        .padding(.top, 2)
    }

    private func arrow(_ side: Int) -> some View {
        let can = side < 0 ? page > 0 : page < pages - 1
        return HoverButton(enabled: can, help: (side < 0 ? "Предыдущие " : "Следующие ") + "\(WorkflowBlock.pageSize)",
                           circle: false) {
            turn(side)
        } label: { over in
            Image(systemName: side < 0 ? "chevron.left" : "chevron.right").font(.system(size: 10, weight: .semibold))
                .foregroundColor(!can ? PanelColor.sub.opacity(0.35) : over ? PanelColor.text : PanelColor.sub)
                .frame(width: 26, height: 24)
        }
    }
}

/// «Впереди · N ⌄»: запланированные под идущими; раскрытое помнится.
private struct AheadRow: View {
    @ObservedObject var model: PanelModel
    let count: Int
    @State private var over = false
    @Environment(\.panelType) private var type

    var body: some View {
        Button {
            withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) { model.aheadOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                type.note.text("Впереди · \(count)", color: over ? PanelColor.text : nil).fixedSize()
                Image(systemName: model.aheadOpen ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundColor(over ? PanelColor.text : PanelColor.sub)
                Spacer(minLength: 0)
            }
            .frame(height: 26)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(over ? 0.06 : 0)))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { over = $0 }
        .handCursor()
        .padding(.top, 4)
        .help(model.aheadOpen ? "Свернуть запланированные" : "Запланированные Workflow — по одному на строку")
    }
}

/// Строка Workflow: [N] короткое имя ……… этап · модель / шаги отрезками ……… «2 из 6 · 42 мин». Готовые
/// и запланированные — тонкой строкой без шагов. В карточке (`inCard`) — шапка страницы: имя проекта вместо
/// короткого имени (под ней «о чём» целиком), без нажатия.
private struct FlowRowView: View {
    @ObservedObject var model: PanelModel
    let row: WorkflowBlock.Row
    let inCard: Bool
    var open: () -> Void = {}
    @State private var over = false
    @Environment(\.panelType) private var type

    var body: some View {
        let slim = !inCard && WorkflowBlock.slim(row)
        let full = WorkflowBlock.rowRight(row, now: model.now)
        let brief = WorkflowBlock.rowRight(row, now: model.now, brief: true)
        let motion = !model.reduceMotion
        let number = row.index + 1
        let second = !slim && (!WorkflowBlock.steps(row).isEmpty || !WorkflowBlock.rowTail(row, now: model.now).isEmpty)
        // Цена Workflow (#6282): во второй строке, а её нет — справа в первой; не влезает — в строке её нет.
        let cost: WorkflowCostItem? = inCard ? nil : model.flowCosts?.cost(row)
        let line = VStack(alignment: .leading, spacing: 0) {
            // Строка без «…» (WF253): этап с моделью и имя в строку; не входит — этап без модели (она в карточке);
            // и так не входит — имя переносится.
            ViewThatFits(in: .horizontal) {
                if !second, let cost = cost { first(full, cost: cost, wrap: false, motion: motion) }
                first(full, wrap: false, motion: motion)
                if brief.text != full.text { first(brief, wrap: false, motion: motion) }
                first(brief, wrap: true, motion: motion)
            }
            // Шагов и времени нет (готовый в карточке, «шаги» не записаны) — второй строки нет.
            if second {
                steps(motion: motion, cost: cost).padding(.leading, FlowCell.width(number) + 6).padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(over && !inCard ? 0.06 : 0)))
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .padding(.vertical, 1)
        if inCard {
            line.accessibilityElement(children: .combine)
        } else {
            line
                .onTapGesture(perform: open)
                .onHover { over = $0 }
                .handCursor()
                .help("Подробнее: этапы, кто и на чём")
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, open)
        }
    }

    /// Ячейка номера, имя и справа этап (ждёт, упал, когда кончился) и цена.
    private func first(_ right: (text: String, tone: WorkflowBlock.Tone), cost: WorkflowCostItem? = nil, wrap: Bool,
                       motion: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            FlowCell(number: row.index + 1, mark: row.mark, motion: motion)
            title.fixedSize(horizontal: !wrap, vertical: true)
            Spacer(minLength: 8)
            if !right.text.isEmpty {
                let tone = right.tone
                (tone == .hot ? type.note.weight(.semibold) : type.note)
                    .text(right.text, color: tone == .wait ? PanelColor.warn : tone == .fail || tone == .hot ? PanelColor.bad
                          : nil)
                    .fixedSize()
            }
            if let cost = cost {
                if !right.text.isEmpty { type.note.text("·").fixedSize() }
                CostLabel(item: cost)
            }
        }
        .frame(minHeight: 24)
    }

    private var title: Text {
        var style = type.value
        style.size = min(style.size, 12.5)
        if inCard { return style.weight(.semibold).text(row.projectName) }
        return style.text(WorkflowBlock.rowName(row), color: row.mark == .plan ? PanelColor.sub : nil)
    }

    /// Шаги отрезками единой схемой и справа «2 из 3 · 25 мин» и цена (#6282): полоса уже 60 pt — цены в строке нет.
    @ViewBuilder private func steps(motion: Bool, cost: WorkflowCostItem?) -> some View {
        let marks = WorkflowBlock.steps(row)
        let tail = WorkflowBlock.rowTail(row, now: model.now)
        if let cost = cost {
            ViewThatFits(in: .horizontal) {
                stepsLine(marks, tail: tail, cost: cost, motion: motion)
                stepsLine(marks, tail: tail, cost: nil, motion: motion)
            }
            .frame(height: 14)
        } else {
            stepsLine(marks, tail: tail, cost: nil, motion: motion).frame(height: 14)
        }
    }

    private func stepsLine(_ marks: [WorkflowBlock.Mark], tail: String, cost: WorkflowCostItem?,
                           motion: Bool) -> some View {
        HStack(spacing: 10) {
            if marks.isEmpty {
                Spacer(minLength: 0)
            } else {
                HStack(spacing: marks.count > 20 ? 1 : 3) {
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                        FlowMark(mark: mark, motion: motion).frame(maxWidth: .infinity)
                    }
                }
                .frame(minWidth: cost == nil ? 0 : 60)
                .frame(height: 6)
            }
            HStack(spacing: 4) {
                if !tail.isEmpty { type.note.text(tail).fixedSize() }
                if let cost = cost {
                    if !tail.isEmpty { type.note.text("·").fixedSize() }
                    CostLabel(item: cost)
                }
            }
        }
    }
}

// MARK: карточка на месте блока (FlowPager, FlowCard)

/// Карточка Workflow на месте блока (пожелание 17.10.2026 ~06:50: «всплывающих окошек не надо — такая же панелька
/// прямо на месте, листать влево-вправо между Workflow, сверху точки-лампочки (на каком ты), дошла до последнего —
/// дальше не идёт»). Сверху ‹ точки ›, справа ✕ — назад к списку (и Esc). Листают стрелки, точки, ← → и свайп
/// по карточке. Высота — по самой высокой странице: при листании блок не прыгает.
private struct FlowCardView: View {
    @ObservedObject var model: PanelModel
    let group: [WorkflowBlock.Row]
    @State private var drag: CGFloat = 0

    var body: some View {
        let at = group.firstIndex { $0.id == model.flow.card } ?? 0
        VStack(spacing: 0) {
            top(at: at)
            ZStack(alignment: .topLeading) {
                // Невидимые страницы держат высоту по самой высокой.
                ForEach(group) { row in
                    FlowPage(model: model, row: row).environment(\.flowStill, true).hidden().accessibilityHidden(true)
                }
                ForEach([group[at]]) { row in
                    FlowPage(model: model, row: row)
                        .transition(slide)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 40 else { return }
                model.turnWorkflowCard(value.translation.width < 0 ? 1 : -1)
            })
            .background(SwipeCatcher { step in model.turnWorkflowCard(step) })
        }
    }

    private var slide: AnyTransition {
        if model.reduceMotion { return .opacity }
        let forward = model.flow.slide > 0
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                           removal: .move(edge: forward ? .leading : .trailing))
    }

    /// ‹ точки › по середине, ✕ справа (на месте шеврона). Точки — знаками единой схемы; на какой ты — крупнее,
    /// в светлом кольце.
    private func top(at: Int) -> some View {
        let n = group.count
        let button: CGFloat = 26
        let room = PimpPanelController.width - 24 - 24 - 2 * 44 - 2 * (button + 6)
        var dot: CGFloat = 7
        var gap: CGFloat = 8
        if CGFloat(n) * dot + CGFloat(n - 1) * gap > room { gap = max(3, (room - CGFloat(n) * dot) / CGFloat(max(1, n - 1))) }
        if CGFloat(n) * dot + CGFloat(n - 1) * gap > room {
            dot = 5
            gap = max(2, (room - CGFloat(n) * dot) / CGFloat(max(1, n - 1)))
        }
        return ZStack {
            HStack(spacing: 6) {
                arrow(-1, can: at > 0)
                HStack(spacing: gap) {
                    ForEach(Array(group.enumerated()), id: \.element.id) { index, row in
                        FlowDot(mark: row.mark, current: index == at, size: dot, motion: !model.reduceMotion,
                                help: row.project.name + " · " + WorkflowBlock.rowName(row)) {
                            model.turnWorkflowCard(to: index, in: group)
                        }
                    }
                }
                arrow(1, can: at < n - 1)
            }
            HStack {
                Spacer()
                HoverButton(enabled: true, help: "К списку Workflow (Esc)") {
                    model.closeWorkflowCard()
                } label: { over in
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(over ? PanelColor.text : PanelColor.sub)
                        .frame(width: button, height: button)
                }
                .padding(.trailing, -7)
            }
        }
        .frame(height: 30)
        .padding(.bottom, 4)
    }

    private func arrow(_ side: Int, can: Bool) -> some View {
        HoverButton(enabled: can, help: side < 0 ? "Предыдущий Workflow (←)" : "Следующий Workflow (→)") {
            model.turnWorkflowCard(side)
        } label: { over in
            Image(systemName: side < 0 ? "chevron.left" : "chevron.right").font(.system(size: 11, weight: .semibold))
                .foregroundColor(!can ? PanelColor.sub.opacity(0.3) : over ? PanelColor.text : PanelColor.sub)
                .frame(width: 26, height: 26)
        }
    }
}

/// Точка листания: готово — залитая зелёная, идёт — колечко с мерцанием, впереди — серая (под курсором — ярче).
private struct FlowDot: View {
    let mark: WorkflowBlock.Mark
    let current: Bool
    let size: CGFloat
    let motion: Bool
    let help: String
    let action: () -> Void
    @State private var over = false
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let d = current ? size + 3 : size
        Button(action: action) {
            ZStack {
                if mark == .run {
                    Pulse(motion: motion) { p in
                        Circle().strokeBorder(accent.opacity(FlowColor.alpha(0x90) + FlowColor.alpha(0x6F) * p), lineWidth: 1.4)
                    }
                    .frame(width: d, height: d)
                } else {
                    Circle().fill(mark == .plan && over ? PanelColor.sub : FlowColor.of(mark, accent: accent))
                        .frame(width: d, height: d)
                }
                if current {
                    Circle().strokeBorder(PanelColor.text.opacity(FlowColor.alpha(0xC0)), lineWidth: 1.2)
                        .frame(width: d + 5, height: d + 5)
                }
            }
            .frame(width: size, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(current)
        .onHover { over = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// Страница карточки: шапка (номер, проект, этап и модель, шаги) и тело — о чём целиком, этапы с кружками и «кто»,
/// когда, «Ждёт тебя: …». Строку «Сейчас: …» не ставим: она про весь проект.
private struct FlowPage: View {
    @ObservedObject var model: PanelModel
    let row: WorkflowBlock.Row
    @Environment(\.panelType) private var type

    var body: some View {
        let flow = row.flow
        let stages = WorkflowBlock.stages(flow)
        let when = WorkflowBlock.when(row.project, flow, now: model.now)
        VStack(alignment: .leading, spacing: 0) {
            FlowRowView(model: model, row: row, inCard: true)
            type.value.text(flow.about.isEmpty ? "Workflow \(row.index + 1)" : flow.about)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 8)
            if stages.isEmpty {
                type.note.text("Роли не записаны в status.md").frame(height: 20, alignment: .leading)
            }
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                StageLine(stage: stage, last: index == stages.count - 1, motion: !model.reduceMotion)
            }
            if !when.isEmpty {
                type.note.text(when).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
            }
            FlowCostLines(model: model, row: row)
            // «Ждёт тебя» с «Не напоминать ▾» (#9820) — у любой активной строки проекта, не только у ✋.
            if let undo = model.flow.waitUndo, undo.inCard, undo.folder == row.project.folder {
                MuteUndoPlate(model: model, undo: undo).padding(.top, 6)
            }
            if [.running, .waiting, .failed].contains(flow.state), model.waitShown(row.project) {
                WaitLine(model: model, project: row.project, inCard: true).padding(.top, 5)
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Этап карточки: кружок (✓ пройден, рамочка с мерцанием — идёт, «!» — ждёт, «✕» — упал, серый — впереди), линия
/// к следующему, название и «кто» справа (Fable и max — красным жирным).
private struct StageLine: View {
    let stage: WorkflowBlock.Stage
    let last: Bool
    let motion: Bool
    @Environment(\.pmpAccent) private var accent
    @Environment(\.panelType) private var type

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            dot
                .frame(width: 12, height: 12)
                .overlay(alignment: .top) {
                    if !last {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1.5, height: 8).offset(y: 15)
                    }
                }
            (stage.mark == .run ? type.note.weight(.semibold) : type.note)
                .text(stage.title, color: stage.mark == .plan ? PanelColor.sub : PanelColor.text)
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)
            Spacer(minLength: 4)
            (stage.hot ? type.note.weight(.semibold) : type.note)
                .text(stage.who, color: stage.hot ? PanelColor.bad : nil)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 22)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var dot: some View {
        switch stage.mark {
        case .done, .wait, .fail:
            ZStack {
                Circle().fill(FlowColor.of(stage.mark, accent: accent))
                Image(systemName: stage.mark == .done ? "checkmark" : stage.mark == .fail ? "xmark" : "exclamationmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(PanelColor.ink)
            }
        case .run:
            Pulse(motion: motion) { p in
                ZStack {
                    Circle().fill(accent.opacity(FlowColor.alpha(0x10) + FlowColor.alpha(0x30) * p))
                    Circle().strokeBorder(accent.opacity(FlowColor.alpha(0x80) + FlowColor.alpha(0x7F) * p), lineWidth: 1.6)
                }
            }
        case .plan:
            Circle().fill(FlowColor.of(.plan, accent: accent))
        }
    }
}

/// Кнопка-значок с подложкой под курсором: круг (стрелки карточки, ✕) или скруглённый прямоугольник.
private struct HoverButton<Label: View>: View {
    let enabled: Bool
    let help: String
    var circle = true
    let action: () -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var over = false

    var body: some View {
        Button(action: action) {
            label(over && enabled)
                .background(Group {
                    if circle { Circle().fill(Color.white.opacity(over && enabled ? 0.08 : 0)) }
                    else { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(over && enabled ? 0.08 : 0)) }
                })
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .onHover { over = $0 }
        .help(enabled ? help : "")
        .accessibilityLabel(help)
    }
}

/// Свайп по карточке двумя пальцами (или колесо с Shift): один жест — одна страница. Ловит прокрутку окна, пока
/// курсор над карточкой; вертикальную отдаёт панели.
private struct SwipeCatcher: NSViewRepresentable {
    let turn: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.turn = turn
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.turn = turn }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.stop() }

    final class CatcherView: NSView {
        var turn: (Int) -> Void = { _ in }
        private var monitor: Any?
        private var sum: CGFloat = 0
        /// Жест уже перелистнул — до его конца больше не листаем.
        private var spent = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self = self, event.window === self.window else { return event }
                return self.take(event) ? nil : event
            }
        }

        func stop() {
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }

        private func take(_ event: NSEvent) -> Bool {
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty && !spent) { sum = 0 }
            if event.phase == .ended || event.phase == .cancelled {
                sum = 0
                spent = false
                return false
            }
            if !event.momentumPhase.isEmpty { return spent }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
            if spent { return true }
            sum += event.scrollingDeltaX
            let limit: CGFloat = event.hasPreciseScrollingDeltas ? 40 : 3
            if abs(sum) >= limit {
                turn(sum < 0 ? 1 : -1)
                sum = 0
                spent = event.hasPreciseScrollingDeltas
            }
            return true
        }
    }
}
