import ClaudeAX
import Foundation

/// Умолчания 03.11.2026 (`docs/decisions/2026-11-03-oformlenie.md`: шрифт панели 49.4, белый акцент, ракета 150 %,
/// Workflow скрыт и у сохранённых раскладок) — только новой установке (#11655, находка 3 проверки слияния PR #21).
/// У кого Пимп уже стоял, один раз записываются прежние умолчания — 2.4 (слово Элвиса 17.10.2026: «его берём»),
/// фиолетовый, 100 %, Workflow как был; выбранное человеком не трогается. Уже жил с умолчаниями 03.11 (сборка Оли
/// поставила `workflowHiddenKey`) — тоже мимо. Зовёт `AppDelegate` со снимком настроек до первой записи.
enum KeepOldDefaults {
    static let doneKey = "keepOldDefaults1105"
    static let typography = "2.4"
    static let accent = PMPAccent.violet
    static let rocketSize = 100

    /// true — прежние умолчания записаны.
    @discardableResult
    static func apply(values: [String: Any], installed: Data?, defaults: UserDefaults = .standard) -> Bool {
        guard values[doneKey] == nil else { return false }
        defaults.set(true, forKey: doneKey)
        guard !PanelColorTiles.isNewInstall(values: values, installed: installed),
              values[PanelWidgetLayout.workflowHiddenKey] == nil else { return false }
        if values[PanelTypography.key] == nil { defaults.set(typography, forKey: PanelTypography.key) }
        if values[PMPAccent.key] == nil { defaults.set(accent.rawValue, forKey: PMPAccent.key) }
        if values[SendLook.sizeKey] == nil { defaults.set(rocketSize, forKey: SendLook.sizeKey) }
        defaults.set(true, forKey: PanelWidgetLayout.workflowHiddenKey)   // сохранённая раскладка — как была
        return true
    }
}
