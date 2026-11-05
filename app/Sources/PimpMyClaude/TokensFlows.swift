import ClaudeAX
import SwiftUI

// Окно «Токены», раздел «Workflow за 7 дней» (#6282, слово Элвиса: «Графики по Workflow»): каждый Workflow, чьи прогоны
// начались за 7 дней, — полосой цены по API, дорогие первыми, сверху сумма. Цены и привязка — `WorkflowCost` (ClaudeAX),
// те же, что «≈ $4,20» в блоке Workflow панели; ни у одного нет цены — раздела нет.

struct TokensFlows: View {
    let flows: [WorkflowWeekFlow]
    let accent: Color
    var now = Date()
    @State private var all = false
    /// Сколько Workflow до «Ещё N».
    static let shortList = 8

    var body: some View {
        let rows = all ? flows : Array(flows.prefix(Self.shortList))
        let hidden = flows.count - rows.count
        let top = max(0.01, flows.map(\.item.totals.usd).max() ?? 0)
        let total = WorkflowCostItem(totals: flows.reduce(CostTotals()) { $0 + $1.item.totals },
                                     missing: flows.contains { $0.item.missing })
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Workflow за 7 дней").font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
                Spacer(minLength: 8)
                Text(total.label + " по ценам API").font(.system(size: 12)).monospacedDigit()
                    .foregroundColor(PanelColor.sub).lineLimit(1)
                    .help(total.help)
            }
            ForEach(Array(rows.enumerated()), id: \.element.key) { index, flow in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(flow.about).font(.system(size: 12)).foregroundColor(PanelColor.text)
                            .lineLimit(1).truncationMode(.tail)
                        Text(flow.project + " · " + Self.when(flow.start, now: now)).font(.system(size: 10))
                            .foregroundColor(PanelColor.sub).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(width: 220, alignment: .leading)
                    .help(flow.about)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.05))
                            Capsule().fill(accent.opacity(max(0.4, 1 - Double(index) * 0.08)))
                                .frame(width: max(4, geometry.size.width * CGFloat(flow.item.totals.usd / top)))
                        }
                    }
                    .frame(height: 8)
                    Text(flow.item.label).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundColor(PanelColor.text).lineLimit(1)
                        .frame(width: 84, alignment: .trailing)
                        .help(flow.item.help)
                }
                .frame(height: 30)
                .accessibilityElement(children: .combine)
            }
            if hidden > 0 || all && flows.count > Self.shortList {
                Button {
                    all.toggle()
                } label: {
                    Text(all ? "Свернуть" : "Ещё \(hidden) Workflow")
                        .font(.system(size: 12)).foregroundColor(PanelColor.sub)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: all)
    }

    /// Когда начался: «сегодня, 13:05», «вчера, 09:40», «27.10, 22:15».
    static func when(_ start: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = String(format: "%02d:%02d", calendar.component(.hour, from: start), calendar.component(.minute, from: start))
        if calendar.isDate(start, inSameDayAs: now) { return "сегодня, " + time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(start, inSameDayAs: yesterday) {
            return "вчера, " + time
        }
        return String(format: "%02d.%02d, ", calendar.component(.day, from: start), calendar.component(.month, from: start)) + time
    }
}
