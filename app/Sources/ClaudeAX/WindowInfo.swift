import CoreGraphics
import Foundation

/// Запись оконного сервера (`CGWindowListCopyWindowInfo`) одним разбором (ревизия WF247, Z7-DU4): владелец, номер,
/// слой, прозрачность и рамка; фильтр у каждого читателя свой.
public struct WindowInfo {
    public let pid: pid_t
    /// Номер окна; нет — 0.
    public let id: CGWindowID
    public let layer: Int?
    /// Нет поля — 1.
    public let alpha: CGFloat
    public let frame: CGRect
    public let onScreen: Bool

    /// nil — нет владельца или рамки.
    public init?(_ info: [String: Any]) {
        guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        self.pid = pid
        self.frame = frame
        id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
        layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue
        alpha = (info[kCGWindowAlpha as String] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1
        onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
    }

    /// Окна оконного сервера спереди назад; `options` — как у `CGWindowListCopyWindowInfo`.
    public static func list(_ options: CGWindowListOption) -> [WindowInfo] {
        (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap(WindowInfo.init)
    }
}
