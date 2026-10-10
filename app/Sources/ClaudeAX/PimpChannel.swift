import CoreGraphics
import Foundation
import Darwin

/// Окно Claude глазами канала «Пимп» (план WF36): номер окна Quartz, заголовок, рамка и —
/// когда карта чатов жива — чат и папка. Номер окна тут главный: заголовки повторяются
/// (у главного окна и безымянного попапа он один — «Claude»), а рамки меняются на глазах,
/// как только окна расставили. По номеру же видно НОВОЕ окно: то, которого не было до запроса.
struct PimpWindow: Equatable {
    let id: CGWindowID
    let title: String
    /// id чата (`local_…`) или "" — карта чатов (`ChatProbe`) молчит или окно не опознано.
    let chat: String
    /// Абсолютный путь папки проекта или "".
    let folder: String
    let frame: CGRect
    /// Resolved per window, never inferred from a duplicate title. nil is legacy/test input.
    let main: Bool?

    func isMain(using fallback: (String) -> Bool) -> Bool { main ?? fallback(title) }

    init(id: CGWindowID, title: String, chat: String = "", folder: String = "",
         frame: CGRect = .zero, main: Bool? = nil) {
        self.id = id
        self.title = title
        self.chat = chat
        self.folder = folder
        self.frame = frame
        self.main = main
    }
}

/// Куда поставить окно (`place` запроса).
enum PimpPlace: Equatable {
    /// Столбцом слева / в середине / справа: порядок задаёт `ArrangeLayout.insert`.
    case left, middle, right
    /// Пополам по высоте столбца окна `from`; остальные окна не трогаем.
    case below, above
    /// Точка в перевёрнутых координатах Quartz — ровно как «🪟 Новое окно» в меню.
    case point(x: Int, y: Int)
}

/// Одно перемещение окна: канал говорит номерами окон, AX-элементы остаются в `ClaudeActions`.
struct PimpMove: Equatable {
    let id: CGWindowID
    let frame: CGRect
}

/// Запрос канала: `{"id","at","action","from",…}` (контракт плана WF36, эталоны
/// `tests/fixtures/pimp/*.request.json`).
struct PimpRequest: Equatable {
    enum Action: String {
        case newWindow = "new-window", arrange, projects, windows
        /// Окна при смене мониторов (#7740, WF94): вернуть их, как стояли на этом наборе экранов.
        case screensRestore = "screens-restore"
        /// Раскладки проектов (план WF41): список, запомнить, вернуть.
        case layouts
        case layoutSave = "layout-save"
        case layoutRestore = "layout-restore"
        /// Голосовой Пимп (план WF75): закрыть окно проекта, вставить в окно, сказать плашкой.
        case closeWindow = "close-window"
        case paste, hud
        /// Замена окна (WF102, #7917): новый чат проекта в рамку окна, старое окно закрыть.
        case renewWindow = "renew-window"
        /// Отправить текст в чат (WF103, #7953, #7927): вставка в поле окна и кнопка «отправить».
        case send
        /// Перезапустить Claude путём «Обновить Claude» и вернуть окна по снимку К5 (WF108, #8176).
        case restartClaude = "restart-claude"
        /// Чат — в главное окно Claude, прежний чат главного окна — в своё окно (WF108, #8148).
        case main
        /// Свернуть все окна Claude, кроме главного, и развернуть свёрнутые (WF112, #8255).
        case hide, show
        /// Притемнение окон, кроме главного (WF113, #8256), и вид ракеты отправки (WF114, #8226): меняют
        /// те же UserDefaults, что панель у часов, и отвечают итогом.
        case dim, look
    }

    let id: String
    /// Когда запрос написан: старше 30 с — «stale», исполнять поздно.
    let at: Date
    let action: Action
    /// id чата, из которого позвали (`local_…`) или "" — переменной у субагента нет.
    let from: String
    /// Имя папки или абсолютный путь (`new-window`, `close-window`, `paste`).
    let project: String
    /// Только `new-window`; поля нет — «справа».
    let place: PimpPlace
    /// Только `new-window` (план WF75): `last` — открыть последний чат проекта вместо нового;
    /// поля нет — "", чужое значение — `bad-request`. У `renew-window` (WF102) — `local_…`
    /// окна, которое меняем.
    let chat: String
    /// Только `arrange` (план WF21): раскладка; nil — `last`, то есть последняя выбранная,
    /// её подставляет приложение. Поля нет — лента (умолчание CLI).
    let layout: ArrangeLayout.Mode?
    /// Только `arrange` (план WF41): порядок проектов — абсолютные пути или имена папок.
    /// nil — поля не было, и ответ остаётся прежним (без `unknown` и `missing`).
    let order: [String]?
    /// Имя раскладки (`layout-save`, `layout-restore`).
    let name: String
    /// `layout-restore`: новые чаты по тем же папкам вместо тех же самых чатов.
    let fresh: Bool
    /// `projects`: просили ли сводку проектов (поле есть, только когда true).
    let status: Bool
    /// Только `paste` (план WF75): вставлять в окно Claude В ФОКУСЕ и только пока Claude —
    /// передняя программа. Элвис жмёт свою клавишу в том чате, куда хочет вставить.
    let front: Bool
    /// Только `paste`: абсолютные пути файлов (0…20). Пусто — вставляем то, что уже лежит
    /// в буфере, и буфер не трогаем.
    let paths: [String]
    /// Только `hud`: текст плашки (1…200 знаков, длиннее — обрезан разбором). У `renew-window`
    /// (WF102) — первое сообщение нового чата без обрезки (до 20 000 знаков); "" — штатный текст.
    let text: String
    /// Только `arrange` + `center` (WF102, #7904): главный — проект, путь или `local_…`;
    /// "" — окно чата `from`, нет его — главное окно Claude.
    var center = ""
    /// Только `renew-window` (WF102): подпись пункта меню модели («Opus 5.5») и ступень
    /// эффорта (`low|medium|high|extra|max`); "" — не трогать.
    var model = ""
    var effort = ""
    /// Только `restart-claude` (WF108): перезапускать, даже когда в чатах идёт ответ.
    var force = false
    /// Только `dim` (WF113): включить или снять; сила — проценты 20…80 (в запросе дробь 0.2…0.8), nil — прежняя.
    var on = false
    var level: Int?
    /// Только `look` (WF114): вид (`1.8|1.1|1.2|1.3|1.4|1.6`, "" — прежний), размер 60…200 или прибавка
    /// к нынешнему (`grow`, «побольше»), `show` — проиграть вид в главном окне.
    var style = ""
    var size: Int?
    var grow: Int?
    var show = false
}

/// Ответ канала: `<id>.result.json` рядом с запросом. Порядок ключей побайтно —
/// id, at, ok, error, fromResolved, screen, затем поля действия (README фикстур).
struct PimpAnswer {
    let id: String
    let at: Date
    let ok: Bool
    let error: String
    /// Нашли ли окно чата `from`. Ищут его `new-window` и (с WF75) `paste` — остальным
    /// действиям окно-источник не нужен, и у них всегда `false` (как в эталонах).
    let fromResolved: Bool
    let fields: [(key: String, value: CommandValue)]

    init(id: String, at: Date, ok: Bool, error: String = "", fromResolved: Bool = false,
         fields: [(key: String, value: CommandValue)] = []) {
        self.id = id
        self.at = at
        self.ok = ok
        self.error = error
        self.fromResolved = fromResolved
        self.fields = fields
    }

    var json: String {
        var all: [(key: String, value: CommandValue)] = [
            (key: "id", value: .string(id)),
            (key: "at", value: .string(PimpChannel.stampText(at))),
            (key: "ok", value: .bool(ok)),
            (key: "error", value: .string(error)),
            (key: "fromResolved", value: .bool(fromResolved)),
            (key: "screen", value: .string(PimpChannel.screen)),
        ]
        all += fields
        return CommandValue.object(all).json
    }
}

/// Всё, что канал спрашивает у приложения. Живьём сиденья вешает `ClaudeAXController`,
/// в тестах — заглушки: ни AX, ни живого Claude каналу для проверки не нужно.
struct PimpSeats {
    /// Claude запущен (окна при этом могут быть спрятаны или свёрнуты).
    var claudeRunning: () -> Bool = { false }
    /// Окна Claude на экране.
    var windows: () -> [PimpWindow] = { [] }
    /// Свёрнутые окна: их не трогаем, но в ответе считаем.
    var minimized: () -> Int = { 0 }
    /// Недавние проекты (`projects.json`), свежие первыми.
    var projects: () -> [Project] = { [] }
    /// Открыть новое окно в папке проекта — тот же путь, что пункт меню «🪟 Новое окно ▸».
    /// `origin` — точка для места «x,y»; nil — как в меню (уступ от окна-источника).
    var openNewWindow: (Project, (x: Int, y: Int)?) -> Void = { _, _ in }
    /// Расставить окна в этом порядке по этой раскладке; возвращает окна с рамками, которые
    /// им поставили, и сколько окон осталось без ячейки — их не двигали (план WF21).
    var arrange: ([CGWindowID], ArrangeLayout.Mode, CGWindowID?) -> (windows: [PimpWindow], skipped: Int)
        = { _, _, _ in ([], 0) }
    /// Умная расстановка (план WF77): сетку выбирает не плитка, а то, как окна стоят
    /// сейчас; окна с разных экранов остаются каждое на своём, стоящие на месте не
    /// двигаются. Отдаёт ВСЕ названные окна с итоговыми рамками — ячейка есть у каждого,
    /// кто влез на экран. Второй параметр — «порядок навязан»: место названо словом.
    var arrangeSmart: (_ ids: [CGWindowID], _ ordered: Bool, _ anchor: CGWindowID?) -> [PimpWindow] = { _, _, _ in [] }
    /// Последняя выбранная раскладка: её берут явные плитки. Умный путь её не читает и не
    /// пишет (критик WF77 блокер 2: иначе «расставь» стирала бы выбор Элвиса).
    var arrangeMode: () -> ArrangeLayout.Mode = { .ribbon }
    /// Влезает ли раскладка на экран (ячейка не уже `minWindowWidth`) — иначе `too-small`.
    var fitsLayout: (ArrangeLayout.Mode) -> Bool = { _ in true }
    /// Поставить окна по рамкам (деление столбца пополам).
    var place: ([PimpMove]) -> Void = { _ in }
    /// Заголовок окна чата `from`: главное окно — по индексу Claude, попап — по карте probe.
    var titleForChat: (String) -> String? = { _ in nil }
    /// Ушли ли слои (цвет) с последней командой «новое окно» — поле `layers` ответа.
    var newWindowLayers: () -> Bool = { false }
    /// Сохранённые раскладки (`layouts.json`), свежие первыми (план WF41).
    var layouts: () -> [WindowLayout] = { [] }
    /// Записать раскладку (перезапись по имени); false — файл не записался.
    var saveLayout: (WindowLayout) -> Bool = { _ in false }
    /// Ячейки раскладки на экране, где стоят окна: по ним считается номер ячейки окна
    /// («Запомнить») и куда его ставить («Вернуть»).
    var cells: (ArrangeLayout.Mode, Int) -> [CGRect] = { _, _ in [] }
    /// Сетка умной расстановки, в которой стоят эти рамки окон, и её ячейки (#6747, WF84):
    /// «Запомнить» сразу после «расставь» иначе отвечало `not-arranged`. nil — ни одно окно
    /// ни в какой умной сетке не стоит.
    var smartGrid: ([CGRect]) -> (grid: LayoutGrid, cells: [CGRect])? = { _ in nil }
    /// Ячейки умной сетки «столбцы × ряды» на экране, где стоят окна, — возврат раскладки,
    /// записанной по такой сетке (#6747).
    var gridCells: (LayoutGrid) -> [CGRect] = { _ in [] }
    /// Зазор между окнами (`windowGap`, WF77): «под этим»/«над этим» делит столбец с ним же
    /// (#7062, WF84). Умолчание 0 — половинки встык, как до WF84.
    var gap: () -> CGFloat = { 0 }
    /// Это главное окно Claude? В записи раскладки у него `chat:"main"`, и при возврате
    /// ему ставится только рамка — чат мы не меняем.
    var isMainWindow: (String) -> Bool = { _ in false }
    /// Вынести названный чат отдельным окном в эту точку — команда `popout-window`
    /// главному окну (план WF41, «Вернуть эти чаты»).
    var openChat: (String, String, (x: Int, y: Int)) -> Void = { _, _, _ in }
    /// Сказать Элвису плашкой, что долгая работа кончилась. У возврата из МЕНЮ запроса нет,
    /// и ответить некому: без этого пункт «↩︎ Вернуть эти чаты» молчит навсегда (#5689).
    /// Тем же сиденьем говорит действие `hud` (план WF75) — своего оно не заводит.
    var notice: (String) -> Void = { _ in }
    /// Поднять окно вперёд (план WF75): «последний чат проекта» уже открыт окном — открывать
    /// нечего, окно поднимается и встаёт на место.
    var raise: (CGWindowID) -> Void = { _ in }
    /// Закрыть окно его красной кнопкой (`AX.close`); false — кнопки у окна нет, и окно
    /// осталось на экране. ⌘W каналу недоступен нарочно: он уходит в процесс и попадает
    /// в ключевое окно, а не в выбранное (#5734).
    var close: (CGWindowID) -> Bool = { _ in false }
    /// Окно Claude в фокусе — и только пока Claude ПЕРЕДНЯЯ программа; иначе nil
    /// (`paste` с `front:true` вставляет ровно туда, куда Элвис нажал бы ⌘V сам).
    var frontWindow: () -> CGWindowID? = { nil }
    /// Положить файлы в буфер (пусто — буфер не трогать), поднять окно и нажать ⌘V.
    /// Ответ канала пишется из замыкания — уже ПОСЛЕ нажатия; false — не нажали.
    var paste: (CGWindowID, [String], @escaping (Bool) -> Void) -> Void = { _, _, done in
        done(false)
    }
    /// Последний чат папки: свежайшая НЕ архивная сессия индекса Claude (`ProjectIndex`),
    /// а не карта probe — она знает только чаты, открытые окнами (критик Б1 плана WF75).
    var lastChat: (URL) -> (chat: String, title: String)? = { _ in nil }

    // Пустое окно проекта (план WF88, К17). Новые сиденья — в конце и с умолчаниями:
    // `PimpChannelTests` и контроллер собирают сиденья поимённо.

    /// Идёт чужая цепочка нового окна: перенос «Обкэшить» («💬 Новый чат», ссылка, отсчёт
    /// «сам») или прогрев «Нового окна» моложе 40 с (правка критика V-N п. 3). Её попап до имени
    /// чата тоже зовётся «Code», и пустое окно в это время не начинаем.
    var newWindowBusy: () -> Bool = { false }
    /// Все окна выбранного Claude по AX — и те, что `windows` отсеивает по рамке служебного
    /// окна (правка критика V-N п. 1). Номер — Quartz, а у окна без пары — свой жетон.
    var blankWindows: () -> [PimpWindow] = { [] }
    /// Нажать File ▸ «New Session in New Window» у выбранного Claude; false — пункта нет,
    /// он выключен или AX отказал.
    var pressDraftItem: (Project) -> Bool = { _ in false }
    /// Команда `draft-setup` черновику, которого только что подняли (`raise`).
    var draftSetup: ([(key: String, value: CommandValue)]) -> Void = { _ in }
    /// Модель чата из его файла сессии: пустое окно берёт её у последнего чата проекта.
    var chatModel: (String) -> SessionModel? = { _ in nil }
    /// Отложить шаг опроса черновика. Живьём — главная очередь; в тестах опрос шагает
    /// `pollBlank(at:)` сам, без таймера.
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { _, _ in }
    /// «Bypass permissions в новых чатах» (WF126 §7.3): черновику — `mode:"bypass"`.
    var bypassNew: () -> Bool = { false }

    // Окна WF94. Новые сиденья — в конце и с умолчаниями, как у WF88.

    /// Ход цепочки «Нового окна» главной страницы (`status().newWindow`, WF94 K-N): кончилась
    /// отказом — канал говорит `chat-not-created` сразу, а не через 40 с. nil — страница молчит.
    var newWindowRun: () -> NewWindowRun? = { nil }
    /// Переднее окно ChatGPT (#7732): в ответе `windows` — отдельной записью с `app:"chatgpt"`.
    var chatGPT: () -> PimpWindow? = { nil }
    /// «Верни окна как были на этих мониторах» (#7740, `screens-restore`): сколько окон встало
    /// и сколько не нашлось; nil — для этого набора экранов окон ещё не запоминали.
    var restoreScreens: () -> (placed: Int, missing: Int)? = { nil }

    // Новое окно сразу на месте (WF98, #7841). Новые сиденья — в конце и с умолчаниями.

    /// Номера окон Claude на экране — один вызов `CGWindowList`, без AX: по нему опрос 0,1 с
    /// замечает рождение окна, пока канал его ждёт. nil — опроса нет, ловит общий тик 2 с.
    var windowIDs: (() -> Set<CGWindowID>)?
    /// Раздвинуть окна ДО рождения нового: порядок номеров как у `arrangeSmart`, среди них
    /// `PimpChannel.phantomID` — место будущего окна. Отдаёт итоговые рамки всех названных,
    /// у призрака — его ячейка. Пусто — посчитать нечем, окно ставится по-старому при рождении.
    var makeRoom: ([CGWindowID]) -> [PimpWindow] = { _ in [] }
    /// Поставить только что родившееся окно в его ячейку — порядком свежего окна
    /// (`setFrame(fresh:true)`, #5791). nil — плана нет вовсе: ставить окно по плану было бы нечем.
    var placeNew: ((PimpMove) -> Void)?

    // Проверка гейта WF98 (#7841). Новые сиденья — в конце и с умолчаниями.

    /// Идёт возврат снимка окон (К5, `windowSnapshots.phase == .restoring`): окна двигает он,
    /// и раздвигать соседей заранее или ловить рождение опросом 0,1 с в это время нельзя.
    var isRestoring: () -> Bool = { false }
    /// Вернуть переднему окну ChatGPT эту рамку — `undo`, когда `makeRoom` его сузил, а окно
    /// Claude так и не пришло.
    var placeChatGPT: (CGRect) -> Void = { _ in }
    /// Capture a native Chrome window for undo; front-window changes do not change the target.
    var chrome: () -> ChatGPTWindow? = { nil }
    var chromeFrame: (ChatGPTWindow) -> CGRect? = { _ in nil }
    var placeChrome: (_ window: ChatGPTWindow, _ expected: CGRect, _ original: CGRect) -> Void = { _, _, _ in }

    // Чистка WF101 (z4-r01). Новые сиденья — в конце и с умолчаниями.

    /// Идёт цепочка «Нового окна», начатая мимо канала (⌥⌘N, «💬 Новый чат», «Обкэшить») —
    /// `ClaudeActions.newWindowStarting`, то же правило, что у `refuseNewWindowRepeat`.
    var newWindowStarting: () -> Bool = { false }
    /// Опрос рождения увидел свежий номер окна (z3-r02): живьём сбрасывает кэш AX-окон, чтобы
    /// `windows` сразу нашёл новому окну пару.
    var windowBorn: () -> Void = {}

    // WF102: замена окна и «главный по центру». Новые сиденья — в конце и с умолчаниями.

    /// Новое окно проекта для `renew-window` (#7917): тот же путь, что `openNewWindow`, плюс
    /// первый текст (nil — штатный) и модель/эффорт/закрепка без записи «Обкэшить».
    var openRenewWindow: (Project, (x: Int, y: Int), String?, NewChatHandoff) -> Void = { _, _, _, _ in }
    /// Экраны: полная рамка и рабочая область (`Screens.all()`). Пусто — экранов не знаем, и
    /// «главный по центру» берёт все окна без проверки `too-small`.
    var screens: () -> [(full: CGRect, usable: CGRect)] = { [] }
    /// `minWindowWidth` — порог `too-small` «главного по центру».
    var cellWidth: () -> CGFloat = { 0 }

    // WF103: «отправь текст в чат». Новые сиденья — в конце и с умолчаниями.

    /// Команда `send-text` окну: `{"id","action":"send-text","at","chat","text"}`, id — id запроса.
    var sendText: (_ chat: String, _ text: String, _ id: String) -> Void = { _, _, _ in }
    /// Исход страницы из круга `cash` (`status().send` с этим id у любого окна); nil — ещё нет.
    var sendState: (_ id: String) -> String? = { _ in nil }

    // WF105, #8071: `arrange --order` не нашёл окно, чей чат не опознан (папка пустая), —
    // спросить страницы о чатах ещё раз и ответить после круга. nil — не переспрашивать.

    /// Попросить страницы назвать свои чаты (`ChatProbe.demand(at:)`).
    var demandChats: ((Date) -> Void)?
    /// Круг опознания пришёл после этой минуты (`ChatProbe.answered(after:)`).
    var chatsAnswered: (Date) -> Bool = { _ in true }

    // WF108, #8176: `restart-claude`. Новые сиденья — в конце и с умолчаниями.

    /// Чаты, где идёт ответ (`working` страниц, WF87): id чата (или "") и имя «папка / заголовок» —
    /// только из ответа страниц, пришедшего не раньше `since` (гейт 2 WF108: карта давностью до
    /// 180 с решать не годится). nil — не знаем: такого ответа нет.
    var workingChats: (_ since: Date) -> [(chat: String, name: String)]? = { _ in nil }
    /// Перезапустить Claude путём «Обновить Claude»: снимок окон К5, заморозка, выход, запуск той же
    /// копии. `done(nil)` — Claude снова запущен, `done(причина)` — нет; зовётся на главной нити.
    var restartClaude: (@escaping (String?) -> Void) -> Void = { done in done("перезапуск не подключён") }
    /// Исход автовозврата снимка К5 (гейт 2 WF108): ждёт свой Claude, возвращать нечего или сдался.
    var snapshotOutcome: () -> SnapshotOutcome = { .notNeeded }
    /// Каталог транскриптов Claude Code (`~/.claude/projects`); nil — не смотреть (гейт 2 WF108:
    /// чат без окна — оркестратор, ждущий фоновых агентов, — страницы не видят).
    var transcriptsRoot: () -> URL? = { nil }
    /// Чаты Claude Desktop с их сессией Claude Code (`cliSessionId` индекса) и именем «папка /
    /// заголовок». nil или пусто — индекс не прочитан, сопоставить транскрипты не с чем.
    var desktopSessions: () -> [(chat: String, cli: String, name: String)]? = { nil }

    // WF108, #8148: «чат в главное окно». Новые сиденья — в конце и с умолчаниями.

    /// Команда `main-chat` главной странице: открыть у себя чат, прежний вынести окном в эту точку.
    var sendMainChat: (_ chat: String, _ origin: (x: Int, y: Int)) -> Void = { _, _ in }
    /// `mainChat` живого `claude.json` (имя проекта или `local_…`); nil — держать нечего.
    var mainChatSetting: () -> String? = { nil }

    // WF112, #8255: «спрячь окна» / «покажи окна». Новые сиденья — в конце и с умолчаниями.

    /// Свернуть окна Claude, кроме главного (`ClaudeAXController.hideOthers`): отказ или заголовки.
    var hideWindows: () -> WindowHideResult = { WindowHideResult(failure: .noWindows) }
    /// Развернуть свёрнутые окна Claude, фокус — главному (`ClaudeAXController.showHidden`).
    var showWindows: () -> WindowHideResult = { WindowHideResult(failure: .noWindows) }
    /// Перед возвратом снимка К5 или раскладки: есть окна, спрятанные Пимпом, — развернуть их
    /// (гейт 1 WF111: свёрнутых нет в списке окон, и их чаты вынеслись бы дублями). true —
    /// развернули, возврат ждёт конца анимации (`WindowHide.focusDelay`).
    var showHiddenForRestore: () -> Bool = { false }
    /// `dim` (WF113): записать выбор, как выключатель и ползунок панели, и сказать итог.
    var setDim: (_ on: Bool, _ percent: Int?) -> PageLook = { on, percent in
        PageLook(dimOn: on, dimPercent: percent ?? DimSetting.defaultPercent)
    }
    /// `look` (WF114): записать вид и размер, как плитки и ползунок панели; `shown` — показ ушёл в главное окно.
    var setLook: (_ style: String?, _ size: Int?, _ grow: Int?, _ show: Bool) -> (look: PageLook, shown: Bool)
        = { _, _, _, _ in (PageLook(), false) }
    /// Restore presence is all Spaces; incomplete census must never mean a missing chat.
    var restoreWindows: (() -> (windows: [PimpWindow], complete: Bool))?
    var restoreFrame: (CGRect) -> CGRect = { $0 }
    var prepareNamedRestore: ([SnapshotWindow]) -> Bool = { _ in true }
    var finishNamedRestore: ([SnapshotWindow]) -> Bool = { _ in true }
    var explicitLayout: ([PimpMove]) -> Void = { _ in }
    var explicitNamedLayout: ([PimpMove]) -> Void = { _ in }
    var restoreFinished: () -> Void = {}

    // 01.10.2026: новый чат при свёрнутом или закрытом главном окне. Новые сиденья — в конце и с умолчаниями.

    /// Главного окна Claude на экране нет: свёрнутое — развернуть, закрытое (Claude его только прячет) —
    /// показать. `true` — шаг сделан, окно встанет через миг.
    var showMain: () -> Bool = { false }

}

/// Опрос рождения окна (WF98, #7841): пока ждём новое окно, раз в 0,1 с сверяем номера окон
/// на экране (дёшево — один `CGWindowList`) и только на СВЕЖИЙ номер смотрим полным списком
/// с AX. Номер без AX-пары (служебное окно) смотрим не дольше `graceSeconds` — дальше опрос
/// его не замечает, и полный список на каждом шаге не гоняется.
struct BirthWatch {
    static let pollSeconds: TimeInterval = 0.1
    static let graceSeconds: TimeInterval = 1

    private let seen: Set<CGWindowID>
    private var firstSeen: [CGWindowID: Date] = [:]

    init(seen: Set<CGWindowID>) {
        self.seen = seen
    }

    /// Есть ли номер, которого не было на старте и который появился не раньше `graceSeconds`.
    mutating func worthLooking(_ ids: Set<CGWindowID>, at: Date) -> Bool {
        var fresh = false
        for id in ids where !seen.contains(id) {
            let since = firstSeen[id] ?? at
            firstSeen[id] = since
            if at.timeIntervalSince(since) < BirthWatch.graceSeconds { fresh = true }
        }
        return fresh
    }
}

/// Канал «Пимп» (план WF36, задача #5531): окна Claude из любого чата — файлами, без клавиатуры.
///
/// Каталог `~/Library/Application Support/MyClaude/pimp/` рядом с `command.json`. Запрос —
/// файл `<id>.json`, взятие в работу — пустой `<id>.taken`, ответ — `<id>.result.json`.
/// Правда об исполнении лежит на диске, а не в памяти процесса: перезапуск приложения на
/// гейте ничего не теряет и ничего не повторяет — у сделанного запроса уже есть ответ.
///
/// Тикает на общем таймере 2 с (`ClaudeAXController`), своего не заводит. Исполняет по одному:
/// пока идёт «новое окно» (до 65 с — страница ждёт `/epitaxy`, шлёт первое сообщение и выносит
/// чат в окно), остальным сразу `busy`. Запрос старше 30 с не исполняется вовсе (`stale`):
/// Элвис уже не ждёт, а окно бы открылось.
///
/// Каталог пишет кто угодно на этой машине, поэтому права 0600/0700, а в ответ не кладётся
/// ничего сверх нужного (риск 4 плана).
final class PimpChannel {
    /// Каталог канала внутри Application Support/MyClaude.
    static let directoryName = "pimp"
    static let requestSuffix = ".json"
    static let resultSuffix = ".result.json"
    static let takenSuffix = ".taken"
    /// Огрызок незавершённой записи — свой и CLI-шный (`.<id>.tmp`): убираем вместе с
    /// остальными старыми файлами канала (#5558).
    static let tmpSuffix = ".tmp"
    /// Запрос старше — не исполняем (`stale`).
    static let freshSeconds: TimeInterval = 30
    /// Сколько `arrange --order` ждёт круг опознания чатов (WF105): столько же, сколько
    /// «💾 Сохранить раскладку» (`ClaudeAXController.chatsWaitSeconds`).
    static let chatsWaitSeconds: TimeInterval = 8
    /// Сколько ждём НОВОЕ окно Claude. С WF102 (C2) 65 с, было 40: цепочка страницы может
    /// ждать диалог доверия до 20 с, и канал отвечал `window-missing`, пока чат ещё создавался.
    static let newWindowSeconds: TimeInterval = 65
    /// `renew-window` (WF102): сколько после рождения окна ждём id его чата (и модель из файла
    /// сессии). Не опознали — `chat-unknown`, старое окно остаётся.
    static let renewChatSeconds: TimeInterval = 10
    /// Потолок первого сообщения `renew-window` (контракт WF102): длиннее — `bad-request`.
    static let renewTextLimit = 20_000
    /// Потолок подписи модели (страница режет до 80 — длиннее такой модели нет).
    static let renewModelLimit = 80
    /// Ступени эффорта `renew-window` — слова ползунка Claude (страница сравнивает без регистра).
    static let renewEfforts: Set<String> = ["low", "medium", "high", "extra", "max"]
    /// Сколько ждём окно чата, вынесенного «Вернуть эти чаты» (план WF41): страница зовёт
    /// `openPopout` сразу, а запасной путь через строку сайдбара — секунды. Новые чаты
    /// (`fresh`) ждут своё прежнее время: там создаётся сессия и уходит первое сообщение.
    static let restoreWindowSeconds: TimeInterval = 15
    /// Open and inspect the same descriptor. FIFOs, links and oversized/growing requests
    /// never block the main queue or reach command parsing.
    static func readRequest(_ url: URL) -> Data? {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= 65_536 else { return nil }
        let expectedSize = info.st_size
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count <= 65_536 {
            let remaining = min(buffer.count, 65_537 - data.count)
            let count = Darwin.read(fd, &buffer, remaining)
            if count < 0 { if errno == EINTR { continue }; return nil }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= 65_536, fstat(fd, &info) == 0,
              info.st_size == expectedSize, data.count == Int(expectedSize) else { return nil }
        return data
    }

    /// Файлы канала старше часа убираем.
    static let keepSeconds: TimeInterval = 3600
    /// Не чаще раза в минуту.
    static let cleanupInterval: TimeInterval = 60
    /// Расставляем на том экране, где стоят окна Claude (`Screens.usableFrame(holding:)`),
    /// — так и говорим в ответе. До 08.09 тут стояло «main», и это была неправда (#5732).
    static let screen = "windows"
    /// Ниже этой высоты столбец пополам не делится (`too-small`). С WF94 — настоящий минимум
    /// высоты окна Claude (`ArrangeLayout.splitMinHeight`, 357): при 360 Odyssey 720 не делился.
    static let minSplitHeight: CGFloat = ArrangeLayout.splitMinHeight
    /// Права файлов канала: каталог общий, а в запросах лежат пути проектов.
    static let filePermissions: NSNumber = 0o600
    static let directoryPermissions: NSNumber = 0o700
    /// `send` (WF103): потолок текста и сколько ждём исход страницы.
    static let sendTextLimit = 8000
    static let sendWaitSeconds: TimeInterval = 20
    /// Действие команды окну для `send` (страница, раздел 15).
    static let sendTextAction = "send-text"
    /// Исходы страницы: `sent` — ответ `ok`, остальные — ошибки с полем `window`.
    /// `queued` (WF111, мост голоса Рика): в поле свой текст Элвиса — фраза в очереди окна, уйдёт, когда поле
    /// опустеет; для канала это успех с полем `queued: true`.
    static let sendStates: Set<String> = ["sent", "queued", "field-busy", "no-field", "no-send"]
    /// Сколько файлов разом берёт `paste` (контракт WF75): больше — `bad-request`.
    static let pasteLimit = 20
    /// Потолок текста плашки `hud`: длиннее — обрезаем, пусто — `bad-request`.
    static let hudTextLimit = 200
    /// Единственное значение ключа `chat` у «нового окна» (контракт WF75).
    static let lastChatKey = "last"
    /// Опрос пустого окна встал (таймер не пришёл) — тик снимает работу через столько сверх срока.
    static let blankStallSeconds: TimeInterval = 3
    /// `restart-claude` (WF108): Claude снова запущен, а возврат окон по снимку К5 не кончился за
    /// столько — `restore-timeout`. Снимок сдаётся сам через 120 с (`WindowSnapshotKeeper.giveUpSeconds`).
    static let restartRestoreSeconds: TimeInterval = WindowSnapshotKeeper.giveUpSeconds + 10
    /// `restart-claude` (гейт 2 WF108): транскрипт Claude Code, менявшийся за столько, — чат работает
    /// (или только что кончил), даже если окна у него нет.
    static let transcriptFreshSeconds: TimeInterval = 90

    /// Ошибки контракта (их же знает `tools/pimp.py`).
    enum Failure: String {
        case stale, busy
        case noWindows = "no-windows"
        case badRequest = "bad-request"
        case projectMissing = "project-missing"
        case windowMissing = "window-missing"
        case tooSmall = "too-small"
        /// План WF41: чат окна приложению неизвестен — раскладку не пишем вовсе.
        case chatUnknown = "chat-unknown"
        /// План WF41: раскладки с таким именем нет.
        case layoutMissing = "layout-missing"
        /// WF43 (#5728): окна стоят не по сетке — ни одно место не получило номера ячейки,
        /// и записывать нечего: такая раскладка вернула бы ноль окон.
        case notArranged = "not-arranged"
        /// План WF75: последнего чата у папки нет вовсе (Claude переустановлен, проект новый).
        case chatMissing = "chat-missing"
        /// План WF75: окон-кандидатов два и больше — не гадаем, какое закрыть или куда
        /// вставить, и не трогаем ни одного.
        case ambiguous
        /// План WF75: закрыть просят главное окно Claude — его не закрываем никогда.
        case mainWindow = "main-window"
        /// План WF88 (К10-N): пункта «New Session in New Window» нет, он выключен или главного
        /// окна нет — пустое окно открыть нечем.
        case noDraftItem = "no-draft-item"
        /// WF94 (K-N): свежая цепочка «Нового окна» кончилась отказом страницы — чата нет,
        /// окна не будет. Поле `state` ответа — исход страницы (`draft`, `no-folder`, …).
        case chatNotCreated = "chat-not-created"
        /// WF94 (#7740): для этого набора мониторов окна ещё не запоминали.
        case screensUnknown = "screens-unknown"
        /// WF103 (`send`): страница не сказала исход за 20 с — текст мог уйти.
        case noAnswer = "no-answer"
        /// WF108 (`restart-claude`): в чате идёт ответ (поле `chats`) — без `force` не перезапускаем.
        case working
        /// WF108: о работе страниц ничего не известно моложе 180 с — не знаем, оборвём ли чей-то ответ.
        case workingUnknown = "working-unknown"
        /// WF108: Claude не закрылся или не открылся — поле `reason`.
        case restartFailed = "restart-failed"
        /// WF108: Claude снова запущен, а возврат окон не кончился за `restartRestoreSeconds`.
        case restoreTimeout = "restore-timeout"
    }

    /// Перезапуск Claude (WF108, #8176): спросили страницы, кто работает → Claude закрыт и
    /// открыт путём «Обновить Claude» → ждём, пока снимок К5 вернёт окна очередью канала.
    private struct RestartJob {
        enum Stage: Equatable {
            /// Ждём свежий круг страниц (до `chatsWaitSeconds`).
            case asking
            /// Claude закрывается и открывается (сиденье `restartClaude`).
            case relaunching
            /// Claude снова запущен — ждём, начнёт ли снимок возврат.
            case waiting
            /// Возврат окон идёт очередью канала (`RestoreJob.forRestart`).
            case restoring
        }

        let id: String
        /// Чат, который позвал: он сам «идёт», пока ждёт ответа инструмента, — из проверки вон.
        let from: String
        var stage: Stage
        /// С какой минуты идёт стадия.
        var since: Date
    }

    /// Идущее «новое окно»: канал занят, пока не появится окно или не выйдут 40 с.
    private struct Job {
        /// id запроса; nil — «↩︎» из меню (план WF88): файла ответа нет, отказ — плашкой.
        let id: String?
        let place: PimpPlace
        /// Окно `from`: номер Quartz (стабилен, пока окно живо) и заголовок на случай,
        /// если номер пропал (гейт WF36: главное окно носит заглушку «Claude», а заголовок
        /// его чата из индекса с ней не совпадает — искать надо по чату, потом по заголовку).
        let fromId: CGWindowID?
        let fromTitle: String?
        var fromResolved: Bool
        /// Окна Claude ДО запроса: новое — то, номера которого здесь нет.
        let before: Set<CGWindowID>
        let startedAt: Date
        /// Чат, чьё окно ждём (`chat:"last"`, план WF75); nil — обычное «новое окно», и
        /// подойдёт любое родившееся окно.
        var chat: String?
        /// Открывали ли мы окно под этот чат — поле `opened` ответа. В ответе оно есть
        /// ТОЛЬКО когда в запросе был `chat`.
        var opened = false
        /// Имя для плашки отказа у работы из меню (название чата «↩︎» или проекта «🪟 Новое окно ▸»).
        var name = ""
        /// Место, посчитанное до команды (WF98, #7841); nil — ставим по-старому при рождении.
        var plan: Plan?
        /// Опрос рождения окна 0,1 с; nil — сиденья `windowIDs` нет.
        var watch: BirthWatch?
        /// `renew-window` (WF102): окно, которое меняем, и что с новым; nil — обычное «новое окно».
        var renew: Renew? = nil
    }

    /// Замена окна (WF102, #7917, правка критика C1): новое окно встаёт в рамку донора, донор
    /// закрывается, только когда известен id нового чата.
    private struct Renew {
        let donor: PimpWindow
        /// Донор — главное окно (WF131, #9078; WF181, #9225): новый чат открывается в нём самом.
        var main = false
        /// Модель из запроса; nil — не просили, и поля `model` в ответе нет.
        let model: String?
        /// Новое окно родилось: его номер и когда.
        var born: CGWindowID?
        var bornAt: Date?
    }

    /// Место нового окна, посчитанное ДО команды (WF98, #7841, слово Элвиса: «сначала высчитать
    /// нужное место, а потом показывать»): его ячейка и соседи, которых уже раздвинули.
    struct Plan {
        let cell: CGRect
        /// Кого подвинули заранее: откуда и куда. По `from` они возвращаются, если окно
        /// не пришло.
        let moved: [(id: CGWindowID, from: CGRect, to: CGRect)]
        /// Столбец (`left/middle/right`) держит весь ряд: план годен, только пока на экране
        /// те же окна. «Под этим»/«над этим» держит одно окно `from`.
        let row: Bool
        /// ChatGPT, сдвинутый `makeRoom` (`ChatGPTWindows.reserve`): откуда и куда. nil — не двигали.
        var chatGPT: (from: CGRect, to: CGRect)? = nil
        var chrome: (window: ChatGPTWindow, to: CGRect)? = nil
    }

    /// Номер-призрак будущего окна в `makeRoom`: с номерами Quartz и жетонами пустого окна
    /// (`0xF000_0000…`) не встречается.
    static let phantomID: CGWindowID = 0xFFFF_FFFE

    /// Пустое окно проекта (план WF88, К17, правка критика V-N п. 2): своя работа, не `Job` —
    /// общий тик её не двигает (его `accepts(chat: nil)` взял бы любое новое окно), ведёт её
    /// только опрос 0,25 с. Ждём от НАЖАТИЯ пункта.
    private struct BlankJob {
        /// id запроса; nil — пункт меню: файла ответа нет, отказ — плашкой.
        let id: String?
        let place: PimpPlace
        let fromId: CGWindowID?
        let fromTitle: String?
        var fromResolved: Bool
        /// Окна выбранного Claude по AX до нажатия.
        let before: Set<CGWindowID>
        let pressedAt: Date
        let folder: URL
    }

    /// Одно место раскладки в работе (план WF41): куда ставить окно и чьё оно.
    private struct RestoreStep {
        /// id чата или `main` — главное окно.
        let chat: String
        /// Папка проекта (для «✨ Новые чаты по этим проектам»).
        let folder: String
        let title: String
        /// Рамка ячейки; nil — ячейки у записи не было (окно стояло не по сетке), и вернуть
        /// его некуда.
        let frame: CGRect?
    }

    /// Идущая «Вернуть раскладку»: канал занят, окна открываются ПО ОДНОМУ, и после каждого
    /// метка `<id>.taken` переписывается — CLI считает ожидание от неё, а не от запроса.
    private struct RestoreJob {
        var incompleteSince: Date?
        var named = false
        var failed = false
        var expected: [SnapshotWindow] = []
        var originalIDs: Set<CGWindowID> = []
        var explicitMoves: [PimpMove] = []
        var allPlacesKnown = true
        /// id запроса канала; nil — пункт меню, и отвечать некому.
        let id: String?
        let name: String
        let fresh: Bool
        /// Места, до которых ещё не дошли.
        var queue: [RestoreStep]
        /// Место, чьё окно сейчас ждём, снимок окон до него и время начала ожидания.
        var waiting: RestoreStep?
        var before: Set<CGWindowID> = []
        var since: Date = .distantPast
        var placed = 0
        var opened = 0
        var missing: [String] = []
        /// Возврат снимка К5 после `restart-claude` (WF108): его итог — ответ на тот запрос.
        var forRestart = false
        /// Спрятанные окна только что развернули (гейт 1 WF111): до этой минуты окна не трогаем.
        var unhideUntil: Date?
    }

    /// Идущая `send` (WF103): команда окну ушла, ждём исход страницы по слепку чатов.
    private struct SendJob {
        let id: String
        let window: String
        let fromResolved: Bool
        let startedAt: Date
    }

    /// «Чат в главное окно» (WF108, #8148): окно цели закрыто (или его не было) → команда `main-chat`
    /// главной странице → её исход кругом `cash` (`status().newWindow`) → вынесенное окно прежнего чата.
    private struct MainJob {
        /// id запроса; nil — из настройки `mainChat`, отвечать некому.
        let id: String?
        let chat: String
        let main: PimpWindow
        let target: PimpWindow?
        let since: Date
        /// Окна до команды странице: вынесенное окно — то, которого среди них нет.
        var before: Set<CGWindowID>
        /// Когда ушла команда странице; nil — ждём, пока закроется окно цели.
        var sent: Date?
        /// Страница сказала `ok`: какой чат вынесла ("" — никакой). nil — исхода ещё нет.
        var popped: String?
        var rollbackFailure: Failure?
        var rollbackSince: Date?
        var rollbackOpenedAt: Date?
        var rollbackFields: [(key: String, value: CommandValue)] = []
    }

    /// Запрос, взятый с диска: имя файла, тело и время для очереди.
    private struct Incoming {
        let url: URL
        let id: String
        let data: Data?
        /// `at` запроса; не разобрали — время файла (для порядка исполнения).
        let at: Date
    }

    let directory: URL
    private let now: () -> Date
    private let fileManager: FileManager
    var seats = PimpSeats()

    private var job: Job?
    /// Идущая «Вернуть раскладку» (план WF41): вторая работа канала, такая же одиночная.
    private var restore: RestoreJob?
    /// Пустое окно (план WF88): третья работа канала, одна на канал вместе с первыми двумя.
    private var blank: BlankJob?
    /// `send` (WF103): четвёртая работа канала, одна на канал вместе с прочими.
    private var sending: SendJob?
    /// `arrange --order` ждёт круг опознания чатов (WF105, #8071): запрос, id и когда спросили.
    private var chatsWait: (request: PimpRequest, id: String, since: Date)?
    /// `restart-claude` (WF108): пятая работа канала; возврат снимка К5 она пускает (`startRestore`).
    private var restart: RestartJob?
    /// «Чат в главное окно» (WF108, #8148): шестая работа канала.
    private var mainJob: MainJob?
    /// Главный чат из настройки `mainChat` пора вернуть в главное окно — на следующем свободном тике
    /// (после «главного по центру» и возврата окон `restart-claude`: рамки к тому тику уже встали).
    private var mainChatDue = false
    private var cleanedAt: Date?
    private(set) var served = 0
    private(set) var failed = 0

    /// Канал занят: работа всегда одна — «новое окно», возврат раскладки или пустое окно.
    /// Открыт с WF94: окна при смене мониторов не возвращаются, пока канал занят (#7740).
    var isBusy: Bool { busyBesidesRestart || restart != nil }

    private var busyBesidesRestart: Bool {
        job != nil || restore != nil || blank != nil || sending != nil || chatsWait != nil || mainJob != nil
    }

    /// Ждём ответ страницы кругом `cash` probe: ход «Нового окна» или исход `send` (WF103).
    var isWaitingPage: Bool { job != nil || sending != nil || mainJob != nil }

    /// Ловим черновик «Code» (замок в обе стороны, проверка S): цепочки «Нового окна» мимо
    /// канала ждут конца этой работы (`ClaudeActions.whenBlankIdle`).
    var isBlankBusy: Bool { blank != nil }

    /// Запрос, который сейчас исполняется; nil — канал свободен или работу начали из меню.
    private var busyID: String? {
        // Первым: возврат окон после перезапуска идёт без своего id — работа всё та же.
        if let restart = restart { return restart.id }
        if let job = job { return job.id }
        if let restore = restore { return restore.id }
        if let blank = blank { return blank.id }
        if let sending = sending { return sending.id }
        if let wait = chatsWait { return wait.id }
        if let main = mainJob { return main.id }
        return nil
    }

    init(directory: URL = CommandChannel.directory
            .appendingPathComponent(PimpChannel.directoryName, isDirectory: true),
         now: @escaping () -> Date = Date.init,
         fileManager: FileManager = .default) {
        self.directory = directory
        self.now = now
        self.fileManager = fileManager
    }

    /// Строка для `statusText`: сколько запросов исполнено и сколько из них отказом.
    var status: String { "\(served)/\(failed)" }

    /// Каталог заводится на старте: по нему CLI видит, что Пимп вообще есть.
    func start() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                         attributes: [.posixPermissions:
                                                        PimpChannel.directoryPermissions])
        answerOrphans()
    }

    /// Сироты прошлого запуска: `<id>.taken` есть, ответа нет — запрос исполняли, когда
    /// приложение перезапустили. Повторять его нельзя (правда об исполнении лежит на диске),
    /// но и молчать незачем: CLI иначе честно ждёт свою минуту (#5556). Отвечаем `stale`.
    private func answerOrphans() {
        let at = now()
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(PimpChannel.takenSuffix) {
            let id = String(name.dropLast(PimpChannel.takenSuffix.count))
            guard !id.isEmpty, !fileManager.fileExists(atPath: result(for: id).path),
                  fileManager.fileExists(atPath: directory
                    .appendingPathComponent(id + PimpChannel.requestSuffix).path) else { continue }
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.stale.rawValue), for: id)
        }
    }

    // MARK: - тик

    /// Общий тик 2 с. Сперва доводим до конца «новое окно», потом отвечаем всем остальным:
    /// пока оно идёт, каждому — `busy` (ждать в очереди нечего, Элвис уже говорит дальше).
    func tick() {
        let at = now()
        cleanup(at)
        if let current = job { advance(current, at: at) }
        // Возврат раскладки идёт своими шагами (план WF41): по окну за раз, пока очередь
        // не кончится. Канал при этом занят так же, как «новым окном».
        if let current = restore { advanceRestore(current, at: at) }
        if let current = sending { advanceSend(current, at: at) }
        if let current = restart { advanceRestart(current, at: at) }
        if let current = mainJob { advanceMain(current, at: at) }
        if mainChatDue, !isBusy {
            mainChatDue = false
            keepMainChat(at: at)
        }
        // Круг опознания чатов пришёл или ждать хватит — расставляем с тем, что знаем.
        if let wait = chatsWait, seats.chatsAnswered(wait.since)
            || at.timeIntervalSince(wait.since) >= PimpChannel.chatsWaitSeconds {
            chatsWait = nil
            if wait.request.action == .send { runSend(wait.request, id: wait.id, at: at, retried: true) }
            else { runArrange(wait.request, id: wait.id, at: at, retried: true) }
        }
        // Пустое окно тик не двигает (правка критика V-N п. 2) — только снимает зависшую работу,
        // если опрос почему-то встал: иначе канал был бы занят навсегда.
        if let current = blank, at.timeIntervalSince(current.pressedAt)
            > BlankWindow.draftWaitSeconds + BlankWindow.untitledGraceSeconds + PimpChannel.blankStallSeconds {
            blank = nil
            refuse(current.id, at: at, .windowMissing, fromResolved: current.fromResolved,
                   notice: MenuModel.blankNoWindowNotice)
        }
        for incoming in pending() {
            if busyID == incoming.id { continue }
            answer(incoming, at: at)
        }
    }

    /// Запросы без ответа, по `at` по возрастанию. Скрытые файлы (у CLI это временный
    /// `.<id>.tmp`) и сами ответы мимо.
    private func pending() -> [Incoming] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        var out: [Incoming] = []
        for name in names where !name.hasPrefix(".")
            && name.hasSuffix(PimpChannel.requestSuffix)
            && !name.hasSuffix(PimpChannel.resultSuffix) {
            let id = String(name.dropLast(PimpChannel.requestSuffix.count))
            guard !id.isEmpty, !fileManager.fileExists(atPath: result(for: id).path) else { continue }
            // Метка «взял в работу» без ответа значит, что запрос уже исполняли, а приложение
            // перезапустили посреди работы: правда на диске, и повторять окно нельзя. CLI
            // сам скажет, что Пимп взял запрос и не ответил.
            guard busyID == id || !fileManager.fileExists(atPath: taken(for: id).path) else {
                continue
            }
            let url = directory.appendingPathComponent(name)
            let data = Self.readRequest(url)
            let at = PimpRequest.parse(data)?.at
                ?? ProjectIndex.fileInfo(of: url)?.modified
                ?? Date.distantPast
            out.append(Incoming(url: url, id: id, data: data, at: at))
        }
        return out.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
    }

    /// Файлы канала старше часа — прибрать (проверяем не чаще раза в минуту). Огрызки
    /// `.tmp` (наши и CLI-шные) убираются вместе с ними: без этого они копятся вечно (#5558).
    private func cleanup(_ at: Date) {
        if let last = cleanedAt, at.timeIntervalSince(last) < PimpChannel.cleanupInterval { return }
        cleanedAt = at
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(PimpChannel.requestSuffix)
            || name.hasSuffix(PimpChannel.takenSuffix)
            || name.hasSuffix(PimpChannel.tmpSuffix) {
            let url = directory.appendingPathComponent(name)
            guard let info = ProjectIndex.fileInfo(of: url),
                  at.timeIntervalSince(info.modified) > PimpChannel.keepSeconds else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - исполнение

    private func answer(_ incoming: Incoming, at: Date) {
        guard let request = PimpRequest.parse(incoming.data) else {
            reply(PimpAnswer(id: incoming.id, at: at, ok: false,
                             error: Failure.badRequest.rawValue), for: incoming.id)
            return
        }
        // Запрос успел протухнуть — окно бы открылось, когда его уже не ждут.
        guard at.timeIntervalSince(request.at) <= PimpChannel.freshSeconds else {
            reply(PimpAnswer(id: incoming.id, at: at, ok: false, error: Failure.stale.rawValue),
                  for: incoming.id)
            return
        }
        // Плашка — единственное действие, которое отвечает ДО проверки занятости (контракт
        // WF75): окон она не трогает, а сказать «сделал 2 из 3» нужно ровно тогда, когда
        // канал занят долгой работой. `stale` и `bad-request` её касаются как всех.
        if request.action == .hud {
            take(incoming.id)
            runHud(request, id: incoming.id, at: at)
            return
        }
        // Притемнение и ракета (WF113/WF114) окон не двигают — занятость канала им не помеха.
        if request.action == .dim || request.action == .look {
            take(incoming.id)
            runPageLook(request, id: incoming.id, at: at)
            return
        }
        guard !isBusy else {
            reply(PimpAnswer(id: incoming.id, at: at, ok: false, error: Failure.busy.rawValue),
                  for: incoming.id)
            return
        }
        // Метка «взял в работу»: по ней CLI отличает молчащего Пимпа от долгой работы.
        take(incoming.id)
        switch request.action {
        case .projects: runProjects(request, id: incoming.id, at: at)
        case .windows: runWindows(id: incoming.id, at: at)
        case .arrange: runArrange(request, id: incoming.id, at: at)
        case .newWindow: runNewWindow(request, id: incoming.id, at: at)
        case .layouts: runLayouts(id: incoming.id, at: at)
        case .layoutSave: runLayoutSave(request, id: incoming.id, at: at)
        case .layoutRestore: runLayoutRestore(request, id: incoming.id, at: at)
        case .closeWindow: runCloseWindow(request, id: incoming.id, at: at)
        case .paste: runPaste(request, id: incoming.id, at: at)
        case .screensRestore: runScreensRestore(id: incoming.id, at: at)
        case .renewWindow: runRenew(request, id: incoming.id, at: at)
        case .send: runSend(request, id: incoming.id, at: at)
        case .restartClaude: runRestart(request, id: incoming.id, at: at)
        case .main: runMain(request, id: incoming.id, at: at)
        case .hide: runHide(show: false, id: incoming.id, at: at)
        case .show: runHide(show: true, id: incoming.id, at: at)
        // Плашка, притемнение и ракета ушли веткой выше — сюда попасть не могут.
        case .hud, .dim, .look: break
        }
    }

    /// Список проектов Claude знать не обязан — он лежит в нашем файле. Просили сводку
    /// (`status`, план WF41) — к каждому проекту добавляются открытые окна и строка из его
    /// `status.md`; не просили — ответ прежний, побайтно (`projects.result.json`).
    private func runProjects(_ request: PimpRequest, id: String, at: Date) {
        let list = seats.projects()
        let windows = request.status ? seats.windows() : []
        reply(PimpAnswer(id: id, at: at, ok: true, fields: [
            (key: "projects", value: .array(list.map { project in
                guard request.status else { return PimpChannel.projectValue(project) }
                return PimpChannel.projectValue(
                    project, chats: PimpChannel.chats(of: project, in: windows),
                    state: PimpChannel.state(of: project.folder, fileManager: fileManager))
            })),
        ]), for: id)
    }

    /// Окна: заголовок, чат, папка, рамка. Все окна свёрнуты — это не «no-windows», а
    /// честный пустой список плюс счётчик свёрнутых (CLI так и говорит). Окно ChatGPT
    /// (WF94) — последней записью с `app:"chatgpt"`; нет его — ответ побайтно прежний.
    private func runWindows(id: String, at: Date) {
        guard seats.claudeRunning() else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let windows = seats.windows()
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.windowsFields(
            windows, minimized: seats.minimized(), chatGPT: seats.chatGPT())), for: id)
    }

    /// «Спрячь окна» / «покажи окна» (WF112, #8255): сворачивает и разворачивает приложение —
    /// канал только говорит итог (эталоны `hide*.json`, `show*.json`).
    private func runHide(show: Bool, id: String, at: Date) {
        let done = show ? seats.showWindows() : seats.hideWindows()
        if let failure = done.failure {
            reply(PimpAnswer(id: id, at: at, ok: false, error: failure.rawValue), for: id)
            return
        }
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.hideFields(done, show: show)),
              for: id)
    }

    /// «Притемни окна» / «поставь ракету 1.3» (WF113/WF114): выбор пишет приложение, канал говорит итог
    /// (эталоны `dim*.json`, `look*.json`).
    private func runPageLook(_ request: PimpRequest, id: String, at: Date) {
        if request.action == .dim {
            let look = seats.setDim(request.on, request.level)
            reply(PimpAnswer(id: id, at: at, ok: true, fields: [
                (key: "on", value: .bool(look.dimOn)),
                (key: "level", value: .decimal(Double(look.dimPercent) / 100)),
            ]), for: id)
            return
        }
        let done = seats.setLook(request.style.isEmpty ? nil : request.style, request.size, request.grow, request.show)
        reply(PimpAnswer(id: id, at: at, ok: true, fields: [
            (key: "style", value: .string(done.look.style)),
            (key: "name", value: .string(SendLook.name(done.look.style))),
            (key: "size", value: .number(done.look.size)),
            (key: "shown", value: .bool(done.shown)),
        ]), for: id)
    }

    /// «Верни окна как были» на этом наборе мониторов (#7740): только живые окна — закрытые
    /// чаты не открываем. Для набора, которого не видели, — `screens-unknown`.
    private func runScreensRestore(id: String, at: Date) {
        guard let done = seats.restoreScreens() else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.screensUnknown.rawValue),
                  for: id)
            return
        }
        reply(PimpAnswer(id: id, at: at, ok: true, fields: [
            (key: "placed", value: .number(max(0, done.placed))),
            (key: "missing", value: .number(max(0, done.missing))),
        ]), for: id)
    }

    /// «Расставить». Голая просьба (`layout: "last"` или поля нет) идёт УМНЫМ путём
    /// (план WF77): плитка не читается и не пишется, `fitsLayout` и `too-small` не
    /// зовутся вовсе (критик блокеры 2 и 3) — сетку выбирает то, как окна стоят сейчас.
    /// Названная плитка (`4|5|5x2|row`) работает по-прежнему: порядок по текущим рамкам,
    /// ячейка уже `minWindowWidth` — `too-small`, такие окна Electron всё равно не сделает.
    private func runArrange(_ request: PimpRequest, id: String, at: Date, retried: Bool = false) {
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        // Названное окно не нашлось, а у кого-то чат не опознан (карта probe пуста или занята,
        // #8071: «не нашёл окна: VkusnoffKz», хотя `windows` его видел) — один раз спросить
        // страницы о чатах и ответить после круга (`tick`).
        // Записи «A+B» (WF107) — по частям: целиком такая запись не подходит ни одному окну.
        if !retried, let demand = seats.demandChats, let entries = request.order,
           windows.contains(where: { $0.folder.isEmpty }),
           !PimpChannel.order(of: windows, by: PimpChannel.flatOrder(entries),
                              base: Array(windows.indices)).missing.isEmpty {
            demand(at)
            chatsWait = (request: request, id: id, since: at)
            return
        }
        if request.layout == .center {
            runArrangeCenter(request, windows: windows, id: id, at: at)
            return
        }
        let base = ArrangeLayout.order(of: windows.map { $0.frame })
        // Порядок по проектам (план WF41): просили — окна названных папок идут первыми,
        // не просили — прежний порядок по рамкам и ответ без `unknown`/`missing`. Стопок эти
        // раскладки не знают (WF107): «A+B» — как если бы A и B назвали подряд.
        let sorted = request.order.map { PimpChannel.order(of: windows, by: PimpChannel.flatOrder($0), base: base) }
        let ids = (sorted?.order ?? base).map { windows[$0].id }
        guard let mode = request.layout else {
            // Порядок назвали сами (`order`) — он и навязан; иначе окна занимают ячейки
            // сами, а стоящие на месте не двигаются вовсе.
            let placed = seats.arrangeSmart(ids, sorted != nil, nil)
            guard !placed.isEmpty else {
                reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue),
                      for: id)
                return
            }
            seats.explicitLayout(placed.map { PimpMove(id: $0.id, frame: $0.frame) })
            // Поле `layout` у умного пути — `row` (решение 8 плана): эталоны канала и слова
            // CLI не меняются, а про умную расстановку CLI говорит своими словами.
            reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.arrangeFields(
                placed, mode: .ribbon, skipped: 0, unknown: sorted?.unknown,
                missing: sorted?.missing, minimized: seats.minimized())), for: id)
            return
        }
        guard seats.fitsLayout(mode) else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.tooSmall.rawValue), for: id)
            return
        }
        let placed = seats.arrange(ids, mode, nil)
        // Не переставили ни одного окна (окна закрылись между снимком и расстановкой, экрана
        // не нашлось): подставлять сюда ВСЕ окна и говорить «Расставил N окон» — неправда,
        // их никто не двигал (#5680).
        guard !placed.windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        seats.explicitLayout(placed.windows.map { PimpMove(id: $0.id, frame: $0.frame) })
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.arrangeFields(
            placed.windows, mode: mode,
            skipped: placed.skipped, unknown: sorted?.unknown, missing: sorted?.missing,
            minimized: seats.minimized())), for: id)
    }

    /// Сколько после возврата главного окна отвечаем `busy`, ожидая его на экране (CLI повторяет раз в 2 с).
    static let mainWaitSeconds: TimeInterval = 6
    /// Новая попытка вернуть главное окно — не раньше: не вернулось — идём прежним путём, а не крутим `busy`.
    static let mainRetrySeconds: TimeInterval = 60
    private var mainShownAt: Date?

    /// Главного окна на экране нет (свёрнуто или закрыто), а выносит чаты только оно: вернуть его и
    /// ответить `busy` — CLI повторит через 2 с, и запрос пойдёт обычным путём. Окно не пришло за
    /// `mainWaitSeconds` — `false`, прежний отказ («нечем выносить» или «окон нет»).
    private func waitingForMain(_ windows: [PimpWindow], id: String, at: Date) -> Bool {
        guard !windows.contains(where: { $0.isMain(using: seats.isMainWindow) }) else {
            mainShownAt = nil
            return false
        }
        if let shown = mainShownAt, at.timeIntervalSince(shown) < PimpChannel.mainRetrySeconds {
            guard at.timeIntervalSince(shown) < PimpChannel.mainWaitSeconds else { return false }
        } else {
            guard seats.showMain() else { return false }
            mainShownAt = at
        }
        reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.busy.rawValue), for: id)
        return true
    }

    /// «Новое окно в проекте»: находим папку, зовём тот же путь, что пункт меню, и ждём
    /// НОВОЕ окно (не по имени: переименование чата может не удаться, риск 1 плана).
    private func runNewWindow(_ request: PimpRequest, id: String, at: Date) {
        let windows = seats.windows()
        if seats.claudeRunning(), waitingForMain(windows, id: id, at: at) { return }
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let known = seats.projects()
        guard let project = PimpChannel.project(named: request.project, in: known,
                                                fileManager: fileManager) else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.projectMissing.rawValue,
                             fields: [(key: "projects",
                                       value: .array(known.map { .string($0.name) }))]), for: id)
            return
        }
        // Окно `from` ищем СРАЗУ: не нашли — «под этим» честно вырождается в «справа»
        // (у субагента переменной чата нет вовсе, п. 1 «Что выяснено»).
        let fromTitle = request.from.isEmpty ? nil : seats.titleForChat(request.from)
        let fromWindow = PimpChannel.window(chat: request.from, title: fromTitle, in: windows)
        let resolved = fromWindow != nil
        var place = request.place
        if !resolved, place == .below || place == .above { place = .right }
        // «Последний чат проекта» вместо нового (контракт WF75): чата нет, есть или его
        // выносят отдельным окном — всё это отдельный путь, нового чата там не заводится.
        // Чужая цепочка ещё идёт (z4-r01): её окно канал принял бы за своё — отвечаем `busy`,
        // `say` и агент повторят сами.
        guard !seats.newWindowStarting() else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.busy.rawValue), for: id)
            return
        }
        if !request.chat.isEmpty {
            runLastChat(project: project, place: place, from: fromWindow, fromTitle: fromTitle,
                        resolved: resolved, windows: windows, id: id, at: at)
            return
        }
        var origin: (x: Int, y: Int)?
        if case .point(let x, let y) = place { origin = (x: x, y: y) }
        let plan = makePlan(place, from: fromWindow, windows: windows)
        if let cell = plan?.cell { origin = PimpChannel.corner(cell) }
        begin(Job(id: id, place: place, fromId: fromWindow?.id, fromTitle: fromTitle,
                  fromResolved: resolved, before: Set(windows.map { $0.id }), startedAt: at, plan: plan))
        seats.openNewWindow(project, origin)
    }

    /// Угол ячейки точкой для `initialPosition` страницы.
    static func corner(_ frame: CGRect) -> (x: Int, y: Int) {
        (Int(frame.minX.rounded()), Int(frame.minY.rounded()))
    }

    /// Ячейка нового окна ДО команды (WF98, #7841): окно родится сразу в её углу, а соседи
    /// уже раздвинуты — при рождении остаётся поставить ему размер. Столбец считает тот же
    /// `arrangeSmart`, что при рождении (`row`), только новое окно в нём — призрак; «под
    /// этим»/«над этим» — та же половина `split`. Точка (`x,y`) плана не имеет: её ставит страница.
    private func makePlan(_ place: PimpPlace, from: PimpWindow?, windows: [PimpWindow]) -> Plan? {
        // Идёт возврат снимка окон — соседей не раздвигаем, окно встанет при рождении (#7841).
        guard seats.placeNew != nil, !seats.isRestoring() else { return nil }
        switch place {
        case .point:
            return nil
        case .left, .middle, .right:
            let order = ArrangeLayout.order(of: windows.map { $0.frame })
            let index = ArrangeLayout.insertIndex(of: place, count: windows.count)
            let full = ArrangeLayout.insert(order: order, count: windows.count, at: index)
            let ids = full.map { $0 == windows.count ? PimpChannel.phantomID : windows[$0].id }
            let gptBefore = seats.chatGPT()?.frame
            let chromeBefore = seats.chrome()
            let placed = seats.makeRoom(ids)
            guard let cell = placed.first(where: { $0.id == PimpChannel.phantomID })?.frame else { return nil }
            let moved = windows.compactMap { window -> (id: CGWindowID, from: CGRect, to: CGRect)? in
                guard let to = placed.first(where: { $0.id == window.id })?.frame,
                      !ClaudeActions.frameMatches(to, window.frame) else { return nil }
                return (id: window.id, from: window.frame, to: to)
            }
            // ChatGPT `makeRoom` мог сузить (правая полоса экрана) — запомним, чтобы `undo` вернул.
            var gpt: (from: CGRect, to: CGRect)?
            if let before = gptBefore, let after = seats.chatGPT()?.frame,
               !ClaudeActions.frameMatches(before, after) { gpt = (from: before, to: after) }
            let chrome = chromeBefore.flatMap { before -> (window: ChatGPTWindow, to: CGRect)? in
                guard let after = seats.chromeFrame(before),
                      !ClaudeActions.frameMatches(before.frame, after) else { return nil }
                return (window: before, to: after)
            }
            return Plan(cell: cell, moved: moved, row: true, chatGPT: gpt, chrome: chrome)
        case .below, .above:
            guard let target = from,
                  let halves = PimpChannel.split(target.frame, above: place == .above, gap: seats.gap())
            else { return nil }
            seats.place([PimpMove(id: target.id, frame: halves.old)])
            return Plan(cell: halves.new, moved: [(id: target.id, from: target.frame, to: halves.old)],
                        row: false)
        }
    }

    /// План ещё годен в момент рождения окна: подвинутые стоят, где их поставили, а у столбца
    /// на экране те же окна, что были до команды (закрыли или открыли соседа — ряд уже другой).
    private static func planHolds(_ plan: Plan, before: Set<CGWindowID>, born: CGWindowID,
                                  windows: [PimpWindow]) -> Bool {
        if plan.row, Set(windows.map { $0.id }).subtracting([born]) != before { return false }
        return plan.moved.allSatisfy { move in
            windows.first { $0.id == move.id }.map { ClaudeActions.frameMatches($0.frame, move.to) } ?? false
        }
    }

    /// Окно не пришло: раздвинутых заранее вернуть, где стояли, — но только тех, кто так и стоит
    /// там, куда мы их поставили (подвинутого Элвисом не трогаем).
    private func undo(_ plan: Plan?) {
        guard let plan = plan else { return }
        if !plan.moved.isEmpty {
            let windows = seats.windows()
            let back = plan.moved.compactMap { move -> PimpMove? in
                guard let now = windows.first(where: { $0.id == move.id }),
                      ClaudeActions.frameMatches(now.frame, move.to) else { return nil }
                return PimpMove(id: move.id, frame: move.from)
            }
            if !back.isEmpty { seats.place(back) }
        }
        // ChatGPT — так же: только если стоит там, куда его сдвинул `makeRoom`.
        if let gpt = plan.chatGPT, let now = seats.chatGPT()?.frame,
           ClaudeActions.frameMatches(now, gpt.to) {
            seats.placeChatGPT(gpt.from)
        }
        if let chrome = plan.chrome, let now = seats.chromeFrame(chrome.window),
           ClaudeActions.frameMatches(now, chrome.to) {
            seats.placeChrome(chrome.window, chrome.to, chrome.window.frame)
        }
    }

    /// Через `recheckSeconds` после `placeNew` — один раз сверить рамку (#7841): свежее окно
    /// Electron иногда отыгрывает свою рамку после первой записи. Не там — ставим ещё раз,
    /// как `cashoutReplace`; окна уже нет — молчим.
    private func recheckPlaced(_ move: PimpMove) {
        seats.schedule(PimpChannel.recheckSeconds) { [weak self] in
            guard let self = self,
                  let now = self.seats.windows().first(where: { $0.id == move.id }),
                  !ClaudeActions.frameMatches(now.frame, move.frame) else { return }
            self.seats.placeNew?(move)
        }
    }

    /// Пауза перед сверкой рамки нового окна (`recheckPlaced`).
    static let recheckSeconds: TimeInterval = 0.7

    /// Завести работу «нового окна» и, если есть чем, опрос его рождения 0,1 с.
    private func begin(_ new: Job) {
        var started = new
        if let ids = seats.windowIDs { started.watch = BirthWatch(seen: ids()) }
        job = started
        if started.watch != nil { scheduleBirthPoll(started.startedAt) }
    }

    private func scheduleBirthPoll(_ startedAt: Date) {
        seats.schedule(BirthWatch.pollSeconds) { [weak self] in
            guard let self = self else { return }
            self.pollBirth(startedAt, at: self.now())
        }
    }

    /// Шаг опроса рождения (WF98, #7841): свежий номер на экране — сразу `advance`, не дожидаясь
    /// тика 2 с. Работа сменилась или кончилась — опрос молча гаснет; срок и отказы по-прежнему
    /// на тике. Открыт для тестов.
    func pollBirth(_ startedAt: Date, at: Date) {
        guard var current = job, current.startedAt == startedAt, var watch = current.watch,
              let ids = seats.windowIDs,
              at.timeIntervalSince(startedAt) < waitSeconds(current) else { return }
        // Идёт возврат снимка окон (#7841): его окна не наши, и двигает их он — опрос ждёт
        // конца возврата, номера не смотрит (свежий номер после возврата увидит как новый).
        if seats.isRestoring() {
            scheduleBirthPoll(startedAt)
            return
        }
        let look = watch.worthLooking(ids(), at: at)
        current.watch = watch
        job = current
        if look {
            seats.windowBorn()
            advance(current, at: at)
            guard job?.startedAt == startedAt else { return }
        }
        scheduleBirthPoll(startedAt)
    }

    /// «🪟 Новое окно ▸ проект» из меню жёлтой кнопки (проверка гейта WF94, #7749): тот же путь,
    /// что `new-window` канала без запроса, — окно ставится самым правым, а не остаётся Claude-
    /// размера рядом с источником. `false` — канал занят или окон нет: меню идёт прежним путём.
    @discardableResult
    func startNewWindow(project: Project) -> Bool {
        let at = now()
        let windows = seats.windows()
        guard !isBusy, !seats.newWindowBusy(), seats.claudeRunning(), !windows.isEmpty else { return false }
        let plan = makePlan(.right, from: nil, windows: windows)
        begin(Job(id: nil, place: .right, fromId: nil, fromTitle: nil, fromResolved: false,
                  before: Set(windows.map { $0.id }), startedAt: at, name: project.name, plan: plan))
        seats.openNewWindow(project, plan.map { PimpChannel.corner($0.cell) })
        return true
    }

    /// `new-window` + `chat:"last"` (контракт WF75): последний чат папки берёт ИНДЕКС чатов
    /// Claude, а не карта probe — она знает только те чаты, что уже открыты окнами (критик Б1).
    /// Чат на экране — окно поднимается и встаёт на место, `opened:false`; закрыт — выносится
    /// тем же путём, что «↩︎ Вернуть эти чаты» (`openChat` → `popout-window` главному окну),
    /// и ждём окно ИМЕННО ЭТОГО чата 15 с.
    /// `id` nil — «↩︎» из меню ⌘B (план WF88): ответа в файл нет, отказ — плашкой.
    @discardableResult
    private func runLastChat(project: Project, place: PimpPlace, from: PimpWindow?,
                             fromTitle: String?, resolved: Bool, windows: [PimpWindow],
                             id: String?, at: Date) -> Bool {
        guard let last = seats.lastChat(project.folder) else {
            refuse(id, at: at, .chatMissing, fromResolved: resolved,
                   notice: MenuModel.lastChatMissingNotice(project.name))
            return false
        }
        let name = last.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.name : last.title
        if let open = windows.first(where: { $0.chat == last.chat }) {
            seats.raise(open.id)
            finish(Job(id: id, place: place, fromId: from?.id, fromTitle: fromTitle,
                       fromResolved: resolved, before: [], startedAt: at, chat: last.chat, name: name),
                   window: open, windows: windows, at: at)
            return true
        }
        // Выносит чат отдельным окном только ГЛАВНОЕ окно Claude — без него открывать нечем.
        guard windows.contains(where: { $0.isMain(using: seats.isMainWindow) }) else {
            refuse(id, at: at, .windowMissing, fromResolved: resolved,
                   notice: MenuModel.lastChatNoWindowNotice(name))
            return false
        }
        begin(Job(id: id, place: place, fromId: from?.id, fromTitle: fromTitle,
                  fromResolved: resolved, before: Set(windows.map { $0.id }), startedAt: at,
                  chat: last.chat, opened: true, name: name))
        seats.openChat(last.chat, last.title,
                       PimpChannel.popoutOrigin(place, near: from?.frame ?? windows.first?.frame))
        return true
    }

    /// Тик, пока идёт «новое окно»: появилось — ставим на место и отвечаем, вышел срок —
    /// `window-missing` (чат при этом создан; так и говорит CLI).
    private func advance(_ current: Job, at: Date) {
        // Сердцебиение (WF102, C2): CLI ждёт от метки `<id>.taken`, а цепочка страницы с
        // диалогом доверия идёт дольше его минуты.
        beat(current.id)
        if let renew = current.renew {
            advanceRenew(current, renew: renew, at: at)
            return
        }
        let windows = seats.windows()
        // Назван чат (`chat:"last"`, WF75) — ждём окно ИМЕННО ЕГО: в эти секунды могло
        // родиться чужое окно (вынос соседнего чата, «Обкэшить», служебное окно), и оно
        // заняло бы чужое место, как в #5691.
        if let fresh = windows.first(where: { !current.before.contains($0.id)
            && PimpChannel.accepts(chat: current.chat, $0) }) {
            job = nil
            finish(current, window: fresh, windows: windows, at: at)
            return
        }
        // Страница сама сказала, что цепочка ЭТОГО запроса сорвалась (WF94, K-N): ждать 40 с
        // нечего, и «чат создал» было бы неправдой. Прошлый исход страница не стирает — ему
        // верим, только когда он записан позже начала работы.
        if let state = seats.newWindowRun()?.failure(since: current.startedAt) {
            job = nil
            undo(current.plan)
            refuseNotCreated(current, state: state, at: at)
            return
        }
        guard at.timeIntervalSince(current.startedAt) >= waitSeconds(current) else { return }
        job = nil
        undo(current.plan)
        refuse(current.id, at: at, .windowMissing, fromResolved: current.fromResolved,
               notice: current.chat == nil ? MenuModel.newChatNoWindowNotice(current.name)
                                           : MenuModel.lastChatNoWindowNotice(current.name))
    }

    /// Отказ `chat-not-created`: запросу — файлом с полем `state` последним (эталон
    /// `new-window-not-created.error.json`), работе из меню — плашкой.
    private func refuseNotCreated(_ current: Job, state: String, at: Date) {
        guard let id = current.id else {
            seats.notice(PimpChannel.notCreatedNotice(state: state, name: current.name))
            return
        }
        reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.chatNotCreated.rawValue,
                         fromResolved: current.fromResolved,
                         fields: [(key: "state", value: .string(state))]), for: id)
    }

    /// Исход цепочки страницы словами — зеркало `NOT_CREATED_WORDS` в `tools/pimp.py` (z4-r03).
    static let notCreatedWords: [String: String] = [
        "draft": "в поле главного окна черновик",
        "no-folder": "папка проекта не выбралась",
        "no-send": "сообщение не ушло",
        "no-home": "Claude не открыл новый чат",
        "no-store": "страница Claude не готова",
        "no-insert": "текст не вставился в поле",
        "error": "ошибка на странице",
    ]

    /// Плашка отказа страницы для работы из меню (WF94): те же слова, что у CLI. Сырой код —
    /// только у незнакомого исхода.
    static func notCreatedNotice(state: String, name: String) -> String {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = who.isEmpty ? "" : "«\(who)»: "
        if state == "popout-failed" { return head + "чат не вынесся в окно — вынеси его руками" }
        guard let words = notCreatedWords[state] else { return head + "чат не создан (\(state))" }
        return head + "чат не создан — " + words
    }

    private func finish(_ current: Job, window: PimpWindow, windows: [PimpWindow], at: Date) {
        var job = current
        // Место посчитано до команды (WF98, #7841): окно родилось в углу своей ячейки, соседи
        // уже раздвинуты — остаётся размер, порядком свежего окна. План устарел (ряд сменился,
        // соседа подвинули) — ставим по-старому, как будто плана не было.
        let planned = job.plan.flatMap { plan in
            PimpChannel.planHolds(plan, before: job.before, born: window.id, windows: windows) ? plan : nil
        }
        if let plan = planned {
            let move = PimpMove(id: window.id, frame: plan.cell)
            seats.placeNew?(move)
            recheckPlaced(move)
        }
        // Точку поставила сама страница — двигать нечего.
        let settled = planned.map { (frame: $0.cell, skipped: 0, fromLost: false, failure: Failure?.none) }
            ?? settle(job.place, window: window, windows: windows,
                      fromId: job.fromId, fromTitle: job.fromTitle, moveToPoint: false)
        if settled.fromLost { job.fromResolved = false }
        let frame = settled.frame
        let skipped = settled.skipped
        if let failure = settled.failure {
            refuse(job.id, at: at, failure, fromResolved: job.fromResolved, notice: nil)
            return
        }
        guard let id = job.id else { return }
        let final = seats.windows().first { $0.id == window.id } ?? window
        var fields: [(key: String, value: CommandValue)] = [
            (key: "window", value: .object([
                (key: "title", value: .string(final.title)),
                (key: "chat", value: .string(final.chat)),
                (key: "frame", value: PimpChannel.frameValue(frame)),
            ])),
            // Слои страница кладёт сама и о судьбе их рассказывает в своём `status()`;
            // приложение знает ровно то, что послало (канал probe у неё не отнимаем).
            // На пути `chat:"last"` слои не уходят вовсе (чат выносится `popout-window` со своей
            // темой), флаг прошлого «нового окна» тут ничего не значит — эталон фиксирует ok.
            (key: "layers", value: .string(job.chat != nil || seats.newWindowLayers() ? "ok" : "")),
        ]
        // Поле есть только когда ячейки не нашлось: эталон `new-window.result.json` — случай
        // с ячейкой, и он обязан остаться побайтно тем же.
        if skipped > 0 { fields.append((key: "skipped", value: .number(skipped))) }
        // `opened` — ПОСЛЕДНИМ и только когда в запросе был `chat` (контракт WF75): без него
        // ответ обычного «нового окна» остаётся побайтно прежним.
        if job.chat != nil { fields.append((key: "opened", value: .bool(job.opened))) }
        reply(PimpAnswer(id: id, at: at, ok: true, fromResolved: job.fromResolved,
                         fields: fields), for: id)
    }

    /// Куда встаёт окно по месту (общая часть `finish` и пустого окна): рамка, `skipped` (ячейки
    /// не нашлось — окно где родилось), потерялось ли окно `from` и отказ `too-small`.
    /// `moveToPoint` — окно само в точку не встало (черновик Claude `initialPosition` не берёт,
    /// разведка S0 п. 9): ставим угол в точку, размер — окна-источника.
    private func settle(_ place: PimpPlace, window: PimpWindow, windows: [PimpWindow],
                        fromId: CGWindowID?, fromTitle: String?, moveToPoint: Bool)
        -> (frame: CGRect, skipped: Int, fromLost: Bool, failure: Failure?) {
        // Новому окну не досталось ячейки (в последней раскладке их меньше, чем окон):
        // оно остаётся где родилось, и об этом честно говорит поле `skipped` (план WF21).
        let atRow: (PimpPlace) -> (frame: CGRect, skipped: Int, fromLost: Bool, failure: Failure?) = { place in
            guard let placed = self.row(place, window: window, in: windows) else {
                return (window.frame, 1, false, nil)
            }
            return (placed, 0, false, nil)
        }
        switch place {
        case .point(let x, let y):
            guard moveToPoint else { return (window.frame, 0, false, nil) }
            let size = PimpChannel.window(id: fromId, title: fromTitle, in: windows)?.frame.size
                ?? window.frame.size
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            seats.place([PimpMove(id: window.id, frame: frame)])
            return (frame, 0, false, nil)
        case .left, .middle, .right:
            return atRow(place)
        case .below, .above:
            // Окно `from` могло закрыться, пока шли 40 с, — тогда «под этим» вырождается
            // в «справа», ровно как при неизвестном чате, и это видно по `fromResolved`.
            guard let target = PimpChannel.window(id: fromId, title: fromTitle, in: windows),
                  target.id != window.id else {
                let right = atRow(.right)
                return (right.frame, right.skipped, true, nil)
            }
            guard let halves = PimpChannel.split(target.frame, above: place == .above,
                                                 gap: seats.gap()) else {
                return (window.frame, 0, false, .tooSmall)
            }
            seats.place([PimpMove(id: target.id, frame: halves.old),
                         PimpMove(id: window.id, frame: halves.new)])
            return (halves.new, 0, false, nil)
        }
    }

    /// Отказ: запросу — код ошибки файлом, работе из меню (`id` nil) — плашкой. `notice` nil —
    /// у работы из меню этот отказ недостижим, и молчим.
    private func refuse(_ id: String?, at: Date, _ failure: Failure, fromResolved: Bool = false,
                        notice: String?) {
        guard let id = id else {
            if let notice = notice { seats.notice(notice) }
            return
        }
        reply(PimpAnswer(id: id, at: at, ok: false, error: failure.rawValue,
                         fromResolved: fromResolved), for: id)
    }

    // MARK: - пустое окно проекта (план WF88, К17)

    /// Пустое окно Claude Code проекта: File ▸ «New Session in New Window» у выбранного Claude,
    /// потом ждём черновик «Code» и ставим его на место. `id` nil — пункт меню ⌘B: файла ответа
    /// нет, отказ — плашкой. false — не начали (занято, Claude нет, пункта нет).
    @discardableResult
    func startBlank(project: Project, place: PimpPlace, from: String?, id: String?) -> Bool {
        let at = now()
        guard !isBusy, !seats.newWindowBusy() else {
            refuse(id, at: at, .busy, notice: MenuModel.blankBusyNotice)
            return false
        }
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            refuse(id, at: at, .noWindows, notice: MenuModel.blankNoClaudeNotice)
            return false
        }
        // Событие пункта Claude адресует главному окну (`B.webContents`, разведка S0): без
        // него нажатие ушло бы в пустоту (правка критика V-N п. 5).
        guard windows.contains(where: { $0.isMain(using: seats.isMainWindow) }) else {
            refuse(id, at: at, .noDraftItem, notice: MenuModel.blankNoItemNotice)
            return false
        }
        let chat = from ?? ""
        let fromTitle = chat.isEmpty ? nil : seats.titleForChat(chat)
        let fromWindow = PimpChannel.window(chat: chat, title: fromTitle, in: windows)
        var place = place
        if fromWindow == nil, place == .below || place == .above { place = .right }
        let before = Set(seats.blankWindows().map { $0.id })
        guard seats.pressDraftItem(project) else {
            refuse(id, at: at, .noDraftItem, fromResolved: fromWindow != nil,
                   notice: MenuModel.blankNoItemNotice)
            return false
        }
        blank = BlankJob(id: id, place: place, fromId: fromWindow?.id, fromTitle: fromTitle,
                         fromResolved: fromWindow != nil, before: before, pressedAt: now(),
                         folder: project.folder)
        scheduleBlankPoll()
        return true
    }

    /// «↩︎» у проекта в меню ⌘B (план WF88, К14-N): путь `chat:"last"` канала (WF75) без
    /// запроса. `id` nil — ответа в файл нет, отказ — плашкой.
    @discardableResult
    func startLast(project: Project, place: PimpPlace, from: String?, id: String?) -> Bool {
        let at = now()
        guard !isBusy, !seats.newWindowBusy() else {
            refuse(id, at: at, .busy, notice: MenuModel.blankBusyNotice)
            return false
        }
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            refuse(id, at: at, .noWindows, notice: MenuModel.blankNoClaudeNotice)
            return false
        }
        let chat = from ?? ""
        let fromTitle = chat.isEmpty ? nil : seats.titleForChat(chat)
        let fromWindow = PimpChannel.window(chat: chat, title: fromTitle, in: windows)
        var place = place
        if fromWindow == nil, place == .below || place == .above { place = .right }
        return runLastChat(project: project, place: place, from: fromWindow, fromTitle: fromTitle,
                           resolved: fromWindow != nil, windows: windows, id: id, at: at)
    }

    /// Шаг опроса пустого окна (0,25 с): черновик пришёл — ставим, срок вышел — отказ.
    /// Открыт для тестов: они шагают опрос сами, без таймера.
    func pollBlank(at: Date) {
        guard let current = blank else { return }
        let fresh = seats.blankWindows().filter { !current.before.contains($0.id) }
        switch BlankWindow.poll(fresh: fresh, elapsed: at.timeIntervalSince(current.pressedAt)) {
        case .take(let draft):
            blank = nil
            acceptBlank(current, draft: draft, at: at)
        case .wait:
            scheduleBlankPoll()
        case .missing:
            // Черновик, если он всё же родится, остаётся, где его поставил Claude.
            blank = nil
            refuse(current.id, at: at, .windowMissing, fromResolved: current.fromResolved,
                   notice: MenuModel.blankNoWindowNotice)
        }
    }

    private func scheduleBlankPoll() {
        seats.schedule(BlankWindow.pollSeconds) { [weak self] in
            guard let self = self else { return }
            self.pollBlank(at: self.now())
        }
    }

    /// Черновик пришёл: место (как у `finish`, только точку ставим сами), вперёд, настройка.
    /// Черновик на рамке служебного окна `windows` не видит — тогда он берётся из AX-списка.
    private func acceptBlank(_ current: BlankJob, draft: PimpWindow, at: Date) {
        let windows = seats.windows()
        let window = windows.first { $0.id == draft.id } ?? draft
        let all = windows.filter { $0.id != draft.id } + [window]
        var job = current
        let settled = settle(job.place, window: window, windows: all,
                             fromId: job.fromId, fromTitle: job.fromTitle, moveToPoint: true)
        if settled.fromLost { job.fromResolved = false }
        seats.raise(window.id)
        // Путь папки «Ч» (S.0): папку ставит страница чипом черновика; модель и ступень — как у
        // последнего чата проекта.
        let last = seats.lastChat(job.folder)
        let model = BlankWindow.model(of: last.flatMap { seats.chatModel($0.chat) })
        seats.draftSetup(BlankWindow.draftSetupFields(folder: job.folder.standardizedFileURL.path,
                                                      model: model.model, effort: model.effort,
                                                      bypass: seats.bypassNew()))
        if let failure = settled.failure {
            refuse(job.id, at: at, failure, fromResolved: job.fromResolved, notice: nil)
            return
        }
        guard let id = job.id else { return }
        var fields: [(key: String, value: CommandValue)] = [
            (key: "window", value: .object([
                (key: "title", value: .string(window.title)),
                (key: "chat", value: .string("")),
                (key: "frame", value: PimpChannel.frameValue(settled.frame)),
            ])),
        ]
        if settled.skipped > 0 { fields.append((key: "skipped", value: .number(settled.skipped))) }
        // `blank` — ПОСЛЕДНИМ (контракт К10-N): `layers` у пустого окна нет.
        fields.append((key: "blank", value: .bool(true)))
        reply(PimpAnswer(id: id, at: at, ok: true, fromResolved: job.fromResolved, fields: fields),
              for: id)
    }

    /// Сколько ждём окно «нового окна»: новый чат создаётся долго (сессия и первое сообщение),
    /// вынос уже готового чата — секунды (контракт WF75).
    private func waitSeconds(_ job: Job) -> TimeInterval {
        job.chat == nil ? PimpChannel.newWindowSeconds : PimpChannel.restoreWindowSeconds
    }

    /// Поставить новое окно столбцом (план WF77 — умным путём). Место названо всегда, и
    /// порядок НАВЯЗАН: «слева» — первым, «посередине» — в середину, «справа» и умолчание
    /// (#7730, WF94) — ПОСЛЕДНИМ среди окон Claude своего экрана (ChatGPT держит правую
    /// полосу сам, новое окно встаёт левее него). До WF94 «справа» было неприкаянным и
    /// садилось в первую свободную ячейку — «заполняешь свободное место», а не справа.
    /// Сидящие окна сохраняют порядок, дыра посередине уплотняется слева направо.
    /// Возвращает рамку нового окна; ячейки не нашлось (окон больше, чем мест на экране) —
    /// nil, и окно остаётся где родилось.
    private func row(_ place: PimpPlace, window: PimpWindow, in windows: [PimpWindow]) -> CGRect? {
        let others = windows.indices.filter { windows[$0].id != window.id }
        let order = ArrangeLayout.order(of: others.map { windows[$0].frame })
        // Число столбцов умной сетки канал не знает (её считает приложение по экрану),
        // поэтому «посередине» — середина всего порядка, как у ленты.
        let index = ArrangeLayout.insertIndex(of: place, count: others.count)
        let full = ArrangeLayout.insert(order: order, count: others.count, at: index)
        let ids = full.map { $0 == others.count ? window.id : windows[others[$0]].id }
        return seats.arrangeSmart(ids, true, window.id).first { $0.id == window.id }?.frame
    }

    // MARK: - закрыть, вставить, сказать (план WF75)

    /// «Закрой окно проекта»: окна проекта ищутся по ПАПКЕ окна, а её знает только живая карта
    /// чатов — молчит карта, окон не находится, и это честный `window-missing`.
    /// Закрываем ровно одно окно и только его красной кнопкой; чат при этом не удаляется.
    private func runCloseWindow(_ request: PimpRequest, id: String, at: Date) {
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let target: PimpWindow
        switch closable(request.project, in: windows) {
        case .ambiguous(let list):
            reply(PimpChannel.ambiguous(id: id, at: at, windows: list), for: id)
            return
        case .refuse(let failure):
            reply(PimpAnswer(id: id, at: at, ok: false, error: failure.rawValue), for: id)
            return
        case .window(let found):
            target = found
        }
        // Кнопки у окна может не быть вовсе (Electron ещё не отдал дерево) — «закрыл» без
        // закрытия не пишем никогда (урок #5779).
        guard seats.close(target.id) else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.windowMissing.rawValue),
                  for: id)
            return
        }
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.closeFields(target.title)),
              for: id)
    }

    /// Какое окно проекта можно закрыть (`close-window`, с WF102 и `renew-window`).
    private enum Closable {
        case window(PimpWindow)
        case refuse(Failure)
        case ambiguous([PimpWindow])
    }

    /// Окно проекта под красную кнопку: ровно одно, не главное и не с заглушкой в заголовке.
    private func closable(_ entry: String, in windows: [PimpWindow]) -> Closable {
        let mine = windows.filter { PimpChannel.matches(folder: $0.folder, entry: entry) }
        let mains = mine.filter { $0.isMain(using: seats.isMainWindow) }
        // Главным приложение может назвать ДВА окна разом: заглушку «Claude» носит и
        // безымянный попап, а окно без AX-заголовка зовётся главным всегда (#5729, #5534).
        // Тогда не трогаем ничего — иначе под кнопку попало бы окно Элвиса.
        guard mains.count < 2 else { return .ambiguous(mains) }
        // Окно с пустым заголовком или заглушкой из кандидатов выбывает по той же причине:
        // по такому заголовку окно не опознать, а закрываем мы навсегда.
        let candidates = mine.filter {
            !$0.isMain(using: seats.isMainWindow) && !PimpChannel.isStubTitle($0.title)
        }
        guard candidates.count < 2 else { return .ambiguous(candidates) }
        // Кандидатов нет, а окно проекта было главным — так и говорим: его не закрываем.
        guard let target = candidates.first else {
            return .refuse(mains.isEmpty ? .windowMissing : .mainWindow)
        }
        return .window(target)
    }

    /// «Вставь» (контракт WF75): файлы из запроса ложатся в буфер, окно поднимается, и в него
    /// уходит ⌘V. Enter канал не шлёт НИКОГДА — вставка не отправка. Ответ пишется ПОСЛЕ
    /// нажатия: фокус асинхронный, и до него `ok` не значил бы ничего (критик п. 6).
    private func runPaste(_ request: PimpRequest, id: String, at: Date) {
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        // Путь не абсолютный и число путей отсеял разбор; здесь — чего нет на диске и что
        // не обычный файл: с таким буфером ⌘V вставил бы чужое.
        guard request.paths.allSatisfy({ isRegularFile($0) }) else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.badRequest.rawValue), for: id)
            return
        }
        var resolved = false
        let target: PimpWindow
        if request.front {
            // Только пока Claude — ПЕРЕДНЯЯ программа: это то же, что ⌘V самого Элвиса
            // в том окне, где он стоит (слово Элвиса 19.09). Иначе не вставляем вовсе.
            guard let front = seats.frontWindow(),
                  let window = windows.first(where: { $0.id == front }) else {
                reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue),
                      for: id)
                return
            }
            target = window
        } else if let window = PimpChannel.window(
            chat: request.from,
            title: request.from.isEmpty ? nil : seats.titleForChat(request.from), in: windows) {
            resolved = true
            target = window
        } else {
            let mine = windows.filter {
                PimpChannel.matches(folder: $0.folder, entry: request.project)
            }
            guard mine.count == 1, let window = mine.first else {
                reply(mine.isEmpty
                        ? PimpAnswer(id: id, at: at, ok: false,
                                     error: Failure.windowMissing.rawValue)
                        : PimpChannel.ambiguous(id: id, at: at, windows: mine), for: id)
                return
            }
            target = window
        }
        seats.paste(target.id, request.paths) { [weak self] pressed in
            guard let self = self else { return }
            guard pressed else {
                // Окно пропало между выбором и нажатием — «вставил» без нажатия не пишем.
                self.reply(PimpAnswer(id: id, at: self.now(), ok: false,
                                      error: Failure.windowMissing.rawValue,
                                      fromResolved: resolved), for: id)
                return
            }
            self.reply(PimpAnswer(id: id, at: self.now(), ok: true, fromResolved: resolved,
                                  fields: PimpChannel.pasteFields(pasted: request.paths.count,
                                                                  window: target.title)), for: id)
        }
    }

    /// Плашка Элвису штатным сиденьем `notice` (= `HUD.show`): своего сиденья у неё нет,
    /// окон она не трогает, и ответ уходит сразу же.
    private func runHud(_ request: PimpRequest, id: String, at: Date) {
        seats.notice(request.text)
        reply(PimpAnswer(id: id, at: at, ok: true), for: id)
    }

    /// Файл годится для буфера: лежит на диске и это обычный файл, а не папка.
    private func isRegularFile(_ path: String) -> Bool {
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &directory) else { return false }
        return !directory.boolValue
    }

    // MARK: - отправить текст в чат (WF103)

    /// «Отправь текст в чат» (#7953, #7927; контракт WF103): окно — как у `renew-window`, но
    /// главное можно. Окну уходит `send-text` с его чатом; исход страница кладёт в
    /// `status().send`, канал ждёт его до 20 с, `<id>.taken` — сердцебиение.
    private func runSend(_ request: PimpRequest, id: String, at: Date, retried: Bool = false) {
        let windows = seats.claudeRunning() ? seats.windows() : []
        let fromTitle = request.from.isEmpty ? nil : seats.titleForChat(request.from)
        let resolved = PimpChannel.window(chat: request.from, title: fromTitle, in: windows) != nil
        let refuse: (Failure, [PimpWindow]?) -> Void = { failure, list in
            let fields: [(key: String, value: CommandValue)] = list.map {
                [(key: "windows", value: .array($0.map { .string($0.title) }))]
            } ?? []
            self.reply(PimpAnswer(id: id, at: at, ok: false, error: failure.rawValue,
                                  fromResolved: resolved, fields: fields), for: id)
        }
        let hits = request.chat.isEmpty
            ? windows.filter { PimpChannel.matches(folder: $0.folder, entry: request.project) }
            : windows.filter { $0.chat == request.chat }
        guard hits.count < 2 else { return refuse(.ambiguous, hits) }
        // Окно не нашлось или его чат не опознан, а у кого-то чат пуст (карта между кругами probe,
        // находка судьи WF111) — один раз спросить страницы и повторить после круга (`tick`).
        if !retried, let demand = seats.demandChats, hits.first?.chat.isEmpty ?? true,
           windows.contains(where: { $0.chat.isEmpty }) {
            demand(at)
            chatsWait = (request: request, id: id, since: at)
            return
        }
        // Чат окна неизвестен — адресовать команду нечем: страница сверяет его с собой.
        guard let target = hits.first, !target.chat.isEmpty else { return refuse(.windowMissing, nil) }
        sending = SendJob(id: id, window: target.title, fromResolved: resolved, startedAt: at)
        seats.sendText(target.chat, request.text, id)
    }

    /// Шаг `send`: исход страницы с нашим id — ответ; 20 с тишины — `no-answer`.
    private func advanceSend(_ current: SendJob, at: Date) {
        beat(current.id)
        let state = seats.sendState(current.id).flatMap { PimpChannel.sendStates.contains($0) ? $0 : nil }
        guard state != nil || at.timeIntervalSince(current.startedAt) >= PimpChannel.sendWaitSeconds
        else { return }
        sending = nil
        let error = state.map { $0 == "sent" || $0 == "queued" ? "" : $0 } ?? Failure.noAnswer.rawValue
        var fields: [(key: String, value: CommandValue)] = [(key: "window", value: .string(current.window))]
        if state == "queued" { fields.append((key: "queued", value: .bool(true))) }
        reply(PimpAnswer(id: current.id, at: at, ok: error.isEmpty, error: error,
                         fromResolved: current.fromResolved, fields: fields), for: current.id)
    }

    // MARK: - перезапуск Claude (WF108, #8176)

    /// «Перезапусти Claude»: без `force` сперва спрашиваем страницы — идёт ответ в чате (кроме
    /// позвавшего `from`) или о работе ничего не известно — отказ, Claude не трогаем. Дальше путь
    /// «Обновить Claude» (сиденье `restartClaude`), окна возвращает снимок К5 очередью канала;
    /// ответ — только когда возврат кончен.
    private func runRestart(_ request: PimpRequest, id: String, at: Date) {
        guard seats.claudeRunning() else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let job = RestartJob(id: id, from: request.from, stage: .asking, since: at)
        guard !request.force else { return relaunch(job, at: at) }
        restart = job
        seats.demandChats?(at)
        advanceRestart(job, at: at)
    }

    private func advanceRestart(_ current: RestartJob, at: Date) {
        switch current.stage {
        case .asking:
            let answered = seats.demandChats == nil || seats.chatsAnswered(current.since)
            guard answered || at.timeIntervalSince(current.since) >= PimpChannel.chatsWaitSeconds else { return }
            // Решаем только по ответу страниц ПОСЛЕ запроса (как «Обновить Claude», гейт 2 WF108):
            // не дождались — «не знаем», карту давностью до 180 с не берём.
            guard answered, let working = seats.workingChats(current.since) else {
                return refuseRestart(current.id, at: at, .workingUnknown)
            }
            var others = working.filter { current.from.isEmpty || $0.chat != current.from }
            // Второй признак — транскрипты Claude Code: чат без окна страницы не видят.
            guard let quiet = transcriptWork(from: current.from, at: at) else {
                return refuseRestart(current.id, at: at, .workingUnknown)
            }
            others += quiet.filter { chat in !others.contains { $0.chat == chat.chat } }
            guard others.isEmpty else {
                return refuseRestart(current.id, at: at, .working,
                                     fields: [(key: "chats", value: .array(others.map { .string($0.name) }))])
            }
            relaunch(current, at: at)
        case .relaunching, .restoring:
            beat(current.id)
        case .waiting:
            beat(current.id)
            switch seats.snapshotOutcome() {
            case .notNeeded:
                // Снимок решил, что возвращать нечего: Claude перезапущен, окон не трогали.
                finishRestart(current.id, at: at, placed: 0, opened: 0, skipped: [])
            case .gaveUp(let skipped):
                // Снимок сдался (окна нового Claude не появились за 120 с) — это не успех.
                refuseRestart(current.id, at: at, .restoreTimeout,
                              fields: [(key: "skipped", value: .array(skipped.map { .string($0) }))])
            case .pending:
                if at.timeIntervalSince(current.since) >= PimpChannel.restartRestoreSeconds {
                    refuseRestart(current.id, at: at, .restoreTimeout)
                }
            }
        }
    }

    /// Чаты Claude Desktop, чей транскрипт Claude Code менялся за `transcriptFreshSeconds` (кроме
    /// `from`). Терминальные сессии `claude` индексу Desktop неизвестны — их перезапуск Claude не
    /// трогает, и они не в счёт. nil — свежие транскрипты есть, а индекса чатов нет: не знаем.
    private func transcriptWork(from: String, at: Date) -> [(chat: String, name: String)]? {
        guard let root = seats.transcriptsRoot() else { return [] }
        let fresh = PimpChannel.freshTranscriptSessions(root: root, at: at, fileManager: fileManager)
        guard !fresh.isEmpty else { return [] }
        guard let sessions = seats.desktopSessions(), !sessions.isEmpty else { return nil }
        let own = sessions.first { !from.isEmpty && $0.chat == from }?.cli.lowercased()
        return sessions.filter { fresh.contains($0.cli.lowercased()) && $0.chat != from && $0.cli.lowercased() != own }
            .map { (chat: $0.chat, name: $0.name) }
    }

    /// Сессии Claude Code с транскриптом (`*.jsonl`), изменённым за `transcriptFreshSeconds`:
    /// `<root>/<папка>/<uuid>.jsonl` — сессия `uuid`; `<root>/<папка>/<uuid>/…/*.jsonl` (субагенты,
    /// воркфлоу) — тоже `uuid`: пишут его агенты, а сам оркестратор молчит.
    static func freshTranscriptSessions(root: URL, at: Date,
                                        fileManager: FileManager = .default) -> Set<String> {
        let since = at.addingTimeInterval(-transcriptFreshSeconds)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles]) else { return [] }
        var found = Set<String>()
        for folder in folders {
            guard let walker = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { continue }
            // Обход — сверху вниз: последний элемент первого уровня и есть предок файла.
            var head = ""
            for case let file as URL in walker {
                if walker.level == 1 { head = file.lastPathComponent }
                guard file.pathExtension == "jsonl",
                      let values = try? file.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= since else { continue }
                let session = walker.level == 1 ? file.deletingPathExtension().lastPathComponent : head
                guard !session.isEmpty,
                      session.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
                else { continue }
                found.insert(session.lowercased())
            }
        }
        return found
    }

    /// Закрыть и открыть Claude. Возврат снимка канал пускает только после `done(nil)` (стадия
    /// `waiting`, Claude уже новый); раньше снимок получает отказ и повторяет на своём тике.
    private func relaunch(_ current: RestartJob, at: Date) {
        var job = current
        job.stage = .relaunching
        job.since = at
        restart = job
        beat(job.id)
        let id = job.id
        seats.restartClaude { [weak self] failure in
            guard let self = self, let job = self.restart, job.id == id else { return }
            if let why = failure {
                return self.refuseRestart(id, at: self.now(), .restartFailed,
                                          fields: [(key: "reason", value: .string(why))])
            }
            guard job.stage == .relaunching else { return }
            self.restart?.stage = .waiting
            self.restart?.since = self.now()
        }
    }

    private func refuseRestart(_ id: String, at: Date, _ failure: Failure,
                               fields: [(key: String, value: CommandValue)] = []) {
        restart = nil
        reply(PimpAnswer(id: id, at: at, ok: false, error: failure.rawValue, fields: fields), for: id)
    }

    private func finishRestart(_ id: String, at: Date, placed: Int, opened: Int, skipped: [String]) {
        restart = nil
        mainChatDue = true
        reply(PimpAnswer(id: id, at: at, ok: true, fields: [
            (key: "placed", value: .number(placed)),
            (key: "opened", value: .number(opened)),
            (key: "skipped", value: .array(skipped.map { .string($0) })),
        ]), for: id)
    }

    // MARK: - чат в главное окно (WF108, #8148)

    /// «Чат в главное окно»: окно названного чата закрывается красной кнопкой (чат в двух окнах —
    /// всегда ошибка), главная страница открывает чат у себя и выносит прежний своим окном; окна
    /// меняются рамками. Не открылся — окно цели выносится обратно (`chat-missing`).
    private func runMain(_ request: PimpRequest, id: String, at: Date) {
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        startMain(chat: request.chat, project: request.project, windows: windows, id: id, at: at)
    }

    /// Настройка `mainChat` (#8148: «Рик всегда в главном»): после возврата окон `restart-claude` и
    /// после «главного по центру». Отвечать некому, отказ молчит.
    private func keepMainChat(at: Date) {
        guard let entry = seats.mainChatSetting(), seats.claudeRunning() else { return }
        let windows = seats.windows()
        guard !windows.isEmpty else { return }
        let isChat = PimpRequest.isChatID(entry)
        startMain(chat: isChat ? entry : "", project: isChat ? "" : entry, windows: windows, id: nil, at: at)
    }

    private func startMain(chat: String, project: String, windows: [PimpWindow], id: String?, at: Date) {
        let plan = PimpChannel.mainPlan(chat: chat, project: project, windows: windows,
                                        isMain: seats.isMainWindow, projects: seats.projects(),
                                        lastChat: seats.lastChat)
        switch plan {
        case .refuse(let failure, let list):
            let key = failure == .projectMissing ? "projects" : "windows"
            answerMain(id, at: at, ok: false, failure,
                       fields: list.isEmpty ? [] : [(key: key, value: .array(list.map { .string($0) }))])
        case .already(let chat):
            answerMain(id, at: at, ok: true, fields: PimpChannel.mainFields(chat: chat, popped: "", already: true))
        case .swap(let main, let chat, let target):
            // Чужая цепочка «Нового окна» ещё идёт: её окно мы приняли бы за вынесенное.
            guard !seats.newWindowStarting() else { return answerMain(id, at: at, ok: false, .busy) }
            var job = MainJob(id: id, chat: chat, main: main, target: target, since: at,
                              before: Set(windows.map { $0.id }))
            if let target = target {
                guard seats.close(target.id) else {
                    return answerMain(id, at: at, ok: false, .windowMissing,
                                      fields: [(key: "windows", value: .array([.string(target.title)]))])
                }
                mainJob = job
                beat(id)
                return
            }
            sendMain(&job, at: at)
            mainJob = job
        }
    }

    private func sendMain(_ job: inout MainJob, at: Date) {
        let origin = job.target.map { PimpChannel.corner($0.frame) }
            ?? PimpChannel.popoutOrigin(.right, near: job.main.frame)
        seats.sendMainChat(job.chat, origin)
        job.sent = at
        beat(job.id)
    }

    private func advanceMain(_ current: MainJob, at: Date) {
        var job = current
        if job.rollbackFailure != nil { return advanceMainRollback(job, at: at) }
        guard let sent = job.sent else {
            let windows = seats.windows()
            if let target = job.target, windows.contains(where: { $0.id == target.id }),
               at.timeIntervalSince(job.since) < PimpChannel.mainCloseSeconds {
                beat(job.id)
                return
            }
            job.before = Set(windows.map { $0.id })
            sendMain(&job, at: at)
            mainJob = job
            return
        }
        beat(job.id)
        let chatField: [(key: String, value: CommandValue)] = [(key: "chat", value: .string(job.chat))]
        if job.popped == nil, let run = seats.newWindowRun(), run.at > sent {
            switch run.state {
            case "already":
                return answerMain(job.id, at: at, ok: true,
                                  fields: PimpChannel.mainFields(chat: job.chat, popped: "", already: true))
            case "ok":
                job.popped = run.chat
            case "chat-missing", "busy", "bad-command":
                return beginMainRollback(job, failure: run.state == "busy" ? .busy : .chatMissing,
                                         fields: chatField, at: at)
            case "no-store", "popout-failed":
                return beginMainRollback(job, failure: .chatNotCreated,
                                         fields: chatField + [(key: "popped", value: .string(run.chat)),
                                                              (key: "state", value: .string(run.state))], at: at)
            case "error", "timeout":
                return beginMainRollback(job, failure: .noAnswer, fields: chatField, at: at)
            default:
                break
            }
        }
        if let popped = job.popped {
            let fresh = popped.isEmpty ? nil : seats.windows().first {
                !job.before.contains($0.id) && PimpChannel.accepts(chat: popped, $0)
            }
            if popped.isEmpty || fresh != nil || at.timeIntervalSince(sent) >= PimpChannel.restoreWindowSeconds {
                // Окно не показалось за срок — главное всё равно на месте цели, вынесенное стоит, где родилось.
                seats.place(PimpChannel.mainMoves(main: job.main, target: job.target, popped: fresh?.id))
                return answerMain(job.id, at: at, ok: true,
                                  fields: PimpChannel.mainFields(chat: job.chat, popped: popped, already: false))
            }
        } else if at.timeIntervalSince(sent) >= PimpChannel.restoreWindowSeconds {
            return beginMainRollback(job, failure: .noAnswer, fields: chatField, at: at)
        }
        mainJob = job
    }

    private func beginMainRollback(_ current: MainJob, failure: Failure,
                                   fields: [(key: String, value: CommandValue)], at: Date) {
        var job = current
        job.rollbackFailure = failure
        job.rollbackSince = at
        job.rollbackFields = fields
        mainJob = job
        seats.demandChats?(at)
        advanceMainRollback(job, at: at)
    }

    private func answerRollback(_ job: MainJob, at: Date, _ failure: Failure) {
        answerMain(job.id, at: at, ok: false, failure, fields: job.rollbackFields)
    }

    private func advanceMainRollback(_ job: MainJob, at: Date) {
        guard let failure = job.rollbackFailure, let since = job.rollbackSince else { return }
        guard let target = job.target else {
            return answerRollback(job, at: at, failure)
        }
        let census = seats.restoreWindows?() ?? (windows: seats.windows(), complete: true)
        let checkpoint = job.rollbackOpenedAt ?? since
        let complete = census.complete && (seats.demandChats == nil || seats.chatsAnswered(checkpoint))
            && (seats.restoreWindows == nil || WindowSnapshotStore.observe(from: census.windows,
                complete: true, isMain: seats.isMainWindow, screen: { _ in "" }).complete)
        guard complete else {
            if at.timeIntervalSince(checkpoint) >= Self.restoreWindowSeconds {
                answerRollback(job, at: at, failure)
                seats.notice("Окно не восстановлено: не удалось проверить окна Claude. Перенос повторно не запускался.")
            } else { mainJob = job; beat(job.id) }
            return
        }
        let found = census.windows.filter { $0.chat == job.chat }
        if let opened = job.rollbackOpenedAt {
            if found.count == 1, let donor = found.first {
                // A late successful main transition wins; never move its main window back.
                mainJob = nil
                if !donor.isMain(using: seats.isMainWindow) {
                    seats.place([PimpMove(id: donor.id, frame: seats.restoreFrame(target.frame))])
                }
                return answerRollback(job, at: at, failure)
            }
            if at.timeIntervalSince(opened) >= Self.restoreWindowSeconds {
                answerRollback(job, at: at, failure)
                seats.notice("Окно чата не появилось после одной попытки возврата.")
            } else { mainJob = job; beat(job.id) }
            return
        }
        guard found.isEmpty, seats.claudeRunning() else {
            return answerRollback(job, at: at, failure)
        }
        // Record the one-shot consumption before effects. The next stage only places the
        // confirmed donor at its full saved frame; it can never call openChat again.
        var pending = job
        pending.rollbackOpenedAt = at
        mainJob = pending
        seats.openChat(job.chat, target.title, PimpChannel.corner(seats.restoreFrame(target.frame)))
        seats.demandChats?(at)
    }

    private func answerMain(_ id: String?, at: Date, ok: Bool, _ failure: Failure? = nil,
                            fields: [(key: String, value: CommandValue)] = []) {
        mainJob = nil
        guard let id = id else {
            if !ok { seats.notice("Не удалось подтвердить перенос чата в главное окно: \(failure?.rawValue ?? "неизвестный исход").") }
            return
        }
        reply(PimpAnswer(id: id, at: at, ok: ok, error: failure?.rawValue ?? "", fields: fields), for: id)
    }

    // MARK: - замена окна и «главный по центру» (WF102)

    /// «Замени окно» (#7917, правки критика C1, C7): новый чат того же проекта рождается в углу
    /// окна-донора и встаёт в его рамку, донор закрывается красной кнопкой, как `close-window`, —
    /// и только когда известен id нового чата. Чат донора не удаляется. Идёт той же работой
    /// `Job`, что «новое окно» (канал занят, отказ страницы — `chat-not-created`).
    private func runRenew(_ request: PimpRequest, id: String, at: Date) {
        let windows = seats.windows()
        if seats.claudeRunning(), waitingForMain(windows, id: id, at: at) { return }
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let fromTitle = request.from.isEmpty ? nil : seats.titleForChat(request.from)
        let fromWindow = PimpChannel.window(chat: request.from, title: fromTitle, in: windows)
        let resolved = fromWindow != nil
        let refuse: (Failure, [(key: String, value: CommandValue)]) -> Void = { failure, fields in
            self.reply(PimpAnswer(id: id, at: at, ok: false, error: failure.rawValue,
                                  fromResolved: resolved, fields: fields), for: id)
        }
        let titles: ([PimpWindow]) -> [(key: String, value: CommandValue)] = { list in
            [(key: "windows", value: .array(list.map { .string($0.title) }))]
        }
        let donor: PimpWindow
        if request.chat.isEmpty {
            switch closable(request.project, in: windows) {
            case .ambiguous(let list): return refuse(.ambiguous, titles(list))
            case .refuse(.mainWindow):
                // Окно проекта одно, и оно главное (WF131): меняем чат в нём самом.
                guard let found = windows.first(where: {
                    PimpChannel.matches(folder: $0.folder, entry: request.project) && $0.isMain(using: seats.isMainWindow)
                }) else { return refuse(.mainWindow, []) }
                donor = found
            case .refuse(let failure): return refuse(failure, [])
            case .window(let found): donor = found
            }
        } else {
            let hits = windows.filter { $0.chat == request.chat }
            guard hits.count < 2 else { return refuse(.ambiguous, titles(hits)) }
            guard let found = hits.first else { return refuse(.windowMissing, []) }
            donor = found
        }
        // Главное окно не закрываем никогда (WF131, #9078). С WF181 (#9225, слово Элвиса 09.10 03:20:
        // «Зачем ты открываешь новое окно? Мы работаем сейчас в одном окне, всегда») новый чат
        // открывается В САМОМ главном окне — `stay`, как «💬 Новый чат» главного окна, второго окна нет;
        // прежний чат остаётся в списке слева.
        let main = donor.isMain(using: seats.isMainWindow)
        // Проект нового чата — папка донора (её знает карта чатов); не знаем — проекта нет.
        let known = seats.projects()
        let folder = donor.folder.isEmpty ? ""
            : URL(fileURLWithPath: donor.folder, isDirectory: true).standardizedFileURL.path
        guard let project = known.first(where: { !folder.isEmpty && $0.folder.standardizedFileURL.path == folder })
            ?? PimpChannel.project(named: folder, in: known, fileManager: fileManager) else {
            return refuse(.projectMissing, [(key: "projects", value: .array(known.map { .string($0.name) }))])
        }
        // Чужая цепочка ещё идёт (z4-r01): её окно канал принял бы за своё.
        guard !seats.newWindowStarting() else { return refuse(.busy, []) }
        // Рождается со сдвигом от угла донора (гейт WF102): окна Quartz и AX сводятся по рамке,
        // и новое окно ровно на рамке донора (оба 900×700 в углу) путало `close` — живьём
        // закрывалось новое окно вместо донора.
        let corner = PimpChannel.corner(donor.frame)
        let origin = (x: corner.x + PimpChannel.renewBirthShift, y: corner.y + PimpChannel.renewBirthShift)
        // Модель и эффорт — без записи «Обкэшить» (C1): текст — из запроса. Закрепки нет (WF181,
        // #9225, слово Элвиса: «Не закрепляй. Вот пин не делай»): ни `pin`, ни `unpin` донора.
        let handoff = NewChatHandoff(model: request.model.isEmpty ? nil : request.model,
                                     effort: request.effort.isEmpty ? nil : request.effort,
                                     stay: main, transfer: false, pin: false)
        begin(Job(id: id, place: .point(x: origin.x, y: origin.y), fromId: fromWindow?.id,
                  fromTitle: fromTitle, fromResolved: resolved, before: Set(windows.map { $0.id }),
                  startedAt: at, renew: Renew(donor: donor, main: main, model: handoff.model)))
        seats.openRenewWindow(project, origin, request.text.isEmpty ? nil : request.text, handoff)
    }

    /// Шаг замены окна: ждём рождения (65 с, отказ страницы — сразу), ставим окно в рамку
    /// донора, потом до `renewChatSeconds` ждём id нового чата (и модель из файла сессии) и
    /// только тогда закрываем донора. Id так и не узнали — `chat-unknown`, донор остаётся.
    private func advanceRenew(_ current: Job, renew start: Renew, at: Date) {
        if start.main { return advanceRenewHere(current, renew: start, at: at) }
        var renew = start
        let windows = seats.windows()
        if renew.born == nil {
            guard let fresh = windows.first(where: { !current.before.contains($0.id) }) else {
                if let state = seats.newWindowRun()?.failure(since: current.startedAt) {
                    job = nil
                    refuseNotCreated(current, state: state, at: at)
                    return
                }
                guard at.timeIntervalSince(current.startedAt) >= waitSeconds(current) else { return }
                job = nil
                refuse(current.id, at: at, .windowMissing, fromResolved: current.fromResolved,
                       notice: nil)
                return
            }
            // В рамку донора новое окно встаёт только ПОСЛЕ закрытия донора (гейт WF102): окна
            // Quartz и AX сводятся по рамке, и два окна в одной рамке путали `close` — живьём
            // закрылось новое окно вместо донора.
            renew.born = fresh.id
            renew.bornAt = at
            var updated = current
            updated.renew = renew
            job = updated
        }
        guard let born = renew.born, let bornAt = renew.bornAt, let id = current.id else { return }
        let window = windows.first { $0.id == born }
        let chat = PimpChannel.renewChat(window: window?.chat ?? "", run: seats.newWindowRun(),
                                         since: current.startedAt, donor: renew.donor.chat)
        let waited = at.timeIntervalSince(bornAt) >= PimpChannel.renewChatSeconds
        let donorFrame = renew.donor.frame
        let windowField: (String) -> (key: String, value: CommandValue) = { chat in
            (key: "window", value: .object([
                (key: "title", value: .string(window?.title ?? "")),
                (key: "chat", value: .string(chat)),
                (key: "frame", value: PimpChannel.frameValue(donorFrame)),
            ]))
        }
        guard !chat.isEmpty else {
            guard waited else { return }
            job = nil
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.chatUnknown.rawValue,
                             fromResolved: current.fromResolved, fields: [windowField("")]), for: id)
            return
        }
        // Модель — из файла сессии нового чата; файла ещё нет — ждём в пределах того же срока.
        var model: String?
        if let want = renew.model {
            let got = seats.chatModel(chat)?.menuModel
            if got == nil, !waited { return }
            model = PimpChannel.sameModel(got, want) ? "ok" : "missed"
        }
        job = nil
        // Донор закрыт руками раньше нас — заменять уже нечего, это не отказ. Кнопки у окна нет —
        // «заменил» без закрытия не пишем (урок #5779), новое окно при этом называем.
        if windows.contains(where: { $0.id == renew.donor.id }), !seats.close(renew.donor.id) {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.windowMissing.rawValue,
                             fromResolved: current.fromResolved, fields: [windowField(chat)]), for: id)
            return
        }
        let move = PimpMove(id: born, frame: donorFrame)
        if let placeNew = seats.placeNew {
            placeNew(move)
            recheckPlaced(move)
        } else {
            seats.place([move])
        }
        var fields = [windowField(chat), (key: "replaced", value: CommandValue.string(renew.donor.chat))]
        // `model` — ПОСЛЕДНИМ и только когда модель просили (эталон `renew-window.result.json`).
        if let model = model { fields.append((key: "model", value: .string(model))) }
        reply(PimpAnswer(id: id, at: at, ok: true, fromResolved: current.fromResolved, fields: fields),
              for: id)
    }

    /// Замена чата главного окна (WF181, #9225): `new-window` + `stay` открывает новый чат в самом
    /// главном окне. Ждём, пока окно (карта чатов) или цепочка страницы назовут новый чат, и модель
    /// из файла сессии — не дольше `renewChatSeconds` после того, как чат назван. Второго окна нет,
    /// закрывать нечего. Страница сказала «готово» без чата (`step:"stay"`, текст не ушёл) —
    /// `chat-not-created` с `state:"no-send"`; молчит дольше срока — `chat-unknown`.
    private func advanceRenewHere(_ current: Job, renew start: Renew, at: Date) {
        var renew = start
        guard let id = current.id else { job = nil; return }
        let windows = seats.windows()
        let main = windows.first { $0.id == renew.donor.id }
            ?? windows.first { $0.isMain(using: seats.isMainWindow) } ?? renew.donor
        let run = seats.newWindowRun()
        let chat = PimpChannel.renewChat(window: main.chat, run: run, since: current.startedAt,
                                         donor: renew.donor.chat)
        let windowField: (String) -> (key: String, value: CommandValue) = { chat in
            (key: "window", value: .object([
                (key: "title", value: .string(main.title)),
                (key: "chat", value: .string(chat)),
                (key: "frame", value: PimpChannel.frameValue(main.frame)),
            ]))
        }
        guard !chat.isEmpty else {
            if let run = run, run.at > current.startedAt {
                if let state = run.failure(since: current.startedAt) {
                    job = nil
                    return refuseNotCreated(current, state: state, at: at)
                }
                if !run.busy, run.step == "stay", run.chat.isEmpty {
                    job = nil
                    return refuseNotCreated(current, state: "no-send", at: at)
                }
            }
            guard at.timeIntervalSince(current.startedAt) >= waitSeconds(current) else { return }
            job = nil
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.chatUnknown.rawValue,
                             fromResolved: current.fromResolved, fields: [windowField("")]), for: id)
            return
        }
        let named = renew.bornAt ?? at
        if renew.bornAt == nil {
            renew.bornAt = at
            var updated = current
            updated.renew = renew
            job = updated
        }
        var model: String?
        if let want = renew.model {
            let got = seats.chatModel(chat)?.menuModel
            if got == nil, at.timeIntervalSince(named) < PimpChannel.renewChatSeconds { return }
            model = PimpChannel.sameModel(got, want) ? "ok" : "missed"
        }
        job = nil
        var fields: [(key: String, value: CommandValue)] = [
            windowField(chat),
            (key: "replaced", value: .string(renew.donor.chat)),
            (key: "main", value: .bool(true)),
        ]
        // `model` — ПОСЛЕДНИМ и только когда модель просили (эталон `renew-window.result.json`).
        if let model = model { fields.append((key: "model", value: .string(model))) }
        reply(PimpAnswer(id: id, at: at, ok: true, fromResolved: current.fromResolved, fields: fields),
              for: id)
    }

    /// Id нового чата замены: сперва карта чатов окна, потом цепочка страницы, начатая после
    /// запроса. Id донора новым не считается.
    /// Сдвиг рождения нового окна замены от угла донора, pt.
    static let renewBirthShift = 24

    static func renewChat(window: String, run: NewWindowRun?, since: Date, donor: String) -> String {
        if !window.isEmpty, window != donor { return window }
        guard let run = run, run.at > since, !run.chat.isEmpty, run.chat != donor else { return "" }
        return run.chat
    }

    /// Встала ли модель: подпись из файла сессии («Opus 5.5») против просьбы запроса — без
    /// регистра и лишних пробелов; просьба может быть длиннее («Opus 5.5 (1M)»).
    static func sameModel(_ got: String?, _ want: String) -> Bool {
        let clean: (String) -> String = {
            $0.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        guard let got = got.map(clean), !got.isEmpty else { return false }
        let asked = clean(want)
        return asked == got || asked.hasPrefix(got + " ")
    }

    /// «Главный по центру» (#7904, правки критика C5, C6): главный — окно чата `center` (проект,
    /// путь или `local_…`), без ключа — окно чата `from`, нет его — главное окно Claude. Берутся
    /// окна экрана главного и (WF103, #7954) окна проектов из `order` с любого экрана — они
    /// переезжают на экран главного; главный — на месте `floor((n−1)/2)` порядка, остальные — по
    /// `order`, а без него по рамкам. Ячейка боковой трети уже `minWindowWidth` — `too-small`.
    /// WF107 (#8125, К1): запись `order` «A+B» — столбец клетками (A сверху), главный, названный в
    /// `order` отдельной записью, стоит там, где назван. Такой путь ставит окна готовыми рамками
    /// (`seats.place`); без стопок и без главного в середине `order` — прежний `seats.arrange`.
    private func runArrangeCenter(_ request: PimpRequest, windows: [PimpWindow], id: String,
                                  at: Date) {
        let fromTitle = request.from.isEmpty ? nil : seats.titleForChat(request.from)
        let fromWindow = PimpChannel.window(chat: request.from, title: fromTitle, in: windows)
        let resolved = fromWindow != nil
        let refuse: (Failure, [PimpWindow]?) -> Void = { failure, list in
            let fields: [(key: String, value: CommandValue)] = list.map {
                [(key: "windows", value: .array($0.map { .string($0.title) }))]
            } ?? []
            self.reply(PimpAnswer(id: id, at: at, ok: false, error: failure.rawValue,
                                  fromResolved: resolved, fields: fields), for: id)
        }
        let hub: PimpWindow
        if !request.center.isEmpty {
            let hits = windows.filter {
                $0.chat == request.center || PimpChannel.matches(folder: $0.folder, entry: request.center)
            }
            guard hits.count < 2 else { return refuse(.ambiguous, hits) }
            guard let found = hits.first else { return refuse(.windowMissing, nil) }
            hub = found
        } else if let from = fromWindow {
            hub = from
        } else {
            let mains = windows.filter { $0.isMain(using: seats.isMainWindow) }
            guard mains.count < 2 else { return refuse(.ambiguous, mains) }
            guard let main = mains.first else { return refuse(.windowMissing, nil) }
            hub = main
        }
        // Окна экрана главного и окна проектов из `order` с любого экрана (WF103, #7954: после
        // блокировки экрана окна съезжают на MacBook); прочие окна других экранов не трогаем (C6).
        let screens = seats.screens()
        var peers = windows
        var area: CGRect?
        if !screens.isEmpty {
            let full = screens.map { $0.full }
            let home = Screens.assign(screens: full, frames: [hub.frame])[0]
            let marks = Screens.assign(screens: full, frames: windows.map { $0.frame })
            let named = PimpChannel.flatOrder(request.order ?? [])
            peers = windows.indices.filter { index in
                marks[index] == home
                    || named.contains { PimpChannel.matches(folder: windows[index].folder, entry: $0) }
            }.map { windows[$0] }
            area = screens[home].usable
        }
        let others = peers.filter { $0.id != hub.id }
        let base = ArrangeLayout.order(of: others.map { $0.frame })
        let plan = request.order.map { PimpChannel.centerPlan(of: others, hub: hub, by: $0, base: base) }
        let columns = plan?.columns ?? base.map { [$0] }
        // Главный назван в середине `order` (слева и справа есть столбцы) — его место оттуда.
        let named = plan?.left.flatMap { $0 >= 1 && $0 < columns.count ? $0 : nil }
        let (cellWidth, gap) = (seats.cellWidth(), seats.gap())
        if let area = area, named != nil || columns.contains(where: { $0.count > 1 }) {
            var layout = columns.map { $0.map { others[$0] } }
            let left = named ?? ArrangeLayout.centerHubIndex(count: columns.count + 1, in: area,
                                                             minCellWidth: cellWidth, gap: gap)
            layout.insert([hub], at: left)
            let rows = ArrangeLayout.stackRows(height: area.height, gap: gap)
            guard layout.allSatisfy({ $0.count <= rows }) else {
                return reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.tooSmall.rawValue,
                                        fromResolved: resolved,
                                        fields: [(key: "rows", value: .number(rows))]), for: id)
            }
            guard let frames = ArrangeLayout.centerStacks(layout.map { $0.count }, hub: left, in: area,
                                                          gap: gap, minCellWidth: cellWidth) else {
                return refuse(.tooSmall, nil)
            }
            // Ответ — из посчитанных рамок, экран не перечитываем (как `ClaudeActions.arrange`).
            var placed: [PimpWindow] = []
            for (column, cells) in zip(layout, frames) {
                for (window, frame) in zip(column, cells) {
                    placed.append(PimpWindow(id: window.id, title: window.title, chat: window.chat,
                                             folder: window.folder, frame: frame, main: window.main))
                }
            }
            // Окно ушло с экрана, пока считали (хвост WF107), — его не ставим и считаем в `skipped`,
            // как прежний путь (`ClaudeActions.arrange`): в ответе — только переставленные.
            let alive = seats.windowIDs?()
            let skipped = alive.map { live in placed.filter { !live.contains($0.id) }.count } ?? 0
            if let live = alive { placed = placed.filter { live.contains($0.id) } }
            seats.place(placed.map { PimpMove(id: $0.id, frame: $0.frame) })
            seats.explicitLayout(placed.map { PimpMove(id: $0.id, frame: $0.frame) })
            reply(PimpAnswer(id: id, at: at, ok: true, fromResolved: resolved,
                             fields: PimpChannel.arrangeFields(
                                placed, mode: .center, skipped: skipped,
                                hub: placed.firstIndex { $0.id == hub.id },
                                unknown: plan?.unknown, missing: plan?.missing,
                                minimized: seats.minimized())), for: id)
            mainChatDue = true
            return
        }
        // Прежний путь: столбец — одно окно (стопки без экрана — окнами подряд).
        var ids = columns.flatMap { $0 }.map { others[$0].id }
        // Тесно — слева окон больше, главный правее середины порядка (#8123); иначе посередине, как было.
        ids.insert(hub.id, at: ArrangeLayout.centerHubIndex(count: ids.count + 1, in: area,
                                                            minCellWidth: cellWidth, gap: gap))
        if let area = area, !ArrangeLayout.centerFits(count: ids.count, in: area,
                                                       minCellWidth: cellWidth, gap: gap) {
            return refuse(.tooSmall, nil)
        }
        let placed = seats.arrange(ids, .center, hub.id)
        guard !placed.windows.isEmpty else { return refuse(.noWindows, nil) }
        seats.explicitLayout(placed.windows.map { PimpMove(id: $0.id, frame: $0.frame) })
        reply(PimpAnswer(id: id, at: at, ok: true, fromResolved: resolved,
                         fields: PimpChannel.arrangeFields(
                            placed.windows, mode: .center, skipped: placed.skipped,
                            hub: placed.windows.firstIndex { $0.id == hub.id },
                            unknown: plan?.unknown, missing: plan?.missing,
                            minimized: seats.minimized())), for: id)
        mainChatDue = true
    }

    // MARK: - раскладки проектов (план WF41)

    /// «Какие раскладки»: имена, раскладка и сколько в ней мест. Свежие первыми — так их
    /// отдаёт `LayoutsStore`.
    private func runLayouts(id: String, at: Date) {
        reply(PimpAnswer(id: id, at: at, ok: true,
                         fields: PimpChannel.layoutsFields(seats.layouts())), for: id)
    }

    /// «Запомни раскладку как …»: снимок окон по ячейкам нынешней сетки. Окно, чей чат
    /// приложение не знает, останавливает запись целиком (`chat-unknown`): вернулись бы
    /// не те чаты, а половина раскладки хуже её отсутствия (#5455).
    private func runLayoutSave(_ request: PimpRequest, id: String, at: Date) {
        let census = seats.restoreWindows?() ?? (windows: seats.windows(), complete: true)
        let windows = census.windows
        guard census.complete else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.chatUnknown.rawValue), for: id)
            return
        }
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let tile = seats.arrangeMode()
        let snapshot = LayoutsStore.bestSnapshot(
            name: request.name, at: at, mode: tile, windows: windows,
            tileCells: seats.cells(tile, ArrangeLayout.capacity(of: tile) ?? windows.count),
            smart: seats.smartGrid(windows.map { $0.frame }), isMain: seats.isMainWindow)
        // Сетка снимка — плитка или умная (#6747): ответ называет ту, по которой записали.
        let mode = snapshot.layout.mode
        guard snapshot.unknown.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.chatUnknown.rawValue,
                             fields: [(key: "windows",
                                       value: .array(snapshot.unknown.map { .string($0) }))]),
                  for: id)
            return
        }
        // Ни одно окно не совпало с ячейкой сетки — окна стоят не по сетке, и запись вышла бы
        // пустышкой: файл говорил бы «5 окон», а возврат двигал бы ноль (#5728). Отказываем
        // словами, как при неизвестном чате.
        let placed = LayoutsStore.placedCells(snapshot.layout)
        guard placed > 0 else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.notArranged.rawValue),
                  for: id)
            return
        }
        guard seats.saveLayout(snapshot.layout) else {
            // Файл не записался (нет прав, том только для чтения) — молчать нельзя.
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.badRequest.rawValue), for: id)
            return
        }
        // `cells` ответа — сколько мест получили НОМЕР ячейки, а не сколько записей всего:
        // Элвису называют то, что вернётся (#5728).
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.layoutSaveFields(
            name: snapshot.layout.name, mode: mode, cells: placed)), for: id)
    }

    /// «Верни Утро»: те же чаты по тем же ячейкам (`fresh:false`) или новые чаты по тем же
    /// папкам (`fresh:true`). Ответ уходит, когда очередь кончится, — до тех пор канал занят.
    private func runLayoutRestore(_ request: PimpRequest, id: String, at: Date) {
        let list = seats.layouts()
        guard let layout = LayoutsStore.matching(name: request.name, in: list) else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.layoutMissing.rawValue,
                             fields: [(key: "layouts",
                                       value: .array(list.map { .string($0.name) }))]), for: id)
            return
        }
        // Окна рождает главное окно Claude: без единого окна на экране открывать нечем.
        guard seats.claudeRunning(), !(seats.restoreWindows?().windows ?? seats.windows()).isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        begin(layout, fresh: request.fresh, id: id, at: at)
    }

    /// «↩︎ Вернуть эти чаты» из меню (план WF41, решение Р5): та же очередь, что у канала,
    /// только отвечать некому — результат виден окнами на экране. Канал занят — не начинаем.
    @discardableResult
    func startRestore(_ layout: WindowLayout, fresh: Bool) -> Bool {
        guard !isBusy, seats.claudeRunning(), !(seats.restoreWindows?().windows ?? seats.windows()).isEmpty else { return false }
        return begin(layout, fresh: fresh, id: nil, at: now())
    }

    /// «Окна как были» (#7065, контракт К5): та же очередь, что у «↩︎ Вернуть эти чаты»,
    /// только рамки абсолютные — из снимка `windows-snapshot.json`, а не из ячеек сетки.
    /// Главное окно встаёт на своё место, закрытые чаты выносятся окнами по одному; чат,
    /// которого больше нет, пропускается и назван на плашке — новых чатов не заводим,
    /// сообщений не шлём. Канал занят или окон нет — false, начать можно позже.
    @discardableResult
    func startRestore(snapshot: WindowSnapshot, name: String) -> Bool {
        // Перезапуск (WF108) ради этого возврата и держит канал — его возврат пускаем, но только
        // когда Claude уже новый (`waiting`, после `done(nil)`), а не посреди выхода и запуска.
        let forRestart = restart?.stage == .waiting
        guard !busyBesidesRestart, restart == nil || forRestart,
              seats.claudeRunning(), !(seats.restoreWindows?().windows ?? seats.windows()).isEmpty else { return false }
        let queue = snapshot.windows.map {
            RestoreStep(chat: $0.chat, folder: $0.folder, title: $0.title, frame: $0.frame)
        }
        if forRestart { restart?.stage = .restoring }
        var job = RestoreJob(id: nil, name: name, fresh: false, queue: queue)
        job.forRestart = forRestart
        launchRestore(job, at: now())
        return true
    }

    /// Идёт ли возврат (раскладки или «окон как были»): пока идёт, снимок окон не пишется —
    /// иначе он записал бы полупустой экран посреди возврата (критик WF84 Б4).
    var isRestoring: Bool { restore != nil }

    /// Saved absolute positions take precedence; old layouts still use their grid cells.
    /// A record with neither frame nor cell remains missing rather than guessing a place.
    @discardableResult
    private func begin(_ layout: WindowLayout, fresh: Bool, id: String?, at: Date) -> Bool {
        let top = (layout.cells.compactMap { $0.cell }.max()).map { $0 + 1 } ?? 0
        // Мест столько же, сколько было окон при записи (запись — на каждое окно): у ЛЕНТЫ
        // ширина ячейки зависит от их числа, и раскладка с окном вне сетки вернулась бы
        // половинами вместо третей (#5688). У сеток число мест ничего не меняет.
        let count = max(top, layout.cells.count)
        // Раскладка по умной сетке (#6747) ставит окна в ту же сетку «столбцы × ряды».
        let frames = layout.grid.map { seats.gridCells($0) }
            ?? (count > 0 ? seats.cells(layout.mode, count) : [])
        let queue = layout.cells
            .sorted { ($0.cell ?? Int.max) < ($1.cell ?? Int.max) }
            .map { record -> RestoreStep in
                let frame = record.frame ?? record.cell.flatMap { frames.indices.contains($0) ? frames[$0] : nil }
                return RestoreStep(chat: record.chat, folder: record.folder,
                                   title: record.title, frame: frame)
            }
        let census = seats.restoreWindows?() ?? (windows: seats.windows(), complete: true)
        let sample = WindowSnapshotStore.observe(from: census.windows, complete: census.complete,
                                                 isMain: seats.isMainWindow, screen: { _ in "" })
        guard census.complete, seats.restoreWindows == nil || sample.complete else {
            if let id = id { reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.chatUnknown.rawValue), for: id) }
            return false
        }
        var expected = sample.windows
        if !fresh {
            for step in queue {
                guard let frame = step.frame else { continue }
                expected.removeAll { $0.chat == step.chat }
                expected.append(SnapshotWindow(chat: step.chat, folder: step.folder, title: step.title, frame: frame, screen: ""))
            }
        }
        guard seats.prepareNamedRestore(fresh ? [] : expected) else {
            if let id = id { reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.badRequest.rawValue), for: id) }
            seats.notice("Раскладка не запущена: не удалось сохранить полный снимок окон.")
            return false
        }
        var job = RestoreJob(id: id, name: layout.name, fresh: fresh, queue: queue)
        job.named = true
        job.expected = expected
        job.originalIDs = Set(census.windows.map { $0.id })
        job.allPlacesKnown = queue.allSatisfy { $0.frame != nil }
        launchRestore(job, at: at)
        return true
    }

    /// Начать возврат (гейт 1 WF111): есть окна, спрятанные Пимпом, — сперва их показываем и ждём
    /// конца анимации разворота (тот же срок, что фокус после `show`), потом первый шаг очереди.
    private func launchRestore(_ fresh: RestoreJob, at: Date) {
        guard seats.showHiddenForRestore() else {
            advanceRestore(fresh, at: at)
            return
        }
        var job = fresh
        job.unhideUntil = at.addingTimeInterval(WindowHide.focusDelay)
        restore = job
        seats.schedule(WindowHide.focusDelay) { [weak self] in
            guard let self = self, var current = self.restore, current.unhideUntil != nil else { return }
            current.unhideUntil = nil
            self.advanceRestore(current, at: self.now())
        }
    }

    /// Шаг возврата на тике: сперва досматриваем окно, которого ждём, потом разбираем
    /// очередь, пока не упрёмся в место, ради которого окно надо открыть. Открытые окна
    /// расставляются здесь же — ждать нечего.
    private func advanceRestore(_ current: RestoreJob, at: Date) {
        var job = current
        // Список окон снимаем ОДИН раз на шаг: он же нужен проверке живости, ожиданию окна
        // и поиску уже открытых чатов, а каждый снимок — полный обход Quartz и AX.
        let census = seats.restoreWindows?() ?? (windows: seats.windows(), complete: true)
        let windows = census.windows
        let complete = seats.restoreWindows == nil ? census.complete
            : WindowSnapshotStore.observe(from: windows, complete: census.complete,
                                           isMain: seats.isMainWindow, screen: { _ in "" }).complete
        if !complete {
            job.incompleteSince = job.incompleteSince ?? at
            if at.timeIntervalSince(job.incompleteSince!) >= Self.restoreWindowSeconds {
                job.failed = true
                if let step = job.waiting { job.missing.append(step.title) }
                job.missing += job.queue.map { $0.title }
                job.waiting = nil
                job.queue = []
                finishRestore(job, at: at)
            } else { restore = job; beat(job.id); seats.demandChats?(at) }
            return
        }
        job.incompleteSince = nil
        // Claude закрыли (или его окна пропали) посреди очереди: открывать больше нечем и
        // некому, а канал иначе занят минутами и всем отвечает «занят» (#5730).
        guard seats.claudeRunning(), !windows.isEmpty else {
            job.failed = true
            if !job.fresh {
                if let step = job.waiting { job.missing.append(step.title) }
                job.missing += job.queue.filter { $0.frame != nil }.map { $0.title }
            }
            job.waiting = nil
            job.queue = []
            finishRestore(job, at: at)
            return
        }
        if let until = job.unhideUntil {
            guard at >= until else {
                restore = job
                return
            }
            job.unhideUntil = nil
        }
        if let step = job.waiting {
            if let fresh = windows.first(where: { !job.before.contains($0.id)
                && (self.seats.restoreWindows != nil && !job.fresh
                    ? $0.chat == step.chat : PimpChannel.accepts(step, $0, fresh: job.fresh)) }) {
                if let frame = step.frame {
                    seats.place([PimpMove(id: fresh.id, frame: seats.restoreFrame(frame))])
                    if job.named, job.fresh {
                        let chat = fresh.isMain(using: seats.isMainWindow) ? LayoutsStore.mainChat : fresh.chat
                        if !chat.isEmpty {
                            job.expected.removeAll { $0.chat == chat }
                            job.expected.append(SnapshotWindow(chat: chat, folder: fresh.folder, title: fresh.title, frame: frame, screen: ""))
                        } else { job.failed = true }
                    }
                }
                job.opened += 1
                job.waiting = nil
                beat(job.id)
            } else if at.timeIntervalSince(job.since) >= waitSeconds(job) {
                job.failed = true
                // Окна нет: чат закрыт совсем или страница ответила `chat-missing`. Ячейка
                // остаётся пустой, новый чат вместо старого не заводим (#5455).
                job.waiting = nil
                // У новых чатов старый заголовок не «пропал» — его и не открывали (README WF41).
                if !job.fresh { job.missing.append(step.title) }
                beat(job.id)
            } else {
                restore = job
                return
            }
        }
        while !job.queue.isEmpty {
            let step = job.queue.removeFirst()
            guard let savedFrame = step.frame else {
                // Места у записи не было (окно стояло вне сетки) — возвращать некуда:
                // окно остаётся где стоит, и «пропавшим» его не зовём (verify гейта 2).
                continue
            }
            let frame = seats.restoreFrame(savedFrame)
            // Тот же чат уже на экране — просто ставим окно в ячейку. У «новых чатов»
            // этой ветки нет вовсе: они открываются заново по папкам.
            if !job.fresh, let window = PimpChannel.window(step.chat, in: windows,
                                                           isMain: seats.isMainWindow) {
                seats.place([PimpMove(id: window.id, frame: frame)])
                if job.named, job.originalIDs.contains(window.id) {
                    job.explicitMoves.append(PimpMove(id: window.id, frame: frame))
                }
                job.placed += 1
                beat(job.id)
                continue
            }
            job.before = Set(windows.map { $0.id })
            job.since = at
            job.waiting = step
            if open(step, fresh: job.fresh, frame: frame) {
                restore = job
                return
            }
            // No opener for this saved place: keep the durable baseline protected.
            job.failed = true
            job.waiting = nil
            if !job.fresh { job.missing.append(step.title) }
        }
        finishRestore(job, at: at)
    }

    /// Очередь кончилась: канал свободен, и Элвису говорят итог — запросу ответом, а пункту
    /// меню плашкой (#5689: раньше «↩︎ Вернуть эти чаты» молчал до конца дней).
    private func finishRestore(_ job: RestoreJob, at: Date) {
        restore = nil
        if job.placed > 0 || job.opened > 0 { seats.restoreFinished() }
        if job.named, !job.failed, job.missing.isEmpty {
            if seats.finishNamedRestore(job.expected) {
                if job.allPlacesKnown { seats.explicitNamedLayout(job.explicitMoves) }
            } else { seats.notice("Окна расставлены, но полный снимок сохранён под защитой: запись не удалась.") }
        }
        guard let id = job.id else {
            seats.notice(PimpChannel.restoreNotice(name: job.name, fresh: job.fresh,
                                                   placed: job.placed, opened: job.opened,
                                                   missing: job.missing))
            if job.forRestart, let current = restart, current.stage == .restoring {
                finishRestart(current.id, at: at, placed: job.placed, opened: job.opened,
                              skipped: job.missing)
            }
            return
        }
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.restoreFields(
            name: job.name, placed: job.placed, opened: job.opened, missing: job.missing)), for: id)
    }

    /// Наше ли это новое окно: у «тех же чатов» оно обязано быть чатом ЭТОГО места, иначе
    /// опоздавшее окно прошлого места займёт чужую ячейку (#5691). Чат ещё не опознан (карта
    /// probe молчит) — принимаем, как раньше: другого признака у нас нет.
    private static func accepts(_ step: RestoreStep, _ window: PimpWindow, fresh: Bool) -> Bool {
        guard !fresh, step.chat != LayoutsStore.mainChat else { return true }
        return accepts(chat: step.chat, window)
    }

    /// То же правило для «нового окна» с чатом (план WF75): назван чат — окно обязано быть
    /// его, а чат не назван (обычное «новое окно») — подходит любое новое окно.
    static func accepts(chat: String?, _ window: PimpWindow) -> Bool {
        guard let chat = chat else { return true }
        return window.chat.isEmpty || window.chat == chat
    }

    /// Сколько ждём окно шага: новый чат создаётся долго (сессия и первое сообщение),
    /// вынос уже готового чата — секунды.
    private func waitSeconds(_ job: RestoreJob) -> TimeInterval {
        job.fresh ? PimpChannel.newWindowSeconds : PimpChannel.restoreWindowSeconds
    }

    /// Открыть окно места: «новые чаты» идут тем же путём, что «🪟 Новое окно ▸ проект»,
    /// а «те же чаты» — командой `popout-window` главному окну. false — открывать нечем.
    private func open(_ step: RestoreStep, fresh: Bool, frame: CGRect) -> Bool {
        let origin = (x: Int(frame.minX.rounded()), y: Int(frame.minY.rounded()))
        guard fresh else {
            // Главное окно не открывают заново — оно либо есть на экране, либо его нет.
            guard step.chat != LayoutsStore.mainChat else { return false }
            seats.openChat(step.chat, step.title, origin)
            return true
        }
        guard let project = PimpChannel.project(named: step.folder, in: seats.projects(),
                                                fileManager: fileManager) else { return false }
        seats.openNewWindow(project, origin)
        return true
    }

    /// Сердцебиение долгой работы: CLI считает своё ожидание от времени файла `<id>.taken`,
    /// а возврат раскладки открывает окна по одному и идёт дольше минуты (контракт WF41).
    private func beat(_ id: String?) {
        guard let id = id else { return }
        take(id)
    }

    // MARK: - файлы

    private func result(for id: String) -> URL {
        directory.appendingPathComponent(id + PimpChannel.resultSuffix)
    }

    private func taken(for id: String) -> URL {
        directory.appendingPathComponent(id + PimpChannel.takenSuffix)
    }

    /// Пустая метка «взял в работу»: CLI по ней отличает работающего Пимпа от выключенного.
    private func take(_ id: String) {
        writeSecure(taken(for: id), "")
    }

    private func reply(_ answer: PimpAnswer, for id: String) {
        served += 1
        if !answer.ok { failed += 1 }
        writeSecure(result(for: id), answer.json + "\n")
    }

    /// Файл канала пишется временным рядом и переезжает на место одним `rename`. Права 0600
    /// ставятся ДО переименования (#5558): каталог общий для машины, а в ответах лежат пути
    /// проектов — файла с правами 0644 не должно существовать ни миллисекунды.
    /// Временный файл скрытый (`.<имя>.tmp`) — очередь его не видит, уборка сносит.
    @discardableResult
    private func writeSecure(_ url: URL, _ body: String) -> Bool {
        let tmp = directory
            .appendingPathComponent("." + url.lastPathComponent + PimpChannel.tmpSuffix)
        let data = Data(body.utf8)
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: PimpChannel.filePermissions]
        if !fileManager.createFile(atPath: tmp.path, contents: data, attributes: attributes) {
            // Каталога нет (снесли руками) — заводим его с 0700 и пробуем ещё раз.
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions:
                                                            PimpChannel.directoryPermissions])
            guard fileManager.createFile(atPath: tmp.path, contents: data,
                                         attributes: attributes) else { return false }
        }
        let moved = tmp.withUnsafeFileSystemRepresentation { from -> Bool in
            url.withUnsafeFileSystemRepresentation { to -> Bool in
                guard let from = from, let to = to else { return false }
                return rename(from, to) == 0
            }
        }
        if !moved { try? fileManager.removeItem(at: tmp) }
        return moved
    }

    // MARK: - чистая часть (её же гоняют тесты)

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    static func stampText(_ date: Date) -> String { stamp.string(from: date) }

    /// `at` запроса. Свой формат — как у `command.json`; чужой ISO с долями секунды тоже
    /// читаем (пишет его кто угодно на машине, а отказывать из-за миллисекунд глупо).
    static func date(_ raw: String) -> Date? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if let date = stamp.date(from: clean) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: clean) ?? ISO8601DateFormatter().date(from: clean)
    }

    /// Папка проекта по слову из запроса: абсолютный путь (или `~/…`) — как есть, иначе имя
    /// среди известных папок, сперва точно, потом без учёта регистра. Наугад не открываем:
    /// не нашли — `project-missing` со списком имён, и Элвису скажут, из чего выбирать.
    static func project(named raw: String, in projects: [Project],
                        fileManager: FileManager = .default) -> Project? {
        let wanted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        if wanted.hasPrefix("/") || wanted.hasPrefix("~") {
            let path = NSString(string: wanted).expandingTildeInPath
            let folder = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard ProjectIndex.isDirectory(folder, fileManager) else { return nil }
            return Project(folder: folder, name: folder.lastPathComponent, lastFocusedAt: 0)
        }
        if let exact = projects.first(where: { $0.name == wanted }) { return exact }
        let lower = wanted.lowercased()
        return projects.first { $0.name.lowercased() == lower }
    }

    /// Окно по заголовку: заголовок носят двое (главное окно и безымянный попап зовутся
    /// одинаково) — окна нет, лучше не двигать, чем двигать чужое.
    /// Окно `from` по чату (главный путь: чат окна считает приложение — индекс для главного
    /// окна, карта probe для попапов), затем по заголовку из `titleForChat`.
    static func window(chat: String, title: String?, in windows: [PimpWindow]) -> PimpWindow? {
        let wanted = chat.trimmingCharacters(in: .whitespaces)
        if !wanted.isEmpty {
            let byChat = windows.filter { $0.chat == wanted }
            if byChat.count == 1 { return byChat[0] }
            if byChat.count > 1 || windows.contains(where: { $0.main != nil }) { return nil }
        }
        return title.flatMap { window(title: $0, in: windows) }
    }

    /// Окно `from` в момент расстановки: по номеру Quartz, потом по заголовку.
    static func window(id: CGWindowID?, title: String?, in windows: [PimpWindow]) -> PimpWindow? {
        if let id = id, let found = windows.first(where: { $0.id == id }) { return found }
        return title.flatMap { window(title: $0, in: windows) }
    }

    /// Окно места раскладки (план WF41): главное окно узнаётся резолвером приложения
    /// (`chat:"main"`), остальные — по id чата. Не нашли — окно закрыто.
    static func window(_ chat: String, in windows: [PimpWindow],
                       isMain: (String) -> Bool) -> PimpWindow? {
        guard chat != LayoutsStore.mainChat else {
            let mains = windows.filter { $0.isMain(using: isMain) }
            return mains.count == 1 ? mains[0] : nil
        }
        let wanted = chat.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        let hits = windows.filter { $0.chat == wanted }
        return hits.count == 1 ? hits[0] : nil
    }

    static func window(title: String, in windows: [PimpWindow]) -> PimpWindow? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let found = windows.filter { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == wanted }
        return found.count == 1 ? found[0] : nil
    }

    /// Столбец пополам по высоте: `above` — новое окно сверху, иначе снизу. Половина ниже
    /// порога — не делим вовсе (`too-small`): Electron всё равно не даст такое окно.
    ///
    /// Между половинками — тот же зазор `gap`, что между столбцами (#7062, WF84): до WF84
    /// они вставали встык среди окон с зазорами. Зазор берётся из высоты столбца, края
    /// столбца остаются где были.
    static func split(_ frame: CGRect, above: Bool, minHeight: CGFloat = minSplitHeight,
                      gap: CGFloat = 0) -> (old: CGRect, new: CGRect)? {
        let gap = max(gap, 0)
        let half = ((frame.height - gap) / 2).rounded(.down)
        let rest = frame.height - gap - half
        guard half >= minHeight, rest >= minHeight else { return nil }
        let top = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: half)
        let bottom = CGRect(x: frame.minX, y: frame.minY + half + gap, width: frame.width,
                            height: rest)
        return above ? (old: bottom, new: top) : (old: top, new: bottom)
    }

    static func frameValue(_ frame: CGRect) -> CommandValue {
        .array([.number(Int(frame.minX.rounded())), .number(Int(frame.minY.rounded())),
                .number(Int(frame.width.rounded())), .number(Int(frame.height.rounded()))])
    }

    /// Проект в ответе: имя, папка, когда открывали. `chats` и `state` (план WF41) идут
    /// ПОСЛЕ `lastUsed` и только когда просили сводку — иначе ответ остаётся прежним.
    static func projectValue(_ project: Project, chats: [String]? = nil,
                             state: String? = nil) -> CommandValue {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "name", value: .string(project.name)),
            (key: "folder", value: .string(project.folder.path)),
            (key: "lastUsed", value: .string(stampText(ProjectsStore.date(project.lastFocusedAt)))),
        ]
        if let chats = chats {
            fields.append((key: "chats", value: .array(chats.map { .string($0) })))
        }
        if let state = state { fields.append((key: "state", value: .string(state))) }
        return .object(fields)
    }

    /// Открытые окна проекта для `projects --status`: заголовки окон, чья папка совпала.
    /// Папку окна знает индекс чатов, поэтому неопознанные окна сюда не попадают.
    static func chats(of project: Project, in windows: [PimpWindow]) -> [String] {
        let folder = project.folder.standardizedFileURL.path
        return windows.filter {
            !$0.folder.isEmpty
                && URL(fileURLWithPath: $0.folder, isDirectory: true).standardizedFileURL.path == folder
        }
        .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    /// Сводка проекта — `docs/status.md`, а нет его — `audit/status.md`; нет и его — "".
    static func state(of folder: URL, fileManager: FileManager = .default) -> String {
        for name in statusFolders {
            let url = folder.appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(StatusFeed.statusFileName)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            return state(try? String(contentsOf: url, encoding: .utf8))
        }
        return ""
    }

    /// Где искать сводку проекта (порядок важен: docs сильнее audit).
    static let statusFolders = ["docs", "audit"]
    static let statusCountWord = "воркфлоу"
    static let statusDoneWord = "готово"
    static let statusNowPrefix = "Сейчас:"
    /// Потолок строки `state`: «Сейчас:» пишут свободным текстом, и без него сводка одного
    /// проекта раздувала бы ответ на все девять (#5690).
    static let stateLimit = 120

    /// Строка `state`: два счёта из шапки status.md и строка «Сейчас:» — «41 воркфлоу ·
    /// 27 готово · Сейчас: …». Сводку целиком читает `StatusFeed`, ему тут делать нечего.
    /// Счётом считаем только строку, начинающуюся ОБЫЧНОЙ цифрой: «1️⃣ Workflow ✅ готово»
    /// начинается с цифры-эмодзи и в шапку не лезет.
    static func state(_ markdown: String?) -> String {
        guard let text = markdown, !text.isEmpty else { return "" }
        var counts: [String] = []
        var now = ""
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let head = line.first, head.isASCII, head.isNumber, counts.count < 2,
               line.hasSuffix(statusCountWord) || line.hasSuffix(statusDoneWord) {
                counts.append(line)
            } else if now.isEmpty, line.hasPrefix(statusNowPrefix) {
                now = line
            }
        }
        let line = (counts + (now.isEmpty ? [] : [now])).joined(separator: " · ")
        guard line.count > stateLimit else { return line }
        return line.prefix(stateLimit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Порядок окон для `arrange` с `order` (план WF41): окна названных папок — первыми и
    /// в этом порядке, остальные опознанные — за ними в прежнем порядке, окна без папки —
    /// в хвост. Возвращает порядок индексов, число окон без папки и записи `order`, которым
    /// окна не нашлось (как их прислали: их же называет CLI).
    static func order(of windows: [PimpWindow], by entries: [String],
                      base: [Int]) -> (order: [Int], unknown: Int, missing: [String]) {
        var taken = Set<Int>()
        var first: [Int] = []
        var missing: [String] = []
        for entry in entries {
            let hits = base.filter { !taken.contains($0) && matches(window: windows[$0], entry: entry) }
            guard !hits.isEmpty else {
                missing.append(entry)
                continue
            }
            first += hits
            taken.formUnion(hits)
        }
        let unknown = base.filter { !taken.contains($0) && windows[$0].folder.isEmpty }
        let rest = base.filter { !taken.contains($0) && !windows[$0].folder.isEmpty }
        return (order: first + rest + unknown, unknown: unknown.count, missing: missing)
    }

    /// Запись `order` на части (WF107, #8125): «A+B» — стопка, окна одного столбца сверху вниз; части
    /// обрезаны, пустые выкинуты. Одна функция на все пути: переспрос чатов, `peers` центра, прочие раскладки.
    static func stackParts(_ entry: String) -> [String] {
        entry.split(separator: "+").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Записи `order` плоским списком частей — как если бы части назвали подряд.
    static func flatOrder(_ entries: [String]) -> [String] { entries.flatMap { stackParts($0) } }

    /// Столбцы «главного по центру» по `order` (WF107, К1) — индексы `others` (окна без главного):
    /// названные — в порядке записей, стопка «A+B» — один столбец (часть подошла двум окнам — оба, в
    /// порядке `base`), простая запись — столбец на каждое окно, как раньше; дальше остальные опознанные
    /// и окна без папки — по столбцу. `left` — сколько столбцов названо ДО главного, если он назван
    /// отдельной записью; часть стопки, подошедшая главному, выкидывается. `missing` — части без окна.
    static func centerPlan(of others: [PimpWindow], hub: PimpWindow, by entries: [String], base: [Int])
        -> (columns: [[Int]], left: Int?, unknown: Int, missing: [String]) {
        var taken = Set<Int>()
        var columns: [[Int]] = []
        var missing: [String] = []
        var left: Int?
        for entry in entries {
            let parts = stackParts(entry)
            if left == nil, parts.count == 1, matches(window: hub, entry: parts[0]) {
                left = columns.count
                continue
            }
            var stack: [Int] = []
            for part in parts where !matches(window: hub, entry: part) {
                let hits = base.filter { !taken.contains($0) && matches(window: others[$0], entry: part) }
                guard !hits.isEmpty else {
                    missing.append(part)
                    continue
                }
                taken.formUnion(hits)
                stack += hits
            }
            guard !stack.isEmpty else { continue }
            if parts.count == 1 { columns += stack.map { [$0] } } else { columns.append(stack) }
        }
        let unknown = base.filter { !taken.contains($0) && others[$0].folder.isEmpty }
        let rest = base.filter { !taken.contains($0) && !others[$0].folder.isEmpty }
        return (columns: columns + (rest + unknown).map { [$0] }, left: left, unknown: unknown.count,
                missing: missing)
    }

    /// Окно и запись `order` (WF105, #8071): как `matches(folder:)`, плюс чат окна (`local_…`,
    /// как `center`) и имя проекта с маркером и в другом регистре («🟢 Dictator» → Dictator) —
    /// так проект показывают `windows` и скилл. Только для `order`: отбор окон других экранов
    /// у `center` идёт узким `matches(folder:)` (критик WF105), иначе уедут чужие окна.
    static func matches(window: PimpWindow, entry: String) -> Bool {
        if !window.chat.isEmpty, window.chat == entry { return true }
        if matches(folder: window.folder, entry: entry) { return true }
        let name = projectName(entry)
        guard !window.folder.isEmpty, !name.isEmpty else { return false }
        return URL(fileURLWithPath: window.folder).lastPathComponent.lowercased() == name.lowercased()
    }

    /// Имя проекта из записи `order`: без маркера спереди (эмодзи, пробелы) и краевых пробелов.
    static func projectName(_ entry: String) -> String {
        var name = Substring(entry.trimmingCharacters(in: .whitespacesAndNewlines))
        while let head = name.first, !(head.isLetter || head.isNumber || "/._~-".contains(head)) {
            name = name.dropFirst()
        }
        return String(name).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Папка окна и запись `order`: абсолютный путь целиком или имя папки (контракт WF41).
    static func matches(folder: String, entry: String) -> Bool {
        guard !folder.isEmpty, !entry.isEmpty else { return false }
        return folder == entry || URL(fileURLWithPath: folder).lastPathComponent == entry
    }

    /// Заголовок, по которому окно не адресовать: пустой или заглушка («Claude», «New chat»).
    /// Такое окно `close-window` не закрывает — заглушку носят двое (#5729, #5534).
    static func isStubTitle(_ title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || ProjectIndex.isStub(clean)
    }

    /// Отказ «не знаю, какое окно» (план WF75): в поле `windows` — заголовки тех окон,
    /// между которыми выбирать. Не трогаем ни одного.
    static func ambiguous(id: String, at: Date, windows: [PimpWindow]) -> PimpAnswer {
        PimpAnswer(id: id, at: at, ok: false, error: Failure.ambiguous.rawValue,
                   fields: [(key: "windows", value: .array(windows.map { .string($0.title) }))])
    }

    /// Куда родиться окну выносимого чата (план WF75): точка из запроса, а нет её — уступ
    /// от окна рядом. На место окно всё равно встанет следующим тиком (`finish`).
    static func popoutOrigin(_ place: PimpPlace, near frame: CGRect?) -> (x: Int, y: Int) {
        if case .point(let x, let y) = place { return (x: x, y: y) }
        guard let frame = frame else { return ClaudeActions.popoutWindowFallback }
        return (x: Int((frame.minX + ClaudeActions.popoutWindowOffset).rounded()),
                y: Int((frame.minY + ClaudeActions.popoutWindowOffset).rounded()))
    }

    static func windowsValue(_ windows: [PimpWindow]) -> CommandValue {
        .array(windows.map { windowValue($0) })
    }

    private static func windowValue(_ window: PimpWindow) -> CommandValue {
        .object([
            (key: "title", value: .string(window.title)),
            (key: "chat", value: .string(window.chat)),
            (key: "folder", value: .string(window.folder)),
            (key: "frame", value: frameValue(window.frame)),
        ])
    }

    /// Значение поля `app` у записи ChatGPT (WF94): у окон Claude поля нет вовсе.
    static let chatGPTApp = "chatgpt"

    /// `chatGPT` (WF94) — последней записью `windows` с полем `app` после `frame`
    /// (эталон `windows-chatgpt.result.json`); nil — ответ прежний (`windows.result.json`).
    static func windowsFields(_ windows: [PimpWindow], minimized: Int,
                              chatGPT: PimpWindow? = nil) -> [(key: String, value: CommandValue)] {
        var list = windows.map { windowValue($0) }
        if let chatGPT = chatGPT, case .object(let fields) = windowValue(chatGPT) {
            list.append(.object(fields + [(key: "app", value: .string(chatGPTApp))]))
        }
        return [(key: "windows", value: .array(list)),
                (key: "minimized", value: .number(max(0, minimized)))]
    }

    /// Поля ответа `arrange` (план WF21): раскладка применённая (`last` уже разрешён),
    /// окна — только переставленные, `skipped` — сколько не тронули. Порядок побайтно —
    /// эталон `tests/fixtures/pimp/arrange.result.json`.
    /// `unknown` и `missing` (план WF41) идут ПОСЛЕ `skipped` и только когда в запросе был
    /// `order` — оба разом (эталон `arrange-order.result.json`).
    /// `hub` (WF107) — номер главного в `windows`, сразу после `skipped`; только у «главного по центру».
    static func arrangeFields(_ windows: [PimpWindow], mode: ArrangeLayout.Mode, skipped: Int,
                              hub: Int? = nil, unknown: Int? = nil, missing: [String]? = nil,
                              minimized: Int) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "layout", value: .string(mode.rawValue)),
            (key: "windows", value: windowsValue(windows)),
            (key: "skipped", value: .number(max(0, skipped))),
        ]
        if let hub = hub { fields.append((key: "hub", value: .number(hub))) }
        if let unknown = unknown {
            fields.append((key: "unknown", value: .number(max(0, unknown))))
            fields.append((key: "missing", value: .array((missing ?? []).map { .string($0) })))
        }
        fields.append((key: "minimized", value: .number(max(0, minimized))))
        return fields
    }

    /// Поля ответа `layouts` (план WF41): имя, время, раскладка и сколько в ней мест.
    /// «Мест» — тех, у кого есть номер ячейки: столько окон и вернётся, и ровно это число
    /// назвал `layout-save` при записи (#5728).
    static func layoutsFields(_ list: [WindowLayout]) -> [(key: String, value: CommandValue)] {
        [(key: "layouts", value: .array(list.map { layout in
            .object([
                (key: "name", value: .string(layout.name)),
                (key: "at", value: .string(stampText(layout.at))),
                (key: "mode", value: .string(layout.mode.rawValue)),
                (key: "cells", value: .number(LayoutsStore.placedCells(layout))),
            ])
        }))]
    }

    /// Поля ответа `layout-save`: имя, раскладка, сколько мест записано.
    static func layoutSaveFields(name: String, mode: ArrangeLayout.Mode,
                                 cells: Int) -> [(key: String, value: CommandValue)] {
        [(key: "name", value: .string(name)),
         (key: "mode", value: .string(mode.rawValue)),
         (key: "cells", value: .number(max(0, cells)))]
    }

    /// Плашка «↩︎ Вернуть эти чаты» по концу очереди (#5689): те же слова, что говорит CLI
    /// на ответ канала, — Элвис читает одно и то же и из меню, и из чата.
    static func restoreNotice(name: String, fresh: Bool, placed: Int, opened: Int,
                              missing: [String]) -> String {
        guard !fresh else { return "Открыл новые чаты по раскладке «\(name)»: \(opened)" }
        var line = "Вернул «\(name)»: \(placed) стояло, \(opened) открыл"
        if !missing.isEmpty {
            line += "; не нашёл " + (missing.count == 1 ? "чат: " : "чаты: ")
                + missing.joined(separator: ", ")
        }
        return line
    }

    /// Поле ответа `close-window` (план WF75): заголовок закрытого окна. Чат не удаляется.
    static func closeFields(_ title: String) -> [(key: String, value: CommandValue)] {
        [(key: "closed", value: .string(title))]
    }

    /// Поля ответа `hide` / `show` (WF112): сколько окон свернули (развернули) и их заголовки,
    /// у `hide` — сколько полноэкранных не тронули; `already` — делать было нечего.
    static func hideFields(_ done: WindowHideResult, show: Bool) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: show ? "shown" : "hidden", value: .number(done.titles.count)),
            (key: "windows", value: .array(done.titles.map { .string($0) })),
        ]
        if !show { fields.append((key: "skipped", value: .number(max(0, done.skipped)))) }
        fields.append((key: "already", value: .bool(done.titles.isEmpty)))
        return fields
    }

    /// Поля ответа `paste` (план WF75): сколько файлов положили в буфер (0 — вставили то,
    /// что там уже лежало) и в какое окно нажали ⌘V.
    static func pasteFields(pasted: Int, window: String) -> [(key: String, value: CommandValue)] {
        [(key: "pasted", value: .number(max(0, pasted))),
         (key: "window", value: .string(window))]
    }

    /// Поля ответа `layout-restore`: имя, сколько окон уже стояло, сколько открыли заново
    /// и чьи ячейки остались пустыми.
    static func restoreFields(name: String, placed: Int, opened: Int,
                              missing: [String]) -> [(key: String, value: CommandValue)] {
        [(key: "name", value: .string(name)),
         (key: "placed", value: .number(max(0, placed))),
         (key: "opened", value: .number(max(0, opened))),
         (key: "missing", value: .array(missing.map { .string($0) }))]
    }
}

extension PimpRequest {
    /// Разбор запроса. Битый JSON, чужое `action`, пустой `id` или нечитаемое `at` — nil,
    /// и канал отвечает `bad-request`: молчать нельзя, CLI ждёт ответ.
    static func parse(_ data: Data?) -> PimpRequest? {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (root["id"] as? String)?.trimmingCharacters(in: .whitespaces), !id.isEmpty,
              let at = (root["at"] as? String).flatMap(PimpChannel.date),
              let action = (root["action"] as? String).flatMap(Action.init(rawValue:))
        else { return nil }
        let from = (root["from"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let project = (root["project"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Папка — единственное, без чего «новое окно» бессмысленно. «Закрой окно проекта»
        // без неё тоже: закрывать наугад нечего (контракт WF75).
        if action == .newWindow || action == .closeWindow, project.isEmpty { return nil }
        // `place` разбирает только «новое окно», `layout` — только «расставить» (#5682):
        // чужое слово в поле, которое к этому действию не относится, роняло весь запрос в
        // `bad-request`. У остальных действий — умолчания, их всё равно никто не читает.
        var place = PimpPlace.right
        var chat = ""
        if action == .newWindow {
            guard let parsed = PimpRequest.place(root["place"] as? String) else { return nil }
            place = parsed
            // Ключ `chat` (WF75) знает одно слово — `last`. Чужое значит, что нас просят
            // не о том, и открывать наугад чужой чат нельзя.
            let wanted = (root["chat"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if !wanted.isEmpty {
                guard wanted == PimpChannel.lastChatKey else { return nil }
                chat = wanted
            }
        }
        // «Вставить» (WF75): пути только абсолютные и не больше двадцати — остальное
        // `bad-request`, и ничего не нажимаем. Чего нет на диске, проверяет уже канал.
        var front = false
        var paths: [String] = []
        if action == .paste {
            front = root["front"] as? Bool ?? false
            if let raw = root["paths"] {
                guard let list = raw as? [String], list.count <= PimpChannel.pasteLimit
                else { return nil }
                let clean = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard clean.allSatisfy({ $0.hasPrefix("/") }) else { return nil }
                paths = clean
            }
        }
        // Плашка без слов бессмысленна, а длинную обрезаем: на экране всё равно строка.
        var text = ""
        if action == .hud {
            let raw = (root["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return nil }
            text = String(raw.prefix(PimpChannel.hudTextLimit))
        }
        // Замена окна (WF102, C7): ровно одно из `chat` (`local_<uuid>`) или `project`; текст —
        // без обрезки, но не длиннее потолка; эффорт — только слова ползунка.
        var model = ""
        var effort = ""
        if action == .renewWindow {
            let wanted = (root["chat"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard wanted.isEmpty != project.isEmpty else { return nil }
            if !wanted.isEmpty {
                guard PimpRequest.isChatID(wanted) else { return nil }
                chat = wanted
            }
            if let raw = root["text"] {
                guard let body = raw as? String, body.count <= PimpChannel.renewTextLimit
                else { return nil }
                text = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : body
            }
            if let raw = root["model"] {
                guard let label = raw as? String else { return nil }
                model = label.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                guard model.count <= PimpChannel.renewModelLimit else { return nil }
            }
            if let raw = root["effort"] {
                guard let step = raw as? String else { return nil }
                effort = step.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard effort.isEmpty || PimpChannel.renewEfforts.contains(effort) else { return nil }
            }
        }
        // «Отправь текст в чат» (WF103): ровно одно из `chat` (`local_<uuid>`) или `project`;
        // текст 1…8000 знаков без `\0`, как есть — его отправят.
        if action == .send {
            let wanted = (root["chat"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard wanted.isEmpty != project.isEmpty else { return nil }
            if !wanted.isEmpty {
                guard PimpRequest.isChatID(wanted) else { return nil }
                chat = wanted
            }
            guard let body = root["text"] as? String, !body.isEmpty,
                  body.unicodeScalars.count <= PimpChannel.sendTextLimit,
                  !body.unicodeScalars.contains("\u{0}") else { return nil }
            text = body
        }
        // «Чат в главное окно» (WF108, #8148): ровно одно из `chat` (`local_<uuid>`) или `project`.
        if action == .main {
            let wanted = (root["chat"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard wanted.isEmpty != project.isEmpty else { return nil }
            if !wanted.isEmpty {
                guard PimpRequest.isChatID(wanted) else { return nil }
                chat = wanted
            }
        }
        // Раскладка (WF21): `last` — nil, то есть умная расстановка (план WF77); туда же
        // идёт запрос БЕЗ поля `layout` — умолчание CLI и так `last`, а руками пишут
        // по-разному. Чужое слово — `bad-request`: наугад окна не двигаем.
        var layout: ArrangeLayout.Mode? = .ribbon
        if action == .arrange {
            let raw = (root["layout"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if raw.isEmpty || raw == "last" {
                layout = nil
            } else {
                guard let mode = ArrangeLayout.Mode(rawValue: raw) else { return nil }
                layout = mode
            }
        }
        // Порядок проектов (план WF41): список папок — путями или именами. Поля нет (или
        // в нём нет ни одной годной строки) — nil, и ответ `arrange` остаётся прежним.
        let entries = (root["order"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let name = (root["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // «Главный по центру» (WF102): кто главный — только у `arrange`.
        let center = action == .arrange
            ? (root["center"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" : ""
        // Раскладку без имени ни записать, ни найти — это `bad-request`.
        if action == .layoutSave || action == .layoutRestore, name.isEmpty { return nil }
        // Притемнение (WF113): `on` обязателен, сила — дробь 0.2…0.8; чужое — `bad-request`, ничего не меняем.
        var level: Int?
        if action == .dim {
            guard PimpRequest.isFlag(root["on"]) else { return nil }
            if let raw = root["level"] {
                guard let number = raw as? NSNumber, !PimpRequest.isFlag(raw),
                      number.doubleValue.isFinite, (0.2...0.8).contains(number.doubleValue) else { return nil }
                let percent = Int((number.doubleValue * 100).rounded())
                guard (DimSetting.minPercent...DimSetting.maxPercent).contains(percent) else { return nil }
                level = percent
            }
        }
        // Ракета (WF114): вид из восьми (`SendLook.styles`), размер 60…200 или прибавка до ±200 — не оба сразу; `show` — булево.
        var style = ""
        var size: Int?
        var grow: Int?
        if action == .look {
            if let raw = root["style"] {
                guard let word = raw as? String, SendLook.isStyle(word) else { return nil }
                style = word
            }
            func whole(_ key: String, _ range: ClosedRange<Int>) -> Int?? {
                guard let raw = root[key] else { return .some(nil) }
                guard let number = raw as? NSNumber, !PimpRequest.isFlag(raw),
                      let value = Int(exactly: number.doubleValue), range.contains(value) else { return nil }
                return .some(value)
            }
            guard let asked = whole("size", SendLook.minSize...SendLook.maxSize),
                  let more = whole("grow", -SendLook.maxSize...SendLook.maxSize),
                  asked == nil || more == nil else { return nil }
            if let raw = root["show"], !PimpRequest.isFlag(raw) { return nil }
            size = asked
            grow = more
        }
        var request = PimpRequest(id: id, at: at, action: action, from: from, project: project,
                           place: place, chat: chat, layout: layout,
                           order: entries.isEmpty ? nil : entries,
                           name: name, fresh: root["fresh"] as? Bool ?? false,
                           status: root["status"] as? Bool ?? false,
                           front: front, paths: paths, text: text,
                           center: center, model: model, effort: effort,
                           force: action == .restartClaude && root["force"] as? Bool ?? false)
        request.on = action == .dim && root["on"] as? Bool == true
        request.level = level
        request.style = style
        request.size = size
        request.grow = grow
        request.show = action == .look && root["show"] as? Bool == true
        return request
    }

    /// JSON-булево, а не число: `NSNumber` из `JSONSerialization` у 0 и 1 тоже отдаётся как `Bool`.
    static func isFlag(_ raw: Any?) -> Bool {
        guard let number = raw as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// `chat` у `renew-window`: `local_` и uuid строчными (36 знаков из 0-9a-f и «-»).
    static func isChatID(_ raw: String) -> Bool {
        let prefix = "local_"
        guard raw.hasPrefix(prefix) else { return false }
        let tail = raw.dropFirst(prefix.count)
        return tail.count == 36 && tail.allSatisfy { "0123456789abcdef-".contains($0) }
    }

    /// `place` запроса; поля нет или оно пустое — «справа» (умолчание CLI). Чужое слово —
    /// nil, то есть `bad-request`: наугад окно не ставим.
    static func place(_ raw: String?) -> PimpPlace? {
        let clean = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case "", "right": return .right
        case "left": return .left
        case "middle": return .middle
        case "below": return .below
        case "above": return .above
        default: break
        }
        let parts = clean.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]),
              x.isFinite, y.isFinite else { return nil }
        return .point(x: Int(x.rounded()), y: Int(y.rounded()))
    }
}
