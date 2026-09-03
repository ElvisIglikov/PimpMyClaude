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
    static let entries: [MenuEntry] = [
        // «Workflow» — первым и без клавиши: ⌘⌥W у Claude свой.
        MenuEntry(command: .workflow, title: "Workflow", icon: "🚀", key: nil, registersHotkey: false),
        MenuEntry(command: .cashout, title: "Обкэшить", icon: "💰",
                  key: KeySpec(mods: [.command, .shift], name: "n"), registersHotkey: true),
        MenuEntry(command: .newChat, title: "Новый чат", icon: "💬",
                  key: KeySpec(mods: [.command], name: "n"), registersHotkey: false),
        MenuEntry(command: .collapse, title: "Свернуть", icon: "⬇️",
                  key: KeySpec(mods: [.command, .option], name: "down"), registersHotkey: true),
        MenuEntry(command: .expand, title: "Развернуть", icon: "⬆️",
                  key: KeySpec(mods: [.command, .option], name: "up"), registersHotkey: true),
        MenuEntry(command: .arrange, title: "Расставить", icon: "▦",
                  key: KeySpec(mods: [.command, .option], name: "a"), registersHotkey: true),
        MenuEntry(command: .show, title: "Показать", icon: "👀",
                  key: KeySpec(mods: [.command, .option], name: "s"), registersHotkey: true),
        MenuEntry(command: .scroll, title: "Прокрутить", icon: "⏬",
                  key: KeySpec(mods: [.command, .option], name: "d"), registersHotkey: true),
    ]

    /// Разделители стоят после «Новый чат» и после «Развернуть» (README).
    static let separatorsAfter: Set<ClaudeCommand> = [.newChat, .expand]

    static func entry(for command: ClaudeCommand) -> MenuEntry? {
        entries.first { $0.command == command }
    }

    // MARK: - темы и шрифты (WF5, переложено в WF6)

    /// Два подменю после семи пунктов, за разделителем. Хоткеев у них нет — только меню.
    /// «Тема окна»/«Тема всех окон» из WF5 схлопнуты в одно «Тема» с вложенным «Всем окнам ▸»:
    /// подменю стояли вплотную и при скольжении мыши вниз одно подменялось другим (жалоба #5313).
    static let themeTitle = "Тема"
    static let fontTitle = "Шрифт"
    /// Вложенное подменю «всем окнам» и его disabled-заголовок — чтобы не спутать с окном.
    static let allWindowsTitle = "Всем окнам"
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

    /// Сброс слоя: в команде `"theme":null` / `"font":null`, второй слой не трогаем.
    static let themeResetTitle = "Как у Claude"
    static let fontResetTitle = "Системный (как у Claude)"
    /// Свои темы (план п. 4).
    static let saveMyThemeTitle = "Сохранить как мою тему…"
    static let deleteMyThemeTitle = "Удалить мою тему"
    static let myThemeNamePrompt = "Имя своей темы"
    static let myThemeNameHint = "Тема и шрифт запомнятся парой — применить их можно будет одним пунктом."
    static let myThemeSaveButton = "Сохранить"
    static let myThemeCancelButton = "Отмена"
    static let myThemeEmptyAlert = "Сначала выбери тему — её и запомню вместе со шрифтом."
    /// Клик по «🚀 Workflow» на сборке без комплекта (критик п. 3 фикс-батча WF9): молчать
    /// нельзя — со стороны пункт выглядит сломанным.
    static let workflowKitMissingAlert = "В сборке нет комплекта workflow-kit — поставь свежий PimpMyClaude.app"
    static let themeIcon = "🎨"
    static let fontIcon = "🔤"
    /// Значения поля `scope` команды `theme` (контракт п. 5 плана WF6).
    static let themeScopeWindow = "window"
    static let themeScopeAll = "all"

    // MARK: - автопокраска (план WF10)

    /// Подменю после «🔤 Шрифт ▸»: наборы, разделитель, «Случайно», «Ещё раз», сброс всем окнам.
    /// Каталог тем ему не нужен — палитры набор считает сам, поэтому оно есть всегда.
    static let autoPaintTitle = "Автопокраска"
    static let autoPaintIcon = "🌈"
    static let autoPaintAgainTitle = "Ещё раз"
    static let autoPaintAgainIcon = "🔁"
    /// Сброс слоя темы всем окнам сразу: `theme: null`, `scope: "all"`.
    static let autoPaintResetTitle = "Как у Claude (все окна)"
    /// Красить нечего: окон Claude на экране нет или ни у одного нет AX-заголовка
    /// (без заголовка страница не понимает, какому окну адресована тема).
    static let autoPaintNoWindowsAlert = "Не нашёл окон Claude с заголовком — красить нечего"

    /// Заголовки-заглушки: у окна с таким именем чата нет, и тема ляжет на ключ, общий для
    /// всех таких окон, — они покрасятся одинаково. Про это HUD и предупреждает.
    static let unnamedChatTitles = ["claude", "new chat"]

    static func isUnnamedChat(_ title: String) -> Bool {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.isEmpty || unnamedChatTitles.contains(text)
    }

    /// HUD перед покраской: окна красятся по одному раз в 600 мс, и без строки это выглядит
    /// как зависшее меню. Окон на экране больше, чем цветов, — сразу говорим почему.
    static func autoPaintStart(windows: Int, unnamed: Int) -> String {
        let count = "\(windows) \(windowsWord(windows))"
        guard unnamed > 0 else { return "Крашу \(count)…" }
        return "Крашу \(count); \(unnamed) без имени чата — одним цветом"
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

    /// ⌘Q — не пункт меню, а блокировка выхода (claude_noquit.lua).
    static let quitKey = KeySpec(mods: [.command], name: "q")
    static let quitMessage = "⌘Q в Claude заблокирован — выход через меню Claude → Quit"
}
