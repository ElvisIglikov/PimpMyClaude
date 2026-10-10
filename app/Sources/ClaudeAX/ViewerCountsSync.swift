import Foundation

/// Bounded delivery with a page acknowledgement. A reinjected document reports counted=0.
final class ViewerCountsSync {
    static let limit = 3
    static let interval: TimeInterval = 5
    private var generation = 0
    private var observed: [UInt32: Int] = [:]
    private var titles: [String] = []
    private var attempts = 0
    private var lastAttempt: Date?
    private var flight: Int?
    private var needed = true
    private var deliveredAt: Date?
    private var baseline: [UInt32: Int] = [:]

    func beginGeneration() {
        generation += 1
        observed = [:]
        titles = []
        attempts = 0
        lastAttempt = nil
        flight = nil
        needed = true
        deliveredAt = nil
        baseline = [:]
    }

    func tick(titles: [String], pages: [ChatPage], at: Date,
              send: (@escaping (Bool) -> Void) -> Void) {
        guard !titles.isEmpty else { return }
        let fresh = pages.filter { $0.kind != .other && ChatProbe.isRecent($0, at: at) && $0.windowId != nil && $0.galleryCounted != nil }
        let zero = fresh.contains { $0.galleryCounted == 0 && observed[$0.windowId!] != 0 }
        let changed = titles.sorted() != self.titles
        if changed || zero {
            generation += 1
            self.titles = titles.sorted()
            attempts = 0
            needed = true
            deliveredAt = nil
            baseline = [:]
            // Leave an existing async send running; its completion cannot acknowledge this generation.
        }
        for page in fresh { observed[page.windowId!] = page.galleryCounted! }
        if let delivered = deliveredAt, !fresh.isEmpty,
           fresh.count == pages.filter({ $0.kind != .other }).count,
           fresh.allSatisfy({ $0.at > delivered && $0.galleryCounted! > (baseline[$0.windowId!] ?? 0) }) { needed = false }
        guard needed, flight == nil, attempts < Self.limit,
              lastAttempt.map({ at.timeIntervalSince($0) >= Self.interval }) ?? true else { return }
        let token = generation
        let sentBaseline = observed
        lastAttempt = at
        flight = token
        send { [weak self] accepted in
            guard let self = self else { return }
            guard self.flight == token else { return }
            self.flight = nil
            guard token == self.generation else { return }
            if accepted {
                self.attempts += 1
                // Each retry keeps the earliest unacknowledged baseline for this generation.
                // A positive counter left by an older title generation is not an ACK.
                if self.deliveredAt == nil {
                    self.deliveredAt = at
                    self.baseline = sentBaseline
                }
            }
        }
    }
}
