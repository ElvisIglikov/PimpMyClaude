import Foundation

extension ClaudeAXController {
    /// «Повторять при ошибке сервера» (#6936, К-AR): смена выбора уходит страницам сразу, повторное применение тех же
    /// настроек — нет; новое поколение страниц получает выбор повтором на общем тике.
    public func configureAutoRetry(on: Bool, every: Int) {
        guard autoRetrySwitch.configure(on: on, every: every), started else { return }
        commands.write(action: AutoRetry.action, fields: AutoRetry.fields(on: autoRetrySwitch.on, every: autoRetrySwitch.every))
    }
}
