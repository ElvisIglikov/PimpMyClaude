import AppKit
import ApplicationServices
import ClaudeAX
import Patcher
import ServiceManagement

/// Меню-бар без окна (LSUIElement): статус патча, три кнопки установки и тумблеры фишек.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Key {
        static let autoAllow = "autoAllowEnabled"
        static let minimizeMenu = "minimizeMenuEnabled"
        static let blockQuit = "blockQuitEnabled"
        static let loginItemConfigured = "loginItemConfigured"
        static let claudePath = "claudeAppPath"
    }

    private let ax: ClaudeAXControlling = ClaudeAXController()
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var busy = false

    private let stateItem = NSMenuItem(title: "Проверяю…", action: nil, keyEquivalent: "")
    private let autoAllowItem = NSMenuItem(title: "Авто-Allow", action: #selector(toggleAutoAllow), keyEquivalent: "")
    private let minimizeMenuItem = NSMenuItem(title: "Меню на кнопке", action: #selector(toggleMinimizeMenu), keyEquivalent: "")
    private let blockQuitItem = NSMenuItem(title: "Блок ⌘Q", action: #selector(toggleBlockQuit), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLoginItem), keyEquivalent: "")

    // ---------------------------------------------------------------- запуск

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Key.autoAllow: true, Key.minimizeMenu: true, Key.blockQuit: true])
        buildStatusItem()
        applySettingsToAX()
        ax.start()
        configureLoginItemOnFirstRun()
        refreshState()
        // `open -a PimpMyClaude.app --args --status` — окно статуса без похода в меню (нужно на гейте).
        if CommandLine.arguments.contains("--status") { showStatus() }

        // Решение 4: проверка при активации Claude и раз в 60 с.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshState() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        ax.stop()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🅿️"
        item.button?.toolTip = "PimpMyClaude"

        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Поставить…", action: #selector(install), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Снять…", action: #selector(uninstall), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Статус…", action: #selector(showStatus), keyEquivalent: "").target = self
        menu.addItem(.separator())
        for toggle in [autoAllowItem, minimizeMenuItem, blockQuitItem] {
            toggle.target = self
            menu.addItem(toggle)
        }
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
        updateToggleMarks()
    }

    // ---------------------------------------------------------------- статус

    @objc private func appActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == Patcher.claudeBundleID else { return }
        refreshState()
    }

    private func refreshState() {
        guard !busy else { return }
        guard let url = chosenClaude(askIfSeveral: false) else { show(state: .claudeNotFound); return }
        DispatchQueue.global(qos: .utility).async {
            let state = ClaudePatcher(appURL: url).state()
            DispatchQueue.main.async { self.show(state: state) }
        }
    }

    private func show(state: ClaudeState) {
        stateItem.title = state.menuTitle
        statusItem?.button?.toolTip = "PimpMyClaude — " + state.menuTitle
    }

    // ---------------------------------------------------------------- поиск Claude

    /// Решение 3: ищем по bundle id (Launch Services видит и ~/Applications). Копий несколько — спрашиваем.
    private func chosenClaude(askIfSeveral: Bool) -> URL? {
        let copies = Patcher.locateClaude()
        if copies.isEmpty { return nil }
        if let saved = UserDefaults.standard.string(forKey: Key.claudePath),
           let match = copies.first(where: { $0.path == saved }) { return match }
        if copies.count == 1 { return copies[0] }
        guard askIfSeveral else { return copies[0] }

        let alert = NSAlert()
        alert.messageText = "Какой Claude патчить?"
        alert.informativeText = "На Маке несколько копий Claude.app. Выбери ту, которой пользуешься."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
        copies.forEach { popup.addItem(withTitle: $0.path) }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Продолжить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let chosen = copies[max(0, popup.indexOfSelectedItem)]
        UserDefaults.standard.set(chosen.path, forKey: Key.claudePath)
        return chosen
    }

    // ---------------------------------------------------------------- Поставить / Снять / Статус

    @objc private func install() {
        guard !busy, let url = askForClaude() else { return }
        let alert = NSAlert()
        alert.messageText = "Поставить патч в Claude?"
        alert.informativeText = """
            Claude закроется и через несколько секунд откроется снова.
            Оригинальные app.asar и Info.plist уйдут в бэкап — «Снять» вернёт их обратно.
            После первой установки macOS один раз заново спросит разрешения (микрофон, экран).

            \(url.path)
            """
        alert.addButton(withTitle: "Поставить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        runOperation(title: "Поставить патч", appURL: url) { patcher, progress in
            switch try patcher.install(progress: progress) {
            case .alreadyInstalled(let version): return "Патч уже стоял — Claude \(version) не трогали."
            case .repaired(let version): return "Починил: хэш и подпись Claude \(version) снова сходятся."
            case .installed(let version): return "Готово. Патч стоит в Claude \(version)."
            }
        }
    }

    @objc private func uninstall() {
        guard !busy, let url = askForClaude() else { return }
        let alert = NSAlert()
        alert.messageText = "Снять патч?"
        alert.informativeText = """
            Вернём оригинальные app.asar и Info.plist из бэкапа и переподпишем Claude локальной подписью.
            Подпись Apple при этом не возвращается — настоящий откат это переустановка Claude с claude.ai/download.
            Claude закроется и откроется снова.

            \(url.path)
            """
        alert.addButton(withTitle: "Снять")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        runOperation(title: "Снять патч", appURL: url) { patcher, progress in
            try patcher.restore(progress: progress)
            return "Готово. Оригинальные файлы Claude на месте."
        }
    }

    @objc private func showStatus() {
        guard let url = chosenClaude(askIfSeveral: true) else { report(PatchError.claudeNotFound); return }
        let window = OperationWindow(title: "Статус")
        window.show()
        let patcher = ClaudePatcher(appURL: url)
        DispatchQueue.global(qos: .userInitiated).async {
            let state = patcher.state()
            let report = (try? patcher.fullStatus())?.report
            DispatchQueue.main.async {
                window.append(state.menuTitle)
                window.append("")
                window.append(report ?? "Подробности недоступны: app.asar не читается.")
                window.finish("")
                self.show(state: state)
            }
        }
    }

    private func askForClaude() -> URL? {
        if let url = chosenClaude(askIfSeveral: true) { return url }
        report(PatchError.claudeNotFound)
        return nil
    }

    /// Патч крутится в фоне, окно только пишет строки — меню-бар остаётся живым.
    private func runOperation(title: String, appURL: URL,
                              body: @escaping (ClaudePatcher, (String) -> Void) throws -> String) {
        busy = true
        let window = OperationWindow(title: title)
        window.show()
        let patcher = ClaudePatcher(appURL: appURL)
        DispatchQueue.global(qos: .userInitiated).async {
            let post: (String) -> Void = { line in DispatchQueue.main.async { window.append(line) } }
            do {
                let done = try body(patcher, post)
                DispatchQueue.main.async {
                    window.finish(done)
                    self.operationFinished()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let settings = Self.settingsAction(for: error)
                DispatchQueue.main.async {
                    window.finish("Не вышло. " + message, settings: settings)
                    self.operationFinished()
                }
            }
        }
    }

    private func operationFinished() {
        busy = false
        refreshState()
    }

    private static func settingsAction(for error: Error) -> (() -> Void)? {
        if case PatchError.needsAppManagement = error { return { SystemSettings.open(SystemSettings.appManagement) } }
        return nil
    }

    private func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Не вышло"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // ---------------------------------------------------------------- тумблеры

    private func applySettingsToAX() {
        let defaults = UserDefaults.standard
        ax.autoAllowEnabled = defaults.bool(forKey: Key.autoAllow)
        ax.minimizeMenuEnabled = defaults.bool(forKey: Key.minimizeMenu)
        ax.blockQuitEnabled = defaults.bool(forKey: Key.blockQuit)
    }

    private func updateToggleMarks() {
        let defaults = UserDefaults.standard
        autoAllowItem.state = defaults.bool(forKey: Key.autoAllow) ? .on : .off
        minimizeMenuItem.state = defaults.bool(forKey: Key.minimizeMenu) ? .on : .off
        blockQuitItem.state = defaults.bool(forKey: Key.blockQuit) ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func flip(_ key: String) -> Bool {
        let value = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        applySettingsToAX()
        updateToggleMarks()
        return value
    }

    @objc private func toggleAutoAllow() {
        if flip(Key.autoAllow) { warnIfNoAccessibility("Авто-Allow") }
    }

    @objc private func toggleMinimizeMenu() {
        if flip(Key.minimizeMenu) { warnIfNoAccessibility("Меню на кнопке «Свернуть»") }
    }

    @objc private func toggleBlockQuit() { _ = flip(Key.blockQuit) }

    private func warnIfNoAccessibility(_ feature: String) {
        guard !AXIsProcessTrusted() else { return }
        let alert = NSAlert()
        alert.messageText = "Нужен Универсальный доступ"
        alert.informativeText = "\(feature) работает через Универсальный доступ (Accessibility). "
            + "Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → включи PimpMyClaude."
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Потом")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { SystemSettings.open(SystemSettings.accessibility) }
    }

    // ---------------------------------------------------------------- автозапуск (решение 5)

    private func configureLoginItemOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.loginItemConfigured) else { updateToggleMarks(); return }
        // Dev-сборка из .build автозапуск не заводит — иначе в «Объектах входа» останется путь в .build.
        let path = Bundle.main.bundleURL.path
        let installed = path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        guard installed else { updateToggleMarks(); return }
        defaults.set(true, forKey: Key.loginItemConfigured)
        try? SMAppService.mainApp.register()
        updateToggleMarks()
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            report(error)
        }
        updateToggleMarks()
        if service.status == .requiresApproval {
            let alert = NSAlert()
            alert.messageText = "Осталось разрешить автозапуск"
            alert.informativeText = "Системные настройки → Основные → Объекты входа: включи PimpMyClaude."
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Потом")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                SystemSettings.open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            }
        }
    }
}
