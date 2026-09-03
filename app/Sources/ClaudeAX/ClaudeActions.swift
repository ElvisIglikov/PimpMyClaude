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
    /// Последний набор автопокраски и его старт — из них «🔁 Ещё раз» (план WF10 п. 5).
    let autoPaintStore: AutoPaintStore

    /// Что это приложение применило последним — из этого делается «моя тема» (план п. 4).
    /// Сброс слоя обнуляет: «Как у Claude» + «Сохранить как мою тему…» сохранять нечего.
    private(set) var lastAppliedTheme: Theme?
    /// Автотемы по заголовку окна (план WF10 п. 6): автопокраска красит все окна разом и
    /// `lastAppliedTheme` не трогает — иначе «Сохранить как мою тему…» на одном окне предложило
    /// бы цвет соседнего. Окно, покрашенное набором, отдаёт свой цвет.
    private(set) var autoPaintedThemes: [String: Theme] = [:]
    private(set) var lastAppliedFont: Font?

    init(app: ClaudeApp, commands: CommandChannel,
         themes: [Theme] = ThemeCatalog.bundled, fonts: [Font] = FontCatalog.available,
         themeStore: ThemeStore = ThemeStore(), myThemes: MyThemesStore = MyThemesStore(),
         autoPaintStore: AutoPaintStore = AutoPaintStore()) {
        self.app = app
        self.commands = commands
        self.themes = themes
        self.fonts = fonts
        self.themeStore = themeStore
        self.myThemes = myThemes
        self.autoPaintStore = autoPaintStore
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

    /// «Сохранить как мою тему…»: пара из темы этого окна и последнего шрифта.
    /// Тема ни разу не выбиралась — сохранять нечего (меню покажет алерт).
    @discardableResult
    func saveMyTheme(name: String, window: AXUIElement? = nil) -> [MyTheme]? {
        guard let theme = themeToSave(window: window) else { return nil }
        return myThemes.add(name: name, theme: theme, font: lastAppliedFont)
    }

    /// Что предложит «Сохранить как мою тему…» (и каким именем): у автопокрашенного окна — его
    /// собственную автотему (план WF10 п. 6), у остальных — последнюю применённую этим
    /// приложением. Иначе на окне «Радуги» сохранялся бы цвет соседнего окна.
    func themeToSave(window: AXUIElement?) -> Theme? {
        let title = window.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        return autoPaintedThemes[title] ?? lastAppliedTheme
    }

    /// Галки в меню и «последнее применённое» — по слоям: слой `.keep` остаётся как был.
    private func remember(scope: String, title: String, theme: Layer<Theme>, font: Layer<Font>) {
        if scope == MenuModel.themeScopeAll {
            if !theme.isKeep {
                themeStore.setAllTheme(theme.value?.id)
                themeStore.clearWindowThemes()
                // Автотем на окнах больше нет: тему всем окнам задали руками.
                autoPaintedThemes.removeAll()
            }
            if !font.isKeep {
                themeStore.setAllFont(font.value?.id)
                themeStore.clearWindowFonts()
            }
        } else {
            if !theme.isKeep {
                themeStore.setWindowTheme(theme.value?.id, title: title)
                autoPaintedThemes[title] = nil // цвет окна выбрали руками — автотема устарела
            }
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

    // MARK: - автопокраска (план WF10)

    /// «🌈 Автопокраска»: все окна Claude на экране красятся гармонично по цветовому кругу —
    /// каждому окну своя тема обычной командой `theme` со `scope: "window"`, через очередь
    /// канала (600 мс на окно). Возвращает, сколько окон покрашено.
    /// Галки в подменю «Тема» автопокраска не ставит (план п. 4): выбранной темы у окна нет,
    /// у него сгенерированная.
    @discardableResult
    func autoPaint(preset: AutoPaintPreset) -> Int {
        paint(preset: preset, start: Double(Int.random(in: 0..<360)),
              scheme: AutoPaint.schemeIndex(for: preset))
    }

    /// «🔁 Ещё раз»: тот же набор И та же схема, старт на +37° (план п. 5) — иначе после
    /// «Случайно» это был бы уже другой набор, а не тот же, повёрнутый.
    /// Набора в памяти нет — берём первый.
    @discardableResult
    func autoPaintAgain() -> Int {
        let last = autoPaintStore.last
        let preset = last.flatMap { AutoPaint.preset(id: $0.preset) } ?? AutoPaint.presets[0]
        return paint(preset: preset, start: (last?.start ?? 0) + AutoPaint.againStep,
                     scheme: AutoPaint.schemeIndex(for: preset, repeating: last?.scheme ?? nil),
                     light: last?.light ?? nil)
    }

    /// «Как у Claude (все окна)»: сброс слоя темы всем окнам одной командой (`theme: null`,
    /// `scope: "all"`). Шрифт не трогаем — слои независимы.
    @discardableResult
    func autoPaintReset(window: AXUIElement? = nil) -> Bool {
        applyTheme(scope: MenuModel.themeScopeAll, theme: .reset, font: .keep, window: window)
    }

    private func paint(preset: AutoPaintPreset, start: Double, scheme index: Int?,
                       light repeated: Bool? = nil) -> Int {
        let windows = paintableWindows()
        let titles = windows.titles
        guard !titles.isEmpty else {
            onWarning?(MenuModel.autoPaintNoWindowsAlert)
            return 0
        }
        // Окна красятся по одному раз в 600 мс — молча это выглядит как зависшее меню.
        onWarning?(MenuModel.autoPaintStart(windows: windows.onScreen, unnamed: windows.unnamed))
        // Режим у набора свой; у «Случайно» — тот же, что в прошлый раз («Ещё раз» повторяет
        // набор целиком), а на первый раз — по памяти окон. После покраски галки сняты, и
        // сама память уже пуста — потому режим и ложится в AutoPaintStore.
        let light = preset.light ?? repeated ?? prefersLightWindows()
        let themes = AutoPaint.themes(preset: preset,
                                      scheme: AutoPaint.scheme(for: preset, index: index),
                                      count: titles.count, start: start, light: light)
        for (title, theme) in zip(titles, themes) {
            let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow, title: title,
                                                   theme: .set(theme), font: .keep)
            commands.write(action: "theme", fields: fields)
            // Галку в «Тема» снимаем: цвет у окна теперь сгенерированный, а старая отметка
            // показывала бы тему каталога, которой на окне уже нет (план п. 4).
            themeStore.setWindowTheme(nil, title: title)
            // А «Сохранить как мою тему…» на этом окне должно предложить его цвет (план п. 6).
            autoPaintedThemes[title] = theme
        }
        autoPaintStore.remember(preset: preset.id, start: start, scheme: index, light: light)
        return titles.count
    }

    /// Окна Claude на экране для покраски: заголовки слева направо, затем сверху вниз (порядок
    /// тот же, что у «Расставить»), и счётчики для HUD. Окно без AX-заголовка пропускаем:
    /// страница узнаёт окно только по нему, а пустой заголовок значит «окно в фокусе» —
    /// покрасились бы все в один цвет. Одинаковые заголовки схлопываются по той же причине:
    /// тема живёт на чате, и двум окнам одного чата достанется один цвет — про это HUD и говорит.
    private func paintableWindows() -> (titles: [String], onScreen: Int, unnamed: Int) {
        guard let pid = app.pid else { return ([], 0, 0) }
        let windows = ClaudeApp.onScreenFrames(pid: pid)
        guard !windows.isEmpty else { return ([], 0, 0) }
        var seen = Set<String>()
        var titles: [String] = []
        var unnamed = 0
        for index in ArrangeLayout.order(of: windows.map { $0.frame }) {
            let title = app.window(matching: windows[index].frame)
                .flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
            if MenuModel.isUnnamedChat(title) { unnamed += 1 }
            guard !title.isEmpty, seen.insert(title).inserted else { continue }
            titles.append(title)
        }
        // Про «одним цветом» говорим, только когда своего цвета кому-то и правда не досталось.
        return (titles, windows.count, titles.count < windows.count ? unnamed : 0)
    }

    /// «🎲 Случайно» красит в тон окнам: светлые сейчас или тёмные. Знаем мы об этом только по
    /// своей же памяти (`ThemeStore` — что это приложение применяло); ничего не применяли —
    /// считаем тёмными, как у Claude по умолчанию.
    private func prefersLightWindows() -> Bool {
        var known: [String: Bool] = [:]
        for theme in themes { known[theme.id] = theme.isLight }
        for my in myThemes.load() { known[my.id] = my.type == "light" }
        let ids = themeStore.windowThemeIDs + [themeStore.allThemeID].compactMap { $0 }
        let types = ids.compactMap { known[$0] }
        return types.filter { $0 }.count > types.filter { !$0 }.count
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
