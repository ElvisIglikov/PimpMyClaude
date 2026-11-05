// Перенесено из NightWolf (#10394, 20.10.2026): движок подсветки клавиатуры как есть, чтобы ползунок жил в панели Пимпа.
// Источник правды поведения — /Users/dev/Projects/NightWolf (README «Как устроено»).
import Foundation
import Darwin
import KeyboardBridge

struct KeyboardSnapshot: Codable, Equatable {
    let keyboardID: UInt64
    let brightness: Float
    let autoBrightness: Bool
    var isValid: Bool { brightness.isFinite && (0...1).contains(brightness) }
}

protocol KeyboardDevice: AnyObject {
    var identifier: UInt64 { get }
    var brightness: Float { get }
    var autoBrightness: Bool { get }
    var idleTimeout: Double { get }
    var idleSeconds: Double { get }
    var pwmHigh: Double { get }
    var pwmEnabled: Bool { get }
    func setBrightness(_ value: Float, fade: Int) -> Bool
    func setAutoBrightness(_ enabled: Bool) -> Bool
}

// One serialized owner. The app runs this engine on its dedicated serial queue.
// tick() never enqueues work: canceling its caller's timer excludes stale writes.
final class LightEngine {
    enum Mode: Equatable { case system, off, night(Int), normal(Int) }
    enum TickRate { case stopped, feedback, idle }
    private(set) var mode: Mode = .system
    private(set) var original: KeyboardSnapshot?
    private(set) var error: String?
    private(set) var suspended = false
    private(set) var idlePaused = false
    private(set) var floor: Double = 0
    private(set) var target: Double = 0
    private var direction = 0
    private var calibrated = false
    private var awaitingCalibration = false
    private var calibrationWaitTicks = 0
    private let device: KeyboardDevice
    // Persist before taking control, and clear only after successful restoration.
    private let saveRecovery: (KeyboardSnapshot?) throws -> Void
    static let minimum: Float = 0.000001
    static let fractions: [Double] = [0.08, 0.13, 0.19, 0.27, 0.35, 0.45, 0.56, 0.68, 0.80, 0.92]

    init(device: KeyboardDevice, saveRecovery: @escaping (KeyboardSnapshot?) throws -> Void) {
        self.device = device
        self.saveRecovery = saveRecovery
    }
    var tickRate: TickRate {
        guard error == nil, !suspended, case .night = mode else { return .stopped }
        return idlePaused ? .idle : .feedback
    }

    @discardableResult func recover(_ snapshot: KeyboardSnapshot) -> Bool {
        guard snapshot.isValid, snapshot.keyboardID == device.identifier else {
            error = "Сохранённая клавиатура недоступна. Восстановление не выполнено."
            return false
        }
        original = snapshot
        return restore()
    }

    @discardableResult func select(_ requested: Mode) -> Bool {
        guard !suspended else { return false }
        if requested == .system { return restore() }
        guard error == nil else { return false }
        switch requested {
        case .night(let level):
            guard (1...10).contains(level) else { return false }
            guard device.pwmHigh.isFinite else { return fail("Ночные уровни недоступны на этой клавиатуре.") }
        case .normal(let percent): guard (1...100).contains(percent) else { return false }
        default: break
        }
        if original == nil {
            let snapshot = KeyboardSnapshot(keyboardID: device.identifier, brightness: device.brightness, autoBrightness: device.autoBrightness)
            guard snapshot.isValid, device.idleTimeout.isFinite, device.idleTimeout >= 0 else {
                error = "Не удалось прочитать исходную подсветку."
                return false
            }
            do { try saveRecovery(snapshot) } catch {
                self.error = "Не удалось сохранить исходную подсветку."
                return false
            }
            original = snapshot
        }
        guard device.setAutoBrightness(false) else { return fail("macOS не разрешила изменить подсветку.") }
        mode = requested
        direction = 0
        idlePaused = false
        awaitingCalibration = false
        calibrationWaitTicks = 0
        switch requested {
        case .off: guard device.setBrightness(0, fade: 0) else { return fail("Не удалось выключить подсветку.") }
        case .normal(let percent):
            guard device.setBrightness(Float(percent) / 100, fade: 0) else { return fail("Не удалось установить яркость.") }
        case .night(let level):
            if !calibrated {
                // First feedback tick is delayed 100 ms, allowing the driver to settle.
                guard device.setBrightness(Self.minimum, fade: 0) else { return fail("Не удалось подготовить ночной режим.") }
                awaitingCalibration = true
            } else {
                target = max(3, (floor * Self.fractions[level - 1]).rounded())
            }
        case .system: break
        }
        return true
    }

    func tick() {
        guard error == nil, !suspended, case .night(let level) = mode else { return }
        // Keep the system's original idle timeout. Read only aggregate idle time.
        let timeout = device.idleTimeout
        // CoreBrightness's "suppressed" flag also follows OUR fade-to-zero target.
        // It is not a sleep signal. Workspace sleep/lock notifications call suspend().
        let shouldPause = timeout > 0 && device.idleSeconds >= timeout
        if shouldPause {
            if !idlePaused {
                guard device.setBrightness(0, fade: 0) else { _ = fail("Не удалось погасить подсветку."); return }
                idlePaused = true; direction = 0
            }
            return
        }
        if idlePaused {
            idlePaused = false; direction = 0
            if awaitingCalibration {
                guard device.setBrightness(Self.minimum, fade: 0) else { _ = fail("Не удалось возобновить ночной режим."); return }
                calibrationWaitTicks = 5
                return
            }
        }
        if calibrationWaitTicks > 0 { calibrationWaitTicks -= 1; return }
        let high = device.pwmHigh
        guard high.isFinite, high >= 0 else { _ = fail("Не удалось прочитать ночную подсветку."); return }
        if awaitingCalibration {
            guard high >= 8, device.pwmEnabled else { _ = fail("macOS временно блокирует ночную подсветку."); return }
            floor = high
            calibrated = true
            awaitingCalibration = false
            target = max(3, (floor * Self.fractions[level - 1]).rounded())
        }
        let next = !device.pwmEnabled || high < target ? 1 : high > target ? -1 : direction
        if next != direction {
            guard device.setBrightness(next > 0 ? Self.minimum : 0, fade: 1000) else {
                _ = fail("Ночной режим остановлен: macOS отклонила команду."); return
            }
            direction = next
        }
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        direction = 0
        // Cancel any in-flight fade without relighting a sleeping display/session.
        if original != nil, !device.setBrightness(0, fade: 0) {
            error = "Подсветка приостановлена с ошибкой. Исходный свет вернётся после пробуждения."
        }
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        guard original != nil else { return }
        if let problem = error {
            if restore() { error = problem }
            return
        }
        let desired = mode
        calibrated = false
        _ = select(desired)
    }

    @discardableResult func restore() -> Bool {
        mode = .system
        direction = 0
        idlePaused = false
        awaitingCalibration = false
        calibrated = false
        guard let snapshot = original else { error = nil; return true }
        // Restore both fields even if one call fails. Never discard recovery on failure.
        let brightnessOK = device.setBrightness(snapshot.brightness, fade: 0)
        let autoOK = device.setAutoBrightness(snapshot.autoBrightness)
        let readback = device.brightness
        let sameOnOffState = (readback > 0) == (snapshot.brightness > 0)
        let tolerance = max(Float(0.0000001), snapshot.brightness * 0.001)
        let verified = snapshot.autoBrightness || (readback.isFinite && sameOnOffState && abs(readback - snapshot.brightness) <= tolerance)
        guard brightnessOK, autoOK, device.autoBrightness == snapshot.autoBrightness, verified else {
            error = "Не удалось вернуть настройки. Нажми «Вернуть управление macOS» ещё раз."
            return false
        }
        do { try saveRecovery(nil) } catch {
            self.error = "Подсветка возвращена, но запись восстановления не удалена."
            return false
        }
        original = nil
        error = nil
        return true
    }

    private func fail(_ message: String) -> Bool {
        let restored = restore()
        if restored { error = message }
        return false
    }
}


struct LightState: Equatable {
    var mode: LightEngine.Mode = .system
    var suspended = false
    var idle = false
    var error: String?
    var canRestore = false
}

// A single queue owns both device and timer. UI never calls the driver directly.
final class LightSession {
    var onChange: ((LightState) -> Void)?
    private let queue = DispatchQueue(label: "local.nightwolf.keyboard", qos: .userInitiated)
    private let engine: LightEngine
    private let store: RecoveryStore
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var pauseReasons = Set<String>()
    private var lastState: LightState?
    private var lockFD: Int32 = -1
    private var startupError: String?
    private let timersEnabled: Bool

    init(device: KeyboardDevice, store: RecoveryStore, timersEnabled: Bool = true) throws {
        self.store = store
        self.timersEnabled = timersEnabled
        engine = LightEngine(device: device, saveRecovery: store.save)
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        lockFD = open(store.url.deletingLastPathComponent().appendingPathComponent("session.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw SessionError("Не удалось открыть NightWolf.") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD); lockFD = -1
            throw SessionError("NightWolf уже запущен. Нажми значок луны в верхней панели.")
        }
        // Startup is read-only except for recovering an unfinished previous session.
        queue.sync {
            do {
                if let saved = try store.load(), !engine.recover(saved) {
                    // Recoverable errors belong to the engine and may clear on wake/retry.
                    // Only a rejected snapshot needs a separate read-only startup block.
                    if engine.original == nil { startupError = engine.error }
                }
            } catch { startupError = "Не удалось прочитать сохранённые настройки подсветки." }
        }
    }
    deinit {
        timer?.cancel()
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) }
    }
    struct SessionError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    var state: LightState { queue.sync { snapshot() } }
    func refresh() { queue.async { self.publish() } }

    func select(_ mode: LightEngine.Mode) {
        queue.async {
            guard self.startupError == nil else { self.publish(); return }
            self.cancelTimer()
            _ = self.engine.select(mode)
            self.startTimer()
            self.publish()
        }
    }
    func setPaused(_ reason: String, _ paused: Bool) {
        queue.async {
            let wasPaused = !self.pauseReasons.isEmpty
            if paused { self.pauseReasons.insert(reason) } else { self.pauseReasons.remove(reason) }
            let isPaused = !self.pauseReasons.isEmpty
            guard wasPaused != isPaused else { return }
            self.cancelTimer()
            if isPaused { self.engine.suspend() } else { self.engine.resume(); self.startTimer() }
            self.publish()
        }
    }
    // Used by both the restore button and application termination.
    @discardableResult func restore() -> Bool {
        queue.sync {
            cancelTimer()
            // A valid snapshot may fail transiently at startup. Keep the retry usable.
            guard startupError == nil || engine.original != nil else { publish(); return false }
            let result = engine.restore()
            if result { startupError = nil }
            publish()
            return result
        }
    }
    private func snapshot() -> LightState {
        LightState(mode: engine.mode, suspended: engine.suspended, idle: engine.idlePaused,
                   error: startupError ?? engine.error, canRestore: engine.original != nil)
    }
    private func publish() {
        let state = snapshot()
        guard state != lastState else { return }
        lastState = state
        let callback = onChange
        DispatchQueue.main.async { callback?(state) }
    }
    private func cancelTimer() {
        generation += 1
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
    private func startTimer() {
        guard timersEnabled, engine.tickRate != .stopped else { return }
        let token = generation
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(20), leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            guard let self, token == self.generation else { return }
            let previousRate = self.engine.tickRate
            self.engine.tick()
            let rate = self.engine.tickRate
            if rate == .stopped {
                self.cancelTimer()
            } else if previousRate != rate {
                let interval: DispatchTimeInterval = rate == .idle ? .seconds(1) : .milliseconds(20)
                self.timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
            }
            self.publish()
        }
        timer = source
        source.resume()
    }
}


final class NativeKeyboard: KeyboardDevice {
    init?() { guard NWKeyboardOpen() else { return nil } }
    var identifier: UInt64 { NWKeyboardID() }
    var brightness: Float { NWBrightness() }
    var autoBrightness: Bool { NWAutoBrightness() }
    var idleTimeout: Double { NWIdleTimeout() }
    var idleSeconds: Double { NWIdleSeconds() }
    var pwmHigh: Double { NWPWMHigh() }
    var pwmEnabled: Bool { NWPWMEnabled() }
    func setBrightness(_ value: Float, fade: Int) -> Bool { NWSetBrightness(value, Int32(fade)) }
    func setAutoBrightness(_ enabled: Bool) -> Bool { NWSetAutoBrightness(enabled) }
}

final class RecoveryStore {
    let url: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NightWolf", isDirectory: true)) {
        url = directory.appendingPathComponent("keyboard-recovery.json")
    }
    func load() throws -> KeyboardSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(KeyboardSnapshot.self, from: Data(contentsOf: url))
    }
    func save(_ snapshot: KeyboardSnapshot?) throws {
        if let snapshot {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
