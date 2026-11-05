import Carbon.HIToolbox
import Foundation

/// Одна горячая клавиша: id уникален внутри процесса, действие зовётся в главном потоке.
struct HotkeyBinding {
    let id: UInt32
    let key: KeySpec
    let action: () -> Void
}

/// Горячие клавиши через Carbon `RegisterEventHotKey` (решение 1 плана) — ровно то, что
/// делает `hs.hotkey`: клавиша ПРОГЛАТЫВАЕТСЯ (важно для ⌘Q) и не требует Input Monitoring,
/// в отличие от глобального монитора NSEvent. Регистрируются, только пока Claude впереди:
/// снятая регистрация возвращает клавишу остальным приложениям.
final class CarbonHotkeys {
    private struct Live {
        let ref: EventHotKeyRef
        let code: UInt32
        let mods: UInt32
        var action: () -> Void
    }

    private static let signature: OSType = 0x504D4331 // 'PMC1'

    private var handler: EventHandlerRef?
    private var live: [UInt32: Live] = [:]

    var count: Int { live.count }

    /// Привести набор зарегистрированных клавиш к заданному: лишние снять, новые поставить,
    /// у совпавших обновить действие. Пустой массив = снять все.
    func apply(_ bindings: [HotkeyBinding]) {
        var wanted: [UInt32: HotkeyBinding] = [:]
        for binding in bindings where binding.key.keyCode != nil { wanted[binding.id] = binding }

        for (id, entry) in live where wanted[id] == nil {
            UnregisterEventHotKey(entry.ref)
            live[id] = nil
        }
        for (id, binding) in wanted {
            let code = binding.key.keyCode ?? 0
            let mods = binding.key.mods.carbon
            if var entry = live[id] {
                if entry.code == code && entry.mods == mods {
                    entry.action = binding.action
                    live[id] = entry
                    continue
                }
                UnregisterEventHotKey(entry.ref)
                live[id] = nil
            }
            installHandlerIfNeeded()
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: CarbonHotkeys.signature, id: id)
            let status = RegisterEventHotKey(code, mods, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref = ref {
                live[id] = Live(ref: ref, code: code, mods: mods, action: binding.action)
            }
        }
    }

    deinit { removeAll() }

    func removeAll() {
        apply([])
        if let handler = handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    fileprivate func fire(id: UInt32) {
        live[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == CarbonHotkeys.signature else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<CarbonHotkeys>.fromOpaque(userData).takeUnretainedValue().fire(id: hotKeyID.id)
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}

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
}

/// Клавиша: имя как в `M.hotkeys` Lua-модуля («n», «down»), код — виртуальный код Carbon.
struct KeySpec {
    let mods: KeyMods
    let name: String

    /// kVK_ANSI_A 0x00, S 0x01, D 0x02, Q 0x0C, N 0x2D, Down 0x7D, Up 0x7E.
    private static let codes: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "q": 0x0C, "n": 0x2D, "down": 0x7D, "up": 0x7E,
    ]

    var keyCode: UInt32? { KeySpec.codes[name] }
}

/// Команда на клавише. С WF237 (#9524) меню жёлтой кнопки нет — список остался ради клавиш.
struct HotkeyEntry {
    let command: ClaudeCommand
    let title: String
    /// nil — у команды клавиши нет вовсе («Воркфлоу»: ⌘⌥W занят самим Claude).
    let key: KeySpec?
    /// ⌘N — штатная клавиша самого Claude: не регистрируем.
    let registersHotkey: Bool
}

/// Клавиши PMP в Claude (выключатель «Клавиши PMP в Claude» в «Окна и Mac») и блок ⌘Q.
enum Hotkeys {
    /// Порядок прежнего меню: по нему `ClaudeAXController.refreshHotkeys` даёт Carbon-хоткеям id = индекс + 1,
    /// поэтому строки не переставлять и не вынимать — у остальных сдвинулись бы id.
    static let entries: [HotkeyEntry] = [
        HotkeyEntry(command: .workflow, title: "Воркфлоу", key: nil, registersHotkey: false),
        HotkeyEntry(command: .newChat, title: "Новый чат", key: KeySpec(mods: [.command], name: "n"),
                    registersHotkey: false),
        HotkeyEntry(command: .newWindow, title: "Новое окно", key: KeySpec(mods: [.command, .option], name: "n"),
                    registersHotkey: true),
        HotkeyEntry(command: .popoutWindow, title: "Вынести этот чат в окно", key: nil, registersHotkey: false),
        HotkeyEntry(command: .expand, title: "Развернуть", key: KeySpec(mods: [.command, .option], name: "up"),
                    registersHotkey: true),
        HotkeyEntry(command: .collapse, title: "Свернуть", key: KeySpec(mods: [.command, .option], name: "down"),
                    registersHotkey: true),
        HotkeyEntry(command: .cashout, title: "Обкэшить", key: KeySpec(mods: [.command, .shift], name: "n"),
                    registersHotkey: true),
        HotkeyEntry(command: .arrange, title: "Расставить", key: KeySpec(mods: [.command, .option], name: "a"),
                    registersHotkey: true),
        HotkeyEntry(command: .show, title: "Показать", key: KeySpec(mods: [.command, .option], name: "s"),
                    registersHotkey: true),
        HotkeyEntry(command: .scroll, title: "Прокрутить", key: KeySpec(mods: [.command, .option], name: "d"),
                    registersHotkey: true),
    ]

    static func entry(for command: ClaudeCommand) -> HotkeyEntry? {
        entries.first { $0.command == command }
    }

    /// ⌘Q — не команда, а блокировка выхода (claude_noquit.lua).
    static let quitKey = KeySpec(mods: [.command], name: "q")
    static let quitMessage = "⌘Q в Claude заблокирован — выход через меню Claude → Quit"
}
