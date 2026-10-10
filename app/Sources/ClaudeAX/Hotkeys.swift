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
