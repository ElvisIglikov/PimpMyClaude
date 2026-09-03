import Foundation

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
}

/// Клавиша: имя как в `M.hotkeys` Lua-модуля («n», «down»), код — виртуальный код Carbon.
struct KeySpec {
    let mods: KeyMods
    let name: String

    /// kVK_ANSI_A 0x00, S 0x01, D 0x02, Q 0x0C, N 0x2D, Down 0x7D, Up 0x7E.
    private static let codes: [String: (code: UInt32, glyph: String)] = [
        "a": (0x00, "A"),
        "s": (0x01, "S"),
        "d": (0x02, "D"),
        "q": (0x0C, "Q"),
        "n": (0x2D, "N"),
        "down": (0x7D, "↓"),
        "up": (0x7E, "↑"),
    ]

    var keyCode: UInt32? { KeySpec.codes[name]?.code }
    var glyph: String { KeySpec.codes[name]?.glyph ?? name.uppercased() }
    var hint: String { mods.hint + glyph }
}

/// Пункт меню на кнопке «Свернуть» — порядок, иконки и клавиши строго как в README.
struct MenuEntry {
    let command: ClaudeCommand
    let title: String
    let icon: String
    let key: KeySpec
    /// ⌘N — штатная клавиша самого Claude: показываем подсказку, но не регистрируем.
    let registersHotkey: Bool

    /// «Обкэшить   ⌘⇧N» — три пробела перед подсказкой, как в Lua (`hint()`).
    var menuTitle: String { title + "   " + key.hint }
}

enum MenuModel {
    static let entries: [MenuEntry] = [
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

    /// ⌘Q — не пункт меню, а блокировка выхода (claude_noquit.lua).
    static let quitKey = KeySpec(mods: [.command], name: "q")
    static let quitMessage = "⌘Q в Claude заблокирован — выход через меню Claude → Quit"
}
