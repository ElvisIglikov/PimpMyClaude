import Foundation

// Идёт ли работа сейчас — один ответ для всех решений об обновлении и перезапуске (WF234).
// До WF234 «работает ли кто-то» приложение знало только по страницам Claude Desktop (`PageSignals`): работа в
// терминальных чатах и Workflow по сводкам проектов была не видна, и карточка у часов звала обновиться словами
// «никто не работает», пока шло семь Workflow. Источников три: страницы (канал probe), идущие Workflow и
// терминальные чаты — оба из той же сводки, что отдаёт `/digest` (К6, К-DG; `ProjectsDigest.work`).
// «Не знаем» (источник молчит или ответ старый) — это не «тихо»: без знания не предлагаем и минут не называем.

/// Работа вне страниц Claude по сводке проектов.
public struct ProjectsWork: Equatable {
    /// Идущих Workflow — число строки «Идёт Workflow сейчас · N»: только у проектов группы «идут».
    public var workflows: Int
    /// В скольких проектах они идут.
    public var projects: Int
    /// Живых терминальных чатов (tmux `rick-<проект>`) — число строки «Работают N терминалов».
    public var terminals: Int
    /// Когда сводка собрана.
    public var at: Date

    public init(workflows: Int = 0, projects: Int = 0, terminals: Int = 0, at: Date) {
        self.workflows = workflows
        self.projects = projects
        self.terminals = terminals
        self.at = at
    }

    public var busy: Bool { workflows > 0 || terminals > 0 }
}

/// Что видно о работе прямо сейчас по всем трём источникам.
public struct WorkNow: Equatable {
    /// Страниц Claude, где идёт ответ; nil — свежего ответа страниц нет.
    public var chats: Int?
    /// Идущих Workflow; nil — свежей сводки нет.
    public var workflows: Int?
    /// В скольких проектах идут Workflow.
    public var projects: Int
    /// Живых терминальных чатов; nil — свежей сводки нет.
    public var terminals: Int?
    /// Секунды с последней работы, видной ЛЮБОМУ источнику (работы не видели — с первого тихого ответа того
    /// источника, что начал наблюдать позже); nil — какой-то источник ещё не наблюдали.
    public var idleSeconds: TimeInterval?

    public init(chats: Int? = nil, workflows: Int? = nil, projects: Int = 0, terminals: Int? = nil,
                idleSeconds: TimeInterval? = nil) {
        self.chats = chats
        self.workflows = workflows
        self.projects = projects
        self.terminals = terminals
        self.idleSeconds = idleSeconds
    }

    /// Работа видна хоть одному источнику.
    public var busy: Bool { (chats ?? 0) > 0 || (workflows ?? 0) > 0 || (terminals ?? 0) > 0 }

    /// true — работа идёт; false — все источники свежо ответили «тихо»; nil — работы не видно, но кто-то из
    /// источников молчит: не знаем.
    public var working: Bool? {
        if busy { return true }
        return chats != nil && workflows != nil && terminals != nil ? false : nil
    }

    /// Claude не запущен или окон нет — страницам работать негде, их молчание не «не знаем»; Workflow и терминалы
    /// спрашиваем всё равно.
    public func seen(claudeRunning: Bool, windowCount: Int) -> WorkNow {
        guard !claudeRunning || windowCount == 0 else { return self }
        var copy = self
        copy.chats = 0
        return copy
    }
}

/// Память о работе вне страниц: последняя сводка и с какого момента по ней тихо. Страницы помнит `ChatProbe`.
public struct WorkWatch: Equatable {
    /// Сводка старше — уже «не знаем» (опрос — раз в `askSeconds`).
    public static let freshSeconds: TimeInterval = 120
    /// Сводку спрашиваем не чаще — тем же шагом, что значок «Проекты».
    public static let askSeconds: TimeInterval = 30

    public private(set) var projects: ProjectsWork?
    /// Когда сводка последний раз показала работу; nil — не показывала.
    public private(set) var lastWorkAt: Date?
    /// Первая тихая сводка после старта Пимпа: от неё тишина, пока работы не видели.
    public private(set) var quietSince: Date?

    public init() {}

    /// Новая сводка; не прочиталась (nil) — прежняя стареет сама и становится «не знаем».
    public mutating func note(_ work: ProjectsWork?) {
        guard let work = work else { return }
        projects = work
        if work.busy { lastWorkAt = work.at } else if quietSince == nil { quietSince = work.at }
    }

    public func now(pages: PageSignals, at now: Date) -> WorkNow {
        let fresh = projects.flatMap { now.timeIntervalSince($0.at) < Self.freshSeconds ? $0 : nil }
        let outside = (lastWorkAt ?? quietSince).map { max(0, now.timeIntervalSince($0)) }
        let idle = pages.idleSeconds(at: now).flatMap { inside in outside.map { min(inside, $0) } }
        return WorkNow(chats: pages.workingChats, workflows: fresh?.workflows, projects: fresh?.projects ?? 0,
                       terminals: fresh?.terminals, idleSeconds: idle)
    }
}
