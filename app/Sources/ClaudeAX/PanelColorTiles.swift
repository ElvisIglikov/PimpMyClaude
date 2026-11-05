import Foundation

// MARK: - «Цвет Claude» (WF141, #9114, #9115; WF169 — #9178; с WF174 — #9182)

/// Блок «Цвет Claude» (WF174, #9182; WF177, #9196, слово Элвиса 09.10 02:35: живую заставку и цвет разом выбирать
/// нельзя — «выбираешь либо живую заставку, либо цвет»; «в одну или в две строчки поплотнее, выравнивание
/// по ширине»; «Отсчёт… должны быть прям картинки»). Свёрнут — строка с образцом выбранного; развёрнут сверху вниз —
/// «Отсчёт» рядом картинок, «Живая заставка» одним рядом видов, «Цвет» двумя рядами по цветовому кругу (тёмные,
/// потом светлые; «Как у Claude» с WF245 — строкой дополнительного оформления). Выбор на весь блок ОДИН (`pick`): живая заставка или цвет; нажал цвет —
/// живой фон снимается, нажал заставку — выделение с цвета уходит. Имена — подсказкой при наведении, строк-подписей
/// нет. Вид — `ColorsCard` в `Panel/PanelColors.swift`, тесты — `PanelWF174Tests`, `PanelWF177Tests`.
public enum PanelColorTiles {
    public enum Tile: Equatable {
        /// «Как у Claude» — ни темы всем окнам, ни цвета по проектам.
        case plain
        case theme(String)
    }

    /// Полос на группу тем (тёмные, светлые), когда группа не влезает в одну: делится на них поровну.
    public static let stripLimit = 2
    /// До стольких образцов группа встаёт одной полосой.
    public static let singleStripMax = 19
    /// Образцов в полосе группы: до `singleStripMax` — все в одной, больше — поровну на две.
    /// «Как у Claude» с WF245 не плитка и в счёт не идёт.
    public static func perStrip(_ chips: [WindowColorChip]) -> Int {
        let count = chips.count
        if count <= singleStripMax { return count }
        return (count + stripLimit - 1) / stripLimit
    }

    /// Что выделено в блоке (WF180, слово Элвиса 09.10 02:50: «Все цвета тогда пусть будут как живой»; «Живые фоны все
    /// одинаковые»): всегда цвет окон — «Живой» его не меняет, только оживляет. Цвет «по проектам» (свой выключатель,
    /// WF237) и тема не из полос (выбранная до WF237 в меню жёлтой кнопки) — nil.
    public static func picked(_ choice: WindowColorChoice) -> Tile? {
        switch choice {
        case .plain: return .plain
        case .theme(let id): return .theme(id)
        case .byProject: return nil
        }
    }

    /// Схема живого фона панели — «Как у темы» (страница берёт акцент цвета окна): живой фон идёт в тонах выбранного
    /// цвета. Отдельные схемы («Фиолетовые сумерки», «Глубокое море»…) — строкой «Схема» под «Живым фоном» (WF237).
    public static let liveScheme = "theme"

    /// Переключатель «Живой»: включить — живой фон в тонах цвета (`liveScheme`), выключить — тот же цвет без движения.
    /// Прочие эффекты вида не трогает.
    static func liveLook(_ look: Look, on: Bool) -> Look {
        on ? look.withScheme(liveScheme) : look.with(.aurora, false)
    }

    /// Строка «Живой фон» (#9994): `nil` — живого фона нет (тот же цвет, без рисунка), иначе — он есть, и движется,
    /// стоит или лежит картинкой. Включение из «нет» ставит тона цвета, как «Живой» раньше; смена движения при
    /// включённом фоне схему не трогает (выбранную строкой «Схема» — тоже).
    static func liveLook(_ look: Look, motion: LookMotion?) -> Look {
        guard let motion = motion else { return liveLook(look, on: false) }
        var next = look.aurora ? look : liveLook(look, on: true)
        next.motion = motion
        return next
    }

    /// Строка «Схема» (WF237, из меню жёлтой кнопки «🎨 Схема ▸»): вид с живым фоном и этой схемой — выбрать схему значит
    /// и включить живой фон; движение и плотность как были. Чужой id или та же схема при включённом фоне — nil
    /// (слать нечего).
    static func schemeLook(_ look: Look, id: String) -> Look? {
        guard LookScheme.all.contains(where: { $0.id == id }) else { return nil }
        let next = look.withScheme(id)
        return next == look ? nil : next
    }

    /// Выбор строки «Живой фон»: подпись сегмента и подсказка под курсором (#9994). Умолчание — «Стоит».
    public static let motionItems: [(value: LookMotion?, title: String, help: String)] = [
        (nil, "Нет", "Без живого фона: окна просто в выбранном цвете"),
        (.live, "Движется", "Фон плавно движется в тонах цвета. Тратит ресурсы Мака — на слабом лучше «Стоит»"),
        (.still, "Стоит", "Тот же живой фон, но неподвижный — ресурсы Мака не тратит"),
        (.image, "Картинка", "Простой градиент в тонах цвета, без размытия и движения — самый лёгкий"),
    ]

    /// Что выбрано в строке «Живой фон»: фона нет — `nil`.
    public static func motionChoice(live: Bool, motion: LookMotion) -> LookMotion? { live ? motion : nil }

    /// Нажатый цвет при живом фоне чужой схемы (выбранной строкой «Схема») переводит фон на тона цвета.
    public static func colorNeedsLiveScheme(live: Bool, scheme: String) -> Bool { live && scheme != liveScheme }

    /// Подписи блока (WF180: «Оформление» вместо «Цвет Claude»). С WF242 (слово Элвиса 11.10.2026: «вот этот
    /// переключатель живой, сделай оформление и там шестерёнку как дополнительную») переключателя в заголовке нет:
    /// «Живой фон» — строкой дополнительного оформления за шестерёнкой.
    public static let title = "Оформление"
    public static let liveTitle = "Живой фон"
    public static let liveHelp = "Фон окон движется в тонах цвета. Выключи, если Мак греется: живой фон нагружает видеокарту"
    public static let zoomTitle = "Масштаб окна"
    public static let zoomHelp = "Масштаб всех окон Claude"
    public static let zoomResetHelp = "Вернуть обычный масштаб"
    public static let timerTitle = "Таймер"
    public static let timerHelp = "Сколько секунд отправку можно отменить. «Нет» — сообщение уходит сразу"
    public static let rocketSizeTitle = "Размер"
    public static let colorTitle = "Цвет"
    public static let countdownTitle = "Отсчёт"
    public static let extraTitle = "Дополнительное оформление"
    /// Строка «Как у Claude» дополнительного оформления (WF245): кнопка возврата обычного вида и пометка, что он стоит.
    public static let plainAction = "Вернуть"
    public static let plainNow = "стоит сейчас"

    // MARK: - текст окон (WF237, #9524: из меню жёлтой кнопки — в дополнительное оформление, лист 48, ответ 2.1)

    public static let schemeTitle = "Схема"
    public static let schemeHelp = "Тона живого фона. «Как у темы» — в тонах выбранного цвета"
    public static let denseTitle = "Плотный текст"
    public static let denseHelp = "Меньше воздуха между строками и абзацами во всех окнах"
    public static let fontTitle = "Шрифт"
    public static let fontHelp = "Шрифт текста во всех окнах Claude"
    public static let sizeTitle = "Размер текста"
    public static let sizeHelp = "Размер текста ответов во всех окнах Claude"
    public static let byProjectTitle = "Свой цвет у каждого проекта"
    public static let byProjectHelp = "Окна каждого проекта — своим цветом. Выключить — окна как у Claude"
    public static let hideToolsTitle = "Прятать инструменты"
    public static let hideToolsHelp = "Скрывать завершённые инструменты и список правок. Работа, ошибки, вопросы и "
        + "запросы разрешения остаются видны"
    public static let hideCodeTitle = "Прятать код и планы"
    public static let hideCodeHelp = "Сворачивать длинные куски кода и планы законченных ответов в строку, нажатие "
        + "раскрывает. Короткие команды и блоки с кнопками видны"
    /// «Как у Claude» у шрифта и размера: слоя нет — у окон обычный вид Claude.
    public static let fontPlain = "Как у Claude"
    public static let sizePlain = "как у Claude"

    /// Секции списка шрифтов — порядок прежнего меню (слово Элвиса 17.09, #6251: «шрифты с засечками — в самый
    /// конец»); `id` — `FontCategory.rawValue`.
    public static let fontSections: [(id: String, title: String)] = [
        ("sans", "Без засечек"), ("hand", "Рукописные и весёлые"), ("mono", "Моноширинные"), ("serif", "С засечками"),
    ]

    /// Ряд размеров «Размер −  +»: шаги прежнего меню, а «как у Claude» (слоя нет) — между 15 и 16, где и стоит
    /// размер Claude: шаг вниз от него — 15, вверх — 16.
    public static let sizeLadder: [Int?] = [12, 13, 14, 15, nil, 16, 18, 20]

    /// Соседняя ступень размера; края лестницы — nil, кнопка там неактивна. Размер не со ступени (записан руками
    /// или старым меню) идёт к ближайшей ступени в свою сторону.
    public static func sizeStep(from current: Int?, up: Bool) -> Int?? {
        let index: Int
        if let found = sizeLadder.firstIndex(of: current) {
            index = up ? found + 1 : found - 1
        } else if let px = current {
            let below = sizeLadder.lastIndex { ($0 ?? 15) < px } ?? -1
            index = up ? below + 1 : below
        } else {
            return nil
        }
        guard sizeLadder.indices.contains(index) else { return nil }
        return .some(sizeLadder[index])
    }

    /// Имя цвета в строке «Цвет · …» (WF242: «подсказка плохо работает. Я курсор навожу, не всегда оно пишет»):
    /// под курсором — имя образца, иначе — выбранного; имя пишет сама панель, системная подсказка не нужна.
    public static let plainName = "Как у Claude"
    public static let byProjectName = "Свой у каждого проекта"

    public static func name(_ tile: Tile, themes: [WindowColorChip]) -> String {
        switch tile {
        case .plain: return plainName
        case .theme(let id): return themes.first { $0.id == id }?.name ?? ""
        }
    }

    public static func shownName(hovered: Tile?, choice: WindowColorChoice, themes: [WindowColorChip]) -> String {
        if let hovered = hovered { return name(hovered, themes: themes) }
        switch choice {
        case .plain: return plainName
        case .byProject: return byProjectName
        case .theme(let id): return name(.theme(id), themes: themes)
        }
    }

    /// Набор полос — по слову Элвиса 11.10.2026 01:40 (WF245): он прошёл по плиткам и назвал, что убрать. Ушли из
    /// каталога «Красная», «Коричневая», «Манго», «Оранжевая», «Мёд», «Жёлтая», «Лайм», «Ультрафиолет», «Розовая»,
    /// «Персиковая», «Апельсин», «Лимонад»; «Как у Claude» — не плитка, а строка дополнительного оформления.
    /// Не названа однозначно и стоит как была «Зелёная». «Малиновую» и «Магму» (одну из них Элвис назвал красной,
    /// «хотелось бы более интимный») сменила одна новая красная «Винная» — ★3.3 листа docs/43.html (#9683, 31.10.2026);
    /// в каталоге обе остаются. «Сиреневая» и «Фиолетовая» — с тихим живым фоном ★1.4/★2.4 (страница, LOOK_THEME_GLOW).
    /// У кого убранная тема стоит — окно показывает её дальше: палитра лежит в записи окна целиком, каталог ей не нужен.
    /// Светлые темы полосы: «Кремовая» и «Светлая» — почти как «Лимонная» и «Небесная».
    public static let lightIDs = ["lemon", "mint", "sky", "lavender", "sakura", "powder"]
    /// Тёмные темы двух полос. Неоновые с фоном не в цвет акцента («Кобальт», «Майами»…) жили в меню жёлтой кнопки — с WF237
    /// их не выбрать, у кого надеты — остаются.
    public static let darkIDs = ["coral", "green", "teal", "electric", "blue", "violet", "lilac", "fuchsia", "wine",
                                 "gray"]

    /// Тема новой установки (WF210, #9378; слово Элвиса 10.10.2026: «по умолчанию… Ультрафиолет… Или даже не
    /// ультрафиолет, а фиолетовая») — вместе с включённым «Живой» (`ClaudeAXController.applyNewInstallLook`).
    /// С 03.11.2026 (слово: «ставь по умолчанию чёрный тема, цвет серая», «давай без живого фона… пусть он будет по
    /// умолчанию») — «Серая» без живого фона: на M1 Air с большим монитором живой фон заметно греет Мак.
    public static let newInstallThemeID = "gray"

    /// Новая установка — снимок настроек приложения до первой записи пуст И файла `installed.json` нет (Claude этим
    /// Пимпом не патчили). У тех, кто уже ставил или выбирал, не пусто хотя бы одно — их умолчания не трогаем.
    public static func isNewInstall(values: [String: Any], installed: Data?) -> Bool {
        values.isEmpty && installed == nil
    }

    /// Полосы цветов: ряд тёмных сверху, ряд светлых снизу (слово Элвиса 11.10.2026 06:20: «нужно сделать ряд
    /// сверху тёмных тем, а снизу светлых тем. Думаю, так правильно будет») — каждая группа по цветовому кругу фона
    /// (серые — в конце своей группы) своей полосой (`perStrip`); плитки обеих полос одной ширины. С WF210 (#9378, слово Элвиса 10.10.2026:
    /// «светлые темы куда-то в конец убрать и начать с тёмных») тёмные первыми — до того (WF180, слово 09.10) было
    /// наоборот. С WF245 (слово 11.10.2026: «не надо первым делать, как у Claude… вообще убери этот цвет») плитки
    /// «Как у Claude» нет — обычный вид возвращает строка дополнительного оформления.
    public static func strips(_ chips: [WindowColorChip]) -> [[Tile]] {
        [wheel(chips.filter { !$0.light }), wheel(chips.filter { $0.light })].flatMap { group -> [[Tile]] in
            let all: [Tile] = group.map { .theme($0.id) }
            let size = max(1, perStrip(group))
            return stride(from: 0, to: all.count, by: size).map { Array(all[$0..<min($0 + size, all.count)]) }
        }
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
        guard let value = ColorMath.rgb(hex: hex) else { return (0, 0) }
        let hsl = ColorMath.hsl(value)
        return (hsl.hue ?? 0, hsl.saturation)
    }

    /// Выбран ли образец: тот, что стоит у окон, — и при живом фоне тоже (по проектам — ни один).
    public static func isSelected(_ tile: Tile, _ choice: WindowColorChoice) -> Bool { picked(choice) == tile }
}

/// Шрифт строки «Шрифт» дополнительного оформления (WF237): id каталога, имя для списка, семейство (им список рисует
/// пункт) и секция (`PanelColorTiles.fontSections`).
public struct WindowFontChip: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let family: String
    public let section: String

    public init(id: String, name: String, family: String, section: String) {
        self.id = id
        self.name = name
        self.family = family
        self.section = section
    }
}
