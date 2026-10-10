import Foundation

/// The native preference is a policy until the user explicitly replaces preserved page choices.
final class AutoContinueSwitch {
    private let delivery = AutoAllowSwitch()
    private(set) var on = false
    private(set) var migrate = false

    func configure(on: Bool, migrate: Bool) {
        guard self.on != on || self.migrate != migrate else { return }
        self.on = on
        self.migrate = migrate
        beginGeneration()
    }
    func beginGeneration() { delivery.beginGeneration() }
    static func fields(on: Bool, migrate: Bool) -> [(key: String, value: CommandValue)] {
        var fields: [(key: String, value: CommandValue)] = [("on", .bool(on))]
        if migrate { fields.append(("migrate", .bool(true))) }
        return fields
    }
    func tick(titles: [String], at: Date, send: ([(key: String, value: CommandValue)]) -> Bool) {
        delivery.tick(titles: titles, at: at) { _ in send(Self.fields(on: self.on, migrate: self.migrate)) }
    }
    /// nil means unknown/mixed; never present a legacy migration preference as a confirmed page state.
    static func reported(_ pages: [ChatPage], at: Date) -> Bool? {
        let ours = pages.filter { $0.kind != .other }
        guard !ours.isEmpty, ours.allSatisfy({ ChatProbe.isRecent($0, at: at) && $0.autoContinue != nil }) else { return nil }
        let values = Set(ours.compactMap { $0.autoContinue })
        return values.count == 1 ? values.first : nil
    }
}
