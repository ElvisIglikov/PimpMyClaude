import Foundation

// Цены моделей Claude по API для «Цены Workflow» (#6282). Источник — страница цен Anthropic
// https://platform.claude.com/docs/en/about-claude/pricing (снято 20.10.2026), сверено со снимком навыка claude-api
// (06.10.2026; где расходятся — верна страница: чтение кэша Sonnet 5.5 $0,10, а не $0,20). Каждая колонка — явные $ за
// 1 млн токенов, без общих множителей; поменялась таблица — поднять `version` (кэш сумм `workflow-cost.json`
// пересчитается). Контракт — `docs/contracts/535-6282-workflow-cost.md`, тесты — `ModelPricesTests`.

/// Цены одной ступени, $ за 1 млн токенов: вход, выход, запись кэша на 5 мин и на 1 ч, чтение кэша.
public struct TokenPrice: Equatable {
    public let input: Double
    public let output: Double
    public let write5m: Double
    public let write1h: Double
    public let read: Double

    public init(_ input: Double, _ output: Double, write5m: Double, write1h: Double, read: Double) {
        self.input = input
        self.output = output
        self.write5m = write5m
        self.write1h = write1h
        self.read = read
    }

    public var all: [Double] { [input, output, write5m, write1h, read] }
}

/// Строка таблицы: модель по началу id, обычные цены, быстрый режим (`usage.speed == "fast"`) и ступень по длине запроса.
public struct ModelPriceRow: Equatable {
    /// Начало model id без даты: «claude-opus-5-5».
    public let id: String
    /// «Opus 5.5».
    public let name: String
    /// «Opus», «Sonnet», «Haiku», «Fable», «Mythos».
    public let family: String
    public let standard: TokenPrice
    /// Быстрый режим; nil — у модели его нет (такой ответ — без цены).
    public let fast: TokenPrice?
    /// Запрос длиннее (вход + запись + чтение кэша) — по ценам `long` (Haiku 5.5: больше 100 000).
    public let longAbove: Int?
    public let long: TokenPrice?

    init(_ id: String, _ name: String, _ family: String, _ standard: TokenPrice, fast: TokenPrice? = nil,
         longAbove: Int? = nil, long: TokenPrice? = nil) {
        self.id = id
        self.name = name
        self.family = family
        self.standard = standard
        self.fast = fast
        self.longAbove = longAbove
        self.long = long
    }
}

public enum ModelPrices {
    /// Версия таблицы: сменилась — суммы из кэша не годятся.
    public static let version = 1
    public static let source = "https://platform.claude.com/docs/en/about-claude/pricing"
    /// `inference_geo: "us"` (данные в США): ×1,1 ко всем ценам (Claude 4.6 и новее; старые такой запрос отвергают).
    public static let usGeoFactor = 1.1

    private static let fable = TokenPrice(10, 50, write5m: 12.5, write1h: 20, read: 0.25)
    private static let fable5 = TokenPrice(10, 50, write5m: 12.5, write1h: 20, read: 1)
    private static let opus5 = TokenPrice(5, 25, write5m: 6.25, write1h: 10, read: 0.5)
    private static let opus5Fast = TokenPrice(10, 50, write5m: 12.5, write1h: 20, read: 1)
    private static let opus41 = TokenPrice(15, 75, write5m: 18.75, write1h: 30, read: 1.5)
    private static let sonnet46 = TokenPrice(3, 15, write5m: 3.75, write1h: 6, read: 0.3)

    public static let rows: [ModelPriceRow] = [
        ModelPriceRow("claude-fable-5-1", "Fable 5.1", "Fable", fable),
        ModelPriceRow("claude-mythos-5-1", "Mythos 5.1", "Mythos", fable),
        ModelPriceRow("claude-fable-5", "Fable 5", "Fable", fable5),
        ModelPriceRow("claude-mythos-5", "Mythos 5", "Mythos", fable5),
        ModelPriceRow("claude-opus-5-5", "Opus 5.5", "Opus", TokenPrice(4, 20, write5m: 5, write1h: 8, read: 0.2),
                      fast: TokenPrice(8, 40, write5m: 10, write1h: 16, read: 0.4)),
        ModelPriceRow("claude-opus-5", "Opus 5", "Opus", opus5, fast: opus5Fast),
        ModelPriceRow("claude-opus-4-8", "Opus 4.8", "Opus", opus5, fast: opus5Fast),
        ModelPriceRow("claude-opus-4-7", "Opus 4.7", "Opus", opus5),
        ModelPriceRow("claude-opus-4-6", "Opus 4.6", "Opus", opus5),
        ModelPriceRow("claude-opus-4-5", "Opus 4.5", "Opus", opus5),
        ModelPriceRow("claude-opus-4-1", "Opus 4.1", "Opus", opus41),
        ModelPriceRow("claude-opus-4", "Opus 4", "Opus", opus41),
        ModelPriceRow("claude-sonnet-5-5", "Sonnet 5.5", "Sonnet", TokenPrice(2, 10, write5m: 2.5, write1h: 4, read: 0.1)),
        ModelPriceRow("claude-sonnet-5", "Sonnet 5", "Sonnet", TokenPrice(2, 10, write5m: 2.5, write1h: 4, read: 0.2)),
        ModelPriceRow("claude-sonnet-4-6", "Sonnet 4.6", "Sonnet", sonnet46),
        ModelPriceRow("claude-sonnet-4-5", "Sonnet 4.5", "Sonnet", sonnet46),
        ModelPriceRow("claude-sonnet-4", "Sonnet 4", "Sonnet", sonnet46),
        ModelPriceRow("claude-haiku-5-5", "Haiku 5.5", "Haiku",
                      TokenPrice(0.1, 0.5, write5m: 0.125, write1h: 0.2, read: 0.01),
                      longAbove: 100_000, long: TokenPrice(0.5, 2.5, write5m: 0.625, write1h: 1, read: 0.05)),
        ModelPriceRow("claude-haiku-4-5", "Haiku 4.5", "Haiku", TokenPrice(1, 5, write5m: 1.25, write1h: 2, read: 0.1)),
        ModelPriceRow("claude-3-5-haiku", "Haiku 3.5", "Haiku", TokenPrice(0.8, 4, write5m: 1, write1h: 1.6, read: 0.08)),
    ]

    /// id без обёрток: «us.anthropic.claude-opus-4-6-v1:0» и «claude-opus-4-5@20251101» → «claude-…», «[1m]» — долой,
    /// строчными.
    static func clean(_ model: String) -> String {
        var id = model.lowercased().trimmingCharacters(in: .whitespaces)
        if let bracket = id.firstIndex(of: "[") { id = String(id[..<bracket]) }
        if let at = id.firstIndex(of: "@") { id = String(id[..<at]) }
        if let start = id.range(of: "claude-") { id = String(id[start.lowerBound...]) }
        if let version = id.range(of: "-v[0-9]+(:[0-9]+)?$", options: .regularExpression) { id.removeSubrange(version) }
        return id
    }

    /// Строка таблицы для model id: id ровно такой или с датой «-20251001». Другой хвост («claude-opus-5-7») —
    /// неизвестная модель: цена соседней версии могла бы оказаться неверной. `<synthetic>` и чужие — nil.
    public static func row(_ model: String) -> ModelPriceRow? {
        let id = clean(model)
        return rows.first { row in
            guard id.hasPrefix(row.id) else { return false }
            let tail = id.dropFirst(row.id.count)
            return tail.isEmpty || tail.range(of: "^-[0-9]{8}$", options: .regularExpression) != nil
        }
    }

    /// Семейство для подписи: «Opus», «Sonnet»…; неизвестная — nil.
    public static func family(_ model: String) -> String? { row(model)?.family }

    /// Цена одного ответа, $; модели нет в таблице или быстрый режим у модели без него — nil.
    public static func cost(model: String, input: Int, output: Int, write5m: Int, write1h: Int, read: Int,
                            fast: Bool = false, usGeo: Bool = false) -> Double? {
        guard let row = row(model) else { return nil }
        var price = row.standard
        if fast {
            guard let quick = row.fast else { return nil }
            price = quick
        } else if let above = row.longAbove, let long = row.long, input + write5m + write1h + read > above {
            price = long
        }
        let sum = Double(input) * price.input + Double(output) * price.output + Double(write5m) * price.write5m
            + Double(write1h) * price.write1h + Double(read) * price.read
        return sum / 1_000_000 * (usGeo ? usGeoFactor : 1)
    }
}
