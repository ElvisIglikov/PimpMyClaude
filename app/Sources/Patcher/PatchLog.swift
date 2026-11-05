/// Начала строк журнала патчера и обновителя Claude, по которым панель узнаёт шаг (`PimpPanelText.patchStep`,
/// `installStep`): пишут и узнают одной константой (ревизия WF247, С5б). Целые строки ожидания человека —
/// `Patcher.appManagementWaitLine`, `claudeQuitWaitLine`, `ownershipLine`.
public enum PatchLog {
    public static let opensClaude = "Открываю Claude"
    public static let closesClaude = "Закрываю Claude"
    public static let forceQuit = "закрываю принудительно"
    public static let installsLoader = "Ставлю лоадер"
    public static let savesOriginal = "Сохраняю оригинал"
    public static let installsPatch = "Ставлю патч"
    public static let restoresOriginals = "Возвращаю оригинальные"
    public static let replacesClaude = "Меняю Claude"
    public static let permissionGranted = "Право «Управление приложениями» есть"
    public static let ownership = "Claude.app принадлежит"
}
