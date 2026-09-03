import CryptoKit
import Foundation

// Формат asar: 4 числа UInt32LE (pickle), затем JSON-хедер, затем данные файлов подряд.
// Порт claude-patch/patch-claude.mjs (readAsar / buildAsarPrefix / patchAsarFile) 1:1.
// Хедер парсится в NSMutableDictionary: нужны ссылочные узлы, чтобы двигать смещения на месте.

/// Что нашли в архиве, не меняя его.
public struct AsarStatus {
    /// Главный сценарий из package.json → "main" (например `.vite/build/index.pre.js`).
    public let mainPath: String
    /// Версия лоадера MyClaude в главном сценарии; 0 — лоадера нет.
    public let loaderVersion: Int
    /// sha256 JSON-хедера — ровно то, что лежит в Info.plist → ElectronAsarIntegrity.
    public let headerSHA256: String
}

/// Итог записи архива.
public struct AsarPatchResult {
    public let changed: Bool
    public let mainPath: String
    public let headerSHA256: String
}

public enum AsarError: LocalizedError {
    case tooSmall(URL)
    case badHeader(URL)
    case missingFile(String)
    case notAPackedFile(String)
    case noMainField
    case notElectronMain(String)
    case sharedData(String)
    case loaderNotFoundAfterRebuild
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .tooSmall(let url): return "\(url.lastPathComponent) слишком мал для asar"
        case .badHeader(let url): return "не читается заголовок \(url.lastPathComponent)"
        case .missingFile(let path): return "в app.asar нет файла \(path)"
        case .notAPackedFile(let path): return "\(path) — не упакованный файл"
        case .noMainField: return "в package.json нет поля main"
        case .notElectronMain(let path): return "\(path) не похож на главный сценарий Electron — патчить вслепую не буду"
        case .sharedData(let path): return "\(path) делит данные с другим файлом архива — патчить не буду"
        case .loaderNotFoundAfterRebuild: return "после пересборки лоадер в архиве не найден"
        case .writeFailed(let why): return "не записать app.asar: \(why)"
        }
    }
}

enum Asar {
    static let loaderVersion = 6
    static let markStart = "/* [MyClaude:v\(loaderVersion):start] */"
    static let markEnd = "/* [MyClaude:v\(loaderVersion):end] */"

    // ------------------------------------------------------------------ чтение

    struct Archive {
        let data: Data              // mappedIfSafe — архив 39 МБ в память целиком не тянем
        let header: NSMutableDictionary
        let headerJSON: Data        // байты хедера ровно как в файле
        let dataOffset: Int         // 8 + headerSize
    }

    static func read(_ url: URL) throws -> Archive {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 16 else { throw AsarError.tooSmall(url) }
        let headerSize = u32(data, 4)
        let jsonSize = u32(data, 12)
        guard jsonSize > 0, 16 + jsonSize <= data.count, headerSize + 8 <= data.count else { throw AsarError.badHeader(url) }
        let headerJSON = data.subdata(in: (data.startIndex + 16)..<(data.startIndex + 16 + jsonSize))
        guard let header = (try? JSONSerialization.jsonObject(with: headerJSON, options: [.mutableContainers])) as? NSMutableDictionary else {
            throw AsarError.badHeader(url)
        }
        return Archive(data: data, header: header, headerJSON: headerJSON, dataOffset: 8 + headerSize)
    }

    /// Запись хедера обратно: pickle-префикс + JSON + выравнивание нулями до 4 байт.
    static func prefix(for header: NSDictionary) throws -> (bytes: Data, headerJSON: Data) {
        // .sortedKeys — чтобы одинаковый вход давал одинаковый хэш (JS полагается на порядок вставки).
        let headerJSON = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys, .withoutEscapingSlashes])
        let padding = (4 - ((8 + headerJSON.count) % 4)) % 4
        let headerSize = 8 + headerJSON.count + padding
        var bytes = Data(capacity: 16 + headerJSON.count + padding)
        appendU32(&bytes, 4)
        appendU32(&bytes, headerSize)
        appendU32(&bytes, headerSize - 4)
        appendU32(&bytes, headerJSON.count)
        bytes.append(headerJSON)
        if padding > 0 { bytes.append(Data(count: padding)) }
        return (bytes, headerJSON)
    }

    static func lookup(_ header: NSDictionary, _ posixPath: String) throws -> NSMutableDictionary {
        var node: NSDictionary = header
        for component in posixPath.split(separator: "/") {
            guard let files = node["files"] as? NSDictionary,
                  let next = files[String(component)] as? NSMutableDictionary else { throw AsarError.missingFile(posixPath) }
            node = next
        }
        guard let entry = node as? NSMutableDictionary else { throw AsarError.missingFile(posixPath) }
        if entry["files"] != nil || truthy(entry["link"]) || truthy(entry["unpacked"]) { throw AsarError.notAPackedFile(posixPath) }
        return entry
    }

    /// Обход всех упакованных файлов (без каталогов, симлинков и unpacked).
    static func walkPacked(_ node: NSDictionary, _ body: (NSMutableDictionary) throws -> Void) rethrows {
        guard let files = node["files"] as? NSDictionary else { return }
        for value in files.allValues {
            guard let entry = value as? NSMutableDictionary else { continue }
            if entry["files"] != nil { try walkPacked(entry, body) }
            else if !truthy(entry["link"]), !truthy(entry["unpacked"]) { try body(entry) }
        }
    }

    static func content(_ archive: Archive, _ entry: NSDictionary) throws -> Data {
        let start = archive.data.startIndex + archive.dataOffset + intValue(entry["offset"])
        let end = start + intValue(entry["size"])
        // Битый или усечённый архив: subdata за концом файла — крэш, а не ошибка.
        guard start >= archive.data.startIndex, end <= archive.data.endIndex else { throw AsarError.badHeader(URL(fileURLWithPath: "app.asar")) }
        return archive.data.subdata(in: start..<end)
    }

    static func content(_ archive: Archive, path: String) throws -> Data {
        try content(archive, try lookup(archive.header, path))
    }

    /// Главный сценарий берём из package.json внутри архива: в 1.40609.1 это
    /// .vite/build/index.pre.js, раньше был index.js — путь не хардкодим.
    static func mainEntryPath(_ archive: Archive) throws -> String {
        let raw = try content(archive, path: "package.json")
        guard let pkg = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let main = pkg["main"] as? String, !main.isEmpty else { throw AsarError.noMainField }
        return main.hasPrefix("./") ? String(main.dropFirst(2)) : main
    }

    // ------------------------------------------------------------------ лоадер

    private static let startMarkPattern = try! NSRegularExpression(pattern: #"/\* \[MyClaude:v(\d+):start\] \*/"#)
    private static let wholeLoaderPattern = try! NSRegularExpression(
        pattern: #"^/\* \[MyClaude:v\d+:start\] \*/[\s\S]*?/\* \[MyClaude:v\d+:end\] \*/\n?"#)

    static func loaderVersion(of source: String) -> Int {
        let range = NSRange(source.startIndex..., in: source)
        guard let m = startMarkPattern.firstMatch(in: source, range: range),
              let digits = Range(m.range(at: 1), in: source) else { return 0 }
        return Int(source[digits]) ?? 0
    }

    static func stripLoader(_ source: String) -> String {
        let range = NSRange(source.startIndex..., in: source)
        guard let m = wholeLoaderPattern.firstMatch(in: source, range: range),
              let whole = Range(m.range, in: source) else { return source }
        return String(source[whole.upperBound...])
    }

    // ------------------------------------------------------------------ integrity

    static func fileIntegrity(_ data: Data, blockSize: Int = 4 * 1024 * 1024) -> NSMutableDictionary {
        var blocks: [String] = []
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(offset + blockSize, data.endIndex)
            blocks.append(sha256Hex(data[offset..<end]))
            offset = end
        }
        return ["algorithm": "SHA256", "hash": sha256Hex(data), "blockSize": blockSize, "blocks": blocks]
    }

    // ------------------------------------------------------------------ статус и патч

    static func status(of url: URL) throws -> AsarStatus {
        let archive = try read(url)
        let mainPath = try mainEntryPath(archive)
        let source = String(decoding: try content(archive, path: mainPath), as: UTF8.self)
        return AsarStatus(mainPath: mainPath, loaderVersion: loaderVersion(of: source), headerSHA256: sha256Hex(archive.headerJSON))
    }

    /// Поставить лоадер v6 в главный сценарий. Идемпотентно: v6 уже стоит — ничего не пишем.
    static func patch(_ url: URL) throws -> AsarPatchResult {
        try rewriteMain(url) { source in
            if loaderVersion(of: source) == loaderVersion { return nil }
            let clean = stripLoader(source)
            guard clean.contains("require("), clean.contains("electron") else { throw AsarError.notElectronMain("главный сценарий") }
            return claudeLoaderSource + clean
        }
    }

    /// Снять лоадер, не трогая ничего больше. Нужен тесту: копия живого app.asar уже пропатчена,
    /// а прогнать надо именно установку. В приложении откат делается из бэкапа.
    @discardableResult
    static func removeLoader(_ url: URL) throws -> AsarPatchResult {
        try rewriteMain(url) { source in
            loaderVersion(of: source) == 0 ? nil : stripLoader(source)
        }
    }

    /// Переписать главный сценарий: сдвинуть смещения всех файлов правее, пересчитать хэши, собрать архив заново.
    /// `transform` возвращает nil, если менять нечего.
    static func rewriteMain(_ url: URL, transform: (String) throws -> String?) throws -> AsarPatchResult {
        let archive = try read(url)
        let mainPath = try mainEntryPath(archive)
        let entry = try lookup(archive.header, mainPath)
        let source = String(decoding: try content(archive, entry), as: UTF8.self)
        guard let rewritten = try transform(source) else {
            return AsarPatchResult(changed: false, mainPath: mainPath, headerSHA256: sha256Hex(archive.headerJSON))
        }

        let targetOffset = intValue(entry["offset"])
        let targetSize = intValue(entry["size"])
        // asar дедуплицирует одинаковые файлы: два входа могут делить одно смещение.
        // Если бы кто-то делил его с главным сценарием, его размер и хэш протухли бы.
        try walkPacked(archive.header) { candidate in
            if candidate === entry { return }
            let offset = intValue(candidate["offset"])
            if offset >= targetOffset && offset < targetOffset + targetSize { throw AsarError.sharedData(mainPath) }
        }

        let replacement = Data(rewritten.utf8)
        let delta = replacement.count - targetSize
        walkPacked(archive.header) { candidate in
            let offset = intValue(candidate["offset"])
            if offset > targetOffset { candidate["offset"] = String(offset + delta) }
        }
        entry["size"] = replacement.count
        let blockSize = (entry["integrity"] as? NSDictionary).map { intValue($0["blockSize"]) } ?? 0
        entry["integrity"] = fileIntegrity(replacement, blockSize: blockSize > 0 ? blockSize : 4 * 1024 * 1024)

        let (prefixBytes, headerJSON) = try prefix(for: archive.header)
        try write(url: url, prefix: prefixBytes, archive: archive, targetOffset: targetOffset, targetSize: targetSize, replacement: replacement)

        // Перечитываем с диска: главный сценарий должен читаться по новым смещениям ровно тем, что записали.
        let written = try content(read(url), path: mainPath)
        guard written == replacement else { throw AsarError.loaderNotFoundAfterRebuild }
        return AsarPatchResult(changed: true, mainPath: mainPath, headerSHA256: sha256Hex(headerJSON))
    }

    private static func write(url: URL, prefix: Data, archive: Archive, targetOffset: Int, targetSize: Int, replacement: Data) throws {
        let temporary = URL(fileURLWithPath: url.path + ".\(getpid()).tmp")
        try? FileManager.default.removeItem(at: temporary)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                             attributes: [.posixPermissions: NSNumber(value: Int16(0o644))]) else {
            throw AsarError.writeFailed("не создать \(temporary.lastPathComponent) — нет прав на Contents/Resources")
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            let body = archive.data.startIndex + archive.dataOffset
            try handle.write(contentsOf: prefix)
            try handle.write(contentsOf: archive.data[body..<(body + targetOffset)])
            try handle.write(contentsOf: replacement)
            try handle.write(contentsOf: archive.data[(body + targetOffset + targetSize)...])
            try handle.close()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw AsarError.writeFailed(error.localizedDescription)
        }
        // rename(2) — как fs.renameSync в mjs: подмена атомарная, старый файл не исчезает при сбое.
        if rename(temporary.path, url.path) != 0 {
            let why = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw AsarError.writeFailed(why)
        }
    }
}

// ------------------------------------------------------------------ мелочи

func sha256Hex<D: DataProtocol>(_ data: D) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// JS-семантика `!value`: nil, false, 0 и "" — ложь.
func truthy(_ value: Any?) -> Bool {
    guard let value = value, !(value is NSNull) else { return false }
    if let number = value as? NSNumber { return number.boolValue }
    if let string = value as? String { return !string.isEmpty }
    return true
}

/// В asar `offset` — строка, `size` — число; JS обходится Number(), тут одна функция на оба.
func intValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String { return Int(string) ?? 0 }
    return 0
}

private func u32(_ data: Data, _ offset: Int) -> Int {
    let base = data.startIndex + offset
    return Int(UInt32(data[base]) | UInt32(data[base + 1]) << 8 | UInt32(data[base + 2]) << 16 | UInt32(data[base + 3]) << 24)
}

private func appendU32(_ data: inout Data, _ value: Int) {
    var little = UInt32(value).littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}
