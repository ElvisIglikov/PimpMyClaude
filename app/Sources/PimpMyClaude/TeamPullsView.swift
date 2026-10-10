import ClaudeAX
import SwiftUI

/// Read-only team requests inside Settings; one model belongs to the panel.
struct TeamPullsSection: View {
    @ObservedObject var pulls: TeamPulls
    @State private var open = false
    @Environment(\.pmpAccent) private var accent

    static let rowHeight: CGFloat = 74
    static let rowSpacing: CGFloat = 4
    /// Как у списка Spotlight: до трёх строк — целиком, дальше прокрутка, третья видна наполовину.
    static func listHeight(_ rows: Int) -> CGFloat {
        rows <= 3 ? CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * rowSpacing
                  : 2.6 * (rowHeight + rowSpacing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(PanelSpring.settings) { open.toggle() }
                if open { pulls.refresh() }
            } label: {
                HStack {
                    Text(TeamPulls.rowTitle(pulls.pulls)).font(.system(size: 13)).foregroundColor(PanelColor.text)
                    Spacer(minLength: 6)
                    Text(TeamPulls.rowDetail(pulls: pulls.pulls, loading: pulls.loading, error: pulls.error))
                        .font(.system(size: 11)).foregroundColor(PanelColor.sub).lineLimit(1)
                }
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Открытые запросы на изменения (pull request) в твоих репозиториях и репозиториях твоих организаций — кроме твоих")
            if open {
                list.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onExitCommand { open = false }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let error = pulls.error { note(error, color: PanelColor.bad) }
            if let list = pulls.pulls {
                if pulls.error != nil { note("Сохранённый список — данные могли измениться", color: PanelColor.warn) }
                if list.isEmpty && pulls.error == nil {
                    note(TeamPulls.emptyText, color: PanelColor.sub)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Self.rowSpacing) {
                            ForEach(list) { row($0).frame(height: Self.rowHeight) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: Self.listHeight(list.count))
                }
            } else if pulls.loading {
                note(TeamPulls.loadingText, color: PanelColor.sub)
            }
            Button { pulls.refresh(force: true) } label: {
                Text(pulls.loading ? "Обновляю…" : "Обновить").font(.system(size: 11))
                    .foregroundColor(pulls.loading ? PanelColor.sub : accent).underline(!pulls.loading)
            }
            .buttonStyle(.plain)
            .disabled(pulls.loading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.045)))
        .padding(.bottom, 4)
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(color).fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ pull: TeamPulls.Pull) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pull.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Без заголовка" : pull.title).font(.system(size: 12)).foregroundColor(PanelColor.text)
                .lineLimit(1).truncationMode(.tail).help(pull.title)
            Text(TeamPulls.detail(pull, now: Date())).font(.system(size: 10.5)).foregroundColor(PanelColor.sub)
                .lineLimit(2).help(TeamPulls.detail(pull, now: Date()))
            if let url = TeamPulls.link(pull) {
                Link("Открыть на GitHub", destination: url)
                    .font(.system(size: 11)).foregroundColor(accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
