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

/// «💬 Новый чат» (#7072, контракт К2 плана WF84): что добавить к команде `new-window`.
/// `model` и `effort` — подписи меню Claude («Opus 5.5», «Extra»); nil — поля нет, и страница
/// ничего не трогает (у донора Auto или чат неизвестен). `stay` — новый чат остаётся в главном
/// окне: без попапа и без возврата.
struct NewChatHandoff: Equatable {
    var model: String?
    var effort: String?
    var stay: Bool
    /// Чат-донор (#7246): новый чат страница закрепляет, донора — открепляет («наверху только
    /// живой чат», решение Элвиса 23.09 по умолчанию). nil — донора не знаем, только закрепка.
    var unpin: String? = nil
    /// Текст передачи — из записи «Обкэшить» (`sendTransfer`). false — у «Замени окно» канала
    /// (`renew-window`, WF102 C1): записи нет, первым сообщением идёт текст самой команды.
    var transfer = true
    /// Закреплять ли новый чат (`pin`/`unpin` команды). false — у «Замени окно» канала (WF181,
    /// #9225, слово Элвиса 09.10: «Не закрепляй. Вот пин не делай»): закрепки не трогаем вовсе.
    var pin = true

    /// Из модели донора — общим правилом имени (`SessionModel.menuModel`), а не таблицей.
    /// `autoChosenInApp` значит «донор на Auto»: модель не шлём, эффорт — как у донора.
    static func from(_ session: SessionModel?, stay: Bool, unpin: String? = nil) -> NewChatHandoff {
        NewChatHandoff(model: session.flatMap { $0.auto ? nil : $0.menuModel },
                       effort: session?.menuEffort, stay: stay, unpin: unpin)
    }
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
        case .cashout: whenCashoutIdle(for: target) { [weak self] in self?.cashout(target) }
        // Заголовок читаем здесь: по нему «Новый чат» решает, ⌘N это или окно рядом (#5734).
        case .newChat:
            newChatCommand(target, title: target.flatMap { AX.string($0, kAXTitleAttribute) } ?? "")
        case .newWindow:
            guard !refuseNewWindowRepeat() else { return }
            whenBlankIdle { [weak self] in self?.newWindow(target) }
        case .popoutWindow: popoutWindow(target)
        case .collapse: stage("collapse", target)
        case .expand: stage("expand", target)
        // ⌥⌘A и «▦ Расставить» — умный путь (план WF77); плитку ставят только рукой.
        case .arrange: arrangeSmart()
        case .show: showAll(target)
        // «Прокрутить» адресована всем окнам сразу — фокус не нужен.
        case .scroll: commands.write(action: "scroll")
        // К3: выключатель всем страницам, без фокуса и Accessibility.
        case .autoAllow: sendAutoAllow(autoAllowOn())
        // Режим кружка-микрофона (К4): тот же, что держит `MicMonitor`, ещё раз во все окна.
        case .mic: sendMic(micMode())
        }
    }

    // MARK: - режим кружка-микрофона (контракт К4 плана WF84, #7054)

    /// Режим, который сейчас положен страницам: `dictator`, пока запущен Диктатор. Живьём
    /// вешает `ClaudeAXController` на `MicMonitor`.
    var micMode: () -> MicMode = { .claude }

    /// Команда `mic` `{mode:"dictator"|"claude"}` во все окна: страница кладёт режим в свой
    /// `localStorage` и в режиме `dictator` клик по кружку не жмёт родную диктовку — клавишу
    /// Диктатора жмёт приложение (`MicMonitor`).
    @discardableResult
    func sendMic(_ mode: MicMode) -> Bool {
        commands.write(action: ClaudeCommand.mic.rawValue, fields: mode.fields)
    }

    /// Команда `dictating {on}` (#8112): Диктатор пишет — окно с фокусом ярко светится (страница, раздел 12и).
    @discardableResult
    func sendDictating(_ on: Bool) -> Bool {
        commands.write(action: "dictating", fields: [(key: "on", value: .bool(on))])
    }

    /// Команда `mic-refused` `{reason:"recording", chat, match}` (контракт WF92 (а), #7704):
    /// нажали кружок, а Диктатор уже пишет — принимает только нажатая страница (свой чат, при
    /// chat=null — свой заголовок, и своё нажатие не старше 4 с): сбрасывает счёт и показывает подсказку.
    @discardableResult
    func sendMicRefused(chat: String?, match: String) -> Bool {
        commands.write(action: MicMonitor.refusedAction, fields: MicMonitor.refusedFields(chat: chat, match: match))
    }

    // MARK: - выключатель Авто-Allow (К3, WF121)

    /// Текущее состояние тумблера у часов; подключает ClaudeAXController.
    var autoAllowOn: () -> Bool = { false }

    @discardableResult
    func sendAutoAllow(_ on: Bool) -> Bool {
        commands.write(action: ClaudeCommand.autoAllow.rawValue, fields: AutoAllowSwitch.fields(on: on))
    }

    // MARK: - страничные команды

    /// «Автосвёртка» (#6666): память — UserDefaults приложения, странице уходит команда
    /// `auto-collapse` всем окнам; свою копию флага страница держит в localStorage.
    var autoCollapseEnabled: Bool { UserDefaults.standard.bool(forKey: MenuModel.autoCollapseKey) }

    func setAutoCollapse(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: MenuModel.autoCollapseKey)
        commands.write(action: "auto-collapse", extra: ["on": on ? "true" : "false"])
    }

    /// «🙈 Прятать инструменты» (WF120, #7976, К-B1) — как «Автосвёртка»: память в UserDefaults,
    /// всем окнам команда `hide-tools` строкой мимо enum; свою копию флага страница держит в localStorage.
    var hideToolsEnabled: Bool { UserDefaults.standard.bool(forKey: MenuModel.hideToolsKey) }

    func setHideTools(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: MenuModel.hideToolsKey)
        commands.write(action: "hide-tools", extra: ["on": on ? "true" : "false"])
    }

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
            self.whenIdentified(title: title, frame: AX.frame(window)) {
                guard let route = self.windowRoute(title: title, frame: AX.frame(window)) else { return }
                switch route {
                case .main:
                    // Как и было по смыслу, только адрес точнее: путь страницы главного окна
                    // (`match`) не даст команде уйти веером безымянным попапам (критик Б1 WF15).
                    // Домашний экран (пути чата нет) адресуется путём `/epitaxy`: заголовком
                    // «Claude» команду взял бы и безымянный попап (проверка WF37, находка 4).
                    self.commands.write(action: "cashout",
                                        fields: ClaudeActions.cashoutFields(
                                            title: title, match: self.windowIdentity?(title, AX.frame(window)).page?.path
                                                ?? self.mainWindowMatch() ?? ChatProbe.homePath))
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
    ///
    /// Новое окно ЗАМЕНЯЕТ старое (#5768, слово Элвиса 08.09 11:40: «Обкэшить — это же
    /// значит, что откроется новое окно и оно заменит полностью старое»): рамку донора
    /// снимаем сейчас, пока окно живо, и его угол уходит в команду точкой — окно рождается
    /// сразу на месте старого (заодно уходит обрезка `popoutOrigin` по главному экрану).
    /// Донор закрывается не здесь и не по факту появления окна, а когда страница подтвердила
    /// доезд текста (`cashoutTick`, #5779).
    private func cashoutNewWindow(from window: AXUIElement, chat: String?,
                                  handoff: NewChatHandoff? = nil) {
        let project = chat.flatMap { projectForChat($0) }
        if let project = project { onProjectUsed?(project) }
        let donor = AX.frame(window)
        beginCashoutReplace(donor: donor, window: window, handoff: handoff != nil)
        newWindow(window, project: project, origin: ClaudeActions.cashoutOrigin(donor: donor),
                  transfer: true, handoff: handoff)
    }

    // MARK: - «💬 Новый чат» на ⌘B (#7072, контракты К1 и К2 плана WF84)

    /// Модель и эффорт чата из его файла сессии (`ProjectIndex`). Живьём вешает контроллер;
    /// nil — чат не знаем, и новый чат возьмёт то, что стоит в домашнем поле Claude.
    var chatModel: (String) -> SessionModel? = { _ in nil }
    /// Чат главного окна (id сессии) — из индекса. Живьём вешает контроллер.
    var mainChat: () -> String? = { nil }

    /// «💬 Новый чат» первым пунктом меню на кнопке боковой панели (⌘B): тот же проект, та же
    /// модель и эффорт, текст передачи из блока «ОТКРОЙ НОВЫЙ ЧАТ» последнего ответа уходит
    /// первым сообщением (ответ Элвиса 6.1: «сразу отправлять»); блока нет — пустой чат.
    ///
    /// Скелет — «Обкэшить» (WF37): сперва `cashout` с `handoff` (страница кладёт текст
    /// передачи в запись), потом `new-window`. Из попапа новое окно рождается в углу донора
    /// и занимает его рамку, донор закрывается ТОЛЬКО по слову новой страницы «вставлено»
    /// (`cashoutTick`); страница говорит его сразу, раз текст уже ушёл (`sent:true`) или его
    /// нет. Из главного окна — `stay:true`: новый чат остаётся здесь же, ни попапа, ни
    /// возврата (главное окно не закрыть — в нём список чатов).
    func handoffNewChat(_ window: AXUIElement?) {
        noteUserCommand()
        guard let window = window ?? focusedWindow() else { return }
        whenCashoutIdle(for: window) { [weak self] in self?.handoff(from: window) }
    }

    private func handoff(from window: AXUIElement) {
        app.focus(window: window)
        after(focusDelay) { [weak self] in
            guard let self = self else { return }
            let title = AX.string(window, kAXTitleAttribute) ?? ""
            let frame = AX.frame(window)
            self.whenIdentified(title: title, frame: frame) {
                // Главное окно — и по рамке страницы главного окна (#7378): резолвер по заголовку
                // мог не узнать его, и тогда донором стало бы окно со списком чатов.
                guard let route = self.windowRoute(title: title, frame: frame) else { return }
                switch route {
                case .main:
                    let chat = self.windowIdentity.map { $0(title, frame).page?.chat } ?? self.mainChat()
                    self.commands.write(action: ClaudeCommand.cashout.rawValue,
                                        fields: ClaudeActions.cashoutFields(
                                            title: title, match: self.windowIdentity?(title, frame).page?.path
                                                ?? self.mainWindowMatch() ?? ChatProbe.homePath,
                                            handoff: true))
                    let project = chat.flatMap { self.projectForChat($0) }
                    if let project = project { self.onProjectUsed?(project) }
                    let handoff = NewChatHandoff.from(chat.flatMap { self.chatModel($0) }, stay: true, unpin: chat)
                    self.after(self.cashoutNewChatDelay) {
                        self.newWindow(window, project: project, handoff: handoff)
                    }
                case .popout(let chat):
                    self.commands.write(action: ClaudeCommand.cashout.rawValue,
                                        fields: ClaudeActions.cashoutFields(title: title, chat: chat,
                                                                            handoff: true))
                    let handoff = NewChatHandoff.from(chat.flatMap { self.chatModel($0) }, stay: false, unpin: chat)
                    self.after(self.cashoutNewChatDelay) {
                        self.cashoutNewWindow(from: window, chat: chat, handoff: handoff)
                    }
                }
            }
        }
    }

    // MARK: - замена окна на «Обкэшить» (#5768; закрытие по доезду — #5779)

    /// Работа «Обкэшить»: чьё место занимает новое окно и какие окна были ДО ⌘N — по ним
    /// отсеиваются чужие окна, родившиеся в те же секунды (окно от канала «Пимп», вынос
    /// другого чата, разворот свёрнутого).
    private struct CashoutJob {
        let donor: CGWindowID
        /// AX-окно донора, снятое ДО ⌘N (живой гейт WF85): закрываем именно его — см.
        /// `cashoutDonorToClose`.
        let window: AXUIElement
        let frame: CGRect
        let before: Set<CGWindowID>
        let startedAt: Date
        /// «💬 Новый чат» (кнопка, ссылка, «сам»): текст живёт в ответе донора, а не в его поле,
        /// и доезд подтверждает ещё и главное окно (`handoffSent`, #7378).
        var handoff = false
        /// Новое окно уже встало на место донора сразу при рождении (WF98, #7841).
        var placed = false
    }

    private var cashoutJob: CashoutJob?
    /// Цепочка «Обкэшить» / «💬 Новый чат» выпущена, а работы ещё нет: между выпуском и
    /// `beginCashoutReplace` фокус 0,1 с и 1,2 с до нового окна — в эту щель второе нажатие
    /// проскочило бы и подменило работу первого (проверка wf93-n2).
    private var cashoutReservedAt: Date?
    /// Сколько держится бронь без работы: 1,3 с хода до `beginCashoutReplace` с запасом на
    /// занятый главный поток. Главное окно работы не заводит — его бронь просто истекает.
    static let cashoutReserveSeconds: TimeInterval = 5

    /// Идёт ли перенос прямо сейчас. По нему канал probe работает при любом тумблере и
    /// спрашивает страницы чаще (`ChatProbe.isCashoutPending`): пока перенос в пути, ответ
    /// страницы решает судьбу окна с текстом Элвиса.
    var cashoutPending: Bool {
        if cashoutJob != nil { return true }
        guard let reserved = cashoutReservedAt else { return false }
        return clock().timeIntervalSince(reserved) < ClaudeActions.cashoutReserveSeconds
    }

    /// Окна для переноса — живьём `pimpWindows`, тесты подменяют (шов `cashoutTick`).
    lazy var cashoutWindows: () -> [(id: CGWindowID, window: AXUIElement, title: String, frame: CGRect)]
        = { [unowned self] in self.pimpWindows() }
    /// Закрыть окно донора — живьём `AX.close`, тесты подменяют.
    var closeWindow: (AXUIElement) -> Bool = { AX.close($0) }

    /// Один перенос за раз (проверка wf93-n2): два «Новых чата» подряд из разных попапов (два
    /// отсчёта «сам», два клика) подменяли работу первого, и закрыться мог не тот донор.
    /// Второй ждёт конца первого опросом, не дольше `cashoutWaitSeconds`, потом отказ плашкой.
    /// Дальше — замок пустого окна, и уже на выпуске цепочка бронирует перенос.
    ///
    /// `window` — донор (WF97 Б5s, #7772): второе нажатие на ТОМ ЖЕ окне, пока его перенос идёт,
    /// забронирован или ждёт очереди, — без последствий, только плашка «уже открываю». Иначе
    /// оно дождалось бы конца первого и перенесло бы уже новый чат ещё раз.
    func whenCashoutIdle(since start: Date? = nil, for window: AXUIElement? = nil,
                         _ block: @escaping () -> Void) {
        if start == nil, let window = window {
            guard !cashoutClaimed(window) else {
                onNotice?(MenuModel.cashoutRepeatNotice, MenuModel.repeatNoticeSeconds)
                return
            }
            cashoutWaiting.append(window)
        }
        let start = start ?? clock()
        let unclaim = { [weak self] in
            guard let self = self, let window = window else { return }
            self.cashoutWaiting.removeAll { CFEqual($0, window) }
        }
        // Цепочку «Нового окна» (⌥⌘N, канал) тоже ждём (z2-r02): страница второй запуск отбивает,
        // и перенос повис бы без адресата.
        guard cashoutPending || newWindowChainRunning else {
            return whenBlankIdle { [weak self] in
                guard let self = self else { return }
                // Пока ждали пустое окно, перенос мог начать другой — снова в очередь.
                guard !self.cashoutPending else { return self.whenCashoutIdle(since: start, for: window, block) }
                unclaim()
                // Метку прогрева только что поставил выпуск `whenBlankIdle` — она наша.
                self.cashoutNewWindowAt = self.lastNewWindowAt
                self.cashoutReservedAt = self.clock()
                self.cashoutReservedWindow = window
                block()
            }
        }
        guard clock().timeIntervalSince(start) < ClaudeActions.cashoutWaitSeconds else {
            unclaim()
            onWarning?(MenuModel.cashoutBusyNotice)
            return
        }
        after(BlankWindow.pollSeconds) { [weak self] in self?.whenCashoutIdle(since: start, for: window, block) }
    }

    /// Окна, чей перенос ждёт очереди (`whenCashoutIdle`), и окно последней брони.
    private var cashoutWaiting: [AXUIElement] = []
    private var cashoutReservedWindow: AXUIElement?

    /// Перенос этого окна уже идёт, забронирован или стоит в очереди.
    func cashoutClaimed(_ window: AXUIElement) -> Bool {
        if let job = cashoutJob, CFEqual(job.window, window) { return true }
        if cashoutPending, let reserved = cashoutReservedWindow, CFEqual(reserved, window) { return true }
        return cashoutWaiting.contains { CFEqual($0, window) }
    }

    /// Сколько ждём доезда текста. Не «на глаз», а СУММА пауз худшего честного хода цепочки
    /// (правило ElvisOS, #5785): 0,1 с фокус → 0,6 с очередь канала → 0,5 с опрос
    /// `command.json` лоадером → 0,8 с до ⌘N → 95 с сторож цепочки «Нового окна» на странице
    /// (`NEW_WINDOW_GUARD_MS`: домашний экран 5 + папка 10 + отправка 3 + сессия 15 + строка
    /// сайдбара 21,5 + имя 7,5 + возврат 1, плюс её собственный запас) → ~6,9 с на вставку с
    /// подтверждением в новом окне (сторож 0,3 с + ожидание чужого черновика 1,8 с + два
    /// способа вставки, 12 и 20 повторов по 150 мс) → ~9 с на круг probe (пол частоты 4 с +
    /// опрос лоадера 2 с + обход страниц + общий тик 2 с). Итого 113 с, округлено вверх.
    /// Всё это время донор ЖИВ: цена ожидания — лишнее окно на экране, цена спешки —
    /// потерянный текст.
    /// С WF84 (К2, «💬 Новый чат») сторож страницы вырос с 95 до 110 с — модель с «More
    /// models» и сверкой ≈ 4,5 с, эффорт ≈ 4 с, запись передачи 3 с: 113 + 15 = 128, вверх до 135.
    static let cashoutWaitSeconds: TimeInterval = 135

    /// Пауза между рамкой нового окна и закрытием донора: свежее окно нельзя спрашивать
    /// сразу после смены рамки — её ставит оконный сервер, а Electron перерисовывает окно
    /// своим ходом (урок ElvisOS, #5784).
    static let cashoutSettlePause: TimeInterval = 0.35

    /// Словарь доезда со страницей (`status().cashout.delivery`, `inject.js` раздел 12):
    /// `"ждём"` — перенос в пути, `"вставлено"` — текст лёг в поле, `"отказ: <причина>"` —
    /// приговор с причиной. Ничего другого приложение за конец работы не считает.
    static let cashoutLanded = "вставлено"
    static let cashoutRefusedPrefix = "отказ:"

    /// Что говорят страницы о доезде переноса.
    enum CashoutDelivery: Equatable {
        /// Никто ещё не сказал ни «доехало», ни «не доедет» — ждём.
        case waiting
        /// Текст лёг в поле; заголовок — у той страницы, которая это сказала (она и есть
        /// адресат переноса, чужая страница такого ответа дать не может).
        case landed(title: String)
        /// Приговор с причиной: закрывать нечего и незачем.
        case refused(String)
    }

    /// Куда рождать новое окно: РОВНО в угол донора, без уступа и без обрезки по экрану —
    /// оно встаёт на место старого. Рамки донора нет (AX молчит) — прежняя точка от угла
    /// экрана, и замены не будет вовсе.
    static func cashoutOrigin(donor frame: CGRect?) -> (x: Int, y: Int) {
        guard let frame = frame else { return popoutWindowFallback }
        return (Int(frame.origin.x.rounded()), Int(frame.origin.y.rounded()))
    }

    /// Приговор по ответам страниц — чистый, его и гоняют тесты. «Вставлено» сильнее любого
    /// отказа: отказ мог прийти от СОСЕДНЕЙ страницы, которой перенос не адресован.
    ///
    /// `since` — начало работы: ответы круга, пришедшего РАНЬШЕ нажатия, о нашем переносе
    /// сказать ничего не могут (страница тогда ещё не видела записи), а сказать «вставлено»
    /// о прошлом переносе — могут. Такой круг мы не слушаем вовсе (находка гейта WF50):
    /// иначе два «Обкэшить» подряд закрывали бы второго донора по ответу про первый.
    static func cashoutDelivery(pages: [ChatPage], since: Date? = nil) -> CashoutDelivery {
        let pages = since.map { start in pages.filter { $0.at >= start } } ?? pages
        for page in pages where page.cashout == cashoutLanded {
            return .landed(title: page.title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for page in pages {
            guard let said = page.cashout, said.hasPrefix(cashoutRefusedPrefix) else { continue }
            let why = said.dropFirst(cashoutRefusedPrefix.count)
                .trimmingCharacters(in: .whitespaces)
            return .refused(why.isEmpty ? MenuModel.cashoutNoAnswerReason : why)
        }
        return .waiting
    }

    /// Наше ли это окно (#5779): среди окон, которых до ⌘N не было, ровно одно с заголовком
    /// той страницы, что назвалась адресатом переноса. Заголовок пустой, совпадений ноль или
    /// больше одного — nil: чужое окно, родившееся в те же секунды (окно канала «Пимп»,
    /// вынос другого чата, служебные окна Electron 800×600 без заголовка), не должно ни
    /// занимать рамку донора, ни закрывать его.
    static func cashoutFresh(title: String, before: Set<CGWindowID>,
                             windows: [(id: CGWindowID, title: String)]) -> CGWindowID? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // «Loading» — заголовок любого свежего попапа до имени чата: по нему окно не наше (WF93).
        guard !wanted.isEmpty, !ProjectIndex.isLoadingTitle(wanted) else { return nil }
        let hits = windows.filter {
            !before.contains($0.id)
                && $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == wanted
        }
        return hits.count == 1 ? hits.first?.id : nil
    }

    /// Закрывать ли донора: только когда новое окно правда другое и донор ещё на экране
    /// (Элвис мог закрыть его сам, пока шла работа).
    static func cashoutCloses(donor: CGWindowID, fresh: CGWindowID, onScreen: [CGWindowID]) -> Bool {
        donor != fresh && onScreen.contains(donor)
    }

    /// Какое AX-окно закрыть донором (живой гейт WF85, 24.09): запомненное ДО ⌘N, а не пару
    /// «номер Quartz → AX» после переезда. Новое окно встаёт РОВНО в рамку донора, пары по
    /// рамке (`pimpWindows`) путаются — и закрывалось НОВОЕ окно, а донор оставался. Совпало с
    /// новым — не закрываем ничего.
    static func cashoutDonorToClose<W>(stored: W, fresh: W, same: (W, W) -> Bool) -> W? {
        same(stored, fresh) ? nil : stored
    }

    /// Что страницы сказали о доезде переноса — карта probe (задача #5779). Живьём вешает
    /// `ClaudeAXController`; без него ответов нет вовсе, и донор не закрывается НИКОГДА:
    /// это и есть безопасная деградация — текст Элвиса дороже лишнего окна на экране.
    var cashoutAnswers: () -> [ChatPage] = { [] }

    /// Запомнить работу до ⌘N: номера окон Quartz, номер донора и его рамка. Донора не нашли
    /// в списке окон (AX не отдал пары) — работы нет, и «Обкэшить» ведёт себя как до #5768.
    func beginCashoutReplace(donor frame: CGRect?, window: AXUIElement, handoff: Bool = false) {
        cashoutJob = nil
        cashoutReservedAt = nil
        cashoutReservedWindow = nil
        guard let frame = frame else { return }
        let windows = cashoutWindows()
        guard let donor = windows.first(where: { CFEqual($0.window, window) })?.id else { return }
        cashoutJob = CashoutJob(donor: donor, window: window, frame: frame,
                                before: Set(windows.map { $0.id }), startedAt: clock(), handoff: handoff)
        if let ids = windowIDs, let job = cashoutJob {
            cashoutWatch = BirthWatch(seen: ids())
            watchCashoutBirth(job.startedAt)
        }
    }

    // MARK: - окно «Обкэшить» сразу на месте донора (WF98, #7841)

    /// Номера окон Claude на экране (`onScreenIDs`) — опрос рождения окна. nil — опроса нет, окно
    /// встаёт на место донора по «вставлено», как до WF98. Живьём вешает `connectNewWindowPlace`.
    var windowIDs: (() -> Set<CGWindowID>)?
    /// Идёт возврат окон (снимок «окна как были», раскладка): новое окно тогда не ставим — возврат
    /// сам открывает окна, и «единственное новое» могло оказаться его окном. Живьём вешает контроллер.
    var isRestoringWindows: () -> Bool = { false }
    /// Поставить свежему окну рамку. Живьём — `setFrame(fresh:true)`; тесты подменяют.
    var placeFresh: (AXUIElement, CGRect) -> Void = { ClaudeActions.setFrame($0, $1, fresh: true) }
    private var cashoutWatch: BirthWatch?

    /// Опрос рождения нового окна переноса: единственное новое окно встаёт в рамку донора сразу,
    /// а не через тик после «вставлено». Донор закрывается по-прежнему только по «вставлено»
    /// (#5779). Двух новых окон разом — не гадаем, какое наше: ставит `cashoutReplace` по заголовку.
    /// Пошёл возврат окон — опрос бросаем совсем: его окна тоже новые, и «единственное новое»
    /// могло бы оказаться чужим; окно встанет по «вставлено», по заголовку, как до WF98.
    private func watchCashoutBirth(_ startedAt: Date) {
        after(BirthWatch.pollSeconds) { [weak self] in
            guard let self = self, let job = self.cashoutJob, job.startedAt == startedAt, !job.placed,
                  var watch = self.cashoutWatch, let ids = self.windowIDs, !self.isRestoringWindows(),
                  self.clock().timeIntervalSince(startedAt) < PimpChannel.newWindowSeconds else { return }
            let look = watch.worthLooking(ids(), at: self.clock())
            self.cashoutWatch = watch
            if look {
                self.app.forgetWindows()
                let windows = self.cashoutWindows()
                let fresh = windows.filter { !job.before.contains($0.id) && $0.id != job.donor }
                if fresh.count > 1 { return }
                if let born = fresh.first {
                    self.cashoutJob?.placed = true
                    AX.timeout(born.window, ClaudeActions.axWindowTimeout)
                    self.placeFresh(born.window, job.frame)
                    self.onWindowsMoved?()
                    return
                }
            }
            self.watchCashoutBirth(startedAt)
        }
    }

    /// Общий тик 2 с, пока идёт перенос (своего таймера у него нет — зовёт `ClaudeAXController`).
    ///
    /// Донор закрывается ТОЛЬКО по подтверждению доезда (#5779): между «окно появилось» и
    /// «текст лёг в поле» у страницы пять путей отказа, и закрытие по факту появления окна
    /// стоило бы Элвису текста навсегда. Пришёл приговор — не закрываем ничего и говорим
    /// причину; не пришло ничего за потолок — тоже не закрываем.
    func cashoutTick(at: Date? = nil) {
        guard let job = cashoutJob else { return }
        let now = at ?? clock()
        let pages = cashoutAnswers()
        switch ClaudeActions.cashoutDelivery(pages: pages, since: job.startedAt) {
        case .refused(let why):
            // Приговор: доезда не будет. Молча выходить нельзя — это «кнопка не работает»
            // (урок ElvisOS, #5784).
            cashoutJob = nil
            onWarning?(MenuModel.cashoutKeptNotice(why))
        case .landed(let title):
            let windows = cashoutWindows()
            // «Новый чат»: страница, сказавшая «вставлено», могла назваться чужим заголовком
            // (#7378) — тогда годится единственное новое окно.
            guard let fresh = ClaudeActions.cashoutFresh(
                title: title, before: job.before,
                windows: windows.map { (id: $0.id, title: $0.title) })
                ?? (job.handoff ? ClaudeActions.onlyNewWindow(before: job.before, donor: job.donor,
                                                               windows: windows.map { $0.id }) : nil) else {
                // Текст доехал, а окна с этим заголовком на экране ещё нет (AX отдаёт имя
                // не сразу) — ждём до потолка и донора не трогаем.
                cashoutGiveUp(job, now: now, windows: windows)
                return
            }
            cashoutJob = nil
            cashoutReplace(job, fresh: fresh, windows: windows)
        case .waiting:
            // «Новый чат» из попапа (#7378): свежий попап мог назвать себя прошлым чатом и
            // молчать. Тогда слово даёт главное окно — его цепочка этого нажатия вынесла чат в
            // окно, и текст передачи ушёл первым сообщением; окно — единственное новое.
            if job.handoff, ClaudeActions.handoffSent(pages: pages, since: job.startedAt) {
                let windows = cashoutWindows()
                if let fresh = ClaudeActions.onlyNewWindow(before: job.before, donor: job.donor,
                                                          windows: windows.map { $0.id }) {
                    cashoutJob = nil
                    cashoutReplace(job, fresh: fresh, windows: windows)
                    return
                }
                cashoutGiveUp(job, now: now, windows: windows)
                return
            }
            cashoutGiveUp(job, now: now, windows: nil)
        }
    }

    /// Родился ли «Новый чат» и ушёл ли его текст — по слову ГЛАВНОГО окна (#7378): его цепочка
    /// «Нового окна» ЭТОГО нажатия (штамп не раньше начала работы) дошла до выноса чата в окно
    /// (`step: back`), и текст передачи ушёл первым сообщением (`send`) или его не было
    /// (`empty`). `held` (модель не встала, текст ждёт вставки в новом окне) — не довод: там
    /// слово за новой страницей.
    static func handoffSent(pages: [ChatPage], since: Date) -> Bool {
        pages.contains { page in
            guard page.kind == .main, page.at >= since, let run = page.newWindow else { return false }
            return run.at >= since && run.step == "back" && !run.chat.isEmpty
                && (run.handoff == "send" || run.handoff == "empty")
        }
    }

    /// Единственное окно, которого до ⌘N не было (и не донор); ноль или два — nil: чужое окно
    /// тех же секунд не должно ни занять рамку донора, ни закрыть его.
    static func onlyNewWindow(before: Set<CGWindowID>, donor: CGWindowID, windows: [CGWindowID]) -> CGWindowID? {
        let fresh = windows.filter { !before.contains($0) && $0 != donor }
        return fresh.count == 1 ? fresh.first : nil
    }

    /// Потолок вышел — бросаем работу и говорим правду о том, чего не дождались. Донора не
    /// трогаем ни в одном случае.
    private func cashoutGiveUp(_ job: CashoutJob, now: Date,
                               windows: [(id: CGWindowID, window: AXUIElement,
                                          title: String, frame: CGRect)]?) {
        guard now.timeIntervalSince(job.startedAt) >= ClaudeActions.cashoutWaitSeconds else { return }
        cashoutJob = nil
        let live = windows ?? cashoutWindows()
        let born = live.contains { !job.before.contains($0.id) }
        onWarning?(born ? MenuModel.cashoutKeptNotice(MenuModel.cashoutNoAnswerReason)
                        : MenuModel.cashoutNoWindowNotice)
    }

    /// Текст доехал: новое окно занимает место донора, и только потом донор закрывается.
    /// Порядок и пауза — урок ElvisOS (#5784): исходное окно портим ПОСЛЕДНИМ действием, а
    /// свежее окно не трогаем сразу после смены рамки.
    private func cashoutReplace(_ job: CashoutJob, fresh: CGWindowID,
                                windows: [(id: CGWindowID, window: AXUIElement,
                                           title: String, frame: CGRect)]) {
        guard let born = windows.first(where: { $0.id == fresh }) else { return }
        AX.timeout(born.window, ClaudeActions.axWindowTimeout)
        // Окно родилось секунду назад — рамка ставится порядком свежего окна (#5791). Встало на
        // место ещё при рождении (WF98) и так и стоит — второй раз его не дёргаем.
        if !(job.placed && ClaudeActions.frameMatches(born.frame, job.frame)) {
            placeFresh(born.window, job.frame)
            onWindowsMoved?()
        }
        after(ClaudeActions.cashoutSettlePause) { [weak self] in
            guard let self = self else { return }
            let live = self.cashoutWindows()
            guard ClaudeActions.cashoutCloses(donor: job.donor, fresh: fresh,
                                              onScreen: live.map { $0.id }),
                  let donor = ClaudeActions.cashoutDonorToClose(stored: job.window, fresh: born.window,
                                                                same: { CFEqual($0, $1) }) else { return }
            AX.timeout(donor, ClaudeActions.axWindowTimeout)
            // Перепроверка перед закрытием (проверка wf93-n2): донор мог стать главным окном
            // (заголовок, рамка страницы главного окна) — окно со списком чатов не закрываем.
            let facts = live.first { CFEqual($0.window, donor) }
            let title = facts?.title ?? AX.string(donor, kAXTitleAttribute) ?? ""
            let route = self.windowRoute(title: title, frame: facts?.frame ?? AX.frame(donor))
            guard case .popout? = route else {
                self.onWarning?(MenuModel.cashoutDonorMainNotice)
                return
            }
            // Кнопки закрытия у окна может не быть вовсе (Electron ещё не отдал дерево) —
            // тогда плашка обязана сказать правду, а не «старое закрыл» (#5779, задача 3).
            self.onWarning?(self.closeWindow(donor) ? MenuModel.cashoutReplacedNotice
                                                    : MenuModel.cashoutCloseFailedNotice)
        }
    }

    /// Свой срок ответа окну-элементу: от элемента приложения он НЕ наследуется (замер
    /// ElvisOS, #5784), а все вызовы AX синхронные и идут в главном потоке — зависший
    /// Electron не должен вешать тик приложения.
    static let axWindowTimeout: Float = 1.0

    /// Поля команды после id, action, at: scope, title, match?, chat? (контракт части B плана
    /// WF37, эталоны `tests/fixtures/cashout/cashout-*.json`). Главному окну уходит `match`
    /// (домашний экран — путь `/epitaxy`), попапу — `chat`, и никогда наоборот.
    /// `handoff` (К1 плана WF84, «💬 Новый чат») — ПОСЛЕДНИМ полем и только `true`: страница
    /// берёт текст передачи из блока «ОТКРОЙ НОВЫЙ ЧАТ» последнего ответа, а не весь ответ.
    /// Эталоны — `cashout-handoff.json` (попап) и `cashout-handoff-main.json` (главное окно).
    static func cashoutFields(title: String, match: String? = nil,
                              chat: String? = nil,
                              handoff: Bool = false) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(MenuModel.themeScopeWindow)),
            (key: "title", value: .string(title)),
        ]
        if let match = match { fields.append((key: "match", value: .string(match))) }
        if let chat = chat { fields.append((key: "chat", value: .string(chat))) }
        if handoff { fields.append((key: "handoff", value: .bool(true))) }
        return fields
    }

    /// Это главное окно Claude? Живьём вешает `ClaudeAXController` тем же резолвером, что
    /// и цели покраски (`ProjectPaint.windowKey(forTitle:) == mainKey`): у главного окна
    /// заголовок бывает и заглушкой «Claude», и настоящим именем чата, и различить их
    /// по одному заголовку нельзя. Без контроллера остаётся правило до WF37 — заглушка
    /// и пустой заголовок значат главное окно.
    var isMainWindowTitle: (String) -> Bool = { ClaudeActions.isMainWindowTitle($0) }
    var windowIdentity: ((String, CGRect?) -> WindowIdentity)?
    var uniqueLegacyTitle: (String) -> Bool = { _ in false }

    static func memoryKey(for page: ChatPage) -> String? {
        if let chat = page.chat, !chat.isEmpty { return "c:" + chat }
        return page.windowId.map { "n:\($0)" }
    }

    func memoryKey(title: String, frame: CGRect? = nil) -> String {
        guard let resolve = windowIdentity else { return title }
        guard let page = resolve(title, frame).page, let key = Self.memoryKey(for: page) else { return "" }
        if uniqueLegacyTitle(title) { themeStore.migrateWindow(title: title, to: key) }
        return key
    }

    /// In production every action shares the frame-aware resolver. The fallback supports standalone callers.
    func windowRoute(title: String, frame: CGRect?) -> CashoutRoute? {
        if let resolve = windowIdentity {
            guard let page = resolve(title, frame).page else { return nil }
            if page.kind == .main { return .main }
            guard let chat = page.chat else { return nil }
            return .popout(chat: chat)
        }
        return Self.cashoutRoute(title: title, isMainTitle: isMainWindowTitle(title) || isMainFrame(frame),
                                 knownChat: chatForTitle(title, frame))
    }

    /// Спросить страницы прямо сейчас, мимо минутного тормоза опознания (`ChatProbe.demand`).
    /// Живьём вешает контроллер.
    var demandPages: () -> Void = {}
    /// Ответы страниц приходят только от старого лоадера (v7) — им не верим. Живьём вешает контроллер.
    var pagesNeedRepatch: () -> Bool = { false }
    static let identityRetryPause: TimeInterval = 0.5
    static let identityWaitSeconds: TimeInterval = 8

    /// Действие по клику человека ждёт опознания окна (находка судьи WF111): между кругами probe
    /// окно бывает «неизвестным». Не узнали — спрашиваем страницы сразу и повторяем, пока круг
    /// не ответит; не дождались — плашка, а не молчаливый выход.
    func whenIdentified(title: String, frame: CGRect?, waited: TimeInterval = 0,
                        _ run: @escaping () -> Void) {
        guard let resolve = windowIdentity, resolve(title, frame).page == nil else { return run() }
        // Старый лоадер — ждать нечего: ответы его страниц не проверить, и повтор их не исправит.
        guard !pagesNeedRepatch() else {
            onNotice?(MenuModel.oldLoaderNotice, MenuModel.newWindowNoticeSeconds)
            return
        }
        if waited == 0 { demandPages() }
        guard waited < Self.identityWaitSeconds else {
            onNotice?(MenuModel.windowUnknownNotice, MenuModel.newWindowNoticeSeconds)
            return
        }
        after(Self.identityRetryPause) { [weak self] in
            self?.whenIdentified(title: title, frame: frame, waited: waited + Self.identityRetryPause, run)
        }
    }

    /// Стоит ли в этой рамке страница главного окна (карта probe, #7378). Живьём вешает
    /// контроллер; без него — нет.
    var isMainFrame: (CGRect?) -> Bool = { _ in false }

    /// Рамка — окна главной страницы, и ни один попап в ней не стоит (попап ровно поверх
    /// главного окна по рамке не различить — тогда решает заголовок). Чужие страницы (артефакт,
    /// панель браузера) живут в окне главной и носят её рамку — они не в счёт.
    static func isMainFrame(_ frame: CGRect?, pages: [ChatPage]) -> Bool {
        guard let frame = frame else { return false }
        let hits = pages.filter { page in
            page.kind != .other && (page.frame.map { frameMatches($0, frame) } ?? false)
        }
        return !hits.isEmpty && hits.allSatisfy { $0.kind == .main }
    }

    static func isMainWindowTitle(_ title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || clean == ProjectPaint.mainWindowTitle
    }

    /// Чат окна по AX-заголовку и РАМКЕ окна — карта probe (план WF29, рамка с WF77).
    /// Живьём вешает контроллер; карта несвежая или тумблер «🗂 Цвет по проекту» выключен —
    /// nil, и попап адресуется заголовком, как до WF37. Рамка решает, когда заголовок носят
    /// два окна: без неё это ничья и nil (#6734).
    var chatForTitle: (String, CGRect?) -> String? = { _, _ in nil }
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
    /// `handoff` (К2 плана WF84) ставит только «💬 Новый чат»: модель, эффорт, текст передачи
    /// первым сообщением и `stay` для главного окна. У `stay` нет ни имени чата (его даст
    /// Claude по тексту передачи), ни слоёв: чат остаётся в главном окне, красить нечего
    /// (эталон `new-window-handoff-stay.json`).
    /// `text` (WF102, `renew-window`) — первое сообщение вместо штатного `newWindowText`.
    private func newWindow(_ window: AXUIElement?, project: Project? = nil,
                           origin fixed: (x: Int, y: Int)? = nil, transfer: Bool = false,
                           handoff: NewChatHandoff? = nil, text custom: String? = nil) {
        // Метка прогрева: пока он идёт, пустое окно не начинаем (правка критика V-N п. 3).
        lastNewWindowAt = clock()
        if transfer || handoff?.transfer == true { cashoutNewWindowAt = lastNewWindowAt }
        // Точку могли задать снаружи (место «x,y» канала «Пимп», план WF36) — тогда окно
        // родится там же, где его просили, и двигать его потом не придётся.
        let origin = fixed ?? ClaudeActions.popoutOrigin(near: window.flatMap { AX.frame($0) })
        // Адресуем ГЛАВНОЕ окно, на каком бы окне ни нажали (дополнение 05.09 к плану WF19):
        // с попапа команда уходила с его заголовком, и её никто не исполнял. Пути не знаем —
        // адресуем заголовком, как раньше.
        let match = mainWindowMatch()
        // Работа идёт до 65 с — молчащая кнопка выглядит сломанной (критик п. 20).
        // Requested/donor settings are not evidence of the new chat's actual model.
        pendingNewWindowNotice = nil
        if handoff != nil {
            onNotice?(MenuModel.newChatNotice(model: nil, effort: nil),
                      MenuModel.newWindowNoticeSeconds)
        } else {
            onNotice?(MenuModel.newWindowNotice, MenuModel.newWindowNoticeSeconds)
        }
        let stay = handoff?.stay == true
        // Папка и имя чата считаются здесь, а не на странице (критик В4 плана WF16): на диске
        // лежат ВСЕ сессии, а сайдбар показывает только хвост. Папки нет — оба поля пустые,
        // и страница ведёт себя ровно как в WF13.
        let folder = project?.folder.standardizedFileURL.path ?? ""
        let name = stay ? "" : project.map { chatName($0) } ?? ""
        // Первое сообщение одно на все окна (#5767/#5447): агент в новом окне читает его как
        // задачу и разворачивает полную ориентировку по правилам проекта — самый дорогой ход
        // во всём открытии окна. Текст прямо просит ничего не делать, а имя чату ставит
        // отдельный шаг переименования на странице (поле `name`), а не авто-заголовок по
        // первому сообщению.
        let text = custom ?? MenuModel.newWindowText
        let send: (String) -> Void = { [weak self] title in
            guard let self = self else { return }
            let layers = stay ? ProjectSettings() : project.map {
                ClaudeActions.newWindowLayers(project: self.projectView($0),
                                              window: self.windowView(title: title, frame: window.flatMap { AX.frame($0) }),
                                              autoColor: self.autoProjectColor(for: $0))
            } ?? ProjectSettings()
            self.lastNewWindowLayers = !layers.isEmpty
            // ⌘N отсчитывается от МОМЕНТА ЗАПИСИ файла, а не от клика (#5735): команда могла
            // простоять в очереди канала до `minInterval`, и тогда прежние 0,8 с истекали
            // раньше, чем лоадер (опрос раз в 500 мс) успевал её прочитать, — главное окно
            // уходило на пустой `/epitaxy`, и вернуть его на чат Элвиса было уже некому.
            // Запись не удалась (папки MyClaude нет вовсе) — ⌘N жмём всё равно, как раньше.
            let commandID = CommandChannel.makeID()
            self.pendingNewWindowNotice = (commandID, self.clock())
            self.commands.write(action: ClaudeCommand.newWindow.rawValue,
                                fields: ClaudeActions.newWindowFields(title: title, match: match,
                                                                      x: origin.x, y: origin.y,
                                                                      text: text, folder: folder, name: name,
                                                                      transfer: transfer ? true : nil,
                                                                      model: handoff?.model,
                                                                      effort: handoff?.effort,
                                                                      sendTransfer: handoff?.transfer == true ? true : nil,
                                                                      stay: stay ? true : nil,
                                                                      pin: handoff?.pin == true ? true : nil,
                                                                      unpin: handoff?.pin == true ? handoff?.unpin : nil,
                                                                      theme: layers.theme, font: layers.font,
                                                                      size: layers.size, frame: layers.frame,
                                                                      bypass: self.bypassNew()), id: commandID,
                                completion: { [weak self] accepted in
                                    guard let self = self else { return }
                                    if !accepted { self.pendingNewWindowNotice = nil }
                                    self.after(self.newWindowKeyDelay) { self.newChat(window) }
                                })
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
    /// `text` и `handoff` (WF102, `renew-window` канала): свой первый текст, модель, эффорт и
    /// закрепка вместо донора — без записи «Обкэшить» (`handoff.transfer == false`).
    func newWindow(in project: Project, on window: AXUIElement?,
                   origin: (x: Int, y: Int)? = nil, text: String? = nil,
                   handoff: NewChatHandoff? = nil) {
        noteUserCommand()
        whenBlankIdle { [weak self] in
            guard let self = self else { return }
            // Папку открыли — она самая свежая в своём списке (план WF36, WF30 ч. 2). Точка одна
            // на оба пути: и клик по пункту меню, и запрос канала «Пимп» идут сюда.
            self.onProjectUsed?(project)
            self.newWindow(window ?? self.focusedWindow(), project: project, origin: origin,
                           handoff: handoff, text: text)
        }
    }

    /// «🪟 Новое окно ▸ проект» из меню — через канал «Пимп», чтобы окно встало самым правым
    /// (проверка гейта WF94). Живьём вешает контроллер; `false` — канал не взял, идём как раньше.
    var menuNewWindow: (Project) -> Bool = { _ in false }

    /// «Bypass permissions в новых чатах» (К5, #9060): читается в момент записи `new-window`, так что
    /// ⌥⌘N, «▸ проект», «💬 Новый чат», «Обкэшить» и канал «Пимп» (`pimp.py open`) — все пути через
    /// одну точку `newWindow(_:…)` — получают `mode:"bypass"` одинаково. Тесты подменяют.
    var bypassNew: () -> Bool = { UserDefaults.standard.bool(forKey: BypassNew.key) }

    func newWindowFromMenu(in project: Project, on window: AXUIElement?) {
        guard !refuseNewWindowRepeat() else { return }
        if menuNewWindow(project) { return }
        newWindow(in: project, on: window)
    }

    /// Ставит ли канал «Пимп» пустое окно прямо сейчас (`BlankJob`). Живьём вешает контроллер.
    var blankBusy: () -> Bool = { false }

    /// Сколько цепочка «Нового окна» ждёт конца пустого окна: черновик ловится до 6 с и ещё
    /// 1 с на пустой заголовок; дальше ждать нечего — идём как есть.
    static let blankWaitSeconds: TimeInterval = BlankWindow.draftWaitSeconds + BlankWindow.untitledGraceSeconds + 1

    /// Замок в обе стороны (проверка S): пока канал ловит черновик «Code», новая цепочка
    /// (⌥⌘N, «🪟 Новое окно ▸», «💬 Новый чат» — кнопка, ссылка, отсчёт «сам», «Обкэшить») не
    /// начинается — её попап до имени чата тоже «Code», и черновиком стал бы он. Ждём опросом
    /// 0,25 с, не дольше `blankWaitSeconds`.
    func whenBlankIdle(since start: Date? = nil, _ block: @escaping () -> Void) {
        let start = start ?? clock()
        guard blankBusy(), clock().timeIntervalSince(start) < ClaudeActions.blankWaitSeconds else {
            // Метка прогрева — на выпуске, а не в `newWindow` через 0,1–1,3 с (проверка wf93-n2):
            // `newWindowBusy` правдив с первой миллисекунды цепочки.
            lastNewWindowAt = clock()
            return block()
        }
        after(BlankWindow.pollSeconds) { [weak self] in self?.whenBlankIdle(since: start, block) }
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
    /// Когда начался последний прогрев «Нового окна» (⌥⌘N, «▸ проект», «💬 Новый чат», канал).
    private(set) var lastNewWindowAt: Date?

    /// Идёт чужая цепочка нового окна (правка критика V-N п. 3): перенос «Обкэшить» или прогрев
    /// моложе 65 с — её попап до имени чата тоже зовётся «Code».
    var newWindowBusy: Bool {
        ClaudeActions.newWindowBusy(cashout: cashoutPending, since: lastNewWindowAt, now: clock())
    }

    /// Ход цепочки «Нового окна» по слову главной страницы (`status().newWindow`). Живьём вешает
    /// контроллер; nil — страница молчит (канал probe занят), решает одно время.
    private var pendingNewWindowNotice: (id: String, since: Date)?
    var isAwaitingNewWindowActual: Bool {
        pendingNewWindowNotice.map { clock().timeIntervalSince($0.since) <= PimpChannel.newWindowSeconds } ?? false
    }

    func noteNewWindowOutcome() {
        guard let pending = pendingNewWindowNotice else { return }
        let now = clock()
        if now.timeIntervalSince(pending.since) > PimpChannel.newWindowSeconds {
            pendingNewWindowNotice = nil
            return
        }
        guard let run = newWindowRun() else { return }
        if let actual = run.confirmedActual(commandId: pending.id, since: pending.since, now: now) {
            pendingNewWindowNotice = nil
            let detail = [actual.model, actual.effort].compactMap { $0 }.joined(separator: " · ")
            if !detail.isEmpty { onNotice?("💬 Новый чат открыт — " + detail, MenuModel.newWindowNoticeSeconds) }
        } else if run.failure(since: pending.since) != nil { pendingNewWindowNotice = nil }
    }

    var newWindowRun: () -> NewWindowRun? = { nil }

    /// Сколько после нажатия «Нового окна» второе считается повтором, пока страница не сказала
    /// «кончилось»: фокус 0,1 с + очередь канала 0,6 с + опрос лоадера 0,5 с + ⌘N 0,8 с и опрос
    /// probe с запасом (WF97 Б5s).
    static let newWindowRepeatSeconds: TimeInterval = 8

    /// Идёт цепочка «Нового окна» или перенос — одно правило для повтора из меню и канала
    /// (`PimpSeats.newWindowStarting`, z4-r01).
    var newWindowStarting: Bool {
        ClaudeActions.newWindowStarting(since: lastNewWindowAt, run: newWindowRun(),
                                        cashout: cashoutPending, now: clock())
    }

    /// Метка прогрева, поставленная самим переносом: его конец ловит `cashoutPending`, а не время.
    private var cashoutNewWindowAt: Date?

    /// Чужая цепочка «Нового окна» (⌥⌘N, меню, канал) — её ждёт `whenCashoutIdle` (z2-r02).
    /// Страница говорит «занята» — ждём любую, её второй запуск она отбивает.
    private var newWindowChainRunning: Bool {
        let since = lastNewWindowAt == cashoutNewWindowAt ? nil : lastNewWindowAt
        return ClaudeActions.newWindowStarting(since: since, run: newWindowRun(), cashout: false, now: clock())
    }

    /// Второе ⌥⌘N, «Здесь же» или «▸ проект», пока первая цепочка идёт (#7772): без второго окна и
    /// без лишнего ⌘N в главное окно — только плашка «уже открываю». `true` — нажатие отклонено.
    func refuseNewWindowRepeat() -> Bool {
        guard newWindowStarting else { return false }
        onNotice?(MenuModel.newWindowRepeatNotice, MenuModel.repeatNoticeSeconds)
        return true
    }

    static func newWindowStarting(since: Date?, run: NewWindowRun?, cashout: Bool, now: Date) -> Bool {
        if cashout { return true }
        if let run = run, run.busy, now.timeIntervalSince(run.at) < BlankWindow.newWindowQuietSeconds { return true }
        guard let since = since, now.timeIntervalSince(since) < newWindowRepeatSeconds else { return false }
        // Страница уже отчиталась о цепочке, начатой после нажатия, и она кончилась — свободно.
        if let run = run, run.at >= since, !run.busy { return false }
        return true
    }

    static func newWindowBusy(cashout: Bool, since: Date?, now: Date) -> Bool {
        if cashout { return true }
        guard let since = since else { return false }
        return now.timeIntervalSince(since) < BlankWindow.newWindowQuietSeconds
    }

    /// Вид окна, каким его помнит приложение: галки меню, а у окна после «Раскрасить по кругу» —
    /// его сгенерированная тема. Нужен «🪟 Новому окну ▸» у проекта без своего вида (план WF16).
    func windowView(title: String, frame: CGRect? = nil) -> ProjectSettings {
        ProjectPaint.view(title: memoryKey(title: title, frame: frame), themeStore: themeStore, themes: themes, fonts: fonts,
                          myThemes: myThemes.load(), autoPainted: autoPaintedTheme(title: title, frame: frame))
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
    /// `model`, `effort`, `sendTransfer`, `stay` (К2 плана WF84, «💬 Новый чат») — после
    /// `transfer` и перед слоями, каждое только когда задано (эталоны `new-window-handoff*.json`).
    /// `pin` и `unpin` (#7246) — после `stay`: закрепить новый чат и открепить донора (id сессии).
    static func newWindowFields(title: String, match: String? = nil, x: Int, y: Int, text: String,
                                folder: String = "", name: String = "", transfer: Bool? = nil,
                                model: String? = nil, effort: String? = nil,
                                sendTransfer: Bool? = nil, stay: Bool? = nil,
                                pin: Bool? = nil, unpin: String? = nil,
                                theme: Layer<Theme> = .keep, font: Layer<Font> = .keep,
                                size: Layer<Size> = .keep,
                                frame: Layer<Bool> = .keep,
                                bypass: Bool = false) -> [(key: String, value: CommandValue)] {
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
        if let model = model { fields.append((key: "model", value: .string(model))) }
        if let effort = effort { fields.append((key: "effort", value: .string(effort))) }
        if let sendTransfer = sendTransfer { fields.append((key: "sendTransfer", value: .bool(sendTransfer))) }
        if let stay = stay { fields.append((key: "stay", value: .bool(stay))) }
        if let pin = pin { fields.append((key: "pin", value: .bool(pin))) }
        if let unpin = unpin { fields.append((key: "unpin", value: .string(unpin))) }
        fields += layerFields(theme: theme, font: font, size: SizeLayer(size), frame: frame)
        // К5 (#9060, WF137): «Bypass в новых чатах» — режим ПОСЛЕДНИМ полем, как у `draft-setup`;
        // выключено — поля нет, команда побайтно прежняя.
        if bypass { fields.append((key: "mode", value: .string(BypassNew.draftMode))) }
        return fields
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
                       // Главное окно на домашнем экране пути в индексе не имеет — тогда
                       // адрес `/epitaxy`, как у «Обкэшить» (WF37); без match команду не взял бы никто.
                       fields: ClaudeActions.popoutWindowFields(title: "", match: mainWindowMatch() ?? ChatProbe.homePath,
                                                                x: origin.x, y: origin.y,
                                                                chat: chat, name: name))
    }

    /// «Чат в главное окно» (WF108, #8148): главная страница открывает `chat` у себя и выносит прежний
    /// свой чат окном в точку `origin`. Адрес — как у `popoutChat`: только `match` главного окна.
    func mainChat(chat: String, origin: (x: Int, y: Int)) {
        commands.write(action: PimpChannel.mainChatAction,
                       fields: ClaudeActions.popoutWindowFields(title: "", match: mainWindowMatch() ?? ChatProbe.homePath,
                                                                x: origin.x, y: origin.y, chat: chat))
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
    ///
    /// Обрезаем по рабочей области ТОГО экрана, где стоит окно-источник, так, чтобы окно
    /// влезло целиком. `Screens.mainUsableFrame` для этого не годится: `NSScreen.main` — экран
    /// активного окна ЛЮБОГО приложения, и новое окно уезжало на второй монитор, стоило Элвису
    /// щёлкнуть там что-нибудь (#5731) — та же болезнь, что чинили у «Расставить» 08.09.
    /// `area` задают тесты; без неё экран считается сам.
    static func popoutOrigin(near frame: CGRect?, area: CGRect? = nil) -> (x: Int, y: Int) {
        guard let frame = frame else { return popoutWindowFallback }
        var x = frame.origin.x + popoutWindowOffset
        var y = frame.origin.y + popoutWindowOffset
        if let area = area ?? Screens.usableFrame(holding: [frame]) {
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
    /// id, action, at, scope, title, preview, theme, font, size, frame, look — вид с WF83).
    /// Окно адресуется AX-заголовком, как «Обкэшить»; пустой заголовок страница понимает как
    /// «окно в фокусе» — тогда, как у «Обкэшить», сперва даём окну фокус и ждём focusDelay.
    /// `toProject: false` — «Применить ▸ Только этому окну» (WF71): выбор остаётся местным,
    /// в `.pimpmyclaude.json` ничего не пишется и окна проекта не трогаются.
    @discardableResult
    func applyTheme(scope: String, theme: Layer<Theme> = .keep, font: Layer<Font> = .keep,
                    size: SizeLayer = .keep, frame: Layer<Bool> = .keep,
                    look: Layer<Look> = .keep,
                    window: AXUIElement?, toProject: Bool = true) -> Bool {
        // Все слои «не трогать» — команде нечего делать.
        guard !theme.isKeep || !font.isKeep || !size.isKeep || !frame.isKeep || !look.isKeep
        else { return false }
        noteUserCommand()
        let target = window ?? focusedWindow()
        let title = target.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        // Рамку снимаем ЗДЕСЬ, пока окно под рукой (план WF77): ею карта probe различает
        // два окна с одинаковым заголовком — и в адресе команды, и в записи вида проекта.
        let box = target.flatMap { AX.frame($0) }
        let send: () -> Bool = { [weak self] in
            guard let self = self else { return false }
            let address = self.themeAddress(scope: scope, title: title, frame: box)
            guard address.valid else { return false }
            let fields = ClaudeActions.themeFields(scope: scope, title: title,
                                                   match: address.match, chat: address.chat,
                                                   theme: theme,
                                                   font: font, size: size, frame: frame, look: look)
            guard self.commands.write(action: "theme", fields: fields) else { return false }
            self.recordTheme(fields: fields)
            self.remember(scope: scope, title: title, windowFrame: box, theme: theme, font: font,
                          size: size, frame: frame, look: look, toProject: toProject)
            return true
        }
        if title.isEmpty, let target = target {
            app.focus(window: target)
            after(focusDelay) { _ = send() }
            return true
        }
        // Окно этого клика пока не опознано (между кругами probe) — ждём ответа страниц.
        if !themeAddress(scope: scope, title: title, frame: box).valid, windowIdentity != nil {
            whenIdentified(title: title, frame: box) { _ = send() }
            return true
        }
        return send()
    }

    /// Умолчания новой установки (WF210, #9378): тема и вид всем окнам — без окна в фокусе и без ответа страницы
    /// (Claude ещё не пропатчен, читать команду некому). Выбор ложится в память галок и в `window-themes.json`:
    /// живая страница красится этой командой, первая после «Пропатчить Claude» — возвратом `themes-restore`.
    func applyNewInstallLook(theme: Theme, look: Look) {
        let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeAll, title: "", theme: .set(theme),
                                               font: .keep, look: look.layer)
        _ = commands.write(action: "theme", fields: fields)
        recordTheme(fields: fields)
        remember(scope: MenuModel.themeScopeAll, title: "", theme: .set(theme), font: .keep, size: .keep,
                 frame: .keep, look: look.layer)
    }

    /// Адрес окна для команды `theme` (#5715): та же развилка, что у «Обкэшить», — главному
    /// окну путь страницы (`match`), вынесенному чату его id (`chat`), а неопознанному окну
    /// ни того ни другого, и команда остаётся адресована заголовком, как раньше.
    /// Без адреса выбор цвета, шрифта или размера красил ВСЕ окна с таким же именем чата:
    /// страница сверяет `document.title` и исполняет команду на КАЖДОЙ подходящей странице —
    /// чаще всего это главное окно на домашнем экране («Claude») и безымянный попап.
    ///
    /// `scope: "all"` адреса не имеет вовсе — эта команда и должна уйти всем окнам. Пустой
    /// заголовок тоже: он значит «окно в фокусе», и какое это окно, приложение не знает.
    /// Не `private` только ради тестов: живой AX они не поднимают, а заголовок окна берётся
    /// из него — иначе развилку не проверить.
    func themeAddress(scope: String, title: String,
                      frame: CGRect? = nil) -> (match: String?, chat: String?, valid: Bool) {
        guard scope == MenuModel.themeScopeWindow else { return (nil, nil, true) }
        if let resolve = windowIdentity {
            guard let page = resolve(title, frame).page else { return (nil, nil, false) }
            if page.kind == .main {
                return (page.path.isEmpty ? mainWindowMatch() ?? ChatProbe.homePath : page.path, nil, true)
            }
            guard let chat = page.chat else { return (nil, nil, false) }
            return (nil, chat, true)
        }
        guard !title.isEmpty else { return (nil, nil, true) }
        switch ClaudeActions.cashoutRoute(title: title, isMainTitle: isMainWindowTitle(title),
                                          knownChat: chatForTitle(title, frame)) {
        case .main: return (mainWindowMatch(), nil, true)
        case .popout(let chat): return (nil, chat, true)
        }
    }

    /// Поля команды после id, action, at: scope, title, match, preview, затем слои — тема,
    /// шрифт, размер, рамка, вид (WF83). Слоя `.keep` в JSON нет вовсе, `.reset` уходит как `null`
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
                            frame: Layer<Bool> = .keep,
                            look: Layer<Look> = .keep) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "scope", value: .string(scope)),
            (key: "title", value: .string(title)),
        ]
        if let match = match { fields.append((key: "match", value: .string(match))) }
        if let chat = chat { fields.append((key: "chat", value: .string(chat))) }
        if let preview = preview { fields.append((key: "preview", value: .bool(preview))) }
        return fields + layerFields(theme: theme, font: font, size: size, frame: frame, look: look)
    }

    /// Четыре слоя как поля команды, в порядке контракта: тема, шрифт, размер, рамка. Ими
    /// одинаково заканчиваются и `theme`, и `new-window` (решение 1 плана WF16) — правило
    /// «поля нет → слой не трогаем, null → сброс» у них одно на двоих. У размера правило то же,
    /// только по половинам: `SizeLayer` сам решает, писать ли поле и что положить внутрь.
    /// Вид (`look`, план WF83) идёт ПОСЛЕ рамки и только у `theme`: `new-window` его не шлёт.
    static func layerFields(theme: Layer<Theme>, font: Layer<Font>, size: SizeLayer,
                            frame: Layer<Bool>,
                            look: Layer<Look> = .keep) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = []
        if let value = theme.commandValue({ $0.commandValue }) { fields.append((key: "theme", value: value)) }
        if let value = font.commandValue({ $0.commandValue }) { fields.append((key: "font", value: value)) }
        if let value = size.commandValue { fields.append((key: "size", value: value)) }
        if let value = frame.commandValue({ .bool($0) }) { fields.append((key: "frame", value: value)) }
        if let value = look.commandValue({ $0.commandValue }) { fields.append((key: "look", value: value)) }
        return fields
    }

    /// Своя тема ставит РОВНО палитру — один слой, как любой другой пункт списка цветов
    /// (решение 2.1 плана WF31, задача #5453: «когда я цвета выбираю, не надо мне из темы
    /// Пудра показывать шрифты»). Шрифт, кегль и рамка в `my-themes.json` по-прежнему
    /// хранятся (`saveMyTheme` пишет их все), но выбираются своими списками — правило одно
    /// и без исключений: список цветов меняет цвет. Так же с WF15 живёт цвет проекта
    /// (`ProjectPaint.view`), и панель «Своя тема» теперь ставит ровно то, что крутила.
    /// `toProject` — как у `applyTheme`: «Только этому окну» в проект не пишет (WF71).
    @discardableResult
    func apply(myTheme: MyTheme, scope: String, window: AXUIElement?, toProject: Bool = true) -> Bool {
        applyTheme(scope: scope, theme: .set(myTheme.theme), window: window, toProject: toProject)
    }

    /// «💾 Сохранить тему»: набор из темы этого окна и последних шрифта и размера.
    /// Тема ни разу не выбиралась — сохранять нечего (меню покажет алерт).
    @discardableResult
    func saveMyTheme(name: String, window: AXUIElement? = nil) -> [MyTheme]? {
        guard let theme = themeToSave(window: window) else { return nil }
        return myThemes.add(name: name, theme: theme, font: lastAppliedFont, size: lastAppliedSize)
    }

    /// Что запишет «💾 Сохранить тему» (и от чего считается имя): у автопокрашенного окна — его
    /// собственную автотему (план WF10 п. 6), у остальных — последнюю применённую этим
    /// приложением. Иначе на окне «Радуги» сохранялся бы цвет соседнего окна.
    func themeToSave(window: AXUIElement?) -> Theme? {
        let title = window.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        let key = memoryKey(title: title, frame: window.flatMap { AX.frame($0) })
        if let id = themeStore.windowThemeID(title: key) ?? (autoPaintedThemes[key] == nil ? themeStore.allThemeID : nil) {
            return themes.first { $0.id == id } ?? myThemes.load().first { $0.id == id }?.theme
        }
        return autoPaintedThemes[key] ?? (windowIdentity == nil ? lastAppliedTheme : nil)
    }

    /// Автотема окна, если его красила автопокраска. Меню спрашивает об этом ради галки
    /// «Как у Claude»: окно цветное, а `ThemeStore` пуст — галка соврала бы (критик В1 плана WF14).
    func autoPaintedTheme(title: String, frame: CGRect? = nil) -> Theme? { autoPaintedThemes[memoryKey(title: title, frame: frame)] }

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
    static var windowKeyForTitle: ((String, CGRect?) -> String)?

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
        let key = memoryKey(title: title, frame: window.flatMap { AX.frame($0) })
        if let id = themeStore.windowThemeID(title: key) ?? (autoPaintedThemes[key] == nil ? themeStore.allThemeID : nil) {
            if let my = myThemes.load().first(where: { $0.id == id }) { return ThemeKnobs.of(my) }
            if let found = themes.first(where: { $0.id == id }) {
                return ThemeKnobs.from(palette: found.palette, type: found.type)
            }
        }
        guard let theme = autoPaintedThemes[key] ?? (windowIdentity == nil ? lastAppliedTheme : nil) else { return ThemeKnobs() }
        return ThemeKnobs.from(palette: theme.palette, type: theme.type)
    }

    /// Галки в меню и «последнее применённое» — по слоям: слой `.keep` остаётся как был.
    /// Размер приходит половинами, поэтому кладётся поверх запомненного — как его склеивает
    /// страница; `.reset` («🧹 Всё как у Claude») снимает слой целиком, а снятая половина
    /// («Как у Claude» в одном из двух подменю) уходит из записи одна (решение 1 плана WF19).
    /// `toProject: false` — крючок `onWindowViewChanged` не зовётся вовсе (WF71): память
    /// окна и галки те же, а вид проекта не меняется. Отпечаток покраски при этом не
    /// трогается, поэтому окно держит выбор, пока не изменится вид проекта или не
    /// перезапустится приложение — после перезапуска оно красится по проекту.
    private func remember(scope: String, title: String, windowFrame: CGRect? = nil,
                          theme: Layer<Theme>, font: Layer<Font>,
                          size: SizeLayer, frame: Layer<Bool>, look: Layer<Look> = .keep,
                          toProject: Bool = true) {
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
            if !look.isKeep {
                themeStore.setAllLook(look.value)
                themeStore.clearWindowLooks()
            }
        } else {
            let key = memoryKey(title: title, frame: windowFrame)
            if !theme.isKeep {
                themeStore.setWindowTheme(theme.value?.id, title: key)
                autoPaintedThemes[key] = nil // цвет окна выбрали руками — автотема устарела
            }
            if !font.isKeep { themeStore.setWindowFont(font.value?.id, title: key) }
            if !size.isKeep {
                let value = ClaudeActions.windowSize(after: size,
                                                     window: themeStore.windowSize(title: key),
                                                     all: themeStore.allSize)
                themeStore.setWindowSize(value, title: key)
                // В файл проекта размер уходит целым слоем, а не половиной: страница склеила
                // половины ровно так же (решение 3.2 плана WF20).
                windowSize = value.map { Layer.set($0) } ?? .reset
            }
            if !look.isKeep { themeStore.setWindowLook(look.value, title: key) }
        }
        if !theme.isKeep { lastAppliedTheme = theme.value }
        if !font.isKeep { lastAppliedFont = font.value }
        // Снятую половину убираем и отсюда (критик В5 плана WF19): иначе «💾 Сохранить как мою
        // тему…» записала бы кегль, которого на экране уже нет.
        if !size.isKeep { lastAppliedSize = size.applied(to: lastAppliedSize) }
        // Ручной выбор в окне проекта — это и есть вид проекта (решение 3.2 плана WF20).
        // Только `scope:"window"`: «всем окнам» проект не перебивает вовсе, а примерка
        // и «Раскрасить по кругу» сюда не доходят. Сверка именно «равно окну», а не «не равно
        // всем» (находка 6 проверки WF20): третий scope, который однажды появится, ушёл бы
        // в файл проекта молча.
        guard scope == MenuModel.themeScopeWindow, toProject else { return }
        onWindowViewChanged?(title, windowFrame, theme, font, windowSize, frame, look)
    }

    /// Окну задали вид руками: заголовок, рамка окна и четыре слоя. Вешает
    /// `ClaudeAXController` — на `ProjectPaint.noteManualChoice`, которая молча кладёт выбор
    /// в `.pimpmyclaude.json` (решение 3.2 плана WF20). Размер приходит целым слоем:
    /// `.reset` — «как у Claude». Рамка (план WF77) находит папку среди окон-однофамильцев:
    /// без неё выбор в одном окне уезжал в проект соседнего (#6734). Вид (`look`, план WF83)
    /// едет в проект так же, как рамка.
    var onWindowViewChanged: ((String, CGRect?, Layer<Theme>, Layer<Font>,
                               Layer<Size>, Layer<Bool>, Layer<Look>) -> Void)?

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

    /// «🔡 Размер шрифта в поле» (WF107 #8126, К2): `composer-font` всем окнам очередью канала; nil — «Как у
    /// Claude». Им же приложение возвращает размер странице, потерявшей `localStorage`.
    @discardableResult
    func sendComposerFont(_ px: Int?) -> Bool {
        commands.write(action: ComposerFont.action, fields: ComposerFont.fields(px: px))
    }

    /// Примерка размера поля в одном окне: адрес — как у `sendPreview` (заголовок и `match`/`chat` из
    /// `themeAddress`), мимо очереди. Снимает её прежний `theme` с `preview:false` (`endPreview`).
    @discardableResult
    func previewComposerFont(_ px: Int?, window: AXUIElement?) -> Bool {
        noteUserCommand()
        let target = window ?? focusedWindow()
        let title = target.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        guard !title.isEmpty else { return false }
        let address = themeAddress(scope: MenuModel.themeScopeWindow, title: title,
                                   frame: target.flatMap { AX.frame($0) })
        guard address.valid else { return false }
        return commands.write(action: ComposerFont.action,
                              fields: ComposerFont.previewFields(title: title, match: address.match,
                                                                 chat: address.chat, px: px),
                              priority: .preview)
    }

    /// Наведение на пункт вида (план WF83) примеряет вид с ЭТИМ эффектом включённым, чем бы он
    /// сейчас ни был. Остальные эффекты — как на окне сейчас: слой уходит объектом целиком.
    @discardableResult
    func previewLook(_ look: Look, window: AXUIElement?) -> Bool {
        sendPreview(true, theme: .keep, font: .keep, look: .set(look), window: window)
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
                             size: SizeLayer = .keep,
                             look: Layer<Look> = .keep, window: AXUIElement?) -> Bool {
        noteUserCommand()
        let target = window ?? focusedWindow()
        let title = target.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        // Без заголовка примерка не адресуется (фокуса у окна Claude нет, пока открыто меню),
        // а «конец примерки» мог бы снять живую тему у окна без ключа — не шлём ничего.
        guard !title.isEmpty else { return false }
        // Примерка адресуется так же, как закрепляющая команда (#5715): иначе цвет под
        // курсором ехал бы на все окна с этим именем чата, а «конец примерки» — тоже.
        // Рамка окна — часть адреса с WF77: по ней различаются окна-однофамильцы.
        let address = themeAddress(scope: MenuModel.themeScopeWindow, title: title,
                                   frame: target.flatMap { AX.frame($0) })
        guard address.valid else { return false }
        let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow, title: title,
                                               match: address.match, chat: address.chat,
                                               preview: preview, theme: theme, font: font,
                                               size: size, look: look)
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
        let targets = windows.named
        guard !targets.isEmpty else {
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
                                      count: targets.count, start: start, light: light)
        var painted = 0
        for (target, theme) in zip(targets, themes) {
            let title = target.title
            let address = themeAddress(scope: MenuModel.themeScopeWindow, title: title, frame: target.frame)
            guard address.valid else { continue }
            let key = memoryKey(title: title, frame: target.frame)
            guard !key.isEmpty else { continue }
            let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeWindow, title: title,
                                                   match: address.match, chat: address.chat,
                                                   theme: .set(theme), font: .keep)
            // Вторая точка зеркала (решение 2 плана WF35): «Раскрасить по кругу» пишет команду
            // напрямую, мимо applyTheme, — и без этой строки её цвета не пережили бы
            // переустановку Claude.
            guard commands.write(action: "theme", fields: fields) else { continue }
            recordTheme(fields: fields)
            painted += 1
            // Галку в «Тема» снимаем: цвет у окна теперь сгенерированный, а старая отметка
            // показывала бы тему каталога, которой на окне уже нет (план п. 4).
            themeStore.setWindowTheme(nil, title: key)
            // А «Сохранить как мою тему…» на этом окне должно предложить его цвет (план п. 6).
            autoPaintedThemes[key] = theme
        }
        autoPaintStore.remember(preset: preset.id, start: start, scheme: index, light: light)
        return painted
    }

    /// Окна Claude на экране для покраски: заголовки слева направо, затем сверху вниз (порядок
    /// тот же, что у «Расставить»), и счётчики для HUD. Окно без AX-заголовка пропускаем совсем:
    /// страница узнаёт окно только по нему, а пустой заголовок значит «окно в фокусе» —
    /// покрасились бы все в один цвет. Одинаковые заголовки схлопываются по той же причине:
    /// тема живёт на чате, и двум окнам одного чата достанется один цвет.
    /// Счётчики считаются по факту (хвост WF10): `shared` — окна, которым своего цвета не
    /// досталось (окна − уникальные заголовки − пропущенные), `skipped` — окна без заголовка.
    private func paintableWindows() -> (titles: [String], named: [(title: String, frame: CGRect?)],
                                        onScreen: Int, shared: Int, skipped: Int) {
        guard let pid = app.pid else { return ([], [], 0, 0, 0) }
        let windows = ClaudeApp.onScreenFrames(pid: pid)
        guard !windows.isEmpty else { return ([], [], 0, 0, 0) }
        var seen = Set<String>()
        var titles: [String] = []
        var named: [(title: String, frame: CGRect?)] = []
        var skipped = 0
        for index in ArrangeLayout.order(of: windows.map { $0.frame }) {
            let frame = windows[index].frame
            let title = app.window(matching: frame)
                .flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
            guard !title.isEmpty else {
                skipped += 1
                continue
            }
            named.append((title: title, frame: frame))
            guard seen.insert(title).inserted else { continue }
            titles.append(title)
        }
        return (titles, named, windows.count, windows.count - titles.count - skipped, skipped)
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
                                               size: SizeLayer(command.size), frame: command.frame,
                                               look: command.look)
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

    /// Снятые в WF220 эффекты (#9440: «✨ Неоновая рамка», «Неон и ретро-экран») — выключить у всех
    /// разом той же командой `theme` `scope:"all"`, какой их гасила галка во «Всем окнам ▸»:
    /// рамке `"frame":null`, виду — «всем окнам» без неона. Окно в фокусе не нужно. Свои виды окон
    /// общая команда снимает — их доливает обратно `WindowThemeStore.retireTick`, поэтому память
    /// галок окон здесь не чистится.
    @discardableResult
    func retireEffects(frame: Bool, look: Layer<Look>) -> Bool {
        let fields = ClaudeActions.themeFields(scope: MenuModel.themeScopeAll, title: "", theme: .keep,
                                               font: .keep, frame: frame ? .reset : .keep, look: look)
        guard commands.write(action: "theme", fields: fields) else { return false }
        recordTheme(fields: fields)
        if !look.isKeep { themeStore.setAllLook(look.value) }
        return true
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

    /// Тот же обход окон на один тик, но двумя списками (план WF77): заголовки со схлопнутыми
    /// однофамильцами — ими адресуются команды и ключуется память вида, и те же окна с
    /// рамками и БЕЗ схлопывания — ими канал probe различает два окна с одним заголовком.
    /// Один вызов вместо двух: обход стоит `CGWindowList` плюс AX-заголовок на каждое окно.
    func paintableSnapshot() -> (titles: [String], windows: [(title: String, frame: CGRect?)]) {
        let seen = paintableWindows()
        return (seen.titles, seen.named)
    }

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

    /// «💬 Новый чат» из меню жёлтой кнопки. ⌘N уходит в ПРОЦЕСС Claude, а исполняет его
    /// всегда главное окно, — из вынесенного окна пункт уводил главное окно Элвиса с его
    /// разговора (#5734). Развилка та же, что у «Обкэшить» (`cashoutRoute`): главное окно —
    /// ⌘N, как было; попап — тот же путь, что кнопка и ссылка «ОТКРОЙ НОВЫЙ ЧАТ» в чате
    /// (`handoffNewChat`, #7378, #7671): новый чат того же проекта ЗАМЕНЯЕТ окно — встаёт в
    /// рамку донора, донор закрывается по слову «вставлено». Блока передачи нет — новый чат
    /// пустой, замена та же (#7749: до этого пункт открывал окно рядом, Claude-размера, и
    /// старое оставлял — «окно не заменило, старое не закрыла, растянулось на весь экран»).
    /// Заголовок приходит снаружи (его читает `perform`) — так развилку видно тестам.
    func newChatCommand(_ window: AXUIElement?, title: String) {
        let frame = window.flatMap { AX.frame($0) }
        whenIdentified(title: title, frame: frame) { [weak self] in
            guard let self = self, let route = self.windowRoute(title: title, frame: frame) else { return }
            switch route {
            case .main:
                self.newChat(window)
            case .popout:
                self.handoffNewChat(window)
            }
        }
    }

    /// ⌘N — штатная клавиша самого Claude, посылаем её в окно (focus асинхронный, отсюда задержка).
    private func newChat(_ window: AXUIElement?) {
        if let window = window { app.focus(window: window) }
        after(focusDelay) { [weak self] in
            guard let key = KeySpec(mods: [.command], name: "n").keyCode else { return }
            self?.app.postKey(CGKeyCode(key), flags: .maskCommand)
        }
    }

    /// Умная расстановка — ⌥⌘A и пункт «▦ Расставить» (план WF77, слова Элвиса 20.09:
    /// «расстановка работает как попало… окна, которые уже стояли на месте, никуда не
    /// переводить; есть свободное место и одно-два окна болтаются неприкаянно — заполни ими
    /// свободное место. Решение принимай по положению окон, у них же координаты есть»).
    ///
    /// Плитку (`themeStore.arrangeMode`) этот путь НЕ читает и НЕ пишет (критик блокер 2:
    /// иначе первая же расстановка стирала бы выбор Элвиса), `arrangeFits` и плашку «экран
    /// мал» не зовёт вовсе (блокер 3) — сетка считается по тому, как окна стоят, и уже она
    /// не бывает минимума. Окна с разных экранов остаются каждое на своём.
    ///
    /// С WF84 (#7062) клавиша и канал «Пимп» расставляют ОДИН И ТОТ ЖЕ набор окон — те, что
    /// на экране (`pimpWindows`, текущий стол). До WF84 клавиша брала `visibleWindows()` —
    /// окна ВСЕХ столов, и сетка считалась по числу окон, которых на экране нет: оставались
    /// дыры, а «расставь» голосом и ⌥⌘A выбирали разные сетки. Там же окно без AX-рамки
    /// становилось `.zero` и занимало ячейку в левом верхнем углу; у `pimpWindows` рамка
    /// есть у каждого окна, а окно без неё в расстановку не попадает вовсе.
    func arrangeSmart() {
        let ids = pimpWindows().map { $0.id }
        guard !ids.isEmpty else { return }
        let placed = arrangeSmart(ids: ids, ordered: false)
        onExplicitLayout?(placed.map { PimpMove(id: $0.id, frame: $0.frame) })
    }

    /// Ровная сетка по главному экрану, раскладка задана плиткой в меню. Порядок окон
    /// сохраняется (см. ArrangeLayout.order). Свёрнутые и спрятанные не трогаем; чужие
    /// приложения — тоже (в отличие от ElvisOS). Ячеек меньше, чем окон («4» при пяти
    /// окнах), — хвост порядка не трогаем вовсе, окна стоят где стояли.
    ///
    /// Окна — тот же набор, что у умной расстановки и канала (`pimpWindows`, #7062).
    func arrange(mode: ArrangeLayout.Mode) {
        let listed = pimpWindows()
        let frames = listed.map { $0.frame }
        guard !listed.isEmpty, let area = Screens.usableFrame(holding: frames) else { return }
        let order = ArrangeLayout.order(of: frames)
        let cells = ArrangeLayout.frames(count: order.count, in: area, mode: mode,
                                         minCellWidth: cellWidth(), gap: cellGap())
        for (index, cell) in cells.enumerated() {
            ClaudeActions.setFrame(listed[order[index]].window, cell)
        }
        onWindowsMoved?()
        onExplicitLayout?(cells.enumerated().map { PimpMove(id: listed[order[$0.offset]].id, frame: $0.element) })
    }

    /// Ячейки раскладки на экране, где стоят окна Claude (план WF41): их номера пишет
    /// «💾 Сохранить эту раскладку…», по ним же «↩︎ Вернуть эти чаты» ставит окна.
    /// Считаются той же арифметикой, что «Расставить», — иначе номер ячейки означал бы
    /// одно при записи и другое при возврате.
    func arrangeCells(mode: ArrangeLayout.Mode, count: Int) -> [CGRect] {
        let frames = pimpWindows().map { $0.frame }
        guard count > 0, let area = Screens.usableFrame(holding: frames) else { return [] }
        return ArrangeLayout.frames(count: count, in: area, mode: mode,
                                    minCellWidth: cellWidth(), gap: cellGap())
    }

    /// Влезает ли раскладка на главный экран (ячейка не уже `minWindowWidth`): по этому
    /// плитка в меню гаснет, а канал «Пимп» отвечает `too-small`. Экрана не знаем — не мешаем.
    /// Умный путь сюда не заходит вовсе (критик WF77 блокер 3).
    func arrangeFits(_ mode: ArrangeLayout.Mode) -> Bool {
        let frames = pimpWindows().map { $0.frame }
        guard let area = Screens.usableFrame(holding: frames) else { return true }
        return ArrangeLayout.fits(mode, in: area, minCellWidth: cellWidth(), gap: cellGap())
    }

    /// Поставить окну рамку и УБЕДИТЬСЯ, что она встала (гейт WF36, 07.09): Electron молча
    /// глотает `kAXPositionAttribute`, пока окно ещё едет (свежий popout, анимация) — на живом
    /// прогоне три окна сузились по сетке, а с места не сдвинулись, и Элвис видел ровно это
    /// («в ширину уменьшились, больше ничего не произошло»). Поэтому после записи читаем рамку
    /// назад и повторяем с паузой; порядок записи — `frameSteps`.
    ///
    /// Кругов четыре, а не три (находка живьём 20.09, план WF77): на Маке Элвиса запись
    /// «позиция → размер → позиция» подряд, без пауз, НЕ ставит размер вовсе — окно
    /// остаётся прежней ширины и высоты, а систему потом прижимает его к низу экрана.
    /// Сработало «позиция → пауза → размер»: круг второй пишет размер уже после того, как
    /// верх окна встал, и высота наконец берётся. Отсюда же сверка размера в
    /// `needsFrameRetry` — до WF77 промах размера повтора не вызывал, и «расставило как
    /// попало» было ровно этим.
    static let frameRetries = 4
    static let frameRetryPause: TimeInterval = 0.25
    static let frameTolerance: CGFloat = 2

    /// Чем откладывается повтор. Живьём — главная очередь ходом вперёд; раньше здесь стоял
    /// `Thread.sleep`, и на пяти окнах приложение (меню-бар, плашки, хоткеи) замирало до
    /// 2,5 с — сон умножался на число окон, а через `setFrame` ходят и «Расставить», и канал
    /// «Пимп», и возврат раскладок (#5557). В тестах расписание подставляется.
    static var frameSchedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    /// Один шаг постановки рамки: что именно пишем окну.
    enum FrameStep: Equatable {
        case position(CGPoint)
        case size(CGSize)
    }

    /// Порядок записи рамки. Чистая — её и гоняют тесты.
    ///
    /// Окну, которое уже стоит на экране, — «позиция → размер → позиция»: смена размера у
    /// правого края может снова сдвинуть окно, и последним словом обязана быть позиция.
    /// СВЕЖЕМУ окну — «размер → позиция → размер» (урок ElvisOS, #5791): его сперва просят
    /// ужаться, пока оно ещё стоит высоко, и только потом двигают вниз. Иначе система урезает
    /// запомненную с прошлого раза высоту по нижнему краю ЭКРАНА (под Dock), а повторный
    /// размер после позиции уже глотает — у ElvisOS нижний ряд стабильно получал 488 точек
    /// вместо 434.
    static func frameSteps(_ frame: CGRect, fresh: Bool) -> [FrameStep] {
        fresh ? [.size(frame.size), .position(frame.origin), .size(frame.size)]
              : [.position(frame.origin), .size(frame.size), .position(frame.origin)]
    }

    /// `true` — рамка встала с первого захода. Не встала — повтор уходит на `frameSchedule`,
    /// и ответ этого вызова про него ничего не знает (окна двигают, не спрашивая результат).
    /// `fresh` — окно только что родилось (см. `frameSteps`); повтор идёт тем же порядком.
    @discardableResult
    static func setFrame(_ window: AXUIElement, _ frame: CGRect, fresh: Bool = false,
                         attempt: Int = 0) -> Bool {
        for step in frameSteps(frame, fresh: fresh) {
            switch step {
            case .position(let origin): AX.set(window, kAXPositionAttribute, point: origin)
            case .size(let size): AX.set(window, kAXSizeAttribute, size: size)
            }
        }
        let now = AX.frame(window)
        if let now = now, frameMatches(now, frame) { return true }
        guard attempt + 1 < frameRetries,
              needsFrameRetry(now: now, want: frame, minWidth: minFrameWidth())
        else { return false }
        frameSchedule(frameRetryPause) { setFrame(window, frame, fresh: fresh, attempt: attempt + 1) }
        return false
    }

    /// Минимальная ширина окна Electron — тот же `minWindowWidth` живого `claude.json`,
    /// который лоадер отдаёт окнам. Живьём читается из файла, в тестах подставляется.
    static var minFrameWidth: () -> CGFloat = { minCellWidth() }

    /// Стоит ли повторять. ПОЗИЦИЯ — всегда: её Electron глотает у окна, которое ещё едет.
    /// РАЗМЕР — с WF77 тоже (находка живьём 20.09: за один заход размер не берётся вовсе,
    /// окно остаётся прежней ширины и высоты, и «расставило как попало» было ровно этим).
    /// Кроме ШИРИНЫ уже `minWidth`: её Electron зажимает осознанно, и на узкой сетке
    /// повторы уходили туда впустую — весь бюджет на каждое окно (#5733). Рамки нет вовсе
    /// (окно закрылось, AX молчит) — повторять некому.
    static func needsFrameRetry(now: CGRect?, want: CGRect,
                                tolerance: CGFloat = frameTolerance,
                                minWidth: CGFloat = 0) -> Bool {
        guard let now = now else { return false }
        if abs(now.origin.x - want.origin.x) > tolerance
            || abs(now.origin.y - want.origin.y) > tolerance { return true }
        if abs(now.height - want.height) > tolerance { return true }
        return want.width >= minWidth && abs(now.width - want.width) > tolerance
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
    typealias WindowRecord = (id: CGWindowID, window: AXUIElement, title: String, frame: CGRect)
    struct Census {
        let windows: [WindowRecord]
        let native: [WindowIdentity.Native]
        let complete: Bool
    }
    private var censusDepth = 0
    private var batchCensus: Census?
    func beginWindowBatch() { censusDepth += 1 }
    func endWindowBatch() { censusDepth -= 1; if censusDepth == 0 { batchCensus = nil } }

    func windowCensus() -> Census {
        if let cached = batchCensus { return cached }
        guard let pid = app.pid else { return Census(windows: [], native: [], complete: false) }
        let elements = app.windows()
        var facts = elements.map { WindowIdentity.Native(title: AX.string($0, kAXTitleAttribute) ?? "", frame: AX.frame($0)) }
        let quartz = ClaudeApp.allFrames(pid: pid)
        // A named AX window is always retained, even at the usual Electron service frame.
        let service: (Int) -> Bool = { index in
            facts[index].title.isEmpty && facts[index].frame.map { ClaudeApp.isServiceWindow(frame: $0, alpha: 1) } == true
        }
        let active = elements.indices.filter { !service($0) }
        let native = active.map { facts[$0] }
        let visibleQuartz = quartz.filter { entry in
            !ClaudeApp.isServiceWindow(frame: entry.frame, alpha: 1) || facts.contains {
                !$0.title.isEmpty && $0.frame.map { ClaudeActions.frameMatches($0, entry.frame) } == true
            }
        }
        let paired = WindowCensus.pair(native: native, quartz: visibleQuartz)
        for pair in paired.pairs { facts[active[pair.native]].id = pair.id }
        let records: [WindowRecord] = paired.pairs.compactMap { pair in
            guard let frame = native[pair.native].frame else { return nil }
            return (pair.id, elements[active[pair.native]], native[pair.native].title, frame)
        }
        let result = Census(windows: records, native: facts, complete: paired.complete)
        if censusDepth > 0 { batchCensus = result }
        return result
    }

    func pimpWindows() -> [WindowRecord] {
        guard let pid = app.pid else { return [] }
        let ids = Set(ClaudeApp.onScreenFrames(pid: pid).map { $0.id })
        return windowCensus().windows.filter { ids.contains($0.id) }
    }

    // MARK: - пустое окно проекта (план WF88, К17)

    /// Все окна выбранного Claude по AX — для приёма черновика (правка критика V-N п. 1): окно
    /// на рамке служебного (335,164 800×600) `pimpWindows` отсеивает, а черновик туда встать
    /// может. Окно с парой Quartz идёт под своим номером, без пары — под жетоном, который
    /// держится, пока окно живо; по жетону его и ставят на место (`arrangeSmart`, `raise`).
    func blankWindows() -> [(id: CGWindowID, title: String, frame: CGRect)] {
        guard let root = app.element() else { return [] }
        let listed = pimpWindows()
        var tokens: [(id: CGWindowID, window: AXUIElement)] = []
        var out: [(id: CGWindowID, title: String, frame: CGRect)] = []
        for window in AX.elements(root, kAXWindowsAttribute) {
            AX.timeout(window, BlankWindow.axTimeout)
            let title = AX.string(window, kAXTitleAttribute) ?? ""
            if let known = listed.first(where: { CFEqual($0.window, window) }) {
                out.append((id: known.id, title: title, frame: known.frame))
                continue
            }
            let id = blankTokens.first(where: { CFEqual($0.window, window) })?.id ?? nextBlankToken()
            tokens.append((id: id, window: window))
            out.append((id: id, title: title, frame: AX.frame(window) ?? .zero))
        }
        blankTokens = tokens
        return out
    }

    /// Жетоны окон без пары Quartz (с прошлого `blankWindows`). Номера — из верхней половины,
    /// с номерами окон Quartz не встречаются.
    private var blankTokens: [(id: CGWindowID, window: AXUIElement)] = []
    private var blankTokenSeed: CGWindowID = 0xF000_0000

    private func nextBlankToken() -> CGWindowID {
        blankTokenSeed += 1
        return blankTokenSeed
    }

    /// Окна канала плюс названные жетоны пустого окна.
    private func pimpWindows(with ids: [CGWindowID])
        -> [(id: CGWindowID, window: AXUIElement, title: String, frame: CGRect)] {
        var out = windowCensus().windows
        for id in ids where !out.contains(where: { $0.id == id }) {
            guard let token = blankTokens.first(where: { $0.id == id }),
                  let frame = AX.frame(token.window) else { continue }
            out.append((id: id, window: token.window,
                        title: AX.string(token.window, kAXTitleAttribute) ?? "", frame: frame))
        }
        return out
    }

    /// Подписи пункта по бандлу выбранного Claude (кэш по пути и mtime `en-US.json`).
    private let draftLabels = BlankWindow.LabelCache()

    /// Нажать File ▸ «New Session in New Window» у ВЫБРАННОГО Claude (у Элвиса их два, #7096).
    /// Пункт не кэшируем: Claude пересобирает меню при смене поверхности, и пункт есть только на
    /// Code. Каждому элементу свои 0,25 с, весь поиск — не дольше 1 с по часам; сперва File.
    /// Claude вперёд не поднимаем: AXPress жмёт пункт и у Claude позади (живая проверка S.0).
    func pressDraftItem(project: Project) -> Bool {
        noteUserCommand()
        guard let running = app.running() else { return false }
        let wanted = Set(draftLabels.labels(bundle: running.bundleURL))
        let root = AXUIElementCreateApplication(running.processIdentifier)
        AX.timeout(root, BlankWindow.axTimeout)
        guard let bar = AX.element(root, kAXMenuBarAttribute) else { return false }
        AX.timeout(bar, BlankWindow.axTimeout)
        let tops = AX.elements(bar, kAXChildrenAttribute)
        let deadline = Date().addingTimeInterval(BlankWindow.searchSeconds)
        for index in BlankWindow.searchOrder(count: tops.count) where Date() < deadline {
            AX.timeout(tops[index], BlankWindow.axTimeout)
            for menu in AX.elements(tops[index], kAXChildrenAttribute) where Date() < deadline {
                AX.timeout(menu, BlankWindow.axTimeout)
                let items = AX.elements(menu, kAXChildrenAttribute)
                // Срок — и внутри перебора пунктов: у зависшего меню каждый пункт ест свои 0,25 с.
                var titles: [BlankWindow.MenuTitle] = []
                for item in items where Date() < deadline {
                    AX.timeout(item, BlankWindow.axTimeout)
                    titles.append((title: AX.string(item, kAXTitleAttribute) ?? "",
                                   enabled: AX.bool(item, kAXEnabledAttribute)))
                }
                if let hit = BlankWindow.match(titles, labels: wanted) {
                    // Папка свежая, только когда пункт правда нажат.
                    guard AX.perform(items[hit], kAXPressAction) else { return false }
                    onProjectUsed?(project)
                    return true
                }
            }
        }
        return false
    }

    /// Пункт «Settings…» меню приложения Claude (WF126 §7.3, «Открыть настройки Claude»): AXPress и Claude вперёд.
    /// Ищем только в первом меню (меню приложения), не дольше `BlankWindow.searchSeconds`.
    func pressClaudeSettings() -> Bool {
        noteUserCommand()
        guard let running = app.running() else { return false }
        let root = AXUIElementCreateApplication(running.processIdentifier)
        AX.timeout(root, BlankWindow.axTimeout)
        guard let bar = AX.element(root, kAXMenuBarAttribute) else { return false }
        AX.timeout(bar, BlankWindow.axTimeout)
        let tops = AX.elements(bar, kAXChildrenAttribute)
        let deadline = Date().addingTimeInterval(BlankWindow.searchSeconds)
        // [0] — меню Apple, [1] — меню приложения.
        for top in tops.prefix(2) where Date() < deadline {
            AX.timeout(top, BlankWindow.axTimeout)
            for menu in AX.elements(top, kAXChildrenAttribute) where Date() < deadline {
                AX.timeout(menu, BlankWindow.axTimeout)
                for item in AX.elements(menu, kAXChildrenAttribute) where Date() < deadline {
                    AX.timeout(item, BlankWindow.axTimeout)
                    guard Self.isSettingsTitle(AX.string(item, kAXTitleAttribute) ?? "") else { continue }
                    guard AX.perform(item, kAXPressAction) else { return false }
                    _ = running.activate(options: [])
                    return true
                }
            }
        }
        return false
    }

    /// «Settings…», «Settings...», «Preferences…» — без учёта регистра.
    static func isSettingsTitle(_ title: String) -> Bool {
        let word = title.trimmingCharacters(in: CharacterSet(charactersIn: " .…")).lowercased()
        return word == "settings" || word == "preferences"
    }

    /// Команда `send-text` окну чата (WF103, #7953): страница сверяет `chat` с собой, вставляет
    /// текст в пустое поле и жмёт «отправить»; исход — `status().send` с этим `id`.
    func sendText(chat: String, text: String, id: String) {
        commands.write(action: PimpChannel.sendTextAction,
                       fields: [(key: "chat", value: .string(chat)), (key: "text", value: .string(text))], id: id)
    }

    /// Команда `draft-setup` черновику (К18): его только что подняли `raise`, и страница берёт
    /// окно в фокусе — пишем после паузы на фокус, как у прочих команд окну.
    func sendDraftSetup(_ fields: [(key: String, value: CommandValue)]) {
        after(focusDelay) { [weak self] in
            self?.commands.write(action: BlankWindow.draftSetupAction, fields: fields)
        }
    }

    /// Какое AX-окно отвечает записи `CGWindowList` и с какой рамкой: сперва совпадение по
    /// рамке, а нет его — пара, запомненная по номеру окна, и её ЖИВАЯ рамка из AX.
    /// Зачем: сразу после переезда `CGWindowList` ещё отдаёт СТАРЫЕ координаты, совпадения
    /// не находится, и окно пропадало из списка целиком — на «расставь» сразу после «расставь»
    /// канал отвечал «окон нет» (#5684, гейт WF21). Номер окна живёт, пока живо само окно.
    /// Запомненная пара без рамки — окно закрылось, её забываем.
    /// Чистая: AX сюда подаёт `pimpWindows`, а тесты — свои замыкания.
    static func pimpPair(byFrame: AXUIElement?, remembered: AXUIElement?, quartz: CGRect,
                         liveFrame: (AXUIElement) -> CGRect? = { AX.frame($0) })
        -> (window: AXUIElement, frame: CGRect)? {
        if let window = byFrame { return (window, quartz) }
        guard let known = remembered, let live = liveFrame(known) else { return nil }
        return (known, live)
    }

    /// Адрес показа выбираем только среди видимых опознанных окон, без догадок по заголовку.
    struct SendDelayPreviewTarget: Equatable {
        let id: CGWindowID
        let match: String?
        let chat: String?
    }

    static func sendDelayPreviewTarget(visible: [(id: CGWindowID, page: ChatPage?)],
                                       focused: CGWindowID?, pages: [ChatPage]) -> SendDelayPreviewTarget? {
        let targets = visible.compactMap { entry -> SendDelayPreviewTarget? in
            guard let page = entry.page else { return nil }
            switch page.kind {
            case .main:
                guard !page.path.isEmpty, page.path != "blank",
                      pages.filter({ $0.kind != .other && $0.path == page.path }).count == 1 else { return nil }
                return SendDelayPreviewTarget(id: entry.id, match: page.path, chat: nil)
            case .popout:
                guard let chat = page.chat, !chat.isEmpty,
                      pages.filter({ $0.kind != .other && $0.chat == chat }).count == 1 else { return nil }
                return SendDelayPreviewTarget(id: entry.id, match: nil, chat: chat)
            case .other: return nil
            }
        }
        return targets.first(where: { $0.id == focused })
            ?? targets.first(where: { $0.match != nil }) ?? targets.first
    }

    /// Окно для показа отсчёта, когда опознать не вышло (WF180): главное окно Claude на экране — в фокусе, если
    /// их несколько; главного на экране нет — nil (команда без адреса играет только в главном).
    static func sendDelayFallbackWindow(_ windows: [(id: CGWindowID, main: Bool, focused: Bool)]) -> CGWindowID? {
        let mains = windows.filter { $0.main }
        return (mains.first(where: { $0.focused }) ?? mains.first)?.id
    }

    /// Поднять окно вперёд (канал «Пимп», план WF75): «последний чат проекта» уже открыт
    /// окном — открывать нечего, окно надо только показать и поставить на место. Тот же
    /// порядок, что у фокуса перед командой: активировать Claude, поднять, сделать главным.
    func raise(id: CGWindowID) {
        guard let entry = pimpWindows(with: [id]).first(where: { $0.id == id }) else { return }
        app.focus(window: entry.window)
    }

    /// Закрыть окно его красной кнопкой (план WF75) — тем же путём, что замена окна на
    /// «Обкэшить» (`cashoutReplace`). ⌘W каналу не даём НИКОГДА: `postKey` уходит в процесс
    /// Claude, и исполнит его КЛЮЧЕВОЕ окно, а не то, что мы выбрали (#5734). Кнопки у окна
    /// может не быть вовсе (Electron ещё не отдал дерево) — тогда false, и канал честно
    /// говорит, что не закрыл.
    func close(id: CGWindowID) -> Bool {
        guard let entry = pimpWindows().first(where: { $0.id == id }) else { return false }
        AX.timeout(entry.window, ClaudeActions.axWindowTimeout)
        return AX.close(entry.window)
    }

    /// Номер окна Claude в фокусе — и только пока Claude ПЕРЕДНЯЯ программа (план WF75):
    /// `paste` с `front:true` обязан вставлять ровно туда, куда Элвис нажал бы ⌘V сам.
    /// Claude позади или окна не видно — nil, и канал отказывает.
    func frontWindowID() -> CGWindowID? {
        guard app.isFrontmost, let focused = app.focusedWindow() else { return nil }
        return pimpWindows().first { CFEqual($0.window, focused) }?.id
    }

    /// «Вставить» каналом (план WF75): файлы ложатся в буфер, окно поднимается, и после
    /// паузы на фокус в процесс Claude уходит ⌘V. **Enter не шлём никогда** — вставка не
    /// отправка. Ответ канала пишется из `done`, уже ПОСЛЕ нажатия (критик п. 6): фокус
    /// асинхронный, и до него `ok` не значил бы ничего.
    func paste(into id: CGWindowID, paths: [String], done: @escaping (Bool) -> Void) {
        guard let entry = pimpWindows().first(where: { $0.id == id }) else {
            done(false)
            return
        }
        if !paths.isEmpty { ClaudeActions.writeFiles(paths) }
        app.focus(window: entry.window)
        after(focusDelay) { [weak self] in
            guard let self = self else {
                done(false)
                return
            }
            // ⌘V уходит в ПРОЦЕСС и достанется ключевому окну (#5734): фокус не доехал —
            // честный отказ, а не вставка в чужой чат.
            guard let focused = self.app.focusedWindow(), CFEqual(focused, entry.window) else {
                done(false)
                return
            }
            self.app.postKey(CGKeyCode(ClaudeActions.pasteKeyCode), flags: .maskCommand)
            done(true)
        }
    }

    /// `kVK_ANSI_V`: в таблице `KeySpec.codes` клавиши «v» нет, и заводить её там незачем —
    /// пункта меню у вставки нет, это код одной команды канала (критик п. 2 плана WF75).
    static let pasteKeyCode: UInt32 = 0x09

    /// Файлы в буфер обмена. Несколько разом умеет только `writeObjects` — `CopyFileRelay`
    /// кладёт ОДИН файл строкой (критик п. 3). Прежний буфер не восстанавливаем: типы
    /// с ленивой поставкой вернуть нельзя (критик п. 5), и обещать это было бы враньём.
    static func writeFiles(_ paths: [String]) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
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
    func arrange(ids: [CGWindowID], mode: ArrangeLayout.Mode, hub: CGWindowID? = nil)
        -> (placed: [(id: CGWindowID, title: String, frame: CGRect)], skipped: Int) {
        let windows = pimpWindows()
        let plan = Self.orderedPlacement(ids: ids, mode: mode, hub: hub,
            windows: windows.map { (id: $0.id, frame: $0.frame) }, minWidth: cellWidth(), gap: cellGap(),
            area: { Screens.usableFrame(holding: $0) })
        var out: [(id: CGWindowID, title: String, frame: CGRect)] = []
        for move in plan {
            guard let window = windows.first(where: { $0.id == move.id }) else { continue }
            ClaudeActions.setFrame(window.window, move.frame)
            out.append((id: window.id, title: window.title, frame: move.frame))
        }
        if !out.isEmpty { onWindowsMoved?() }
        return (placed: out, skipped: ids.count - out.count)
    }

    /// Explicit hub identity selects both the screen and the central cell. Missing neighbours
    /// may compact the order; a missing hub never promotes a neighbour to main.
    static func orderedPlacement(ids: [CGWindowID], mode: ArrangeLayout.Mode, hub: CGWindowID?,
                                 windows: [(id: CGWindowID, frame: CGRect)], minWidth: CGFloat, gap: CGFloat,
                                 area: ([CGRect]) -> CGRect?) -> [PimpMove] {
        var ordered = ids.compactMap { id in windows.first { $0.id == id } }
        guard !ordered.isEmpty else { return [] }
        let holding: [CGRect]
        if mode == .center {
            guard let hub = hub, let main = ordered.first(where: { $0.id == hub }) else { return [] }
            holding = [main.frame]
        } else { holding = ordered.map { $0.frame } }
        guard let screen = area(holding) else { return [] }
        if mode == .center, let hub = hub, let main = ordered.first(where: { $0.id == hub }) {
            ordered.removeAll { $0.id == hub }
            ordered.insert(main, at: ArrangeLayout.centerHubIndex(count: ordered.count + 1, in: screen,
                                                                  minCellWidth: minWidth, gap: gap))
        }
        let cells = ArrangeLayout.frames(count: ordered.count, in: screen, mode: mode,
                                         minCellWidth: minWidth, gap: gap)
        return zip(ordered, cells).map { PimpMove(id: $0.0.id, frame: $0.1) }
    }

    /// Место главного в порядке «главного по центру» по экранам окон (хвост WF107): в тесноте главный
    /// на `n / 2`, иначе на `(n − 1) / 2` (`ArrangeLayout.centerHubIndex`). Место верное, когда экран его
    /// окна даёт это же место; сперва — `n / 2`: у Элвиса главный на широком экране, а соседом бывает
    /// окно MacBook, где на `n` окон не тесно, а не влезает вовсе, и там вышло бы `(n − 1) / 2`.
    /// Ничто не сошлось — `(n − 1) / 2`, как было. `area` — рабочая область экрана окна с этим номером.
    static func centerSlot(count: Int, minCellWidth: CGFloat, gap: CGFloat,
                           area: (Int) -> CGRect?) -> Int {
        let loose = max(0, (count - 1) / 2)
        for slot in [count / 2, loose] where slot < count {
            if let found = area(slot),
               ArrangeLayout.centerHubIndex(count: count, in: found, minCellWidth: minCellWidth, gap: gap) == slot {
                return slot
            }
        }
        return loose
    }

    /// Умная расстановка для канала «Пимп» (план WF77): окна названы номерами, экран у
    /// каждого свой. Отдаёт ВСЕ названные окна с итоговыми рамками — и сидящих тоже, им
    /// рамку не пишем вовсе («окна, которые уже стояли на месте, никуда не переводить»).
    /// Ячейка находится каждому, кто влез на экран, поэтому `skipped` у этого пути не
    /// бывает. `ordered` — порядок навязан: место названо словом («слева», «посередине»).
    /// `phantom` (WF98, #7841) — рамка, где родилось бы новое окно: номер `PimpChannel.phantomID`
    /// среди `ids` встаёт в расстановку без AX-окна, ему рамку не пишем, а в ответе он с ячейкой.
    @discardableResult
    func arrangeSmart(ids: [CGWindowID], ordered: Bool, anchor: CGWindowID? = nil,
                      phantom: CGRect? = nil)
        -> [(id: CGWindowID, title: String, frame: CGRect)] {
        let windows = pimpWindows(with: ids)
        let listed = ids.compactMap { id -> (id: CGWindowID, window: AXUIElement?, title: String, frame: CGRect)? in
            if let phantom = phantom, id == PimpChannel.phantomID {
                return (id: id, window: nil, title: "", frame: phantom)
            }
            return windows.first { $0.id == id }.map { (id: $0.id, window: $0.window, title: $0.title, frame: $0.frame) }
        }
        guard !listed.isEmpty else { return [] }
        let frames = listed.map { $0.frame }
        // ChatGPT (WF94, #7732) держит правую полосу экрана, где стоят окна Claude: ему — ширина
        // одного столбца (Electron зажмёт по своему минимуму), окнам Claude — остаток левее.
        var screens = Screens.all()
        let anchorFrame = anchor.flatMap { id in listed.first { $0.id == id }?.frame }
        for (strip, keepCells) in [(chatGPTWindows, false), (chromeWindows, true)] {
            guard let front = strip.front() else { continue }
            screens = ChatGPTWindows.reserve(screens: screens, claude: frames, chatGPT: front.frame,
                knownMinWidth: strip.learnedMinWidth, minCellWidth: cellWidth(), gap: cellGap(),
                keepCells: keepCells, anchor: anchorFrame,
                set: { strip.setFrame(front, $0) }).screens
        }
        // Окна уже идут в том порядке, о котором просили, — навязанный порядок это он и есть.
        let placed = ArrangeLayout.smart(frames: frames, screens: screens,
                                         minCellWidth: cellWidth(), gap: cellGap(),
                                         order: ordered ? Array(frames.indices) : nil,
                                         anchor: anchor.flatMap { id in listed.firstIndex { $0.id == id } })
        var out: [(id: CGWindowID, title: String, frame: CGRect)] = []
        var moved = 0
        for (index, entry) in listed.enumerated() {
            // Сидящему окну рамку не пишем ВОВСЕ: лишняя запись в AX дёргает окно даже на
            // тех же координатах, а Элвис просил таких не трогать.
            if let window = entry.window, !ClaudeActions.frameMatches(frames[index], placed[index]) {
                ClaudeActions.setFrame(window, placed[index])
                moved += 1
            }
            out.append((id: entry.id, title: entry.title, frame: placed[index]))
        }
        // Никто не сдвинулся — и probe переспрашивать незачем (#7062, как у `place`): лишний
        // «окна переехали» гонял круг карты чатов впустую.
        if moved > 0 { onWindowsMoved?() }
        return out
    }

    /// Умная сетка, в которой стоят эти окна, и её ячейки (#6747, WF84) — для снимка
    /// раскладки. Экран — тот, где стоит большинство окон, как у плиток.
    func smartGrid(frames: [CGRect]) -> (grid: LayoutGrid, cells: [CGRect])? {
        guard let area = Screens.usableFrame(holding: frames),
              let found = ArrangeLayout.sittingGrid(frames: frames, in: area,
                                                    minCellWidth: cellWidth(), gap: cellGap())
        else { return nil }
        let grid = LayoutGrid(cols: found.cols, rows: found.rows)
        return (grid: grid, cells: gridCells(grid, frames: frames))
    }

    /// Ячейки умной сетки на экране, где стоят окна Claude (#6747): по ним возвращается
    /// раскладка, записанная по такой сетке. `frames` nil — окна на экране сейчас.
    func gridCells(_ grid: LayoutGrid, frames: [CGRect]? = nil) -> [CGRect] {
        guard let area = Screens.usableFrame(holding: frames ?? pimpWindows().map { $0.frame })
        else { return [] }
        return ArrangeLayout.cells(cols: grid.cols, rows: grid.rows, count: grid.cols * grid.rows,
                                   in: area, gap: cellGap())
    }

    /// Поставить окна по рамкам — деление столбца пополам («под этим»/«над этим»).
    /// Остальные окна не трогаем вовсе.
    /// `fresh` — окно только что родилось (WF98, #7841): рамка порядком свежего окна (#5791).
    @discardableResult
    func place(_ moves: [PimpMove], fresh: Bool = false) -> Int {
        guard !moves.isEmpty else { return 0 }
        let windows = pimpWindows(with: moves.map { $0.id })
        var moved = 0
        for move in moves {
            guard let entry = windows.first(where: { $0.id == move.id }) else { continue }
            if fresh { AX.timeout(entry.window, ClaudeActions.axWindowTimeout) }
            ClaudeActions.setFrame(entry.window, move.frame, fresh: fresh)
            moved += 1
        }
        if moved > 0 { batchCensus = nil; onWindowsMoved?() }
        return moved
    }

    // MARK: - новое окно сразу на месте (WF98, #7841)

    /// Номера окон Claude на экране — один вызов `CGWindowList`, без AX: опрос рождения окна
    /// 0,1 с (`BirthWatch`) спрашивает только это.
    func onScreenIDs() -> Set<CGWindowID> {
        guard let pid = app.pid else { return [] }
        return Set(ClaudeApp.onScreenFrames(pid: pid).map { $0.id })
    }

    /// Где родилось бы новое окно без плана — там же, куда его ставит «Новое окно»: уступ от окна
    /// в фокусе (`popoutOrigin`) и размер попапа Claude. По ней призрак попадает на свой экран.
    func birthFrame() -> CGRect {
        let origin = ClaudeActions.popoutOrigin(near: focusedWindow().flatMap { AX.frame($0) })
        return CGRect(origin: CGPoint(x: origin.x, y: origin.y), size: ClaudeActions.popoutWindowSize)
    }

    /// Сиденья канала для «сразу на месте» и опрос рождения окна «Обкэшить»/«💬 Новый чат» —
    /// одним вызовом из контроллера.
    func connectNewWindowPlace(_ seats: inout PimpSeats) {
        let ids: () -> Set<CGWindowID> = { [weak self] in self?.onScreenIDs() ?? [] }
        seats.windowIDs = ids
        seats.makeRoom = { [weak self] order in
            guard let self = self else { return [] }
            return self.arrangeSmart(ids: order, ordered: true, anchor: PimpChannel.phantomID,
                                     phantom: self.birthFrame())
                .map { PimpWindow(id: $0.id, title: $0.title, frame: $0.frame) }
        }
        seats.placeNew = { [weak self] move in self?.place([move], fresh: true) }
        seats.windowBorn = { [weak self] in self?.app.forgetWindows() }
        seats.placeChatGPT = { [weak self] frame in
            guard let self = self, let gpt = self.chatGPTWindows.front() else { return }
            _ = self.chatGPTWindows.setFrame(gpt, frame)
        }
        seats.chrome = { [weak self] in self?.chromeWindows.front() }
        seats.chromeFrame = { [weak self] in self?.chromeWindows.currentFrame(of: $0) }
        seats.placeChrome = { [weak self] window, expected, original in
            guard let self = self, let frame = self.chromeWindows.currentFrame(of: window),
                  Self.frameMatches(frame, expected) else { return }
            _ = self.chromeWindows.setFrame(window, original)
        }
        windowIDs = ids
    }

    /// Окна ChatGPT (WF94): отдельный список, в `pimpWindows` они не входят никогда.
    let chatGPTWindows = ChatGPTWindows()
    let chromeWindows = ChatGPTWindows(bundleIDs: [HtmlChromeOpener.chromeBundleID])

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

    /// Зазор между окнами. Живьём — из claude.json, в тестах подставляется.
    var cellGap: () -> CGFloat = { ClaudeActions.windowGap() }

    /// Зазор по умолчанию и его потолок (план WF77, слово Элвиса 20.09: «между окнами
    /// небольшие отступы — это специально… должна быть настройка, сколько пикселей; по
    /// умолчанию — как у меня сейчас»). Шире 40 pt не берём: ячейки начали бы съедаться
    /// щелями, а потолок столбцов — проваливаться.
    static let defaultWindowGap: CGFloat = 5
    static let maxWindowGap: CGFloat = 40

    /// `windowGap` из живого `claude.json` — тем же способом, что `minCellWidth`: пункта
    /// меню у него нет, Элвис правит файл руками, и битое значение не должно разъезжать
    /// окна. Ключа нет или он не число — 5; за края зажимаем.
    static func windowGap(configURL: URL = CommandChannel.directory
                            .appendingPathComponent(StatusFeed.configFileName)) -> CGFloat {
        let data = try? Data(contentsOf: configURL)
        let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        guard let value = (json?["windowGap"] as? NSNumber)?.doubleValue, value.isFinite else {
            return defaultWindowGap
        }
        return min(max(CGFloat(value), 0), maxWindowGap)
    }

    /// Все окна Claude вперёд, потом фокус обратно тому, из которого пришли.
    func showAll(_ window: AXUIElement?) {
        guard app.running() != nil else { return }
        // Через замок меню (WF145): открытое меню PMP активация закрыла бы.
        MenuHold.shared.run { [weak self] in
            guard let self = self, let running = self.app.running() else { return }
            running.activate(options: [.activateAllWindows])
            for candidate in self.app.visibleWindows() { AX.perform(candidate, kAXRaiseAction) }
        }
        guard let window = window else { return }
        // activate/raise асинхронные — даём им тик, прежде чем забрать фокус назад.
        after(focusDelay) { [weak self] in self?.app.focus(window: window) }
    }

    /// Окна переехали: кэш прямоугольников кнопки «Свернуть» протух.
    var onExplicitLayout: (([PimpMove]) -> Void)?
    var onWindowsMoved: (() -> Void)?

    /// Короткая плашка на экран (HUD) — ставит ClaudeAXController. Пока единственный повод:
    /// в сборке нет комплекта workflow-kit.
    var onWarning: ((String) -> Void)?

    /// То же, но со своим сроком: «Новое окно» работает до 65 с, и штатные 2,5 с `onWarning`
    /// гасли бы задолго до результата (критик п. 20 плана WF13).
    var onNotice: ((String, TimeInterval) -> Void)?

    /// Чем откладываются шаги цепочек окон (фокус → команда, команда → ⌘N). Живьём — главная
    /// очередь ходом вперёд, как было; в тестах подставляется, чтобы шаг был виден без
    /// ожидания (тот же приём, что у `frameSchedule` и у канала команд).
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        schedule(delay, block)
    }
}
