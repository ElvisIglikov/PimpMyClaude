import AppKit

/// Окно «Поставить / Снять / Статус»: журнал шагов, спиннер и человеческий текст ошибки.
/// Работа идёт в фоне, окно только показывает строки — UI не блокируется.
final class OperationWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let textView = NSTextView()
    private let spinner = NSProgressIndicator()
    private let settingsButton = NSButton()
    private let closeButton = NSButton()
    private var onSettings: (() -> Void)?
    private var retained: OperationWindow?

    init(title: String) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered,
                          defer: false)
        super.init()
        window.title = title
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 380))
        content.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: NSRect(x: 16, y: 56, width: 588, height: 308))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.frame = NSRect(origin: .zero, size: scroll.contentSize)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        content.addSubview(scroll)

        spinner.frame = NSRect(x: 16, y: 20, width: 18, height: 18)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.autoresizingMask = [.maxXMargin]
        spinner.startAnimation(nil)
        content.addSubview(spinner)

        closeButton.frame = NSRect(x: 508, y: 14, width: 96, height: 30)
        closeButton.title = "Закрыть"
        closeButton.bezelStyle = .rounded
        closeButton.autoresizingMask = [.minXMargin]
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.keyEquivalent = "\r"
        content.addSubview(closeButton)

        settingsButton.frame = NSRect(x: 300, y: 14, width: 200, height: 30)
        settingsButton.title = "Открыть настройки"
        settingsButton.bezelStyle = .rounded
        settingsButton.autoresizingMask = [.minXMargin]
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.isHidden = true
        content.addSubview(settingsButton)

        window.contentView = content
        retained = self // живём, пока окно на экране
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func append(_ line: String) {
        assert(Thread.isMainThread)
        textView.string += textView.string.isEmpty ? line : "\n" + line
        textView.scrollToEndOfDocument(nil)
    }

    /// Работа кончилась: гасим спиннер и, если нужно, показываем кнопку «Открыть настройки».
    func finish(_ line: String, settings: (() -> Void)? = nil) {
        if !line.isEmpty {
            append("")
            append(line)
        }
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        onSettings = settings
        settingsButton.isHidden = settings == nil
    }

    @objc private func close() { window.close() }

    @objc private func openSettings() { onSettings?() }

    func windowWillClose(_ notification: Notification) { retained = nil }
}

/// Панели «Конфиденциальность и безопасность», куда шлём человека за разрешениями.
enum SystemSettings {
    static let appManagement = "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
    static let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
