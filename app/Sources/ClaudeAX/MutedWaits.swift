import CryptoKit
import Foundation
import Patcher

// «Не напоминать» у «Ждёт тебя» (#9820, слово Элвиса: «Сделай такую кнопочку всегда, чтобы она там высвечивалась рядом.
// „Не напоминать“… И таймер такой… секунд пять отменить, если он случайно нажал… для всех отключать не хочу, по
// умолчанию хочу, чтобы было включено»). Заглушённая строка «Ждёт Элвиса:» сводки проекта не видна в панели, в `/digest`
// и в сводке для полоски (StatusFeed) и не ставит ✋ у часов; сменился текст — напоминание новое. Контракт —
// `docs/contracts/530-9820-muted-waits.md`, решения — `docs/decisions/2026-10-19-ne-napominat-9820.md`, тесты —
// `MutedWaits9820Tests`; вид — `Panel/PanelMuteWait.swift`.

/// Заглушённые строки «Ждёт Элвиса:». Чистое значение: его берут снимок панели, `/digest` и StatusFeed.
public struct MutedWaits: Equatable {
    public static let fileName = "muted-waits.json"
    public static let version = 1
    /// Бессрочные записи («пока текст не сменится») старше — долой: текст давно сменился или забыт.
    static let keepSeconds: TimeInterval = 90 * 86_400
    /// Потолок записей: сверх — уходят самые старые.
    static let limit = 500

    public struct Item: Equatable {
        /// «<папка проекта>|<sha1 текста>» (`key`).
        public let key: String
        /// До какого времени не напоминать; nil — пока текст не сменится.
        public let until: Date?
        /// Когда заглушили.
        public let at: Date

        public init(key: String, until: Date?, at: Date) {
            self.key = key
            self.until = until
            self.at = at
        }
    }

    /// Срок из меню «Не напоминать ▾».
    public enum Choice: CaseIterable {
        case hour, tomorrow, week, textChange

        public var title: String {
            switch self {
            case .hour: return "На час"
            case .tomorrow: return "До завтра"
            case .week: return "На неделю"
            case .textChange: return "Пока текст не сменится"
            }
        }
    }

    public var items: [Item]

    public init(items: [Item] = []) { self.items = items }

    public static let empty = MutedWaits()

    // MARK: ключ

    /// Папка проекта — один вид во всех потребителях: ссылки раскрыты, путь стандартный.
    public static func folderKey(_ folder: URL) -> String {
        folder.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Ключ строки: папка проекта и SHA1 текста «Ждёт Элвиса:» после разбора (`PanelStatus.waitFor`), без пробелов по
    /// краям. Новый текст — новый ключ: напоминание снова видно.
    public static func key(folder: URL, text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = Insecure.SHA1.hash(data: Data(clean.utf8)).map { String(format: "%02x", $0) }.joined()
        return folderKey(folder) + "|" + hash
    }

    public static func key(folder: String, text: String) -> String {
        key(folder: URL(fileURLWithPath: folder, isDirectory: true), text: text)
    }

    // MARK: правило

    /// Запись заглушает до `until` (не включая его); бессрочная — пока текст тот же (то есть ключ тот же).
    public func isMuted(_ key: String, now: Date) -> Bool {
        items.contains { $0.key == key && ($0.until.map { now < $0 } ?? true) }
    }

    /// Строка «Ждёт Элвиса:» проекта заглушена; пустая или «ничего» — нечего заглушать.
    public func isMuted(folder: URL, text: String, now: Date) -> Bool {
        guard !items.isEmpty, !PanelProjects.isNothing(text) else { return false }
        return isMuted(Self.key(folder: folder, text: text), now: now)
    }

    /// Срок по выбору: час; «до завтра» — 06:00 следующего календарного дня; неделя; nil — пока текст не сменится.
    public static func until(_ choice: Choice, now: Date, calendar: Calendar = .current) -> Date? {
        switch choice {
        case .hour: return now.addingTimeInterval(3600)
        case .tomorrow:
            let today = calendar.startOfDay(for: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
            return calendar.date(byAdding: .hour, value: 6, to: tomorrow) ?? tomorrow.addingTimeInterval(6 * 3600)
        case .week: return now.addingTimeInterval(7 * 86_400)
        case .textChange: return nil
        }
    }

    /// Без истёкших, без бессрочных старше `keepSeconds`; сверх `limit` — остаются самые свежие.
    public func pruned(now: Date) -> MutedWaits {
        var kept = items.filter { item in
            if let until = item.until { return now < until }
            return now.timeIntervalSince(item.at) <= Self.keepSeconds
        }
        if kept.count > Self.limit {
            kept = Array(kept.sorted { $0.at > $1.at }.prefix(Self.limit))
        }
        return MutedWaits(items: kept)
    }

    /// Заглушить: прежняя запись того же ключа заменяется.
    public func muting(_ key: String, until: Date?, now: Date) -> MutedWaits {
        MutedWaits(items: items.filter { $0.key != key } + [Item(key: key, until: until, at: now)]).pruned(now: now)
    }

    public func unmuting(_ key: String) -> MutedWaits {
        MutedWaits(items: items.filter { $0.key != key })
    }

    // MARK: файл

    private static let isoMillis: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func date(_ raw: String) -> Date? { isoMillis.date(from: raw) ?? isoPlain.date(from: raw) }

    /// `{"version":1,"muted":[{"key","until":ISO|null,"at":ISO}]}`. Нет файла, битый, чужая версия — пусто
    /// (всё напоминается); мусорная запись пропускается; без `at` (дописана руками) — «только что».
    public static func parse(_ data: Data?) -> MutedWaits {
        guard let data = data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["version"] as? NSNumber)?.intValue == version,
              let list = root["muted"] as? [Any] else { return .empty }
        var items: [Item] = []
        for raw in list {
            guard let entry = raw as? [String: Any], let key = entry["key"] as? String, key.contains("|") else { continue }
            let until: Date?
            switch entry["until"] {
            case let text as String:
                guard let date = date(text) else { continue }
                until = date
            case nil, is NSNull: until = nil
            default: continue
            }
            let at = (entry["at"] as? String).flatMap(date) ?? Date()
            items.append(Item(key: key, until: until, at: at))
        }
        return MutedWaits(items: items)
    }

    public func encode() -> Data {
        let list: [[String: Any]] = items.map { item in
            ["key": item.key, "until": item.until.map { Self.isoMillis.string(from: $0) } ?? NSNull(),
             "at": Self.isoMillis.string(from: item.at)]
        }
        let body: [String: Any] = ["version": Self.version, "muted": list]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }
}

/// Файл `muted-waits.json` в папке MyClaude (0600, временный рядом и `rename`): лоадер его не читает. Читают снимок
/// панели, `/digest` и StatusFeed со своих очередей, пишет нажатие в панели — всё под замком; файл перечитывается,
/// когда сменились его время правки или размер.
public final class MutedWaitsStore {
    public static let shared = MutedWaitsStore(file: SupportFiles.directory.appendingPathComponent(MutedWaits.fileName))

    private let lock = NSLock()
    private let file: URL
    private var cached = MutedWaits.empty
    private var stamp: (mtime: Date?, size: Int)?

    public init(file: URL) { self.file = file }

    /// Что заглушено сейчас (истёкшие уже не мешают — их отсекает `isMuted`).
    public func current() -> MutedWaits {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    /// Заглушить строку; false — записать не вышло (в памяти всё как было).
    @discardableResult
    public func mute(_ key: String, until: Date?, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return save(load().muting(key, until: until, now: now))
    }

    /// Снять запись («Отменить»); false — записать не вышло.
    @discardableResult
    public func unmute(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let current = load()
        guard current.items.contains(where: { $0.key == key }) else { return true }
        return save(current.unmuting(key))
    }

    /// Под замком: файл сменился — перечитать; нет файла — пусто.
    private func load() -> MutedWaits {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard let attributes = attributes else {
            stamp = nil
            cached = .empty
            return cached
        }
        let now = (mtime: attributes[.modificationDate] as? Date, size: (attributes[.size] as? NSNumber)?.intValue ?? 0)
        if let known = stamp, known.mtime == now.mtime, known.size == now.size { return cached }
        cached = MutedWaits.parse(try? Data(contentsOf: file))
        stamp = now
        return cached
    }

    private func save(_ next: MutedWaits) -> Bool {
        guard SupportFiles.writeAtomic(file, next.encode()) else { return false }
        cached = next
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        stamp = (attributes?[.modificationDate] as? Date, (attributes?[.size] as? NSNumber)?.intValue ?? 0)
        return true
    }
}

/// Плашка после «Не напоминать» в блоке Workflow: 5 с «Не буду напоминать · Отменить» или 3 с «Не вышло записать».
public struct WaitUndo: Equatable {
    public let key: String
    /// Папка проекта (как у `PanelProject.folder`): плашка встаёт на место его строки.
    public let folder: String
    public let choice: MutedWaits.Choice
    public let at: Date
    /// Записать не вышло: строка остаётся, плашка говорит об этом.
    public let failed: Bool
    /// Нажали в карточке Workflow (true) или в строке «Ждёт тебя» без карточки (`loneWaits`).
    public let inCard: Bool

    public init(key: String, folder: String, choice: MutedWaits.Choice, at: Date, failed: Bool, inCard: Bool) {
        self.key = key
        self.folder = folder
        self.choice = choice
        self.at = at
        self.failed = failed
        self.inCard = inCard
    }

    public static let undoSeconds: TimeInterval = 5
    public static let failSeconds: TimeInterval = 3

    /// Сколько секунд осталось на «Отменить» (5…1); вышло — 0.
    public func left(now: Date) -> Int {
        max(0, Int((Self.undoSeconds - now.timeIntervalSince(at)).rounded(.up)))
    }

    /// «Не буду напоминать час», «… до завтра», «… неделю», «… пока текст тот же».
    public var text: String {
        if failed { return "Не вышло записать — напоминание осталось" }
        switch choice {
        case .hour: return "Не буду напоминать час"
        case .tomorrow: return "Не буду напоминать до завтра"
        case .week: return "Не буду напоминать неделю"
        case .textChange: return "Не буду напоминать, пока текст тот же"
        }
    }
}

extension PanelProjects {
    /// Строки «Ждут тебя» без своей карточки в блоке Workflow (#9820): проекты, у которых есть «Ждёт Элвиса:», но ничего
    /// не идёт — их Workflow в блоке нет, и кнопке «Не напоминать» иначе негде встать. Свежие сверху; `hidden` — ключи,
    /// заглушённые в этом открытии панели (снимок ещё не перечитан).
    public static func loneWaits(_ snapshot: PanelSnapshot, hidden: Set<String> = []) -> [PanelProject] {
        var seen = Set<String>()
        return (snapshot.waiting + snapshot.working + snapshot.others).filter { project in
            guard seen.insert(project.folder).inserted, project.running.isEmpty,
                  !isNothing(project.waitFor) else { return false }
            return !hidden.contains(MutedWaits.key(folder: project.folder, text: project.waitFor))
        }
    }
}
