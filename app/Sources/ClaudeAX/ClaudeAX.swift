import Foundation

/// Команды страницам и окнам (меню, хоткеи, command.json). Менять только по согласованию на гейте.
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
