import ClaudeAX
import SwiftUI

// «Не напоминать» у «Ждёт тебя» (#9820): кнопка-меню рядом со строкой «Ждёт тебя: …» в карточке Workflow и в строках
// «Ждёт тебя» проектов без идущего Workflow (`PanelProjects.loneWaits`; в блоке Workflow с #10461 их нет), плашка «Не буду напоминать · Отменить» на 5 с
// и «Не вышло записать» на 3 с. Правило и файл — `MutedWaits` (ClaudeAX), запись — `AppDelegate+MutedWaits`.

extension PanelModel {
    private var muteAnimation: Animation { reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings }

    /// Ключ строки «Ждёт тебя» проекта.
    func waitKey(_ project: PanelProject) -> String { MutedWaits.key(folder: project.folder, text: project.waitFor) }

    /// Строку «Ждёт тебя» проекта видно: она есть и не заглушена в этом открытии панели.
    func waitShown(_ project: PanelProject) -> Bool {
        !PanelProjects.isNothing(project.waitFor) && !flow.hiddenWaits.contains(waitKey(project))
    }

    /// Выбор срока в «Не напоминать ▾»: запись сразу; строка уходит, на её месте 5 с «Отменить». Не записалось —
    /// строка остаётся, 3 с «Не вышло записать».
    func muteWait(_ project: PanelProject, _ choice: MutedWaits.Choice, inCard: Bool) {
        let key = waitKey(project)
        let now = Date()
        let written = actions.muteWait(key, MutedWaits.until(choice, now: now))
        let undo = WaitUndo(key: key, folder: project.folder, choice: choice, at: now, failed: !written, inCard: inCard)
        withAnimation(muteAnimation) {
            flow.waitUndo = undo
            if written { flow.hiddenWaits.insert(key) }
        }
        let wait = written ? WaitUndo.undoSeconds : WaitUndo.failSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self = self, self.flow.waitUndo == undo else { return }
            withAnimation(self.muteAnimation) { self.flow.waitUndo = nil }
        }
    }

    /// «Отменить»: запись снимается, строка возвращается.
    func undoMuteWait() {
        guard let undo = flow.waitUndo, !undo.failed else { return }
        actions.unmuteWait(undo.key)
        withAnimation(muteAnimation) {
            flow.waitUndo = nil
            flow.hiddenWaits.remove(undo.key)
        }
    }
}

/// «Ждёт тебя: …» жёлтым и справа «Не напоминать ▾». `title` — имя проекта у строки без карточки.
struct WaitLine: View {
    @ObservedObject var model: PanelModel
    let project: PanelProject
    var title: String?
    let inCard: Bool
    @Environment(\.panelType) private var type

    var body: some View {
        let head: String = title.map { "Ждёт тебя · \($0): " } ?? "Ждёт тебя: "
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            type.note.text(head + project.waitFor, color: PanelColor.warn)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            MuteMenu(model: model, project: project, inCard: inCard)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Меню сроков: на час, до завтра, на неделю, пока текст не сменится.
private struct MuteMenu: View {
    @ObservedObject var model: PanelModel
    let project: PanelProject
    let inCard: Bool

    var body: some View {
        Menu {
            ForEach(MutedWaits.Choice.allCases, id: \.self) { choice in
                Button(choice.title) { model.muteWait(project, choice, inCard: inCard) }
            }
        } label: {
            Text("Не напоминать").font(.system(size: 11)).foregroundColor(PanelColor.sub)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .handCursor()
        .help("Спрятать это «Ждёт тебя» на время; сменится текст — напомню снова")
        .accessibilityLabel("Не напоминать: " + project.waitFor)
    }
}

/// Плашка после выбора: «Не буду напоминать до завтра · Отменить 5» (отсчёт раз в секунду) или «Не вышло записать».
struct MuteUndoPlate: View {
    @ObservedObject var model: PanelModel
    let undo: WaitUndo
    @Environment(\.panelType) private var type

    var body: some View {
        HStack(spacing: 8) {
            type.note.text(undo.text, color: undo.failed ? PanelColor.bad : PanelColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !undo.failed {
                TimelineView(.periodic(from: undo.at, by: 1)) { context in
                    cancel(left: undo.left(now: context.date))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }

    private func cancel(left: Int) -> some View {
        Button { model.undoMuteWait() } label: {
            HStack(spacing: 4) {
                type.note.weight(.semibold).text("Отменить", color: PanelColor.text)
                type.note.text("\(max(1, left))")
            }
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .handCursor()
        .help("Вернуть напоминание")
        .accessibilityLabel("Отменить, осталось \(max(1, left)) с")
    }
}
