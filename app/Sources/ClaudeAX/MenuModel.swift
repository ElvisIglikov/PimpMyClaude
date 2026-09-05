import AppKit

/// Модификаторы горячей клавиши. Значения — маски Carbon `RegisterEventHotKey`
/// (cmdKey 0x0100, shiftKey 0x0200, optionKey 0x0800, controlKey 0x1000).
struct KeyMods: OptionSet {
    let rawValue: UInt32
    static let command = KeyMods(rawValue: 1 << 0)
    static let shift = KeyMods(rawValue: 1 << 1)
    static let control = KeyMods(rawValue: 1 << 2)
    static let option = KeyMods(rawValue: 1 << 3)

    var carbon: UInt32 {
        var mask: UInt32 = 0
        if contains(.command) { mask |= 0x0100 }
        if contains(.shift) { mask |= 0x0200 }
        if contains(.option) { mask |= 0x0800 }
        if contains(.control) { mask |= 0x1000 }
        return mask
    }

    /// Подсказка как в README: ⌘ первым (⌘⇧N, ⌘⌥↓), а не в системном порядке ⌃⌥⇧⌘.
    var hint: String {
        var s = ""
        if contains(.command) { s += "⌘" }
        if contains(.shift) { s += "⇧" }
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        return s
    }

    /// Те же модификаторы для NSMenuItem: подсказку справа серым AppKit рисует сам
    /// (решение 4 плана WF9) — в системном порядке и своим шрифтом.
    var appKit: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if contains(.command) { mask.insert(.command) }
        if contains(.shift) { mask.insert(.shift) }
        if contains(.control) { mask.insert(.control) }
        if contains(.option) { mask.insert(.option) }
        return mask
    }
}

/// Клавиша: имя как в `M.hotkeys` Lua-модуля («n», «down»), код — виртуальный код Carbon.
struct KeySpec {
    let mods: KeyMods
    let name: String

    /// kVK_ANSI_A 0x00, S 0x01, D 0x02, Q 0x0C, N 0x2D, Down 0x7D, Up 0x7E.
    /// `equivalent` — тот же символ для `NSMenuItem.keyEquivalent`: у стрелок это
    /// `NSDownArrowFunctionKey`/`NSUpArrowFunctionKey` из приватной зоны Юникода.
    private static let codes: [String: (code: UInt32, glyph: String, equivalent: String)] = [
        "a": (0x00, "A", "a"),
        "s": (0x01, "S", "s"),
        "d": (0x02, "D", "d"),
        "q": (0x0C, "Q", "q"),
        "n": (0x2D, "N", "n"),
        "down": (0x7D, "↓", String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!)),
        "up": (0x7E, "↑", String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)),
    ]

    var keyCode: UInt32? { KeySpec.codes[name]?.code }
    var glyph: String { KeySpec.codes[name]?.glyph ?? name.uppercased() }
    var hint: String { mods.hint + glyph }
    /// Пара для NSMenuItem: клавиша и её модификаторы (решение 4 плана WF9).
    var keyEquivalent: String { KeySpec.codes[name]?.equivalent ?? name.lowercased() }
    var modifierMask: NSEvent.ModifierFlags { mods.appKit }
}

/// Пункт меню на кнопке «Свернуть» — порядок, иконки и клавиши строго как в README.
struct MenuEntry {
    let command: ClaudeCommand
    let title: String
    let icon: String
    /// nil — у пункта клавиши нет вовсе («Workflow»: ⌘⌥W занят самим Claude).
    let key: KeySpec?
    /// ⌘N — штатная клавиша самого Claude: показываем подсказку, но не регистрируем.
    let registersHotkey: Bool

    /// Заголовок пункта — голое название: клавишу справа серым рисует AppKit по
    /// `keyEquivalent`, хвоста «   ⌘⇧N» в заголовке больше нет (решение 4 плана WF9).
    var menuTitle: String { title }
}

enum MenuModel {
    /// Порядок — экранный, вариант А плана WF14: «Развернуть выше, свернуть ниже», а четвёрка
    /// редких команд (`moreCommands`) стоит в конце и рисуется внутри «⋯ Ещё ▸».
    /// Список остаётся ПОЛНЫМ из десяти пунктов: по нему же `ClaudeAXController.refreshHotkeys`
    /// регистрирует Carbon-хоткеи (id = индекс+1), и вынести пункт отсюда = убить его клавишу.
    static let entries: [MenuEntry] = [
        // «Workflow» — первым и без клавиши: ⌘⌥W у Claude свой.
        MenuEntry(command: .workflow, title: "Workflow", icon: "🚀", key: nil, registersHotkey: false),
        MenuEntry(command: .newChat, title: "Новый чат", icon: "💬",
                  key: KeySpec(mods: [.command], name: "n"), registersHotkey: false),
        // «Новое окно» — новый чат сразу отдельным окном (план WF13). ⌥⌘N у Claude свободна,
        // поэтому её мы регистрируем сами; «В отдельное окно» — без клавиши.
        MenuEntry(command: .newWindow, title: "Новое окно", icon: "🪟",
                  key: KeySpec(mods: [.command, .option], name: "n"), registersHotkey: true),
        MenuEntry(command: .popoutWindow, title: "В отдельное окно", icon: "🪟",
                  key: nil, registersHotkey: false),
        MenuEntry(command: .expand, title: "Развернуть", icon: "⬆️",
                  key: KeySpec(mods: [.command, .option], name: "up"), registersHotkey: true),
        MenuEntry(command: .collapse, title: "Свернуть", icon: "⬇️",
                  key: KeySpec(mods: [.command, .option], name: "down"), registersHotkey: true),
        MenuEntry(command: .cashout, title: "Обкэшить", icon: "💰",
                  key: KeySpec(mods: [.command, .shift], name: "n"), registersHotkey: true),
        MenuEntry(command: .arrange, title: "Расставить", icon: "▦",
                  key: KeySpec(mods: [.command, .option], name: "a"), registersHotkey: true),
        MenuEntry(command: .show, title: "Показать", icon: "👀",
                  key: KeySpec(mods: [.command, .option], name: "s"), registersHotkey: true),
        MenuEntry(command: .scroll, title: "Прокрутить", icon: "⏬",
                  key: KeySpec(mods: [.command, .option], name: "d"), registersHotkey: true),
    ]

    /// Редкое — внутри «⋯ Ещё ▸» (решение Элвиса 04.09: «Расставить, показать, прокрутить —
    /// давай все скроем», «Обкэшить… давай спрячем»). Прячем только с глаз: пункты остаются
    /// в `entries`, поэтому ⇧⌘N, ⌥⌘A, ⌥⌘S и ⌥⌘D работают как раньше.
    static let moreCommands: Set<ClaudeCommand> = [.cashout, .arrange, .show, .scroll]
    static let moreTitle = "Ещё"
    static let moreIcon = "⋯"

    /// Разделители стоят после «В отдельное окно» и после «Свернуть»: оконные пункты WF13 идут
    /// одной группой с «Новый чат», дальше пара «Развернуть/Свернуть». Разделители вокруг
    /// «🎨 Оформление ▸» ставит сам `build()`.
    static let separatorsAfter: Set<ClaudeCommand> = [.popoutWindow, .collapse]

    static func entry(for command: ClaudeCommand) -> MenuEntry? {
        entries.first { $0.command == command }
    }

    // MARK: - новое окно (план WF13)

    /// Первое сообщение нового чата: локальная сессия рождается только с ним, пустой строкой
    /// окно не открыть. Только приветствие — никаких команд, путей и просьб что-то запустить
    /// (в этой сессии работает авто-Allow).
    static let newWindowText = "Привет"
    /// Плашка на время работы: чат создаётся и выносится в окно до 40 с, и молчащая кнопка
    /// выглядит сломанной. Успех Элвис видит по самому окну, отказ — плашкой страницы.
    static let newWindowNotice = "Открываю новое окно, несколько секунд…"
    /// Штатные 2,5 с `onWarning` гаснут задолго до результата (критик п. 20 плана WF13).
    static let newWindowNoticeSeconds: TimeInterval = 4

    // MARK: - новое окно в папке проекта (план WF16, вариант А макета)

    /// «🪟 Новое окно ▸» становится подменю: первым пунктом привычное «Здесь же» с клавишей
    /// ⌥⌘N, ниже — список недавних папок. Сам `.newWindow` при этом остаётся в `entries` и на
    /// своём индексе: по нему `ClaudeAXController.refreshHotkeys` регистрирует Carbon-хоткей
    /// (критик В2 плана WF16 — это повтор блокера Б1 из WF14), а у пункта с подменю AppKit
    /// клавишу не отрабатывает, поэтому у родителя её и не рисуем.
    static let newWindowHereTitle = "Здесь же (последняя папка)"
    static let recentProjectsHeader = "НЕДАВНИЕ ПРОЕКТЫ"
    static let projectFolderIcon = "📁"
    /// Сколько папок показывать (вопрос 3 макета WF16 — ответ Элвиса «8»): длиннее список
    /// уже не пробежать глазами.
    static let newWindowProjectsLimit = 8

    // MARK: - оформление (WF5 → WF6, переложено в WF14)

    /// Всё про вид окна — в одном подменю «🎨 Оформление ▸» (вариант А макета WF14):
    /// свои темы сверху, дальше цвет, шрифт, размеры, рамка, поля и «Всем окнам ▸».
    static let appearanceTitle = "Оформление"
    static let appearanceIcon = "🎨"
    /// «Тема» из WF6 переименована в «Цвет» (слово Элвиса 04.09: «там цвет подраздел, шрифт подраздел»).
    static let colorTitle = "Цвет"
    static let fontTitle = "Шрифт"
    /// Вложенное подменю «всем окнам» и его disabled-заголовок — чтобы не спутать с окном.
    /// Заголовок ставится РОВНО ОДИН раз, первым пунктом самого «🖥 Всем окнам ▸»: списки
    /// внутри него своих шапок больше не рисуют (критик В4).
    static let allWindowsTitle = "Всем окнам"
    static let allWindowsIcon = "🖥"
    static let allWindowsHeader = "ВСЕМ ОКНАМ"
    /// Disabled-заголовки секций.
    static let myThemesHeader = "МОИ ТЕМЫ"
    static let darkThemesHeader = "ТЁМНЫЕ"
    static let lightThemesHeader = "СВЕТЛЫЕ"
    /// Секции подменю «Шрифт» — по категориям (решение 7 плана WF9), в порядке FontCategory.
    static let serifFontsHeader = "С ЗАСЕЧКАМИ"
    static let sansFontsHeader = "БЕЗ ЗАСЕЧЕК"
    static let handFontsHeader = "РУКОПИСНЫЕ И ВЕСЁЛЫЕ"
    static let monoFontsHeader = "МОНОШИРИННЫЕ"

    static func fontsHeader(_ category: FontCategory) -> String {
        switch category {
        case .serif: return serifFontsHeader
        case .sans: return sansFontsHeader
        case .hand: return handFontsHeader
        case .mono: return monoFontsHeader
        }
    }

    /// Сброс слоя: в команде `"theme":null` / `"font":null`, остальные слои не трогаем.
    static let themeResetTitle = "Как у Claude"
    static let fontResetTitle = "Системный (как у Claude)"
    /// Размер текста сообщений (план WF12 п. 2) — два подменю «🎨 Оформление ▸».
    static let answerSizeTitle = "Размер ответов"
    static let questionSizeTitle = "Размер вопросов"
    static let sizeIcon = "🔠"
    /// Сброс размера в подменю: снимает ровно СВОЮ половину (`{"answer":null}`, решение 1
    /// плана WF19) — размер вопросов от «Как у Claude» в ответах больше не пропадает.
    /// Обе половины разом снимает «🧹 Всё как у Claude» (`"size":null`).
    static let sizeResetTitle = "Как у Claude"

    static func sizeTitle(_ half: Size.Half) -> String {
        half == .answer ? answerSizeTitle : questionSizeTitle
    }

    /// Тумблер «✨ Неоновая рамка» в «🎨 Оформление ▸» и в его «🖥 Всем окнам ▸» (план WF12 п. 4):
    /// галка — рамка включена, клик переключает, наведение примеряет включённую.
    static let frameTitle = "Неоновая рамка"
    static let frameIcon = "✨"
    /// Свои темы (план п. 4).
    static let saveMyThemeTitle = "Сохранить как мою тему…"
    static let saveMyThemeIcon = "💾"
    static let deleteMyThemeTitle = "Удалить мою тему"
    static let deleteMyThemeIcon = "🗑"
    static let myThemeNamePrompt = "Имя своей темы"
    static let myThemeNameHint = "Тема, шрифт и размер запомнятся парой. "
        + "Имя как у сохранённой — спрошу, перезаписать ли."
    static let myThemeSaveButton = "Сохранить"
    static let myThemeCancelButton = "Отмена"
    static let myThemeEmptyAlert = "Сначала выбери тему — её и запомню вместе со шрифтом."
    /// Имя занято своей темой — перезапись только после подтверждения (критик В2 плана WF14):
    /// иначе «Фиолетовая → Сохранить» на втором окне молча затрёт сохранённую раньше.
    static let myThemeOverwriteButton = "Перезаписать"

    static func myThemeOverwritePrompt(_ name: String) -> String { "Перезаписать «\(name)»?" }

    /// «🧹 Всё как у Claude» — сброс всех четырёх слоёв окна разом, без подтверждения
    /// (слои возвращаются одним кликом; мелочь М10 критика).
    static let resetAllTitle = "Всё как у Claude"
    static let resetAllIcon = "🧹"

    /// «↔️ Поля по бокам» — ползунок прямо в открытом меню (задача #5360). Значение живёт
    /// в `claude.json` (`sidePadding`), лоадер видит файл опросом раз в секунду.
    static let sidePaddingTitle = "Поля по бокам"
    static let sidePaddingIcon = "↔️"
    /// Клик по «🚀 Workflow» на сборке без комплекта (критик п. 3 фикс-батча WF9): молчать
    /// нельзя — со стороны пункт выглядит сломанным.
    static let workflowKitMissingAlert = "В сборке нет комплекта workflow-kit — поставь свежий PimpMyClaude.app"
    /// Иконка достаётся и «Оформление ▸», и «Цвет ▸» — так в утверждённом макете (мелочь М11).
    static let themeIcon = "🎨"
    static let fontIcon = "🔤"
    /// Значения поля `scope` команды `theme` (контракт п. 5 плана WF6).
    static let themeScopeWindow = "window"
    static let themeScopeAll = "all"

    // MARK: - автопокраска (план WF10)

    /// Подменю внутри «🖥 Всем окнам ▸»: наборы, разделитель, «Случайно», «Ещё раз», сброс
    /// всем окнам. Каталог тем ему не нужен — палитры набор считает сам, поэтому оно есть всегда.
    /// С верхнего уровня меню окна и из меню-бара снято (решение Элвиса 04.09 19:30, задача #5362),
    /// имя тоже его — «Раскрасить по кругу» вместо «Автопокраска».
    static let autoPaintTitle = "Раскрасить по кругу"
    static let autoPaintIcon = "🌈"
    static let autoPaintAgainTitle = "Ещё раз"
    static let autoPaintAgainIcon = "🔁"
    /// Сброс слоя темы всем окнам сразу: `theme: null`, `scope: "all"`.
    static let autoPaintResetTitle = "Как у Claude (все окна)"
    /// Красить нечего: окон Claude на экране нет или ни у одного нет AX-заголовка
    /// (без заголовка страница не понимает, какому окну адресована тема).
    static let autoPaintNoWindowsAlert = "Не нашёл окон Claude с заголовком — красить нечего"
    /// Пока крутятся живые цвета, красить по кругу нечем: живой слой перекрывает темы окон
    /// сразу же (критик В13 плана WF18). Пункты подменю гасим, а строкой говорим, что делать.
    static let autoPaintLiveHint = "сначала выключи живые цвета"

    // MARK: - живые цвета (план WF18)

    /// «🌊 Живые цвета ▸» — в «🖥 Всем окнам ▸», сразу под «🌈 Раскрасить по кругу ▸»
    /// (вариант А макета, вопрос 4).
    static let liveColorsTitle = "Живые цвета"
    static let liveColorsIcon = "🌊"
    static let liveColorsOffTitle = "Выключить"
    static let liveColorsOffIcon = "⏹"
    static let liveColorsSyncTitle = "Все окна одним цветом"
    static let liveColorsSyncIcon = "🔗"
    static let liveColorsSoloTitle = "Каждое окно своим цветом"
    static let liveColorsSoloIcon = "🎭"
    static let liveColorsSpeedTitle = "Скорость"
    static let liveColorsSpeedIcon = "⏱"
    static let liveColorsDarkTitle = "Тёмные"
    static let liveColorsDarkIcon = "🌑"
    static let liveColorsLightTitle = "Светлые"
    static let liveColorsLightIcon = "☀️"
    static let liveColorsWindowTitle = "Как окно сейчас"
    static let liveColorsWindowIcon = "🪟"

    static func liveColorsMode(_ mode: LiveColorsMode) -> (title: String, icon: String) {
        mode == .sync ? (liveColorsSyncTitle, liveColorsSyncIcon)
                      : (liveColorsSoloTitle, liveColorsSoloIcon)
    }

    static func liveColorsTone(_ tone: LiveColorsTone) -> (title: String, icon: String) {
        switch tone {
        case .dark: return (liveColorsDarkTitle, liveColorsDarkIcon)
        case .light: return (liveColorsLightTitle, liveColorsLightIcon)
        case .window: return (liveColorsWindowTitle, liveColorsWindowIcon)
        }
    }

    /// Подпись справа от ползунка скорости: вся шкала — целые минуты.
    static func liveColorsSpeed(_ period: Int) -> String { "круг за \(max(period, 60) / 60) мин" }

    /// HUD перед покраской: окна красятся по одному раз в 600 мс, и без строки это выглядит
    /// как зависшее меню. Окон на экране больше, чем цветов, — сразу говорим почему.
    /// `shared` — сколько окон осталось без своего цвета: их заголовок (имя чата) уже занят
    /// соседним окном, а тема живёт на чате. `skipped` — окна без AX-заголовка: их не красим
    /// вовсе, страница не поняла бы, кому адресована тема.
    static func autoPaintStart(windows: Int, shared: Int = 0, skipped: Int = 0) -> String {
        let count = "Крашу \(windows) \(windowsWord(windows))"
        var tails: [String] = []
        if shared > 0 { tails.append("\(shared) без имени чата — одним цветом") }
        if skipped > 0 { tails.append("\(skipped) без заголовка — \(skippedWord(skipped))") }
        guard !tails.isEmpty else { return count + "…" }
        return count + "; " + tails.joined(separator: "; ")
    }

    /// «1 окно пропущено», «2 окна пропущены».
    static func skippedWord(_ count: Int) -> String {
        abs(count) % 10 == 1 && abs(count) % 100 != 11 ? "пропущено" : "пропущены"
    }

    /// «1 окно», «2 окна», «5 окон».
    static func windowsWord(_ count: Int) -> String {
        let hundreds = abs(count) % 100, ones = abs(count) % 10
        if (11...14).contains(hundreds) { return "окон" }
        switch ones {
        case 1: return "окно"
        case 2...4: return "окна"
        default: return "окон"
        }
    }

    // MARK: - цвет проекта (план WF15)

    /// «🗂 Проект: PimpMyClaude ▸» — первый раздел «🎨 Оформление ▸» (решение 5 плана WF15,
    /// вопрос 3 макета: «это про вид»).
    static let projectIcon = "🗂"
    static let projectPaintTitle = "Красить чаты по проекту"
    static let projectApplyTitle = "Взять цвет проекта"
    static let projectApplyIcon = "🎨"
    static let projectWriteTitle = "Записать этот вид в проект"
    static let projectWriteIcon = "💾"
    /// Файла в папке ещё нет — пункт зовётся иначе (макет WF15).
    static let projectCreateTitle = "Завести настройки проекта"
    static let projectCreateIcon = "✍️"
    static let projectAgentsTitle = "Вписать строку в AGENTS.md"
    static let projectAgentsIcon = "📝"
    static let projectRemoveTitle = "Убрать настройки из проекта"
    static let projectRemoveIcon = "🗑"
    /// Папку не узнали (не Claude Code, чужая машина, индекс сменил формат) — пункт остаётся
    /// и гаснет: Элвис должен видеть, что приложение не знает папку, а не гадать, почему
    /// не красит.
    static let projectUnknownTitle = "Проект: не определён"

    static func projectTitle(_ name: String) -> String { "Проект: " + name }

    /// Плашки. Подсказка «у проекта нет своего вида» — один раз на папку (решение 6 плана
    /// WF15, ключ по пути — критик М7).
    static func projectHint(_ name: String) -> String {
        "У проекта \(name) нет своего вида. Меню ▸ Оформление ▸ Проект"
    }

    static func projectWritten(_ name: String) -> String {
        "Вид записан в \(name)/\(ProjectSettings.fileName)"
    }

    /// В папку писать нельзя (нет прав, том только для чтения, отказ TCC) — вид ушёл в реестр
    /// приложения и с папкой к команде уже не поедет.
    static func projectWrittenToRegistry(_ name: String) -> String {
        "В папку \(name) писать нельзя — запомнил вид в приложении"
    }

    static func projectWriteFailed(_ name: String) -> String { "Не удалось записать вид в \(name)" }

    static func projectAgentsWritten(_ name: String) -> String {
        "Строка-памятка вписана в \(name)/\(ProjectPaint.agentsFileName)"
    }

    static func projectAgentsFailed(_ name: String) -> String {
        "Не удалось вписать строку в \(name)/\(ProjectPaint.agentsFileName)"
    }

    /// «Убрать настройки» окна назад не перекрашивает и AGENTS.md не трогает — говорим об этом.
    static func projectRemoved(_ name: String) -> String {
        "Настройки \(name) убраны; строку в AGENTS.md не трогал, цвет окон остался"
    }

    static let projectNoSettings = "У этого проекта своего вида нет"
    static let projectNothingToWrite = "Сначала выбери окну цвет или шрифт — его и запишу в проект"

    /// ⌘Q — не пункт меню, а блокировка выхода (claude_noquit.lua).
    static let quitKey = KeySpec(mods: [.command], name: "q")
    static let quitMessage = "⌘Q в Claude заблокирован — выход через меню Claude → Quit"
}
