import AppKit
import ApplicationServices

/// Окно первого запуска и пункта «Настроить разрешения…»: шаги по-русски, зелёная галка,
/// когда шаг закрыт, и кнопка «Поставить» в конце. Опрос раз в секунду — человек уходит
/// в Системные настройки и возвращается, окно должно обновиться само.
///
/// Шагов три, плюс нулевой: если приложение запущено не из «Программ», сперва предлагаем
/// себя туда скопировать — иначе автозапуск и выданные разрешения привязываются к пути
/// в «Загрузках» или .build и слетают при первом же переносе.
final class SetupWindow: NSObject, NSWindowDelegate {
    /// Ширина текстовой колонки: 640 окно − 24·2 поля − 24 колонка с номером − 12 отступ.
    fileprivate static let textWidth: CGFloat = 556
    fileprivate static let windowWidth: CGFloat = 640

    private let window: NSWindow
    private let onInstall: () -> Void
    private let stateText: () -> String
    private let patchInstalled: () -> Bool
    private let onClose: () -> Void

    private var moveRow: StepRow?
    private let accessRow: StepRow
    private let manageRow: StepRow
    private let notifyRow: StepRow
    private let stateLabel = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?
    private var retained: SetupWindow?
    private var notificationsAllowed: Bool?
    private var promptedAccessibility = false

    /// Приложение лежит в «Программах» — своих или системных?
    static var isInApplicationsFolder: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let mine = NSHomeDirectory() + "/Applications"
        return folder == "/Applications" || folder.hasPrefix("/Applications/")
            || folder == mine || folder.hasPrefix(mine + "/")
    }

    init(stateText: @escaping () -> String,
         patchInstalled: @escaping () -> Bool,
         onInstall: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.stateText = stateText
        self.patchInstalled = patchInstalled
        self.onInstall = onInstall
        self.onClose = onClose

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SetupWindow.windowWidth, height: 560),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        // Нулевого шага нет: если приложение не в «Программах», оно становится первым, остальные едут вниз.
        let hasMove = !SetupWindow.isInApplicationsFolder
        accessRow = StepRow(number: hasMove ? "2" : "1", title: "Универсальный доступ (Accessibility)")
        manageRow = StepRow(number: hasMove ? "3" : "2", title: "Управление приложениями")
        notifyRow = StepRow(number: hasMove ? "4" : "3", title: "Уведомления")
        super.init()

        window.title = "Настройка PimpMyClaude"
        window.delegate = self
        window.isReleasedWhenClosed = false

        let root = NSStackView(views: [])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18

        let title = NSTextField(labelWithString: "Что нужно, чтобы всё заработало")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        root.addArrangedSubview(title)

        let subtitle = SetupWindow.paragraph(
            "PimpMyClaude меняет окна Claude: узкие окна и поля, ручка над полем ввода, меню на "
            + "кнопке «Свернуть» с горячими клавишами, авто-Allow и блокировка ⌘Q. "
            + "Для этого macOS должна пустить его к Claude.")
        root.addArrangedSubview(subtitle)

        if hasMove {
            let row = StepRow(number: "1", title: "Скопировать в «Программы»")
            row.setText("Сейчас приложение лежит в \(Bundle.main.bundleURL.deletingLastPathComponent().path). "
                        + "Из «Загрузок» или временной папки разрешения и автозапуск привяжутся к этому пути "
                        + "и слетят, как только файл переедет. Скопирую в «Программы» и перезапущусь оттуда; старую копию потом можно удалить.")
            row.setPrimary(title: "Скопировать и перезапустить", target: self, action: #selector(moveToApplications))
            moveRow = row
            root.addArrangedSubview(row.view)
        }

        accessRow.setText("Нужен для авто-Allow, меню на кнопке «Свернуть» и его горячих клавиш. "
                          + "Блокировка ⌘Q работает и без него. macOS сейчас спросит сама; если окно не появилось — "
                          + "Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → включи PimpMyClaude.")
        accessRow.setPrimary(title: "Открыть настройки", target: self, action: #selector(openAccessibility))
        root.addArrangedSubview(accessRow.view)

        manageRow.setText("Отдельного окна тут нажимать не надо: macOS спросит сама, когда нажмёшь «Поставить» — "
                          + "PimpMyClaude меняет файлы внутри Claude.app. Ответь «Разрешить» — установка продолжится сама. "
                          + "Если промпт закрыли — включи PimpMyClaude в настройках руками.")
        manageRow.setPrimary(title: "Открыть настройки", target: self, action: #selector(openAppManagement))
        root.addArrangedSubview(manageRow.view)

        notifyRow.setText("Одно уведомление: Claude обновился, патч слетел — с кнопкой «Поставить снова». "
                          + "Больше ничего не шлём. Откажешься — ничего не сломается, статус всё равно виден в строке меню.")
        notifyRow.setPrimary(title: "Разрешить", target: self, action: #selector(askNotifications))
        root.addArrangedSubview(notifyRow.view)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: SetupWindow.windowWidth - 48).isActive = true
        root.addArrangedSubview(separator)

        stateLabel.font = .systemFont(ofSize: 12)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.preferredMaxLayoutWidth = SetupWindow.windowWidth - 48
        stateLabel.widthAnchor.constraint(equalToConstant: SetupWindow.windowWidth - 48).isActive = true
        root.addArrangedSubview(stateLabel)

        let install = NSButton(title: "Поставить", target: self, action: #selector(runInstall))
        install.bezelStyle = .rounded
        install.keyEquivalent = "\r"
        let close = NSButton(title: "Закрыть", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [install, spacer, close])
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: SetupWindow.windowWidth - 48).isActive = true
        root.addArrangedSubview(footer)

        let content = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: SetupWindow.windowWidth, height: content.fittingSize.height))
        window.center()
        retained = self // живём, пока окно на экране
    }

    // ---------------------------------------------------------------- показ и опрос

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        refreshNotifications()
        refresh()
        // Промпт macOS показываем один раз за открытие окна и только если доступа ещё нет.
        if moveRow == nil, !promptedAccessibility, !AXIsProcessTrusted() {
            promptedAccessibility = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        if let moveRow = moveRow, SetupWindow.isInApplicationsFolder {
            moveRow.setDone(true)
            moveRow.setText("Приложение уже в «Программах».")
        }
        let trusted = AXIsProcessTrusted()
        accessRow.setDone(trusted)
        if trusted { accessRow.setText("Доступ выдан — авто-Allow, меню и горячие клавиши работают.") }

        // У «Управления приложениями» API статуса нет: считаем шаг закрытым, когда патч встал —
        // значит, запись внутрь Claude.app прошла.
        let installed = patchInstalled()
        manageRow.setDone(installed)
        if installed { manageRow.setText("Уже сработало: патч стоит, значит записывать в Claude.app macOS даёт.") }

        notifyRow.setDone(notificationsAllowed == true)
        if notificationsAllowed == true {
            notifyRow.setText("Разрешено. Пришлём только «патч слетел».")
        } else if notificationsAllowed == false {
            notifyRow.setText("Уведомления запрещены — это нормально, ничего не сломается. "
                              + "Передумаешь: Системные настройки → Уведомления → PimpMyClaude.")
            notifyRow.setPrimary(title: "Открыть настройки", target: self, action: #selector(openNotifications))
        }
        stateLabel.stringValue = stateText()
        fitWindow()
    }

    /// Тексты шагов по ходу дела становятся короче — подтягиваем высоту, чтобы снизу не зияла пустота.
    private func fitWindow() {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let height = content.fittingSize.height
        guard abs(content.frame.height - height) > 1 else { return }
        window.setContentSize(NSSize(width: SetupWindow.windowWidth, height: height))
    }

    private func refreshNotifications() {
        Notifier.authorization { [weak self] value in
            self?.notificationsAllowed = value
            self?.refresh()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshNotifications()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        onClose()
        retained = nil
    }

    // ---------------------------------------------------------------- кнопки шагов

    @objc private func openAccessibility() { SystemSettings.open(SystemSettings.accessibility) }
    @objc private func openAppManagement() { SystemSettings.open(SystemSettings.appManagement) }
    @objc private func openNotifications() { SystemSettings.open(SystemSettings.notifications) }
    @objc private func closeWindow() { window.close() }

    @objc private func askNotifications() {
        Notifier.requestAuthorization { [weak self] granted in
            self?.notificationsAllowed = granted
            self?.refresh()
            // Спрашивать второй раз система не даст — отправляем в настройки.
            if !granted { self?.refreshNotifications() }
        }
    }

    @objc private func runInstall() { onInstall() }

    // ---------------------------------------------------------------- шаг 0: переезд в «Программы»

    @objc private func moveToApplications() {
        let name = Bundle.main.bundleURL.lastPathComponent
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(name)
        do {
            try copySelf(to: system)
            relaunch(at: system)
        } catch {
            let mine = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
            let alert = NSAlert()
            alert.messageText = "Не пускает в «Программы»"
            alert.informativeText = SetupWindow.message(error)
                + "\n\nОбычно так бывает, когда ты не администратор этого Мака. "
                + "Можно положить приложение в свою папку \(mine.path) — там прав хватит."
            alert.addButton(withTitle: "Положить в мою папку")
            alert.addButton(withTitle: "Отмена")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
                let target = mine.appendingPathComponent(name)
                try copySelf(to: target)
                relaunch(at: target)
            } catch {
                report(error)
            }
        }
    }

    private func copySelf(to target: URL) throws {
        let fm = FileManager.default
        let source = Bundle.main.bundleURL
        guard source.standardizedFileURL != target.standardizedFileURL else { return }
        if fm.fileExists(atPath: target.path) {
            let others = NSRunningApplication
                .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if others.contains(where: { $0.bundleURL?.standardizedFileURL == target.standardizedFileURL }) {
                throw SetupError.copyRunning(target.path)
            }
            // Старую копию не стираем насовсем — она уезжает в корзину, оттуда её можно вернуть.
            try fm.trashItem(at: target, resultingItemURL: nil)
        }
        try fm.copyItem(at: source, to: target)
    }

    private func relaunch(at target: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: target, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error { self?.report(error); return }
                NSApp.terminate(nil)
            }
        }
    }

    private func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Не вышло"
        alert.informativeText = SetupWindow.message(error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func paragraph(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.preferredMaxLayoutWidth = windowWidth - 48
        label.widthAnchor.constraint(equalToConstant: windowWidth - 48).isActive = true
        return label
    }
}

enum SetupError: LocalizedError {
    case copyRunning(String)

    var errorDescription: String? {
        switch self {
        case .copyRunning(let path):
            return "В «Программах» уже запущен \(path). Закрой его (значок в строке меню → «Выйти») и попробуй ещё раз."
        }
    }
}

/// Один шаг: номер слева (или зелёная галка, когда закрыт), заголовок, объяснение и кнопка.
private final class StepRow {
    let view: NSStackView
    private let number: String
    private let mark = NSTextField(labelWithString: "")
    private let text = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton()

    init(number: String, title: String) {
        self.number = number

        mark.font = .systemFont(ofSize: 15, weight: .semibold)
        mark.alignment = .center
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        text.translatesAutoresizingMaskIntoConstraints = false
        text.preferredMaxLayoutWidth = SetupWindow.textWidth
        text.widthAnchor.constraint(equalToConstant: SetupWindow.textWidth).isActive = true

        button.bezelStyle = .rounded
        button.isHidden = true

        let column = NSStackView(views: [titleLabel, text, button])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6

        view = NSStackView(views: [mark, column])
        view.orientation = .horizontal
        view.alignment = .top
        view.spacing = 12

        setDone(false)
    }

    func setText(_ value: String) {
        guard text.stringValue != value else { return }
        text.stringValue = value
    }

    func setPrimary(title: String, target: AnyObject, action: Selector) {
        button.title = title
        button.target = target
        button.action = action
        button.isHidden = false
    }

    /// Шаг закрыт: зелёная галка вместо номера, кнопка больше не нужна.
    func setDone(_ done: Bool) {
        mark.stringValue = done ? "✓" : number
        mark.textColor = done ? .systemGreen : .secondaryLabelColor
        button.isHidden = done || button.title.isEmpty
    }
}
