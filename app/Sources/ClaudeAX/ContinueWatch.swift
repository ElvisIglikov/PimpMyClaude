import AppKit
import ApplicationServices

/// Кнопка «💬 Новый чат» в самом чате (#7246; контракт — `docs/CONTRACTS.md`,
/// раздел WF84). Страница по клику ставит в `document.title` своего окна метку
/// `Пимп: продолжить в новом чате · <метка>` (метка — `Date.now()` в base36, новая на каждый
/// клик) и держит её 1,2 с. Приложение читает заголовки окон Claude раз в 0,25 с: увидело
/// новую метку — запоминает ОКНО, ждёт, пока метка уйдёт (прочитай `handoffNewChat` заголовок
/// раньше — он взял бы метку вместо имени чата и не узнал бы окно), и зовёт тот же путь, что
/// пункт меню ⌘B «💬 Новый чат». Ответ странице — сама команда `cashout`.
///
/// Канал — заголовок окна (так же ходил снятый в WF101 замок К6; от него остались константы
/// `PimpLock`): спайк S0 показал, что смена `document.title` видна в AX за 3–13 мс, а probe.js
/// на гейте занят агентом.
final class ContinueWatch {
    /// Начало метки — побайтно как `CONTINUE_TITLE_PREFIX` страницы (`inject.js`, раздел 12к).
    static let labelPrefix = "Пимп: продолжить в новом чате"
    static let pollInterval: TimeInterval = 0.25

    /// Окна Claude с заголовками. Живьём вешает `ClaudeAXController`.
    var windows: () -> [(window: AXUIElement, title: String)] = { [] }
    /// Окно, где нажали кнопку, — туда «💬 Новый чат».
    var onContinue: ((AXUIElement) -> Void)?

    private var machine = ContinueWatchMachine()
    private var armed: AXUIElement?
    private var timer: Timer?

    /// Заголовки страниц внутри окна (главное окно, гейт 26.09) — их читает `windows` контроллера.
    let pages = ContinueWebAreas()

    /// Сколько раз кнопка сработала — поле `cont=` строки диагностики.
    private(set) var fires = 0

    func start() {
        stop()
        let timer = Timer(timeInterval: ContinueWatch.pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        armed = nil
        machine = ContinueWatchMachine()
    }

    private func poll() {
        let list = windows()
        switch machine.step(titles: list.map { $0.title }, now: Date.timeIntervalSinceReferenceDate) {
        case .none: return
        case .arm(let index): armed = list[index].window
        case .fire:
            guard let window = armed else { return }
            armed = nil
            fires += 1
            onContinue?(window)
        }
    }
}

/// Решение кнопки — чистое, без окон и таймера: его гоняют тесты (`ContinueWF84Tests`).
struct ContinueWatchMachine: Equatable {
    enum Action: Equatable {
        case none
        /// Новая метка в окне с этим номером списка — запомнить окно.
        case arm(Int)
        /// Метка ушла (или ждали дольше `maxWait`) — звать «💬 Новый чат».
        case fire
    }

    /// Дольше этого метку не ждём: страница держит её 1,2 с, но могла и не снять
    /// (перезагрузка посреди срока) — клик Элвиса всё равно исполняем.
    static let maxWait: TimeInterval = 2.5
    /// Сколько последних меток помним, чтобы не исполнить клик дважды.
    static let memory = 16

    private(set) var armedNonce: String?
    private(set) var armedAt: TimeInterval = 0
    private(set) var handled: [String] = []

    /// Метка из заголовка: всё после «<префикс> · »; не метка — nil.
    static func nonce(of title: String) -> String? {
        let line = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix(ContinueWatch.labelPrefix) else { return nil }
        var rest = line.dropFirst(ContinueWatch.labelPrefix.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("·") else { return nil }
        rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// Один опрос: заголовки всех окон Claude по порядку списка.
    mutating func step(titles: [String], now: TimeInterval) -> Action {
        if let nonce = armedNonce {
            let still = titles.contains { ContinueWatchMachine.nonce(of: $0) == nonce }
            guard !still || now - armedAt >= ContinueWatchMachine.maxWait else { return .none }
            armedNonce = nil
            remember(nonce)
            return .fire
        }
        for (index, title) in titles.enumerated() {
            guard let nonce = ContinueWatchMachine.nonce(of: title), !handled.contains(nonce) else { continue }
            armedNonce = nonce
            armedAt = now
            return .arm(index)
        }
        return .none
    }

    private mutating func remember(_ nonce: String) {
        handled.append(nonce)
        if handled.count > ContinueWatchMachine.memory { handled.removeFirst(handled.count - ContinueWatchMachine.memory) }
    }
}

/// Заголовки страниц ВНУТРИ окна (живой гейт 26.09, «нажимаю „Открыть новый чат“ — ничего»).
/// Главное окно Claude — рамка `file://…/main_window`, а чат в нём — вложенная страница
/// claude.ai (WebContentsView). Её `document.title` в заголовок окна не попадает: Claude
/// переносит заголовок страницы в окно только у попапов, и главное окно всегда зовётся
/// «Claude». Метка кнопки из главного окна до `ContinueWatch` не доходила вовсе (страница
/// ставила её 4 раза, `cashout` не пришёл ни разу). Зато Chromium отдаёт в AX корень каждой
/// страницы — `AXWebArea` с заголовком документа, и видно его даже без `AXManualAccessibility`
/// (в главном окне две такие: рамка с пустым заголовком и claude.ai с «Claude»).
///
/// Корни страниц окна ищутся обходом (дерево без контента — полтора десятка узлов) и
/// помнятся `refresh` секунд; дальше — одно чтение заголовка на страницу за опрос.
final class ContinueWebAreas {
    static let role = "AXWebArea"
    /// Глубже корня страницы в главном окне (живьём — 8) не ищем; внутрь страницы не спускаемся:
    /// с включённым AX там весь чат.
    static let maxDepth = 12
    static let maxNodes = 64
    /// Как часто искать корни заново: страница перезагрузилась — её старый корень мёртв.
    static let refresh: TimeInterval = 5

    private var known: [(window: AXUIElement, areas: [AXUIElement], at: TimeInterval)] = []

    /// Заголовки окна для `ContinueWatchMachine`: заголовок самого окна и заголовки его
    /// страниц. Окна, которых в этом опросе нет, забываются.
    func titles(of windows: [(window: AXUIElement, title: String)],
                now: TimeInterval) -> [(window: AXUIElement, title: String)] {
        known.removeAll { entry in !windows.contains { CFEqual($0.window, entry.window) } }
        return windows.flatMap { item -> [(window: AXUIElement, title: String)] in
            let pages = areas(of: item.window, now: now).compactMap { area -> String? in
                AX.timeout(area, PimpLock.titleTimeout)
                return AX.string(area, kAXTitleAttribute)
            }
            return ContinueWebAreas.titles(window: item.title, pages: pages).map { (window: item.window, title: $0) }
        }
    }

    private func areas(of window: AXUIElement, now: TimeInterval) -> [AXUIElement] {
        if let index = known.firstIndex(where: { CFEqual($0.window, window) }) {
            if now - known[index].at < ContinueWebAreas.refresh { return known[index].areas }
            known.remove(at: index)
        }
        let found = ContinueWebAreas.find(root: window, children: { node in
            AX.timeout(node, PimpLock.titleTimeout)
            return AX.elements(node, kAXChildrenAttribute)
        }, isWebArea: { AX.string($0, kAXRoleAttribute) == ContinueWebAreas.role })
        known.append((window: window, areas: found, at: now))
        return found
    }

    /// Корни страниц под `root` обходом в ширину; в найденную страницу не спускаемся.
    static func find<Node>(root: Node, children: (Node) -> [Node], isWebArea: (Node) -> Bool) -> [Node] {
        var found: [Node] = []
        var level = children(root)
        var seen = 0
        var depth = 1
        while !level.isEmpty, depth <= maxDepth, seen < maxNodes {
            var next: [Node] = []
            for node in level {
                seen += 1
                if seen > maxNodes { break }
                if isWebArea(node) { found.append(node) } else { next += children(node) }
            }
            level = next
            depth += 1
        }
        return found
    }

    /// Заголовок окна первым, за ним непустые заголовки страниц, которых нет в окне: у попапа
    /// страница и окно зовутся одинаково — лишней строки не будет.
    static func titles(window: String, pages: [String]) -> [String] {
        var out = [window]
        for page in pages where !page.isEmpty && !out.contains(page) { out.append(page) }
        return out
    }
}
