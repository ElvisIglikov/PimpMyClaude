import AppKit
import ApplicationServices

/// Слой команды «тема»: тема, шрифт, размер и рамка живут отдельно (контракт п. 5 плана WF6,
/// п. 1 плана WF12).
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

/// Куда идёт «Обкэшить» (план WF37, часть B1): главное окно обкэшивается на месте (команда,
/// потом ⌘N), а вынесенный в окно чат рождает НОВОЕ окно рядом — ⌘N из попапа исполняет
/// главное окно Claude, и до WF37 «Обкэшить» в попапе сбивал чат Элвиса в главном окне (#5575).
enum CashoutRoute: Equatable {
    case main
    /// Попап: `chat` — id его чата, если страница сама назвала его в круге probe; nil —
    /// адресуем заголовком, как до WF37.
    case popout(chat: String?)
}

/// Семь действий меню и хоткеев — порт `claude_minimize_menu.lua`.
/// Страничные (`collapse`, `expand`, `scroll`, `cashout`) уходят в command.json,
/// оконные (`newChat`, `arrange`, `show`) делаются нативно.
final class ClaudeActions {
    /// Фокус → команда: страница отвечает только когда `document.hasFocus()`.
    let focusDelay: TimeInterval = 0.1
    /// «Обкэшить» → ⌘N: лоадер опрашивает command.json раз в 500 мс (fs.watchFile interval),
    /// плюс IPC до страницы — ⌘N раньше 1,2 с открыл бы новый чат до того, как старый отложил ответ.
    let cashoutNewChatDelay: TimeInterval = 1.2
    /// «Новое окно» → ⌘N: команда должна доехать до страницы раньше, чем ⌘N уведёт окно
    /// на `/epitaxy` — иначе странице нечего будет запоминать (куда возвращаться).
    let newWindowKeyDelay: TimeInterval = 0.8

    private let app: ClaudeApp
    private let commands: CommandChannel
    /// Каталоги тем и шрифтов и последний выбор — для подменю в меню кнопки «Свернуть».
    let themes: [Theme]
    let fonts: [Font]
    let themeStore: ThemeStore
    let myThemes: MyThemesStore
    /// Последний набор автопокраски и его старт — из них «🔁 Ещё раз» (план WF10 п. 5).
    let autoPaintStore: AutoPaintStore
    /// Состояние живых цветов (план WF18): тумблер, режим, скорость, режим света и точка
    /// отсчёта круга.
    let liveColorsStore: LiveColorsStore
    /// Стенные часы: `epoch` живых цветов считается в тех же миллисекундах, что `Date.now()`
    /// страницы. Подставляются в тестах.
    var clock: () -> Date = Date.init
    /// Темы окон на диске (план WF35): зеркало закрепляющих команд `theme`. Живьём вешает
    /// `ClaudeAXController`; nil — зеркала нет вовсе (в тестах и в сборке без него), и ни один
    /// файл в `Application Support` не трогается.
    var windowThemes: WindowThemeStore?
    /// Зеркало записано — повод спросить страницы (решение 3 плана WF35): без него файл
    /// догонял бы правду только зеркалом. Вешает `ClaudeAXController` на `ChatProbe.noteMirror`.
    var onThemeRecorded: (() -> Void)?

    /// Что это приложение применило последним — из этого делается «моя тема» (план п. 4).
    /// Сброс слоя обнуляет: «Как у Claude» + «Сохранить как мою тему…» сохранять нечего.
    private(set) var lastAppliedTheme: Theme?
    /// Автотемы по заголовку окна (план WF10 п. 6): автопокраска красит все окна разом и
    /// `lastAppliedTheme` не трогает — иначе «Сохранить как мою тему…» на одном окне предложило
    /// бы цвет соседнего. Окно, покрашенное набором, отдаёт свой цвет.
    private(set) var autoPaintedThemes: [String: Theme] = [:]
    private(set) var lastAppliedFont: Font?
    /// Размер копится по половинам: «Размер ответов ▸ 16», потом «Размер вопросов ▸ 14» —
    /// в «мою тему» обязаны попасть обе (страница слой склеивает так же).
    private(set) var lastAppliedSize: Size?
    /// Тумблер рамки: nil — в этот запуск её не трогали.
    private(set) var lastAppliedFrame: Bool?

    init(app: ClaudeApp, commands: CommandChannel,
         themes: [Theme] = ThemeCatalog.bundled, fonts: [Font] = FontCatalog.available,
         themeStore: ThemeStore = ThemeStore(), myThemes: MyThemesStore = MyThemesStore(),
         autoPaintStore: AutoPaintStore = AutoPaintStore(),
         liveColorsStore: LiveColorsStore = LiveColorsStore()) {
        self.app = app
        self.commands = commands
        self.themes = themes
        self.fonts = fonts
        self.themeStore = themeStore
        self.myThemes = myThemes
        self.autoPaintStore = autoPaintStore
        self.liveColorsStore = liveColorsStore
    }

    var lastCommand: String { commands.lastCommand }

    /// Окно, на которое действует хоткей: окно Claude в фокусе (хоткеи живут, только пока
    /// Claude впереди).
    func focusedWindow() -> AXUIElement? { app.focusedWindow() }

    func perform(_ command: ClaudeCommand, on window: AXUIElement?) {
        noteUserCommand()
        let target = window ?? focusedWindow()
        switch command {
        case .workflow: workflow(target)
        case .cashout: cashout(target)
        case .newChat: newChat(target)
        case .newWindow: newWindow(target)
        case .popoutWindow: popoutWindow(target)
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
            switch ClaudeActions.cashoutRoute(title: title,
                                              isMainTitle: self.isMainWindowTitle(title),
                                              knownChat: self.chatForTitle(title)) {
            case .main:
                // Как и было по смыслу, только адрес точнее: путь страницы главного окна
                // (`match`) не даст команде уйти веером безымянным попапам (критик Б1 WF15).
                // Домашний экран (пути чата нет) адресуется путём `/epitaxy`: заголовком
                // «Claude» команду взял бы и безымянный попап (проверка WF37, находка 4).
                self.commands.write(action: "cashout",
                                    fields: ClaudeActions.cashoutFields(
                                        title: title, match: self.mainWindowMatch() ?? ChatProbe.homePath))
                self.after(self.cashoutNewChatDelay) { self.newChat(window) }
            case .popout(let chat):
                // ⌘N из попапа исполняет ГЛАВНОЕ окно — вместо него рождаем новое окно рядом
                // и просим страницу перенести отложенный ответ туда (план WF37 B1, #5575).
                self.commands.write(action: "cashout",
                                    fields: ClaudeActions.cashoutFields(title: title, chat: chat))
                self.after(self.cashoutNewChatDelay) { self.cashoutNewWindow(from: window, chat: chat) }
            }
        }
    }

    /// Развилка «Обкэшить» чистой функцией: окон и AX тут нет, поэтому её гоняют тесты
    /// (критик, важно 3 плана WF37). Верим ТОЛЬКО резолверу главного окна: заглушка «Claude»
    /// сама по себе главным окном не делает — её носит и безымянный попап (#5534), а у
    /// главного окна с названным чатом заголовок и вовсе имя чата (критик, блокер 3).
    static func cashoutRoute(title: String, isMainTitle: Bool, knownChat: String?) -> CashoutRoute {
        guard !isMainTitle else { return .main }
        return .popout(chat: knownChat)
    }

    /// «Обкэшить» из попапа: новое окно рядом тем же путём, что «🪟 Новое окно ▸ проект» —
    /// имя чата по проекту, слои и авто-цвет, запись в `projects.json`. Проекта не знаем
    /// (чат неизвестен или его нет в индексе) — «Здесь же», но всё равно с переносом.
    /// Точка ставится сама (`popoutOrigin` от рамки попапа — уступ от окна, где нажали).
    private func cashoutNewWindow(from window: AXUIElement, chat: String?) {
        let project = chat.flatMap { projectForChat($0) }
        if let project = project { onProjectUsed?(project) }
        newWindow(window, project: project, transfer: true)
    }

    /// Поля команды после id, action, at: scope, title, match?, chat? (контракт части B плана
    /// WF37, эталоны `tests/fixtures/cashout/cashout-*.json`). Главному окну уходит `match`
    /// (домашний экран — путь `/epitaxy`), попапу — `chat`, и никогда наоборот.
    static func cashoutFields(title: String, match: String? = nil,
                              chat: String? = nil) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(MenuModel.themeScopeWindow)),
            (key: "title", value: .string(title)),
        ]
        if let match = match { fields.append((key: "match", value: .string(match))) }
        if let chat = chat { fields.append((key: "chat", value: .string(chat))) }
        return fields
    }

    /// Это главное окно Claude? Живьём вешает `ClaudeAXController` тем же резолвером, что
    /// и цели покраски (`ProjectPaint.windowKey(forTitle:) == mainKey`): у главного окна
    /// заголовок бывает и заглушкой «Claude», и настоящим именем чата, и различить их
    /// по одному заголовку нельзя. Без контроллера остаётся правило до WF37 — заглушка
    /// и пустой заголовок значат главное окно.
    var isMainWindowTitle: (String) -> Bool = { ClaudeActions.isMainWindowTitle($0) }

    static func isMainWindowTitle(_ title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || clean == ProjectPaint.mainWindowTitle
    }

    /// Чат окна по AX-заголовку — карта probe (план WF29). Живьём вешает контроллер;
    /// карта несвежая или тумблер «🗂 Цвет по проекту» выключен — nil, и попап адресуется
    /// заголовком, как до WF37.
    var chatForTitle: (String) -> String? = { _ in nil }
    /// Проект чата: папка из индекса Claude Code. Живьём вешает контроллер; nil — папки
    /// не знаем, и новое окно откроется «Здесь же».
    var projectForChat: (String) -> Project? = { _ in nil }

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

    // MARK: - новое окно (план WF13)

    /// «🪟 Новое окно»: новый чат открывает штатный ⌘N (синтетический keydown страница
    /// игнорирует — микро-разведка П2), всё остальное делает страница по команде `new-window`:
    /// ждёт `/epitaxy`, проверяет, что композер пуст, вставляет первое сообщение, отправляет
    /// и выносит созданный чат отдельным окном. Порядок здесь важен: сперва фокус и команда
    /// (страница должна успеть запомнить, где стояло главное окно), и только потом ⌘N.
    /// Окно адресуется AX-заголовком, как «Обкэшить»; пустой заголовок страница понимает
    /// как «окно в фокусе».
    /// `transfer` (план WF37 B1) ставит только ветка «Обкэшить»: страница по нему штампует
    /// отложенный ответ донора на НОВЫЙ чат. ⌥⌘N, «▸ проект», «Здесь же» и канал «Пимп»
    /// поля не пишут никогда.
    private func newWindow(_ window: AXUIElement?, project: Project? = nil,
                           origin fixed: (x: Int, y: Int)? = nil, transfer: Bool = false) {
        // Точку могли задать снаружи (место «x,y» канала «Пимп», план WF36) — тогда окно
        // родится там же, где его просили, и двигать его потом не придётся.
        let origin = fixed ?? ClaudeActions.popoutOrigin(near: window.flatMap { AX.frame($0) })
        // Адресуем ГЛАВНОЕ окно, на каком бы окне ни нажали (дополнение 05.09 к плану WF19):
        // с попапа команда уходила с его заголовком, и её никто не исполнял. Пути не знаем —
        // адресуем заголовком, как раньше.
        let match = mainWindowMatch()
        // Работа идёт до 40 с — молчащая кнопка выглядит сломанной (критик п. 20).
        onNotice?(MenuModel.newWindowNotice, MenuModel.newWindowNoticeSeconds)
        // Папка и имя чата считаются здесь, а не на странице (критик В4 плана WF16): на диске
        // лежат ВСЕ сессии, а сайдбар показывает только хвост. Папки нет — оба поля пустые,
        // и страница ведёт себя ровно как в WF13.
        let folder = project?.folder.standardizedFileURL.path ?? ""
        let name = project.map { chatName($0) } ?? ""
        // Первое сообщение — оно же авто-заголовок чата: с папкой это имя проекта, без папки
        // прежнее «Привет» (решение 4 плана WF16). Ни команд, ни путей: работает авто-Allow.
        let text = name.isEmpty ? MenuModel.newWindowText : name
        let send: (String) -> Void = { [weak self] title in
            guard let self = self else { return }
            let layers = project.map {
                ClaudeActions.newWindowLayers(project: self.projectView($0),
                                              window: self.windowView(title: title),
                                              autoColor: self.autoProjectColor(for: $0))
            } ?? ProjectSettings()
            self.lastNewWindowLayers = !layers.isEmpty
            self.commands.write(action: ClaudeCommand.newWindow.rawValue,
                                fields: ClaudeActions.newWindowFields(title: title, match: match,
                                                                      x: origin.x, y: origin.y,
                                                                      text: text, folder: folder, name: name,
                                                                      transfer: transfer ? true : nil,
                                                                      theme: layers.theme, font: layers.font,
                                                                      size: layers.size, frame: layers.frame))
            self.after(self.newWindowKeyDelay) { self.newChat(window) }
        }
        guard let window = window else {
            send("")
            return
        }
        app.focus(window: window)
        after(focusDelay) { send(AX.string(window, kAXTitleAttribute) ?? "") }
    }

    /// «🪟 Новое окно ▸ PimpMyClaude» (план WF16): то же самое, но чат рождается в папке
    /// проекта, зовётся его именем и открывается уже в нужном цвете. Пункт меню зовёт этот
    /// метод мимо `perform` — отметку «была команда из меню» ставим сами, иначе фоновая
    /// покраска по проекту не замолчала бы на свои 2 с.
    func newWindow(in project: Project, on window: AXUIElement?,
                   origin: (x: Int, y: Int)? = nil) {
        noteUserCommand()
        // Папку открыли — она самая свежая в своём списке (план WF36, WF30 ч. 2). Точка одна
        // на оба пути: и клик по пункту меню, и запрос канала «Пимп» идут сюда.
        onProjectUsed?(project)
        newWindow(window ?? focusedWindow(), project: project, origin: origin)
    }

    /// Чем красить новое окно (вопрос 2 макета WF16, ответ Элвиса — «1»): вид проекта из
    /// `.pimpmyclaude.json`, а пока его нет — авто-цвет по имени папки (план WF36 п. 4),
    /// и только если нет и его — вид окна, из которого нажали. Пусто везде — слоёв в команде
    /// не будет вовсе, окно откроется как у Claude.
    ///
    /// Авто-цвет сильнее вида окна нарочно: без него окно рождалось цветом соседнего чата и
    /// перекрашивалось в свой только через такты, когда `ProjectPaint` доберётся до него
    /// через probe. Остальные слои (шрифт, размер, рамка) как были — от окна-источника.
    static func newWindowLayers(project: ProjectSettings?, window: ProjectSettings,
                                autoColor: Theme? = nil) -> ProjectSettings {
        if let project = project, !project.isEmpty { return project }
        guard let auto = autoColor else { return window }
        return ProjectSettings(name: window.name, theme: .set(auto), font: window.font,
                               size: window.size, frame: window.frame)
    }

    /// Авто-цвет проекта для нового окна — ровно на тех же двух условиях, на которых красит
    /// папки `ProjectPaint` (`ProjectPaint.swift:169,217`): включён тумблер «🗂 Цвет по
    /// проекту» и не задан вид «всем окнам». Иначе цвет в команде спорил бы с тем, что
    /// приложение красит дальше.
    private func autoProjectColor(for project: Project) -> Theme? {
        guard isProjectColorOn(), !hasAllWindowsView else { return nil }
        return AutoPaint.projectTheme(folderName: project.folder.lastPathComponent)
    }

    /// Тумблер «🗂 Цвет по проекту». Живьём вешает `ClaudeAXController`; без него авто-цвета
    /// нет вовсе — как было до WF36.
    var isProjectColorOn: () -> Bool = { false }
    /// Папку открыли: `ProjectsStore` запоминает её как свежую. Живьём вешает контроллер.
    var onProjectUsed: ((Project) -> Void)?
    /// Ушли ли слои с последней командой «новое окно» — поле `layers` ответа канала «Пимп».
    private(set) var lastNewWindowLayers = false

    /// Вид окна, каким его помнит приложение: галки меню, а у окна после «Раскрасить по кругу» —
    /// его сгенерированная тема. Нужен «🪟 Новому окну ▸» у проекта без своего вида (план WF16).
    func windowView(title: String) -> ProjectSettings {
        ProjectPaint.view(title: title, themeStore: themeStore, themes: themes, fonts: fonts,
                          myThemes: myThemes.load(), autoPainted: autoPaintedTheme(title: title))
    }

    /// Уникальное имя чата для нового окна в папке проекта. Живьём ставит `ClaudeAXController`
    /// (заголовки всех чатов знает `ProjectIndex`); без него имя = имя папки.
    var chatName: (Project) -> String = { $0.name }
    /// Вид проекта из `.pimpmyclaude.json`; nil — своего вида у проекта нет.
    var projectView: (Project) -> ProjectSettings? = { _ in nil }

    /// «🪟 В отдельное окно»: текущий чат главного окна выносится в окно одним `openPopout`
    /// на странице — ни нового чата, ни первого сообщения, ни ожиданий. Он же честная
    /// деградация «Нового окна»: чат создан, а окно не открылось — этот пункт доделает.
    private func popoutWindow(_ window: AXUIElement?) {
        let origin = ClaudeActions.popoutOrigin(near: window.flatMap { AX.frame($0) })
        // Как и «Новое окно», адресуется главному окну: с попапа выносить нечего, а команда
        // с его заголовком раньше просто пропадала (дополнение 05.09 к плану WF19).
        let match = mainWindowMatch()
        let send: (String) -> Void = { [weak self] title in
            self?.commands.write(action: ClaudeCommand.popoutWindow.rawValue,
                                 fields: ClaudeActions.popoutWindowFields(title: title, match: match,
                                                                          x: origin.x, y: origin.y))
        }
        guard let window = window else {
            send("")
            return
        }
        app.focus(window: window)
        after(focusDelay) { send(AX.string(window, kAXTitleAttribute) ?? "") }
    }

    /// Поля команды после id, action, at: scope, title, match, x, y, text, folder, name, затем
    /// слои — тема, шрифт, размер, рамка (контракт п. 1 плана WF13, расширен решением 1 плана
    /// WF16 и адресацией `match` — дополнение 05.09 к плану WF19).
    /// `x`/`y` — числа, а не строки (`write(action:extra:)` сюда не годится: он сортирует ключи
    /// и делает всё строками), страница проверяет их `Number.isFinite`.
    /// `folder` и `name` есть ВСЕГДА: пустая строка = «не трогать», и страница ведёт себя ровно
    /// как в WF13. Слои — по правилам команды `theme`: `.keep` в JSON нет вовсе, `.reset` — null.
    /// `match` — путь страницы главного окна, как у команды `theme`: поля нет — адресуем
    /// заголовком, как раньше.
    /// `transfer` — необязательное поле ветки «Обкэшить» (план WF37): стоит ПОСЛЕ `name` и
    /// ПЕРЕД слоями, значение только `true`; у остальных путей поля нет вовсе.
    static func newWindowFields(title: String, match: String? = nil, x: Int, y: Int, text: String,
                                folder: String = "", name: String = "", transfer: Bool? = nil,
                                theme: Layer<Theme> = .keep, font: Layer<Font> = .keep,
                                size: Layer<Size> = .keep,
                                frame: Layer<Bool> = .keep) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(MenuModel.themeScopeWindow)),
            (key: "title", value: .string(title)),
        ]
        if let match = match { fields.append((key: "match", value: .string(match))) }
        fields += [(key: "x", value: .number(x)),
                   (key: "y", value: .number(y)),
                   (key: "text", value: .string(text)),
                   (key: "folder", value: .string(folder)),
                   (key: "name", value: .string(name))]
        if let transfer = transfer { fields.append((key: "transfer", value: .bool(transfer))) }
        return fields + layerFields(theme: theme, font: font, size: SizeLayer(size), frame: frame)
    }

    /// То же без первого сообщения: scope, title, match, x, y (решение Элвиса 04.09).
    /// `chat` и `name` (план WF41) идут ПОСЛЕ `y` и только у «Вернуть эти чаты»: они —
    /// ГРУЗ команды, чей разговор вынести, а не адрес (адрес у неё всегда `match`).
    static func popoutWindowFields(title: String, match: String? = nil, x: Int, y: Int,
                                   chat: String? = nil,
                                   name: String? = nil) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(MenuModel.themeScopeWindow)),
            (key: "title", value: .string(title)),
        ]
        if let match = match { fields.append((key: "match", value: .string(match))) }
        fields += [(key: "x", value: .number(x)), (key: "y", value: .number(y))]
        if let chat = chat { fields.append((key: "chat", value: .string(chat))) }
        if let name = name { fields.append((key: "name", value: .string(name))) }
        return fields
    }

    /// «↩︎ Вернуть эти чаты» (план WF41): закрытый разговор выносит отдельным окном ГЛАВНОЕ
    /// окно — оно одно умеет `openPopout`. Адресуем только путём (`match`): заголовок здесь
    /// не нужен, а поле `chat` для страницы значит «эта страница и есть тот чат» (WF29) —
    /// адресом ему быть нельзя, закрытый чат не взял бы команду вовсе.
    /// Имя шлём всегда: у названного чата заголовок окна берётся из него.
    func popoutChat(chat: String, name: String, origin: (x: Int, y: Int)) {
        commands.write(action: ClaudeCommand.popoutWindow.rawValue,
                       fields: ClaudeActions.popoutWindowFields(title: "", match: mainWindowMatch(),
                                                                x: origin.x, y: origin.y,
                                                                chat: chat, name: name))
    }

    /// Путь страницы ГЛАВНОГО окна (`/epitaxy/local_…`) для поля `match`. «Новое окно» и
    /// «В отдельное окно» исполняет только главное окно, а нажимают их с любого: с попапа
    /// команда уходила с его заголовком и молчала (гейт WF16, 05.09 — «ничего не произошло»).
    /// Читаем ту же диагностику лоадера, что `ProjectIndex`; страниц claude.ai оказалось
    /// несколько или ни одной — nil, и адресация остаётся прежней, по заголовку.
    /// Замыкание — чтобы `ClaudeAXController` мог подставить сюда свой `ProjectIndex.mainWindow()`
    /// (он умеет разбирать и случай двух страниц) и чтобы тесты не читали живой диск.
    var mainWindowMatch: () -> String? = { ClaudeActions.mainWindowMatch() }

    static func mainWindowMatch(statusURL: URL = CommandChannel.directory
                                    .appendingPathComponent(ProjectIndex.statusFileName)) -> String? {
        let pages = ProjectIndex.pages(try? Data(contentsOf: statusURL))
        guard pages.count == 1 else { return nil }
        return pages.first?.match
    }

    /// Размер окна popout, по которому считается обрезка по экрану (у Claude оно примерно такое).
    static let popoutWindowSize = CGSize(width: 900, height: 700)
    /// Новое окно ставим уступом от окна под кнопкой — чтобы не легло ровно на него.
    static let popoutWindowOffset: CGFloat = 40
    /// Окна под кнопкой нет (меню-бар приложения, окно без AX-рамки) — ставим от угла экрана.
    static let popoutWindowFallback = (x: 120, y: 120)

    /// Куда поставить новое окно: угол окна под кнопкой + 40/40 в точках **Quartz** (начало —
    /// левый верхний угол главного экрана, y вниз) — ровно те же координаты, что у Electron
    /// в `initialPosition`. Координаты AppKit (снизу вверх) брать нельзя: окно уедет за экран.
    /// Обрезаем по рабочей области главного экрана так, чтобы окно влезло целиком.
    static func popoutOrigin(near frame: CGRect?,
                             area: CGRect? = Screens.mainUsableFrame) -> (x: Int, y: Int) {
        guard let frame = frame else { return popoutWindowFallback }
        var x = frame.origin.x + popoutWindowOffset
        var y = frame.origin.y + popoutWindowOffset
        if let area = area {
            x = min(max(x, area.minX), max(area.minX, area.maxX - popoutWindowSize.width))
            y = min(max(y, area.minY), max(area.minY, area.maxY - popoutWindowSize.height))
        }
        return (Int(x.rounded()), Int(y.rounded()))
    }

    // MARK: - темы и шрифты

    /// Тема одного окна (`scope: "window"`) или всех сразу (`"all"`), слоями: тема, шрифт,
    /// размер и рамка независимы. `.keep` — поля в команде нет, слой не трогаем; `.reset` —
    /// `null`, «Как у Claude»; `.set` — значение слоя. Палитра уходит в страницу целиком:
    /// файлов страница не читает (контракт п. 1 плана WF12, порядок полей
    /// id, action, at, scope, title, preview, theme, font, size, frame).
    /// Окно адресуется AX-заголовком, как «Обкэшить»; пустой заголовок страница понимает как
    /// «окно в фокусе» — тогда, как у «Обкэшить», сперва даём окну фокус и ждём focusDelay.
    @discardableResult
    func applyTheme(scope: String, theme: Layer<Theme> = .keep, font: Layer<Font> = .keep,
                    size: SizeLayer = .keep, frame: Layer<Bool> = .keep,
                    window: AXUIElement?) -> Bool {
        // Все слои «не трогать» — команде нечего делать.
        guard !theme.isKeep || !font.isKeep || !size.isKeep || !frame.isKeep else { return false }
        noteUserCommand()
        let target = window ?? focusedWindow()
        let title = target.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        let send: () -> Bool = { [weak self] in
            guard let self = self else { return false }
            let fields = ClaudeActions.themeFields(scope: scope, title: title, theme: theme,
                                                   font: font, size: size, frame: frame)
            guard self.commands.write(action: "theme", fields: fields) else { return false }
            self.recordTheme(fields: fields)
            self.remember(scope: scope, title: title, theme: theme, font: font, size: size, frame: frame)
            return true
        }
        if title.isEmpty, let target = target {
            app.focus(window: target)
            after(focusDelay) { _ = send() }
            return true
        }
        return send()
    }

    /// Поля команды после id, action, at: scope, title, match, preview, затем слои — тема,
    /// шрифт, размер, рамка. Слоя `.keep` в JSON нет вовсе, `.reset` уходит как `null`
    /// (контракт п. 1 плана WF12). `preview` — только у предпросмотра (контракт п. 1 плана WF8):
    /// у закрепляющей команды поля нет вовсе, `true` — примерить слой не запоминая,
    /// `false` без слоёв — конец примерки.
    /// `match` — необязательная адресация ПУТЁМ страницы (`/epitaxy/local_…`, план WF15):
    /// поля нет — всё как было, заголовком; поле есть — страница сверяет `location.pathname`
    /// и заголовок не смотрит вовсе. Им адресуется главное окно: его заголовок — заглушка
    /// «Claude», и по ней команда ушла бы веером всем безымянным попапам (критик Б1 плана WF15).
    /// `chat` — необязательная адресация ПО ЧАТУ окна (`local_<uuid>`, план WF29): страница
    /// сверяет id со своим и заголовок не смотрит вовсе. Им адресуются вынесенные в окно чаты:
    /// их заголовок — снимок имени чата на момент выноса, и после переименования он
    /// с индексом не сходится (задача #5455). Поле уходит только той странице, которая сама
    /// назвала свой id в последнем круге probe; вместе с `match` не посылается никогда.
    static func themeFields(scope: String, title: String, match: String? = nil,
                            chat: String? = nil, preview: Bool? = nil,
                            theme: Layer<Theme>, font: Layer<Font>,
                            size: SizeLayer = .keep,
                            frame: Layer<Bool> = .keep) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(scope)),
            (key: "title", value: .string(title)),
        ]
        if let match = match { fields.append((key: "match", value: .string(match))) }
        if let chat = chat { fields.append((key: "chat", value: .string(chat))) }
        if let preview = preview { fields.append((key: "preview", value: .bool(preview))) }
        return fields + layerFields(theme: theme, font: font, size: size, frame: frame)
    }

    /// Четыре слоя как поля команды, в порядке контракта: тема, шрифт, размер, рамка. Ими
    /// одинаково заканчиваются и `theme`, и `new-window` (решение 1 плана WF16) — правило
    /// «поля нет → слой не трогаем, null → сброс» у них одно на двоих. У размера правило то же,
    /// только по половинам: `SizeLayer` сам решает, писать ли поле и что положить внутрь.
    static func layerFields(theme: Layer<Theme>, font: Layer<Font>, size: SizeLayer,
                            frame: Layer<Bool>) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = []
        if let value = theme.commandValue({ $0.commandValue }) { fields.append((key: "theme", value: value)) }
        if let value = font.commandValue({ $0.commandValue }) { fields.append((key: "font", value: value)) }
        if let value = size.commandValue { fields.append((key: "size", value: value)) }
        if let value = frame.commandValue({ .bool($0) }) { fields.append((key: "frame", value: value)) }
        return fields
    }

    /// Своя тема ставит РОВНО палитру — один слой, как любой другой пункт списка цветов
    /// (решение 2.1 плана WF31, задача #5453: «когда я цвета выбираю, не надо мне из темы
    /// Пудра показывать шрифты»). Шрифт, кегль и рамка в `my-themes.json` по-прежнему
    /// хранятся (`saveMyTheme` пишет их все), но выбираются своими списками — правило одно
    /// и без исключений: список цветов меняет цвет. Так же с WF15 живёт цвет проекта
    /// (`ProjectPaint.view`), и панель «Своя тема» теперь ставит ровно то, что крутила.
    @discardableResult
    func apply(myTheme: MyTheme, scope: String, window: AXUIElement?) -> Bool {
        applyTheme(scope: scope, theme: .set(myTheme.theme), window: window)
    }

    /// «Сохранить как мою тему…»: набор из темы этого окна и последних шрифта, размера и рамки.
    /// Тема ни разу не выбиралась — сохранять нечего (меню покажет алерт).
    @discardableResult
    func saveMyTheme(name: String, window: AXUIElement? = nil) -> [MyTheme]? {
        guard let theme = themeToSave(window: window) else { return nil }
        return myThemes.add(name: name, theme: theme, font: lastAppliedFont, size: lastAppliedSize,
                            frame: lastAppliedFrame == true)
    }

    /// Что предложит «Сохранить как мою тему…» (и каким именем): у автопокрашенного окна — его
    /// собственную автотему (план WF10 п. 6), у остальных — последнюю применённую этим
    /// приложением. Иначе на окне «Радуги» сохранялся бы цвет соседнего окна.
    func themeToSave(window: AXUIElement?) -> Theme? {
        let title = window.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        return autoPaintedThemes[title] ?? lastAppliedTheme
    }

    /// Автотема окна, если его красила автопокраска. Меню спрашивает об этом ради галки
    /// «Как у Claude»: окно цветное, а `ThemeStore` пуст — галка соврала бы (критик В1 плана WF14).
    func autoPaintedTheme(title: String) -> Theme? { autoPaintedThemes[title] }

    /// Заголовок окна, которым сейчас владеет панель «Своя тема» (критик Б3 плана WF20).
    /// Пока он занят, фоновая покраска по проекту это окно не трогает, а живые цвета
    /// не запускаются вовсе: обычная команда `theme` гасит примерку на странице
    /// (`endPreviewExcept`), и ползунок остался бы без цвета. Ставит и снимает `ThemeEditor`;
    /// панель одна на приложение — отсюда и статик, как у `ThemeEditor.current`.
    static var themeEditorTitle: String?

    /// То же окно, но КЛЮЧОМ покраски (`main` / `c:<id>` / `w:<заголовок>`, находка 5 проверки
    /// WF20): заголовок для сверки не годится — у цели главного окна стоит заглушка «Claude»,
    /// а панель видит настоящий заголовок чата, и тик гасил примерку. Ставит `ThemeEditor`
    /// вместе с заголовком; nil — резолвер не повешен, сверка идёт по-старому.
    static var themeEditorKey: String?

    /// Ключ окна по его заголовку — резолвер покраски (`ProjectPaint.windowKey(forTitle:)`).
    /// Вешает `ClaudeAXController`; в сборке без покраски и в тестах его нет.
    static var windowKeyForTitle: ((String) -> String)?

    /// Панель закрылась: флаг снят, и отложенный крутёж живых цветов уезжает на страницу
    /// (находка 4 проверки WF20). Пока панель была открыта, `sendLiveColors` его только
    /// запоминал — приложение считало живые цвета включёнными, а страница ничего не крутила
    /// до перезапуска. Зовёт `ThemeEditor.finish()`, и только он.
    func finishThemeEditor() {
        ClaudeActions.themeEditorTitle = nil
        ClaudeActions.themeEditorKey = nil
        _ = resendLiveColors()
    }

    /// Ручки, с которых открывается «🎚 Своя тема…»: у выбранной окном своей темы — записанные
    /// в файл, у темы каталога и автотемы — подобранные по палитре (приблизительно, п. 4
    /// «Что выяснено»). Ничего не выбрано — умолчание панели.
    func editorKnobs(window: AXUIElement?) -> ThemeKnobs {
        let title = window.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        if let id = themeStore.windowThemeID(title: title) {
            if let my = myThemes.load().first(where: { $0.id == id }) { return ThemeKnobs.of(my) }
            if let found = themes.first(where: { $0.id == id }) {
                return ThemeKnobs.from(palette: found.palette, type: found.type)
            }
        }
        guard let theme = autoPaintedThemes[title] ?? lastAppliedTheme else { return ThemeKnobs() }
        return ThemeKnobs.from(palette: theme.palette, type: theme.type)
    }

    /// Галки в меню и «последнее применённое» — по слоям: слой `.keep` остаётся как был.
    /// Размер приходит половинами, поэтому кладётся поверх запомненного — как его склеивает
    /// страница; `.reset` («🧹 Всё как у Claude») снимает слой целиком, а снятая половина
    /// («Как у Claude» в одном из двух подменю) уходит из записи одна (решение 1 плана WF19).
    private func remember(scope: String, title: String, theme: Layer<Theme>, font: Layer<Font>,
                          size: SizeLayer, frame: Layer<Bool>) {
        // Размер окна ЦЕЛЫМ слоем — таким он и уйдёт в файл проекта (крючок в конце).
        var windowSize: Layer<Size> = .keep
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
            if !size.isKeep {
                themeStore.setAllSize(size.applied(to: themeStore.allSize))
                themeStore.clearWindowSizes()
            }
            if !frame.isKeep {
                themeStore.setAllFrame(frame.value == true)
                themeStore.clearWindowFrames()
            }
        } else {
            if !theme.isKeep {
                themeStore.setWindowTheme(theme.value?.id, title: title)
                autoPaintedThemes[title] = nil // цвет окна выбрали руками — автотема устарела
            }
            if !font.isKeep { themeStore.setWindowFont(font.value?.id, title: title) }
            if !size.isKeep {
                let value = ClaudeActions.windowSize(after: size,
                                                     window: themeStore.windowSize(title: title),
                                                     all: themeStore.allSize)
                themeStore.setWindowSize(value, title: title)
                // В файл проекта размер уходит целым слоем, а не половиной: страница склеила
                // половины ровно так же (решение 3.2 плана WF20).
                windowSize = value.map { Layer.set($0) } ?? .reset
            }
            if !frame.isKeep { themeStore.setWindowFrame(frame.value == true, title: title) }
        }
        if !theme.isKeep { lastAppliedTheme = theme.value }
        if !font.isKeep { lastAppliedFont = font.value }
        // Снятую половину убираем и отсюда (критик В5 плана WF19): иначе «💾 Сохранить как мою
        // тему…» записала бы кегль, которого на экране уже нет.
        if !size.isKeep { lastAppliedSize = size.applied(to: lastAppliedSize) }
        if !frame.isKeep { lastAppliedFrame = frame.value == true }
        // Ручной выбор в окне проекта — это и есть вид проекта (решение 3.2 плана WF20).
        // Только `scope:"window"`: «всем окнам» проект не перебивает вовсе, а примерка
        // и «Раскрасить по кругу» сюда не доходят. Сверка именно «равно окну», а не «не равно
        // всем» (находка 6 проверки WF20): третий scope, который однажды появится, ушёл бы
        // в файл проекта молча.
        guard scope == MenuModel.themeScopeWindow else { return }
        onWindowViewChanged?(title, theme, font, windowSize, frame)
    }

    /// Окну задали вид руками: заголовок и четыре слоя. Вешает `ClaudeAXController` — на
    /// `ProjectPaint.noteManualChoice`, которая молча кладёт выбор в `.pimpmyclaude.json`
    /// (решение 3.2 плана WF20). Размер приходит целым слоем: `.reset` — «как у Claude».
    var onWindowViewChanged: ((String, Layer<Theme>, Layer<Font>, Layer<Size>, Layer<Bool>) -> Void)?

    /// Что записать окну после команды размера (критик В4 плана WF19): база слияния — своя
    /// запись окна, а её нет — запись «всем окнам». Страница мержит по той же цепочке
    /// (`storedLayer`: чат → сессия → main → «всем») и материализует унаследованную половину
    /// в запись чата; мержь Swift поверх одной только записи окна, галки разъехались бы
    /// с экраном на первом же снятии половины.
    static func windowSize(after layer: SizeLayer, window: Size?, all: Size?) -> Size? {
        layer.applied(to: window ?? all)
    }

    // MARK: - предпросмотр (план WF8)

    /// Мышь ведут по подменю: окно красится сразу, но ничего не запоминает — ни страница
    /// (`preview: true`), ни это приложение (`themeStore`/`lastApplied…` не трогаем).
    /// `nil` — примерка сброса слоя («Как у Claude»). В команде ровно один слой.
    @discardableResult
    func previewTheme(_ theme: Theme?, window: AXUIElement?) -> Bool {
        sendPreview(true, theme: theme.map { Layer.set($0) } ?? .reset, font: .keep, window: window)
    }

    /// Своя тема примеряется тем же одним слоем, каким и ставится (решение 2.1 плана WF31):
    /// примерка становится неотличима от примерки темы каталога с тем же id. Правило WF8
    /// «примерка = то, что получишь» запрещает разводить наведение и клик.
    @discardableResult
    func preview(myTheme: MyTheme, window: AXUIElement?) -> Bool {
        previewTheme(myTheme.theme, window: window)
    }

    /// То же для шрифта; `nil` — «Системный (как у Claude)».
    @discardableResult
    func previewFont(_ font: Font?, window: AXUIElement?) -> Bool {
        sendPreview(true, theme: .keep, font: font.map { Layer.set($0) } ?? .reset, window: window)
    }

    /// То же для размера: в команде одна половина слоя, вторую страница доклеивает сама
    /// из того, что сейчас на экране. «Как у Claude» примеряется тем же слоем со снятой
    /// половиной (`{"answer":null}`, решение 2 плана WF19) — вторая на экране не дрогнет.
    @discardableResult
    func previewSize(_ size: SizeLayer, window: AXUIElement?) -> Bool {
        sendPreview(true, theme: .keep, font: .keep, size: size, window: window)
    }

    /// Наведение на тумблер рамки примеряет её ВКЛЮЧЁННОЙ, чем бы она сейчас ни была:
    /// пункт показывает, как это выглядит (план WF12 п. 4).
    @discardableResult
    func previewFrame(window: AXUIElement?) -> Bool {
        sendPreview(true, theme: .keep, font: .keep, frame: .set(true), window: window)
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
                             size: SizeLayer = .keep, frame: Layer<Bool> = .keep,
                             window: AXUIElement?) -> Bool {
        noteUserCommand()
        let target = window ?? focusedWindow()
        let title = target.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        // Без заголовка примерка не адресуется (фокуса у окна Claude нет, пока открыто меню),
        // а «конец примерки» мог бы снять живую тему у окна без ключа — не шлём ничего.
        guard !title.isEmpty else { return false }
        let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow, title: title,
                                               preview: preview, theme: theme, font: font,
                                               size: size, frame: frame)
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

    /// «🔁 Ещё раз»: тот же набор и тот же режим, старт на +37° (план WF10 п. 5). После
    /// «🎲 Случайно» гармония берётся НОВАЯ — из трёх оставшихся, прежняя не выпадет
    /// (решение 4 плана WF19): «та же схема, только повёрнутая» читалась как «ничего
    /// не изменилось». У наборов со своей схемой менять нечего — там `schemeIndex` даёт nil.
    /// Набора в памяти нет — берём первый.
    @discardableResult
    func autoPaintAgain() -> Int {
        let last = autoPaintStore.last
        let preset = last.flatMap { AutoPaint.preset(id: $0.preset) } ?? AutoPaint.presets[0]
        return paint(preset: preset, start: (last?.start ?? 0) + AutoPaint.againStep,
                     scheme: AutoPaint.schemeIndex(for: preset, avoiding: last?.scheme ?? nil),
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
        noteUserCommand()
        let windows = paintableWindows()
        let titles = windows.titles
        guard !titles.isEmpty else {
            onWarning?(MenuModel.autoPaintNoWindowsAlert)
            return 0
        }
        // Окна красятся по одному раз в 600 мс — молча это выглядит как зависшее меню.
        // В счёт «Крашу N» идут только окна, которым цвет достанется (без пропущенных).
        onWarning?(MenuModel.autoPaintStart(windows: windows.onScreen - windows.skipped, shared: windows.shared,
                                            skipped: windows.skipped))
        // Режим у набора свой; у «🎲 Случайно» — наоборот к прошлой покраске, а прошлой нет —
        // монетка (решение 3 плана WF19). «🔁 Ещё раз» режим не меняет — он приходит из памяти
        // (`repeated`). Считать режим по галкам окон больше нельзя: покраска сама их снимает,
        // и «Случайно» после неё всегда выпадало тёмным.
        let light = preset.light ?? repeated ?? AutoPaint.nextLight(last: autoPaintStore.last?.light)
        let themes = AutoPaint.themes(preset: preset,
                                      scheme: AutoPaint.scheme(for: preset, index: index),
                                      count: titles.count, start: start, light: light)
        for (title, theme) in zip(titles, themes) {
            let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow, title: title,
                                                   theme: .set(theme), font: .keep)
            // Вторая точка зеркала (решение 2 плана WF35): «Раскрасить по кругу» пишет команду
            // напрямую, мимо applyTheme, — и без этой строки её цвета не пережили бы
            // переустановку Claude.
            if commands.write(action: "theme", fields: fields) { recordTheme(fields: fields) }
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
    /// тот же, что у «Расставить»), и счётчики для HUD. Окно без AX-заголовка пропускаем совсем:
    /// страница узнаёт окно только по нему, а пустой заголовок значит «окно в фокусе» —
    /// покрасились бы все в один цвет. Одинаковые заголовки схлопываются по той же причине:
    /// тема живёт на чате, и двум окнам одного чата достанется один цвет.
    /// Счётчики считаются по факту (хвост WF10): `shared` — окна, которым своего цвета не
    /// досталось (окна − уникальные заголовки − пропущенные), `skipped` — окна без заголовка.
    private func paintableWindows() -> (titles: [String], onScreen: Int, shared: Int, skipped: Int) {
        guard let pid = app.pid else { return ([], 0, 0, 0) }
        let windows = ClaudeApp.onScreenFrames(pid: pid)
        guard !windows.isEmpty else { return ([], 0, 0, 0) }
        var seen = Set<String>()
        var titles: [String] = []
        var skipped = 0
        for index in ArrangeLayout.order(of: windows.map { $0.frame }) {
            let title = app.window(matching: windows[index].frame)
                .flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
            guard !title.isEmpty else {
                skipped += 1
                continue
            }
            guard seen.insert(title).inserted else { continue }
            titles.append(title)
        }
        return (titles, windows.count, windows.count - titles.count - skipped, skipped)
    }

    // MARK: - живые цвета (план WF18)

    /// Что крутится сейчас — из этого галки меню, гашение «🌈 Раскрасить по кругу ▸» и молчание
    /// цвета проекта.
    var liveColors: LiveColorsState { liveColorsStore.state }

    /// «🔗 Все окна одним цветом» / «🎭 Каждое окно своим цветом»: одна команда на все окна.
    /// Круг стартует от сейчас; смена режима на ходу точку отсчёта не сбивает — цвет едет дальше.
    @discardableResult
    func startLiveColors(mode: LiveColorsMode) -> Bool {
        var state = liveColorsStore.state
        let now = LiveColors.milliseconds(clock())
        if !state.on { state.epoch = now }
        state.on = true
        state.mode = mode
        // «Как окно сейчас» в режиме «все одним цветом» смысла не имеет (критик М2): в меню
        // пункт погашен, а тут закрыт и путь «переключили режим, когда он уже был выбран».
        state.tone = LiveColors.tone(state.tone, mode: mode)
        return sendLiveColors(state)
    }

    /// «⏹ Выключить»: короткая команда `on:false` — страница сама возвращает окну тему чата
    /// (`restoreTheme`), запоминать «что было» не нужно.
    @discardableResult
    func stopLiveColors() -> Bool {
        var state = liveColorsStore.state
        state.on = false
        return sendLiveColors(state)
    }

    /// Ползунок скорости: новый период и пересчитанная точка отсчёта, чтобы цвет не прыгнул.
    /// Живые цвета выключены — просто запоминаем скорость, команду не шлём.
    ///
    /// Идёт мимо очереди канала, как примерка темы: ползунок тащат мышью, и очередь по 0,6 с
    /// на запись растянула бы смену темпа на секунды после того, как Элвис его отпустил.
    /// Потерянная промежуточная скорость безвредна — на диске остаётся последняя.
    @discardableResult
    func setLiveColors(period: Int) -> Bool {
        let state = LiveColors.state(liveColorsStore.state, period: period,
                                     now: LiveColors.milliseconds(clock()))
        guard state.on else {
            liveColorsStore.save(state)
            return false
        }
        return sendLiveColors(state, priority: .preview)
    }

    /// «🌑 Тёмные» / «☀️ Светлые» / «🪟 Как окно сейчас». Выключенные живые цвета так же только
    /// запоминают выбор: галка в меню обязана стоять там, куда её поставили.
    @discardableResult
    func setLiveColors(tone: LiveColorsTone) -> Bool {
        var state = liveColorsStore.state
        state.tone = LiveColors.tone(tone, mode: state.mode)
        guard state.on else {
            liveColorsStore.save(state)
            return false
        }
        return sendLiveColors(state)
    }

    /// Пересыл при старте приложения: окна могли открыться, пока приложение не работало, и
    /// список `titles` в них устарел. Крутёж выключен — молчим (страница и так ничего не крутит).
    @discardableResult
    func resendLiveColors() -> Bool {
        let state = liveColorsStore.state
        guard state.on else { return false }
        return sendLiveColors(state)
    }

    /// Одна команда на всё (`scope: "all"`) — ни в одном режиме N команд по окнам не пишем.
    /// `ClaudeCommand.liveColors` не заводим: enum — это пункты верхнего уровня и слоты
    /// хоткеев, а `theme` и `status` тоже пишутся строкой (критик В1).
    @discardableResult
    private func sendLiveColors(_ state: LiveColorsState,
                                priority: CommandChannel.Priority = .normal) -> Bool {
        noteUserCommand()
        // Пока открыта панель «Своя тема», крутёж не запускаем и не пересылаем: живой слой
        // перекрасил бы окно поверх примерки через четверть секунды (критик Б3 плана WF20).
        // Выбор всё равно запоминаем — поедет, как только панель закроют. Выключение проходит
        // всегда: оно примерке только помогает.
        guard !state.on || ClaudeActions.themeEditorTitle == nil else {
            liveColorsStore.save(state)
            return false
        }
        let fields = LiveColors.fields(state: state, titles: paintableTitles())
        guard commands.write(action: LiveColors.action, fields: fields,
                             priority: priority) else { return false }
        liveColorsStore.save(state)
        return true
    }

    // MARK: - цвет проекта (план WF15)

    /// Когда меню или хоткей в последний раз слали команду (примерка считается тоже).
    /// Фоновая покраска по проекту после этого молчит 2 с: не-preview команда гасит примерку
    /// темы мышью (`endPreviewExcept`, критик В1 плана WF15). Сама покраска сюда не пишет —
    /// она же и ждёт.
    private(set) var lastUserCommandAt: Date?

    private func noteUserCommand() { lastUserCommandAt = Date() }

    /// Покраска по проекту: та же команда `theme` (`scope: "window"`), но память приложения
    /// она не трогает вовсе — галки в меню ставит только ручной выбор (критик Б3 плана WF15).
    /// Окно адресуется путём страницы (`match`, главное окно) или заголовком (попапы);
    /// фокус не нужен — как и автопокраске.
    @discardableResult
    func applyProject(_ command: ProjectPaintCommand) -> Bool {
        guard !command.isEmpty else { return false }
        let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow,
                                               title: command.title, match: command.match,
                                               chat: command.chat,
                                               theme: command.theme, font: command.font,
                                               size: SizeLayer(command.size), frame: command.frame)
        guard commands.write(action: "theme", fields: fields) else { return false }
        recordTheme(fields: fields)
        return true
    }

    // MARK: - темы на диске (план WF35)

    /// Зеркало закрепляющей команды `theme` в `window-themes.json` — ЕДИНСТВЕННАЯ точка входа
    /// на все три места, откуда приложение пишет такую команду (`applyTheme`, «Раскрасить
    /// по кругу», цвет проекта). Ключи считаются по тем же полям, что ушли в команду, —
    /// второй реализации `writeKeys` в Swift нет (решение 2 плана WF35).
    ///
    /// Примерка (`sendPreview`) сюда не приходит вовсе, а команду с полем `preview` хранилище
    /// отбрасывает и само: примерка это экран, а не выбор.
    private func recordTheme(fields: [(key: String, value: CommandValue)]) {
        guard let store = windowThemes else { return }
        store.record(fields: fields)
        // Файл обязан догнать правду страницы: выбор темы поводом спросить probe не является,
        // и без этого сигнала самолечение решения 3 не работало бы вовсе.
        onThemeRecorded?()
    }

    /// Возврат тем после переустановки Claude: одна команда `themes-restore` на все окна
    /// (решение 4 плана WF35). Поля собирает `WindowThemeStore`, шлёт — общий канал, очередью.
    @discardableResult
    func sendThemesRestore(fields: [(key: String, value: CommandValue)]) -> Bool {
        commands.write(action: WindowThemeStore.restoreAction, fields: fields)
    }

    /// Заголовки окон Claude на экране — те же, что берёт «Раскрасить по кругу»: без
    /// заголовка окно не адресовать, одинаковые схлопнуты.
    func paintableTitles() -> [String] { paintableWindows().titles }

    /// Окно красила «Раскрасить по кругу» — цвет у него сгенерированный, и проект такое окно
    /// не трогает (критик Б3 плана WF15). Ручной выбор из меню (`ThemeStore`) окно больше
    /// НЕ занимает: с WF20 он и есть вид проекта (решение 3.2), а старая защита не дала бы
    /// окну взять цвет нового проекта после смены чата (п. 16 «Что выяснено»).
    func isWindowAutoPainted(title: String) -> Bool {
        guard !title.isEmpty else { return false }
        return autoPaintedThemes[title] != nil
    }

    /// Задан вид «всем окнам» — его проект не перебивает вовсе (критик Б3 плана WF15).
    var hasAllWindowsView: Bool { themeStore.allThemeID != nil || themeStore.allFontID != nil }

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
    /// ⌥⌘A и пункт «▦ Расставить» повторяют последнюю раскладку (план WF21).
    func arrange() { arrange(mode: themeStore.arrangeMode) }

    /// То же по заданной раскладке — её выбирают плиткой в меню. Ячеек меньше, чем окон
    /// («4» при пяти окнах), — хвост порядка не трогаем вовсе, окна стоят где стояли.
    func arrange(mode: ArrangeLayout.Mode) {
        let windows = app.visibleWindows()
        let frames = windows.map { AX.frame($0) ?? .zero }
        guard !windows.isEmpty, let area = Screens.usableFrame(holding: frames) else { return }
        let order = ArrangeLayout.order(of: frames)
        let cells = ArrangeLayout.frames(count: order.count, in: area, mode: mode,
                                         minCellWidth: cellWidth())
        for (index, cell) in cells.enumerated() {
            ClaudeActions.setFrame(windows[order[index]], cell)
        }
        onWindowsMoved?()
    }

    /// Ячейки раскладки на экране, где стоят окна Claude (план WF41): их номера пишет
    /// «💾 Сохранить эту раскладку…», по ним же «↩︎ Вернуть эти чаты» ставит окна.
    /// Считаются той же арифметикой, что «Расставить», — иначе номер ячейки означал бы
    /// одно при записи и другое при возврате.
    func arrangeCells(mode: ArrangeLayout.Mode, count: Int) -> [CGRect] {
        let frames = pimpWindows().map { $0.frame }
        guard count > 0, let area = Screens.usableFrame(holding: frames) else { return [] }
        return ArrangeLayout.frames(count: count, in: area, mode: mode, minCellWidth: cellWidth())
    }

    /// Влезает ли раскладка на главный экран (ячейка не уже `minWindowWidth`): по этому
    /// плитка в меню гаснет, а канал «Пимп» отвечает `too-small`. Экрана не знаем — не мешаем.
    func arrangeFits(_ mode: ArrangeLayout.Mode) -> Bool {
        let frames = app.visibleWindows().compactMap { AX.frame($0) }
        guard let area = Screens.usableFrame(holding: frames) else { return true }
        return ArrangeLayout.fits(mode, in: area, minCellWidth: cellWidth())
    }

    /// Поставить окну рамку и УБЕДИТЬСЯ, что она встала (гейт WF36, 07.09): Electron молча
    /// глотает `kAXPositionAttribute`, пока окно ещё едет (свежий popout, анимация) — на живом
    /// прогоне три окна сузились по сетке, а с места не сдвинулись, и Элвис видел ровно это
    /// («в ширину уменьшились, больше ничего не произошло»). Поэтому после записи читаем рамку
    /// назад и повторяем до трёх раз с паузой; порядок «позиция → размер → позиция»: смена
    /// размера у правого края может снова сдвинуть окно. Сон короткий и только при промахе —
    /// в штатном случае вызов остаётся мгновенным.
    static let frameRetries = 3
    static let frameRetryPause: TimeInterval = 0.25
    static let frameTolerance: CGFloat = 2

    @discardableResult
    static func setFrame(_ window: AXUIElement, _ frame: CGRect) -> Bool {
        for attempt in 0..<frameRetries {
            AX.set(window, kAXPositionAttribute, point: frame.origin)
            AX.set(window, kAXSizeAttribute, size: frame.size)
            AX.set(window, kAXPositionAttribute, point: frame.origin)
            if let now = AX.frame(window), frameMatches(now, frame) { return true }
            if attempt + 1 < frameRetries { Thread.sleep(forTimeInterval: frameRetryPause) }
        }
        return AX.frame(window).map { frameMatches($0, frame) } ?? false
    }

    static func frameMatches(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = frameTolerance) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    // MARK: - канал «Пимп» (план WF36)

    /// Окна Claude на экране для канала: номер окна Quartz, AX-элемент, заголовок и рамка.
    /// Номер нужен, чтобы отличить НОВОЕ окно от прежних (по имени нельзя — переименование
    /// чата может не удаться) и чтобы канал говорил номерами, не таская наружу AX.
    /// Геометрия — из `CGWindowList` (один вызов), как у автопокраски; окно без AX-пары
    /// пропускаем: двигать его нечем.
    func pimpWindows() -> [(id: CGWindowID, window: AXUIElement, title: String, frame: CGRect)] {
        guard let pid = app.pid else { return [] }
        var out: [(id: CGWindowID, window: AXUIElement, title: String, frame: CGRect)] = []
        for entry in ClaudeApp.onScreenFrames(pid: pid) {
            guard let window = app.window(matching: entry.frame) else { continue }
            out.append((id: entry.id, window: window,
                        title: AX.string(window, kAXTitleAttribute) ?? "", frame: entry.frame))
        }
        return out
    }

    /// Свёрнутые окна: их «Расставить» не трогает — канал только считает их в ответе,
    /// чтобы CLI сказал «одно окно свёрнуто, не считал».
    func minimizedCount() -> Int {
        app.windows().filter { AX.bool($0, kAXMinimizedAttribute) == true }.count
    }

    /// Расставить окна в ЗАДАННОМ порядке (номера окон Quartz) по заданной раскладке.
    /// Возвращает окна с рамками, которые им поставили (канал отдаёт их в ответе, не
    /// перечитывая экран — `CGWindowList` после переезда отвечает не сразу), и сколько
    /// окон осталось без ячейки: их не двигали вовсе.
    @discardableResult
    func arrange(ids: [CGWindowID], mode: ArrangeLayout.Mode)
        -> (placed: [(id: CGWindowID, title: String, frame: CGRect)], skipped: Int) {
        let windows = pimpWindows()
        let ordered = ids.compactMap { id in windows.first { $0.id == id } }
        guard !ordered.isEmpty,
              let area = Screens.usableFrame(holding: ordered.map { $0.frame }) else { return ([], 0) }
        let cells = ArrangeLayout.frames(count: ordered.count, in: area, mode: mode,
                                         minCellWidth: cellWidth())
        var out: [(id: CGWindowID, title: String, frame: CGRect)] = []
        for (index, cell) in cells.enumerated() {
            ClaudeActions.setFrame(ordered[index].window, cell)
            out.append((id: ordered[index].id, title: ordered[index].title, frame: cell))
        }
        onWindowsMoved?()
        return (placed: out, skipped: ordered.count - out.count)
    }

    /// Поставить окна по рамкам — деление столбца пополам («под этим»/«над этим»).
    /// Остальные окна не трогаем вовсе.
    @discardableResult
    func place(_ moves: [PimpMove]) -> Int {
        guard !moves.isEmpty else { return 0 }
        let windows = pimpWindows()
        var moved = 0
        for move in moves {
            guard let entry = windows.first(where: { $0.id == move.id }) else { continue }
            ClaudeActions.setFrame(entry.window, move.frame)
            moved += 1
        }
        if moved > 0 { onWindowsMoved?() }
        return moved
    }

    /// Ширина ячейки «Расставить». Живьём — из claude.json, в тестах подставляется.
    var cellWidth: () -> CGFloat = { ClaudeActions.minCellWidth() }

    /// `minWindowWidth` из живого `claude.json` (его правит и сам Элвис, и лоадер берёт
    /// ширину оттуда же): уже этой ширины Electron окно всё равно не сделает, а константа
    /// 340 у `ArrangeLayout` про это не знает. Ключа нет или он битый — 360, как в патче.
    static func minCellWidth(configURL: URL = CommandChannel.directory
                                .appendingPathComponent(StatusFeed.configFileName)) -> CGFloat {
        let data = try? Data(contentsOf: configURL)
        let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        guard let value = (json?["minWindowWidth"] as? NSNumber)?.doubleValue,
              value.isFinite, value > 0 else { return 360 }
        return CGFloat(value)
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

    /// То же, но со своим сроком: «Новое окно» работает до 40 с, и штатные 2,5 с `onWarning`
    /// гасли бы задолго до результата (критик п. 20 плана WF13).
    var onNotice: ((String, TimeInterval) -> Void)?

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}
