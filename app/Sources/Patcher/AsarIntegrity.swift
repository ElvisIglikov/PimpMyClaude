import CryptoKit
import Foundation

// Второй замок целостности Electron 41+ (ревизия WF100, A2; критик WF101, C4). Кроме хэша в
// Info.plist (его патчер пересчитывает) Electron Framework может нести в секции
// `__DATA_CONST,__asar_integrity` свой digest словаря ElectronAsarIntegrity. Включит его Anthropic —
// новый хэш в Info.plist с ним не сойдётся, и пропатченный Claude не запустится, хотя подпись и
// хэш «прошли». Формат слота — Electron v44.4.3 `shell/common/asar/integrity_digest.mm`:
// 32 байта сторожевой строки, `used` (1 байт), `version` (1 байт), SHA256 (32 байта).
// Версия 1: SHA256 подряд по ключам словаря (сортировка NSLiteralSearch) — путь, `algorithm`, `hash`.
// С Claude 4.29 замок включён (#11144): патч пересчитывает digest под новый хэш и вписывает его в слот
// каждого среза до подписи. Отказ — версия слота не 1 или digest не сходится с Info.plist (формула
// не наша); секции нет (Electron < 41) — патчим как раньше; файл не читается или формат незнаком —
// тоже патчим, но пишем строку в журнал.

/// Что говорит Electron Framework про второй замок.
public enum AsarIntegrityVerdict: Equatable {
    /// Секции нет или во всех срезах `used = 0` — нынешний патч безопасен.
    case ok
    /// Замок включён, версия 1, digest каждого среза сходится с Info.plist — патч перепишет его
    /// под новый хэш (`writeAsarIntegrityDigest`).
    case digest
    /// Замок незнакомой версии или digest не сходится с Info.plist: пропатченный Claude не запустится — не патчить.
    case refuse(String)
    /// Прочитать не вышло или формат незнаком — не повод останавливать патч.
    case unknown(String)
}

extension Patcher {
    /// `Contents/Frameworks/Electron Framework.framework` внутри Claude.app.
    public static func electronFramework(of app: URL) -> URL {
        app.appendingPathComponent("Contents/Frameworks/Electron Framework.framework", isDirectory: true)
    }

    /// Словарь `ElectronAsarIntegrity` из `Contents/Info.plist` бандла; nil — нет файла или ключа.
    public static func asarIntegrity(of app: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["ElectronAsarIntegrity"] as? [String: Any]
    }

    /// Digest версии 1 — как `IsIntegrityDictionaryValid` в Electron; nil — у записи нет `algorithm` или `hash`.
    static func asarIntegrityDigest(_ integrity: [String: Any]) -> Data? {
        var bytes = Data()
        for key in integrity.keys.sorted(by: { ($0 as NSString).compare($1, options: .literal) == .orderedAscending }) {
            guard let entry = integrity[key] as? [String: Any], let algorithm = entry["algorithm"] as? String,
                  let hash = entry["hash"] as? String else { return nil }
            bytes.append(contentsOf: Array(key.utf8) + Array(algorithm.utf8) + Array(hash.utf8))
        }
        return Data(SHA256.hash(data: bytes))
    }

    /// Чистая проверка без побочных действий. `framework` — папка `.framework` (бинарь внутри
    /// ищется по её имени через симлинк `Versions/Current`) или сам бинарь; `integrity` — словарь
    /// `ElectronAsarIntegrity` того же бандла: с ним сверяется digest включённого замка. Файл 420 МБ
    /// целиком не читается: только заголовки, команды загрузки и 66 байт слота на каждый срез.
    public static func asarIntegrityVerdict(framework: URL, integrity: [String: Any]?) -> AsarIntegrityVerdict {
        let binary = frameworkBinary(framework)
        guard let handle = try? FileHandle(forReadingFrom: binary) else {
            return .unknown("не открывается \(binary.path)")
        }
        defer { try? handle.close() }
        return MachOIntegrity(handle: handle).verdict(digest: integrity.flatMap(asarIntegrityDigest))
    }

    /// Вписать digest словаря `integrity` в каждый включённый слот (версия 1), где он другой. Бинарь не
    /// правится на месте: клон рядом (APFS — мгновенно), запись, переименование поверх — подпись старого
    /// файла не ложится на новый. Звать после правки Info.plist и до подписи. Возвращает число
    /// переписанных срезов; замок выключен или бинарь не разобрать — 0 (разбор уже сказал своё).
    @discardableResult
    public static func writeAsarIntegrityDigest(framework: URL, integrity: [String: Any]) throws -> Int {
        let binary = frameworkBinary(framework)
        guard let handle = try? FileHandle(forReadingFrom: binary) else { return 0 }
        let slots = MachOIntegrity(handle: handle).slots()
        try? handle.close()
        guard !slots.isEmpty else { return 0 }
        guard let digest = asarIntegrityDigest(integrity) else {
            throw PatchError.tool(name: "Digest __asar_integrity", output: "в ElectronAsarIntegrity нет algorithm или hash")
        }
        let stale = slots.filter { $0.digest != digest }
        guard !stale.isEmpty else { return 0 }
        let temporary = binary.deletingLastPathComponent().appendingPathComponent(".\(binary.lastPathComponent).pimp-\(UUID().uuidString)")
        do {
            if clonefile(binary.path, temporary.path, 0) != 0 {
                try FileManager.default.copyItem(at: binary, to: temporary)
            }
            let writer = try FileHandle(forUpdating: temporary)
            defer { try? writer.close() }
            for slot in stale {
                try writer.seek(toOffset: slot.offset + UInt64(MachOIntegrity.slotHead))
                try writer.write(contentsOf: digest)
            }
            try writer.synchronize()
            guard rename(temporary.path, binary.path) == 0 else {
                throw PatchError.tool(name: "Digest __asar_integrity", output: String(cString: strerror(errno)))
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return stale.count
    }

    /// Бинарь фреймворка: папка `.framework` — по её имени через симлинк `Versions/Current`.
    private static func frameworkBinary(_ framework: URL) -> URL {
        var binary = framework
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: framework.path, isDirectory: &isDirectory), isDirectory.boolValue {
            binary = framework.appendingPathComponent(framework.deletingPathExtension().lastPathComponent)
        }
        return binary.resolvingSymlinksInPath()
    }
}

/// Разбор Mach-O ровно настолько, чтобы найти слот `__asar_integrity` в каждом срезе.
struct MachOIntegrity {
    static let sentinel = Array("AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A".utf8)
    static let slotHead = sentinel.count + 2 // сторожевая строка + used + version
    static let digestSize = 32

    private enum Slice {
        case absent, off
        /// `offset` — начало слота от начала файла, `digest` — его 32 байта.
        case on(version: UInt8, offset: UInt64, digest: Data)
        case unknown(String)
    }

    private struct Unreadable: Error { let why: String }

    let handle: FileHandle

    /// `digest` — digest словаря из Info.plist того же бандла (nil — словаря нет): включённый слот обязан
    /// с ним совпасть, иначе формула не наша и новый digest Electron не примет.
    func verdict(digest: Data?) -> AsarIntegrityVerdict {
        do {
            var used: [String] = []
            var foreign: [String] = []
            var unknown: [String] = []
            var on = false
            for slice in try sliceTable() {
                let label = slice.name.isEmpty ? "" : "срез \(slice.name): "
                switch self.slice(at: slice.offset, size: slice.size) {
                case .absent, .off: break
                case .on(let version, _, let slot):
                    on = true
                    if version != 1 { foreign.append(label + "версия \(version)") }
                    else if slot != digest { used.append(label + "digest не сходится с Info.plist") }
                case .unknown(let why): unknown.append(label + why)
                }
            }
            if !foreign.isEmpty {
                return .refuse("в Electron Framework проверка __asar_integrity незнакомой версии (\(foreign.joined(separator: "; ")))")
            }
            if !used.isEmpty {
                return .refuse("в Electron Framework включена проверка __asar_integrity, а \(used.joined(separator: "; "))")
            }
            if !unknown.isEmpty { return .unknown(unknown.joined(separator: "; ")) }
            return on ? .digest : .ok
        } catch let error as Unreadable {
            return .unknown(error.why)
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    /// Включённые слоты версии 1 — их переписывает `writeAsarIntegrityDigest`; бинарь не разобрать — пусто.
    func slots() -> [(offset: UInt64, digest: Data)] {
        guard let slices = try? sliceTable() else { return [] }
        return slices.compactMap { slice in
            guard case .on(1, let offset, let digest) = self.slice(at: slice.offset, size: slice.size) else { return nil }
            return (offset, digest)
        }
    }

    private func sliceTable() throws -> [(name: String, offset: UInt64, size: UInt64)] {
        let size = try handle.seekToEnd()
        let magic = try read(0, 4, size: size)
        switch be32(magic, 0) {
        case 0xCAFE_BABE, 0xCAFE_BABF:
            return try fatSlices(wide: be32(magic, 0) == 0xCAFE_BABF, size: size)
        default:
            return [("", 0, size)]
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
                        let slotSize = Self.slotHead + Self.digestSize
                        guard sectionSize >= UInt64(slotSize), offset + UInt64(slotSize) <= size else {
                            return .unknown("секция __asar_integrity за концом среза")
                        }
                        let slot = try read(base + offset, slotSize, size: fileSize)
                        guard Array(slot.prefix(Self.sentinel.count)) == Self.sentinel else {
                            return .unknown("незнакомый формат слота __asar_integrity")
                        }
                        let used = slot[slot.startIndex + Self.sentinel.count]
                        let version = slot[slot.startIndex + Self.sentinel.count + 1]
                        return used == 0 ? .off : .on(version: version, offset: base + offset, digest: Data(slot.suffix(Self.digestSize)))
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
