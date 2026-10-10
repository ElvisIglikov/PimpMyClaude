import CoreFoundation
import Foundation

/// Притемнение окон Claude, кроме главного (WF113, #8256): команда страницам
/// `{"id","action":"dim","at","on":bool,"level":0.2..0.8[,"keep":["local_…"]]}` → `localStorage["myclaude-dim-v1"]`.
/// Вуаль рисует страница (не в фокусе, не у ждущего Элвиса чата; `keep` пуст — только у попапа, непуст — у
/// всех окон, кроме окон главного проекта); здесь — чистая часть.
public enum DimSetting {
    static let action = "dim"
    /// UserDefaults приложения: выключатель (нет ключа — выкл) и сила дробью 0.2…0.8 (нет — 0.5).
    public static let onKey = "dimOthers"
    public static let levelKey = "dimLevel"
    /// На каждом старте снимаем старую вуаль, после снимка умолчаний. Сила остаётся для CLI.
    public static func resetOnLaunch(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: onKey) }

    /// Сила в процентах: 20…80 шагом 5.
    public static let minPercent = 20
    public static let maxPercent = 80
    public static let defaultPercent = 50
    public static let step = 5

    /// Проценты в границы и на шаг ползунка.
    static func clamp(_ percent: Int) -> Int {
        let bounded = min(max(percent, minPercent), maxPercent)
        let stepped = Int((Double(bounded) / Double(step)).rounded()) * step
        return min(max(stepped, minPercent), maxPercent)
    }

    /// Дробь из UserDefaults (или канала) в проценты; не число — умолчание.
    static func percent(level: Double?) -> Int {
        guard let level = level, level.isFinite else { return defaultPercent }
        let bounded = min(max(level, Double(minPercent) / 100), Double(maxPercent) / 100)
        return clamp(Int((bounded * 100).rounded()))
    }

    /// Больше чатов в `keep` страница не примет (её проверка — массив строк `local_…`, ≤ 32).
    static let keepMax = 32

    /// Поля команды после id, action, at. `keep` — id чатов окон главного проекта (гейт WF111): пустой массив явно снимает прежние исключения.
    static func fields(on: Bool, percent: Int, keep: [String] = []) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "on", value: .bool(on)), (key: "level", value: .decimal(Double(clamp(percent)) / 100)),
        ]
        let chats = keep.filter { $0.hasPrefix("local_") }.prefix(keepMax)
        fields.append((key: "keep", value: .array(chats.map { .string($0) })))
        return fields
    }
}

/// Явный выбор отсчёта (WF119). Чтение страницы/умолчания не создаёт ключ приложения.
public struct SendDelaySetting: Equatable {
    public static let key = "sendDelayWF119"
    static let action = "send-delay"
    public let on: Bool
    public let seconds: Int

    /// По умолчанию — 3 с (слово Элвиса 07.10.2026: «Трёхсекундного отсчёта достаточно»).
    public init(on: Bool = true, seconds: Int = 3) {
        self.on = on
        self.seconds = Self.validSeconds(seconds) ? seconds : 3
    }

    static func validSeconds(_ value: Int) -> Bool { [3, 5, 10].contains(value) }

    static func parse(_ raw: Any?) -> SendDelaySetting? {
        guard let raw = raw as? [String: Any],
              let on = raw["on"] as? NSNumber, CFGetTypeID(on) == CFBooleanGetTypeID(),
              let seconds = raw["seconds"] as? NSNumber, CFGetTypeID(seconds) != CFBooleanGetTypeID(),
              [3.0, 5.0, 10.0].contains(seconds.doubleValue) else { return nil }
        return SendDelaySetting(on: on.boolValue, seconds: seconds.intValue)
    }

    var fields: [(key: String, value: CommandValue)] {
        [(key: "on", value: .bool(on)), (key: "seconds", value: .number(seconds))]
    }
}

/// Звук отсчёта (WF151, #9108; страница играет с WF147): живой `claude.json` ключом `countdownSound` — правда
/// (его правит и Элвис руками), запасная память — UserDefaults с тем же именем, когда файла нет. Страницам — поле
/// `sound` команды `send-delay` отдельно от `on/seconds`, как `second`/`shift`. Нет ключа или мусор — `bell`.
public enum CountdownSound: String, CaseIterable {
    case bell, tick, drop, retro, off
    public static let configKey = "countdownSound"
    public static let defaultsKey = "countdownSound"
    public static let fallback = CountdownSound.bell

    public var title: String {
        switch self {
        case .bell: return "🔔 Мягкий колокольчик"
        case .tick: return "🕰 Тик"
        case .drop: return "💧 Капля"
        case .retro: return "👾 Ретро-бип"
        case .off: return "🔇 Без звука"
        }
    }

    /// Имя без значка — строка «Звук» панели (WF180: «эмодзи меня бесят»).
    public var name: String {
        switch self {
        case .bell: return "Мягкий колокольчик"
        case .tick: return "Тик"
        case .drop: return "Капля"
        case .retro: return "Ретро-бип"
        case .off: return "Без звука"
        }
    }

    /// Любое значение ключа в звук: не строка или незнакомое — `bell`.
    public static func parse(_ raw: Any?) -> CountdownSound {
        (raw as? String).flatMap(CountdownSound.init(rawValue:)) ?? fallback
    }

    /// Ключ в теле `claude.json`: nil — ключа нет (или JSON не разобрался), иначе звук (мусор — `bell`).
    static func fromConfig(_ data: Data?) -> CountdownSound? {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root[configKey] else { return nil }
        return parse(raw)
    }

    /// Merge-запись одного ключа, как `LiveStyle.merged`: битый JSON — nil (файл не трогаем), пустой — `{}`.
    static func merged(config: String, sound: CountdownSound) -> String? {
        var root: [String: Any] = [:]
        if !config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any] else {
                return nil
            }
            root = parsed
        }
        root[configKey] = sound.rawValue
        guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text + "\n"
    }

    var fields: [(key: String, value: CommandValue)] { [(key: "sound", value: .string(rawValue))] }

    /// Подменю «🔊 Звук отсчёта ▸»: пять пунктов по порядку, галка только у текущего.
    public static let menuTitle = "🔊 Звук отсчёта"
    public static func menuItems(selected: CountdownSound) -> [(sound: CountdownSound, title: String, checked: Bool)] {
        allCases.map { (sound: $0, title: $0.title, checked: $0 == selected) }
    }
}

/// Клавиши отсчёта (WF126 §7.2, поправки критика 1–2): второй Enter и ⇧Enter во время счёта — полями
/// `second`/`shift` той же команды `send-delay` (страница — `myclaude-send-delay-second`/`-shift`). Ключи
/// приложения создаёт только выбор; нет ключа — команда без поля, страница ведёт себя как сейчас.
public struct EnterKeys: Equatable {
    public enum Second: String, CaseIterable { case cancel, send, nothing = "none" }
    public enum Shift: String, CaseIterable { case send, newline }
    public static let secondKey = "sendDelaySecond"
    public static let shiftKey = "sendDelayShift"
    public var second: Second
    public var shift: Shift

    public init(second: Second = .cancel, shift: Shift = .newline) {
        self.second = second
        self.shift = shift
    }

    /// Подпись отсчёта — как `sendDelayLabel` страницы.
    public func label(left: Int) -> String {
        let shiftTail = shift == .send ? " · ⇧Enter — сразу" : ""
        switch second {
        case .cancel: return "Отправка через \(left) · Enter или Esc — отмена\(shiftTail)"
        case .send: return "Отправка через \(left) · Enter — сразу · Esc — отмена"
        case .nothing: return "Отправка через \(left)\(shiftTail) · Esc — отмена"
        }
    }

    static func fields(second: Second?, shift: Shift?) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = []
        if let second = second { fields.append((key: "second", value: .string(second.rawValue))) }
        if let shift = shift { fields.append((key: "shift", value: .string(shift.rawValue))) }
        return fields
    }
}

/// Bypass permissions во всех чатах (WF126 §7.3 путь А + WF161 путь Б, #9060): черновик, который открывает PMP,
/// получает `mode:"bypass"` в `draft-setup`; всем страницам — `{"id","action":"bypass-chats","at","on":"true"|"false"}`
/// строкой, без адреса окна (как `hide-tools`), страница ставит Bypass в каждом своём чате (раздел 12с¹).
/// Разрешён ли режим в Claude — только читаем его `claude_desktop_config.json`.
public enum BypassNew {
    public static let key = "bypassNewChats"
    public static let draftMode = "bypass"
    static let action = "bypass-chats"
    public static let menuTitle = "Bypass permissions во всех чатах"

    static func fields(on: Bool) -> [(key: String, value: CommandValue)] {
        [(key: "on", value: .string(on ? "true" : "false"))]
    }

    public enum Permission: Equatable {
        case allowed
        case notAllowed
        /// Организация выключила (`bypassPermissionsGateByAccount` — хоть одно false).
        case blockedByOrg
        /// Файла нет или не читается.
        case unknown
    }

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    /// Разбор файла (поправка критика 6): запрет организации сильнее согласия.
    public static func permission(config data: Data?) -> Permission {
        guard let data = data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }
        let preferences = root["preferences"] as? [String: Any] ?? [:]
        func values(_ key: String) -> [Bool] {
            (preferences[key] as? [String: Any] ?? [:]).values.compactMap { ($0 as? NSNumber)?.boolValue }
        }
        if values("bypassPermissionsGateByAccount").contains(false) { return .blockedByOrg }
        return values("bypassPermissionsOptInByAccount").contains(true) ? .allowed : .notAllowed
    }

    public static func permission(at url: URL = configURL) -> Permission {
        permission(config: try? Data(contentsOf: url))
    }
}

/// «Чистые ответы» (WF210, #9398, К-CA; слово Элвиса 10.10.2026: «строку расхода прятать, вот эти служебные строки…
/// текст работы-то я оставлю»): `{"id","action":"clean-answers","at","on":"true"|"false"}` строкой, без адреса окна
/// (как `hide-tools`). Страница без команды прячет (умолчание — включено); приложение помнит выбор в
/// `UserDefaults["cleanAnswersWF210"]` и повторяет его каждому новому поколению страниц; нет ключа — нет команды.
public enum CleanAnswers {
    public static let key = "cleanAnswersWF210"
    static let action = "clean-answers"
    /// Показанный выбор, пока ключа нет: умолчание страницы — прятать.
    public static let defaultOn = true
    public static let title = "Чистые ответы"
    public static let caption = "Прячет под ответами строки расхода и состояния."

    static func fields(on: Bool) -> [(key: String, value: CommandValue)] {
        [(key: "on", value: .string(on ? "true" : "false"))]
    }
}

/// Блок «Текст» панели PMP (WF167, #9168): выравнивание ответов и поля по бокам.
/// Выравнивание — `{"id","action":"text-justify","at","on":"true"|"false"}` строкой, без адреса окна (как `hide-tools`);
/// страница (WF165) хранит выбор в `localStorage["myclaude.textJustify"]`, нет ключа — по ширине. Приложение помнит
/// выбор в `UserDefaults["textJustifyWF167"]` и повторяет его каждому новому поколению страниц; нет ключа — нет команды.
/// Поля — тот же `claude.json.sidePadding`, что ползунок «↔️ Поля» на «−» (`LiveStyle.apply`).
public enum TextLook {
    public static let justifyKey = "textJustifyWF167"
    static let justifyAction = "text-justify"
    /// Показанный выбор, пока ключа нет: умолчание страницы — по ширине.
    public static let justifyDefault = true
    public static let paddingRange = LiveStyle.minSidePadding...LiveStyle.maxSidePadding
    /// Отметки под ползунком: 24 — умолчание, 32 и 40 — 33.2/33.3 (слово Элвиса 09.10.2026).
    public static let paddingMarks = [24, 32, 40]

    static func fields(justify on: Bool) -> [(key: String, value: CommandValue)] {
        [(key: "on", value: .string(on ? "true" : "false"))]
    }

    /// Ползунок «Поля» панели: зажим 0…40, блок в claude.css и `sidePadding` в claude.json; возвращает записанное.
    @discardableResult
    public static func setSidePadding(_ value: Int) -> Int {
        setSidePadding(value, directory: LiveStyle.defaultDirectory, defaults: .standard)
    }

    @discardableResult
    static func setSidePadding(_ value: Int, directory: URL, defaults: UserDefaults) -> Int {
        let padding = LiveStyle.clamp(value)
        LiveStyle.apply(sidePadding: padding, directory: directory, defaults: defaults)
        return padding
    }

    /// Нынешние поля: claude.json, иначе память приложения, иначе 24.
    public static var sidePadding: Int { LiveStyle.currentSidePadding() }
}

/// «Закреплённые» (#8743): показывать ли у закреплённых чатов название проекта и таймер. Команда
/// `{"id","action":"pinned-look","at","folder","clock"}` всем окнам → localStorage страницы (раздел 2е).
/// Нет ключа приложения — показывать, как было до настройки.
public struct PinnedLook: Equatable {
    public static let folderKey = "pinnedFolderShown"
    public static let clockKey = "pinnedClockShown"
    static let action = "pinned-look"
    public var folder: Bool
    public var clock: Bool

    public init(folder: Bool = true, clock: Bool = true) {
        self.folder = folder
        self.clock = clock
    }

    var fields: [(key: String, value: CommandValue)] {
        [(key: "folder", value: .bool(folder)), (key: "clock", value: .bool(clock))]
    }
}

/// Вид и размер отсчёта отправки (WF114, #8226; К1 v3 WF128, #9041): команда `{"id","action":"send-look","at","style","size",
/// "preview"[,"seconds","match"|"chat"]}` → `localStorage["myclaude-send-look-v2"]` (страница, раздел 12у). `preview: true` —
/// адресованное окно (`match`/`chat`, без них — главное) проигрывает отсчёт, ничего не отправляя.
public enum SendLook {
    static let action = "send-look"
    /// UserDefaults приложения: вид строкой (нет — «1.8» «Ракета», до WF180 звался «Взлёт») и размер в процентах (нет — 100). Старый ключ
    /// `sendLookStyle` (там у всех «1.5» с WF119) не читается.
    public static let styleKey = "sendLookStyleWF128"
    public static let sizeKey = "sendLookSize"
    /// Восемь видов К1 v3 в порядке меню; «1.3» и «1.7» не принимаются (летящие цифры, 08.10).
    public static let styles: [(id: String, name: String)] = [
        ("1.8", "Ракета"), ("1.9", "Пульс"), ("1.10", "Мерцание"), ("1.1", "Штрих по кругу"),
        ("1.2", "Удар"), ("1.4", "Кольцо"), ("1.6", "Шнур"), ("1.5", "Спокойная цифра"),
    ]
    public static let defaultStyle = "1.8"
    public static let menuTitle = "🚀 Вид отсчёта"
    public static let minSize = 60
    public static let maxSize = 200
    public static let defaultSize = 100
    public static let step = 10

    public static func isStyle(_ style: String) -> Bool { styles.contains { $0.id == style } }

    public static func name(_ style: String) -> String {
        styles.first { $0.id == style }?.name ?? ""
    }

    /// Подменю «🚀 Вид отсчёта ▸»: восемь видов по порядку, галка только у выбранного (ключа нет — у «1.8»).
    public static func menuItems(selected: String) -> [(style: String, title: String, checked: Bool)] {
        let current = isStyle(selected) ? selected : defaultStyle
        return styles.map { (style: $0.id, title: $0.name, checked: $0.id == current) }
    }

    /// Размер в границы и на шаг ползунка.
    static func clamp(_ size: Int) -> Int {
        let bounded = min(max(size, minSize), maxSize)
        let stepped = Int((Double(bounded) / Double(step)).rounded()) * step
        return min(max(stepped, minSize), maxSize)
    }

    /// Вид/размер всегда вместе; секунды и один адрес — только для показа.
    static func fields(style: String, size: Int, preview: Bool,
                       match: String?, seconds: Int? = nil, chat: String? = nil) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "style", value: .string(isStyle(style) ? style : defaultStyle)),
            (key: "size", value: .number(clamp(size))), (key: "preview", value: .bool(preview)),
        ]
        if preview {
            if let seconds = seconds { fields.append((key: "seconds", value: .number(seconds))) }
            if let match = match, !match.isEmpty { fields.append((key: "match", value: .string(match))) }
            else if let chat = chat, !chat.isEmpty { fields.append((key: "chat", value: .string(chat))) }
        }
        return fields
    }
}

/// Выбор CLI «Пимп»: притемнение, вид и размер отсчёта.
public struct PageLook: Equatable {
    public var dimOn: Bool
    /// Сила притемнения, проценты 20…80.
    public var dimPercent: Int
    public var style: String
    /// Размер цифры, проценты 60…200.
    public var size: Int

    public init(dimOn: Bool = false, dimPercent: Int = DimSetting.defaultPercent,
                style: String = SendLook.defaultStyle, size: Int = SendLook.defaultSize) {
        self.dimOn = dimOn
        self.dimPercent = dimPercent
        self.style = style
        self.size = size
    }
}

/// Память и рассылка `dim` и `send-look` (WF113/WF114): UserDefaults приложения — правда, страницам —
/// команда сразу при смене и повтор в каждом поколении страниц (правило `trust-root`: первый тик с окнами,
/// смена состава окон, до 3 раз). Отсчёт повторяется только после явного выбора приложения.
/// Живёт на главной очереди.
final class PageLookSettings {
    private let defaults: UserDefaults
    /// Запись команды в `command.json`; живьём — `CommandChannel.write`.
    var write: (_ action: String, _ fields: [(key: String, value: CommandValue)],
                _ priority: CommandChannel.Priority) -> Bool = { _, _, _ in false }
    /// `match` страницы главного окна для показа CLI; nil — страница решит сама (`isMainWindow`).
    var mainMatch: () -> String? = { nil }
    /// Claude запущен — показать отсчёт есть где.
    var isRunning: () -> Bool = { false }
    private let dimSwitch = AutoAllowSwitch()
    private let lookSwitch = AutoAllowSwitch()
    private let delaySwitch = AutoAllowSwitch()
    private let pinnedSwitch = AutoAllowSwitch()
    private let keysSwitch = AutoAllowSwitch()
    private let soundSwitch = AutoAllowSwitch()
    private let bypassSwitch = AutoAllowSwitch()
    private let justifySwitch = AutoAllowSwitch()
    private let cleanSwitch = AutoAllowSwitch()
    /// Живой `claude.json` (WF151, звук отсчёта); nil — файла нет (тесты без своего файла живой не читают).
    let configURL: URL?
    /// id чатов окон главного проекта (`keep` команды `dim`); в UserDefaults не пишется — это не выбор.
    private(set) var keep: [String] = []

    /// Набор окон главного проекта сменился — `dim` уходит страницам заново новым поколением (на ближайшем
    /// тике с окнами). Тот же набор — ничего.
    func setKeep(_ chats: [String]) {
        guard chats != keep else { return }
        keep = chats
        dimSwitch.beginGeneration()
    }

    init(defaults: UserDefaults = .standard, configURL: URL? = nil) {
        self.defaults = defaults
        self.configURL = configURL
    }

    /// Выбор из UserDefaults; негодное — умолчание.
    var current: PageLook {
        let size = defaults.object(forKey: SendLook.sizeKey) as? Int ?? SendLook.defaultSize
        let style = defaults.string(forKey: SendLook.styleKey).flatMap { SendLook.isStyle($0) ? $0 : nil }
        return PageLook(dimOn: defaults.bool(forKey: DimSetting.onKey),
                        dimPercent: DimSetting.percent(level: defaults.object(forKey: DimSetting.levelKey) as? Double),
                        style: style ?? SendLook.defaultStyle,
                        size: SendLook.clamp(size))
    }

    /// Притемнение из CLI: nil — поле не меняется.
    @discardableResult
    func setDim(on: Bool? = nil, percent: Int? = nil) -> PageLook {
        var look = current
        if let on = on { look.dimOn = on }
        if let percent = percent { look.dimPercent = DimSetting.clamp(percent) }
        let fields = DimSetting.fields(on: look.dimOn, percent: look.dimPercent, keep: keep)
        defaults.set(look.dimOn, forKey: DimSetting.onKey)
        defaults.set(Double(look.dimPercent) / 100, forKey: DimSetting.levelKey)
        _ = write(DimSetting.action, fields, .normal)
        dimSwitch.beginGeneration()
        return look
    }

    /// Вид отсчёта: nil — поле не меняется; `grow` — прибавить к нынешнему размеру (канал: «побольше»).
    /// `show` — проиграть вид в главном окне. `shown` — показ ушёл (Claude запущен, команда принята).
    @discardableResult
    func setLook(style: String? = nil, size: Int? = nil, grow: Int? = nil, show: Bool = false) -> (look: PageLook, shown: Bool) {
        var look = current
        if let style = style, SendLook.isStyle(style) { look.style = style }
        if let size = size { look.size = SendLook.clamp(size) }
        if let grow = grow {
            let bounded = min(max(grow, -SendLook.maxSize), SendLook.maxSize)
            look.size = SendLook.clamp(look.size + bounded)
        }
        let running = isRunning()
        let preview = show && running
        let fields = SendLook.fields(style: look.style, size: look.size, preview: preview,
                                     match: preview ? mainMatch() : nil)
        defaults.set(look.style, forKey: SendLook.styleKey)
        defaults.set(look.size, forKey: SendLook.sizeKey)
        let sent = write(SendLook.action, fields, .normal)
        lookSwitch.beginGeneration()
        return (look, sent && preview)
    }

    var savedSendDelay: SendDelaySetting? { SendDelaySetting.parse(defaults.object(forKey: SendDelaySetting.key)) }

    func sendDelaySetting(pages: [ChatPage]) -> SendDelaySetting {
        savedSendDelay ?? pages.first(where: { $0.kind != .other && $0.sendDelaySetting != nil })?.sendDelaySetting
            ?? SendDelaySetting()
    }

    func setSendDelay(on: Bool, seconds: Int) {
        guard SendDelaySetting.validSeconds(seconds) else { return }
        let setting = SendDelaySetting(on: on, seconds: seconds)
        defaults.set(["on": on, "seconds": seconds], forKey: SendDelaySetting.key)
        _ = write(SendDelaySetting.action, setting.fields, .normal)
        delaySwitch.beginGeneration()
    }

    /// Клавиши отсчёта: выбор приложения; ключа нет — умолчание страницы (отмена, отправить).
    var enterKeys: EnterKeys {
        EnterKeys(second: savedSecond ?? .cancel, shift: savedShift ?? .newline)
    }

    private var savedSecond: EnterKeys.Second? { defaults.string(forKey: EnterKeys.secondKey).flatMap(EnterKeys.Second.init) }
    private var savedShift: EnterKeys.Shift? { defaults.string(forKey: EnterKeys.shiftKey).flatMap(EnterKeys.Shift.init) }

    /// nil — поле не меняется.
    func setEnterKeys(second: EnterKeys.Second? = nil, shift: EnterKeys.Shift? = nil) {
        guard second != nil || shift != nil else { return }
        if let second = second { defaults.set(second.rawValue, forKey: EnterKeys.secondKey) }
        if let shift = shift { defaults.set(shift.rawValue, forKey: EnterKeys.shiftKey) }
        _ = write(SendDelaySetting.action, EnterKeys.fields(second: second, shift: shift), .normal)
        keysSwitch.beginGeneration()
    }

    /// Звук отсчёта, если его выбирали: ключ `countdownSound` в `claude.json`, иначе память приложения; nil — не
    /// выбирали (рассылки нет, страница звучит своим `bell`).
    var chosenCountdownSound: CountdownSound? {
        if let sound = CountdownSound.fromConfig(configURL.flatMap { try? Data(contentsOf: $0) }) { return sound }
        guard let raw = defaults.object(forKey: CountdownSound.defaultsKey) else { return nil }
        return CountdownSound.parse(raw)
    }

    /// Показанный выбор: нет ключа или мусор — `bell`.
    var countdownSound: CountdownSound { chosenCountdownSound ?? .fallback }

    /// Выбор в панели: ключ в живой `claude.json` (merge, битый файл не трогаем), память приложения и команда
    /// `send-delay` только с полем `sound`; новое поколение — повтор страницам, что откроются позже.
    func setCountdownSound(_ sound: CountdownSound) {
        defaults.set(sound.rawValue, forKey: CountdownSound.defaultsKey)
        if let url = configURL, let old = try? String(contentsOf: url, encoding: .utf8) {
            if let new = CountdownSound.merged(config: old, sound: sound) {
                if new != old { _ = CommandChannel.writeAtomic(url, new) }
            } else {
                NSLog("PimpMyClaude: %@ не разобрался — countdownSound не записан", url.path)
            }
        }
        _ = write(SendDelaySetting.action, sound.fields, .normal)
        soundSwitch.beginGeneration()
    }

    /// «Закреплённые» (#8743): выбор приложения; ключа нет — показывать.
    var pinned: PinnedLook {
        PinnedLook(folder: defaults.object(forKey: PinnedLook.folderKey) as? Bool ?? true,
                   clock: defaults.object(forKey: PinnedLook.clockKey) as? Bool ?? true)
    }

    private var pinnedChosen: Bool {
        defaults.object(forKey: PinnedLook.folderKey) != nil || defaults.object(forKey: PinnedLook.clockKey) != nil
    }

    func setPinned(_ look: PinnedLook) {
        defaults.set(look.folder, forKey: PinnedLook.folderKey)
        defaults.set(look.clock, forKey: PinnedLook.clockKey)
        _ = write(PinnedLook.action, look.fields, .normal)
        pinnedSwitch.beginGeneration()
    }

    /// «Bypass permissions во всех чатах» (#9060 путь Б): ключа нет — выкл и страницам ничего не шлём.
    var bypassChats: Bool { defaults.bool(forKey: BypassNew.key) }

    /// Выбор пишется сразу, команда `bypass-chats` уходит всем страницам; новое поколение — повтор.
    func setBypassChats(_ on: Bool) {
        defaults.set(on, forKey: BypassNew.key)
        _ = write(BypassNew.action, BypassNew.fields(on: on), .normal)
        bypassSwitch.beginGeneration()
        justifySwitch.beginGeneration()
    }

    /// Выравнивание текста (WF167): ключа нет — показываем умолчание страницы, страницам ничего не шлём.
    var textJustify: Bool { defaults.object(forKey: TextLook.justifyKey) as? Bool ?? TextLook.justifyDefault }

    /// Выбор пишется сразу, команда `text-justify` уходит всем страницам; новое поколение — повтор.
    func setTextJustify(_ on: Bool) {
        defaults.set(on, forKey: TextLook.justifyKey)
        _ = write(TextLook.justifyAction, TextLook.fields(justify: on), .normal)
        justifySwitch.beginGeneration()
    }

    /// «Чистые ответы» (WF210, К-CA): ключа нет — показываем умолчание страницы (включено), страницам ничего не шлём.
    var cleanAnswers: Bool { defaults.object(forKey: CleanAnswers.key) as? Bool ?? CleanAnswers.defaultOn }

    /// Выбор пишется сразу, команда `clean-answers` уходит всем страницам; новое поколение — повтор.
    func setCleanAnswers(_ on: Bool) {
        defaults.set(on, forKey: CleanAnswers.key)
        _ = write(CleanAnswers.action, CleanAnswers.fields(on: on), .normal)
        cleanSwitch.beginGeneration()
    }

    /// Показ панели не меняет выбор отсчёта и вида, только рисует его у выбранного окна.
    @discardableResult
    func previewSendDelay(seconds: Int, match: String?, chat: String?) -> Bool {
        guard SendDelaySetting.validSeconds(seconds),
              (match?.isEmpty == false) != (chat?.isEmpty == false), match != "blank" else { return false }
        return write(SendLook.action, SendLook.fields(style: current.style, size: current.size, preview: true,
                     match: match, seconds: seconds, chat: chat), .normal)
    }

    /// Показ без адреса (WF180): окно не опознано — играет главное окно (страница, раздел 12у: без match/chat — главное).
    @discardableResult
    func previewSendDelayMain(seconds: Int) -> Bool {
        guard SendDelaySetting.validSeconds(seconds) else { return false }
        return write(SendLook.action, SendLook.fields(style: current.style, size: current.size, preview: true,
                     match: nil, seconds: seconds, chat: nil), .normal)
    }

    /// Новое поколение страниц: старт приложения или смена pid Claude.
    func beginGeneration() {
        dimSwitch.beginGeneration()
        lookSwitch.beginGeneration()
        delaySwitch.beginGeneration()
        pinnedSwitch.beginGeneration()
        keysSwitch.beginGeneration()
        soundSwitch.beginGeneration()
        bypassSwitch.beginGeneration()
        justifySwitch.beginGeneration()
        cleanSwitch.beginGeneration()
    }

    /// Тик 2 с: повтор выбора страницам этого поколения.
    func tick(titles: [String], at: Date) {
        let look = current
        if pinnedChosen {
            let pinned = self.pinned
            pinnedSwitch.tick(titles: titles, at: at) { _ in write(PinnedLook.action, pinned.fields, .normal) }
        }
        if savedSecond != nil || savedShift != nil {
            let fields = EnterKeys.fields(second: savedSecond, shift: savedShift)
            keysSwitch.tick(titles: titles, at: at) { _ in write(SendDelaySetting.action, fields, .normal) }
        }
        if let sound = chosenCountdownSound {
            soundSwitch.tick(titles: titles, at: at) { _ in write(SendDelaySetting.action, sound.fields, .normal) }
        }
        if defaults.object(forKey: BypassNew.key) != nil {
            let fields = BypassNew.fields(on: bypassChats)
            bypassSwitch.tick(titles: titles, at: at) { _ in write(BypassNew.action, fields, .normal) }
        }
        if defaults.object(forKey: TextLook.justifyKey) is Bool {
            let fields = TextLook.fields(justify: textJustify)
            justifySwitch.tick(titles: titles, at: at) { _ in write(TextLook.justifyAction, fields, .normal) }
        }
        if defaults.object(forKey: CleanAnswers.key) is Bool {
            let fields = CleanAnswers.fields(on: cleanAnswers)
            cleanSwitch.tick(titles: titles, at: at) { _ in write(CleanAnswers.action, fields, .normal) }
        }
        if let setting = savedSendDelay {
            delaySwitch.tick(titles: titles, at: at) { _ in write(SendDelaySetting.action, setting.fields, .normal) }
        }
        dimSwitch.tick(titles: titles, at: at) { _ in
            write(DimSetting.action, DimSetting.fields(on: look.dimOn, percent: look.dimPercent, keep: keep), .normal)
        }
        lookSwitch.tick(titles: titles, at: at) { _ in
            write(SendLook.action, SendLook.fields(style: look.style, size: look.size, preview: false, match: nil),
                  .normal)
        }
    }
}
