import Foundation

/// Папка `~/Library/Application Support/MyClaude` и запись в неё — одна точка для патчера и ClaudeAX (ревизия WF247,
/// С5б). Права (аудит 10.10.2026, В2, быстрая часть): новые папки — 0700, файлы — 0600, от других учёток этого Мака.
/// Существующую папку `createDirectory` не трогает: у людей она остаётся с прежними правами (chmod — отдельным решением,
/// когда будет проверено, что лоадер Claude и PimpViewer читают её после смены).
public enum SupportFiles {
    /// Папку не переименовывать: лоадер смотрит именно в MyClaude.
    public static var directory: URL { Patcher.defaultSupportDirectory }
    public static let configFileName = "claude.json"
    public static let cssFileName = "claude.css"
    public static let injectFileName = "inject.js"
    public static let commandFileName = "command.json"
    /// Что и когда пропатчено (`ClaudePatcher.writeInstalled`): по нему статус, обновитель Claude и «новая установка».
    public static let installedFileName = "installed.json"
    public static let directoryPermissions = 0o700
    public static let filePermissions = 0o600

    /// Папка (и недостающие над ней) с правами 0700; есть — остаётся как есть.
    public static func ensureDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: directoryPermissions])
    }

    /// Запись через временный файл рядом и `rename(2)`: лоадер опрашивает файлы и не должен увидеть их наполовину
    /// записанными; tmp обязан лежать в той же папке, иначе rename не атомарен. Права ставятся при создании tmp
    /// (`open(2)` с `O_EXCL`) — файла с правами 0644 не бывает ни миллисекунды (#5558). Папки нет — заводится с 0700.
    public static func write(_ data: Data, to url: URL, tmp: URL? = nil, permissions: Int = filePermissions,
                             fileManager: FileManager = .default) throws {
        let tmp = tmp ?? url.appendingPathExtension("tmp")
        do {
            try create(tmp, data, permissions: permissions)
        } catch let error as POSIXError where error.code == .ENOENT {
            try ensureDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
            try create(tmp, data, permissions: permissions)
        }
        guard rename(tmp.path, url.path) == 0 else {
            let code = errno
            unlink(tmp.path)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// То же без броска: записалось ли.
    @discardableResult
    public static func writeAtomic(_ url: URL, _ data: Data, tmp: URL? = nil, permissions: Int = filePermissions) -> Bool {
        (try? write(data, to: url, tmp: tmp, permissions: permissions)) != nil
    }

    private static func create(_ url: URL, _ data: Data, permissions: Int) throws {
        unlink(url.path)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(permissions))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = 0
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count, let base = buffer.baseAddress {
                let written = Darwin.write(fd, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = errno
                    return
                }
                offset += written
            }
        }
        if close(fd) != 0, failure == 0 { failure = errno }
        guard failure == 0 else {
            unlink(url.path)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }
}
