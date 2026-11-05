import Foundation

// MARK: «Обновить при следующем запуске» (#10765, WF283)

// Слово Элвиса 23.10.2026: «Там должно быть две, наверное, кнопки обновить сейчас… или обновить при следующем запуске.
// И после этого, если обновить при следующем запуске, он должен типа как-то свернуться. Ну, чтобы не маячить… чтоб
// человек понимал, что обновление его ждёт при следующем запуске клауда». Отложенная версия лежит в UserDefaults и
// переживает перезапуск Пимпа; вышла другая — снова полная карточка. Ставится, как только Claude не запущен.

extension PimpPanelText {
    /// Какую готовую версию отложили «При запуске» (String); другая версия — ключ не действует.
    public static let updatePlannedKey = "claudeUpdateNextLaunchVersion"

    /// Свёрнутая карточка — одна тихая строка; номер версии — в подсказке (`plannedHelp`) и в «Настройках», в строку
    /// рядом с «Сейчас · Отменить» он не влезает.
    public static let plannedLine = "Claude обновится при запуске"
    public static func plannedHelp(_ version: String) -> String {
        "Claude \(version) скачан. Обновлю, как только Claude закроют, — сам его не открою. Перезапуск Claude из PMP тоже обновит"
    }
    public static let plannedNowTitle = "Сейчас"
    public static let plannedCancelTitle = "Отменить"
    /// Подсказки: что будет и когда — раскрывают строку, которую в панели сказать коротко.
    public static let plannedNowHelp = "Обновить сейчас: Claude закроется секунд на 20, спрошу, если идёт работа"
    public static let plannedCancelHelp = "Вернуть карточку с кнопкой «Обновить сейчас»"
    /// Подсказка второй кнопки карточки.
    public static let nextLaunchHelp = "Свернуть в строку: обновлю, когда Claude закроют или PMP его перезапустит"

    /// Ставить ли отложенное прямо сейчас: отложена ровно готовая версия, PMP ничем не занят (патч, установка,
    /// перезапуск, загрузка, перепроверка готового) и Claude не запущен (прерывать нечего) — или PMP сам его
    /// перезапускает (`restarting`, `restart-claude`): перезапуск и есть «следующий запуск».
    public static func installPlannedNow(planned: String?, ready: String?, claudeRunning: Bool, restarting: Bool = false,
                                         pimpBusy: Bool) -> Bool {
        guard let planned = planned, planned == ready, !pimpBusy else { return false }
        return !claudeRunning || restarting
    }
}
