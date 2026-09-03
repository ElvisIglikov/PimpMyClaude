import Foundation

/// Значение поля command.json: строка, булево (`font.mono`, `frame`), целое (`size.answer`),
/// вложенный объект (тема, шрифт, размер) или null (сброс слоя). Объект пишется в том порядке
/// ключей, в каком его собрали: контракт п. 5 плана WF6 перечисляет поля темы как
/// id, name, type, palette — живой файл должен читаться так же.
enum CommandValue {
    case string(String)
    case bool(Bool)
    /// Кегль в пикселях (контракт п. 1 плана WF12): число, а не строка — страница
    /// проверяет его `Number.isFinite` и границами 11…24.
    case number(Int)
    case object([(key: String, value: CommandValue)])
    /// Список объектов — `projects` в команде `status` (контракт п. 2 плана WF9).
    case array([CommandValue])
    case null

    var json: String {
        switch self {
        case .string(let value): return CommandChannel.jsonString(value)
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return String(value)
        case .null: return "null"
        case .array(let items):
            return "[" + items.map { $0.json }.joined(separator: ",") + "]"
        case .object(let fields):
            let body = fields.map { "\(CommandChannel.jsonString($0.key)):\($0.value.json)" }
            return "{" + body.joined(separator: ",") + "}"
        }
    }
}

/// Канал команд в страницы Claude: `~/Library/Application Support/MyClaude/command.json`.
/// Лоадер v6 (patch-claude.mjs) читает файл по `fs.watchFile` раз в 500 мс, отбрасывает
/// команду с тем же `id`, и рассылает `{id, action, at, …}` событием `myclaude-command`
/// во все страницы (inject.js, `onCommand`). Канал probe.js (лоадер v5) сюда не переносится.
///
/// Файл один, писатель тоже один — с очередью (критик п. 1 плана WF9): опрос раз в 500 мс
/// значит, что две записи подряд теряют первую. Отсюда зазор `minInterval` между записями,
/// FIFO для команд меню и отдельный слот низшего приоритета для сводки проектов.
/// Всё живёт на главной очереди — как и все, кто сюда пишет (меню, хоткеи, StatusFeed).
final class CommandChannel {
    /// Папку не переименовывать: лоадер смотрит именно в MyClaude.
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MyClaude", isDirectory: true)
    static let path = directory.appendingPathComponent("command.json")
    /// Сводка проектов (StatusFeed) — единственная команда, которую пишет не Элвис.
    static let statusAction = "status"
    /// Минимальный зазор между записями: лоадер успевает увидеть каждую (опрос — 500 мс).
    static let minInterval: TimeInterval = 0.6

    /// Куда команду ставить (критик п. 1 плана WF9).
    enum Priority {
        /// Команда меню или хоткея: очередь FIFO, не чаще одной записи в `minInterval`.
        case normal
        /// Предпросмотр темы: вне очереди, пишется сразу — мышь идёт по подменю, ждать
        /// нечего, а потерянная примерка безвредна. Не-preview команда после него всё
        /// равно ждёт `minInterval`.
        case preview
        /// Сводка проектов: пишет её не Элвис, поэтому она уступает всем — ждёт, пока
        /// очередь опустеет, и отбрасывается, если за это время пришла любая другая
        /// команда (StatusFeed попробует снова на следующем тике, через 60 с).
        case status
    }

    /// Команда в очереди. Тело собирается в момент записи: `id` и `at` должны быть тем
    /// временем, когда файл действительно поменялся, а не когда команду поставили в очередь.
    private struct Item {
        let action: String
        let body: () -> String
        let completion: ((Bool) -> Void)?
    }

    private(set) var lastCommand = "(none)"

    private let url: URL
    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    private var queue: [Item] = []
    private var pendingStatus: Item?
    private var lastWriteAt: Date?
    private var waiting = false

    /// Часы и таймер подставляются в тестах (тест гонки), путь — чтобы не трогать живой
    /// `~/Library`; в приложении всё по умолчанию.
    init(path: URL = CommandChannel.path,
         now: @escaping () -> Date = Date.init,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
         }) {
        self.url = path
        self.now = now
        self.schedule = schedule
    }

    /// Сколько прошло с последней записи; записей ещё не было — «бесконечно давно».
    private var secondsSinceWrite: TimeInterval {
        lastWriteAt.map { now().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Экранирование как в Lua `jsonString`: кавычка, слэш и любые управляющие — \u00xx.
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Уникальный id: миллисекунды + случайные четыре цифры (формат Lua «%d-%04d»).
    /// Уникальность важна — лоадер игнорирует команду с прежним id.
    static func makeID(now: TimeInterval = Date().timeIntervalSince1970,
                       random: Int = Int.random(in: 0...9999)) -> String {
        String(format: "%d-%04d", Int(now * 1000), random)
    }

    /// Тело command.json. Порядок полей — как в Lua: id, action, at, затем дополнительные
    /// (строковые — по алфавиту).
    static func payload(action: String, extra: [String: String] = [:],
                        id: String = makeID(), at: Date = Date()) -> String {
        payload(action: action,
                fields: extra.keys.sorted().map { (key: $0, value: .string(extra[$0] ?? "")) },
                id: id, at: at)
    }

    /// То же тело, но поля идут в заданном порядке и могут быть непростыми: тема, шрифт и
    /// размер — вложенные объекты, сброс слоя — null, отсутствие поля — «слой не трогать»
    /// (контракт п. 1 плана WF12: id, action, at, scope, title, preview, theme, font, size, frame).
    static func payload(action: String, fields: [(key: String, value: CommandValue)],
                        id: String = makeID(), at: Date = Date()) -> String {
        var parts = ["\"id\":\(jsonString(id))",
                     "\"action\":\(jsonString(action))",
                     "\"at\":\(jsonString(stamp.string(from: at)))"]
        parts += fields.map { "\(jsonString($0.key)):\($0.value.json)" }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// Запись через временный файл рядом и `rename(2)`: лоадер опрашивает файл и не должен
    /// увидеть его наполовину записанным. tmp обязан лежать в той же папке — иначе rename не атомарен.
    @discardableResult
    static func writeAtomic(_ url: URL, _ body: String) -> Bool {
        let tmp = url.appendingPathExtension("tmp")
        let data = Data(body.utf8)
        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            // Патч ещё не ставили: папки MyClaude нет.
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            guard (try? data.write(to: tmp, options: .atomic)) != nil else { return false }
        }
        let moved = tmp.withUnsafeFileSystemRepresentation { from -> Bool in
            url.withUnsafeFileSystemRepresentation { to -> Bool in
                guard let from = from, let to = to else { return false }
                return rename(from, to) == 0
            }
        }
        if !moved { try? FileManager.default.removeItem(at: tmp) }
        return moved
    }

    /// Возвращает, принята ли команда: `true` — записана или стоит в очереди. Что она дошла
    /// до диска, знает только `completion` (у сводки он же сообщает, что её вытеснили).
    @discardableResult
    func write(action: String, extra: [String: String] = [:]) -> Bool {
        enqueue(action: action, priority: .normal, completion: nil) {
            CommandChannel.payload(action: action, extra: extra)
        }
    }

    /// Команда с полями сложнее строки (тема, сводка, workflow).
    @discardableResult
    func write(action: String, fields: [(key: String, value: CommandValue)],
               priority: Priority = .normal, completion: ((Bool) -> Void)? = nil) -> Bool {
        enqueue(action: action, priority: priority, completion: completion) {
            CommandChannel.payload(action: action, fields: fields)
        }
    }

    @discardableResult
    private func enqueue(action: String, priority: Priority, completion: ((Bool) -> Void)?,
                         body: @escaping () -> String) -> Bool {
        let item = Item(action: action, body: body, completion: completion)
        // Приоритет сводки не зависит от того, кто её шлёт: она всегда последняя в очереди.
        switch action == CommandChannel.statusAction ? .status : priority {
        case .preview:
            return deliver(item)
        case .normal:
            dropStatus()
            queue.append(item)
        case .status:
            dropStatus()
            pendingStatus = item
        }
        flush()
        return true
    }

    /// Очередная команда — когда с прошлой записи прошло `minInterval`. Сводка идёт только
    /// на пустой очереди.
    private func flush() {
        guard !waiting, let item = queue.first ?? pendingStatus else { return }
        let wait = CommandChannel.minInterval - secondsSinceWrite
        guard wait <= 0 else {
            waiting = true
            schedule(wait) { [weak self] in
                self?.waiting = false
                self?.flush()
            }
            return
        }
        if queue.isEmpty { pendingStatus = nil } else { queue.removeFirst() }
        deliver(item)
        flush()
    }

    /// Сводку вытеснила команда меню — она не поедет вовсе; StatusFeed узнаёт об этом
    /// из completion и не считает её посланной.
    private func dropStatus() {
        guard let status = pendingStatus else { return }
        pendingStatus = nil
        status.completion?(false)
    }

    /// Собственно запись. Зазор отсчитывается и от предпросмотра: команда меню сразу после
    /// примерки затёрла бы её раньше, чем лоадер прочитает файл.
    @discardableResult
    private func deliver(_ item: Item) -> Bool {
        let at = now()
        guard CommandChannel.writeAtomic(url, item.body()) else {
            item.completion?(false)
            return false
        }
        lastWriteAt = at
        lastCommand = "\(item.action) @ \(CommandChannel.clock.string(from: at))"
        item.completion?(true)
        return true
    }
}
