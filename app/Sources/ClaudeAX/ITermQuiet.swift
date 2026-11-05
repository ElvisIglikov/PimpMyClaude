import AppKit
import CoreGraphics
import Foundation
import Patcher

// iTerm сам вперёд не выходит — второй заход #11016 (слово Элвиса 28.10 ~05:20: «Вот эта штука, которая на скриншоте
// вылезает, надоела постоянно наверх встаёт огромного размера… Её можно как-то утихомирить, чтобы она на первый план не
// подскакивал»). Настройку `tmuxWindowsOpenInBackground` (1.10.84) iTerm читает только при запуске, и даже с ней новая
// вкладка tmux показывает окно: скрытый iTerm показывает себя сам (замер 28.10 05:12 — hidden → false через 3 с после
// нового чата, фокус не взял), видимый в фоне встаёт поверх Claude (05:06). Пимп следит за iTerm: показался или стал
// активным без человека — прячет обратно (`hide`, фокус macOS отдаёт прежнему приложению); новые вкладки в hub Пимп
// связывает, только пока iTerm активен (#11403, `TerminalKeeper.runHub`). Показ человека не трогает: строка
// «Терминалов» (`allow`), `pimp.py term --show` (файл `iterm/show-at` свежее `allowSeconds`), клик или клавиша за
// `userWindow` до показа.
public final class ITermQuiet {
    public static let shared = ITermQuiet()
    /// Клик или клавиша человека не раньше стольких секунд до показа — показ его.
    static let userWindow: TimeInterval = 1.5
    /// После строки «Терминалов» или `--show` столько секунд iTerm не прячем.
    static let allowSeconds: TimeInterval = 8
    /// Запуск iTerm моложе — нажатие человека считаем от запуска.
    static let launchSeconds: TimeInterval = 10
    /// Пауза перед решением, когда человек только что нажимал: нажатие в Dock даёт «показался» раньше «активен».
    /// Не нажимал — решаем сразу: пауза — это вспышка окна (замер 28.10 06:05 — 0,26 с).
    static let settle: TimeInterval = 0.25
    static var showMark: URL { SupportFiles.directory.appendingPathComponent("iterm/show-at") }

    private let lock = NSLock()
    private var allowUntil = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    /// Человек сделал iTerm активным (главный поток): Пимп связывает отложенные вкладки чатов (#11403). Стал активным сам —
    /// не зовём: его тут же спрячут, а вкладка в спрятанном iTerm снова мигнула бы окном.
    public var activated: (() -> Void)?

    public func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == ITermHub.bundle else { return }
                let human = Self.sinceUserInput() <= Self.userWindow
                self?.check(app, after: human ? Self.settle : 0)
                if name == NSWorkspace.didActivateApplicationNotification, human || self?.allowed() == true {
                    self?.activated?()
                }
            })
        }
    }

    /// Показ по слову человека (строка «Терминалов»): следующие `allowSeconds` iTerm не прячем.
    public func allow() {
        lock.lock()
        allowUntil = Date().addingTimeInterval(Self.allowSeconds)
        lock.unlock()
    }

    private func check(_ app: NSRunningApplication, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            let sinceLaunch = app.launchDate.map { Date().timeIntervalSince($0) } ?? .infinity
            guard !app.isTerminated, !app.isHidden,
                  Self.shouldHide(active: app.isActive, allowed: allowed(), sinceInput: Self.sinceUserInput(),
                                  sinceLaunch: sinceLaunch)
            else { return }
            app.hide()
        }
    }

    /// Прятать ли показавшийся iTerm. Разрешён — нет. Только что запущен (запуск по клику в Dock идёт секунды, активным
    /// он становится в конце) — если человек ничего не нажимал за `userWindow` до запуска и после. Иначе неактивный
    /// показался сам — да: человек показывает iTerm, только делая его активным; активный — если человек ничего не
    /// нажимал за `userWindow`.
    static func shouldHide(active: Bool, allowed: Bool, sinceInput: TimeInterval,
                           sinceLaunch: TimeInterval = .infinity) -> Bool {
        if allowed { return false }
        if sinceLaunch < launchSeconds { return sinceInput > sinceLaunch + userWindow }
        return !active || sinceInput > userWindow
    }

    func allowed(now: Date = Date(), mark: URL = showMark) -> Bool {
        lock.lock()
        let until = allowUntil
        lock.unlock()
        if now < until { return true }
        guard let at = (try? FileManager.default.attributesOfItem(atPath: mark.path))?[.modificationDate] as? Date
        else { return false }
        return abs(now.timeIntervalSince(at)) < Self.allowSeconds
    }

    /// Секунд с последнего клика или клавиши (состояние HID).
    static func sinceUserInput() -> TimeInterval {
        let kinds: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .keyDown, .keyUp]
        return kinds.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? .infinity
    }
}
