import AppKit
import ClaudeAX
import SwiftUI

// MARK: патч

struct PatchCardView: View {
    @ObservedObject var model: PanelModel
    let card: PimpPanelText.PatchCard
    @Environment(\.panelType) private var type

    var body: some View {
        // По левому краю (#10305, слово Элвиса 19.10.2026: «центральное выравнивание… отвратительное… Оно должно быть
        // левым»).
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок — подпись набора шрифтов, как «Неделя» (WF267).
            type.label.text(card.title)
            Text(card.text).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .fixedSize(horizontal: false, vertical: true)
            switch model.patchRun {
            case .idle:
                BigButton(title: card.button) { notFound ? model.actions.findClaude() : model.actions.patch() }
                footnote
                if !notFound { KeychainSoonLine() }
                if !notFound, let work = model.patchWorkNote {
                    Text(work).font(.system(size: 11)).foregroundColor(PanelColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .running(let step):
                BigButton(title: step, enabled: false) {}
                footnote
                // WF234: абзаца заранее нет — пример окна связки ключей показываем, когда патч уже идёт.
                if !notFound { KeychainExample() }
            case .failed(let why):
                BigButton(title: model.patchFix ?? "Ещё раз") { model.actions.patch() }
                Text(why).font(.system(size: 11)).foregroundColor(PanelColor.bad)
                    .fixedSize(horizontal: false, vertical: true)
                LinkButton(title: "Подробнее…") { model.actions.patchLog() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var notFound: Bool { model.patch == .claudeNotFound }

    @ViewBuilder private var footnote: some View {
        if notFound {
            LinkButton(title: card.footnote) { NSWorkspace.shared.open(URL(string: "https://claude.ai/download")!) }
        } else {
            Text(card.footnote).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Доступы Claude в macOS (#10252) — с #10310 мастер доступов (`AccessWizardCard`, `PanelAccess.swift`).
struct AccessCardView: View {
    @ObservedObject var model: PanelModel

    var body: some View { AccessWizardCard(model: model) }
}

// MARK: цвета (§2.3; с WF129 — #9040, #9020)

/// Квадрат цвета PMP (#9020 п. 7: «красивее, крупнее»): 31 pt; наведение — 1,08 пружиной, выбран — рамка цвета
/// текста через зазор 3 pt.
private struct ColorTile<Face: View>: View {
    static var size: CGFloat { 31 }
    var size: CGFloat = 31
    let selected: Bool
    let help: String
    let hover: (Bool) -> Void
    let action: () -> Void
    @ViewBuilder let face: () -> Face
    @State private var hovering = false

    var body: some View {
        let radius: CGFloat = size > Self.size ? 11 : 8
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Button(action: action) {
            face()
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                    .strokeBorder(PanelColor.text, lineWidth: selected ? 2 : 0).padding(-3))
                .scaleEffect(hovering ? 1.08 : 1)
                .animation(PanelSpring.press, value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            hovering = inside
            hover(inside)
        }
        .handCursor()
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Оформление. С 03.11.2026 (слово: «вся эта система оформления… перегружена, нелогичная», «скрытые настройки, неочевидные,
/// что можно нажать», «пример Винды возьми») — один лист сверху вниз, без шестерёнки и второго нажатия: цвет и живой фон,
/// отсчёт с таймером, вид окон и текста, возврат к Claude. Блока «цвет у каждого проекта» и схем живого фона в панели нет.
/// Имя цвета пишет сама панель в строке «Цвет»: под курсором — имя образца, иначе — выбранного (системная подсказка
/// `.help` в неактивирующей панели показывалась через раз). Наведение на цвет — ещё и примерка в окне Claude.
struct ColorsCard: View {
    @ObservedObject var model: PanelModel
    @State private var plainHover = false
    @State private var hovered: PanelColorTiles.Tile?
    @Environment(\.panelType) private var type

    static let swatchHeight: CGFloat = 22
    /// Промежуток между плитками — один на все ряды блока, края рядов — по краям блока.
    static let gap: CGFloat = 4

    /// Цвета окон живут патчем: без него образцы приглушены и не нажимаются.
    private var patched: Bool {
        switch model.patch {
        case .installed, .unknown: return true
        default: return false
        }
    }

    private var picked: PanelColorTiles.Tile? { PanelColorTiles.picked(model.windowColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Шеврон у названия и нажатие по нему — общие у всех блоков (`WidgetTitle`, `WidgetCell`).
            type.label.text(PanelColorTiles.title).fixedSize(horizontal: false, vertical: true).widgetTitle()
                .frame(minHeight: 18)
            // WF210 (#9379 п. 2): беда патча — своей строкой под заголовком.
            if let trouble = trouble {
                Text(trouble).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    NameLine(title: PanelColorTiles.colorTitle, live: hovered != nil,
                             name: PanelColorTiles.shownName(hovered: hovered, choice: model.windowColor,
                                                             themes: model.allThemes))
                    strips
                        .opacity(patched ? 1 : 0.4)
                        .disabled(!patched)
                        .onHover { inside in
                            if !inside {
                                hovered = nil
                                model.actions.previewWindowColor(nil)
                            }
                        }
                    ExtraSwitchRow(title: PanelColorTiles.liveTitle, help: PanelColorTiles.liveHelp,
                                   on: model.liveBackground) {
                        model.actions.live(model.liveBackground ? nil : .live)
                    }
                    .opacity(patched ? 1 : 0.4)
                    .disabled(!patched)
                }
                CountdownRow(model: model)
                windowRows
            }
            // #10394: подсветка клавиатуры — узкая полоска внизу «Оформления».
            if NightLight.supported { NightStrip() }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Вид окон и текста: всё сразу на виду, строки одного вида — подпись слева, управление справа. Всё — всем окнам.
    private var windowRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                ExtraZoomRow(value: model.claudeZoom) { model.actions.zoom($0) }
                ExtraSizeRow(value: model.windowTextSize) { model.actions.textSize($0) }
                fontRow
                ExtraSwitchRow(title: PanelColorTiles.denseTitle, help: PanelColorTiles.denseHelp, on: model.denseText) {
                    model.actions.dense(!model.denseText)
                }
                ExtraSwitchRow(title: PanelColorTiles.hideToolsTitle, help: PanelColorTiles.hideToolsHelp,
                               on: model.hideTools) { model.actions.hideTools(!model.hideTools) }
                ExtraSwitchRow(title: PanelColorTiles.hideCodeTitle, help: PanelColorTiles.hideCodeHelp,
                               on: model.hideCode) { model.actions.hideCode(!model.hideCode) }
            }
            .opacity(patched ? 1 : 0.4)
            .disabled(!patched)
            plainRow
        }
    }

    /// «Шрифт» (WF237): справа — имя шрифта окон, по нажатию — «Как у Claude» и шрифты по секциям прежнего меню.
    private var fontRow: some View {
        let chosen = model.windowFonts.first { $0.id == model.windowFontID }
        return ExtraMenuRow(title: PanelColorTiles.fontTitle, value: chosen?.name ?? PanelColorTiles.fontPlain,
                            help: PanelColorTiles.fontHelp) {
            Button { if chosen != nil { model.actions.windowFont(nil) } } label: {
                if chosen == nil { Label(PanelColorTiles.fontPlain, systemImage: "checkmark") }
                else { Text(PanelColorTiles.fontPlain) }
            }
            ForEach(PanelColorTiles.fontSections, id: \.id) { section in
                let fonts = model.windowFonts.filter { $0.section == section.id }
                if !fonts.isEmpty {
                    Section(section.title) {
                        ForEach(fonts) { font in
                            Button { if font.id != chosen?.id { model.actions.windowFont(font.id) } } label: {
                                if font.id == chosen?.id { Label(font.name, systemImage: "checkmark") } else { Text(font.name) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// «Как у Claude»: справа «Вернуть» — снимает цвет окон; обычный вид уже стоит — тихая пометка вместо кнопки.
    private var plainRow: some View {
        let now = model.windowColor == .plain
        return Button { model.actions.windowColor(.plain) } label: {
            HStack(spacing: 6) {
                Text(PanelColorTiles.plainName).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                Spacer(minLength: 6)
                if now {
                    Text(PanelColorTiles.plainNow).font(.system(size: 11)).foregroundColor(PanelColor.sub.opacity(0.7))
                } else {
                    Text(PanelColorTiles.plainAction).font(.system(size: 11)).foregroundColor(PanelColor.text)
                        .padding(.horizontal, 8).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.white.opacity(plainHover ? 0.4 : 0.22), lineWidth: 1))
                }
            }
            .frame(minHeight: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { plainHover = $0 }
        .handCursor()
        .opacity(patched ? 1 : 0.4)
        .disabled(!patched || now)
        .accessibilityLabel(now ? "\(PanelColorTiles.plainName), \(PanelColorTiles.plainNow)"
                                : "\(PanelColorTiles.plainAction) вид \(PanelColorTiles.plainName)")
    }

    /// Строка под заголовком — только беда патча.
    private var trouble: String? {
        if case .lost = model.patch { return "Цвета окон вернутся вместе с патчем" }
        return patched ? nil : "Цвета окон — после патча"
    }

    static var systemDark: Bool { NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    /// Полосы цветов: поровну образцов равной ширины, края в край; короткая последняя держит ту же ширину.
    private var strips: some View {
        let rows = PanelColorTiles.strips(model.windowThemes)
        let width = rows.map { $0.count }.max() ?? 0
        return VStack(alignment: .leading, spacing: Self.gap + 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, strip in
                HStack(spacing: Self.gap) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { _, tile in swatch(tile) }
                    ForEach(0..<max(0, width - strip.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity).frame(height: Self.swatchHeight)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func swatch(_ tile: PanelColorTiles.Tile) -> some View {
        let selected = picked == tile
        let name = PanelColorTiles.name(tile, themes: model.windowThemes)
        switch tile {
        // «Как у Claude» с WF245 не плитка: полосы её не дают.
        case .plain: EmptyView()
        case .theme(let id):
            if let chip = model.windowThemes.first(where: { $0.id == id }) {
                ColorSwatch(background: PanelColor.css(chip.background), accent: PanelColor.css(chip.accent),
                            selected: selected, name: name, hover: { swatchHover(tile, .theme(id), $0) },
                            action: { model.actions.windowColor(.theme(id)) })
            }
        }
    }

    /// Наведение на цвет — его имя в строке «Цвет» и примерка в окне Claude в фокусе.
    private func swatchHover(_ tile: PanelColorTiles.Tile, _ choice: WindowColorChoice, _ inside: Bool) {
        if inside {
            hovered = tile
            model.actions.previewWindowColor(choice)
        } else if hovered == tile {
            hovered = nil
        }
    }
}

/// Строка дополнительного оформления с выключателем (WF237): подпись 11 слева, выключатель справа; нажатие по всей
/// строке, под курсором — подложка, как у строк настроек.
private struct ExtraSwitchRow: View {
    let title: String
    let help: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                Spacer(minLength: 6)
                Switch(on: on)
            }
            .frame(minHeight: 22)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(hover ? 0.06 : 0)))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { hover = $0 }
        .handCursor()
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "Включено" : "Выключено")
    }
}

/// Строка дополнительного оформления со списком (WF237): подпись слева, справа — выбранное и стрелка списка.
private struct ExtraMenuRow<Items: View>: View {
    let title: String
    let value: String
    let help: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            Spacer(minLength: 6)
            Menu { items() } label: {
                Text(value).font(.system(size: 11)).foregroundColor(PanelColor.text).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            // Свой отступ справа у кнопки-меню AppKit — 6 pt: без сдвига стрелка не встаёт по правому краю
            // выключателей и «+» строк ниже.
            .padding(.trailing, -6)
            .handCursor()
        }
        .frame(minHeight: 22)
        .help(help)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// «Размер −  15  +» (WF237, лист 48): шаги прежнего меню, «как у Claude» — между 15 и 16
/// (`PanelColorTiles.sizeLadder`); на краю лестницы кнопка бледнеет и не нажимается.
private struct ExtraSizeRow: View {
    let value: Int?
    let pick: (Int?) -> Void

    var body: some View {
        let down = PanelColorTiles.sizeStep(from: value, up: false)
        let up = PanelColorTiles.sizeStep(from: value, up: true)
        let shown = value.map(String.init) ?? PanelColorTiles.sizePlain
        HStack(spacing: 6) {
            Text(PanelColorTiles.sizeTitle).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            Spacer(minLength: 6)
            StepButton(symbol: "minus", label: "Меньше", step: down, pick: pick)
            Text(shown).font(.system(size: 11).monospacedDigit()).foregroundColor(PanelColor.text)
                .frame(minWidth: 76)
            StepButton(symbol: "plus", label: "Больше", step: up, pick: pick)
        }
        .frame(minHeight: 22)
        .help(PanelColorTiles.sizeHelp)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(PanelColorTiles.sizeTitle): \(shown)")
    }
}

/// «Масштаб окна −  100 %  +»: шаг — пункт меню Claude (`ClaudeZoom`), нажатие по числу — обычный размер. Claude держит
/// масштаб сам и одним на все окна.
private struct ExtraZoomRow: View {
    let value: Int?
    let step: (ClaudeZoom) -> Void

    var body: some View {
        let shown = value.map { "\($0) %" } ?? "—"
        HStack(spacing: 6) {
            Text(PanelColorTiles.zoomTitle).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            Spacer(minLength: 6)
            StepButton(symbol: "minus", label: "Мельче", step: .some(nil)) { _ in step(.smaller) }
            Button { step(.actual) } label: {
                Text(shown).font(.system(size: 11).monospacedDigit()).foregroundColor(PanelColor.text)
                    .frame(minWidth: 76).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .handCursor()
            .help(PanelColorTiles.zoomResetHelp)
            StepButton(symbol: "plus", label: "Крупнее", step: .some(nil)) { _ in step(.larger) }
        }
        .frame(minHeight: 22)
        .help(PanelColorTiles.zoomHelp)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(PanelColorTiles.zoomTitle): \(shown)")
    }
}

/// Кнопка «−» / «+» у размера: круг 20 pt, под курсором светлее; шага нет — бледная.
private struct StepButton: View {
    let symbol: String
    let label: String
    let step: Int??
    let pick: (Int?) -> Void
    @State private var hover = false

    var body: some View {
        Button { if case .some(let next) = step { pick(next) } } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .foregroundColor(PanelColor.text)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(hover && step != nil ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .handCursor()
        .opacity(step == nil ? 0.35 : 1)
        .disabled(step == nil)
        .accessibilityLabel(label)
    }
}

/// Строка «Цвет · Фиолетовая» / «Отсчёт · Ракета» над рядом плиток: подпись и имя — под курсором (ярче) или
/// выбранного. Имя видно всегда и сразу — системной подсказки ждать не надо.
private struct NameLine: View {
    let title: String
    let live: Bool
    let name: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            if !name.isEmpty {
                Text(" · ").font(.system(size: 11)).foregroundColor(PanelColor.sub)
                Text(name).font(.system(size: 11)).foregroundColor(live ? PanelColor.text : PanelColor.sub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Лицо образца: фон темы и полоса акцента снизу — так выглядит окно, а не одна кнопка.
private struct ColorSwatchFace: View {
    let background: Color
    let accent: Color

    var body: some View {
        // WF180 («плитки заметно разные»): акцент — нижние две пятых, тёмные темы различаются им, а не фоном.
        GeometryReader { box in
            background.overlay(alignment: .bottom) { accent.frame(height: max(4, (box.size.height * 0.4).rounded())) }
        }
    }
}

/// Образец цвета (WF174): скруглённый прямоугольник — фон темы с полоской акцента; наведение — 1,08 пружиной,
/// выбран — рамка цвета текста через зазор 2 pt. Имя — в строке «Цвет» над полосами (WF242) и для VoiceOver.
private struct ColorSwatch: View {
    let background: Color
    let accent: Color
    let selected: Bool
    let name: String
    let hover: (Bool) -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button(action: action) {
            ColorSwatchFace(background: background, accent: accent)
                .frame(maxWidth: .infinity)
                .frame(height: ColorsCard.swatchHeight)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(PanelColor.text, lineWidth: selected ? 1.5 : 0).padding(-2))
                .scaleEffect(hovering ? 1.08 : 1)
                .animation(PanelSpring.press, value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            hovering = inside
            hover(inside)
        }
        .handCursor()
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// «Отсчёт»: ряд из восьми плиток — вид К1 v3 на кнопке «Отправить» (`CountdownFace`), выбранный в рамке, под ним таймер и
/// размер. С WF242 в покое плитки неподвижны, под курсором через 0,3 с плитка играет свой вид; цвета — темы окон. С 03.11.2026
/// настройки всегда на виду (слово: «скрытые настройки… неочевидные»), нажатие только выбирает вид. Настройка macOS
/// «Уменьшить движение» плитки не останавливает (#9204): оживают они только по наведению.
private struct CountdownRow: View {
    @ObservedObject var model: PanelModel
    @State private var pending: DispatchWorkItem?

    var body: some View {
        let current = SendLook.isStyle(model.sendLookStyle) ? model.sendLookStyle : SendLook.defaultStyle
        let palette = PanelCountdown.palette(model.windowColor, themes: model.allThemes, dark: ColorsCard.systemDark)
        let scale = PanelCountdown.tileScale(size: model.sendLookSize)
        let seconds = PanelCountdown.tileSeconds(model.sendDelay)
        VStack(alignment: .leading, spacing: 5) {
            NameLine(title: PanelColorTiles.countdownTitle, live: model.countdownHover.hovered != nil,
                     name: SendLook.name(model.countdownHover.hovered ?? current))
            HStack(spacing: ColorsCard.gap) {
                ForEach(SendLook.styles, id: \.id) { style in
                    CountdownTile(style: style.id, name: style.name, selected: style.id == current,
                                  palette: palette, scale: scale, seconds: seconds,
                                  playingSince: model.countdownHover.playing == style.id ? model.countdownSince : nil,
                                  hover: { hover(style.id, $0) }) {
                        if style.id != current { model.actions.sendLookStyle(style.id) }
                    }
                }
            }
            .padding(.vertical, 2)
            CountdownSettings(model: model, name: SendLook.name(current))
        }
        .onDisappear {
            pending?.cancel()
            model.countdownHover = CountdownHover()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Вид отсчёта: \(SendLook.name(current))")
    }

    /// Курсор над плиткой — её имя сразу, вид оживает через 0,3 с покоя; ушёл — замирает.
    private func hover(_ style: String, _ inside: Bool) {
        if inside {
            model.countdownHover.enter(style)
            pending?.cancel()
            let work = DispatchWorkItem {
                model.countdownSince = Date()
                model.countdownHover.rested(style)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + PanelCountdown.hoverDelay, execute: work)
        } else {
            if model.countdownHover.hovered == style {
                pending?.cancel()
                pending = nil
            }
            model.countdownHover.leave(style)
        }
    }
}

/// Настройки отсчёта под плитками: таймер (`PanelCountdown.delayItems`, «Нет» выключает счёт), а при включённом — размер
/// 60…200 % и показ.
private struct CountdownSettings: View {
    @ObservedObject var model: PanelModel
    let name: String

    var body: some View {
        let delay = model.sendDelay
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(PanelColorTiles.timerTitle).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                Segments(items: PanelCountdown.delayItems, selected: delay.on ? delay.seconds : 0) { seconds in
                    model.actions.sendDelay(seconds != 0, seconds == 0 ? delay.seconds : seconds)
                }
            }
            .help(PanelColorTiles.timerHelp)
            if delay.on {
                HStack(alignment: .top, spacing: 10) {
                    Text(PanelColorTiles.rocketSizeTitle).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                        .frame(height: 18)
                    MarkSlider(value: model.sendLookSize, range: PanelCountdown.sizeRange, marks: PanelCountdown.sizeMarks,
                               step: SendLook.step, unit: "%", label: "Размер отсчёта") { size in
                        model.actions.sendLookSize(PanelCountdown.size(size))
                    }
                }
                .padding(.top, 2)
                SettingsActionRow(title: "Показать в окне Claude", chevron: true) {
                    model.actions.previewSendDelay(delay.seconds)
                }
                .help("Показать отсчёт «\(name)» в окне Claude, ничего не отправляя")
            }
            if let line = model.sendDelayLine {
                Text(line).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Настройки отсчёта «\(name)»")
    }
}

/// Плитка вида отсчёта: фон окна темы, на нём кнопка «Отправить» с видом; наведение — 1,05 пружиной и рамка ярче,
/// выбран — рамка цвета текста через зазор 2 pt, как у цветов. `playingSince` — с какого момента вид играет; nil —
/// неподвижный кадр.
private struct CountdownTile: View {
    let style: String
    let name: String
    let selected: Bool
    let palette: CountdownPalette
    let scale: Double
    /// С какой цифры считает плитка — настоящий таймер.
    let seconds: Int
    let playingSince: Date?
    let hover: (Bool) -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: action) {
            Group {
                if let since = playingSince {
                    TimelineView(.animation) { context in
                        CountdownFace(style: style, palette: palette, scale: scale,
                                      frame: PanelCountdown.frame(at: PanelCountdown.stillTime
                                                                  + context.date.timeIntervalSince(since),
                                                                  seconds: seconds))
                    }
                } else {
                    CountdownFace(style: style, palette: palette, scale: scale,
                                  frame: PanelCountdown.frame(at: PanelCountdown.stillTime, seconds: seconds))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(shape.fill(PanelColor.hex(palette.background)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(hovering ? 0.28 : 0.12), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PanelColor.text, lineWidth: selected ? 1.5 : 0).padding(-2))
            .scaleEffect(hovering ? 1.05 : 1)
            .animation(PanelSpring.press, value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            hovering = inside
            hover(inside)
        }
        .handCursor()
        .accessibilityLabel("Отсчёт: " + name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Кадр вида отсчёта на круглой кнопке «Отправить» — как рисует страница (раздел 12у `inject.js`): акцент, фон поля
/// и цвет текста — темы окон (`CountdownPalette`), янтарь шнура и пламени — свой у вида. `frame` — момент: цифра,
/// доля секунды, доля счёта, пуск. `scale` — размер цифры и ракеты (`PanelCountdown.tileScale`).
private struct CountdownFace: View {
    let style: String
    let palette: CountdownPalette
    let scale: Double
    let frame: PanelCountdown.Frame

    private static let amber = PanelColor.hex(0xF59E0B)
    private static let side: CGFloat = 20

    // Тело разбито на функции по видам: одно выражение `switch` на все виды не успевал проверить компилятор
    // Command Line Tools на M2 (Мак коллеги, 19.10.2026: «unable to type-check this expression in reasonable time»).
    var body: some View {
        ZStack { styled }
            .frame(width: Self.side, height: Self.side)
            .accessibilityHidden(true)
    }

    private var accent: Color { PanelColor.hex(palette.accent) }
    private var ink: Color { PanelColor.hex(palette.ink) }
    private var field: Color { PanelColor.hex(palette.field) }
    private var tint: Color { PanelColor.hex(ColorMath.mix(palette.accent, palette.field, 0.22)) }
    private var digitInk: Color { PanelColor.hex(ColorMath.mix(palette.accent, palette.ink, 0.45)) }
    private var amber: Color { Self.amber }
    private var side: CGFloat { Self.side }
    private var k: CGFloat { CGFloat(scale) }
    private var beat: CGFloat { CGFloat(frame.beat) }
    private var passed: CGFloat { CGFloat(frame.passed) }
    private var flight: CGFloat? { frame.flight.map { CGFloat($0) } }
    /// Последняя секунда — вдвое чаще (как у страницы).
    private var pulse: CGFloat { frame.digit == 1 ? (beat * 2).truncatingRemainder(dividingBy: 1) : beat }

    @ViewBuilder private var styled: some View {
        switch style {
        case "1.8":
            style0()
        case "1.9":
            style1()
        case "1.10":
            style2()
        case "1.1":
            style3()
        case "1.2":
            style4()
        case "1.4":
            style5()
        case "1.6":
            style6()
        default:
            style7()
        }
    }

    /// Ракета: стрелка вверх, пламя под ней, метка секунд в углу; пуск — уходит вверх, за ней линия.
    @ViewBuilder private func style0() -> some View {
        Circle().fill(tint)
        if let flight = flight { rocketFlight(flight) } else { rocketWait() }
    }

    /// Ракета в полёте: уходит вверх, за ней линия.
    @ViewBuilder private func rocketFlight(_ flight: CGFloat) -> some View {
        let rise: CGFloat = flight * flight * 34
        let fade: Double = Double(min(1, (1 - flight) * 2.2))
        let size: CGFloat = 10 * k * (1 + 0.5 * flight)
        let trail = LinearGradient(colors: [PanelColor.hex(0xFFF6D0), amber, amber.opacity(0.3)],
                                   startPoint: .top, endPoint: .bottom)
        Capsule().fill(trail)
            .frame(width: 2 * k, height: max(1, rise)).offset(y: -rise / 2)
            .opacity(fade)
        Image(systemName: "arrow.up").font(.system(size: size, weight: .bold))
            .foregroundColor(digitInk).offset(y: -rise)
    }

    /// Ракета ждёт: пламя под стрелкой, метка секунд в углу.
    @ViewBuilder private func rocketWait() -> some View {
        let wobble: CGFloat = 1.5 * sin(beat * .pi * 10)
        let flame: CGFloat = (6 + 5 * passed + wobble) * k
        let shake: CGFloat = frame.digit == 1 ? 0.6 * sin(beat * .pi * 24) : 0
        let fire = LinearGradient(colors: [PanelColor.hex(0xFFF6D0), amber, amber.opacity(0)],
                                  startPoint: .top, endPoint: .bottom)
        Capsule().fill(fire)
            .frame(width: 5 * k, height: flame).offset(y: 4 * k + flame / 2)
        Image(systemName: "arrow.up").font(.system(size: 10 * k, weight: .bold)).foregroundColor(digitInk)
            .offset(x: shake)
        Text(digit).font(.system(size: 7, weight: .heavy)).foregroundColor(PanelColor.hex(0x1F1E1D))
            .frame(width: 10, height: 10).background(Circle().fill(amber))
            .background(Circle().fill(field).padding(-1)).offset(x: 9, y: -9)
    }

    /// Пульс: цифра дышит, от кнопки расходится мягкая волна.
    @ViewBuilder private func style1() -> some View {
        wave(accent.opacity(0.55), progress: flight ?? pulse, reach: flight == nil ? 1.5 : 1.9, width: 1.5)
        Circle().fill(tint).frame(width: side, height: side)
        face(digit, size: 13, weight: .heavy,
             color: PanelColor.hex(ColorMath.mix(palette.accent, palette.ink, 0.7)), k: k)
            .scaleEffect(flight == nil ? 1 + 0.16 * sin(pulse * .pi) : 1)
    }

    /// Мерцание: ореол вокруг кнопки то ярче, то тише.
    @ViewBuilder private func style2() -> some View {
        let glow = 0.35 + 0.45 * (0.5 + 0.5 * sin(pulse * 2 * .pi))
        if let flight = flight { wave(accent, progress: flight, reach: 2.2, width: 2) }
        Circle().stroke(accent.opacity(flight == nil ? Double(glow) : 0.25), lineWidth: 3).blur(radius: 2.5)
            .frame(width: side + 3, height: side + 3)
        Circle().fill(tint).frame(width: side, height: side)
        face(digit, size: 11, weight: .semibold, color: digitInk, k: k)
    }

    /// Штрих по кругу: дуга растёт с головой-точкой и замыкается.
    @ViewBuilder private func style3() -> some View {
        if let flight = flight { wave(accent, progress: flight, reach: 1.5, width: 2) }
        Circle().fill(tint)
        Circle().stroke(ink.opacity(0.12), lineWidth: 2)
        Circle().trim(from: 0, to: max(0.02, passed)).stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
        if flight == nil {
            Circle().fill(Color.white).frame(width: 3, height: 3).offset(y: -side / 2)
                .rotationEffect(.degrees(360 * Double(passed)))
        }
        face(digit, size: 10, weight: .bold, color: digitInk, k: k)
    }

    /// Удар: сплошной диск акцента, на каждую секунду — ударная волна.
    @ViewBuilder private func style4() -> some View {
        wave(accent.opacity(0.7), progress: flight ?? beat, reach: flight == nil ? 1.6 : 2.6, width: 1.5)
        Circle().fill(accent).frame(width: side - 2, height: side - 2)
            .scaleEffect(flight == nil ? 1 + 0.12 * (1 - beat) * (1 - beat) : 1)
        face(digit, size: 11, weight: .heavy, color: .white, k: k)
    }

    /// Кольцо: тонкое кольцо тает, цифра спокойная.
    @ViewBuilder private func style5() -> some View {
        Circle().fill(field)
        Circle().stroke(ink.opacity(0.08), lineWidth: 1.5)
        Circle().trim(from: min(passed, 0.999), to: 1)
            .stroke(ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
        face(digit, size: 10, weight: .semibold, color: ink, k: k)
    }

    /// Шнур: искра бежит по шнуру к кнопке с янтарной цифрой.
    @ViewBuilder private func style6() -> some View {
        if let flight = flight {
            wave(amber, progress: flight, reach: 2.2, width: 2)
        } else {
            let rope = 8 * (1 - passed)
            Capsule().fill(amber.opacity(0.8)).frame(width: max(0.5, rope), height: 1.4)
                .offset(x: -side / 2 - rope / 2)
            Circle().fill(PanelColor.hex(0xFFD27A)).frame(width: 3.5, height: 3.5)
                .offset(x: -side / 2 - rope - 1)
                .shadow(color: amber, radius: 2)
        }
        Circle().fill(field).frame(width: side, height: side)
        Circle().strokeBorder(amber.opacity(0.6), lineWidth: 1.2).frame(width: side, height: side)
        face(digit, size: 10, weight: .bold, color: amber, k: k)
    }

    /// 1.5 Спокойная цифра: светлая кнопка, цифра цветом поля.
    @ViewBuilder private func style7() -> some View {
        Circle().fill(ink)
        face(digit, size: 10, weight: .semibold, color: field, k: k)
    }

    private var digit: String { frame.digit > 0 ? "\(frame.digit)" : "" }

    /// Цифра на кнопке; счёт кончился — стрелка «Отправить», как у кнопки без отсчёта. Размер — по `k`, но не шире
    /// кнопки (как у страницы: цифра не вылезает из своего круга).
    @ViewBuilder private func face(_ digit: String, size: CGFloat, weight: Font.Weight, color: Color, k: CGFloat) -> some View {
        if digit.isEmpty {
            Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundColor(color)
        } else {
            Text(digit).font(.system(size: min(size * k, Self.side - 4), weight: weight)).foregroundColor(color)
        }
    }

    /// Волна от кнопки: кольцо растёт до `reach` своих размеров и тает.
    private func wave(_ color: Color, progress: CGFloat, reach: CGFloat, width: CGFloat) -> some View {
        Circle().strokeBorder(color.opacity(Double(max(0, 1 - progress))), lineWidth: width)
            .frame(width: Self.side, height: Self.side)
            .scaleEffect(1 + (reach - 1) * progress)
    }
}

/// Цвет PMP (#9020 п. 1–5): под шапкой по нажатию на значок; значок у часов и в шапке меняются вместе. С WF189
/// (слово Элвиса 09.10 04:00): цвета — одним рядом по всей ширине блока, по цветовому кругу, без подписи имени (имя —
/// подсказкой); ниже — варианты значка у часов той же сеткой («Как с цветами сделай — варианты»).
struct AccentCard: View {
    @ObservedObject var model: PanelModel
    /// Девять цветов края в край по ширине блока (296 pt): 9 × 28 и восемь равных промежутков ≈ 5,5 pt.
    static let tile: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccentTitle(title: "Цвет PMP", note: "значок у часов и эта панель")
            HStack(spacing: 0) {
                ForEach(Array(PMPAccent.allCases.enumerated()), id: \.element) { index, accent in
                    if index > 0 { Spacer(minLength: 2) }
                    ColorTile(size: Self.tile, selected: model.accent == accent, help: accent.name,
                              hover: { inside in
                                  if inside { model.accentPreview = accent }
                                  else if model.accentPreview == accent { model.accentPreview = nil }
                              },
                              action: { model.actions.setAccent(accent) }) {
                        PanelColor.hex(accent.hex)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            AccentTitle(title: "Значок", note: "в строке меню").padding(.top, 4)
            IconGroup(model: model)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct AccentTitle: View {
    let title: String
    let note: String
    @Environment(\.panelType) private var type

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            type.label.text(title)
            type.note.text(note)
            Spacer(minLength: 0)
        }
    }
}
