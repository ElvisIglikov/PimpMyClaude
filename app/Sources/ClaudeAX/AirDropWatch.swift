import AppKit
import CoreGraphics
import Darwin
import Foundation
import Patcher

/// «Фото с AirDrop — в поле Рика» (#9358, слово Элвиса: «когда с аэродропа отправляю фотки — чтоб они сразу вставлялись
/// в окно ввода в Рике»). Сторож папки «Загрузки» — `DispatchSource` на её каталоге, без опроса: событие каталога —
/// короткий досмотр новых имён, пока файлы доезжают (раз в секунду, только пока есть недоехавшие).
///
/// Что считаем фото с AirDrop (проверено на живых «Загрузках» 17.10.2026): AirDrop ставит файлу `com.apple.quarantine`
/// вида `0081;6abbdd65;sharingd;<UUID>` — агент `sharingd`, время — шестнадцатеричные секунды Unix, это и есть время
/// приезда. `kMDItemWhereFroms` у AirDrop пуст, а mtime бывает днём съёмки (фото месячной давности приезжает с mtime
/// месяц назад) — ни тем, ни другим не отбираем. Расширения — те же, что у `pimp.py paste-airdrop` (`PHOTO_EXT`).
///
/// Вставка — тем же путём, что `pimp.py paste-airdrop`: файлы в буфер, окно поднимается, ⌘V (`ClaudeActions.paste`,
/// его же зовёт канал «Пимп»), Enter не жмём никогда; вставили — отметка `voice-pasted.json` (её читает CLI: «вставь
/// фотки» после автовставки скажет «уже вставлял»). Перед ⌘V страницам уходит `airdrop-guard {n}`: страница говорит
/// плашкой «вставил N фото» (раздел 12т²); с #11310 и в поле с текстом — фото ложатся рядом с черновиком.
public final class AirDropWatch {
    /// Ключ `UserDefaults` выключателя «Настроек». Нет ключа — включено там, где есть главный чат (`mainProject`).
    public static let enabledKey = "airDropToMainChat"
    /// Команда страницам перед ⌘V (page-only, раздел 12т²): `{id, action, at, n}`.
    static let guardAction = "airdrop-guard"
    /// Агент карантина у AirDrop.
    static let agent = "sharingd"
    /// = `PHOTO_EXT` в `tools/pimp.py`.
    static let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"]
    /// Сколько файлов за раз (= `AIRDROP_LIMIT` CLI и `PimpChannel.pasteLimit`).
    static let limit = PimpChannel.pasteLimit
    /// Приехал раньше — это не «сейчас скинул» (перенесли старый файл обратно в «Загрузки»).
    static let freshSeconds: TimeInterval = 600
    /// Тишина каталога перед досмотром и шаг досмотра, пока файлы доезжают.
    static let quietSeconds: TimeInterval = 1
    /// Фото без карантина дольше этого — не AirDrop (снимок экрана, сохранённое из браузера руками).
    static let settleSeconds: TimeInterval = 30
    /// Элвис печатает (клавиша была ближе этого) — окно не выдёргиваем, ждём.
    static let typingIdleSeconds: TimeInterval = 2
    /// Ждём тишины клавиатуры не дольше: дальше фото остаются в «Загрузках» с плашкой.
    static let typingWaitSeconds: TimeInterval = 60
    /// Пауза между записью `airdrop-guard` и ⌘V: лоадер читает `command.json` раз в 500 мс.
    static let armSeconds: TimeInterval = 0.8
    static let noticeSeconds: TimeInterval = 4
    /// Каталог не открылся — пробуем снова не чаще.
    static let retrySeconds: TimeInterval = 60

    /// Новый файл каталога глазами сторожа.
    struct Entry: Equatable {
        let name: String
        let path: String
        let size: Int64
        let mtime: Double
        /// Значение `com.apple.quarantine`; nil — атрибута нет.
        let quarantine: String?
    }

    enum Verdict: Equatable { case ready, settling, skip }

    // MARK: - чистая часть

    /// Выключатель: явный выбор сильнее; нет выбора — включено, если главный чат задан.
    public static func isEnabled(in defaults: UserDefaults, mainProject: String?) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func isPhoto(_ name: String) -> Bool {
        !name.hasPrefix(".") && photoExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// `flags;время16;агент;UUID` → агент и время приезда; не разобрать — nil.
    static func quarantine(_ raw: String?) -> (agent: String, at: Date)? {
        guard let parts = raw?.split(separator: ";", omittingEmptySubsequences: false), parts.count >= 3,
              let seconds = UInt64(parts[1], radix: 16) else { return nil }
        return (agent: String(parts[2]), at: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    /// Готов ли файл: карантин AirDrop свежий и размер не изменился с прошлого досмотра. Без карантина — ждём его
    /// `settleSeconds` (атрибут ложится в конце приёма); чужой агент или давний приезд — мимо навсегда.
    static func verdict(_ entry: Entry, previousSize: Int64?, firstSeen: Date, now: Date) -> Verdict {
        guard let mark = quarantine(entry.quarantine) else {
            return now.timeIntervalSince(firstSeen) < settleSeconds ? .settling : .skip
        }
        guard mark.agent == agent, now.timeIntervalSince(mark.at) <= freshSeconds else { return .skip }
        return entry.size > 0 && previousSize == entry.size ? .ready : .settling
    }

    /// Отметка CLI (`voice-pasted.json`, `{"mtime": …}`): нет файла или мусор — 0.
    static func mark(_ data: Data?) -> Double {
        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let value = json["mtime"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return 0 }
        return value.doubleValue.isFinite ? value.doubleValue : 0
    }

    /// Тело отметки — как пишет CLI (`json.dumps({"mtime": …}, separators=(",", ":"))`).
    static func markBody(_ mtime: Double) -> String { "{\"mtime\":\(mtime)}\n" }

    static func guardFields(count: Int) -> [(key: String, value: CommandValue)] {
        [(key: "n", value: .number(count))]
    }

    /// Плашка отказа: что не вставили, почему и где фото.
    static func refusal(count: Int, _ why: String) -> String {
        "📲 \(count) фото с AirDrop не вставил: \(why) — они в «Загрузках»"
    }

    // MARK: - сторож

    /// Отдать порцию (пути по времени приезда); `done(true)` — ⌘V нажат.
    var onBatch: (([String], @escaping (Bool) -> Void) -> Void)?
    var onNotice: ((String) -> Void)?
    /// Окна заняты своей цепочкой (новое окно, возврат раскладки) — подождать, как с клавиатурой.
    var blocked: () -> Bool = { false }
    var idleSeconds: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }
    var now: () -> Date = Date.init
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
    var listNames: (URL) -> [String]? = { try? FileManager.default.contentsOfDirectory(atPath: $0.path) }
    var inspect: (URL) -> Entry? = AirDropWatch.entry(at:)

    let directory: URL
    let markURL: URL
    public private(set) var running = false
    private var starting = false
    /// Доступа к каталогу не дали — следующая попытка не раньше этого.
    private var retryAt: Date?
    private var source: DispatchSourceFileSystemObject?
    /// Имена, что лежали до старта, и уже решённые: мимо. Пропал файл — имя забываем (тот же снимок, присланный
    /// заново после удаления, — новый).
    private var baseline: Set<String> = []
    private var handled: Set<String> = []
    private var sizes: [String: Int64] = [:]
    private var firstSeen: [String: Date] = [:]
    private var scanQueued = false
    private var inFlight = false
    private var waitingSince: Date?
    private var deniedShown = false

    init(directory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads"),
         markURL: URL = SupportFiles.directory.appendingPathComponent("voice-pasted.json")) {
        self.directory = directory
        self.markURL = markURL
    }

    /// Включить или выключить по выключателю; повторный вызов с тем же — ничего (его зовёт тик).
    func apply(enabled: Bool) {
        if enabled, !running, retryAt.map({ now() >= $0 }) ?? true { start() }
        else if !enabled, running || starting || retryAt != nil { stop() }
    }

    /// Каталог открывается в фоне: первый доступ к «Загрузкам» macOS держит до ответа на свой вопрос, и главная нить
    /// на это время не встаёт. Не открылся (доступа нет) — одна плашка на включение; тик пробует снова.
    func start() {
        guard !running, !starting else { return }
        starting = true
        let directory = self.directory, listNames = self.listNames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fd = open(directory.path, O_EVTONLY)
            let names = fd >= 0 ? listNames(directory) : nil
            DispatchQueue.main.async {
                guard let self = self, self.starting else {
                    if fd >= 0 { close(fd) }
                    return
                }
                self.starting = false
                guard fd >= 0, let names = names else {
                    if fd >= 0 { close(fd) }
                    self.retryAt = self.now().addingTimeInterval(AirDropWatch.retrySeconds)
                    if !self.deniedShown {
                        self.deniedShown = true
                        self.onNotice?("📲 Фото с AirDrop: macOS не дал PMP папку «Загрузки» — разреши в «Конфиденциальность ▸ Файлы и папки»")
                    }
                    return
                }
                self.begin(fd: fd, names: names)
            }
        }
    }

    /// Сторож встал: имена, что уже лежат, — мимо; события каталога — досмотр после тишины.
    func begin(fd: Int32, names: [String]) {
        baseline = Set(names)
        handled = []
        sizes = [:]
        firstSeen = [:]
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                                   queue: .main)
            source.setEventHandler { [weak self] in self?.scanSoon() }
            source.setCancelHandler { close(fd) }
            source.resume()
            self.source = source
        }
        running = true
    }

    func stop() {
        source?.cancel()
        source = nil
        running = false
        starting = false
        retryAt = nil
        deniedShown = false
        waitingSince = nil
    }

    func scanSoon(_ delay: TimeInterval = AirDropWatch.quietSeconds) {
        guard running, !scanQueued else { return }
        scanQueued = true
        schedule(delay) { [weak self] in
            self?.scanQueued = false
            self?.scan()
        }
    }

    /// Досмотр новых имён. Готовые отдаются одной порцией, когда больше никто не доезжает; пока доезжают — ещё раз
    /// через секунду.
    func scan() {
        guard running, let names = listNames(directory).map(Set.init) else { return }
        baseline.formIntersection(names)
        handled.formIntersection(names)
        sizes = sizes.filter { names.contains($0.key) }
        firstSeen = firstSeen.filter { names.contains($0.key) }
        let at = now()
        var ready: [(entry: Entry, at: Date)] = []
        var settling = false
        for name in names.sorted() where !baseline.contains(name) && !handled.contains(name) && AirDropWatch.isPhoto(name) {
            guard let entry = inspect(directory.appendingPathComponent(name)) else { continue }
            let first = firstSeen[name] ?? at
            firstSeen[name] = first
            switch AirDropWatch.verdict(entry, previousSize: sizes[name], firstSeen: first, now: at) {
            case .ready: ready.append((entry, AirDropWatch.quarantine(entry.quarantine)?.at ?? at))
            case .settling: settling = true
            case .skip: handled.insert(name)
            }
            sizes[name] = entry.size
        }
        guard !ready.isEmpty else {
            waitingSince = nil
            if settling { scanSoon() }
            return
        }
        // Порция доезжает — ждём всю; занято (вставка идёт, Элвис печатает, окна в работе) — ждём тишины.
        let typing = idleSeconds() < AirDropWatch.typingIdleSeconds
        let busy = inFlight || blocked() || typing
        if settling || busy {
            if busy, !inFlight {
                let since = waitingSince ?? at
                waitingSince = since
                if at.timeIntervalSince(since) >= AirDropWatch.typingWaitSeconds {
                    waitingSince = nil
                    ready.forEach { handled.insert($0.entry.name) }
                    onNotice?(AirDropWatch.refusal(count: ready.count, typing ? "ты печатал — скажи «вставь фотки»"
                                                                            : "окна Claude были заняты — скажи «вставь фотки»"))
                    return
                }
            }
            scanSoon()
            return
        }
        waitingSince = nil
        let batch = ready.sorted { ($0.at, $0.entry.name) < ($1.at, $1.entry.name) }.prefix(AirDropWatch.limit).map { $0.entry }
        batch.forEach { handled.insert($0.name) }
        if ready.count > batch.count { scanSoon() }
        inFlight = true
        guard let deliver = onBatch else {
            inFlight = false
            return
        }
        deliver(batch.map { $0.path }) { [weak self] pressed in
            guard let self = self else { return }
            self.inFlight = false
            if pressed { self.writeMark(batch.map { $0.mtime }.max() ?? 0) }
        }
    }

    /// Отметка CLI только растёт: старое фото (mtime — день съёмки) её назад не отматывает.
    private func writeMark(_ mtime: Double) {
        let current = AirDropWatch.mark(try? Data(contentsOf: markURL))
        guard mtime > current else { return }
        _ = SupportFiles.writeAtomic(markURL, Data(AirDropWatch.markBody(mtime).utf8))
    }

    /// Размер, mtime и карантин файла; не обычный файл или пропал — nil.
    static func entry(at url: URL) -> Entry? {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let mtime = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
        return Entry(name: url.lastPathComponent, path: url.path, size: Int64(info.st_size), mtime: mtime,
                     quarantine: xattr(url.path, "com.apple.quarantine"))
    }

    private static func xattr(_ path: String, _ name: String) -> String? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW)
        guard read > 0 else { return nil }
        return String(decoding: buffer.prefix(read), as: UTF8.self)
    }
}

extension ClaudeAXController {
    // MARK: - фото с AirDrop в поле Рика (#9358)

    /// Состояние выключателя «Настроек» (с умолчанием по главному чату).
    public var airDropEnabled: Bool {
        AirDropWatch.isEnabled(in: .standard, mainProject: mainProjectSetting())
    }

    public func setAirDrop(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: AirDropWatch.enabledKey)
        applyAirDrop()
    }

    /// Сторож — по выключателю; зовут старт, тик (главный чат мог появиться) и выключатель.
    func applyAirDrop() {
        if airDrop.onBatch == nil {
            airDrop.onBatch = { [weak self] paths, done in
                guard let self = self else { return done(false) }
                self.pasteAirDrop(paths, done: done)
            }
            airDrop.onNotice = { [weak self] text in self?.hud.show(text, seconds: AirDropWatch.noticeSeconds) }
            airDrop.blocked = { [weak self] in self.map { $0.app.running() != nil && $0.isSettlingWindows } ?? false }
        }
        airDrop.apply(enabled: started && airDropEnabled)
    }

    /// Окно главного проекта (в фокусе — оно, иначе первое), `airdrop-guard` страницам, пауза на доставку — и ⌘V тем же
    /// `ClaudeActions.paste`, что у канала «Пимп».
    private func pasteAirDrop(_ paths: [String], done: @escaping (Bool) -> Void) {
        let count = paths.count
        let refuse: (String) -> Void = { [weak self] why in
            self?.hud.show(AirDropWatch.refusal(count: count, why), seconds: AirDropWatch.noticeSeconds)
            done(false)
        }
        guard app.running() != nil else { return refuse("Claude не запущен") }
        guard let entry = mainProjectSetting() else { return refuse("главный чат не задан") }
        let mine = pimpWindowList().filter { PimpChannel.matches(window: $0, entry: entry) }
        guard !mine.isEmpty else {
            chatProbe.demand(at: Date())
            return refuse("окна \(PimpChannel.projectName(entry)) не нашёл")
        }
        let front = actions.frontWindowID()
        let target = mine.first { $0.id == front } ?? mine[0]
        commands.write(action: AirDropWatch.guardAction, fields: AirDropWatch.guardFields(count: count)) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + AirDropWatch.armSeconds) {
                guard let self = self else { return done(false) }
                self.actions.paste(into: target.id, paths: paths) { pressed in
                    if !pressed { refuse("окно «\(target.title)» не встало вперёд") } else { done(true) }
                }
            }
        }
    }
}
