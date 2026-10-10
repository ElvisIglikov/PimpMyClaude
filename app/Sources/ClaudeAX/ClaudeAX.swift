import Foundation

/// Контракт между AX-модулем (батч B) и приложением (батч A/C). Менять только по согласованию на гейте.
public enum ClaudeCommand: String, CaseIterable {
    /// `workflow` — первый пункт меню (решение 3 плана WF9): кладёт комплект воркфлоу
    /// в Application Support и вставляет текст кикоффа в поле ввода окна.
    /// `newWindow`/`popoutWindow` — план WF13: новый чат сразу отдельным окном и вынос
    /// текущего чата в окно; в command.json их действия пишутся через дефис.
    /// `autoAllow` — выключатель К3: строковое `{on:"true"|"false"}` всем страницам.
    /// `mic` — режим кружка-микрофона (контракт К4 плана WF84, #7054): `{mode:"dictator"|"claude"}`
    /// на все окна; `dictator` — только пока запущен Диктатор. Шлёт `MicMonitor` по запуску и
    /// выходу Диктатора и в каждом поколении страниц; пункта меню и клавиши нет.
    case workflow, cashout, newChat, newWindow = "new-window", popoutWindow = "popout-window", collapse, expand, arrange, show, scroll
    case autoAllow = "auto-allow-once"
    case mic
}

public protocol ClaudeAXControlling: AnyObject {
    /// Запустить опрос окон Claude, меню на кнопке «Свернуть», хоткеи, блок ⌘Q.
    func start()
    func stop()
    var autoAllowEnabled: Bool { get set }
    func configureAutoContinue(on: Bool, preservePageChoice: Bool)
    var autoContinueReported: Bool? { get }
    var minimizeMenuEnabled: Bool { get set }
    var blockQuitEnabled: Bool { get set }
    /// Отправить команду во все окна Claude (пишет command.json в Application Support/MyClaude).
    func send(_ command: ClaudeCommand)
    /// Обновление Claude (WF86, критик WF87 п. 2): `true` — перед закрытием Claude заморозить снимок
    /// окон (К5), пока не появится новый Claude, иначе окна другой копии перепишут снимок; `false` —
    /// обновление сорвалось до закрытия, снимок ведётся дальше.
    func freezeWindowSnapshot(_ frozen: Bool)
    /// Лимиты подписки и «работает ли чат» по ответам страниц (WF87, канал probe): значок у
    /// часов, панель и «самое время» обновить Claude. Главная нить.
    var pageSignals: PageSignals { get }
    /// Спросить страницы о работе прямо сейчас, мимо минутного круга (гейт 2 WF87): «Обновить»
    /// решает по ответу, пришедшему после нажатия (`PageSignals.answered(after:)`). Главная нить.
    func refreshPageSignals()
    /// «🙈 Спрятать окна» (WF112, #8255): свернуть все окна Claude, кроме главного. Главная нить.
    func hideOthers() -> WindowHideResult
    /// «👀 Показать окна»: развернуть свёрнутые окна Claude, фокус — главному. Главная нить.
    func showHidden() -> WindowHideResult
    /// Показанный выбор: явный выбор приложения, одна ответившая страница или 5 с.
    var sendDelaySetting: SendDelaySetting { get }
    func setSendDelay(on: Bool, seconds: Int)
    /// nil — запрос показа принят; строка — причина отказа для панели.
    func previewSendDelay(seconds: Int) -> String?
    /// «Закреплённые» (#8743): название проекта и таймер у закреплённых чатов; запись шлёт выбор страницам.
    var pinnedLook: PinnedLook { get set }
}

// Реализация — ClaudeAXController.swift.
