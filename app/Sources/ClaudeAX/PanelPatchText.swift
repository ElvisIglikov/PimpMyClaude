import CoreGraphics
import Foundation
import Patcher

// MARK: - вылетающая панель

public enum PimpPanelText {
    /// Карточка «одна кнопка» (не пропатчен, слетел, Claude не найден). У «всё хорошо» — nil.
    public struct PatchCard: Equatable {
        public let title: String
        public let text: String
        public let button: String
        public let footnote: String
    }

    /// Предупреждение перед обновлением и патчем Claude (WF210, #9382; смысл — `docs/audit-security-2026-10-10.md`,
    /// раздел «Окно „Claude хочет…“»): патч заменяет подпись Claude локальной, и macOS заново спрашивает доступ к
    /// записи «Claude Safe Storage». Абзацем — только в окне разрешений; в панели с WF234 его нет: там после нажатия
    /// показывается пример самого окна macOS (`keychainTitle`, `keychainHint`). С WF238 под самим окном macOS встаёт
    /// плашка `KeychainHint`.
    public static let keychainNote = "Потом macOS спросит про «Claude Safe Storage» в связке ключей — это нормально: "
        + "PMP заново подписывает Claude, и macOS переспрашивает. Пароль получает macOS, не PMP. "
        + "Нажми «Разрешать всегда»."

    /// Пример окна связки ключей в карточке (WF234, слово владельца 10.10.2026: «когда нажимаешь обновить, там
    /// должно быть прямо пример. Нажмите вот сюда»): слова окна macOS как есть (WF238 — по снимку настоящего окна,
    /// `docs/ref/claude-svyazka-klyuchey.png`), кнопки и одна строка под ним.
    public static let keychainTitle = "«Claude» хочет использовать конфиденциальную информацию, хранящуюся в "
        + "«Claude Safe Storage» в Вашей связке ключей."
    public static let keychainBody = "Чтобы разрешить это, введите пароль для связки ключей «Вход»."
    public static let keychainPassword = "Пароль:"
    public static let keychainAlways = "Разрешать всегда"
    public static let keychainDeny = "Отказать"
    public static let keychainAllow = "Разрешить"
    public static let keychainHint = "Нажми «Разрешать всегда» — пароль получает macOS, не PMP"
    /// Тихая строка до нажатия «Обновить» и «Пропатчить» (WF238, макет 41, кадр 1.1); `keychainSoonBold` — что в
    /// ней набрано полужирным. Пробелы в «пароль от Мака —» неразрывные: строка узкая, а полужирное не рвётся и тире
    /// не уходит в начало строки.
    public static let keychainSoonBold = "пароль\u{00A0}от\u{00A0}Мака"
    public static let keychainSoon = "Потом macOS один раз спросит " + keychainSoonBold + "\u{00A0}— покажу, что нажать"
    /// Код открыт с 10.10.2026 (#9382: «написать, что Пимп — программа с открытым исходным кодом»).
    public static let openSourceWord = "код открыт"
    public static let openSourceURL = "https://github.com/ElvisIglikov/PimpMyClaude"

    public static func patchCard(_ patch: StatusIcon.Patch) -> PatchCard? {
        switch patch {
        case .notInstalled:
            return PatchCard(title: "Claude пока без патча PMP",
                             text: "Узкие окна, темы, полоска работы и отсчёт отправки — после одного нажатия.",
                             button: "Пропатчить Claude", footnote: "Claude закроется и откроется сам · ~10 с")
        case .lost(_, let reason) where reason == oldLoaderReason:
            return PatchCard(title: "Окна не опознаются — нужен «Вернуть патч» (старый лоадер)",
                             text: "Страницы Claude отвечают без печати нового лоадера, и PMP им не верит: темы окна, "
                                 + "новый чат, отправка и раскладки молчат.",
                             button: "Вернуть патч",
                             footnote: "Claude закроется и откроется сам · ~10 с · окна вернутся")
        case .lost(_, let reason):
            return PatchCard(title: reason == claudeUpdatedReason ? "Claude обновился — патч слетел"
                                                                  : "Патч слетел: \(reason)",
                             text: "Темы, узкие окна и полоска работы сейчас молчат. Настройки целы.",
                             button: "Вернуть патч",
                             footnote: "Claude закроется и откроется сам · ~10 с · окна вернутся")
        case .claudeNotFound:
            return PatchCard(title: "Claude не найден",
                             text: "Поставь Claude с claude.ai/download или покажи, где он лежит.",
                             button: "Найти Claude…", footnote: "Скачать Claude")
        case .installed, .unknown:
            return nil
        }
    }

    /// Строка шапки (#8894): «Claude 2.42304.0 · PMP 1.10.47», номера лоадера нет. С #10308 (слово Элвиса 19.10.2026:
    /// «подписку сверху убрать, оставить только версию Claude и версию PMP, мелко, в одну строку») тарифа нет.
    /// О беде с патчем говорит карточка патча (WF126); Claude не найден — только версия приложения. `short` — номер
    /// Claude без последнего числа («Claude 2.42304»): так шапка встаёт в одну строку. `app` пуст — без версии
    /// приложения.
    public static func headerLine(_ patch: StatusIcon.Patch, app: String = "", short: Bool = false) -> String {
        let claude: String?
        switch patch {
        case .claudeNotFound: claude = nil
        // Ещё не проверили — ни слова в строке (WF181, #9217: без «…»), «Проверяю Claude» — в подсказке.
        case .unknown: claude = nil
        case .notInstalled(let version), .lost(let version, _), .installed(let version, _):
            claude = "Claude " + (short ? shortVersion(version) : version)
        }
        return [claude, app.isEmpty ? nil : "PMP \(app)"].compactMap { $0 }.joined(separator: " · ")
    }

    /// «2.42304.0» → «2.42304» (#10308): последнее число долой, когда чисел больше двух; иначе как есть.
    public static func shortVersion(_ version: String) -> String {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 2 else { return version }
        return parts.dropLast().joined(separator: ".")
    }

    /// Подсказка строки шапки: пока Claude не проверен — «Проверяю Claude»; иначе подсказки нет.
    public static func headerHelp(_ patch: StatusIcon.Patch) -> String {
        if case .unknown = patch { return "Проверяю Claude" }
        return ""
    }

    public static func loaderText(_ loader: Int) -> String { "\(loader).0" }

    /// Причина `.lost`, при которой говорим «Claude обновился» (как пишет `Patcher.state()`).
    public static let claudeUpdatedReason = "Claude обновился"
    /// Причина `.lost` по ответам самих страниц (WF111): отвечает только старый лоадер — патч на
    /// диске мог и встать, а Claude живёт прежним (не перезапущен, перепатч сорвался).
    public static let oldLoaderReason = "старый лоадер"

    /// Вид патча с поправкой на ответы страниц: они говорят «старый лоадер» — это `.lost`,
    /// что бы ни лежало на диске. Не найден и не пропатчен — как есть.
    public static func patch(_ patch: StatusIcon.Patch, needsRepatch: Bool) -> StatusIcon.Patch {
        guard needsRepatch else { return patch }
        switch patch {
        case .installed(let version, _), .lost(let version, _): return .lost(version: version, reason: oldLoaderReason)
        case .claudeNotFound, .notInstalled, .unknown: return patch
        }
    }

    /// Уведомление «патч слетел» — по причине (z7-s03): «обновился» только когда Claude и правда обновился.
    public static func patchLostNotice(version: String, reason: String) -> String {
        let what = reason == claudeUpdatedReason ? "Claude \(version) обновился — патч слетел"
                                                 : "Патч слетел (\(reason)) · Claude \(version)"
        return what + ". Одно нажатие — всё вернётся."
    }

    // MARK: подсказки выключателей

    /// Как ведёт себя маяк окон доступа (`ConsentBeaconStyle.choose`): вода на любом числе мониторов (#9661).
    public static let consentToolTip = "Окно «приложение запрашивает доступ» обводит фиолетовая вода, "
        + "у курсора — окошко со стрелкой; клик ведёт курсор к окну. Нажимаешь в нём ты."

    /// Гигабайты с одной десятичной через запятую: 2 800 000 000 → «2,8».
    public static func gigabytesText(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(max(0, bytes)) / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
    }

    /// Фоновой загрузке обновления не хватило места (z6-r06).
    public static func noSpaceText(needed: Int64, free: Int64) -> String {
        "мало места на диске: нужно \(gigabytesText(needed)) ГБ, свободно \(gigabytesText(free)) ГБ"
    }

    /// Текст кнопки патча по строке журнала `Patcher`; nil — строка не про шаг.
    public static func patchStep(_ line: String, loader: Int) -> String? {
        if line.contains(PatchLog.opensClaude) { return "Открываю Claude…" }
        // Шаги, где ждём человека (`ClaudePatcher.waitForWritable`, `quitClaude`; #9842): кнопка говорит, что сделать.
        if line == Patcher.appManagementWaitLine { return "Включи PimpMyClaude в настройках…" }
        if line.hasPrefix(PatchLog.permissionGranted) { return "Продолжаю…" }
        if line.hasPrefix(PatchLog.ownership) { return "Введи пароль Мака…" }
        if line.contains(PatchLog.forceQuit) { return "Закрываю Claude принудительно…" }
        if line == Patcher.claudeQuitWaitLine { return "Закрой Claude — дальше сам…" }
        if [PatchLog.installsLoader, PatchLog.savesOriginal, PatchLog.installsPatch, PatchLog.restoresOriginals]
            .contains(where: line.hasPrefix) { return "Ставлю патч \(loaderText(loader))…" }
        if line.hasPrefix(PatchLog.closesClaude) { return "Закрываю Claude…" }
        return nil
    }

    // MARK: блок обновления Claude

    /// Запасной путь обновления (#9823; слово Элвиса: «нужно добавить кнопку „Скачать сайт Клауда“… Ссылку надо
    /// показать на всякий случай, чтобы скопировать»): страница загрузки Claude — её открывает и копирует
    /// `DownloadFromSiteRow` в карточке обновления.
    public static let claudeDownloadURL = "https://claude.ai/download"
    /// Та же ссылка без схемы — так она видна в строке рядом со значком «копировать».
    public static let claudeDownloadShort = "claude.ai/download"
    public static let siteDownloadTitle = "Скачать с claude.ai"
    /// Загрузка кнопкой идёт дольше — под гонкой встаёт запасной путь.
    public static let siteDownloadAfter: TimeInterval = 3 * 60

    /// Показать ли запасной путь под гонкой загрузки (#9823): идёт дольше `siteDownloadAfter` или упала — все
    /// дорожки сошли с дистанции. Обычная загрузка — без строки.
    public static func siteDownloadShown(_ race: ClaudeUpdateMenu.Race, elapsed: TimeInterval) -> Bool {
        if elapsed >= siteDownloadAfter { return true }
        return !race.lanes.isEmpty && race.lanes.allSatisfy { lane in
            switch lane.state {
            case .dropped, .failed: return true
            case .running, .leading, .won: return false
            }
        }
    }

    /// Что показывает блок обновления (§3.3 выбора).
    public enum UpdateBlock: Equatable {
        case none
        /// Вышло новее; `canWrite == false` — кнопки нет, «поставь сам»; `note` — почему фон не скачал.
        case available(version: String, canWrite: Bool, note: String?)
        case downloading(ClaudeUpdateMenu.Race)
        /// Гонка кончилась, идёт проверка подписи; `from` — чья дорожка победила.
        case verifying(version: String, from: String?)
        /// Скачалось; `question` — вопрос «идёт работа…» прямо в блоке.
        case ready(version: String, question: String?)
        /// «Самое время» и причина словами.
        case timely(version: String, reason: String)
        /// Скачалось, но сейчас идёт работа (WF234): `work` — что идёт; обновление подождёт, кнопка остаётся.
        case busy(version: String, work: String)
        /// Скачалось и отложено до следующего запуска Claude (#10765, WF283): одна тихая строка вместо карточки.
        case planned(version: String)
        case snoozed
        case installing(version: String, step: Int)
        case done(version: String)
        case failed(String)
    }

    /// Состояние панели поверх машины `ClaudeUpdateMenu`: что добавляет сама панель —
    /// «самое время», вопрос перед закрытием, «Позже», шаг установки, «готово» и сбой установки.
    public struct UpdateExtras: Equatable {
        public var offerReason: String?
        /// Что сейчас идёт (`workLine`); nil — работы не видно.
        public var workLine: String?
        /// То же коротко (`workShort`, #10307) — строкой «идёт работа: …» в карточке; nil — длинная строка.
        public var workShort: String?
        public var question: String?
        public var snoozedShown = false
        public var installStep = 0
        public var doneVersion: String?
        public var installFailure: String?
        /// Какую версию человек отложил «При следующем запуске» (`updatePlannedKey`, WF283).
        public var plannedVersion: String?

        public init(offerReason: String? = nil, workLine: String? = nil, workShort: String? = nil,
                    question: String? = nil, snoozedShown: Bool = false, installStep: Int = 0,
                    doneVersion: String? = nil, installFailure: String? = nil, plannedVersion: String? = nil) {
            self.offerReason = offerReason
            self.workLine = workLine
            self.workShort = workShort
            self.question = question
            self.snoozedShown = snoozedShown
            self.installStep = installStep
            self.doneVersion = doneVersion
            self.installFailure = installFailure
            self.plannedVersion = plannedVersion
        }
    }

    public static func updateBlock(_ menu: ClaudeUpdateMenu, _ extras: UpdateExtras) -> UpdateBlock {
        if extras.snoozedShown { return .snoozed }
        switch menu.phase {
        case .installing(let version):
            return .installing(version: version, step: extras.installStep)
        case .downloading(let race):
            if let won = race.lanes.first(where: { $0.state == .won }) {
                return .verifying(version: race.version, from: laneName(won))
            }
            return .downloading(race)
        default:
            break
        }
        // Сбой установки виден, пока его не сняли «Ещё раз» — и поверх вернувшегося готового.
        if let why = extras.installFailure { return .failed(why) }
        switch menu.phase {
        case .ready(let version):
            if let question = extras.question { return .ready(version: version, question: question) }
            // Отложено до запуска (WF283) — тихая строка: ни работа, ни «самое время» карточку не раскрывают.
            if extras.plannedVersion == version { return .planned(version: version) }
            // Работа видна — правда о ней сильнее «самого времени» (WF234).
            if let work = extras.workLine { return .busy(version: version, work: extras.workShort ?? work) }
            if let reason = extras.offerReason { return .timely(version: version, reason: reason) }
            return .ready(version: version, question: nil)
        case .available(let version):
            return .available(version: version, canWrite: menu.canWrite,
                              note: menu.lastError.map { "Фоновая загрузка не вышла: \($0)" })
        default:
            if let version = extras.doneVersion { return .done(version: version) }
            return .none
        }
    }

    /// Почему «самое время» — зелёная пилюля. nil — так сказать нельзя (WF234): работа идёт (на страницах, в Workflow
    /// или в терминальных чатах) или про неё не знаем; тогда блок — не «самое время».
    public static func offerReason(claudeRunning: Bool, windowCount: Int, work: WorkNow) -> String? {
        guard work.seen(claudeRunning: claudeRunning, windowCount: windowCount).working == false else { return nil }
        if !claudeRunning { return "Claude не запущен" }
        if windowCount == 0 { return "окна Claude закрыты" }
        // Наблюдали меньше 2 минут — минут не называем: «2 мин» было бы неправдой (гейт 2 WF87).
        guard let idle = work.idleSeconds, idle >= ClaudeUpdateMenu.offerIdleSeconds else { return "никто не работает" }
        return "\(Int(idle / 60)) мин никто не работает"
    }

    /// Что идёт, словами карточки (WF234): «Идут 7 Workflow в 3 проектах · работают 4 терминала · идёт работа в
    /// 2 чатах». Работы не видно — nil.
    public static func workLine(_ work: WorkNow) -> String? {
        var parts: [String] = []
        if let flows = work.workflows, flows > 0 { parts.append(PanelTiles.goes(flows) + " " + flowsText(work)) }
        if let terminals = work.terminals, terminals > 0 {
            parts.append(Plural.ru(terminals, "работает ", "работают ", "работают ") + terminalsText(terminals))
        }
        if let chats = work.chats, chats > 0 { parts.append("идёт работа в \(chats) \(chatsWord(chats))") }
        guard let first = parts.first else { return nil }
        parts[0] = first.prefix(1).uppercased() + first.dropFirst()
        return parts.joined(separator: " · ")
    }

    /// Что идёт, коротко (#10307): «3 Workflow · 4 терминала · 2 чата» — для строки «идёт работа: …» карточки
    /// обновления в одну строку. Нули не называются; работы не видно — nil.
    public static func workShort(_ work: WorkNow) -> String? {
        var parts: [String] = []
        if let flows = work.workflows, flows > 0 { parts.append("\(flows) Workflow") }
        if let terminals = work.terminals, terminals > 0 { parts.append(terminalsText(terminals)) }
        if let chats = work.chats, chats > 0 { parts.append(ChatArchive.chatsWord(chats)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «7 Workflow в 3 проектах»: слово «Workflow» не склоняется.
    private static func flowsText(_ work: WorkNow) -> String {
        let flows = work.workflows ?? 0, projects = max(1, work.projects)
        return "\(flows) Workflow в \(projects) \(Plural.ru(projects, "проекте", "проектах", "проектах"))"
    }

    private static func terminalsText(_ count: Int) -> String {
        ChatArchive.plural(count, "терминал", "терминала", "терминалов")
    }

    /// «в 1 чате», «в 3 чатах».
    private static func chatsWord(_ count: Int) -> String { Plural.ru(count, "чате", "чатах", "чатах") }

    /// Вопрос в блоке перед закрытием Claude (WF234; с WF283 — словами Элвиса «у вас терминал работает, работа
    /// сбросится»): сперва что работает — Workflow, терминальные чаты и чаты с числами (`workLine`), потом что будет.
    /// «Может» — честно: ответ в чате Claude прервётся наверняка, а терминал живёт в tmux вне Claude. Работы не видно,
    /// но и сказать наверняка нельзя (окна есть, а источник молчит) — общий вопрос.
    public static func confirmQuestion(work: WorkNow) -> String {
        guard let line = workLine(work) else { return "Claude закроется вместе с окнами — обновить сейчас?" }
        return line + " — Claude закроется, работа может сброситься. Обновить всё равно?"
    }

    /// Строка под кнопкой патча и в вопросах «Пропатчить / Снять патч» (WF234): Claude закроется — что при этом идёт.
    /// Работы не видно — nil.
    public static func patchWorkNote(_ work: WorkNow) -> String? {
        workLine(work).map { $0 + " — Claude закроется и прервёт их." }
    }

    /// Одно уведомление «Скачалось» на версию: в первый момент «самое время», а не наступил он
    /// за сутки после готовности — всё равно одно.
    public static let notifyAfter: TimeInterval = 24 * 3600

    public static func shouldNotifyReady(version: String, notified: String?, offer: Bool, readySince: Date?,
                                         now: Date) -> Bool {
        guard notified != version else { return false }
        if offer { return true }
        guard let since = readySince else { return false }
        return now.timeIntervalSince(since) >= notifyAfter
    }

    /// `opensClaude: false` — отложенное ставится при закрытом Claude (WF283): открывать его и ставить окна PMP не будет.
    public static func installSteps(version: String, loader: Int, opensClaude: Bool = true) -> [String] {
        let steps = ["Закрываю Claude", "Ставлю Claude \(version)", "Ставлю патч \(loaderText(loader))", "Открываю Claude",
                     "Окна встают на места"]
        return opensClaude ? steps : Array(steps.prefix(3))
    }
    public static let installClosedLine = "Claude закрыт — ставлю, сам его не открою"


    /// Шаг установки по строке журнала `ClaudeUpdater.install`; шаги только растут.
    public static func installStep(_ line: String, current: Int) -> Int {
        let step: Int
        if line.contains(PatchLog.opensClaude) {
            step = 3
        } else if line.hasPrefix(PatchLog.installsPatch) || line.hasPrefix(PatchLog.installsLoader) {
            step = 2
        } else if line.hasPrefix(PatchLog.replacesClaude) {
            step = 1
        } else {
            step = 0
        }
        return max(current, step)
    }

    // MARK: гонка

    /// Имя дорожки вместо `title` контракта.
    public static func laneName(_ lane: ClaudeUpdateMenu.Lane) -> String {
        switch lane.id {
        case "r2": return "Cloudflare"
        case "anthropic": return "Anthropic"
        case "github": return "GitHub"
        case "file": return "С диска"
        default: return lane.title
        }
    }

    /// Дорожки в постоянном порядке.
    public static func orderedLanes(_ lanes: [ClaudeUpdateMenu.Lane]) -> [ClaudeUpdateMenu.Lane] {
        let order = ["r2", "anthropic", "github", "file"]
        return lanes.enumerated().sorted { a, b in
            let x = order.firstIndex(of: a.element.id) ?? order.count
            let y = order.firstIndex(of: b.element.id) ?? order.count
            return x != y ? x < y : a.offset < b.offset
        }.map { $0.element }
    }

    /// Подстрока гонки: первые 5 с — «наперегонки из трёх мест», дальше «осталось ~N мин» по лидеру.
    public static func raceSubtitle(_ race: ClaudeUpdateMenu.Race, elapsed: TimeInterval) -> String {
        if elapsed < 5 {
            let places = [1: "одного места", 2: "двух мест", 3: "трёх мест", 4: "четырёх мест"]
            return "наперегонки из \(places[race.lanes.count] ?? "\(race.lanes.count) мест")"
        }
        let leader = race.lanes.first { $0.state == .leading } ?? race.lanes.filter {
            if case .running = $0.state { return true }
            return false
        }.max { $0.bytesPerSec < $1.bytesPerSec }
        guard let lane = leader, let total = lane.total, lane.bytesPerSec > 0 else { return "наперегонки" }
        let left = Double(max(0, total - lane.bytes)) / lane.bytesPerSec
        if left < 90 { return "наперегонки · осталось ~\(max(5, Int((left / 5).rounded()) * 5)) с" }
        return "наперегонки · осталось ~\(Int((left / 60).rounded())) мин"
    }

    /// «0:36» — время с начала гонки.
    public static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// «212 из 374 МБ»; меньше 10 МБ — с десятыми: «2,7 из 374 МБ».
    public static func bytesText(_ bytes: Int64, total: Int64?) -> String {
        let mb = Double(max(0, bytes)) / 1_000_000
        let done = mb < 10 ? String(format: "%.1f", mb).replacingOccurrences(of: ".", with: ",")
                           : "\(Int(mb))"
        guard let total = total, total > 0 else { return "\(done) МБ" }
        return "\(done) из \(Int((Double(total) / 1_000_000).rounded())) МБ"
    }

    /// Метка дорожки: «лидер», «победил», «ожил — лидер сполз», причина отсева, «сорвался».
    public static func laneBadge(_ lane: ClaudeUpdateMenu.Lane, revived: Bool) -> String? {
        switch lane.state {
        case .leading: return revived ? "ожил — лидер сполз" : "лидер"
        case .running: return revived ? "ожил — лидер сполз" : nil
        case .won: return "победил"
        case .dropped(let why): return why
        case .failed: return "сорвался"
        }
    }
}

/// Память панели о дорожках: «ожила» та, что была отключена и снова бежит (6 с метки).
public struct LaneMemory: Equatable {
    public static let revivedSeconds: TimeInterval = 6
    private var dropped: Set<String> = []
    private var revivedAt: [String: Date] = [:]

    public init() {}

    public mutating func note(_ race: ClaudeUpdateMenu.Race, at now: Date) {
        for lane in race.lanes {
            switch lane.state {
            case .dropped, .failed:
                dropped.insert(lane.id)
            case .running, .leading:
                if dropped.remove(lane.id) != nil { revivedAt[lane.id] = now }
            case .won:
                dropped.remove(lane.id)
            }
        }
    }

    public func isRevived(_ id: String, at now: Date) -> Bool {
        guard let at = revivedAt[id] else { return false }
        return now.timeIntervalSince(at) < Self.revivedSeconds
    }

    public mutating func reset() { self = LaneMemory() }
}
