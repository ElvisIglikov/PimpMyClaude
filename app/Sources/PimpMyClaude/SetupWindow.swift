import AppKit
import ApplicationServices
import ClaudeAX

/// Окно первого запуска и пункта «Настроить разрешения…»: шаги по-русски, зелёная галка,
/// когда шаг закрыт, и кнопка «Пропатчить Claude» в конце. Опрос раз в секунду — человек уходит
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
    private let kontekstRow: StepRow
    private let kontekst: () -> KontekstInstall
    private let onKontekst: () -> Void
    private let staleHint = SetupWindow.paragraph(AccessWizard.staleRowHint)
    private let stateLabel = NSTextField(wrappingLabelWithString: "")
    private let installButton = NSButton(title: "Пропатчить Claude", target: nil, action: nil)
    private let closeButton = NSButton(title: "Закрыть", target: nil, action: nil)
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

    /// Строка про Рика (WF216): на новой установке он уже встал сам — говорим, где он и что с ним делать.
    static func rickLine(_ folder: URL) -> String {
        "Рик уже стоит в \(NSString(string: folder.path).abbreviatingWithTildeInPath) — открой эту папку в Claude Code, "
            + "это главный чат: он ведёт остальные проекты и Workflow. С чего начать — в её README."
    }

    init(rickFolder: URL? = nil,
         kontekst: @escaping () -> KontekstInstall = { .ok },
         onKontekst: @escaping () -> Void = {},
         stateText: @escaping () -> String,
         patchInstalled: @escaping () -> Bool,
         onInstall: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.kontekst = kontekst
        self.onKontekst = onKontekst
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
        kontekstRow = StepRow(number: hasMove ? "5" : "4", title: "Сторож контекста")
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
            "PimpMyClaude меняет окна Claude: узкие окна и поля, ручка над полем ввода, цвета и шрифт окон, "
            + "горячие клавиши, обратный отсчёт, Авто-Allow и блокировка ⌘Q. "
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

        accessRow.setText("Нужен для горячих клавиш PMP в Claude (⌥⌘N, ⌥⌘A, ⌥⌘S…). "
                          + "Обратный отсчёт, Авто-Allow и блокировка ⌘Q работают и без него. macOS сейчас спросит сама; если окно не появилось — "
                          + "Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → включи PimpMyClaude.")
        accessRow.setPrimary(title: "Открыть настройки", target: self, action: #selector(openAccessibility))
        root.addArrangedSubview(accessRow.view)
        root.addArrangedSubview(staleHint)

        manageRow.setText("PimpMyClaude меняет файлы внутри Claude.app. Окна «Разрешить» у этого права нет: когда нажмёшь "
                          + "«Пропатчить Claude», PimpMyClaude сам откроет эту страницу настроек и покажет рядом, что нажать, — "
                          + "включи там PimpMyClaude, установка продолжится сама. Можно включить и заранее.")
        manageRow.setPrimary(title: "Открыть настройки", target: self, action: #selector(openAppManagement))
        root.addArrangedSubview(manageRow.view)

        notifyRow.setText("Уведомления редкие: слетел патч, скачалось обновление Claude, что-то не так с окном Claude, "
                          + "значок PMP не виден или Мак перегрелся. Откажешься — ничего не сломается, "
                          + "статус всё равно виден в строке меню.")
        notifyRow.setPrimary(title: "Разрешить", target: self, action: #selector(askNotifications))
        root.addArrangedSubview(notifyRow.view)

        kontekstRow.setText(KontekstInstall.why)
        kontekstRow.setPrimary(title: "Поставить сторож", target: self, action: #selector(runKontekst))
        root.addArrangedSubview(kontekstRow.view)

        if let rickFolder = rickFolder {
            root.addArrangedSubview(SetupWindow.paragraph(SetupWindow.rickLine(rickFolder)))
        }

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

        // Предупреждение про окно связки ключей (WF210, #9382) и «код открыт» со ссылкой (WF234: код открыт 10.10.2026).
        root.addArrangedSubview(SetupWindow.keychainParagraph())

        let install = installButton
        install.target = self
        install.action = #selector(runInstall)
        install.bezelStyle = .rounded
        install.keyEquivalent = "\r"
        let close = closeButton
        close.target = self
        close.action = #selector(closeWindow)
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
        staleHint.isHidden = trusted
        if trusted { accessRow.setText("Доступ выдан — горячие клавиши работают.") }

        // У «Управления приложениями» API статуса нет: считаем шаг закрытым, когда патч встал —
        // значит, запись внутрь Claude.app прошла.
        let installed = patchInstalled()
        manageRow.setDone(installed)
        if installed { manageRow.setText("Уже сработало: патч стоит, значит записывать в Claude.app macOS даёт.") }
        // #10287 (слово Элвиса 19.10: зелёная «Пропатчить» при «Патч стоит» путает): патч стоит — главная «Закрыть»,
        // перепатч — обычной кнопкой «Пропатчить заново»; патча нет — главная снова «Пропатчить Claude».
        installButton.title = installed ? "Пропатчить заново" : "Пропатчить Claude"
        installButton.keyEquivalent = installed ? "" : "\r"
        closeButton.keyEquivalent = installed ? "\r" : ""

        notifyRow.setDone(notificationsAllowed == true)
        if notificationsAllowed == true {
            notifyRow.setText("Разрешено. Пишем только о важном: патч, обновление Claude, окно Claude, значок PMP, нагрев Мака.")
        } else if notificationsAllowed == false {
            notifyRow.setText("Уведомления запрещены — это нормально, ничего не сломается. "
                              + "Передумаешь: Системные настройки → Уведомления → PimpMyClaude.")
            notifyRow.setPrimary(title: "Открыть настройки", target: self, action: #selector(openNotifications))
        }
        let guardState = kontekst()
        kontekstRow.setDone(guardState == .ok)
        switch guardState {
        case .ok: kontekstRow.setText("Стоит. Работай в чате проекта в терминале, помощников зови для коротких дел. "
                                      + "Проект закончили — закрой терминал.")
        case .missing: kontekstRow.setText(KontekstInstall.why)
        case .running: kontekstRow.setText("Ставлю сторож…")
        case .failed(let why): kontekstRow.setText("Сторож не встал: \(why)")
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
    @objc private func runKontekst() { onKontekst() }

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
            alert.informativeText = error.humanText
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

    private func report(_ error: Error) { Alerts.failure(error) }

    /// Абзац про связку ключей и в конце — «Код открыт.» ссылкой на исходники (нажимается: поле выделяемое).
    private static func keychainParagraph() -> NSTextField {
        let label = paragraph(PimpPanelText.keychainNote)
        let font = NSFont.systemFont(ofSize: 12)
        let word = PimpPanelText.openSourceWord
        let text = NSMutableAttributedString(string: PimpPanelText.keychainNote + " ",
                                             attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        var link: [NSAttributedString.Key: Any] = [.font: font, .underlineStyle: NSUnderlineStyle.single.rawValue]
        if let url = URL(string: PimpPanelText.openSourceURL) { link[.link] = url }
        text.append(NSAttributedString(string: word.prefix(1).uppercased() + word.dropFirst(), attributes: link))
        text.append(NSAttributedString(string: ".", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        label.attributedStringValue = text
        label.allowsEditingTextAttributes = true
        label.isSelectable = true
        return label
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
