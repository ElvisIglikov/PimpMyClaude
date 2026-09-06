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
    /// Что со стором попапов на странице: `ok`, `cache`, `busy`, `none`, `skip`.
    let store: String
    /// Когда пришёл круг, в котором страница ответила.
    let at: Date
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
/// Класс не потокобезопасен — живёт на главной очереди, вместе с общим тиком 2 с.
final class ChatProbe {
    static let scriptName = "probe.js"
    static let resultName = "probe-result.json"
    /// Метка своего скрипта — по ней приложение узнаёт файл от прошлого запуска, а человек
    /// на гейте видит, кто держит канал (`head -1 probe.js`).
    static let mark = "// myclaude-chats v1"
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
    /// Ответ главного окна старше — берём чат из `status.json` (решение 8 плана WF29).
    static let mainChatSeconds: TimeInterval = 60
    /// Стор попапов на странице работает: `self:null` при нём значит «чат не определён»,
    /// а не «спросить некого» (решение 9 плана WF29).
    static let storeOK = "ok"

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

    /// Чат главного окна по ответу самой страницы. Ответ старше минуты не годится — пусть
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

    /// Чат попапа по AX-заголовку окна. Заголовок пустой или заглушка — nil (такой носит
    /// и главное окно, и безымянный попап); два окна с ОДНИМ заголовком назвали разные
    /// чаты — тоже nil: лучше не покрасить, чем покрасить чужим цветом.
    func chat(forTitle title: String) -> String? { ChatProbe.chat(forTitle: title, in: pages) }

    /// То же правило чистой функцией: её же вешает `ClaudeAXController` через `chat(forTitle:)`,
    /// а покраска зовёт сиденьем — второй реализации сопоставления в проекте нет.
    static func chat(forTitle title: String, in pages: [ChatPage]) -> String? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, !ProjectIndex.isStub(wanted) else { return nil }
        var found: String?
        for page in pages where page.kind == .popout
            && page.title.trimmingCharacters(in: .whitespacesAndNewlines) == wanted {
            guard let chat = page.chat else { continue }
            if let known = found, known != chat { return nil }
            found = chat
        }
        return found
    }

    /// Строка для `statusText`: канал / сколько страниц ответило / сколько назвали свой чат.
    var status: String {
        "\(channel.rawValue)/\(answers.count)/\(answers.filter { $0.chat != nil }.count)"
    }

    // MARK: - тик

    /// Общий тик 2 с: забрать ответ и, если есть повод, спросить заново. Своего таймера
    /// у канала нет — он живёт на том же таймере, что и покраска (решение 3 плана WF29).
    func tick(windowTitles: [String], indexRevision: Int) {
        // Тумблер выключен — ни записи, ни чтения: probe остаётся инструментом гейта.
        guard isEnabled() else {
            channel = .off
            return
        }
        if channel == .off { channel = .own }
        let at = now()
        readAnswer(at)
        let sorted = windowTitles.sorted()
        let unknown = sorted.contains { !isKnown(title: $0) }
        // Повод запоминаем ТОЛЬКО вместе с вопросом: окно открылось, пока шёл прошлый круг
        // или пока канал держал агент, — повод обязан дожить до первого нашего вопроса.
        guard reason(titles: sorted, revision: indexRevision, unknown: unknown, at: at),
              claim(at), ask(scan: unknown, at: at) else { return }
        titles = sorted
        revision = indexRevision
        started = true
        if unknown { askedAt = at }
    }

    /// Есть ли повод спросить (решение 3 плана WF29): первый тик, изменился набор окон,
    /// изменился состав чатов, есть неопознанное окно и спрашивали давно, канал освободился.
    /// Плюс два тормоза: пол частоты и незакрытый круг.
    private func reason(titles: [String], revision: Int, unknown: Bool, at: Date) -> Bool {
        // Прошлый круг не закрыт и ещё не потерян — второй не начинаем: старый ответ
        // затёр бы свежий (критик В2 плана WF29).
        if pendingNonce != nil, let wrote = lastWriteAt,
           at.timeIntervalSince(wrote) < ChatProbe.answerTimeout { return false }
        if let wrote = lastWriteAt, at.timeIntervalSince(wrote) < ChatProbe.askInterval { return false }
        if !started { return true }
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
        let fresh = ChatProbe.parse(files.readResult(), nonce: nonce, at: at)
        guard !fresh.isEmpty else { return }
        // Чужие страницы (артефакты, панель браузера) в карте не нужны — их там четыре пятых.
        answers = fresh.filter { $0.kind != .other }
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
        if text == lastScript || text.hasPrefix(ChatProbe.mark) { return take() }
        if at.timeIntervalSince(info.modified) > ChatProbe.foreignStale { return take() }
        return wait(at, info.stamp)
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
    private func ask(scan: Bool, at: Date) -> Bool {
        let nonce = ChatProbe.makeNonce(at: at, random: random())
        let text = ChatProbe.script(nonce: nonce, scan: scan)
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
    static func script(nonce: String, scan: Bool) -> String {
        let miss = "{v:1,nonce:\(CommandChannel.jsonString(nonce)),kind:\"other\",store:\"skip\"}"
        return """
        \(mark) \(nonce)
        // Пишет PimpMyClaude: спрашивает у страницы, какой в ней чат (план WF29).
        // Свой probe.js на гейте? Приложение уступит: чужой свежий файл оно не переписывает.
        (function () {
          try {
            var api = window.__myclaude;
            if (!api || typeof api.chats !== "function") return \(miss);
            return api.chats({ scan: \(scan), nonce: \(CommandChannel.jsonString(nonce)) });
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
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["results"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let result = entry["result"] as? [String: Any],
                  (result["nonce"] as? String) == nonce else { return nil }
            let kind = ChatPage.Kind(rawValue: (result["kind"] as? String) ?? "") ?? .other
            let title = (result["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ChatPage(kind: kind, chat: chatId(result["self"] as? String), title: title,
                            store: (result["store"] as? String) ?? "", at: at)
        }
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
