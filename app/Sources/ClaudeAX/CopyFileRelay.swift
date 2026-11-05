import AppKit
import Foundation

/// File clipboard writer used by the authenticated HTTP copy endpoint. No background pasteboard reads.
public enum CopyFileRelay {
    public static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// Путь просит любая страница (z5-r03; до WF117 — меткой в HTML-слое буфера, теперь — запросом `/copy-file`):
    /// скрытые папки и файлы (`.ssh`, `.aws`, `.gnupg`, `.config`…) и связки ключей и cookies Мака в буфер файлом
    /// не кладём.
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
