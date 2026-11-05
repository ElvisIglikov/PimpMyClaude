import CoreGraphics
import Foundation

/// One identity decision for both kinds of Claude windows: the page whose loader-reported
/// `windowId` is the window's own (`resolveNative`, WF116). Neither a title nor a stale
/// position may override a contradictory observation; the title/frame resolver is gone (WF248).
enum WindowIdentity: Equatable {
    case page(ChatPage)
    case unknown
    case ambiguous

    struct Native {
        let title: String
        let frame: CGRect?
        var id: CGWindowID? = nil
    }

    var page: ChatPage? { if case .page(let page) = self { return page }; return nil }
    var isMain: Bool { page?.kind == .main }

    /// Production identity comes from Electron's owning macOS window, never from a
    /// renderer's cached position. AX-only callers first need a unique CURRENT Quartz pair.
    static func resolveNative(id: CGWindowID? = nil, title: String, frame: CGRect?,
                              pages: [ChatPage], nativeWindows: [Native], at: Date) -> WindowIdentity {
        let candidates: [Native]
        if let id = id {
            candidates = nativeWindows.filter { $0.id == id }
        } else {
            guard let frame = frame else { return .unknown }
            let title = ChatProbe.clean(title)
            candidates = nativeWindows.filter {
                (title.isEmpty || ChatProbe.clean($0.title) == title)
                    && ($0.frame.map { ClaudeActions.frameMatches($0, frame) } ?? false)
            }
        }
        guard candidates.count == 1 else { return candidates.isEmpty ? .unknown : .ambiguous }
        guard let id = candidates[0].id, id > 0 else { return .unknown }
        guard nativeWindows.filter({ $0.id == id }).count == 1 else { return .ambiguous }
        let matches = pages.filter { $0.windowId == id }
        guard matches.count == 1 else { return matches.isEmpty ? .unknown : .ambiguous }
        let page = matches[0]
        // Свежесть 10 с — только у главного окна: его чат меняется на месте. Попап годен, пока
        // карта свежая (`pages` несвежей карты пусты) и его windowId в текущей переписи — это
        // проверено выше (находка судьи WF111: иначе 5–9 с из каждого круга все окна «неизвестны»).
        guard page.kind != .other, page.kind == .popout || ChatProbe.isRecent(page, at: at) else { return .unknown }
        return .page(page)
    }
}
