import ClaudeAX
import SwiftUI

/// «Повторять при ошибке сервера» (#6936) в группе «Дополнительно»: выключатель, под ним — интервал, пока включено.
struct AutoRetryRows: View {
    @ObservedObject var model: PanelModel
    static let everyItems: [(value: Int, title: String)] = [(2, "2 мин"), (5, "5 мин"), (10, "10 мин")]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switchRow
            if model.autoRetryOn { everyRow }
        }
    }

    private var switchRow: some View {
        SettingsSwitchRow(title: AutoRetry.title, on: model.autoRetryOn, help: AutoRetry.help,
                          caption: AutoRetry.caption) {
            model.pickAutoRetry(!model.autoRetryOn, model.autoRetryEvery)
        }
    }

    private var everyRow: some View {
        Segments(items: Self.everyItems, selected: model.autoRetryEvery) { (minutes: Int) in
            model.pickAutoRetry(true, minutes)
        }
        .padding(.bottom, 4)
    }
}
