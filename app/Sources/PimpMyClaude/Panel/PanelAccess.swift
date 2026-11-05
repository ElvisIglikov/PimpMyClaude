import AppKit
import ClaudeAX
import SwiftUI

// Карточка доступов Claude в панели (#10252) — с #10310 сама мастер (#10306 — её шаг 0): заголовок слева, столбик всех
// нужных шагов с ✓/○, у текущего — кнопка, плитки PMP и Claude для перетаскивания в список Системных настроек,
// «Назад»/«Далее» и «Позже». Расчёт шагов — `AccessWizard` (ClaudeAX), опрос, `tccutil` и плашка у окна настроек —
// `AccessWizardController`. SwiftUI — мелкими функциями с явными типами: компилятор Command Line Tools не успевает
// проверять длинные выражения.

struct AccessWizardCard: View {
    @ObservedObject var model: PanelModel
    @Environment(\.panelType) private var type
    @Environment(\.pmpAccent) private var accent
    @AppStorage(AccessWizardController.dismissedKey) private var dismissed = false
    @AppStorage(AccessWizardController.laterKey) private var later = ""

    var body: some View {
        if AccessWizard.cardVisible(state: model.access, phase: wizard.phase, dismissed: dismissed,
                                    later: later.isEmpty ? nil : later) {
            card
        }
    }

    private var wizard: AccessWizard.Snapshot { model.wizard }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            type.label.text(AccessWizard.cardTitle(wizard))
            if wizard.phase == .done {
                note(AccessWizard.doneText)
            } else {
                stepsBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var stepsBody: some View {
        if wizard.steps.count > 1 { column }
        if let step = wizard.current { detail(step) }
        navigation
        if wizard.signFailed && wizard.adhoc == true {
            Text(AccessWizard.adhocLine).font(.system(size: 10)).foregroundColor(PanelColor.sub)
        }
    }

    // MARK: столбик

    private var column: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(wizard.steps.enumerated()), id: \.offset) { index, step in
                row(step, current: index == wizard.index)
            }
        }
    }

    private func row(_ step: AccessWizard.Step, current: Bool) -> some View {
        let label: String = "\(step.number). " + AccessWizard.stepTitle(step.target)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark(step.status)).font(.system(size: 12, weight: .semibold)).foregroundColor(markColor(step.status))
                .frame(width: 14, alignment: .leading)
            Text(label).font(.system(size: 12, weight: current ? .semibold : .regular))
                .foregroundColor(current ? PanelColor.text : PanelColor.sub)
        }
    }

    private func mark(_ status: AccessWizard.Status) -> String {
        switch status {
        case .done: return "✓"
        case .skipped: return "–"
        case .todo: return "○"
        }
    }

    private func markColor(_ status: AccessWizard.Status) -> Color {
        status == .done ? accent : PanelColor.sub
    }

    // MARK: текущий шаг

    private func detail(_ step: AccessWizard.Step) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note(hint(step))
            action(step)
            if step.target != .sign && !step.apps.isEmpty { tiles(step.apps) }
            if step.target == .sign && step.status == .todo { note(AccessWizard.passwordLine) }
            if step.target == .pmpFullDisk && wizard.relaunchOffer {
                note(AccessWizard.staleRowHint)
                LinkButton(title: AccessWizard.relaunchLink) { model.actions.accessWizard(.relaunch) }
            }
        }
    }

    private func hint(_ step: AccessWizard.Step) -> String {
        if step.target == .sign && step.status == .skipped { return AccessWizard.signFailedText }
        guard case .service(let service) = step.target else {
            return AccessWizard.hint(step, grant: nil, resetFailed: false)
        }
        return AccessWizard.hint(step, grant: wizard.grants[service], resetFailed: wizard.resetFailed.contains(service))
    }

    @ViewBuilder private func action(_ step: AccessWizard.Step) -> some View {
        if step.target == .sign {
            signAction(step)
        } else if step.status == .todo {
            BigButton(title: AccessWizard.openTitle(step.target)) { model.actions.accessWizard(.open) }
        }
    }

    /// Подпись идёт через «Пропатчить» (`patchFromPanel`): шаг и ошибка — те же, что в карточке патча.
    @ViewBuilder private func signAction(_ step: AccessWizard.Step) -> some View {
        switch model.patchRun {
        case .running(let text):
            BigButton(title: text, enabled: false) {}
        case .failed(let why):
            BigButton(title: "Ещё раз") { model.actions.accessWizard(.open) }
            Text(why).font(.system(size: 11)).foregroundColor(PanelColor.bad).fixedSize(horizontal: false, vertical: true)
            LinkButton(title: "Подробнее…") { model.actions.patchLog() }
        case .idle:
            if step.status == .todo {
                BigButton(title: AccessWizard.openTitle(.sign)) { model.actions.accessWizard(.open) }
            }
        }
    }

    private func tiles(_ apps: [AccessWizard.App]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                if let url = app == .pmp ? wizard.pmpApp : wizard.claudeApp {
                    AppDragTile(url: url, title: AccessWizard.appName(app))
                }
            }
        }
    }

    // MARK: низ

    private var navigation: some View {
        HStack(spacing: 8) {
            if wizard.index > 0 {
                SmallButton(title: "Назад", primary: false) { model.actions.accessWizard(.back) }
            }
            if wizard.index < wizard.steps.count - 1 {
                SmallButton(title: "Далее", primary: false) { model.actions.accessWizard(.next) }
            }
            Spacer(minLength: 0)
            if model.access == .unknown {
                LinkButton(title: AccessWizard.dismiss) { model.actions.accessWizard(.dismiss) }
            } else {
                LinkButton(title: AccessWizard.later) { model.actions.accessWizard(.later) }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - плитка программы для перетаскивания

/// Плитка программы, как «Gemini» на снимке: иконка и имя; тащится мышью в список Системных настроек (file URL бандла).
struct AppDragTile: View {
    let url: URL
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
            Spacer(minLength: 0)
            Image(systemName: "hand.draw").font(.system(size: 11)).foregroundColor(PanelColor.sub)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(shape.fill(Color.white.opacity(0.06)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .overlay(AppDragSource(url: url))
        .help("Перетащи \(title) в список Системных настроек")
        .accessibilityLabel("\(title) — перетащи в список Системных настроек")
    }
}

/// Прозрачный слой над плиткой: нажал и повёл — macOS тащит file URL бандла, как из Finder.
struct AppDragSource: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AppDragSourceView { AppDragSourceView(url: url) }

    func updateNSView(_ view: AppDragSourceView, context: Context) { view.url = url }
}

final class AppDragSourceView: NSView, NSDraggingSource {
    var url: URL
    private var down: NSEvent?

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    /// Панель и плашка не становятся главными окнами — первое нажатие уже тащит.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) { down = event }

    override func mouseUp(with event: NSEvent) { down = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let start = down else { return }
        down = nil
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 48, height: 48)
        let point = convert(start.locationInWindow, from: nil)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [item], event: start, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .link, .generic]
    }
}
