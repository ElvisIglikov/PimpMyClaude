import Foundation

/// Покраска одного окна по проекту: чем адресовать окно и какие слои поставить или снять.
/// Уходит обычной командой `theme` (`scope:"window"`) — нового действия WF15 не заводит,
/// добавляется лишь необязательное поле `match` (решение 1 плана WF15).
struct ProjectPaintCommand: Equatable {
    /// Ключ окна в памяти отпечатков: `main` у главного окна, `c:<id чата>` у опознанного
    /// попапа, `w:<заголовок>` у неопознанного.
    let key: String
    /// Поле `match` — путь страницы главного окна (`/epitaxy/local_…`); nil — адресуем заголовком.
    let match: String?
    /// Поле `chat` — id чата (`local_<uuid>`, план WF29): страница сверяет его со своим и
    /// заголовок не смотрит вовсе. Уходит только той странице, которая сама назвала свой id
    /// в последнем круге probe; nil — адресуем по-старому, заголовком.
    let chat: String?
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
    /// Ключ памяти окна: `main` у главного окна, `c:<id чата>` у окна, которое само назвало
    /// свой чат, `w:<заголовок>` у остальных. Ключ на окно ровно ОДИН — при появлении и потере
    /// id отпечаток переезжает (решение 9 плана WF29). У главного окна он ОБЯЗАН пережить
    /// смену чата: иначе смена папки прошла бы незамеченной, и цвет прошлого проекта остался
    /// бы на окне навсегда (критик Б2 плана WF15).
    let key: String
    /// Путь страницы для поля `match` (главное окно); nil — попап, адресуем заголовком или `chat`.
    let match: String?
    /// id чата окна для поля `chat`; nil — окно себя не назвало, адресуем заголовком.
    let chat: String?
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
    /// Окно, которое само назвало свой чат (план WF29): ключ переживает переименование окна —
    /// переименовали попап, а команды повторной нет.
    static let chatPrefix = "c:"
    /// Заголовок главного окна на вкладке Claude Code — заглушка (probe 04.09, п. 4 плана):
    /// команду по ней не адресуем, а память ручного выбора ключуется именно ею.
    static let mainWindowTitle = "Claude"
    /// Пока открыто меню и столько секунд после его последней команды — молчим: не-preview
    /// команда гасит примерку темы мышью (`endPreviewExcept`, критик В1 плана WF15).
    static let quietSeconds: TimeInterval = 2

    /// Отпечаток окна: какой проект на нём стоит и какие слои поставил.
    private struct Mark: Equatable {
        let match: String?
        /// id чата окна: им же уходит снятие слоёв, когда покраску выключают.
        let chat: String?
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
    /// Что страницы ответили в последнем круге probe (план WF29): «какой во мне чат».
    /// Карта несвежая (канал занят агентом, приложение только стартовало) — пусто, и покраска
    /// попапов уходит на старый путь по заголовку. В `init` канал НЕ лезет: `ProjectPaint`
    /// собирают напрямую тесты, и новый параметр сломал бы им сборку (критик В6 плана WF29).
    var chatPages: () -> [ChatPage] = { [] }
    /// Чат попапа по AX-заголовку окна: ничья по заголовку и заглушки — nil.
    var chatForTitle: (String) -> String? = { _ in nil }
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
            _ = send(ProjectPaintCommand(key: key, match: mark.match, chat: mark.chat,
                                         title: mark.match == nil ? mark.title : "",
                                         theme: undo(mark, ProjectSettings.themeKey),
                                         font: undo(mark, ProjectSettings.fontKey),
                                         size: undo(mark, ProjectSettings.sizeKey),
                                         frame: undo(mark, ProjectSettings.frameKey)))
        }
        marks = [:]
    }

    /// Claude перезапустился: его `localStorage` пуст, а отпечатки у нас прежние — окна
    /// проектов остались бы серыми до перезапуска ПРИЛОЖЕНИЯ (п. 21 плана WF35, ровно это
    /// Элвис и видел после переустановки). Забываем отпечатки и молчим: команд снятия тут
    /// быть не должно — в отличие от `clear()`, окна и так уже голые, а ближайший тик (2 с)
    /// перекрасит их заново.
    func forget() { marks = [:] }

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
    /// окна, сколько окон покрашено проектом и сколько из них опознано по чату.
    var status: String {
        let folder = index.mainWindow()?.folder?.lastPathComponent ?? "—"
        let painted = marks.values.filter { !$0.layers.isEmpty }.count
        let known = marks.keys.filter { $0.hasPrefix(ProjectPaint.chatPrefix) }.count
        return "\(enabled ? "on" : "off")/\(folder)/\(painted)/\(known)"
    }

    /// Окна с известной папкой. Главное — по адресу страницы из `status.json` лоадера, но чат
    /// ему даёт сама страница, если ответила (решение 8 плана WF29). Попапы — по ответам
    /// страниц: назвала страница свой чат, и папка берётся по id, а не по заголовку (задача
    /// #5455: заголовок попапа — снимок имени чата на момент выноса в окно, после
    /// переименования он с индексом не сходится).
    ///
    /// Страница ответила, стор у неё рабочий, а чат назвать не смогла — окно «не определён»:
    /// команды нет, отпечаток не трогаем и папку главного окна не подставляем НИКОГДА.
    /// Ответа нет вовсе (канал занят, стор не нашёлся) — работает старый путь по заголовку.
    private func targets() -> [ProjectTarget] {
        var out: [ProjectTarget] = []
        let pages = chatPages()
        if let main = index.mainWindow() {
            // Свежий ответ страницы сильнее адреса из status.json (решение 8 плана WF29);
            // протухший не в счёт — пусть решает лоадер. Расхождение видно в statusText.
            let answer = pages.first { $0.kind == .main && ChatProbe.isRecent($0, at: now()) }
            // Назвала страница свой чат — он и решает, даже если индекс такого чата не знает:
            // тогда папки просто НЕТ. Откатиться на чат из status.json значило бы покрасить
            // окно цветом чужого проекта — ровно то, на что Элвис пожаловался в #5455
            // (находка 2 проверки WF29: `session.map(…) ?? main.folder` откат как раз давал).
            let named = answer?.chat
            let folder = named == nil
                ? main.folder
                : named.flatMap { index.session(for: $0) }.map(index.folder(of:))
            out.append(ProjectTarget(key: ProjectPaint.mainKey, match: main.match, chat: nil,
                                     title: ProjectPaint.mainWindowTitle, folder: folder))
        }
        var seen = Set<String>()
        // Окна, о которых страница уже сказала всё: по заголовку их больше не ищем.
        var answered = Set<String>()
        for page in pages where page.kind == .popout {
            let clean = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let chat = page.chat else {
                // «Не определён» — только когда стор на странице рабочий: иначе спросить было
                // некого, и заголовок остаётся единственным, что у нас есть.
                if page.store == ChatProbe.storeOK, !clean.isEmpty { answered.insert(clean) }
                continue
            }
            guard seen.insert(ProjectPaint.chatPrefix + chat).inserted else { continue }
            if !clean.isEmpty { answered.insert(clean) }
            out.append(ProjectTarget(key: ProjectPaint.chatPrefix + chat, match: nil, chat: chat,
                                     title: clean, folder: index.folder(for: chat)))
        }
        for title in windowTitles() {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !answered.contains(clean),
                  seen.insert(ProjectPaint.windowPrefix + clean).inserted,
                  let folder = index.folder(forTitle: clean) else { continue }
            out.append(ProjectTarget(key: ProjectPaint.windowPrefix + clean, match: nil, chat: nil,
                                     title: clean, folder: folder))
        }
        return out
    }

    /// Одно окно: сверить отпечаток, при надобности послать команду и запомнить, что послали.
    @discardableResult
    private func paint(_ target: ProjectTarget) -> Bool {
        moveMark(to: target)
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
        guard !ProjectPaint.ownedByEditor(target) else { return false }
        return commit(self.command(for: target, settings: wanted?.settings, previous: previous),
                      to: target, folder: folder, digest: digest)
    }

    /// Послать команду и запомнить отпечаток. Слать нечего (папку не знаем, а прошлый проект
    /// ничего не ставил) — просто запоминаем.
    @discardableResult
    private func commit(_ command: ProjectPaintCommand, to target: ProjectTarget, folder: String,
                        digest: String) -> Bool {
        if !command.isEmpty, !send(command) { return false }
        marks[target.key] = Mark(match: target.match, chat: target.chat, title: target.title,
                                 folder: folder, digest: digest, layers: command.setLayers)
        return true
    }

    /// Ключ на окно ровно ОДИН (решение 9 плана WF29). Появился id — отпечаток ПЕРЕЕЗЖАЕТ
    /// из `w:<заголовок>` в `c:<id>` вместе со слоями; потерялся (страница перезапустила
    /// инжект, стор пропал, канал занят) — обратно. Заведи мы второй отпечаток, окно на каждом
    /// переходе получало бы полную команду заново, а слои прошлого ключа никто бы не снимал.
    ///
    /// Назад `digest` обнуляем нарочно: команда с полем `chat` могла уйти в никуда — отпечаток
    /// пишется сразу после постановки в очередь, а не после того, как страница команду взяла.
    /// Потеряла страница id — ближайший тик пришлёт вид заново, уже заголовком.
    private func moveMark(to target: ProjectTarget) {
        guard target.key != ProjectPaint.mainKey, marks[target.key] == nil,
              !target.title.isEmpty else { return }
        let byChat = target.key.hasPrefix(ProjectPaint.chatPrefix)
        let old: String? = byChat
            ? ProjectPaint.windowPrefix + target.title
            : marks.keys.sorted().first { $0.hasPrefix(ProjectPaint.chatPrefix)
                && marks[$0]?.title == target.title }
        guard let key = old, let mark = marks[key] else { return }
        marks[key] = nil
        marks[target.key] = Mark(match: target.match, chat: target.chat, title: target.title,
                                 folder: mark.folder, digest: byChat ? mark.digest : "",
                                 layers: mark.layers)
    }

    /// Окном владеет панель «Своя тема»? Сверяем КЛЮЧОМ окна (находка 5 проверки WF20):
    /// у цели главного окна стоит заглушка «Claude», а панель видит настоящий заголовок чата —
    /// сверка по заголовку не сходилась, и тик гасил примерку.
    ///
    /// Заголовок при этом остаётся ВТОРОЙ половиной сверки (находка 3 проверки WF29):
    /// `paintableTitles()` отдаёт заголовки всех окон, включая главное, поэтому у главного
    /// окна целей две — `main` и `w:<настоящий заголовок>`; ключ защищает первую, заголовок —
    /// вторую. Он же работает, когда ключа нет вовсе (панель открыта там, где резолвер
    /// не повешен), — как до WF29.
    static func ownedByEditor(_ target: ProjectTarget) -> Bool {
        // Пустой заголовок в сверке не участвует: у панели это состояние «нет заголовка —
        // нет примерки» (`ThemeEditor.drawStatus`), а целей без заголовка бывает несколько.
        if let title = ClaudeActions.themeEditorTitle, !title.isEmpty, title == target.title {
            return true
        }
        guard let key = ClaudeActions.themeEditorKey else { return false }
        return key == target.key
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
        return ProjectPaintCommand(key: target.key, match: target.match, chat: target.chat,
                                   title: target.commandTitle,
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
        guard enabled, let folder = writableFolder(for: title) else { return }
        let old = store.settings(in: folder) ?? ProjectSettings()
        let name = folder.lastPathComponent
        let path = folder.standardizedFileURL.path
        let settings = ProjectSettings(name: name,
                                       theme: ProjectPaint.merged(old.theme, theme),
                                       font: ProjectPaint.merged(old.font, font),
                                       size: ProjectPaint.merged(old.size, size),
                                       frame: ProjectPaint.merged(old.frame, frame))
        // Отпечатки этой папки ГАСИМ, но не забываем (находка 3 проверки WF20): ближайший тик
        // (≤ 2 с) перекрасит остальные её окна, а список поставленных слоёв нужен, чтобы СНЯТЫЙ
        // слой ушёл и с них тоже — иначе шрифт, убранный в одном окне проекта, остался бы висеть
        // в соседнем. Пустой отпечаток с настоящим совпасть не может: у известной папки вид есть
        // всегда (файл или авто-цвет).
        marks = marks.mapValues { mark in
            guard mark.folder == path else { return mark }
            return Mark(match: mark.match, chat: mark.chat, title: mark.title, folder: mark.folder,
                        digest: "", layers: mark.layers)
        }
        if settings.isEmpty {
            // Битый файл не удаляем (находка 1 проверки WF20): разобрать его мы не смогли,
            // а в нём чужие ключи. Говорим об этом плашкой и выходим тем же путём, что и
            // неудачная запись, — выбор остаётся местным.
            if store.isBroken(in: folder) {
                notice(MenuModel.projectBroken(name), folder: path, broken: true)
            } else {
                store.remove(from: folder)
                // Файла больше нет — у проекта снова авто-цвет, и окно-инициатор берёт его сразу,
                // иначе оно две секунды стояло бы голым Claude.
                if let target = target(for: title) { repaint(target) }
                return
            }
        } else {
            switch store.write(settings, to: folder) {
            case .written: notice(MenuModel.projectWritten(name), folder: path)
            case .registry: notice(MenuModel.projectWrittenToRegistry(name), folder: path)
            // Битый файл не перезаписываем «на всякий случай»: в нём могли быть чужие ключи.
            case .broken: notice(MenuModel.projectBroken(name), folder: path, broken: true)
            case .failed: notice(MenuModel.projectWriteFailed(name), folder: path, broken: true)
            }
        }
        // Окну-инициатору — свежий отпечаток: выбранное на нём уже стоит, слать его обратно
        // незачем. Отпечаток берём ТОТ, что посчитает ближайший тик: иначе на битом файле
        // (вид проекта остался авто-цветом) тик тут же перекрасил бы окно.
        guard let target = target(for: title) else { return }
        marks[target.key] = Mark(match: target.match, chat: target.chat, title: target.title,
                                 folder: path, digest: wanted(in: folder)?.digest ?? "",
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

    /// Папка, в файл которой можно ЗАПИСАТЬ ручной выбор. Тут запас «а возьмём главное окно»
    /// опасен (находка 2 проверки WF20): попап обычного чата claude.ai в индексе не значится,
    /// и его тема молча уехала бы в проект главного окна, перекрасив все его окна. Поэтому
    /// запас только у безымянного окна и у заглушки «Claude» — то есть у самого главного окна;
    /// у окна с настоящим заголовком папка берётся строго из индекса, а нет её — выбор
    /// остаётся местным (решение 3.6 плана WF20, строка «Окно без папки»).
    private func writableFolder(for title: String) -> URL? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != ProjectPaint.mainWindowTitle else {
            return index.mainWindow()?.folder
        }
        // Сперва чат окна (план WF29): по нему папка верна и после переименования чата,
        // а заголовок попапа — снимок имени на момент выноса в окно.
        if let chat = chatForTitle(clean), let folder = index.folder(for: chat) { return folder }
        return index.folder(forTitle: clean)
    }

    /// Как адресовать окно под кнопкой: назвало свой чат — полем `chat`, иначе попап — своим
    /// заголовком, а безымянное окно — путём страницы главного окна.
    private func target(for title: String) -> ProjectTarget? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let chat = chatForTitle(clean), let folder = index.folder(for: chat) {
            return ProjectTarget(key: ProjectPaint.chatPrefix + chat, match: nil, chat: chat,
                                 title: clean, folder: folder)
        }
        if let folder = index.folder(forTitle: clean) {
            return ProjectTarget(key: ProjectPaint.windowPrefix + clean, match: nil, chat: nil,
                                 title: clean, folder: folder)
        }
        guard let main = index.mainWindow() else { return nil }
        return ProjectTarget(key: ProjectPaint.mainKey, match: main.match, chat: nil,
                             title: ProjectPaint.mainWindowTitle, folder: main.folder)
    }

    /// Ключ окна по AX-заголовку — тот же резолвер, что и у целей покраски. Им панель
    /// «Своя тема» помечает, каким окном владеет (находка 5 проверки WF20): у главного окна
    /// заголовок бывает настоящим заголовком чата, а в цели покраски стоит заглушка «Claude».
    func windowKey(forTitle title: String) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != ProjectPaint.mainWindowTitle else {
            return ProjectPaint.mainKey
        }
        if let main = index.mainWindow()?.session?.title, main == clean {
            return ProjectPaint.mainKey
        }
        if let chat = chatForTitle(clean) { return ProjectPaint.chatPrefix + chat }
        return ProjectPaint.windowPrefix + clean
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
