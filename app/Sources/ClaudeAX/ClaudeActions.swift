import AppKit
import ApplicationServices

/// Слой команды «тема»: тема и шрифт живут отдельно (контракт п. 5 плана WF6).
/// `keep` — поля в команде нет (страница слой не трогает), `reset` — `null` (сброс слоя),
/// `set` — объект слоя.
enum Layer<Value> {
    case keep
    case reset
    case set(Value)

    var isKeep: Bool {
        if case .keep = self { return true }
        return false
    }

    /// Значение слоя или nil (сброс/не трогать) — из него же берётся id для галки в меню.
    var value: Value? {
        if case .set(let value) = self { return value }
        return nil
    }

    /// Поле команды: nil — поля в JSON нет вовсе.
    func commandValue(_ encode: (Value) -> CommandValue) -> CommandValue? {
        switch self {
        case .keep: return nil
        case .reset: return .null
        case .set(let value): return encode(value)
        }
    }
}

extension Layer: Equatable where Value: Equatable {}

/// Семь действий меню и хоткеев — порт `claude_minimize_menu.lua`.
/// Страничные (`collapse`, `expand`, `scroll`, `cashout`) уходят в command.json,
/// оконные (`newChat`, `arrange`, `show`) делаются нативно.
final class ClaudeActions {
    /// Фокус → команда: страница отвечает только когда `document.hasFocus()`.
    let focusDelay: TimeInterval = 0.1
    /// «Обкэшить» → ⌘N: лоадер опрашивает command.json раз в 500 мс (fs.watchFile interval),
    /// плюс IPC до страницы — ⌘N раньше 1,2 с открыл бы новый чат до того, как старый отложил ответ.
    let cashoutNewChatDelay: TimeInterval = 1.2

    private let app: ClaudeApp
    private let commands: CommandChannel
    /// Каталоги тем и шрифтов и последний выбор — для подменю в меню кнопки «Свернуть».
    let themes: [Theme]
    let fonts: [Font]
    let themeStore: ThemeStore
    let myThemes: MyThemesStore

    /// Что это приложение применило последним — из этого делается «моя тема» (план п. 4).
    /// Сброс слоя обнуляет: «Как у Claude» + «Сохранить как мою тему…» сохранять нечего.
    private(set) var lastAppliedTheme: Theme?
    private(set) var lastAppliedFont: Font?

    init(app: ClaudeApp, commands: CommandChannel,
         themes: [Theme] = ThemeCatalog.bundled, fonts: [Font] = FontCatalog.available,
         themeStore: ThemeStore = ThemeStore(), myThemes: MyThemesStore = MyThemesStore()) {
        self.app = app
        self.commands = commands
        self.themes = themes
        self.fonts = fonts
        self.themeStore = themeStore
        self.myThemes = myThemes
    }

    var lastCommand: String { commands.lastCommand }

    /// Окно, на которое действует хоткей: окно Claude в фокусе (хоткеи живут, только пока
    /// Claude впереди).
    func focusedWindow() -> AXUIElement? { app.focusedWindow() }

    func perform(_ command: ClaudeCommand, on window: AXUIElement?) {
        let target = window ?? focusedWindow()
        switch command {
        case .workflow: workflow(target)
        case .cashout: cashout(target)
        case .newChat: newChat(target)
        case .collapse: stage("collapse", target)
        case .expand: stage("expand", target)
        case .arrange: arrange()
        case .show: showAll(target)
        // «Прокрутить» адресована всем окнам сразу — фокус не нужен.
        case .scroll: commands.write(action: "scroll")
        }
    }

    // MARK: - страничные команды

    private func stage(_ action: String, _ window: AXUIElement?) {
        guard let window = window else { return }
        app.focus(window: window)
        after(focusDelay) { [weak self] in self?.commands.write(action: action) }
    }

    private func cashout(_ window: AXUIElement?) {
        guard let window = window else { return }
        app.focus(window: window)
        after(focusDelay) { [weak self] in
            guard let self = self else { return }
            // Заголовок нужен, чтобы страница поняла «это я»: окно «Open in new window»
            // (about:blank) может не считать себя в фокусе (грабли 03.09).
            let title = AX.string(window, kAXTitleAttribute) ?? ""
            self.commands.write(action: "cashout", extra: ["title": title])
            self.after(self.cashoutNewChatDelay) { self.newChat(window) }
        }
    }

    // MARK: - Workflow (решение 3 плана WF9)

    /// «🚀 Workflow»: комплект правил ложится в Application Support (путь к нему зашит в текст
    /// кикоффа), а сам кикофф уходит командой в поле ввода окна — страница его вставляет и НЕ
    /// отправляет. Окно адресуется AX-заголовком, как «Обкэшить»; фокус нужен до команды —
    /// вставка идёт в поле ввода, а оно принимает текст только у страницы в фокусе.
    /// Без доверия Accessibility окна нет: команда всё равно уходит с пустым заголовком —
    /// страница понимает его как «окно в фокусе».
    private func workflow(_ window: AXUIElement?) {
        WorkflowKit.install()
        guard let text = WorkflowKit.kickoff() else {
            // Комплекта нет вовсе (старый бандл) — говорим об этом, а не проглатываем клик.
            onWarning?(MenuModel.workflowKitMissingAlert)
            return
        }
        guard let window = window else {
            commands.write(action: "workflow", fields: ClaudeActions.workflowFields(title: "", text: text))
            return
        }
        app.focus(window: window)
        after(focusDelay) { [weak self] in
            let title = AX.string(window, kAXTitleAttribute) ?? ""
            self?.commands.write(action: "workflow",
                                 fields: ClaudeActions.workflowFields(title: title, text: text))
        }
    }

    /// Поля команды после id, action, at: scope, title, text (контракт п. 3 плана WF9).
    static func workflowFields(title: String, text: String) -> [(key: String, value: CommandValue)] {
        [(key: "scope", value: .string(MenuModel.themeScopeWindow)),
         (key: "title", value: .string(title)),
         (key: "text", value: .string(text))]
    }

    // MARK: - темы и шрифты

    /// Тема одного окна (`scope: "window"`) или всех сразу (`"all"`), слоями: тема и шрифт
    /// независимы. `.keep` — поля в команде нет, слой не трогаем; `.reset` — `null`, «Как у Claude»;
    /// `.set` — объект слоя. Палитра уходит в страницу целиком: файлов страница не читает
    /// (контракт п. 5 плана WF6, порядок полей id, action, at, scope, title, theme, font).
    /// Окно адресуется AX-заголовком, как «Обкэшить»; пустой заголовок страница понимает как
    /// «окно в фокусе» — тогда, как у «Обкэшить», сперва даём окну фокус и ждём focusDelay.
    @discardableResult
    func applyTheme(scope: String, theme: Layer<Theme> = .keep, font: Layer<Font> = .keep,
                    window: AXUIElement?) -> Bool {
        // Оба слоя «не трогать» — команде нечего делать.
        guard !theme.isKeep || !font.isKeep else { return false }
        let target = window ?? focusedWindow()
        let title = target.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        let send: () -> Bool = { [weak self] in
            guard let self = self else { return false }
            let fields = ClaudeActions.themeFields(scope: scope, title: title, theme: theme, font: font)
            guard self.commands.write(action: "theme", fields: fields) else { return false }
            self.remember(scope: scope, title: title, theme: theme, font: font)
            return true
        }
        if title.isEmpty, let target = target {
            app.focus(window: target)
            after(focusDelay) { _ = send() }
            return true
        }
        return send()
    }

    /// Поля команды после id, action, at: scope, title, preview, затем слои — тема, потом шрифт.
    /// Слоя `.keep` в JSON нет вовсе, `.reset` уходит как `null` (контракт п. 5 плана WF6).
    /// `preview` — только у предпросмотра (контракт п. 1 плана WF8): у закрепляющей команды
    /// поля нет вовсе, `true` — примерить слой не запоминая, `false` без слоёв — конец примерки.
    static func themeFields(scope: String, title: String, preview: Bool? = nil,
                            theme: Layer<Theme>,
                            font: Layer<Font>) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(scope)),
            (key: "title", value: .string(title)),
        ]
        if let preview = preview { fields.append((key: "preview", value: .bool(preview))) }
        if let value = theme.commandValue({ $0.commandValue }) { fields.append((key: "theme", value: value)) }
        if let value = font.commandValue({ $0.commandValue }) { fields.append((key: "font", value: value)) }
        return fields
    }

    /// Своя тема — одна команда с обоими слоями; без шрифта пара сбрасывает слой шрифта,
    /// чтобы применилось ровно то, что сохраняли.
    @discardableResult
    func apply(myTheme: MyTheme, scope: String, window: AXUIElement?) -> Bool {
        // Своя тема без шрифта шрифт не трогает: из «Всем окнам» иначе снялись бы шрифты всех окон.
        applyTheme(scope: scope, theme: .set(myTheme.theme),
                   font: myTheme.font.map { Layer.set($0) } ?? .keep, window: window)
    }

    /// «Сохранить как мою тему…»: пара из последней применённой темы и шрифта.
    /// Тема ни разу не выбиралась — сохранять нечего (меню покажет алерт).
    @discardableResult
    func saveMyTheme(name: String) -> [MyTheme]? {
        guard let theme = lastAppliedTheme else { return nil }
        return myThemes.add(name: name, theme: theme, font: lastAppliedFont)
    }

    /// Галки в меню и «последнее применённое» — по слоям: слой `.keep` остаётся как был.
    private func remember(scope: String, title: String, theme: Layer<Theme>, font: Layer<Font>) {
        if scope == MenuModel.themeScopeAll {
            if !theme.isKeep {
                themeStore.setAllTheme(theme.value?.id)
                themeStore.clearWindowThemes()
            }
            if !font.isKeep {
                themeStore.setAllFont(font.value?.id)
                themeStore.clearWindowFonts()
            }
        } else {
            if !theme.isKeep { themeStore.setWindowTheme(theme.value?.id, title: title) }
            if !font.isKeep { themeStore.setWindowFont(font.value?.id, title: title) }
        }
        if !theme.isKeep { lastAppliedTheme = theme.value }
        if !font.isKeep { lastAppliedFont = font.value }
    }

    // MARK: - предпросмотр (план WF8)

    /// Мышь ведут по подменю: окно красится сразу, но ничего не запоминает — ни страница
    /// (`preview: true`), ни это приложение (`themeStore`/`lastApplied…` не трогаем).
    /// `nil` — примерка сброса слоя («Как у Claude»). В команде ровно один слой.
    @discardableResult
    func previewTheme(_ theme: Theme?, window: AXUIElement?) -> Bool {
        sendPreview(true, theme: theme.map { Layer.set($0) } ?? .reset, font: .keep, window: window)
    }

    /// Своя тема примеряется парой, как и закрепляется: цвет + шрифт (без шрифта — только цвет).
    @discardableResult
    func preview(myTheme: MyTheme, window: AXUIElement?) -> Bool {
        sendPreview(true, theme: .set(myTheme.theme), font: myTheme.font.map { Layer.set($0) } ?? .keep, window: window)
    }

    /// То же для шрифта; `nil` — «Системный (как у Claude)».
    @discardableResult
    func previewFont(_ font: Font?, window: AXUIElement?) -> Bool {
        sendPreview(true, theme: .keep, font: font.map { Layer.set($0) } ?? .reset, window: window)
    }

    /// Конец предпросмотра: `preview: false` без слоёв — страница возвращает окну то, что
    /// лежит у неё в хранилище. Шлётся, когда меню закрылось без выбора.
    @discardableResult
    func endPreview(window: AXUIElement?) -> Bool {
        sendPreview(false, theme: .keep, font: .keep, window: window)
    }

    /// Предпросмотр всегда адресован одному окну (`scope: "window"`), фокуса не просит:
    /// пока открыто меню, окно Claude всё равно не впереди, а `focus()` закрыл бы само меню —
    /// страница узнаёт окно по заголовку, как в «Обкэшить».
    private func sendPreview(_ preview: Bool, theme: Layer<Theme>, font: Layer<Font>,
                             window: AXUIElement?) -> Bool {
        let target = window ?? focusedWindow()
        let title = target.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        // Без заголовка примерка не адресуется (фокуса у окна Claude нет, пока открыто меню),
        // а «конец примерки» мог бы снять живую тему у окна без ключа — не шлём ничего.
        guard !title.isEmpty else { return false }
        let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow, title: title,
                                               preview: preview, theme: theme, font: font)
        // Примерка идёт мимо очереди канала: мышь скользит по списку, ждать 600 мс нечего.
        return commands.write(action: "theme", fields: fields, priority: .preview)
    }

    // MARK: - оконные команды

    /// ⌘N — штатная клавиша самого Claude, посылаем её в окно (focus асинхронный, отсюда задержка).
    private func newChat(_ window: AXUIElement?) {
        if let window = window { app.focus(window: window) }
        after(focusDelay) { [weak self] in
            guard let key = KeySpec(mods: [.command], name: "n").keyCode else { return }
            self?.app.postKey(CGKeyCode(key), flags: .maskCommand)
        }
    }

    /// Ровная сетка по главному экрану. Порядок окон сохраняется (см. ArrangeLayout.order).
    /// Свёрнутые и спрятанные не трогаем; чужие приложения — тоже (в отличие от ElvisOS).
    func arrange() {
        let windows = app.visibleWindows()
        guard !windows.isEmpty, let area = Screens.mainUsableFrame else { return }
        let frames = windows.map { AX.frame($0) ?? .zero }
        let order = ArrangeLayout.order(of: frames)
        let cells = ArrangeLayout.frames(count: order.count, in: area)
        for (index, windowIndex) in order.enumerated() {
            let cell = cells[index]
            let window = windows[windowIndex]
            AX.set(window, kAXPositionAttribute, point: cell.origin)
            AX.set(window, kAXSizeAttribute, size: cell.size)
        }
        onWindowsMoved?()
    }

    /// Все окна Claude вперёд, потом фокус обратно тому, из которого пришли.
    func showAll(_ window: AXUIElement?) {
        guard let running = app.running() else { return }
        running.activate(options: [.activateAllWindows])
        for candidate in app.visibleWindows() { AX.perform(candidate, kAXRaiseAction) }
        guard let window = window else { return }
        // activate/raise асинхронные — даём им тик, прежде чем забрать фокус назад.
        after(focusDelay) { [weak self] in self?.app.focus(window: window) }
    }

    /// Окна переехали: кэш прямоугольников кнопки «Свернуть» протух.
    var onWindowsMoved: (() -> Void)?

    /// Короткая плашка на экран (HUD) — ставит ClaudeAXController. Пока единственный повод:
    /// в сборке нет комплекта workflow-kit.
    var onWarning: ((String) -> Void)?

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}
