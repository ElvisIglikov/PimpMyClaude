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
    enum Action: String { case newWindow = "new-window", arrange, projects, windows }

    let id: String
    /// Когда запрос написан: старше 30 с — «stale», исполнять поздно.
    let at: Date
    let action: Action
    /// id чата, из которого позвали (`local_…`) или "" — переменной у субагента нет.
    let from: String
    /// Имя папки или абсолютный путь (только `new-window`).
    let project: String
    /// Только `new-window`; поля нет — «справа».
    let place: PimpPlace
}

/// Ответ канала: `<id>.result.json` рядом с запросом. Порядок ключей побайтно —
/// id, at, ok, error, fromResolved, screen, затем поля действия (README фикстур).
struct PimpAnswer {
    let id: String
    let at: Date
    let ok: Bool
    let error: String
    /// Нашли ли окно чата `from`. Только `new-window` его ищет — остальным действиям
    /// окно-источник не нужно, и у них всегда `false` (как в эталонах).
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
    /// Расставить окна в этом порядке; возвращает окна с рамками, которые им поставили.
    var arrange: ([CGWindowID]) -> [PimpWindow] = { _ in [] }
    /// Поставить окна по рамкам (деление столбца пополам).
    var place: ([PimpMove]) -> Void = { _ in }
    /// Заголовок окна чата `from`: главное окно — по индексу Claude, попап — по карте probe.
    var titleForChat: (String) -> String? = { _ in nil }
    /// Ушли ли слои (цвет) с последней командой «новое окно» — поле `layers` ответа.
    var newWindowLayers: () -> Bool = { false }
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
    /// Запрос старше — не исполняем (`stale`).
    static let freshSeconds: TimeInterval = 30
    /// Сколько ждём НОВОЕ окно Claude.
    static let newWindowSeconds: TimeInterval = 40
    /// Файлы канала старше часа убираем.
    static let keepSeconds: TimeInterval = 3600
    /// Не чаще раза в минуту.
    static let cleanupInterval: TimeInterval = 60
    /// Расставляем на главном экране — так и говорим в ответе.
    static let screen = "main"
    /// Ниже этой высоты столбец пополам не делится (`too-small`).
    static let minSplitHeight: CGFloat = 360
    /// Права файлов канала: каталог общий, а в запросах лежат пути проектов.
    static let filePermissions: NSNumber = 0o600
    static let directoryPermissions: NSNumber = 0o700

    /// Ошибки контракта (их же знает `tools/pimp.py`).
    enum Failure: String {
        case stale, busy
        case noWindows = "no-windows"
        case badRequest = "bad-request"
        case projectMissing = "project-missing"
        case windowMissing = "window-missing"
        case tooSmall = "too-small"
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
    private var cleanedAt: Date?
    private(set) var served = 0
    private(set) var failed = 0

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
    }

    // MARK: - тик

    /// Общий тик 2 с. Сперва доводим до конца «новое окно», потом отвечаем всем остальным:
    /// пока оно идёт, каждому — `busy` (ждать в очереди нечего, Элвис уже говорит дальше).
    func tick() {
        let at = now()
        cleanup(at)
        if let current = job { advance(current, at: at) }
        for incoming in pending() {
            if let current = job, current.id == incoming.id { continue }
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
            guard job?.id == id || !fileManager.fileExists(atPath: taken(for: id).path) else {
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

    /// Файлы канала старше часа — прибрать (проверяем не чаще раза в минуту).
    private func cleanup(_ at: Date) {
        if let last = cleanedAt, at.timeIntervalSince(last) < PimpChannel.cleanupInterval { return }
        cleanedAt = at
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(PimpChannel.requestSuffix)
            || name.hasSuffix(PimpChannel.takenSuffix) {
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
        guard job == nil else {
            reply(PimpAnswer(id: incoming.id, at: at, ok: false, error: Failure.busy.rawValue),
                  for: incoming.id)
            return
        }
        // Метка «взял в работу»: по ней CLI отличает молчащего Пимпа от долгой работы.
        take(incoming.id)
        switch request.action {
        case .projects: runProjects(id: incoming.id, at: at)
        case .windows: runWindows(id: incoming.id, at: at)
        case .arrange: runArrange(id: incoming.id, at: at)
        case .newWindow: runNewWindow(request, id: incoming.id, at: at)
        }
    }

    /// Список проектов Claude знать не обязан — он лежит в нашем файле.
    private func runProjects(id: String, at: Date) {
        let list = seats.projects()
        reply(PimpAnswer(id: id, at: at, ok: true, fields: [
            (key: "projects", value: .array(list.map { PimpChannel.projectValue($0) })),
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

    /// «Расставить в ряд» — то же, что пункт меню: порядок по текущим рамкам.
    private func runArrange(id: String, at: Date) {
        let windows = seats.windows()
        guard seats.claudeRunning(), !windows.isEmpty else {
            reply(PimpAnswer(id: id, at: at, ok: false, error: Failure.noWindows.rawValue), for: id)
            return
        }
        let order = ArrangeLayout.order(of: windows.map { $0.frame })
        let placed = seats.arrange(order.map { windows[$0].id })
        reply(PimpAnswer(id: id, at: at, ok: true, fields: PimpChannel.windowsFields(
            placed.isEmpty ? windows : placed, minimized: seats.minimized())), for: id)
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
        var origin: (x: Int, y: Int)?
        if case .point(let x, let y) = place { origin = (x: x, y: y) }
        job = Job(id: id, place: place, fromId: fromWindow?.id, fromTitle: fromTitle,
                  fromResolved: resolved, before: Set(windows.map { $0.id }), startedAt: at)
        seats.openNewWindow(project, origin)
    }

    /// Тик, пока идёт «новое окно»: появилось — ставим на место и отвечаем, вышли 40 с —
    /// `window-missing` (чат при этом создан; так и говорит CLI).
    private func advance(_ current: Job, at: Date) {
        let windows = seats.windows()
        if let fresh = windows.first(where: { !current.before.contains($0.id) }) {
            job = nil
            finish(current, window: fresh, windows: windows, at: at)
            return
        }
        guard at.timeIntervalSince(current.startedAt) >= PimpChannel.newWindowSeconds else { return }
        job = nil
        reply(PimpAnswer(id: current.id, at: at, ok: false, error: Failure.windowMissing.rawValue,
                         fromResolved: current.fromResolved), for: current.id)
    }

    private func finish(_ current: Job, window: PimpWindow, windows: [PimpWindow], at: Date) {
        var job = current
        var frame = window.frame
        var failure: Failure?
        switch job.place {
        case .point:
            // Точку поставила сама страница — двигать нечего.
            break
        case .left, .middle, .right:
            frame = row(job.place, window: window, in: windows) ?? frame
        case .below, .above:
            // Окно `from` могло закрыться, пока шли 40 с, — тогда «под этим» вырождается
            // в «справа», ровно как при неизвестном чате, и это видно по `fromResolved`.
            guard let target = PimpChannel.window(id: job.fromId, title: job.fromTitle, in: windows),
                  target.id != window.id else {
                job.fromResolved = false
                frame = row(.right, window: window, in: windows) ?? frame
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
        reply(PimpAnswer(id: job.id, at: at, ok: true, fromResolved: job.fromResolved, fields: [
            (key: "window", value: .object([
                (key: "title", value: .string(final.title)),
                (key: "chat", value: .string(final.chat)),
                (key: "frame", value: PimpChannel.frameValue(frame)),
            ])),
            // Слои страница кладёт сама и о судьбе их рассказывает в своём `status()`;
            // приложение знает ровно то, что послало (канал probe у неё не отнимаем).
            (key: "layers", value: .string(seats.newWindowLayers() ? "ok" : "")),
        ]), for: job.id)
    }

    /// Поставить новое окно столбцом: порядок существующих окон берём по их рамкам, новое
    /// вставляем по индексу места и расставляем всё в ряд. Возвращает рамку нового окна.
    private func row(_ place: PimpPlace, window: PimpWindow, in windows: [PimpWindow]) -> CGRect? {
        let others = windows.indices.filter { windows[$0].id != window.id }
        let order = ArrangeLayout.order(of: others.map { windows[$0].frame })
        let index = ArrangeLayout.insertIndex(of: place, count: others.count)
        let full = ArrangeLayout.insert(order: order, count: others.count, at: index)
        let ids = full.map { $0 == others.count ? window.id : windows[others[$0]].id }
        return seats.arrange(ids).first { $0.id == window.id }?.frame
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
        let url = taken(for: id)
        guard CommandChannel.writeAtomic(url, "") else { return }
        secure(url)
    }

    private func reply(_ answer: PimpAnswer, for id: String) {
        served += 1
        if !answer.ok { failed += 1 }
        let url = result(for: id)
        guard CommandChannel.writeAtomic(url, answer.json + "\n") else { return }
        secure(url)
    }

    private func secure(_ url: URL) {
        try? fileManager.setAttributes([.posixPermissions: PimpChannel.filePermissions],
                                       ofItemAtPath: url.path)
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

    static func projectValue(_ project: Project) -> CommandValue {
        .object([
            (key: "name", value: .string(project.name)),
            (key: "folder", value: .string(project.folder.path)),
            (key: "lastUsed", value: .string(stampText(ProjectsStore.date(project.lastFocusedAt)))),
        ])
    }

    static func windowsFields(_ windows: [PimpWindow],
                              minimized: Int) -> [(key: String, value: CommandValue)] {
        [(key: "windows", value: .array(windows.map { window in
            .object([
                (key: "title", value: .string(window.title)),
                (key: "chat", value: .string(window.chat)),
                (key: "folder", value: .string(window.folder)),
                (key: "frame", value: frameValue(window.frame)),
            ])
        })),
         (key: "minimized", value: .number(max(0, minimized)))]
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
        // Папка — единственное, без чего «новое окно» бессмысленно.
        if action == .newWindow, project.isEmpty { return nil }
        guard let place = PimpRequest.place(root["place"] as? String) else { return nil }
        return PimpRequest(id: id, at: at, action: action, from: from, project: project,
                           place: place)
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
