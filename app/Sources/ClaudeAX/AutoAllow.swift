import ApplicationServices
import Foundation

/// Порт `claude_autoallow.lua`: раз в 1.5 с обходит AX-дерево окон Claude, находит кнопку
/// «Allow…» и жмёт её (AXPress). Не event tap — обычный таймер, ввод не тормозит.
/// Диалог обязан быть виден на экране: свёрнутое окно AX не отдаёт.
final class AutoAllow {
    struct Press {
        let at: String
        let heading: String
        let button: String
        let ok: Bool
    }

    var enabled = true
    /// Секунды между обходами. Реже, чем в Lua, не делаем; чаще — нельзя (правило задачи).
    let interval: TimeInterval = 1.5
    /// Обход дольше этого времени обрывается — главный поток не должен стоять.
    let maxScanSeconds: TimeInterval = 0.4
    /// Тексты кнопок, которые жмём (в Lua — паттерны ^Allow once, ^Allow$, ^Allow for this,
    /// ^Allow always, ^Yes, allow).
    var buttonPatterns: [TextPattern] = [
        .prefix("Allow once"), .exact("Allow"), .prefix("Allow for this"),
        .prefix("Allow always"), .prefix("Yes, allow"),
    ]
    /// Что НИКОГДА не подтверждаем: удаление и необратимое, деньги, внешние сервисы (слово
    /// Элвиса по странице ревизии, вариант A вопроса 7 — #5736). Список короткий и живёт в
    /// коде: настроек и панелей у него нет.
    ///
    /// Сравнение — с НАЧАЛОМ команды, которую диалог подтверждает (`action(of:)` + `isBlocked`),
    /// а не с любым местом заголовка. До #5779 слово ловилось где угодно, и «Claude wants to
    /// read refunds.md» глушил авто-Allow на ровном месте: у VkusnoffKz оплаты, счета и
    /// возвраты — это имена файлов в каждом втором вопросе. Теперь ловятся команды (`rm -rf …`,
    /// `delete from …`) и имена инструментов (`payment_create`), а хвосты путей — нет.
    /// «force push» из списка ушёл: команда всегда начинается с `git push`.
    /// Заголовок диалога не опознан (`heading` вернул пустую строку) — жмём, как раньше:
    /// иначе авто-Allow замолчал бы на любой незнакомой разметке.
    var blockActionPatterns: [String] = [
        "rm ", "sudo rm", "delete", "drop table", "drop database",
        "git push", "payment", "refund", "invoice",
    ]

    private let app: ClaudeApp
    private let hud: HUD
    private var timer: Timer?
    private var lastPressAt: TimeInterval = 0
    private var log: [Press] = []
    private let maxLog = 50
    /// Сколько диалогов не нажали по списку исключений — их же считает строка диагностики.
    private(set) var blockedCount = 0
    /// Сколько обходов оборвалось по дедлайну, не нажав ничего (#5736): на длинном чате
    /// дерево AX не успевает пройтись за `maxScanSeconds`, а диалог дорисовывается в его
    /// конец — авто-Allow молчит, и без этого счётчика узнать об этом было неоткуда.
    private(set) var timeoutCount = 0
    /// Последний заголовок из списка исключений: пока на экране висит тот же диалог, тик
    /// идёт раз в 1,5 с, а плашка и счёт должны сработать по одному разу на диалог.
    private var lastBlockedHeading = ""

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(app: ClaudeApp, hud: HUD) {
        self.app = app
        self.hud = hud
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var isRunning: Bool { timer != nil }
    var history: [Press] { log }
    var pressCount: Int { log.count }

    /// Один обход. Возвращает текст нажатой кнопки, если нажали.
    @discardableResult
    func scan() -> String? {
        guard enabled, AX.isTrustedCached, let appElement = app.element() else { return nil }
        // Electron отдаёт дерево только при включённом AXManualAccessibility, а Claude
        // роняет флаг после перезапусков (03.09: дерево ужалось до 45 узлов, флаг читается
        // false даже после успешной установки) — переустанавливаем на каждом тике.
        if AX.bool(appElement, "AXManualAccessibility") != true {
            AX.set(appElement, "AXManualAccessibility", bool: true)
            AX.set(appElement, "AXEnhancedUserInterface", bool: true)
        }
        let deadline = Date.timeIntervalSinceReferenceDate + maxScanSeconds
        var cut = false
        for window in AX.elements(appElement, kAXWindowsAttribute) {
            let found = AutoAllow.findButtons(root: window, patterns: buttonPatterns, deadline: deadline)
            cut = cut || found.timedOut
            for hit in found.hits {
                let head = AutoAllow.heading(of: hit.element)
                if AutoAllow.isBlocked(heading: head, patterns: blockActionPatterns) {
                    // Не жмём и говорим, почему: диалог остаётся Элвису, а молчаливого
                    // «ничего не происходит» больше нет (#5736).
                    if head != lastBlockedHeading {
                        lastBlockedHeading = head
                        blockedCount += 1
                        hud.show("Не жму сам: " + head, seconds: 2)
                    }
                    continue
                }
                let now = Date.timeIntervalSinceReferenceDate
                guard now - lastPressAt > 0.7 else { continue }
                let ok = AX.perform(hit.element, kAXPressAction)
                lastPressAt = now
                log.insert(Press(at: AutoAllow.clock.string(from: Date()), heading: head,
                                 button: hit.text, ok: ok), at: 0)
                if log.count > maxLog { log.removeLast() }
                hud.show("Auto-allow: " + (head.isEmpty ? hit.text : head), seconds: 1.2)
                return hit.text
            }
        }
        // Обход не дошёл до конца и ничего не нажал — считаем это отдельно от «диалогов не было».
        if cut { timeoutCount += 1 }
        return nil
    }

    /// Обёртка вопроса вокруг действия: её снимаем, чтобы осталось само действие.
    /// Порядок важен — длинная обёртка идёт раньше своей короткой части.
    static let actionWrappers = [
        "allow claude to ", "claude wants to ", "do you want to ", "would you like to ",
        "let claude ", "allow ", "confirm ", "run ", "execute ", "use ", "call ",
    ]
    /// «… to run », «… wants to use » — после этих слов начинается сама команда, даже если
    /// перед ними стоит имя инструмента («Allow Bash to run …»).
    static let actionMarkers = [" to run ", " to use ", " to execute ", " to call ", " to launch "]
    /// Одно действие бывает цепочкой: `cd build && rm -rf *` — опасна вторая команда, и
    /// начало у неё своё.
    static let commandSeparators = CharacterSet(charactersIn: ";|&`\n")

    /// Что диалог на самом деле подтверждает, без вопросительной обёртки и в нижнем регистре:
    /// «Allow Bash to run rm -rf build?» → «rm -rf build», «Claude wants to edit invoice.md» →
    /// «edit invoice.md». Чистая, её и гоняют тесты.
    static func action(of heading: String) -> String {
        var text = heading.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, last == "?" || last == "." || last == "!" { text.removeLast() }
        // Хвост после САМОГО ПОЗДНЕГО признака команды: «allow claude to use bash to run rm …».
        var cut: String.Index?
        for marker in actionMarkers {
            guard let found = text.range(of: marker, options: .backwards) else { continue }
            if cut == nil || found.upperBound > cut! { cut = found.upperBound }
        }
        if let cut = cut {
            text = String(text[cut...])
        } else {
            // Обёртки снимаются слоями: «allow run rm -rf x» → «run rm -rf x» → «rm -rf x».
            for _ in 0..<3 {
                guard let wrapper = actionWrappers.first(where: { text.hasPrefix($0) }) else { break }
                text.removeFirst(wrapper.count)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Диалог из списка исключений? Чистая, её и гоняют тесты. Сравнивается НАЧАЛО команды
    /// (`action(of:)`), а не любое место заголовка: иначе имя файла (`refunds.md`,
    /// `delete-old.sql`) глушило бы авто-Allow без всякой причины (#5779).
    /// Регистр не важен: заголовок приходит из разметки Claude, список написан строчными.
    static func isBlocked(heading: String, patterns: [String]) -> Bool {
        guard !heading.isEmpty, !patterns.isEmpty else { return false }
        let wanted = patterns.map { $0.lowercased() }
        for command in action(of: heading).components(separatedBy: commandSeparators) {
            let clean = command.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { continue }
            if wanted.contains(where: { clean.hasPrefix($0) }) { return true }
        }
        return false
    }

    // MARK: - обход дерева

    struct Hit {
        let element: AXUIElement
        let text: String
    }

    /// AXTitle + AXDescription + AXValue элемента.
    static func text(of element: AXUIElement) -> String {
        var parts: [String] = []
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let value = AX.string(element, attribute), !value.isEmpty { parts.append(value) }
        }
        return parts.joined(separator: " ")
    }

    /// Текст элемента и его потомков на два уровня, пробелы схлопнуты.
    static func deepText(of element: AXUIElement) -> String {
        var parts = [text(of: element)]
        for child in AX.elements(element, kAXChildrenAttribute) {
            parts.append(text(of: child))
            for grandchild in AX.elements(child, kAXChildrenAttribute) {
                parts.append(text(of: grandchild))
            }
        }
        return parts.joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Кнопки, чей текст подходит под паттерны. В AXButton не спускаемся (как в Lua),
    /// глубина ограничена 80 уровнями, обход обрывается по дедлайну.
    /// `timedOut` — обход оборвался по времени, то есть дерево пройдено НЕ целиком и кнопки
    /// могло просто не хватить времени найти (#5736). Упор в глубину 80 обрывом не считается.
    static func findButtons(root: AXUIElement, patterns: [TextPattern],
                            deadline: TimeInterval) -> (hits: [Hit], timedOut: Bool) {
        var found: [Hit] = []
        var timedOut = false
        func walk(_ element: AXUIElement, _ depth: Int) {
            if depth > 80 { return }
            if Date.timeIntervalSinceReferenceDate > deadline {
                timedOut = true
                return
            }
            if AX.string(element, kAXRoleAttribute) == kAXButtonRole {
                let t = deepText(of: element)
                if patterns.contains(where: { $0.matches(t) }) { found.append(Hit(element: element, text: t)) }
                return
            }
            for child in AX.elements(element, kAXChildrenAttribute) { walk(child, depth + 1) }
        }
        walk(root, 0)
        return (found, timedOut)
    }

    /// Заголовок диалога, которому принадлежит кнопка: поднимаемся до шести родителей и в
    /// каждом ищем в ширину (не больше 80 узлов) первый AXStaticText, похожий на вопрос.
    static func heading(of button: AXUIElement) -> String {
        var element: AXUIElement? = button
        for _ in 0..<6 {
            element = element.flatMap { AX.element($0, kAXParentAttribute) }
            guard let parent = element else { break }
            var queue = [parent]
            var seen = 0
            while !queue.isEmpty && seen < 80 {
                let current = queue.removeFirst()
                seen += 1
                if AX.string(current, kAXRoleAttribute) == kAXStaticTextRole {
                    let t = text(of: current)
                    if t.hasPrefix("Allow") || t.contains("wants to") || t.hasSuffix("?") { return t }
                }
                queue.append(contentsOf: AX.elements(current, kAXChildrenAttribute))
            }
        }
        return ""
    }
}

/// Простые текстовые правила вместо Lua-паттернов: в модуле встречались только
/// «начинается с» и «точное совпадение».
enum TextPattern {
    case prefix(String)
    case exact(String)
    case contains(String)

    func matches(_ value: String) -> Bool {
        switch self {
        case .prefix(let p): return value.hasPrefix(p)
        case .exact(let e): return value == e
        case .contains(let c): return value.contains(c)
        }
    }
}
