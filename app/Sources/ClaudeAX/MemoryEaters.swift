import Darwin
import Foundation

// Кто съел память (#11620, слово Элвиса 04.11.2026 08:57: «оперативной памяти не хватает. В чём причина, не могу
// понять? Может быть, что-то лишнее открыто…»). Под графиком «Нагрузки на память» — три главных пожирателя: ВМ, Claude
// Code ×N, Chrome — чтобы причина была видна, а не угадывалась. Объём — как в «Мониторинге системы» (phys_footprint),
// не RSS: общие библиотеки у 29 claude RSS посчитал бы 29 раз. Процессы чужих пользователей (root) не читаются — мимо.

public struct MemoryEater: Equatable {
    public let name: String
    public let bytes: UInt64
    public let count: Int

    public init(name: String, bytes: UInt64, count: Int) {
        self.name = name
        self.bytes = bytes
        self.count = count
    }
}

public enum MemoryEaters {
    public static let topCount = 3
    /// Имена, понятнее пути: ВМ UTM (QEMU) и терминальный Claude Code (`…/claude-code/<версия>/…/claude.app`), чтобы
    /// не путать с приложением Claude.
    static let names: [String: String] = ["UTM": "ВМ UTM", "claude": "Claude Code"]

    /// Путь программы → имя (`MacHeatWarn.humanName`, помощники — в одну строку с приложением).
    public static func name(_ path: String) -> String {
        let human = MacHeatWarn.humanName(path)
        return names[human] ?? human
    }

    /// Сложить по имени; по убыванию, равные — в порядке встречи.
    public static func group(_ processes: [(path: String, bytes: UInt64)]) -> [MemoryEater] {
        var sums: [String: (bytes: UInt64, count: Int)] = [:]
        var order: [String] = []
        for process in processes where process.bytes > 0 && !process.path.isEmpty {
            let key = name(process.path)
            if sums[key] == nil { order.append(key) }
            let old = sums[key] ?? (0, 0)
            sums[key] = (old.bytes + process.bytes, old.count + 1)
        }
        return order.enumerated()
            .map { (offset: $0.offset, eater: MemoryEater(name: $0.element, bytes: sums[$0.element]?.bytes ?? 0,
                                                          count: sums[$0.element]?.count ?? 0)) }
            .sorted { $0.eater.bytes != $1.eater.bytes ? $0.eater.bytes > $1.eater.bytes : $0.offset < $1.offset }
            .map(\.eater)
    }

    /// «Больше всех: ВМ UTM 10.1 ГБ · Claude Code ×29 5.0 ГБ · Chrome 3.7 ГБ»; пусто — nil.
    public static func text(_ eaters: [MemoryEater]) -> String? {
        let top = eaters.prefix(topCount).filter { $0.bytes > 0 }
        guard !top.isEmpty else { return nil }
        let parts = top.map { eater in
            (eater.count > 1 ? "\(eater.name) ×\(eater.count)" : eater.name) + " " + MacMemory.gigabytes(eater.bytes) + "\u{00A0}ГБ"
        }
        return "Больше всех: " + parts.joined(separator: " · ")
    }

    /// Все свои процессы: путь и phys_footprint. Не на главном потоке (≈ 600 процессов, миллисекунды).
    public static func read() -> [MemoryEater] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let filled = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard filled > 0 else { return [] }
        var processes: [(path: String, bytes: UInt64)] = []
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(min(filled, capacity)) where pid > 0 {
            var info = rusage_info_v4()
            let read = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard read == 0, info.ri_phys_footprint > 0 else { continue }
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            processes.append((String(cString: buffer), info.ri_phys_footprint))
        }
        return group(processes)
    }
}
