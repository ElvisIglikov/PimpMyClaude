import Darwin
import Foundation
import Security

// Обновление самого Пимпа и PimpViewer (WF217, #9410; контракт К-SU в docs/CONTRACTS.md). Образец —
// `ClaudeUpdater`: скачать заранее, проверить, поставить в тихий момент. Отличие: здесь ставится код автора
// Пимпа, поэтому источник один (выпуски GitHub), а верим не источнику, а подписи.
//   1. `check` — последний выпуск репозитория; новее стоящего — архив в свою папку `self-update/` (0700,
//      файлы 0600) и ВСЕ проверки `verify`: одно приложение с нужным именем и bundle id, строгая подпись
//      Developer ID команды F27N4S4NJ4, Gatekeeper, права без записи чужим, версия равна выпуску и выше стоящей.
//      Любая осечка — архив удалён, версия на сутки отложена, строка в журнал; на экране ничего.
//   2. `install` — в тихий момент (`mayInstall`): архив сверен с суммой, распакован и проверен ЗАНОВО,
//      новое приложение меняется местами со старым одним системным вызовом (тот же том), подпись проверяется
//      ещё раз уже на месте (находка М7 проверки 10.10.2026); не сошлось — старое возвращается обратным обменом.
//      Старое уходит в `self-update/rollback/` (одна прошлая версия, имя без `.app`).
// Папка отката — для человека: сам код из неё ничего не ставит (находка М3). Сети кроме GitHub нет.

/// Что обновляем: имя бандла, репозиторий выпусков, bundle id.
public struct SelfUpdateProduct: Equatable {
    /// Ключ в `state.json`.
    public let key: String
    /// Имя для людей: «Пимп», «Viewer».
    public let title: String
    /// Имя бандла без `.app` — оно же начало имени архива.
    public let name: String
    /// `владелец/репозиторий` на GitHub.
    public let repo: String
    public let bundleID: String

    public static let pimp = SelfUpdateProduct(key: "pimp", title: "Пимп", name: "PimpMyClaude",
                                               repo: "ElvisIglikov/PimpMyClaude", bundleID: "com.elvis.pimpmyclaude")
    public static let viewer = SelfUpdateProduct(key: "viewer", title: "Viewer", name: "PimpViewer",
                                                 repo: "ElvisIglikov/PimpViewer", bundleID: "com.elvis.pimpviewer")

    public var appName: String { name + ".app" }
    /// Имя вложения выпуска — как кладёт `tools/release.sh`: `PimpMyClaude-1.10.20.zip`.
    public func assetName(_ version: String) -> String { "\(name)-\(version).zip" }
    public var latestURL: URL { URL(string: "https://api.github.com/repos/\(repo)/releases/latest")! }
    public func assetURL(tag: String, version: String) -> URL {
        URL(string: "https://github.com/\(repo)/releases/download/\(tag)/\(assetName(version))")!
    }

    /// Требование к подписи: этот bundle id, цепочка Apple, промежуточный Developer ID CA, лист Developer ID
    /// Application, команда F27N4S4NJ4 — тот же вид, что macOS пишет приложениям Developer ID сама.
    public var requirement: String {
        "identifier \"\(bundleID)\" and anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(SelfUpdater.teamID)\""
    }
}

/// Выпуск GitHub, из которого берём архив.
public struct SelfUpdateRelease: Equatable {
    public let version: String
    public let tag: String
    public let asset: String
    public let size: Int64
    /// sha256 вложения из ответа GitHub (`digest`); nil — GitHub его не прислал.
    public let sha256: String?
    public let url: URL
}

public enum SelfUpdateError: Error, Equatable {
    /// Сети нет или GitHub не ответил.
    case offline(String)
    /// Выпусков не видно: 404/403 и gh не помог (репозиторий закрыт, gh нет или не вошёл).
    case missing(String)
    /// Выпуск не подходит: черновик, пред-выпуск, нет вложения с нужным именем.
    case release(String)
    case archive(String)
    case bundle(String)
    case signature(String)
    case gatekeeper(String)
    case version(String)
    /// Сюда не ставим: не «Программы» или нельзя писать.
    case place(String)
    case swap(String, restored: Bool)
    /// Распаковка или проверка не уложилась в срок. При установке это не изъян версии: она уже проверена при
    /// загрузке, архив остаётся и ждёт следующего момента (находка R3 проверки 10.10.2026).
    case timeout(String)

    /// Начало причины в `refusedWhy`, когда версия прошла проверки, но не встала на место — по нему строка
    /// настроек отличает «не встала на место» от «не прошла проверку».
    static let swapWord = "подмена сорвалась"

    public var text: String {
        switch self {
        case .offline(let why): return "нет связи с GitHub: \(why)"
        case .missing(let why): return "выпусков не видно: \(why)"
        case .release(let why): return "выпуск не подходит: \(why)"
        case .archive(let why): return "архив не тот: \(why)"
        case .bundle(let why): return "приложение не то: \(why)"
        case .signature(let why): return "подпись не прошла: \(why)"
        case .gatekeeper(let why): return "Gatekeeper не принял: \(why)"
        case .version(let why): return "версия не та: \(why)"
        case .place(let why): return "не ставлю: \(why)"
        case .swap(let why, let restored):
            return "\(Self.swapWord): \(why); " + (restored ? "прежняя версия на месте" : "прежняя версия лежит в папке отката")
        case .timeout(let why): return "не дождался: \(why)"
        }
    }
}

/// Что запомнено между запусками (`self-update/state.json`).
public struct SelfUpdateState: Codable, Equatable {
    public enum Problem: String, Codable { case offline, missing }

    public struct Product: Codable, Equatable {
        /// Когда последний раз спрашивали источник — от него считается пауза.
        public var attemptedAt: Date?
        /// Когда источник последний раз ответил.
        public var checkedAt: Date?
        /// Последний запрос не удался — почему.
        public var problem: Problem?
        public var latest: String?
        /// Версия, которая скачана и прошла все проверки; её архив лежит рядом.
        public var ready: String?
        public var readySHA256: String?
        /// Версия, не прошедшая проверку или не вставшая на место, — сутки её не качаем.
        public var refused: String?
        public var refusedAt: Date?
        public var refusedWhy: String?

        public init() {}
    }

    /// Автообновление прошло — панель скажет об этом одной строкой при первом открытии.
    public struct Note: Codable, Equatable {
        public let product: String
        public let from: String
        public let to: String
    }

    public var products: [String: Product] = [:]
    public var notes: [Note] = []

    public init() {}
}

/// Что сейчас происходит на Маке — можно ли подменять приложение.
public struct SelfUpdateMoment: Equatable {
    /// Переключатель «Обновлять Пимп и Viewer самим».
    public var enabled = true
    public var panelOpen = false
    /// Идёт патч, обновление Claude или его загрузка.
    public var busy = false
    /// Диктатор пишет в окно Claude.
    public var recording = false
    public var viewerRunning = false
    /// Канал «Пимп» занят или окна Claude ещё не «как были» (возврат снимка К5 ждёт или идёт) — Пимп себя
    /// не подменяет: его выход оборвал бы возврат, а запрос канала получил бы `stale` (находка R2 проверки
    /// 10.10.2026). Viewer это не держит: его подмена Пимп не перезапускает.
    public var windows = false

    public init(enabled: Bool = true, panelOpen: Bool = false, busy: Bool = false, recording: Bool = false,
                viewerRunning: Bool = false, windows: Bool = false) {
        self.enabled = enabled
        self.panelOpen = panelOpen
        self.busy = busy
        self.recording = recording
        self.viewerRunning = viewerRunning
        self.windows = windows
    }
}

/// Откуда берём выпуск и архив. Тесты подставляют свои.
public struct SelfUpdateTransport {
    /// Тело ответа `releases/latest`.
    public var latest: (SelfUpdateProduct) -> Result<Data, SelfUpdateError>
    /// Архив выпуска — в файл.
    public var download: (SelfUpdateRelease, SelfUpdateProduct, URL) -> Result<Void, SelfUpdateError>

    public init(latest: @escaping (SelfUpdateProduct) -> Result<Data, SelfUpdateError>,
                download: @escaping (SelfUpdateRelease, SelfUpdateProduct, URL) -> Result<Void, SelfUpdateError>) {
        self.latest = latest
        self.download = download
    }
}

/// Проверки подписи. Ответ — причина отказа, nil — прошла. Тесты подставляют свои.
public struct SelfUpdateChecks {
    /// Строгая проверка подписи с требованием (как `codesign --verify --deep --strict -R=…`).
    public var signature: (_ app: URL, _ requirement: String) -> String?
    /// Нотаризация и Gatekeeper (`spctl --assess --type execute`).
    public var gatekeeper: (_ app: URL) -> String?

    public init(signature: @escaping (URL, String) -> String?, gatekeeper: @escaping (URL) -> String?) {
        self.signature = signature
        self.gatekeeper = gatekeeper
    }
}

public struct SelfUpdater {
    /// Team ID сертификата Developer ID «ELVIS IGLIKOV» — им подписаны Пимп и PimpViewer.
    public static let teamID = "F27N4S4NJ4"
    public static let directoryName = "self-update"
    /// Фоновая проверка — не чаще.
    public static let checkInterval: TimeInterval = 6 * 60 * 60
    /// Проверка на запуске Пимпа или Claude — не чаще (общий лимит GitHub без входа — 60 запросов в час на адрес).
    public static let launchInterval: TimeInterval = 15 * 60
    /// Версию, не прошедшую проверку, не качаем заново столько.
    public static let refusedPause: TimeInterval = 24 * 60 * 60
    public static let maxArchiveBytes: Int64 = 300_000_000

    public var directory: URL
    public var transport = SelfUpdateTransport.live
    public var checks = SelfUpdateChecks.live
    /// В каких папках приложение можно подменять.
    public var allowedParents = SelfUpdater.standardParents
    /// Сколько ждём каждый шаг проверки скачанного: распаковку, подпись, Gatekeeper. На запуске Пимпа водитель
    /// ставит меньше — там главная нитка и значка у часов ещё нет (находка R3 проверки 10.10.2026).
    public var patience: TimeInterval = 60
    var now: () -> Date = Date.init

    public init(directory: URL = Patcher.defaultSupportDirectory.appendingPathComponent(SelfUpdater.directoryName, isDirectory: true)) {
        self.directory = directory
    }

    public static var standardParents: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
    }

    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var journalURL: URL { directory.appendingPathComponent("journal.log") }
    var rollbackDirectory: URL { directory.appendingPathComponent("rollback", isDirectory: true) }
    func archiveURL(_ product: SelfUpdateProduct, _ version: String) -> URL {
        directory.appendingPathComponent(product.assetName(version))
    }

    // -------------------------------------------------------------- чистые правила (под тестом)

    /// Версия — только цифры через точку, без пробелов и хвостов.
    static func isVersion(_ text: String) -> Bool {
        text.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") } && ClaudeUpdater.compareVersions(text, text) != nil
    }

    /// `a` строго новее `b` — числами по частям (1.10.19 > 1.10.9); мусор не новее ничего.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        isVersion(a) && isVersion(b) && ClaudeUpdater.compareVersions(a, b) == .orderedDescending
    }

    /// Последний выпуск из ответа GitHub: не черновик и не пред-выпуск, версия — тег без «v», вложение ровно
    /// одно, с именем `<Имя>-<версия>.zip`, загружено, ссылка — закреплённая на этот же репозиторий и тег.
    public static func parseRelease(_ data: Data, product: SelfUpdateProduct) throws -> SelfUpdateRelease {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SelfUpdateError.release("ответ GitHub не разобрался")
        }
        guard json["draft"] as? Bool == false else { throw SelfUpdateError.release("черновик") }
        guard json["prerelease"] as? Bool == false else { throw SelfUpdateError.release("пред-выпуск") }
        guard let tag = json["tag_name"] as? String else { throw SelfUpdateError.release("нет тега") }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isVersion(version) else {
            throw SelfUpdateError.release("тег «\(tag.prefix(40))» — не версия")
        }
        let name = product.assetName(version)
        let assets = (json["assets"] as? [[String: Any]] ?? []).filter { $0["name"] as? String == name }
        guard assets.count == 1, let asset = assets.first else {
            throw SelfUpdateError.release("нет вложения \(name)")
        }
        let url = product.assetURL(tag: tag, version: version)
        guard asset["state"] as? String == "uploaded",
              asset["browser_download_url"] as? String == url.absoluteString,
              let size = asset["size"] as? NSNumber, CFGetTypeID(size) != CFBooleanGetTypeID(),
              size.int64Value > 0, size.int64Value <= maxArchiveBytes, size.doubleValue == Double(size.int64Value) else {
            throw SelfUpdateError.release("вложение \(name) не загружено или не того вида")
        }
        var sha: String?
        if let digest = asset["digest"] as? String {
            let hex = digest.hasPrefix("sha256:") ? String(digest.dropFirst(7)).lowercased() : ""
            guard hex.count == 64, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                throw SelfUpdateError.release("у вложения \(name) непонятная сумма")
            }
            sha = hex
        }
        return SelfUpdateRelease(version: version, tag: tag, asset: name, size: size.int64Value, sha256: sha, url: url)
    }

    /// Пора ли спрашивать источник: с прошлой попытки (удачной или нет) прошло не меньше `interval`.
    public static func shouldCheck(_ state: SelfUpdateState.Product?, now: Date, interval: TimeInterval) -> Bool {
        guard let last = state?.attemptedAt else { return true }
        let elapsed = now.timeIntervalSince(last)
        return elapsed < 0 || elapsed >= interval
    }

    /// Можно ли подменять приложение сейчас: никогда посреди открытой панели, записи, патча или обновления
    /// Claude; PimpViewer — ещё и только когда он не запущен; Пимп — ещё и не посреди работы канала «Пимп» и
    /// возврата окон. Выключено — никогда.
    public static func mayInstall(_ product: SelfUpdateProduct, _ moment: SelfUpdateMoment) -> Bool {
        guard moment.enabled, !moment.panelOpen, !moment.busy, !moment.recording else { return false }
        return product == .viewer ? !moment.viewerRunning : !moment.windows
    }

    /// Адреса, куда может ходить загрузка: только GitHub по HTTPS, без учёток и чужих портов.
    static func allowedHost(_ url: URL?) -> Bool {
        guard let url = url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "api.github.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// Версия стоящего приложения; nil — Info.plist не читается или bundle id не тот.
    public static func installedVersion(_ app: URL, bundleID: String) -> String? {
        guard let info = info(app), info["CFBundleIdentifier"] as? String == bundleID else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    static func info(_ app: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Почему в это место не ставим; nil — можно. Ставим только туда, откуда запущено, и только если это
    /// «Программы» (общие или свои) с правом записи: сборку разработчика и копию на рабочем столе не трогаем.
    public func placeProblem(_ app: URL, product: SelfUpdateProduct) -> String? {
        func key(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
        let real = app.resolvingSymlinksInPath().standardizedFileURL
        guard real.lastPathComponent == product.appName,
              allowedParents.contains(where: { key($0) == real.deletingLastPathComponent().path }) else {
            return "\(product.title) лежит не в «Программах»"
        }
        guard FileManager.default.isWritableFile(atPath: real.deletingLastPathComponent().path) else {
            return "в «Программы» нельзя писать"
        }
        // Обмен переносит в другую папку сам бандл, а на это нужна запись в НЕГО, не только в «Программы»
        // (находка R1 проверки 10.10.2026): чужой или закрытый бандл скачивался бы и не вставал без срока.
        var bundle = stat()
        guard stat(real.path, &bundle) == 0, bundle.st_uid == getuid() else {
            return "\(product.title) в «Программах» положен другой учёткой"
        }
        guard access(real.path, W_OK) == 0 else { return "\(product.title) в «Программах» закрыт от записи" }
        // Подмена — переименованием, а оно атомарно только в пределах тома: папка отката лежит у нас.
        var ours = directory
        while !FileManager.default.fileExists(atPath: ours.path), ours.pathComponents.count > 1 { ours.deleteLastPathComponent() }
        guard let here = Self.device(real.deletingLastPathComponent()), here == Self.device(ours) else {
            return "«Программы» на другом диске"
        }
        return nil
    }

    private static func device(_ url: URL) -> dev_t? {
        var info = stat()
        return stat(url.path, &info) == 0 ? info.st_dev : nil
    }

    // -------------------------------------------------------------- слова для панели

    /// «сегодня в 05:10», «вчера в 23:40», «08.10 в 05:10».
    static func whenText(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "сегодня в \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "вчера в \(time)"
        }
        formatter.dateFormat = "dd.MM"
        return "\(formatter.string(from: date)) в \(time)"
    }

    /// Тихая строка под переключателем: что стоит и что с обновлением. `place` — причина из `placeProblem`.
    public static func statusLine(installed: String, state: SelfUpdateState.Product?, enabled: Bool, place: String?,
                                  now: Date, calendar: Calendar = .current) -> String {
        let stands = "Стоит \(installed)"
        guard enabled else { return stands }
        if let place = place { return "\(stands) · \(place) — сам не обновится" }
        guard let state = state else { return stands }
        if let ready = state.ready, isNewer(ready, than: installed) {
            return "Скачано \(ready) — встанет при следующем запуске"
        }
        if let refused = state.refused, isNewer(refused, than: installed) {
            let swap = state.refusedWhy?.hasPrefix(SelfUpdateError.swapWord) == true
            return "\(stands) · \(refused) \(swap ? "не встала на место" : "не прошла проверку") — не ставлю"
        }
        switch state.problem {
        case .offline?: return "\(stands) · нет связи с GitHub"
        case .missing?: return "\(stands) · выпусков на GitHub не видно"
        case nil: break
        }
        guard let checked = state.checkedAt else { return stands }
        return "\(stands) · проверено \(whenText(checked, now: now, calendar: calendar))"
    }

    /// Хвост про Viewer к строке Пимпа — только когда его обновление ждёт закрытия.
    public static func viewerLine(installed: String?, state: SelfUpdateState.Product?) -> String? {
        guard let installed = installed, let ready = state?.ready, isNewer(ready, than: installed) else { return nil }
        return "Viewer \(ready) скачан — встанет, когда его закроешь"
    }

    /// «Пимп обновился до 1.10.20» — одна строка панели после автообновления; по продукту — последняя запись.
    public static func noteLine(_ notes: [SelfUpdateState.Note]) -> String? {
        let lines = [SelfUpdateProduct.pimp, .viewer].compactMap { product in
            notes.last { $0.product == product.key }.map { "\(product.title) обновился до \($0.to)" }
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    // -------------------------------------------------------------- состояние и журнал

    public func loadState() -> SelfUpdateState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? Data(contentsOf: stateURL), let state = try? decoder.decode(SelfUpdateState.self, from: data) else {
            return SelfUpdateState()
        }
        return state
    }

    func saveState(_ state: SelfUpdateState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        write(data, to: stateURL)
    }

    /// Панель показала строку «обновился» — больше не показывать.
    public func clearNotes() {
        var state = loadState()
        guard !state.notes.isEmpty else { return }
        state.notes = []
        saveState(state)
    }

    /// Своя папка 0700, файлы 0600 — другим учёткам этого Мака туда хода нет.
    private func prepareDirectory(_ url: URL? = nil) throws {
        let target = url ?? directory
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
    }

    private func write(_ data: Data, to url: URL) {
        guard (try? prepareDirectory()) != nil, (try? data.write(to: url, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Строка в `journal.log`; файл держим коротким — хвост в 64 КБ.
    func log(_ product: SelfUpdateProduct, _ line: String) {
        var text = (try? String(contentsOf: journalURL, encoding: .utf8)) ?? ""
        text += "\(ISO8601DateFormatter().string(from: now())) \(product.key): \(line)\n"
        if text.utf8.count > 64 * 1024 {
            text = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(200).joined(separator: "\n") + "\n"
        }
        write(Data(text.utf8), to: journalURL)
    }

    // -------------------------------------------------------------- 1. проверить выпуск и скачать заранее

    /// Один круг по продукту: спросить выпуск, новее стоящего — скачать и проверить. Ничего не ставит и
    /// ничего не показывает: исход — в `state.json` и журнале. `proceed` спрашивается перед каждым шагом
    /// (запрос, загрузка, проверка): «нет» — круг кончается на этом месте (выключатель, находка R8 проверки
    /// 10.10.2026).
    @discardableResult
    public func check(_ product: SelfUpdateProduct, app: URL, proceed: () -> Bool = { true }) -> SelfUpdateState.Product {
        var state = loadState()
        var entry = state.products[product.key] ?? SelfUpdateState.Product()
        entry.attemptedAt = now()
        round(product, app: app, entry: &entry, proceed: proceed)
        state.products[product.key] = entry
        saveState(state)
        return entry
    }

    private func round(_ product: SelfUpdateProduct, app: URL, entry: inout SelfUpdateState.Product, proceed: () -> Bool) {
        let fm = FileManager.default
        // Ставить некуда (сборка разработчика, копия не в «Программах») — и спрашивать незачем: без сети.
        guard placeProblem(app, product: product) == nil,
              let installed = Self.installedVersion(app, bundleID: product.bundleID) else { return }
        // Стоящая версия догнала скачанное (поставили руками) — архив больше не нужен.
        if let ready = entry.ready, !Self.isNewer(ready, than: installed) { forgetReady(product, &entry) }
        sweep(product, keep: entry.ready)
        guard proceed() else { return }
        let release: SelfUpdateRelease
        do {
            release = try Self.parseRelease(try transport.latest(product).get(), product: product)
        } catch {
            if case SelfUpdateError.offline = error { entry.problem = .offline } else { entry.problem = .missing }
            log(product, Self.describe(error))
            return
        }
        entry.problem = nil
        entry.checkedAt = now()
        entry.latest = release.version
        guard Self.isNewer(release.version, than: installed) else { return }
        let archive = archiveURL(product, release.version)
        if entry.ready == release.version, fm.fileExists(atPath: archive.path) { return }
        if entry.refused == release.version, let at = entry.refusedAt, now().timeIntervalSince(at) < Self.refusedPause { return }

        forgetReady(product, &entry) // прежний архив — более старой версии
        guard proceed(), (try? prepareDirectory()) != nil else { return }
        if case .failure(let error) = transport.download(release, product, archive) {
            try? fm.removeItem(at: archive)
            // Пришло больше, чем обещал выпуск, — изъян выпуска, а не связи: тот же отказ на сутки, что и за
            // несошедшийся размер (находка R6 проверки 10.10.2026).
            if case SelfUpdateError.archive = error { return refuse(product, version: release.version, error, &entry) }
            entry.problem = .offline
            log(product, "\(release.version) не скачалась: \(Self.describe(error))")
            return
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        // Выключили, пока качалось, — не проверяем и не держим: непроверенный архив ничего не ждёт.
        guard proceed() else { try? fm.removeItem(at: archive); return }
        do {
            let size = (try? fm.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.int64Value ?? -1
            guard size == release.size else { throw SelfUpdateError.archive("размер \(size), выпуск обещал \(release.size)") }
            let sha = try ClaudeUpdater.sha256(of: archive)
            if let expected = release.sha256, expected != sha { throw SelfUpdateError.archive("сумма не сошлась с выпуском") }
            let staged = try verify(archive: archive, product: product, version: release.version, installed: installed)
            try? fm.removeItem(at: staged.deletingLastPathComponent())
            entry.ready = release.version
            entry.readySHA256 = sha
            entry.refused = nil
            entry.refusedAt = nil
            entry.refusedWhy = nil
            log(product, "\(release.version) скачана и проверена, встанет в тихий момент")
        } catch {
            try? fm.removeItem(at: archive)
            refuse(product, version: release.version, error, &entry)
        }
    }

    /// Хвосты оборванных кругов: распаковки и архивы продукта, кроме того, что ждёт установки.
    private func sweep(_ product: SelfUpdateProduct, keep: String?) {
        let kept = keep.map { product.assetName($0) }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        where name.hasPrefix("unpack-") || (name.hasPrefix(product.name + "-") && name.hasSuffix(".zip") && name != kept) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func forgetReady(_ product: SelfUpdateProduct, _ entry: inout SelfUpdateState.Product) {
        if let ready = entry.ready { try? FileManager.default.removeItem(at: archiveURL(product, ready)) }
        entry.ready = nil
        entry.readySHA256 = nil
    }

    private func refuse(_ product: SelfUpdateProduct, version: String, _ error: Error, _ entry: inout SelfUpdateState.Product) {
        entry.ready = nil
        entry.readySHA256 = nil
        entry.refused = version
        entry.refusedAt = now()
        entry.refusedWhy = Self.describe(error)
        log(product, "\(version) не ставлю — \(Self.describe(error)); архив удалён")
    }

    static func describe(_ error: Error) -> String {
        (error as? SelfUpdateError)?.text ?? (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // -------------------------------------------------------------- проверка скачанного

    /// Все проверки скачанного, по порядку; любая не прошла — распаковка удалена, ошибка наружу.
    /// Удача — путь к проверенному приложению во временной папке 0700 (её убирает вызывающий).
    func verify(archive: URL, product: SelfUpdateProduct, version: String, installed: String) throws -> URL {
        let fm = FileManager.default
        let box = directory.appendingPathComponent("unpack-\(UUID().uuidString)", isDirectory: true)
        try prepareDirectory()
        try prepareDirectory(box)
        do {
            guard let unzip = Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, box.path], timeout: patience) else {
                throw SelfUpdateError.timeout("распаковка не уложилась в срок")
            }
            guard unzip.status == 0 else { throw SelfUpdateError.archive("не распаковался") }
            // Внутри ровно одно приложение с ожидаемым именем — и больше ничего.
            let names = ((try? fm.contentsOfDirectory(atPath: box.path)) ?? []).filter { $0 != "__MACOSX" }
            guard names == [product.appName] else {
                throw SelfUpdateError.archive("внутри не одно \(product.appName), а: \(names.sorted().joined(separator: ", ").prefix(120))")
            }
            let app = box.appendingPathComponent(product.appName, isDirectory: true)
            let values = try? app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values?.isSymbolicLink == false, values?.isDirectory == true, let info = Self.info(app) else {
                throw SelfUpdateError.bundle("\(product.appName) — не папка приложения")
            }
            let bundleID = info["CFBundleIdentifier"] as? String ?? "—"
            guard bundleID == product.bundleID else {
                throw SelfUpdateError.bundle("bundle id \(bundleID.prefix(80)), а не \(product.bundleID)")
            }
            guard let signature = Self.within(patience, { checks.signature(app, product.requirement) }) else {
                throw SelfUpdateError.timeout("проверка подписи не уложилась в срок")
            }
            if let why = signature { throw SelfUpdateError.signature(why) }
            guard let gatekeeper = Self.within(patience, { checks.gatekeeper(app) }) else {
                throw SelfUpdateError.timeout("Gatekeeper не ответил в срок")
            }
            if let why = gatekeeper { throw SelfUpdateError.gatekeeper(why) }
            // Права подпись не покрывает (находка R6 проверки 10.10.2026): бандл, куда пишет группа или кто угодно,
            // на общем Маке поправит другая учётка. Отказ, а не починка: проверенное перед подменой не трогаем.
            if let loose = Self.writableByOthers(app) {
                throw SelfUpdateError.bundle("внутри пишет не только хозяин: \(loose.prefix(120))")
            }
            let inside = info["CFBundleShortVersionString"] as? String ?? "—"
            guard inside == version else { throw SelfUpdateError.version("внутри \(inside.prefix(40)), выпуск обещал \(version)") }
            guard Self.isNewer(inside, than: installed) else { throw SelfUpdateError.version("\(inside) не новее стоящей \(installed)") }
            return app
        } catch {
            try? fm.removeItem(at: box)
            throw error
        }
    }

    /// Первый путь в бандле, куда может писать группа или кто угодно («.» — сам бандл); nil — таких нет.
    /// Ярлыки не в счёт: их права ничего не значат, а куда они ведут — проверяет подпись.
    static func writableByOthers(_ app: URL) -> String? {
        var info = stat()
        guard lstat(app.path, &info) == 0, info.st_mode & 0o022 == 0,
              let walker = FileManager.default.enumerator(atPath: app.path) else { return "." }
        for case let name as String in walker {
            guard lstat(app.appendingPathComponent(name).path, &info) == 0 else { return name }
            if info.st_mode & S_IFMT != S_IFLNK, info.st_mode & 0o022 != 0 { return name }
        }
        return nil
    }

    // -------------------------------------------------------------- 2. подмена

    /// Поставить скачанное. nil — ставить нечего или момент ушёл (`confirm` ответил «нет»; архив остаётся).
    /// `confirm` зовётся прямо перед подменой, когда всё уже распаковано и проверено.
    /// Сбой проверки или подмены — архив удалён, версия на сутки отложена; прежнее приложение остаётся на месте.
    /// Срыв срока (`timeout`) — не сбой версии: ошибка наружу, архив и `ready` остаются до следующего момента.
    @discardableResult
    public func install(_ product: SelfUpdateProduct, app: URL, confirm: () -> Bool = { true }) throws -> SelfUpdateState.Note? {
        let fm = FileManager.default
        var state = loadState()
        var entry = state.products[product.key] ?? SelfUpdateState.Product()
        guard let version = entry.ready else { return nil }
        func save() {
            state.products[product.key] = entry
            saveState(state)
        }
        if let why = placeProblem(app, product: product) { throw SelfUpdateError.place(why) }
        guard let installed = Self.installedVersion(app, bundleID: product.bundleID) else {
            throw SelfUpdateError.place("у стоящего \(product.appName) не читается версия")
        }
        let archive = archiveURL(product, version)
        guard Self.isNewer(version, than: installed) else {
            forgetReady(product, &entry)
            save()
            return nil
        }
        // Архив лежал на диске с момента проверки — сверяем сумму и проверяем всё заново (М3, М7).
        let staged: URL
        do {
            guard let known = entry.readySHA256, (try? ClaudeUpdater.sha256(of: archive)) == known else {
                throw SelfUpdateError.archive("изменился после проверки")
            }
            staged = try verify(archive: archive, product: product, version: version, installed: installed)
        } catch {
            // Не уложились в срок — версия от этого не хуже, чем была при загрузке (находка R3 проверки
            // 10.10.2026): на сутки не откладываем, архив ждёт следующего момента.
            if case SelfUpdateError.timeout = error {
                log(product, "\(version) пока не встала — \(Self.describe(error))")
                throw error
            }
            try? fm.removeItem(at: archive)
            refuse(product, version: version, error, &entry)
            save()
            throw error
        }
        let box = staged.deletingLastPathComponent()
        defer { try? fm.removeItem(at: box) }
        guard confirm() else { return nil }

        // Меняем по тому же раскрытому пути, который проверял `placeProblem` (находка R7 проверки 10.10.2026):
        // обмен по пути-ярлыку подменил бы сам ярлык, а приложение, на которое он ведёт, осталось бы прежним.
        let place = app.resolvingSymlinksInPath().standardizedFileURL
        try prepareDirectory(rollbackDirectory)
        var previous = rollbackDirectory.appendingPathComponent("\(product.name)-\(installed).previous", isDirectory: true)
        // Наша же копия той же версии от прошлой попытки. Не убралась — прежнее приложение ляжет рядом под
        // запасным именем, а не пропадёт вместе с распаковкой (R7).
        try? fm.removeItem(at: previous)
        if fm.fileExists(atPath: previous.path) {
            previous = rollbackDirectory.appendingPathComponent("\(product.name)-\(installed)-\(UUID().uuidString.prefix(8)).previous",
                                                                isDirectory: true)
        }
        // Обмен местами одним системным вызовом (renamex_np RENAME_SWAP, APFS, тот же том): по пути приложения
        // ни на миг не пусто, и вернуть прежнее — тот же обмен ещё раз. Через FileManager нельзя: он молча копирует.
        guard renamex_np(staged.path, place.path, UInt32(RENAME_SWAP)) == 0 else {
            let code = errno
            // Обмен не удался — такой же отказ, как несошедшаяся проверка (находка R1 проверки 10.10.2026):
            // без него попытка шла бы на каждом запуске без срока, а строка обещала бы «встанет».
            let failure = SelfUpdateError.swap("новая версия не встала на место (\(String(cString: strerror(code))), errno \(code))",
                                               restored: true)
            try? fm.removeItem(at: archive)
            refuse(product, version: version, failure, &entry)
            save()
            throw failure
        }
        // Теперь по пути `staged` лежит прежнее приложение. Между проверкой и подменой бандл лежал в папке —
        // подпись и версия ещё раз, уже на месте (М7).
        var failure: String?
        var late = false
        switch Self.within(patience, { checks.signature(place, product.requirement) }) {
        case .none:
            failure = "после подмены проверка подписи не уложилась в срок"
            late = true
        case .some(.some(let why)):
            failure = "после подмены подпись не сошлась (\(why))"
        case .some(.none):
            if Self.installedVersion(place, bundleID: product.bundleID) != version { failure = "после подмены на месте не \(version)" }
        }
        if let failure = failure {
            let restored = renamex_np(staged.path, place.path, UInt32(RENAME_SWAP)) == 0
            // Не вернулось — прежнее хотя бы не пропадёт вместе с распаковкой.
            if !restored { _ = rename(staged.path, previous.path) }
            // Прежнее на месте, а сорвался только срок — версия ждёт следующего момента, как до подмены (R3).
            if late, restored {
                log(product, "\(version) пока не встала — \(failure); прежняя версия на месте")
                throw SelfUpdateError.timeout(failure)
            }
            try? fm.removeItem(at: archive)
            refuse(product, version: version, SelfUpdateError.swap(failure, restored: restored), &entry)
            save()
            throw SelfUpdateError.swap(failure, restored: restored)
        }
        if rename(staged.path, previous.path) != 0 {
            log(product, "прежнюю версию \(installed) не убрать в папку отката (\(String(cString: strerror(errno))))")
        }

        // Удача: прошлая версия в папке отката одна, архив больше не нужен.
        for name in (try? fm.contentsOfDirectory(atPath: rollbackDirectory.path)) ?? []
        where name.hasPrefix(product.name + "-") && name.hasSuffix(".previous") && name != previous.lastPathComponent {
            try? fm.removeItem(at: rollbackDirectory.appendingPathComponent(name))
        }
        try? fm.removeItem(at: archive)
        entry.ready = nil
        entry.readySHA256 = nil
        let note = SelfUpdateState.Note(product: product.key, from: installed, to: version)
        state.notes.append(note)
        save()
        log(product, "обновился с \(installed) до \(version); прежняя версия — \(previous.path)")
        return note
    }

    /// Маленький отвязанный помощник: ждёт выхода процесса `pid` (не дольше 20 с) и открывает приложение.
    /// Путь и pid идут аргументами, не в текст скрипта. `opener` подменяет тест.
    @discardableResult
    public static func relaunch(_ app: URL, afterExitOf pid: pid_t = getpid(), opener: String = "/usr/bin/open") -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"i=0; while /bin/kill -0 "$1" 2>/dev/null && [ "$i" -lt 200 ]; do /bin/sleep 0.1; i=$((i+1)); done; exec "$3" "$2""#,
                             "sh", String(pid), app.path, opener]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return (try? process.run()) != nil
    }

    // -------------------------------------------------------------- системные утилиты и сеть

    /// Утилита со сроком: вывод (stdout, при `merge` и stderr) до 4 МБ. nil — не запустилась или не уложилась
    /// (тогда она погашена).
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval, merge: Bool = true,
                    environment: [String: String]? = nil, directory: URL? = nil) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let environment = environment { process.environment = environment }
        if let directory = directory { process.currentDirectoryURL = directory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = merge ? pipe as Any : FileHandle.nullDevice as Any
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let read = DispatchSemaphore(value: 0)
        let output = OutputBox()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                output.append(chunk)
            }
            read.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var finished = read.wait(timeout: .now() + timeout) == .success
        while finished, process.isRunning {
            if Date() > deadline { finished = false } else { usleep(20_000) }
        }
        guard finished else {
            process.terminate()
            usleep(300_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            return nil
        }
        return (process.terminationStatus, output.text)
    }

    /// Проверка со сроком: nil — не уложилась. Оборвать её нечем — она дорабатывает на своей нитке (только
    /// читает), а ждать перестаём.
    static func within<T>(_ seconds: TimeInterval, _ work: @escaping () -> T) -> T? {
        let done = DispatchSemaphore(value: 0)
        let answer = AnswerBox<T>()
        DispatchQueue.global(qos: .userInitiated).async {
            answer.set(work())
            done.signal()
        }
        return done.wait(timeout: .now() + seconds) == .success ? answer.value : nil
    }

    private final class AnswerBox<T> {
        private let lock = NSLock()
        private var stored: T?
        func set(_ value: T) { lock.lock(); stored = value; lock.unlock() }
        var value: T? { lock.lock(); defer { lock.unlock() }; return stored }
    }

    private final class OutputBox {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) {
            lock.lock()
            if data.count < 4 * 1024 * 1024 { data.append(chunk) }
            lock.unlock()
        }
        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Строгая проверка подписи с требованием средствами Security (то же, что `codesign --verify --deep
    /// --strict -R=…`): все архитектуры, вложенный код, строгий режим. nil — подпись прошла.
    static func signatureProblem(_ app: URL, requirement: String) -> String? {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &code)
        guard status == errSecSuccess, let code = code else { return "бандл не читается (\(status))" }
        var parsed: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, SecCSFlags(), &parsed)
        guard status == errSecSuccess, let parsed = parsed else { return "требование к подписи не разобралось (\(status))" }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        var error: Unmanaged<CFError>?
        status = SecStaticCodeCheckValidityWithErrors(code, flags, parsed, &error)
        let details = error?.takeRetainedValue()
        guard status != errSecSuccess else { return nil }
        let text = (SecCopyErrorMessageString(status, nil) as String?) ?? details.map { CFErrorCopyDescription($0) as String } ?? ""
        return "\(text) (\(status))"
    }

    static let ghCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    /// gh по одному из известных путей, PATH не читаем. Находка М6 проверки 10.10.2026 (gh лежит в папке, куда
    /// пишет пользователь, а зовём мы его сами, в фоне): берём только обычный исполняемый файл, чей хозяин —
    /// эта учётка или root и куда другим учёткам писать нельзя. Ответу gh всё равно не верим — выпуск и архив
    /// проходят те же проверки, что и по HTTPS.
    static func ghExecutable(_ candidates: [String] = ghCandidates) -> String? {
        for candidate in candidates {
            let path = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value, owner == 0 || owner == getuid(),
                  let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue,
                  mode & 0o022 == 0, mode & 0o100 != 0 else { continue }
            return path
        }
        return nil
    }

    /// Окружение для gh: без вопросов, цвета и своего обновления; PATH — только системный. Переменные, которыми
    /// окружение увело бы gh на другой сервер, в другой репозиторий или к чужим настройкам, убраны (находка R5
    /// проверки 10.10.2026). Вход человека на github.com (его настройки gh, `GH_TOKEN`) остаётся — им gh и ходит.
    static func ghEnvironment(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        for key in ["GH_HOST", "GH_REPO", "GH_ENTERPRISE_TOKEN", "GH_CONFIG_DIR", "GH_DEBUG"] { environment[key] = nil }
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        environment["NO_COLOR"] = "1"
        environment["PATH"] = "/usr/bin:/bin"
        return environment
    }

    /// Запросы gh — с явным сервером github.com: куда идти, решаем мы, а не настройки gh (R5).
    static func ghLatestArguments(_ product: SelfUpdateProduct) -> [String] {
        ["api", "--hostname", "github.com", "repos/\(product.repo)/releases/latest"]
    }

    static func ghDownloadArguments(_ release: SelfUpdateRelease, _ product: SelfUpdateProduct, to file: URL) -> [String] {
        ["release", "download", release.tag, "-R", "github.com/\(product.repo)", "-p", release.asset, "-O", file.path, "--clobber"]
    }

    static func gh(_ arguments: [String], timeout: TimeInterval, directory: URL? = nil) -> (status: Int32, output: String)? {
        guard let gh = ghExecutable() else { return nil }
        return run(gh, arguments, timeout: timeout, merge: false, environment: ghEnvironment(), directory: directory)
    }

    enum HTTPAnswer {
        case ok(Data)
        case status(Int)
        case failed(String)
        /// Пришло (или обещано заголовком) больше `limit` — загрузка оборвана.
        case overflow
    }

    /// Один запрос к GitHub без входа и без идентификаторов. `file` — тело сразу в файл (архив).
    /// Перенаправление — только на адреса из `allowedHost`. `limit` — сколько байт обещал выпуск: пришло
    /// больше — обрываем, не дожидаясь конца (находка R6 проверки 10.10.2026). `protocols` подставляет тест.
    static func http(_ url: URL, timeout: TimeInterval, resource: TimeInterval, file: URL? = nil, limit: Int64? = nil,
                     protocols: [AnyClass] = []) -> HTTPAnswer {
        guard allowedHost(url) else { return .failed("чужой адрес") }
        let config = URLSessionConfiguration.ephemeral
        if !protocols.isEmpty { config.protocolClasses = protocols + (config.protocolClasses ?? []) }
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = resource
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: Redirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        if file == nil { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        let done = DispatchSemaphore(value: 0)
        var answer = HTTPAnswer.failed("нет ответа")
        func finish(_ response: URLResponse?, _ error: Error?, _ body: () -> HTTPAnswer) {
            defer { done.signal() }
            if let error = error { answer = .failed(error.localizedDescription); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            answer = code == 200 ? body() : .status(code)
        }
        let task: URLSessionTask
        if let file = file {
            task = session.downloadTask(with: request) { location, response, error in
                finish(response, error) {
                    guard let location = location else { return .failed("пустой ответ") }
                    try? FileManager.default.removeItem(at: file)
                    do { try FileManager.default.moveItem(at: location, to: file) } catch { return .failed(error.localizedDescription) }
                    return .ok(Data())
                }
            }
        } else {
            task = session.dataTask(with: request) { data, response, error in
                finish(response, error) { .ok(data ?? Data()) }
            }
        }
        task.resume()
        var overflow = false
        while done.wait(timeout: .now() + 0.25) == .timedOut {
            if let limit = limit, !overflow, max(task.countOfBytesReceived, task.countOfBytesExpectedToReceive) > limit {
                overflow = true
                task.cancel()
            }
        }
        return overflow ? .overflow : answer
    }

    private final class Redirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(SelfUpdater.allowedHost(request.url) ? request : nil)
        }
    }
}

extension SelfUpdateTransport {
    /// Сначала обычный HTTPS без входа (сработает, когда репозиторий открыт); 404 или 403 — запасной путь
    /// через gh человека, если gh стоит и вошёл: запрос идёт с его учёткой, и адреса выбирает gh — мы задаём
    /// только сервер github.com. Зеркал и сторонних адресов нет.
    public static let live = SelfUpdateTransport(
        latest: { product in
            switch SelfUpdater.http(product.latestURL, timeout: 15, resource: 30) {
            case .ok(let data): return .success(data)
            case .failed(let why): return .failure(.offline(why))
            case .overflow: return .failure(.offline("ответ длиннее ожидаемого"))
            case .status(let code) where code != 403 && code != 404: return .failure(.offline("GitHub ответил \(code)"))
            case .status(let code):
                guard let run = SelfUpdater.gh(SelfUpdater.ghLatestArguments(product), timeout: 30), run.status == 0 else {
                    return .failure(.missing("GitHub ответил \(code), gh не помог"))
                }
                return .success(Data(run.output.utf8))
            }
        },
        download: { release, product, file in
            switch SelfUpdater.http(release.url, timeout: 30, resource: 15 * 60, file: file, limit: release.size) {
            case .ok: return .success(())
            case .failed(let why): return .failure(.offline(why))
            case .overflow: return .failure(.archive("пришло больше \(release.size) байт, обещанных выпуском"))
            case .status(let code) where code != 403 && code != 404: return .failure(.offline("GitHub ответил \(code)"))
            case .status(let code):
                guard let run = SelfUpdater.gh(SelfUpdater.ghDownloadArguments(release, product, to: file), timeout: 15 * 60,
                                               directory: file.deletingLastPathComponent()),
                      run.status == 0 else {
                    return .failure(.missing("GitHub ответил \(code), gh не скачал"))
                }
                return .success(())
            }
        })
}

extension SelfUpdateChecks {
    public static let live = SelfUpdateChecks(
        signature: { app, requirement in SelfUpdater.signatureProblem(app, requirement: requirement) },
        gatekeeper: { app in
            // Ждать перестаёт `SelfUpdater.within` по `patience` — раньше этого срока; он здесь затем, чтобы
            // зависший spctl не жил вечно.
            guard let run = SelfUpdater.run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path], timeout: 120) else {
                return "spctl не ответил"
            }
            return run.status == 0 ? nil : (run.output.isEmpty ? "код \(run.status)" : String(run.output.prefix(200)))
        })
}
