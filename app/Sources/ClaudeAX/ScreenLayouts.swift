import CoreGraphics
import Foundation

/// Монитор в ключе набора экранов (#7740, WF94): имя и полная рамка в перевёрнутых координатах.
struct ScreenSpec: Equatable {
    let name: String
    let frame: CGRect
}

/// Последняя расстановка окон на одном наборе мониторов: окна Claude (по чату, главное —
/// `main`) и ChatGPT.
struct ScreenLayout: Equatable {
    let key: String
    let at: Date
    let windows: [SnapshotWindow]
    let chatGPT: CGRect?
    let restorePending: Bool
    let restoreExpected: [SnapshotWindow]?

    init(key: String, at: Date, windows: [SnapshotWindow], chatGPT: CGRect?, restorePending: Bool = false, restoreExpected: [SnapshotWindow]? = nil) {
        self.key = key; self.at = at; self.windows = windows; self.chatGPT = chatGPT
        self.restorePending = restorePending
        self.restoreExpected = restoreExpected
    }
}

/// Файл `~/Library/Application Support/MyClaude/windows-by-screens.json` (#7740, WF94) —
/// файл приложения, лоадер его не знает:
/// `{"version":1,"layouts":[{"key","at","windows":[{"chat","folder","title","frame","screen"}],"chatgpt":[x,y,w,h]|null}]}`.
/// Набор — строкой `ScreenLayouts.key`; свежие первыми, не больше `limit`.
final class ScreenLayoutStore {
    static let fileName = "windows-by-screens.json"
    static let version = 1
    /// Наборов мониторов больше не бывает; вытесняются самые старые.
    static let limit = 20
    static var defaultURL: URL { CommandChannel.directory.appendingPathComponent(fileName) }

    private let url: URL

    init(url: URL = ScreenLayoutStore.defaultURL) { self.url = url }

    func load() -> [ScreenLayout] { ScreenLayoutStore.parse(try? Data(contentsOf: url)) }

    @discardableResult
    func save(_ layouts: [ScreenLayout]) -> Bool {
        CommandChannel.writeAtomic(url, ScreenLayoutStore.json(layouts))
    }

    // MARK: - чистая часть

    /// Запись по тому же набору заменяется, новая встаёт первой, хвост сверх `limit` уходит.
    static func merge(_ layout: ScreenLayout, into list: [ScreenLayout]) -> [ScreenLayout] {
        Array(([layout] + list.filter { $0.key != layout.key }).prefix(limit))
    }

    static func json(_ layouts: [ScreenLayout]) -> String {
        CommandValue.object([
            (key: "version", value: .number(version)),
            (key: "layouts", value: .array(layouts.map { layout in
                .object([
                    (key: "key", value: .string(layout.key)),
                    (key: "at", value: .string(PimpChannel.stampText(layout.at))),
                    (key: "windows", value: .array(layout.windows.map { window in
                        .object([
                            (key: "chat", value: .string(window.chat)),
                            (key: "folder", value: .string(window.folder)),
                            (key: "title", value: .string(window.title)),
                            (key: "frame", value: PimpChannel.frameValue(window.frame)),
                            (key: "screen", value: .string(window.screen)),
                        ])
                    })),
                    (key: "chatgpt", value: layout.chatGPT.map { PimpChannel.frameValue($0) } ?? .null),
                ] + (layout.restorePending ? [(key: "restorePending", value: .bool(true))] : [])
                  + (layout.restoreExpected.map { [(key: "restoreExpected", value: WindowSnapshotStore.windowValues($0))] } ?? []))
            })),
        ]).json + "\n"
    }

    /// Битый файл или чужая версия — наборов нет; кривая запись пропускается.
    static func parse(_ data: Data?) -> [ScreenLayout] {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["version"] as? NSNumber)?.intValue == version,
              let items = root["layouts"] as? [[String: Any]] else { return [] }
        return items.compactMap { item -> ScreenLayout? in
            guard let key = item["key"] as? String, !key.isEmpty,
                  let at = (item["at"] as? String).flatMap(PimpChannel.date) else { return nil }
            // Окна — тем же разбором, что у снимка К5: формат записи у них общий.
            return ScreenLayout(key: key, at: at, windows: WindowSnapshotStore.windows(from: item["windows"]),
                                chatGPT: frame(item["chatgpt"]), restorePending: item["restorePending"] as? Bool ?? false,
                                restoreExpected: item["restoreExpected"].map { WindowSnapshotStore.windows(from: $0) })
        }
    }

    private static func frame(_ value: Any?) -> CGRect? {
        guard let numbers = value as? [NSNumber], numbers.count == 4 else { return nil }
        let rect = CGRect(x: numbers[0].doubleValue, y: numbers[1].doubleValue,
                          width: numbers[2].doubleValue, height: numbers[3].doubleValue)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }
}

/// Окна при смене мониторов (#7740, WF94): на каждый набор экранов — последняя расстановка
/// окон Claude и ChatGPT; набор сменился на знакомый — окна встают как стояли на нём.
///
/// Правила (план WF94, пункт 5):
/// (а) выборка раз в `sampleSeconds`, ключ — в момент выборки; пишем, только если две выборки
///     подряд с одним ключом совпали и после последнего уведомления о смене экранов прошло
///     `settleSeconds`; пока идёт или ждёт возврат — не пишем; окно, чей центр вне экранов
///     ключа, не пишем;
/// (б) возврат — только при переходе ключ X → известный Y (X ≠ Y), после `quietSeconds`
///     тишины уведомлений, и повтор через `retrySeconds`; уведомление без смены ключа (док,
///     меню-бар) — ничего; «A → A» после сна или мигания мониторов (#7975, WF120) — один возврат
///     тем же путём, если живые рамки разошлись с записью;
/// (в) не начинаем, пока занят канал «Пимп» или идёт возврат К5 (`busy`);
/// (г) закрытые чаты НЕ открываем — двигаем только живые окна.
///
/// Всё живое приходит сиденьями — тесты гоняют это без AX и без мониторов.
final class ScreenLayoutKeeper {
    /// Мониторы сейчас.
    var screens: () -> [ScreenSpec] = { [] }
    /// Окна Claude на экране — уже окнами снимка (чат или `main`).
    var windows: () -> [SnapshotWindow] = { [] }
    var observation: (() -> SnapshotObservation)?
    var adaptFrame: (CGRect) -> CGRect = { $0 }
    var adaptChatGPTFrame: (CGRect) -> CGRect = { $0 }
    private func observe() -> SnapshotObservation {
        observation?() ?? SnapshotObservation(windows: windows(), complete: true)
    }
    /// Окна Claude для возврата: номер, заголовок, чат, рамка.
    var live: () -> [PimpWindow] = { [] }
    var isMain: (String) -> Bool = { _ in false }
    /// Рамка переднего окна ChatGPT; nil — его нет.
    var chatGPT: () -> CGRect? = { nil }
    /// Занят канал «Пимп» (работа или прогрев нового окна) или идёт возврат К5.
    var busy: () -> Bool = { false }
    /// Поставить окна Claude по рамкам и ChatGPT (nil — не трогать).
    var apply: ([PimpMove], CGRect?) -> Void = { _, _ in }
    /// Сколько окон Claude свёрнуто (WF112, #8255): пока они есть, запись набора не пишется —
    /// иначе раскладка этих мониторов затёрлась бы одним главным окном.
    var minimized: () -> Int = { 0 }

    /// Automatic wake requires both existing passive input monitors. Manual restore is separate.
    var wakeInputReady: () -> Bool = { false }
    var processID: () -> pid_t? = { nil }
    private struct WakeContext: Equatable {
        let pid: pid_t
        let windows: [CGWindowID: String]
    }
    private var wakeContext: WakeContext?
    private var lastWakeContext: WakeContext?
    private var sleepContext: WakeContext?
    private var wakeSeen = false
    var wantsWakeProbe: Bool { wakeContext != nil && (pendingFrom != nil || retry != nil) }

    private func currentWakeContext() -> WakeContext? {
        guard wakeInputReady(), let pid = processID(), observe().complete, minimized() == 0 else { return nil }
        let list = live()
        var identities: [CGWindowID: String] = [:]
        for window in list {
            let chat = window.isMain(using: isMain) ? LayoutsStore.mainChat : window.chat
            guard window.id > 0, !chat.isEmpty, identities[window.id] == nil,
                  !identities.values.contains(chat) else { return nil }
            identities[window.id] = chat
        }
        return identities.isEmpty ? nil : WakeContext(pid: pid, windows: identities)
    }

    func noteSleep() {
        let context = baselineWakeContext()
        cancelWake()
        // A manual move may not have reached the stable disk sample yet. Never undo it
        // using an older saved layout just because the native IDs still match.
        wakeSeen = context == nil
        sleepContext = context
    }

    private func baselineWakeContext() -> WakeContext? {
        guard !busy(), let key = currentKey, let layout = layout(for: key),
              let context = currentWakeContext(), !diverged(from: layout) else { return nil }
        return context
    }

    /// Input/monitor loss invalidates the entire episode, including the delayed retry and
    /// a later paired screensDidWake. Only a subsequent sleep starts another episode.
    func cancelWake() {
        lastWakeContext = nil
        guard wakeContext != nil || sleepContext != nil
            || pendingFrom != nil || retry != nil else { return }
        wakeSeen = true
        wakeContext = nil
        sleepContext = nil
        pendingFrom = nil
        pendingSince = nil
        retry = nil
        lastSample = nil
    }

    private func wakeIsSafe(_ layout: ScreenLayout) -> Bool {
        guard let context = wakeContext, context == currentWakeContext() else { return false }
        let names = layout.windows.map { $0.chat }
        return Set(names).count == names.count && Set(names) == Set(context.windows.values)
    }

    static let sampleSeconds: TimeInterval = 10
    static let settleSeconds: TimeInterval = 20
    static let quietSeconds: TimeInterval = 2
    static let retrySeconds: TimeInterval = 5
    /// Канал занят дольше — возврат бросаем: окна уже живут своей жизнью.
    static let busyGiveUpSeconds: TimeInterval = 60

    private let store: ScreenLayoutStore
    private var layouts: [ScreenLayout]
    /// Набор, в котором мы считаем экраны сейчас.
    private var currentKey: String?
    /// Последнее уведомление о смене экранов (или замеченная сменой ключа).
    private var noticeAt: Date?
    /// Набор ДО смены, пока смена не улеглась; nil — смены нет.
    private var pendingFrom: String?
    private var pendingSince: Date?
    /// Повтор возврата: когда и для какого набора.
    private var retry: (at: Date, key: String)?
    /// Запись набора, на который пришли сменой, — какой она была ДО смены (проверка гейта
    /// WF94): автовозврат сорвался (канал занят дольше минуты, окна не опознаны), а через
    /// 20 с выборка переписала запись сбитой раскладкой — ручному «верни окна» остаётся она.
    /// Живёт до следующей смены набора и `arrivedSeconds` после этой.
    private var arrived: (layout: ScreenLayout, at: Date)?
    static let arrivedSeconds: TimeInterval = 30 * 60
    private var sampledAt: Date?
    private var lastSample: (key: String, windows: [SnapshotWindow], chatGPT: CGRect?)?
    private(set) var writes = 0
    private(set) var restores = 0
    /// Защита записи после возврата не вечная (находка судьи WF111): после расстановки первый
    /// полный замер вне работы канала запоминает живые чаты (закрытый чат или ChatGPT из записи
    /// больше не ждём) и заводит срок `releaseSeconds`; вышел — пишется следующий полный
    /// стабильный замер. Защита, доставшаяся с диска от прошлого запуска, — только срок.
    private struct Settle {
        var prune: Bool
        var since: Date?
        var live: Set<String>?
        var chatGPTMissing = false
    }
    private var settles: [String: Settle] = [:]
    static let releaseSeconds: TimeInterval = 150

    init(store: ScreenLayoutStore = ScreenLayoutStore()) {
        self.store = store
        layouts = store.load()
        for layout in layouts where layout.restorePending { settles[layout.key] = Settle(prune: false) }
    }

    /// Строка для `statusText`: `<наборов>/<записей>/<возвратов>`.
    var hasPendingRestore: Bool { currentKey == nil || pendingFrom != nil || retry != nil || currentKey.flatMap { layout(for: $0) }?.restorePending == true }

    var status: String { "\(layouts.count)/\(writes)/\(restores)" }

    /// Ключ набора: для каждого экрана имя, размер и начало; экраны по порядку ключей, так что
    /// порядок `NSScreen.screens` его не меняет, а перестановка мониторов — меняет.
    static func key(_ screens: [ScreenSpec]) -> String {
        screens.map { screen in
            let f = screen.frame
            return "\(screen.name)@\(Int(f.minX.rounded())),\(Int(f.minY.rounded()))"
                + ",\(Int(f.width.rounded()))x\(Int(f.height.rounded()))"
        }.sorted().joined(separator: " | ")
    }

    /// Пришло `didChangeScreenParameters`.
    func noteScreensChanged(at: Date = Date()) {
        noticeAt = at
    }

    /// Пришло `didWake` или `screensDidWake` (#7975, WF120): набор мониторов мог остаться прежним,
    /// а macOS за сон — сжать окна. Это смена «A → A»: выборка не пишет сжатую раскладку
    /// (`pendingFrom`), а `settle` после тишины один раз вернёт окна, если они разошлись с записью.
    func noteWake(at: Date = Date()) {
        guard !wakeSeen else {
            if wakeContext != nil { noticeAt = at }
            return
        }
        wakeSeen = true
        guard let current = currentKey, let context = sleepContext ?? lastWakeContext,
              wakeInputReady(), context.pid == processID() else { cancelWake(); return }
        wakeContext = context
        sleepContext = nil
        noticeAt = at
        if pendingFrom == nil { pendingSince = at }
        pendingFrom = pendingFrom ?? current
        lastSample = nil
    }

    func tick(at: Date = Date()) {
        let specs = screens()
        guard !specs.isEmpty else { return }
        let key = ScreenLayoutKeeper.key(specs)
        guard let current = currentKey else {
            // Первый взгляд: с чего начали, то и «было» — на запуске ничего не возвращаем.
            currentKey = key
            lastWakeContext = baselineWakeContext()
            return
        }
        if let wake = wakeContext {
            if !wakeInputReady() || wake.pid != processID() { cancelWake() }
            else if let current = currentWakeContext(), current != wake { cancelWake() }
        }
        if key != current {
            if pendingFrom == nil {
                pendingFrom = current
                pendingSince = at
            }
            currentKey = key
            retry = nil
            arrived = layout(for: key).map { (layout: $0, at: at) }
            if let layout = arrived?.layout { _ = protect(layout) }
            lastSample = nil
            // Смену увидели раньше уведомления — считаем её уведомлением (гонка).
            noticeAt = max(noticeAt ?? at, at)
        }
        let quiet = noticeAt.map { at.timeIntervalSince($0) >= ScreenLayoutKeeper.quietSeconds } ?? true
        if let from = pendingFrom, quiet { settle(from: from, key: key, at: at) }
        if let planned = retry, at >= planned.at, quiet {
            retry = nil
            if planned.key == key, !busy(), let layout = layout(for: key) {
                if wakeContext == nil || wakeIsSafe(layout) { _ = place(layout) }
                else { cancelWake() }
            }
            wakeContext = nil
        }
        sample(key: key, screens: specs, at: at)
        if pendingFrom == nil, retry == nil {
            lastWakeContext = baselineWakeContext()
        }
    }

    /// «Верни окна как были» руками (`screens-restore`): набор сейчас; nil — его не видели.
    var prepareOtherRestore: ([SnapshotWindow]) -> Bool = { _ in true }
    var onRestorePlaced: () -> Void = {}

    func restoreNow(at: Date = Date()) -> (placed: Int, missing: Int)? {
        let specs = screens()
        guard !specs.isEmpty else { return nil }
        let key = ScreenLayoutKeeper.key(specs)
        let before = arrived.flatMap { $0.layout.key == key
            && at.timeIntervalSince($0.at) < ScreenLayoutKeeper.arrivedSeconds ? $0.layout : nil }
        guard !busy(), let layout = before ?? layout(for: key), protect(layout, resetExpected: true), prepareOtherRestore(layout.windows) else { return nil }
        lastSample = nil
        restores += 1
        let result = place(layout)
        if result.placed > 0 { onRestorePlaced() }
        return result
    }

    @discardableResult
    func prepareNamedRestore(expected: [SnapshotWindow], at: Date = Date()) -> Bool {
        let specs = screens(), sample = observe()
        guard !specs.isEmpty, sample.complete, !sample.windows.isEmpty else { return false }
        let key = Self.key(specs)
        let original = layout(for: key) ?? ScreenLayout(key: key, at: at, windows: sample.windows, chatGPT: chatGPT())
        let pending = ScreenLayout(key: key, at: original.at, windows: original.windows, chatGPT: original.chatGPT,
                                   restorePending: true, restoreExpected: expected)
        let next = ScreenLayoutStore.merge(pending, into: layouts)
        guard store.save(next) else { return false }
        layouts = next
        settles[key] = Settle(prune: true)
        lastSample = nil
        return true
    }

    // MARK: - шаги

    private func settle(from: String, key: String, at: Date) {
        if wakeContext != nil, let since = pendingSince, at.timeIntervalSince(since) >= Self.busyGiveUpSeconds {
            cancelWake()
            return
        }
        guard let layout = layout(for: key) else {
            // Набор новый — возвращать нечего, дальше его запишет выборка.
            pendingFrom = nil
            wakeContext = nil
            return
        }
        if from == key, wakeContext == nil {
            guard !wakeSeen, let context = lastWakeContext, context == currentWakeContext() else {
                pendingFrom = nil
                return
            }
            wakeSeen = true
            wakeContext = context
        }
        if wakeContext != nil, !wakeIsSafe(layout) {
            // Main identity expires during sleep. Keep the baseline while a fresh probe arrives;
            // incomplete or conflicting evidence never permits a move.
            lastSample = nil
            _ = protect(layout)
            if let since = pendingSince, at.timeIntervalSince(since) >= Self.busyGiveUpSeconds { cancelWake() }
            return
        }
        // «A → A» (сон, мигание мониторов, #7975): окна стоят по записи — ничего; macOS их
        // сдвинула — один возврат тем же путём, что у X → Y (защита записи, занятость, повтор).
        if from == key, !diverged(from: layout) {
            pendingFrom = nil
            wakeContext = nil
            return
        }
        // Persist the original positions before any effect or timeout. A failed write
        // leaves the pending transition in place, so a later tick may safely retry.
        guard protect(layout) else { lastSample = nil; return }
        guard !busy() else {
            lastSample = nil
            if let since = pendingSince, at.timeIntervalSince(since) >= ScreenLayoutKeeper.busyGiveUpSeconds {
                pendingFrom = nil
            }
            return
        }
        if wakeContext != nil, !wakeIsSafe(layout) { cancelWake(); return }
        let automaticWake = wakeContext != nil
        pendingFrom = nil
        restores += 1
        let result = place(layout)
        if result.placed > 0 { onRestorePlaced() }
        if !automaticWake || wakeContext != nil {
            retry = (at: at.addingTimeInterval(ScreenLayoutKeeper.retrySeconds), key: key)
        }
    }

    private func sample(key: String, screens specs: [ScreenSpec], at: Date) {
        guard !busy(), minimized() == 0 else { lastSample = nil; return }
        let sample = observe()
        guard sample.complete else { lastSample = nil; return }
        if var settle = settles[key], settle.since == nil {
            settle.since = at
            if settle.prune {
                settle.live = Set(sample.windows.map { $0.chat })
                settle.chatGPTMissing = chatGPT() == nil
            }
            settles[key] = settle
        }
        if let last = sampledAt, at.timeIntervalSince(last) < Self.sampleSeconds { return }
        sampledAt = at
        let inside: (CGRect) -> Bool = { frame in
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return specs.contains { $0.frame.contains(center) }
        }
        // Off-screen geometry is incomplete until restoration brings it into a real display.
        guard sample.windows.allSatisfy({ inside($0.frame) }) else { lastSample = nil; return }
        let list = sample.windows
        let gpt = chatGPT().flatMap { inside($0) ? $0 : nil }
        let previous = lastSample
        lastSample = (key: key, windows: list, chatGPT: gpt)
        guard pendingFrom == nil, retry == nil, !list.isEmpty,
              noticeAt.map({ at.timeIntervalSince($0) >= Self.settleSeconds }) ?? true,
              let before = previous, before.key == key, before.windows == list, before.chatGPT == gpt
        else { return }
        if let known = layout(for: key) {
            if known.restorePending {
                let settle = settles[key]
                let expired = settle?.since.map { at.timeIntervalSince($0) >= Self.releaseSeconds } ?? false
                if !expired {
                    let expected = (known.restoreExpected ?? known.windows).filter { settle?.live?.contains($0.chat) ?? true }
                    guard !expected.isEmpty, RestoreFrame.restored(expected, in: list, adapt: adaptFrame) else { return }
                    if known.restoreExpected == nil, settle?.chatGPTMissing != true, let expected = known.chatGPT {
                        guard let actual = gpt, ClaudeActions.frameMatches(actual, adaptChatGPTFrame(expected)) else { return }
                    }
                }
            } else if known.windows == list, known.chatGPT == gpt { return }
        }
        let next = ScreenLayoutStore.merge(ScreenLayout(key: key, at: at, windows: list, chatGPT: gpt), into: layouts)
        guard store.save(next) else { return }
        layouts = next
        settles[key] = nil
        arrived = nil
        writes += 1
    }

    /// Mark the original full record before applying any restore effects. No separate
    /// journal is needed: the windows and pending flag are one atomic JSON replacement.
    private func protect(_ layout: ScreenLayout, resetExpected: Bool = false) -> Bool {
        if !resetExpected, self.layout(for: layout.key)?.restorePending == true { return true }
        let current = self.layout(for: layout.key)
        let original = current?.restorePending == true ? current! : layout
        let expected = original.windows == layout.windows ? nil : layout.windows
        let guarded = ScreenLayout(key: layout.key, at: original.at, windows: original.windows,
                                   chatGPT: original.chatGPT, restorePending: true, restoreExpected: expected)
        let next = ScreenLayoutStore.merge(guarded, into: layouts)
        guard store.save(next) else { return false }
        layouts = next
        // Срок защиты пойдёт от расстановки (`place`), не раньше.
        settles[layout.key] = nil
        return true
    }

    private func layout(for key: String) -> ScreenLayout? { layouts.first { $0.key == key } }

    /// Живые окна Claude или ChatGPT стоят не по записи — возврату есть что двигать.
    private func diverged(from layout: ScreenLayout) -> Bool {
        let plan = ScreenLayoutKeeper.moves(for: layout, live: live(), isMain: isMain, chatGPT: chatGPT(),
                                            adaptFrame: adaptFrame, adaptChatGPTFrame: adaptChatGPTFrame)
        return !plan.moves.isEmpty || plan.chatGPT != nil
    }

    /// Поставить живые окна по записи: сколько встало (и стоявших на месте) и сколько не
    /// нашлось. Закрытые чаты не открываем (правило (г)).
    @discardableResult
    private func place(_ layout: ScreenLayout) -> (placed: Int, missing: Int) {
        let plan = ScreenLayoutKeeper.moves(for: layout, live: live(), isMain: isMain,
                                            chatGPT: chatGPT(), adaptFrame: adaptFrame, adaptChatGPTFrame: adaptChatGPTFrame)
        apply(plan.moves, plan.chatGPT)
        settles[layout.key] = Settle(prune: true)
        return (placed: plan.placed, missing: plan.missing)
    }

    /// Чистая часть возврата: какие окна куда. Главное окно — по заголовку (`isMain`), прочие —
    /// по чату; окно берётся одно на запись. Стоящее на месте (2 pt) не двигаем, но считаем.
    static func moves(for layout: ScreenLayout, live: [PimpWindow], isMain: (String) -> Bool,
                      chatGPT: CGRect?, adaptFrame: (CGRect) -> CGRect = { $0 },
                      adaptChatGPTFrame: (CGRect) -> CGRect = { $0 })
        -> (moves: [PimpMove], chatGPT: CGRect?, placed: Int, missing: Int) {
        var moves: [PimpMove] = []
        var used = Set<CGWindowID>()
        var placed = 0, missing = 0
        for record in layout.windows {
            let found = live.filter { window in
                guard !used.contains(window.id) else { return false }
                return record.chat == LayoutsStore.mainChat ? window.isMain(using: isMain) : window.chat == record.chat
            }
            guard found.count == 1, let window = found.first else {
                missing += 1
                continue
            }
            used.insert(window.id)
            placed += 1
            let target = adaptFrame(record.frame)
            if !ClaudeActions.frameMatches(window.frame, target) {
                moves.append(PimpMove(id: window.id, frame: target))
            }
        }
        var gpt: CGRect?
        if let frame = layout.chatGPT {
            let wanted = adaptChatGPTFrame(frame)
            if let now = chatGPT {
                placed += 1
                if !ClaudeActions.frameMatches(now, wanted) { gpt = wanted }
            } else {
                missing += 1
            }
        }
        return (moves: moves, chatGPT: gpt, placed: placed, missing: missing)
    }
}
