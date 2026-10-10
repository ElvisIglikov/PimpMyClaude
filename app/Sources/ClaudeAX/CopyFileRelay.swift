import AppKit
import Foundation

/// File clipboard writer used by the authenticated HTTP copy endpoint. No background pasteboard reads.
public enum CopyFileRelay {
    public static let markStart = "<!--pimpmyclaude:copy-file:"
    public static let markEnd = "-->"
    public static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// Путь из HTML-слоя буфера; nil — метки нет (обычная копия), метка битая, путь не абсолютный
    /// или закрытый (`isRefused`).
    public static func path(inHTML html: String,
                            home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String? {
        guard let start = html.range(of: markStart) else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: markEnd) else { return nil }
        let encoded = String(rest[..<end.lowerBound])
        guard !encoded.isEmpty, let path = encoded.removingPercentEncoding, path.hasPrefix("/"),
              !isRefused(path, home: home) else { return nil }
        return path
    }

    /// Метку может положить любая страница своим обработчиком copy (z5-r03): скрытые папки и файлы
    /// (`.ssh`, `.aws`, `.gnupg`, `.config`…) и связки ключей и cookies Мака в буфер файлом не кладём.
    /// Весь `~/Library` не закрыт: где Claude хранит вложения чатов, не проверено.
    static func isRefused(_ path: String, home: String) -> Bool {
        if path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return true }
        let full = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
        let base = URL(fileURLWithPath: home).standardizedFileURL.path.lowercased()
        return ["Library/Keychains", "Library/Cookies"].contains { folder in
            let closed = (base as NSString).appendingPathComponent(folder.lowercased())
            return full == closed || full.hasPrefix(closed + "/")
        }
    }

    /// Файл в буфер тремя слоями одного элемента — как после «Скопировать» в Finder.
    @discardableResult
    public static func write(path: String, to pasteboard: NSPasteboard) -> Bool {
        let url = URL(fileURLWithPath: path)
        pasteboard.clearContents()
        let fileURL = pasteboard.setString(url.absoluteString, forType: .fileURL)
        let names = pasteboard.setPropertyList([path], forType: filenamesType)
        let text = pasteboard.setString(path, forType: .string)
        return fileURL && names && text
    }
}
