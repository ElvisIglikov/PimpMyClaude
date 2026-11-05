import AppKit
import ClaudeAX
import UserNotifications

/// Уведомления приложения: Claude обновился, патч слетел — баннер с кнопкой «Вернуть патч»
/// (решение 4 плана, WF87); скачалось обновление Claude — баннер с кнопками «Обновить» и «Позже»
/// (WF86, WF87). Клики
/// разводятся по категории (`ClaudeUpdateMenu.route`). Разрешение необязательное:
/// отказали — просто ничего не показываем, значок в строке меню всё равно станет «!».
///
/// Все входы идут через `center`: у голого бинарника из `.build` (без .app вокруг)
/// `UNUserNotificationCenter.current()` падает, поэтому сперва проверяем, что мы в бандле.
enum Notifier {
    static let lostCategory = ClaudeUpdateMenu.patchLostCategory
    static let installAction = ClaudeUpdateMenu.patchAgainAction
    /// «Позже» на баннере «Скачалось обновление» — не предлагать 3 часа.
    static let laterAction = "UpdateClaudeLater"
    private static let lostRequestID = "patch-lost"
    private static let readyRequestID = "claude-update-ready"
    /// Проверка окна нашла поломки (#10527): кнопка «Отчёт» открывает файл отчёта, путь — в `userInfo`.
    static let liveCheckCategory = "LiveCheckRed"
    static let liveCheckReportAction = "LiveCheckReport"
    static let liveCheckFileKey = "file"
    private static let liveCheckRequestID = "live-check-red"
    private static let heatRequestID = "mac-heat"

    static var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Категории с кнопкой прямо в баннере + делегат, который ловит нажатие.
    static func registerCategory(delegate: UNUserNotificationCenterDelegate) {
        guard let center = center else { return }
        center.delegate = delegate
        let action = UNNotificationAction(identifier: installAction,
                                          title: "Вернуть патч",
                                          options: [.foreground])
        let category = UNNotificationCategory(identifier: lostCategory,
                                              actions: [action],
                                              intentIdentifiers: [],
                                              options: [])
        let update = UNNotificationAction(identifier: ClaudeUpdateMenu.updateAction,
                                          title: ClaudeUpdateMenu.confirmButton,
                                          options: [.foreground])
        let later = UNNotificationAction(identifier: laterAction, title: ClaudeUpdateMenu.laterButton, options: [])
        let ready = UNNotificationCategory(identifier: ClaudeUpdateMenu.readyCategory,
                                           actions: [update, later],
                                           intentIdentifiers: [],
                                           options: [])
        let report = UNNotificationAction(identifier: liveCheckReportAction, title: "Отчёт", options: [.foreground])
        let live = UNNotificationCategory(identifier: liveCheckCategory, actions: [report], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category, ready, live])
    }

    /// Шаг 3 первого запуска. Отказ ничего не ломает — возвращаем false и идём дальше.
    static func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        guard let center = center else { done(false); return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { done(granted) }
        }
    }

    /// true — разрешено, false — запрещено руками, nil — ещё не спрашивали.
    static func authorization(_ done: @escaping (Bool?) -> Void) {
        guard let center = center else { done(false); return }
        center.getNotificationSettings { settings in
            let value: Bool?
            switch settings.authorizationStatus {
            case .authorized, .provisional: value = true
            case .notDetermined: value = nil
            default: value = false
            }
            DispatchQueue.main.async { done(value) }
        }
    }

    /// Одно уведомление «патч слетел». Повтор гасит сам центр: id запроса один и тот же.
    static func postPatchLost(_ body: String, completion: @escaping (Bool) -> Void = { _ in }) {
        post(id: lostRequestID, title: "Патч Claude слетел", body: body, category: lostCategory, completion: completion)
    }

    /// «Скачалось обновление Claude X» с кнопкой «Обновить». Повтор гасит id запроса.
    static func postClaudeReady(version: String, completion: @escaping (Bool) -> Void = { _ in }) {
        post(id: readyRequestID, title: ClaudeUpdateMenu.readyNotificationTitle(version: version),
             body: ClaudeUpdateMenu.readyNotificationBody, category: ClaudeUpdateMenu.readyCategory, completion: completion)
    }

    /// «Claude 3.1623: Пимп нашёл поломки — …» с кнопкой «Отчёт» (#10527): одно на версию — его зовут один раз.
    static func postLiveCheck(_ body: String, file: URL?) {
        post(id: liveCheckRequestID, title: "Проверка окна Claude", body: body, category: liveCheckCategory,
             userInfo: file.map { [liveCheckFileKey: $0.path] } ?? [:], completion: { _ in })
    }

    /// «Мак перегрелся» (#10998): что грузит — в тексте; не чаще раза в 30 мин решает `MacHeatWarner`, повтор id заменяет.
    static func postHeatWarn(title: String, body: String) {
        post(id: heatRequestID, title: title, body: body, category: "", completion: { _ in })
    }

    /// Проверить разрешение и показать уведомление со звуком; `completion` — на главной очереди, показано ли.
    private static func post(id: String, title: String, body: String, category: String,
                             userInfo: [String: String] = [:], completion: @escaping (Bool) -> Void) {
        guard let center = center else { completion(false); return }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional: break
            default: DispatchQueue.main.async { completion(false) }; return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = category
            content.userInfo = userInfo
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }

    /// Патч снова на месте — снимаем баннер из центра уведомлений.
    static func clearPatchLost() {
        guard let center = center else { return }
        center.removeDeliveredNotifications(withIdentifiers: [lostRequestID])
    }
}
