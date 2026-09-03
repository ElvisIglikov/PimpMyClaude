import AppKit
import UserNotifications

/// Уведомления приложения. Нужны ровно для одного: Claude обновился, патч слетел —
/// баннер с кнопкой «Поставить снова» (решение 4 плана). Разрешение необязательное:
/// отказали — просто ничего не показываем, значок в строке меню всё равно станет «!».
///
/// Все входы идут через `center`: у голого бинарника из `.build` (без .app вокруг)
/// `UNUserNotificationCenter.current()` падает, поэтому сперва проверяем, что мы в бандле.
enum Notifier {
    static let lostCategory = "PatchLost"
    static let installAction = "InstallAgain"
    private static let lostRequestID = "patch-lost"

    static var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Категория с кнопкой прямо в баннере + делегат, который ловит нажатие.
    static func registerCategory(delegate: UNUserNotificationCenterDelegate) {
        guard let center = center else { return }
        center.delegate = delegate
        let action = UNNotificationAction(identifier: installAction,
                                          title: "Поставить снова",
                                          options: [.foreground])
        let category = UNNotificationCategory(identifier: lostCategory,
                                              actions: [action],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
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
        guard let center = center else { completion(false); return }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional: break
            default: DispatchQueue.main.async { completion(false) }; return
            }
            let content = UNMutableNotificationContent()
            content.title = "Патч Claude слетел"
            content.body = body
            content.categoryIdentifier = lostCategory
            content.sound = .default
            center.add(UNNotificationRequest(identifier: lostRequestID, content: content, trigger: nil)) { error in
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
