import AppKit
import Charts
import ClaudeAX
import SwiftUI

// Окно «Токены» (WF157, #9149; переделано WF170, #9179): открывается рядом с панелью у часов по плитке «Токены».
// Сверху период («Сегодня · Вчера · 7 дней · Месяц», у Месяца — «Дни / Недели»), крупный итог и сравнение с прошлым
// таким же периодом; ниже ОДИН ряд общего расхода по дням цветом PMP (без стопок по проектам, не накопительный) и
// ранжир проектов за период полосами одной гаммы. Данные и решения — `TokenStats` (ClaudeAX), здесь вид и окно.

final class TokensModel: ObservableObject {
    static let periodKey = "tokensPeriodWF157"
    static let groupingKey = "tokensGroupingWF157"

    @Published var data = TokensDaily.empty
    @Published var loaded = false
    @Published var now = Date()
    @Published var period = TokenPeriod(rawValue: UserDefaults.standard.string(forKey: periodKey) ?? "") ?? .week {
        didSet { UserDefaults.standard.set(period.rawValue, forKey: Self.periodKey) }
    }
    @Published var grouping = TokenGrouping(rawValue: UserDefaults.standard.string(forKey: groupingKey) ?? "") ?? .days {
        didSet { UserDefaults.standard.set(grouping.rawValue, forKey: Self.groupingKey) }
    }
}

final class TokensPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }
}

final class TokensWindowController: NSObject, NSWindowDelegate {
    /// Новый ключ (WF170): старый размер был под одну диаграмму, теперь ещё итог и ранжир.
    static let sizeKey = "tokensWindowSizeWF170"
    static let defaultSize = NSSize(width: 600, height: 640)
    static let minSize = NSSize(width: 440, height: 400)

    let model = TokensModel()
    private var window: TokensPanelWindow?
    private var store: TokensDailyStore?
    private let queue = DispatchQueue(label: "pimpmyclaude.tokens", qos: .utility)

    /// Клик в этом окне — не «мимо» панели.
    static func owns(_ window: NSWindow?) -> Bool { window is TokensPanelWindow }

    /// Хранилище под текущий путь (настройка могла смениться). Только на `queue`.
    private func currentStore() -> TokensDailyStore {
        let url = TokenStats.liveURL()
        if let store = store, store.url == url { return store }
        let fresh = TokensDailyStore(url: url)
        store = fresh
        return fresh
    }

    /// Спарклайн панели за 7 дней; файла нет — nil (плитки нет).
    func spark(_ done: @escaping (TokenSpark?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let store = self.currentStore()
            let exists = FileManager.default.fileExists(atPath: store.url.path)
            let values = exists ? TokenStats.spark(store.load(), now: Date()) : nil
            DispatchQueue.main.async { done(values) }
        }
    }

    /// Перечитать по mtime.
    func refresh() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let data = self.currentStore().load()
            DispatchQueue.main.async {
                self.model.data = data
                self.model.now = Date()
                self.model.loaded = true
            }
        }
    }

    /// Открыть рядом с карточкой панели (слева, нет места — справа), верхом вровень с ней.
    func show(beside card: NSRect, screen: NSScreen?) {
        refresh()
        let window = self.window ?? makeWindow()
        self.window = window
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 875)
        var size = Self.savedSize()
        size.width = min(size.width, visible.width - 16)
        size.height = min(size.height, visible.height - 16)
        var x = card.minX - 10 - size.width
        if x < visible.minX + 8 { x = card.maxX + 10 }
        x = min(max(x, visible.minX + 8), visible.maxX - 8 - size.width)
        let top = min(card.maxY, visible.maxY)
        let y = max(top - size.height, visible.minY + 8)
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    func close() { window?.close() }

    static func savedSize() -> NSSize {
        guard let text = UserDefaults.standard.string(forKey: sizeKey) else { return defaultSize }
        let size = NSSizeFromString(text)
        guard size.width >= minSize.width, size.height >= minSize.height else { return defaultSize }
        return size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let size = window?.frame.size else { return }
        UserDefaults.standard.set(NSStringFromSize(size), forKey: Self.sizeKey)
    }

    private func makeWindow() -> TokensPanelWindow {
        let window = TokensPanelWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                                       styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        window.title = "Токены"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x28 / 255.0, alpha: 1)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.minSize = Self.minSize
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = TokensHostingView(rootView: TokensView(model: model))
        return window
    }
}

private final class TokensHostingView: NSHostingView<TokensView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - вид

struct TokensView: View {
    @ObservedObject var model: TokensModel
    @State private var hover: (id: String, point: CGPoint)?
    @State private var allProjects = false

    private var accent: Color { PanelColor.hex(PMPAccent.current.hex) }
    /// Сколько проектов в ранжире до «ещё N».
    private static let shortList = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TokensSegments(items: TokenPeriod.allCases.map { ($0, $0.title) }, selected: model.period,
                               accent: accent) { model.period = $0; hover = nil; allProjects = false }
                if model.period == .month {
                    Spacer(minLength: 8)
                    TokensSegments(items: TokenGrouping.allCases.map { ($0, $0.title) }, selected: model.grouping,
                                   accent: accent) { model.grouping = $0; hover = nil }
                        .frame(width: 140)
                        .help("Столбик — день или неделя")
                }
            }
            content
        }
        .padding(EdgeInsets(top: 34, leading: 18, bottom: 0, trailing: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelColor.panel)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if !model.loaded {
            centered("Читаю токены…")
        } else if model.data.isEmpty {
            centered("Нет данных — Рик соберёт")
        } else {
            let summary = TokenStats.summary(model.data, period: model.period, grouping: model.grouping, now: model.now)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header(summary)
                    if summary.allPending {
                        note("Рик сегодня ещё не собирал токены — соберёт, и цифры появятся")
                    } else if summary.total == 0 {
                        note("За этот период токенов нет")
                    } else {
                        // WF177 (#9182 п. 8: «графика нет»): у «Сегодня» и «Вчера» — неделя столбиками, свой день ярко.
                        if model.period.isSingleDay {
                            chart(TokenStats.summary(model.data, period: .week, grouping: .days, now: model.now),
                                  focus: summary.points.first?.id).frame(height: 230)
                        } else {
                            chart(summary).frame(height: 230)
                        }
                        ranking(summary)
                    }
                }
                .padding(.bottom, 18)
            }
        }
    }

    // MARK: итог

    private func header(_ summary: TokenSummary) -> some View {
        let caption = model.period.isSingleDay
            ? model.period.title + " · " + TokenStats.dayTitle(summary.points.first?.id ?? "")
            : "Токены · " + model.period.title
        let comparison = TokenStats.comparison(summary)
        let collected = TokenStats.scannedText(model.data.scanned, now: model.now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(caption.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.6)
                    .foregroundColor(PanelColor.sub)
                Spacer(minLength: 8)
                if !collected.isEmpty {
                    Text(collected).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                        .help("Копилку пополняет Рик (token_stats.py); позже этого времени токенов ещё нет")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.allPending ? "—" : TokenStats.human(summary.total))
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundColor(PanelColor.text)
                Text("токенов").font(.system(size: 15)).foregroundColor(PanelColor.sub)
            }
            if !comparison.isEmpty {
                Text(comparison).font(.system(size: 12)).monospacedDigit().foregroundColor(PanelColor.sub)
            }
            if summary.pending && !summary.allPending {
                Text("сегодня Рик ещё не собирал — последний столбик пуст").font(.system(size: 12))
                    .foregroundColor(PanelColor.sub)
            }
        }
    }

    private func centered(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundColor(PanelColor.sub)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundColor(PanelColor.sub)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: главный график — общий расход по дням (неделям), один цвет

    private func chart(_ summary: TokenSummary, focus: String? = nil) -> some View {
        let points = summary.points
        let dense = points.count > 14
        let top = Double(max(1, points.map { $0.value }.max() ?? 1))
        return Chart {
            ForEach(points) { point in
                BarMark(x: .value("День", point.id), y: .value("Токены", Double(point.value)), width: .ratio(dense ? 0.72 : 0.62))
                    .foregroundStyle(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .cornerRadius(dense ? 3 : 6)
                    .opacity(hover.map { $0.id == point.id ? 1 : 0.4 } ?? (focus == nil || focus == point.id ? 1 : 0.4))
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        barLabel(point, summary: summary, dense: dense)
                    }
            }
        }
        .chartYScale(domain: 0...top * 1.18)
        .chartXAxis {
            AxisMarks(values: points.map { $0.id }) { value in
                AxisValueLabel(centered: true) {
                    if let id = value.as(String.self), let point = points.first(where: { $0.id == id }) {
                        VStack(spacing: 1) {
                            Text(point.label).font(.system(size: dense ? 9 : 11))
                                .foregroundColor(id == summary.peak ? PanelColor.text : PanelColor.sub)
                            if !dense && !point.weekday.isEmpty {
                                Text(point.weekday).font(.system(size: 10)).foregroundColor(PanelColor.sub.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self), number > 0 {
                        Text(TokenStats.human(Int(number))).font(.system(size: 10)).foregroundColor(PanelColor.sub)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geometry[proxy.plotAreaFrame].origin
                            guard let id = proxy.value(atX: location.x - origin.x, as: String.self) else { hover = nil; return }
                            hover = (id, location)
                        case .ended:
                            hover = nil
                        }
                    }
                if let hover = hover, let point = points.first(where: { $0.id == hover.id }) {
                    tooltip(point, at: hover.point, in: geometry.size)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hover?.id)
    }

    /// Число над столбиком: у 7 дней и недель — у каждого, у 30 дней — только над пиком; несобранный — «нет».
    @ViewBuilder private func barLabel(_ point: TokenPoint, summary: TokenSummary, dense: Bool) -> some View {
        if point.pending {
            Text(dense ? "·" : "не собрано").font(.system(size: 10)).foregroundColor(PanelColor.sub)
        } else if point.value > 0 && (!dense || point.id == summary.peak) {
            Text(TokenStats.human(point.value))
                .font(.system(size: dense ? 10 : 11, weight: point.id == summary.peak ? .semibold : .regular))
                .monospacedDigit().lineLimit(1).fixedSize()
                .foregroundColor(point.id == summary.peak ? PanelColor.text : PanelColor.sub)
        }
    }

    private func tooltip(_ point: TokenPoint, at location: CGPoint, in size: CGSize) -> some View {
        let text = point.title + " · " + (point.pending ? "ещё не собрано" : TokenStats.human(point.value) + " токенов")
        let width: CGFloat = 230
        let x = min(max(location.x + 14, 4), size.width - width - 4)
        let y = min(max(location.y - 44, 4), size.height - 34)
        return Text(text).font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundColor(PanelColor.text)
            .padding(EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9))
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(PanelColor.ink.opacity(0.96)))
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }

    // MARK: ранжир проектов за период

    private func ranking(_ summary: TokenSummary) -> some View {
        let rows = allProjects ? summary.ranking : Array(summary.ranking.prefix(Self.shortList))
        let hidden = summary.ranking.count - rows.count
        let top = Double(max(1, summary.ranking.first?.value ?? 1))
        return VStack(alignment: .leading, spacing: 8) {
            Text("Проекты").font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
            ForEach(Array(rows.enumerated()), id: \.element.project) { index, row in
                HStack(spacing: 10) {
                    Text(row.project).font(.system(size: 12)).foregroundColor(PanelColor.text).lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 120, alignment: .leading)
                        .help(row.project)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.05))
                            Capsule().fill(accent.opacity(max(0.4, 1 - Double(index) * 0.08)))
                                .frame(width: max(4, geometry.size.width * CGFloat(Double(row.value) / top)))
                        }
                    }
                    .frame(height: 8)
                    Text(TokenStats.human(row.value)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundColor(PanelColor.text).lineLimit(1)
                        .frame(width: 70, alignment: .trailing)
                    Text(row.percent).font(.system(size: 11)).monospacedDigit().foregroundColor(PanelColor.sub)
                        .frame(width: 34, alignment: .trailing)
                }
                .frame(height: 20)
            }
            if hidden > 0 || allProjects && summary.ranking.count > Self.shortList {
                Button {
                    allProjects.toggle()
                } label: {
                    Text(allProjects ? "Свернуть" : "Ещё \(hidden) проект\(Self.ending(hidden))")
                        .font(.system(size: 12)).foregroundColor(PanelColor.sub)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: allProjects)
    }

    static func ending(_ count: Int) -> String {
        let tens = count % 100, ones = count % 10
        if (11...14).contains(tens) { return "ов" }
        if ones == 1 { return "" }
        if (2...4).contains(ones) { return "а" }
        return "ов"
    }
}

/// Переключатель сегментами, как в настройках панели.
private struct TokensSegments<Value: Hashable>: View {
    let items: [(Value, String)]
    let selected: Value
    let accent: Color
    let pick: (Value) -> Void
    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let (value, title) = items[index]
                let chosen = value == selected
                Button { if !chosen { pick(value) } } label: {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundColor(chosen ? PanelColor.ink : PanelColor.text)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(chosen ? accent : Color.white.opacity(hovered == index ? 0.14 : 0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hovered = index } else if hovered == index { hovered = nil }
                }
                .animation(.easeOut(duration: 0.12), value: hovered)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}
