import CoreGraphics
import Foundation

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

    init(id: CGWindowID, title: String, chat: String = "", folder: String = "",
         frame: CGRect = .zero) {
        self.id = id
        self.title = title
        self.chat = chat
        self.folder = folder
        self.frame = frame
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
        /// Раскладки проектов (план WF41): список, запомнить, вернуть.
        case layouts
        case layoutSave = "layout-save"
        case layoutRestore = "layout-restore"
        /// Голосовой Пимп (план WF75): закрыть окно проекта, вставить в окно, сказать плашкой.
        case closeWindow = "close-window"
        case paste, hud
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
    /// поля нет — "", чужое значение — `bad-request`.
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
    /// Только `hud`: текст плашки (1…200 знаков, длиннее — обрезан разбором).
    let text: String
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
    var arrange: ([CGWindowID], ArrangeLayout.Mode) -> (windows: [PimpWindow], skipped: Int)
        = { _, _ in ([], 0) }
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
}

/// Канал «Пимп» (план WF36, задача #5531): окна Claude из любого чата — файлами, без клавиатуры.
///
/// Каталог `~/Library/Application Support/MyClaude/pimp/` рядом с `command.json`. Запрос —
/// файл `<id>.json`, взятие в работу — пустой `<id>.taken`, ответ — `<id>.result.json`.
/// Правда об исполнении лежит на диске, а не в памяти процесса: перезапуск приложения на
/// гейте ничего не теряет и ничего не повторяет — у сделанного запроса уже есть ответ.
///
/// Тикает на общем таймере 2 с (`ClaudeAXController`), своего не заводит. Исполняет по одному:
/// пока идёт «новое окно» (до 40 с — страница ждёт `/epitaxy`, шлёт первое сообщение и выносит
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
    /// Сколько ждём НОВОЕ окно Claude.
    static let newWindowSeconds: TimeInterval = 40
    /// Сколько ждём окно чата, вынесенного «Вернуть эти чаты» (план WF41): страница зовёт
    /// `openPopout` сразу, а запасной путь через строку сайдбара — секунды. Новые чаты
    /// (`fresh`) ждут своё прежнее время: там создаётся сессия и уходит первое сообщение.
    static let restoreWindowSeconds: TimeInterval = 15
    /// Файлы канала старше часа убираем.
    static let keepSeconds: TimeInterval = 3600
    /// Не чаще раза в минуту.
    static let cleanupInterval: TimeInterval = 60
    /// Расставляем на том экране, где стоят окна Claude (`Screens.usableFrame(holding:)`),
    /// — так и говорим в ответе. До 08.09 тут стояло «main», и это была неправда (#5732).
    static let screen = "windows"
    /// Ниже этой высоты столбец пополам не делится (`too-small`).
    static let minSplitHeight: CGFloat = 360
    /// Права файлов канала: каталог общий, а в запросах лежат пути проектов.
    static let filePermissions: NSNumber = 0o600
    static let directoryPermissions: NSNumber = 0o700
    /// Сколько файлов разом берёт `paste` (контракт WF75): больше — `bad-request`.
    static let pasteLimit = 20
    /// Потолок текста плашки `hud`: длиннее — обрезаем, пусто — `bad-request`.
    static let hudTextLimit = 200
    /// Единственное значение ключа `chat` у «нового окна» (контракт WF75).
    static let lastChatKey = "last"

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
    }

    /// Идущее «новое окно»: канал занят, пока не появится окно или не выйдут 40 с.
    private struct Job {
        let id: String
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
    private var cleanedAt: Date?
    private(set) var served = 0
    private(set) var failed = 0

    /// Канал занят: работа всегда одна — «новое окно» или возврат раскладки.
    private var isBusy: Bool { job != nil || restore != nil }

    /// Запрос, который сейчас исполняется; nil — канал свободен или работу начали из меню.
    private var busyID: String? {
        if let job = job { return job.id }
        if let restore = restore { return restore.id }
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
            let data = try? Data(contentsOf: url)
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
        // Плашка ушла веткой выше — сюда попасть не может.
        case .hud: break
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
    /// честный пустой список плюс счётчик свёрнутых (CLI так и говорит).
    private func runWindows(id: String, at: Date) {
        guard seats.claudeRunning() else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let windows = seats.windows()
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.windowsFields(
            windows, minimized: seats.minimized())), for: id)
    }

    /// «Расставить». Голая просьба (`layout: "last"` или поля нет) идёт УМНЫМ путём
    /// (план WF77): плитка не читается и не пишется, `fitsLayout` и `too-small` не
    /// зовутся вовсе (критик блокеры 2 и 3) — сетку выбирает то, как окна стоят сейчас.
    /// Названная плитка (`4|5|5x2|row`) работает по-прежнему: порядок по текущим рамкам,
    /// ячейка уже `minWindowWidth` — `too-small`, такие окна Electron всё равно не сделает.
    private func runArrange(_ request: PimpRequest, id: String, at: Date) {
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let base = ArrangeLayout.order(of: windows.map { $0.frame })
        // Порядок по проектам (план WF41): просили — окна названных папок идут первыми,
        // не просили — прежний порядок по рамкам и ответ без `unknown`/`missing`.
        let sorted = request.order.map { PimpChannel.order(of: windows, by: $0, base: base) }
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
        let placed = seats.arrange(ids, mode)
        // Не переставили ни одного окна (окна закрылись между снимком и расстановкой, экрана
        // не нашлось): подставлять сюда ВСЕ окна и говорить «Расставил N окон» — неправда,
        // их никто не двигал (#5680).
        guard !placed.windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.arrangeFields(
            placed.windows, mode: mode,
            skipped: placed.skipped, unknown: sorted?.unknown, missing: sorted?.missing,
            minimized: seats.minimized())), for: id)
    }

    /// «Новое окно в проекте»: находим папку, зовём тот же путь, что пункт меню, и ждём
    /// НОВОЕ окно (не по имени: переименование чата может не удаться, риск 1 плана).
    private func runNewWindow(_ request: PimpRequest, id: String, at: Date) {
        let windows = seats.windows()
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
        if !request.chat.isEmpty {
            runLastChat(project: project, place: place, from: fromWindow, fromTitle: fromTitle,
                        resolved: resolved, windows: windows, id: id, at: at)
            return
        }
        var origin: (x: Int, y: Int)?
        if case .point(let x, let y) = place { origin = (x: x, y: y) }
        job = Job(id: id, place: place, fromId: fromWindow?.id, fromTitle: fromTitle,
                  fromResolved: resolved, before: Set(windows.map { $0.id }), startedAt: at)
        seats.openNewWindow(project, origin)
    }

    /// `new-window` + `chat:"last"` (контракт WF75): последний чат папки берёт ИНДЕКС чатов
    /// Claude, а не карта probe — она знает только те чаты, что уже открыты окнами (критик Б1).
    /// Чат на экране — окно поднимается и встаёт на место, `opened:false`; закрыт — выносится
    /// тем же путём, что «↩︎ Вернуть эти чаты» (`openChat` → `popout-window` главному окну),
    /// и ждём окно ИМЕННО ЭТОГО чата 15 с.
    private func runLastChat(project: Project, place: PimpPlace, from: PimpWindow?,
                             fromTitle: String?, resolved: Bool, windows: [PimpWindow],
                             id: String, at: Date) {
        guard let last = seats.lastChat(project.folder) else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.chatMissing.rawValue,
                             fromResolved: resolved), for: id)
            return
        }
        if let open = windows.first(where: { $0.chat == last.chat }) {
            seats.raise(open.id)
            finish(Job(id: id, place: place, fromId: from?.id, fromTitle: fromTitle,
                       fromResolved: resolved, before: [], startedAt: at, chat: last.chat),
                   window: open, windows: windows, at: at)
            return
        }
        // Выносит чат отдельным окном только ГЛАВНОЕ окно Claude — без него открывать нечем.
        guard windows.contains(where: { seats.isMainWindow($0.title) }) else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.windowMissing.rawValue,
                             fromResolved: resolved), for: id)
            return
        }
        job = Job(id: id, place: place, fromId: from?.id, fromTitle: fromTitle,
                  fromResolved: resolved, before: Set(windows.map { $0.id }), startedAt: at,
                  chat: last.chat, opened: true)
        seats.openChat(last.chat, last.title,
                       PimpChannel.popoutOrigin(place, near: from?.frame ?? windows.first?.frame))
    }

    /// Тик, пока идёт «новое окно»: появилось — ставим на место и отвечаем, вышли 40 с —
    /// `window-missing` (чат при этом создан; так и говорит CLI).
    private func advance(_ current: Job, at: Date) {
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
        guard at.timeIntervalSince(current.startedAt) >= waitSeconds(current) else { return }
        job = nil
        reply(PimpAnswer(id: current.id, at: at, ok: false, error: Failure.windowMissing.rawValue,
                         fromResolved: current.fromResolved), for: current.id)
    }

    private func finish(_ current: Job, window: PimpWindow, windows: [PimpWindow], at: Date) {
        var job = current
        var frame = window.frame
        var failure: Failure?
        // Новому окну не досталось ячейки (в последней раскладке их меньше, чем окон):
        // оно остаётся где родилось, и об этом честно говорит поле `skipped` (план WF21).
        var skipped = 0
        switch job.place {
        case .point:
            // Точку поставила сама страница — двигать нечего.
            break
        case .left, .middle, .right:
            if let placed = row(job.place, window: window, in: windows) {
                frame = placed
            } else {
                skipped = 1
            }
        case .below, .above:
            // Окно `from` могло закрыться, пока шли 40 с, — тогда «под этим» вырождается
            // в «справа», ровно как при неизвестном чате, и это видно по `fromResolved`.
            guard let target = PimpChannel.window(id: job.fromId, title: job.fromTitle, in: windows),
                  target.id != window.id else {
                job.fromResolved = false
                if let placed = row(.right, window: window, in: windows) {
                    frame = placed
                } else {
                    skipped = 1
                }
                break
            }
            guard let halves = PimpChannel.split(target.frame, above: job.place == .above) else {
                failure = .tooSmall
                break
            }
            seats.place([PimpMove(id: target.id, frame: halves.old),
                         PimpMove(id: window.id, frame: halves.new)])
            frame = halves.new
        }
        if let failure = failure {
            reply(PimpAnswer(id: job.id, at: at, ok: false, error: failure.rawValue,
                             fromResolved: job.fromResolved), for: job.id)
            return
        }
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
        reply(PimpAnswer(id: job.id, at: at, ok: true, fromResolved: job.fromResolved,
                         fields: fields), for: job.id)
    }

    /// Сколько ждём окно «нового окна»: новый чат создаётся долго (сессия и первое сообщение),
    /// вынос уже готового чата — секунды (контракт WF75).
    private func waitSeconds(_ job: Job) -> TimeInterval {
        job.chat == nil ? PimpChannel.newWindowSeconds : PimpChannel.restoreWindowSeconds
    }

    /// Поставить новое окно столбцом (план WF77 — умным путём). «Справа» и умолчание:
    /// новое окно просто неприкаянное, ячейку оно займёт само, а окна, стоящие на месте,
    /// не двинутся. «Слева» и «посередине» называют место — там порядок НАВЯЗАН, и окна
    /// кладутся подряд. Возвращает рамку нового окна; ячейки не нашлось (окон больше, чем
    /// мест на экране) — nil, и окно остаётся где родилось.
    private func row(_ place: PimpPlace, window: PimpWindow, in windows: [PimpWindow]) -> CGRect? {
        let others = windows.indices.filter { windows[$0].id != window.id }
        let order = ArrangeLayout.order(of: others.map { windows[$0].frame })
        guard place == .left || place == .middle else {
            let ids = order.map { windows[others[$0]].id } + [window.id]
            return seats.arrangeSmart(ids, false, nil).first { $0.id == window.id }?.frame
        }
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
        let mine = windows.filter { PimpChannel.matches(folder: $0.folder, entry: request.project) }
        let mains = mine.filter { seats.isMainWindow($0.title) }
        // Главным приложение может назвать ДВА окна разом: заглушку «Claude» носит и
        // безымянный попап, а окно без AX-заголовка зовётся главным всегда (#5729, #5534).
        // Тогда не трогаем ничего — иначе под кнопку попало бы окно Элвиса.
        guard mains.count < 2 else {
            reply(PimpChannel.ambiguous(id: id, at: at, windows: mains), for: id)
            return
        }
        // Окно с пустым заголовком или заглушкой из кандидатов выбывает по той же причине:
        // по такому заголовку окно не опознать, а закрываем мы навсегда.
        let candidates = mine.filter {
            !seats.isMainWindow($0.title) && !PimpChannel.isStubTitle($0.title)
        }
        guard candidates.count < 2 else {
            reply(PimpChannel.ambiguous(id: id, at: at, windows: candidates), for: id)
            return
        }
        guard let target = candidates.first else {
            // Кандидатов нет, а окно проекта было главным — так и говорим: его не закрываем.
            reply(PimpAnswer(id: id, at: at, ok: false,
                             error: (mains.isEmpty ? Failure.windowMissing : .mainWindow).rawValue),
                  for: id)
            return
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
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let mode = seats.arrangeMode()
        let snapshot = LayoutsStore.snapshot(
            name: request.name, at: at, mode: mode, windows: windows,
            cells: seats.cells(mode, ArrangeLayout.capacity(of: mode) ?? windows.count),
            isMain: seats.isMainWindow)
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
        guard seats.claudeRunning(), !seats.windows().isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        begin(layout, fresh: request.fresh, id: id, at: at)
    }

    /// «↩︎ Вернуть эти чаты» из меню (план WF41, решение Р5): та же очередь, что у канала,
    /// только отвечать некому — результат виден окнами на экране. Канал занят — не начинаем.
    @discardableResult
    func startRestore(_ layout: WindowLayout, fresh: Bool) -> Bool {
        guard !isBusy, seats.claudeRunning(), !seats.windows().isEmpty else { return false }
        begin(layout, fresh: fresh, id: nil, at: now())
        return true
    }

    /// Очередь мест: сперва те, у кого есть ячейка, по возрастанию её номера; записи без
    /// ячейки — в хвост (вернуть их некуда, и они честно уходят в `missing`).
    private func begin(_ layout: WindowLayout, fresh: Bool, id: String?, at: Date) {
        let top = (layout.cells.compactMap { $0.cell }.max()).map { $0 + 1 } ?? 0
        // Мест столько же, сколько было окон при записи (запись — на каждое окно): у ЛЕНТЫ
        // ширина ячейки зависит от их числа, и раскладка с окном вне сетки вернулась бы
        // половинами вместо третей (#5688). У сеток число мест ничего не меняет.
        let count = max(top, layout.cells.count)
        let frames = count > 0 ? seats.cells(layout.mode, count) : []
        let queue = layout.cells
            .sorted { ($0.cell ?? Int.max) < ($1.cell ?? Int.max) }
            .map { record -> RestoreStep in
                let frame = record.cell.flatMap { frames.indices.contains($0) ? frames[$0] : nil }
                return RestoreStep(chat: record.chat, folder: record.folder,
                                   title: record.title, frame: frame)
            }
        advanceRestore(RestoreJob(id: id, name: layout.name, fresh: fresh, queue: queue), at: at)
    }

    /// Шаг возврата на тике: сперва досматриваем окно, которого ждём, потом разбираем
    /// очередь, пока не упрёмся в место, ради которого окно надо открыть. Открытые окна
    /// расставляются здесь же — ждать нечего.
    private func advanceRestore(_ current: RestoreJob, at: Date) {
        var job = current
        // Список окон снимаем ОДИН раз на шаг: он же нужен проверке живости, ожиданию окна
        // и поиску уже открытых чатов, а каждый снимок — полный обход Quartz и AX.
        let windows = seats.windows()
        // Claude закрыли (или его окна пропали) посреди очереди: открывать больше нечем и
        // некому, а канал иначе занят минутами и всем отвечает «занят» (#5730).
        guard seats.claudeRunning(), !windows.isEmpty else {
            if !job.fresh {
                if let step = job.waiting { job.missing.append(step.title) }
                job.missing += job.queue.filter { $0.frame != nil }.map { $0.title }
            }
            job.waiting = nil
            job.queue = []
            finishRestore(job, at: at)
            return
        }
        if let step = job.waiting {
            if let fresh = windows.first(where: { !job.before.contains($0.id)
                && PimpChannel.accepts(step, $0, fresh: job.fresh) }) {
                if let frame = step.frame { seats.place([PimpMove(id: fresh.id, frame: frame)]) }
                job.opened += 1
                job.waiting = nil
                beat(job.id)
            } else if at.timeIntervalSince(job.since) >= waitSeconds(job) {
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
            guard let frame = step.frame else {
                // Места у записи не было (окно стояло вне сетки) — возвращать некуда:
                // окно остаётся где стоит, и «пропавшим» его не зовём (verify гейта 2).
                continue
            }
            // Тот же чат уже на экране — просто ставим окно в ячейку. У «новых чатов»
            // этой ветки нет вовсе: они открываются заново по папкам.
            if !job.fresh, let window = PimpChannel.window(step.chat, in: windows,
                                                           isMain: seats.isMainWindow) {
                seats.place([PimpMove(id: window.id, frame: frame)])
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
            // Открывать нечем: папки нет на диске (новые чаты) или это главное окно,
            // которого на экране не нашлось. Ячейка остаётся пустой.
            job.waiting = nil
            if !job.fresh { job.missing.append(step.title) }
        }
        finishRestore(job, at: at)
    }

    /// Очередь кончилась: канал свободен, и Элвису говорят итог — запросу ответом, а пункту
    /// меню плашкой (#5689: раньше «↩︎ Вернуть эти чаты» молчал до конца дней).
    private func finishRestore(_ job: RestoreJob, at: Date) {
        restore = nil
        guard let id = job.id else {
            seats.notice(PimpChannel.restoreNotice(name: job.name, fresh: job.fresh,
                                                   placed: job.placed, opened: job.opened,
                                                   missing: job.missing))
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
        guard chat != LayoutsStore.mainChat else { return windows.first { isMain($0.title) } }
        let wanted = chat.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        return windows.first { $0.chat == wanted }
    }

    static func window(title: String, in windows: [PimpWindow]) -> PimpWindow? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let found = windows.filter { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == wanted }
        return found.count == 1 ? found[0] : nil
    }

    /// Столбец пополам по высоте: `above` — новое окно сверху, иначе снизу. Половина ниже
    /// порога — не делим вовсе (`too-small`): Electron всё равно не даст такое окно.
    static func split(_ frame: CGRect, above: Bool,
                      minHeight: CGFloat = minSplitHeight) -> (old: CGRect, new: CGRect)? {
        let half = (frame.height / 2).rounded(.down)
        guard half >= minHeight, frame.height - half >= minHeight else { return nil }
        let top = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: half)
        let bottom = CGRect(x: frame.minX, y: frame.minY + half, width: frame.width,
                            height: frame.height - half)
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
            let hits = base.filter { !taken.contains($0) && matches(folder: windows[$0].folder,
                                                                    entry: entry) }
            guard !hits.isEmpty else {
                missing.append(entry)
                continue
            }
            first += hits
            taken.formUnion(hits)
        }
        let unknown = base.filter { windows[$0].folder.isEmpty }
        let rest = base.filter { !taken.contains($0) && !windows[$0].folder.isEmpty }
        return (order: first + rest + unknown, unknown: unknown.count, missing: missing)
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
        .array(windows.map { window in
            .object([
                (key: "title", value: .string(window.title)),
                (key: "chat", value: .string(window.chat)),
                (key: "folder", value: .string(window.folder)),
                (key: "frame", value: frameValue(window.frame)),
            ])
        })
    }

    static func windowsFields(_ windows: [PimpWindow],
                              minimized: Int) -> [(key: String, value: CommandValue)] {
        [(key: "windows", value: windowsValue(windows)),
         (key: "minimized", value: .number(max(0, minimized)))]
    }

    /// Поля ответа `arrange` (план WF21): раскладка применённая (`last` уже разрешён),
    /// окна — только переставленные, `skipped` — сколько не тронули. Порядок побайтно —
    /// эталон `tests/fixtures/pimp/arrange.result.json`.
    /// `unknown` и `missing` (план WF41) идут ПОСЛЕ `skipped` и только когда в запросе был
    /// `order` — оба разом (эталон `arrange-order.result.json`).
    static func arrangeFields(_ windows: [PimpWindow], mode: ArrangeLayout.Mode, skipped: Int,
                              unknown: Int? = nil, missing: [String]? = nil,
                              minimized: Int) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [
            (key: "layout", value: .string(mode.rawValue)),
            (key: "windows", value: windowsValue(windows)),
            (key: "skipped", value: .number(max(0, skipped))),
        ]
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
        // Раскладку без имени ни записать, ни найти — это `bad-request`.
        if action == .layoutSave || action == .layoutRestore, name.isEmpty { return nil }
        return PimpRequest(id: id, at: at, action: action, from: from, project: project,
                           place: place, chat: chat, layout: layout,
                           order: entries.isEmpty ? nil : entries,
                           name: name, fresh: root["fresh"] as? Bool ?? false,
                           status: root["status"] as? Bool ?? false,
                           front: front, paths: paths, text: text)
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
