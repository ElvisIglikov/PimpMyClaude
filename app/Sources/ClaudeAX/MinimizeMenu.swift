import AppKit
import ApplicationServices

/// Меню на жёлтой кнопке «Свернуть» — порт `claude_minimize_menu.lua` (решение 7 плана).
/// Таймер 8 Гц читает `NSEvent.mouseLocation` и сравнивает с рамками окон Claude из
/// `CGWindowListCopyWindowInfo`; AX спрашиваем только про прямоугольник AXMinimizeButton,
/// и только когда курсор в верхней полосе окна. Никаких event tap.
final class MinimizeMenu: NSObject {
    var enabled = true
    /// Опрос курсора, 8 Гц.
    let interval: TimeInterval = 0.125
    /// Полоса от верха рамки, где может жить кнопка (кнопка на y+16..34; 30 обрезало низ).
    let topBand: CGFloat = 48
    /// Сколько курсор должен простоять на кнопке.
    let hoverSeconds: TimeInterval = 0.3
    /// Кэш геометрии кнопки (и промахов) на окно.
    let buttonCacheSeconds: TimeInterval = 0.5

    private let app: ClaudeApp
    private let actions: ClaudeActions
    private var timer: Timer?

    /// Кэш на окно: AX-элемент, прямоугольник кнопки и рамка, при которой их читали.
    /// Промахи кэшируются тоже — иначе AX опрашивался бы на каждом тике.
    private struct ButtonCache {
        let element: AXUIElement?
        let rect: CGRect?
        let frame: CGRect
        let at: TimeInterval
    }

    private var buttons: [CGWindowID: ButtonCache] = [:]
    private var hoverID: CGWindowID?
    private var hoverSince: TimeInterval = 0
    private var suppressed = false
    private var menuOpen = false
    private(set) var shows = 0
    /// Меню сейчас всплывёт — самое время перечитать сводки проектов (решение 2 плана WF9).
    var onWillShow: (() -> Void)?
    /// Цвет проекта (план WF15, переделан в WF20): один тумблер «🗂 Цвет по проекту»
    /// в «🖥 Всем окнам ▸». nil — приложение собрано без покраски по проекту, тогда тумблера
    /// в меню нет вовсе.
    var project: ProjectPaint?
    /// Недавние папки для «🪟 Новое окно ▸» (план WF16): их даёт `ProjectIndex` — единственный
    /// источник правды «папка ↔ сессия». Пусто — в подменю остаётся один пункт «Здесь же».
    var recentProjects: () -> [Project] = { [] }
    /// Сохранённые раскладки для «🗂 Раскладки ▸» (план WF41): читаем на каждый показ меню —
    /// файл правит и сам Элвис. Пусто — в подменю остаётся одно «💾 Сохранить эту раскладку…».
    var savedLayouts: () -> [WindowLayout] = { [] }
    /// Запомнить нынешнюю раскладку под именем; строка в ответе — плашка о том, почему не
    /// записалось (nil — записано).
    var saveLayout: (String) -> String? = { _ in nil }
    /// Сохранение раскладки началось — ДО вопроса об имени: приложение просит страницы
    /// назвать свои чаты (#5770) и предлагает имя по проектам этих окон (#5769).
    /// Пустая строка — предложить нечего, поле диалога останется пустым.
    var startSaveLayout: () -> String = { "" }
    /// «↩︎ Вернуть эти чаты» (false) и «✨ Новые чаты по этим проектам» (true).
    var restoreLayout: (WindowLayout, Bool) -> Void = { _, _ in }
    var deleteLayout: (WindowLayout) -> Void = { _ in }

    /// Открыто ли меню (или его модальный диалог): пока открыто, фоновая покраска по проекту
    /// молчит — не-preview команда сбила бы примерку темы мышью (критик В1 плана WF15).
    var isMenuOpen: Bool { menuOpen }

    /// Открыта панель «Своя тема» (блокер Б2 плана WF20). Панель стоит вплотную к окну, и курсор,
    /// задержавшийся на жёлтой кнопке, поднял бы меню поверх неё: наведение на тему послало бы
    /// свою примерку, а закрытие меню — `endPreview`, и окно прыгнуло бы на сохранённую тему.
    /// Ставит и снимает `ThemeEditor`; панель одна на приложение — отсюда статик.
    static var editorOpen = false

    /// Можно ли поднимать меню наведением. Первый же `guard` в `tick()` — и он же проверяется
    /// тестом: живой `tick()` без доверия Accessibility ничего не докажет.
    var hoverPaused: Bool { !enabled || menuOpen || MinimizeMenu.editorOpen }

    init(app: ClaudeApp, actions: ClaudeActions) {
        self.app = app
        self.actions = actions
        super.init()
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        clearCache()
        hoverID = nil
        hoverSince = 0
        suppressed = false
        menuOpen = false
        // Панель редактора уходит вместе с меню — и уносит с собой `endPreview` (решение 1.3
        // плана WF20): иначе окно осталось бы в цвете ползунка навсегда.
        ThemeEditor.current?.close()
        // И отложенная примерка наведения (план WF31): ждать её больше некому.
        PreviewMenuDelegate.shared.cancel()
    }

    var isRunning: Bool { timer != nil }

    /// Окна переехали или Claude перезапустился — прямоугольники кнопок протухли.
    func clearCache() { buttons = [:] }

    private func tick() {
        guard !hoverPaused, AX.isTrustedCached, let pid = app.pid else { return }
        let point = Screens.flip(point: NSEvent.mouseLocation)

        var target: (window: AXUIElement, id: CGWindowID, rect: CGRect)?
        // Окна перекрываются: решает первое (самое переднее) под курсором.
        for window in ClaudeApp.onScreenFrames(pid: pid) {
            let f = window.frame
            guard point.x >= f.minX, point.x <= f.maxX,
                  point.y >= f.minY, point.y <= f.minY + topBand else { continue }
            if let hit = minimizeButton(of: window), hit.rect.contains(point) {
                target = (hit.element, window.id, hit.rect)
            }
            break
        }

        guard let hit = target else {
            hoverID = nil
            hoverSince = 0
            suppressed = false
            return
        }
        if hoverID != hit.id {
            hoverID = hit.id
            hoverSince = Date.timeIntervalSinceReferenceDate
            suppressed = false
            return
        }
        if suppressed { return } // меню уже показывали: ждём, пока курсор уйдёт с кнопки
        if Date.timeIntervalSinceReferenceDate - hoverSince >= hoverSeconds {
            suppressed = true // до блокирующего popUp, а не после
            show(for: hit.window, at: hit.rect)
        }
    }

    /// AX-окно и прямоугольник его AXMinimizeButton в экранных координатах.
    /// Кэш живёт buttonCacheSeconds и сбрасывается, как только окно переехало, — обращение
    /// к AX выходит не чаще двух раз в секунду и только для окна под курсором.
    private func minimizeButton(of window: ClaudeWindowFrame) -> (element: AXUIElement, rect: CGRect)? {
        let now = Date.timeIntervalSinceReferenceDate
        if let hit = buttons[window.id], now - hit.at < buttonCacheSeconds, hit.frame == window.frame {
            guard let element = hit.element, let rect = hit.rect else { return nil }
            return (element, rect)
        }
        let element = app.window(matching: window.frame)
        var rect: CGRect?
        if let element = element, let button = AX.element(element, kAXMinimizeButtonAttribute) {
            rect = AX.frame(button)
        }
        buttons[window.id] = ButtonCache(element: element, rect: rect, frame: window.frame, at: now)
        guard let element = element, let rect = rect else { return nil }
        return (element, rect)
    }

    // MARK: - меню

    private func show(for window: AXUIElement, at rect: CGRect) {
        onWillShow?()
        // Заголовок окна нужен и команде темы (адресация, как у «Обкэшить»), и галке в подменю.
        let title = AX.string(window, kAXTitleAttribute) ?? ""
        var config = MenuConfig()
        config.themes = actions.themes
        config.fonts = actions.fonts
        // Файл своих тем читаем на каждый показ: его правит и сам Элвис (план п. 4).
        config.myThemes = actions.myThemes.load()
        config.windowThemeID = actions.themeStore.windowThemeID(title: title)
        config.allThemeID = actions.themeStore.allThemeID
        config.windowFontID = actions.themeStore.windowFontID(title: title)
        config.allFontID = actions.themeStore.allFontID
        config.windowSize = actions.themeStore.windowSize(title: title)
        config.allSize = actions.themeStore.allSize
        config.windowFrame = actions.themeStore.windowFrame(title: title)
        config.allFrame = actions.themeStore.allFrame
        // Два случая, где памяти о цвете окна верить нельзя (критик В1 плана WF14).
        config.windowTitled = !title.isEmpty
        config.windowAutoPainted = actions.autoPaintedTheme(title: title) != nil
        // «🗂 Цвет по проекту» — один тумблер вместо всего подменю «Проект ▸» (решение 3.4 плана
        // WF20): папку окна и файл проекта меню больше не показывает — цвет и так стоит,
        // а выбор темы в окне проекта сам становится темой проекта.
        if let project = project {
            config.projectColor = project.enabled
            config.setProjectColor = { on in DispatchQueue.main.async { project.setEnabled(on) } }
        }
        // Была ли примерка и закрепили ли её выбором — оба флага живут до конца popUp
        // (замыкания меню срабатывают внутри его цикла).
        var previewed = false
        var committed = false
        // «🗂 <Проект>» (план WF71 п. 3): тема проекта этого окна под именем папки; клик
        // возвращает окну вид проекта БЕЗ записи в файл и мимо `remember`, иначе авто-цвет
        // молча стал бы `.pimpmyclaude.json`. Покраска идёт очередью канала, как у тика, —
        // это закрепление, а не примерка: «конец примерки» после popUp ей не нужен.
        if let project = project {
            config.projectTheme = project.projectTheme(forTitle: title)
            config.repaintProject = {
                committed = true
                DispatchQueue.main.async { project.repaintProject(forTitle: title) }
            }
        }
        // Поля по бокам: значение читаем из claude.json на каждый показ — его правит и сам
        // Элвис, и лоадер берёт его оттуда же (критик В7).
        config.sidePadding = LiveStyle.currentSidePadding()
        // Ползунок пишет claude.css и claude.json, а не command.json: очередь канала и примерку
        // тем он не трогает, отсюда отклик до ~1 с (лоадер опрашивает файлы раз в секунду).
        config.setSidePadding = { LiveStyle.apply(sidePadding: $0) }
        // Пункт срабатывает внутри цикла popUp: откладываем на ход вперёд, чтобы
        // сначала закрылось меню и вернулся фокус окну Claude.
        // Обычная команда примерку НЕ закрепляет: после popUp уйдёт «конец примерки», а сама
        // команда — следом через очередь CommandChannel (600 мс), ничего не теряется.
        config.perform = { [weak self] command in
            DispatchQueue.main.async { self?.actions.perform(command, on: window) }
        }
        // «🪟 Новое окно ▸ <проект>» (план WF16): список папок читаем на каждый показ — чаты
        // Claude Code заводятся и закрываются, пока меню не открыто.
        config.projects = recentProjects()
        config.newWindowInProject = { [weak self] project in
            DispatchQueue.main.async { self?.actions.newWindow(in: project, on: window) }
        }
        // Полоса раскладок (план WF21): выбор закрепляется — его повторяют ⌥⌘A и «▦ Расставить».
        // Отсрочки здесь нет: плитка сама закрывает меню и зовёт это ходом вперёд.
        config.arrangeMode = actions.themeStore.arrangeMode
        config.arrangeFits = { [weak self] mode in self?.actions.arrangeFits(mode) ?? true }
        // Тот же список окон, по которому работает «Расставить» (свёрнутые в него не входят):
        // по рамкам плитка «как сейчас» рисует настоящее положение окон (#5798), по их числу
        // собирается полоса (#5800). Список кэширован секунду — лишнего обхода AX нет.
        let onScreen = app.visibleWindows().compactMap { AX.frame($0) }
        config.windowFrames = onScreen
        config.windowArea = Screens.usableFrame(holding: onScreen)
        config.arrange = { [weak self] mode in
            guard let self = self else { return }
            self.actions.themeStore.arrangeMode = mode
            self.actions.arrange(mode: mode)
        }
        // «🗂 Раскладки ▸» (план WF41): список читаем на каждый показ, диалог имени и возврат
        // окон — ходом вперёд, как все диалоги: сперва должно закрыться меню.
        config.layouts = savedLayouts()
        config.saveLayout = { [weak self] in
            DispatchQueue.main.async { self?.askAndSaveLayout(window: window) }
        }
        config.restoreLayout = { [weak self] layout, fresh in
            DispatchQueue.main.async { self?.restoreLayout(layout, fresh) }
        }
        config.deleteLayout = { [weak self] layout in
            DispatchQueue.main.async { self?.deleteLayout(layout) }
        }
        config.apply = { [weak self] scope, theme, font, size, frame in
            committed = true
            DispatchQueue.main.async {
                self?.actions.applyTheme(scope: scope, theme: theme, font: font, size: size,
                                         frame: frame, window: window)
            }
        }
        config.applyMyTheme = { [weak self] scope, my in
            committed = true
            DispatchQueue.main.async { self?.actions.apply(myTheme: my, scope: scope, window: window) }
        }
        // «Применить ▸ Только этому окну» (план WF71 п. 2): та же команда окну, но в проект
        // не пишется — соседние окна проекта остаются как были.
        config.applyMyThemeHere = { [weak self] my in
            committed = true
            DispatchQueue.main.async {
                self?.actions.apply(myTheme: my, scope: MenuModel.themeScopeWindow, window: window,
                                    toProject: false)
            }
        }
        // Примерка уходит в страницу сразу, без отсрочки: пока Элвис ведёт мышью, окно должно
        // перекрашиваться под курсором. Хранилища примерка не касается — ни на странице, ни здесь.
        config.previewTheme = { [weak self] theme in
            guard let self = self, self.actions.previewTheme(theme, window: window) else { return }
            previewed = true
        }
        config.previewMyTheme = { [weak self] my in
            guard let self = self, self.actions.preview(myTheme: my, window: window) else { return }
            previewed = true
        }
        config.previewFont = { [weak self] font in
            guard let self = self, self.actions.previewFont(font, window: window) else { return }
            previewed = true
        }
        config.previewSize = { [weak self] size in
            guard let self = self, self.actions.previewSize(size, window: window) else { return }
            previewed = true
        }
        config.previewFrame = { [weak self] in
            guard let self = self, self.actions.previewFrame(window: window) else { return }
            previewed = true
        }
        config.saveMyTheme = { [weak self] in
            DispatchQueue.main.async { self?.saveMyTheme(window: window) }
        }
        // Панель редактора открывается ходом вперёд, как и остальные диалоги: сперва должно
        // закрыться меню (и уйти `endPreview`), и только потом панель берёт примерку себе.
        config.editMyTheme = { [weak self] my in
            DispatchQueue.main.async { self?.openThemeEditor(window: window, editing: my) }
        }
        config.deleteMyTheme = { [weak self] my in
            DispatchQueue.main.async { self?.actions.myThemes.delete(id: my.id) }
        }
        // Автопокраска адресуется всем окнам на экране, а не окну под курсором; примерку она
        // не закрепляет (`committed` не трогаем) — после popUp окну вернут сохранённое, а следом
        // придёт своя тема из очереди канала.
        config.autoPaint = { [weak self] preset in
            DispatchQueue.main.async { self?.actions.autoPaint(preset: preset) }
        }
        config.autoPaintAgain = { [weak self] in
            DispatchQueue.main.async { self?.actions.autoPaintAgain() }
        }
        config.autoPaintReset = { [weak self] in
            DispatchQueue.main.async { self?.actions.autoPaintReset(window: window) }
        }
        // Живые цвета адресованы всем окнам сразу (одна команда `scope: "all"`), поэтому окно
        // под курсором им тоже не нужно; примерку они не закрепляют — крутёж и так перекроет
        // всё, что примерялось.
        config.liveColors = actions.liveColors
        config.setLiveColorsMode = { [weak self] mode in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let mode = mode { self.actions.startLiveColors(mode: mode) }
                else { self.actions.stopLiveColors() }
            }
        }
        config.setLiveColorsTone = { [weak self] tone in
            DispatchQueue.main.async { self?.actions.setLiveColors(tone: tone) }
        }
        // Ползунок скорости, как и «Поля по бокам», работает в открытом меню — отсрочки нет.
        config.setLiveColorsPeriod = { [weak self] period in
            self?.actions.setLiveColors(period: period)
        }
        let menu = MinimizeMenu.build(config: config)

        shows += 1
        menuOpen = true
        // popUp требует активного приложения, иначе меню не получает событий и закрывается
        // при первом же движении мыши (03.09: подменю тем «схлопывалось»). Кооперативный
        // activate() на macOS 14+ без yield со стороны Claude приложение не активирует —
        // нужен именно ignoringOtherApps, как делает Hammerspoon перед popupMenu.
        NSApp.activate(ignoringOtherApps: true)
        // …но `activate` только ПРОСИТ активность, а приезжает она событием (#5797). Меню,
        // поднятое до её приезда, AppKit гасит через четверть секунды: снаружи это «мигнуло
        // и пропало». Ровно это Элвис поймал 08.09 на свежей сборке — по журналу окон видно
        // пять попыток подряд, каждая жила 250 мс, и все в первые полминуты после запуска
        // приложения, пока оно ни разу не было впереди. Ждём подтверждения, разбирая события
        // главной очереди, не дольше `activateWait`; не дождались — меню всё равно поднимаем.
        MinimizeMenu.awaitActive(isActive: { NSApp.isActive }, pump: MinimizeMenu.pumpEvent,
                                 now: { Date.timeIntervalSinceReferenceDate })
        // Меню встаёт СЛЕВА от жёлтой кнопки (решение 2.1 плана WF20): точку считает чистая
        // `origin`, а `NSMenu.size` спрашиваем только здесь — AppKit считает её лениво.
        // Область — экран, где стоит САМА кнопка (#5716): `Screens.mainUsableFrame` это
        // `NSScreen.main`, то есть экран активного окна любого приложения, и на втором
        // мониторе меню вставало не с той стороны — та же болезнь, что чинили у «Расставить».
        let point = MinimizeMenu.origin(button: rect, menuWidth: menu.size.width,
                                        area: Screens.usableFrame(holding: [rect]))
        let origin = Screens.flip(point: point)
        // Ушли с примерки в другой раздел (#6250: «Матрица, Пудра, потом чуть ниже спускаюсь —
        // надо вернуть») — окну сразу возвращается своё, не дожидаясь закрытия меню. Крючок
        // держит `window`, поэтому живёт ровно столько, сколько открыто меню.
        PreviewMenuDelegate.shared.onLeave = { [weak self] in
            guard let self = self, self.actions.endPreview(window: window) else { return }
            previewed = false
        }
        menu.popUp(positioning: nil, at: origin, in: nil)
        PreviewMenuDelegate.shared.onLeave = nil
        // Меню закрылось — отложенная примерка (пауза наведения, план WF31) отменяется
        // СИНХРОННО и до проверки ниже: иначе она докрасила бы окно уже после `endPreview`
        // и оставила его в чужом цвете до смены чата.
        PreviewMenuDelegate.shared.cancel()
        menuOpen = false
        // Ушли из меню, ничего не выбрав, — вернуть окну сохранённое. Синхронно, сразу после
        // popUp: замыкания выбора отложены на ход вперёд, и «конец предпросмотра», посланный
        // после них, перекрыл бы закрепление — лоадер читает command.json раз в 500 мс и
        // берёт последнюю команду.
        // Примеркой владеет панель «Своя тема» — молчим: её ползунок мы бы просто погасили.
        if previewed && !committed && !MinimizeMenu.editorOpen { actions.endPreview(window: window) }
        // Меню закрылось — фокус обратно окну Claude (решение 7 плана).
        app.focus(window: window)
    }

    // MARK: - активность перед popUp (#5797)

    /// Сколько ждём активность после `activate`. Живьём она приезжает за десятки миллисекунд;
    /// не приехала за это время — не приедет вовсе, и лишняя пауза перед меню хуже попытки.
    static let activateWait: TimeInterval = 0.3
    /// Шаг ожидания: столько ждём одно событие за заход.
    static let activateStep: TimeInterval = 0.02

    /// Дождаться, пока приложение ПРАВДА станет активным. Чистая — её и гоняют тесты:
    /// `isActive` спрашивает состояние, `pump` даёт AppKit ход (живьём — разбор одного
    /// события главной очереди), `now` — часы. Отвечает, дождались ли.
    @discardableResult
    static func awaitActive(isActive: () -> Bool, pump: () -> Void, now: () -> TimeInterval,
                            timeout: TimeInterval = activateWait) -> Bool {
        let deadline = now() + timeout
        while !isActive() {
            guard now() < deadline else { return false }
            pump()
        }
        return true
    }

    /// Один шаг ожидания живьём: берём событие из очереди и отдаём его AppKit — тем же путём,
    /// каким его разобрал бы главный цикл. Без этого активация так и лежала бы в очереди,
    /// пока мы стоим на `popUp`. Событий нет — ждём до `activateStep` и выходим.
    private static func pumpEvent() {
        let until = Date().addingTimeInterval(activateStep)
        guard let event = NSApp.nextEvent(matching: .any, until: until, inMode: .default,
                                          dequeue: true) else { return }
        NSApp.sendEvent(event)
    }

    // MARK: - положение меню (чистая часть — её и проверяет тест)

    /// Отступ меню от жёлтой кнопки: правый край на столько ЛЕВЕЕ её левого края, верх — на
    /// столько НИЖЕ её низа (слово Элвиса 05.09 10:40: «правый край чуть левее и чуть ниже значка»).
    static let menuGap: CGFloat = 2
    /// Ширина меню, когда `NSMenu.size` соврал: на пунктах с кастомными `view` («↔️ Поля»,
    /// «⏱ Скорость») он может отдать что угодно. 280 — та же константа, что стояла в WF19.
    static let fallbackMenuWidth: CGFloat = 280
    /// Границы, в которых ширине меню верим (решение 2.1 плана WF20).
    static let minMenuWidth: CGFloat = 120
    static let maxMenuWidth: CGFloat = 600

    /// Куда поставить меню — в перевёрнутых координатах Quartz; точка это ЛЕВЫЙ ВЕРХНИЙ угол
    /// меню, именно её ждёт `popUp(positioning: nil, at:, in: nil)` после `Screens.flip`.
    ///
    /// Правило одно, без «если влезет справа» (слово Элвиса 05.09 10:40 перекрывает WF19/#5395):
    /// правый край меню чуть левее жёлтой кнопки, верх — чуть ниже неё. Слева места нет (окно
    /// придвинули к краю экрана) — меню падает под левый край окна, как было до WF19.
    /// Области экрана не знаем — ставим слева и не обрезаем: рисовать меню поверх кнопки хуже.
    static func origin(button rect: CGRect, menuWidth: CGFloat, area: CGRect?) -> CGPoint {
        // NaN и прочая небывальщина в `contains` не попадает — уйдёт в запасные 280.
        let width = (minMenuWidth...maxMenuWidth).contains(menuWidth) ? menuWidth : fallbackMenuWidth
        let top = rect.maxY + menuGap
        let left = rect.minX - menuGap - width
        guard let area = area, left < area.minX else { return CGPoint(x: left, y: top) }
        return CGPoint(x: rect.minX, y: top)
    }

    /// «💾 Сохранить тему» — одним кликом, без диалога (слово Элвиса 17.09 14:20): имя даёт
    /// `MyThemesStore.autoName` — имя цвета окна, а занято — «Матрица 2», «Матрица 3»…, так
    /// что вопроса «Перезаписать?» больше нет (переименовать — «✏️ Изменить…», панель имя
    /// спрашивает). Пару берём из последней команды этого приложения — а у автопокрашенного
    /// окна из его же автотемы (план WF10 п. 6), иначе на окне «Радуги» записался бы цвет
    /// соседнего окна. Тему ни разу не выбирали — сохранять нечего, показываем алерт.
    /// После алерта фокус возвращается окну Claude, как после самого меню.
    private func saveMyTheme(window: AXUIElement) {
        // Пока висит алерт, тик наведения не должен всплывать меню поверх него.
        menuOpen = true
        defer { menuOpen = false; app.focus(window: window) }
        guard let theme = actions.themeToSave(window: window) else {
            MinimizeMenu.warn(MenuModel.myThemeEmptyAlert)
            return
        }
        let name = MyThemesStore.autoName(for: theme, among: actions.myThemes.load())
        if actions.saveMyTheme(name: name, window: window) == nil {
            MinimizeMenu.warn(MenuModel.themeEditorWriteFailed)
        }
    }

    /// «💾 Сохранить эту раскладку…» (план WF41): имя спрашиваем тем же модальным диалогом,
    /// что у своих тем; имя занято — раскладка перезаписывается (о том и подпись в диалоге).
    /// Окно с неопознанным чатом отменяет запись целиком — об этом плашка.
    ///
    /// Круг опознания чатов и имя по проектам считаются ДО диалога (#5769, #5770): после
    /// того, как Элвис нажал «Сохранить», спрашивать страницы уже поздно, а имя ему нужно
    /// в поле — чтобы можно было просто нажать «Сохранить», ничего не печатая.
    private func askAndSaveLayout(window: AXUIElement) {
        // Пока висит диалог, тик наведения не должен всплывать меню поверх него.
        menuOpen = true
        defer { menuOpen = false; app.focus(window: window) }
        let suggestion = startSaveLayout()
        // Отмена — молча; пустое поле — словами (#5769): раньше и то и другое было
        // молчаливым отказом, и «Сохранить» с пустым именем выглядело сломанной кнопкой.
        guard let name = MinimizeMenu.askLayoutName(default: suggestion) else { return }
        guard !name.isEmpty else {
            MinimizeMenu.warn(MenuModel.layoutNameEmptyAlert)
            return
        }
        if let problem = saveLayout(name) { MinimizeMenu.warn(problem) }
    }

    /// «✏️ Изменить…» в подменю своей темы (решение 1.5 плана WF20; с WF71 — единственный
    /// вход в панель, пункта «🎚 Своя тема…» нет). Ручки берутся у правимой темы, а без неё
    /// подбираются по нынешней теме окна. Красит панель ровно то окно, из меню которого
    /// её открыли.
    private func openThemeEditor(window: AXUIElement, editing: MyTheme?) {
        let knobs = editing.map { ThemeKnobs.of($0) } ?? actions.editorKnobs(window: window)
        ThemeEditor.open(window: window, knobs: knobs, editing: editing, actions: actions, app: app)
    }

    // MARK: - сборка меню (без AX и popUp — так его и проверяют тесты)

    /// Всё, что меню знает о мире: каталоги, галки и что делать по нажатию.
    /// Одним struct — параметров стало слишком много для списка аргументов (план п. 2).
    struct MenuConfig {
        var themes: [Theme] = []
        var fonts: [Font] = []
        var myThemes: [MyTheme] = []
        var windowThemeID: String?
        var allThemeID: String?
        var windowFontID: String?
        var allFontID: String?
        /// Галки в «🔠 Размер шрифта ▸» (план WF12 п. 2; в меню с WF71 одна половина — `answer`).
        var windowSize: Size?
        var allSize: Size?
        /// Состояние тумблера «✨ Неоновая рамка» (план WF12 п. 4).
        var windowFrame = false
        var allFrame = false
        /// Есть ли у окна AX-заголовок: без него память по заголовку пуста ВСЕГДА
        /// (`windowThemeID(title:"")` — nil), и галка «Как у Claude» врала бы (критик В1).
        var windowTitled = true
        /// Окно покрашено автопокраской: цвет на нём есть, а записи в ThemeStore нет
        /// («автопокраска не ставит галки и стирает старые») — галка соврала бы и здесь.
        var windowAutoPainted = false
        /// Поля по бокам (задача #5360): текущее значение ползунка из claude.json и обработчик.
        var sidePadding = LiveStyle.defaultSidePadding
        var setSidePadding: (Int) -> Void = { _ in }
        /// Тумблер «🗂 Цвет по проекту» (решение 3.4 плана WF20): галка — покраска включена.
        /// nil — меню собрано без сведений о проекте, и тумблера в нём нет вовсе.
        var projectColor: Bool?
        /// «🗂 <Проект>» первым пунктом раздела своих тем (план WF71 п. 3): имя папки, тема
        /// проекта (файл или авто-цвет) и стоит ли она на окне. nil — окно проектом не
        /// опознано, пункта нет; с ним уходит и адресат «Окнам проекта …» у своих тем.
        var projectTheme: (name: String, theme: Theme, current: Bool)?
        /// Клик по «🗂 <Проект>»: вернуть окну вид проекта, ничего не записывая.
        var repaintProject: () -> Void = {}
        /// Недавние папки в «🪟 Новое окно ▸» (план WF16, ступень b). Пусто — подменю остаётся
        /// с одним пунктом «Здесь же», раздела «НЕДАВНИЕ ПРОЕКТЫ» нет вовсе: пункт, молча
        /// открывающий окно не в той папке, хуже отсутствия пункта.
        var projects: [Project] = []
        /// Клик по папке: новый чат в ней, имя чата — имя проекта, цвет — сразу проектный.
        var newWindowInProject: (Project) -> Void = { _ in }
        /// Клик по тумблеру «🗂 Цвет по проекту» — приходит уже перевёрнутым.
        var setProjectColor: (Bool) -> Void = { _ in }
        /// Полоса раскладок первым пунктом (план WF21): какая раскладка выбрана сейчас,
        /// влезает ли раскладка на экран (иначе плитка серая) и что делать по клику.
        var arrangeMode: ArrangeLayout.Mode = .ribbon
        var arrangeFits: (ArrangeLayout.Mode) -> Bool = { _ in true }
        var arrange: (ArrangeLayout.Mode) -> Void = { _ in }
        /// Как окна Claude стоят прямо сейчас (рамки в перевёрнутых координатах AX) и рабочая
        /// область экрана, на котором они стоят. По ним плитка «как сейчас» рисует настоящее
        /// положение окон (#5798), а по их числу собирается сама полоса (#5800): раскладка,
        /// у которой при этом числе окон половина ячеек осталась бы пустой, в полосу не
        /// попадает. Рамок нет — в полосе одна плитка «как сейчас» со схемой столбиками.
        var windowFrames: [CGRect] = []
        var windowArea: CGRect?
        /// Сохранённые раскладки в «🗂 Раскладки ▸» (план WF41) и что делать по клику:
        /// запомнить нынешние окна, вернуть те же чаты (`false`) или открыть новые (`true`),
        /// удалить запись.
        var layouts: [WindowLayout] = []
        var saveLayout: () -> Void = {}
        var restoreLayout: (WindowLayout, Bool) -> Void = { _, _ in }
        var deleteLayout: (WindowLayout) -> Void = { _ in }

        /// Можно ли верить памяти приложения об этом окне — от этого зависит галка «Как у Claude».
        var windowMemoryTrusted: Bool { windowTitled && !windowAutoPainted }
        var perform: (ClaudeCommand) -> Void = { _ in }
        /// scope и четыре слоя — одна команда на все (контракт п. 1 плана WF12);
        /// пункт меню трогает ровно свой слой, остальные уходят `.keep`. У размера — ровно свою
        /// ПОЛОВИНУ слоя (`SizeLayer`, решение 1 плана WF19).
        var apply: (String, Layer<Theme>, Layer<Font>, SizeLayer, Layer<Bool>) -> Void = { _, _, _, _, _ in }
        /// Своя тема адресату: `scope` окна — «Окнам проекта …» (выбор ложится в проект, как
        /// любой ручной выбор), `scope` всех — «Всем окнам» и «Всем окнам ▸ Цвет ▸ Мои темы».
        var applyMyTheme: (String, MyTheme) -> Void = { _, _ in }
        /// «Применить ▸ Только этому окну» (план WF71 п. 2): окну — та же команда, в проект —
        /// ничего.
        var applyMyThemeHere: (MyTheme) -> Void = { _ in }
        /// Наведение на пункт списка окна: примерить слой, ничего не запоминая (план WF8 п. 2).
        /// `nil` — примерка сброса слоя («Как у Claude» / «Системный»); у размера сброс приходит
        /// половиной слоя (`.one(half, .reset)`).
        var previewTheme: (Theme?) -> Void = { _ in }
        var previewMyTheme: (MyTheme) -> Void = { _ in }
        var previewFont: (Font?) -> Void = { _ in }
        var previewSize: (SizeLayer) -> Void = { _ in }
        /// У тумблера рамки примерка одна — включённая рамка (план WF12 п. 4).
        var previewFrame: () -> Void = {}
        var saveMyTheme: () -> Void = {}
        var deleteMyTheme: (MyTheme) -> Void = { _ in }
        /// «✏️ Изменить…» в подменю своей темы — панель с ручками правимой темы (план WF20).
        var editMyTheme: (MyTheme) -> Void = { _ in }
        /// «🌈 Раскрасить по кругу» (план WF10, переименовано в WF14): набор красит все окна
        /// на экране — окно под курсором ему не нужно.
        var autoPaint: (AutoPaintPreset) -> Void = { _ in }
        var autoPaintAgain: () -> Void = {}
        var autoPaintReset: () -> Void = {}
        /// «🌊 Живые цвета ▸» (план WF18): что крутится сейчас — от этого галки и гашение
        /// «🌈 Раскрасить по кругу ▸».
        var liveColors = LiveColorsState()
        /// Клик по режиму; nil — «⏹ Выключить».
        var setLiveColorsMode: (LiveColorsMode?) -> Void = { _ in }
        /// Ползунок скорости: секунды на круг, уже с деления шкалы.
        var setLiveColorsPeriod: (Int) -> Void = { _ in }
        var setLiveColorsTone: (LiveColorsTone) -> Void = { _ in }
    }

    /// Меню кнопки — с WF71 про оформление (слово Элвиса 17.09, #6248: «минус нажимаешь — там
    /// всё с оформлением связано»): раздел своих тем («🗂 <Проект>», свои темы с подменю у
    /// каждой, «💾 Сохранить тему»), дальше цвет, шрифт, размер, рамка и ползунок полей,
    /// «🧹 Всё как у Claude», а всё остальное — команды, полоса раскладок и «🖥 Всем окнам ▸» —
    /// внутри «⋯ Ещё ▸». Собрано отдельно от show(), чтобы проверять его в тестах.
    /// Каталога нет (старый бандл без themes.json) — «Цвет ▸» и «Шрифт ▸» не появляются,
    /// остальное оформление на месте (критик В10 плана WF14).
    static func build(config: MenuConfig) -> NSMenu {
        let window = MenuModel.themeScopeWindow
        let menu = NSMenu()
        menu.autoenablesItems = false
        // Свои темы живут на этом уровне — значит, и примерка по наведению нужна здесь же;
        // до WF71 у корня делегата не было (примерка жила в «Оформление ▸»), и без него
        // наведение на тему наверху не красило бы ничего.
        menu.delegate = PreviewMenuDelegate.shared

        // Раздел тем: первым «Как у Claude» — тема по умолчанию (слово Элвиса 17.09 16:10:
        // «всё как у Клауда — это же по сути тема Клауда, значит должно идти первое»), потом
        // тема проекта (её нет — окно проектом не опознано), у каждой своей темы подменю,
        // замыкает раздел «💾 Сохранить тему» — он есть всегда, поэтому и разделитель за ним
        // стоит всегда.
        menu.addItem(claudeThemeItem(config))
        if let project = config.projectTheme { menu.addItem(projectThemeItem(config, project)) }
        for my in config.myThemes { menu.addItem(myThemeMenuItem(config, my)) }
        let save = BlockMenuItem(title: MenuModel.saveMyThemeTitle) { config.saveMyTheme() }
        save.image = icon(MenuModel.saveMyThemeIcon)
        menu.addItem(save)
        menu.addItem(.separator())

        if !config.themes.isEmpty { menu.addItem(colorItem(config, scope: window)) }
        if !config.fonts.isEmpty { menu.addItem(fontItem(config, scope: window)) }
        // Одно подменю размера — половина `answer` («Размер вопросов ▸» убран, #6252).
        menu.addItem(sizeItem(config, half: .answer, scope: window))
        menu.addItem(frameItem(config, scope: window))
        menu.addItem(sidePaddingItem(config))
        menu.addItem(.separator())
        // Сброс всех четырёх слоёв разом, без подтверждения (мелочь М10 критика WF14).
        let reset = BlockMenuItem(title: MenuModel.resetAllTitle) {
            config.apply(window, .reset, .reset, .reset, .reset)
        }
        reset.image = icon(MenuModel.resetAllIcon)
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(moreItem(config))
        return menu
    }

    /// Полоса раскладок (план WF21): пункт-вьюха, четыре картинки. Заголовок на экран не
    /// выходит — его закрывает вьюха, — но он нужен VoiceOver и тестам структуры меню.
    /// Клавиша ⌥⌘A остаётся на «▦ Расставить» рядом в «⋯ Ещё ▸»: по view-пункту клавиатура
    /// не ходит вовсе.
    static func layoutPickerItem(_ config: MenuConfig) -> NSMenuItem {
        let item = NSMenuItem(title: MenuModel.layoutsTitle, action: nil, keyEquivalent: "")
        item.view = LayoutPickerView(config: config)
        return item
    }

    /// Пункт-команда: иконка картинкой, клавиша — в keyEquivalent (её справа серым AppKit
    /// рисует сам, решение 4 плана WF9). Маску ставим и пустую: по умолчанию у NSMenuItem
    /// она ⌘, а у «Workflow» клавиши нет.
    static func commandItem(_ entry: MenuEntry, _ config: MenuConfig) -> NSMenuItem {
        let item = BlockMenuItem(title: entry.menuTitle) { config.perform(entry.command) }
        item.image = icon(entry.icon)
        item.keyEquivalent = entry.key?.keyEquivalent ?? ""
        item.keyEquivalentModifierMask = entry.key?.modifierMask ?? []
        return item
    }

    /// «🪟 Новое окно ▸» — вариант А макета WF16: первым пунктом привычное «Здесь же
    /// (последняя папка)» с клавишей ⌥⌘N, ниже — «НЕДАВНИЕ ПРОЕКТЫ» и папки, где Claude уже
    /// работал (в новой папке он поднял бы своё окно доверия, и цепочка встала бы).
    /// Имя пункта — имя папки, полный путь — подсказкой при наведении.
    ///
    /// Клавиша живёт на пункте «Здесь же», а НЕ на родителе: у пункта с подменю AppKit
    /// `keyEquivalent` не отрабатывает — нарисовал бы и не сработал (критик В2). Сам хоткей
    /// ⌥⌘N от этого меню не зависит вовсе: его регистрирует `refreshHotkeys` по `MenuModel.entries`,
    /// откуда `.newWindow` не выпадает.
    /// Список пуст (папок не знаем, ступень b не состоялась) — подменю из одного пункта:
    /// внешне всё как в WF13.
    static func newWindowItem(_ entry: MenuEntry, _ config: MenuConfig) -> NSMenuItem {
        let here = commandItem(entry, config)
        here.title = MenuModel.newWindowHereTitle
        let submenu = NSMenu(title: entry.menuTitle)
        submenu.autoenablesItems = false
        submenu.addItem(here)
        if !config.projects.isEmpty {
            submenu.addItem(.separator())
            submenu.addItem(header(MenuModel.recentProjectsHeader))
            for project in config.projects {
                let item = BlockMenuItem(title: project.name) { config.newWindowInProject(project) }
                item.image = icon(MenuModel.projectFolderIcon)
                item.toolTip = ProjectPaint.short(path: project.folder)
                submenu.addItem(item)
            }
        }
        let item = submenuItem(title: entry.menuTitle, icon: entry.icon, submenu: submenu)
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []
        return item
    }

    /// Два разделителя подряд AppKit рисует двумя линиями — ставим только там, где его ещё нет
    /// (и никогда первым пунктом).
    static func addSeparator(_ menu: NSMenu) {
        guard let last = menu.items.last, !last.isSeparatorItem else { return }
        menu.addItem(.separator())
    }

    /// «⋯ Ещё ▸» — всё, что не про вид (слово Элвиса 17.09, #6248): полоса раскладок первой
    /// строкой, за ней команды `MenuModel.entries` по порядку с разделителями `separatorsAfter`
    /// («🪟 Новое окно ▸» — подменю с проектами, иначе список папок потерялся бы), «🗂 Раскладки ▸»
    /// (план WF41) и последним «🖥 Всем окнам ▸» — по слову критика WF71: там единственные
    /// тумблеры «Цвет по проекту», «Раскрасить по кругу» и «Живые цвета», и, выключив их
    /// однажды, включить было бы негде. Прячем только с глаз: клавиши регистрируются по
    /// `entries` и работают как раньше.
    static func moreItem(_ config: MenuConfig) -> NSMenuItem {
        let submenu = NSMenu(title: MenuModel.moreTitle)
        submenu.autoenablesItems = false
        submenu.addItem(layoutPickerItem(config))
        submenu.addItem(.separator())
        for entry in MenuModel.entries where MenuModel.moreCommands.contains(entry.command) {
            submenu.addItem(entry.command == .newWindow ? newWindowItem(entry, config)
                                                        : commandItem(entry, config))
            if MenuModel.separatorsAfter.contains(entry.command) { submenu.addItem(.separator()) }
        }
        submenu.addItem(savedLayoutsItem(config))
        submenu.addItem(.separator())
        submenu.addItem(allWindowsItem(config))
        return submenuItem(title: MenuModel.moreTitle, icon: MenuModel.moreIcon, submenu: submenu)
    }

    /// «🗂 Раскладки ▸» (план WF41, решение Р5): «💾 Сохранить эту раскладку…», под ним имена
    /// сохранённых, у каждой своё подменю — вернуть те же чаты, открыть новые по тем же
    /// проектам, удалить. Сохранённых нет — остаётся один пункт «Сохранить…».
    static func savedLayoutsItem(_ config: MenuConfig) -> NSMenuItem {
        let submenu = NSMenu(title: MenuModel.savedLayoutsTitle)
        submenu.autoenablesItems = false
        let save = BlockMenuItem(title: MenuModel.saveLayoutTitle) { config.saveLayout() }
        save.image = icon(MenuModel.saveLayoutIcon)
        submenu.addItem(save)
        if !config.layouts.isEmpty { submenu.addItem(.separator()) }
        for layout in config.layouts {
            let item = submenuItem(title: layout.name, icon: MenuModel.savedLayoutIcon,
                                   submenu: layoutItems(config, layout))
            item.toolTip = MenuModel.layoutHint(layout)
            submenu.addItem(item)
        }
        return submenuItem(title: MenuModel.savedLayoutsTitle, icon: MenuModel.savedLayoutsIcon,
                           submenu: submenu)
    }

    /// Что можно сделать с сохранённой раскладкой: те же чаты, новые чаты, а за разделителем —
    /// «🗑 Удалить» (порядок макета WF41).
    static func layoutItems(_ config: MenuConfig, _ layout: WindowLayout) -> NSMenu {
        let submenu = NSMenu(title: layout.name)
        submenu.autoenablesItems = false
        let back = BlockMenuItem(title: MenuModel.restoreLayoutTitle) {
            config.restoreLayout(layout, false)
        }
        back.image = icon(MenuModel.restoreLayoutIcon)
        submenu.addItem(back)
        let fresh = BlockMenuItem(title: MenuModel.freshLayoutTitle) {
            config.restoreLayout(layout, true)
        }
        fresh.image = icon(MenuModel.freshLayoutIcon)
        submenu.addItem(fresh)
        submenu.addItem(.separator())
        let drop = BlockMenuItem(title: MenuModel.deleteLayoutTitle) { config.deleteLayout(layout) }
        drop.image = icon(MenuModel.deleteLayoutIcon)
        submenu.addItem(drop)
        return submenu
    }

    /// «🗂 <Проект>» — первый пункт раздела своих тем (план WF71 п. 3): имя папки, значок
    /// проекта, подсказкой — имя темы. Клик возвращает окну вид проекта, ничего не записывая;
    /// наведение примеряет тему проекта, как любой цвет.
    ///
    /// Галка — когда вид проекта стоит на окне: отпечаток покраски сошёлся с видом И память
    /// выбора не держит чужой id. Одного отпечатка мало: после «Применить ▸ Только этому окну»
    /// он нарочно не меняется (иначе ближайший тик перекрасил бы окно обратно), и по нему
    /// одному галка стояла бы и у проекта, и у своей темы разом.
    /// «Как у Claude» первым пунктом — тема по умолчанию: снимает только цвет (шрифт, размер и
    /// рамку не трогает, как тот же пункт в «🎨 Цвет ▸»), в окне проекта записывает в
    /// `.pimpmyclaude.json` `"theme": null`, чтобы авто-цвет не вернулся (см. `ProjectPaint`).
    /// Галка — когда цвета на окне нет ни своего, ни проектного; пустой кружок вместо палитры.
    static func claudeThemeItem(_ config: MenuConfig) -> NSMenuItem {
        let window = MenuModel.themeScopeWindow
        let item = BlockMenuItem(title: MenuModel.themeResetTitle) {
            config.apply(window, .reset, .keep, .keep, .keep)
        }
        item.image = claudeSwatch()
        item.preview = { config.previewTheme(nil) }
        let bare = resetState(config, all: false, windowEmpty: config.windowThemeID == nil,
                              allEmpty: config.allThemeID == nil) == .on
        item.state = bare && !(config.projectTheme?.current ?? false) ? .on : .off
        return item
    }

    static func projectThemeItem(_ config: MenuConfig,
                                 _ project: (name: String, theme: Theme, current: Bool)) -> NSMenuItem {
        let item = BlockMenuItem(title: MenuModel.projectThemeTitle(project.name)) { config.repaintProject() }
        // Кружок палитры проекта, а не папка: с папкой пункт читался как «открыть папку».
        item.image = swatch(palette: project.theme.palette)
        item.toolTip = project.theme.name
        item.preview = { config.previewTheme(project.theme) }
        let foreign = config.windowThemeID != nil && config.windowThemeID != project.theme.id
        item.state = project.current && !foreign ? .on : .off
        return item
    }

    /// Своя тема на верхнем уровне (план WF71 п. 2, слово Элвиса 17.09: «изменить мою тему,
    /// сохранить как мою тему, удалить — это должно быть прямо у темы»): кружок палитры,
    /// галка по id, а в подменю — «Применить ▸» с адресатом («Только этому окну» / «Окнам
    /// проекта …», если окно опознано проектом / «Всем окнам»), «✏️ Изменить…», разделитель,
    /// «🗑 Удалить».
    ///
    /// Примерка ОДНА на родителя, «Применить ▸» и каждого адресата: быстрый заход внутрь
    /// всё равно примерит тему, а делегат стоит на корне, на подменю темы и на подменю
    /// «Применить» — без него наведение внутри ничего не красило бы. У «Изменить…» и
    /// «Удалить» примерки нет, и по правилу предка (`PreviewMenuDelegate`) они её не гасят:
    /// окно остаётся в цвете темы, пока мышь в её подменю.
    static func myThemeMenuItem(_ config: MenuConfig, _ my: MyTheme) -> NSMenuItem {
        let preview = { config.previewMyTheme(my) }
        let targets = NSMenu(title: MenuModel.applyMyThemeTitle)
        targets.autoenablesItems = false
        targets.delegate = PreviewMenuDelegate.shared
        let here = BlockMenuItem(title: MenuModel.applyMyThemeWindowTitle) {
            config.applyMyThemeHere(my)
        }
        here.preview = preview
        targets.addItem(here)
        if let project = config.projectTheme {
            // Как нынешний клик по теме в окне проекта: выбор ложится в `.pimpmyclaude.json`,
            // и покраска перекрашивает остальные окна проекта.
            let windows = BlockMenuItem(title: MenuModel.applyMyThemeProjectTitle(project.name)) {
                config.applyMyTheme(MenuModel.themeScopeWindow, my)
            }
            windows.preview = preview
            targets.addItem(windows)
        }
        let all = BlockMenuItem(title: MenuModel.applyMyThemeAllTitle) {
            config.applyMyTheme(MenuModel.themeScopeAll, my)
        }
        all.preview = preview
        targets.addItem(all)

        let submenu = NSMenu(title: my.name)
        submenu.autoenablesItems = false
        submenu.delegate = PreviewMenuDelegate.shared
        // Родитель подменю — тоже `BlockMenuItem`: примерку делегат берёт только у него.
        // Действия у пункта с подменю AppKit не шлёт, поэтому обработчик пустой.
        let apply = BlockMenuItem(title: MenuModel.applyMyThemeTitle) {}
        apply.preview = preview
        apply.submenu = targets
        submenu.addItem(apply)
        let edit = BlockMenuItem(title: MenuModel.editMyThemeTitle) { config.editMyTheme(my) }
        edit.image = icon(MenuModel.editMyThemeIcon)
        submenu.addItem(edit)
        submenu.addItem(.separator())
        let drop = BlockMenuItem(title: MenuModel.deleteMyThemeTitle) { config.deleteMyTheme(my) }
        drop.image = icon(MenuModel.deleteMyThemeIcon)
        submenu.addItem(drop)

        let item = BlockMenuItem(title: my.name) {}
        item.preview = preview
        item.image = swatch(palette: my.palette)
        item.state = my.id == config.windowThemeID ? .on : .off
        item.submenu = submenu
        return item
    }

    /// «🗂 Цвет по проекту» — тумблер в «🖥 Всем окнам ▸», всё, что осталось от подменю
    /// «Проект ▸» (решение 3.4 плана WF20). По умолчанию включён; выключение снимает слои,
    /// которые проект поставил окнам, включение — красит ближайшим тиком.
    static func projectColorItem(_ config: MenuConfig, on: Bool) -> NSMenuItem {
        let item = BlockMenuItem(title: MenuModel.projectColorTitle) { config.setProjectColor(!on) }
        item.image = icon(MenuModel.projectIcon)
        item.state = on ? .on : .off
        return item
    }

    /// «🖥 Всем окнам ▸» — то же самое, но сразу всем; с WF71 стоит последним в «⋯ Ещё ▸».
    /// Заголовок «ВСЕМ ОКНАМ» ровно один, первым пунктом (критик В4): вложенные списки своих
    /// шапок больше не рисуют.
    /// Предпросмотра по наведению внутри нет — красить все окна на наведении шумно (план WF8).
    static func allWindowsItem(_ config: MenuConfig) -> NSMenuItem {
        let all = MenuModel.themeScopeAll
        let submenu = NSMenu(title: MenuModel.allWindowsTitle)
        submenu.autoenablesItems = false
        submenu.addItem(header(MenuModel.allWindowsHeader))
        // МОИ ТЕМЫ остаются и здесь: свою тему можно применить сразу всем окнам (блокер Б2).
        if !config.themes.isEmpty {
            submenu.addItem(colorItem(config, scope: all, includeMyThemes: true))
        }
        if !config.fonts.isEmpty { submenu.addItem(fontItem(config, scope: all)) }
        submenu.addItem(sizeItem(config, half: .answer, scope: all))
        submenu.addItem(frameItem(config, scope: all))
        submenu.addItem(.separator())
        // Тумблер стоит ПЕРЕД «🌈 Раскрасить по кругу ▸» (решение 3.4 плана WF20).
        if let on = config.projectColor { submenu.addItem(projectColorItem(config, on: on)) }
        submenu.addItem(autoPaintItem(config))
        submenu.addItem(liveColorsItem(config))
        return submenuItem(title: MenuModel.allWindowsTitle, icon: MenuModel.allWindowsIcon,
                           submenu: submenu)
    }

    /// «🌈 Раскрасить по кругу ▸»: наборы, разделитель, «🎲 Случайно», «🔁 Ещё раз» и сброс всем
    /// окнам (план WF10 п. 1). Предпросмотра тут нет: набор красит все окна разом, примерять нечего.
    ///
    /// Пока крутятся живые цвета, все пункты погашены и сверху стоит строка «сначала выключи
    /// живые цвета» (критик В13): покраска писала бы окнам темы, а живой слой перекрывал бы их
    /// через четверть секунды — со стороны это «кнопка не работает». Обратной симметрии нет:
    /// включение живых цветов у автопокраски ничего не спрашивает.
    static func autoPaintItem(_ config: MenuConfig) -> NSMenuItem {
        let live = config.liveColors.on
        let submenu = NSMenu(title: MenuModel.autoPaintTitle)
        submenu.autoenablesItems = false
        if live { submenu.addItem(header(MenuModel.autoPaintLiveHint)) }
        for preset in AutoPaint.presets {
            let item = BlockMenuItem(title: preset.title) { config.autoPaint(preset) }
            item.image = icon(preset.icon)
            item.isEnabled = !live
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let random = BlockMenuItem(title: AutoPaint.random.title) { config.autoPaint(AutoPaint.random) }
        random.image = icon(AutoPaint.random.icon)
        random.isEnabled = !live
        submenu.addItem(random)
        let again = BlockMenuItem(title: MenuModel.autoPaintAgainTitle) { config.autoPaintAgain() }
        again.image = icon(MenuModel.autoPaintAgainIcon)
        again.isEnabled = !live
        submenu.addItem(again)
        let reset = BlockMenuItem(title: MenuModel.autoPaintResetTitle) { config.autoPaintReset() }
        reset.isEnabled = !live
        submenu.addItem(reset)
        return submenuItem(title: MenuModel.autoPaintTitle, icon: MenuModel.autoPaintIcon, submenu: submenu)
    }

    /// «🌊 Живые цвета ▸» (план WF18, вариант А макета): выключатель, два режима, ползунок
    /// скорости и три режима света. Тумблера как такового нет — «⏹ Выключить» и два режима
    /// стоят одной тройкой галок: выключено — галка у «Выключить».
    ///
    /// Предпросмотра нет и здесь: команда одна на все окна, примерять нечего.
    static func liveColorsItem(_ config: MenuConfig) -> NSMenuItem {
        let state = config.liveColors
        let submenu = NSMenu(title: MenuModel.liveColorsTitle)
        submenu.autoenablesItems = false

        let off = BlockMenuItem(title: MenuModel.liveColorsOffTitle) { config.setLiveColorsMode(nil) }
        off.image = icon(MenuModel.liveColorsOffIcon)
        off.state = state.on ? .off : .on
        submenu.addItem(off)
        submenu.addItem(.separator())
        for mode in LiveColorsMode.allCases {
            let names = MenuModel.liveColorsMode(mode)
            let item = BlockMenuItem(title: names.title) { config.setLiveColorsMode(mode) }
            item.image = icon(names.icon)
            item.state = state.on && state.mode == mode ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(liveSpeedItem(config))
        submenu.addItem(.separator())
        for tone in LiveColorsTone.allCases {
            let names = MenuModel.liveColorsTone(tone)
            let item = BlockMenuItem(title: names.title) { config.setLiveColorsTone(tone) }
            item.image = icon(names.icon)
            item.state = tone == LiveColors.tone(state.tone, mode: state.mode) ? .on : .off
            // «🪟 Как окно сейчас» — только в режиме «🎭 Каждое окно своим цветом» (критик М2):
            // команда одна на всех, и в «синхронно» окна взяли бы разные кольца.
            item.isEnabled = tone != .window || state.mode == .solo
            submenu.addItem(item)
        }
        return submenuItem(title: MenuModel.liveColorsTitle, icon: MenuModel.liveColorsIcon,
                           submenu: submenu)
    }

    /// «⏱ Скорость» — тот же пункт-ползунок, что «↔️ Поля» (компонент WF14):
    /// восемь делений шкалы `LiveColors.periods`, справа подпись «круг за 5 мин».
    static func liveSpeedItem(_ config: MenuConfig) -> NSMenuItem {
        let item = NSMenuItem(title: MenuModel.liveColorsSpeedTitle, action: nil, keyEquivalent: "")
        item.view = SliderMenuView(title: MenuModel.liveColorsSpeedIcon + " "
                                        + MenuModel.liveColorsSpeedTitle,
                                   range: 0...(LiveColors.periods.count - 1),
                                   value: LiveColors.index(of: config.liveColors.period),
                                   width: 280, titleWidth: 80, valueWidth: 84,
                                   format: { MenuModel.liveColorsSpeed(LiveColors.period(at: $0)) },
                                   onChange: { config.setLiveColorsPeriod(LiveColors.period(at: $0)) })
        return item
    }

    /// «🎨 Цвет ▸» — три коротких списка (слово Элвиса 12.09, задача #5801).
    static func colorItem(_ config: MenuConfig, scope: String,
                          includeMyThemes: Bool = false) -> NSMenuItem {
        submenuItem(title: MenuModel.colorTitle, icon: MenuModel.themeIcon,
                    submenu: themeList(config, scope: scope, includeMyThemes: includeMyThemes))
    }

    /// Список цветов одного адресата: «Как у Claude» первым, разделитель, дальше три набора
    /// подменю — 🌙 Тёмные, ☀️ Светлые, ✨ Яркие (макет WF52, слово Элвиса 12.09: «мне надо
    /// будет три списка, не один длинный»). Галка стоит и у самого набора — того, откуда взят
    /// цвет окна: искать выбранное по всем трём спискам не надо.
    /// `includeMyThemes` — секция «Мои темы» сверху: у окна свои темы живут на верхнем уровне
    /// меню, у «Всем окнам ▸» остались здесь, иначе свою тему нельзя было бы дать всем окнам
    /// (блокер Б2 плана WF14).
    ///
    /// Пока крутятся живые цвета, весь список погашен и сверху стоит та же строка «сначала
    /// выключи живые цвета», что у «🌈 Раскрасить по кругу ▸» (критик В13): выбор цвета
    /// страница закрепляет в карте, а живой слой перекрывает его через четверть секунды —
    /// со стороны это мёртвая кнопка, и Элвис не догадывается, что мешает крутёж (#5742).
    static func themeList(_ config: MenuConfig, scope: String,
                          includeMyThemes: Bool = false) -> NSMenu {
        let all = scope == MenuModel.themeScopeAll
        let selected = all ? config.allThemeID : config.windowThemeID
        let live = config.liveColors.on
        let submenu = NSMenu(title: MenuModel.colorTitle)
        submenu.autoenablesItems = false
        // Предпросмотр по наведению — только в списке окна: красить все окна на наведении
        // шумно (план WF8 п. 2), поэтому у «Всем окнам ▸» ни делегата, ни примерок у пунктов.
        if !all { submenu.delegate = PreviewMenuDelegate.shared }
        if live { submenu.addItem(header(MenuModel.autoPaintLiveHint)) }

        if includeMyThemes, !config.myThemes.isEmpty {
            submenu.addItem(header(MenuModel.myThemesHeader))
            for my in config.myThemes {
                let item = myThemeItem(config, my, scope: scope)
                item.isEnabled = !live
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
        }

        // Сбрасываем только свой слой: шрифт, размер и рамку окна тема «Как у Claude» не трогает.
        let reset = BlockMenuItem(title: MenuModel.themeResetTitle) {
            config.apply(scope, .reset, .keep, .keep, .keep)
        }
        reset.preview = all ? nil : { config.previewTheme(nil) }
        reset.state = resetState(config, all: all, windowEmpty: config.windowThemeID == nil,
                                 allEmpty: config.allThemeID == nil)
        reset.isEnabled = !live
        submenu.addItem(reset)

        // Полоска одна — между «Как у Claude» и наборами: сами наборы стоят одной тройкой
        // (макет WF52), и линии между ними разбили бы её на три куска.
        let groups: [(set: ThemeSet, themes: [Theme])] = ThemeSet.allCases.compactMap { set in
            let themes = config.themes.filter { $0.set == set }
            return themes.isEmpty ? nil : (set: set, themes: themes)
        }
        if !groups.isEmpty { addSeparator(submenu) }
        for (set, themes) in groups {
            let list = NSMenu(title: MenuModel.themeSetTitle(set))
            list.autoenablesItems = false
            // Примерка живёт на том уровне, где лежат сами цвета (план WF31): делегат нужен
            // каждому списку набора, иначе наведение в нём ничего не красило бы.
            if !all { list.delegate = PreviewMenuDelegate.shared }
            for theme in themes {
                let item = BlockMenuItem(title: theme.name) {
                    config.apply(scope, .set(theme), .keep, .keep, .keep)
                }
                item.preview = all ? nil : { config.previewTheme(theme) }
                item.image = swatch(palette: theme.palette)
                item.state = theme.id == selected ? .on : .off
                item.isEnabled = !live
                list.addItem(item)
            }
            let item = submenuItem(title: MenuModel.themeSetTitle(set),
                                   icon: MenuModel.themeSetIcon(set), submenu: list)
            let chosen = themes.contains(where: { $0.id == selected })
            item.state = chosen ? .on : .off
            // Крутятся живые цвета — набор не открыть вовсе: выбор в нём был бы мёртвой
            // кнопкой (#5742), а пункты внутри уже погашены тем же признаком.
            item.isEnabled = !live
            submenu.addItem(item)
        }
        return submenu
    }

    /// Пункт своей темы в «Всем окнам ▸ Цвет ▸»: кружок палитры, галка по id, применение
    /// одним слоем цвета. На верхнем уровне у своей темы подменю — `myThemeMenuItem`.
    static func myThemeItem(_ config: MenuConfig, _ my: MyTheme, scope: String) -> NSMenuItem {
        let all = scope == MenuModel.themeScopeAll
        let item = BlockMenuItem(title: my.name) { config.applyMyTheme(scope, my) }
        // Примеряем набор своей темы; у «всем окнам» примерки нет.
        item.preview = all ? nil : { config.previewMyTheme(my) }
        item.image = swatch(palette: my.palette)
        item.state = my.id == (all ? config.allThemeID : config.windowThemeID) ? .on : .off
        return item
    }

    /// Галка у «Как у Claude» / «Системный (как у Claude)» (задача #5363): у «всем окнам» —
    /// когда записи нет; у окна — когда нет ни своей записи, ни записи «всем окнам» (окно
    /// наследует её, и тогда галка стоит внутри «Всем окнам ▸», а у окна пусто).
    ///
    /// Правило отменяет намеренное решение WF6 «не ставить галку у окна никогда», поэтому два
    /// случая, где память соврала бы, закрыты явно (критик В1): окно без AX-заголовка (память
    /// по заголовку там пуста всегда) и окно после автопокраски (оно цветное, а ThemeStore пуст).
    /// Главное окно, меняющее заголовок вместе с чатом, иначе не решается — про это строка
    /// в README и TEAM.md.
    static func resetState(_ config: MenuConfig, all: Bool, windowEmpty: Bool,
                           allEmpty: Bool) -> NSControl.StateValue {
        if all { return allEmpty ? .on : .off }
        return config.windowMemoryTrusted && windowEmpty && allEmpty ? .on : .off
    }

    /// Тумблер «✨ Неоновая рамка» на верхнем уровне и в «🖥 Всем окнам ▸»: галка —
    /// включена, клик переключает (включённую снимаем сбросом слоя, `"frame":null`), наведение
    /// примеряет включённую (план WF12 п. 4). Менять правило галки тут нечего: «выключена»
    /// и есть «как у Claude» (критик В3).
    static func frameItem(_ config: MenuConfig, scope: String) -> NSMenuItem {
        let all = scope == MenuModel.themeScopeAll
        let on = all ? config.allFrame : config.windowFrame
        let item = BlockMenuItem(title: MenuModel.frameTitle) {
            config.apply(scope, .keep, .keep, .keep, on ? .reset : .set(true))
        }
        item.image = icon(MenuModel.frameIcon)
        item.state = on ? .on : .off
        // Примерка — только у окна: зажигать рамку на всех окнах по наведению шумно, как и цвет.
        item.preview = all ? nil : { config.previewFrame() }
        return item
    }

    /// «🔤 Шрифт ▸» — список одного адресата (у окна и внутри «Всем окнам ▸» он один и тот же).
    static func fontItem(_ config: MenuConfig, scope: String) -> NSMenuItem {
        submenuItem(title: MenuModel.fontTitle, icon: MenuModel.fontIcon,
                    submenu: fontList(config, scope: scope))
    }

    /// «🔠 Размер шрифта ▸» — тоже по адресату. Меню с WF71 зовёт его только с половиной
    /// `answer` (#6252); вторая половина осталась в контракте и в старых файлах.
    static func sizeItem(_ config: MenuConfig, half: Size.Half, scope: String) -> NSMenuItem {
        submenuItem(title: MenuModel.sizeTitle(half), icon: MenuModel.sizeIcon,
                    submenu: sizeList(config, half: half, scope: scope))
    }

    /// «Как у Claude» первым, разделитель и кегли из Size.steps. Сброс снимает ровно СВОЮ
    /// половину слоя (`{"answer":null}`, решение 2 плана WF19): «Как у Claude» в «Размер
    /// шрифта ▸» не уносит с собой размер вопросов из старой записи. Обе половины сразу снимает
    /// «🧹 Всё как у Claude» — там слой уходит целиком (`"size":null`).
    static func sizeList(_ config: MenuConfig, half: Size.Half, scope: String) -> NSMenu {
        let all = scope == MenuModel.themeScopeAll
        let selected = (all ? config.allSize : config.windowSize)?.value(half)
        let submenu = NSMenu(title: MenuModel.sizeTitle(half))
        submenu.autoenablesItems = false
        if !all { submenu.delegate = PreviewMenuDelegate.shared }

        let reset = BlockMenuItem(title: MenuModel.sizeResetTitle) {
            config.apply(scope, .keep, .keep, .one(half, .reset), .keep)
        }
        // Примерка — та же команда: вторая половина на экране не дрогнет (решение 2 плана WF19).
        reset.preview = all ? nil : { config.previewSize(.one(half, .reset)) }
        // Сравниваем не слой, а свою ПОЛОВИНУ (критик В3): у окна с answer:nil, question:13
        // из старой записи галка «Как у Claude» обязана встать — половина ответов пуста.
        reset.state = resetState(config, all: all,
                                 windowEmpty: config.windowSize?.value(half) == nil,
                                 allEmpty: config.allSize?.value(half) == nil)
        submenu.addItem(reset)
        submenu.addItem(.separator())

        for px in Size.steps {
            let size = SizeLayer.one(half, .set(px))
            let item = BlockMenuItem(title: String(px)) { config.apply(scope, .keep, .keep, size, .keep) }
            item.preview = all ? nil : { config.previewSize(size) }
            item.state = px == selected ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    /// «Системный (как у Claude)» первым, дальше четыре секции по категориям. Каждый пункт
    /// нарисован своим шрифтом — чтобы видеть, как он выглядит, до применения.
    static func fontList(_ config: MenuConfig, scope: String) -> NSMenu {
        let all = scope == MenuModel.themeScopeAll
        let selected = all ? config.allFontID : config.windowFontID
        let submenu = NSMenu(title: MenuModel.fontTitle)
        submenu.autoenablesItems = false
        if !all { submenu.delegate = PreviewMenuDelegate.shared }

        let reset = BlockMenuItem(title: MenuModel.fontResetTitle) {
            config.apply(scope, .keep, .reset, .keep, .keep)
        }
        reset.preview = all ? nil : { config.previewFont(nil) }
        reset.state = resetState(config, all: all, windowEmpty: config.windowFontID == nil,
                                 allEmpty: config.allFontID == nil)
        submenu.addItem(reset)

        // Четыре секции по категориям (решение 7 плана WF9); порядок — `fontSectionOrder`:
        // с засечками последними (#6251).
        for (title, fonts) in MenuModel.fontSectionOrder.map({ category in
            (MenuModel.fontsHeader(category), config.fonts.filter { $0.category == category })
        }) where !fonts.isEmpty {
            addSeparator(submenu)
            submenu.addItem(header(title))
            for font in fonts {
                let item = BlockMenuItem(title: font.displayName) {
                    config.apply(scope, .keep, .set(font), .keep, .keep)
                }
                item.preview = all ? nil : { config.previewFont(font) }
                item.attributedTitle = NSAttributedString(string: font.displayName, attributes: [
                    .font: NSFont(name: font.family, size: 13) ?? NSFont.systemFont(ofSize: 13),
                ])
                item.state = font.id == selected ? .on : .off
                submenu.addItem(item)
            }
        }
        return submenu
    }

    /// «↔️ Поля» — пункт-ползунок: своя вьюха фиксированного размера, слайдер 0…24
    /// без делений (25 засечек на дорожке ~90 px дают гребёнку) и число моноширинными цифрами.
    /// Тащится мышью прямо в открытом меню, кнопки «применить» нет; подсветки строки у
    /// view-пункта не бывает — это нормально (критик В6).
    /// Колонка подписи ужата под короткое слово (WF71): под «Поля по бокам» стояло 122, и с
    /// «Поля» между словом и дорожкой зияла дыра в ~70 px.
    ///
    /// Не заработает на macOS 26 (висит вне строки, не тащится) — запасной вариант описан
    /// в решении 3 плана: подменю со значениями 0 · 2 · 5 · 8 · 12 · 16 · 24 и галкой на текущем.
    static func sidePaddingItem(_ config: MenuConfig) -> NSMenuItem {
        let item = NSMenuItem(title: MenuModel.sidePaddingTitle, action: nil, keyEquivalent: "")
        item.view = SliderMenuView(title: MenuModel.sidePaddingIcon + " " + MenuModel.sidePaddingTitle,
                                   range: LiveStyle.minSidePadding...LiveStyle.maxSidePadding,
                                   value: LiveStyle.clamp(config.sidePadding),
                                   titleWidth: 64, valueWidth: 20,
                                   format: { String($0) }, onChange: config.setSidePadding)
        return item
    }

    /// Disabled-заголовок секции (меню с autoenablesItems = false, иначе AppKit включит его сам).
    static func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static func submenuItem(title: String, icon emoji: String? = nil, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let emoji = emoji { item.image = icon(emoji) }
        item.submenu = submenu
        return item
    }

    // MARK: - картинки и диалоги

    /// Кружок темы 14 px: заливка background, ободок accent. Не `icon()` — там эмодзи текстом,
    /// а тут нужна цветная картинка (`isTemplate = false`, иначе macOS перекрасит её в цвет метки).
    /// Пустой кружок «Как у Claude»: контур без заливки — цвета на окне нет.
    static func claudeSwatch(size: CGFloat = 14) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            NSColor.secondaryLabelColor.setStroke()
            path.lineWidth = 1.2
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    static func swatch(palette: [String: String], size: CGFloat = 14) -> NSImage {
        let fill = color(palette["background"]) ?? .windowBackgroundColor
        let ring = color(palette["accent"]) ?? .labelColor
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            fill.setFill()
            path.fill()
            ring.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// «#a78bfa» или «#abc» → NSColor; всё остальное — nil (кружок возьмёт системный цвет).
    static func color(_ hex: String?) -> NSColor? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// Имя своей темы — с WF71 спрашивает только панель «Своя тема» («✏️ Изменить…»; пункт
    /// «💾 Сохранить тему» имя даёт сам). Приложение — LSUIElement: без
    /// activate(ignoringOtherApps:) окно алерта уходит за Claude, а без initialFirstResponder
    /// курсор не встаёт в поле.
    static func askThemeName(default value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = MenuModel.myThemeNamePrompt
        alert.informativeText = MenuModel.myThemeNameHint
        alert.addButton(withTitle: MenuModel.myThemeSaveButton)
        alert.addButton(withTitle: MenuModel.myThemeCancelButton)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = MyThemesStore.clean(name: field.stringValue)
        return name.isEmpty ? nil : name
    }

    /// Имя раскладки (план WF41) — тот же модальный диалог, что у своих тем: приложение
    /// LSUIElement, без `activate(ignoringOtherApps:)` окно уходит за Claude.
    /// Второго вопроса про перезапись здесь нет: раскладка — снимок окон, а не собранная
    /// руками тема, и о перезаписи сказано прямо в подписи диалога.
    /// В поле подставляется имя по проектам окон (#5769) — «Сохранить» можно нажать сразу.
    /// nil — «Отмена»; пустая строка — поле очистили, и об этом каллер говорит словами
    /// (у своей темы `askThemeName` пустое имя по-прежнему значит «ничего не делать»).
    static func askLayoutName(default value: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = MenuModel.layoutNamePrompt
        alert.informativeText = MenuModel.layoutNameHint
        alert.addButton(withTitle: MenuModel.layoutSaveButton)
        alert.addButton(withTitle: MenuModel.myThemeCancelButton)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return LayoutsStore.clean(name: field.stringValue)
    }

    /// «Перезаписать «X»?» — второй вопрос перед перезаписью своей темы (критик В2 плана WF14);
    /// с WF71 его задаёт только панель «Своя тема». Отмена значит «ничего не писать»: имя
    /// занято, а плодить дубли мы больше не умеем.
    static func confirmOverwrite(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = MenuModel.myThemeOverwritePrompt(name)
        alert.addButton(withTitle: MenuModel.myThemeOverwriteButton)
        alert.addButton(withTitle: MenuModel.myThemeCancelButton)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func warn(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Эмодзи → картинка 18×18. Монохромный ▦ берёт цвет метки, цветные эмодзи рисуются как есть.
    static func icon(_ emoji: String, size: CGFloat = 18) -> NSImage? {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let text = NSAttributedString(string: emoji, attributes: [
                .font: NSFont.systemFont(ofSize: size * 0.78),
                .paragraphStyle: style,
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let height = text.size().height
            text.draw(in: NSRect(x: 0, y: (rect.height - height) / 2, width: rect.width, height: height))
            return true
        }
        return image
    }
}

/// Наведение на пункт подменю тем и шрифтов — предпросмотр (план WF8 п. 2): окно красится
/// не сразу, а после паузы (`defaultDelay`, задача #5452 и план WF31) — проехал мышью мимо,
/// и ничего не произошло. Что примерять, знает сам пункт (`BlockMenuItem.preview`), а делегат
/// помнит РОВНО одно: чью примерку он сейчас ждёт. Подсветка сменилась или меню закрылось —
/// отложенная примерка отменяется поколением и не выстрелит уже никогда.
/// Делегат по-прежнему один на все меню (`shared`) — `NSMenu.delegate` слабая ссылка, а
/// состояние обязано пережить любое из них; отсюда же требование к будущим «меню»-воркфлоу:
/// вешать этот делегат и звать `cancel()`, когда меню закрылось.
/// Заголовки секций, разделители и пункты с подменю примерок не имеют: наведение на них
/// отменяет отложенное и своего ничего не ставит.
/// Расписание — `DispatchQueue.main.asyncAfter`, а НЕ `Timer.scheduledTimer`: меню крутится
/// в `NSEventTrackingRunLoopMode`, и таймер в режиме `.default` во время трекинга не сработает
/// (тот же довод у `SliderMenuView`). В тестах расписание подставляется (`schedule`).
///
/// **Правило предка (WF71, #6250).** Примерка выстрелила, а мышь ушла на пункт БЕЗ примерки
/// в том же меню или в его предке по `supermenu` — зовётся `onLeave`, и окну возвращается
/// своё, не дожидаясь закрытия меню (слово Элвиса: «Матрица, Пудра, потом чуть ниже
/// спускаюсь — надо вернуть»). Потомки не в счёт: «Изменить…» и «Удалить» в подменю самой
/// темы окно не гасят — пока мышь в её подменю, тема остаётся примеренной.
final class PreviewMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = PreviewMenuDelegate()

    /// Сколько курсор должен простоять на пункте, прежде чем окно перекрасится (задача #5452:
    /// «нужно секундочку подождать… только при долгом удержании просмотр»). К этой выдержке
    /// на экране прибавляется доставка — лоадер читает `command.json` раз в 500 мс, — поэтому
    /// честное «остановился → цвет» выходит 0,5…1,0 с. Тюнится только здесь.
    static let defaultDelay: TimeInterval = 0.5

    /// Боевое расписание вынесено в константу, чтобы `tearDown` тестов вернул его на место.
    static let liveSchedule: (TimeInterval, @escaping () -> Void) -> Void = { wait, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: block)
    }

    var delay = PreviewMenuDelegate.defaultDelay
    /// Подставляется в тестах — как `schedule` у `ThemeEditorModel` и `CommandChannel`.
    var schedule = PreviewMenuDelegate.liveSchedule
    /// Ушли с примерки (правило предка) — `MinimizeMenu.show()` вешает сюда «конец примерки»
    /// на время `popUp` и снимает сразу после: замыкание держит окно.
    var onLeave: (() -> Void)?

    private weak var pendingMenu: NSMenu?
    private weak var pendingItem: NSMenuItem?
    private var generation = 0
    /// Примерка выстрелила и ещё не снята правилом предка.
    private(set) var fired = false
    /// Где выстрелила — самое ВЕРХНЕЕ меню серии: своя тема несёт одну примерку на родителя,
    /// «Применить ▸» и адресатов, и повторный выстрел в её подменю не должен утаскивать
    /// исходное меню вглубь — иначе «Изменить…» рядом с «Применить ▸» гасил бы примерку.
    private weak var firedMenu: NSMenu?

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        // «Подсветки нет» из ЧУЖОГО меню отложенную примерку не отменяет: родительское меню
        // гасит свою подсветку, пока мышь ушла в подменю, — иначе примерка не случилась бы
        // никогда (наведение на «🎨 Цвет ▸» открывает подменю и гасит подсветку родителя).
        if item == nil, let pending = pendingMenu, pending !== menu { return }
        // Тот же пункт (дрожь руки) таймер не перезапускает — иначе пауза не кончилась бы.
        if let item = item, item === pendingItem, pendingMenu === menu { return }
        generation &+= 1
        guard let preview = (item as? BlockMenuItem)?.preview else {
            pendingMenu = nil
            pendingItem = nil
            // Пустая подсветка (`item == nil`) — как раньше, ничего: это ещё не уход.
            if item != nil, fired, let origin = firedMenu,
               PreviewMenuDelegate.isAncestorOrSelf(menu, of: origin) {
                fired = false
                firedMenu = nil
                onLeave?()
            }
            return
        }
        pendingMenu = menu
        pendingItem = item
        let mine = generation
        schedule(delay) { [weak self] in
            guard let self = self, self.generation == mine else { return }
            let origin = PreviewMenuDelegate.previewOrigin(of: menu)
            if !self.fired || PreviewMenuDelegate.isAncestorOrSelf(origin, of: self.firedMenu) {
                self.firedMenu = origin
            }
            self.fired = true
            preview()
        }
    }

    /// Откуда считать выстрел, если он случился внутри подменю своей темы: быстро зашли в
    /// «Матрица ▸», не выждав паузы на ней, и примерка выстрелила уже на «Применить ▸» или
    /// адресате. Родительский пункт (подсвеченный в надменю, с той же примеркой) и есть
    /// исходное место — поднимаемся по таким родителям до самого верхнего; иначе переход на
    /// «Изменить…» в том же подменю гасил бы примерку, пока мышь ещё внутри темы
    /// (проверка WF71). В тестах `highlightedItem` пуст — подъёма нет, правило предка прежнее.
    static func previewOrigin(of menu: NSMenu) -> NSMenu {
        var origin = menu
        while let parent = origin.supermenu,
              let item = parent.highlightedItem as? BlockMenuItem,
              item.preview != nil, item.submenu === origin {
            origin = parent
        }
        return origin
    }

    /// `menu` — это `origin` или один из его предков по `supermenu`. `origin` nil — нет.
    static func isAncestorOrSelf(_ menu: NSMenu, of origin: NSMenu?) -> Bool {
        var current = origin
        while let candidate = current {
            if candidate === menu { return true }
            current = candidate.supermenu
        }
        return false
    }

    /// Закрылось ТО меню, в котором мы ждём: подсветке уже некуда двигаться, отменяем сами —
    /// иначе весь класс «примерка выстрелила в закрытое подменю» держался бы только на
    /// `cancel()` после `popUp`. Память о выстреле НЕ трогаем: подменю набора закрывается
    /// и когда мышь ушла на соседний набор, а какой из двух вызовов AppKit пришлёт первым —
    /// это или подсветку родителя, — на себя не брать; правило предка обязано сработать.
    func menuDidClose(_ menu: NSMenu) {
        guard menu === pendingMenu else { return }
        generation &+= 1
        pendingMenu = nil
        pendingItem = nil
    }

    /// Меню закрылось (выбором или мимо) — отложенная примерка отменяется, а с ней и память
    /// о выстреле: закрытое меню само возвращает окну своё (`endPreview` после `popUp`).
    func cancel() {
        generation &+= 1
        pendingMenu = nil
        pendingItem = nil
        fired = false
        firedMenu = nil
    }
}

/// Строка-ползунок внутри открытого меню (задача #5360): заголовок, `NSSlider` и подпись
/// значения справа. `NSMenuItem.view` события мыши получает сам, поэтому ползунок тащится
/// прямо в меню, и кнопки «применить» нет.
///
/// Компонент общий на два пункта (план WF18: «второй раз не изобретать»): «↔️ Поля»
/// (0…24 пикселя, WF14) и «⏱ Скорость» живых цветов (восемь делений шкалы, подпись
/// «круг за 5 мин»). Отличаются только границами, шириной колонок и тем, как значение
/// показывается словами.
///
/// Дебаунс — только `DispatchQueue.main.asyncAfter`: меню крутится в
/// `NSEventTrackingRunLoopMode`, и `Timer.scheduledTimer` в режиме `.default` во время трекинга
/// просто не сработает (критик В6). Главная очередь в tracking-режиме обслуживается.
final class SliderMenuView: NSView {
    /// Пауза перед записью: пока Элвис ведёт ползунок, дёргать файлы и канал на каждый шаг незачем.
    static let debounce: TimeInterval = 0.15
    static let width: CGFloat = 260
    static let height: CGFloat = 26

    let slider = NSSlider()

    private let value = NSTextField(labelWithString: "")
    private let range: ClosedRange<Int>
    private let format: (Int) -> String
    private let onChange: (Int) -> Void
    private var pending: Int?
    private var scheduled = false

    init(title text: String, range: ClosedRange<Int>, value current: Int,
         width: CGFloat = SliderMenuView.width, titleWidth: CGFloat, valueWidth: CGFloat,
         format: @escaping (Int) -> String, onChange: @escaping (Int) -> Void) {
        self.range = range
        self.format = format
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: SliderMenuView.height))
        let current = min(max(current, range.lowerBound), range.upperBound)

        let title = NSTextField(labelWithString: text)
        title.font = NSFont.menuFont(ofSize: 0)
        title.textColor = .labelColor
        title.frame = NSRect(x: 21, y: 5, width: titleWidth, height: 16)
        addSubview(title)

        // Делений не рисуем: 25 засечек на дорожке ~90 px дают гребёнку; округляем в обработчике.
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        slider.doubleValue = Double(current)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(dragged(_:))
        let valueX = width - 7 - valueWidth
        let sliderX = 21 + titleWidth + 4
        slider.frame = NSRect(x: sliderX, y: 4, width: max(40, valueX - 4 - sliderX), height: 18)
        addSubview(slider)

        value.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.stringValue = format(current)
        value.frame = NSRect(x: valueX, y: 5, width: valueWidth, height: 16)
        addSubview(value)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    @objc private func dragged(_ sender: NSSlider) {
        let step = min(max(Int(sender.doubleValue.rounded()), range.lowerBound), range.upperBound)
        value.stringValue = format(step)
        pending = step
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + SliderMenuView.debounce) { [weak self] in
            guard let self = self else { return }
            self.scheduled = false
            guard let step = self.pending else { return }
            self.pending = nil
            self.onChange(step)
        }
    }
}

/// NSMenuItem с замыканием: цели-селекторы здесь только мешают.
final class BlockMenuItem: NSMenuItem {
    /// Что примерить при наведении (план WF8 п. 2); nil — пункт предпросмотра не делает.
    var preview: (() -> Void)?

    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) не используется") }

    @objc private func fire() { handler() }
}
