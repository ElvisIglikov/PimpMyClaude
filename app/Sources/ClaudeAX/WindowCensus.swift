import CoreGraphics
import Foundation

/// A missing AX/Quartz pair is an incomplete observation, never evidence of a closed chat.
/// Полнота считается со стороны AX (находка судьи WF111): каждое не служебное AX-окно обязано
/// однозначно сойтись с Quartz. Quartz-окно без AX-пары и не на экране — спрятанное окно Electron
/// (закрытое главное, закрытый попап): его AX не видит никогда, и в полноту оно не идёт; без пары
/// и на экране — перепись неполная, как раньше.
enum WindowCensus {
    struct Pair: Equatable { let id: CGWindowID; let native: Int }
    static func pair(native: [WindowIdentity.Native], quartz: [ClaudeWindowFrame]) -> (pairs: [Pair], complete: Bool) {
        var pairs: [Pair] = []
        for entry in quartz {
            let hits = native.indices.filter { index in
                native[index].frame.map { ClaudeActions.frameMatches($0, entry.frame) } ?? false
            }
            guard hits.count == 1 else { continue }
            let index = hits[0]
            let reverse = quartz.filter { ClaudeActions.frameMatches(native[index].frame!, $0.frame) }
            guard reverse.count == 1 else { continue }
            pairs.append(Pair(id: entry.id, native: index))
        }
        let paired = Set(pairs.map { $0.id })
        let unpairedOnScreen = quartz.contains { $0.onScreen && !paired.contains($0.id) }
        return (pairs, pairs.count == native.count && !unpairedOnScreen)
    }
}

/// Restore targets are clamped once using the same public screen geometry and minimum width
/// for placement and its later verification. Ordinary arrange commands retain their own grids.
enum RestoreFrame {
    static func adapt(_ frame: CGRect, screens: [CGRect], minWidth: CGFloat) -> CGRect {
        guard !screens.isEmpty else { return frame }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let area = screens.first(where: { $0.contains(center) }) ?? screens[0]
        let width = min(area.width, max(frame.width, minWidth))
        let height = min(area.height, max(1, frame.height))
        return CGRect(x: min(max(frame.minX, area.minX), area.maxX - width),
                      y: min(max(frame.minY, area.minY), area.maxY - height), width: width, height: height)
    }

    static func adaptChatGPT(_ frame: CGRect, screens: [CGRect], minWidth: CGFloat) -> CGRect {
        let width = max(frame.width, minWidth)
        let aligned = CGRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)
        return adapt(aligned, screens: screens, minWidth: minWidth)
    }

    static func restored(_ expected: [SnapshotWindow], in actual: [SnapshotWindow],
                         adapt: (CGRect) -> CGRect) -> Bool {
        expected.allSatisfy { wanted in
            let hits = actual.filter { $0.chat == wanted.chat }
            return hits.count == 1 && ClaudeActions.frameMatches(hits[0].frame, adapt(wanted.frame))
        }
    }
}
