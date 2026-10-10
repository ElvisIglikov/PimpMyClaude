import CoreGraphics
import Foundation

/// Одно окно снимка «окна как были» (#7065, контракт К5 плана WF84).
struct SnapshotWindow: Equatable {
    /// id чата (`local_…`) или `main` — главное окно Claude: при возврате ему ставится
    /// только рамка, чат в нём Claude выбирает сам.
    let chat: String
    /// Папка проекта или "" — приложение её не знало.
    let folder: String
    /// Заголовок окна: им плашка называет чат, которого больше нет.
    let title: String
    /// Рамка в перевёрнутых координатах (как у AX) — абсолютная, экран в ней уже зашит.
    let frame: CGRect
    /// Имя экрана, где стоял центр окна, — справка для человека; возврат его не читает.
    let screen: String
}

/// Снимок окон Claude: когда снят, при каком Claude (его версия) и какие окна где стояли.
struct WindowSnapshot: Equatable {
    let at: Date
    let claude: String
    let windows: [SnapshotWindow]
    let restorePending: Bool
    let restoreExpected: [SnapshotWindow]?

    init(at: Date, claude: String, windows: [SnapshotWindow], restorePending: Bool = false, restoreExpected: [SnapshotWindow]? = nil) {
        self.at = at; self.claude = claude; self.windows = windows; self.restorePending = restorePending
        self.restoreExpected = restoreExpected
    }
}

/// The list and its completeness belong to one observation, never to separate AX reads.
struct SnapshotObservation {
    let windows: [SnapshotWindow]
    let complete: Bool
}

/// Файл `~/Library/Application Support/MyClaude/windows-snapshot.json` (контракт К5):
/// `{"version":1,"at","claude","windows":[{"chat","folder","title","frame":[x,y,w,h],"screen"}]}`.
/// Файл приложения — лоадер его не знает, как `layouts.json` и `window-themes.json`.
/// Битый файл — снимка нет.
final class WindowSnapshotStore {
    static let fileName = "windows-snapshot.json"
    static let version = 1
    static var defaultURL: URL { CommandChannel.directory.appendingPathComponent(fileName) }

    /// Claude запущен не раньше, чем за столько до того, как Пимп его увидел, — иначе
    /// автовозврата нет (критик WF84 Б4а): Пимп подменили на Claude, который работает
    /// давно, а свежего снимка у него нет (все окна были спрятаны). Возраст самого снимка
    /// не ограничен (критик п. 12): утром после ночи окна обязаны вернуться.
    static let freshLaunchSeconds: TimeInterval = 300
    /// Имя возврата на плашке канала: «Вернул «Окна как были»: 1 стояло, 4 открыл».
    static let restoreName = "Окна как были"

    private let url: URL

    init(url: URL = WindowSnapshotStore.defaultURL) { self.url = url }

    func load() -> WindowSnapshot? { WindowSnapshotStore.parse(try? Data(contentsOf: url)) }

    @discardableResult
    func save(_ snapshot: WindowSnapshot) -> Bool {
        CommandChannel.writeAtomic(url, WindowSnapshotStore.json(snapshot))
    }

    // MARK: - чистая часть (её гоняют тесты)

    /// Возвращать ли окна этому Claude (контракт К5, критик Б4): Claude запущен ПОЗЖЕ снимка
    /// (подмена Пимпа на живом Claude окон по второму разу не открывает), запущен недавно
    /// (`freshLaunchSeconds`) и в снимке есть окна.
    static func shouldRestore(_ snapshot: WindowSnapshot, launch: Date?, seenAt: Date) -> Bool {
        guard let launch = launch, !snapshot.windows.isEmpty, launch > snapshot.at else { return false }
        return seenAt.timeIntervalSince(launch) <= freshLaunchSeconds
    }

    /// Окна канала → окна снимка. Главное окно — первым и одно (`main`); окно, чей чат
    /// приложение не знает, и второе «главное» (безымянный попап носит ту же заглушку,
    /// #5729) в снимок не идут — вернуть их нечем. Остальные — слева направо, сверху вниз
    /// (`ArrangeLayout.order`), по одному на чат.
    static func windows(from list: [PimpWindow], isMain: (String) -> Bool,
                        screen: (CGRect) -> String) -> [SnapshotWindow] {
        var main: SnapshotWindow?
        var rest: [SnapshotWindow] = []
        var chats = Set<String>()
        for index in ArrangeLayout.order(of: list.map { $0.frame }) {
            let window = list[index]
            if window.isMain(using: isMain) {
                guard main == nil else { continue }
                main = SnapshotWindow(chat: LayoutsStore.mainChat, folder: window.folder,
                                      title: window.title, frame: window.frame,
                                      screen: screen(window.frame))
                continue
            }
            let chat = window.chat.trimmingCharacters(in: .whitespaces)
            guard !chat.isEmpty, chat != LayoutsStore.mainChat, chats.insert(chat).inserted else { continue }
            rest.append(SnapshotWindow(chat: chat, folder: window.folder, title: window.title,
                                       frame: window.frame, screen: screen(window.frame)))
        }
        return (main.map { [$0] } ?? []) + rest
    }

    /// Главных окон 0 или 1 (находка судьи WF111, как до WF116): закрытое главное окно Electron
    /// прячет, и у Элвиса его на экране обычно нет — это полный замер, а не неизвестный.
    static func observe(from list: [PimpWindow], complete: Bool, isMain: (String) -> Bool,
                        screen: (CGRect) -> String) -> SnapshotObservation {
        let snapshot = windows(from: list, isMain: isMain, screen: screen)
        return SnapshotObservation(windows: snapshot,
            complete: complete && snapshot.count == list.count
                && Set(list.map { $0.id }).count == list.count
                && list.filter { $0.isMain(using: isMain) }.count <= 1)
    }

    /// Порядок ключей побайтно: version, at, claude, windows; в окне — chat, folder, title,
    /// frame, screen.
    static func json(_ snapshot: WindowSnapshot) -> String {
        CommandValue.object([
            (key: "version", value: .number(version)),
            (key: "at", value: .string(PimpChannel.stampText(snapshot.at))),
            (key: "claude", value: .string(snapshot.claude)),
            (key: "windows", value: windowValues(snapshot.windows)),
        ] + (snapshot.restorePending ? [(key: "restorePending", value: .bool(true))] : [])
          + (snapshot.restoreExpected.map { [(key: "restoreExpected", value: windowValues($0))] } ?? [])).json + "\n"
    }

    static func windowValues(_ windows: [SnapshotWindow]) -> CommandValue {
        .array(windows.map { window in .object([
            (key: "chat", value: .string(window.chat)), (key: "folder", value: .string(window.folder)),
            (key: "title", value: .string(window.title)), (key: "frame", value: PimpChannel.frameValue(window.frame)),
            (key: "screen", value: .string(window.screen))
        ]) })
    }

    /// Нет `at` или чужая версия — снимка нет. Окно без чата или без рамки из четырёх
    /// чисел пропускается, остальные читаются.
    static func parse(_ data: Data?) -> WindowSnapshot? {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["version"] as? NSNumber)?.intValue == version,
              let at = (root["at"] as? String).flatMap(PimpChannel.date) else { return nil }
        return WindowSnapshot(at: at, claude: (root["claude"] as? String) ?? "",
                              windows: windows(from: root["windows"]), restorePending: root["restorePending"] as? Bool ?? false,
                              restoreExpected: root["restoreExpected"].map { windows(from: $0) })
    }

    /// Окна записи — общий разбор снимка К5 и расстановок по мониторам (WF94,
    /// `windows-by-screens.json`): формат окна у них один.
    static func windows(from value: Any?) -> [SnapshotWindow] {
        let items = (value as? [[String: Any]]) ?? []
        return items.compactMap { item -> SnapshotWindow? in
            let chat = ((item["chat"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard !chat.isEmpty, let numbers = item["frame"] as? [NSNumber], numbers.count == 4
            else { return nil }
            let frame = CGRect(x: numbers[0].doubleValue, y: numbers[1].doubleValue,
                               width: numbers[2].doubleValue, height: numbers[3].doubleValue)
            guard frame.width > 0, frame.height > 0 else { return nil }
            return SnapshotWindow(chat: chat, folder: (item["folder"] as? String) ?? "",
                                  title: (item["title"] as? String) ?? "", frame: frame,
                                  screen: (item["screen"] as? String) ?? "")
        }
    }
}

/// Кто ведёт снимок окон и когда их возвращать (#7065, контракт К5, критик WF84 Б4).
///
/// Триггер возврата ОДИН — появление процесса Claude (при старте Пимпа или сменой pid).
/// В этот момент снимок читается в память, и если Claude запущен позже снимка, окна
/// возвращаются, как только у Claude есть окно и главная страница ответила (или вышла
/// запасная пауза). Пока возврат этого Claude не кончился или не брошен, файл снимка НЕ
/// пишется: иначе тик записал бы экран с одним главным окном, и возвращать было бы нечего.
/// Дальше снимок пишется сам — когда набор окон простоял два замера подряд и отличается от
/// записанного (и один раз обязательно для каждого Claude: `at` снимка должен стать позже
/// его запуска, иначе подмена Пимпа вернула бы окна ещё раз).
///
/// Всё, что нужно от приложения, приходит сиденьями — тесты гоняют это без AX и без Claude.
/// Исход автовозврата снимка для `restart-claude` (гейт 2 WF108): возврат ещё впереди, возвращать
/// нечего или снимок сдался — окна нового Claude не появились за `giveUpSeconds` (`skipped` —
/// заголовки чатов снимка, главное окно не в счёт). Кончившийся возврат канал знает сам.
enum SnapshotOutcome: Equatable {
    case pending
    case notNeeded
    case gaveUp(skipped: [String])
}

final class WindowSnapshotKeeper {
    enum Phase: Equatable {
        /// Claude не запущен.
        case idle
        /// Ждём окно и страницу, чтобы вернуть окна.
        case waiting
        /// Возврат идёт очередью канала «Пимп».
        case restoring
        /// Возврата нет или он кончился — снимок ведётся.
        case keeping
    }

    /// Выбранный Claude: pid, когда запущен и его версия (поле `claude` снимка).
    var claude: () -> (pid: pid_t, launch: Date?, version: String)? = { nil }
    /// Окна на экране — уже в виде окон снимка.
    var windows: () -> [SnapshotWindow] = { [] }
    var observation: (() -> SnapshotObservation)?
    var busy: () -> Bool = { false }
    var adaptFrame: (CGRect) -> CGRect = { $0 }
    private func observe() -> SnapshotObservation {
        observation?() ?? SnapshotObservation(windows: windows(), complete: true)
    }
    /// Ответила ли главная страница ПОСЛЕ запуска Claude (лоадер жив, `popout-window` дойдёт).
    var pageReady: (Date?) -> Bool = { _ in false }
    /// Попросить страницы ответить прямо сейчас (`ChatProbe.demand`) — и при выключенном
    /// тумблере «🗂 Цвет по проекту».
    var demandPages: () -> Void = {}
    /// Начать возврат очередью канала; false — канал занят или окон нет, попробуем позже.
    var startRestore: (WindowSnapshot) -> Bool = { _ in false }
    /// Идёт ли возврат в канале.
    var isRestoring: () -> Bool = { false }
    /// Сколько окон Claude свёрнуто (WF112, #8255): пока они есть, снимок не пишется — свёрнутых
    /// в списке окон нет, и снимок «спрятанных» окон затёрся бы одним главным (критик WF111).
    var minimized: () -> Int = { 0 }

    /// Как часто снимаем окна, пока ведём снимок.
    static let sampleSeconds: TimeInterval = 4
    /// Сколько ждём окна и страницу нового Claude, прежде чем бросить автовозврат.
    static let giveUpSeconds: TimeInterval = 120
    /// Окно есть, а страница молчит (канал probe занят агентом) — через столько возвращаем всё
    /// равно: `popout-window` лоадер прочтёт, как только страница встанет.
    static let pageFallbackSeconds: TimeInterval = 20
    /// Как часто переспрашиваем страницы, пока ждём.
    static let demandSeconds: TimeInterval = 10

    private let store: WindowSnapshotStore
    private(set) var phase: Phase = .idle
    private var pid: pid_t?
    private var launch: Date?
    /// Снимок, прочитанный при появлении этого Claude и снятый ДО его запуска: его
    /// возвращает и автовозврат, и ручной пункт «↩️ Вернуть окна».
    private(set) var launchSnapshot: WindowSnapshot?
    /// Снимок, возврат которого этот Claude бросил по `giveUpSeconds` (гейт 2 WF108); nil — не бросал.
    private(set) var gaveUp: WindowSnapshot?
    private var waitingSince: Date?
    private var windowsSeenAt: Date?
    private var demandedAt: Date?
    private var sampledAt: Date?
    private var lastSample: [SnapshotWindow]?
    private var written: [SnapshotWindow]?
    /// Until full placement is observed, the pre-restore file is also the durable baseline.
    private var protected: [SnapshotWindow]?
    /// Защита после возврата не вечная (находка судьи WF111): возврат кончился — первый полный
    /// замер вне работы канала убирает из ожидания чаты, которых среди окон нет (закрыт,
    /// в архиве, не открылся), и заводит срок `releaseSeconds`; вышел — пишется следующий полный
    /// стабильный замер. Защита, доставшаяся с диска от прошлого запуска Пимпа, — только срок.
    private var settleArmed = false
    private var inheritedPending = false
    private var protectedSince: Date?
    static let releaseSeconds: TimeInterval = 150
    /// Сколько раз снимок записан — для диагностики и тестов.
    private(set) var writes = 0
    /// С какой минуты снимок заморожен (обновление Claude, критик WF87 п. 2): пока выбранная копия
    /// закрыта и на экране окна ДРУГОЙ копии, снимок не пишется и Claude не переопределяется.
    private(set) var frozenSince: Date?
    /// Заморозка тает сама, как только появился Claude, запущенный после неё, — или через столько.
    static let freezeLimitSeconds: TimeInterval = 600

    init(store: WindowSnapshotStore = WindowSnapshotStore()) { self.store = store }

    /// Строка для `statusText`: фаза и сколько раз писали снимок.
    var hasPendingRestore: Bool { protected != nil || phase != .keeping || frozenSince != nil }

    var status: String { "\(phase)/\(writes)" + (frozenSince == nil ? "" : "/frozen") }

    /// Исход автовозврата для `restart-claude`: заморожен, Claude закрыт, ждём или возвращаем — ещё впереди.
    var outcome: SnapshotOutcome {
        guard frozenSince == nil, phase == .keeping else { return .pending }
        guard let lost = gaveUp else { return .notNeeded }
        return .gaveUp(skipped: lost.windows.filter { $0.chat != LayoutsStore.mainChat }.map { $0.title })
    }

    /// Заморозить снимок перед закрытием Claude на обновлении (сперва `saveNow`). Тает сама: новый
    /// Claude (запущен позже заморозки) дальше идёт обычным путём — появление, возврат окон.
    func freeze(at: Date = Date()) { frozenSince = at }

    /// Обновление сорвалось до закрытия Claude — снимок ведётся дальше как был.
    func thaw() { frozenSince = nil }

    func tick(at: Date = Date()) {
        if let since = frozenSince {
            let fresh = claude()?.launch.map { $0 > since } ?? false
            guard fresh || at.timeIntervalSince(since) >= WindowSnapshotKeeper.freezeLimitSeconds else { return }
            frozenSince = nil
        }
        guard let current = claude() else {
            // Claude закрыт: снимок не трогаем — он и есть «как было».
            pid = nil
            phase = .idle
            return
        }
        if current.pid != pid { appeared(current.pid, launch: current.launch, at: at) }
        switch phase {
        case .idle, .keeping: keep(version: current.version, at: at)
        case .waiting: wait(at: at)
        case .restoring:
            if !isRestoring() { finishRestore() }
        }
    }

    /// Ручной «↩️ Вернуть окна» (пункт вешает меню): снимок до запуска этого Claude, а нет
    /// его — последний записанный. false — вернуть нечего или канал занят.
    var prepareOtherRestore: ([SnapshotWindow]) -> Bool = { _ in true }

    @discardableResult
    func restoreNow() -> Bool {
        guard !busy(), phase != .restoring, phase != .idle,
              let snapshot = launchSnapshot ?? store.load(), !snapshot.windows.isEmpty,
              protect(snapshot, resetExpected: true), prepareOtherRestore(snapshot.windows), startRestore(snapshot) else { return false }
        protected = snapshot.windows
        settleArmed = false
        protectedSince = nil
        lastSample = nil
        phase = .restoring
        return true
    }

    /// Снять окна прямо сейчас (перед закрытием Claude на обновлении). Пока идёт или ждёт
    /// возврат, не пишем — там на экране ещё не «как было».
    @discardableResult
    func saveNow(at: Date = Date()) -> Bool {
        guard phase == .keeping, protected == nil, !busy(), let current = claude(), minimized() == 0 else { return false }
        let sample = observe()
        guard sample.complete, !sample.windows.isEmpty else { return false }
        return write(sample.windows, version: current.version, at: at)
    }

    /// Named restore keeps the original baseline; an empty expected list means a fresh
    /// layout's new chat identities are not known yet and must never clear automatically.
    @discardableResult
    func prepareNamedRestore(expected: [SnapshotWindow]) -> Bool {
        let sample = observe()
        guard sample.complete, !sample.windows.isEmpty, let current = claude() else { return false }
        let original = store.load() ?? WindowSnapshot(at: Date(), claude: current.version, windows: sample.windows)
        let pending = WindowSnapshot(at: original.at, claude: original.claude, windows: original.windows,
                                     restorePending: true, restoreExpected: expected)
        guard store.save(pending) else { return false }
        protected = expected
        // Именованный возврат идёт каналом (он «занят»): срок пойдёт с первого замера после него.
        settleArmed = true
        protectedSince = nil
        lastSample = nil
        return true
    }

    // MARK: - фазы

    private func appeared(_ newPID: pid_t, launch: Date?, at: Date) {
        pid = newPID
        self.launch = launch
        lastSample = nil
        written = nil
        sampledAt = nil
        windowsSeenAt = nil
        demandedAt = nil
        gaveUp = nil
        let stored = store.load()
        // Снимок до запуска этого Claude держим для ручного пункта, даже если автовозврата нет.
        launchSnapshot = stored.flatMap { snapshot in
            launch.map { $0 > snapshot.at } == true ? snapshot : nil
        }
        protected = stored?.restorePending == true ? (stored?.restoreExpected ?? stored?.windows) : launchSnapshot?.windows
        settleArmed = false
        inheritedPending = stored?.restorePending == true
        protectedSince = nil
        if let snapshot = stored, WindowSnapshotStore.shouldRestore(snapshot, launch: launch, seenAt: at) {
            phase = .waiting
            waitingSince = at
        } else {
            phase = .keeping
        }
    }

    private func wait(at: Date) {
        guard let snapshot = launchSnapshot, let since = waitingSince,
              at.timeIntervalSince(since) <= WindowSnapshotKeeper.giveUpSeconds else {
            // Брошен: окна у Claude так и не появились. Снимок остаётся ручному пункту.
            gaveUp = launchSnapshot
            phase = .keeping
            return
        }
        if demandedAt.map({ at.timeIntervalSince($0) >= WindowSnapshotKeeper.demandSeconds }) ?? true {
            demandedAt = at
            demandPages()
        }
        guard !observe().windows.isEmpty else {
            windowsSeenAt = nil
            return
        }
        let seen = windowsSeenAt ?? at
        windowsSeenAt = seen
        guard pageReady(launch)
            || at.timeIntervalSince(seen) >= WindowSnapshotKeeper.pageFallbackSeconds else { return }
        if protect(snapshot), startRestore(snapshot) { phase = .restoring }
    }

    private func protect(_ snapshot: WindowSnapshot, resetExpected: Bool = false) -> Bool {
        let stored = store.load()
        let original = stored?.restorePending == true ? stored! : snapshot
        let expected = !resetExpected && original.restorePending
            ? original.restoreExpected : (original.windows == snapshot.windows ? nil : snapshot.windows)
        let pending = WindowSnapshot(at: original.at, claude: original.claude, windows: original.windows,
                                     restorePending: true, restoreExpected: expected)
        if stored != pending, !store.save(pending) { return false }
        protected = expected ?? snapshot.windows
        return true
    }

    private func finishRestore() {
        phase = .keeping
        lastSample = nil
        sampledAt = nil
        settleArmed = true
        protectedSince = nil
    }

    private func keep(version: String, at: Date) {
        phase = .keeping
        // Reset even between sample deadlines: no sample may bridge a busy/incomplete interval.
        guard !busy(), minimized() == 0 else { lastSample = nil; return }
        let sample = observe()
        guard sample.complete else { lastSample = nil; return }
        if let expected = protected {
            if settleArmed {
                let live = Set(sample.windows.map { $0.chat })
                protected = expected.filter { live.contains($0.chat) }
                protectedSince = at
            } else if inheritedPending, protectedSince == nil {
                protectedSince = at
            }
            settleArmed = false
        }
        if let last = sampledAt, at.timeIntervalSince(last) < Self.sampleSeconds { return }
        sampledAt = at
        let list = sample.windows
        let previous = lastSample
        lastSample = list
        guard !list.isEmpty, list == previous else { return }
        if let expected = protected {
            let expired = protectedSince.map { at.timeIntervalSince($0) >= Self.releaseSeconds } ?? false
            guard expired || (!expected.isEmpty && RestoreFrame.restored(expected, in: list, adapt: adaptFrame)) else { return }
        }
        guard written == nil || list != written || protected != nil else { return }
        if write(list, version: version, at: at) { protected = nil; gaveUp = nil; inheritedPending = false }
    }

    @discardableResult
    private func write(_ list: [SnapshotWindow], version: String, at: Date) -> Bool {
        guard store.save(WindowSnapshot(at: at, claude: version, windows: list)) else { return false }
        written = list
        writes += 1
        return true
    }
}
