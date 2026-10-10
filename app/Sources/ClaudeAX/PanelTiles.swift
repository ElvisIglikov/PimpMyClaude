import Foundation

// Панель PMP, WF129 (#9043, #9077): «Идут Workflow» плиткой по проектам, блоки-виджеты и сводка всех проектов
// для значка у часов. Чистая часть — группы плиток, раскладка виджетов, строка сводки, разбор `tmux ls`;
// вид — `PimpPanel.swift`, тесты — `PanelTilesWF129Tests`.

/// Плитка проекта в «Идут Workflow».
public struct PanelTile: Equatable, Identifiable {
    public enum Group: Equatable { case running, waiting, doneToday }

    public var id: String { folder }
    public let folder: String
    public let name: String
    public let marker: String
    /// Строка марафона из шапки сводки; нет — пусто.
    public let marathon: String
    /// «Workflow 1, 2 из 3» (идут) / «готово 3 из 3»; Workflow нет — пусто.
    public let count: String
    /// О чём идущий (ждущий, последний готовый) Workflow.
    public let about: String
    /// «кодинг · шаг 1 из 3» / «ждёт Элвиса» / «готово · 1 ч» / «чат в терминале».
    public let phase: String
    /// Состояния всех Workflow по порядку — тонкая полоска.
    public let segments: [PanelWorkflow.State]
    /// Живой чат в терминале (tmux `rick-<проект>`).
    public let terminal: Bool
    /// Идёт и при этом ждёт Элвиса (строка «Ждёт Элвиса» или блок ✋).
    public let waits: Bool
    /// Идущий упал — фаза красным.
    public let failed: Bool
    /// Подсказка: «сейчас» сводки и что ждёт.
    public let help: String
    /// Чего ждёт от Элвиса — строка «Ждут тебя» (WF214); не ждёт — пусто.
    public let wait: String
}

public struct PanelTileGroup: Equatable, Identifiable {
    public var id: String { title }
    public let group: PanelTile.Group
    public let title: String
    public let tiles: [PanelTile]
}

public enum PanelTiles {
    public static let numbersLimit = 3

    /// Группы сверху вниз: «Идут», «Ждут Элвиса», «Готово сегодня»; пустых нет. Проект — в одной группе:
    /// идёт — «Идут» (даже если и ждёт), только ждёт — «Ждут Элвиса», всё готово и сводка сегодняшняя —
    /// «Готово сегодня». Живой чат в терминале без своей группы — тоже «Идут». Внутри группы свежие (сводка правлена
    /// позже) — наверх (WF141, Рик: «в ячейках и списках новые — наверх»).
    public static func groups(_ snapshot: PanelSnapshot, now: Date, calendar: Calendar = .current) -> [PanelTileGroup] {
        var seen = Set<String>()
        var running: [PanelTile] = [], waiting: [PanelTile] = [], done: [PanelTile] = []
        let all = snapshot.working + snapshot.waiting + snapshot.others
        let order = all.indices.sorted { left, right in
            let a = all[left].updated ?? .distantPast, b = all[right].updated ?? .distantPast
            return a != b ? a > b : left < right
        }
        for project in order.map({ all[$0] }) where !seen.contains(project.folder) {
            seen.insert(project.folder)
            let terminal = hasTerminal(project, snapshot.terminals)
            if !project.running.isEmpty {
                running.append(tile(project, .running, terminal: terminal))
            } else if project.waits {
                waiting.append(tile(project, .waiting, terminal: terminal))
            } else if let updated = project.updated, calendar.isDate(updated, inSameDayAs: now),
                      !project.workflows.isEmpty, project.workflows.allSatisfy({ $0.state == .done }) {
                done.append(tile(project, .doneToday, terminal: terminal))
            } else if terminal {
                running.append(tile(project, .running, terminal: true))
            }
        }
        return [(PanelTile.Group.running, "Идут", running), (.waiting, "Ждут Элвиса", waiting),
                (.doneToday, "Готово сегодня", done)]
            .filter { !$0.2.isEmpty }
            .map { PanelTileGroup(group: $0.0, title: $0.1, tiles: $0.2) }
    }

    /// Сессия `rick-<папка>` или `rick-<имя сводки>`, без учёта регистра.
    static func hasTerminal(_ project: PanelProject, _ terminals: Set<String>) -> Bool {
        let names = Set(terminals.map { $0.lowercased() })
        let folder = URL(fileURLWithPath: project.folder).lastPathComponent.lowercased()
        return names.contains(folder) || names.contains(project.name.lowercased())
    }

    static func tile(_ project: PanelProject, _ group: PanelTile.Group, terminal: Bool) -> PanelTile {
        let all = project.workflows
        let live: [Int] = group == .doneToday ? [] : all.indices.filter {
            [.running, .waiting, .failed].contains(all[$0].state)
        }
        let doneCount = all.filter { $0.state == .done }.count
        var count = ""
        if !live.isEmpty {
            var numbers = live.prefix(numbersLimit).map { String($0 + 1) }.joined(separator: ", ")
            if live.count > numbersLimit { numbers += "…" }
            count = "Workflow \(numbers) из \(all.count)"
        } else if !all.isEmpty {
            count = "готово \(doneCount) из \(all.count)"
        }
        let current = project.running.first ?? live.first.map { all[$0] }
        let failed = current?.state == .failed
        let about: String
        let phase: String
        switch group {
        case .running:
            guard let workflow = current else {
                about = project.now
                phase = "чат в терминале"
                break
            }
            about = workflow.about
            let name = workflow.phases.first { $0.state == .current || $0.state == .failed }?.name ?? ""
            let steps = workflow.stepsDone.flatMap { done in workflow.stepsTotal.map { "шаг \(done) из \($0)" } }
            phase = failed ? ([name, "упал"].filter { !$0.isEmpty }.joined(separator: " · "))
                : [name, steps ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        case .waiting:
            about = current?.about ?? (project.note.isEmpty ? project.words.joined(separator: " · ") : project.note)
            phase = "ждёт Элвиса"
        case .doneToday:
            let last = all.last { $0.state == .done }
            about = last?.about ?? ""
            phase = last.map { $0.duration.isEmpty ? "готово" : "готово · \($0.duration)" } ?? "готово"
        }
        let waitsToo = group == .running && project.waits
        // Что идёт — в подсказке (31.1): «10 · о чём · 1/3», номера вразбивку в квадрат не влезают.
        var lines = live.map { index -> String in
            let workflow = all[index]
            let steps = workflow.stepsDone.flatMap { done in workflow.stepsTotal.map { "\(done)/\($0)" } }
            let mark = workflow.state == .failed ? "упал" : workflow.state == .waiting ? "ждёт" : steps
            return ["\(index + 1)", workflow.about, mark ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        lines.append(project.now)
        let what = project.note.isEmpty ? project.words.map { "«\($0)»" }.joined(separator: "; ") : project.note
        if waitsToo || group == .waiting, !what.isEmpty { lines.append("Ждёт Элвиса: " + what) }
        let help = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        let wait = waitsToo ? what : group == .waiting ? (what.isEmpty ? about : what) : ""
        return PanelTile(folder: project.folder, name: project.name, marker: project.marker,
                         marathon: project.marathon, count: count, about: about, phase: phase,
                         segments: all.map { $0.state }, terminal: terminal, waits: waitsToo, failed: failed,
                         help: help, wait: wait)
    }

    // MARK: «Идёт Workflow сейчас» кольцами (WF214, #9404; макет `docs/31.html` 31.2)

    /// Подпись блока — слово Элвиса 10.10.2026 дословно.
    public static let nowTitle = "Идёт Workflow сейчас"
    public static let nowEmpty = "Сейчас ничего не идёт"
    /// Плиток-колец в ряд («то, что их по три влезает, очень круто»).
    public static let ringColumns = 3
    /// Строк «Ждут тебя» в блоке; остальные — одной строкой имён.
    public static let waitersLimit = 3

    /// Число в подписи блока: идущие Workflow всех плиток «Идут».
    public static func runningCount(_ groups: [PanelTileGroup]) -> Int {
        (groups.first { $0.group == .running }?.tiles ?? []).reduce(0) { $0 + $1.segments.filter { $0 == .running }.count }
    }

    /// «идёт» / «идут» по числу: 1, 21 — «идёт».
    public static func goes(_ count: Int) -> String { count % 10 == 1 && count % 100 != 11 ? "идёт" : "идут" }

    /// Кольцо плитки: доля готовых Workflow 0…1 и подпись «9/12»; Workflow нет (только чат в терминале) — пусто.
    public static func ring(_ tile: PanelTile) -> (fraction: Double, text: String) {
        let total = tile.segments.count
        guard total > 0 else { return (0, "") }
        let done = tile.segments.filter { $0 == .done }.count
        return (Double(done) / Double(total), "\(done)/\(total)")
    }

    /// Под именем плитки: «3 идут»; идущих нет — «упал» (красным), «ждёт» или «терминал».
    public static func ringWords(_ tile: PanelTile) -> (text: String, failed: Bool) {
        let running = tile.segments.filter { $0 == .running }.count
        if running > 0 { return ("\(running) \(goes(running))", false) }
        if tile.failed || tile.segments.contains(.failed) { return ("упал", true) }
        return (tile.segments.isEmpty ? "терминал" : "ждёт", false)
    }

    /// Точка в углу плитки: упал — красная, ждёт Элвиса — жёлтая, иначе нет.
    public enum Corner: Equatable { case failed, waits }

    public static func corner(_ tile: PanelTile) -> Corner? {
        if tile.failed || tile.segments.contains(.failed) { return .failed }
        return tile.waits ? .waits : nil
    }

    /// «Ждут тебя»: идущие, что ещё и ждут, потом те, где ничего не идёт, — как в макете.
    public static func waiters(_ groups: [PanelTileGroup]) -> [PanelTile] {
        (groups.first { $0.group == .running }?.tiles ?? []).filter { $0.waits }
            + (groups.first { $0.group == .waiting }?.tiles ?? [])
    }

    // MARK: сводка у часов (#9077)

    /// «⏳ 3 · ✋ 1 · WF 4/11»: идут, ждут, готово из всех Workflow идущих и ждущих проектов; ничего не идёт —
    /// «✅ 2» (готово сегодня) или «—».
    public static func summary(_ groups: [PanelTileGroup]) -> String {
        let running = groups.first { $0.group == .running }?.tiles ?? []
        let waiting = groups.first { $0.group == .waiting }?.tiles ?? []
        let done = groups.first { $0.group == .doneToday }?.tiles ?? []
        let active = running + waiting
        let total = active.reduce(0) { $0 + $1.segments.count }
        let finished = active.reduce(0) { $0 + $1.segments.filter { $0 == .done }.count }
        var parts: [String] = []
        if !running.isEmpty { parts.append("⏳ \(running.count)") }
        if !waiting.isEmpty { parts.append("✋ \(waiting.count)") }
        if total > 0 { parts.append("WF \(finished)/\(total)") }
        if parts.isEmpty { return done.isEmpty ? "—" : "✅ \(done.count)" }
        return parts.joined(separator: " · ")
    }

    /// Подсказка значка: по строке на группу — «Идут: PimpMyClaude — Workflow 1, 2 из 3 · кодинг; …».
    public static func summaryHelp(_ groups: [PanelTileGroup]) -> String {
        guard !groups.isEmpty else { return "PMP — Workflow сейчас не идут" }
        return (["PMP — проекты"] + groups.map { group in
            group.title + ": " + group.tiles.map { tile in
                tile.name + ([tile.count, tile.phase].filter { !$0.isEmpty }.isEmpty ? ""
                    : " — " + [tile.count, tile.phase].filter { !$0.isEmpty }.joined(separator: " · "))
            }.joined(separator: "; ")
        }).joined(separator: "\n")
    }

    // MARK: терминальные чаты

    /// Имена проектов из `tmux ls -F '#{session_name}'` (или обычного `tmux ls`): сессии `rick-<проект>`.
    public static func terminals(_ output: String) -> Set<String> {
        var names = Set<String>()
        for line in output.components(separatedBy: "\n") {
            let session = line.split(separator: ":", maxSplits: 1).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard session.hasPrefix("rick-"), session.count > 5 else { continue }
            names.insert(String(session.dropFirst(5)))
        }
        return names
    }

    /// Где искать tmux: у приложения из Finder в PATH нет Homebrew.
    static let tmuxPaths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    /// Живые сессии `rick-…` (в фоне, не дольше 2 с). tmux нет, сервер не запущен — пусто.
    public static func liveTerminals(fileManager: FileManager = .default) -> Set<String> {
        guard let tmux = tmuxPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = ["ls", "-F", "#{session_name}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationStatus == 0 else { return [] }
        return terminals(String(decoding: data, as: UTF8.self))
    }
}

// MARK: - виджеты панели

/// Блок панели, который можно двигать и делать уже/шире (#9043). Порядок `allCases` — «как было».
/// WF171 (#9177, слово Элвиса 09.10 00:15: «Убери её пока… Не нужны они мне… Он очень лёгким должен быть»):
/// «Идут Workflow», «Workflow списком» и «Остальные проекты» из панели сняты — их id (`tiles`, `workflows`,
/// `projects`) в сохранённых раскладках `normalized()` выкидывает как чужие. Сводка проектов (`PanelTiles`,
/// `ProjectsDigest`) живёт дальше: значок у часов, /digest, полоса страницы.
/// WF174 (#9182 п. 5: «Фейбл пятичасовая расценивается как одна панель, не очень интуитивно»): «5 часов» (id прежний —
/// `limits`) и «Fable» — два блока, по умолчанию половинками в одном ряду; блок можно скрыть и вернуть.
/// WF214 (#9404, слово Элвиса 10.10.2026 02:05: «31.2, живые данные. Очень прикольно… такие невесомые виджеты, то,
/// что их по три влезает, очень круто»): «Идёт Workflow сейчас» возвращается кольцами 31.2 — новым блоком `workflow`,
/// первым; у сохранённых раскладок он встаёт сверху (`normalized`), скрывается крестиком, как прочие.
/// WF177 (#9196, слово Элвиса 09.10 02:35: «Элемент управления по темам перегруженный — он должен быть внизу»):
/// «Цвет Claude» — последним; сохранённые раскладки переезжают один раз (`load`, ключ `colorsLastKey`).
public enum PanelWidget: String, CaseIterable {
    case workflow, week, limits, fable, reset, temperature, memory, tokens, colors

    /// Имя в меню правого клика и в строке «Скрытые».
    public var title: String {
        switch self {
        case .colors: return "Оформление"
        case .workflow: return PanelTiles.nowTitle
        case .week: return "Неделя"
        case .limits: return "5 часов"
        case .fable: return "Fable"
        case .reset: return "Сброс"
        case .temperature: return "Температура"
        case .memory: return "Память"
        case .tokens: return "Токены"
        }
    }

    /// Три кольца в ряд и подпись «Идёт Workflow сейчас» в половину панели не встают — этот блок только во всю ширину.
    public var canNarrow: Bool { self != .workflow }

    /// Ширина «как было»: «5 часов» и «Fable» — половинками рядом, остальные во всю ширину.
    public var defaultWide: Bool { self != .limits && self != .fable }
}

/// Раскладка виджетов: порядок и ширина (2 колонки — `wide`, 1 — нет). Хранится JSON-строкой
/// в `UserDefaults["panelLayoutWF129"]`; нет ключа или мусор — «как было» (все во всю ширину).
public struct PanelWidgetLayout: Equatable {
    public struct Item: Hashable, Codable, Identifiable {
        public let id: String
        public var wide: Bool
        /// Скрыт крестиком (WF174); в JSON только `true` — старые раскладки читаются как были.
        public var hidden: Bool

        public init(id: String, wide: Bool = true, hidden: Bool = false) {
            self.id = id
            self.wide = wide
            self.hidden = hidden
        }

        private enum CodingKeys: String, CodingKey { case id, wide, hidden }

        public init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            id = try box.decode(String.self, forKey: .id)
            wide = try box.decodeIfPresent(Bool.self, forKey: .wide) ?? true
            hidden = try box.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        }

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(id, forKey: .id)
            try box.encode(wide, forKey: .wide)
            if hidden { try box.encode(true, forKey: .hidden) }
        }

        public var widget: PanelWidget? { PanelWidget(rawValue: id) }
    }

    public static let key = "panelLayoutWF129"
    /// Умолчание (WF181, #9217, слово Элвиса 09.10 03:05 по снимку 37: «Вот такое отображение сделай по умолчанию»):
    /// плитки половинками по двое — «Неделя · Сброс», «5 часов · Fable», «Температура · Память»; «Токены» и «Цвет Claude»
    /// во всю ширину, «Цвет Claude» — внизу (WF177). Сохранённую раскладку человека не трогает: она лежит своим ключом.
    /// `defaultWide` и порядок перечисления — для блоков, которых нет в сохранённой раскладке (`normalized`).
    public static let standard = PanelWidgetLayout(items: [
        Item(id: PanelWidget.workflow.rawValue),
        Item(id: PanelWidget.week.rawValue, wide: false), Item(id: PanelWidget.reset.rawValue, wide: false),
        Item(id: PanelWidget.limits.rawValue, wide: false), Item(id: PanelWidget.fable.rawValue, wide: false),
        Item(id: PanelWidget.temperature.rawValue, wide: false), Item(id: PanelWidget.memory.rawValue, wide: false),
        Item(id: PanelWidget.tokens.rawValue), Item(id: PanelWidget.colors.rawValue),
    ])

    public private(set) var items: [Item]

    public init(items: [Item]) { self.items = Self.normalized(items) }

    public var isStandard: Bool { self == Self.standard }

    /// Чужие и повторные id долой; недостающий — сразу за своим соседом «как было» (или первым), своей ширины «как
    /// было». Раскладка до WF174 без «Fable»: широкий «5 часов» держал обе плитки — оба встают половинками рядом.
    static func normalized(_ raw: [Item]) -> [Item] {
        var out: [Item] = []
        for var item in raw where item.widget != nil && !out.contains(where: { $0.id == item.id }) {
            if item.widget?.canNarrow == false { item.wide = true }
            out.append(item)
        }
        let all = PanelWidget.allCases
        for (index, widget) in all.enumerated() where !out.contains(where: { $0.id == widget.rawValue }) {
            let previous = all[..<index].reversed().first { prev in out.contains { $0.id == prev.rawValue } }
            let at = previous.flatMap { prev in out.firstIndex { $0.id == prev.rawValue } }.map { $0 + 1 } ?? 0
            var item = Item(id: widget.rawValue, wide: widget.defaultWide)
            if widget == .fable, at > 0, out[at - 1].id == PanelWidget.limits.rawValue, out[at - 1].wide {
                out[at - 1].wide = false
                item.wide = false
            }
            out.insert(item, at: at)
        }
        return out
    }

    /// Раскладка уже переехала: «Цвет Claude» вниз (WF177) — дальше порядок снова выбирает человек.
    public static let colorsLastKey = "panelColorsLastWF177"

    public static func load(_ defaults: UserDefaults = .standard) -> PanelWidgetLayout {
        guard let text = defaults.string(forKey: key), let data = text.data(using: .utf8),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return standard }
        var layout = PanelWidgetLayout(items: items)
        if !defaults.bool(forKey: colorsLastKey) {
            defaults.set(true, forKey: colorsLastKey)
            if let at = layout.items.firstIndex(where: { $0.id == PanelWidget.colors.rawValue }) {
                var item = layout.items.remove(at: at)
                item.wide = true
                layout.items.append(item)
                layout.save(defaults)
            }
        }
        return layout
    }

    /// «Как было» — ключ снимается. Сохранённое после WF177 — уже выбор человека: переезд «Цвет Claude» вниз не нужен.
    public func save(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Self.colorsLastKey)
        guard !isStandard else { defaults.removeObject(forKey: Self.key); return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: Self.key)
    }

    public func item(_ id: String) -> Item? { items.first { $0.id == id } }

    /// Перетаскивание: `id` встаёт на место `target`, остальные сдвигаются. true — что-то сдвинулось.
    @discardableResult
    public mutating func move(_ id: String, over target: String) -> Bool {
        guard id != target, let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == target }) else { return false }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        return true
    }

    /// «Шире» / «Уже»; уже нельзя — без изменений.
    public mutating func toggleWidth(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].wide == false || items[index].widget?.canNarrow == true else { return }
        items[index].wide.toggle()
    }

    /// Скрыть блок (крестик) или вернуть его на прежнее место.
    public mutating func setHidden(_ id: String, _ hidden: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].hidden = hidden
    }

    /// Скрытые из тех, что сейчас есть, — строка «Скрытые: + Fable» под блоками.
    public func hidden(visible: Set<String>) -> [Item] { items.filter { $0.hidden && visible.contains($0.id) } }

    /// Ряды видимых и не скрытых: широкий — свой ряд; узкие встают по двое подряд, одинокий узкий — половиной ряда.
    public func rows(visible: Set<String>) -> [[Item]] {
        var rows: [[Item]] = []
        var pending: Item?
        for item in items where visible.contains(item.id) && !item.hidden {
            if item.wide {
                if let single = pending { rows.append([single]); pending = nil }
                rows.append([item])
            } else if let first = pending {
                rows.append([first, item])
                pending = nil
            } else {
                pending = item
            }
        }
        if let single = pending { rows.append([single]) }
        return rows
    }
}

/// Перетаскивание виджета: раскладка до начала (Esc её возвращает) и последний, с кем поменялись, — пока указатель
/// над ним, второй раз не меняемся (высокий сосед иначе дёргал бы блок туда-обратно).
public struct PanelWidgetDrag: Equatable {
    public let id: String
    public let before: PanelWidgetLayout
    public private(set) var lastSwap: String?
    /// Esc: раскладка вернулась, до отпускания мыши блок не двигается.
    public var cancelled = false

    public init(id: String, before: PanelWidgetLayout) {
        self.id = id
        self.before = before
    }

    /// Указатель над чужим виджетом `hit` (nil — над своим или пустым местом); вернёт раскладку, если сдвинулись.
    public mutating func step(over hit: String?, in layout: PanelWidgetLayout) -> PanelWidgetLayout? {
        guard !cancelled else { return nil }
        guard let hit = hit, hit != id else { lastSwap = nil; return nil }
        guard hit != lastSwap else { return nil }
        var next = layout
        guard next.move(id, over: hit) else { return nil }
        lastSwap = hit
        return next
    }
}

// MARK: - «Цвет Claude» (WF141, #9114, #9115; WF169 — #9178; с WF174 — #9182)

/// Блок «Цвет Claude» (WF174, #9182; WF177, #9196, слово Элвиса 09.10 02:35: живую заставку и цвет разом выбирать
/// нельзя — «выбираешь либо живую заставку, либо цвет»; «в одну или в две строчки поплотнее, выравнивание
/// по ширине»; «Отсчёт… должны быть прям картинки»). Свёрнут — строка с образцом выбранного; развёрнут сверху вниз —
/// «Отсчёт» рядом картинок, «Живая заставка» одним рядом видов, «Цвет» двумя рядами по цветовому кругу («Как у
/// Claude» и светлые первыми, дальше тёмные). Выбор на весь блок ОДИН (`pick`): живая заставка или цвет; нажал цвет —
/// живой фон снимается, нажал заставку — выделение с цвета уходит. Имена — подсказкой при наведении, строк-подписей
/// нет. Вид — `ColorsCard` в `PimpPanel.swift`, тесты — `PanelWF174Tests`, `PanelWF177Tests`.
public enum PanelColorTiles {
    public enum Tile: Equatable {
        /// «Как у Claude» — ни темы всем окнам, ни цвета по проектам.
        case plain
        case theme(String)
    }

    /// Раскрыт ли блок — в UserDefaults; нет ключа — свёрнут.
    public static let openKey = "panelColorsOpenWF141"

    /// Полос цветов (WF177: «в одну или в две строчки»): все образцы делятся на них поровну.
    public static let stripLimit = 2
    /// Образцов в полосе — сколько выйдет на две полосы (29 тем + «Как у Claude» → по 15).
    public static func perStrip(_ chips: [WindowColorChip]) -> Int {
        (chips.count + 1 + stripLimit - 1) / stripLimit
    }

    /// Что выделено в блоке (WF180, слово Элвиса 09.10 02:50: «Все цвета тогда пусть будут как живой»; «Живые фоны все
    /// одинаковые»): всегда цвет окон — «Живой» его не меняет, только оживляет. Цвет «по проектам» и тема не из полос
    /// (выбраны в меню жёлтой кнопки) — nil.
    public static func picked(_ choice: WindowColorChoice) -> Tile? {
        switch choice {
        case .plain: return .plain
        case .theme(let id): return .theme(id)
        case .byProject: return nil
        }
    }

    /// Схема живого фона панели — «Как у темы» (страница берёт акцент цвета окна): живой фон идёт в тонах выбранного
    /// цвета. Отдельные схемы («Фиолетовые сумерки», «Глубокое море»…) остались в меню жёлтой кнопки «🎨 Схема ▸».
    public static let liveScheme = "theme"

    /// Переключатель «Живой»: включить — живой фон в тонах цвета (`liveScheme`), выключить — тот же цвет без движения.
    /// Прочие эффекты вида не трогает.
    static func liveLook(_ look: Look, on: Bool) -> Look {
        on ? look.withScheme(liveScheme) : look.with(.aurora, false)
    }

    /// Нажатый цвет при живом фоне чужой схемы (выбранной до WF180 или в меню окна) переводит фон на тона цвета.
    public static func colorNeedsLiveScheme(live: Bool, scheme: String) -> Bool { live && scheme != liveScheme }

    /// Подписи блока (WF180: «Оформление» вместо «Цвет Claude», «Живой» — переключатель в заголовке).
    public static let title = "Оформление"
    public static let liveTitle = "Живой"
    public static let countdownTitle = "Отсчёт"

    /// Светлые темы полосы (кроме «Как у Claude»): «Кремовая» и «Светлая» — почти как «Лимонная» и «Небесная».
    public static let lightIDs = ["peach", "orangeade", "lemonade", "lemon", "mint", "sky", "lavender", "sakura",
                                  "powder"]
    /// Тёмные темы двух полос: неоновые с фоном не в цвет акцента («Кобальт», «Майами»…) — в меню жёлтой кнопки.
    public static let darkIDs = ["red", "coral", "orange", "mango", "brown", "honey", "yellow", "lime", "green",
                                 "teal", "electric", "blue", "violet", "ultra", "lilac", "fuchsia", "pink", "crimson",
                                 "magma", "gray"]

    /// Тема новой установки (WF210, #9378; слово Элвиса 10.10.2026: «по умолчанию… Ультрафиолет… Или даже не
    /// ультрафиолет, а фиолетовая») — вместе с включённым «Живой» (`ClaudeAXController.applyNewInstallLook`).
    public static let newInstallThemeID = "violet"

    /// Новая установка — снимок настроек приложения до первой записи пуст И файла `installed.json` нет (Claude этим
    /// Пимпом не патчили). У тех, кто уже ставил или выбирал, не пусто хотя бы одно — их умолчания не трогаем.
    public static func isNewInstall(values: [String: Any], installed: Data?) -> Bool {
        values.isEmpty && installed == nil
    }

    /// Полосы цветов: «Как у Claude», тёмные по цветовому кругу фона, потом светлые по кругу (серые — в конце
    /// своей группы), подряд и поровну на `stripLimit` полос — плитки во всю ширину, края в край. С WF210 (#9378,
    /// слово Элвиса 10.10.2026: «светлые темы куда-то в конец убрать и начать с тёмных») тёмные первыми — до того
    /// (WF180, слово 09.10) было наоборот.
    public static func strips(_ chips: [WindowColorChip]) -> [[Tile]] {
        let all: [Tile] = [.plain] + (wheel(chips.filter { !$0.light }) + wheel(chips.filter { $0.light }))
            .map { .theme($0.id) }
        let size = max(1, perStrip(chips))
        return stride(from: 0, to: all.count, by: size).map { Array(all[$0..<min($0 + size, all.count)]) }
    }

    /// Порядок по цветовому кругу: тон фона 0…360, почти серые (насыщенность HSL < 0,15) — после цветных.
    public static func wheel(_ chips: [WindowColorChip]) -> [WindowColorChip] {
        let keyed = chips.enumerated().map { (index: $0.offset, chip: $0.element, key: hue($0.element.background)) }
        return keyed.sorted { a, b in
            let ga = a.key.saturation < 0.15, gb = b.key.saturation < 0.15
            if ga != gb { return !ga }
            return a.key.hue != b.key.hue ? a.key.hue < b.key.hue : a.index < b.index
        }.map { $0.chip }
    }

    /// Тон (0…360) и насыщенность HSL (0…1) цвета `#rrggbb`; не цвет — серый.
    public static func hue(_ hex: String) -> (hue: Double, saturation: Double) {
        let raw = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return (0, 0) }
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        guard delta > 0 else { return (0, 0) }
        let light = (high + low) / 2
        let saturation = delta / (1 - abs(2 * light - 1))
        var hue: Double
        if high == r { hue = (g - b) / delta } else if high == g { hue = (b - r) / delta + 2 } else { hue = (r - g) / delta + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation)
    }

    /// Выбран ли образец: тот, что стоит у окон, — и при живом фоне тоже (по проектам — ни один).
    public static func isSelected(_ tile: Tile, _ choice: WindowColorChoice) -> Bool { picked(choice) == tile }

    public static func isOpen(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: openKey) }

    public static func setOpen(_ open: Bool, _ defaults: UserDefaults = .standard) {
        if open { defaults.set(true, forKey: openKey) } else { defaults.removeObject(forKey: openKey) }
    }
}
