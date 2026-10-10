import CoreGraphics
import Foundation

/// One correction after an explicit layout operation. Desired frames only qualify a
/// candidate; the baseline always comes from two complete, stable native readbacks.
struct OneShotLayoutGuard {
    struct Observation {
        var pid: Int32?
        var screens: String
        var windows: [PimpWindow]
        var complete: Bool
        var safe: Bool
        var restorePending: Bool = false
        var nativeComplete: Bool = true
    }
    private struct State {
        let pid: Int32
        let screens: String
        let nativeIDs: Set<CGWindowID>
        var identities: [CGWindowID: String]?
        let desired: [PimpMove]
        let deadline: Date
        let expires: Date
        let waitForRestore: Bool
        var baseline: [PimpMove]?
        var previous: [PimpMove]?
    }
    static let candidateSeconds: TimeInterval = 45
    static let lifetimeSeconds: TimeInterval = 60
    private var state: State?
    var active: Bool { state != nil }
    var armed: Bool { state?.baseline != nil }
    func wantsProbe(at: Date) -> Bool { state.map { at <= $0.expires } ?? false }

    mutating func disarm() { state = nil }

    mutating func arm(_ desired: [PimpMove], observation: Observation, at: Date, waitForRestore: Bool = false) {
        disarm()
        let nativeIDs = Set(observation.windows.map { $0.id })
        let identities = Self.identities(observation.windows)
        guard observation.safe, observation.nativeComplete, let pid = observation.pid, pid > 0,
              !observation.screens.isEmpty, !desired.isEmpty,
              nativeIDs.count == observation.windows.count, !nativeIDs.contains(0),
              !observation.complete || identities != nil,
              !observation.restorePending || waitForRestore,
              Set(desired.map { $0.id }).count == desired.count,
              desired.allSatisfy({ nativeIDs.contains($0.id) && Self.valid($0.frame) }) else { return }
        state = State(pid: pid, screens: observation.screens, nativeIDs: nativeIDs,
                      identities: observation.complete ? identities : nil,
                      desired: desired.sorted { $0.id < $1.id }, deadline: at + Self.candidateSeconds,
                      expires: at + Self.lifetimeSeconds, waitForRestore: waitForRestore)
    }

    /// Consumes the one shot before returning any effects, including when AX will refuse them.
    mutating func tick(_ observation: Observation, at: Date) -> [PimpMove] {
        guard var current = state else { return [] }
        guard observation.safe, observation.nativeComplete, observation.pid == current.pid,
              observation.screens == current.screens, at <= current.expires,
              Set(observation.windows.map { $0.id }) == current.nativeIDs else { disarm(); return [] }
        if current.baseline == nil, at > current.deadline { disarm(); return [] }
        // A candidate may wait for the first bounded probe answer. No baseline or effect
        // is admitted until the normal strict identity resolver declares the whole map fresh.
        if !observation.complete {
            guard current.baseline == nil else { disarm(); return [] }
            current.previous = nil; state = current
            return []
        }
        guard let identities = Self.identities(observation.windows),
              current.identities == nil || current.identities == identities else { disarm(); return [] }
        current.identities = identities
        if observation.restorePending {
            guard current.baseline == nil, current.waitForRestore else { disarm(); return [] }
            current.previous = nil; state = current
            return []
        }
        let byID = Dictionary(uniqueKeysWithValues: observation.windows.map { ($0.id, $0.frame) })
        let actual = current.desired.compactMap { wanted in byID[wanted.id].map { PimpMove(id: wanted.id, frame: $0) } }
        guard actual.count == current.desired.count, actual.allSatisfy({ Self.valid($0.frame) }) else { disarm(); return [] }
        if let baseline = current.baseline {
            if Self.matches(actual, baseline) { current.previous = nil; state = current; return [] }
            if let previous = current.previous, Self.matches(actual, previous) {
                disarm()
                return baseline.filter { saved in
                    actual.first(where: { $0.id == saved.id }).map { !ClaudeActions.frameMatches($0.frame, saved.frame) } ?? false
                }
            }
        } else {
            guard Self.matches(actual, current.desired) else { current.previous = nil; state = current; return [] }
            if let previous = current.previous, Self.matches(actual, previous) {
                current.baseline = actual
                current.previous = nil
                state = current
                return []
            }
        }
        current.previous = actual
        state = current
        return []
    }

    private static func identities(_ windows: [PimpWindow]) -> [CGWindowID: String]? {
        guard !windows.isEmpty, Set(windows.map { $0.id }).count == windows.count,
              windows.allSatisfy({ $0.id > 0 && $0.main != nil && ($0.main == true || !$0.chat.isEmpty) }) else { return nil }
        return Dictionary(uniqueKeysWithValues: windows.map { ($0.id, ($0.main == true ? "main:" : "chat:") + $0.chat) })
    }
    private static func valid(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
            && frame.width > 0 && frame.height > 0
    }
    private static func matches(_ lhs: [PimpMove], _ rhs: [PimpMove]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.0.id == $0.1.id && ClaudeActions.frameMatches($0.0.frame, $0.1.frame) }
    }
}
