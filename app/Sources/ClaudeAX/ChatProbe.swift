import Foundation

/// Ответ одной страницы Claude на вопрос «какой в тебе чат» (план WF29, решение 4).
struct ChatPage: Equatable {
    /// Главное окно (`claude.ai/epitaxy/local_…`), вынесенный чат (`about:blank`) или
    /// чужая страница — артефакт, панель браузера, рамка окна.
    enum Kind: String { case main, popout, other }

    let kind: Kind
    /// id чата ЭТОЙ страницы (`local_<uuid>`); nil — страница себя не опознала.
    let chat: String?
    /// `document.title` страницы — он же AX-заголовок окна, им адресуется попап.
    let title: String
    /// `location.pathname` страницы: `/epitaxy/local_…` в открытом чате, `/epitaxy` на
    /// домашнем экране, `blank` у попапа (план WF37, часть C).
    let path: String
    /// Что со стором попапов на странице: `ok`, `cache`, `busy`, `none`, `skip`.
    let store: String
    /// Папка чипа над пустым полем ввода — её страница отдаёт ТОЛЬКО у главного окна и
    /// только на домашнем экране (план WF37 C1); во всех остальных случаях nil.
    let folder: String?
    /// Что страница говорит о доезде переноса «Обкэшить» (`status().cashout.delivery`,
    /// задача #5779): `"ждём"`, `"вставлено"` или `"отказ: <причина>"`. nil — страницу об
    /// этом не спрашивали (круг ушёл без `cash`), сказать ей нечего или она промолчала.
    let cashout: String?
    /// Когда пришёл круг, в котором страница ответила.
    let at: Date

    /// Новые поля — со значениями по умолчанию, чтобы прежние восемь конструкторов в тестах
    /// остались как были (критик, мелочь 1 плана WF37). Автоматический memberwise-init для
    /// `let` со значением по умолчанию Swift не заводит — отсюда свой.
    init(kind: Kind, chat: String?, title: String, path: String = "", store: String,
         folder: String? = nil, cashout: String? = nil, at: Date) {
        self.kind = kind
        self.chat = chat
        self.title = title
        self.path = path
        self.store = store
        self.folder = folder
        self.cashout = cashout
        self.at = at
    }
}

/// Файловая часть канала probe. Живьём это два файла рядом с `command.json`, в тестах —
/// память: диска в них нет, а правило владения каналом и разбор ответа проверяются как
/// чистые функции (решение 7 плана WF29).
struct ChatProbeFiles {
    /// Отпечаток `probe.js` (mtime+размер) и время правки; nil — файла нет вовсе.
    var scriptInfo: () -> (stamp: String, modified: Date)?
    var readScript: () -> String?
    var writeScript: (String) -> Bool
    /// Отпечаток `probe-result.json`; nil — файла нет.
    var resultInfo: () -> String?
    var readResult: () -> Data?

    /// Живые файлы в `~/Library/Application Support/MyClaude/`.
    static func onDisk(directory: URL = CommandChannel.directory) -> ChatProbeFiles {
        let script = directory.appendingPathComponent(ChatProbe.scriptName)
        let result = directory.appendingPathComponent(ChatProbe.resultName)
        // Отпечатки — через `ProjectIndex.fileInfo`: он спрашивает свежий `URL`, а иначе
        // значения ресурсов закэшировались бы в этих самых ссылках навсегда.
        return ChatProbeFiles(
            scriptInfo: {
                guard let info = ProjectIndex.fileInfo(of: script) else { return nil }
                return ("\(info.modified.timeIntervalSince1970):\(info.size)", info.modified)
            },
            readScript: { try? String(contentsOf: script, encoding: .utf8) },
            writeScript: { CommandChannel.writeAtomic(script, $0) },
            resultInfo: {
                guard let info = ProjectIndex.fileInfo(of: result) else { return nil }
                return "\(info.modified.timeIntervalSince1970):\(info.size)"
            },
            readResult: { try? Data(contentsOf: result) })
    }
}

/// Канал «страница → приложение»: приложение кладёт в `probe.js` короткий скрипт, лоадер
/// исполняет его во всех страницах Claude и складывает ответы в `probe-result.json`
/// (лоадер v7, `patch-claude.mjs:179-191`). Другого пути у страницы нет: `command.json`
/// односторонний, в `status.json` пишет только лоадер, а CSP claude.ai закрывает fetch
/// на localhost (решение 2 плана WF29).
///
/// Зачем: пока приложение не знает, КАКОЙ чат показывает окно, оно красит попапы по
/// заголовку — а заголовок попапа это снимок имени чата на момент выноса в окно, и после
/// переименования он с индексом не сходится (задача #5455). Отсюда же #5448: смена папки
/// видна сразу, как только известен чат.
///
/// Канал общий с агентом на гейте, поэтому приложение владеет им **вежливо**:
/// свой скрипт помечает первой строкой, чужой свежий — не трогает вовсе и молчит минуту,
/// а карту помечает несвежей (покраска уходит на старый путь по заголовку).
/// Тумблер «🗂 Цвет по проекту» выключен — канала не касаемся совсем: probe нужен ровно
/// покраске (риск 11 плана WF29).
///
/// WF35 добавил к ответу ОДНО поле — `themes`, карту тем страницы: файл `window-themes.json`
/// догоняет ею правду, второго probe-скрипта под это не заводится (решение 3 плана WF35).
///
/// Класс не потокобезопасен — живёт на главной очереди, вместе с общим тиком 2 с.
final class ChatProbe {
    static let scriptName = "probe.js"
    static let resultName = "probe-result.json"
    /// Метка своего скрипта — по ней приложение узнаёт файл от прошлого запуска, а человек
    /// на гейте видит, кто держит канал (`head -1 probe.js`).
    static let mark = "// myclaude-chats v1"
    /// Потолок длины круга в метке: по нему из чужой первой строки не собирается скрипт
    /// на мегабайт (задача #5741). Живой круг — `chats-<мс>-<4 цифры>`, это 24 знака.
    static let nonceLimit = 64
    /// Пол частоты: круг стоит лоадеру обхода всех страниц (их 41) и записи файла на 3,9 МБ —
    /// чаще раза в 15 с спрашивать нельзя (критик Б2 плана WF29).
    static let askInterval: TimeInterval = 15
    /// Окно, которое не опознаётся в принципе (попап обычного чата claude.ai), не должно
    /// дёргать канал каждые 15 с.
    static let unknownInterval: TimeInterval = 60
    /// Круг не закрыт, а с записи прошло столько — считаем его потерянным и спрашиваем снова.
    /// Раньше нельзя: `probeStamp` лоадер ставит ДО обхода страниц, и поздно завершившийся
    /// старый круг затёр бы свежий ответ (критик В2 плана WF29).
    static let answerTimeout: TimeInterval = 30
    /// Чужой свежий скрипт — молчим столько и пробуем снова.
    static let foreignQuiet: TimeInterval = 60
    /// Чужой скрипт, которого не касались дольше — брошенный: канал забираем.
    static let foreignStale: TimeInterval = 600
    /// Путь страницы главного окна на домашнем экране (`/epitaxy`): сессии у него нет, и
    /// папку окна знает только сама страница — по чипу над пустым полем (план WF37, часть C).
    static let homePath = "/epitaxy"
    /// Пол частоты на домашнем экране: чип папки меняется молча, и 15 с там — это 15 с
    /// серого окна (план WF37 C3). Меньше 4 с не выйдет: общий тик приложения — 2 с.
    static let homeInterval: TimeInterval = 4
    /// Потолок длины папки из ответа: путь приходит из чужой страницы, и складывать в поле
    /// команды что попало нельзя.
    static let folderLimit = 1024
    /// Потолок длины слова о доезде переноса: строку пишет страница, и в плашку Элвису
    /// уходит она же (задача #5779).
    static let cashoutLimit = 200
    /// Пол частоты, пока идёт перенос «Обкэшить»: донор стоит закрытым только по ответу
    /// страницы, и ждать его прежние 15 с — это 15 с лишнего окна на экране (задача #5779).
    /// Меньше 2 с не выйдет: общий тик приложения ровно такой.
    static let cashoutInterval: TimeInterval = 4
    /// Ответ главного окна старше — берём чат из `status.json` (решение 8 плана WF29).
    /// Держать его дольше круга нельзя (находка 1 проверки WF29): переключили чат в главном
    /// окне — `status.json` знает об этом через 2 с, а карта probe обновится в лучшем случае
    /// через `askInterval`, и всё это время окно стояло бы в цвете прошлого проекта.
    static let mainChatSeconds: TimeInterval = 10
    /// Стор попапов на странице работает: `self:null` при нём значит «чат не определён»,
    /// а не «спросить некого» (решение 9 плана WF29).
    static let storeOK = "ok"
    /// Сколько живёт требование «спроси страницы прямо сейчас» (задача #5770): круг уходит
    /// ближайшим тиком (2 с) и отвечает за секунды, а спросившему надо успеть забрать карту.
    /// Дальше при выключенном тумблере канал снова замолкает совсем.
    static let demandSeconds: TimeInterval = 30
    /// Карту тем берём только у страницы claude.ai (решение 3 плана WF35): probe лоадер гоняет
    /// во ВСЕХ страницах, и артефакт на чужом origin вернул бы ПУСТУЮ карту — а пустая карта
    /// значит «Элвис снял всё сам» и чистит файл.
    static let claudeOrigin = "https://claude.ai/"

    /// Кто держит канал — для строки диагностики.
    private enum Channel: String {
        case off, own, busy
    }

    private let files: ChatProbeFiles
    private let now: () -> Date
    private let random: () -> Int

    /// Тумблер «🗂 Цвет по проекту»: выключен — канал не трогаем вовсе. Живьём его вешает
    /// `ClaudeAXController` на `ProjectPaint.enabled`.
    var isEnabled: () -> Bool = { true }
    /// Идёт ли перенос «Обкэшить» (задача #5779). Пока идёт: канал работает даже при
    /// выключенном тумблере (доезд текста дороже покраски), спрашиваем чаще и просим у
    /// страниц ещё одно поле — чем кончилась вставка. Живьём вешает `ClaudeAXController`
    /// на `ClaudeActions.cashoutPending`.
    var isCashoutPending: () -> Bool = { false }

    private var answers: [ChatPage] = []
    private var answeredAt: Date?
    /// Что и когда писали в прошлый раз: побайтное сравнение — первое правило владения.
    private var lastScript: String?
    private var lastStamp: String?
    private var lastWriteAt: Date?
    private var pendingNonce: String?
    /// Отпечаток разобранного `probe-result.json`: файл на 3,9 МБ читаем один раз на круг.
    private var resultStamp: String?
    private var titles: [String] = []
    private var revision: Int?
    private var askedAt: Date?
    /// До этого времени канал занят чужим probe, и отпечаток того самого чужого файла:
    /// пока он не менялся, минуту не перечитываем.
    private var quietUntil: Date?
    private var foreignStamp: String?
    private var channel: Channel = .own
    private var started = false
    /// Карта тем последнего круга (решение 3 плана WF35): её забирает `WindowThemeStore`,
    /// и забирает ровно один раз.
    private var freshThemes: [String: WindowThemeEntry]?
    /// Приложение только что писало зеркало тем — повод спросить страницы (решение 3 плана
    /// WF35). Разовый: снимается первым же вопросом.
    private var mirrored = false
    /// До этого времени канал работает, даже когда тумблер выключен (задача #5770).
    private var demandUntil: Date?
    /// Требование ещё не обслужено: это повод спросить мимо пола частоты. Разовое, как
    /// `mirrored`, — снимается первым же вопросом.
    private var demandPending = false

    init(files: ChatProbeFiles = .onDisk(), now: @escaping () -> Date = Date.init,
         random: @escaping () -> Int = { Int.random(in: 0...9999) }) {
        self.files = files
        self.now = now
        self.random = random
    }

    // MARK: - что знает приложение

    /// Круг состоялся и канал наш. Несвежая карта — это «канал занят чужим probe» или
    /// «кругов ещё не было»: покраска попапов уходит на старый путь по заголовку
    /// (деградация решения 9 плана WF29).
    var isFresh: Bool { answeredAt != nil && channel == .own }

    /// Ответы последнего круга; карта несвежая — пусто.
    var pages: [ChatPage] { isFresh ? answers : [] }

    /// Чат главного окна по ответу самой страницы. Протухший ответ не годится — пусть
    /// решает `status.json` (решение 8 плана WF29). Тем же правилом покраска смотрит на свою
    /// карту (`ProjectPaint.targets()`), поэтому оно одно и живёт в `isRecent`.
    var mainChat: String? {
        pages.first { $0.kind == .main && ChatProbe.isRecent($0, at: now()) }?.chat
    }

    /// Ответ страницы ещё свежий? Только для чата главного окна: у попапов ответ живёт,
    /// пока держится карта, — иначе окна мигали бы между цветом по чату и цветом по заголовку.
    static func isRecent(_ page: ChatPage, at: Date) -> Bool {
        at.timeIntervalSince(page.at) < mainChatSeconds
    }

    /// Последний СВЕЖИЙ ответ главного окна говорит «я на домашнем экране» (план WF37 C3).
    /// Не «Claude впереди» и не «сессии нет в индексе»: спрашивает страница о себе сама,
    /// и как только она уедет в чат, частота вернётся к прежним 15 с (критик, важно 5).
    static func isMainAtHome(_ pages: [ChatPage], at: Date) -> Bool {
        guard let main = pages.last(where: { $0.kind == .main }) else { return false }
        return main.path == homePath && isRecent(main, at: at)
    }

    /// Чат попапа по AX-заголовку окна. Заголовок пустой или заглушка — nil (такой носит
    /// и главное окно, и безымянный попап); заголовок носят два окна — тоже nil, и неважно,
    /// назвали они разные чаты или второе не назвало ничего: лучше не покрасить, чем
    /// покрасить чужим цветом.
    func chat(forTitle title: String) -> String? { ChatProbe.chat(forTitle: title, in: pages) }

    /// То же правило чистой функцией: её же вешает `ClaudeAXController` через `chat(forTitle:)`,
    /// а покраска зовёт сиденьем — второй реализации сопоставления в проекте нет.
    static func chat(forTitle title: String, in pages: [ChatPage]) -> String? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, !ProjectIndex.isStub(wanted) else { return nil }
        var found: String?
        for page in pages where page.kind == .popout
            && page.title.trimmingCharacters(in: .whitespacesAndNewlines) == wanted {
            // Страница с тем же заголовком, которая себя не назвала, — тоже ничья
            // (находка 4 проверки WF29): иначе ручной выбор темы в неопознанном окне уехал
            // бы в проект соседнего окна-однофамильца.
            guard let chat = page.chat else { return nil }
            if let known = found, known != chat { return nil }
            found = chat
        }
        return found
    }

    /// Карта тем страницы из последнего круга (`localStorage["myclaude-themes-v1"]`, решение 3
    /// плана WF35). Отдаётся ОДИН раз: файл догоняет правду ровно на том круге, где она пришла.
    /// nil — поля `themes` в круге не было вовсе (главное окно claude.ai не ответило), и это
    /// не то же самое, что пустая карта.
    func takeThemes() -> [String: WindowThemeEntry]? {
        defer { freshThemes = nil }
        return freshThemes
    }

    /// Приложение записало зеркало тем: ближайший круг обязан спросить страницы, иначе файл
    /// догонял бы правду только зеркалом (решение 3 плана WF35). Пол частоты канала при этом
    /// остаётся прежним — шторма не будет.
    func noteMirror() { mirrored = true }

    /// «Спроси страницы прямо сейчас» (задача #5770). Тумблер «🗂 Цвет по проекту» выключен —
    /// канал молчит совсем (риск 11 плана WF29), и карта чатов пуста: «💾 Сохранить раскладку»
    /// отказывало плашкой «не знаю, какие чаты в окнах — включи тумблер». Требовать тумблер
    /// от человека стыдно, держать канал занятым ради выключенной покраски — тоже, поэтому
    /// канал открывается НА ТРЕБОВАНИЕ и на полминуты: ближайший тик спрашивает страницы
    /// (мимо пола частоты, но не поверх незакрытого круга), спросивший забирает карту через
    /// `answered(after:)` и `pages`, дальше канал замолкает сам.
    func demand(at: Date = Date()) {
        demandPending = true
        demandUntil = at.addingTimeInterval(ChatProbe.demandSeconds)
    }

    /// Пришёл ли круг ПОСЛЕ этого времени: по нему ждущий понимает, что карта уже про сейчас,
    /// а не про прошлый час. Канал не наш (занят агентом) — false, ждать нечего.
    func answered(after: Date) -> Bool {
        guard isFresh, let at = answeredAt else { return false }
        return at >= after
    }

    /// Требование ещё живо? Оно же тут и гасится по времени: спросили и не дождались — канал
    /// возвращается к правилу тумблера, а не остаётся открытым навсегда.
    private func isDemanded(_ at: Date) -> Bool {
        guard let until = demandUntil else { return false }
        guard at < until else {
            demandUntil = nil
            demandPending = false
            return false
        }
        return true
    }

    /// Строка для `statusText`: канал / сколько страниц ответило / сколько назвали свой чат.
    var status: String {
        "\(channel.rawValue)/\(answers.count)/\(answers.filter { $0.chat != nil }.count)"
    }

    // MARK: - тик

    /// Общий тик 2 с: забрать ответ и, если есть повод, спросить заново. Своего таймера
    /// у канала нет — он живёт на том же таймере, что и покраска (решение 3 плана WF29).
    func tick(windowTitles: [String], indexRevision: Int) {
        let at = now()
        // Тумблер выключен — ни записи, ни чтения: probe остаётся инструментом гейта.
        // Исключения два: живое требование (задача #5770) — о чатах окон спросили по делу,
        // и полминуты канал работает как при включённом тумблере; и идущий перенос
        // «Обкэшить» (#5779) — по ответу страницы закрывается окно Элвиса с его текстом,
        // и молчать тут нельзя ни при каком тумблере.
        let cash = isCashoutPending()
        guard isEnabled() || isDemanded(at) || cash else {
            channel = .off
            return
        }
        if channel == .off { channel = .own }
        readAnswer(at)
        let sorted = windowTitles.sorted()
        let unknown = sorted.contains { !isKnown(title: $0) }
        // Повод запоминаем ТОЛЬКО вместе с вопросом: окно открылось, пока шёл прошлый круг
        // или пока канал держал агент, — повод обязан дожить до первого нашего вопроса.
        guard reason(titles: sorted, revision: indexRevision, unknown: unknown, at: at),
              claim(at), ask(scan: unknown, cash: cash, at: at) else { return }
        titles = sorted
        revision = indexRevision
        started = true
        mirrored = false
        demandPending = false
        if unknown { askedAt = at }
    }

    /// Есть ли повод спросить (решение 3 плана WF29): первый тик, изменился набор окон,
    /// изменился состав чатов, есть неопознанное окно и спрашивали давно, канал освободился.
    /// Четвёртый повод добавил WF35: приложение писало зеркало тем, и файл обязан догнать
    /// правду страницы. Плюс два тормоза: пол частоты и незакрытый круг.
    private func reason(titles: [String], revision: Int, unknown: Bool, at: Date) -> Bool {
        // Прошлый круг не закрыт и ещё не потерян — второй не начинаем: старый ответ
        // затёр бы свежий (критик В2 плана WF29).
        if pendingNonce != nil, let wrote = lastWriteAt,
           at.timeIntervalSince(wrote) < ChatProbe.answerTimeout { return false }
        // Требование (задача #5770) сильнее пола частоты: человек ждёт ответа здесь и сейчас,
        // а лишний круг ему стоит одного обхода страниц. Незакрытый круг всё равно сильнее —
        // проверка выше.
        if demandPending { return true }
        // Пол частоты свой, пока главное окно стоит на домашнем экране (план WF37 C3):
        // папку там меняют молча, и о смене чипа мы узнаём только следующим кругом.
        // Признак берём из своей же карты — нового параметра у тика нет.
        let home = ChatProbe.isMainAtHome(pages, at: at)
        let cash = isCashoutPending()
        let floor = cash ? ChatProbe.cashoutInterval
            : (home ? ChatProbe.homeInterval : ChatProbe.askInterval)
        if let wrote = lastWriteAt, at.timeIntervalSince(wrote) < floor { return false }
        if !started { return true }
        // Идущий перенос — повод сам по себе, как и домашний экран: ни заголовки окон, ни
        // состав чатов от того, что текст лёг в поле, не меняются (задача #5779).
        if cash { return true }
        // Домашний экран — повод сам по себе: ни заголовки окон, ни состав чатов при смене
        // папки чипа не меняются, и спросить об этом больше некому.
        if home { return true }
        if mirrored { return true }
        if titles != self.titles { return true }
        if revision != self.revision { return true }
        if channel == .busy { return true }
        guard unknown else { return false }
        guard let asked = askedAt else { return true }
        return at.timeIntervalSince(asked) >= ChatProbe.unknownInterval
    }

    /// Окно опознано? Заглушки и пустые заголовки не в счёт — по ним чат и не ищут.
    private func isKnown(title: String) -> Bool {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, !ProjectIndex.isStub(wanted) else { return true }
        return pages.contains {
            $0.chat != nil && $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == wanted
        }
    }

    /// Ответ на наш круг. Файл весит мегабайты (в нём `url` каждой страницы, включая
    /// `data:`-адреса артефактов) — читаем его только по смене отпечатка, то есть один раз
    /// на круг, а не на тик. Чужой ответ (другой `nonce`) не разбираем вовсе.
    private func readAnswer(_ at: Date) {
        guard let stamp = files.resultInfo(), stamp != resultStamp else { return }
        resultStamp = stamp
        guard let nonce = pendingNonce else { return }
        let fresh = ChatProbe.parseAnswer(files.readResult(), nonce: nonce, at: at)
        guard !fresh.pages.isEmpty else { return }
        // Чужие страницы (артефакты, панель браузера) в карте не нужны — их там четыре пятых.
        answers = fresh.pages.filter { $0.kind != .other }
        // Карта тем ждёт своего читателя (`WindowThemeStore.absorb`); поля не было — nil,
        // и файл в этом круге не трогают вовсе.
        freshThemes = fresh.themes
        answeredAt = at
        pendingNonce = nil
    }

    /// Можно ли писать в `probe.js` (правило владения, решение 2 плана WF29): файла нет;
    /// он побайтно наш; он начинается с нашей метки (свой скрипт от прошлого запуска);
    /// его не трогали дольше 10 минут. Иначе канал держит агент — молчим минуту.
    private func claim(_ at: Date) -> Bool {
        // Файла нет вовсе — канал свободен. Так он и возвращается после `rm probe.js`
        // на гейте: ждать минуту молчания тут нечего (гейт, п. 4).
        guard let info = files.scriptInfo() else { return take() }
        if let stamp = lastStamp, stamp == info.stamp { return take() }
        // Чужой файл на месте и минута молчания не вышла — даже не читаем его.
        if let until = quietUntil, at < until, foreignStamp == info.stamp {
            channel = .busy
            return false
        }
        // Отпечаток чужой или молчание вышло — только теперь читаем сам файл.
        guard let text = files.readScript() else { return wait(at, info.stamp) }
        if text == lastScript || ChatProbe.isOwnScript(text) { return take() }
        if at.timeIntervalSince(info.modified) > ChatProbe.foreignStale { return take() }
        return wait(at, info.stamp)
    }

    /// Наш ли это скрипт ПОБАЙТНО (задача #5741). Метка в первой строке остаётся договором —
    /// по ней и человек на гейте, и приложение видят, кто держит канал, — но одной метки мало:
    /// агент на гейте берёт наш файл за основу (`head -1 probe.js` в чеклисте прямо к этому
    /// подталкивает) и дописывает своё, а мы молча переписывали бы его посреди проверки.
    /// Поэтому из метки берём только круг и собираем скрипт заново: совпал байт в байт — он
    /// правда наш (в том числе от прошлого запуска приложения), не совпал — чужой, и дальше
    /// по прежнему правилу 10 минут.
    static func isOwnScript(_ text: String) -> Bool {
        guard let nonce = markNonce(text) else { return false }
        for scan in [false, true] {
            for cash in [false, true] where text == script(nonce: nonce, scan: scan, cash: cash) {
                return true
            }
        }
        return false
    }

    /// Круг из первой строки (`// myclaude-chats v1 <nonce>`). Метка не с начала строки, хвост
    /// пустой, с пробелом или длиннее потолка — не наша.
    static func markNonce(_ text: String) -> String? {
        let head = text.prefix { $0 != "\n" }
        guard head.hasPrefix(mark) else { return nil }
        let nonce = head.dropFirst(mark.count).trimmingCharacters(in: .whitespaces)
        guard !nonce.isEmpty, nonce.count <= nonceLimit,
              !nonce.contains(where: { $0.isWhitespace }) else { return nil }
        return nonce
    }

    private func take() -> Bool {
        channel = .own
        quietUntil = nil
        foreignStamp = nil
        return true
    }

    /// Канал занят чужим скриптом: карта помечается несвежей, и минуту мы молчим
    /// (агент на гейте гоняет probe десятками — переписывать его файл нельзя).
    private func wait(_ at: Date, _ stamp: String) -> Bool {
        channel = .busy
        foreignStamp = stamp
        quietUntil = at.addingTimeInterval(ChatProbe.foreignQuiet)
        return false
    }

    /// Спросить страницы. Запись не удалась (папки нет, прав нет) — считаем, что не спросили:
    /// повод останется, и ближайший тик попробует снова.
    private func ask(scan: Bool, cash: Bool = false, at: Date) -> Bool {
        let nonce = ChatProbe.makeNonce(at: at, random: random())
        let text = ChatProbe.script(nonce: nonce, scan: scan, cash: cash)
        guard files.writeScript(text) else { return false }
        lastScript = text
        lastStamp = files.scriptInfo()?.stamp
        lastWriteAt = at
        pendingNonce = nonce
        return true
    }

    // MARK: - чистая часть (её же гоняют тесты)

    /// Скрипт для `probe.js`. Первая строка — метка владения, дальше одна проверка «наша ли
    /// это страница» и один вызов `window.__myclaude.chats()`. Ничего не пишет и ничего
    /// не красит: канал общий с гейтом, и побочные действия тут недопустимы.
    ///
    /// `cash` (задача #5779) добавляет к ответу слепок `status().cashout` — что страница
    /// говорит о доезде переноса «Обкэшить». Просим его только пока перенос идёт: `status()`
    /// считается на каждой из четырёх десятков страниц, и платить за него в обычном круге
    /// незачем. Обычный круг при этом остался ПОБАЙТНО прежним: иначе первый запуск после
    /// обновления приложения считал бы свой же вчерашний `probe.js` чужим и молчал 10 минут.
    static func script(nonce: String, scan: Bool, cash: Bool = false) -> String {
        let miss = "{v:1,nonce:\(CommandChannel.jsonString(nonce)),kind:\"other\",store:\"skip\"}"
        let ask = "api.chats({ scan: \(scan), nonce: \(CommandChannel.jsonString(nonce)) })"
        let body = cash ? """
            var answer = \(ask);
            var cashout = null;
            try {
              if (typeof api.status === "function") cashout = (api.status() || {}).cashout || null;
            } catch (e) {}
            return Promise.resolve(answer).then(function (r) {
              return (r && typeof r === "object") ? Object.assign({}, r, { cashout: cashout }) : r;
            });
        """ : """
            return \(ask);
        """
        return """
        \(mark) \(nonce)
        // Пишет PimpMyClaude: спрашивает у страницы, какой в ней чат (план WF29).
        // Свой probe.js на гейте? Приложение уступит: чужой свежий файл оно не переписывает.
        (function () {
          try {
            var api = window.__myclaude;
            if (!api || typeof api.chats !== "function") return \(miss);
        \(body)
          } catch (e) {
            return \(miss);
          }
        })()

        """
    }

    /// Метка круга: миллисекунды и четыре случайные цифры — как `id` у команд.
    static func makeNonce(at: Date, random: Int) -> String {
        String(format: "chats-%d-%04d", Int(at.timeIntervalSince1970 * 1000), random)
    }

    /// Разбор `probe-result.json` лоадера: `{at, results:[{id,url,result|error}]}`.
    /// Берутся только записи со СВОИМ `nonce` — иначе поздно завершившийся прошлый круг
    /// или ответ агентского скрипта попал бы в карту; записи с `error` пропускаются.
    static func parse(_ data: Data?, nonce: String, at: Date) -> [ChatPage] {
        parseAnswer(data, nonce: nonce, at: at).pages
    }

    /// То же, но вместе с картой тем (решение 3 плана WF35). Файл весит мегабайты — разбираем
    /// его один раз и за один проход.
    ///
    /// Поле `themes` берём ТОЛЬКО из ответа страницы `https://claude.ai/…`: probe лоадер гоняет
    /// во всех страницах подряд (`isClaudePage`, `Loader.swift`), и артефакт на чужом origin
    /// вернул бы пустую карту — а пустая карта позже в поколении чистит файл. Попапы
    /// (`about:blank`) поле не шлют вовсе. `themes` без карты (не объект) — тоже не ответ.
    static func parseAnswer(_ data: Data?, nonce: String, at: Date)
        -> (pages: [ChatPage], themes: [String: WindowThemeEntry]?) {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["results"] as? [[String: Any]] else { return ([], nil) }
        var pages: [ChatPage] = []
        var themes: [String: WindowThemeEntry]?
        for entry in list {
            guard let result = entry["result"] as? [String: Any],
                  (result["nonce"] as? String) == nonce else { continue }
            let kind = ChatPage.Kind(rawValue: (result["kind"] as? String) ?? "") ?? .other
            let title = (result["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if themes == nil, let raw = result["themes"] as? [String: Any],
               let url = entry["url"] as? String, url.hasPrefix(claudeOrigin) {
                themes = WindowThemeStore.map(from: raw)
            }
            pages.append(ChatPage(kind: kind, chat: chatId(result["self"] as? String), title: title,
                                  path: (result["path"] as? String) ?? "",
                                  store: (result["store"] as? String) ?? "",
                                  // Папку принимаем ТОЛЬКО у главного окна (план WF37 C2):
                                  // у попапа и чужой страницы её и не бывает, а поверить
                                  // чужой строке значило бы покрасить окно чужим проектом.
                                  folder: kind == .main ? folderPath(result["folder"]) : nil,
                                  cashout: cashoutWord(result["cashout"]),
                                  at: at))
        }
        return (pages, themes)
    }

    /// Слово страницы о доезде переноса (задача #5779). Контракт со страницей один:
    /// `status().cashout` — объект, и в поле `delivery` лежит одно из трёх слов — `"ждём"`,
    /// `"вставлено"`, `"отказ: <причина>"` (`inject.js`, раздел 12). Поля нет, оно не строка,
    /// пустое или длиннее потолка — nil, и приложение считает, что страница ничего не
    /// сказала: донор в этом случае НЕ закрывается вовсе.
    static func cashoutWord(_ value: Any?) -> String? {
        guard let map = value as? [String: Any],
              let said = (map["delivery"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !said.isEmpty, said.count <= cashoutLimit else { return nil }
        return said
    }

    /// Папка из ответа страницы: абсолютный путь и не длиннее `folderLimit`. Всё прочее —
    /// nil: относительный путь пришёл бы из чужого стора, а на нём стоит покраска окна.
    static func folderPath(_ value: Any?) -> String? {
        guard let path = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/"), path.count <= folderLimit else { return nil }
        return path
    }

    /// id чата из ответа страницы. Сито то же, что у адреса страницы в `ProjectIndex.page(url:)`:
    /// `local_` и дальше только буквы, цифры, дефис и подчёркивание — всё прочее пришло не от
    /// Claude, и в поле `chat` команды ему делать нечего.
    static func chatId(_ value: String?) -> String? {
        guard let id = value?.trimmingCharacters(in: .whitespaces),
              id.hasPrefix(ProjectIndex.sessionPrefix), id.count > ProjectIndex.sessionPrefix.count,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        return id
    }
}
