import AppKit
import ClaudeAX

// Проба подсказки у окна связки ключей (WF238): `open -n <сборка>.app --args --keychain-hint-demo`. Стоит ДО
// `AppDelegate()`: уже его свойства поднимают AX-модуль, панель у часов и обновление самих себя.
if KeychainHint.isDemoLaunch(CommandLine.arguments) { KeychainHintDemo.run() }

// Приложение без окна в доке: живёт иконкой в строке меню (LSUIElement в Info.plist).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
