import Foundation

// Масштаб окон Claude в блоке «Оформление» (слово 03.11.2026: «в оформлении должен быть масштаб тоже, сколько сейчас
// масштаб клауда окна»). Масштаб держит сам Claude: Пимп нажимает его пункты меню «Вид», а значение читает у страницы
// (`outerWidth / innerWidth`, поле `zoom` ответа `ChatProbe`). Вид строки — `ExtraZoomRow` в `Panel/PanelColors.swift`.

public enum ClaudeZoom: Equatable {
    case larger, smaller, actual

    /// Клавиши пунктов меню с ⌘ без других модификаторов: пункты ищем по ним — подписи зависят от языка Claude.
    var keys: [String] {
        switch self {
        case .larger: return ["+", "="]
        case .smaller: return ["-"]
        case .actual: return ["0"]
        }
    }

    /// Шаг Claude — половина уровня Electron, уровень L — множитель 1,2^L.
    static let levelStep = 0.5
    static let levelBase = 1.2

    /// Проценты после шага: показать сразу, не дожидаясь круга `ChatProbe`.
    public func percent(after current: Int) -> Int {
        let level = (log(Double(current) / 100) / log(Self.levelBase) / Self.levelStep).rounded() * Self.levelStep
        switch self {
        case .actual: return 100
        case .larger: return Int((pow(Self.levelBase, level + Self.levelStep) * 100).rounded())
        case .smaller: return Int((pow(Self.levelBase, level - Self.levelStep) * 100).rounded())
        }
    }

    /// Проценты из ответа страницы; мусор — nil.
    static func parse(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (25.0...500.0).contains(number.doubleValue) else { return nil }
        return number.intValue
    }
}
