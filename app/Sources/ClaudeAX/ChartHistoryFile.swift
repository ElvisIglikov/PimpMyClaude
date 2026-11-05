import Foundation

// MARK: история графиков на диске (#10215)

/// Температура и память копили 3 ч только в памяти: Пимп перезапустился (падение 18.10 22:15, #10207) — график начинался
/// заново, «за 9 мин: 34–56°» (слово Элвиса 18.10.2026: «этот период температуры что-то мне не нравится, слишком он
/// маленький»). Теперь точки лежат в `Application Support/MyClaude/<имя>.json` и после перезапуска читаются обратно;
/// старше окна (3 ч) отбрасываются, пропуск между запусками график рисует разрывом, как сон Мака.
public struct ChartHistoryFile<Row: Codable> {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Нет файла или мусор — пусто.
    public func load() -> [Row] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Row].self, from: data)) ?? []
    }

    /// Пишет целиком атомарно; не вышло — молча (история не важнее работы панели).
    public func save(_ rows: [Row]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Строка файла температуры: `ProcessInfo.ThermalState` — числом.
struct TemperatureRow: Codable {
    let at: Date
    let chipAverage: Double?
    let chipMax: Double?
    let battery: Double?
    let state: Int

    init(_ sample: MacTemperatureSample) {
        at = sample.at
        chipAverage = sample.chipAverage
        chipMax = sample.chipMax
        battery = sample.battery
        state = sample.state.rawValue
    }

    var sample: MacTemperatureSample {
        MacTemperatureSample(at: at, chipAverage: chipAverage, chipMax: chipMax, battery: battery,
                             state: ProcessInfo.ThermalState(rawValue: state) ?? .nominal)
    }
}

/// Строка файла памяти.
struct MemoryRow: Codable {
    let at: Date
    let pressure: Double?
    let level: Int?
    let used: UInt64?
    let total: UInt64
    let swap: UInt64?

    init(_ sample: MacMemorySample) {
        at = sample.at
        pressure = sample.pressure
        level = sample.level?.rawValue
        used = sample.used
        total = sample.total
        swap = sample.swap
    }

    var sample: MacMemorySample {
        MacMemorySample(at: at, pressure: pressure, level: level.flatMap(MemoryPressureLevel.init(rawValue:)),
                        used: used, total: total, swap: swap)
    }
}
