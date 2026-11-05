import AppKit
import ClaudeAX
import SwiftUI

// MARK: обновление Claude

struct UpdateBlockView: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent
    @Environment(\.panelType) private var type
    @State private var breathe = false

    var body: some View {
        // Дышит только в открытой панели: закрытая — ни анимаций, ни нагрузки (z6-r08).
        let timely: Bool = {
            if case .timely = model.update { return model.phase == .open }
            return false
        }()
        VStack(alignment: .leading, spacing: 8) {
            content
            // Проверка окна после обновления Claude (#10527): что сломалось — красной строкой под обновлением.
            if let line = model.liveCheckLine {
                Text(line).font(.system(size: 12)).foregroundColor(PanelColor.bad).fixedSize(horizontal: false, vertical: true)
            }
        }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PanelColor.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(timely && breathe ? accent : PanelColor.frame, lineWidth: 1))
            .onAppear { startBreathing(timely) }
            .onChange(of: timely) { startBreathing($0) }
    }

    private func startBreathing(_ on: Bool) {
        // Выключение — своей короткой анимацией: иначе повторяющаяся может остаться крутиться.
        guard on, !model.reduceMotion else { withAnimation(.linear(duration: 0)) { breathe = false }; return }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { breathe = true }
    }

    /// Заголовок карточки — подпись набора, как «Неделя» (WF267), строки — пояснение (WF253).
    private func title(_ text: String) -> some View {
        type.label.text(text).fixedSize(horizontal: false, vertical: true)
    }

    private func sub(_ text: String) -> some View {
        type.note.text(text).fixedSize(horizontal: false, vertical: true)
    }

    /// Готовое обновление (`.ready`, `.busy`, `.timely`) — одной раскладкой в три строки (#10307); прочие — своим видом.
    @ViewBuilder private var content: some View {
        if !model.updateCardHidden, let card = PimpPanelText.updateCard(model.update, size: model.readySize) {
            UpdateCardRows(model: model, card: card)
        } else {
            other
        }
    }

    /// Сколько идёт гонка загрузки — как в `RaceView`.
    private var raceElapsed: TimeInterval { model.raceStartedAt.map { model.now.timeIntervalSince($0) } ?? 0 }

    @ViewBuilder private var other: some View {
        switch model.update {
        case .none, .ready, .busy, .timely:
            EmptyView()
        case .planned(let version):
            PlannedRow(model: model, version: version)
        case .available(let version, _, _) where model.refusedVersion == version:
            title("PMP пока не патчит Claude \(version)")
            sub("Стоящий Claude не тронут. Новая версия PMP научится — предложу снова.")
        case .available(let version, let canWrite, let note):
            title("Вышел Claude \(version)")
            if let note = note { sub(note) }
            if canWrite {
                SmallButton(title: "Скачать") { model.actions.download() }
            } else {
                sub("Нет прав на папку «Программы» — поставь Claude сам с сайта")
            }
            // #9823: запасной путь есть всегда — кнопкой не вышло, Claude ставится с сайта.
            DownloadFromSiteRow()
        case .downloading(let race):
            RaceView(model: model, race: race, startedAt: model.raceStartedAt, memory: model.lanes,
                     title: "Качаю Claude \(race.version)",
                     note: "подпись Anthropic проверю в конце — откуда бы ни скачалось") { model.actions.cancelRace() }
            // #9823: загрузка тянется дольше 3 мин или упала — рядом путь через сайт; обычная загрузка — без строки.
            if PimpPanelText.siteDownloadShown(race, elapsed: raceElapsed) { DownloadFromSiteRow() }
        case .verifying(_, let from):
            title("Проверяю подпись Anthropic…")
            sub((from.map { "файл с \($0)" } ?? "файл скачан") + ", проверка — как у официального")
        case .snoozed:
            sub("Хорошо, напомню через 3 часа")
        case .installing(let version, let step):
            let opens = model.installOpensClaude
            let steps = PimpPanelText.installSteps(version: version, loader: model.loader, opensClaude: opens)
            HStack {
                title("Обновляю Claude до \(version)")
                Spacer()
                Text("\(min(step + 1, steps.count))/\(steps.count)").font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PanelColor.sub)
            }
            sub(opens ? "Claude закрыт секунд на 20 — дальше всё само" : PimpPanelText.installClosedLine)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                HStack(spacing: 8) {
                    StepDot(state: index < step ? .done : (index == step ? .running : .waiting))
                    Text(text).font(.system(size: 13))
                        .foregroundColor(index <= step ? PanelColor.text : PanelColor.sub)
                }
            }
            // WF234 (слово владельца 10.10.2026: «когда нажимаешь обновить, там должно быть прямо пример»): пример
            // окна связки ключей виден, пока идёт установка; готово или сорвалось — блок сменился, примера нет.
            // Claude не открываем (WF283) — и связка ключей не спросит.
            if opens { KeychainExample() }
        case .done(let version):
            Text("✓ Claude \(version) стоит, патч на месте").font(.system(size: 13, weight: .semibold))
                .foregroundColor(PanelColor.good(accent))
        case .failed(let why):
            Text("Не вышло: \(why). Claude остался прежним.").font(.system(size: 13))
                .foregroundColor(PanelColor.bad).fixedSize(horizontal: false, vertical: true)
            SmallButton(title: "Ещё раз") { model.actions.retryUpdate() }
            DownloadFromSiteRow()
        }
    }
}

/// Запасной путь обновления Claude (#9823): ссылка «Скачать с claude.ai» открывает страницу загрузки в браузере по
/// умолчанию, рядом — сама ссылка со значком «копировать»: кладёт в буфер ровно `claudeDownloadURL` и на 1,5 с
/// говорит «Скопировано». Браузер не открылся — ссылка всё равно ляжет в буфер. По левому краю (#10305).
struct DownloadFromSiteRow: View {
    static let copiedFor: TimeInterval = 1.5
    @State private var copied = false
    @Environment(\.pmpAccent) private var accent
    @State private var generation = 0
    @State private var hover = false

    /// Ровно `claudeDownloadURL` в буфер; `pasteboard` — для теста (свой, не общий буфер человека).
    @discardableResult
    static func copyLink(to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(PimpPanelText.claudeDownloadURL, forType: .string)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            LinkButton(title: PimpPanelText.siteDownloadTitle, action: open)
                .help("Открыть \(PimpPanelText.claudeDownloadURL) в браузере")
            Button(action: copy) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                    Text(copied ? "Скопировано" : PimpPanelText.claudeDownloadShort).font(.system(size: 11))
                }
                .foregroundColor(copied ? accent : (hover ? PanelColor.text : PanelColor.sub))
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .help("Скопировать ссылку \(PimpPanelText.claudeDownloadURL)")
            .accessibilityLabel(copied ? "Ссылка скопирована" : "Скопировать ссылку \(PimpPanelText.claudeDownloadURL)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open() {
        if let url = URL(string: PimpPanelText.claudeDownloadURL), NSWorkspace.shared.open(url) { return }
        copy()
    }

    /// Повторное нажатие продлевает «Скопировано» — снимает его только последний таймер.
    private func copy() {
        guard Self.copyLink() else { return }
        copied = true
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedFor) {
            if mine == generation { copied = false }
        }
    }
}

/// Готовое обновление в три строки (#10307; #10305 — по левому краю, главная кнопка заметна сразу): подпись «Обновление
/// Claude» и номер версии тихо справа; одна причина цветом (зелёный — самое время, жёлтый — идёт работа или вопрос,
/// серый — просто готово); главная кнопка во всю ширину и рядом, если нужна, маленькая вторая той же высоты. Абзац
/// «Claude закроется…» — подсказкой кнопки, строка про связку ключей — при самой установке (`KeychainExample`).
private struct UpdateCardRows: View {
    @ObservedObject var model: PanelModel
    let card: PimpPanelText.UpdateCard
    @Environment(\.panelType) private var type
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                type.label.text("Обновление Claude").lineLimit(1)
                Spacer(minLength: 8)
                type.note.text(card.version).lineLimit(1).fixedSize()
                HideCardButton { model.hideUpdateCard() }
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            Text(card.reason)
                .font(.system(size: 11, weight: card.tone == .quiet ? .regular : .semibold))
                .foregroundColor(tone)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                BigButton(title: card.main.title) { perform(card.main) }
                    .help(card.help)
                if let second = card.second {
                    SmallButton(title: second.title, primary: false, height: 30) { perform(second) }
                        .help(second == .nextLaunch ? PimpPanelText.nextLaunchHelp : "")
                }
            }
        }
    }

    private var tone: Color {
        switch card.tone {
        case .good: return PanelColor.good(accent)
        case .warn: return PanelColor.warn
        case .quiet: return PanelColor.sub
        }
    }

    private func perform(_ action: PimpPanelText.UpdateCard.Action) {
        switch action {
        case .update: model.actions.update()
        case .updateNow: model.actions.updateNow()
        case .updateAnyway: model.actions.updateAnyway()
        case .wait: model.actions.wait()
        case .nextLaunch: model.actions.nextLaunch()
        }
    }
}

/// Обновление отложено «При запуске» (#10765, WF283): карточка свёрнута в одну тихую строку — обновление ждёт
/// запуска Claude (номер версии — в подсказке); справа «Сейчас» (то же, что «Обновить сейчас», с вопросом при работе) и «Отменить» (карточка
/// вернётся). Ссылки — цветом подписей, под курсором ярче: строка не маячит.
private struct PlannedRow: View {
    @ObservedObject var model: PanelModel
    let version: String

    var body: some View {
        // Одна строка (слово Элвиса «свернуться… чтобы не маячить»): значок снят — с ним фраза и ссылки в 292 pt не
        // влезали и строка ломалась на две.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(PimpPanelText.plannedLine).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .lineLimit(1).layoutPriority(1)
                .help(PimpPanelText.plannedHelp(version))
            Spacer(minLength: 0)
            QuietLink(title: PimpPanelText.plannedNowTitle, help: PimpPanelText.plannedNowHelp) { model.actions.updateNow() }
            QuietLink(title: PimpPanelText.plannedCancelTitle, help: PimpPanelText.plannedCancelHelp) {
                model.actions.cancelNextLaunch()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// Тихая ссылка строки «обновится при запуске»: цвет подписей, под курсором — текста.
private struct QuietLink: View {
    let title: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundColor(hover ? PanelColor.text : PanelColor.sub).underline(hover)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Крестик карточки обновления (#10765): скрыть эту версию до следующей. Под курсором — ярче и с кружком, нажатие —
/// `PressStyle`, с клавиатуры — обычная кнопка (Tab при полном доступе с клавиатуры, пробел).
private struct HideCardButton: View {
    static let help = "Скрыть до следующей версии Claude — обновить можно в «Настройках»"
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                .foregroundColor(hover ? PanelColor.text : PanelColor.sub)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(hover ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .help(Self.help)
        .accessibilityLabel("Скрыть обновление Claude до следующей версии")
    }
}

/// Пример окна macOS «„Claude“ хочет использовать… в Вашей связке ключей» (WF234, #9382; с WF238 — как настоящее
/// окно, `KeychainDialogExample`): нарисован, не снимок экрана; нужная кнопка, «Разрешать всегда», обведена цветом
/// PMP. Под примером — одна строка, что нажать, и «код открыт» со ссылкой на исходники. По левому краю (#10305).
struct KeychainExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KeychainDialogExample(compact: true, marked: true)
            Text(PimpPanelText.keychainHint).font(.system(size: 11)).foregroundColor(PanelColor.text)
                .fixedSize(horizontal: false, vertical: true)
            LinkButton(title: PimpPanelText.openSourceWord) {
                if let url = URL(string: PimpPanelText.openSourceURL) { NSWorkspace.shared.open(url) }
            }
            .help(PimpPanelText.openSourceURL)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Тихая строка до нажатия «Пропатчить» (WF238, макет 41, кадр 1.1): macOS потом спросит пароль — одна строка вместо
/// абзаца; что нажать, покажет плашка под самим окном macOS. По левому краю (#10305); в карточке обновления её нет
/// с #10307 — там пример окна встаёт при самой установке.
struct KeychainSoonLine: View {
    var body: some View {
        let parts = PimpPanelText.keychainSoon.components(separatedBy: PimpPanelText.keychainSoonBold)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "key.fill").font(.system(size: 9)).foregroundColor(PanelColor.sub)
            (Text(parts.first ?? "")
                + Text(PimpPanelText.keychainSoonBold).fontWeight(.semibold).foregroundColor(PanelColor.text)
                + Text(parts.dropFirst().joined(separator: PimpPanelText.keychainSoonBold)))
                .font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PimpPanelText.keychainSoon)
    }
}

private struct StepDot: View {
    enum State { case waiting, running, done }
    let state: State
    @SwiftUI.State private var turn = false
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        ZStack {
            switch state {
            case .waiting:
                Circle().strokeBorder(PanelColor.sub.opacity(0.5), lineWidth: 1.2)
            case .running:
                Circle().trim(from: 0, to: 0.28).stroke(accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(turn ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { turn = true } }
            case .done:
                Circle().fill(accent)
                Text("✓").font(.system(size: 10, weight: .bold)).foregroundColor(PanelColor.ink)
            }
        }
        .frame(width: 16, height: 16)
        .animation(PanelSpring.press, value: state)
    }
}

private struct RaceView: View {
    @ObservedObject var model: PanelModel
    let race: ClaudeUpdateMenu.Race
    let startedAt: Date?
    let memory: LaneMemory
    let title: String
    let note: String
    let stop: () -> Void
    @Environment(\.pmpAccent) private var accent
    @Environment(\.panelType) private var type

    var body: some View {
        let elapsed = startedAt.map { model.now.timeIntervalSince($0) } ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                type.label.text(title)
                Spacer()
                Text("\(race.percent) %").font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(accent)
            }
            HStack {
                Text(PimpPanelText.raceSubtitle(race, elapsed: elapsed)).font(.system(size: 11))
                    .foregroundColor(PanelColor.sub)
                Spacer()
                Text(PimpPanelText.elapsedText(elapsed)).font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PanelColor.sub)
            }
            ForEach(PimpPanelText.orderedLanes(race.lanes), id: \.id) { lane in
                LaneRow(lane: lane, revived: memory.isRevived(lane.id, at: model.now))
            }
            HStack(alignment: .top) {
                Text(note)
                    .font(.system(size: 11)).foregroundColor(PanelColor.sub).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                LinkButton(title: "остановить", color: PanelColor.sub, action: stop)
            }
        }
    }
}

private struct LaneRow: View {
    let lane: ClaudeUpdateMenu.Lane
    let revived: Bool
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let off = isOff
        let fraction = lane.total.map { $0 > 0 ? min(1, Double(lane.bytes) / Double($0)) : 0 } ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(PimpPanelText.laneName(lane)).font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PanelColor.text)
                if let badge = PimpPanelText.laneBadge(lane, revived: revived) {
                    Text(badge).font(.system(size: 10, weight: .semibold))
                        .foregroundColor(badgeInk)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(badgeFill))
                        .help(failure ?? "")
                        .transition(.opacity)
                }
                Spacer()
                Text(off ? "—" : ClaudeUpdateMenu.speedText(lane.bytesPerSec))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(PanelColor.sub)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(fill).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.25), value: fraction)
            Text(PimpPanelText.bytesText(lane.bytes, total: lane.total)).font(.system(size: 11, design: .monospaced))
                .foregroundColor(PanelColor.sub)
        }
        .opacity(off ? 0.42 : 1)
        .animation(.easeInOut(duration: 0.3), value: off)
    }

    private var isOff: Bool {
        switch lane.state {
        case .dropped, .failed: return true
        default: return false
        }
    }

    private var failure: String? {
        if case .failed(let why) = lane.state { return why }
        return nil
    }

    private var fill: Color {
        switch lane.state {
        case .leading, .won: return accent
        case .running: return PanelColor.sub
        case .dropped, .failed: return PanelColor.frame
        }
    }

    private var badgeFill: Color {
        if revived || lane.state == .won { return accent.opacity(0.2) }
        switch lane.state {
        case .leading: return accent
        default: return Color.white.opacity(0.1)
        }
    }

    private var badgeInk: Color {
        if revived || lane.state == .won { return accent }
        return lane.state == .leading ? PanelColor.ink : PanelColor.sub
    }
}
