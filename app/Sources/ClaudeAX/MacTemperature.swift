import Foundation
import IOKit

// Температура Мака в панели у часов (#8898, WF126 «Кодинг 3»; вид — `docs/25.html`, раздел 4). Слово Элвиса:
// «я бы график температуры хотел видеть ещё в Пимпе. MacBook греется» и «проверь, чтобы не грузило».
//
// Откуда градусы:
//   • чип — датчики `PMU tdie*` (температура кристалла у каждого кластера; у M1–M4 их 8–14) через
//     IOHIDEventSystemClient — так же читает Stats. Функции есть в IOKit, но не в открытых заголовках:
//     берём их `dlsym`, нет хоть одной — чтения чипа нет, без падения. `PMU tcal` — постоянная калибровки,
//     не температура; `tdev`/`TP*` — датчики корпуса и платы, их берём, только если `tdie` нет вовсе;
//   • батарея — открытый `AppleSmartBattery` «Temperature» (сотые доли °C): запасной путь, когда чипа нет;
//   • `ProcessInfo.thermalState` — как оценивает сама macOS, словом.
// Опрос — раз в минуту на своей очереди (не главный поток), допуск таймера 10 с (macOS склеивает пробуждения),
// история — 180 точек (3 ч) только в памяти, на диск ничего не пишется.

/// Одно чтение.
public struct MacTemperatureSample: Equatable {
    public let at: Date
    /// Среднее по датчикам кристалла, °C.
    public let chipAverage: Double?
    /// Самый горячий датчик кристалла, °C.
    public let chipMax: Double?
    public let battery: Double?
    public let state: ProcessInfo.ThermalState

    public init(at: Date, chipAverage: Double?, chipMax: Double?, battery: Double?, state: ProcessInfo.ThermalState) {
        self.at = at
        self.chipAverage = chipAverage
        self.chipMax = chipMax
        self.battery = battery
        self.state = state
    }

    /// Что рисуем: чип, без него — батарея.
    public var value: Double? { chipAverage ?? battery }
    public var isChip: Bool { chipAverage != nil }
}

/// Чистая часть: разбор датчиков, история, слова, масштаб графика (тесты `TemperatureWF126Tests`).
public enum MacTemperature {
    public static let interval: TimeInterval = 60
    public static let window: TimeInterval = 3 * 3600
    public static let capacity = 180
    /// Разрыв линии: пропущено больше двух чтений (сон Мака, выключали и включали).
    public static let gap: TimeInterval = 150
    /// Ключ выключателя «Температура в панели» (умолчание — включено).
    public static let enabledKey = "temperatureInPanel"

    /// Правдоподобные градусы датчика: 0 и мусор (−127, 0xFFFF) отбрасываем.
    static func plausible(_ value: Double) -> Bool { value.isFinite && value > 5 && value < 130 }

    /// Средняя и максимальная по кристаллу: `tdie`, без них — прочие `PMU` (кроме `tcal`).
    public static func chip(_ sensors: [(name: String, value: Double)]) -> (average: Double, max: Double, count: Int)? {
        let pmu = sensors.filter { $0.name.hasPrefix("PMU") && !$0.name.lowercased().contains("tcal") && plausible($0.value) }
        let die = pmu.filter { $0.name.lowercased().contains("tdie") }
        let use = die.isEmpty ? pmu : die
        guard !use.isEmpty else { return nil }
        let values = use.map { $0.value }
        return (values.reduce(0, +) / Double(values.count), values.max() ?? 0, values.count)
    }

    /// `AppleSmartBattery` «Temperature» — сотые доли °C (3050 → 30,5°).
    public static func battery(raw: Int?) -> Double? {
        guard let raw = raw else { return nil }
        let value = Double(raw) / 100
        return plausible(value) ? value : nil
    }

    /// Новая точка в истории: старше 3 ч и сверх 180 — прочь; точка без данных не добавляется.
    public static func append(_ sample: MacTemperatureSample, to history: [MacTemperatureSample]) -> [MacTemperatureSample] {
        guard sample.value != nil else { return history }
        var next = history.filter { sample.at.timeIntervalSince($0.at) < window && $0.at <= sample.at }
        next.append(sample)
        if next.count > capacity { next.removeFirst(next.count - capacity) }
        return next
    }

    public static func word(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "не нагрет"
        case .fair: return "слегка нагрет"
        case .serious: return "сильно нагрет"
        case .critical: return "перегрет"
        @unknown default: return "—"
        }
    }

    public static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    /// Подпись под графиком: «за 3 ч: 47–71° · батарея 34° · macOS: слегка нагрет». Размах — по той же линии, что
    /// на графике; «самый горячий» датчик (другой источник) снят: «37–49» и «самый горячий 41» спорили (#9020 п. 14).
    /// Слово macOS — только когда нагрет («macOS: не нагрет» снят, #9020 п. 13).
    public static func caption(_ history: [MacTemperatureSample]) -> String {
        guard let last = history.last else { return "" }
        var parts: [String] = []
        let values = history.compactMap { $0.value }
        if let low = values.min(), let high = values.max(), history.count > 1 {
            let span = Int((last.at.timeIntervalSince(history[0].at) / 60).rounded())
            let when = span >= 175 ? "за 3 ч" : span >= 60 ? "за \(span / 60) ч \(span % 60) мин" : "за \(max(span, 1)) мин"
            parts.append(Int(low.rounded()) == Int(high.rounded()) ? "\(when): \(degrees(low))"
                         : "\(when): \(Int(low.rounded()))–\(degrees(high))")
        }
        if last.isChip, let battery = last.battery { parts.append("батарея \(degrees(battery))") }
        if last.state != .nominal { parts.append("macOS: \(word(last.state))") }
        return parts.joined(separator: " · ")
    }

    /// Шкала графика: ступенями по 20° (как в файле 25: 40/60/80/100), не уже 20°.
    public static func scale(_ history: [MacTemperatureSample]) -> (low: Double, high: Double, ticks: [Double]) {
        let values = history.compactMap { $0.value }
        guard let min = values.min(), let max = values.max() else { return (40, 100, [40, 60, 80, 100]) }
        let low = Swift.max(0, (min / 20).rounded(.down) * 20)
        let high = Swift.max((max / 20).rounded(.up) * 20, low + 20)
        return (low, high, Array(stride(from: low, through: high, by: 20)))
    }

    /// Куски линии без разрывов: индексы точек истории.
    public static func segments(_ history: [MacTemperatureSample]) -> [[Int]] {
        var result: [[Int]] = []
        for index in history.indices {
            if index > 0, history[index].at.timeIntervalSince(history[index - 1].at) <= gap, !result.isEmpty {
                result[result.count - 1].append(index)
            } else {
                result.append([index])
            }
        }
        return result
    }

    /// Ближайшая по времени точка к доле 0…1 оси X (наведение на график).
    public static func nearest(_ history: [MacTemperatureSample], fraction: Double) -> Int? {
        guard let first = history.first, let last = history.last else { return nil }
        let span = last.at.timeIntervalSince(first.at)
        guard span > 0 else { return 0 }
        let target = first.at.addingTimeInterval(span * Swift.min(1, Swift.max(0, fraction)))
        return history.indices.min { abs(history[$0].at.timeIntervalSince(target)) < abs(history[$1].at.timeIntervalSince(target)) }
    }
}

/// Датчики через IOHIDEventSystemClient. Клиент и список служб создаются один раз — чтение только копирует
/// события датчиков кристалла; не вышло — пересоздаются при следующем чтении. Вызывать с одной очереди.
final class HIDTemperatureSensors {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValue = @convention(c) (AnyObject, UInt32) -> Double

    /// kIOHIDEventTypeTemperature и его поле уровня (тип << 16).
    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: UInt32 = 15 << 16

    private let create: CreateClient
    private let setMatching: SetMatching
    private let copyServices: CopyServices
    private let copyProperty: CopyProperty
    private let copyEvent: CopyEvent
    private let floatValue: FloatValue
    private var client: AnyObject?
    private var services: [(service: AnyObject, name: String)] = []

    /// nil — функций в этой macOS нет: чип не читаем, остаются батарея и `thermalState`.
    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", CreateClient.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", CopyEvent.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", FloatValue.self) else { return nil }
        self.create = create
        self.setMatching = setMatching
        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.floatValue = floatValue
    }

    private func connect() {
        services = []
        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { self.client = nil; return }
        // Датчики температуры: страница AppleVendor (0xFF00), использование TemperatureSensor (5).
        setMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary)
        self.client = client
        guard let list = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return }
        var all: [(service: AnyObject, name: String)] = []
        for service in list {
            let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String
            if let name = name { all.append((service, name)) }
        }
        // Читаем только то, из чего считается чип (`MacTemperature.chip`): каждое событие — свой вызов в ядро,
        // 57 датчиков M1 — ~55 мс, 15 `tdie` — вчетверо меньше.
        let pmu = all.filter { $0.name.hasPrefix("PMU") }
        let die = pmu.filter { $0.name.lowercased().contains("tdie") }
        services = die.isEmpty ? pmu : die
    }

    /// Все датчики с градусами; nil — ни один не ответил.
    func read() -> [(name: String, value: Double)]? {
        if client == nil || services.isEmpty { connect() }
        var result: [(name: String, value: Double)] = []
        for (service, name) in services {
            guard let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            result.append((name, floatValue(event, Self.temperatureField)))
        }
        if result.isEmpty { client = nil; services = [] }
        return result.isEmpty ? nil : result
    }
}

/// Открытый путь: температура батареи из `AppleSmartBattery`.
enum BatteryTemperature {
    static func read() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let raw = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber
        return MacTemperature.battery(raw: raw?.intValue)
    }
}

/// Опрос раз в минуту на своей очереди; история — в памяти. `onUpdate` зовётся на главном потоке.
public final class MacTemperatureMonitor {
    private let queue = DispatchQueue(label: "pimp.temperature", qos: .utility)
    private var timer: DispatchSourceTimer?
    private lazy var sensors = HIDTemperatureSensors()
    private var history: [MacTemperatureSample] = []
    /// Сколько миллисекунд заняло последнее чтение (для замера нагрузки и статуса).
    public private(set) var lastReadMilliseconds: Double = 0
    public var onUpdate: (([MacTemperatureSample]) -> Void)?

    public init() {}

    public var running: Bool { timer != nil }

    /// Первое чтение сразу, дальше — раз в минуту.
    public func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: MacTemperature.interval, leeway: .seconds(10))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    /// Выключили — опроса нет, история забыта (включат — начнётся заново).
    public func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.history = []
            DispatchQueue.main.async { self?.onUpdate?([]) }
        }
    }

    /// Одно чтение всех источников (на очереди монитора).
    public func readNow() -> MacTemperatureSample {
        dispatchPrecondition(condition: .onQueue(queue))
        let started = DispatchTime.now().uptimeNanoseconds
        let chip = sensors?.read().flatMap { MacTemperature.chip($0) }
        let sample = MacTemperatureSample(at: Date(), chipAverage: chip?.average, chipMax: chip?.max,
                                          battery: BatteryTemperature.read(), state: ProcessInfo.processInfo.thermalState)
        lastReadMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return sample
    }

    /// Для замера: синхронное чтение с очереди монитора.
    public func measureOnce() -> (sample: MacTemperatureSample, milliseconds: Double) {
        queue.sync { (readNow(), lastReadMilliseconds) }
    }

    private func tick() {
        history = MacTemperature.append(readNow(), to: history)
        let snapshot = history
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
    }
}
