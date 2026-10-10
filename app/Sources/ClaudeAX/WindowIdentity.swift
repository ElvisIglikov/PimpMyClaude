import CoreGraphics
import Foundation

/// One identity decision for both kinds of Claude windows. Neither a title nor a stale
/// position may override a contradictory observation. Production supplies all AX windows.
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

    static func resolve(title: String, frame: CGRect?, pages: [ChatPage],
                        nativeWindows: [Native]? = nil, at: Date? = nil) -> WindowIdentity {
        let pages = pages.filter { page in
            page.kind != .other && (at.map { ChatProbe.isRecent(page, at: $0) } ?? true)
        }
        let title = ChatProbe.clean(title)
        let named = pages.filter { !title.isEmpty && ChatProbe.clean($0.title) == title }
        if let frame = frame {
            let geometric = pages.filter { $0.frame.map { ChatProbe.near($0, frame) } ?? false }
            if !geometric.isEmpty {
                // A rename or move must wait for a new probe, including an incomplete map
                // in which the newly observed title has no page yet.
                let compatible = geometric.filter { title.isEmpty || ChatProbe.clean($0.title) == title }
                guard compatible.count == 1 else { return .ambiguous }
                let page = compatible[0]
                if let nativeWindows = nativeWindows {
                    let native = nativeWindows.filter {
                        ChatProbe.clean($0.title) == ChatProbe.clean(page.title)
                            && ($0.frame.map { ChatProbe.near($0, page.frame!) } ?? false)
                    }
                    guard native.count == 1 else { return .ambiguous }
                }
                return .page(page)
            }
            if named.contains(where: { $0.frame != nil }) { return named.count > 1 ? .ambiguous : .unknown }
        }
        // Title-only fallback needs positive proof from the independent AX inventory.
        guard named.count == 1 else { return named.isEmpty ? .unknown : .ambiguous }
        guard let nativeWindows = nativeWindows else { return .unknown }
        let native = nativeWindows.filter { ChatProbe.clean($0.title) == title }
        guard native.count == 1 else { return .ambiguous }
        if let pageFrame = named[0].frame, let nativeFrame = native[0].frame,
           !ChatProbe.near(pageFrame, nativeFrame) { return .unknown }
        return .page(named[0])
    }
}
