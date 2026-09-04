import Foundation

/// Покраска одного окна по проекту: чем адресовать окно и какие слои поставить или снять.
/// Уходит обычной командой `theme` (`scope:"window"`) — нового действия WF15 не заводит,
/// добавляется лишь необязательное поле `match` (решение 1 плана WF15).
struct ProjectPaintCommand: Equatable {
    /// Ключ окна в памяти отпечатков: `main` у главного окна, `w:<заголовок>` у попапа.
    let key: String
    /// Поле `match` — путь страницы главного окна (`/epitaxy/local_…`); nil — адресуем заголовком.
    let match: String?
    /// Поле `title` — заголовок попапа. У главного окна пустой: адресует `match`, а запись
    /// страница всё равно ключует своим `document.title` (у неё это `main`).
    let title: String
    let theme: Layer<Theme>
    let font: Layer<Font>
    let size: Layer<Size>
    let frame: Layer<Bool>

    /// Ни одного слоя — слать нечего.
    var isEmpty: Bool { theme.isKeep && font.isKeep && size.isKeep && frame.isKeep }

    /// Слои, которые команда СТАВИТ: их и снимем, когда окно уйдёт в другой проект.
    /// Сброшенные сюда не идут — снятое снимать второй раз незачем.
    var setLayers: [String] {
        var out: [String] = []
        if case .set = theme { out.append(ProjectSettings.themeKey) }
        if case .set = font { out.append(ProjectSettings.fontKey) }
        if case .set = size { out.append(ProjectSettings.sizeKey) }
        if case .set = frame { out.append(ProjectSettings.frameKey) }
        return out
    }
}

/// Окно, которое красит проект.
struct ProjectTarget: Equatable {
    /// Ключ памяти окна — те же ключи, что у страницы в sessionStorage: `main` / `w:<заголовок>`.
    /// Он ОБЯЗАН пережить смену чата в главном окне: иначе смена папки прошла бы незамеченной,
    /// и цвет прошлого проекта остался бы на окне навсегда (критик Б2 плана WF15).
    let key: String
    /// Путь страницы для поля `match` (главное окно); nil — попап, адресуем заголовком.
    let match: String?
    /// AX-заголовок окна: им адресуется попап и им же ключуется память ручного выбора
    /// (`ThemeStore`, `autoPaintedThemes`). У главного окна на вкладке Claude Code это
    /// заглушка «Claude» — адресовать по ней нельзя (её носят и безымянные попапы).
    let title: String
    /// Корень проекта; nil — папку не знаем (красить нечем, но снять чужое надо).
    let folder: URL?

    /// Заголовок в самой команде: у главного окна пустой — адресует `match`.
    var commandTitle: String { match == nil ? title : "" }
}

/// Что показать в пункте «🗂 Проект ▸» (решение 5 плана WF15).
struct ProjectMenuState: Equatable {
    /// Корень проекта; nil — папку не узнали, пункт виден и погашен.
    let folder: URL?
    /// Подпись под заголовком: путь с `~`.
    let path: String
    /// У проекта уже есть свой вид (файл в папке или запись реестра).
    let hasSettings: Bool
    /// Тумблер «Красить чаты по проекту».
    let painting: Bool

    /// Имя проекта в заголовке пункта — последний компонент пути папки.
    var name: String { folder?.lastPathComponent ?? "" }
}

/// Цвет проекта: приложение само узнаёт папку каждого окна Claude и красит окно тем видом,
/// что лежит в папке проекта (`.pimpmyclaude.json`).
///
/// Всё делает Swift: папку даёт `ProjectIndex` (индекс чатов Claude Code + `status.json`
/// лоадера), вид — `ProjectSettings`, а на страницу уходит та же команда `theme`, что и из
/// меню. Работа идёт на общем таймере 2 с `ClaudeAXController` — своего таймера у покраски
/// нет (критик М2 плана WF15).
///
/// Три правила, без которых покраска мешала бы жить:
/// 1. **Отпечаток** «окно → папка + хэш вида»: пока ничего не изменилось, команда не шлётся
///    (очередь канала пишет раз в 0,6 с, и лишние команды дёргали бы страницу).
/// 2. **Смена папки снимает прошлое**: проект без настроек = только снятие слоёв, которые
///    ставил прошлый проект. Иначе окно (а у главного окна — навсегда, запись `main`
///    переживает перезапуск) осталось бы в чужом цвете (критик Б2).
/// 3. **Ручной выбор сильнее**: окно, которому цвет выбрали из меню (`ThemeStore`) или
///    которое красила «Раскрасить по кругу» (`autoPaintedThemes`), проект не трогает; запись
///    «всем окнам» он не перебивает вовсе (критик Б3).
///
/// Индекса нет (не Claude Code, старая сборка Claude, чужая машина) — покраска просто молчит:
/// ни команд, ни подсказок, ни ошибок.
final class ProjectPaint {
    /// Тумблер «Красить чаты по проекту» (UserDefaults, по умолчанию включён).
    static let enabledKey = "projectPaintEnabled"
    /// Показанные подсказки: карта «путь папки → true». Одним ключом, чтобы «Забыть
    /// подсказки» однажды сделать одной строкой (критик М7 плана WF15).
    static let hintsKey = "projectHints"
    static let mainKey = "main"
    static let windowPrefix = "w:"
    /// Заголовок главного окна на вкладке Claude Code — заглушка (probe 04.09, п. 4 плана):
    /// команду по ней не адресуем, а память ручного выбора ключуется именно ею.
    static let mainWindowTitle = "Claude"
    /// Пока открыто меню и столько секунд после его последней команды — молчим: не-preview
    /// команда гасит примерку темы мышью (`endPreviewExcept`, критик В1 плана WF15).
    static let quietSeconds: TimeInterval = 2
    /// Плашка «у проекта нет своего вида» — не чаще одной за раз: при первом запуске папок
    /// без настроек может быть несколько, и плашки перекрыли бы друг друга.
    static let hintInterval: TimeInterval = 10
    /// Памятка агенту проекта (решение 5 плана WF15): пишем по клику, назад НЕ читаем.
    static let agentsFileName = "AGENTS.md"
    static let agentsMarker = "<!-- pimpmyclaude:"

    /// Отпечаток окна: какой проект на нём стоит и какие слои поставил.
    private struct Mark: Equatable {
        let match: String?
        let title: String
        /// Путь папки проекта; пусто — папку не знаем.
        let folder: String
        /// Хэш вида; пусто — у проекта настроек нет.
        let digest: String
        /// Слои, которые поставил проект: их и снимать при смене папки.
        let layers: [String]
    }

    private let index: ProjectIndex
    private let store: ProjectSettingsStore
    private let defaults: ThemeDefaults
    private let now: () -> Date

    /// Живёт в памяти: после перезапуска приложение просто покрасит окна заново.
    private var marks: [String: Mark] = [:]
    private var lastHintAt: Date?

    // MARK: - сиденья (живьём их ставит ClaudeAXController)

    /// Заголовки окон Claude на экране — те же, что берёт «Раскрасить по кругу».
    var windowTitles: () -> [String] = { [] }
    /// Отправка команды; false — не записалась, попробуем на следующем тике.
    var send: (ProjectPaintCommand) -> Bool = { _ in false }
    /// Окну уже выбрали вид руками или его красила автопокраска (критик Б3).
    var isWindowBusy: (String) -> Bool = { _ in false }
    /// Задан вид «всем окнам» — проект его не перебивает (критик Б3).
    var isAllWindowsSet: () -> Bool = { false }
    /// Крутятся живые цвета (план WF18, критик Б2): живой слой перекрыл бы цвет проекта через
    /// четверть секунды, и окна мигали бы между ними. Выключили живые — следующая смена чата
    /// красит как обычно.
    var isLiveColorsOn: () -> Bool = { false }
    /// Открыто меню на кнопке «Свернуть».
    var isMenuOpen: () -> Bool = { false }
    /// Когда меню в последний раз слало команду (примерка считается тоже).
    var lastMenuCommand: () -> Date? = { nil }
    /// Плашка на экран: подсказка про папку без настроек и ответы пунктов меню.
    var showNotice: (String) -> Void = { _ in }
    /// Что применено к этому окну — это и ложится в файл проекта по «Записать этот вид».
    var currentView: (String) -> ProjectSettings = { _ in ProjectSettings() }

    init(index: ProjectIndex = ProjectIndex(),
         store: ProjectSettingsStore = ProjectSettingsStore(),
         defaults: ThemeDefaults = UserDefaults.standard,
         now: @escaping () -> Date = Date.init) {
        self.index = index
        self.store = store
        self.defaults = defaults
        self.now = now
    }

    // MARK: - тумблер

    /// «Красить чаты по проекту»: по умолчанию включено.
    var enabled: Bool { (defaults.object(forKey: ProjectPaint.enabledKey) as? Bool) ?? true }

    /// Выключение СНИМАЕТ слои с окон, которые красил проект (критик Б2): иначе цвет проекта
    /// залипал бы на окнах навсегда. Включение ничего не шлёт — покрасит ближайший тик.
    func setEnabled(_ on: Bool) {
        defaults.set(on, forKey: ProjectPaint.enabledKey)
        guard !on else { return }
        clear()
    }

    /// Снять всё, что поставил проект, и забыть отпечатки.
    private func clear() {
        for (key, mark) in marks.sorted(by: { $0.key < $1.key }) where !mark.layers.isEmpty {
            _ = send(ProjectPaintCommand(key: key, match: mark.match,
                                         title: mark.match == nil ? mark.title : "",
                                         theme: undo(mark, ProjectSettings.themeKey),
                                         font: undo(mark, ProjectSettings.fontKey),
                                         size: undo(mark, ProjectSettings.sizeKey),
                                         frame: undo(mark, ProjectSettings.frameKey)))
        }
        marks = [:]
    }

    /// Слой, который ставил проект, — сброс; чужой не трогаем.
    private func undo<Value>(_ mark: Mark, _ key: String) -> Layer<Value> {
        mark.layers.contains(key) ? .reset : .keep
    }

    // MARK: - тик

    /// Пока открыто меню и 2 с после его команды покраска молчит (критик В1 плана WF15).
    var isQuiet: Bool {
        if isMenuOpen() { return true }
        guard let at = lastMenuCommand() else { return false }
        return now().timeIntervalSince(at) < ProjectPaint.quietSeconds
    }

    /// Тик общего таймера 2 с: что изменилось — то и красим. Пока крутятся живые цвета, проект
    /// молчит совсем (критик Б2 плана WF18) — и отпечатки не трогает: выключат живые, и
    /// ближайший тик покрасит окно, если за это время что-то изменилось.
    func tick() {
        guard enabled, !isQuiet, !isLiveColorsOn(), !isAllWindowsSet() else { return }
        for target in targets() { paint(target) }
    }

    /// Строка для `statusText` приложения (живая проверка на гейте): тумблер, папка главного
    /// окна и сколько окон покрашено проектом.
    var status: String {
        let folder = index.mainWindow()?.folder?.lastPathComponent ?? "—"
        return "\(enabled ? "on" : "off")/\(folder)/\(marks.values.filter { !$0.layers.isEmpty }.count)"
    }

    /// Окна с известной папкой: главное — по адресу страницы из `status.json` лоадера,
    /// попапы — по AX-заголовку через индекс чатов. Заголовок пустой, заглушка или найденный
    /// в РАЗНЫХ папках папки не даёт (решение 2 плана WF15) — такое окно не красим вовсе.
    private func targets() -> [ProjectTarget] {
        var out: [ProjectTarget] = []
        if let main = index.mainWindow() {
            out.append(ProjectTarget(key: ProjectPaint.mainKey, match: main.match,
                                     title: ProjectPaint.mainWindowTitle, folder: main.folder))
        }
        var seen = Set<String>()
        for title in windowTitles() {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean).inserted,
                  let folder = index.folder(forTitle: clean) else { continue }
            out.append(ProjectTarget(key: ProjectPaint.windowPrefix + clean, match: nil,
                                     title: clean, folder: folder))
        }
        return out
    }

    /// Одно окно: сверить отпечаток, при надобности послать команду и запомнить, что послали.
    @discardableResult
    private func paint(_ target: ProjectTarget) -> Bool {
        let settings = target.folder.flatMap { store.settings(in: $0) }
        let folder = target.folder?.standardizedFileURL.path ?? ""
        let digest = settings?.digest ?? ""
        let previous = marks[target.key]
        // Ни папка, ни вид не изменились — молчим: иначе очередь команд (0,6 с на запись)
        // забьётся, а лоадер будет зря дёргать страницу.
        guard previous?.folder != folder || previous?.digest != digest else { return false }
        hint(about: target.folder, settings: settings)
        // Ручной выбор из меню и «Раскрасить по кругу» сильнее проекта (критик Б3): окно
        // остаётся неотмеченным, и как только память о нём очистят, проект его покрасит.
        guard !isWindowBusy(target.title) else { return false }
        let command = self.command(for: target, settings: settings, previous: previous)
        // Слать нечего (у проекта настроек нет, и прошлый ничего не ставил) — просто запомним.
        if !command.isEmpty, !send(command) { return false }
        marks[target.key] = Mark(match: target.match, title: target.title, folder: folder,
                                 digest: digest, layers: command.setLayers)
        return true
    }

    /// Что послать окну: слои из файла проекта плюс снятие слоёв, которые ставил ПРОШЛЫЙ
    /// проект, а этот не задаёт. Проект без файла настроек = только снятие (критик Б2).
    private func command(for target: ProjectTarget, settings: ProjectSettings?,
                         previous: Mark?) -> ProjectPaintCommand {
        let want = settings ?? ProjectSettings()
        return ProjectPaintCommand(key: target.key, match: target.match, title: target.commandTitle,
                                   theme: layer(want.theme, previous, ProjectSettings.themeKey),
                                   font: layer(want.font, previous, ProjectSettings.fontKey),
                                   size: layer(want.size, previous, ProjectSettings.sizeKey),
                                   frame: layer(want.frame, previous, ProjectSettings.frameKey))
    }

    /// Слой из файла; проект его не задаёт, а прошлый ставил — сброс.
    private func layer<Value>(_ want: Layer<Value>, _ previous: Mark?, _ key: String) -> Layer<Value> {
        guard want.isKeep else { return want }
        return previous?.layers.contains(key) == true ? .reset : .keep
    }

    /// «У проекта нет своего вида» — плашкой один раз на папку (решение 6 плана WF15).
    /// Сказал «потом» — больше не покажем, остаётся пункт меню.
    private func hint(about folder: URL?, settings: ProjectSettings?) {
        guard settings == nil || settings?.isEmpty == true, let folder = folder else { return }
        if let at = lastHintAt, now().timeIntervalSince(at) < ProjectPaint.hintInterval { return }
        let path = folder.standardizedFileURL.path
        var hints = defaults.dictionary(forKey: ProjectPaint.hintsKey) ?? [:]
        guard hints[path] == nil else { return }
        hints[path] = true
        defaults.set(hints, forKey: ProjectPaint.hintsKey)
        lastHintAt = now()
        showNotice(MenuModel.projectHint(folder.lastPathComponent))
    }

    // MARK: - пункт меню «🗂 Проект ▸»

    /// Папка окна под кнопкой: по заголовку через индекс, а у безымянного окна (главное зовётся
    /// «Claude») — папка главного окна.
    func folder(for title: String) -> URL? {
        if let folder = index.folder(forTitle: title) { return folder }
        return index.mainWindow()?.folder
    }

    /// Что показать в подменю проекта для окна под кнопкой.
    func menuState(title: String) -> ProjectMenuState {
        let folder = self.folder(for: title)
        return ProjectMenuState(folder: folder,
                                path: folder.map { ProjectPaint.short(path: $0) } ?? "",
                                hasSettings: folder.flatMap { store.settings(in: $0) } != nil,
                                painting: enabled)
    }

    /// Как адресовать окно под кнопкой: попап — своим заголовком, безымянное окно — путём
    /// страницы главного окна.
    private func target(for title: String) -> ProjectTarget? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder = index.folder(forTitle: clean) {
            return ProjectTarget(key: ProjectPaint.windowPrefix + clean, match: nil, title: clean,
                                 folder: folder)
        }
        guard let main = index.mainWindow() else { return nil }
        return ProjectTarget(key: ProjectPaint.mainKey, match: main.match,
                             title: ProjectPaint.mainWindowTitle, folder: main.folder)
    }

    /// «🎨 Взять цвет проекта» — та же команда, что на тике, но мимо проверок «окно занято» и
    /// «ничего не изменилось»: клик по пункту это явная просьба.
    func applyNow(title: String) {
        guard let target = target(for: title), let folder = target.folder else { return }
        guard let settings = store.settings(in: folder), !settings.isEmpty else {
            showNotice(MenuModel.projectNoSettings)
            return
        }
        let command = self.command(for: target, settings: settings, previous: marks[target.key])
        guard !command.isEmpty, send(command) else { return }
        marks[target.key] = Mark(match: target.match, title: target.title,
                                 folder: folder.standardizedFileURL.path, digest: settings.digest,
                                 layers: command.setLayers)
    }

    /// «💾 Записать этот вид в проект» / «✍️ Завести настройки проекта»: в файл ложатся ровно
    /// те слои, что применены к этому окну. Битый файл этот пункт перезаписывает (`force`) —
    /// он и есть то явное «да», без которого чужой файл не трогают.
    func writeCurrentView(title: String) {
        guard let folder = folder(for: title) else { return }
        let view = currentView(title)
        guard !view.isEmpty else {
            showNotice(MenuModel.projectNothingToWrite)
            return
        }
        let name = folder.lastPathComponent
        let settings = ProjectSettings(name: name, theme: view.theme, font: view.font,
                                       size: view.size, frame: view.frame)
        switch store.write(settings, to: folder, force: true) {
        case .written: showNotice(MenuModel.projectWritten(name))
        case .registry: showNotice(MenuModel.projectWrittenToRegistry(name))
        case .broken, .failed: showNotice(MenuModel.projectWriteFailed(name))
        }
    }

    /// «📝 Вписать строку в AGENTS.md» — памятка агенту проекта, а не хранилище (критик М4):
    /// пишем по клику, назад не читаем, «Убрать настройки» её не трогает.
    func writeAgentsLine(title: String) {
        guard let folder = folder(for: title) else { return }
        let name = folder.lastPathComponent
        guard let settings = store.settings(in: folder), !settings.isEmpty else {
            showNotice(MenuModel.projectNoSettings)
            return
        }
        let url = folder.appendingPathComponent(ProjectPaint.agentsFileName)
        let text = ProjectPaint.agents(file: try? String(contentsOf: url, encoding: .utf8),
                                       line: ProjectPaint.agentsLine(settings))
        showNotice(CommandChannel.writeAtomic(url, text) ? MenuModel.projectAgentsWritten(name)
                                                         : MenuModel.projectAgentsFailed(name))
    }

    /// «🗑 Убрать настройки из проекта»: файл и запись реестра. Строку в `AGENTS.md` не трогаем
    /// (о ней говорим плашкой), окна назад НЕ перекрашиваем — цвет остаётся, пока Элвис не
    /// выберет «Как у Claude» (решение 5 плана WF15). Для этого и забываем отпечатки папки:
    /// иначе ближайший тик снял бы слои обратно.
    func removeSettings(title: String) {
        guard let folder = folder(for: title) else { return }
        let path = folder.standardizedFileURL.path
        let removed = store.remove(from: folder)
        marks = marks.filter { $0.value.folder != path }
        showNotice(removed ? MenuModel.projectRemoved(folder.lastPathComponent)
                           : MenuModel.projectNoSettings)
    }

    // MARK: - чистая часть (её же гоняют тесты)

    /// `/Users/elvis/_ElvisProjects/PimpMyClaude` → `~/_ElvisProjects/PimpMyClaude`.
    static func short(path url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        guard path == base || path.hasPrefix(base + "/") else { return path }
        return "~" + path.dropFirst(base.count)
    }

    /// Строка-памятка: только id слоёв, коротко — её читает агент проекта, а не приложение.
    static func agentsLine(_ settings: ProjectSettings) -> String {
        var fields: [(key: String, value: CommandValue)] = []
        if let theme = settings.theme.value, !theme.id.isEmpty {
            fields.append((key: ProjectSettings.themeKey, value: .string(theme.id)))
        }
        if let font = settings.font.value {
            fields.append((key: ProjectSettings.fontKey, value: .string(font.id)))
        }
        if let size = settings.size.value {
            fields.append((key: ProjectSettings.sizeKey, value: size.commandValue))
        }
        if case .set(true) = settings.frame {
            fields.append((key: ProjectSettings.frameKey, value: .bool(true)))
        }
        return ProjectPaint.agentsMarker + " " + CommandValue.object(fields).json + " -->"
    }

    /// Текст `AGENTS.md` после вписывания строки: прежняя памятка заменяется на месте, новая
    /// дописывается в конец. Больше в файле не меняется ничего — его правят и Элвис, и агенты.
    static func agents(file old: String?, line: String) -> String {
        guard let old = old, !old.isEmpty else { return line + "\n" }
        var lines = old.components(separatedBy: "\n")
        if let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(ProjectPaint.agentsMarker)
        }) {
            lines[index] = line
            return lines.joined(separator: "\n")
        }
        return old + (old.hasSuffix("\n") ? "" : "\n") + "\n" + line + "\n"
    }

    /// Вид окна, каким его помнит приложение: галки меню (`ThemeStore`), а у окна после
    /// «Раскрасить по кругу» — его сгенерированная тема (галок она не ставит, план WF10 п. 4).
    /// Слоя, которого у окна нет, в файле проекта не будет вовсе — «этот слой проект не трогает».
    static func view(title: String, themeStore: ThemeStore, themes: [Theme], fonts: [Font],
                     myThemes: [MyTheme], autoPainted: Theme?) -> ProjectSettings {
        var theme: Layer<Theme> = .keep
        if let id = themeStore.windowThemeID(title: title) {
            if let found = themes.first(where: { $0.id == id }) {
                theme = .set(found)
            } else if let my = myThemes.first(where: { $0.id == id }) {
                theme = .set(my.theme)
            }
        } else if let painted = autoPainted {
            theme = .set(painted)
        }
        var font: Layer<Font> = .keep
        if let id = themeStore.windowFontID(title: title),
           let found = fonts.first(where: { $0.id == id }) {
            font = .set(found)
        }
        let size = themeStore.windowSize(title: title).map { Layer.set($0) } ?? Layer<Size>.keep
        return ProjectSettings(theme: theme, font: font, size: size,
                               frame: themeStore.windowFrame(title: title) ? .set(true) : .keep)
    }
}
