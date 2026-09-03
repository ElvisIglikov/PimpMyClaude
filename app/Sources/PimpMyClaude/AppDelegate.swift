import AppKit
import ApplicationServices
import ClaudeAX
import Patcher
import ServiceManagement
import UserNotifications

/// Меню-бар без окна (LSUIElement): статус патча, три кнопки установки и тумблеры фишек.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private enum Key {
        static let autoAllow = "autoAllowEnabled"
        static let minimizeMenu = "minimizeMenuEnabled"
        static let blockQuit = "blockQuitEnabled"
        static let loginItemConfigured = "loginItemConfigured"
        static let claudePath = "claudeAppPath"
        static let setupDone = "setupWindowSeen"
    }

    private let ax = ClaudeAXController()
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var busy = false
    private var setup: SetupWindow?
    private var lastState: ClaudeState?
    private var lostNotified = false

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
        Notifier.registerCategory(delegate: self)
        configureLoginItemOnFirstRun()
        refreshState()
        // `open -a PimpMyClaude.app --args --status` — окно статуса без похода в меню (нужно на гейте).
        if CommandLine.arguments.contains("--status") { showStatus() }
        // Первый запуск: пошаговое окно разрешений. Закрыли — больше не всплываем,
        // вернуться можно пунктом «Настроить разрешения…».
        if !UserDefaults.standard.bool(forKey: Key.setupDone) { showSetup() }

        // Решение 4: проверка при активации Claude и раз в 60 с.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        let poll = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refreshState() }
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
    }

    /// Повторный запуск из Finder/Launchpad: окна в доке нет, покажем окно настройки — иначе
    /// человеку кажется, что приложение не запускается.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showSetup() }
        return true
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
        menu.delegate = self
        menu.autoenablesItems = false // тумблеры гасим руками: без Accessibility их включать бессмысленно
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Поставить…", action: #selector(install), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Снять…", action: #selector(uninstall), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Статус…", action: #selector(showStatus), keyEquivalent: "").target = self
        menu.addItem(.separator())
        for toggle in [autoAllowItem, minimizeMenuItem, blockQuitItem, loginItem] {
            toggle.target = self
            menu.addItem(toggle)
        }
        blockQuitItem.toolTip = "⌘Q не закрывает Claude, пока его окно впереди. Работает и без Accessibility."
        loginItem.toolTip = "Автозапуск при входе в систему; включается сам, когда приложение лежит в «Программах»."
        menu.addItem(.separator())
        menu.addItem(withTitle: "Настроить разрешения…", action: #selector(showSetup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "История авто-Allow…", action: #selector(showAutoAllowHistory), keyEquivalent: "").target = self
        menu.addItem(withTitle: "О программе", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
        updateToggleMarks()
    }

    /// Меню открывают редко — обновляем прямо перед показом, чтобы галки и статус были свежие.
    func menuWillOpen(_ menu: NSMenu) {
        updateToggleMarks()
        refreshState()
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
        applyStatusIcon(state)
        notifyIfPatchLost(state)
        lastState = state
    }

    /// Значок в строке меню по статусу: стоит — галка, слетел — красный «!»,
    /// не стоит — пустой кружок, Claude не найден — крестик. Нет SF Symbols — рисуем текстом.
    private func applyStatusIcon(_ state: ClaudeState) {
        guard let button = statusItem?.button else { return }
        let symbol: String, fallback: String, alarm: Bool
        switch state {
        case .installed: (symbol, fallback, alarm) = ("checkmark.circle", "✓", false)
        case .lost: (symbol, fallback, alarm) = ("exclamationmark.triangle.fill", "!", true)
        case .notInstalled: (symbol, fallback, alarm) = ("circle.dashed", "○", false)
        case .claudeNotFound: (symbol, fallback, alarm) = ("xmark.circle", "✗", false)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard var image = NSImage(systemSymbolName: symbol, accessibilityDescription: state.menuTitle)?
            .withSymbolConfiguration(config) else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = fallback
            return
        }
        // «Слетел» — единственное состояние, где надо что-то делать: красим в красный,
        // остальные значки шаблонные и подстраиваются под светлую/тёмную строку меню.
        if alarm, let red = image.withSymbolConfiguration(config.applying(.init(paletteColors: [.systemRed]))) {
            image = red
            image.isTemplate = false
        } else {
            image.isTemplate = true
        }
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    /// Решение 4: одно уведомление «патч слетел» с кнопкой «Поставить снова»,
    /// повторов нет, пока патч не вернулся на место.
    private func notifyIfPatchLost(_ state: ClaudeState) {
        if case .lost(let version, let reason) = state {
            guard !lostNotified else { return }
            // Флаг взводится только когда баннер реально отправлен: без разрешения на уведомления
            // попробуем снова на следующей проверке (человек мог разрешить их в окне настройки).
            Notifier.postPatchLost("Claude \(version): \(reason). Нажми «Поставить снова» — это полминуты.") { [weak self] sent in
                if sent { self?.lostNotified = true }
            }
            return
        }
        if lostNotified {
            lostNotified = false
            Notifier.clearPatchLost()
        }
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
        guard !busy else { return }
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

    // ---------------------------------------------------------------- первый запуск, история, о программе

    /// Пошаговое окно разрешений: первый запуск и пункт меню. Второй раз не плодим — поднимаем открытое.
    @objc private func showSetup() {
        if let setup = setup {
            setup.show()
            return
        }
        let window = SetupWindow(
            stateText: { [weak self] in self?.stateItem.title ?? "" },
            patchInstalled: { [weak self] in self?.lastState?.isInstalled ?? false },
            onInstall: { [weak self] in self?.install() },
            onClose: { [weak self] in
                UserDefaults.standard.set(true, forKey: Key.setupDone)
                self?.setup = nil
            })
        setup = window
        window.show()
    }

    @objc private func showAutoAllowHistory() {
        let window = OperationWindow(title: "История авто-Allow")
        window.show()
        let history = ax.autoAllowHistory()
        if history.isEmpty {
            window.append("Пока пусто: авто-Allow ещё ничего не нажимал.")
            window.append("Он сам жмёт кнопки «Allow…» в диалогах Claude — кроме заголовков из списка исключений.")
        } else {
            for line in history { window.append(line) }
        }
        window.append("")
        window.append("Исключения: " + (ax.blockedHeadings.isEmpty ? "нет" : ax.blockedHeadings.joined(separator: ", ")))
        window.append("Диагностика: " + ax.statusText)
        window.finish("")
    }

    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let alert = NSAlert()
        alert.messageText = "PimpMyClaude \(version) (\(build))"
        alert.informativeText = """
            Прокачка Claude Desktop: узкие окна и поля, ручка над полем ввода, меню на кнопке «Свернуть» \
            с горячими клавишами, авто-Allow и блокировка ⌘Q. Без Hammerspoon и Node.

            \(Bundle.main.bundleURL.path)
            Elvis Iglikov
            """
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // ---------------------------------------------------------------- уведомления

    /// Баннер показываем, даже когда наше приложение впереди.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Кнопка «Поставить снова» (и клик по самому баннеру) — это обычная операция «Поставить».
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        if action == Notifier.installAction || action == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async { [weak self] in self?.install() }
        }
        completionHandler()
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

        // Без Универсального доступа живым остаётся только блок ⌘Q (Carbon-хоткеи доверия не просят),
        // поэтому два верхних тумблера гасим и прямо в названии пишем, чего не хватает.
        let trusted = ax.isAccessibilityTrusted || AXIsProcessTrusted()
        let needsAX = "Включи PimpMyClaude в Универсальном доступе: пункт «Настроить разрешения…»"
        autoAllowItem.isEnabled = trusted
        autoAllowItem.title = trusted ? "Авто-Allow" : "Авто-Allow — нужен Accessibility"
        autoAllowItem.toolTip = trusted ? "Сам жмёт «Allow…» в диалогах Claude." : needsAX
        minimizeMenuItem.isEnabled = trusted
        minimizeMenuItem.title = trusted ? "Меню на кнопке" : "Меню на кнопке — нужен Accessibility"
        // Хоткеи меню живут отдельно от тумблера: он гасит само меню на жёлтой кнопке, клавиши остаются.
        minimizeMenuItem.toolTip = trusted
            ? "Меню на жёлтой кнопке окна. Горячие клавиши (⌘⌥↑ ↓ A S D) от него не зависят."
            : needsAX
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
        guard SetupWindow.isInApplicationsFolder else { updateToggleMarks(); return }
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
            if alert.runModal() == .alertFirstButtonReturn { SystemSettings.open(SystemSettings.loginItems) }
        }
    }
}
