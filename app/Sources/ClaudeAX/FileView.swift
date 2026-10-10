import AppKit
import WebKit

/// Просмотр файла поверх окна чата (WF103; #7939, #7938, #7964): окно Пимпа без рамки ровно в
/// рамку окна чата — тот же размер и то же место, сверху одна полоса 28 pt цвета фона
/// темы окна — «← Вернуть» слева, «в галерею» и «в браузер» справа; больше ничего. Страница
/// Claude HTML со скриптами показать не может (CSP claude.ai), поэтому окно своё: WKWebView грузит
/// `file://` с доступом к папке проекта — скрипты, cdnjs, соседние картинки работают. Окно Claude
/// не трогается вовсе, и «Вернуть» возвращает ровно туда, где был.
///
/// Всё — на главной. `presents == false` (тесты) — окно не строится и не показывается, живёт
/// только состояние: что показано, счётчики, закрытие.
public final class FileView: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    /// Что сейчас показано.
    struct Shown: Equatable {
        let path: String
        let chat: String?
        /// Рамка окна чата (перевёрнутые координаты) — по ней «Вернуть» ищет окно Claude.
        let frame: CGRect?
    }

    static let barHeight: CGFloat = 28
    static let buttonHeight: CGFloat = 22
    static let fontSize: CGFloat = 12
    /// Нейтральный тёмно-серый графит — полоса, когда страница фона не прислала.
    static let fallbackBackground = "262628"
    static let escapeKeyCode: UInt16 = 53
    /// Отпускание Esc не пришло (редко: клавишу отпустили вне приложения) — Claude всё равно вперёд.
    static let escapeUpWait: TimeInterval = 0.6
    static let escapeHoldLimit: TimeInterval = 5

    /// «Вернуть»: Claude вперёд, его окно с этой рамкой — переднее (nil — просто активация).
    var onReturn: (CGRect?) -> Void = { _ in }
    /// «в галерею»: путь и чат.
    var toGallery: (String, String?) -> Void = { _, _ in }
    /// «в браузер».
    var toBrowser: (String) -> Void = { _ in }
    /// false — окно не строится (тесты).
    var presents = true

    private(set) var current: Shown?
    private var shownCount = 0
    private var closedCount = 0
    private let counters = NSLock()
    public var shown: Int { counters.lock(); defer { counters.unlock() }; return shownCount }
    public var closed: Int { counters.lock(); defer { counters.unlock() }; return closedCount }

    private var window: FileViewWindow?
    private var webView: WKWebView?
    private var bar: NSView?
    private var buttons: [NSButton] = []
    private var keyMonitor: Any?
    private var savedMenu: NSMenu?
    /// Esc нажат, ждём отпускания: только после него Claude вперёд (Esc в чате Claude
    /// останавливает агента).
    private var escapePending = false
    private var escapeFrame: CGRect?
    private var escapeGeneration = 0
    private var loadedFile: URL?
    private var loadedAccess: URL?

    public override init() {
        super.init()
        // Ушёл без «Вернуть» (⌘Tab, клик в Claude на другом мониторе) — просмотр закрывается,
        // чтобы окно не всплыло при следующей активации Пимпа.
        NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive(_:)),
                                               name: NSApplication.didResignActiveNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - чистые части (их гоняют тесты)

    /// Рамка окна просмотра — ровно рамка окна чата (слово Элвиса 27.09.2026, #7964: «по размеру быть
    /// строго как окошко клауда, к которому он принадлежит, и располагаться в том же самом месте»).
    /// `frame` — перевёрнутые координаты страницы, ответ — координаты AppKit.
    static func windowFrame(for frame: CGRect) -> CGRect { Screens.flip(rect: frame) }

    /// Доступ WKWebView на чтение: папка проекта чата, если файл в ней и она не закрытая; иначе
    /// папка файла; закрытая и она — только сам файл (`isPrivate`: дом, его предки, `~/Library`).
    static func readAccess(file: String, cwd: String?, home: String) -> URL {
        let path = URL(fileURLWithPath: file).standardizedFileURL.path
        if let cwd = cwd.map({ URL(fileURLWithPath: $0).standardizedFileURL.path }),
           !isPrivate(cwd, home: home), path.hasPrefix(cwd.hasSuffix("/") ? cwd : cwd + "/") {
            return URL(fileURLWithPath: cwd, isDirectory: true)
        }
        let folder = (path as NSString).deletingLastPathComponent
        if !isPrivate(folder, home: home) { return URL(fileURLWithPath: folder, isDirectory: true) }
        return URL(fileURLWithPath: path)
    }

    /// Папка, которую нельзя открывать на чтение целиком: `/`, предки домашней, сама домашняя, `~/Library`
    /// и всё в ней (перенесено из встроенного Viewer, WF104).
    private static func isPrivate(_ folder: String, home: String) -> Bool {
        let folder = folder.count > 1 && folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        if folder.isEmpty || folder == "/" || folder == home || home.hasPrefix(folder + "/") { return true }
        let library = home + "/Library"
        return folder == library || folder.hasPrefix(library + "/")
    }

    /// Надписи тёмные — фон светлый (относительная яркость sRGB больше 0,5); мусор — графит.
    static func prefersDarkText(bg: String?) -> Bool {
        let (r, g, b) = rgb(HtmlChromeOpener.color(bg) ?? fallbackBackground)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) > 0.5
    }

    static func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let value = Int(hex, radix: 16) ?? 0
        return (CGFloat((value >> 16) & 0xff) / 255, CGFloat((value >> 8) & 0xff) / 255, CGFloat(value & 0xff) / 255)
    }

    /// Окно Claude, которое вернуть вперёд: больше всего пересекается с рамкой чата.
    static func nearest(_ frame: CGRect, among frames: [CGRect?]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, candidate) in frames.enumerated() {
            guard let candidate = candidate else { continue }
            let common = candidate.intersection(frame)
            guard !common.isNull, common.width > 0, common.height > 0 else { continue }
            let area = common.width * common.height
            if best == nil || area > best!.area { best = (index, area) }
        }
        return best?.index
    }

    // MARK: - показ

    /// Принятый `view`: файл в окне поверх экрана чата. Окно уже открыто — новый файл в нём же и
    /// на экран новой рамки.
    func show(_ request: HtmlChromeOpener.Request, cwd: String?) {
        escapePending = false
        current = Shown(path: request.path, chat: request.chat, frame: request.frame)
        counters.lock()
        shownCount += 1
        counters.unlock()
        guard presents else { return }
        let window = ensureWindow()
        paint(bg: request.bg)
        if let frame = request.frame { window.setFrame(Self.windowFrame(for: frame), display: true) }
        let file = URL(fileURLWithPath: request.path)
        let access = Self.readAccess(file: request.path, cwd: cwd, home: NSHomeDirectory())
        loadedFile = file
        loadedAccess = access
        webView?.loadFileURL(file, allowingReadAccessTo: access)
        // Клавиши (стрелки, пробел) — сразу файлу, без клика внутрь.
        if let web = webView { window.makeFirstResponder(web) }
        // Кооперативный `activate()` на macOS 14+ не срабатывает (DECISIONS:56) — как у меню кнопки.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        MinimizeMenu.awaitActive(isActive: { NSApp.isActive }, pump: MinimizeMenu.pumpEvent,
                                 now: { Date.timeIntervalSinceReferenceDate })
        window.makeKeyAndOrderFront(nil)
    }

    /// Закрыть: окно прячется, страница выгружается; `returning` — Claude вперёд.
    func close(returning: Bool) {
        guard let shown = current else { return }
        current = nil
        counters.lock()
        closedCount += 1
        counters.unlock()
        restoreMenu()
        window?.orderOut(nil)
        loadedFile = nil
        loadedAccess = nil
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        if returning { onReturn(shown.frame) }
    }

    @objc private func appResignedActive(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.close(returning: false) }
            return
        }
        close(returning: false)
    }

    @objc func returnTapped(_ sender: Any?) { close(returning: true) }

    @objc func galleryTapped(_ sender: Any?) {
        guard let shown = current else { return }
        close(returning: false)
        toGallery(shown.path, shown.chat)
    }

    @objc func browserTapped(_ sender: Any?) {
        guard let shown = current else { return }
        close(returning: false)
        toBrowser(shown.path)
    }

    // MARK: - Esc

    /// Esc в окне просмотра — до WKWebView: закрыть сразу, а Claude вперёд — только по
    /// отпусканию (его `keyUp` глотаем), иначе отпускание Esc долетело бы до чата.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == Self.escapeKeyCode else { return event }
        if event.type == .keyDown {
            if escapePending { return nil }
            guard let shown = current, let window = window, event.window === window else { return event }
            escapePending = true
            escapeFrame = shown.frame
            escapeGeneration += 1
            let generation = escapeGeneration
            close(returning: false)
            awaitEscapeUp(generation: generation, left: Self.escapeHoldLimit)
            return nil
        }
        if event.type == .keyUp, escapePending {
            finishEscape()
            return nil
        }
        return event
    }

    /// Отпускание не пришло за `escapeUpWait` — Claude вперёд, только когда Esc правда отпущен
    /// (держат дольше — автоповтор долетел бы до чата), но не позже `escapeHoldLimit`.
    private func awaitEscapeUp(generation: Int, left: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.escapeUpWait) { [weak self] in
            guard let self = self, self.escapePending, self.escapeGeneration == generation else { return }
            let held = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(Self.escapeKeyCode))
            if held, left > Self.escapeUpWait { return self.awaitEscapeUp(generation: generation, left: left - Self.escapeUpWait) }
            self.finishEscape()
        }
    }

    private func finishEscape() {
        escapePending = false
        onReturn(escapeFrame)
        escapeFrame = nil
    }

    // MARK: - окно

    private func ensureWindow() -> FileViewWindow {
        if let window = window { return window }
        let configuration = WKWebViewConfiguration()
        // Ни одного script-handler; `window.open` без жеста не гоняет браузер и не крадёт фокус.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let window = FileViewWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                    styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        content.autoresizesSubviews = true
        let height = content.bounds.height
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: content.bounds.width, height: height - Self.barHeight),
                            configuration: configuration)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.uiDelegate = self
        let bar = NSView(frame: NSRect(x: 0, y: height - Self.barHeight, width: content.bounds.width,
                                       height: Self.barHeight))
        bar.wantsLayer = true
        bar.autoresizingMask = [.width, .minYMargin]
        let back = button("← Вернуть", action: #selector(returnTapped(_:)))
        let browser = button("в браузер", action: #selector(browserTapped(_:)))
        let gallery = button("в галерею", action: #selector(galleryTapped(_:)))
        let top = (Self.barHeight - Self.buttonHeight) / 2
        back.setFrameOrigin(NSPoint(x: 8, y: top))
        back.autoresizingMask = [.maxXMargin]
        browser.setFrameOrigin(NSPoint(x: bar.bounds.width - 8 - browser.frame.width, y: top))
        browser.autoresizingMask = [.minXMargin]
        gallery.setFrameOrigin(NSPoint(x: browser.frame.minX - 4 - gallery.frame.width, y: top))
        gallery.autoresizingMask = [.minXMargin]
        for item in [back, gallery, browser] { bar.addSubview(item) }
        content.addSubview(web)
        content.addSubview(bar)
        window.contentView = content
        self.window = window
        self.webView = web
        self.bar = bar
        self.buttons = [back, gallery, browser]
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        return window
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: Self.fontSize)
        button.sizeToFit()
        button.setFrameSize(NSSize(width: button.frame.width + 12, height: Self.buttonHeight))
        return button
    }

    private func paint(bg: String?) {
        let (r, g, b) = Self.rgb(HtmlChromeOpener.color(bg) ?? Self.fallbackBackground)
        let background = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        let text = Self.prefersDarkText(bg: bg) ? NSColor(white: 0.1, alpha: 0.9) : NSColor(white: 0.95, alpha: 0.9)
        window?.backgroundColor = background
        bar?.layer?.backgroundColor = background.cgColor
        for button in buttons {
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .foregroundColor: text, .font: NSFont.systemFont(ofSize: Self.fontSize)])
        }
    }

    // MARK: - меню, пока окно ключевое (своё «Правка»: ⌘C/⌘V/⌘A работают в странице)

    public func windowDidBecomeKey(_ notification: Notification) {
        for item in FileView.menu.items.flatMap({ $0.submenu?.items ?? [] })
        where item.action == #selector(returnTapped(_:)) { item.target = self }
        guard NSApp.mainMenu !== FileView.menu else { return }
        savedMenu = NSApp.mainMenu
        NSApp.mainMenu = FileView.menu
    }

    public func windowDidResignKey(_ notification: Notification) {
        restoreMenu()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        close(returning: true)
        return false
    }

    private func restoreMenu() {
        // `NSApp` пуст, пока приложения нет (тесты).
        guard let app = NSApp, app.mainMenu === FileView.menu else { return }
        app.mainMenu = savedMenu
        savedMenu = nil
    }

    /// Скрытое меню: приложение — accessory, главного меню нет, и ⌘C/⌘V/⌘A до WKWebView не
    /// дошли бы. «Close ⌘W» — «Вернуть». Quit нет — ⌘Q Пимп не закрывает.
    static let menu: NSMenu = {
        let main = NSMenu()
        main.addItem(NSMenuItem())
        let file = NSMenuItem()
        main.addItem(file)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(FileView.returnTapped(_:)), keyEquivalent: "w")
        file.submenu = fileMenu
        let holder = NSMenuItem()
        main.addItem(holder)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        holder.submenu = edit
        return main
    }()

    // MARK: - навигация (файл — в окне, ссылки наружу — в браузер)

    static func opensExternally(_ url: URL, type: WKNavigationType) -> Bool {
        type == .linkActivated && ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let file = loadedFile, let access = loadedAccess { webView.loadFileURL(file, allowingReadAccessTo: access) }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        let web = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        // Only an explicit link opens the browser; scripts, forms and redirects stay cancelled.
        if web && (action.targetFrame == nil || action.targetFrame?.isMainFrame == true) {
            if Self.opensExternally(url, type: action.navigationType) { NSWorkspace.shared.open(url) }
            return decisionHandler(.cancel)
        }
        if action.targetFrame == nil { return decisionHandler(.cancel) }
        decisionHandler(.allow)
    }

    /// `window.open` и `target=_blank`: сайт — в браузер по умолчанию, остальное — никуда.
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, Self.opensExternally(url, type: action.navigationType) {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}

/// Окно без рамки ключевым не становится — просмотру это нужно (образец — `AnchorWindow`).
final class FileViewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
