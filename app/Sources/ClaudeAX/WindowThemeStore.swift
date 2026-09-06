import Foundation

/// Слой записи хранилища: значение (объект темы, шрифта, размера или булево рамки) либо явный
/// сброс — маркер `"none"`. Третье состояние, «слоя не касались», это отсутствие ключа в записи —
/// ровно как на странице (`themeEntry`/`entryLayer`, `inject.js`).
enum WindowThemeLayer {
    case value(CommandValue)
    /// «Как у Claude» — тоже выбор: без маркера окно на следующем инжекте покрасилось бы
    /// обратно из карты (решение 1 плана WF35).
    case reset

    /// Слой как значение JSON — и в файле, и в команде `themes-restore`.
    var commandValue: CommandValue {
        switch self {
        case .value(let value): return value
        case .reset: return .string(WindowThemeStore.resetMarker)
        }
    }
}

/// `CommandValue` сравнивать нечем (у него нет Equatable), а записи сравнивать надо: файл
/// не переписывается, если ничего не изменилось. Сверяем по байтам JSON — тем самым, которыми
/// слой и уезжает на диск.
extension WindowThemeLayer: Equatable {
    static func == (lhs: WindowThemeLayer, rhs: WindowThemeLayer) -> Bool {
        lhs.commandValue.json == rhs.commandValue.json
    }
}

/// Запись одного ключа карты: слои и время последней правки. По `at` идёт вытеснение, когда
/// файл перерастает потолок; странице `at` не нужен — в команду он не уходит.
struct WindowThemeEntry: Equatable {
    var layers: [String: WindowThemeLayer]
    /// Миллисекунды, в тех же единицах, что `Date.now()` страницы.
    var at: Int

    init(layers: [String: WindowThemeLayer] = [:], at: Int = 0) {
        self.layers = layers
        self.at = at
    }

    var isEmpty: Bool { layers.isEmpty }

    /// Запись как объект JSON: слои в порядке контракта (`theme, font, size, frame`), `at`
    /// последним. `withStamp: false` — тело команды `themes-restore`, там `at` нет.
    func value(withStamp: Bool) -> CommandValue {
        var fields: [(key: String, value: CommandValue)] = WindowThemeStore.layerOrder
            .compactMap { key in layers[key].map { (key: key, value: $0.commandValue) } }
        if withStamp { fields.append((key: "at", value: .number(at))) }
        return .object(fields)
    }
}

/// Темы окон на диске у Пимпа: `~/Library/Application Support/MyClaude/window-themes.json`
/// (решение 1 плана WF35, задача #5473). Переустановка Claude стирает `localStorage` страниц —
/// вместе с ним пропадали все темы, и пять окон Элвиса оказались серыми. Живые файлы в
/// `MyClaude/` переустановка не трогает, поэтому карта тем живёт здесь.
///
/// Файл наполняется двумя путями:
/// - **зеркало** (решение 2): каждая закрепляющая команда `theme`, которую пишет приложение,
///   попадает сюда же — `record(fields:)` разбирает те же поля, что ушли в команду;
/// - **правда страницы** (решение 3): ответ probe приносит карту `myclaude-themes-v1` целиком,
///   и она заменяет `entries` — так в файл попадает и всё, что Элвис выбирал до этого воркфлоу,
///   и любая ошибка зеркала сама лечится на ближайшем круге.
///
/// Обратно карта уезжает одной командой `themes-restore` на все окна (решение 4): страница
/// доливает недостающие СЛОИ и красится, а что у неё есть — не трогает.
///
/// Класс не потокобезопасен: живёт на главной очереди вместе с меню и общим тиком 2 с.
final class WindowThemeStore {
    static let fileName = "window-themes.json"
    /// Команда возврата (контракт решения 4 плана WF35).
    static let restoreAction = "themes-restore"
    static let version = 1
    /// Маркер явного сброса слоя — его же понимает страница (`themeEntry`, `inject.js`).
    static let resetMarker = "none"
    /// Порядок слоёв в записи — как `layerFields` (`ClaudeActions.swift`): рамка после темы,
    /// потому что берёт её акцент.
    static let layerOrder = ["theme", "font", "size", "frame"]
    /// Ключи карты: id чата (главный), заголовок чата (тень), главное окно, «всем окнам».
    static let idPrefix = "id:"
    static let chatPrefix = "chat:"
    static let mainKey = "main"
    static let allKey = "*"
    /// Легаси-ключ страницы (до WF9) — в файле он появляется только из карты страницы.
    static let legacyPrefix = "w:"
    /// Потолок один и он байтовый: 32 КБ тела будущей команды — тот же, что у сводки проектов
    /// (`StatusFeed.totalLimit`). Вытеснение по `at`, самое старое первым.
    static let bodyLimit = StatusFeed.totalLimit
    /// Страховочный потолок от порчи файла: ровно столько ключей принимает страница.
    static let keyLimit = 200
    /// Ключ длиннее странице тоже не годится.
    static let keyLengthLimit = 200
    /// В одном поколении (старт приложения или перезапуск Claude) — не больше трёх команд
    /// возврата и не чаще одной в 5 с (решение 5).
    static let restoreLimit = 3
    static let restoreInterval: TimeInterval = 5

    private let url: URL
    private let now: () -> Date

    /// Карта в памяти: файл пишем только мы, поэтому читаем его один раз за запуск.
    private var cache: [String: WindowThemeEntry]?
    /// В этом поколении уже был ответ probe? Первый пустой ответ значит «переустановка»
    /// (терять нечего), любой следующий — «Элвис снял всё сам» (решение 3).
    private var sawAnswer = false
    private var sent = 0
    private var lastSentAt: Date?
    private var sentTitles: [String]?

    /// Заголовок принадлежит ГЛАВНОМУ окну? Живьём вешает `ClaudeAXController` на
    /// `ProjectPaint.windowKey(forTitle:)`; себя нет — считаем, что нет, и ключ `main`
    /// не пишем вовсе (цена ошибки — окно вернётся серым, а не чужого цвета).
    var isMainWindowTitle: (String) -> Bool = { _ in false }

    init(url: URL = CommandChannel.directory.appendingPathComponent(WindowThemeStore.fileName),
         now: @escaping () -> Date = Date.init) {
        self.url = url
        self.now = now
    }

    // MARK: - чтение

    /// Записи файла. Битый файл читается как пустой и НЕ удаляется: в нём могли остаться
    /// чужие ключи, а разобрать мы их не смогли (то же правило, что у `.pimpmyclaude.json`).
    var entries: [String: WindowThemeEntry] {
        if let cache = cache { return cache }
        let loaded = WindowThemeStore.parse(try? Data(contentsOf: url))
        cache = loaded
        return loaded
    }

    var count: Int { entries.count }

    /// Строка для `statusText`: сколько ключей в файле и сколько команд возврата ушло
    /// в этом поколении.
    var status: String { "\(count)/\(sent)" }

    // MARK: - поколение

    /// Новое поколение: старт приложения или смена pid Claude (решение 5). Счётчик команд
    /// обнуляется, и следующий пустой ответ probe снова считается переустановкой.
    func beginGeneration() {
        sawAnswer = false
        sent = 0
        lastSentAt = nil
        sentTitles = nil
    }

    // MARK: - зеркало (решение 2)

    /// Те же поля, что ушли в команду `theme`, — в файл. Примерка сюда не доходит никогда:
    /// команда с полем `preview` это экран, а не выбор.
    func record(fields: [(key: String, value: CommandValue)]) {
        guard let change = WindowThemeStore.change(from: fields) else { return }
        var next = entries
        let stamp = WindowThemeStore.milliseconds(now())
        if change.scope == MenuModel.themeScopeAll {
            WindowThemeStore.setAll(change.layers, in: &next, stamp: stamp)
        } else {
            let keys = WindowThemeStore.keys(title: change.title, match: change.match,
                                             chat: change.chat, isMainWindow: isMainWindowTitle)
            guard !keys.isEmpty else { return }
            for key in keys {
                WindowThemeStore.set(change.layers, in: &next, key: key, stamp: stamp)
            }
        }
        save(next)
    }

    // MARK: - правда страницы (решение 3)

    /// Карта страницы из ответа probe. `nil` — поля `themes` в круге не было вовсе (главное
    /// окно не ответило): файл не трогаем и ответом это не считаем.
    func absorb(page: [String: WindowThemeEntry]?, at: Date) {
        guard let page = page else { return }
        let first = !sawAnswer
        sawAnswer = true
        guard !page.isEmpty else {
            // Первый ответ поколения пустой — это переустановка Claude: терять нечего,
            // возвращать есть что. Любой следующий — «Как у Claude (все окна)» дошло
            // до нуля ключей, и файл обязан это повторить.
            guard !first else { return }
            save([:])
            return
        }
        let stamp = WindowThemeStore.milliseconds(at)
        let old = entries
        var next: [String: WindowThemeEntry] = [:]
        for (key, entry) in page {
            var entry = entry
            // Ключ не менялся — держим прежний `at`: по нему идёт вытеснение, и обновление
            // карты не должно делать все записи одинаково свежими.
            entry.at = old[key].map { $0.layers == entry.layers ? $0.at : stamp } ?? stamp
            next[key] = entry
        }
        save(next)
    }

    // MARK: - возврат (решения 4 и 5)

    /// Тик рассылки. Возвращает `true`, если команда ушла. Claude не запущен (окон нет),
    /// файл пуст, лимит поколения выбран или набор заголовков не менялся — молчим.
    @discardableResult
    func restoreTick(titles: [String], at: Date,
                     send: ([(key: String, value: CommandValue)]) -> Bool) -> Bool {
        guard sent < WindowThemeStore.restoreLimit, !titles.isEmpty else { return false }
        let map = entries
        guard !map.isEmpty else { return false }
        let wanted = titles.sorted()
        // Первый тик поколения, где Claude вообще есть на экране, шлём всегда; дальше —
        // только на смену состава окон, не чаще раза в 5 с.
        if let last = lastSentAt {
            guard at.timeIntervalSince(last) >= WindowThemeStore.restoreInterval,
                  wanted != sentTitles else { return false }
        }
        guard send(WindowThemeStore.restoreFields(map)) else { return false }
        sent += 1
        lastSentAt = at
        sentTitles = wanted
        return true
    }

    /// Поля команды после id, action, at: `scope`, `entries`. `at` записей в команду не идёт —
    /// он бухгалтерия файла.
    static func restoreFields(_ entries: [String: WindowThemeEntry])
        -> [(key: String, value: CommandValue)] {
        [(key: "scope", value: .string(MenuModel.themeScopeAll)),
         (key: "entries", value: object(entries, withStamp: false))]
    }

    // MARK: - запись

    /// Сохранить карту: вытеснение по потолку, атомарная запись. Ничего не изменилось —
    /// файла не касаемся вовсе (лишний mtime будит чтение у соседей).
    private func save(_ map: [String: WindowThemeEntry]) {
        var next = map
        WindowThemeStore.trim(&next)
        guard next != entries else { return }
        cache = next
        _ = CommandChannel.writeAtomic(url, WindowThemeStore.body(next, at: now()))
    }

    /// Тело файла: `{"version":1,"at":"…","entries":{…}}`, ключи по алфавиту, внутри записи
    /// `theme, font, size, frame, at`.
    static func body(_ entries: [String: WindowThemeEntry], at: Date) -> String {
        CommandValue.object([
            (key: "version", value: .number(version)),
            (key: "at", value: .string(stamp.string(from: at))),
            (key: "entries", value: object(entries, withStamp: true)),
        ]).json
    }

    private static func object(_ entries: [String: WindowThemeEntry],
                               withStamp: Bool) -> CommandValue {
        .object(entries.keys.sorted().compactMap { key in
            entries[key].map { (key: key, value: $0.value(withStamp: withStamp)) }
        })
    }

    /// Вытеснение: сперва страховочный потолок ключей, потом байтовый — по телу будущей
    /// команды. Самое старое по `at` уходит первым.
    static func trim(_ map: inout [String: WindowThemeEntry]) {
        while map.count > keyLimit, dropOldest(&map) {}
        while !map.isEmpty, bodySize(map) > bodyLimit, dropOldest(&map) {}
    }

    /// Байты тела команды `themes-restore` с этой картой. id и `at` у команды постоянной
    /// длины, поэтому мерить можно любым.
    static func bodySize(_ map: [String: WindowThemeEntry]) -> Int {
        CommandChannel.payload(action: restoreAction, fields: restoreFields(map),
                               id: "0000000000000-0000", at: Date(timeIntervalSince1970: 0))
            .utf8.count
    }

    @discardableResult
    private static func dropOldest(_ map: inout [String: WindowThemeEntry]) -> Bool {
        // При равном `at` порядок задаём ключом — иначе вытеснение зависело бы от хэша словаря.
        guard let oldest = map.keys.sorted()
            .min(by: { (map[$0]?.at ?? 0) < (map[$1]?.at ?? 0) }) else { return false }
        map.removeValue(forKey: oldest)
        return true
    }

    // MARK: - ключи (таблица решения 2)

    /// Что меняет команда `theme`: адрес окна и слои.
    struct Change {
        let scope: String
        let title: String
        let match: String?
        let chat: String?
        /// Слой → значение или `.reset` (в команде это `null`).
        let layers: [String: WindowThemeLayer]
    }

    /// Разбор полей команды. `nil` — записывать нечего: примерка (поле `preview` есть),
    /// ни одного слоя или чужой scope.
    static func change(from fields: [(key: String, value: CommandValue)]) -> Change? {
        var scope = ""
        var title = ""
        var match: String?
        var chat: String?
        var layers: [String: WindowThemeLayer] = [:]
        for field in fields {
            switch field.key {
            case "scope": if case .string(let value) = field.value { scope = value }
            case "title": if case .string(let value) = field.value { title = value }
            case "match": if case .string(let value) = field.value { match = value }
            case "chat": if case .string(let value) = field.value { chat = value }
            // Примерка это экран, а не выбор: команда с этим полем в файл не идёт никогда.
            case "preview": return nil
            case let key where layerOrder.contains(key):
                if case .null = field.value { layers[key] = .reset } else {
                    layers[key] = .value(field.value)
                }
            default: break
            }
        }
        guard !layers.isEmpty,
              scope == MenuModel.themeScopeAll || scope == MenuModel.themeScopeWindow else {
            return nil
        }
        return Change(scope: scope, title: title, match: match, chat: chat, layers: layers)
    }

    /// Ключи, под которыми выбор ложится в файл (таблица решения 2 плана WF35). Правила те же,
    /// что у `writeKeys` страницы: id чата — главный ключ, заголовок — тень для окна, которое
    /// своего id ещё не знает, `main` — у главного окна. Заголовка нет вовсе (адресация
    /// фокусом) — не пишем ничего: какое это окно, неизвестно.
    static func keys(title: String, match: String?, chat: String?,
                     isMainWindow: (String) -> Bool) -> [String] {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var keys: [String] = []
        if let chat = chat, !chat.isEmpty { keys.append(idPrefix + chat) }
        // `match` носит только главное окно (WF15) — по нему оно и опознаётся.
        if match != nil {
            keys.append(mainKey)
        } else if !clean.isEmpty, isMainWindow(clean) {
            keys.append(mainKey)
        }
        // Тень по заголовку: заглушки («Claude», «New chat») ключом чата не становятся —
        // их носят и главное окно, и любой безымянный попап.
        if !clean.isEmpty, !ProjectIndex.isStub(clean) { keys.append(chatPrefix + clean) }
        return keys
    }

    // MARK: - слои

    /// `scope:"window"`: слой ложится в запись ключа. Сброс пишем маркером `"none"` только
    /// когда у ЭТОГО слоя есть запись «для всех» — иначе запись лишняя; пустая запись
    /// не хранится. Правило побайтно повторяет `setMapLayers` страницы.
    static func set(_ layers: [String: WindowThemeLayer], in map: inout [String: WindowThemeEntry],
                    key: String, stamp: Int) {
        guard isValid(key: key) else { return }
        var entry = map[key] ?? WindowThemeEntry(at: stamp)
        let all = map[allKey]
        for layer in layerOrder {
            guard let value = layers[layer] else { continue }
            switch value {
            case .value(let raw):
                entry.layers[layer] = .value(layer == "size"
                    ? merged(size: raw, into: entry.layers[layer])
                    : raw)
            case .reset:
                if all?.layers[layer] != nil { entry.layers[layer] = .reset }
                else { entry.layers.removeValue(forKey: layer) }
            }
        }
        entry.at = stamp
        if entry.isEmpty { map.removeValue(forKey: key) } else { map[key] = entry }
        // Перенос старой записи: всё, что в ней было, уже в entry (то же делает страница).
        if key.hasPrefix(chatPrefix) {
            map.removeValue(forKey: legacyPrefix + key.dropFirst(chatPrefix.count))
        }
    }

    /// `scope:"all"`: слой уходит в `*`, а у всех остальных записей снимается — его задаёт
    /// теперь общая запись (`runThemeCommand`, `inject.js`). Сброс убирает слой и из `*`.
    static func setAll(_ layers: [String: WindowThemeLayer],
                       in map: inout [String: WindowThemeEntry], stamp: Int) {
        var all = map[allKey] ?? WindowThemeEntry(at: stamp)
        for (key, entry) in map where key != allKey {
            var entry = entry
            for layer in layers.keys { entry.layers.removeValue(forKey: layer) }
            if entry.isEmpty { map.removeValue(forKey: key) } else { map[key] = entry }
        }
        for layer in layerOrder {
            guard let value = layers[layer] else { continue }
            if case .value(let raw) = value { all.layers[layer] = .value(raw) }
            else { all.layers.removeValue(forKey: layer) }
        }
        all.at = stamp
        if all.isEmpty { map.removeValue(forKey: allKey) } else { map[allKey] = all }
    }

    /// Размер — единственный слой с половинками: «Размер ответов ▸ 16» приходит без поля
    /// `question`, и оно обязано остаться прежним. Половина со значением `null` из записи
    /// уходит: в хранилище такая читается как «слоя нет».
    static func merged(size: CommandValue, into old: WindowThemeLayer?) -> CommandValue {
        guard case .object(let halves) = size else { return size }
        var fields: [(key: String, value: CommandValue)] = []
        if case .value(.object(let base))? = old { fields = base }
        for half in halves {
            fields.removeAll { $0.key == half.key }
            if case .null = half.value { continue }
            fields.append(half)
        }
        let order = [Size.answerKey, Size.questionKey]
        fields.sort { (order.firstIndex(of: $0.key) ?? order.count)
            < (order.firstIndex(of: $1.key) ?? order.count) }
        return .object(fields)
    }

    /// Ключ, который поймёт страница: `*`, `main`, `chat:…`, `id:…`, `w:…` и не длиннее
    /// 200 знаков. Всё прочее в файл не пускаем — его всё равно отбросил бы возврат.
    static func isValid(key: String) -> Bool {
        guard !key.isEmpty, key.count <= keyLengthLimit else { return false }
        if key == allKey || key == mainKey { return true }
        // Пустой хвост у префикса (`id:`, `chat:`) страница тоже не примет — сверка побайтно
        // повторяет `restoreKeyOk` (`inject.js`).
        return [chatPrefix, idPrefix, legacyPrefix]
            .contains { key.hasPrefix($0) && key.count > $0.count }
    }

    // MARK: - разбор JSON

    /// Файл целиком: `{"version":1,"at":"…","entries":{…}}`. Битый — пустая карта.
    static func parse(_ data: Data?) -> [String: WindowThemeEntry] {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return map(from: root["entries"])
    }

    /// Карта записей из JSON — и из файла, и из ответа probe (`themes`). Мусор отбрасывается
    /// по записи, а не по карте: из-за одного кривого ключа терять остальные незачем.
    static func map(from json: Any?) -> [String: WindowThemeEntry] {
        guard let raw = json as? [String: Any] else { return [:] }
        var out: [String: WindowThemeEntry] = [:]
        for (key, value) in raw {
            guard isValid(key: key), let entry = entry(from: value), !entry.isEmpty else { continue }
            out[key] = entry
        }
        trim(&out)
        return out
    }

    /// Запись карты. Читается и старый формат WF5 (тема на верхнем уровне, строка `"none"`) —
    /// ровно как его читает страница (`themeEntry`): в живых окнах такие записи ещё лежат.
    static func entry(from json: Any?) -> WindowThemeEntry? {
        if let marker = json as? String {
            return marker == resetMarker ? WindowThemeEntry(layers: ["theme": .reset]) : nil
        }
        guard let raw = json as? [String: Any] else { return nil }
        var entry = WindowThemeEntry(at: (raw["at"] as? NSNumber)?.intValue ?? 0)
        if raw["palette"] != nil {
            guard let value = value(from: raw, field: "theme") else { return nil }
            entry.layers["theme"] = .value(value)
            return entry
        }
        for layer in layerOrder {
            guard let value = raw[layer] else { continue }
            if let marker = value as? String {
                if marker == resetMarker { entry.layers[layer] = .reset }
                continue
            }
            guard let converted = self.value(from: value, field: layer) else { continue }
            // Тема, шрифт и размер — объекты, рамка — булево; всё прочее равно мусору.
            switch converted {
            case .object: if layer != "frame" { entry.layers[layer] = .value(converted) }
            case .bool: if layer == "frame" { entry.layers[layer] = .value(converted) }
            default: break
            }
        }
        return entry
    }

    /// JSON → значение команды. Порядок ключей объекта задаём сами (у словаря его нет вовсе):
    /// известные поля по контракту, остальные по алфавиту — иначе файл переписывался бы
    /// каждый круг новыми байтами.
    static func value(from json: Any, field: String) -> CommandValue? {
        if let text = json as? String { return .string(text) }
        if let number = json as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.intValue)
        }
        guard let raw = json as? [String: Any] else { return nil }
        let order = fieldOrder[field] ?? []
        var keys = order.filter { raw[$0] != nil }
        keys += raw.keys.filter { !order.contains($0) }.sorted()
        return .object(keys.compactMap { key in
            value(from: raw[key] ?? NSNull(), field: key).map { (key: key, value: $0) }
        })
    }

    /// Порядок полей внутри слоёв — тот же, что у команды (`Theme.commandValue`,
    /// `Font.commandValue`, `Size.commandValue`).
    private static let fieldOrder: [String: [String]] = [
        "theme": ["id", "name", "type", "palette"],
        "palette": Theme.paletteOrder,
        "font": ["id", "family", "mono"],
        "size": [Size.answerKey, Size.questionKey],
    ]

    static func milliseconds(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()
}
