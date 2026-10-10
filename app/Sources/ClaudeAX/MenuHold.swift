import AppKit

/// Замок «меню PMP открыто» (WF145, диагноз WF137): фоновые `ClaudeApp.focus`/`activate`/raise (тики, показ ждущего
/// окна, раскладка, возврат из просмотра файла) выводили Claude вперёд и закрывали открытое меню — на жёлтой кнопке
/// окна, у часов. Пока замок держат, такие действия откладываются и идут разом после закрытия, по порядку.
///
/// Кто держит: любое NSMenu процесса (`NSMenu.didBeginTracking`/`didEndTracking` — меню кнопки окна, у часов,
/// подменю). Пропущенный конец не запирает навсегда:
/// держатель старше `maxHold` не считается, отложенное тогда уходит по таймеру. Только главный поток.
public final class MenuHold {
    public static let shared = MenuHold()

    /// Дольше этого меню само не висит: держатель старше — забытый (конец потерялся).
    static let maxHold: TimeInterval = 120
    /// Больше отложенных не копим: тики за долгое открытое меню — старые выбрасываем, последние важнее.
    static let maxDeferred = 16

    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Таймер страховки; тестам — подменить.
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private var holders: [ObjectIdentifier: TimeInterval] = [:]
    private var deferred: [() -> Void] = []
    /// Держатели-меню (для снятия разом по концу корневого).
    private var menus = Set<ObjectIdentifier>()
    private var observers: [NSObjectProtocol] = []

    init() {}

    /// Подписка на меню процесса — один раз, из контроллера.
    public func start(center: NotificationCenter = .default) {
        guard observers.isEmpty else { return }
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                            queue: nil) { [weak self] note in
            guard let menu = note.object as? NSMenu else { return }
            self?.menus.insert(ObjectIdentifier(menu))
            self?.begin(menu)
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil,
                                            queue: nil) { [weak self] note in
            guard let menu = note.object as? NSMenu else { return }
            self?.endMenu(menu, root: menu.supermenu == nil)
        })
    }

    /// Конец слежения за меню: корневое (у часов, жёлтой кнопки) закрывается целиком — снимаем и все подменю,
    /// даже если их конец не пришёл; подменю — только себя.
    func endMenu(_ menu: AnyObject, root: Bool) {
        if root {
            for id in menus { holders.removeValue(forKey: id) }
            menus = []
        }
        menus.remove(ObjectIdentifier(menu))
        end(menu)
        if root { schedule(0) { [weak self] in self?.flush() } }
    }

    /// Открыто ли меню сейчас (без забытых держателей).
    public var isHeld: Bool {
        let at = now()
        holders = holders.filter { at - $0.value < Self.maxHold }
        return !holders.isEmpty
    }

    public func begin(_ holder: AnyObject) {
        holders[ObjectIdentifier(holder)] = now()
    }

    public func end(_ holder: AnyObject) {
        guard holders.removeValue(forKey: ObjectIdentifier(holder)) != nil else { return }
        // Следующим тиком: действие пункта меню и подменю, закрывающееся вместе с родителем, успевают отработать.
        schedule(0) { [weak self] in self?.flush() }
    }

    /// Фоновое действие с фокусом: меню закрыто — сразу, открыто — после закрытия.
    public func run(_ action: @escaping () -> Void) {
        guard Thread.isMainThread, isHeld else { return action() }
        deferred.append(action)
        if deferred.count > Self.maxDeferred { deferred.removeFirst(deferred.count - Self.maxDeferred) }
        if deferred.count == 1 {
            // Страховка от потерянного конца: держатель устареет — отложенное уйдёт.
            schedule(Self.maxHold) { [weak self] in self?.flush() }
        }
    }

    /// Отложенное — по порядку, если замок снят.
    func flush() {
        guard !isHeld, !deferred.isEmpty else { return }
        let ready = deferred
        deferred = []
        ready.forEach { $0() }
    }

    /// Сколько ждёт — тестам.
    var pending: Int { deferred.count }
}
