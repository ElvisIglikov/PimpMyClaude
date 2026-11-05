import Darwin
import Foundation
import IOKit

// Нагрузка процессора и видеокарты в панели у часов (#10308, слово Элвиса 19.10.2026: панель — как PimpTray на
// Windows, плитки «Процессор» и «Видеокарта» парой под температурой и памятью). Образец — память (`MacMemory.swift`).
//
// Откуда цифры (всё открытое, без прав):
//   • процессор — `host_statistics(HOST_CPU_LOAD_INFO)`: тики всех ядер «пользователь / система / простой / nice»
//     с запуска Мака; занятость — доля не-простоя в разнице двух опросов;
//   • видеокарта — IOKit, службы `IOAccelerator`, свойство `PerformanceStatistics` → «Device Utilization %» (на Apple
//     Silicon есть без прав; нет ключа — плитки нет, как температуры без датчика).
// Опрос раз в минуту на своей очереди; первое чтение — через 2 с после включения (процессору нужны два снимка);
// история — 180 точек (3 ч) в памяти и в `load-history.json`, как у температуры и памяти (#10215).

/// Одно чтение: занятость процессора и видеокарты, %; nil — не прочитали.
public struct MacLoadSample: Equatable, Codable {
    public let at: Date
    public let cpu: Double?
    public let gpu: Double?

    public init(at: Date, cpu: Double?, gpu: Double?) {
        self.at = at
        self.cpu = cpu
        self.gpu = gpu
    }

    public func value(_ kind: MacLoad.Kind) -> Double? { kind == .cpu ? cpu : gpu }
}

/// Чистая часть: проценты из сырых чисел, история, цвет, подпись (тесты `PanelLikeWindows10308Tests`).
public enum MacLoad {
    public enum Kind: Equatable { case cpu, gpu }

    public static let interval: TimeInterval = 60
    /// Первое чтение после включения: разница тиков за 2 с — живой процент сразу, а не через минуту.
    public static let firstDelay: TimeInterval = 2
    public static let window: TimeInterval = 3 * 3600
    public static let capacity = 180
    /// Разрыв линии: пропущено больше двух чтений (сон Мака, выключали и включали).
    public static let gap: TimeInterval = 150
    /// Ключ выключателя «Процессор и видеокарта в панели» (умолчание — включено, как у температуры и памяти).
    public static let enabledKey = "loadInPanel"
    /// Ключ видеокарты в `PerformanceStatistics`.
    public static let gpuKey = "Device Utilization %"

    /// Тики `host_cpu_load_info` (`natural_t`, растут с запуска Мака и переходят через ноль).
    public struct CPUTicks: Equatable {
        public var user: UInt32
        public var system: UInt32
        public var idle: UInt32
        public var nice: UInt32

        public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }
    }

    /// Занятость процессора между двумя снимками, %: (пользователь + система + nice) / все тики разницы. Счётчик
    /// перешёл через ноль — разница по модулю 2³² (`&-`); тиков за это время нет — nil.
    public static func cpuPercent(previous: CPUTicks, current: CPUTicks) -> Double? {
        let busy = Double(current.user &- previous.user) + Double(current.system &- previous.system)
            + Double(current.nice &- previous.nice)
        let total = busy + Double(current.idle &- previous.idle)
        guard total > 0 else { return nil }
        return Swift.min(100, Swift.max(0, busy / total * 100))
    }

    /// Занятость видеокарты, %: «Device Utilization %» самой занятой из служб `IOAccelerator` (у Мака с двумя
    /// видеокартами — та, что работает), зажим 0…100. Ключа нет ни у одной — nil.
    public static func gpuPercent(_ statistics: [[String: Any]]) -> Double? {
        let values = statistics.compactMap { ($0[gpuKey] as? NSNumber)?.doubleValue }.filter { $0.isFinite }
        guard let top = values.max() else { return nil }
        return Swift.min(100, Swift.max(0, top))
    }

    /// Цвет, как `Palette.ForLoad` у PimpTray: от 90 % красный, от 70 % жёлтый, ниже — зелёный.
    public static func health(_ percent: Double) -> MacHealth {
        if percent >= 90 { return .bad }
        if percent >= 70 { return .warn }
        return .good
    }

    /// «26 %» — число плитки, неразрывным пробелом.
    public static func percentText(_ value: Double) -> String { "\(Int(value.rounded()))\u{00A0}%" }

    /// Новая точка в истории: старше 3 ч и сверх 180 — прочь; точка без обоих чисел не добавляется.
    public static func append(_ sample: MacLoadSample, to history: [MacLoadSample]) -> [MacLoadSample] {
        guard sample.cpu != nil || sample.gpu != nil else { return history }
        var next = history.filter { sample.at.timeIntervalSince($0.at) < window && $0.at <= sample.at }
        next.append(sample)
        if next.count > capacity { next.removeFirst(next.count - capacity) }
        return next
    }

    /// Точки одного датчика: время и процент, без пропусков.
    public static func series(_ history: [MacLoadSample], _ kind: Kind) -> [(at: Date, value: Double)] {
        history.compactMap { sample in sample.value(kind).map { (at: sample.at, value: $0) } }
    }

    /// Куски линии без разрывов: индексы точек `series`.
    public static func segments(_ dates: [Date]) -> [[Int]] {
        var result: [[Int]] = []
        for index in dates.indices {
            if index > 0, dates[index].timeIntervalSince(dates[index - 1]) <= gap, !result.isEmpty {
                result[result.count - 1].append(index)
            } else {
                result.append([index])
            }
        }
        return result
    }

    /// Подпись под графиком, как у температуры: «за 3 ч: 12–68 %», после перезапуска — «за 9 мин: …»; одно число —
    /// «за 9 мин: 26 %». Точек меньше двух — пусто.
    public static func caption(_ history: [MacLoadSample], _ kind: Kind) -> String {
        let points = series(history, kind)
        guard points.count > 1, let first = points.first, let last = points.last else { return "" }
        let values = points.map { Int($0.value.rounded()) }
        guard let low = values.min(), let high = values.max() else { return "" }
        let span = Int((last.at.timeIntervalSince(first.at) / 60).rounded())
        let when = span >= 175 ? "за 3 ч" : span >= 60 ? "за \(span / 60) ч \(span % 60) мин" : "за \(Swift.max(span, 1)) мин"
        return low == high ? "\(when): \(low)\u{00A0}%" : "\(when): \(low)–\(high)\u{00A0}%"
    }

    /// Подсказка плитки: «Процессор: 26 % · опрос раз в минуту».
    public static func help(_ history: [MacLoadSample], _ kind: Kind) -> String {
        let name = kind == .cpu ? "Процессор" : "Видеокарта"
        guard let value = history.last?.value(kind) else { return name }
        return "\(name): \(percentText(value)) · опрос раз в минуту"
    }
}

/// Чтение: `host_statistics` и IOKit.
enum LoadReader {
    /// Порт хоста — один раз: `mach_host_self()` на каждом опросе копил бы права на порт.
    private static let host = mach_host_self()

    static func cpuTicks() -> MacLoad.CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return MacLoad.CPUTicks(user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
    }

    /// `PerformanceStatistics` всех служб `IOAccelerator`; итератор и службы отпускаются.
    static func gpuStatistics() -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)
            if let statistics = property?.takeRetainedValue() as? [String: Any] { result.append(statistics) }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }
}

/// Опрос раз в минуту на своей очереди, как температура: `onUpdate` зовётся на главном потоке. История — в памяти и
/// в файле (`file`): после перезапуска Пимпа график продолжается.
public final class MacLoadMonitor {
    private let queue = DispatchQueue(label: "pimp.load", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var history: [MacLoadSample] = []
    /// Прошлый снимок тиков процессора — опорный для следующего процента.
    private var ticks: MacLoad.CPUTicks?
    private let file: ChartHistoryFile<MacLoadSample>?
    public var onUpdate: (([MacLoadSample]) -> Void)?

    public init(file: URL? = nil) { self.file = file.map(ChartHistoryFile.init(url:)) }

    public var running: Bool { timer != nil }

    /// Опорные тики — сразу, первое чтение — через 2 с, дальше раз в минуту.
    public func start() {
        guard timer == nil else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            self.ticks = LoadReader.cpuTicks()
            guard let file = self.file, self.history.isEmpty else { return }
            let now = Date()
            self.history = file.load()
                .filter { now.timeIntervalSince($0.at) < MacLoad.window && $0.at <= now && ($0.cpu != nil || $0.gpu != nil) }
                .suffix(MacLoad.capacity).map { $0 }
            let snapshot = self.history
            if !snapshot.isEmpty { DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) } }
        }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + MacLoad.firstDelay, repeating: MacLoad.interval, leeway: .seconds(10))
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
            self?.ticks = nil
            self?.file?.save([])
            DispatchQueue.main.async { self?.onUpdate?([]) }
        }
    }

    private func tick() {
        let now = LoadReader.cpuTicks()
        let cpu = ticks.flatMap { previous in now.flatMap { MacLoad.cpuPercent(previous: previous, current: $0) } }
        if let now = now { ticks = now }
        let gpu = MacLoad.gpuPercent(LoadReader.gpuStatistics())
        history = MacLoad.append(MacLoadSample(at: Date(), cpu: cpu, gpu: gpu), to: history)
        let snapshot = history
        file?.save(snapshot)
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
    }
}
