import AppKit
import ApplicationServices

// Кружок-микрофон у поля ввода (#7054, контракт К4 плана WF84). Сам значок рисует страница
// (`inject.js`, `#myclaude-mic`) и отдаёт его место в `chats()` полем `mic`; приложение
// ловит клики по нему глобальным монитором мыши:
//   • левый клик, пока запущен Диктатор, — клавиша Диктатора из его настроек (у Элвиса F5,
//     спайк S0): первый клик — запись пошла, второй — остановка, Диктатор вставит текст
//     ⌘V, страница отправит его, когда текст поля сменится и постоит;
//     а если Диктатор уже пишет не с этого кружка — клавишу не жмём, странице `mic-refused`,
//     плашка «Сначала останови запись в Диктаторе» (#7704, WF92);
//   • правый клик — меню «🎙 Рик»: голоса из `Rick/voice/config.json` (`voices`), отметка по
//     `current`, «🔁 Повторить последний ответ». В `profiles.json` Пимп не пишет (критик WF84,
//     «Важное» 7): голос меняет сам `rick_voice.py use <alias>`.
// Режим страницам — команда `mic` `{mode}`: `dictator` только пока Диктатор запущен, иначе
// его клавиша ушла бы в поле текстом; повтор в каждом поколении страниц — тем же правилом,
// что у выключателя Авто-Allow (К3).

/// Режим кружка (К4).
enum MicMode: String {
    case dictator, claude

    /// Поля команды `mic` после id, action, at.
    var fields: [(key: String, value: CommandValue)] {
        [(key: "mode", value: .string(rawValue))]
    }
}

/// Чья диктовка у кнопок микрофона (#9681, слово Элвиса 11.10.2026: «чтобы диктатор её перехватывал эту кнопку…
/// чтобы правой кнопкой… можно было выбирать диктовка какая стандартная клауде или… другая»). Выбор — в меню правой
/// кнопки на кружке и на родной кнопке Claude; хранится у приложения. По умолчанию — Диктатор (как было до #9681).
enum MicChoice: String {
    case dictator, claude

    static let key = "micChoiceWF9681"

    static func load(_ defaults: UserDefaults = .standard) -> MicChoice {
        defaults.string(forKey: key).flatMap(MicChoice.init(rawValue:)) ?? .dictator
    }

    func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.key) }

    var title: String { self == .dictator ? "Диктатор" : "Диктовка Claude" }
}

/// От какого края окна страница считает место значка (контракт WF92 (б), пятый элемент `mic`).
enum MicAnchor: Int, Equatable {
    /// dx от правого края — значок у кружка (как было до WF92).
    case right = 0
    /// dx от левого края — значок в открытом поле.
    case left = 1

    static func parse(_ value: Any?) -> MicAnchor? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        guard raw == raw.rounded() else { return nil }
        return MicAnchor(rawValue: Int(raw))
    }
}

/// Клавиша диктовки из настроек Диктатора (`defaults` домена `kz.elvis.dictatorik`):
/// `hotkeyKeyCode` — виртуальный код клавиши, `hotkeyModifiers` — свои биты Диктатора
/// (`HotkeyModifiers` в `Dictator/Sources/Dictatorik/Settings.swift`): control 1, option 2,
/// shift 4, command 8. Ключей нет — заводская клавиша Диктатора ⌥D.
struct DictatorHotkey: Equatable {
    static let domain = "kz.elvis.dictatorik"
    static let factory = DictatorHotkey(keyCode: 2, modifiers: 1 << 1)

    let keyCode: CGKeyCode
    let modifiers: Int

    /// Функциональные клавиши F1–F20. Настоящее нажатие такой клавиши несёт флаг `fn`
    /// (`maskSecondaryFn`), и Carbon-клавиша Диктатора без него синтетическое нажатие не узнаёт:
    /// живой замер 26.09.2026 — F5 без `fn` Диктатор молча пропускал, с `fn` запись пошла (#7704).
    static let functionKeys: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                               105, 107, 113, 106, 64, 79, 80, 90]

    /// Флаги синтетического нажатия — модификаторы Диктатора, без чужих; у F-клавиш ещё `fn`.
    var flags: CGEventFlags {
        var flags: CGEventFlags = []
        if Self.functionKeys.contains(keyCode) { flags.insert(.maskSecondaryFn) }
        if modifiers & (1 << 0) != 0 { flags.insert(.maskControl) }
        if modifiers & (1 << 1) != 0 { flags.insert(.maskAlternate) }
        if modifiers & (1 << 2) != 0 { flags.insert(.maskShift) }
        if modifiers & (1 << 3) != 0 { flags.insert(.maskCommand) }
        return flags
    }

    /// Из значений настроек. Код не число или вне 0…127 — заводская клавиша целиком: с чужим
    /// кодом и своими модификаторами вышла бы клавиша, которой Диктатор не ждёт.
    static func from(keyCode: Any?, modifiers: Any?) -> DictatorHotkey {
        guard let code = (keyCode as? NSNumber)?.intValue, (0...127).contains(code) else { return factory }
        let mods = (modifiers as? NSNumber)?.intValue ?? 0
        return DictatorHotkey(keyCode: CGKeyCode(code), modifiers: mods & 0b1111)
    }

    /// Живые настройки Диктатора: перечитываем на каждое нажатие — клавишу меняют в его окне.
    static func live() -> DictatorHotkey {
        let app = domain as CFString
        CFPreferencesAppSynchronize(app)
        return from(keyCode: CFPreferencesCopyAppValue("hotkeyKeyCode" as CFString, app),
                    modifiers: CFPreferencesCopyAppValue("hotkeyModifiers" as CFString, app))
    }

    /// Нажать и отпустить. Carbon-клавишу Диктатора синтетическое нажатие будит так же, как
    /// настоящее: событие идёт через оконный сервер (`.cghidEventTap`).
    func post() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}

/// Что делает Диктатор СЕЙЧАС (#7704, WF92). Своего сигнала наружу у Диктатора нет: ни
/// DistributedNotification, ни файла состояния (`running.marker` — только «жив»). В
/// CGWindowList надёжного признака тоже нет: плашка в строке меню числится не за его PID,
/// кружок записи (90×90, слой 1000) выключается настройкой, а рамка свечения (слой 19)
/// горит и в заставке «Светить всегда»; вход микрофона процесса занят и той же заставкой.
/// Признак — его плашка в строке меню через AX (`AXExtrasMenuBar`). Сперва описание: пауза
/// («Диктовка на паузе») и распознавание («Распознаю…») подписаны; потом ширина: в покое
/// плашка квадратная (`NSStatusItem.squareLength`), с часами записи — шире
/// (`RecordingIndicator.refreshStatusItem`).
enum DictatorState: String, Equatable {
    case idle, recording, paused, processing, unknown

    /// Запись не кончилась (пишет или на паузе): чужому кружку её сначала остановить.
    var isRecording: Bool { self == .recording || self == .paused }
}

enum DictatorRecording {
    /// Подпись плашки на паузе — `L("Диктовка на паузе")` на всех языках Диктатора. Пауза — запись идёт.
    static let pausedLabels: Set<String> = ["Диктовка на паузе", "Dictation paused", "Айтып жазу кідірісте"]
    /// Подпись плашки при распознавании — `L("Распознаю…")` на всех языках Диктатора.
    static let processingLabels: Set<String> = ["Распознаю…", "Recognizing…", "Танып жатырмын…"]
    /// Насколько плашка шире высоты, чтобы считаться часами: в покое квадрат, часы — от 40 pt.
    static let widthSlack: CGFloat = 6

    /// Чистая часть: размер пункта строки меню и его AX-описание. Описание сильнее ширины.
    static func state(size: CGSize?, description: String?) -> DictatorState {
        let label = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if pausedLabels.contains(label) { return .paused }
        if processingLabels.contains(label) { return .processing }
        guard let size = size, size.height > 0 else { return .unknown }
        return size.width > size.height + widthSlack ? .recording : .idle
    }

    /// Прежний вопрос «пишет ли» — запись или пауза.
    static func isRecording(size: CGSize, description: String?) -> Bool {
        state(size: size, description: description).isRecording
    }

    /// Живьём. Диктатора нет — idle; плашку не прочесть (нет доступа) — unknown: тогда
    /// микрофон ведёт себя по-старому.
    static func live() -> DictatorState {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: DictatorHotkey.domain).first
        else { return .idle }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AX.timeout(element, 0.25)
        guard let bar = AX.element(element, "AXExtrasMenuBar"),
              let item = AX.elements(bar, kAXChildrenAttribute).first else { return .unknown }
        return state(size: AX.size(item, kAXSizeAttribute), description: AX.string(item, kAXDescriptionAttribute))
    }
}

/// Голос Рика (`Rick/voice/config.json`, ключ `voices`).
struct RickVoice: Equatable {
    let alias: String
    let name: String
}

/// Голоса Рика и их переключение — только через `rick_voice.py`: файлы Рика Пимп не пишет.
enum RickVoices {
    /// Рик лежит в папке проектов (`projectsRoot` из claude.json, WF108): без личного пути в коде.
    static var directory: URL {
        StatusFeed.projectsRoot().appendingPathComponent("Rick/voice", isDirectory: true)
    }
    static var script: URL { directory.appendingPathComponent("rick_voice.py") }
    static var config: URL { directory.appendingPathComponent("config.json") }

    /// Меню Рика есть, только когда есть сам Рик (у команды его нет).
    static func isAvailable(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: script.path) && fileManager.fileExists(atPath: config.path)
    }

    /// Голоса по имени и текущий псевдоним. `use` принимает только ключи `voices`, поэтому
    /// меню строится по ним, а не по `profiles.json` (критик WF84, «Важное» 7).
    static func parse(_ data: Data?) -> (voices: [RickVoice], current: String?) {
        guard let data = data,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([], nil) }
        let voices = (root["voices"] as? [String: Any] ?? [:]).compactMap { alias, value -> RickVoice? in
            guard let name = (value as? [String: Any])?["name"] as? String,
                  !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return RickVoice(alias: alias, name: name)
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return (voices, root["current"] as? String)
    }

    static func load() -> (voices: [RickVoice], current: String?) {
        parse(try? Data(contentsOf: config))
    }

    /// Питон, который есть на этом Маке: у приложения из Finder в PATH только системный.
    static func python(fileManager: FileManager = .default) -> String {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { fileManager.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
    }

    /// `rick_voice.py <args>` в фоне; ответ — на главной очереди: удалось ли и что сказал скрипт.
    static func run(_ args: [String], completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python())
            process.arguments = [script.path] + args
            process.currentDirectoryURL = directory
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var ok = false
            var said = ""
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                ok = process.terminationStatus == 0
                said = String(decoding: data, as: UTF8.self)
            } catch {
                said = error.localizedDescription
            }
            let line = said.split(separator: "\n").last.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            DispatchQueue.main.async { completion(ok, line) }
        }
    }
}

/// Монитор мыши у кружка-микрофона и режим кружка на страницах. Класс не потокобезопасен:
/// живёт на главной очереди вместе с общим тиком 2 с.
final class MicMonitor {
    /// Допуск попадания вокруг значка, точки.
    static let hitSlack: CGFloat = 2
    static let rickTitle = "🎙 Рик"
    static let repeatTitle = "🔁 Повторить последний ответ"
    /// Слово Элвиса (#7704): запись уже идёт — сначала остановить её.
    static let refusedText = "🎙 Сначала останови запись в Диктаторе"
    /// Команда странице (контракт WF92): сбросить счёт нажатий и показать подсказку.
    static let refusedAction = "mic-refused"
    /// Сколько после своего нажатия считать запись идущей, пока плашка Диктатора не догнала.
    static let startGrace: TimeInterval = 1.5
    
    /// Поля `mic-refused` (контракт WF92 (а)): адресно — чат нажатого окна (или null) и его заголовок.
    static func refusedFields(chat: String?, match: String) -> [(key: String, value: CommandValue)] {
        [(key: "reason", value: .string("recording")),
         (key: "chat", value: chat.map { .string($0) } ?? .null),
         (key: "match", value: .string(match))]
    }

    /// Ответы страниц (карта probe). Живьём — `ChatProbe.pages`.
    var pages: () -> [ChatPage] = { [] }
    var claudePID: () -> pid_t? = { nil }
    /// AX-заголовок окна Claude с такой рамкой (перевёрнутые координаты); nil — не нашли.
    var windowTitle: (CGRect) -> String? = { _ in nil }
    /// Команда `mic` во все окна; ушла — true.
    var sendMode: (MicMode) -> Bool = { _ in false }
    var notice: (String) -> Void = { _ in }
    /// После меню Рика фокус обратно Claude.
    var focusClaude: () -> Void = {}
    /// Без Универсального доступа ни окон, ни синтетической клавиши — монитор молчит.
    var isTrusted: () -> Bool = { AX.isTrustedCached }
    /// Что делает Диктатор сейчас.
    var dictatorState: () -> DictatorState = { DictatorRecording.live() }
    /// Клавиша Диктатора.
    var postKey: () -> Void = { DictatorHotkey.live().post() }
    /// Команда `mic-refused` (чат, заголовок нажатого окна); ушла — true.
    var sendRefused: (_ chat: String?, _ match: String) -> Bool = { _, _ in false }
    /// Часы нажатий (тесты подменяют).
    var now: () -> Date = { Date() }

    private(set) var dictatorRunning = false
    /// Выбор диктовки (#9681); `dictator` работает, только пока Диктатор запущен.
    private(set) var choice = MicChoice.load()
    /// Где хранится выбор (тесты подменяют).
    var defaults: UserDefaults = .standard
    private(set) var rickAvailable = false
    private(set) var keys = 0
    private(set) var menus = 0
    private(set) var refusals = 0
    /// Окно (`ownerKey` — CGWindowID), чей кружок начал идущую запись: его второе нажатие её
    /// останавливает, чужое — отказ. Устаревает: Диктатор в покое — хозяина нет.
    private(set) var ownStart: String?
    /// Когда хозяин нажал: пока плашка не догнала (`startGrace`), запись считаем идущей.
    private(set) var ownAt: Date?
    /// Когда тик последний раз спрашивал Диктатора о хозяине.
    private var ownCheckedAt: Date?
    /// Повтор режима в поколении страниц — то же правило, что у выключателя Авто-Allow (К3):
    /// `on` здесь значит «Диктатор запущен».
    private let resend = AutoAllowSwitch()
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// Значок, на котором нажали левую кнопку, и его окно: клавиша уходит, только если
    /// отпустили там же.
    private var pressed: Hit?

    /// Нажатый значок: место, ключ окна-хозяина и адрес страницы для `mic-refused`.
    struct Hit: Equatable {
        let rect: CGRect
        let key: String
        let chat: String?
        let match: String
    }

    /// Режим страниц: Диктатор запущен и выбран (#9681).
    var dictating: Bool { dictatorRunning && choice == .dictator }
    var mode: MicMode { dictating ? .dictator : .claude }
    /// Карта страниц нужна кружку: есть Диктатор или Рик (`ChatProbe.isMicWanted`).
    var wantsPages: Bool { dictatorRunning || rickAvailable }
    /// Карту освежать чаще (контракт WF92 (в)): режим `dictator` и кружок или родная кнопка хоть где-то видны.
    var wantsFastPages: Bool { dictating && pages().contains { $0.mic != nil || $0.micNative != nil } }
    /// Поле `mic=` строки диагностики: режим/повтор поколения/нажатий клавиши/меню Рика/отказов.
    var status: String { "\(mode.rawValue)/\(resend.status)/\(keys)/\(menus)/\(refusals)" }

    func start() {
        stop()
        rickAvailable = RickVoices.isAvailable()
        noteDictator(MicMonitor.isDictatorRunning())
        resend.beginGeneration()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event.type, clickCount: event.clickCount)
        }) {
            monitors.append(monitor)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == DictatorHotkey.domain else { return }
                self?.noteDictator(MicMonitor.isDictatorRunning())
            })
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        pressed = nil
    }

    /// Новое поколение страниц (перезапуск Claude): localStorage с режимом умер вместе с ними.
    func beginGeneration() {
        resend.beginGeneration()
    }

    /// Общий тик: режим страницам — первый тик поколения с окнами и смена их состава.
    func tick(titles: [String], at: Date) {
        expireOwner(at: at)
        resend.on = dictating
        resend.tick(titles: titles, at: at) { [weak self] dictator in
            self?.sendMode(dictator ? .dictator : .claude) ?? false
        }
    }

    static func isDictatorRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: DictatorHotkey.domain).isEmpty
    }

    /// Хозяин записи устаревает (WF92): раз в 2 с спросить Диктатора; в покое — хозяина нет
    /// (запись остановили клавишей или в самом Диктаторе). Пока плашка не догнала нажатие — не трогаем.
    func expireOwner(at: Date) {
        guard ownStart != nil else { return }
        if let checked = ownCheckedAt, at.timeIntervalSince(checked) < 2 { return }
        if let own = ownAt, at.timeIntervalSince(own) < MicMonitor.startGrace { return }
        ownCheckedAt = at
        if dictatorState() == .idle { clearOwner() }
    }

    private func clearOwner() {
        ownStart = nil
        ownAt = nil
        ownCheckedAt = nil
    }

    /// Диктатор запустился или вышел — режим меняется сразу, новым поколением.
    func noteDictator(_ running: Bool) {
        if !running { clearOwner() }
        guard running != dictatorRunning else { return }
        dictatorRunning = running
        resend.on = dictating
        resend.beginGeneration()
    }

    /// Выбор в меню правой кнопки (#9681): запомнить и сразу разослать режим страницам новым поколением.
    func choose(_ value: MicChoice) {
        choice = value
        value.save(defaults)
        if value == .claude { clearOwner() }
        resend.on = dictating
        resend.beginGeneration()
    }

    // MARK: - клики

    private func handle(_ type: NSEvent.EventType, clickCount: Int) {
        let point = Screens.flip(point: NSEvent.mouseLocation)
        mouse(type, clickCount: clickCount, at: point) { [weak self] in self?.micHit(at: point) }
    }

    /// Клик по кружку; `hit` ищет значок под курсором (тесты подставляют свой).
    /// Второй клик двойного (#7873): `clickCount > 1` — клавишу не жмём, иначе Диктатор
    /// останавливается сразу после старта.
    func mouse(_ type: NSEvent.EventType, clickCount: Int, at point: CGPoint, hit: () -> Hit?) {
        switch type {
        case .leftMouseDown:
            pressed = dictating && clickCount <= 1 ? hit() : nil
        case .leftMouseUp:
            guard let hit = pressed else { return }
            pressed = nil
            guard MicMonitor.contains(hit.rect, point) else { return }
            // Режим `dictator` проверяем ещё раз: Диктатор мог выйти, пока держали кнопку.
            guard dictating else { return }
            press(hit)
        case .rightMouseDown:
            // #9681: правой кнопкой — выбор диктовки (пока Диктатор запущен) и голоса Рика.
            guard rickAvailable || dictatorRunning, hit() != nil else { return }
            // Ходом вперёд: монитор не место для модального меню.
            DispatchQueue.main.async { [weak self] in self?.showRickMenu(at: point) }
        default:
            return
        }
    }

    /// Нажатие кружка в режиме `dictator` (#7704): Диктатор уже пишет, и не этим кружком, —
    /// клавишу не жмём, нажатой странице `mic-refused`, человеку плашка.
    func press(_ hit: Hit) {
        let at = now()
        let age = ownAt.map { at.timeIntervalSince($0) }
        switch MicMonitor.decide(state: dictatorState(), own: ownStart, key: hit.key, ownAge: age) {
        case .press(let own):
            if own == nil {
                clearOwner()
            } else if own != ownStart {
                ownStart = own
                ownAt = at
                ownCheckedAt = nil
            }
            postKey()
            keys += 1
        case .refuse:
            refusals += 1
            _ = sendRefused(hit.chat, hit.match)
            notice(MicMonitor.refusedText)
        }
    }

    /// Для тестов и простых вызовов: нажатие окна `key`.
    func press(key: String, chat: String? = nil, match: String = "") {
        press(Hit(rect: .zero, key: key, chat: chat, match: match))
    }

    /// Значок под курсором и его окно: верхнее окно в точке — окно Claude, его страница видит кружок.
    private func micHit(at point: CGPoint) -> Hit? {
        let known = pages()
        guard known.contains(where: { $0.mic != nil || $0.micNative != nil }), isTrusted(), let pid = claudePID(),
              let window = MicMonitor.frontWindow(at: point, in: MicMonitor.windowList(),
                                                  ownPID: getpid()),
              window.pid == pid,
              let page = MicMonitor.page(window: window.frame, title: windowTitle(window.frame) ?? "",
                                         in: known),
              let rect = MicMonitor.spots(page, window: window.frame).first(where: { MicMonitor.contains($0, point) })
        else { return nil }
        return Hit(rect: rect, key: MicMonitor.ownerKey(window: window, page: page), chat: page.chat,
                   match: page.title)
    }

    private func showRickMenu(at point: CGPoint) {
        let rick = rickAvailable ? RickVoices.load() : (voices: [RickVoice](), current: String?.none)
        let menu = MicMonitor.rickMenu(voices: rick.voices, current: rick.current,
                                       choice: dictatorRunning ? choice : nil,
                                       choose: { [weak self] value in
            self?.choose(value)
            self?.notice("🎙 Диктовка — \(value.title)")
        },
                                       use: { [weak self] voice in
            RickVoices.run(["use", voice.alias]) { ok, said in
                self?.notice(ok ? "🎙 Голос Рика — \(voice.name)" : "🎙 Голос не сменился: \(said)")
            }
        }, repeatLast: { [weak self] in
            RickVoices.run(["repeat"]) { ok, said in
                if !ok { self?.notice("🔁 Не повторил: \(said)") }
            }
        })
        menus += 1
        // Как у меню на кнопке окна (#5797): popUp ждёт активного приложения.
        NSApp.activate(ignoringOtherApps: true)
        MinimizeMenu.awaitActive(isActive: { NSApp.isActive }, pump: MinimizeMenu.pumpEvent,
                                 now: { Date.timeIntervalSinceReferenceDate })
        menu.popUp(positioning: nil, at: Screens.flip(point: point), in: nil)
        focusClaude()
    }

    // MARK: - чистая часть (её гоняют тесты)

    enum Decision: Equatable {
        /// Жать клавишу Диктатора; `own` — чей кружок теперь держит запись (nil — ничей).
        case press(own: String?)
        case refuse
    }

    /// Решение по нажатию (WF92):
    ///   • пишет: этим же кружком — жмём, это остановка, хозяина нет; чужим — отказ;
    ///   • на паузе: этим же кружком — жмём, это продолжение, хозяин остаётся; чужим — отказ;
    ///   • иначе, но свой кружок нажали меньше `startGrace` назад (плашка не догнала) — как запись;
    ///   • иначе (покой, распознавание, не узнать) — жмём, запись теперь этого окна.
    static func decide(state: DictatorState, own: String?, key: String, ownAge: TimeInterval?) -> Decision {
        switch state {
        case .recording:
            return own == key ? .press(own: nil) : .refuse
        case .paused:
            return own == key ? .press(own: key) : .refuse
        case .idle, .processing, .unknown:
            if let own = own, let age = ownAge, age >= 0, age < startGrace {
                return own == key ? .press(own: nil) : .refuse
            }
            return .press(own: key)
        }
    }

    /// Чей кружок: окно оконного сервера (CGWindowID) — заголовок и чат у двух окон бывают
    /// одинаковыми. Без номера окна (0) — чат страницы, без него — заголовок.
    static func ownerKey(window: ScreenWindow, page: ChatPage) -> String {
        window.id != 0 ? "win:\(window.id)" : ownerKey(page)
    }

    static func ownerKey(_ page: ChatPage) -> String {
        "\(page.kind.rawValue):" + (page.chat ?? page.title)
    }

    /// Места кнопок окна в экранных координатах: кружок и родная кнопка Claude (#9681).
    static func spots(_ page: ChatPage, window: CGRect) -> [CGRect] {
        [page.mic.map { micRect(spot: $0, window: window, anchor: page.micAnchor) },
         page.micNative.map { micRect(spot: $0, window: window, anchor: page.micNativeAnchor) }].compactMap { $0 }
    }

    static let dictationTitle = "🎙 Диктовка"

    /// Меню правой кнопки: выбор диктовки (#9681, пока Диктатор запущен — `choice` не nil) с отметкой ●/○, дальше
    /// «🎙 Рик» (макет 6.4): заголовок, голоса с отметкой ●/○, «Повторить». Голосов нет — раздела Рика нет.
    static func rickMenu(voices: [RickVoice], current: String?, choice: MicChoice? = nil,
                         choose: @escaping (MicChoice) -> Void = { _ in },
                         use: @escaping (RickVoice) -> Void, repeatLast: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let choice = choice {
            let head = NSMenuItem(title: dictationTitle, action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
            for value in [MicChoice.dictator, .claude] {
                menu.addItem(BlockMenuItem(title: (value == choice ? "● " : "○ ") + value.title) { choose(value) })
            }
            guard !voices.isEmpty else { return menu }
            menu.addItem(.separator())
        }
        let head = NSMenuItem(title: rickTitle, action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        for voice in voices {
            menu.addItem(BlockMenuItem(title: (voice.alias == current ? "● " : "○ ") + voice.name) { use(voice) })
        }
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: repeatTitle) { repeatLast() })
        return menu
    }

    /// Значок в экранных (перевёрнутых) координатах: место от нижнего края окна и от правого
    /// (anchor 0, значок у кружка) или левого (anchor 1, значок в открытом поле) края.
    static func micRect(spot: CGRect, window: CGRect, anchor: MicAnchor = .right) -> CGRect {
        let x = anchor == .left ? window.minX + spot.minX : window.maxX - spot.minX
        return CGRect(x: x, y: window.maxY - spot.minY, width: spot.width, height: spot.height)
    }

    static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        rect.insetBy(dx: -hitSlack, dy: -hitSlack).contains(point)
    }

    /// Страница этого окна: по заголовку (однофамильцев решает рамка — то же правило, что у
    /// покраски, `ChatProbe.nearest`); заголовок не сошёлся (метка замка, переименование) —
    /// по левому верхнему углу рамки. Чужие страницы не в счёт.
    static func page(window: CGRect, title: String, in pages: [ChatPage]) -> ChatPage? {
        let own = pages.filter { $0.kind != .other }
        let wanted = ChatProbe.clean(title)
        let named = wanted.isEmpty ? [] : own.filter { ChatProbe.clean($0.title) == wanted }
        if named.count == 1 { return named[0] }
        if named.count > 1 { return ChatProbe.nearest(named, to: window) }
        // Без заголовка — только страница, чей угол стоит у этого окна, и ровно одна.
        let close = own.filter { $0.frame.map { ChatProbe.near($0, window) } ?? false }
        return close.count == 1 ? close[0] : nil
    }

    /// Окно оконного сервера: владелец, рамка (перевёрнутые координаты), прозрачность.
    struct ScreenWindow: Equatable {
        let pid: pid_t
        let frame: CGRect
        let alpha: CGFloat
        /// CGWindowID; 0 — не знаем.
        var id: CGWindowID = 0
    }

    /// Верхнее окно в точке: список идёт спереди назад; свои окна (плашки, замок) и
    /// прозрачные мимо — клик сквозь них уходит ниже.
    static func frontWindow(at point: CGPoint, in windows: [ScreenWindow], ownPID: pid_t) -> ScreenWindow? {
        windows.first { $0.pid != ownPID && $0.alpha >= ClaudeApp.minWindowAlpha && $0.frame.contains(point) }
    }

    static func windowList() -> [ScreenWindow] {
        WindowInfo.list([.optionOnScreenOnly, .excludeDesktopElements])
            .map { ScreenWindow(pid: $0.pid, frame: $0.frame, alpha: $0.alpha, id: $0.id) }
    }
}
