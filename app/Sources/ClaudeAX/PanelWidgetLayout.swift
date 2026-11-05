import Foundation

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
/// #10308 (слово Элвиса 19.10.2026: панель — как PimpTray на Windows): «Процессор» и «Видеокарта» — половинками
/// за «Токенами» в `allCases`; порядок по умолчанию — `standard`, сохранённые раскладки переезжают один раз
/// (`reorderOnce`).
public enum PanelWidget: String, CaseIterable {
    case workflow, week, limits, fable, reset, temperature, memory, tokens, cpu, gpu, terminals, colors

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
        // #10704 (слово Элвиса 23.10.2026 по снимку панели: «Давай напишем: память, проц… Видюха и токены»): короткие
        // имена входят в половинку целиком — подписи не ужимаются и стоят одним кеглем. #10993 (слово Элвиса 27.10.2026:
        // «там не проц, там процессор, надо написать») — снова полным словом.
        case .cpu: return "Процессор"
        case .gpu: return "Видюха"
        case .terminals: return "Терминалы"
        }
    }

    /// Строка «Идут 7 · PimpMyClaude 2/3 · …» в половину панели не встаёт — этот блок только во всю ширину.
    public var canNarrow: Bool { self != .workflow && self != .terminals }

    /// Ширина «как было»: «5 часов» и «Fable», «Процессор» и «Видеокарта» — половинками рядом, остальные во всю ширину.
    public var defaultWide: Bool { ![PanelWidget.limits, .fable, .cpu, .gpu].contains(self) }
}

/// Раскладка виджетов: порядок и ширина (2 колонки — `wide`, 1 — нет). Хранится JSON-строкой
/// в `UserDefaults["panelLayoutWF129"]`; нет ключа или мусор — «как было» (все во всю ширину).
public struct PanelWidgetLayout: Equatable {
    public struct Item: Hashable, Codable, Identifiable {
        public let id: String
        public var wide: Bool
        /// Скрыт крестиком (WF174); в JSON только `true` — старые раскладки читаются как были.
        public var hidden: Bool
        /// Свёрнут в одну строку (WF269, #10205, по образцу панели Оли); в JSON только `true`, как `hidden`.
        public var collapsed: Bool

        public init(id: String, wide: Bool = true, hidden: Bool = false, collapsed: Bool = false) {
            self.id = id
            self.wide = wide
            self.hidden = hidden
            self.collapsed = collapsed
        }

        private enum CodingKeys: String, CodingKey { case id, wide, hidden, collapsed }

        public init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            id = try box.decode(String.self, forKey: .id)
            wide = try box.decodeIfPresent(Bool.self, forKey: .wide) ?? true
            hidden = try box.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
            collapsed = try box.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        }

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(id, forKey: .id)
            try box.encode(wide, forKey: .wide)
            if hidden { try box.encode(true, forKey: .hidden) }
            if collapsed { try box.encode(true, forKey: .collapsed) }
        }

        public var widget: PanelWidget? { PanelWidget(rawValue: id) }
    }

    public static let key = "panelLayoutWF129"
    /// Умолчание — как панель коллеги (#10461, слово Элвиса 21.10.2026: «Должно быть неделя, сброс, потом… Вот такая
    /// последовательность блоков должна быть… чтоб отображение было Денисовское»; 12:10: «Внизу Workflow и в самом низу
    /// терминалы открытые»): сверху развёрнутые «Неделя · Сброс» (крупно), дальше свёрнутыми строками парами «5 часов ·
    /// Fable», «Температура · Память», «Процессор · Видеокарта», «Токены · Оформление», Workflow — свёрнутой строкой во
    /// всю ширину, в самом низу «Терминалы» (#10464) — тоже свёрнутой строкой (слово Элвиса 22.10.2026: «Оно же должно
    /// быть скрыто… Свёрнуто»). До #10461 — #10308 (системные плитки сверху),
    /// WF181, WF214. Сохранённую раскладку человека не трогает: она лежит своим ключом и переезжает один раз
    /// (`reorderOnce`). `defaultWide` и порядок перечисления — для блоков, которых нет в сохранённой раскладке.
    public static let standard = PanelWidgetLayout(items: [
        Item(id: PanelWidget.week.rawValue, wide: false), Item(id: PanelWidget.reset.rawValue, wide: false),
        Item(id: PanelWidget.limits.rawValue, wide: false, collapsed: true),
        Item(id: PanelWidget.fable.rawValue, wide: false, collapsed: true),
        Item(id: PanelWidget.temperature.rawValue, wide: false, collapsed: true),
        Item(id: PanelWidget.memory.rawValue, wide: false, collapsed: true),
        Item(id: PanelWidget.cpu.rawValue, wide: false, collapsed: true),
        Item(id: PanelWidget.gpu.rawValue, wide: false, collapsed: true),
        Item(id: PanelWidget.tokens.rawValue, wide: false, collapsed: true),
        Item(id: PanelWidget.colors.rawValue, wide: false, collapsed: true),
        // Слово 03.11.2026: «убери воркфлоу оттуда, они там не нужны… только людей запутает».
        Item(id: PanelWidget.workflow.rawValue, hidden: true, collapsed: true),
        Item(id: PanelWidget.terminals.rawValue, collapsed: true),
    ])

    /// Умолчание, где ничего не свёрнуто, — «Развернуть всё» на `standard` (#10461): все плитки с числами и графиками.
    public static let unfolded = PanelWidgetLayout(items: standard.items.map {
        Item(id: $0.id, wide: $0.wide, hidden: $0.hidden, collapsed: false)
    })

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
    /// Workflow скрыт один раз и у сохранённых раскладок; вернуть — «Изменить виджеты».
    public static let workflowHiddenKey = "panelWorkflowHidden1103"

    public static func load(_ defaults: UserDefaults = .standard) -> PanelWidgetLayout {
        guard let text = defaults.string(forKey: key), let data = text.data(using: .utf8),
              let items = try? JSONDecoder().decode([Item].self, from: data) else {
            defaults.set(true, forKey: workflowHiddenKey)   // `standard` уже скрыл: вернул Workflow — не скрываем ещё раз
            return standard
        }
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
        if !defaults.bool(forKey: workflowHiddenKey) {
            defaults.set(true, forKey: workflowHiddenKey)
            layout.setHidden(PanelWidget.workflow.rawValue, true)
            layout.save(defaults)
        }
        return layout
    }

    /// Номер порядка блоков, как `LayoutOrder` у PimpTray (#10308): сохранённая раскладка со старым номером один раз
    /// встаёт в `standard`. Ключ — тот же, что на Windows.
    public static let orderKey = "panelLayoutOrder"
    public static let order = 4

    /// Разовая перестановка (#10308; с #10461 — порядок 2, раскладка коллеги; порядок 3 — #10464, «Терминалы» внизу и
    /// раскладка коллеги ещё раз: у Элвиса «Развернуть всё» сохранилось развёрнутым): раскладка, сохранённая до этого порядка,
    /// встаёт в порядок, ширины и свёрнутость `standard`; скрытые остаются скрытыми. Номер ставится сразу — дальше
    /// перестановки человека уважаются. Зовётся перед `load`. true — раскладку переставили.
    /// Порядок 4 (слово Элвиса 22.10.2026: «терминалы… Оно же должно быть скрыто… Свёрнуто»): раскладка порядка 3
    /// остаётся как есть, только «Терминалы» сворачиваются.
    @discardableResult
    public static func reorderOnce(_ defaults: UserDefaults = .standard) -> Bool {
        let was = defaults.integer(forKey: orderKey)
        guard was < order else { return false }
        defaults.set(order, forKey: orderKey)
        guard let text = defaults.string(forKey: key), let data = text.data(using: .utf8),
              let saved = try? JSONDecoder().decode([Item].self, from: data) else { return false }
        if was == 3 {
            var layout = PanelWidgetLayout(items: saved)
            guard layout.item(PanelWidget.terminals.rawValue)?.collapsed == false else { return false }
            layout.setCollapsed(PanelWidget.terminals.rawValue, true)
            layout.save(defaults)
            return true
        }
        let items = standard.items.map { item -> Item in
            var next = item
            if let old = saved.first(where: { $0.id == item.id }) { next.hidden = old.hidden }
            return next
        }
        PanelWidgetLayout(items: items).save(defaults)
        return true
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

    /// «Сдвинуть выше» (`step` −1) / «Сдвинуть ниже» (+1) из меню правой кнопки (файл 53, 1.2): блок меняется местами
    /// с соседним видимым нескрытым блоком. Соседа нет — false, без изменений.
    @discardableResult
    public mutating func shift(_ id: String, by step: Int, visible: Set<String>) -> Bool {
        guard let neighbor = neighbor(id, by: step, visible: visible) else { return false }
        return move(id, over: neighbor)
    }

    /// Соседний видимый нескрытый блок выше (−1) или ниже (+1); нет — nil.
    public func neighbor(_ id: String, by step: Int, visible: Set<String>) -> String? {
        let shown = items.filter { visible.contains($0.id) && !$0.hidden }.map { $0.id }
        guard let at = shown.firstIndex(of: id), shown.indices.contains(at + step) else { return nil }
        return shown[at + step]
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

    /// Свернуть блок в одну строку или развернуть (WF269, #10205).
    public mutating func setCollapsed(_ id: String, _ collapsed: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].collapsed = collapsed
    }

    /// Хоть один видимый нескрытый блок развёрнут — кнопка шапки говорит «Свернуть всё» (WF269).
    public func anyExpanded(visible: Set<String>) -> Bool {
        items.contains { visible.contains($0.id) && !$0.hidden && !$0.collapsed }
    }

    /// Соседи по ряду (#10993, слово Элвиса 27.10.2026: «неделю сворачиваю, сброс тоже должен свернуться, они же в
    /// одной строке»): блок и его пара в ряду сетки — как ряды стоят без раскрытых графиков (`rows` без `expanded`).
    /// Широкий или одинокий — только он сам; блока нет среди видимых — тоже только он.
    public func rowMates(_ id: String, visible: Set<String>) -> [String] {
        rows(visible: visible).first { row in row.contains { $0.id == id } }?.map { $0.id } ?? [id]
    }

    /// Свернуть или развернуть блок вместе с соседом по ряду (#10993) — пара «Неделя · Сброс», «5 часов · Fable»
    /// не стоит половиной свёрнутой рядом с пустой развёрнутой коробкой.
    public mutating func setRowCollapsed(_ id: String, _ collapsed: Bool, visible: Set<String>) {
        for mate in rowMates(id, visible: visible) { setCollapsed(mate, collapsed) }
    }

    /// Хоть один видимый нескрытый блок свёрнут — кнопка шапки говорит «Развернуть» (#10993: на виде по умолчанию
    /// первая команда — развернуть).
    public func anyCollapsed(visible: Set<String>) -> Bool {
        items.contains { visible.contains($0.id) && !$0.hidden && $0.collapsed }
    }

    /// Вид по умолчанию (#10993: «сворачиваются все к вот этому виду по умолчанию»): видимые нескрытые блоки свёрнуты
    /// так, как в `standard` — «Неделя · Сброс» развёрнуты, остальные строками. Порядок, ширина и скрытые не меняются.
    /// Человек переставил блоки и в ряду встретились развёрнутый и свёрнутый по умолчанию — ряд развёрнут целиком.
    public mutating func setDefaultFolds(visible: Set<String>) {
        for row in rows(visible: visible) {
            let open = row.contains { Self.standard.item($0.id)?.collapsed == false }
            for item in row { setCollapsed(item.id, !open) }
        }
    }

    /// Пара вразнобой, сохранённая до #10993 (#11276, слово Элвиса 30.10.2026: «у Фейбл тоже должен быть развёрнут
    /// так же, как 68 %»): в ряду развёрнут хоть один — разворачиваются оба. Зовёт доска виджетов с настоящим набором
    /// блоков на экране (тариф без Fable, Мак без видеокарты — ряды другие); ряды, где свёрнуты все или развёрнуты все,
    /// не трогает.
    public mutating func alignRowFolds(visible: Set<String>) {
        for row in rows(visible: visible) where row.count > 1 && row.contains(where: { !$0.collapsed }) {
            for item in row { setCollapsed(item.id, false) }
        }
    }

    /// «Свернуть всё» / «Развернуть всё»: все видимые нескрытые блоки разом.
    public mutating func setAllCollapsed(_ collapsed: Bool, visible: Set<String>) {
        for index in items.indices where visible.contains(items[index].id) && !items[index].hidden {
            items[index].collapsed = collapsed
        }
    }

    /// Скрытые из тех, что сейчас есть, — строка «Скрытые: + Fable» под блоками.
    public func hidden(visible: Set<String>) -> [Item] { items.filter { $0.hidden && visible.contains($0.id) } }

    /// Ряды видимых и не скрытых: широкий — свой ряд; узкие встают по двое подряд, одинокий узкий — половиной ряда.
    /// `expanded` (WF242) — блоки с раскрытым графиком (температура, память): раскрытый встаёт своим рядом во всю
    /// ширину, даже если он половинка, — два раскрытых графика стоят друг под другом одной ширины, края сходятся.
    /// Сама раскладка не меняется: свернул — половинка вернулась к соседу. Свёрнутый в строку блок (WF269) раскрытым
    /// графиком не считается.
    public func rows(visible: Set<String>, expanded: Set<String> = []) -> [[Item]] {
        var rows: [[Item]] = []
        var pending: Item?
        for item in items where visible.contains(item.id) && !item.hidden {
            if item.wide || (expanded.contains(item.id) && !item.collapsed) {
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
