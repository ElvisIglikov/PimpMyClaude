import AppKit
import SwiftUI

// Типографика панели у часов (WF253; слово Элвиса 17.10.2026 00:05: «6 часов 1 минута написано не влезает… переделай
// и покажи ещё раз с шрифтами»). Одна система ролей на все плитки — подписи одной роли одним
// стилем (правило 8 `INTERFACES.md`). С WF255 (слово Элвиса 17.10.2026 06:00 по листу 47: «Два.4, журнальный… его
// берём… ещё 2.3… возможность выбора сделай… Сделай варианты только посмелее») наборов семь: 2.4 и 2.3 с листа 47,
// пять смелых с листа 49; номер набора — номер на листе. Выбор — в «Настройках» («Шрифт панели»), помнится
// в UserDefaults (`PanelTypography.saved`). Кроме шрифтов здесь — строка блока без многоточия (`FitLine`): текст
// не обрезается и не вылезает ни при какой длине.

/// Стиль роли: шрифт, кегль, начертание, цвет, регистр, разрядка. Цифры всегда табличные — числа не прыгают.
struct PanelTextStyle: Equatable {
    /// Системный гротеск или антиква New York.
    enum Face: Equatable { case sans, serif }
    enum Letters: Equatable { case asIs, upper, smallCaps }

    var face = Face.sans
    var size: CGFloat
    var weight = Font.Weight.regular
    var color: Color
    var letters = Letters.asIs
    var tracking: CGFloat = 0
    var italic = false

    var font: Font {
        var font: Font = face == .serif ? .system(size: size, weight: weight, design: .serif)
            : .system(size: size, weight: weight)
        if italic { font = font.italic() }
        if letters == .smallCaps { font = font.smallCaps() }
        return font.monospacedDigit()
    }

    /// Текст роли; `color` — цвет вместо своего (прочерк без данных, сегодняшний день).
    func text(_ string: String, color: Color? = nil) -> Text {
        Text(verbatim: letters == .upper ? string.uppercased() : string)
            .font(font).foregroundColor(color ?? self.color).tracking(tracking)
    }

    /// Тот же стиль другим начертанием (сегодняшний день в полосе «Сброс»).
    func weight(_ weight: Font.Weight) -> PanelTextStyle {
        var copy = self
        copy.weight = weight
        return copy
    }
}

/// Роли текста панели и их стили. Геометрия плиток общая; меняются только шрифты.
struct PanelTypography: Equatable {
    /// Номер на листе («2.4» — лист 47, «49.2» — лист 49): им Элвис называет набор, он же хранится в UserDefaults.
    let number: String
    let name: String
    /// Одна строка: чем набор хорош — подсказка в «Настройках» и подпись на листе.
    let hint: String
    /// Шапка: «Claude … · PMP …» (#10308 — без тарифа, одной строкой).
    var header: PanelTextStyle
    /// Подпись — имя блока и карточки везде в панели: «Неделя», «Сброс», «5 часов», «Fable», «Температура»,
    /// «Оформление», «Скачалось обновление», «Цвет PMP», «Как остудить Мак». С WF267 (слово Элвиса 17.10.2026 11:21:
    /// «скачалось обновление, должно писаться капсом, вот как Неделя… таким же цветом… этим же шрифтом везде во всех
    /// темах») своего стиля у заголовка карточки нет: все подписи — этой ролью, в любом наборе.
    var label: PanelTextStyle
    /// Значение-герой — крупные проценты «5 часов» и «Fable»; `unit` — знак «%» при нём.
    var hero: PanelTextStyle
    var unit: PanelTextStyle
    /// Вторичное значение: «93 %», «6 часов 1 минута», «1,2 млрд».
    var value: PanelTextStyle
    /// Пояснение: «израсходовано», «сброс через 32 мин», дни недели, «7 дней», строки карточки обновления.
    var note: PanelTextStyle

    /// Показание — «48°» и «20.8 ГБ» у температуры и памяти (WF267, слово Элвиса 17.10.2026 11:21: «где температура
    /// и память… чтобы они побольше были»): лицо, начертание и наклон героя набора, кегль `readingSize`.
    var reading: PanelTextStyle {
        var style = hero
        style.size = Self.readingSize
        return style
    }

    var roles: [PanelTextStyle] { [header, label, hero, unit, value, note, reading] }
}

extension PanelTypography {
    /// Набор по умолчанию — 49.4 «Тонкий гигант» с 03.11.2026 (`docs/decisions/2026-11-03-oformlenie.md`); до того 2.4.
    static let chosen = "49.4"
    /// Выбор в «Настройках» (WF255).
    static let key = "panelTypography"

    static var standard: PanelTypography { all.first { $0.number == chosen } ?? all[0] }

    /// Порядок списка в «Настройках»: 2.4, 2.3, 49.2, 49.4 — все выбраны Элвисом (49.2 и 49.4 — слово 17.10.2026
    /// 11:21: «этот 492… берём… будет одним из вариантов… 49.4… возьми его тоже»), дальше остальные с листа 49.
    static let all: [PanelTypography] = [newYork, ultralight, italic, giant, cover, hairline, letterpress]

    /// Кегль показания (`reading`): «127.9 ГБ» любым набором входит в половинку плитки под подписью и во всю ширину
    /// строкой рядом с «Нагрузкой на память».
    static let readingSize: CGFloat = 22

    /// Выбранный набор; не выбирали или набора с таким номером больше нет — 2.4.
    static func saved(_ defaults: UserDefaults = .standard) -> PanelTypography {
        defaults.string(forKey: key).flatMap { number in all.first { $0.number == number } } ?? standard
    }

    static func save(_ type: PanelTypography, _ defaults: UserDefaults = .standard) {
        defaults.set(type.number, forKey: key)
    }

    private static let text = PanelColor.text
    private static let sub = PanelColor.sub
    /// Тёплый песок — подписи и «%» у «Курсива» (49.2): 8,3 : 1 к плитке, не спорит с жёлтым «мало осталось».
    static let warm = PanelColor.hex(0xE6B88A)
    private static let line = PanelTextStyle(size: 11, color: sub)

    /// 2.4 ★ «New York в цифрах» (лист 44, № 14): проценты антиквой, подписи капителью, остальное системным.
    static let newYork = PanelTypography(
        number: "2.4", name: "New York в цифрах", hint: "Проценты антиквой New York, подписи капителью — журнальный",
        header: line,
        label: PanelTextStyle(size: 12.5, weight: .medium, color: sub, letters: .smallCaps, tracking: 1),
        hero: PanelTextStyle(face: .serif, size: 34, color: text),
        unit: PanelTextStyle(face: .serif, size: 17, color: sub),
        value: PanelTextStyle(size: 13, color: text),
        note: line)

    /// 2.3 «Ультралёгкие» (лист 44, № 8): проценты 40 самым тонким начертанием, подписи мелким капсом с разрядкой.
    static let ultralight = PanelTypography(
        number: "2.3", name: "Ультралёгкие", hint: "Проценты самым тонким начертанием, подписи заглавными с разрядкой",
        header: line,
        label: PanelTextStyle(size: 11, weight: .medium, color: sub, letters: .upper, tracking: 0.9),
        hero: PanelTextStyle(size: 40, weight: .thin, color: text),
        unit: PanelTextStyle(size: 17, weight: .light, color: sub),
        value: PanelTextStyle(size: 13, color: text),
        note: line)

    /// 49.1 «Обложка» — 2.4 крупнее: проценты 54 полужирной антиквой, как номер журнала на обложке, «%» курсивом;
    /// значения — тоже антиквой.
    static let cover = PanelTypography(
        number: "49.1", name: "Обложка", hint: "Огромные проценты полужирной антиквой, «%» курсивом — как обложка журнала",
        header: line,
        label: PanelTextStyle(size: 12.5, weight: .medium, color: sub, letters: .smallCaps, tracking: 1.6),
        hero: PanelTextStyle(face: .serif, size: 54, weight: .semibold, color: text),
        unit: PanelTextStyle(face: .serif, size: 22, color: sub, italic: true),
        value: PanelTextStyle(face: .serif, size: 14, weight: .medium, color: text),
        note: line)

    /// 49.2 ★ листа 49 «Курсив» — проценты курсивом New York, подписи капителью тёплым песком с широкой разрядкой.
    static let italic = PanelTypography(
        number: "49.2", name: "Курсив", hint: "Проценты курсивом New York, подписи тёплой капителью вразрядку",
        header: line,
        label: PanelTextStyle(size: 12, weight: .semibold, color: warm, letters: .smallCaps, tracking: 2),
        hero: PanelTextStyle(face: .serif, size: 46, color: text, italic: true),
        unit: PanelTextStyle(face: .serif, size: 20, color: warm, italic: true),
        value: PanelTextStyle(face: .serif, size: 14, color: text),
        note: line)

    /// 49.3 «Антиква и нить» — 2.4 и 2.3 вместе: жирная антиква в процентах против волосяного гротеска во всём
    /// остальном — «%», значения и подписи тонкие.
    static let hairline = PanelTypography(
        number: "49.3", name: "Антиква и нить", hint: "Жирные проценты антиквой рядом с волосяным гротеском",
        header: line,
        label: PanelTextStyle(size: 11, weight: .light, color: text, letters: .upper, tracking: 2),
        hero: PanelTextStyle(face: .serif, size: 48, weight: .bold, color: text),
        unit: PanelTextStyle(size: 26, weight: .ultraLight, color: text),
        value: PanelTextStyle(size: 14, weight: .light, color: text),
        note: line)

    /// 49.4 «Тонкий гигант» — 2.3 смелее: проценты 58 ультратонким, подписи плотными заглавными вразрядку.
    static let giant = PanelTypography(
        number: "49.4", name: "Тонкий гигант", hint: "Сверхкрупные ультратонкие проценты, подписи плотными заглавными",
        header: line,
        label: PanelTextStyle(size: 11, weight: .semibold, color: sub, letters: .upper, tracking: 1.7),
        hero: PanelTextStyle(size: 58, weight: .ultraLight, color: text),
        unit: PanelTextStyle(size: 24, weight: .ultraLight, color: sub),
        value: PanelTextStyle(size: 14, weight: .light, color: text),
        note: line)

    /// 49.5 «Капитель» — подписи заглавными антиквы New York вразрядку (своей капители для кириллицы у New York нет —
    /// мелкие заглавные дают тот же вид), проценты и значения тоже антиквой; пояснения системные, как у соседей.
    static let letterpress = PanelTypography(
        number: "49.5", name: "Капитель", hint: "Подписи заглавными антиквы вразрядку, цифры антиквой — как книга",
        header: line,
        label: PanelTextStyle(face: .serif, size: 11, weight: .semibold, color: sub, letters: .upper, tracking: 1.4),
        hero: PanelTextStyle(face: .serif, size: 42, weight: .medium, color: text),
        unit: PanelTextStyle(face: .serif, size: 18, color: sub),
        value: PanelTextStyle(face: .serif, size: 14, color: text),
        note: line)
}

private struct PanelTypeKey: EnvironmentKey {
    static let defaultValue = PanelTypography.standard
}

private struct PanelStackedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Набор шрифтов панели: ставит `PanelRoot` из `PanelModel.typography`; без него — `PanelTypography.standard`.
    var panelType: PanelTypography {
        get { self[PanelTypeKey.self] }
        set { self[PanelTypeKey.self] = newValue }
    }

    /// Соседу по ряду строка не вошла — эта тоже ставит подпись над значением: значения и полосы двух плиток
    /// остаются на одной линии (ставит `WidgetBoard` по `PanelFitKey`).
    var panelStacked: Bool {
        get { self[PanelStackedKey.self] }
        set { self[PanelStackedKey.self] = newValue }
    }
}

/// Короткие записи для тесных плиток.
enum PanelShort {
    /// «6 ч 1 мин», «6 дн 23 ч», «12 мин» — тот же счёт, что «6 часов 1 минута» в полосе «Сброс» (`StatusIcon.weekStrip`):
    /// до ближайшей минуты, при днях минут нет.
    static func left(_ date: Date?, now: Date) -> String? {
        guard let date = date, date > now else { return nil }
        let total = max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
        let days = total / 1440, hours = (total % 1440) / 60, minutes = total % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)\u{00A0}дн") }
        if hours > 0 { parts.append("\(hours)\u{00A0}ч") }
        if days == 0 && minutes > 0 { parts.append("\(minutes)\u{00A0}мин") }
        return parts.isEmpty ? "<\u{00A0}1\u{00A0}мин" : parts.joined(separator: " ")
    }

    /// Цифра и буква срока для крупной строки «Сброса».
    struct HeroPart: Equatable {
        let number: String
        let unit: String
    }

    /// «5д 2ч», «5ч 12м», «<1м» — пары для ролей hero и unit; счёт как в `left`: при днях минут нет.
    static func heroParts(_ date: Date?, now: Date) -> [HeroPart] {
        guard let date = date, date > now else { return [] }
        let total = max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
        let days = total / 1440, hours = (total % 1440) / 60, minutes = total % 60
        var parts: [HeroPart] = []
        if days > 0 { parts.append(HeroPart(number: "\(days)", unit: "д")) }
        if hours > 0 { parts.append(HeroPart(number: "\(hours)", unit: "ч")) }
        if days == 0 && minutes > 0 { parts.append(HeroPart(number: "\(minutes)", unit: "м")) }
        return parts.isEmpty ? [HeroPart(number: "<1", unit: "м")] : parts
    }

    /// «сброс через 23 ч 59 мин» переносится только после «через» (или «сброс»): срок не рвётся посередине.
    static func keepTogether(_ text: String) -> String {
        guard let cut = text.range(of: "через ") ?? text.range(of: "сброс ") else { return text }
        return String(text[..<cut.upperBound]) + text[cut.upperBound...].replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

/// Какой вид строки блока выбран (`FitLine`): кадры и тесты видят его через `PanelFitKey`.
enum PanelFit: String, Equatable {
    /// Всё в строку; `bare` — в строку без линии графика; `short` — в строку с короткой записью значения.
    case row, bare, short
    /// Подпись над значением; `stackedShort` — то же с короткой записью.
    case stacked, stackedShort
    /// Ничего не вошло — ужато (последняя страховка, вместо многоточия).
    case squeezed

    /// Подпись над значением — соседи по ряду встают так же.
    var stacked: Bool { self == .stacked || self == .stackedShort || self == .squeezed }
}

struct PanelFitKey: PreferenceKey {
    static var defaultValue: [String: PanelFit] = [:]
    static func reduce(value: inout [String: PanelFit], nextValue: () -> [String: PanelFit]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Строка блока «подпись … значение ›» без многоточия: ViewThatFits берёт первый вид, что входит целиком, —
/// всё в строку; без линии графика; с короткой записью («6 ч 1 мин»); подпись над значением; то же коротко;
/// последней страховкой — ужатие. Короткая запись в строку идёт раньше подписи сверху: строка «Сброс» стоит
/// рядом со строкой «Неделя», и их полосы остаются на одной линии (правило №1 `INTERFACES.md`). Соседу по ряду
/// пришлось поставить подпись сверху (`panelStacked`) — эта строка встаёт так же, а свой вид «как вошло бы»
/// по-прежнему сообщает: ряд возвращается в строку, как только сосед снова входит.
struct FitLine<Extra: View>: View {
    /// Имя строки для `PanelFitKey`.
    let id: String
    let label: String
    let value: Text?
    let short: Text?
    let chevron: Bool
    let open: Bool
    let spacing: CGFloat
    let extra: () -> Extra
    @Environment(\.panelType) private var type
    @Environment(\.panelStacked) private var paired

    init(id: String, label: String, value: Text?, short: Text? = nil, chevron: Bool = false, open: Bool = false,
         spacing: CGFloat = 8, @ViewBuilder extra: @escaping () -> Extra) {
        self.id = id
        self.label = label
        self.value = value
        self.short = short
        self.chevron = chevron
        self.open = open
        self.spacing = spacing
        self.extra = extra
    }

    var body: some View {
        Group {
            if paired {
                ViewThatFits(in: .horizontal) {
                    stacked(value)
                    if let short = short { stacked(short) }
                    squeezed
                }
                .background(natural.hidden())
            } else {
                natural
            }
        }
        .frame(minHeight: 18)
    }

    /// Свой вид — первый, что входит целиком.
    private var natural: some View {
        ViewThatFits(in: .horizontal) {
            row(value, extra: true).fit(id, .row)
            if Extra.self != EmptyView.self { row(value, extra: false).fit(id, .bare) }
            if let short = short { row(short, extra: false).fit(id, .short) }
            stacked(value).fit(id, .stacked)
            if let short = short { stacked(short).fit(id, .stackedShort) }
            squeezed.fit(id, .squeezed)
        }
    }

    private var title: some View { type.label.text(label).fixedSize().widgetTitle() }

    private func row(_ value: Text?, extra shown: Bool) -> some View {
        // Зазор между подписью и значением — два промежутка строки (в половинке 5 + 5), распорка сверх них не берёт.
        HStack(spacing: spacing) {
            title
            Spacer(minLength: 0)
            // Линия строки (`sparkFill`) берёт свободное место первой — распорке остаётся ноль.
            if shown { extra().layoutPriority(1) }
            value?.fixedSize()
            mark
        }
    }

    private func stacked(_ value: Text?) -> some View {
        HStack(spacing: spacing) {
            VStack(alignment: .leading, spacing: 2) {
                title
                value?.fixedSize()
            }
            Spacer(minLength: 0)
            mark
        }
    }

    private var squeezed: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                type.label.text(label).lineLimit(1).minimumScaleFactor(0.5).widgetTitle()
                (short ?? value)?.lineLimit(1).minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
            mark
        }
    }

    @ViewBuilder private var mark: some View {
        if chevron {
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                .foregroundColor(PanelColor.sub)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
    }
}

extension FitLine where Extra == EmptyView {
    init(id: String, label: String, value: Text?, short: Text? = nil, chevron: Bool = false, open: Bool = false,
         spacing: CGFloat = 8) {
        self.init(id: id, label: label, value: value, short: short, chevron: chevron, open: open, spacing: spacing) {
            EmptyView()
        }
    }
}

private extension View {
    func fit(_ id: String, _ form: PanelFit) -> some View {
        preference(key: PanelFitKey.self, value: [id: form])
    }
}
