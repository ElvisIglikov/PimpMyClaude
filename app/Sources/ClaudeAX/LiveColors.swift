import Foundation

/// Режим живых цветов (решение 6 плана WF18): все окна одним цветом или каждое своим.
/// Значение уезжает в поле `mode` команды побайтно — «sync» / «solo».
enum LiveColorsMode: String, CaseIterable {
    /// Все окна считают один и тот же цвет: одинаковые `epoch` и `period`, фазы нет.
    case sync
    /// Каждое окно сдвинуто по кругу на свою фазу (`360 · индекс / число окон`).
    case solo
}

/// Нижняя секция подменю: тёмные, светлые или «как окно сейчас».
/// В команде это поле `light`: `false` / `true` / `null` (контракт п. 3 плана WF18).
enum LiveColorsTone: String, CaseIterable {
    case dark
    case light
    case window

    /// Значение поля `light`; nil — «как окно сейчас», страница смотрит тип своей темы.
    var lightValue: Bool? {
        switch self {
        case .dark: return false
        case .light: return true
        case .window: return nil
        }
    }
}

/// Что крутится сейчас: тумблер, режим, скорость, режим света и общая точка отсчёта круга.
/// Живёт в `UserDefaults` приложения (`LiveColorsStore`), а на странице — своей копией в
/// `localStorage` (`myclaude-live-v1`), поэтому окно, открытое во время крутёжа, подхватывает
/// цвет само, без команды.
struct LiveColorsState: Equatable {
    var on = false
    var mode = LiveColors.defaultMode
    /// Секунд на полный круг.
    var period = LiveColors.defaultPeriod
    var tone = LiveColors.defaultTone
    /// Точка отсчёта круга в миллисекундах (стенные часы): цвет считается от неё, а не
    /// накоплением тиков, поэтому придушенное фоновое окно после пробуждения оказывается
    /// на правильном цвете, а не отстаёт.
    var epoch = 0
}

/// «🌊 Живые цвета» (план WF18): окна Claude плавно едут по цветовому кругу.
///
/// Swift здесь считает только ДВЕ вещи — кольцо опорных палитр и арифметику скорости —
/// и шлёт ОДНУ команду `live-colors` на все окна (`scope: "all"`). Сам цвет крутит страница
/// по стенным часам: каналом командами это делать нельзя (зазор `CommandChannel.minInterval`
/// 0,6 с и опрос лоадера раз в 500 мс, п. 6 «что выяснено» плана).
///
/// Новой цветовой математики тут нет: палитры даёт проверенный тестами `AutoPaint.palette`
/// (потолок насыщенности фона, текст по контрасту 7, акцент в полосе 4,5–6 / 4,5–7).
enum LiveColors {
    /// Действие команды. `ClaudeCommand` для неё НЕ заводится: enum — это пункты верхнего
    /// уровня меню и слоты хоткеев, а `theme` и `status` тоже пишутся строкой (критик В1).
    static let action = "live-colors"

    /// Сколько опорных палитр в кольце: страница между соседними интерполирует в sRGB
    /// покомпонентно. 12 точек = шаг 30°; контраст в серединах хорд проверяет тест (критик В14) —
    /// не уложились бы, здесь стояло бы 24.
    static let ringCount = 12
    /// «Сила» палитры кольца — обычная, как у наборов автопокраски.
    static let strength = 0.5

    /// Шкала скорости, секунд на круг: 30 · 20 · 15 · 10 · 5 · 3 · 2 · 1 минуты (решение 5).
    /// Быстрее минуты не даём: при потолке 4 Гц это уже больше 1,5° за шаг — мигание,
    /// а не смена цвета (критик В4).
    static let periods = [1800, 1200, 900, 600, 300, 180, 120, 60]
    /// По умолчанию круг за 5 минут (вопрос 3 макета, ответ Элвиса — «по рекомендациям»).
    static let defaultPeriod = 300
    /// По умолчанию — «каждое окно своим цветом» (вопрос 1 макета) и тёмные (вопрос 2).
    static let defaultMode = LiveColorsMode.solo
    static let defaultTone = LiveColorsTone.dark

    // MARK: - шкала скорости

    /// Деление ползунка → секунды на круг; за края шкалы не выходим.
    static func period(at index: Int) -> Int {
        periods[min(max(index, 0), periods.count - 1)]
    }

    /// Секунды на круг → деление ползунка: файл настроек правят и руками, поэтому берём
    /// ближайшее деление, а не падаем на незнакомом числе.
    static func index(of period: Int) -> Int {
        var best = 0
        for (index, value) in periods.enumerated()
        where abs(value - period) < abs(periods[best] - period) { best = index }
        return best
    }

    /// Значение шкалы, ближайшее к заданному: в команду уходит только оно.
    static func period(clamping period: Int) -> Int { self.period(at: index(of: period)) }

    // MARK: - положение на круге

    /// Цвет считается от стенных часов, а не накоплением тиков (решение 1 плана):
    /// `hue = 360 · (now − epoch) / (period · 1000)`.
    static func hue(epoch: Int, period: Int, now: Int) -> Double {
        guard period > 0 else { return 0 }
        return AutoPaint.normalized(360 * Double(now - epoch) / (Double(period) * 1000))
    }

    /// Обратный ход: точка отсчёта, при которой в `now` окажется именно этот hue.
    static func epoch(hue: Double, period: Int, now: Int) -> Int {
        now - Int((AutoPaint.normalized(hue) / 360 * Double(period) * 1000).rounded())
    }

    /// Смена скорости не должна дёргать цвет (решение 3 плана): новый `epoch` подбирается так,
    /// чтобы текущий hue сохранился.
    static func state(_ state: LiveColorsState, period: Int, now: Int) -> LiveColorsState {
        var next = state
        next.period = self.period(clamping: period)
        next.epoch = epoch(hue: hue(epoch: state.epoch, period: state.period, now: now),
                           period: next.period, now: now)
        return next
    }

    /// «Как окно сейчас» осмысленно только в режиме «каждое своим» (критик М2): команда одна
    /// на всех, и в «синхронно» окна взяли бы разные кольца — цвет перестал бы быть одним.
    /// В меню пункт при этом погашен, а здесь закрыт и путь «руками в настройках».
    static func tone(_ tone: LiveColorsTone, mode: LiveColorsMode) -> LiveColorsTone {
        mode == .sync && tone == .window ? defaultTone : tone
    }

    /// Стенные часы в миллисекундах — в них живут `epoch` команды и `Date.now()` страницы.
    static func milliseconds(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1000).rounded()) }

    // MARK: - кольцо палитр (решение 2 плана)

    /// Опорные палитры по кругу: `count` штук, шаг `360 / count`.
    static func palettes(light: Bool, count: Int = ringCount) -> [[String: String]] {
        (0..<max(count, 1)).map { index in
            AutoPaint.palette(hue: 360 * Double(index) / Double(max(count, 1)),
                              light: light, strength: strength)
        }
    }

    /// Палитра как объект команды. Обход словаря напрямую в Swift непредсказуем, и побайтный
    /// контракт кольца плыл бы от запуска к запуску, — поэтому только `Theme.paletteValue`
    /// с его `Theme.paletteOrder` (критик В6).
    static func paletteValue(_ palette: [String: String]) -> CommandValue {
        Theme(id: "", name: "", type: "", palette: palette).paletteValue
    }

    /// Кольцо целиком: `{"dark":[…],"light":[…]}`. Оба всегда — чтобы работал режим
    /// «как окно сейчас», где окна берут разные половины.
    static func ring(count: Int = ringCount) -> CommandValue {
        .object([
            (key: "dark", value: .array(palettes(light: false, count: count).map(paletteValue))),
            (key: "light", value: .array(palettes(light: true, count: count).map(paletteValue))),
        ])
    }

    /// Смешение соседних палитр — ровно так же их смешивает страница (линейно по каналам sRGB).
    /// Здесь оно нужно тесту: контраст WF10 гарантирован в опорных точках, а глазами видна
    /// и середина хорды (критик В14).
    static func mix(_ first: String, _ second: String, _ t: Double) -> String {
        guard let a = AutoPaint.channels(hex: first), let b = AutoPaint.channels(hex: second) else {
            return first
        }
        func channel(_ from: Int, _ to: Int) -> Int {
            min(max(Int((Double(from) + (Double(to) - Double(from)) * t).rounded()), 0), 255)
        }
        return String(format: "#%02x%02x%02x", channel(a.r, b.r), channel(a.g, b.g),
                      channel(a.b, b.b))
    }

    // MARK: - команда (контракт п. 3 плана)

    /// Поля команды после id, action, at — в этом порядке: scope, on, mode, period, epoch,
    /// light, titles, ring. Выключение — только `scope` и `on:false`: страница возвращает
    /// окну прежнюю тему сама (`restoreTheme`), и «что было» запоминать не нужно.
    /// `titles` — AX-заголовки окон слева направо (порядок «Расставить»): по ним страница
    /// раздаёт начальные фазы, дальше фаза окна защёлкивается у него самого.
    static func fields(state: LiveColorsState,
                       titles: [String] = []) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(MenuModel.themeScopeAll)),
            (key: "on", value: .bool(state.on)),
        ]
        guard state.on else { return fields }
        let light = tone(state.tone, mode: state.mode).lightValue
        fields += [
            (key: "mode", value: .string(state.mode.rawValue)),
            (key: "period", value: .number(period(clamping: state.period))),
            (key: "epoch", value: .number(state.epoch)),
            (key: "light", value: light.map { CommandValue.bool($0) } ?? .null),
            (key: "titles", value: .array(titles.map { .string($0) })),
            (key: "ring", value: ring()),
        ]
        return fields
    }
}

/// Память живых цветов: `UserDefaults` приложения, ключи `liveColors.*` (решение 4 плана).
/// Приложение при старте пересылает состояние командой заново — но и без него страница
/// поднимает крутёж из своего `localStorage`.
final class LiveColorsStore {
    static let onKey = "liveColors.on"
    static let modeKey = "liveColors.mode"
    static let periodKey = "liveColors.period"
    static let toneKey = "liveColors.tone"
    static let epochKey = "liveColors.epoch"

    private let defaults: ThemeDefaults

    init(defaults: ThemeDefaults = UserDefaults.standard) { self.defaults = defaults }

    private func number(_ key: String) -> Int? {
        (defaults.object(forKey: key) as? NSNumber)?.intValue ?? defaults.object(forKey: key) as? Int
    }

    /// Записи нет или она мусорная — берём умолчания: живые цветы выключены, круг за 5 минут.
    var state: LiveColorsState {
        var state = LiveColorsState()
        state.on = (defaults.object(forKey: LiveColorsStore.onKey) as? Bool) ?? false
        if let raw = defaults.string(forKey: LiveColorsStore.modeKey),
           let mode = LiveColorsMode(rawValue: raw) { state.mode = mode }
        if let period = number(LiveColorsStore.periodKey) {
            state.period = LiveColors.period(clamping: period)
        }
        if let raw = defaults.string(forKey: LiveColorsStore.toneKey),
           let tone = LiveColorsTone(rawValue: raw) { state.tone = tone }
        state.epoch = number(LiveColorsStore.epochKey) ?? 0
        return state
    }

    func save(_ state: LiveColorsState) {
        defaults.set(state.on, forKey: LiveColorsStore.onKey)
        defaults.set(state.mode.rawValue, forKey: LiveColorsStore.modeKey)
        defaults.set(LiveColors.period(clamping: state.period), forKey: LiveColorsStore.periodKey)
        defaults.set(state.tone.rawValue, forKey: LiveColorsStore.toneKey)
        defaults.set(state.epoch, forKey: LiveColorsStore.epochKey)
    }
}
