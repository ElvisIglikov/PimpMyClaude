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
        // поэтому её мы регистрируем сами; «Вынести этот чат в окно» — без клавиши.
        MenuEntry(command: .newWindow, title: "Новое окно", icon: "🪟",
                  key: KeySpec(mods: [.command, .option], name: "n"), registersHotkey: true),
        MenuEntry(command: .popoutWindow, title: "Вынести этот чат в окно", icon: "🪟",
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

    /// Все команды — внутри «⋯ Ещё ▸» (слово Элвиса 17.09, #6248: «Workflow, новый чат, новое
    /// окно, вынести этот чат в окно, развернуть, свернуть — всё в ещё. PimpMyClaude — про
    /// прокачку именно визуала»; до WF71 тут была одна редкая четвёрка, решение 04.09).
    /// Прячем только с глаз: пункты остаются в `entries`, поэтому ⌥⌘N, ⌥⌘↑, ⌥⌘↓, ⇧⌘N, ⌥⌘A,
    /// ⌥⌘S и ⌥⌘D работают как раньше.
    static let moreCommands: Set<ClaudeCommand> = [.workflow, .newChat, .newWindow, .popoutWindow,
                                                   .expand, .collapse, .cashout, .arrange, .show,
                                                   .scroll]
    static let moreTitle = "Ещё"
    static let moreIcon = "⋯"

    /// Разделители стоят после «Вынести этот чат в окно» и после «Свернуть»: оконные пункты WF13
    /// идут одной группой с «Новый чат», дальше пара «Развернуть/Свернуть». С WF71 всё это
    /// внутри «⋯ Ещё ▸», разделители там ставит `moreItem` по этому же списку.
    static let separatorsAfter: Set<ClaudeCommand> = [.popoutWindow, .collapse]

    static func entry(for command: ClaudeCommand) -> MenuEntry? {
        entries.first { $0.command == command }
    }

    // MARK: - новое окно (план WF13)

    /// Первое сообщение нового чата: локальная сессия рождается только с ним, пустой строкой
    /// окно не открыть. Текст прямо просит не начинать работу и не читать правила: на «Привет»
    /// (и тем более на имя проекта) агент разворачивал полную ориентировку по правилам, и одно
    /// новое окно стоило 2–5 долларов в пересчёте на API при 6–11 окнах в день (#5767/#5447,
    /// слово Элвиса 08.09 11:40). Имя чату это не ломает: его ставит отдельный шаг
    /// переименования на странице (поле `name` команды), а не авто-заголовок по первому
    /// сообщению. Ни команд, ни путей: в этой сессии работает авто-Allow.
    static let newWindowText = "Окно открыто. Не читай правила и ничего не делай, жди задачу."
    /// Плашка на время работы: чат создаётся и выносится в окно до 40 с, и молчащая кнопка
    /// выглядит сломанной. Успех Элвис видит по самому окну, отказ — плашкой страницы.
    static let newWindowNotice = "Открываю новое окно, несколько секунд…"
    /// Штатные 2,5 с `onWarning` гаснут задолго до результата (критик п. 20 плана WF13).
    static let newWindowNoticeSeconds: TimeInterval = 4

    // MARK: - «Обкэшить» заменяет окно (#5768; правда о доезде — #5779)

    /// Новое окно встало на место старого, и старое ПРАВДА закрылось: `AX.close` вернул успех.
    static let cashoutReplacedNotice = "Новое окно на месте старого. Старое закрыл — чат остался в списке слева"
    /// Текст доехал, а кнопки закрытия у старого окна AX не отдал: раньше плашка всё равно
    /// говорила «закрыл» — и врала (#5779).
    static let cashoutCloseFailedNotice = "Перенёс в новое окно. Старое закрыть не смог — закрой его сам"
    /// Нового окна не появилось вовсе: старое не трогаем.
    static let cashoutNoWindowNotice = "Новое окно не открылось — старое оставил как было"
    /// Окно родилось, а доезд текста так никто и не подтвердил.
    static let cashoutNoAnswerReason = "страница не подтвердила вставку"

    /// Перенос не доехал: старое окно остаётся на месте, и Элвис слышит, что именно не вышло.
    /// Молчаливый выход по проверке = «кнопка не работает» (урок ElvisOS, #5784).
    static func cashoutKeptNotice(_ why: String) -> String {
        "Перенос не доехал (\(why)) — старое окно оставил как было"
    }

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

    // MARK: - полоса раскладок (план WF21, слова Элвиса 08.09)

    /// Первый пункт «⋯ Ещё ▸» (до WF71 — всего меню) — четыре картинки: «4 в ряд», «5 в ряд»,
    /// «5 × 2» и «как сейчас» (лента). Заголовок пункта на экран не выходит — его рисует
    /// `LayoutPickerView`, — но он нужен VoiceOver и тестам структуры меню.
    static let layoutsTitle = "Раскладки"
    /// Подписи под плитками, в порядке полосы.
    static func layoutTitle(_ mode: ArrangeLayout.Mode) -> String {
        switch mode {
        case .four: return "4 в ряд"
        case .five: return "5 в ряд"
        case .tenGrid: return "5 × 2"
        case .ribbon: return "как сейчас"
        }
    }

    /// Порядок плиток — как в макете: сетки, потом лента. Какие из них попадут в полосу,
    /// решает число окон на экране (`ArrangeLayout.suits`, #5800).
    static let layoutOrder: [ArrangeLayout.Mode] = [.four, .five, .tenGrid, .ribbon]
    /// Последняя клетка полосы — «💾 сохранить» (#5799, слово Элвиса 08.09: «это же пресеты,
    /// где-то прямо там должна быть кнопочка "сохранить пресет"»). Действие то же, что у
    /// пункта «💾 Сохранить эту раскладку…» в «⋯ Ещё ▸ 🗂 Раскладки ▸» — оттуда он не убран.
    static let saveLayoutTileTitle = "сохранить"
    /// Раскладка на этом экране дала бы ячейки уже `minWindowWidth` — плитка серая.
    static let layoutTooSmallHint = "экран уже"
    /// ⌥⌘A и «▦ Расставить» повторяют последнюю раскладку, а она бывает с чужого экрана
    /// (#5733): на узком она дала бы налезающие окна. Кладём лентой и говорим плашкой.
    static let arrangeTooSmallNotice = "Экран мал для этой сетки — разложил лентой"

    // MARK: - раскладки проектов (план WF41, решение Р5)

    /// «🗂 Раскладки ▸» — последним пунктом «⋯ Ещё ▸»: запомнить нынешние окна под именем
    /// и вернуть их же потом. У каждой сохранённой раскладки своё подменю.
    static let savedLayoutsTitle = "Раскладки"
    static let savedLayoutsIcon = "🗂"
    static let savedLayoutIcon = "▦"
    static let saveLayoutTitle = "Сохранить эту раскладку…"
    static let saveLayoutIcon = "💾"
    static let restoreLayoutTitle = "Вернуть эти чаты"
    static let restoreLayoutIcon = "↩︎"
    static let freshLayoutTitle = "Новые чаты по этим проектам"
    static let freshLayoutIcon = "✨"
    static let deleteLayoutTitle = "Удалить"
    static let deleteLayoutIcon = "🗑"
    static let layoutNamePrompt = "Имя раскладки"
    static let layoutNameHint = "Запомню, какой чат в каком месте стоит: «Утро», «Разбор». "
        + "Имя как у сохранённой — перезапишу её."
    static let layoutSaveButton = "Сохранить"
    /// Окон Claude на экране нет — запоминать нечего.
    static let layoutNoWindowsAlert = "Не нашёл окон Claude — запоминать нечего"
    /// Поле имени очистили: без имени раскладку не найти потом (#5769). Имя приложение
    /// подставляет само, поэтому пустым поле бывает только руками.
    static let layoutNameEmptyAlert = "Без имени не запомню — назови раскладку, например «Утро»"
    /// Ни одно окно не попало в ячейку сетки: такая раскладка вернула бы ноль окон, и писать
    /// её нечего (#5728). Те же слова, что у канала «Пимп» (`tools/pimp.py`).
    static let layoutNotArrangedAlert = "Окна стоят не по сетке — сперва расставь их, потом запоминай раскладку"
    /// Возврат идёт по одному окну и занимает минуту и дольше — молчать нельзя.
    static let layoutRestoreNotice = "Возвращаю окна, по одному…"
    static let layoutBusyNotice = "Занят — открываю окна по прошлой просьбе"
    static let layoutWriteFailed = "Не удалось записать layouts.json в Application Support/MyClaude"

    /// Чат окна приложению неизвестен: раскладку не пишем вовсе — вернулись бы не те чаты
    /// (#5455). Лечится тумблером «🗂 Цвет по проекту» и свободным probe.js.
    static func layoutChatUnknownAlert(_ titles: [String]) -> String {
        let names = titles.filter { !$0.isEmpty }.map { "«\($0)»" }.joined(separator: ", ")
        let tail = names.isEmpty ? "" : " (\(names))"
        return "Не знаю, какие чаты в окнах\(tail) — включи «🗂 Цвет по проекту» и попробуй снова"
    }

    /// Подсказка у сохранённой раскладки: какая сетка и сколько в ней окон.
    static func layoutHint(_ layout: WindowLayout) -> String {
        layoutTitle(layout.mode) + " · " + "\(layout.cells.count) " + windowsWord(layout.cells.count)
    }

    // MARK: - оформление (WF5 → WF6, переложено в WF14, поднято на верх в WF71)

    /// Всё про вид окна — с WF71 это и есть верхний уровень меню (слово Элвиса 17.09, #6248:
    /// «минус нажимаешь — там всё с оформлением связано»): свои темы сверху, дальше цвет,
    /// шрифт, размер, рамка, поля. Подменю «🎨 Оформление ▸» больше нет; заголовок остался
    /// константой — по нему тесты называют раздел, а «🖥 Всем окнам ▸» уехало в «⋯ Ещё ▸».
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
    /// Disabled-заголовок секции своих тем. Капса у цветов больше нет (макет WF52, раздел
    /// «Решено»): пишем обычными буквами, как Claude в своих меню.
    static let myThemesHeader = "Мои темы"
    /// Три списка цветов вместо одного длинного (слово Элвиса 12.09, задача #5801): каждый —
    /// своё подменю с галкой у того набора, откуда взят цвет окна.
    static let darkThemesHeader = "Тёмные"
    static let lightThemesHeader = "Светлые"
    static let brightThemesHeader = "Яркие"
    static let darkThemesIcon = "🌙"
    static let lightThemesIcon = "☀️"
    static let brightThemesIcon = "✨"

    static func themeSetTitle(_ set: ThemeSet) -> String {
        switch set {
        case .dark: return darkThemesHeader
        case .light: return lightThemesHeader
        case .bright: return brightThemesHeader
        }
    }

    static func themeSetIcon(_ set: ThemeSet) -> String {
        switch set {
        case .dark: return darkThemesIcon
        case .light: return lightThemesIcon
        case .bright: return brightThemesIcon
        }
    }
    /// Секции подменю «Шрифт» — по категориям (решение 7 плана WF9).
    static let serifFontsHeader = "С ЗАСЕЧКАМИ"
    static let sansFontsHeader = "БЕЗ ЗАСЕЧЕК"
    static let handFontsHeader = "РУКОПИСНЫЕ И ВЕСЁЛЫЕ"
    static let monoFontsHeader = "МОНОШИРИННЫЕ"
    /// Порядок секций в меню (слово Элвиса 17.09, #6251: «шрифты с засечками — в самый
    /// конец»). Сам `FontCategory` не трогаем: на порядке его case стоят каталог
    /// (`FontCatalog.build`) и `category(family:mono:)`.
    static let fontSectionOrder: [FontCategory] = [.sans, .hand, .mono, .serif]

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
    /// Размер текста ответов (план WF12 п. 2). С WF71 в меню одно подменю «🔠 Размер шрифта ▸»
    /// (слово Элвиса 17.09 14:22) — оно по-прежнему меняет половину `answer`. «Размер
    /// вопросов ▸» из меню убран (#6252: «ни на что не влияет»); константа осталась, потому
    /// что половина `question` живёт в контракте `size` и в старых файлах, и тест сторожит,
    /// что пункта с этим именем в меню нет.
    static let answerSizeTitle = "Размер шрифта"
    static let questionSizeTitle = "Размер вопросов"
    static let sizeIcon = "🔠"
    /// Сброс размера в подменю: снимает ровно СВОЮ половину (`{"answer":null}`, решение 1
    /// плана WF19) — размер вопросов от «Как у Claude» в ответах больше не пропадает.
    /// Обе половины разом снимает «🧹 Всё как у Claude» (`"size":null`).
    static let sizeResetTitle = "Как у Claude"

    static func sizeTitle(_ half: Size.Half) -> String {
        half == .answer ? answerSizeTitle : questionSizeTitle
    }

    /// Тумблер «✨ Неоновая рамка» на верхнем уровне и в «🖥 Всем окнам ▸» (план WF12 п. 4):
    /// галка — рамка включена, клик переключает, наведение примеряет включённую.
    static let frameTitle = "Неоновая рамка"
    static let frameIcon = "✨"
    /// Свои темы (план п. 4, переложено в WF71). «💾 Сохранить тему» — один пункт раздела,
    /// без диалога и без «мою» (слово Элвиса 17.09 14:20: «сохранить тему и всё, и она чик
    /// сразу появляется сверху»): имя даёт `MyThemesStore.autoName`, новая тема встаёт первой.
    static let saveMyThemeTitle = "Сохранить тему"
    static let saveMyThemeIcon = "💾"
    /// У каждой своей темы своё подменю (#6249: «изменить, сохранить, удалить — это должно
    /// быть прямо у темы»): «Применить ▸» с адресатом, «✏️ Изменить…», разделитель, «🗑 Удалить».
    static let applyMyThemeTitle = "Применить"
    static let applyMyThemeWindowTitle = "Только этому окну"
    static let applyMyThemeAllTitle = "Всем окнам"
    static let deleteMyThemeTitle = "Удалить"
    static let deleteMyThemeIcon = "🗑"

    /// «Окнам проекта PimpMyClaude» — пункт есть только у окна, опознанного проектом.
    static func applyMyThemeProjectTitle(_ name: String) -> String { "Окнам проекта \(name)" }

    static let myThemeNamePrompt = "Имя своей темы"
    /// Строка честная (решение 2.5 плана WF31): в файл `my-themes.json` по-прежнему уходят
    /// цвет, шрифт и размер, а ставится из своей темы только цвет. С WF71 диалог имени
    /// спрашивает только панель «Своя тема» (это и есть переименование).
    static let myThemeNameHint = "Запомню цвет, шрифт и размер, но ставиться будет только цвет — "
        + "шрифт и размер выбираются отдельно. Имя как у сохранённой — спрошу, перезаписать ли."
    static let myThemeSaveButton = "Сохранить"
    static let myThemeCancelButton = "Отмена"
    static let myThemeEmptyAlert = "Сначала выбери тему — её цвет и запомню."
    /// Имя занято своей темой — перезапись только после подтверждения (критик В2 плана WF14):
    /// иначе «Фиолетовая → Сохранить» на втором окне молча затрёт сохранённую раньше.
    /// С WF71 вопрос задаёт только панель «Своя тема»: у «💾 Сохранить тему» имя всегда новое.
    static let myThemeOverwriteButton = "Перезаписать"

    static func myThemeOverwritePrompt(_ name: String) -> String { "Перезаписать «\(name)»?" }

    // MARK: - редактор своей темы (план WF20, решения 1.1 и 1.5)

    /// Панель с ручками открывается ТОЛЬКО из «✏️ Изменить…» в подменю своей темы (WF71):
    /// пункта «🎚 Своя тема…» в меню больше нет (слово Элвиса 17.09: «плюс своя тема не
    /// нужно»); заголовок остался константой — панель так и называется, а тест сторожит,
    /// что пункта с этим именем в меню нет. Предпросмотра по наведению у «Изменить…» нет:
    /// панель и так красит окно, как только тронули ручку.
    static let themeEditorTitle = "Своя тема…"
    static let themeEditorIcon = "🎚"
    static let editMyThemeTitle = "Изменить…"
    static let editMyThemeIcon = "✏️"

    /// Заголовок панели и подписи её ручек (вариант А макета WF20).
    static let themeEditorPanel = "Своя тема"
    static let themeEditorHueTitle = "Цвет"
    static let themeEditorAccentTitle = "Акцент"
    static let themeEditorStrengthTitle = "Сила цвета"
    static let themeEditorDarkTitle = "Тёмная"
    static let themeEditorLightTitle = "Светлая"
    static let themeEditorSaveButton = "Сохранить"
    static let themeEditorCancelButton = "Отмена"
    /// Ручки не из файла, а подобранные по палитре (тон ±2°, сила ±5 %) — честно говорим.
    static let themeEditorGuessedHint = "ручки подобраны по цветам"
    /// Примерка адресуется AX-заголовком окна; заголовка нет — примерять нечем, но панель
    /// остаётся рабочей: «Сохранить» запишет тему и без него.
    static let themeEditorNoTitleHint = "у окна нет заголовка — примерка невозможна"
    static let themeEditorWriteFailed = "Не удалось записать my-themes.json в Application Support/MyClaude"

    /// Строка под ручками: оба контраста числами, как в макете.
    static func themeEditorContrast(text: Double, accent: Double) -> String {
        func number(_ value: Double) -> String {
            String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        }
        return "контраст текста \(number(text)) · акцент \(number(accent))"
    }

    /// «🧹 Всё как у Claude» — сброс всех четырёх слоёв окна разом, без подтверждения
    /// (слои возвращаются одним кликом; мелочь М10 критика).
    static let resetAllTitle = "Всё как у Claude"
    static let resetAllIcon = "🧹"

    /// «↔️ Поля» — ползунок прямо в открытом меню (задача #5360; «Поля по бокам → просто Поля» —
    /// слово Элвиса 17.09, #6253). Значение живёт в `claude.json` (`sidePadding`), лоадер
    /// видит файл опросом раз в секунду.
    static let sidePaddingTitle = "Поля"
    static let sidePaddingIcon = "↔️"
    /// Клик по «🚀 Workflow» на сборке без комплекта (критик п. 3 фикс-батча WF9): молчать
    /// нельзя — со стороны пункт выглядит сломанным.
    static let workflowKitMissingAlert = "В сборке нет комплекта workflow-kit — поставь свежий PimpMyClaude.app"
    /// Иконка «🎨 Цвет ▸» — та же, что была у «Оформление ▸» (мелочь М11 плана WF14).
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

    // MARK: - цвет проекта (план WF15, переделан в WF20)

    /// Тумблер «🗂 Цвет по проекту» — всё, что осталось от подменю «Проект ▸» (решение 3.4
    /// плана WF20): стоит в «🖥 Всем окнам ▸» перед «🌈 Раскрасить по кругу ▸», включён по
    /// умолчанию. Подписи папки, «Взять цвет проекта», «Записать этот вид», «Вписать строку
    /// в AGENTS.md» и «Убрать настройки» больше нет: цвет у проекта появляется сам, а выбор
    /// темы в окне проекта сам в проект и ложится.
    /// Тот же значок носит «🗂 <Проект>» — первый пункт раздела своих тем (WF71, #6249:
    /// «у каждого проекта же своя тема»): имя папки, кружок темы проекта, клик возвращает
    /// окну вид проекта, ничего не записывая.
    static let projectIcon = "🗂"
    static let projectColorTitle = "Цвет по проекту"

    /// Плашка про молчаливую запись — один раз на папку (решение 3.2 плана WF20, ключ по пути):
    /// файл заводится сам, и Элвис должен знать, что в папке проекта он появился.
    static func projectWritten(_ name: String) -> String {
        "Цвет записан в проект \(name) (\(ProjectSettings.fileName))"
    }

    /// В папку писать нельзя (нет прав, том только для чтения, отказ TCC) — вид ушёл в реестр
    /// приложения и с папкой к команде уже не поедет.
    static func projectWrittenToRegistry(_ name: String) -> String {
        "В папку \(name) писать нельзя — запомнил вид в приложении"
    }

    static func projectWriteFailed(_ name: String) -> String { "Не удалось записать вид в \(name)" }

    /// Файл проекта битый: перезаписывать его «на всякий случай» нельзя — в нём могли быть
    /// чужие ключи (решение 3.6 плана WF20). Плашка тоже один раз на папку.
    static func projectBroken(_ name: String) -> String {
        "\(name)/\(ProjectSettings.fileName) битый — не трогаю"
    }

    /// ⌘Q — не пункт меню, а блокировка выхода (claude_noquit.lua).
    static let quitKey = KeySpec(mods: [.command], name: "q")
    static let quitMessage = "⌘Q в Claude заблокирован — выход через меню Claude → Quit"
}
