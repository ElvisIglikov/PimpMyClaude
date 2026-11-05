import AppKit
import ClaudeAX
import SwiftUI

// Окно подсказки у окна macOS «Claude Safe Storage» (WF238, #9580): плашка прямо под окном macOS (само окно
// подсвечивает маяк окон доступа). Когда показывать и где встать, считает `KeychainHint` (ClaudeAX); здесь — опрос, окно и проба.

/// Первое нажатие по плашке — уже действие: ключевой она не становится никогда. Крестик и ссылку ловим здесь, по
/// рамкам из вида: нажатие срабатывает и в окне без фокуса.
final class KeychainHintHostingView: NSHostingView<KeychainHintPlaque> {
    let spots = KeychainHintSpots()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        switch spots.spot(at: convert(event.locationInWindow, from: nil)) {
        case .close: rootView.close()
        case .source: rootView.openSource()
        case nil: super.mouseDown(with: event)
        }
    }
}

/// Плашка: поверх окон и на всех рабочих столах, фокус у окна пароля не забирает — ловит только нажатия по себе.
final class KeychainHintPanel: NSPanel {
    let host = KeychainHintHostingView(rootView: KeychainHintPlaque(content: .hint(.update),
                                                                    width: KeychainHint.minWidth))

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        // Выше окон-слоёв маяка: те стоят на уровне заставки.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        // Без тени: рядом с окном запроса macOS нашего нет ничего, кроме самой плашки.
        hasShadow = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Подсказка живьём: `begin` — Claude открывается после переподписи; дальше она сама ждёт окно macOS, встаёт под
/// ним, после его закрытия говорит «Готово…» и уходит.
final class KeychainHintController {
    /// Окно macOS сейчас. Живьём — окно `SecurityAgent`; в пробе — нарисованный пример.
    var findWindow: () -> KeychainHint.Target? = KeychainHint.findWindow
    /// Крестик плашки. Нет — подсказка просто уходит; проба закрывает им свой пример окна.
    var onClose: (() -> Void)?
    /// Подсказка ушла совсем.
    var onFinish: () -> Void = {}

    private var state = KeychainHint.State()
    private var kind = KeychainHint.Kind.update
    private var timer: Timer?
    private var panel: KeychainHintPanel?
    // Слово Элвиса 11.10.2026 02:25: «неоновая рамка… убери… Была же… подсветка, такая как пузырёк» — своей рамки
    // вокруг окна и плашки подсказка больше не рисует: окно пароля, как любое окно запроса, подсвечивает маяк
    // (`ConsentBeacon`) — пузырёк со стрелкой у курсора. Плашка остаётся со своей тонкой каймой.
    /// Где окно macOS видели в последний раз: «Готово…» встаёт на то же место.
    private var lastWindow: CGRect?
    private var laid: (content: KeychainHintPlaque.Content, window: CGRect)?
    /// Подлёт к окну macOS и «дыхание» к нему (#9841), уход — растворением.
    private var pull: HintPullDriver?

    func begin(_ kind: KeychainHint.Kind) {
        self.kind = kind
        state = KeychainHint.begin(now: Date())
        guard timer == nil else { return }
        let timer = Timer(timeInterval: KeychainHint.pollInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// Убрать сразу, без «Готово…».
    func end() {
        guard timer != nil else { return }
        state = KeychainHint.State()
        apply(found: nil)
    }

    private func tick() {
        let found = findWindow()
        state = KeychainHint.step(state, windowVisible: found != nil, now: Date())
        apply(found: found)
    }

    private func apply(found: KeychainHint.Target?) {
        if let found = found { lastWindow = found.bounds }
        switch state.phase {
        case .idle:
            timer?.invalidate()
            timer = nil
            if let pull = pull { pull.hide() } else { panel?.orderOut(nil) }
            laid = nil
            lastWindow = nil
            onFinish()
        case .watching:
            break
        case .shown:
            guard let window = lastWindow else { return }
            place(.hint(kind), under: window)
        case .done:
            guard let window = lastWindow else { return }
            place(.done(kind), under: window)
        }
    }

    /// Плашка с содержимым `content` под окном macOS `window` (CG).
    private func place(_ content: KeychainHintPlaque.Content, under window: CGRect) {
        let panel = self.panel ?? KeychainHintPanel()
        self.panel = panel
        let pull = self.pull ?? HintPullDriver(window: panel)
        self.pull = pull
        let primary = NSScreen.screens.first?.frame.height ?? 0
        guard laid?.content != content || laid?.window != window || !pull.isShown else { return }
        laid = (content, window)
        var plaque = KeychainHintPlaque(content: content, width: KeychainHint.plaqueWidth(window: window),
                                        close: { [weak self] in self?.closePressed() }, spots: panel.host.spots)
        panel.host.rootView = plaque
        // Окно плашки — плашка и поле под стрелку со всех сторон (`hintPointer`): место считается по самой плашке.
        let edge = HintPointer.inset
        let outer = panel.host.fittingSize
        let size = CGSize(width: outer.width - 2 * edge, height: outer.height - 2 * edge)
        let cocoa = KeychainHint.flipped(window, primaryHeight: primary)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: cocoa.midX, y: cocoa.midY)) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let visible = KeychainHint.flipped(screen?.visibleFrame ?? cocoa, primaryHeight: primary)
        let frame = KeychainHint.plaqueFrame(window: window, size: size, visible: visible)
        // «Готово…» — окна macOS уже нет: показывать стрелкой некуда.
        if case .hint = content { plaque.pointer = HintPull.side(of: window, from: frame) }
        panel.host.rootView = plaque
        pull.show(at: KeychainHint.flipped(frame.insetBy(dx: -edge, dy: -edge), primaryHeight: primary),
                  toward: NSPoint(x: cocoa.midX, y: cocoa.midY))
    }

    private func closePressed() {
        if let onClose = onClose { onClose() } else { end() }
    }
}

// MARK: - проба

/// Проба плашки без установки и без Claude (`open -n <сборка>.app --args --keychain-hint-demo`): посреди экрана —
/// нарисованный пример окна macOS и под ним плашка, как будет в жизни. Обычный PMP при этом не
/// поднимается: ни значка у часов, ни патчера, ни каналов, ни записи в Application Support; уже работающую копию
/// проба не трогает. Держится минуту или до ✕, Esc и нажатия кнопки примера, потом «Готово…» и выход.
final class KeychainHintDemo: NSObject, NSApplicationDelegate {
    /// Сколько висит пример окна, если его не закрыли.
    static let seconds: TimeInterval = 60

    private let hint = KeychainHintController()
    private var dialog: KeychainDemoDialog?

    /// Вместо обычного запуска; не возвращается.
    static func run() -> Never {
        let app = NSApplication.shared
        let demo = KeychainHintDemo()
        app.delegate = demo
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dialog = KeychainDemoDialog { [weak self] in self?.answer() }
        self.dialog = dialog
        dialog.center()
        NSApp.activate(ignoringOtherApps: true)
        dialog.makeKeyAndOrderFront(nil)
        hint.findWindow = { [weak self] in
            guard let dialog = self?.dialog, dialog.isVisible else { return nil }
            let primary = NSScreen.screens.first?.frame.height ?? 0
            return KeychainHint.Target(number: dialog.windowNumber,
                                       bounds: KeychainHint.flipped(dialog.frame, primaryHeight: primary))
        }
        hint.onClose = { [weak self] in self?.answer() }
        hint.onFinish = { NSApp.terminate(nil) }
        hint.begin(.update)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.seconds) { [weak self] in self?.answer() }
    }

    /// «Ответили» окну-примеру: оно закрывается — плашка говорит «Готово…» и проба выходит.
    private func answer() {
        dialog?.orderOut(nil)
        dialog = nil
    }
}

/// Пример окна macOS в пробе: настоящего размера, по центру экрана, как ставит его macOS. Ключевое — ради Esc.
private final class KeychainDemoDialog: NSPanel {
    private let answer: () -> Void

    init(answer: @escaping () -> Void) {
        self.answer = answer
        let host = NSHostingView(rootView: KeychainDialogExample(press: answer))
        super.init(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .modalPanel
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { answer() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { answer() } else { super.keyDown(with: event) }
    }
}
