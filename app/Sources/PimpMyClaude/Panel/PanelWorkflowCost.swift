import ClaudeAX
import SwiftUI

// Цена Workflow (#6282): «≈ $4,20» подписью в строке блока и в карточке, подсказка — разбивка по ценам API; в карточке —
// и сумма Workflow проекта за 7 дней. Подсчёт — `WorkflowCost` (ClaudeAX), в фоне; нет данных — цены нет совсем.

/// «≈ $4,20» ролью подписи; при наведении — «По ценам API: вход …, выход …, кэш …».
struct CostLabel: View {
    let item: WorkflowCostItem
    @Environment(\.panelType) private var type

    var body: some View {
        type.note.text(item.label)
            .fixedSize()
            .help(item.help)
            .accessibilityLabel("По ценам API " + item.label)
    }
}

/// Карточка Workflow: «≈ $4,20 по ценам API» и «Workflow PimpMyClaude за 7 дней ≈ $31,50».
struct FlowCostLines: View {
    @ObservedObject var model: PanelModel
    let row: WorkflowBlock.Row
    @Environment(\.panelType) private var type

    var body: some View {
        let cost: WorkflowCostItem? = model.flowCosts?.cost(row)
        let week: WorkflowCostItem? = model.flowCosts?.week(row)
        if cost != nil || week != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let cost = cost {
                    type.note.text(cost.label + " по ценам API").fixedSize(horizontal: false, vertical: true)
                        .help(cost.help)
                }
                if let week = week {
                    type.note.text("Workflow \(row.projectName) за 7 дней " + week.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(week.help)
                }
            }
            .padding(.top, 5)
        }
    }
}
