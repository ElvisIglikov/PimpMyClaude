import AppKit
import ClaudeAX
import SwiftUI

// MARK: лимиты

/// Полоска лимита: заливка — израсходованное (#7863, как у Claude), цвет — по остатку (8adc156); последнее известное,
/// не свежее (#9824) — серая: тревогу по старой цифре не поднимаем.
private struct LimitBar: View {
    @Environment(\.pmpAccent) private var accent
    let fill: Int?
    let left: Int?
    let height: CGFloat
    var stale = false

    private var color: Color {
        if stale { return PanelColor.sub }
        switch StatusIcon.level(left) {
        case .critical: return PanelColor.bad
        case .low: return PanelColor.warn
        case .normal: return PanelColor.good(accent)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                if let fill = fill, fill > 0 {
                    Capsule().fill(color).frame(width: max(height, proxy.size.width * CGFloat(fill) / 100))
                }
            }
        }
        .frame(height: height)
    }
}

/// Неделя (вернулась в #8958; значок с WF126 всегда про неделю). С WF242 — слово Элвиса 11.10.2026: «Вот этот верхний
/// виджет, где 85 % израсходовано, неделя, все модели — громоздкий… негармонично смотрится, сброс узенький, он высокий.
/// Сделай их как сброс»: той же высоты и плотности, что «Сброс» рядом, — строка «Неделя … 39 %», полоса 5 pt на
/// линии отрезков «Сброса», под ней подпись 11 на линии его дней. Данные те же: процент и полоса.
struct MainLimit: View {
    @ObservedObject var model: PanelModel
    @Environment(\.panelType) private var type

    // #10461 (слово Элвиса 21.10.2026 12:10: «неделей сброс крупными» — как у коллеги): подпись, крупное число с «%»,
    // полоса; как «5 часов». Нет свежих — последнее известное бледным и «было 25 мин назад» (#9824).
    var body: some View {
        let lim = StatusIcon.limit(.week, in: model.known)
        let left = StatusIcon.remaining(lim, now: model.now)
        let spent = StatusIcon.used(lim, now: model.now)
        let age = model.limitsAge
        VStack(alignment: .leading, spacing: 5) {
            type.label.text("Неделя").fixedSize().widgetTitle()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                type.hero.text(spent.map(String.init) ?? "—", color: left == nil || age != nil ? PanelColor.sub : nil)
                    .fixedSize()
                type.unit.text("%").fixedSize()
            }
            if model.known == nil || age != nil {
                type.note.text(model.known == nil ? "Лимиты придут, когда откроется окно Claude" : "было " + (age ?? ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Полоса — по низу карточки: в ряду с «Сбросом» и «5 часов» полосы на одной линии (слово Элвиса 22.10.2026:
            // «полоса процентов… и полоса дней… сравнялись в одну полосу»).
            Spacer(minLength: 0)
            LimitBar(fill: spent, left: left, height: 6, stale: age != nil)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .help(age.map { LimitsText.staleHelp($0) } ?? "")
    }
}

/// Слова несвежих лимитов (#9824).
enum LimitsText {
    static func staleHelp(_ age: String) -> String {
        "Последнее известное значение — \(age). Сейчас окно Claude не отвечает; свежие цифры придут, когда оно откроется"
    }
}

/// «5 часов» и «Fable» — два блока (WF174, #9182 п. 5), по умолчанию половинками в одном ряду.
struct LimitTile: View {
    @ObservedObject var model: PanelModel
    let kind: StatusIcon.Mode
    @Environment(\.panelType) private var type

    var body: some View {
        let lim = StatusIcon.limit(kind, in: model.known)
        let left = StatusIcon.remaining(lim, now: model.now)
        let spent = StatusIcon.used(lim, now: model.now)
        let age = model.limitsAge
        return VStack(alignment: .leading, spacing: 5) {
            // Подпись — той же роли, что «Неделя» и «Сброс» рядом (WF253: было «5 ЧАСОВ» капсом 10,5 против «Сброс» 13).
            type.label.text(kind == .fable ? "Fable" : "5 часов").fixedSize().widgetTitle()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                type.hero.text(spent.map(String.init) ?? "—", color: left == nil || age != nil ? PanelColor.sub : nil).fixedSize()
                type.unit.text("%").fixedSize()
            }
            // Строка под числом — `resetNote`: срок у «5 часов», запись про неделю у Fable; нет срока — пустая строка держит высоту плиток равной. Длинный срок
            // переносится после «через», без «…» (WF253). Над полосой: полоса — по низу карточки, на одной линии с
            // полосами соседей (22.10.2026).
            type.note.text(PanelShort.keepTogether(Self.resetNote(kind, in: model.known, now: model.now) ?? " "))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            LimitBar(fill: spent, left: left, height: 6, stale: age != nil)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .help(age.map { LimitsText.staleHelp($0) } ?? "")
    }
}

extension LimitTile {
    /// Строка под крупным числом. У «5 часов» — срок сброса. У Fable (слово 03.11.2026) вместо срока постоянная
    /// строка: он входит в недельный лимит и уменьшает его. Процент от недели не пишем, пока не проверен.
    static func resetNote(_ kind: StatusIcon.Mode, in limits: ClaudeLimits?, now: Date) -> String? {
        if kind == .fable { return fableNote }
        return StatusIcon.resetText(StatusIcon.limit(kind, in: limits)?.resetsAt, now: now)
    }

    static let fableNote = "Входит в лимит недели и уменьшает его"
}

// MARK: «Сброс»

/// «Сброс» (#8881, слово Элвиса 07.10: «в окне Пимпа не хватает… вот этого виджета»). С 03.11.2026 в одном стиле с
/// «Неделей» рядом: подпись, срок крупно, как 49 % («5д 2ч»: цифра ролью hero, буква ролью unit), буквы дней внизу,
/// сегодняшний ярче. Полосок под днями нет, линия букв совпадает с полосой «Недели».
struct WeekStripView: View {
    let strip: StatusIcon.WeekStrip
    /// Срок парами цифра и буква (`PanelShort.heroParts`).
    let parts: [PanelShort.HeroPart]
    /// Когда сброс — «пт 08:00» справа от названия (слово Элвиса 22.10.2026: «писалось ещё время сброса… 08—00»).
    var clock: String? = nil
    @Environment(\.panelType) private var type

    /// Одним `Text`: половинка уже крупного срока, поэтому «23ч 59м» ужимается целиком, а не переносится.
    private var hero: Text {
        guard !parts.isEmpty else { return type.hero.text("—", color: PanelColor.sub) }
        var line = Text(verbatim: "")
        for (index, part) in parts.enumerated() {
            if index > 0 { line = line + type.unit.text(" ") }
            line = line + type.hero.text(part.number) + type.unit.text(part.unit)
        }
        return line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                type.label.text("Сброс").fixedSize().widgetTitle()
                Spacer(minLength: 0)
                if let clock = clock { type.note.text(clock).monospacedDigit().lineLimit(1).fixedSize() }
            }
            // Ужатый срок держит базовую линию полного размера: иначе «23ч 59м» стоит выше числа «Недели» рядом.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                type.hero.text("0").lineLimit(1).fixedSize().hidden().frame(width: 0).accessibilityHidden(true)
                hero.lineLimit(1).minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(0..<strip.days.count, id: \.self) { index in
                    let today = index == strip.today
                    (today ? type.note.weight(.semibold) : type.note)
                        .text(String(strip.days[index].prefix(1)), color: today ? PanelColor.text : nil)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
            // Низ букв, без запаса шрифта под строкой, стоит на линии низа полосы «Недели».
            .padding(.bottom, -round(type.note.size * 0.22))
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
