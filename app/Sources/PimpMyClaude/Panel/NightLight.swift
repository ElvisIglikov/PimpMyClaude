import AppKit
import SwiftUI
import KeyboardBridge

/// Подсветка клавиатуры NightWolf одной полоской в «Оформлении» (#10394, слово Элвиса 20.10: «в Пимпе прямо напрашивается
/// где-то внизу. Полоска такая узенькая снизу… от него только одно поло[ска]»). Движок — NightWolf как есть
/// (`NightLightEngine.swift`): ползунок 0 — выкл., 1–10 — ночные уровни ниже минимума macOS, 11–110 — обычный свет 1–100 %.
/// Папка восстановления и замок — те же, что у NightWolf.app: пока он открыт, полоска пишет «закрой NightWolf», и два
/// движка клавиатуру не делят. До первого движения ползунка подсветкой управляет macOS, выход Пимпа её возвращает.
final class NightLight: ObservableObject {
    static let shared = NightLight()

    @Published private(set) var state = LightState()
    @Published private(set) var slider: Double
    @Published private(set) var note: String?
    private(set) var session: LightSession?
    private var nightAvailable = false
    private var observations: [NSObjectProtocol] = []
    private static let levelKey = "nightLightLevel10394"

    private init() {
        slider = Self.startSlider(UserDefaults.standard.object(forKey: Self.levelKey) as? Double)
    }

    /// #10962 (слово Элвиса: «подсветка начиналась с четырёх, это было бы минимальным значением, потому что на более
    /// низких значениях мерцания появляется клавиатуры. Четыре будет начальное значение всех крутилок»): ползунок — от
    /// «ночь 4 из 10», с неё и стартует. Выкл. и ночь 1–3 ползунком больше не выбрать (вернуть подсветку macOS — кнопка).
    static let minLevel: Double = 4
    static let startLevel: Double = 4
    static let maxLevel: Double = 110

    /// Положение ползунка при запуске: сохранённое, поджатое к `minLevel…maxLevel`; нет или мусор — `startLevel`.
    static func startSlider(_ saved: Double?) -> Double {
        guard let saved = saved, saved.isFinite else { return startLevel }
        return min(maxLevel, max(minLevel, saved.rounded()))
    }

    /// Уровень ползунка словами: «ночь 4 из 10», «37 %», 0 — «выкл.».
    static func levelText(_ level: Int) -> String {
        level <= 0 ? "выкл." : level <= 10 ? "ночь \(level) из 10" : "\(level - 10) %"
    }

    /// Нет встроенной клавиатуры с подсветкой — полоски нет.
    static let supported: Bool = NWKeyboardOpen()

    /// Запущенное приложение, которое тоже правит подсветкой (`NightLightRival`); nil — никого.
    @Published private(set) var rival: NightLightRival.App?
    private var retrying = false
    private var rivalWatch: NSObjectProtocol?

    /// Движок — при первом показе полоски. Подсветкой правит запущенный NightWolf или Midnight Keyboard — надпись и
    /// кнопка «Закрыть», движок встаёт, когда тот завершится. Замок занят кем-то другим (прогон тестов, вторая копия
    /// Пимпа при подмене) — надписи нет, пробуем снова через `retryDelay` (слово Элвиса 22.10.2026: «Открыт NightWolf»
    /// висела, когда NightWolf не был запущен). Под XCTest движок не встаёт: тест не держит замок живой клавиатуры.
    func attach() {
        guard Self.supported, session == nil, !Self.underTests, let device = NativeKeyboard() else { return }
        if let app = NightLightRival.running(NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier }) {
            rival = app
            note = NightLightRival.note(app)
            watchRival()
            return
        }
        rival = nil
        do {
            let made = try LightSession(device: device, store: RecoveryStore())
            nightAvailable = device.pwmHigh.isFinite
            made.onChange = { [weak self] state in self?.state = state }
            session = made
            state = made.state
            note = nil
            watchSleep()
        } catch {
            note = nil
            retryLater()
        }
    }

    static let retryDelay: TimeInterval = 10
    static let underTests = NSClassFromString("XCTestCase") != nil

    private func retryLater() {
        guard !retrying else { return }
        retrying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            self?.retrying = false
            self?.attach()
        }
    }

    /// Кнопка «Закрыть»: завершить NightWolf или Midnight Keyboard; завершится — движок встанет сам (`watchRival`).
    func quitRival() {
        guard let app = rival else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundle).forEach { $0.terminate() }
    }

    /// Соперник завершился — пробуем движок снова.
    private func watchRival() {
        guard rivalWatch == nil else { return }
        rivalWatch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let gone = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard let self = self, let rival = self.rival, gone == rival.bundle else { return }
            self.attach()
        }
    }

    func select(_ value: Double) {
        guard let session = session else { return }
        let level = Int(min(Self.maxLevel, max(Self.minLevel, value.rounded())))
        if (1...10).contains(level) && !nightAvailable { return }
        slider = Double(level)
        UserDefaults.standard.set(slider, forKey: Self.levelKey)
        session.select(level == 0 ? .off : level <= 10 ? .night(level) : .normal(level - 10))
    }

    func restore() { _ = session?.restore() }

    /// Выход Пимпа: вернуть подсветку macOS (как «Выход» NightWolf).
    func quit() {
        guard let session = session, session.state.canRestore else { return }
        _ = session.restore()
    }

    var label: String { Self.label(state, slider: slider) }

    /// Подпись полоски. Подсветкой правит macOS — рядом стоит, что выставит ползунок (#10962: у «Подсветка · macOS»
    /// значение видно, а не голый ползунок без числа).
    static func label(_ state: LightState, slider: Double) -> String {
        if let error = state.error { return error }
        if state.suspended || state.idle { return "Подсветка · пауза" }
        switch state.mode {
        case .system: return "Подсветка · macOS · ползунок: " + levelText(Int(startSlider(slider)))
        case .off: return "Подсветка · " + levelText(0)
        case .night(let level): return "Подсветка · " + levelText(level)
        case .normal(let percent): return "Подсветка · " + levelText(percent + 10)
        }
    }

    private func watchSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, String, Bool)] = [
            (NSWorkspace.willSleepNotification, "sleep", true), (NSWorkspace.didWakeNotification, "sleep", false),
            (NSWorkspace.screensDidSleepNotification, "screen", true), (NSWorkspace.screensDidWakeNotification, "screen", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session", false),
        ]
        for (name, reason, paused) in pairs {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.session?.setPaused(reason, paused)
            })
        }
        for (name, paused) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observations.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil,
                                                                                 queue: .main) { [weak self] _ in
                self?.session?.setPaused("lock", paused)
            })
        }
    }
}

/// Узкая полоска: подпись слева, «macOS» справа (вернуть системе), ползунок во всю ширину.
struct NightStrip: View {
    @ObservedObject var light = NightLight.shared
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "moon.stars").font(.system(size: 10)).foregroundColor(PanelColor.sub)
                Text(light.note ?? light.label).font(.system(size: 11)).foregroundColor(PanelColor.sub).lineLimit(1)
                Spacer(minLength: 4)
                if let rival = light.rival {
                    Button("Закрыть", action: light.quitRival).buttonStyle(.plain).font(.system(size: 11))
                        .foregroundColor(PanelColor.text).handCursor()
                        .help("Завершить \(rival.name) — подсветкой будет править PMP")
                } else if light.session != nil, light.state.mode != .system {
                    Button("macOS", action: light.restore).buttonStyle(.plain).font(.system(size: 11))
                        .foregroundColor(PanelColor.sub).handCursor()
                        .help("Вернуть подсветку macOS")
                }
            }
            if light.session != nil {
                Slider(value: Binding(get: { light.slider }, set: { light.select($0) }), in: NightLight.minLevel...NightLight.maxLevel, step: 1)
                    .controlSize(.mini)
                    .tint(accent)
                    .disabled(light.state.suspended || light.state.error != nil)
                    .accessibilityLabel("Подсветка клавиатуры")
                    .help("Ночь 4–10 → обычный свет")
            }
        }
        .onAppear { light.attach() }
    }
}

/// Кто ещё правит подсветкой клавиатуры (слово Элвиса 22.10.2026: «Открыт NightWolf» висела, хотя ни NightWolf, ни
/// Midnight Keyboard не были запущены — замок держал прогон тестов). Решает только список запущенных приложений macOS.
enum NightLightRival {
    struct App: Equatable {
        let bundle: String
        let name: String
    }

    static let apps = [App(bundle: "local.nightwolf.app", name: "NightWolf"),
                       App(bundle: "com.jessedacri.MidKey", name: "Midnight Keyboard")]

    /// Первый из `apps` среди bundle id запущенных приложений; никого — nil.
    static func running(_ bundles: [String?]) -> App? {
        let live = Set(bundles.compactMap { $0 })
        return apps.first { live.contains($0.bundle) }
    }

    /// Строка полоски рядом с кнопкой «Закрыть».
    static func note(_ app: App) -> String { "Открыт \(app.name) — подсветкой правит он" }
}
