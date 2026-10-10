import Foundation

/// «Поддержать автора» (WF108, #8179; окно переделано в WF227, #9406, макет `docs/37.html`): чистая часть —
/// разбор `donate.json`, какой файл сильнее, видны ли входы, какие способы оплаты есть, ряд сумм, ссылки,
/// счёт людей, адрес Instagram. Сети нет: способы, счёт и курс — только из файла (умолчание в бандле + живой в
/// Application Support/MyClaude, живой сильнее). Окно и строка панели — в приложении.
public struct DonateConfig: Equatable {
    public struct Coin: Equatable {
        public var coin: String
        public var network: String
        public var address: String
    }

    /// Сколько человек поддержали — счёт «Друзья Пимпа» (WF227: вместо шкалы денег).
    public var people: Int
    /// Тенге за доллар; nil — «≈ $» не пишем.
    public var usdRate: Double?
    public var amounts: [Int]
    /// Ссылки на оплату (только http/https); nil — способа нет, и кнопки нет.
    public var applePay: String?
    public var card: String?
    public var kaspi: String?
    public var crypto: [Coin]
    /// Имя в Instagram без «@»; nil — ссылки нет.
    public var instagram: String?

    static let defaultAmounts = [1000, 5000, 10000]
    /// Ряд сумм — не больше трёх готовых (четвёртая плитка — «Своя»).
    static let maxAmounts = 3
    /// Своя сумма — до семи цифр (как поле в макете).
    public static let maxAmount = 9_999_999

    /// Разбор тела файла. Не JSON или не объект — nil (тогда берут другой файл); битые поля —
    /// умолчание или «нет»: одна опечатка не должна прятать весь сбор.
    public static func parse(_ data: Data?) -> DonateConfig? {
        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let amounts = (json["amounts"] as? [Any])?.compactMap { positive($0) }.filter { $0 <= maxAmount }
        let crypto: [Coin] = (json["crypto"] as? [Any] ?? []).compactMap { item in
            guard let item = item as? [String: Any], let address = text(item["address"]) else { return nil }
            return Coin(coin: text(item["coin"]) ?? "", network: text(item["network"]) ?? "", address: address)
        }
        let rate = number(json["usdRate"]).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        return DonateConfig(people: max(0, integer(json["people"]) ?? 0),
                            usdRate: rate,
                            amounts: Array((amounts ?? defaultAmounts).prefix(maxAmounts)),
                            applePay: link(json["applePay"]),
                            card: link(json["card"]),
                            kaspi: link(json["kaspi"]),
                            crypto: crypto,
                            instagram: Donate.instagramHandle(text(json["instagram"])))
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty
        else { return nil }
        return string
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let double = number(value), double.isFinite, abs(double) < 1e12 else { return nil }
        return Int(double.rounded())
    }

    private static func positive(_ value: Any?) -> Int? {
        integer(value).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Только http/https: живой файл пишет человек руками, чужая схема в Safari не нужна.
    private static func link(_ value: Any?) -> String? {
        guard let string = text(value) else { return nil }
        let probe = string.replacingOccurrences(of: Donate.amountToken, with: "1")
        guard let url = URL(string: probe), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return nil }
        return string
    }
}

/// Решения окна и входов — тут, чтобы их проверяли тесты (`DonateTests`).
public enum Donate {
    public static let fileName = "donate.json"
    /// «Не показывать „Поддержать“» — выключатель в «Ещё».
    public static let hiddenKey = "donateHidden"
    public static let amountToken = "{amount}"
    public static let unofficial = "Pimp My Claude — неофициальная программа, не связана с Anthropic"

    /// Способ оплаты. Порядок — как в окне: главная кнопка — первый из тех, что есть в файле.
    public enum Method: Equatable { case applePay, card, kaspi, crypto }

    /// Способы, у которых в файле есть адрес (WF227, #9406): нет ссылки — нет кнопки, «скоро» на кнопках не пишем.
    public static func methods(_ config: DonateConfig) -> [Method] {
        var out: [Method] = []
        if config.applePay != nil { out.append(.applePay) }
        if config.card != nil { out.append(.card) }
        if config.kaspi != nil { out.append(.kaspi) }
        if !config.crypto.isEmpty { out.append(.crypto) }
        return out
    }

    /// Есть хоть один способ оплаты.
    public static func hasAddress(_ config: DonateConfig?) -> Bool {
        config.map { !methods($0).isEmpty } ?? false
    }

    /// Окно и входы в него есть, только когда есть хоть один способ оплаты (решение файла 37: пока платить
    /// нечем — строки, окна и напоминаний не видно никому; вход, ведущий к «скоро», — тупик).
    public static func windowAvailable(_ config: DonateConfig?) -> Bool {
        hasAddress(config)
    }

    /// Строка в панели и пункт меню: окну есть что показать и человек их не выключал.
    public static func entriesVisible(_ config: DonateConfig?, hidden: Bool) -> Bool {
        windowAvailable(config) && !hidden
    }

    /// Ряд сумм — только если хоть одна ссылка на оплату умеет `{amount}`; нет — сумму спросит страница.
    public static func showsAmounts(_ config: DonateConfig) -> Bool {
        [config.applePay, config.card, config.kaspi].contains { $0?.contains(amountToken) == true }
    }

    /// Имя в Instagram из файла: «_elvis.kz_», «@_elvis.kz_» или ссылка `instagram.com/_elvis.kz_`. Подчёркивания по
    /// краям — часть имени (#9394), их не срезаем. Знаки не из имени Instagram или длиннее 30 — nil.
    public static func instagramHandle(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let host = name.range(of: "instagram.com/", options: .caseInsensitive) { name = String(name[host.upperBound...]) }
        name = name.split(whereSeparator: { "/?#".contains($0) }).first.map(String.init) ?? ""
        if name.hasPrefix("@") { name.removeFirst() }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        guard (1...30).contains(name.count), name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return name
    }

    public static func instagramURL(_ handle: String) -> URL? {
        URL(string: "https://instagram.com/" + handle)
    }

    /// Счёт «Друзья Пимпа» (WF227, кадр 37.5): ячейки до ближайшей ступени и строка под ними.
    public struct Friends: Equatable {
        /// Сколько ячеек в ряду — ближайшая ступень; 0 — все ступени пройдены, ряда нет.
        public var cells: Int
        public var filled: Int
        public var note: String
    }

    static let friendSteps = [10, 25, 50, 100]

    public static func friends(_ people: Int) -> Friends {
        let passed = friendSteps.last { people >= $0 }
        guard let next = friendSteps.first(where: { people < $0 }) else {
            return Friends(cells: 0, filled: 0, note: "Ступень «\(friendSteps.last ?? 0)» пройдена.")
        }
        if people <= 0 { return Friends(cells: next, filled: 0, note: "Пока никто — стань первым.") }
        let left = "ещё \(next - people)"
        let note = passed.map { "Ступень «\($0)» пройдена. До «\(next)» — \(left)." } ?? "До ступени «\(next)» — \(left)."
        return Friends(cells: next, filled: people, note: note)
    }

    /// Ссылка на оплату с подставленной суммой; `{amount}` без суммы — nil (кнопка серая).
    public static func payURL(_ template: String?, amount: Int?) -> URL? {
        guard let template = template else { return nil }
        guard template.contains(amountToken) else { return URL(string: template) }
        guard let amount = amount, amount > 0 else { return nil }
        return URL(string: template.replacingOccurrences(of: amountToken, with: String(amount)))
    }

    /// «≈ $10» по курсу файла, не меньше $1; курса нет — nil.
    public static func usd(_ tenge: Int, rate: Double?) -> String? {
        guard let rate = rate, rate > 0, tenge > 0 else { return nil }
        return "≈ $" + group(max(1, Int((Double(tenge) / rate).rounded())))
    }

    /// «1 376 000 ₸» — разряды неразрывным пробелом, как `toLocaleString('ru-RU')` в макете.
    public static func tenge(_ value: Int) -> String {
        group(value) + "\u{00A0}₸"
    }

    public static func group(_ value: Int) -> String {
        let digits = String(abs(value))
        var out = ""
        for (index, char) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append("\u{00A0}") }
            out.append(char)
        }
        return value < 0 ? "−" + out : out
    }

    /// Возврат платёжки: `pimpmyclaude://donate/thanks` и `…/cancel`.
    public enum Return: Equatable { case thanks, cancel }

    public static func parseReturn(_ url: URL) -> Return? {
        guard url.scheme?.lowercased() == "pimpmyclaude", url.host?.lowercased() == "donate" else { return nil }
        switch url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "thanks": return .thanks
        case "cancel": return .cancel
        default: return nil
        }
    }
}

/// Два файла: умолчание в бандле и живой. Живой (если разобрался) сильнее целиком; перечитывается
/// по mtime — зовут при открытии панели и окна.
public final class DonateStore {
    public static let liveURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MyClaude", isDirectory: true)
        .appendingPathComponent(Donate.fileName)

    private let live: URL
    private let bundled: URL?
    private var stamp: (live: Date?, bundled: Date?)?
    private var cached: DonateConfig?

    public init(live: URL = DonateStore.liveURL,
                bundled: URL? = Bundle.main.url(forResource: "donate", withExtension: "json")) {
        self.live = live
        self.bundled = bundled
    }

    /// Свежий конфиг: файлы не менялись — из памяти. Ни один не разобрался — nil (входов нет).
    public func current() -> DonateConfig? {
        let now = (Self.mtime(live), bundled.flatMap(Self.mtime))
        if let stamp = stamp, stamp.live == now.0, stamp.bundled == now.1 { return cached }
        stamp = now
        cached = Self.resolve(live: now.0 == nil ? nil : try? Data(contentsOf: live),
                              bundled: bundled.flatMap { try? Data(contentsOf: $0) })
        return cached
    }

    /// Живой сильнее; битый живой — умолчание из бандла.
    public static func resolve(live: Data?, bundled: Data?) -> DonateConfig? {
        DonateConfig.parse(live) ?? DonateConfig.parse(bundled)
    }

    private static func mtime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
