import Foundation

// Второй замок целостности Electron 41+ (ревизия WF100, A2; критик WF101, C4). Кроме хэша в
// Info.plist (его патчер пересчитывает) Electron Framework может нести в секции
// `__DATA_CONST,__asar_integrity` свой digest словаря ElectronAsarIntegrity. Включит его Anthropic —
// новый хэш в Info.plist с ним не сойдётся, и пропатченный Claude не запустится, хотя подпись и
// хэш «прошли». Формат слота — Electron v44.4.3 `shell/common/asar/integrity_digest.mm`:
// 32 байта сторожевой строки, `used` (1 байт), `version` (1 байт), SHA256 (32 байта).
// Отказ — только при доказанном `used ≠ 0`; секции нет (Electron < 41) — патчим как раньше;
// файл не читается или формат незнаком — тоже патчим, но пишем строку в журнал.

/// Что говорит Electron Framework про второй замок.
public enum AsarIntegrityVerdict: Equatable {
    /// Секции нет или во всех срезах `used = 0` — нынешний патч безопасен.
    case ok
    /// Хоть в одном срезе `used ≠ 0`: пропатченный Claude не запустится — не патчить.
    case refuse(String)
    /// Прочитать не вышло или формат незнаком — не повод останавливать патч.
    case unknown(String)
}

extension Patcher {
    /// `Contents/Frameworks/Electron Framework.framework` внутри Claude.app.
    public static func electronFramework(of app: URL) -> URL {
        app.appendingPathComponent("Contents/Frameworks/Electron Framework.framework", isDirectory: true)
    }

    /// Чистая проверка без побочных действий. `framework` — папка `.framework` (бинарь внутри
    /// ищется по её имени через симлинк `Versions/Current`) или сам бинарь. Файл 420 МБ целиком
    /// не читается: только заголовки, команды загрузки и 34 байта слота на каждый срез.
    public static func asarIntegrityVerdict(framework: URL) -> AsarIntegrityVerdict {
        var binary = framework
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: framework.path, isDirectory: &isDirectory), isDirectory.boolValue {
            binary = framework.appendingPathComponent(framework.deletingPathExtension().lastPathComponent)
        }
        binary = binary.resolvingSymlinksInPath()
        guard let handle = try? FileHandle(forReadingFrom: binary) else {
            return .unknown("не открывается \(binary.path)")
        }
        defer { try? handle.close() }
        return MachOIntegrity(handle: handle).verdict()
    }
}

/// Разбор Mach-O ровно настолько, чтобы найти слот `__asar_integrity` в каждом срезе.
struct MachOIntegrity {
    static let sentinel = Array("AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A".utf8)
    static let slotHead = sentinel.count + 2 // сторожевая строка + used + version

    private enum Slice {
        case absent, off
        case on(version: UInt8)
        case unknown(String)
    }

    private struct Unreadable: Error { let why: String }

    let handle: FileHandle

    func verdict() -> AsarIntegrityVerdict {
        do {
            let size = try handle.seekToEnd()
            let magic = try read(0, 4, size: size)
            let slices: [(name: String, offset: UInt64, size: UInt64)]
            switch be32(magic, 0) {
            case 0xCAFE_BABE, 0xCAFE_BABF:
                slices = try fatSlices(wide: be32(magic, 0) == 0xCAFE_BABF, size: size)
            default:
                slices = [("", 0, size)]
            }
            var used: [String] = []
            var unknown: [String] = []
            for slice in slices {
                let label = slice.name.isEmpty ? "" : "срез \(slice.name): "
                switch self.slice(at: slice.offset, size: slice.size) {
                case .absent, .off: break
                case .on(let version): used.append("\(slice.name.isEmpty ? "" : "срез \(slice.name), ")версия \(version)")
                case .unknown(let why): unknown.append(label + why)
                }
            }
            if !used.isEmpty {
                return .refuse("в Electron Framework включена проверка __asar_integrity (\(used.joined(separator: "; ")))")
            }
            if !unknown.isEmpty { return .unknown(unknown.joined(separator: "; ")) }
            return .ok
        } catch let error as Unreadable {
            return .unknown(error.why)
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    /// fat-заголовок big-endian: `fat_arch` 20 байт, `fat_arch_64` 32 байта.
    private func fatSlices(wide: Bool, size: UInt64) throws -> [(name: String, offset: UInt64, size: UInt64)] {
        let count = be32(try read(4, 4, size: size), 0)
        // 0xCAFEBABE — ещё и магия class-файла Java; там на этом месте версия, а не 1–16 срезов.
        guard count > 0, count <= 16 else { throw Unreadable(why: "fat-заголовок: \(count) срезов") }
        let entry = wide ? 32 : 20
        let table = try read(8, entry * Int(count), size: size)
        return (0..<Int(count)).map { i in
            let at = i * entry
            let offset = wide ? be64(table, at + 8) : UInt64(be32(table, at + 8))
            let length = wide ? be64(table, at + 16) : UInt64(be32(table, at + 12))
            return (Self.cpuName(be32(table, at)), offset, length)
        }
    }

    private func slice(at base: UInt64, size: UInt64) -> Slice {
        do {
            let fileSize = try handle.seekToEnd()
            guard base.addingReportingOverflow(size).partialValue <= fileSize, size >= 32 else {
                return .unknown("срез за концом файла")
            }
            let header = try read(base, 32, size: fileSize)
            guard le32(header, 0) == 0xFEED_FACF else { return .unknown("не 64-битный Mach-O") }
            let commands = Int(le32(header, 16))
            let length = Int(le32(header, 20))
            guard UInt64(length) <= size - 32, length <= 16 << 20 else { return .unknown("команды загрузки за концом среза") }
            let table = try read(base + 32, length, size: fileSize)
            var at = 0
            for _ in 0..<commands {
                guard at + 8 <= length else { return .unknown("команды загрузки обрезаны") }
                let command = le32(table, at)
                let commandSize = Int(le32(table, at + 4))
                guard commandSize >= 8, at + commandSize <= length else { return .unknown("битая команда загрузки") }
                if command == 0x19 /* LC_SEGMENT_64 */, commandSize >= 72, Self.name(table, at + 8) == "__DATA_CONST" {
                    let sections = Int(le32(table, at + 64))
                    guard 72 + sections * 80 <= commandSize else { return .unknown("битый сегмент __DATA_CONST") }
                    for s in 0..<sections {
                        let section = at + 72 + s * 80
                        guard Self.name(table, section) == "__asar_integrity" else { continue }
                        let sectionSize = le64(table, section + 40)
                        let offset = UInt64(le32(table, section + 48))
                        guard sectionSize >= UInt64(Self.slotHead), offset + UInt64(Self.slotHead) <= size else {
                            return .unknown("секция __asar_integrity за концом среза")
                        }
                        let slot = try read(base + offset, Self.slotHead, size: fileSize)
                        guard Array(slot.prefix(Self.sentinel.count)) == Self.sentinel else {
                            return .unknown("незнакомый формат слота __asar_integrity")
                        }
                        let used = slot[slot.startIndex + Self.sentinel.count]
                        let version = slot[slot.startIndex + Self.sentinel.count + 1]
                        return used == 0 ? .off : .on(version: version)
                    }
                }
                at += commandSize
            }
            return .absent
        } catch let error as Unreadable {
            return .unknown(error.why)
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    private func read(_ offset: UInt64, _ count: Int, size: UInt64) throws -> Data {
        guard offset.addingReportingOverflow(UInt64(count)).partialValue <= size else {
            throw Unreadable(why: "файл обрезан")
        }
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw Unreadable(why: "файл обрезан") }
        return data
    }

    private static func cpuName(_ type: UInt32) -> String {
        switch type {
        case 0x0100_000C: return "arm64"
        case 0x0100_0007: return "x86_64"
        default: return String(format: "cpu 0x%x", type)
        }
    }

    /// Имя сегмента или секции: 16 байт, добито нулями (у `__asar_integrity` нуля нет — ровно 16).
    private static func name(_ data: Data, _ at: Int) -> String {
        let bytes = data[(data.startIndex + at)..<(data.startIndex + at + 16)].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func be32(_ d: Data, _ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 << 8 | UInt32(d[d.startIndex + at + $1]) } }
    private func be64(_ d: Data, _ at: Int) -> UInt64 { (0..<8).reduce(0) { $0 << 8 | UInt64(d[d.startIndex + at + $1]) } }
    private func le32(_ d: Data, _ at: Int) -> UInt32 { (0..<4).reversed().reduce(0) { $0 << 8 | UInt32(d[d.startIndex + at + $1]) } }
    private func le64(_ d: Data, _ at: Int) -> UInt64 { (0..<8).reversed().reduce(0) { $0 << 8 | UInt64(d[d.startIndex + at + $1]) } }
}
