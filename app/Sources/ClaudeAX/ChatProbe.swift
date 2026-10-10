import CoreGraphics
import CoreFoundation
import Foundation

/// Ответ одной страницы Claude на вопрос «какой в тебе чат» (план WF29, решение 4).
struct ChatPage: Equatable {
    /// Главное окно (`claude.ai/epitaxy/local_…`), вынесенный чат (`about:blank`) или
    /// чужая страница — артефакт, панель браузера, рамка окна.
    enum Kind: String { case main, popout, other }

    let kind: Kind
    /// CGWindowID from loader-owned BrowserWindow metadata, never from renderer result.
    let windowId: CGWindowID?
    var sendDelaySetting: SendDelaySetting?
    var autoContinue: Bool?
    var galleryCounted: Int?
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
    /// Рамка окна, в котором живёт страница (`[screenX, screenY, outerWidth, outerHeight]`,
    /// план WF77): те же перевёрнутые координаты, что у AX. Ею различаются два окна с
    /// ОДИНАКОВЫМ заголовком — у Элвиса это норма (#6734). Поля в ответе нет (старая
    /// страница, чужой origin, браузер не дал чисел) — nil, и окно опознаётся по-старому,
    /// одним заголовком.
    let frame: CGRect?
    /// Место кружка-микрофона (контракт К4 плана WF84, #7054): `[dxRight, dyBottom, w, h]` —
    /// левый верхний угол значка от ПРАВОГО и НИЖНЕГО края окна, в точках; так оно переживает
    /// сдвиг и ресайз окна, пока карта не обновилась. nil — значка не видно (поле открыто,
    /// страница старая) или поля нет. Хранится как есть: `x` = dxRight, `y` = dyBottom.
    let mic: CGRect?
    /// От какого края окна считан `mic.x` (контракт WF92 (б), пятый элемент): 0 — от правого
    /// (значок у кружка), 1 — от левого (значок в открытом поле). Пятого нет — правый.
    let micAnchor: MicAnchor
    /// Работает ли чат страницы (кнопка стопа видна, WF87): только у main и popout;
    /// nil — поля нет (старая страница, чужой origin).
    let working: Bool?
    /// Лимиты подписки (WF87) — только у главного окна; nil — поля нет.
    let limits: ClaudeLimits?
    /// Ход цепочки «Нового окна» (`status().newWindow`, #7378) — только у главного окна и только
    /// в круге переноса; nil — не спрашивали, цепочки не было или поля нет.
    let newWindow: NewWindowRun?
    /// Исход команды `send-text` (`status().send`, WF103) — у любой нашей страницы и только в
    /// круге `cash`; nil — не спрашивали или поля нет.
    let send: SendRun?
    /// Чат страницы ждёт слова Элвиса (#8282, `status().attention.want`: Allow или вопрос Claude, либо ход
    /// кончен и строка состояния говорит «жду»/«упал»; просто законченный ход — нет): у наших страниц и только
    /// в круге с `status()`; nil — не спрашивали.
    var waiting: Bool?
    /// Когда пришёл круг, в котором страница ответила.
    let at: Date

    /// Новые поля — со значениями по умолчанию, чтобы прежние восемь конструкторов в тестах
    /// остались как были (критик, мелочь 1 плана WF37). Автоматический memberwise-init для
    /// `let` со значением по умолчанию Swift не заводит — отсюда свой.
    init(kind: Kind, chat: String?, title: String, path: String = "", store: String,
         folder: String? = nil, cashout: String? = nil, frame: CGRect? = nil, mic: CGRect? = nil,
         micAnchor: MicAnchor = .right, working: Bool? = nil, limits: ClaudeLimits? = nil,
         newWindow: NewWindowRun? = nil, send: SendRun? = nil, windowId: CGWindowID? = nil, at: Date) {
        self.kind = kind
        self.windowId = windowId
        self.chat = chat
        self.title = title
        self.path = path
        self.store = store
        self.folder = folder
        self.cashout = cashout
        self.frame = frame
        self.mic = mic
        self.micAnchor = micAnchor
        self.working = working
        self.limits = limits
        self.newWindow = newWindow
        self.send = send
        self.at = at
    }
}

/// Ход цепочки «Нового окна» главной страницы — слепок `status().newWindow` (`inject.js`,
/// раздел 12б). По нему приложение знает, что «💬 Новый чат» из попапа РОДИЛСЯ и текст
/// передачи ушёл, даже когда свежий попап себя не опознал и «вставлено» не сказал (#7378).
struct NewWindowRun: Equatable {
    /// Штамп последней отметки цепочки (`Date.now()` страницы).
    let at: Date
    /// Шаг: `back` — чат вынесен в окно, главное окно возвращается.
    let step: String
    /// Текст передачи: `send` — ушёл первым сообщением, `empty` — его не было, `held` — лёг в
    /// поле неотправленным, `none` — записи нет, `wait` — ещё не дошли; пусто — не «Новый чат».
    let handoff: String
    /// id нового чата; пусто — сессия ещё не родилась.
    let chat: String
    /// Исход цепочки (`run`, `ok`, `draft`, `no-folder`, …; WF94, K-N): страница СЛИВАЕТ запись,
    /// и прошлый исход висит до новой цепочки — верить ему можно только вместе со свежим `at`.
    var state: String = ""
    /// Цепочка идёт прямо сейчас (`busy` страницы): второе «Новое окно» в это время — без последствий (WF97 Б5s).
    var busy = false
    struct Actual: Equatable {
        let commandId: String
        let chat: String
        let model: String?
        let effort: String?
    }
    var actual: Actual? = nil

    static func actual(_ raw: Any?) -> Actual? {
        guard let fields = raw as? [String: Any] else { return nil }
        func text(_ key: String, limit: Int) -> String? {
            guard let raw = fields[key] as? String else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= limit,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return value
        }
        guard let commandId = text("commandId", limit: 64),
              let chat = text("chat", limit: 128), ChatProbe.chatId(chat) == chat else { return nil }
        return Actual(commandId: commandId, chat: chat, model: text("model", limit: 100), effort: text("effort", limit: 32))
    }

    func confirmedActual(commandId: String, since: Date, now: Date) -> Actual? {
        guard state == "ok", !busy, at > since, now.timeIntervalSince(at) >= 0,
              now.timeIntervalSince(at) <= ChatProbe.mainChatSeconds,
              let actual = actual, actual.commandId == commandId, actual.chat == chat else { return nil }
        return actual
    }

    /// Исходы, после которых чата точно нет и окна не будет (WF94, K-N): канал отказывает
    /// сразу, а не через 40 с `window-missing`. `popout-failed` — чат есть, но в окно не вынесся.
    static let failedStates: Set<String> = ["draft", "no-folder", "no-send", "no-home", "no-store",
                                            "no-insert", "error", "popout-failed"]

    /// Цепочка, начатая ПОСЛЕ `since`, кончилась отказом: её исход, иначе nil.
    func failure(since: Date) -> String? {
        at > since && NewWindowRun.failedStates.contains(state) ? state : nil
    }

    /// Разбор объекта страницы: без числового `at` — nil, прочие поля — строки или пусто.
    static func parse(_ value: Any?) -> NewWindowRun? {
        guard let map = value as? [String: Any],
              let at = (map["at"] as? NSNumber)?.doubleValue, at.isFinite else { return nil }
        let text: (String) -> String = { ((map[$0] as? String) ?? "").trimmingCharacters(in: .whitespaces) }
        return NewWindowRun(at: Date(timeIntervalSince1970: at / 1000), step: text("step"),
                            handoff: text("handoff"), chat: ChatProbe.chatId(text("id")) ?? "",
                            state: text("state"),
                            busy: (map["busy"] as? Bool) == true, actual: actual(map["actual"]))
    }
}

/// Исход `send-text` страницы — слепок `status().send = {id, state, at, sends}` (WF103).
struct SendRun: Equatable {
    /// id команды — он же id запроса канала «Пимп».
    let id: String
    /// `sent`, `field-busy`, `no-field`, `no-send`.
    let state: String

    /// Разбор объекта страницы: без строкового `id` и `state` — nil.
    static func parse(_ value: Any?) -> SendRun? {
        guard let map = value as? [String: Any],
              let id = map["id"] as? String, !id.isEmpty, id.count <= ChatProbe.nonceLimit,
              let state = map["state"] as? String, !state.isEmpty, state.count <= ChatProbe.nonceLimit
        else { return nil }
        return SendRun(id: id, state: state)
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
    /// Пол частоты, пока режим `dictator` и кружок виден (контракт WF92 (в)).
    static let micFastInterval: TimeInterval = 5
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
    /// Допуск сверки рамки окна с рамкой страницы (план WF77, критик блокер 6в). Сверяется
    /// ТОЛЬКО левый верхний угол: ширину Electron зажимает своим минимумом, и по размеру
    /// рамки не сойдутся никогда, а угол сходится точка в точку. Допуск широкий нарочно —
    /// пока окно едет после расстановки, ближайшая страница всё равно его.
    static let frameTolerance: CGFloat = 24
    /// Свой повод спрашивать ради лимитов и «работает ли чат» (WF87): раз в столько, даже когда
    /// «Цвет по проекту» выключен. Вопрос сам заводит в главном окне запрос лимитов (раз в 60 с).
    static let limitsInterval: TimeInterval = 60
    /// Ответ о работе страниц старше — «не знаем», а не «никто не работает».
    static let workingSeconds: TimeInterval = 180

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
    /// Bounded native layout confirmation uses only the ordinary chats payload.
    var isLayoutGuardWanted: () -> Bool = { false }
    /// Нужен ли кружок-микрофон (#7054, К4): запущен Диктатор или есть голос Рика. Пока нужен,
    /// канал работает при любом тумблере и спрашивает страницы не реже раза в `askInterval`:
    /// значок появляется и пропадает вместе с режимом чтения поля, а повода спросить об этом
    /// у приложения нет — ни заголовки окон, ни состав чатов при этом не меняются. Живьём
    /// вешает `ClaudeAXController` на `MicMonitor.wantsPages`.
    var isMicWanted: () -> Bool = { false }
    /// Режим `dictator` и кружок виден (контракт WF92 (в)): пол частоты карты — `micFastInterval`,
    /// а не `askInterval`. Живьём вешает `ClaudeAXController` на `MicMonitor.wantsFastPages`.
    var isMicFast: () -> Bool = { false }
    /// Нужны ли лимиты и «работает ли чат» (значок и панель у часов, WF87). Пока нужны и окна
    /// Claude есть, канал спрашивает страницы раз в `limitsInterval` при любом тумблере.
    var isLimitsWanted: () -> Bool = { false }
    /// Есть окна, спрятанные Пимпом (#8282): канал работает при любом тумблере, спрашивает страницы раз
    /// в `askInterval` и просит `status()` — ждёт ли чат Элвиса. Живьём вешает `ClaudeAXController`.
    var isWaitWanted: () -> Bool = { false }

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
    /// Окна только что переехали (план WF77): рамки в карте стали вчерашними. Разовый повод,
    /// как `mirrored`, — снимается первым же вопросом.
    private var moved = false
    private var staleRefinement: String?
    private var automaticRefinement: (fingerprint: String, at: Date)?
    /// Лимиты и работа страниц из последнего ответа (WF87): живут дольше карты — между
    /// кругами «ради лимитов» канал при выключенном тумблере снова молчит.
    private var lastLimits: ClaudeLimits?
    private var workingChats: Int?
    private var workingAnsweredAt: Date?
    private var lastWorkingAt: Date?
    private var quietSince: Date?
    /// Когда наш круг в последний раз отвечен только непроверенными страницами (старый лоадер).
    private var untrustedAt: Date?

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

    /// Чат попапа по AX-заголовку окна и рамке окна. Заголовок пустой или заглушка — nil
    /// (такой носит и главное окно, и безымянный попап); заголовок носят два окна — решает
    /// РАМКА, а без неё ничья и nil: лучше не покрасить, чем покрасить чужим цветом.
    private var nativeWindows: [WindowIdentity.Native] = []

    func chat(forTitle title: String, frame: CGRect? = nil) -> String? {
        let identity = WindowIdentity.resolve(title: title, frame: frame, pages: pages, nativeWindows: nativeWindows, at: now())
        return identity.page?.kind == .popout ? identity.page?.chat : nil
    }

    /// Чистый вариант общего резолвера. Без native inventory один заголовок ничего не доказывает.
    static func chat(forTitle title: String, frame: CGRect? = nil, in pages: [ChatPage],
                     nativeWindows: [WindowIdentity.Native]? = nil) -> String? {
        let identity = WindowIdentity.resolve(title: title, frame: frame, pages: pages, nativeWindows: nativeWindows)
        return identity.page?.kind == .popout ? identity.page?.chat : nil
    }

    /// Одноимённые страницы назвали один и тот же чат — рамка тут ни при чём. Хоть одна
    /// себя не назвала (находка 4 проверки WF29) или чатов два — nil, дальше решает рамка.
    static func agreedChat(_ pages: [ChatPage]) -> String? {
        let named = pages.compactMap { $0.chat }
        guard named.count == pages.count, Set(named).count == 1 else { return nil }
        return named.first
    }

    /// Какая из одноимённых страниц показывает ИМЕННО это окно: ближайшая по левому верхнему
    /// углу в допуске `frameTolerance` и только при единственном победителе (критик WF77,
    /// блокер 6в). Страница одна — она, и рамки не надо; рамок нет или победителей двое — nil.
    static func nearest(_ pages: [ChatPage], to frame: CGRect?) -> ChatPage? {
        if pages.count == 1 { return pages.first }
        guard let frame = frame else { return nil }
        var best: ChatPage?
        var least = CGFloat.greatestFiniteMagnitude
        var tie = false
        for page in pages {
            guard let corner = page.frame else { continue }
            let distance = hypot(corner.minX - frame.minX, corner.minY - frame.minY)
            guard distance <= frameTolerance else { continue }
            if distance < least {
                least = distance
                best = page
                tie = false
            } else if distance == least {
                tie = true
            }
        }
        return tie ? nil : best
    }

    /// Левый верхний угол рамки страницы и рамки окна сошлись в допуске.
    static func near(_ page: CGRect, _ window: CGRect) -> Bool {
        hypot(page.minX - window.minX, page.minY - window.minY) <= frameTolerance
    }

    /// Заголовки, которые носят два окна и больше: только по ним и работает сверка рамкой.
    /// Пустые и заглушки («Claude», «New chat») в счёт не идут — по ним окно не адресуется
    /// вовсе, и дёргать из-за них probe незачем.
    static func twinTitles(_ titles: [String]) -> Set<String> {
        var seen = Set<String>()
        var twins = Set<String>()
        for raw in titles {
            let title = clean(raw)
            guard !title.isEmpty, !ProjectIndex.isStub(title) else { continue }
            if !seen.insert(title).inserted { twins.insert(title) }
        }
        return twins
    }

    static func clean(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Окна переехали — расстановка, новое окно, перенос «Обкэшить» или рука Элвиса
    /// (критик WF77, блокер 6б). Рамки в карте стали вчерашними, а по ним различаются
    /// окна-однофамильцы: ближайший тик обязан спросить страницы заново. Пол частоты при
    /// этом прежний, и на одиноком окне повода не возникает вовсе (`framesStale`).
    func noteWindowsMoved() { moved = true }

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

    /// Background ambiguity refines once per changed observation, otherwise at most once
    /// a minute. Explicit user demand above remains immediate.
    func demandIdentity(native: [WindowIdentity.Native], at: Date = Date()) {
        let key = Self.refinementFingerprint(native: native, pages: answers)
        if let last = automaticRefinement, last.fingerprint == key,
           at.timeIntervalSince(last.at) < Self.unknownInterval { return }
        automaticRefinement = (key, at)
        demand(at: at)
    }

    static func refinementFingerprint(native: [WindowIdentity.Native], pages: [ChatPage]) -> String {
        let windows = native.map { "n:\($0.id ?? 0):\(CommandChannel.jsonString($0.title)):\(String(describing: $0.frame))" }.sorted()
        let answers = pages.map { "p:\($0.windowId ?? 0):\($0.kind.rawValue):\(CommandChannel.jsonString($0.title)):\(CommandChannel.jsonString($0.chat ?? "")):\(String(describing: $0.frame))" }.sorted()
        return (windows + answers).joined(separator: "\n")
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

    /// Лимиты главного окна и работа страниц для значка и панели у часов (WF87). Ответ о работе
    /// старше `workingSeconds` — «не знаем» (nil), а не «никто не работает».
    var signals: PageSignals {
        var fresh: Int?
        if let at = workingAnsweredAt, now().timeIntervalSince(at) < ChatProbe.workingSeconds { fresh = workingChats }
        return PageSignals(limits: lastLimits, workingChats: fresh, lastWorkingAt: lastWorkingAt,
                           quietSince: quietSince, workingAt: fresh == nil ? nil : workingAnsweredAt,
                           needsRepatch: needsRepatch)
    }

    /// Страницы отвечают, но только со старым лоадером (WF111): окна не опознаются, нужен «Вернуть
    /// патч». Ответ старше `workingSeconds` — уже не знаем (Claude мог перезапуститься с патчем).
    var needsRepatch: Bool {
        untrustedAt.map { now().timeIntervalSince($0) < ChatProbe.workingSeconds } ?? false
    }

    /// Строка для `statusText`: канал / сколько страниц ответило / сколько назвали свой чат.
    var status: String {
        "\(channel.rawValue)/\(answers.count)/\(answers.filter { $0.chat != nil }.count)"
    }

    // MARK: - тик

    /// Тик без рамок окон: окна опознаются одним заголовком, как до WF77. Живьём так уже
    /// не зовут — путь остаётся у тестов и у сборки, где рамки окон взять неоткуда.
    func tick(windowTitles: [String], indexRevision: Int) {
        tick(windows: windowTitles.map { (title: $0, frame: nil) }, indexRevision: indexRevision)
    }

    /// Общий тик 2 с: забрать ответ и, если есть повод, спросить заново. Своего таймера
    /// у канала нет — он живёт на том же таймере, что и покраска (решение 3 плана WF29).
    ///
    /// Окна приходят С РАМКАМИ и БЕЗ схлопывания однофамильцев (план WF77): по рамке карта
    /// различает два окна с одинаковым заголовком, а разъехавшиеся рамки — сами по себе
    /// повод спросить страницы заново (критик блокер 6).
    func tick(windows: [(title: String, frame: CGRect?)], indexRevision: Int) {
        nativeWindows = windows.map { WindowIdentity.Native(title: $0.title, frame: $0.frame) }
        let at = now()
        // Тумблер выключен — ни записи, ни чтения: probe остаётся инструментом гейта.
        // Исключения два: живое требование (задача #5770) — о чатах окон спросили по делу,
        // и полминуты канал работает как при включённом тумблере; и идущий перенос
        // «Обкэшить» (#5779) — по ответу страницы закрывается окно Элвиса с его текстом,
        // и молчать тут нельзя ни при каком тумблере.
        let cash = isCashoutPending()
        // Лимиты (WF87): канал открывается на свой круг раз в минуту и держится, пока круг не закрыт.
        let limits = isLimitsWanted() && !windows.isEmpty && (pendingNonce != nil || limitsDue(at))
        let wait = isWaitWanted()
        guard isEnabled() || isDemanded(at) || cash || isMicWanted() || limits || wait || isLayoutGuardWanted() else {
            channel = .off
            return
        }
        if channel == .off { channel = .own }
        readAnswer(at)
        let sorted = windows.map { $0.title }.sorted()
        let unknown = windows.contains { !isKnown(title: $0.title, frame: $0.frame) }
        let fingerprint = Self.refinementFingerprint(native: nativeWindows, pages: pages)
        let stale = framesStale(windows) && (moved || fingerprint != staleRefinement)
        // Повод запоминаем ТОЛЬКО вместе с вопросом: окно открылось, пока шёл прошлый круг
        // или пока канал держал агент, — повод обязан дожить до первого нашего вопроса.
        guard reason(titles: sorted, revision: indexRevision, unknown: unknown, stale: stale,
                     at: at),
              claim(at), ask(scan: unknown, cash: cash || wait, at: at) else { return }
        titles = sorted
        revision = indexRevision
        started = true
        mirrored = false
        demandPending = false
        moved = false
        if stale { staleRefinement = fingerprint }
        if unknown { askedAt = at }
    }

    /// Есть ли повод спросить (решение 3 плана WF29): первый тик, изменился набор окон,
    /// изменился состав чатов, есть неопознанное окно и спрашивали давно, канал освободился.
    /// Четвёртый повод добавил WF35: приложение писало зеркало тем, и файл обязан догнать
    /// правду страницы. Плюс два тормоза: пол частоты и незакрытый круг.
    private func reason(titles: [String], revision: Int, unknown: Bool, stale: Bool,
                        at: Date) -> Bool {
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
        var floor = cash ? ChatProbe.cashoutInterval
            : (home ? ChatProbe.homeInterval : ChatProbe.askInterval)
        if isMicWanted() && isMicFast() { floor = min(floor, ChatProbe.micFastInterval) }
        if isLayoutGuardWanted() { floor = min(floor, ChatProbe.cashoutInterval) }
        if let wrote = lastWriteAt, at.timeIntervalSince(wrote) < floor { return false }
        if !started { return true }
        // Идущий перенос — повод сам по себе, как и домашний экран: ни заголовки окон, ни
        // состав чатов от того, что текст лёг в поле, не меняются (задача #5779).
        if cash || isLayoutGuardWanted() { return true }
        // Домашний экран — повод сам по себе: ни заголовки окон, ни состав чатов при смене
        // папки чипа не меняются, и спросить об этом больше некому.
        if home { return true }
        // Кружок-микрофон (К4): его место меняется молча — раз в пол частоты, как домашний экран.
        if isMicWanted() { return true }
        // Лимиты и «работает ли чат» (WF87) меняются молча — раз в минуту.
        if isLimitsWanted() && limitsDue(at) { return true }
        // Спрятанные окна (#8282): чат в свёрнутом окне начинает ждать Элвиса молча — раз в пол частоты.
        if isWaitWanted() { return true }
        if mirrored { return true }
        // Рамки окон разошлись с рамками карты (критик WF77, блокер 6): после расстановки
        // и после того, как окно подвинули рукой, карта про однофамильцев врёт, а заголовки
        // и поколение индекса при этом не меняются — без этого повода починка жила бы
        // до первой же расстановки.
        if stale { return true }
        if titles != self.titles { return true }
        if revision != self.revision { return true }
        if channel == .busy { return true }
        guard unknown else { return false }
        guard let asked = askedAt else { return true }
        return at.timeIntervalSince(asked) >= ChatProbe.unknownInterval
    }

    /// Пора спросить ради лимитов: с прошлого вопроса прошла минута.
    private func limitsDue(_ at: Date) -> Bool {
        guard let wrote = lastWriteAt else { return true }
        return at.timeIntervalSince(wrote) >= ChatProbe.limitsInterval
    }

    /// Окно опознано? Заглушки и пустые заголовки не в счёт — по ним чат и не ищут.
    /// Однофамильцы (план WF77): окно опознано, только когда карта отвечает именно ПРО НЕГО —
    /// иначе покраска всё равно промолчит, и страницы надо спросить ещё раз.
    private func isKnown(title: String, frame: CGRect?) -> Bool {
        let wanted = ChatProbe.clean(title)
        guard !wanted.isEmpty, !ProjectIndex.isStub(wanted) else { return true }
        let twins = pages.filter { ChatProbe.clean($0.title) == wanted }
        guard !twins.isEmpty else { return false }
        if ChatProbe.agreedChat(twins) != nil { return true }
        return ChatProbe.nearest(twins, to: frame)?.chat != nil
    }

    /// Живые рамки окон разошлись с рамками карты. Смотрим ТОЛЬКО однофамильцев: одинокое
    /// окно опознаётся заголовком, и дёргать probe на каждое его движение незачем (критик
    /// WF77, блокер 6а). Карта про этот заголовок рамок не знает вовсе (страница старая,
    /// ответа ещё не было) — сверять нечего, и лишний круг ничего не даст.
    private func framesStale(_ windows: [(title: String, frame: CGRect?)]) -> Bool {
        let twins = ChatProbe.twinTitles(windows.map { $0.title })
        guard !twins.isEmpty else { return false }
        // Окна ТОЛЬКО что двигали — спрашиваем, не сверяя: рамки в карте старше переезда.
        if moved { return true }
        for window in windows {
            let title = ChatProbe.clean(window.title)
            guard twins.contains(title), let frame = window.frame else { continue }
            let known = pages.filter { ChatProbe.clean($0.title) == title }.compactMap { $0.frame }
            guard !known.isEmpty else { continue }
            guard !known.contains(where: { ChatProbe.near($0, frame) }) else { continue }
            return true
        }
        return false
    }

    /// Ответ на наш круг. Файл весит мегабайты (в нём `url` каждой страницы, включая
    /// `data:`-адреса артефактов) — читаем его только по смене отпечатка, то есть один раз
    /// на круг, а не на тик. Чужой ответ (другой `nonce`) не разбираем вовсе.
    private func readAnswer(_ at: Date) {
        guard let stamp = files.resultInfo(), stamp != resultStamp else { return }
        resultStamp = stamp
        guard let nonce = pendingNonce else { return }
        let data = files.readResult()
        let fresh = ChatProbe.parseAnswer(data, nonce: nonce, at: at)
        guard !fresh.pages.isEmpty else {
            // Наш круг отвечен, но только без печати лоадера v8 — Claude живёт со старым лоадером.
            if ChatProbe.answeredUntrusted(data, nonce: nonce) { untrustedAt = at }
            return
        }
        untrustedAt = nil
        // Чужие страницы (артефакты, панель браузера) в карте не нужны — их там четыре пятых.
        answers = fresh.pages.filter { $0.kind != .other }
        // Карта тем ждёт своего читателя (`WindowThemeStore.absorb`); поля не было — nil,
        // и файл в этом круге не трогают вовсе.
        freshThemes = fresh.themes
        absorbSignals(fresh.pages, at: at)
        answeredAt = at
        pendingNonce = nil
    }

    /// Лимиты главного окна и работа страниц (WF87). Ни одна страница не прислала `working`
    /// (старый inject.js) — о работе молчим, а не говорим «никто не работает».
    private func absorbSignals(_ pages: [ChatPage], at: Date) {
        if let limits = pages.last(where: { $0.kind == .main && $0.limits != nil })?.limits { lastLimits = limits }
        let said = pages.compactMap { $0.working }
        guard !said.isEmpty else { return }
        let busy = said.filter { $0 }.count
        workingChats = busy
        workingAnsweredAt = at
        if busy > 0 { lastWorkingAt = at } else if quietSince == nil { quietSince = at }
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
    /// говорит о доезде переноса «Обкэшить», — и `status().newWindow` (#7378: дошла ли цепочка
    /// «Нового окна» до выноса и ушёл ли текст передачи), а с WF103 — `status().send` (исход команды
    /// `send-text` у любого окна), а с #8282 — `status().attention.want` (чат ждёт слова Элвиса; нужен, пока есть окна,
    /// спрятанные Пимпом). Просим их только пока перенос или `send` идёт: `status()`
    /// считается на каждой из четырёх десятков страниц, и платить за него в обычном круге
    /// незачем. Обычный круг при этом остался ПОБАЙТНО прежним: иначе первый запуск после
    /// обновления приложения считал бы свой же вчерашний `probe.js` чужим и молчал 10 минут.
    static func script(nonce: String, scan: Bool, cash: Bool = false) -> String {
        let miss = "{v:1,nonce:\(CommandChannel.jsonString(nonce)),kind:\"other\",store:\"skip\"}"
        let ask = "api.chats({ scan: \(scan), nonce: \(CommandChannel.jsonString(nonce)) })"
        let body = cash ? """
            var answer = \(ask);
            var cashout = null;
            var newWindow = null;
            var send = null;
            var wait = false;
            try {
              if (typeof api.status === "function") {
                var status = api.status() || {};
                cashout = status.cashout || null;
                newWindow = status.newWindow || null;
                send = status.send || null;
                wait = !!(status.attention && status.attention.want);
              }
            } catch (e) {}
            return Promise.resolve(answer).then(function (r) {
              return (r && typeof r === "object") ? Object.assign({}, r, { cashout: cashout, newWindow: newWindow, send: send, wait: wait }) : r;
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
            guard trustedSource(entry), let result = entry["result"] as? [String: Any],
                  (result["nonce"] as? String) == nonce else { continue }
            let kind = ChatPage.Kind(rawValue: (result["kind"] as? String) ?? "") ?? .other
            let title = (result["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if themes == nil, let raw = result["themes"] as? [String: Any],
               let url = entry["url"] as? String, url.hasPrefix(claudeOrigin) {
                themes = WindowThemeStore.map(from: raw, trimming: false)
            }
            pages.append(ChatPage(kind: kind, chat: chatId(result["self"] as? String), title: title,
                                  path: (result["path"] as? String) ?? "",
                                  store: (result["store"] as? String) ?? "",
                                  // Папку принимаем ТОЛЬКО у главного окна (план WF37 C2):
                                  // у попапа и чужой страницы её и не бывает, а поверить
                                  // чужой строке значило бы покрасить окно чужим проектом.
                                  folder: kind == .main ? folderPath(result["folder"]) : nil,
                                  cashout: cashoutWord(result["cashout"]),
                                  frame: frameRect(result["frame"]),
                                  mic: micSpot(result["mic"]),
                                  micAnchor: micAnchor(result["mic"]),
                                  // WF87: работа — у наших страниц, лимиты — только у главного окна.
                                  working: kind == .other ? nil : result["working"] as? Bool,
                                  limits: kind == .main ? ClaudeLimits.parse(result["limits"]) : nil,
                                  // #7378: ход цепочки «Нового окна» — только у главного окна.
                                  newWindow: kind == .main ? NewWindowRun.parse(result["newWindow"]) : nil,
                                  // WF103: исход `send-text` — у любого нашего окна.
                                  send: kind == .other ? nil : SendRun.parse(result["send"]),
                                  windowId: sourceWindowId((entry["source"] as? [String: Any])?["windowId"]),
                                  at: at))
            // #8282: ждёт ли чат Элвиса — у наших страниц, поле есть только в круге с `status()`.
            if kind != .other { pages[pages.count - 1].waiting = result["wait"] as? Bool }
            if kind != .other { pages[pages.count - 1].sendDelaySetting = SendDelaySetting.parse(result["sendDelaySetting"]) }
            if kind != .other { pages[pages.count - 1].autoContinue = result["autoContinue"] as? Bool }
            if kind != .other, let value = result["galleryCounted"] as? NSNumber,
               CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
               value.doubleValue >= 0, value.doubleValue <= 9_007_199_254_740_991,
               value.doubleValue.rounded(.towardZero) == value.doubleValue {
                pages[pages.count - 1].galleryCounted = value.intValue
            }
        }
        return (pages, themes)
    }

    /// На наш круг ответили страницы, и ни на одной нет печати лоадера v8 (WF111): так отвечает
    /// Claude со старым лоадером (v7) — до перепатча или если перепатч сорвался.
    static func answeredUntrusted(_ data: Data?, nonce: String) -> Bool {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["results"] as? [[String: Any]] else { return false }
        let ours = list.filter { (($0["result"] as? [String: Any])?["nonce"] as? String) == nonce }
        return !ours.isEmpty && !ours.contains { ($0["source"] as? [String: Any])?["loader"] as? Int == 8 }
    }

    /// Metadata is written outside renderer-controlled `result` by loader v8. Old loaders cannot
    /// establish blank-page provenance, so their answers fail closed until an authorized repatch.
    static func trustedSource(_ entry: [String: Any]) -> Bool {
        guard let source = entry["source"] as? [String: Any],
              source["loader"] as? Int == 8, source["origin"] as? String == "https://claude.ai",
              let url = source["url"] as? String, entry["url"] as? String == url,
              let process = source["processId"] as? Int, process > 0,
              let routing = source["routingId"] as? Int, routing > 0 else { return false }
        if let value = source["windowId"], sourceWindowId(value) == nil { return false }
        if url == "about:blank" || url.isEmpty { return true }
        guard let parsed = URLComponents(string: url) else { return false }
        return parsed.scheme == "https" && parsed.host == "claude.ai"
            && (parsed.port == nil || parsed.port == 443) && parsed.user == nil && parsed.password == nil
    }

    static func sourceWindowId(_ value: Any?) -> CGWindowID? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let n = number.doubleValue
        guard n.isFinite, n >= 1, n <= Double(UInt32.max), n.rounded(.towardZero) == n else { return nil }
        return CGWindowID(n)
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

    /// Рамка окна из ответа страницы (план WF77, решение 10): `[screenX, screenY, outerWidth,
    /// outerHeight]`, четыре конечных числа, ширина и высота больше нуля. Разбор
    /// НЕОБЯЗАТЕЛЬНЫЙ: поля нет, длина не та, внутри не числа — nil, и окно опознаётся
    /// по-старому, одним заголовком (старая страница не должна ломать новое приложение).
    static func frameRect(_ value: Any?) -> CGRect? {
        guard let list = value as? [Any], list.count == 4 else { return nil }
        let numbers = list.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard numbers.count == 4, numbers.allSatisfy({ $0.isFinite }),
              numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    /// Место кружка-микрофона из ответа страницы (К4): `[dx, dyBottom, w, h]` или с пятым
    /// элементом `anchor` (контракт WF92 (б): 0 — dx от правого края, 1 — от левого); четыре
    /// конечных числа больше нуля (значок внутри окна, размер есть), anchor — 0 или 1.
    /// `null`, поля нет или мусор — nil: кружка не видно, кликам мимо него приложение не мешает.
    static func micSpot(_ value: Any?) -> CGRect? {
        guard let list = value as? [Any], list.count == 4 || list.count == 5 else { return nil }
        let numbers = list.prefix(4).compactMap { ($0 as? NSNumber)?.doubleValue }
        guard numbers.count == 4, numbers.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        if list.count == 5, MicAnchor.parse(list[4]) == nil { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    /// Край, от которого считан `mic` (контракт WF92 (б)); четыре элемента или мусор — правый.
    static func micAnchor(_ value: Any?) -> MicAnchor {
        guard let list = value as? [Any], list.count == 5 else { return .right }
        return MicAnchor.parse(list[4]) ?? .right
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
