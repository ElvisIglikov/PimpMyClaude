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

/// Цвет проекта: приложение само узнаёт папку каждого окна Claude и красит окно цветом этого
/// проекта — видом из `.pimpmyclaude.json`, а пока файла нет, авто-цветом по имени папки.
///
/// Всё делает Swift: папку даёт `ProjectIndex` (индекс чатов Claude Code + `status.json`
/// лоадера), вид — `ProjectSettings`, а на страницу уходит та же команда `theme`, что и из
/// меню. Работа идёт на общем таймере 2 с `ClaudeAXController` — своего таймера у покраски
/// нет (критик М2 плана WF15).
///
/// Четыре правила, без которых покраска мешала бы жить:
/// 1. **Отпечаток** «окно → папка + хэш вида»: пока ничего не изменилось, команда не шлётся
///    (очередь канала пишет раз в 0,6 с, и лишние команды дёргали бы страницу). У авто-цвета
///    отпечаток свой — `auto:<hue>` (решение 3.1 плана WF20).
/// 2. **Смена папки снимает прошлое**: слои, которые ставил прошлый проект, а этот не задаёт,
///    уходят. Иначе окно (а у главного окна — навсегда, запись `main` переживает перезапуск)
///    осталось бы в чужом цвете (критик Б2 плана WF15).
/// 3. **Ручной выбор — это и есть вид проекта** (решение 3.2 плана WF20): он молча ложится
///    в `.pimpmyclaude.json`, и «окно занято ручным выбором» больше не повод молчать. Сильнее
///    проекта осталась только «Раскрасить по кругу» (`autoPaintedThemes`); запись «всем окнам»
///    проект не перебивает вовсе (критик Б3 плана WF15).
/// 4. **Папки не знаем — молчим**: ни авто-цвета, ни записи; снимается только чужое.
///
/// Индекса нет (не Claude Code, старая сборка Claude, чужая машина) — покраска просто молчит:
/// ни команд, ни подсказок, ни ошибок.
final class ProjectPaint {
    /// Тумблер «🗂 Цвет по проекту» (UserDefaults, по умолчанию включён).
    static let enabledKey = "projectPaintEnabled"
    /// Показанные плашки: карта «путь папки → true» (у плашки про битый файл ключ с приставкой).
    /// Одним ключом, чтобы «Забыть подсказки» однажды сделать одной строкой (критик М7 плана WF15).
    static let hintsKey = "projectHints"
    /// Приставка ключа плашки про битый файл: иначе одна плашка на папку съела бы другую.
    static let brokenPrefix = "broken:"
    static let mainKey = "main"
    static let windowPrefix = "w:"
    /// Заголовок главного окна на вкладке Claude Code — заглушка (probe 04.09, п. 4 плана):
    /// команду по ней не адресуем, а память ручного выбора ключуется именно ею.
    static let mainWindowTitle = "Claude"
    /// Пока открыто меню и столько секунд после его последней команды — молчим: не-preview
    /// команда гасит примерку темы мышью (`endPreviewExcept`, критик В1 плана WF15).
    static let quietSeconds: TimeInterval = 2

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

    // MARK: - сиденья (живьём их ставит ClaudeAXController)

    /// Заголовки окон Claude на экране — те же, что берёт «Раскрасить по кругу».
    var windowTitles: () -> [String] = { [] }
    /// Отправка команды; false — не записалась, попробуем на следующем тике.
    var send: (ProjectPaintCommand) -> Bool = { _ in false }
    /// Окно красила «Раскрасить по кругу» — она сильнее проекта (критик Б3 плана WF15).
    /// Ручной выбор с WF20 сюда не считается: он и есть вид проекта (решение 3.2).
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
    /// Плашка на экран: про молчаливую запись вида в папку проекта — один раз на папку.
    var showNotice: (String) -> Void = { _ in }

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
        let wanted = self.wanted(in: target.folder)
        let folder = target.folder?.standardizedFileURL.path ?? ""
        let digest = wanted?.digest ?? ""
        let previous = marks[target.key]
        // Ни папка, ни вид не изменились — молчим: иначе очередь команд (0,6 с на запись)
        // забьётся, а лоадер будет зря дёргать страницу.
        guard previous?.folder != folder || previous?.digest != digest else { return false }
        // «Раскрасить по кругу» сильнее проекта (критик Б3 плана WF15): окно остаётся
        // неотмеченным, и как только память о нём очистят, проект его покрасит. А вот ручной
        // выбор окно больше не «занимает» — он сам стал видом проекта (решение 3.2 плана WF20).
        guard !isWindowBusy(target.title) else { return false }
        // Панель «Своя тема» владеет примеркой этого окна (решение 1.6 плана WF20): обычная
        // команда `theme` погасила бы её на странице, и ползунок остался бы без цвета.
        // Отпечаток не трогаем — закроют панель, и ближайший тик покрасит окно как обычно.
        guard ClaudeActions.themeEditorTitle != target.title else { return false }
        return commit(self.command(for: target, settings: wanted?.settings, previous: previous),
                      to: target, folder: folder, digest: digest)
    }

    /// Послать команду и запомнить отпечаток. Слать нечего (папку не знаем, а прошлый проект
    /// ничего не ставил) — просто запоминаем.
    @discardableResult
    private func commit(_ command: ProjectPaintCommand, to target: ProjectTarget, folder: String,
                        digest: String) -> Bool {
        if !command.isEmpty, !send(command) { return false }
        marks[target.key] = Mark(match: target.match, title: target.title, folder: folder,
                                 digest: digest, layers: command.setLayers)
        return true
    }

    /// Вид проекта: `.pimpmyclaude.json` из папки, а его нет (или он пуст, или битый) —
    /// **авто-цвет по имени папки** (решение 3.1 плана WF20). Файла авто-цвет не заводит:
    /// он живёт в голове приложения. Папки не знаем — вида нет вовсе, окну достанется одно
    /// снятие чужих слоёв.
    private func wanted(in folder: URL?) -> (settings: ProjectSettings, digest: String)? {
        guard let folder = folder else { return nil }
        if let settings = store.settings(in: folder), !settings.isEmpty {
            return (settings, settings.digest)
        }
        let name = folder.lastPathComponent
        return (ProjectSettings(name: name, theme: .set(AutoPaint.projectTheme(folderName: name))),
                ProjectPaint.autoDigest(name: name))
    }

    /// Отпечаток авто-цвета. С хэшем настроек из файла он совпасть не может — значит переход
    /// «свой вид ⇄ авто-цвет» тик не пропустит.
    static func autoDigest(name: String) -> String { "auto:\(AutoPaint.hue(forName: name))" }

    /// Что послать окну: слои вида проекта (файл или авто-цвет) плюс снятие слоёв, которые
    /// ставил ПРОШЛЫЙ проект, а этот не задаёт. Вида нет вовсе (папку не знаем) = только
    /// снятие (критик Б2 плана WF15).
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

    /// Плашка про папку — один раз на папку (решение 3.2 плана WF20): файл `.pimpmyclaude.json`
    /// заводится молча, и Элвис должен узнать об этом хотя бы однажды. Про битый файл говорим
    /// своим ключом — иначе одна плашка на папку съела бы другую.
    private func notice(_ text: String, folder path: String, broken: Bool = false) {
        let key = broken ? ProjectPaint.brokenPrefix + path : path
        var hints = defaults.dictionary(forKey: ProjectPaint.hintsKey) ?? [:]
        guard hints[key] == nil else { return }
        hints[key] = true
        defaults.set(hints, forKey: ProjectPaint.hintsKey)
        showNotice(text)
    }

    // MARK: - ручной выбор = вид проекта (решение 3.2 плана WF20)

    /// Выбрал в окне проекта тему (шрифт, размер, рамку) — она молча стала видом проекта.
    /// Зовётся из `ClaudeActions.remember` и только при `scope:"window"`: примерка мышью
    /// до `remember` не доходит вовсе, а «Раскрасить по кругу» идёт мимо него.
    ///
    /// `.set` — слой ложится в файл, `.reset` («Как у Claude») — уходит из файла, `.keep` —
    /// не трогаем. Не осталось ни одного слоя — файл удаляется, у проекта снова авто-цвет,
    /// и окно берёт его сразу, не дожидаясь тика (решение 3.3). Папки не знаем — выходим
    /// молча: выбор остаётся местным, как до WF20.
    func noteManualChoice(title: String, theme: Layer<Theme>, font: Layer<Font>,
                          size: Layer<Size>, frame: Layer<Bool>) {
        // Тумблер выключен — покраски по проекту нет вовсе; в чужую папку тем более не пишем.
        guard enabled, let folder = folder(for: title) else { return }
        let old = store.settings(in: folder) ?? ProjectSettings()
        let name = folder.lastPathComponent
        let path = folder.standardizedFileURL.path
        let settings = ProjectSettings(name: name,
                                       theme: ProjectPaint.merged(old.theme, theme),
                                       font: ProjectPaint.merged(old.font, font),
                                       size: ProjectPaint.merged(old.size, size),
                                       frame: ProjectPaint.merged(old.frame, frame))
        // Отпечатки этой папки забываем: остальные её окна перекрасит ближайший тик (≤ 2 с).
        marks = marks.filter { $0.value.folder != path }
        guard !settings.isEmpty else {
            store.remove(from: folder)
            // Файла больше нет — у проекта снова авто-цвет, и окно-инициатор берёт его сразу,
            // иначе оно две секунды стояло бы голым Claude.
            if let target = target(for: title) { repaint(target) }
            return
        }
        switch store.write(settings, to: folder) {
        case .written: notice(MenuModel.projectWritten(name), folder: path)
        case .registry: notice(MenuModel.projectWrittenToRegistry(name), folder: path)
        // Битый файл не перезаписываем «на всякий случай»: в нём могли быть чужие ключи.
        case .broken: notice(MenuModel.projectBroken(name), folder: path, broken: true)
        case .failed: notice(MenuModel.projectWriteFailed(name), folder: path, broken: true)
        }
        // Окну-инициатору — свежий отпечаток: выбранное на нём уже стоит, слать его обратно
        // незачем. Отпечаток берём ТОТ, что посчитает ближайший тик: иначе на битом файле
        // (вид проекта остался авто-цветом) тик тут же перекрасил бы окно.
        guard let target = target(for: title) else { return }
        marks[target.key] = Mark(match: target.match, title: target.title, folder: path,
                                 digest: wanted(in: folder)?.digest ?? "",
                                 layers: ProjectPaint.setLayers(settings))
    }

    /// Покрасить окно прямо сейчас, мимо отпечатка и проверок: файл проекта только что удалили,
    /// и окно должно вернуться к авто-цвету, а не ждать тика.
    private func repaint(_ target: ProjectTarget) {
        guard let wanted = self.wanted(in: target.folder) else { return }
        commit(command(for: target, settings: wanted.settings, previous: marks[target.key]),
               to: target, folder: target.folder?.standardizedFileURL.path ?? "",
               digest: wanted.digest)
    }

    /// Слой файла после ручного выбора: `.set` — записать, `.reset` («Как у Claude») — убрать
    /// слой из файла, `.keep` — не трогать. `null` от ручного выбора в файл не пишем: «в этом
    /// проекте как у Claude» — это и есть отсутствие ключа (решение 3.3 плана WF20).
    static func merged<Value>(_ old: Layer<Value>, _ change: Layer<Value>) -> Layer<Value> {
        switch change {
        case .keep: return old
        case .reset: return .keep
        case .set(let value): return .set(value)
        }
    }

    /// Слои, которые вид проекта СТАВИТ окну: их и снимать, когда окно уйдёт в другой проект.
    static func setLayers(_ settings: ProjectSettings) -> [String] {
        var out: [String] = []
        if case .set = settings.theme { out.append(ProjectSettings.themeKey) }
        if case .set = settings.font { out.append(ProjectSettings.fontKey) }
        if case .set = settings.size { out.append(ProjectSettings.sizeKey) }
        if case .set = settings.frame { out.append(ProjectSettings.frameKey) }
        return out
    }

    // MARK: - папка окна

    /// Папка окна под кнопкой: по заголовку через индекс, а у безымянного окна (главное зовётся
    /// «Claude») — папка главного окна.
    func folder(for title: String) -> URL? {
        if let folder = index.folder(forTitle: title) { return folder }
        return index.mainWindow()?.folder
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

    // MARK: - чистая часть (её же гоняют тесты)

    /// `/Users/elvis/_ElvisProjects/PimpMyClaude` → `~/_ElvisProjects/PimpMyClaude`.
    static func short(path url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        guard path == base || path.hasPrefix(base + "/") else { return path }
        return "~" + path.dropFirst(base.count)
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
