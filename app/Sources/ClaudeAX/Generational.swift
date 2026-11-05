/// Новое поколение страниц (старт приложения или новый Claude: localStorage умер вместе со страницами) — у всех,
/// кто повторяет команды страницам, один вызов. Контроллер держит их одним списком `generational` (ревизия WF247,
/// С5а), и новая фича вписывает себя в одно место, а не в `onRestart` и `start()` порознь.
protocol Generational: AnyObject {
    func beginGeneration()
}

/// Общий повтор команды страницам по поколениям — это `AutoAllowSwitch` (≈12 экземпляров: PageLook ×9, MicMonitor,
/// AutoContinue, контроллер). Имя по смыслу для нового кода; не удалять — поведение и тесты те же, класс не переименован.
typealias GenerationResend = AutoAllowSwitch

extension AutoAllowSwitch: Generational {}
extension AutoContinueSwitch: Generational {}
extension LiveColorsRetire: Generational {}
extension MicMonitor: Generational {}
extension PageLookSettings: Generational {}
extension ViewerCountsSync: Generational {}
extension WindowThemeStore: Generational {}
