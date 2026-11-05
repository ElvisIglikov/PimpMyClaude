import ClaudeAX
import SwiftUI

// MARK: открытые терминалы (#10464)

/// Слова блока «Терминалы».
enum TerminalsText {
    /// Таймер строки — прямой счёт с последней активности, как часы: «0:07», «3:56», «1:03:56» (слово Элвиса
    /// 22.10.2026: «наоборот, чтобы отсчёт шёл… без нуля, три двоеточия, 56—55… тик-тик-тик»); nil — не знаем.
    /// Цвет — кеш: тёплый (меньше часа с активности) — зелёный, остыл — серый.
    static func timer(_ terminal: PanelTerminal, now: Date) -> String? {
        terminal.idleSeconds(now: now).map(clock)
    }

    /// Подсказка строки: «🧼 VkusSES — тишина 3:56, кеш тёплый ещё 57 мин. Нажми — окно терминала».
    static func help(_ title: String, timer: String?, left: Int) -> String {
        let cache: String
        if let timer = timer {
            cache = "тишина " + timer + ", " + (left > 0 ? "кеш тёплый ещё \(left) мин" : "кеш остыл")
        } else {
            cache = "кеш неизвестен"
        }
        return title + " — " + cache + ". Нажми — окно терминала"
    }

    /// Минуты без нуля впереди, секунды двумя цифрами; от часа — «ч:мм:сс».
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// Свёрнутый блок: «4 · тёплых 2».
    static func collapsed(_ terminals: [PanelTerminal], now: Date) -> String? {
        guard !terminals.isEmpty else { return nil }
        let warm = terminals.filter { ($0.cacheMinutes(now: now) ?? 0) > 0 }.count
        return "\(terminals.count) · тёплых \(warm)"
    }
}

/// Блок «Терминалы» внизу панели (#10464; слово Элвиса 21.10.2026 12:10: «в самом низу терминалы открытые… лучшую
/// замену этих точек — сколько до протухания… даже картинки не нужны… один раз нажал… открывается окно терминала,
/// становится активным»): блок раскладки, как все — сворачивается, при наведении на подпись — значки управления.
/// Строки по две в ряд: имя проекта и счёт с последней активности (кеш тёплый — зелёным, остыл — серым); нажатие — окно Terminal
/// этого терминала вперёд. Данные — `PanelTerminals` (ClaudeAX), обновление — `PanelFeed`.
struct TerminalsBlock: View {
    @ObservedObject var model: PanelModel
    @Environment(\.panelType) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            type.label.text(PanelWidget.terminals.title).lineLimit(1).fixedSize().widgetTitle()
            if let alarm = model.terminalsAlarm {
                type.note.text(alarm, color: PanelColor.warn).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 4) {
                ForEach(model.terminals) { terminal in TerminalChip(model: model, terminal: terminal) }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct TerminalChip: View {
    @ObservedObject var model: PanelModel
    let terminal: PanelTerminal
    @State private var hover = false
    @Environment(\.panelType) private var type
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let timer = TerminalsText.timer(terminal, now: model.now)
        let left = terminal.cacheMinutes(now: model.now) ?? 0
        let warm = left > 0
        Button { model.showTerminal(terminal) } label: {
            HStack(spacing: 6) {
                type.note.text(terminal.name, color: PanelColor.text).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let timer = timer {
                    // Цифры одной ширины — строка не дрожит, когда секунды тикают.
                    type.note.text(timer, color: warm ? accent : PanelColor.sub).monospacedDigit()
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hover ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .handCursor()
        .help(TerminalsText.help(terminal.title, timer: timer, left: left))
        .accessibilityLabel(terminal.name + ", " + (timer ?? ""))
    }
}
