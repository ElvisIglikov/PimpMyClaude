import CoreGraphics
import Foundation

/// «Чат в главное окно» (WF108, #8148): чистая часть — кого с кем менять. Работа канала (закрыть окно
/// цели, команда `main-chat` главной странице, дождаться вынесенного прежнего чата, поменять рамки) —
/// в `PimpChannel` (`runMain`/`advanceMain`), её гоняют тесты `MainChatTests`.
extension PimpChannel {
    /// Команда главной странице (страница, раздел 12б): `{id, action, at, scope, title, match?, x, y, chat}`.
    static let mainChatAction = "main-chat"
    /// Ключ живого `claude.json`: чей чат держать в главном окне (имя проекта или `local_…`). Нет ключа — ничего.
    static let mainChatKey = "mainChat"
    /// Сколько ждём, пока закроется окно названного чата, прежде чем звать страницу.
    static let mainCloseSeconds: TimeInterval = 3

    /// Кого с кем менять.
    enum MainPlan: Equatable {
        /// Главное окно открывает `chat`; `target` — его отдельное окно (закрыть до команды), nil — окна нет.
        case swap(main: PimpWindow, chat: String, target: PimpWindow?)
        /// Чат уже в главном окне — ничего не трогаем.
        case already(chat: String)
        /// Отказ; `list` — заголовки окон (`ambiguous`, `chat-unknown`) или имена проектов (`project-missing`).
        case refuse(Failure, list: [String])
    }

    /// Ровно одно из `chat` (`local_…`) или `project` (имя папки или путь, как у `send`). Главное окно — то,
    /// что `isMain` зовёт главным; два таких — `ambiguous`, ни одного — `window-missing`. Проект без окна —
    /// его последний чат по индексу Claude (`lastChat`), как `open --last`.
    static func mainPlan(chat: String, project: String, windows: [PimpWindow], isMain: (String) -> Bool,
                         projects: [Project], lastChat: (URL) -> (chat: String, title: String)?) -> MainPlan {
        let mains = windows.filter { $0.isMain(using: isMain) }
        guard mains.count < 2 else { return .refuse(.ambiguous, list: mains.map { $0.title }) }
        guard let main = mains.first else { return .refuse(.windowMissing, list: []) }
        let others = windows.filter { !$0.isMain(using: isMain) }
        let pick: (String, PimpWindow?) -> MainPlan = { wanted, target in
            !main.chat.isEmpty && main.chat == wanted ? .already(chat: wanted)
                : .swap(main: main, chat: wanted, target: target)
        }
        if !chat.isEmpty {
            let hits = others.filter { $0.chat == chat }
            guard hits.count < 2 else { return .refuse(.ambiguous, list: hits.map { $0.title }) }
            return pick(chat, hits.first)
        }
        // Проект уже в главном окне — хватит: второй его чат окном («Рик» и «Рик 2») главным не делаем.
        if matches(window: main, entry: project) { return .already(chat: main.chat) }
        let hits = others.filter { matches(window: $0, entry: project) }
        guard hits.count < 2 else { return .refuse(.ambiguous, list: hits.map { $0.title }) }
        if let hit = hits.first {
            guard !hit.chat.isEmpty else { return .refuse(.chatUnknown, list: [hit.title]) }
            return pick(hit.chat, hit)
        }
        guard let found = PimpChannel.project(named: project, in: projects) else {
            return .refuse(.projectMissing, list: projects.map { $0.name })
        }
        guard let last = lastChat(found.folder) else { return .refuse(.chatMissing, list: []) }
        return pick(last.chat, nil)
    }

    /// Рамки после замены: главное окно — на место окна цели, вынесенный прежний чат — на место главного.
    /// Окна цели не было — не двигаем никого: новое окно стоит, где родилось.
    static func mainMoves(main: PimpWindow, target: PimpWindow?, popped: CGWindowID?) -> [PimpMove] {
        guard let target = target else { return [] }
        var moves = [PimpMove(id: main.id, frame: target.frame)]
        if let popped = popped { moves.insert(PimpMove(id: popped, frame: main.frame), at: 0) }
        return moves
    }

    /// Поля ответа `main`: `chat` — чей чат теперь в главном окне, `popped` — чей чат ушёл в своё окно
    /// ("" — никакой), `already` — чат уже был в главном окне.
    static func mainFields(chat: String, popped: String, already: Bool) -> [(key: String, value: CommandValue)] {
        [(key: "chat", value: .string(chat)),
         (key: "popped", value: .string(popped)),
         (key: "already", value: .bool(already))]
    }

    /// `mainChat` живого `claude.json`: строка без краевых пробелов; нет файла, ключа или не строка — nil.
    static func mainChatSetting(_ data: Data?) -> String? { liveString(data, key: mainChatKey) }

    /// Ключ живого `claude.json` (гейт WF111, #8284): главный проект — имя папки или путь, как запись `order`.
    /// Слово Элвиса 30.09: главное окно Claude маленькое в углу («чтобы там чисто Allow отстреливали»),
    /// а Рик — попапом впереди. Окна этого проекта hide не сворачивает, притемнение их не трогает, рамки
    /// внимания на них нет. Нет ключа — всё как прежде (главное — только главное окно Claude).
    static let mainProjectKey = "mainProject"

    /// `mainProject` живого `claude.json`, по тем же правилам, что `mainChat`.
    static func mainProjectSetting(_ data: Data?) -> String? { liveString(data, key: mainProjectKey) }

    /// Окно главного проекта: папка окна совпала с записью (`matches(folder:entry:)`); нет записи — нет.
    static func isMainProject(folder: String, entry: String?) -> Bool {
        guard let entry = entry else { return false }
        return matches(folder: folder, entry: entry)
    }

    /// id чатов окон главного проекта — поле `keep` команды `dim`: без повторов и пустых, по порядку.
    static func mainProjectChats(_ windows: [PimpWindow], entry: String?) -> [String] {
        var seen = Set<String>()
        return windows.filter { isMainProject(folder: $0.folder, entry: entry) }.map { $0.chat }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Строковый ключ живого `claude.json` без краевых пробелов; нет файла, ключа или не строка — nil.
    private static func liveString(_ data: Data?, key: String) -> String? {
        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = json[key] as? String else { return nil }
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
