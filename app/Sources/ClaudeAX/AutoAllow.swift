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
    /// Заголовки диалогов, которые НИКОГДА не подтверждаем (M.blockHeadingPatterns).
    /// Пусто = подтверждать всё. Сравнение — вхождение подстроки: { "rm -rf", "git push" }.
    var blockHeadingPatterns: [String] = []

    private let app: ClaudeApp
    private let hud: HUD
    private var timer: Timer?
    private var lastPressAt: TimeInterval = 0
    private var log: [Press] = []
    private let maxLog = 50
    private(set) var blockedCount = 0

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
        for window in AX.elements(appElement, kAXWindowsAttribute) {
            for hit in AutoAllow.findButtons(root: window, patterns: buttonPatterns, deadline: deadline) {
                let head = AutoAllow.heading(of: hit.element)
                if !blockHeadingPatterns.isEmpty,
                   blockHeadingPatterns.contains(where: { head.contains($0) }) {
                    blockedCount += 1
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
        return nil
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
    static func findButtons(root: AXUIElement, patterns: [TextPattern], deadline: TimeInterval) -> [Hit] {
        var found: [Hit] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            if depth > 80 || Date.timeIntervalSinceReferenceDate > deadline { return }
            if AX.string(element, kAXRoleAttribute) == kAXButtonRole {
                let t = deepText(of: element)
                if patterns.contains(where: { $0.matches(t) }) { found.append(Hit(element: element, text: t)) }
                return
            }
            for child in AX.elements(element, kAXChildrenAttribute) { walk(child, depth + 1) }
        }
        walk(root, 0)
        return found
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
