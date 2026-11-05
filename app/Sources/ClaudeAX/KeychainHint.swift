import AppKit

// Подсказка у окна macOS «Claude Safe Storage» (WF238, #9580; макет `docs/41.html`, кадры 1.2 и 2.1).
// После обновления Claude и после «Пропатчить / Вернуть патч» Claude переподписан, и macOS заново спрашивает
// пароль к записи «Claude Safe Storage» в связке ключей. Окно системное: нажимать его программно нельзя и накрывать
// нельзя (решение 12.5 у `ConsentWater.swift`) — прямо под ним встаёт плашка «что это и что нажать»; само окно, как
// любое окно запроса, подсвечивает маяк (`ConsentBeacon`). Своей рамки у подсказки нет с WF246 (слово Элвиса 11.10).
//
// Здесь слова, расчёт «когда показывать и когда уходить», место плашки и поиск окна. Само окно плашки — в
// приложении (`KeychainHintWindow.swift`). Координаты — CG, как у маяка: y вниз от верха главного монитора.

public enum KeychainHint {
    /// После чего macOS спрашивает: обновление Claude или патч («Пропатчить», «Вернуть патч»).
    public enum Kind: Equatable {
        case update, patch
    }

    // MARK: слова

    /// Шаг плашки: главное — полужирным, пояснение — тихо.
    public struct Step: Equatable {
        public let lead: String
        public let rest: String
        public var text: String { lead + " — " + rest }
    }

    public static let title = "Это окно — от macOS. Так и должно быть"
    public static let steps = [Step(lead: "Впиши пароль от Мака", rest: "тот, которым входишь в компьютер"),
                               Step(lead: "Нажми «Разрешать всегда»", rest: "и оно больше не спросит")]
    public static let passwordStays = "Пароль остаётся в macOS — ни Claude, ни PMP его не видят"
    public static let sourceLink = "Код PMP открыт"
    public static let sourceTail = " — можно проверить"
    public static let closeHelp = "Скрыть подсказку"
    public static let doneText = "Про пароль спросит снова только после следующего обновления Claude"

    /// Почему спрашивает. После патча без обновления Claude не «обновлённый».
    public static func reason(_ kind: Kind) -> String {
        let claude = kind == .update ? "обновлённый Claude" : "Claude"
        return "Спрашивает, потому что PMP заново прокачал \(claude), чтобы темы, кнопка PMP и остальное работали"
    }

    public static func doneTitle(_ kind: Kind) -> String {
        kind == .update ? "Готово — Claude обновлён" : "Готово — патч на месте"
    }

    // MARK: запуск

    /// Проба плашки без установки: `open -n <сборка>.app --args --keychain-hint-demo`.
    public static let demoArgument = "--keychain-hint-demo"

    /// Запуск ради пробы: обычное приложение при нём не поднимается вовсе.
    public static func isDemoLaunch(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains(demoArgument)
    }

    /// Строка журнала патча, после которой Claude открывается уже переподписанным (`ClaudePatcher.install`,
    /// «Готово. Открываю Claude…») — с неё ждём окно macOS.
    public static func opensClaude(_ line: String) -> Bool {
        line.contains("Открываю Claude")
    }

    // MARK: когда показывать и когда уходить

    public enum Phase: Equatable {
        /// Ничего не ждём и не показываем.
        case idle
        /// Claude открывается — ждём окно macOS, на экране пока ничего.
        case watching
        /// Окно macOS висит — плашка под ним.
        case shown
        /// Окно закрыли — «Готово…» на несколько секунд.
        case done
    }

    public struct State: Equatable {
        public var phase = Phase.idle
        /// Когда началась фаза.
        public var since = Date.distantPast
        /// `shown`: с какого момента окна macOS не видно (между двумя запросами подряд оно пропадает на миг).
        public var missingSince: Date?

        public init(phase: Phase = .idle, since: Date = .distantPast) {
            self.phase = phase
            self.since = since
        }
    }

    /// Опрос окон, пока подсказка не в покое.
    public static let pollInterval: TimeInterval = 0.25
    /// Сколько ждём окно macOS после запуска Claude: не появилось — молча уходим.
    public static let watchSeconds: TimeInterval = 60
    /// Потолок показа: человек отошёл, окно висит — плашка не висит вечно.
    public static let shownSeconds: TimeInterval = 300
    /// Окно пропало меньше чем на столько — ещё не «закрыли».
    public static let goneGrace: TimeInterval = 0.6
    /// Сколько держится «Готово…».
    public static let doneSeconds: TimeInterval = 4.5

    public static func begin(now: Date) -> State {
        State(phase: .watching, since: now)
    }

    /// Один опрос: видно ли сейчас окно macOS.
    public static func step(_ state: State, windowVisible: Bool, now: Date) -> State {
        var next = state
        switch state.phase {
        case .idle:
            break
        case .watching:
            if windowVisible { return State(phase: .shown, since: now) }
            if now.timeIntervalSince(state.since) >= watchSeconds { return State() }
        case .shown:
            if windowVisible {
                if now.timeIntervalSince(state.since) >= shownSeconds { return State() }
                next.missingSince = nil
            } else {
                let gone = state.missingSince ?? now
                if now.timeIntervalSince(gone) >= goneGrace { return State(phase: .done, since: now) }
                next.missingSince = gone
            }
        case .done:
            // macOS спросила ещё раз следом — снова подсказка.
            if windowVisible { return State(phase: .shown, since: now) }
            if now.timeIntervalSince(state.since) >= doneSeconds { return State() }
        }
        return next
    }

    // MARK: место плашки

    /// Сколько жидкая рамка маяка (`ConsentBeacon`) занимает снаружи окна macOS.
    static let ringReach = ConsentWaterK.gap + ConsentWaterK.thick
    /// Между окном macOS и плашкой: рамка маяка вокруг окна и просвет. Своей рамки у плашки нет с WF246 — второго
    /// запаса под неё тоже нет.
    public static let spacing = ringReach + 10
    /// Отступ плашки от краёв видимой части монитора.
    static let edgeMargin: CGFloat = 4
    /// Плашка шириной с окно macOS — общие края; в этих пределах.
    public static let minWidth: CGFloat = 400
    public static let maxWidth: CGFloat = 520

    public static func plaqueWidth(window: CGRect) -> CGFloat {
        min(max(window.width, minWidth), maxWidth)
    }

    /// Где встать плашке размера `size`: под окном macOS по его оси; не помещается на видимой части монитора
    /// `visible` — над ним, потом справа и слева. Нигде не помещается — под окном: пусть уйдёт за край, но окно
    /// пароля не накроет.
    public static func plaqueFrame(window: CGRect, size: CGSize, visible: CGRect) -> CGRect {
        let room = visible.insetBy(dx: edgeMargin, dy: edgeMargin)
        let x = min(max(window.midX - size.width / 2, room.minX), max(room.minX, room.maxX - size.width))
        let y = min(max(window.minY, room.minY), max(room.minY, room.maxY - size.height))
        let below = CGRect(x: x, y: window.maxY + spacing, width: size.width, height: size.height)
        let tries = [below,
                     CGRect(x: x, y: window.minY - spacing - size.height, width: size.width, height: size.height),
                     CGRect(x: window.maxX + spacing, y: y, width: size.width, height: size.height),
                     CGRect(x: window.minX - spacing - size.width, y: y, width: size.width, height: size.height)]
        return tries.first { room.contains($0) } ?? below
    }

    /// CG (y вниз от верха главного монитора) ↔ Cocoa (y вверх от его низа): пересчёт один в обе стороны.
    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        ConsentBeaconGeometry.cocoaRect(fromCG: rect, primaryHeight: primaryHeight)
    }

    // MARK: окно macOS

    /// Окно на экране: номер у оконного сервера и рамка (CG).
    public struct Target: Equatable {
        public let number: Int
        public let bounds: CGRect

        public init(number: Int, bounds: CGRect) {
            self.number = number
            self.bounds = bounds
        }
    }

    /// Окно пароля связки ключей показывает `SecurityAgent` — узнаём его так же, как маяк окон доступа.
    static let process = "securityagent"

    /// Окно macOS с вопросом о связке ключей, если оно сейчас на экране.
    public static func findWindow() -> Target? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let own = getpid()
        return pick(list.compactMap {
            ConsentWindow.parse($0, ownPID: own, processName: ConsentWindow.executableName)
        })
    }

    /// Из окон запроса — окно `SecurityAgent`; их несколько — самое большое.
    static func pick(_ windows: [ConsentWindow]) -> Target? {
        windows.filter { $0.process.lowercased() == process }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
            .map { Target(number: $0.number, bounds: $0.bounds) }
    }
}
