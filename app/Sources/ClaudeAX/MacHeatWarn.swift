import Foundation

// Предупреждение о перегреве Мака (#10998, слово Элвиса 27.10.2026: «так ну кипяток уже, ты почему не сообщаешь?»):
// MacBook Air M4 раскалился, видеокарта 76 %, kernel_task 25 % — а Пимп молчал и показывал 52° (среднее по датчикам).
//
// Когда предупреждаем (`reason`), по последней свежей точке истории температуры:
//   • macOS сама говорит «сильно нагрет» или «перегрет» (`thermalState` serious/critical) — сразу: она уже сбавляет
//     частоту и знает модель Мака лучше любого порога;
//   • самый горячий датчик кристалла `hotDegrees` (95°) и выше два чтения подряд (2 мин). Почему 95: под нагрузкой
//     90° у Apple Silicon — норма (см. `MacTemperature.health`), а около 100–105° кристалл уже сбрасывает частоту;
//     95° подряд — Мак держится у самой границы, а не на миг подскочил. Батарея (запасной путь без чипа) порогом
//     не служит — там только `thermalState`.
// Не чаще раза в `cooldown` (30 мин); время последнего — в UserDefaults, чтобы перезапуск Пимпа не повторял баннер.
// Что грузит — три верхних по процессору из `ps`, помощники приложения сложены в одно имя («Claude», «Chrome»).

public enum MacHeatWarn {
    public static let hotDegrees: Double = 95
    public static let hotReadings = 2
    public static let cooldown: TimeInterval = 30 * 60
    /// Точка старше — Мак спал или опрос стоял: по ней не предупреждаем.
    public static let maxAge: TimeInterval = 300
    public static let lastKey = "macHeatWarnLast10998"
    public static let topCount = 3

    public enum Reason: Equatable {
        /// macOS: serious / critical; градусы чипа, если есть.
        case state(ProcessInfo.ThermalState, degrees: Int?)
        /// Порог по самому горячему датчику.
        case degrees(Int)
    }

    /// Повод предупредить по истории (последняя точка — сейчас); nil — не горячо.
    public static func reason(_ history: [MacTemperatureSample], now: Date) -> Reason? {
        guard let last = history.last, now.timeIntervalSince(last.at) <= maxAge, last.at <= now.addingTimeInterval(60)
        else { return nil }
        let chip = last.isChip ? last.value.map { Int($0.rounded()) } : nil
        if last.state == .serious || last.state == .critical { return .state(last.state, degrees: chip) }
        let tail = Array(history.suffix(hotReadings))
        guard tail.count == hotReadings else { return nil }
        for (index, sample) in tail.enumerated() {
            guard sample.isChip, let value = sample.value, value >= hotDegrees else { return nil }
            if index > 0, sample.at.timeIntervalSince(tail[index - 1].at) > MacTemperature.gap { return nil }
        }
        return chip.map(Reason.degrees)
    }

    /// Можно ли уже снова: прошлого не было или прошло `cooldown`. Часы ушли назад — тоже можно.
    public static func allowed(last: Date?, now: Date) -> Bool {
        guard let last = last else { return true }
        let passed = now.timeIntervalSince(last)
        return passed >= cooldown || passed < 0
    }

    // MARK: что грузит

    public struct ProcessLoad: Equatable {
        public let name: String
        public let cpu: Double

        public init(name: String, cpu: Double) {
            self.name = name
            self.cpu = cpu
        }
    }

    /// Имена по-человечески по последней части пути; известные — словом, остальное — как есть.
    static let known: [String: String] = [
        "WindowServer": "WindowServer (экран и окна)",
        "kernel_task": "kernel_task (macOS гасит жар)",
        "node": "node (скрипты и тесты)",
        "swift-frontend": "сборка Swift", "swift-build": "сборка Swift", "swiftc": "сборка Swift",
        "swift-test": "сборка Swift", "xctest": "тесты Swift", "clang": "сборка", "ld": "сборка",
        "com.apple.WebKit.WebContent": "Safari и WebKit",
        "mds_stores": "Spotlight", "mds": "Spotlight", "mdworker_shared": "Spotlight",
        "python3": "Python", "Python": "Python",
    ]
    /// Приложения, чьё имя в пути длиннее нужного.
    static let apps: [String: String] = ["Google Chrome": "Chrome", "Google Chrome Canary": "Chrome Canary"]

    /// «/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/…» → «Claude»: известное имя
    /// программы сильнее, иначе — первое `.app` в пути (помощники в одну строку с приложением), иначе — сама программа.
    public static func humanName(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "/").map(String.init)
        let tail = parts.last ?? trimmed
        if let name = known[tail] { return name }
        if let bundle = parts.first(where: { $0.hasSuffix(".app") }) {
            let app = String(bundle.dropLast(4))
            return apps[app] ?? app
        }
        return tail
    }

    /// Вывод `ps -Ao pcpu=,comm=`: строки «12.3 /путь/к/программе»; по человеческому имени сложено, сам `ps` и
    /// нули — прочь, по убыванию.
    public static func parse(_ output: String) -> [ProcessLoad] {
        var sums: [String: Double] = [:]
        var order: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let space = text.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let number = text[..<space].replacingOccurrences(of: ",", with: ".")
            let command = text[space...].trimmingCharacters(in: .whitespaces)
            guard let cpu = Double(number), cpu.isFinite, cpu > 0, !command.isEmpty else { continue }
            if command == "ps" || command.hasSuffix("/ps") { continue }
            let name = humanName(command)
            if sums[name] == nil { order.append(name) }
            sums[name, default: 0] += cpu
        }
        return order.map { ProcessLoad(name: $0, cpu: sums[$0] ?? 0) }
            .enumerated().sorted { $0.element.cpu != $1.element.cpu ? $0.element.cpu > $1.element.cpu : $0.offset < $1.offset }
            .map { $0.element }
    }

    /// Заголовок и текст баннера.
    public static func text(_ reason: Reason, top: [ProcessLoad], gpu: Double?) -> (title: String, body: String) {
        let head: String
        switch reason {
        case .state(let state, let degrees):
            head = "macOS: \(MacTemperature.word(state))" + (degrees.map { ", чип \($0)°" } ?? "")
                + " — Мак сбавляет частоту."
        case .degrees(let degrees):
            head = "Чип \(degrees)° уже две минуты."
        }
        var lines = [head]
        let loads = top.prefix(topCount).map { "\($0.name) \(Int($0.cpu.rounded()))\u{00A0}%" }
        if !loads.isEmpty { lines.append("Грузят: " + loads.joined(separator: ", ") + ".") }
        if let gpu = gpu, gpu >= 50 { lines.append("Видеокарта \(Int(gpu.rounded()))\u{00A0}%.") }
        return ("Мак перегрелся", lines.joined(separator: " "))
    }

    /// `ps` раз в момент предупреждения (не на каждом опросе), не с главного потока. Не вышло — пусто.
    public static func readTop() -> [ProcessLoad] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "pcpu=,comm="]
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }
}

/// Сторож: держит время последнего баннера и решает, пора ли. Звать на главном потоке из `onUpdate` температуры;
/// `ps` читается на фоне, `post` — снова на главном.
public final class MacHeatWarner {
    private let defaults: UserDefaults
    private let readTop: () -> [MacHeatWarn.ProcessLoad]
    private let background: DispatchQueue

    public init(defaults: UserDefaults = .standard,
                readTop: @escaping () -> [MacHeatWarn.ProcessLoad] = MacHeatWarn.readTop,
                background: DispatchQueue = .global(qos: .utility)) {
        self.defaults = defaults
        self.readTop = readTop
        self.background = background
    }

    public var last: Date? { defaults.object(forKey: MacHeatWarn.lastKey) as? Date }

    /// Горячо и можно — отметка ставится сразу (второй опрос до ответа `ps` не дублирует), баннер — через `post`.
    /// Возвращает повод, если предупреждение ушло.
    @discardableResult
    public func check(_ history: [MacTemperatureSample], gpu: Double?, now: Date = Date(),
                      post: @escaping (_ title: String, _ body: String) -> Void) -> MacHeatWarn.Reason? {
        guard let reason = MacHeatWarn.reason(history, now: now), MacHeatWarn.allowed(last: last, now: now) else { return nil }
        defaults.set(now, forKey: MacHeatWarn.lastKey)
        let readTop = self.readTop
        background.async {
            let text = MacHeatWarn.text(reason, top: readTop(), gpu: gpu)
            DispatchQueue.main.async { post(text.title, text.body) }
        }
        return reason
    }
}
