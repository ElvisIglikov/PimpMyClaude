import CryptoKit
import Foundation

/// Вид проекта — файл `.pimpmyclaude.json` в корне папки проекта (решение 3 плана WF15,
/// вопрос 1 макета: «настройки едут вместе с папкой»). Слои те же, что у команды `theme`:
/// ключа нет — слой не трогаем, `null` — сброс слоя («в этом проекте как у Claude»),
/// значение — применить.
///
/// **Хранилище ровно одно** (критик М4): читаем настройки ТОЛЬКО из этого файла. Строка
/// `<!-- pimpmyclaude: … -->` в `AGENTS.md` проекта — памятка агенту, её пишет пункт меню и
/// назад НЕ читает. Реестр приложения (`ProjectSettingsStore`) — не второе хранилище, а запись
/// «в эту папку писать нельзя».
///
/// Контракт файла побайтно: порядок ключей `pimpmyclaude, name, theme, font, size, frame`,
/// два пробела отступа, перевод строки в конце; чужие ключи возвращаются на место следом за
/// нашими, по алфавиту. Палитра копируется целиком (как в `my-themes.json`), чтобы файл пережил
/// смену каталога тем: `id` нужен только для галки в меню.
struct ProjectSettings: Equatable {
    static let fileName = ".pimpmyclaude.json"
    /// Версия контракта; чужое значение не мешает читать слои («читаем что смогли»).
    static let version = 1
    static let versionKey = "pimpmyclaude"
    static let nameKey = "name"
    static let themeKey = "theme"
    static let fontKey = "font"
    static let sizeKey = "size"
    static let frameKey = "frame"
    /// Наши ключи в порядке контракта — всё, чего в этом списке нет, считается чужим.
    static let knownKeys = [versionKey, nameKey, themeKey, fontKey, sizeKey, frameKey]
    static let indent = "  "

    /// Имя проекта — только для глаз (в меню имя берётся от папки).
    let name: String
    let theme: Layer<Theme>
    let font: Layer<Font>
    let size: Layer<Size>
    let frame: Layer<Bool>

    init(name: String = "", theme: Layer<Theme> = .keep, font: Layer<Font> = .keep,
         size: Layer<Size> = .keep, frame: Layer<Bool> = .keep) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.theme = theme
        self.font = font
        // Пустой размер — не слой, а «не трогать»: страница читает `{}` как сброс.
        if case .set(let value) = size, value.isEmpty {
            self.size = .keep
        } else {
            self.size = size
        }
        // Рамка — слой-тумблер: значение у неё ровно одно, true (`normalizeFrame`, inject.js:720).
        // «Рамки в этом проекте нет» — это сброс слоя, а не `false`.
        if case .set(let on) = frame, !on {
            self.frame = .reset
        } else {
            self.frame = frame
        }
    }

    /// Ни одного слоя — красить нечем (в файле только имя).
    var isEmpty: Bool { theme.isKeep && font.isKeep && size.isKeep && frame.isKeep }

    /// Хэш вида: половина отпечатка «окно → папка + настройки», по которому покраска не шлёт
    /// одну и ту же команду дважды (решение 4 плана WF15).
    var digest: String {
        SHA256.hash(data: Data(json().utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Наши ключи как объект команды — тем же порядком, что в файле (реестр кладёт его под
    /// путь папки).
    var objectValue: CommandValue { .object(fields) }

    private var fields: [(key: String, value: CommandValue)] {
        var out: [(key: String, value: CommandValue)] = [
            (key: ProjectSettings.versionKey, value: .number(ProjectSettings.version)),
            (key: ProjectSettings.nameKey, value: .string(name)),
        ]
        if let value = theme.commandValue({ $0.commandValue }) {
            out.append((key: ProjectSettings.themeKey, value: value))
        }
        if let value = font.commandValue({ $0.commandValue }) {
            out.append((key: ProjectSettings.fontKey, value: value))
        }
        if let value = size.commandValue({ $0.commandValue }) {
            out.append((key: ProjectSettings.sizeKey, value: value))
        }
        if let value = frame.commandValue({ .bool($0) }) {
            out.append((key: ProjectSettings.frameKey, value: value))
        }
        return out
    }

    // MARK: - текст файла

    /// Файл целиком. `extras` — чужие ключи прочитанного файла (уже отрисованные): они идут
    /// следом за нашими, иначе «Записать этот вид в проект» съедало бы чужие настройки.
    func json(extras: [(key: String, text: String)] = []) -> String {
        let ours = fields.map { (key: $0.key, text: ProjectSettings.pretty($0.value, level: 1)) }
        return ProjectSettings.object(ours + extras, level: 0) + "\n"
    }

    /// Текст файла после записи этого вида поверх прежнего. Файла не было (`nil`) — пишем свой;
    /// прежний разобрался — чужие ключи сохраняем; **прежний битый — возвращаем nil и файл не
    /// трогаем вовсе** (тот же приём, что `LiveStyle.merged`): иначе одна кривая скобка стоила бы
    /// Элвису его же настроек. Перезапись битого — только явным `force` из пункта меню.
    static func merged(file old: String?, settings: ProjectSettings) -> String? {
        guard let old = old else { return settings.json() }
        let trimmed = old.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return settings.json() }
        guard let root = try? JSONSerialization.jsonObject(with: Data(old.utf8)) as? [String: Any]
        else { return nil }
        let extras = root.keys.filter { !knownKeys.contains($0) }.sorted()
            .compactMap { key -> (key: String, text: String)? in
                guard let value = root[key], let text = foreignText(value, level: 1) else { return nil }
                return (key: key, text: text)
            }
        return settings.json(extras: extras)
    }

    /// Объект: каждый ключ со своей строки, два пробела на уровень.
    static func object(_ fields: [(key: String, text: String)], level: Int) -> String {
        guard !fields.isEmpty else { return "{}" }
        let pad = String(repeating: indent, count: level)
        let inner = String(repeating: indent, count: level + 1)
        let body = fields.map { "\(inner)\(CommandChannel.jsonString($0.key)): \($0.text)" }
        return "{\n" + body.joined(separator: ",\n") + "\n" + pad + "}"
    }

    /// Значение команды в читаемом виде (порядок ключей сохраняется — на нём стоит контракт).
    static func pretty(_ value: CommandValue, level: Int) -> String {
        switch value {
        case .object(let fields):
            return object(fields.map { (key: $0.key, text: pretty($0.value, level: level + 1)) },
                          level: level)
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            let pad = String(repeating: indent, count: level)
            let inner = String(repeating: indent, count: level + 1)
            return "[\n" + items.map { inner + pretty($0, level: level + 1) }
                .joined(separator: ",\n") + "\n" + pad + "]"
        default:
            return value.json
        }
    }

    /// Чужое значение: рисуем средствами Foundation (ключи по алфавиту — чтобы файл не менялся
    /// сам собой) и сдвигаем под наш отступ.
    static func foreignText(_ value: Any, level: Int) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]),
            let text = String(data: data, encoding: .utf8) else { return nil }
        let pad = String(repeating: indent, count: level)
        return text.components(separatedBy: "\n").enumerated()
            .map { $0.offset == 0 ? $0.element : pad + $0.element }
            .joined(separator: "\n")
    }

    // MARK: - разбор

    /// Битый JSON — «настроек нет» (nil): файл при этом не трогаем.
    static func parse(_ data: Data?) -> ProjectSettings? {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parse(object: root)
    }

    /// Читаем что смогли: чужая версия и лишние ключи не мешают, кривой слой равен его
    /// отсутствию (так же читает команду `entryLayer` в inject.js).
    static func parse(object root: [String: Any]) -> ProjectSettings {
        ProjectSettings(name: root[nameKey] as? String ?? "",
                        theme: layer(root[themeKey], theme(_:)),
                        font: layer(root[fontKey], font(_:)),
                        size: layer(root[sizeKey], { ThemeStore.size($0) }),
                        frame: frameLayer(root[frameKey]))
    }

    /// Ключа нет — слой не трогаем, `null` — сброс, мусор — тоже «не трогаем».
    static func layer<Value>(_ raw: Any?, _ decode: (Any) -> Value?) -> Layer<Value> {
        guard let raw = raw else { return .keep }
        if raw is NSNull { return .reset }
        return decode(raw).map { Layer.set($0) } ?? .keep
    }

    /// Тумблер: `true` — рамка, всё остальное (`false`, `null`, мусор) — сброс слоя.
    static func frameLayer(_ raw: Any?) -> Layer<Bool> {
        guard let raw = raw else { return .keep }
        return (raw as? Bool) == true ? .set(true) : .reset
    }

    /// Тема из файла. Каталог тут ни при чём: работаем по палитре, `id` нужен только для галки
    /// в меню. Палитры нет — слоя нет (одним `id` тему не восстановить).
    static func theme(_ raw: Any) -> Theme? {
        guard let item = raw as? [String: Any],
              let palette = item["palette"] as? [String: String], !palette.isEmpty else { return nil }
        let id = item["id"] as? String ?? ""
        return Theme(id: id, name: item["name"] as? String ?? id,
                     type: item["type"] as? String ?? "dark", palette: palette)
    }

    /// Шрифт из файла — как в `MyThemesStore.parse`: имя семейства голое и через санитайзер
    /// контракта (стек и кавычки дописывает страница).
    static func font(_ raw: Any) -> Font? {
        guard let item = raw as? [String: Any],
              let family = item["family"] as? String,
              let clean = FontCatalog.sanitize(family: family) else { return nil }
        let mono = item["mono"] as? Bool ?? false
        return Font(id: item["id"] as? String ?? FontCatalog.id(for: clean), family: clean,
                    category: FontCatalog.category(family: clean, mono: mono),
                    displayName: FontCatalog.localizedName(clean))
    }
}

/// Диск: файл вида в папке проекта и запасной реестр.
///
/// Реестр `projects.json` рядом с command.json — не второе хранилище (критик М4), а ответ на
/// «в эту папку писать нельзя» (нет прав, том только для чтения, отказ TCC в `~/Documents`).
/// Файл в папке всегда сильнее: есть он — реестр для этой папки не читается вовсе, а удачная
/// запись файла запись реестра стирает. Настройки из реестра с папкой не едут — это и есть
/// его минус, о нём README говорит честно.
final class ProjectSettingsStore {
    static let registryFileName = "projects.json"
    static let registryVersionKey = "version"
    static let registryProjectsKey = "projects"
    static let registryVersion = 1

    /// Чем кончилась запись — пункт меню показывает это плашкой.
    enum WriteResult: Equatable {
        /// Записали `.pimpmyclaude.json` в папку проекта.
        case written
        /// В папку писать нельзя — вид лёг в реестр приложения.
        case registry
        /// Файл в папке битый: сами не переписываем, ждём явного «да» (`force`).
        case broken
        /// Папки нет или писать некуда вовсе.
        case failed
    }

    private let registryURL: URL
    private let fileManager: FileManager

    init(registryURL: URL = CommandChannel.directory
            .appendingPathComponent(ProjectSettingsStore.registryFileName),
         fileManager: FileManager = .default) {
        self.registryURL = registryURL
        self.fileManager = fileManager
    }

    func url(in folder: URL) -> URL { folder.appendingPathComponent(ProjectSettings.fileName) }

    /// Вид проекта. Файл есть — читаем только его (битый = «настроек нет»); файла нет —
    /// смотрим реестр.
    func settings(in folder: URL) -> ProjectSettings? {
        let url = self.url(in: folder)
        if fileManager.fileExists(atPath: url.path) {
            return ProjectSettings.parse(try? Data(contentsOf: url))
        }
        return registry()[folder.standardizedFileURL.path]
    }

    /// Записать вид в папку проекта. Прежние чужие ключи сохраняются; в папку писать нельзя —
    /// уходим в реестр; файл битый — `.broken`, пока не позовут с `force`.
    @discardableResult
    func write(_ settings: ProjectSettings, to folder: URL, force: Bool = false) -> WriteResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .failed }
        let url = self.url(in: folder)
        let old = try? String(contentsOf: url, encoding: .utf8)
        var text = ProjectSettings.merged(file: old, settings: settings)
        if text == nil, force { text = settings.json() }
        guard let body = text else { return .broken }
        // Тот же текст — файл не трогаем: лишняя запись дёргает mtime, а по нему покраска
        // и решает, что вид проекта изменился.
        guard body != old else { return .written }
        guard CommandChannel.writeAtomic(url, body) else {
            return remember(settings, folder: folder) ? .registry : .failed
        }
        forget(folder: folder)
        return .written
    }

    /// «🗑 Убрать настройки из проекта»: файл и запись реестра. Строку в `AGENTS.md` не трогаем
    /// (решение 5 плана WF15) и окна назад не перекрашиваем.
    @discardableResult
    func remove(from folder: URL) -> Bool {
        let url = self.url(in: folder)
        var removed = forget(folder: folder)
        if fileManager.fileExists(atPath: url.path) {
            removed = (try? fileManager.removeItem(at: url)) != nil || removed
        }
        return removed
    }

    // MARK: - реестр

    /// Что лежит в реестре: путь папки → вид.
    func registry() -> [String: ProjectSettings] {
        guard let data = try? Data(contentsOf: registryURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root[ProjectSettingsStore.registryProjectsKey] as? [String: Any]
        else { return [:] }
        var out: [String: ProjectSettings] = [:]
        for (path, value) in list {
            guard let item = value as? [String: Any] else { continue }
            out[path] = ProjectSettings.parse(object: item)
        }
        return out
    }

    @discardableResult
    private func remember(_ settings: ProjectSettings, folder: URL) -> Bool {
        var map = registry()
        map[folder.standardizedFileURL.path] = settings
        return writeRegistry(map)
    }

    /// Убрать папку из реестра; её там не было — ничего не пишем.
    @discardableResult
    private func forget(folder: URL) -> Bool {
        var map = registry()
        guard map.removeValue(forKey: folder.standardizedFileURL.path) != nil else { return false }
        return writeRegistry(map)
    }

    private func writeRegistry(_ map: [String: ProjectSettings]) -> Bool {
        let projects = map.keys.sorted().map { (key: $0, value: map[$0]?.objectValue ?? .null) }
        let body = CommandValue.object([
            (key: ProjectSettingsStore.registryVersionKey,
             value: .number(ProjectSettingsStore.registryVersion)),
            (key: ProjectSettingsStore.registryProjectsKey, value: .object(projects)),
        ])
        return CommandChannel.writeAtomic(registryURL, ProjectSettings.pretty(body, level: 0) + "\n")
    }
}
