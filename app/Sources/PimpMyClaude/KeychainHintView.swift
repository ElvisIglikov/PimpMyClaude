import ClaudeAX
import SwiftUI

// Виды подсказки у окна macOS «Claude Safe Storage» (WF238, #9580; макет `docs/41.html`): плашка под окном
// macOS и нарисованный пример самого окна. Слова и расчёт — `KeychainHint` в ClaudeAX, окно — `KeychainHintWindow.swift`.

/// Пример окна macOS «„Claude“ хочет использовать конфиденциальную информацию…» — нарисован по настоящему
/// (`docs/ref/claude-svyazka-klyuchey.png`): замок, заголовок, подпись, поле пароля, «?» и три кнопки. Не снимок
/// экрана: резкий на любом мониторе. Поле не принимает ввод; кнопки нажимаются только в пробе (`press`).
struct KeychainDialogExample: View {
    /// Компактный — в карточке панели у часов; полный — размером с настоящее окно (проба).
    var compact = false
    /// Обвести «Разрешать всегда» цветом PMP (в карточке: это наш пример, поверх него рисовать можно).
    var marked = false
    /// Нажали кнопку примера.
    var press: (() -> Void)?
    @Environment(\.pmpAccent) private var accent

    /// Ширина настоящего окна macOS, pt.
    static let fullWidth: CGFloat = 477
    private static let window = PanelColor.hex(0x1C1E29)
    private static let control = PanelColor.hex(0x2B2E3B)
    private static let lockGold = PanelColor.hex(0xE9A23B)

    private var pad: CGFloat { compact ? 10 : 20 }
    private var icon: CGFloat { compact ? 28 : 50 }
    private var gap: CGFloat { compact ? 9 : 17 }
    private var titleFont: Font { .system(size: compact ? 11 : 13, weight: .bold) }
    private var textFont: Font { .system(size: compact ? 10 : 11) }
    private var controlFont: Font { .system(size: compact ? 10 : 13) }
    private var controlHeight: CGFloat { compact ? 20 : 23 }
    private var radius: CGFloat { compact ? 12 : 26 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 15) {
            HStack(alignment: .top, spacing: gap) {
                lock
                VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                    Text(PimpPanelText.keychainTitle).font(titleFont).foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(PimpPanelText.keychainBody).font(textFont).foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: compact ? 5 : 7) {
                        Text(PimpPanelText.keychainPassword).font(controlFont).foregroundColor(.white.opacity(0.92))
                        RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous).fill(Self.control)
                            .frame(maxWidth: .infinity).frame(height: compact ? 18 : 25)
                            .overlay(RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .padding(.top, compact ? 2 : 5)
                }
            }
            HStack(spacing: 0) {
                Text("?").font(.system(size: compact ? 10 : 13, weight: .medium)).foregroundColor(.white.opacity(0.85))
                    .frame(width: controlHeight, height: controlHeight)
                    .background(Circle().fill(Self.control))
                    // Как в настоящем окне: «?» под замком, кнопки — во всю колонку текста, от её левого края до правого.
                    .frame(width: icon)
                    .padding(.trailing, gap)
                HStack(spacing: compact ? 4 : 12) {
                    button(PimpPanelText.keychainAlways, marked: marked, wide: false)
                    button(PimpPanelText.keychainDeny, marked: false, wide: true)
                    button(PimpPanelText.keychainAllow, marked: false, wide: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(pad)
        .frame(maxWidth: compact ? .infinity : nil)
        .frame(width: compact ? nil : Self.fullWidth)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Self.window))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Пример окна macOS: \(PimpPanelText.keychainTitle) \(PimpPanelText.keychainBody) "
            + "Кнопки: \(PimpPanelText.keychainAlways), \(PimpPanelText.keychainDeny), \(PimpPanelText.keychainAllow)")
        // #11181 (WF298): кнопки внутри скрыты от доступности (`children: .ignore`) — нажатие пробы AXPress идёт сюда.
        .accessibilityAction(.default) { press?() }
    }

    /// Замок связки ключей со значком программы на углу.
    private var lock: some View {
        Image(systemName: "lock.fill").font(.system(size: icon * 0.82)).foregroundColor(Self.lockGold)
            .frame(width: icon, height: icon)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "asterisk").font(.system(size: icon * 0.26, weight: .bold)).foregroundColor(.white)
                    .frame(width: icon * 0.46, height: icon * 0.46)
                    .background(RoundedRectangle(cornerRadius: icon * 0.11, style: .continuous)
                        .fill(PanelColor.hex(0x33302C)))
                    .offset(x: icon * 0.08, y: icon * 0.04)
            }
    }

    private func button(_ title: String, marked: Bool, wide: Bool) -> some View {
        Text(title).font(controlFont.weight(marked ? .semibold : .regular)).foregroundColor(.white)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, compact ? 4 : 14)
            .frame(maxWidth: wide ? .infinity : nil).frame(height: controlHeight)
            .background(RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
                .fill(marked ? accent.opacity(0.24) : Self.control))
            .overlay(RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
                .strokeBorder(marked ? accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
            .onTapGesture { press?() }
    }
}

/// Плашка PMP под окном macOS: что это за окно и что нажать; окно закрыли — «Готово…». Кайма своя, тонкая —
/// жидкая рамка идёт снаружи отдельными окнами-слоями.
struct KeychainHintPlaque: View {
    enum Content: Equatable {
        case hint(KeychainHint.Kind)
        case done(KeychainHint.Kind)
    }

    /// Нажимаемые места плашки.
    enum Spot: Hashable {
        case close, source
    }

    let content: Content
    let width: CGFloat
    var close: () -> Void = {}
    /// Куда плашка сообщает рамки нажимаемых мест (координаты плашки, y вниз) — нажатия ловит её окно.
    var spots: KeychainHintSpots?
    /// Стрелка к окну macOS (#9841): с той стороны, где окно; nil — без стрелки. Поле под неё есть всегда.
    var pointer: HintPull.Side?
    @Environment(\.pmpAccent) private var accent

    static let radius: CGFloat = 12
    fileprivate static let space = "keychain-hint"

    func openSource() {
        if let url = URL(string: PimpPanelText.openSourceURL) { NSWorkspace.shared.open(url) }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        Group {
            switch content {
            case .hint(let kind): hint(kind)
            case .done(let kind): done(kind)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: width, alignment: .leading)
        .background(shape.fill(PanelColor.panel))
        .overlay(shape.strokeBorder(accent.opacity(0.9), lineWidth: 1.5))
        .hintPointer(pointer, fill: PanelColor.panel, stroke: accent.opacity(0.9), lineWidth: 1.5)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(SpotKey.self) { spots?.frames = $0 }
    }

    private func hint(_ kind: KeychainHint.Kind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Badge(outlined: false)
                Text(KeychainHint.title).font(.system(size: 15, weight: .semibold)).foregroundColor(PanelColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                CloseButton(action: close).spot(.close)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(KeychainHint.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)").font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(PanelColor.ink)
                            .frame(width: 20, height: 20).background(Circle().fill(accent))
                            // Кружок шириной с плашку PMP — цифры и подписи шагов встают в одну колонку.
                            .frame(width: 32)
                        (Text(step.lead).font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
                            + Text(" — " + step.rest).font(.system(size: 13)).foregroundColor(PanelColor.sub))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Rectangle().fill(PanelColor.frame).frame(height: 1)
            VStack(alignment: .leading, spacing: 5) {
                quiet(KeychainHint.passwordStays)
                quiet(KeychainHint.reason(kind))
                HStack(spacing: 0) {
                    Button(action: openSource) {
                        Text(KeychainHint.sourceLink).font(.system(size: 12)).foregroundColor(accent).underline()
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .help(PimpPanelText.openSourceURL)
                    .spot(.source)
                    quiet(KeychainHint.sourceTail)
                }
            }
        }
    }

    private func done(_ kind: KeychainHint.Kind) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(PanelColor.ink)
                .frame(width: 24, height: 24).background(Circle().fill(accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(KeychainHint.doneTitle(kind)).font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PanelColor.text)
                quiet(KeychainHint.doneText)
            }
            Spacer(minLength: 0)
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundColor(PanelColor.sub).fixedSize(horizontal: false, vertical: true)
    }
}

/// Рамки нажимаемых мест плашки. Плашка не бывает ключевым окном (фокус остаётся у окна пароля), поэтому нажатия
/// ловит само окно — как у плашки маяка окон доступа — и сверяет с этими рамками.
final class KeychainHintSpots {
    var frames: [KeychainHintPlaque.Spot: CGRect] = [:]

    func spot(at point: CGPoint) -> KeychainHintPlaque.Spot? {
        frames.first { $0.value.contains(point) }?.key
    }
}

private struct SpotKey: PreferenceKey {
    static var defaultValue: [KeychainHintPlaque.Spot: CGRect] = [:]
    static func reduce(value: inout [KeychainHintPlaque.Spot: CGRect], nextValue: () -> [KeychainHintPlaque.Spot: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func spot(_ id: KeychainHintPlaque.Spot) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: SpotKey.self, value: [id: proxy.frame(in: .named(KeychainHintPlaque.space))])
        })
    }
}

/// Крестик плашки: тихий, под курсором — цветом текста; под мышь 24 pt.
private struct CloseButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                .foregroundColor(hover ? PanelColor.text : PanelColor.sub)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hover ? 0.12 : 0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .handCursor()
        .help(KeychainHint.closeHelp)
        .accessibilityLabel(KeychainHint.closeHelp)
    }
}
