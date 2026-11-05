import AppKit
import ClaudeAX
import SwiftUI

// MARK: - содержимое

struct PanelContent: View {
    @ObservedObject var model: PanelModel
    @Environment(\.panelType) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Header(model: model, visible: visibleWidgets).appear(0, model)
            // Пимп обновился сам (WF217, К-SU): одна тихая строка при первом открытии панели, без окон и уведомлений;
            // пояснением набора шрифтов (WF267).
            if let note = model.selfUpdate.note {
                type.note.text(note).fixedSize(horizontal: false, vertical: true)
            }
            // Сторож контекста (пожелания 03.11, раздел 0): на обоих листах, скрыть нельзя, уходит после установки.
            if model.kontekst != .ok {
                KontekstGuardCard(model: model).appear(1, model)
            }
            // «Не влезли в строку меню» (#10264) с #10286 — полоской у часов (MenuExtrasStrip), в панели ряда нет.
            if model.sheet == .settings {
                SettingsSheet(model: model).appear(1, model)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                if model.accentOpen {
                    AccentCard(model: model).transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let card = PimpPanelText.patchCard(model.patch) {
                    PatchCardView(model: model, card: card).appear(1, model)
                }
                AccessCardView(model: model)
                // Цвет Claude — первым сверху (#9040, #9020 п. 11: «основная наша фишка — цвет Клауда»),
                // подписка под ним (#8958).
                // С WF129 блоки — виджеты (#9043): порядок и ширину выбирает человек; обновление Claude — не
                // виджет, стоит над ними.
                // Скрытая крестиком версия (#10765) блока не занимает, строку проверки окна всё равно видно.
                if (model.update != .none && !model.updateCardHidden) || model.liveCheckLine != nil {
                    UpdateBlockView(model: model).appear(1, model)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                WidgetBoard(model: model, visible: visibleWidgets) { widget in cell(widget) }
                // WF171 (#9177): входа «Открыть панель — проекты и Workflow» нет — панель у часов и по кнопке PMP одна
                // и та же, лёгкая. «Идёт Workflow» с WF214 — обычный виджет, с WF258 — одной строкой, с #10239 — блок
                // Workflow PMP Tray для Windows (`WorkflowBlockView`).
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }

    /// Блок сетки. Своей функцией (#10308): длинный `switch` в замыкании компилятор Command Line Tools не успевает
    /// проверить.
    @ViewBuilder private func cell(_ widget: PanelWidget) -> some View {
        switch widget {
        case .workflow: WorkflowBlockView(model: model)
        case .colors: ColorsCard(model: model)
        case .week: MainLimit(model: model)
        case .limits: LimitTile(model: model, kind: .fiveHour)
        case .fable: LimitTile(model: model, kind: .fable)
        case .reset:
            if let strip = weekStrip {
                WeekStripView(strip: strip, parts: weekParts,
                              clock: StatusIcon.resetClock(StatusIcon.limit(.week, in: model.known)?.resetsAt, now: model.now))
            }
        case .temperature: TemperatureView(model: model)
        case .memory: MemoryView(model: model)
        case .tokens: TokensTile(model: model)
        case .cpu: LoadView(model: model, kind: .cpu)
        case .gpu: LoadView(model: model, kind: .gpu)
        case .terminals: TerminalsBlock(model: model)
        }
    }

    private var weekStrip: StatusIcon.WeekStrip? {
        StatusIcon.weekStrip(StatusIcon.limit(.week, in: model.known)?.resetsAt, now: model.now)
    }

    /// Срок сброса крупной строкой — «5д 2ч» (слово 03.11.2026: в одном стиле с «Неделей»).
    private var weekParts: [PanelShort.HeroPart] {
        PanelShort.heroParts(StatusIcon.limit(.week, in: model.known)?.resetsAt, now: model.now)
    }

    /// Какие виджеты сейчас есть: «Сброс» — когда известен срок, температура — когда датчики отвечают.
    private var visibleWidgets: Set<String> {
        // «Идёт Workflow» снова виден одной строкой (WF258, лист 48 · 1.2); скрыт он был словом Элвиса 10.10 23:05.
        var shown: [PanelWidget] = [.workflow, .colors, .week, .limits]
        // Тариф без Fable (ответ API без поля) — блока нет.
        if !(model.known.map { $0.fable == nil && $0.source == "api" } ?? false) { shown.append(.fable) }
        if weekStrip != nil { shown.append(.reset) }
        if let last = model.temperature.last, last.value != nil { shown.append(.temperature) }
        if let last = model.memory.last, last.value != nil { shown.append(.memory) }
        // Процессор и видеокарта (#10308): число есть — плитка есть; у видеокарты без «Device Utilization %» плитки нет.
        if model.macLoad.last?.cpu != nil { shown.append(.cpu) }
        if model.macLoad.last?.gpu != nil { shown.append(.gpu) }
        if model.tokenSpark != nil { shown.append(.tokens) }
        // Открытые терминалы (#10464): есть живые сессии rick-* — блок есть.
        if !model.terminals.isEmpty { shown.append(.terminals) }
        return Set(shown.map { $0.rawValue })
    }
}

private struct CardModifier: ViewModifier {
    let radius: CGFloat
    @Environment(\.panelFill) private var fill

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: fill ? .infinity : nil, alignment: .top)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(PanelColor.frame, lineWidth: 1))
    }
}

/// Блоки сверху вниз: прозрачность 0 → 1, сдвиг −8 и масштаб 0,98 → на место, задержка 60 + 45·i мс.
private struct Appear: ViewModifier {
    let index: Int
    let shown: Bool
    let reduce: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : -8)
            .scaleEffect(shown || reduce ? 1 : 0.98, anchor: .top)
            .animation(shown ? (reduce ? .easeOut(duration: 0.15)
                                       : PanelSpring.roll.delay(0.06 + 0.045 * Double(index)))
                             : .easeOut(duration: 0.1), value: shown)
    }
}

extension View {
    func appear(_ index: Int, _ model: PanelModel) -> some View {
        modifier(Appear(index: index, shown: model.phase == .open, reduce: model.reduceMotion))
    }

    /// Карточка: радиус 12, фон белый 4,5 %, рамка 1 px. В сетке виджетов — на всю высоту ряда (`panelFill`).
    func card(radius: CGFloat = 12) -> some View {
        modifier(CardModifier(radius: radius))
    }
}

extension View {
    /// Заголовок блока-виджета (WF187): на его место встают значки управления. Не `private` — им пользуется
    /// строка блока `FitLine` (WF253).
    func widgetTitle() -> some View {
        modifier(WidgetTitle())
    }

    /// Над нажимаемым — рука (§1.5).
    func handCursor() -> some View {
        onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

/// Нажатие — пружина press (0,97).
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(PanelSpring.press, value: configuration.isPressed)
    }
}

/// Кнопка во всю ширину (патч, «Обновить Claude»): 13 полужирный на акценте.
struct BigButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @Environment(\.pmpAccent) private var accent
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PanelColor.ink)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent).brightness(hover && enabled ? 0.08 : 0))
                .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .onHover { hover = $0 }
    }
}

struct SmallButton: View {
    let title: String
    var primary = true
    /// Рядом с `BigButton` — 30, вровень с ней (#10307).
    var height: CGFloat = 26
    let action: () -> Void
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(primary ? PanelColor.ink : PanelColor.text)
                .padding(.horizontal, 11)
                .frame(minHeight: height)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(primary ? accent : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressStyle())
    }
}

struct LinkButton: View {
    let title: String
    var color: Color?
    let action: () -> Void
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11)).foregroundColor(color ?? accent).underline()
        }
        .buttonStyle(.plain)
    }
}

struct Badge: View {
    let outlined: Bool
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text("PMP")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(outlined ? accent : PanelColor.ink)
            .frame(width: 32, height: 20)
            .background(shape.fill(outlined ? Color.clear : accent))
            .overlay(shape.strokeBorder(accent, lineWidth: outlined ? 1.2 : 0))
    }
}

/// Кружок «нажми» на углу плашки PMP в шапке (WF189): тихий — цветом подписей; под курсором и при открытом
/// «Цвет PMP» — цветом текста. Вырезан кольцом цвета панели, чтобы не слипался с плашкой.
struct BadgeHint: View {
    static let size: CGFloat = 7
    /// Центр кружка — угол плашки (26; 4,5 от левого верха кнопки 31 × 22): плашка в картинке x 1…24, y 4…18,
    /// у картинки поля по 3 pt.
    static let offset = CGSize(width: -1.5, height: 1)
    /// Запасная плашка `Badge` (32 × 20, до первого `iconLook`; WF193): угол плашки — угол самой вьюхи, центр
    /// кружка — на 1 pt внутрь справа и 0,5 сверху, как у плашки в картинке.
    static let badgeOffset = CGSize(width: 2.5, height: -3)
    let hover: Bool
    let open: Bool
    var offset: CGSize = BadgeHint.offset

    /// Видна ли точка: у плашки-картинки — пока угол не занят меткой беды; у запасной плашки — пока патч не слетел
    /// (тогда рядом красная точка).
    static func shows(_ look: StatusIcon.Look?, patch: StatusIcon.Patch) -> Bool {
        if let look = look { return look.mark == .none }
        if case .lost = patch { return false }
        return true
    }

    var body: some View {
        Circle().fill(hover || open ? PanelColor.text : PanelColor.sub)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(PanelColor.ink).padding(-1.5))
            .offset(offset)
            .animation(.easeOut(duration: 0.15), value: hover)
            .allowsHitTesting(false)
    }
}

private struct Header: View {
    @ObservedObject var model: PanelModel
    /// Какие блоки сейчас есть — для «Свернуть всё / Развернуть всё» (WF269).
    let visible: Set<String>
    @State private var hover = false
    @State private var foldHover = false
    @State private var badgeHover = false
    @Environment(\.panelType) private var type
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        // Одна тонкая строка (#8894; #10308 — как PimpTray): значок, «Claude … · PMP …» мелко серым, «Свернуть всё» и
        // шестерёнка настроек (WF126). Тарифа нет. Точка — только беда (патч слетел); слова о беде — в карточке патча.
        let settings = model.sheet == .settings
        HStack(spacing: 8) {
            // Тот же значок, что у часов (#9020 п. 3–5): нажатие — выбор цвета PMP, смена красит оба.
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.sheet = .panel
                    model.settingsGroup = nil
                    model.accentOpen.toggle()
                }
            } label: {
                // Только значок PMP (WF181, #9217: «Убери „PMP 39“ — зачем дублировать, просто значок отобрази»): полоски,
                // сводка проектов и число — у часов, здесь плашка одна.
                if let look = model.iconLook.map(StatusIcon.badgeOnly) {
                    Image(nsImage: StatusIconArt.image(look, dark: true, accent: model.shownAccent.nsColor))
                        .padding(.horizontal, 3)
                        // «Нажми» (WF189, слово Элвиса 09.10 04:00: «не все догадаются, что на него можно нажать…
                        // кругляшок сверху, как индикатор»): кружок на правом верхнем углу плашки; угол занят меткой
                        // беды — её и видно.
                        .overlay(alignment: .topTrailing) {
                            if BadgeHint.shows(look, patch: model.patch) {
                                BadgeHint(hover: badgeHover, open: model.accentOpen)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(model.accentOpen ? 0.12 : (badgeHover ? 0.08 : 0))))
                } else {
                    // Та же точка-подсказка, что у плашки-картинки (WF193); беда — красной точкой рядом, без подсказки.
                    Badge(outlined: outlined)
                        .overlay(alignment: .topTrailing) {
                            if BadgeHint.shows(nil, patch: model.patch) {
                                BadgeHint(hover: badgeHover, open: model.accentOpen, offset: BadgeHint.badgeOffset)
                            }
                        }
                }
            }
            .buttonStyle(PressStyle())
            // Плашка — по левой грани карточек (правило №1): подложка наведения выступает за грань, а не значок.
            .padding(.leading, model.iconLook == nil ? 0 : -4)
            .onHover { badgeHover = $0 }
            .handCursor()
            .help("Цвет PMP")
            .accessibilityLabel("Цвет PMP")
            if case .lost = model.patch, model.iconLook == nil { Circle().fill(PanelColor.bad).frame(width: 6, height: 6) }
            // #10308: всегда одна строка, без переноса — первый вид, что входит целиком: полная строка и «Свернуть всё»
            // словами; номер Claude короче; капсула без слов (слова — в подсказке: версии важнее, у PimpTray версий в
            // шапке нет вовсе); последней страховкой — ужатие до 0,8.
            // #10461 (как у коллеги): «Свернуть всё» словами важнее номера PMP — он уходит первым.
            ViewThatFits(in: .horizontal) {
                headerRow(short: false, words: true)
                headerRow(short: true, words: true)
                headerRow(short: true, words: true, app: false)
                headerRow(short: false, words: false)
                headerRow(short: true, words: false)
                headerRow(short: true, words: false, squeeze: true)
            }
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.sheet = settings ? .panel : .settings
                    model.settingsGroup = nil
                }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13))
                    .foregroundColor(hover || settings ? PanelColor.text : PanelColor.sub)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(settings ? 0.12 : (hover ? 0.08 : 0))))
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .handCursor()
            .help("Настройки (⌘,)")
            .accessibilityLabel("Настройки")
        }
        .frame(minHeight: 22)
    }

    /// Строка версий и «Свернуть всё» справа; в «Настройках» капсулы нет. `short` — номер Claude короче, полный —
    /// в подсказке; `squeeze` — ужать, если не вошло и так.
    private func headerRow(short: Bool, words: Bool, squeeze: Bool = false, app: Bool = true) -> some View {
        let full = PimpPanelText.headerLine(model.patch, app: model.appVersion)
        let line = PimpPanelText.headerLine(model.patch, app: app ? model.appVersion : "", short: short)
        return HStack(spacing: 8) {
            headerText(line, squeeze: squeeze)
                .help(line != full ? full : PimpPanelText.headerHelp(model.patch))
            Spacer(minLength: 0)
            if model.sheet != .settings { if model.editingWidgets { done } else { foldAll(words: words) } }
        }
    }

    @ViewBuilder private func headerText(_ line: String, squeeze: Bool) -> some View {
        if squeeze {
            type.header.text(line).lineLimit(1).minimumScaleFactor(0.8)
        } else {
            type.header.text(line).lineLimit(1).fixedSize()
        }
    }

    /// «Развернуть / Свернуть» (WF269, #10205, как у Оли): контуром. `words: false` — одна стрелка в капсуле (#10308),
    /// слова — в подсказке. #10993 (слово Элвиса 27.10.2026: «я открываю… потом кнопочка развернуть, я чик нажимаю, и
    /// оно разворачивается… кнопка называется „свернуть“, и сворачиваются все к вот этому виду по умолчанию»): хоть один
    /// блок свёрнут — «Развернуть» (все блоки); всё развёрнуто — «Свернуть» к виду по умолчанию (`setDefaultFolds`).
    private func foldAll(words: Bool) -> some View {
        let collapse = !model.layout.anyCollapsed(visible: visible)
        let title = collapse ? "Свернуть" : "Развернуть"
        let help: String = collapse ? "Свернуть к виду по умолчанию" : "Развернуть все блоки"
        let named: String = collapse ? "Свернуть — к виду по умолчанию" : "Развернуть — все блоки"
        return Button {
            if collapse { model.foldToDefault(visible: visible) } else { model.setAllCollapsed(false, visible: visible) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: collapse ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                if words { Text(title).font(.system(size: 11)).lineLimit(1).fixedSize() }
            }
            .foregroundColor(foldHover ? PanelColor.text : PanelColor.sub)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(Color.white.opacity(foldHover ? 0.06 : 0)))
            .overlay(Capsule().strokeBorder(PanelColor.frame, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .onHover { foldHover = $0 }
        .handCursor()
        .help(words ? help : named)
        .accessibilityLabel(title)
    }

    /// «Готово» в шапке на месте «Свернуть всё», пока идёт правка блоков (файл 53, 2.3): капсула цветом PMP.
    private var done: some View {
        Button { model.setEditingWidgets(false) } label: {
            Text("Готово").font(.system(size: 11, weight: .semibold)).foregroundColor(PanelColor.ink)
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Capsule().fill(accent))
        }
        .buttonStyle(PressStyle())
        .handCursor()
        .help("Закончить правку блоков (Esc)")
        .accessibilityLabel("Готово")
    }

    /// Бейдж контуром — Claude без патча или не найден (10-choice §3.2).
    private var outlined: Bool {
        switch model.patch {
        case .notInstalled, .claudeNotFound: return true
        default: return false
        }
    }
}
