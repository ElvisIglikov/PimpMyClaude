import AppKit

// Приложение без окна в доке: живёт иконкой в строке меню (LSUIElement в Info.plist).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
