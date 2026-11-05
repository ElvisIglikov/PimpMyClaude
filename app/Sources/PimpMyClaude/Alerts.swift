import AppKit
import Patcher

/// Окно «Не вышло» с текстом ошибки и «Понятно» — одно на действия панели и окно настройки (ревизия WF247, С5б).
enum Alerts {
    static func failure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Не вышло"
        alert.informativeText = error.humanText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
