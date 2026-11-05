import ClaudeAX
import Foundation

extension AppDelegate {
    /// «Повторять при ошибке сервера» (#6936, К-AR): выбор в панели пишется в UserDefaults и сразу уходит страницам.
    func wireAutoRetry() {
        panel.model.pickAutoRetry = { [weak self] on, every in
            let defaults = UserDefaults.standard
            defaults.set(on, forKey: AutoRetry.onKey)
            defaults.set(AutoRetry.minutes(every), forKey: AutoRetry.everyKey)
            self?.applyAutoRetry()
        }
    }

    /// Выбор из UserDefaults — в панель и страницам (нет ключа — выключено, интервал 5 мин).
    func applyAutoRetry() {
        let defaults = UserDefaults.standard
        let on = AutoRetry.isOn(defaults)
        let every = AutoRetry.every(defaults)
        if panel.model.autoRetryOn != on { panel.model.autoRetryOn = on }
        if panel.model.autoRetryEvery != every { panel.model.autoRetryEvery = every }
        ax.configureAutoRetry(on: on, every: every)
    }
}
